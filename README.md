# Windows C: Drive Analyzer & Cleaner

A PowerShell script to find what's eating your C: drive and safely recover space — including hidden folders, developer caches, and AI model runners like Ollama.

---

## Real-World Case Study

This script was built from a real troubleshooting session on a **120 GB C: drive** that had only **2.57 GB free**.

### What We Found

| Folder | Reported Size | Real Size | Verdict |
|--------|--------------|-----------|---------|
| `C:\Users\<username>\.ollama\models\blobs` | 41.4 GB | ~0 GB | Sparse files — misleading! |
| `C:\Windows\WinSxS` | 19 GB | 19 GB | DISM can shrink this |
| `C:\Windows\LiveKernelReports` | 2.23 GB | 2.23 GB | Crash dumps — safe to delete |
| `AppData\Local\npm-cache` | 4.17 GB | 4.17 GB | Safe to wipe |
| `AppData\Local\Google` | 1.69 GB | 1.69 GB | Chrome cache — safe to wipe |
| `AppData\Local\uv` | 1.43 GB | 1.43 GB | Python uv cache — safe to wipe |
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

## Key Lesson: Sparse Files

Ollama (and some other tools) store model files as **NTFS sparse files** on Windows.

- Sparse files report a large **logical size** (e.g. 41 GB) in PowerShell's `Length` property
- But they consume very little **actual disk space**
- Deleting them frees almost nothing
- `ollama list` showing empty = all blobs are orphaned/incomplete downloads

**Don't be fooled by the reported size — check actual freed space after deletion.**

---

## What the Script Does

| Step | Action |
|------|--------|
| 1 | Shows top 15 largest folders on `C:\` |
| 2 | Scans `AppData\Local` (hidden — most tools miss this) |
| 3 | Finds `.vhdx` virtual disk files (Docker, WSL, app VMs) |
| 4 | Detects and fully removes Ollama |
| 5 | Cleans safe caches (npm, pip, uv, Chrome, Temp, Teams, Windows Update) |
| 6 | Runs DISM to shrink the WinSxS component store |

---

## Usage

### Requirements
- Windows 10 or 11
- PowerShell 5.1 or later
- **Run as Administrator**

### Run

```powershell
# Allow script execution for this session
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# Basic run
.\Analyze-And-Clean-CDrive.ps1

# Preview only — no deletions
.\Analyze-And-Clean-CDrive.ps1 -DryRun

# Skip the slow DISM step
.\Analyze-And-Clean-CDrive.ps1 -SkipDISM

# Also scan D: drive for Ollama/vhdx files
.\Analyze-And-Clean-CDrive.ps1 -IncludeDrive
```

---

## Common Hidden Space Hogs

### AppData\Local (hidden folder)
Most disk scanners miss this because it's a hidden system folder. It contains:
- Browser caches (Chrome, Edge)
- Developer tool caches (npm, pip, uv, cargo)
- Virtual machine disks (Docker, WSL, Claude desktop app)
- App update installers

### .vhdx Files (Virtual Disks)
These grow automatically but **never shrink on their own**:
- **Docker Desktop**: `C:\Users\<username>\AppData\Local\Docker\wsl\data\ext4.vhdx`
- **WSL (Ubuntu etc.)**: `C:\Users\<username>\AppData\Local\Packages\Canonical...\LocalState\ext4.vhdx`
- **Claude desktop app**: `C:\Users\<username>\AppData\Local\Packages\Claude_...\LocalCache\...\rootfs.vhdx`

### WinSxS (Windows Component Store)
Always looks huge (~15-25 GB). You cannot delete it manually — use DISM:
```powershell
DISM /Online /Cleanup-Image /StartComponentCleanup /ResetBase
```

### Ollama Model Runner
Stores AI models (Llama, Mistral, Qwen, etc.) in `C:\Users\<you>\.ollama\models\blobs`.
Each model is 2–8 GB. Use `ollama list` to see installed models, `ollama rm <name>` to remove.

---

## Manual Steps (Not in Script)

1. **Disk Cleanup**: Run `cleanmgr.exe` as Admin → click "Clean up system files" → check all boxes
2. **Storage Sense**: Settings → System → Storage → turn on Storage Sense
3. **Hibernation file** (`hiberfil.sys`): If you don't use hibernate, run `powercfg /hibernate off` to delete it (saves ~75% of your RAM in GB)
4. **Uninstall unused apps**: Settings → Apps → sort by size
5. **WinDirStat**: Free visual disk map tool — shows everything including hidden/system files

---

## Safety Notes

- The script uses `-ErrorAction SilentlyContinue` — it skips files it can't access without crashing
- The `-DryRun` flag lets you preview all deletions before committing
- System files (`System32`, `SysWOW64`, `registry`) are never touched
- `.vhdx` files are reported but **not deleted** — they belong to running apps
