# ============================================================
# Fresh Windows Setup
# Version: 2.1
# ============================================================

$ErrorActionPreference = "Continue"

# ------------------------------------------------------------
# CONFIGURATION
# ------------------------------------------------------------

$SetupRoot = "$env:SystemDrive\FreshWindowsSetup"
$LogDir    = "$SetupRoot\Logs"
$TempDir   = "$SetupRoot\Temp"

New-Item -ItemType Directory -Force -Path $SetupRoot, $LogDir, $TempDir | Out-Null

$LogFile = "$LogDir\setup-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"

try {
    Start-Transcript -Path $LogFile -Append | Out-Null
} catch {}

# Current Microsoft Office Deployment Tool
$ODTUrl = "https://download.microsoft.com/download/2/fe/0642e2-4248-4175-94df-3e2a5bc09119/officedeploymenttool_20326-20112.exe"

# ------------------------------------------------------------
# APPLICATION LIST
# ------------------------------------------------------------

$Apps = @(
    [PSCustomObject]@{
        Number = 1
        Name   = "Telegram"
        ID     = "Telegram.TelegramDesktop"
        Source = "winget"
    },
    [PSCustomObject]@{
        Number = 2
        Name   = "PowerToys"
        ID     = "Microsoft.PowerToys"
        Source = "winget"
    },
    [PSCustomObject]@{
        Number = 3
        Name   = "Python 3.13"
        ID     = "Python.Python.3.13"
        Source = "winget"
    },
    [PSCustomObject]@{
        Number = 4
        Name   = "Visual Studio Code"
        ID     = "Microsoft.VisualStudioCode"
        Source = "winget"
    },
    [PSCustomObject]@{
        Number = 5
        Name   = "Spotify"
        ID     = "Spotify.Spotify"
        Source = "winget"
    },
    [PSCustomObject]@{
        Number = 6
        Name   = "WhatsApp"
        ID     = "WhatsApp"
        Source = "msstore"
    },
    [PSCustomObject]@{
        Number = 7
        Name   = "Brave"
        ID     = "Brave.Brave"
        Source = "winget"
    },
    [PSCustomObject]@{
        Number = 8
        Name   = "Google Chrome"
        ID     = "Google.Chrome"
        Source = "winget"
    },
    [PSCustomObject]@{
        Number = 9
        Name   = "Git"
        ID     = "Git.Git"
        Source = "winget"
    },
    [PSCustomObject]@{
        Number = 10
        Name   = "Cloudflare WARP"
        ID     = "Cloudflare.Warp"
        Source = "winget"
    },
    [PSCustomObject]@{
        Number = 11
        Name   = "Node.js LTS"
        ID     = "OpenJS.NodeJS.LTS"
        Source = "winget"
    },
    [PSCustomObject]@{
        Number = 12
        Name   = "7-Zip"
        ID     = "7zip.7zip"
        Source = "winget"
    },
    [PSCustomObject]@{
        Number = 13
        Name   = "AB Download Manager"
        ID     = "amir1376.ABDownloadManager"
        Source = "winget"
    },
    [PSCustomObject]@{
        Number = 14
        Name   = "VLC"
        ID     = "VideoLAN.VLC"
        Source = "winget"
    },
    [PSCustomObject]@{
        Number = 15
        Name   = "FFmpeg"
        ID     = "Gyan.FFmpeg"
        Source = "winget"
    },
    [PSCustomObject]@{
        Number = 16
        Name   = "GitHub CLI"
        ID     = "GitHub.cli"
        Source = "winget"
    },
    [PSCustomObject]@{
        Number = 17
        Name   = "PowerShell 7"
        ID     = "Microsoft.PowerShell"
        Source = "winget"
    },
    [PSCustomObject]@{
        Number = 18
        Name   = "Microsoft 365 (Word + Excel + PowerPoint)"
        ID     = "OFFICE"
        Source = "microsoft"
    }
)

# ------------------------------------------------------------
# STATE
# ------------------------------------------------------------

$Results = @()

# ------------------------------------------------------------
# UI
# ------------------------------------------------------------

function Write-Header {

    Clear-Host

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "                 FRESH WINDOWS SETUP" -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-ProgressBar {

    param(
        [int]$Current,
        [int]$Total,
        [string]$Activity = ""
    )

    if ($Total -le 0) {
        return
    }

    $Percent = [math]::Min(
        100,
        [math]::Max(
            0,
            [math]::Round(($Current / $Total) * 100)
        )
    )

    $Width = 42

    $Filled = [math]::Round(($Percent / 100) * $Width)
    $Empty  = $Width - $Filled

    $Bar = ("█" * $Filled) + ("░" * $Empty)

    Write-Host ""
    Write-Host "[$Bar] $Percent%  $Current / $Total" -ForegroundColor Cyan

    if ($Activity) {
        Write-Host "Current : $Activity" -ForegroundColor White
    }
}

function Format-Time {

    param(
        [TimeSpan]$Time
    )

    if ($Time.TotalHours -ge 1) {
        return "{0:hh\:mm\:ss}" -f $Time
    }

    return "{0:mm\:ss}" -f $Time
}

# ------------------------------------------------------------
# SYSTEM CHECKS
# ------------------------------------------------------------

function Test-Admin {

    $CurrentUser = [Security.Principal.WindowsIdentity]::GetCurrent()

    $Principal = New-Object Security.Principal.WindowsPrincipal($CurrentUser)

    return $Principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

function Test-Winget {

    return $null -ne (
        Get-Command winget -ErrorAction SilentlyContinue
    )
}

function Initialize-Winget {

    Write-Host ""
    Write-Host "Updating WinGet sources..." -ForegroundColor Yellow

    winget source update `
        --disable-interactivity 2>&1 |
        Out-File "$LogDir\winget-source-update.log" -Append

    Write-Host "WinGet sources updated." -ForegroundColor Green
}

# ------------------------------------------------------------
# CHECK IF APP IS INSTALLED
# ------------------------------------------------------------

function Test-AppInstalled {

    param(
        [string]$ID,
        [string]$Source
    )

    try {

        $Output = @(
            winget list `
                --id $ID `
                --source $Source `
                --exact `
                --accept-source-agreements `
                --disable-interactivity 2>$null
        )

        if ($LASTEXITCODE -eq 0) {

            if ($Output -match [regex]::Escape($ID)) {
                return $true
            }
        }

        return $false
    }
    catch {

        return $false
    }
}

# ------------------------------------------------------------
# INSTALL NORMAL APP
# ------------------------------------------------------------

function Install-App {

    param(
        [PSCustomObject]$App,
        [int]$Current,
        [int]$Total,
        [datetime]$StartTime
    )

    Write-ProgressBar `
        -Current $Current `
        -Total $Total `
        -Activity $App.Name

    Write-Host ""

    $Elapsed = (Get-Date) - $StartTime

    Write-Host "Elapsed : $(Format-Time $Elapsed)" `
        -ForegroundColor DarkGray

    Write-Host ""
    Write-Host "Checking $($App.Name)..." `
        -ForegroundColor Yellow

    if (Test-AppInstalled `
        -ID $App.ID `
        -Source $App.Source) {

        Write-Host "Already installed." `
            -ForegroundColor DarkYellow

        return [PSCustomObject]@{
            Name   = $App.Name
            Status = "Already Installed"
        }
    }

    Write-Host ""
    Write-Host "Installing $($App.Name)..." `
        -ForegroundColor Cyan

    $SafeName =
        $App.Name -replace '[^a-zA-Z0-9]', '_'

    $OutputFile =
        "$LogDir\$($App.Number)-$SafeName.log"

    $Arguments = @(
        "install"
        "--id", $App.ID
        "--exact"
        "--source", $App.Source
        "--silent"
        "--accept-package-agreements"
        "--accept-source-agreements"
        "--disable-interactivity"
    )

    try {

        & winget @Arguments 2>&1 |
            Tee-Object -FilePath $OutputFile

        $ExitCode = $LASTEXITCODE

        if ($ExitCode -eq 0) {

            Write-Host ""
            Write-Host "SUCCESS: $($App.Name)" `
                -ForegroundColor Green

            return [PSCustomObject]@{
                Name   = $App.Name
                Status = "Installed"
            }
        }

        Write-Host ""
        Write-Host "FAILED: $($App.Name)  ExitCode=$ExitCode" `
            -ForegroundColor Red

        return [PSCustomObject]@{
            Name   = $App.Name
            Status = "Failed"
        }
    }
    catch {

        Write-Host ""
        Write-Host "FAILED: $($App.Name)" `
            -ForegroundColor Red

        Write-Host $_.Exception.Message `
            -ForegroundColor Red

        return [PSCustomObject]@{
            Name   = $App.Name
            Status = "Failed"
        }
    }
}

# ------------------------------------------------------------
# MICROSOFT 365 CONFIGURATION
# ------------------------------------------------------------

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

    <Display
        Level="None"
        AcceptEULA="TRUE"
    />

</Configuration>
"@
}

# ------------------------------------------------------------
# INSTALL MICROSOFT 365
# ------------------------------------------------------------

function Install-Office {

    Write-Host ""
    Write-Host "============================================================" `
        -ForegroundColor Cyan

    Write-Host " Microsoft 365" `
        -ForegroundColor White

    Write-Host " Word + Excel + PowerPoint" `
        -ForegroundColor Gray

    Write-Host "============================================================" `
        -ForegroundColor Cyan

    Write-Host ""

    $OfficeDir = "$TempDir\Office"

    if (Test-Path $OfficeDir) {

        Remove-Item `
            $OfficeDir `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }

    New-Item `
        -ItemType Directory `
        -Force `
        -Path $OfficeDir |
        Out-Null

    $ODTInstaller = "$OfficeDir\ODT.exe"

    Write-Host "Downloading Microsoft Office Deployment Tool..." `
        -ForegroundColor Yellow

    try {

        Invoke-WebRequest `
            -Uri $ODTUrl `
            -OutFile $ODTInstaller `
            -UseBasicParsing

        Write-Host "ODT downloaded." `
            -ForegroundColor Green
    }
    catch {

        Write-Host "Failed to download ODT." `
            -ForegroundColor Red

        return [PSCustomObject]@{
            Name   = "Microsoft 365"
            Status = "Failed"
        }
    }

    Write-Host ""
    Write-Host "Extracting ODT..." `
        -ForegroundColor Yellow

    $ExtractDir = "$OfficeDir\ODT"

    New-Item `
        -ItemType Directory `
        -Force `
        -Path $ExtractDir |
        Out-Null

    $Process = Start-Process `
        -FilePath $ODTInstaller `
        -ArgumentList "/quiet /extract:$ExtractDir" `
        -Wait `
        -PassThru

    if ($Process.ExitCode -ne 0) {

        Write-Host "ODT extraction failed." `
            -ForegroundColor Red

        return [PSCustomObject]@{
            Name   = "Microsoft 365"
            Status = "Failed"
        }
    }

    $SetupExe = "$ExtractDir\setup.exe"

    if (-not (Test-Path $SetupExe)) {

        Write-Host "setup.exe was not found." `
            -ForegroundColor Red

        return [PSCustomObject]@{
            Name   = "Microsoft 365"
            Status = "Failed"
        }
    }

    $ConfigFile = "$OfficeDir\configuration.xml"

    Get-OfficeConfig |
        Out-File `
            -FilePath $ConfigFile `
            -Encoding UTF8

    Write-Host ""
    Write-Host "Installing Word, Excel and PowerPoint..." `
        -ForegroundColor Cyan

    Write-Host "This may take several minutes." `
        -ForegroundColor DarkGray

    Write-Host ""

    $OfficeProcess = Start-Process `
        -FilePath $SetupExe `
        -ArgumentList "/configure `"$ConfigFile`"" `
        -Wait `
        -PassThru

    if ($OfficeProcess.ExitCode -eq 0) {

        Write-Host ""
        Write-Host "SUCCESS: Microsoft 365" `
            -ForegroundColor Green

        return [PSCustomObject]@{
            Name   = "Microsoft 365"
            Status = "Installed"
        }
    }

    Write-Host ""
    Write-Host "Microsoft 365 installation returned ExitCode=$($OfficeProcess.ExitCode)" `
        -ForegroundColor Red

    return [PSCustomObject]@{
        Name   = "Microsoft 365"
        Status = "Failed"
    }
}

# ------------------------------------------------------------
# DEVELOPMENT ENVIRONMENT
# ------------------------------------------------------------

function Configure-Development {

    Write-Host ""
    Write-Host "Configuring development environment..." `
        -ForegroundColor Cyan

    # --------------------------------------------------------
    # Python
    # --------------------------------------------------------

    $Python = Get-Command python -ErrorAction SilentlyContinue

    if ($Python) {

        Write-Host ""
        Write-Host "Updating Python tools..." `
            -ForegroundColor Yellow

        python -m pip install `
            --upgrade `
            pip `
            setuptools `
            wheel `
            --disable-pip-version-check

        $Packages = @(
            "requests"
            "httpx"
            "flask"
            "fastapi"
            "uvicorn"
            "pandas"
            "numpy"
            "matplotlib"
            "openpyxl"
            "pillow"
            "rich"
            "python-dotenv"
            "beautifulsoup4"
            "lxml"
            "psutil"
        )

        Write-Host ""
        Write-Host "Installing Python packages..." `
            -ForegroundColor Yellow

        python -m pip install `
            $Packages `
            --disable-pip-version-check
    }

    # --------------------------------------------------------
    # Node.js
    # --------------------------------------------------------

    $Node = Get-Command node -ErrorAction SilentlyContinue

    if ($Node) {

        Write-Host ""
        Write-Host "Configuring Node.js package managers..." `
            -ForegroundColor Yellow

        npm install -g pnpm yarn
    }

    # --------------------------------------------------------
    # Git
    # --------------------------------------------------------

    $Git = Get-Command git -ErrorAction SilentlyContinue

    if ($Git) {

        Write-Host ""
        Write-Host "Git configuration" `
            -ForegroundColor Cyan

        $GitName = git config --global user.name

        if (-not $GitName) {

            $GitName = Read-Host "Git user.name"

            if ($GitName) {
                git config --global user.name "$GitName"
            }
        }

        $GitEmail = git config --global user.email

        if (-not $GitEmail) {

            $GitEmail = Read-Host "Git user.email"

            if ($GitEmail) {
                git config --global user.email "$GitEmail"
            }
        }

        git config --global init.defaultBranch main
        git config --global core.autocrlf true

        Write-Host "Git configured." `
            -ForegroundColor Green
    }

    # --------------------------------------------------------
    # Windows Long Paths
    # --------------------------------------------------------

    try {

        New-ItemProperty `
            -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" `
            -Name "LongPathsEnabled" `
            -Value 1 `
            -PropertyType DWORD `
            -Force `
            -ErrorAction SilentlyContinue |
            Out-Null
    }
    catch {}

    # --------------------------------------------------------
    # Python UTF-8
    # --------------------------------------------------------

    [Environment]::SetEnvironmentVariable(
        "PYTHONUTF8",
        "1",
        "User"
    )

    Write-Host ""
    Write-Host "Development configuration complete." `
        -ForegroundColor Green
}

# ------------------------------------------------------------
# START INSTALLATION
# ------------------------------------------------------------

function Start-Installation {

    param(
        [array]$SelectedApps
    )

    if ($SelectedApps.Count -eq 0) {

        Write-Host ""
        Write-Host "No applications selected." `
            -ForegroundColor Yellow

        return
    }

    $StartTime = Get-Date

    $Total   = $SelectedApps.Count
    $Current = 0

    $script:Results = @()

    foreach ($App in $SelectedApps) {

        $Current++

        if ($App.ID -eq "OFFICE") {

            Write-ProgressBar `
                -Current $Current `
                -Total $Total `
                -Activity $App.Name

            $Result = Install-Office
        }
        else {

            $Result = Install-App `
                -App $App `
                -Current $Current `
                -Total $Total `
                -StartTime $StartTime
        }

        $script:Results += $Result

        # ----------------------------------------------------
        # ETA
        # ----------------------------------------------------

        $Elapsed = (Get-Date) - $StartTime

        if ($Current -gt 0) {

            $AverageSeconds =
                $Elapsed.TotalSeconds / $Current

            $Remaining =
                $Total - $Current

            $ETASeconds =
                $AverageSeconds * $Remaining

            $ETA =
                [TimeSpan]::FromSeconds($ETASeconds)

            Write-Host ""
            Write-Host "Elapsed: $(Format-Time $Elapsed)    ETA: $(Format-Time $ETA)" `
                -ForegroundColor DarkGray
        }
    }

    # Development tools
    Configure-Development

    Show-Summary `
        -StartTime $StartTime `
        -Total $Total
}

# ------------------------------------------------------------
# SUMMARY
# ------------------------------------------------------------

function Show-Summary {

    param(
        [datetime]$StartTime,
        [int]$Total
    )

    $Elapsed = (Get-Date) - $StartTime

    $Installed =
        @(
            $Results |
            Where-Object Status -eq "Installed"
        ).Count

    $AlreadyInstalled =
        @(
            $Results |
            Where-Object Status -eq "Already Installed"
        ).Count

    $Failed =
        @(
            $Results |
            Where-Object Status -eq "Failed"
        ).Count

    $Skipped =
        @(
            $Results |
            Where-Object Status -eq "Skipped"
        ).Count

    Write-Host ""
    Write-Host ""
    Write-Host "============================================================" `
        -ForegroundColor Cyan

    Write-Host "                 INSTALLATION COMPLETE" `
        -ForegroundColor White

    Write-Host "============================================================" `
        -ForegroundColor Cyan

    Write-Host ""

    Write-Host "Total selected     : $Total"
    Write-Host "Installed          : $Installed" `
        -ForegroundColor Green

    Write-Host "Already installed  : $AlreadyInstalled" `
        -ForegroundColor DarkYellow

    Write-Host "Failed             : $Failed" `
        -ForegroundColor Red

    Write-Host "Skipped            : $Skipped"

    Write-Host ""
    Write-Host "Total time         : $(Format-Time $Elapsed)" `
        -ForegroundColor Cyan

    Write-Host ""
    Write-Host "------------------------------------------------------------"
    Write-Host "Application Status"
    Write-Host "------------------------------------------------------------"

    foreach ($Result in $Results) {

        switch ($Result.Status) {

            "Installed" {

                Write-Host "  [OK]  $($Result.Name)" `
                    -ForegroundColor Green
            }

            "Already Installed" {

                Write-Host "  [--]  $($Result.Name)  (already installed)" `
                    -ForegroundColor DarkYellow
            }

            "Failed" {

                Write-Host "  [!!]  $($Result.Name)" `
                    -ForegroundColor Red
            }

            default {

                Write-Host "  [??]  $($Result.Name)"
            }
        }
    }

    if ($Failed -gt 0) {

        Write-Host ""
        Write-Host "Failed applications:" `
            -ForegroundColor Red

        $Results |
            Where-Object Status -eq "Failed" |
            ForEach-Object {

                Write-Host "  - $($_.Name)" `
                    -ForegroundColor Red
            }

        Write-Host ""
        Write-Host "Check logs:" `
            -ForegroundColor Yellow

        Write-Host "  $LogDir" `
            -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "Log file:"
    Write-Host "  $LogFile" `
        -ForegroundColor Gray

    Write-Host ""
    Write-Host "============================================================"
}

# ------------------------------------------------------------
# RETRY FAILED INSTALLATIONS
# ------------------------------------------------------------

function Retry-Failed {

    $FailedResults =
        @(
            $Results |
            Where-Object Status -eq "Failed"
        )

    if ($FailedResults.Count -eq 0) {

        Write-Host ""
        Write-Host "No failed applications to retry." `
            -ForegroundColor Green

        return
    }

    $RetryApps = @()

    foreach ($Result in $FailedResults) {

        $App =
            $Apps |
            Where-Object Name -eq $Result.Name

        if ($App) {
            $RetryApps += $App
        }
    }

    if ($RetryApps.Count -gt 0) {

        Start-Installation `
            -SelectedApps $RetryApps
    }
}

# ------------------------------------------------------------
# MANUAL INSTALLATION
# ------------------------------------------------------------

function Manual-Installation {

    while ($true) {

        Write-Header

        Write-Host "MANUAL INSTALLATION" `
            -ForegroundColor Cyan

        Write-Host ""

        foreach ($App in $Apps) {

            Write-Host (
                " {0,2}. {1}" -f
                $App.Number,
                $App.Name
            )
        }

        Write-Host ""
        Write-Host " A. Install ALL"
        Write-Host " B. Back"
        Write-Host ""

        $Choice =
            Read-Host "Enter app numbers (example: 1,4,7,18)"

        if ($Choice -match "^[Bb]$") {
            return
        }

        if ($Choice -match "^[Aa]$") {

            Start-Installation `
                -SelectedApps $Apps

            Read-Host "`nPress Enter to continue"

            continue
        }

        $Numbers =
            $Choice -split "," |
            ForEach-Object {
                $_.Trim()
            } |
            Where-Object {
                $_ -match "^\d+$"
            } |
            ForEach-Object {
                [int]$_
            } |
            Sort-Object -Unique

        $SelectedApps =
            @(
                $Apps |
                Where-Object {
                    $Numbers -contains $_.Number
                }
            )

        if ($SelectedApps.Count -eq 0) {

            Write-Host ""
            Write-Host "Invalid selection." `
                -ForegroundColor Red

            Start-Sleep -Seconds 2

            continue
        }

        Write-Host ""
        Write-Host "Selected:" `
            -ForegroundColor Cyan

        foreach ($App in $SelectedApps) {

            Write-Host "  - $($App.Name)"
        }

        Write-Host ""

        $Confirm =
            Read-Host "Continue? [Y/N]"

        if ($Confirm -match "^[Yy]$") {

            Start-Installation `
                -SelectedApps $SelectedApps

            Write-Host ""
            Write-Host "Press Enter to return to menu..."

            Read-Host
        }
    }
}

# ------------------------------------------------------------
# REMOVE OFFICE
# ------------------------------------------------------------

function Remove-Office {

    Write-Host ""
    Write-Host "Removing Microsoft 365..." `
        -ForegroundColor Yellow

    $OfficeDir = "$TempDir\OfficeRemove"

    New-Item `
        -ItemType Directory `
        -Force `
        -Path $OfficeDir |
        Out-Null

    $ODTInstaller = "$OfficeDir\ODT.exe"

    try {

        Invoke-WebRequest `
            -Uri $ODTUrl `
            -OutFile $ODTInstaller `
            -UseBasicParsing

        $ExtractDir = "$OfficeDir\ODT"

        New-Item `
            -ItemType Directory `
            -Force `
            -Path $ExtractDir |
            Out-Null

        $ExtractProcess = Start-Process `
            -FilePath $ODTInstaller `
            -ArgumentList "/quiet /extract:$ExtractDir" `
            -Wait `
            -PassThru

        if ($ExtractProcess.ExitCode -ne 0) {

            throw "ODT extraction failed."
        }

        $SetupExe = "$ExtractDir\setup.exe"

        if (-not (Test-Path $SetupExe)) {

            throw "ODT setup.exe not found."
        }

        $Config = @"
<Configuration>

    <Remove All="TRUE" />

    <Display
        Level="None"
        AcceptEULA="TRUE"
    />

</Configuration>
"@

        $ConfigFile = "$OfficeDir\remove.xml"

        $Config |
            Out-File `
                -FilePath $ConfigFile `
                -Encoding UTF8

        $RemoveProcess = Start-Process `
            -FilePath $SetupExe `
            -ArgumentList "/configure `"$ConfigFile`"" `
            -Wait `
            -PassThru

        if ($RemoveProcess.ExitCode -eq 0) {

            Write-Host "Microsoft 365 removed." `
                -ForegroundColor Green
        }
        else {

            Write-Host "Office removal returned ExitCode=$($RemoveProcess.ExitCode)" `
                -ForegroundColor Red
        }
    }
    catch {

        Write-Host "Office removal failed." `
            -ForegroundColor Red

        Write-Host $_.Exception.Message `
            -ForegroundColor Red
    }
}

# ------------------------------------------------------------
# REMOVE APP
# ------------------------------------------------------------

function Remove-App {

    param(
        [PSCustomObject]$App
    )

    Write-Host ""
    Write-Host "Removing $($App.Name)..." `
        -ForegroundColor Yellow

    try {

        if ($App.ID -eq "OFFICE") {

            Remove-Office

            return
        }

        winget uninstall `
            --id $App.ID `
            --exact `
            --source $App.Source `
            --silent `
            --accept-source-agreements `
            --disable-interactivity

        if ($LASTEXITCODE -eq 0) {

            Write-Host "Removed: $($App.Name)" `
                -ForegroundColor Green
        }
        else {

            Write-Host "Failed to remove: $($App.Name)" `
                -ForegroundColor Red
        }
    }
    catch {

        Write-Host "Failed to remove: $($App.Name)" `
            -ForegroundColor Red
    }
}

# ------------------------------------------------------------
# REMOVE MENU
# ------------------------------------------------------------

function Remove-Applications {

    while ($true) {

        Write-Header

        Write-Host "REMOVE APPLICATIONS" `
            -ForegroundColor Red

        Write-Host ""

        foreach ($App in $Apps) {

            Write-Host (
                " {0,2}. {1}" -f
                $App.Number,
                $App.Name
            )
        }

        Write-Host ""
        Write-Host " A. Remove ALL"
        Write-Host " B. Back"
        Write-Host ""

        $Choice =
            Read-Host "Enter app numbers (example: 1,4,18)"

        if ($Choice -match "^[Bb]$") {
            return
        }

        if ($Choice -match "^[Aa]$") {

            Write-Host ""
            Write-Host "WARNING: This will attempt to remove ALL applications in this list." `
                -ForegroundColor Red

            Write-Host ""

            $Confirm =
                Read-Host "Type REMOVE to continue"

            if ($Confirm -eq "REMOVE") {

                foreach ($App in $Apps) {

                    Remove-App -App $App
                }

                Write-Host ""
                Read-Host "Press Enter to continue"
            }

            continue
        }

        $Numbers =
            $Choice -split "," |
            ForEach-Object {
                $_.Trim()
            } |
            Where-Object {
                $_ -match "^\d+$"
            } |
            ForEach-Object {
                [int]$_
            } |
            Sort-Object -Unique

        $SelectedApps =
            @(
                $Apps |
                Where-Object {
                    $Numbers -contains $_.Number
                }
            )

        if ($SelectedApps.Count -eq 0) {

            Write-Host ""
            Write-Host "Invalid selection." `
                -ForegroundColor Red

            Start-Sleep -Seconds 2

            continue
        }

        Write-Host ""
        Write-Host "Selected for removal:" `
            -ForegroundColor Yellow

        foreach ($App in $SelectedApps) {

            Write-Host "  - $($App.Name)"
        }

        Write-Host ""

        $Confirm =
            Read-Host "Type REMOVE to confirm"

        if ($Confirm -eq "REMOVE") {

            foreach ($App in $SelectedApps) {

                Remove-App -App $App
            }

            Write-Host ""

            Read-Host "Press Enter to continue"
        }
    }
}

# ------------------------------------------------------------
# FULL INSTALLATION
# ------------------------------------------------------------

function Full-Installation {

    Write-Header

    Write-Host "FULL INSTALLATION" `
        -ForegroundColor Cyan

    Write-Host ""

    Write-Host "The following will be installed:" `
        -ForegroundColor White

    Write-Host ""

    foreach ($App in $Apps) {

        Write-Host (
            "  {0}. {1}" -f
            $App.Number,
            $App.Name
        )
    }

    Write-Host ""

    $Confirm =
        Read-Host "Start full installation? [Y/N]"

    if ($Confirm -notmatch "^[Yy]$") {
        return
    }

    Start-Installation `
        -SelectedApps $Apps

    Write-Host ""
    Write-Host "Press Enter to return to the main menu..."

    Read-Host
}

# ------------------------------------------------------------
# STARTUP CHECKS
# ------------------------------------------------------------

if (-not (Test-Admin)) {

    Write-Host ""
    Write-Host "This script must be run as Administrator." `
        -ForegroundColor Red

    Write-Host ""

    Write-Host "Please run the script as Administrator." `
        -ForegroundColor Yellow

    Write-Host ""

    Read-Host "Press Enter to exit"

    exit 1
}

if (-not (Test-Winget)) {

    Write-Host ""
    Write-Host "WinGet was not found." `
        -ForegroundColor Red

    Write-Host ""

    Write-Host "Install/update App Installer from Microsoft Store and try again."

    Write-Host ""

    Read-Host "Press Enter to exit"

    exit 1
}

Initialize-Winget

# ------------------------------------------------------------
# MAIN MENU
# ------------------------------------------------------------

while ($true) {

    Write-Header

    Write-Host "  1. Full Installation" `
        -ForegroundColor Green

    Write-Host "  2. Manual Installation" `
        -ForegroundColor Cyan

    Write-Host "  3. Remove Applications" `
        -ForegroundColor Red

    Write-Host "  4. Retry Failed Installations" `
        -ForegroundColor Yellow

    Write-Host "  5. Exit" `
        -ForegroundColor Gray

    Write-Host ""

    $Choice =
        Read-Host "Select an option"

    switch ($Choice) {

        "1" {
            Full-Installation
        }

        "2" {
            Manual-Installation
        }

        "3" {
            Remove-Applications
        }

        "4" {

            Retry-Failed

            Read-Host "`nPress Enter to continue"
        }

        "5" {

            try {
                Stop-Transcript | Out-Null
            }
            catch {}

            Write-Host ""
            Write-Host "Setup finished. Goodbye!" `
                -ForegroundColor Green

            exit
        }

        default {

            Write-Host ""
            Write-Host "Invalid option." `
                -ForegroundColor Red

            Start-Sleep -Seconds 1
        }
    }
}