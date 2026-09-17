# Sleep Network installer

Public because a teammate needs to be able to download it before they have access to anything else.
It contains no secrets: it installs Git/Node/Python if missing, clones the **private** `tooltim/sleep-network`
workspace (GitHub asks you to log in), and runs its setup (your name, e-mail, the team passphrase Tim gives you).

**You need a GitHub invite to `tooltim/sleep-network`.** Without it, clone fails with `Repository not found` and the installer stops (it will not pretend the workspace is OK). Prefer `gh auth login` (or Git Credential Manager) before retrying.

## Install (Windows)

Open **PowerShell** (Start menu → type PowerShell → Enter) and paste:

```powershell
irm https://raw.githubusercontent.com/tooltim/sleep-network-install/main/install.ps1 | iex
```

Or download and double-click [`Install-SleepNetwork.cmd`](https://github.com/tooltim/sleep-network-install/raw/main/Install-SleepNetwork.cmd).

When it finishes there is a **Sleep Network** icon on your desktop. That is all you use from then on.

The installer is a copy of `install/install.ps1` in the private workspace repo; update it there and copy it here.
