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

Write-Host ""; Write-Host "Sleep Network installer" -ForegroundColor Cyan; Write-Host ""
$ProgressPreference = 'SilentlyContinue'

if ($Check) {
    Refresh-Path
    foreach ($c in 'git', 'node', 'claude', 'codex', 'python') { if (Have $c) { Ok "$c found" } else { Say "$c missing" } }
    Say ("workspace: " + $(if (Test-Path (Join-Path $Dest 'sleepmag.cmd')) { 'present' } else { 'not installed' }))
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

# 2. Workspace
if (-not (Test-Path (Join-Path $Dest '.git'))) {
    Say "downloading the workspace into $Dest (a GitHub login window may open: use your GitHub account)…"
    & $gitExe clone -q $Repo $Dest
} else { Say "workspace already present, updating…"; & $gitExe -C $Dest pull -q --ff-only }
# Canonicalize Dest (OneDrive Documents redirects / junctions) so later CLI paths resolve reliably.
if (Test-Path -LiteralPath $Dest) {
    try { $Dest = (Resolve-Path -LiteralPath $Dest).Path } catch { }
}
Ok "workspace at $Dest"

# 3. Assistant preference + optional install (before sleepmag setup so chosen CLIs are on PATH)
# Claude/Codex are optional: missing must never abort install/setup.
if (-not $Assistant) {
    $a = Read-Host "  Which assistant do you use? [1] Claude Code  [2] Codex  [3] both  [4] already installed / skip"
    $Assistant = @{ '1' = 'claude'; '2' = 'codex'; '3' = 'both'; '4' = 'none' }[$a]; if (-not $Assistant) { $Assistant = 'none' }
}
if ($Assistant -notin 'claude','codex','both','none') { $Assistant = 'none' }
if (($Assistant -eq 'claude' -or $Assistant -eq 'both') -and -not (Have 'claude')) {
    Say "installing Claude Code…"
    try { Invoke-RestMethod https://claude.ai/install.ps1 | Invoke-Expression } catch { Say "Claude install skipped ($($_.Exception.Message))" }
    Refresh-Path
}
if (($Assistant -eq 'codex' -or $Assistant -eq 'both') -and -not (Have 'codex')) {
    Say "installing Codex…"
    try { npm install -g @openai/codex | Out-Null } catch { Say "Codex install skipped ($($_.Exception.Message))" }
    Refresh-Path
}
if (($Assistant -eq 'claude' -or $Assistant -eq 'both') -and -not (Have 'claude')) { Say "claude not on PATH yet (optional — continuing)" }
if (($Assistant -eq 'codex' -or $Assistant -eq 'both') -and -not (Have 'codex')) { Say "codex not on PATH yet (optional — continuing)" }

# 4. Identity + passphrase + platform + shortcut + PATH (sleepmag setup)
if (-not $Name)  { $Name  = Read-Host "  Your first name" }
if (-not $Email) { $Email = Read-Host "  Your work e-mail" }
$setupArgs = @('setup', '--name', $Name, '--email', $Email)
if (-not $Passphrase) {
    $sec = Read-Host "  Team passphrase (Tim gives it to you; typing is hidden)" -AsSecureString
    $Passphrase = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
}
$setupArgs += @('--passphrase', $Passphrase)
# Resolve cli.mjs under Dest (backslash/forward slash + OneDrive-safe absolute path).
$setupCli = $null
foreach ($rel in @((Join-Path 'tools' (Join-Path 'sleepmag' 'cli.mjs')), 'tools\sleepmag\cli.mjs', 'tools/sleepmag/cli.mjs')) {
    $candidate = Join-Path $Dest $rel
    if (Test-Path -LiteralPath $candidate) {
        try { $setupCli = (Resolve-Path -LiteralPath $candidate).Path } catch { $setupCli = $candidate }
        break
    }
}
if (-not $setupCli) {
    throw "sleepmag CLI not found at $(Join-Path $Dest (Join-Path 'tools' (Join-Path 'sleepmag' 'cli.mjs'))). Re-run after confirming GitHub access to tooltim/sleep-network, or delete the workspace folder and try again."
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
        if (-not (Test-Path (Join-Path $Dest 'sleepmag.cmd'))) {
            Say "note: sleepmag may have stopped before finishing the desktop shortcut/PATH; re-run after the sleepmag optional-assistant fix if the shortcut is missing"
        }
    } else {
        throw "setup failed"
    }
}

Write-Host ""
Ok "Installed. Double-click 'Sleep Network' on your desktop."
Say "First time only: the assistant asks you to log in with your own Claude / OpenAI account, and Claude asks you to trust the folder. Say yes to both."
Write-Host ""
