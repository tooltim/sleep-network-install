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
function Winget-Install($id, $label) {
    if (-not (Have 'winget')) { throw "winget is missing; install $label by hand (https://$label) and run this again." }
    Say "installing $label…"; winget install --id $id -e --silent --accept-package-agreements --accept-source-agreements | Out-Null
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}

Write-Host ""; Write-Host "Sleep Network installer" -ForegroundColor Cyan; Write-Host ""
$ProgressPreference = 'SilentlyContinue'

if ($Check) {
    foreach ($c in 'git', 'node', 'claude', 'codex', 'python') { if (Have $c) { Ok "$c found" } else { Say "$c missing" } }
    Say ("workspace: " + $(if (Test-Path (Join-Path $Dest 'sleepmag.cmd')) { 'present' } else { 'not installed' }))
    exit 0
}

# 1. Tools
if (-not (Have 'git')) { Winget-Install 'Git.Git' 'git-scm.com' } ; Ok ("git " + ((git --version) -replace 'git version ', ''))
if (-not (Have 'node')) { Winget-Install 'OpenJS.NodeJS.LTS' 'nodejs.org' } ; Ok ("node " + (node --version))
if (-not (Have 'python')) { Winget-Install 'Python.Python.3.12' 'python.org' } ; Ok "python present (used to repair the server allowlist)"

# 2. Workspace
if (-not (Test-Path (Join-Path $Dest '.git'))) {
    Say "downloading the workspace into $Dest (a GitHub login window may open: use your GitHub account)…"
    git clone -q $Repo $Dest
} else { Say "workspace already present, updating…"; git -C $Dest pull -q --ff-only }
Ok "workspace at $Dest"

# 3. Identity + passphrase + platform + shortcut + PATH (sleepmag setup)
if (-not $Name)  { $Name  = Read-Host "  Your first name" }
if (-not $Email) { $Email = Read-Host "  Your work e-mail" }
$setupArgs = @('setup', '--name', $Name, '--email', $Email)
if (-not $Passphrase) {
    $sec = Read-Host "  Team passphrase (Tim gives it to you; typing is hidden)" -AsSecureString
    $Passphrase = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
}
$setupArgs += @('--passphrase', $Passphrase)
& node (Join-Path $Dest 'tools\sleepmag\cli.mjs') @setupArgs
if ($LASTEXITCODE -ne 0) { throw "setup failed" }

# 4. Assistant
if (-not $Assistant) {
    $a = Read-Host "  Which assistant do you use? [1] Claude Code  [2] Codex  [3] both  [4] already installed"
    $Assistant = @{ '1' = 'claude'; '2' = 'codex'; '3' = 'both'; '4' = 'none' }[$a]; if (-not $Assistant) { $Assistant = 'none' }
}
if ($Assistant -notin 'claude','codex','both','none') { $Assistant = 'none' }
if (($Assistant -eq 'claude' -or $Assistant -eq 'both') -and -not (Have 'claude')) { Say "installing Claude Code…"; Invoke-RestMethod https://claude.ai/install.ps1 | Invoke-Expression }
if (($Assistant -eq 'codex' -or $Assistant -eq 'both') -and -not (Have 'codex')) { Say "installing Codex…"; npm install -g @openai/codex | Out-Null }

Write-Host ""
Ok "Installed. Double-click 'Sleep Network' on your desktop."
Say "First time only: the assistant asks you to log in with your own Claude / OpenAI account, and Claude asks you to trust the folder. Say yes to both."
Write-Host ""
