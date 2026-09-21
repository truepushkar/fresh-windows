#requires -Version 5.1
<#
    Fresh Windows Setup
    --------------------
    Version : 2.2
    Purpose : Interactive bulk-install / remove tool for a freshly imaged
              Windows machine, built on top of WinGet + the Office
              Deployment Tool.
#>

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ============================================================
#  PALETTE  (single source of truth for the look & feel)
# ============================================================

$C = @{
    Accent   = "Cyan"
    Title    = "White"
    Success  = "Green"
    Warning  = "Yellow"
    Error    = "Red"
    Muted    = "DarkGray"
    Existing = "DarkYellow"
    Prompt   = "Magenta"
}

$Icon = @{
    Ok    = "✔"
    Fail  = "✖"
    Skip  = "•"
    Warn  = "!"
    Arrow = "➜"
}

$Glyph = @{
    TL = "╔"; TR = "╗"; BL = "╚"; BR = "╝"; H = "═"; V = "║"
    TeeL = "╠"; TeeR = "╣"
}

# ============================================================
#  CONFIGURATION
# ============================================================

$SetupRoot = "$env:SystemDrive\FreshWindowsSetup"
$LogDir    = "$SetupRoot\Logs"
$TempDir   = "$SetupRoot\Temp"
New-Item -ItemType Directory -Force -Path $SetupRoot, $LogDir, $TempDir | Out-Null

$LogFile = "$LogDir\setup-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
try { Start-Transcript -Path $LogFile -Append | Out-Null } catch {}

$ODTUrl = "https://download.microsoft.com/download/2/fe/0642e2-4248-4175-94df-3e2a5bc09119/officedeploymenttool_20326-20112.exe"

$Apps = @(
    [PSCustomObject]@{ Number = 1;  Name = "Telegram";                              ID = "Telegram.TelegramDesktop";  Source = "winget"  }
    [PSCustomObject]@{ Number = 2;  Name = "PowerToys";                             ID = "Microsoft.PowerToys";       Source = "winget"  }
    [PSCustomObject]@{ Number = 3;  Name = "Python 3.14";                           ID = "Python.Python.3.14";        Source = "winget"  }
    [PSCustomObject]@{ Number = 4;  Name = "Visual Studio Code";                    ID = "Microsoft.VisualStudioCode";Source = "winget"  }
    [PSCustomObject]@{ Number = 5;  Name = "Spotify";                               ID = "Spotify.Spotify";           Source = "winget"  }
    [PSCustomObject]@{ Number = 6;  Name = "WhatsApp";                              ID = "WhatsApp";                  Source = "msstore" }
    [PSCustomObject]@{ Number = 7;  Name = "Brave";                                 ID = "Brave.Brave";               Source = "winget"  }
    [PSCustomObject]@{ Number = 8;  Name = "Google Chrome";                         ID = "Google.Chrome";             Source = "winget"  }
    [PSCustomObject]@{ Number = 9;  Name = "Git";                                   ID = "Git.Git";                   Source = "winget"  }
    [PSCustomObject]@{ Number = 10; Name = "Cloudflare WARP";                       ID = "Cloudflare.Warp";           Source = "winget"  }
    [PSCustomObject]@{ Number = 11; Name = "Node.js LTS";                           ID = "OpenJS.NodeJS.LTS";         Source = "winget"  }
    [PSCustomObject]@{ Number = 12; Name = "7-Zip";                                 ID = "7zip.7zip";                 Source = "winget"  }
    [PSCustomObject]@{ Number = 13; Name = "AB Download Manager";                   ID = "amir1376.ABDownloadManager";Source = "winget"  }
    [PSCustomObject]@{ Number = 14; Name = "VLC";                                   ID = "VideoLAN.VLC";              Source = "winget"  }
    [PSCustomObject]@{ Number = 15; Name = "FFmpeg";                                ID = "Gyan.FFmpeg";               Source = "winget"  }
    [PSCustomObject]@{ Number = 16; Name = "GitHub CLI";                            ID = "GitHub.cli";                Source = "winget"  }
    [PSCustomObject]@{ Number = 17; Name = "PowerShell 7";                          ID = "Microsoft.PowerShell";      Source = "winget"  }
    [PSCustomObject]@{ Number = 18; Name = "Microsoft 365 (Word + Excel + PowerPoint)"; ID = "OFFICE";                Source = "microsoft" }
)

$Results = @()

# ============================================================
#  UI PRIMITIVES
# ============================================================

function Write-Box {
    # Draws a centered double-line box around one or two lines of text.
    param([string]$Title, [string]$Subtitle, [string]$Color = $C.Accent)

    $width = 60
    $pad = { param($s) $l = [math]::Max(0, ($width - 2 - $s.Length)); $left = [math]::Floor($l / 2); $right = $l - $left; (" " * $left) + $s + (" " * $right) }

    Write-Host ($Glyph.TL + ($Glyph.H * ($width - 2)) + $Glyph.TR) -ForegroundColor $Color
    Write-Host ($Glyph.V + (& $pad $Title) + $Glyph.V) -ForegroundColor $Color
    if ($Subtitle) {
        Write-Host ($Glyph.V + (& $pad $Subtitle) + $Glyph.V) -ForegroundColor $Color
    }
    Write-Host ($Glyph.BL + ($Glyph.H * ($width - 2)) + $Glyph.BR) -ForegroundColor $Color
}

function Write-Rule {
    param([string]$Color = $C.Muted)
    Write-Host ("─" * 60) -ForegroundColor $Color
}

function Write-Header {
    Clear-Host
    Write-Host ""
    Write-Box -Title "FRESH WINDOWS SETUP" -Subtitle "v2.2 · WinGet + Office Deployment Tool"
    Write-Host ""
}

function Write-Status {
    # One consistent line format for every status message in the script.
    param([string]$Icon, [string]$Text, [string]$Color)
    Write-Host "  $Icon  $Text" -ForegroundColor $Color
}

function Write-ProgressBar {
    param([int]$Current, [int]$Total, [string]$Activity = "")
    if ($Total -le 0) { return }

    $Percent = [math]::Min(100, [math]::Max(0, [math]::Round(($Current / $Total) * 100)))
    $Width   = 40
    $Filled  = [math]::Round(($Percent / 100) * $Width)
    $Bar     = ("█" * $Filled) + ("░" * ($Width - $Filled))

    Write-Host ""
    Write-Host "  [$Bar] " -NoNewline -ForegroundColor $C.Accent
    Write-Host "$Percent%" -NoNewline -ForegroundColor $C.Title
    Write-Host "  ($Current/$Total)" -ForegroundColor $C.Muted
    if ($Activity) {
        Write-Host "  $($Icon.Arrow) $Activity" -ForegroundColor $C.Title
    }
}

function Format-Time {
    param([TimeSpan]$Time)
    if ($Time.TotalHours -ge 1) { return "{0:hh\:mm\:ss}" -f $Time }
    return "{0:mm\:ss}" -f $Time
}

function Show-AppMenu {
    # Two-column layout so the 18-item list doesn't sprawl down the screen.
    param([array]$List)

    $half = [math]::Ceiling($List.Count / 2)
    for ($i = 0; $i -lt $half; $i++) {
        $left  = $List[$i]
        $right = $List[$i + $half]
        $l = "{0,2}. {1}" -f $left.Number, $left.Name
        $line = $l.PadRight(34)
        if ($right) {
            $r = "{0,2}. {1}" -f $right.Number, $right.Name
            $line += $r
        }
        Write-Host "  $line"
    }
}

# ============================================================
#  SYSTEM CHECKS
# ============================================================

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-Winget {
    $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
}

function Initialize-Winget {
    Write-Status -Icon "…" -Text "Updating WinGet sources" -Color $C.Warning
    winget source update --disable-interactivity 2>&1 | Out-File "$LogDir\winget-source-update.log" -Append
    Write-Status -Icon $Icon.Ok -Text "WinGet sources updated" -Color $C.Success
}

function Test-AppInstalled {
    param([string]$ID, [string]$Source)
    try {
        $Output = @(winget list --id $ID --source $Source --exact --accept-source-agreements --disable-interactivity 2>$null)
        return ($LASTEXITCODE -eq 0) -and ($Output -match [regex]::Escape($ID))
    } catch { return $false }
}

# ============================================================
#  INSTALL / REMOVE — SINGLE APP
# ============================================================

function Install-App {
    param([PSCustomObject]$App, [int]$Current, [int]$Total, [datetime]$StartTime)

    Write-ProgressBar -Current $Current -Total $Total -Activity $App.Name
    Write-Host "  Elapsed: $(Format-Time ((Get-Date) - $StartTime))" -ForegroundColor $C.Muted
    Write-Host ""

    if (Test-AppInstalled -ID $App.ID -Source $App.Source) {
        Write-Status -Icon $Icon.Skip -Text "$($App.Name) — already installed" -Color $C.Existing
        return [PSCustomObject]@{ Name = $App.Name; Status = "Already Installed" }
    }

    Write-Status -Icon $Icon.Arrow -Text "Installing $($App.Name)…" -Color $C.Accent

    $SafeName   = $App.Name -replace '[^a-zA-Z0-9]', '_'
    $OutputFile = "$LogDir\$($App.Number)-$SafeName.log"
    $Arguments  = @(
        "install", "--id", $App.ID, "--exact", "--source", $App.Source,
        "--silent", "--accept-package-agreements", "--accept-source-agreements", "--disable-interactivity"
    )

    try {
        & winget @Arguments 2>&1 | Tee-Object -FilePath $OutputFile | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Status -Icon $Icon.Ok -Text "$($App.Name) installed" -Color $C.Success
            return [PSCustomObject]@{ Name = $App.Name; Status = "Installed" }
        }
        Write-Status -Icon $Icon.Fail -Text "$($App.Name) failed (exit $LASTEXITCODE)" -Color $C.Error
        return [PSCustomObject]@{ Name = $App.Name; Status = "Failed" }
    } catch {
        Write-Status -Icon $Icon.Fail -Text "$($App.Name) failed — $($_.Exception.Message)" -Color $C.Error
        return [PSCustomObject]@{ Name = $App.Name; Status = "Failed" }
    }
}

function Remove-App {
    param([PSCustomObject]$App)

    Write-Status -Icon $Icon.Arrow -Text "Removing $($App.Name)…" -Color $C.Warning

    if ($App.ID -eq "OFFICE") { Remove-Office; return }

    try {
        winget uninstall --id $App.ID --exact --source $App.Source --silent --accept-source-agreements --disable-interactivity | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Status -Icon $Icon.Ok -Text "Removed $($App.Name)" -Color $C.Success
        } else {
            Write-Status -Icon $Icon.Fail -Text "Failed to remove $($App.Name)" -Color $C.Error
        }
    } catch {
        Write-Status -Icon $Icon.Fail -Text "Failed to remove $($App.Name)" -Color $C.Error
    }
}

# ============================================================
#  MICROSOFT 365 (Office Deployment Tool)
# ============================================================

function Get-OfficeConfig {
@"
<Configuration>
    <Add OfficeClientEdition="64" Channel="Current">
        <Product ID="O365ProPlusRetail">
            <Language ID="en-us" />
            <ExcludeApp ID="Access" />
            <ExcludeApp ID="Groove" />
            <ExcludeApp ID="Lync" />
            <ExcludeApp ID="OneNote" />
            <ExcludeApp ID="Outlook" />
            <ExcludeApp ID="OutlookForWindows" />
            <ExcludeApp ID="Publisher" />
            <ExcludeApp ID="Teams" />
            <ExcludeApp ID="OneDrive" />
        </Product>
    </Add>
    <Updates Enabled="TRUE" />
    <Display Level="None" AcceptEULA="TRUE" />
</Configuration>
"@
}

function Get-OfficeRemoveConfig {
@"
<Configuration>
    <Remove All="TRUE" />
    <Display Level="None" AcceptEULA="TRUE" />
</Configuration>
"@
}

function Expand-ODT {
    # Downloads + extracts the Office Deployment Tool into $Dest, returns setup.exe path (or $null).
    param([string]$Dest)

    New-Item -ItemType Directory -Force -Path $Dest | Out-Null
    $ODTInstaller = "$Dest\ODT.exe"

    Write-Status -Icon $Icon.Arrow -Text "Downloading Office Deployment Tool…" -Color $C.Warning
    try {
        Invoke-WebRequest -Uri $ODTUrl -OutFile $ODTInstaller -UseBasicParsing
    } catch {
        Write-Status -Icon $Icon.Fail -Text "Failed to download ODT" -Color $C.Error
        return $null
    }

    $ExtractDir = "$Dest\ODT"
    New-Item -ItemType Directory -Force -Path $ExtractDir | Out-Null
    $Process = Start-Process -FilePath $ODTInstaller -ArgumentList "/quiet /extract:$ExtractDir" -Wait -PassThru
    if ($Process.ExitCode -ne 0) {
        Write-Status -Icon $Icon.Fail -Text "ODT extraction failed" -Color $C.Error
        return $null
    }

    $SetupExe = "$ExtractDir\setup.exe"
    if (-not (Test-Path $SetupExe)) {
        Write-Status -Icon $Icon.Fail -Text "setup.exe not found after extraction" -Color $C.Error
        return $null
    }
    return $SetupExe
}

function Install-Office {
    Write-Host ""
    Write-Box -Title "Microsoft 365" -Subtitle "Word · Excel · PowerPoint" -Color $C.Accent
    Write-Host ""

    $OfficeDir = "$TempDir\Office"
    if (Test-Path $OfficeDir) { Remove-Item $OfficeDir -Recurse -Force -ErrorAction SilentlyContinue }

    $SetupExe = Expand-ODT -Dest $OfficeDir
    if (-not $SetupExe) { return [PSCustomObject]@{ Name = "Microsoft 365"; Status = "Failed" } }

    $ConfigFile = "$OfficeDir\configuration.xml"
    Get-OfficeConfig | Out-File -FilePath $ConfigFile -Encoding UTF8

    Write-Status -Icon $Icon.Arrow -Text "Installing Word, Excel and PowerPoint (this can take a while)…" -Color $C.Accent

    $OfficeProcess = Start-Process -FilePath $SetupExe -ArgumentList "/configure `"$ConfigFile`"" -Wait -PassThru
    if ($OfficeProcess.ExitCode -eq 0) {
        Write-Status -Icon $Icon.Ok -Text "Microsoft 365 installed" -Color $C.Success
        return [PSCustomObject]@{ Name = "Microsoft 365"; Status = "Installed" }
    }
    Write-Status -Icon $Icon.Fail -Text "Microsoft 365 install failed (exit $($OfficeProcess.ExitCode))" -Color $C.Error
    return [PSCustomObject]@{ Name = "Microsoft 365"; Status = "Failed" }
}

function Remove-Office {
    Write-Status -Icon $Icon.Arrow -Text "Removing Microsoft 365…" -Color $C.Warning

    $OfficeDir = "$TempDir\OfficeRemove"
    try {
        $SetupExe = Expand-ODT -Dest $OfficeDir
        if (-not $SetupExe) { throw "Could not prepare the Office Deployment Tool." }

        $ConfigFile = "$OfficeDir\remove.xml"
        Get-OfficeRemoveConfig | Out-File -FilePath $ConfigFile -Encoding UTF8

        $RemoveProcess = Start-Process -FilePath $SetupExe -ArgumentList "/configure `"$ConfigFile`"" -Wait -PassThru
        if ($RemoveProcess.ExitCode -eq 0) {
            Write-Status -Icon $Icon.Ok -Text "Microsoft 365 removed" -Color $C.Success
        } else {
            Write-Status -Icon $Icon.Fail -Text "Office removal returned exit $($RemoveProcess.ExitCode)" -Color $C.Error
        }
    } catch {
        Write-Status -Icon $Icon.Fail -Text "Office removal failed — $($_.Exception.Message)" -Color $C.Error
    }
}

# ============================================================
#  DEVELOPMENT ENVIRONMENT
# ============================================================

function Configure-Development {
    Write-Host ""
    Write-Box -Title "Development Environment" -Color $C.Accent
    Write-Host ""

    if (Get-Command python -ErrorAction SilentlyContinue) {
        Write-Status -Icon $Icon.Arrow -Text "Updating pip / setuptools / wheel…" -Color $C.Warning
        python -m pip install --upgrade pip setuptools wheel --disable-pip-version-check

        $Packages = @(
            "requests", "httpx", "flask", "fastapi", "uvicorn", "pandas", "numpy",
            "matplotlib", "openpyxl", "pillow", "rich", "python-dotenv", "beautifulsoup4", "lxml", "psutil"
        )
        Write-Status -Icon $Icon.Arrow -Text "Installing common Python packages…" -Color $C.Warning
        python -m pip install $Packages --disable-pip-version-check
    }

    if (Get-Command node -ErrorAction SilentlyContinue) {
        Write-Status -Icon $Icon.Arrow -Text "Installing pnpm and yarn…" -Color $C.Warning
        npm install -g pnpm yarn
    }

    if (Get-Command git -ErrorAction SilentlyContinue) {
        Write-Status -Icon $Icon.Arrow -Text "Configuring Git…" -Color $C.Accent

        $GitName = git config --global user.name
        if (-not $GitName) {
            $GitName = Read-Host "  Git user.name"
            if ($GitName) { git config --global user.name "$GitName" }
        }

        $GitEmail = git config --global user.email
        if (-not $GitEmail) {
            $GitEmail = Read-Host "  Git user.email"
            if ($GitEmail) { git config --global user.email "$GitEmail" }
        }

        git config --global init.defaultBranch main
        git config --global core.autocrlf true
        Write-Status -Icon $Icon.Ok -Text "Git configured" -Color $C.Success
    }

    try {
        New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" `
            -Name "LongPathsEnabled" -Value 1 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
    } catch {}

    [Environment]::SetEnvironmentVariable("PYTHONUTF8", "1", "User")

    Write-Status -Icon $Icon.Ok -Text "Development environment ready" -Color $C.Success
}

# ============================================================
#  ORCHESTRATION
# ============================================================

function Start-Installation {
    param([array]$SelectedApps)

    if ($SelectedApps.Count -eq 0) {
        Write-Status -Icon $Icon.Warn -Text "No applications selected" -Color $C.Warning
        return
    }

    $StartTime = Get-Date
    $Total     = $SelectedApps.Count
    $Current   = 0
    $script:Results = @()

    foreach ($App in $SelectedApps) {
        $Current++

        if ($App.ID -eq "OFFICE") {
            Write-ProgressBar -Current $Current -Total $Total -Activity $App.Name
            $Result = Install-Office
        } else {
            $Result = Install-App -App $App -Current $Current -Total $Total -StartTime $StartTime
        }
        $script:Results += $Result

        $Elapsed = (Get-Date) - $StartTime
        if ($Current -gt 0) {
            $AverageSeconds = $Elapsed.TotalSeconds / $Current
            $ETA = [TimeSpan]::FromSeconds($AverageSeconds * ($Total - $Current))
            Write-Host "  Elapsed $(Format-Time $Elapsed)   ETA $(Format-Time $ETA)" -ForegroundColor $C.Muted
        }
        Write-Rule
    }

    Configure-Development
    Show-Summary -StartTime $StartTime -Total $Total
}

function Show-Summary {
    param([datetime]$StartTime, [int]$Total)

    $Elapsed          = (Get-Date) - $StartTime
    $Installed        = @($Results | Where-Object Status -eq "Installed").Count
    $AlreadyInstalled = @($Results | Where-Object Status -eq "Already Installed").Count
    $Failed           = @($Results | Where-Object Status -eq "Failed").Count
    $Skipped          = @($Results | Where-Object Status -eq "Skipped").Count

    Write-Host ""
    Write-Box -Title "INSTALLATION COMPLETE" -Subtitle "Total time $(Format-Time $Elapsed)"
    Write-Host ""

    Write-Host ("  {0,-20}{1}" -f "Total selected", $Total)
    Write-Host ("  {0,-20}{1}" -f "Installed", $Installed)         -ForegroundColor $C.Success
    Write-Host ("  {0,-20}{1}" -f "Already installed", $AlreadyInstalled) -ForegroundColor $C.Existing
    Write-Host ("  {0,-20}{1}" -f "Failed", $Failed)               -ForegroundColor $C.Error
    Write-Host ("  {0,-20}{1}" -f "Skipped", $Skipped)

    Write-Host ""
    Write-Rule
    Write-Host "  Application Status" -ForegroundColor $C.Title
    Write-Rule

    foreach ($Result in $Results) {
        switch ($Result.Status) {
            "Installed"          { Write-Status -Icon $Icon.Ok   -Text $Result.Name -Color $C.Success }
            "Already Installed"  { Write-Status -Icon $Icon.Skip -Text "$($Result.Name)  (already installed)" -Color $C.Existing }
            "Failed"              { Write-Status -Icon $Icon.Fail -Text $Result.Name -Color $C.Error }
            default                { Write-Status -Icon "?" -Text $Result.Name -Color $C.Muted }
        }
    }

    if ($Failed -gt 0) {
        Write-Host ""
        Write-Status -Icon $Icon.Warn -Text "Failed applications — check the logs below" -Color $C.Error
        $Results | Where-Object Status -eq "Failed" | ForEach-Object {
            Write-Host "     - $($_.Name)" -ForegroundColor $C.Error
        }
        Write-Host "  Logs: $LogDir" -ForegroundColor $C.Muted
    }

    Write-Host ""
    Write-Host "  Transcript: $LogFile" -ForegroundColor $C.Muted
    Write-Rule
}

function Retry-Failed {
    $FailedResults = @($Results | Where-Object Status -eq "Failed")

    if ($FailedResults.Count -eq 0) {
        Write-Status -Icon $Icon.Ok -Text "No failed applications to retry" -Color $C.Success
        return
    }

    $RetryApps = @($FailedResults | ForEach-Object { $Apps | Where-Object Name -eq $_.Name } | Where-Object { $_ })
    if ($RetryApps.Count -gt 0) {
        Start-Installation -SelectedApps $RetryApps
    }
}

# ============================================================
#  MENUS
# ============================================================

function Read-AppSelection {
    # Parses a comma-separated number list into matching $Apps entries.
    param([string]$Choice)

    $Numbers = $Choice -split "," | ForEach-Object { $_.Trim() } |
        Where-Object { $_ -match "^\d+$" } | ForEach-Object { [int]$_ } | Sort-Object -Unique

    return @($Apps | Where-Object { $Numbers -contains $_.Number })
}

function Full-Installation {
    Write-Header
    Write-Host "  FULL INSTALLATION" -ForegroundColor $C.Accent
    Write-Host ""
    Write-Host "  The following will be installed:" -ForegroundColor $C.Title
    Write-Host ""
    Show-AppMenu -List $Apps
    Write-Host ""

    $Confirm = Read-Host "Start full installation? [Y/N]"
    if ($Confirm -notmatch "^[Yy]$") { return }

    Start-Installation -SelectedApps $Apps
    Write-Host ""
    Read-Host "Press Enter to return to the main menu"
}

function Manual-Installation {
    while ($true) {
        Write-Header
        Write-Host "  MANUAL INSTALLATION" -ForegroundColor $C.Accent
        Write-Host ""
        Show-AppMenu -List $Apps
        Write-Host ""
        Write-Host "   A. Install ALL" -ForegroundColor $C.Success
        Write-Host "   B. Back" -ForegroundColor $C.Muted
        Write-Host ""

        $Choice = Read-Host "Enter app numbers (example: 1,4,7,18)"
        if ($Choice -match "^[Bb]$") { return }

        if ($Choice -match "^[Aa]$") {
            Start-Installation -SelectedApps $Apps
            Read-Host "`nPress Enter to continue"
            continue
        }

        $SelectedApps = Read-AppSelection -Choice $Choice
        if ($SelectedApps.Count -eq 0) {
            Write-Status -Icon $Icon.Warn -Text "Invalid selection" -Color $C.Error
            Start-Sleep -Seconds 2
            continue
        }

        Write-Host ""
        Write-Host "  Selected:" -ForegroundColor $C.Accent
        $SelectedApps | ForEach-Object { Write-Host "    - $($_.Name)" }
        Write-Host ""

        if ((Read-Host "Continue? [Y/N]") -match "^[Yy]$") {
            Start-Installation -SelectedApps $SelectedApps
            Write-Host ""
            Read-Host "Press Enter to return to menu"
        }
    }
}

function Remove-Applications {
    while ($true) {
        Write-Header
        Write-Host "  REMOVE APPLICATIONS" -ForegroundColor $C.Error
        Write-Host ""
        Show-AppMenu -List $Apps
        Write-Host ""
        Write-Host "   A. Remove ALL" -ForegroundColor $C.Error
        Write-Host "   B. Back" -ForegroundColor $C.Muted
        Write-Host ""

        $Choice = Read-Host "Enter app numbers (example: 1,4,18)"
        if ($Choice -match "^[Bb]$") { return }

        if ($Choice -match "^[Aa]$") {
            Write-Host ""
            Write-Status -Icon $Icon.Warn -Text "This will attempt to remove ALL applications in this list" -Color $C.Error
            Write-Host ""
            if ((Read-Host "Type REMOVE to continue") -eq "REMOVE") {
                $Apps | ForEach-Object { Remove-App -App $_ }
                Write-Host ""
                Read-Host "Press Enter to continue"
            }
            continue
        }

        $SelectedApps = Read-AppSelection -Choice $Choice
        if ($SelectedApps.Count -eq 0) {
            Write-Status -Icon $Icon.Warn -Text "Invalid selection" -Color $C.Error
            Start-Sleep -Seconds 2
            continue
        }

        Write-Host ""
        Write-Host "  Selected for removal:" -ForegroundColor $C.Warning
        $SelectedApps | ForEach-Object { Write-Host "    - $($_.Name)" }
        Write-Host ""

        if ((Read-Host "Type REMOVE to confirm") -eq "REMOVE") {
            $SelectedApps | ForEach-Object { Remove-App -App $_ }
            Write-Host ""
            Read-Host "Press Enter to continue"
        }
    }
}

# ============================================================
#  STARTUP CHECKS
# ============================================================

if (-not (Test-Admin)) {
    Write-Host ""
    Write-Status -Icon $Icon.Fail -Text "This script must be run as Administrator" -Color $C.Error
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

if (-not (Test-Winget)) {
    Write-Host ""
    Write-Status -Icon $Icon.Fail -Text "WinGet was not found" -Color $C.Error
    Write-Host "  Install/update 'App Installer' from the Microsoft Store and try again." -ForegroundColor $C.Muted
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

Initialize-Winget

# ============================================================
#  MAIN MENU
# ============================================================

while ($true) {
    Write-Header
    Write-Host "   1  Full Installation"          -ForegroundColor $C.Success
    Write-Host "   2  Manual Installation"        -ForegroundColor $C.Accent
    Write-Host "   3  Remove Applications"        -ForegroundColor $C.Error
    Write-Host "   4  Retry Failed Installations" -ForegroundColor $C.Warning
    Write-Host "   5  Exit"                       -ForegroundColor $C.Muted
    Write-Host ""

    switch (Read-Host "Select an option") {
        "1" { Full-Installation }
        "2" { Manual-Installation }
        "3" { Remove-Applications }
        "4" { Retry-Failed; Read-Host "`nPress Enter to continue" }
        "5" {
            try { Stop-Transcript | Out-Null } catch {}
            Write-Host ""
            Write-Status -Icon $Icon.Ok -Text "Setup finished. Goodbye!" -Color $C.Success
            exit
        }
        default {
            Write-Status -Icon $Icon.Warn -Text "Invalid option" -Color $C.Error
            Start-Sleep -Seconds 1
        }
    }
}
