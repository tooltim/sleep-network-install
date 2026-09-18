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

When it finishes, the installer prints the full **Shortcut:** path(s) and an **Or run:** fallback. Use those if you cannot see the icon.

## Where is Sleep Network?

1. **Desktop shortcut** named `Sleep Network`  
   Path is usually one of:
   - `%USERPROFILE%\Desktop\Sleep Network.lnk`
   - `%OneDrive%\Desktop\Sleep Network.lnk` (OneDrive-redirected Desktop — common on work PCs)
   The installer uses `[Environment]::GetFolderPath('Desktop')` and also tries classic + OneDrive Desktop folders, so look at the printed `Shortcut:` line for your exact path.

2. **Fallback launcher** (always works if install succeeded):
   - `%USERPROFILE%\Documents\sleep-network\sleepmag.cmd`
   - Or OneDrive Documents: `%OneDrive%\Documents\sleep-network\sleepmag.cmd`  
   Paste that path into File Explorer’s address bar, or run it from a terminal.

If install fails, keep the window open (the `.cmd` pauses; paste-into-PowerShell shows a red **FAIL** banner), screenshot it, and send it to Tim.

The installer is a copy of `install/install.ps1` in the private workspace repo; update it there and copy it here.
