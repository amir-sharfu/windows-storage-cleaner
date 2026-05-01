# =============================================================================
# Analyze-And-Clean-CDrive.ps1
# Description : Interactive Windows C: drive analyzer and cleaner
# Run as      : Administrator
# Usage       : .\Analyze-And-Clean-CDrive.ps1
# =============================================================================

#Requires -RunAsAdministrator

$script:LogFile = "$env:USERPROFILE\Desktop\disk-cleanup-log-$(Get-Date -Format 'yyyy-MM-dd_HH-mm').txt"
$script:TotalFreed = 0

# =============================================================================
# UTILITIES
# =============================================================================

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
    Add-Content -Path $script:LogFile -Value $Message -ErrorAction SilentlyContinue
}

function Get-FolderSize {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 0 }
    (Get-ChildItem $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
     Measure-Object -Property Length -Sum).Sum
}

function Format-GB { param([long]$Bytes) [math]::Round($Bytes / 1GB, 2) }
function Format-MB { param([long]$Bytes) [math]::Round($Bytes / 1MB, 1) }

function Get-FreeSpace { [math]::Round((Get-PSDrive C).Free / 1GB, 2) }

function Show-Header {
    Clear-Host
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║       Windows C: Drive Analyzer & Cleaner        ║" -ForegroundColor Cyan
    Write-Host "  ║              Run as Administrator                 ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
    $free  = Get-FreeSpace
    $used  = [math]::Round((Get-PSDrive C).Used / 1GB, 2)
    $total = [math]::Round($free + $used, 2)
    $pct   = [math]::Round(($used / $total) * 100)
    $bar   = "#" * [math]::Round($pct / 5)
    $empty = "-" * (20 - [math]::Round($pct / 5))
    $color = if ($pct -gt 90) { "Red" } elseif ($pct -gt 75) { "Yellow" } else { "Green" }
    Write-Host ""
    Write-Host "  Drive C:  [$bar$empty] $pct% used" -ForegroundColor $color
    Write-Host "  Free: $free GB  |  Used: $used GB  |  Total: $total GB" -ForegroundColor White
    Write-Host "  Session freed so far: $script:TotalFreed GB" -ForegroundColor Green
    Write-Host ""
}

function Confirm-Delete {
    param([string]$Label, [double]$SizeGB)
    $color = if ($SizeGB -gt 2) { "Red" } elseif ($SizeGB -gt 0.5) { "Yellow" } else { "Green" }
    Write-Host ""
    Write-Host "  $Label" -ForegroundColor White
    Write-Host "  Size: $SizeGB GB" -ForegroundColor $color
    $choice = Read-Host "  Delete this? [Y/N]"
    return $choice -match "^[Yy]"
}

function Remove-WithConfirm {
    param([string]$Path, [string]$Label, [switch]$NoConfirm)
    if (-not (Test-Path $Path)) {
        Write-Log "  [SKIP] Not found: $Label" "DarkGray"
        return
    }
    $before = Get-FolderSize $Path
    $sizeGB = Format-GB $before
    if ($sizeGB -eq 0) {
        Write-Log "  [SKIP] Already empty: $Label" "DarkGray"
        return
    }
    $go = $NoConfirm -or (Confirm-Delete -Label $Label -SizeGB $sizeGB)
    if ($go) {
        Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue
        $freed = $before - (Get-FolderSize $Path)
        $freedGB = Format-GB $freed
        $script:TotalFreed = [math]::Round($script:TotalFreed + $freedGB, 2)
        Write-Log "  [DELETED] $Label — freed $freedGB GB" "Green"
    } else {
        Write-Log "  [KEPT] $Label" "DarkGray"
    }
}

function Show-Progress {
    param([string]$Activity, [int]$Percent)
    Write-Progress -Activity $Activity -PercentComplete $Percent
}

# =============================================================================
# SCAN FUNCTIONS
# =============================================================================

function Show-DriveScan {
    Show-Header
    Write-Log "═══ TOP FOLDERS ON C:\ ═══" "Cyan"
    Write-Log ""
    $items = Get-ChildItem -Path "C:\" -Directory -ErrorAction SilentlyContinue
    $i = 0
    $results = foreach ($item in $items) {
        $i++
        Show-Progress "Scanning C:\ folders..." ([math]::Round($i / $items.Count * 100))
        $bytes = Get-FolderSize $item.FullName
        [PSCustomObject]@{ Folder = $item.FullName; SizeGB = Format-GB $bytes }
    }
    Write-Progress -Activity "Scanning" -Completed
    $results | Sort-Object SizeGB -Descending | Select-Object -First 15 | Format-Table -AutoSize
    Write-Log ""
    Write-Log "═══ APDATA\LOCAL (hidden) ═══" "Cyan"
    Write-Log "  Most scanners miss this folder." "DarkYellow"
    Write-Log ""
    $items2 = Get-ChildItem -Path "$env:LOCALAPPDATA" -Directory -Force -ErrorAction SilentlyContinue
    $j = 0
    $results2 = foreach ($item in $items2) {
        $j++
        Show-Progress "Scanning AppData\Local..." ([math]::Round($j / $items2.Count * 100))
        $bytes = Get-FolderSize $item.FullName
        [PSCustomObject]@{ Folder = $item.Name; SizeGB = Format-GB $bytes }
    }
    Write-Progress -Activity "Scanning" -Completed
    $results2 | Sort-Object SizeGB -Descending | Select-Object -First 20 | Format-Table -AutoSize
    Pause
}

function Show-VhdxScan {
    Show-Header
    Write-Log "═══ VIRTUAL DISK FILES (.vhdx) ═══" "Cyan"
    Write-Log "  Docker / WSL / App VMs grow silently and never shrink." "DarkYellow"
    Write-Log ""
    $found = Get-ChildItem -Path "C:\Users" -Recurse -Filter "*.vhdx" -Force -ErrorAction SilentlyContinue |
             Select-Object FullName, @{N='SizeGB';E={Format-GB $_.Length}} |
             Sort-Object SizeGB -Descending
    if ($found) {
        $found | Format-Table -AutoSize
        Write-Log "  NOTE: These belong to running apps. Do NOT delete unless you uninstall the app." "Yellow"
    } else {
        Write-Log "  No .vhdx files found." "Green"
    }
    Pause
}

function Show-OllamaScan {
    Show-Header
    Write-Log "═══ OLLAMA AI MODEL RUNNER ═══" "Cyan"
    Write-Log ""
    $ollamaPath = "$env:USERPROFILE\.ollama"
    if (-not (Test-Path $ollamaPath)) {
        Write-Log "  Ollama not found — already clean." "Green"
        Pause; return
    }
    $logicalGB  = Format-GB (Get-FolderSize $ollamaPath)
    $blobCount  = (Get-ChildItem "$ollamaPath\models\blobs" -Recurse -File -ErrorAction SilentlyContinue).Count
    Write-Log "  Location  : $ollamaPath" "White"
    Write-Log "  Logical size: $logicalGB GB  (may be sparse — actual disk use could be less)" "Yellow"
    Write-Log "  Blob files: $blobCount" "White"
    Write-Log ""
    Write-Log "  Registered models:" "White"
    $models = & ollama list 2>$null
    if ($models) { Write-Log $models "White" } else { Write-Log "  (none)" "DarkGray" }
    Write-Log ""

    $choice = Read-Host "  Remove all Ollama data? [Y/N]"
    if ($choice -match "^[Yy]") {
        Stop-Process -Name "ollama" -Force -ErrorAction SilentlyContinue
        Remove-WithConfirm "$ollamaPath"                   "Ollama home (.ollama)"           -NoConfirm
        Remove-WithConfirm "$env:LOCALAPPDATA\Ollama"      "Ollama AppData\Local"            -NoConfirm
        Remove-WithConfirm "$env:APPDATA\Ollama"           "Ollama AppData\Roaming"          -NoConfirm
        Write-Log "  Ollama fully removed." "Green"
    } else {
        Write-Log "  Kept Ollama." "DarkGray"
    }
    Pause
}

# =============================================================================
# CLEAN FUNCTIONS
# =============================================================================

function Clean-WindowsJunk {
    Show-Header
    Write-Log "═══ WINDOWS SYSTEM JUNK ═══" "Cyan"
    Write-Log ""

    # Stop Windows Update service before clearing its cache
    $wuRunning = (Get-Service wuauserv).Status -eq "Running"
    if ($wuRunning) { Stop-Service wuauserv -Force -ErrorAction SilentlyContinue }

    Remove-WithConfirm "C:\Windows\Temp\*"                                     "Windows Temp"
    Remove-WithConfirm "C:\Windows\LiveKernelReports\*"                        "Kernel Crash Dumps"
    Remove-WithConfirm "C:\Windows\SoftwareDistribution\Download\*"            "Windows Update Download Cache"
    Remove-WithConfirm "$env:LOCALAPPDATA\Temp\*"                              "User Temp (AppData)"
    Remove-WithConfirm "$env:LOCALAPPDATA\Microsoft\Windows\INetCache\*"       "IE / Edge Cache"

    if ($wuRunning) { Start-Service wuauserv -ErrorAction SilentlyContinue }

    Write-Log ""
    Write-Log "  Emptying Recycle Bin..." "White"
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    Write-Log "  Recycle Bin cleared." "Green"
    Pause
}

function Clean-BrowserCaches {
    Show-Header
    Write-Log "═══ BROWSER CACHES ═══" "Cyan"
    Write-Log ""
    Remove-WithConfirm "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache\*"       "Chrome Cache"
    Remove-WithConfirm "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache\*"  "Chrome Code Cache"
    Remove-WithConfirm "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache\*"      "Edge Cache"
    Remove-WithConfirm "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache\*" "Edge Code Cache"
    Remove-WithConfirm "$env:APPDATA\Mozilla\Firefox\Profiles"                           "Firefox Cache"
    Pause
}

function Clean-DevCaches {
    Show-Header
    Write-Log "═══ DEVELOPER TOOL CACHES ═══" "Cyan"
    Write-Log ""

    # npm
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        $npmSize = Format-GB (Get-FolderSize "$env:LOCALAPPDATA\npm-cache")
        $choice = Read-Host "  npm cache ($npmSize GB) — Clean? [Y/N]"
        if ($choice -match "^[Yy]") {
            npm cache clean --force 2>$null
            Write-Log "  [DELETED] npm cache" "Green"
        }
    }

    # pip
    if (Get-Command pip -ErrorAction SilentlyContinue) {
        $pipSize = Format-GB (Get-FolderSize "$env:LOCALAPPDATA\pip")
        $choice = Read-Host "  pip cache ($pipSize GB) — Clean? [Y/N]"
        if ($choice -match "^[Yy]") {
            pip cache purge 2>$null
            Write-Log "  [DELETED] pip cache" "Green"
        }
    }

    # uv
    if (Get-Command uv -ErrorAction SilentlyContinue) {
        $uvSize = Format-GB (Get-FolderSize "$env:LOCALAPPDATA\uv")
        $choice = Read-Host "  uv cache ($uvSize GB) — Clean? [Y/N]"
        if ($choice -match "^[Yy]") {
            uv cache clean 2>$null
            Write-Log "  [DELETED] uv cache" "Green"
        }
    }

    # cargo
    Remove-WithConfirm "$env:USERPROFILE\.cargo\registry" "Rust cargo registry cache"
    Remove-WithConfirm "$env:USERPROFILE\.cargo\git"       "Rust cargo git cache"

    # Playwright
    Remove-WithConfirm "$env:LOCALAPPDATA\ms-playwright"     "Playwright browsers"
    Remove-WithConfirm "$env:LOCALAPPDATA\ms-playwright-go"  "Playwright Go browsers"

    Pause
}

function Clean-AppCaches {
    Show-Header
    Write-Log "═══ APP CACHES ═══" "Cyan"
    Write-Log ""
    Remove-WithConfirm "$env:APPDATA\Microsoft\Teams\Cache\*"                 "Microsoft Teams Cache"
    Remove-WithConfirm "$env:APPDATA\Slack\Cache\*"                           "Slack Cache"
    Remove-WithConfirm "$env:APPDATA\Spotify\Data\*"                          "Spotify Cache"
    Remove-WithConfirm "$env:LOCALAPPDATA\Discord\Cache\*"                    "Discord Cache"
    Remove-WithConfirm "$env:USERPROFILE\.cache\*"                            "General .cache folder"
    Pause
}

function Run-DismCleanup {
    Show-Header
    Write-Log "═══ WINDOWS COMPONENT STORE (DISM) ═══" "Cyan"
    Write-Log ""
    Write-Log "  This shrinks WinSxS by removing old Windows Update components." "White"
    Write-Log "  Takes 5-15 minutes. Cannot be undone." "Yellow"
    Write-Log ""
    $choice = Read-Host "  Run DISM cleanup now? [Y/N]"
    if ($choice -match "^[Yy]") {
        Write-Log "  Running DISM... please wait." "White"
        DISM /Online /Cleanup-Image /StartComponentCleanup /ResetBase
        Write-Log "  DISM cleanup complete." "Green"
    } else {
        Write-Log "  Skipped." "DarkGray"
    }
    Pause
}

function Run-CleanAll {
    Show-Header
    Write-Log "═══ CLEAN EVERYTHING ═══" "Cyan"
    Write-Log "  This will prompt you for each category." "Yellow"
    Write-Log ""
    $choice = Read-Host "  Continue with full clean? [Y/N]"
    if ($choice -notmatch "^[Yy]") { return }
    Clean-WindowsJunk
    Clean-BrowserCaches
    Clean-DevCaches
    Clean-AppCaches
    Show-OllamaScan
}

function Show-Summary {
    Show-Header
    Write-Log "═══ SESSION SUMMARY ═══" "Cyan"
    Write-Log ""
    Write-Log "  Total space freed this session : $script:TotalFreed GB" "Green"
    Write-Log "  Current free space on C:       : $(Get-FreeSpace) GB" "White"
    Write-Log "  Log saved to                   : $script:LogFile" "White"
    Write-Log ""
    Write-Log "  Manual steps still recommended:" "Yellow"
    Write-Log "    1. Run Disk Cleanup : cleanmgr.exe (click 'Clean up system files')" "White"
    Write-Log "    2. Storage Sense    : Settings > System > Storage > Storage Sense" "White"
    Write-Log "    3. Uninstall apps   : Settings > Apps (sort by size)" "White"
    Write-Log "    4. Hibernation file : Run 'powercfg /hibernate off' to delete hiberfil.sys" "White"
    Write-Log "    5. Visual map       : Download WinDirStat for full disk visualization" "White"
    Write-Log ""
    Pause
}

# =============================================================================
# MAIN MENU
# =============================================================================

function Show-Menu {
    Show-Header
    Write-Host "  ┌─────────────────────────────────────────────────┐" -ForegroundColor DarkCyan
    Write-Host "  │                    MAIN MENU                    │" -ForegroundColor DarkCyan
    Write-Host "  ├─────────────────────────────────────────────────┤" -ForegroundColor DarkCyan
    Write-Host "  │  SCAN                                           │" -ForegroundColor DarkCyan
    Write-Host "  │   [1] Scan C:\ and AppData (find space hogs)   │" -ForegroundColor White
    Write-Host "  │   [2] Find virtual disk files (.vhdx)          │" -ForegroundColor White
    Write-Host "  │   [3] Check Ollama AI model runner              │" -ForegroundColor White
    Write-Host "  ├─────────────────────────────────────────────────┤" -ForegroundColor DarkCyan
    Write-Host "  │  CLEAN                                          │" -ForegroundColor DarkCyan
    Write-Host "  │   [4] Windows junk (Temp, crash dumps, WU)     │" -ForegroundColor White
    Write-Host "  │   [5] Browser caches (Chrome, Edge, Firefox)   │" -ForegroundColor White
    Write-Host "  │   [6] Developer caches (npm, pip, uv, cargo)   │" -ForegroundColor White
    Write-Host "  │   [7] App caches (Teams, Slack, Discord)       │" -ForegroundColor White
    Write-Host "  │   [8] DISM — shrink Windows component store    │" -ForegroundColor White
    Write-Host "  │   [9] Run ALL cleaners (guided)                │" -ForegroundColor Yellow
    Write-Host "  ├─────────────────────────────────────────────────┤" -ForegroundColor DarkCyan
    Write-Host "  │   [S] Session summary + log location           │" -ForegroundColor Green
    Write-Host "  │   [Q] Quit                                      │" -ForegroundColor Red
    Write-Host "  └─────────────────────────────────────────────────┘" -ForegroundColor DarkCyan
    Write-Host ""
}

# =============================================================================
# ENTRY POINT
# =============================================================================

Add-Content -Path $script:LogFile -Value "=== Disk Cleanup Session: $(Get-Date) ===" -ErrorAction SilentlyContinue

do {
    Show-Menu
    $input = Read-Host "  Enter choice"
    switch ($input.Trim().ToUpper()) {
        "1" { Show-DriveScan }
        "2" { Show-VhdxScan }
        "3" { Show-OllamaScan }
        "4" { Clean-WindowsJunk }
        "5" { Clean-BrowserCaches }
        "6" { Clean-DevCaches }
        "7" { Clean-AppCaches }
        "8" { Run-DismCleanup }
        "9" { Run-CleanAll }
        "S" { Show-Summary }
        "Q" { Show-Summary; break }
        default { Write-Host "  Invalid choice. Try again." -ForegroundColor Red; Start-Sleep 1 }
    }
} while ($input.Trim().ToUpper() -ne "Q")
