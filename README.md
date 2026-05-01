# windows-storage-cleaner

An interactive PowerShell tool to analyze and clean your Windows C: drive.  
Finds hidden space hogs, developer caches, AI model runners, and virtual disks — then lets you clean them interactively with confirmation prompts.

---

## Features

- **Interactive menu** — numbered options, no flags to memorize
- **Live disk usage bar** — shows % used and GB free at every screen
- **Confirm before delete** — every deletion shows size and asks Y/N
- **Progress bars** — visible scanning progress for large folders
- **Session tracker** — shows total GB freed during your session
- **Auto log file** — saves everything to your Desktop as a `.txt` file
- **Finds hidden folders** — scans `AppData\Local` which most tools miss
- **Detects sparse files** — warns when Ollama blobs are logical-only size
- **Virtual disk finder** — locates `.vhdx` files from Docker, WSL, app VMs
- **Dev cache cleaner** — npm, pip, uv, cargo, Playwright in one place
- **DISM integration** — shrinks Windows component store with one click

---

## What It Cleans

| Category | What's included |
|----------|----------------|
| Windows junk | Temp folders, kernel crash dumps, Windows Update cache, Recycle Bin |
| Browser caches | Chrome, Edge, Firefox |
| Developer caches | npm, pip, uv, cargo registry, Playwright browsers |
| App caches | Teams, Slack, Discord, Spotify, `.cache` folder |
| Ollama | AI model blobs, manifests, AppData leftovers |
| DISM | Windows component store (WinSxS) — removes old update remnants |

---

## Usage

### Requirements
- Windows 10 or 11
- PowerShell 5.1+
- **Must run as Administrator**

### Run

```powershell
# 1. Open PowerShell as Administrator
# 2. Allow script execution for this session
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# 3. Run the script
.\Analyze-And-Clean-CDrive.ps1
```

### Menu Options

```
SCAN
  [1] Scan C:\ and AppData — shows top 15 folders + hidden AppData breakdown
  [2] Find .vhdx virtual disk files — Docker, WSL, app VMs
  [3] Check Ollama — shows registered models, blob count, size

CLEAN
  [4] Windows junk — Temp, crash dumps, Windows Update cache
  [5] Browser caches — Chrome, Edge, Firefox
  [6] Developer caches — npm, pip, uv, cargo, Playwright
  [7] App caches — Teams, Slack, Discord, Spotify
  [8] DISM — shrinks WinSxS (takes 5-15 min, cannot be undone)
  [9] Run ALL cleaners — walks through everything with prompts

  [S] Session summary — total freed, log file location
  [Q] Quit
```

---

## Real-World Case Study

Built from a real troubleshooting session on a **120 GB C: drive** with only **2.57 GB free**.

### What We Found

| Location | Reported | Real | Note |
|----------|----------|------|------|
| `~\.ollama\models\blobs` | 41.4 GB | ~0 GB | Sparse files — misleading number |
| `C:\Windows\WinSxS` | 19 GB | 19 GB | DISM can shrink this |
| `C:\Windows\LiveKernelReports` | 2.23 GB | 2.23 GB | Crash dumps — safe to delete |
| `AppData\Local\npm-cache` | 4.17 GB | 4.17 GB | Safe to wipe |
| `AppData\Local\Google` | 1.69 GB | 1.69 GB | Chrome cache |
| `AppData\Local\uv` | 1.43 GB | 1.43 GB | Python uv cache |
| `AppData\Local\ms-playwright` | 1.32 GB | 1.32 GB | Browser test binaries |
| `AppData\Local\pip` | 1.09 GB | 1.09 GB | Safe to wipe |

### Result

| Stage | Free Space |
|-------|-----------|
| Start | 2.57 GB |
| After Ollama removal | 10.69 GB |
| After Chrome + Temp + Playwright | 19.04 GB |
| After npm + pip + uv caches | ~25 GB |

---

## Key Lessons

### Sparse Files (Ollama)
Ollama stores model files as **NTFS sparse files** on Windows.  
They report a large *logical* size (e.g. 41 GB) but consume little *real* disk space.  
PowerShell's `Length` reads the logical size — so the number is misleading.  
Always verify actual freed space after deletion.

### AppData\Local Is Hidden
Most disk scanner tools (and basic PowerShell scans) skip `AppData\Local` because it's a hidden system folder.  
It commonly holds 5–20 GB of recoverable cache from browsers, dev tools, and apps.

### Virtual Disks Never Shrink
Docker, WSL, and some desktop apps store data in `.vhdx` virtual disk files.  
These grow automatically as you use the app but **never release space back to Windows** on their own.  
This script locates them so you know their size — but does not delete them automatically.

---

## Manual Steps (Not in Script)

| Action | How |
|--------|-----|
| Disk Cleanup | Run `cleanmgr.exe` as Admin → click "Clean up system files" → check all |
| Storage Sense | Settings → System → Storage → turn on Storage Sense |
| Hibernation file | `powercfg /hibernate off` — frees ~75% of your RAM in GB |
| Uninstall apps | Settings → Apps → sort by size |
| Visual disk map | Download **WinDirStat** — shows all files including hidden/system |

---

## Log File

Every run saves a timestamped log to your Desktop:
```
C:\Users\<username>\Desktop\disk-cleanup-log-2025-01-15_14-30.txt
```

---

## Safety

- Every deletion shows the size and asks **Y/N** before proceeding
- System files (`System32`, `SysWOW64`, registry) are never touched
- `.vhdx` files are shown but **never deleted automatically**
- Uses PowerShell environment variables — no hardcoded usernames or paths
