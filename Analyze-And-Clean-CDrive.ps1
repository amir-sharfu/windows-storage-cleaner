# =============================================================================
# Analyze-And-Clean-CDrive.ps1
# Author: Published via GitHub
# Description: Analyzes Windows C: drive usage, finds hidden space hogs,
#              and safely cleans recoverable space.
# Run as: Administrator
# =============================================================================

param(
    [switch]$DryRun,        # Show what would be deleted without deleting
    [switch]$SkipDISM,      # Skip the slow DISM component cleanup
    [switch]$IncludeDrive   # Also scan D: drive if present
)

function Get-FolderSize {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 0 }
    (Get-ChildItem $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
     Measure-Object -Property Length -Sum).Sum
}

function Format-GB {
    param([long]$Bytes)
    [math]::Round($Bytes / 1GB, 2)
}

function Remove-SafeItem {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path $Path)) { return }
    $size = Get-FolderSize $Path
    if ($DryRun) {
        Write-Host "[DRY RUN] Would delete: $Label ($( Format-GB $size ) GB)" -ForegroundColor Yellow
    } else {
        Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "Deleted: $Label ($( Format-GB $size ) GB freed)" -ForegroundColor Green
    }
}

# =============================================================================
# STEP 0 — Baseline
# =============================================================================
Write-Host "`n=============================================" -ForegroundColor Cyan
Write-Host " Windows C: Drive Analyzer & Cleaner" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

$driveBefore = Get-PSDrive C
$freeBefore  = Format-GB $driveBefore.Free
$usedBefore  = Format-GB $driveBefore.Used
$totalGB     = Format-GB ($driveBefore.Free + $driveBefore.Used)

Write-Host "`n[BASELINE] Free: $freeBefore GB  |  Used: $usedBefore GB  |  Total: $totalGB GB" -ForegroundColor Yellow

# =============================================================================
# STEP 1 — Top-Level Folder Sizes on C:\
# =============================================================================
Write-Host "`n[1/6] Scanning top-level folders on C:\ ..." -ForegroundColor Cyan

Get-ChildItem -Path "C:\" -Directory -ErrorAction SilentlyContinue |
  ForEach-Object {
    $bytes = Get-FolderSize $_.FullName
    [PSCustomObject]@{ Folder = $_.FullName; SizeGB = Format-GB $bytes }
  } |
  Sort-Object SizeGB -Descending |
  Select-Object -First 15 |
  Format-Table -AutoSize

# =============================================================================
# STEP 2 — AppData\Local Breakdown (hidden folder — most scanners miss this)
# =============================================================================
Write-Host "`n[2/6] Scanning AppData\Local (hidden) ..." -ForegroundColor Cyan
Write-Host "NOTE: This folder is hidden from regular scans. Contains app caches and virtual disks." -ForegroundColor DarkYellow

Get-ChildItem -Path "$env:LOCALAPPDATA" -Directory -Force -ErrorAction SilentlyContinue |
  ForEach-Object {
    $bytes = Get-FolderSize $_.FullName
    [PSCustomObject]@{ Folder = $_.Name; SizeGB = Format-GB $bytes }
  } |
  Sort-Object SizeGB -Descending |
  Select-Object -First 20 |
  Format-Table -AutoSize

# =============================================================================
# STEP 3 — Virtual Disk Files (.vhdx) — Docker / WSL / App VMs
# =============================================================================
Write-Host "`n[3/6] Searching for virtual disk files (.vhdx) ..." -ForegroundColor Cyan
Write-Host "NOTE: These grow automatically and never shrink. Common culprits: Docker, WSL, Claude app." -ForegroundColor DarkYellow

$drives = @("C:\")
if ($IncludeDrive -and (Test-Path "D:\")) { $drives += "D:\" }

foreach ($drv in $drives) {
    Get-ChildItem -Path $drv -Recurse -Filter "*.vhdx" -Force -ErrorAction SilentlyContinue |
      Select-Object FullName, @{N='SizeGB';E={Format-GB $_.Length}} |
      Sort-Object SizeGB -Descending |
      Format-Table -AutoSize
}

# =============================================================================
# STEP 4 — Ollama Detection & Removal
# =============================================================================
Write-Host "`n[4/6] Checking for Ollama AI model runner ..." -ForegroundColor Cyan
Write-Host "NOTE: Ollama blob files appear large but may be sparse files (logical size != real size)." -ForegroundColor DarkYellow

$ollamaPath   = "$env:USERPROFILE\.ollama"
$ollamaLocal  = "$env:LOCALAPPDATA\Ollama"
$ollamaRoaming = "$env:APPDATA\Ollama"

if (Test-Path $ollamaPath) {
    $blobCount = (Get-ChildItem "$ollamaPath\models\blobs" -Recurse -File -ErrorAction SilentlyContinue).Count
    $logicalGB = Format-GB (Get-FolderSize $ollamaPath)
    Write-Host "Found .ollama folder  — Logical size: $logicalGB GB  |  Blob files: $blobCount" -ForegroundColor Red

    # List registered models
    Write-Host "Registered models:" -ForegroundColor White
    & ollama list 2>$null

    Remove-SafeItem $ollamaPath    "Ollama home (.ollama)"
    Remove-SafeItem $ollamaLocal   "Ollama AppData\Local"
    Remove-SafeItem $ollamaRoaming "Ollama AppData\Roaming"
} else {
    Write-Host "No .ollama folder found — already clean." -ForegroundColor Green
}

# =============================================================================
# STEP 5 — Safe Cache Cleanup
# =============================================================================
Write-Host "`n[5/6] Cleaning known safe caches ..." -ForegroundColor Cyan

# Windows system caches
Remove-SafeItem "C:\Windows\Temp\*"                                                     "Windows Temp"
Remove-SafeItem "C:\Windows\LiveKernelReports\*"                                        "Kernel Crash Dumps"
Remove-SafeItem "C:\Windows\SoftwareDistribution\Download\*"                            "Windows Update Cache"

# User caches
Remove-SafeItem "$env:LOCALAPPDATA\Temp\*"                                              "User Temp"
Remove-SafeItem "$env:LOCALAPPDATA\Microsoft\Windows\INetCache\*"                       "IE/Edge Cache"
Remove-SafeItem "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache\*"             "Chrome Cache"
Remove-SafeItem "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache\*"        "Chrome Code Cache"
Remove-SafeItem "$env:APPDATA\Microsoft\Teams\Cache\*"                                  "Teams Cache"

# Developer tool caches
if (Get-Command npm -ErrorAction SilentlyContinue) {
    Write-Host "Cleaning npm cache..." -ForegroundColor White
    if (-not $DryRun) { npm cache clean --force 2>$null }
}
if (Get-Command pip -ErrorAction SilentlyContinue) {
    Write-Host "Cleaning pip cache..." -ForegroundColor White
    if (-not $DryRun) { pip cache purge 2>$null }
}
if (Get-Command uv -ErrorAction SilentlyContinue) {
    Write-Host "Cleaning uv cache..." -ForegroundColor White
    if (-not $DryRun) { uv cache clean 2>$null }
}

# Empty Recycle Bin
Write-Host "Emptying Recycle Bin..." -ForegroundColor White
if (-not $DryRun) { Clear-RecycleBin -Force -ErrorAction SilentlyContinue }

# =============================================================================
# STEP 6 — Windows Component Store Cleanup (DISM)
# =============================================================================
if (-not $SkipDISM) {
    Write-Host "`n[6/6] Running DISM component cleanup (this takes 5-10 min) ..." -ForegroundColor Cyan
    Write-Host "NOTE: Shrinks WinSxS folder by removing superseded Windows Update components." -ForegroundColor DarkYellow
    if (-not $DryRun) {
        DISM /Online /Cleanup-Image /StartComponentCleanup /ResetBase
    } else {
        Write-Host "[DRY RUN] Would run: DISM /Online /Cleanup-Image /StartComponentCleanup /ResetBase" -ForegroundColor Yellow
    }
} else {
    Write-Host "`n[6/6] Skipping DISM (use without -SkipDISM to enable)" -ForegroundColor DarkGray
}

# =============================================================================
# SUMMARY
# =============================================================================
Write-Host "`n=============================================" -ForegroundColor Cyan
Write-Host " SUMMARY" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

$driveAfter = Get-PSDrive C
$freeAfter  = Format-GB $driveAfter.Free
$freedGB    = [math]::Round($freeAfter - $freeBefore, 2)

Write-Host "Free before : $freeBefore GB" -ForegroundColor Yellow
Write-Host "Free after  : $freeAfter GB"  -ForegroundColor Green
Write-Host "Total freed : $freedGB GB"     -ForegroundColor Cyan

Write-Host "`nManual steps still recommended:" -ForegroundColor White
Write-Host "  1. Run Disk Cleanup: cleanmgr.exe (click 'Clean up system files')" -ForegroundColor White
Write-Host "  2. Settings > System > Storage > Storage Sense (enable auto cleanup)" -ForegroundColor White
Write-Host "  3. Settings > Apps — uninstall apps you no longer use" -ForegroundColor White
Write-Host "  4. Use WinDirStat for a full visual map of disk usage" -ForegroundColor White
Write-Host ""
