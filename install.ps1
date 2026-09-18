# Sleep Network installer (Windows). Idempotent: safe to run again.
# No parameter attributes here: the script is piped into Invoke-Expression, which validates attributes
# against empty defaults and fails. Modes come from environment variables instead.
#   SLEEPNET_MODE=check   only report what is installed
#   SLEEPNET_NAME / SLEEPNET_EMAIL / SLEEPNET_PASSPHRASE / SLEEPNET_ASSISTANT(claude|codex|both|none)  skip the prompts
$Check = ($env:SLEEPNET_MODE -eq 'check')
$Passphrase = $env:SLEEPNET_PASSPHRASE; $Name = $env:SLEEPNET_NAME; $Email = $env:SLEEPNET_EMAIL; $Assistant = $env:SLEEPNET_ASSISTANT

$ErrorActionPreference = 'Stop'
$Repo = 'https://github.com/tooltim/sleep-network.git'
$Dest = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'sleep-network'

function Say($m) { Write-Host ("  " + $m) }
function Ok($m) { Write-Host ("  OK  " + $m) -ForegroundColor Green }
function Have($cmd) { return [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }
function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User') + ';' + $env:Path
    # A program installed a second ago is often not on PATH of THIS shell yet: add the usual folders directly.
    # Join-Path + forward slashes avoid escape corruption of path literals (backslash-n / backslash-b).
    foreach ($d in @(
        (Join-Path $env:ProgramFiles 'nodejs'),
        (Join-Path $env:LOCALAPPDATA 'Programs/nodejs'),
        (Join-Path $env:ProgramFiles 'Git/cmd'),
        (Join-Path $env:LOCALAPPDATA 'Programs/Git/cmd'),
        (Join-Path $env:LOCALAPPDATA 'Programs/Python/Python312'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft/WindowsApps'),
        (Join-Path $env:USERPROFILE '.local/bin')
    )) {
        if ((Test-Path $d) -and ($env:Path -notlike "*$d*")) { $env:Path = "$d;" + $env:Path }
    }
}
# Resolve an exe via refreshed PATH, then known install locations (avoids crashing right after install).
function Resolve-Exe($name) {
    Refresh-Path
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @()
    if ($name -eq 'node') {
        $candidates = @(
            (Join-Path $env:ProgramFiles 'nodejs/node.exe'),
            (Join-Path $env:LOCALAPPDATA 'Programs/nodejs/node.exe')
        )
    } elseif ($name -eq 'git') {
        $candidates = @(
            (Join-Path $env:ProgramFiles 'Git/cmd/git.exe'),
            (Join-Path $env:LOCALAPPDATA 'Programs/Git/cmd/git.exe')
        )
    }
    foreach ($p in $candidates) { if (Test-Path $p) { return $p } }
    return $null
}
# Fresh MSI/EXE installs can lag a few seconds before files appear on disk / PATH.
function Wait-For-Exe($name, $seconds) {
    $deadline = (Get-Date).AddSeconds($seconds)
    do {
        $found = Resolve-Exe $name
        if ($found) { return $found }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    return $null
}
function Test-IsAdmin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p = New-Object Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}
function Winget-Install($id, $label) {
    # Pin --source winget: the default msstore source often fails with cert errors (0x8a15005e) on locked-down PCs.
    if (Have 'winget') {
        Say "installing $label via winget (a Windows admin prompt may appear: accept it)..."
        try {
            winget install --id $id -e --source winget --silent --accept-package-agreements --accept-source-agreements
        } catch {
            Say "winget install of $label reported an error ($($_.Exception.Message)); will try a direct download if needed"
        }
        Refresh-Path
        # Brief wait: winget can return before PATH/files are visible in this shell.
        if ($label -eq 'nodejs.org') {
            if (Wait-For-Exe 'node' 20) { return }
        } elseif ($label -eq 'git-scm.com') {
            if (Wait-For-Exe 'git' 20) { return }
        } else {
            # python.org etc. — caller re-checks Have
            return
        }
    }
    if ($label -eq 'nodejs.org') {
        if (Resolve-Exe 'node') { return }
        # winget missing or failed: install Node from the official MSI directly.
        Say "installing Node.js from nodejs.org..."
        $msi = Join-Path $env:TEMP 'node-lts.msi'
        Invoke-WebRequest 'https://nodejs.org/dist/v22.14.0/node-v22.14.0-x64.msi' -OutFile $msi
        # /qn needs elevation for Program Files; without admin msiexec often exits non-zero and installs nothing.
        $msiArgs = "/i `"$msi`" /qn /norestart"
        $proc = Start-Process msiexec.exe -ArgumentList $msiArgs -Wait -PassThru
        $code = $proc.ExitCode
        # 0 = success, 3010 = success reboot required — both OK.
        if ($null -eq $code) { $code = -1 }
        if ($code -ne 0 -and $code -ne 3010) {
            $hint = "msiexec exited with code $code."
            if (-not (Test-IsAdmin)) {
                $hint += " Quiet MSI install usually needs an elevated PowerShell (Run as administrator), or approve the UAC prompt if one appeared."
            }
            Say "Node.js MSI did not succeed ($hint)"
            return
        }
        # Files can take a moment to appear after msiexec returns.
        if (-not (Wait-For-Exe 'node' 45)) {
            Say "Node.js MSI finished (exit $code) but node.exe was not found yet under Program Files or %LOCALAPPDATA%\Programs\nodejs"
        }
        return
    }
    if ($label -eq 'git-scm.com') {
        if (Resolve-Exe 'git') { return }
        Say "installing Git from git-scm.com..."
        $exe = Join-Path $env:TEMP 'git-setup.exe'
        Invoke-WebRequest 'https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.1/Git-2.47.1-64-bit.exe' -OutFile $exe
        $proc = Start-Process $exe -ArgumentList '/VERYSILENT /NORESTART' -Wait -PassThru
        $code = $proc.ExitCode
        if ($null -eq $code) { $code = -1 }
        if ($code -ne 0) {
            $hint = "Git setup exited with code $code."
            if (-not (Test-IsAdmin)) {
                $hint += " If an admin/UAC prompt was declined, approve it next time or run PowerShell as administrator."
            }
            Say "Git installer did not succeed ($hint)"
            return
        }
        if (-not (Wait-For-Exe 'git' 45)) {
            Say "Git installer finished (exit $code) but git.exe was not found yet under the usual Git\cmd folders"
        }
        return
    }
    # Python (and anything else): winget-only; caller checks Have/Resolve afterward.
}

# Capture native git/gh output under Continue so stderr does not become a terminating NativeCommandError.
function Invoke-NativeCapture {
    param([string]$Exe, [string[]]$ArgList)
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $raw = @(& $Exe @ArgList 2>&1)
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prevEap
    }
    if ($null -eq $code) { $code = 0 }
    $lines = @($raw | ForEach-Object {
        if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.ToString() } else { "$_" }
    })
    return @{ ExitCode = $code; Text = ($lines -join "`n"); Lines = $lines }
}

function Show-PrivateRepoAuthHelp {
    Write-Host ""
    Say "tooltim/sleep-network is a PRIVATE GitHub repo — clone fails with 'Repository not found' if you lack access or are not signed in."
    Say "Fix, then re-run this installer:"
    Say "  1. Ask Tim to invite your GitHub account to https://github.com/tooltim/sleep-network"
    Say "  2. Sign in on this PC (preferred):  gh auth login"
    Say "     Or approve the Git Credential Manager / browser prompt when Git asks."
    Say "  3. Confirm access:  gh auth status"
    Say "     and:  git ls-remote https://github.com/tooltim/sleep-network.git"
    Say "  4. If a half-downloaded folder exists, delete it:  $Dest"
    Write-Host ""
}

function Ensure-GitHubAuthReady {
    # Prefer gh + Git Credential Manager so private clone does not silently look like success.
    if (Have 'gh') {
        $st = Invoke-NativeCapture 'gh' @('auth', 'status')
        if ($st.ExitCode -eq 0) {
            $setup = Invoke-NativeCapture 'gh' @('auth', 'setup-git')
            if ($setup.ExitCode -ne 0 -and $setup.Text) { Say "gh auth setup-git: $($setup.Text)" }
            Ok "GitHub CLI authenticated"
            return
        }
        Say "GitHub CLI found but not logged in — starting gh auth login (browser)…"
        Say "Use the same GitHub account Tim invited to tooltim/sleep-network."
        $login = Invoke-NativeCapture 'gh' @('auth', 'login', '-h', 'github.com', '-p', 'https', '-w')
        if ($login.Lines) { $login.Lines | ForEach-Object { if ($_) { Write-Host $_ } } }
        if ($login.ExitCode -eq 0) {
            $null = Invoke-NativeCapture 'gh' @('auth', 'setup-git')
            Ok "GitHub CLI authenticated"
            return
        }
        Say "gh auth login did not finish (exit $($login.ExitCode)). Git may still prompt via Credential Manager during clone."
        return
    }
    Say "Tip: for reliable private-repo access, install GitHub CLI (winget install --id GitHub.cli -e --source winget) then run: gh auth login"
    Say "Otherwise Git Credential Manager may open a browser during clone — sign in with an account that has access to tooltim/sleep-network."
}

function Resolve-SleepmagCli($dest) {
    foreach ($rel in @((Join-Path 'tools' (Join-Path 'sleepmag' 'cli.mjs')), 'tools\sleepmag\cli.mjs', 'tools/sleepmag/cli.mjs')) {
        $candidate = Join-Path $dest $rel
        if (Test-Path -LiteralPath $candidate) {
            try { return (Resolve-Path -LiteralPath $candidate).Path } catch { return $candidate }
        }
    }
    return $null
}

function Test-WorkspaceComplete($dest) {
    $gitOk = Test-Path -LiteralPath (Join-Path $dest '.git')
    $cliOk = [bool](Resolve-SleepmagCli $dest)
    return ($gitOk -and $cliOk)
}

function Get-DesktopFolders {
    # Prefer the real Desktop (may be OneDrive-redirected); also cover classic + OneDrive paths coworkers actually see.
    $dirs = New-Object System.Collections.Generic.List[string]
    foreach ($p in @(
        [Environment]::GetFolderPath('Desktop'),
        [Environment]::GetFolderPath('CommonDesktopDirectory')
    )) {
        if ($p -and (Test-Path -LiteralPath $p)) { [void]$dirs.Add(((Resolve-Path -LiteralPath $p).Path)) }
    }
    foreach ($root in @($env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial)) {
        if (-not $root) { continue }
        $od = Join-Path $root 'Desktop'
        if (Test-Path -LiteralPath $od) {
            try { [void]$dirs.Add(((Resolve-Path -LiteralPath $od).Path)) } catch { [void]$dirs.Add($od) }
        }
    }
    $classic = Join-Path $env:USERPROFILE 'Desktop'
    if (Test-Path -LiteralPath $classic) {
        try { [void]$dirs.Add(((Resolve-Path -LiteralPath $classic).Path)) } catch { [void]$dirs.Add($classic) }
    }
    return @($dirs | Select-Object -Unique)
}

function Ensure-SleepmagCmd($dest) {
    $cmdPath = Join-Path $dest 'sleepmag.cmd'
    if (Test-Path -LiteralPath $cmdPath) {
        try { return (Resolve-Path -LiteralPath $cmdPath).Path } catch { return $cmdPath }
    }
    # Do not depend on sleepmag setup having written the launcher (soft-continue / partial setup).
    $lines = @(
        '@echo off',
        'setlocal',
        'cd /d "%~dp0"',
        'where node >nul 2>&1',
        'if errorlevel 1 (',
        '  echo Node.js not found on PATH. Re-run the Sleep Network installer.',
        '  pause',
        '  exit /b 1',
        ')',
        'node "tools\sleepmag\cli.mjs" %*'
    )
    Set-Content -LiteralPath $cmdPath -Value ($lines -join "`r`n") -Encoding ASCII
    if (-not (Test-Path -LiteralPath $cmdPath)) {
        throw "Could not create launcher at $cmdPath"
    }
    try { return (Resolve-Path -LiteralPath $cmdPath).Path } catch { return $cmdPath }
}

function New-SleepNetworkShortcut($targetCmd, $desktopDir) {
    $lnkPath = Join-Path $desktopDir 'Sleep Network.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $sc = $shell.CreateShortcut($lnkPath)
    $sc.TargetPath = $targetCmd
    $sc.WorkingDirectory = (Split-Path -Parent $targetCmd)
    $sc.WindowStyle = 1
    $sc.Description = 'Sleep Network'
    $sc.Save()
    if (-not (Test-Path -LiteralPath $lnkPath)) {
        throw "shortcut file missing after Save: $lnkPath"
    }
    try { return (Resolve-Path -LiteralPath $lnkPath).Path } catch { return $lnkPath }
}

function Wait-OnInstallError {
    if ($env:SLEEPNET_PAUSE_ON_ERROR -eq '1') {
        Write-Host ""
        Write-Host "  Press Enter to close this window..." -ForegroundColor Yellow
        try { [void][Console]::ReadLine() } catch {
            try { Read-Host "  Press Enter to close" | Out-Null } catch { Start-Sleep -Seconds 30 }
        }
    }
}

function Show-InstallFail($message, $detail) {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host "  FAIL  Sleep Network install did not finish" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Red
    if ($message) { Write-Host ("  " + $message) -ForegroundColor Red }
    if ($detail) {
        Write-Host ""
        Write-Host $detail
    }
    Write-Host ""
    Say "Screenshot this window and send it to Tim."
    Say "Then fix the problem (or ask Tim) and re-run the installer."
    Write-Host ""
}

Write-Host ""; Write-Host "Sleep Network installer" -ForegroundColor Cyan; Write-Host ""
$ProgressPreference = 'SilentlyContinue'

try {

if ($Check) {
    Refresh-Path
    foreach ($c in 'git', 'node', 'claude', 'codex', 'python') { if (Have $c) { Ok "$c found" } else { Say "$c missing" } }
    Say ("workspace: " + $(if (Test-WorkspaceComplete $Dest) { 'present' } else { 'not installed' }))
    exit 0
}

# 1. Tools
Refresh-Path
$gitExe = Resolve-Exe 'git'
if (-not $gitExe) { Winget-Install 'Git.Git' 'git-scm.com'; $gitExe = Resolve-Exe 'git' }
if (-not $gitExe) {
    $adminHint = if (Test-IsAdmin) { '' } else { ' If an admin/UAC prompt was declined, open an elevated PowerShell (Run as administrator) and run the installer again.' }
    throw ("Git did not install. Close this window, open a NEW PowerShell and run the installer again; if it still fails, install Git from https://git-scm.com and retry." + $adminHint)
}
Ok ("git " + ((& $gitExe --version) -replace 'git version ', ''))
$nodeExe = Resolve-Exe 'node'
if (-not $nodeExe) { Winget-Install 'OpenJS.NodeJS.LTS' 'nodejs.org'; $nodeExe = Resolve-Exe 'node' }
if (-not $nodeExe) {
    $adminHint = if (Test-IsAdmin) { '' } else { ' If the MSI/winget step needs admin, close this window, open an elevated PowerShell (Run as administrator), and run the installer again.' }
    throw ("Node.js did not install. Close this window, open a NEW PowerShell and run the installer again; if it still fails, install Node LTS from https://nodejs.org and retry." + $adminHint)
}
Ok ("node " + (& $nodeExe --version))
if (-not (Have 'python')) { Winget-Install 'Python.Python.3.12' 'python.org' }
if (Have 'python') { Ok "python present (used to repair the server allowlist)" } else { Say "python missing: the automatic IP-allowlist repair will not work until Python is installed (winget install Python.Python.3.12)" }

# 2. Workspace (must succeed before assistants / identity / sleepmag setup)
Ensure-GitHubAuthReady
$gitDir = Join-Path $Dest '.git'
if (-not (Test-Path -LiteralPath $gitDir)) {
    # Prior failed clone can leave an empty/incomplete folder; remove so git clone can retry cleanly.
    if (Test-Path -LiteralPath $Dest) {
        Say "removing incomplete workspace folder at $Dest…"
        Remove-Item -LiteralPath $Dest -Recurse -Force -ErrorAction SilentlyContinue
    }
    Say "downloading the workspace into $Dest (a GitHub login window may open: use your GitHub account)…"
    $gitOp = Invoke-NativeCapture $gitExe @('clone', $Repo, $Dest)
} else {
    Say "workspace already present, updating…"
    $gitOp = Invoke-NativeCapture $gitExe @('-C', $Dest, 'pull', '--ff-only')
}
if ($gitOp.ExitCode -ne 0) {
    if ($gitOp.Text) {
        $gitOp.Lines | ForEach-Object { if ($_) { Write-Host $_ } }
    }
    Show-PrivateRepoAuthHelp
    throw "Git clone/pull of tooltim/sleep-network failed (exit $($gitOp.ExitCode)). Fix GitHub access and re-run; installer will not continue."
}
# Canonicalize Dest (OneDrive Documents redirects / junctions) so later CLI paths resolve reliably.
if (Test-Path -LiteralPath $Dest) {
    try { $Dest = (Resolve-Path -LiteralPath $Dest).Path } catch { }
}
$setupCli = Resolve-SleepmagCli $Dest
if (-not (Test-Path -LiteralPath (Join-Path $Dest '.git')) -or -not $setupCli) {
    Show-PrivateRepoAuthHelp
    $missing = if (-not $setupCli) { "tools\sleepmag\cli.mjs" } else { ".git" }
    throw "Workspace incomplete at $Dest (missing $missing) after clone/pull. Delete that folder if it is partial, fix GitHub access to tooltim/sleep-network, and re-run."
}
Ok "workspace at $Dest"

# 3. Assistant preference + optional install (only after workspace is verified)
# Claude/Codex are optional: missing must never abort install/setup.
if (-not $Assistant) {
    $a = Read-Host "  Which assistant do you use? [1] Claude Code  [2] Codex  [3] both  [4] already installed / skip"
    $Assistant = @{ '1' = 'claude'; '2' = 'codex'; '3' = 'both'; '4' = 'none' }[$a]; if (-not $Assistant) { $Assistant = 'none' }
}
if ($Assistant -notin 'claude','codex','both','none') { $Assistant = 'none' }
$claudeJustInstalled = $false
if (($Assistant -eq 'claude' -or $Assistant -eq 'both') -and -not (Have 'claude')) {
    Say "installing Claude Code…"
    try { Invoke-RestMethod https://claude.ai/install.ps1 | Invoke-Expression; $claudeJustInstalled = $true } catch { Say "Claude install skipped ($($_.Exception.Message))" }
    Refresh-Path
}
if (($Assistant -eq 'codex' -or $Assistant -eq 'both') -and -not (Have 'codex')) {
    Say "installing Codex…"
    try { npm install -g @openai/codex | Out-Null } catch { Say "Codex install skipped ($($_.Exception.Message))" }
    Refresh-Path
}
if (($Assistant -eq 'claude' -or $Assistant -eq 'both') -and -not (Have 'claude')) { Say "claude not on PATH yet (optional — continuing)" }
if (($Assistant -eq 'codex' -or $Assistant -eq 'both') -and -not (Have 'codex')) { Say "codex not on PATH yet (optional — continuing)" }
if ($claudeJustInstalled -or (($Assistant -eq 'claude' -or $Assistant -eq 'both') -and (Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.local\bin')))) {
    $localBin = Join-Path $env:USERPROFILE '.local\bin'
    if (Test-Path -LiteralPath $localBin) {
        Say "note: if new terminals cannot find 'claude', add %USERPROFILE%\.local\bin to your User PATH (non-fatal for this install)"
    }
}

# 4. Identity + passphrase only after workspace + cli.mjs are verified present
if (-not $Name)  { $Name  = Read-Host "  Your first name" }
if (-not $Email) { $Email = Read-Host "  Your work e-mail" }
$setupArgs = @('setup', '--name', $Name, '--email', $Email)
if (-not $Passphrase) {
    $sec = Read-Host "  Team passphrase (Tim gives it to you; typing is hidden)" -AsSecureString
    $Passphrase = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
}
$setupArgs += @('--passphrase', $Passphrase)
# Re-resolve cli.mjs (Dest may have been canonicalized); refuse setup if still missing.
$setupCli = Resolve-SleepmagCli $Dest
if (-not $setupCli) {
    throw "sleepmag CLI not found at $(Join-Path $Dest (Join-Path 'tools' (Join-Path 'sleepmag' 'cli.mjs'))). Refusing to run setup. Confirm GitHub access to tooltim/sleep-network, delete the workspace folder if incomplete, and re-run."
}
$setupLog = Join-Path $env:TEMP 'sleepnet-setup.log'
# Capture stdout+stderr without letting NativeCommandError terminate under $ErrorActionPreference=Stop.
# Node often writes warnings/progress to stderr even when setup succeeds; 2>&1 wraps those as ErrorRecords.
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $setupRaw = @(& $nodeExe $setupCli @setupArgs 2>&1)
    $setupExit = $LASTEXITCODE
} finally {
    $ErrorActionPreference = $prevEap
}
if ($null -eq $setupExit) { $setupExit = 0 }
# Stringify ErrorRecords so soft-continue regex and the log see plain text, not ErrorRecord objects.
$setupLines = @($setupRaw | ForEach-Object {
    if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.ToString() } else { "$_" }
})
$setupLines | ForEach-Object { Write-Host $_ }
$setupText = ($setupLines -join "`n")
try { Set-Content -LiteralPath $setupLog -Value $setupText -Encoding UTF8 } catch { }
if ($setupExit -ne 0) {
    if (-not $setupText) { $setupText = '' }
    # sleepmag prints "❌ Command not found: claude|codex" and currently exits non-zero even though assistants are optional.
    $assistantMissOnly = [regex]::Matches($setupText, '(?im)Command not found:\s*(claude|codex)\b')
    $scrubbed = [regex]::Replace($setupText, '(?im)^.*Command not found:\s*(claude|codex)\b.*\r?\n?', '')
    $otherHardFail = $scrubbed -match '(?im)(Command not found:|❌|✖|\bfatal\b|\berror\b)'
    $requiredOk = ($setupText -match '(?im)passphrase stored') -and ($setupText -match '(?im)platform')
    if ($assistantMissOnly.Count -gt 0 -and -not $otherHardFail -and $requiredOk) {
        $missed = @($assistantMissOnly | ForEach-Object { $_.Groups[1].Value.ToLowerInvariant() } | Select-Object -Unique) -join ', '
        Say "optional assistant CLI missing ($missed) — continuing (not required for setup)"
    } else {
        $tail = ($setupLines | Select-Object -Last 30) -join "`n"
        if (-not $tail) { $tail = '(no setup output captured — process may have crashed)' }
        $logHint = if (Test-Path -LiteralPath $setupLog) { "`nFull log: $setupLog" } else { '' }
        throw "sleepmag setup failed (exit $setupExit). Last output:`n$tail$logHint"
    }
}

# 5. Always ensure launcher + desktop shortcut(s) — do not rely on sleepmag creating the .lnk.
$launcher = Ensure-SleepmagCmd $Dest
$createdLnks = @()
$shortcutErrors = @()
foreach ($desk in (Get-DesktopFolders)) {
    try {
        $lnk = New-SleepNetworkShortcut $launcher $desk
        $createdLnks += $lnk
        Ok "shortcut: $lnk"
    } catch {
        $shortcutErrors += "${desk}: $($_.Exception.Message)"
        Say "could not create shortcut on $desk ($($_.Exception.Message))"
    }
}

Write-Host ""
if ($createdLnks.Count -gt 0) {
    Ok "Installed."
    foreach ($lnk in $createdLnks) {
        Write-Host ("  Shortcut: " + $lnk) -ForegroundColor Green
    }
    Write-Host ("  Or run: " + $launcher) -ForegroundColor Cyan
    Say "Double-click the Sleep Network shortcut, or run the path above."
} else {
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host "  WARN  Workspace is installed, but no desktop shortcut was created" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Yellow
    if ($shortcutErrors.Count -gt 0) {
        foreach ($e in $shortcutErrors) { Say "shortcut error: $e" }
    } else {
        Say "No Desktop folder was found (checked GetFolderPath('Desktop'), OneDrive Desktop, and %USERPROFILE%\Desktop)."
    }
    Write-Host ("  Or run: " + $launcher) -ForegroundColor Cyan
    Say "Do not look only on the Desktop — use the Or run path above (paste into File Explorer or a terminal)."
}
Say "First time only: the assistant asks you to log in with your own Claude / OpenAI account, and Claude asks you to trust the folder. Say yes to both."
Write-Host ""

} catch {
    $errText = $_.Exception.Message
    if (-not $errText) { $errText = "$_" }
    $detail = $null
    if ($_.ScriptStackTrace) { $detail = $_.ScriptStackTrace }
    Show-InstallFail $errText $detail
    Wait-OnInstallError
    exit 1
}
