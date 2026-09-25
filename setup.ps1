#requires -Version 5.1
param(
    [switch]$GuiWorker,
    [string]$WorkerSelection = "",
    [ValidateSet("Install","Remove")][string]$WorkerMode = "Install",
    [string]$WorkerLog = ""
)
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

# Office Deployment Tool (verified 2026-09; Expand-ODT auto-resolves a fresh link if this one goes stale)
$ODTUrl          = "https://download.microsoft.com/download/6c1eeb25-cf8b-41d9-8d0d-cc1dbc032140/officedeploymenttool_20326-20112.exe"
$ODTFallbackPage = "https://www.microsoft.com/en-us/download/details.aspx?id=49117"

# Hermes Agent (https://hermes-agent.nousresearch.com/) — official Windows installer.
# Installs per-user into %LOCALAPPDATA%\hermes (uv, Python 3.11, Node.js, ripgrep,
# ffmpeg are provisioned automatically by the installer itself).
$HermesInstallUrl = "https://hermes-agent.nousresearch.com/install.ps1"

# EvoFox Phantom Air wired gaming mouse configuration software (Amkette).
# Direct link from https://www.amkette.com/pages/evofox-phantom-air-wired-gaming-mouse-help
# (Inno Setup 5.5.9 package; verified 2026-09). Installs to
# "C:\Program Files (x86)\EvoFox Phantom Air Gaming Mouse" (config app:
# Gaming Mouse 3.0.exe).
$EvoFoxUrl      = "https://cdn.shopify.com/s/files/1/0676/1273/7846/files/EvoFox_Phantom_Air_Gaming_Mouse._20250620_1.exe?v=1750394461"
$EvoFoxHelpPage = "https://www.amkette.com/pages/evofox-phantom-air-wired-gaming-mouse-help"

# Chris Titus WinUtil — open-source Windows tweak/debloat utility (interactive GUI).
# The script already runs elevated (Test-Admin gate), so WinUtil launches
# with admin rights automatically.
$WinUtilUrl = "https://christitus.com/win"

# MassGrave (Microsoft Activation Scripts) — open-source activation tool
# (irm https://get.activated.win | iex). Interactive menu opens after launch;
# the user picks an activation option there (green = recommended).
# The script already runs elevated (Test-Admin gate), so MAS launches
# with admin rights automatically — no UAC prompt.
$MassGraveUrl = "https://get.activated.win"

$Apps = @(
    [PSCustomObject]@{ Number = 1;  Name = "Telegram";                              ID = "Telegram.TelegramDesktop";  Source = "winget"  }
    [PSCustomObject]@{ Number = 2;  Name = "PowerToys";                             ID = "Microsoft.PowerToys";       Source = "winget"  }
    [PSCustomObject]@{ Number = 3;  Name = "Python 3.14";                           ID = "Python.Python.3.14";        Source = "winget"  }
    [PSCustomObject]@{ Number = 4;  Name = "Visual Studio Code";                    ID = "Microsoft.VisualStudioCode";Source = "winget"  }
    # Spotify is installed from the Microsoft Store (store product ID, not a winget name).
    [PSCustomObject]@{ Number = 5;  Name = "Spotify";                               ID = "9NCBCSZSJRSB";               Source = "msstore" }
    # msstore packages are identified by their Store ID, not a name.
    [PSCustomObject]@{ Number = 6;  Name = "WhatsApp";                              ID = "9NKSQGP7F2NH";              Source = "msstore" }
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
    # Hermes Agent uses its own installer (iex irm install.ps1), not winget.
    # The sentinel ID "HERMES" is dispatched to Install-Hermes / Remove-Hermes.
    [PSCustomObject]@{ Number = 19; Name = "Hermes Agent (Nous Research CLI)";        ID = "HERMES";                Source = "custom"  }
    # EvoFox Phantom Air mouse software uses its own installer from Amkette's
    # help page. Sentinel ID "EVOFOX" is dispatched to Install-EvoFox / Remove-EvoFox.
    [PSCustomObject]@{ Number = 20; Name = "EvoFox Phantom Air Mouse Software";      ID = "EVOFOX";                Source = "custom"  }
)

$Results = @()

# ============================================================
#  UI PRIMITIVES
# ============================================================

$Banner = @'
███████ █████████ ███████ █████████ ███   ███
▓▓█     ▓▓█   █▓▓ ▓▓█     ▓▓█       ▓▓█▄▄▄█▓▓
▒▓▓▓▒   ▒▒▓▓▒░▓▓  ▒▓▓▓▒   ▒▓▓▓▒░▓▓▒ ▒▒▓▓██▓▓▒
▒▒░     ░░▒   ░░▒ ▒▒░           ░░▒ ░░▒   ░░▒
░░      ░░░    ░░ ░░      ░░ ███░    ░░   ░░

███     ███ ███ ██▄   ███ ████████▄ █████████ ███     ███ █████████
▓▓█ ▄▄▄ █▓▓ ▓▓█ ▓▓██▄ █▓▓ ▓▓█   █▓▓ ▓▓█   █▓▓ ▓▓█ ▄▄▄ █▓▓ ▓▓█
▒▒▓ ▒░▒ ▓▓▒ ▒▒▓ ▒▒▓▀██▓▓▒ ▒▒▓   ▓▓▒ ▒▒▓   ▓▓▒ ▒▒▓ ▒░▒ ▓▓▒ ▒▓▓▓▒░▓▓▒
░░▒ ░█░ ░░▒ ░░▒ ░░▒  ▀░░▒ ░░▒   ░░▒ ░░▒   ░░▒ ░░▒ ░█░ ░░▒       ░░▒
░░  █▀       ░░  ░░   ░   ░░      ▀ ░░        ░░  █▀      ░░ ███░
'@

function Set-TerminalLayout {
    try {
        if ($Host.UI.RawUI.WindowSize.Width -lt 110) {
            $size = $Host.UI.RawUI.WindowSize
            $newWidth = [math]::Min(140, [math]::Max(110, $size.Width))
            $newHeight = [math]::Min(45, [math]::Max(30, $size.Height))
            $Host.UI.RawUI.WindowSize = New-Object System.Management.Automation.Host.Size($newWidth, $newHeight)
        }
        $Host.UI.RawUI.WindowTitle = "Fresh Windows Setup"
    } catch {}
}

function Write-Centered {
    param(
        [string]$Text,
        [string]$Color = $C.Title,
        [switch]$NoNewline
    )

    try {
        $width = $Host.UI.RawUI.WindowSize.Width
        $left = [math]::Max(0, [int](($width - $Text.Length) / 2))
    } catch {
        $left = 0
    }

    $line = (" " * $left) + $Text
    if ($NoNewline) {
        Write-Host $line -NoNewline -ForegroundColor $Color
    } else {
        Write-Host $line -ForegroundColor $Color
    }
}

function Write-Panel {
    param(
        [string]$Title,
        [string]$Subtitle = "",
        [string]$Color = $C.Accent,
        [int]$Width = 76
    )

    $inner = $Width - 2
    $titlePad = [math]::Max(0, $inner - $Title.Length)
    $left = [math]::Floor($titlePad / 2)
    $right = $titlePad - $left

    Write-Host ""
    Write-Host ("╭" + ("─" * $inner) + "╮") -ForegroundColor $Color
    Write-Host ("│" + (" " * $left) + $Title + (" " * $right) + "│") -ForegroundColor $Color

    if ($Subtitle) {
        $subPad = [math]::Max(0, $inner - $Subtitle.Length)
        $sLeft = [math]::Floor($subPad / 2)
        $sRight = $subPad - $sLeft
        Write-Host ("│" + (" " * $sLeft) + $Subtitle + (" " * $sRight) + "│") -ForegroundColor $C.Muted
    }

    Write-Host ("╰" + ("─" * $inner) + "╯") -ForegroundColor $Color
}

function Write-Box {
    param(
        [string]$Title,
        [string]$Subtitle,
        [string]$Color = $C.Accent
    )
    Write-Panel -Title $Title -Subtitle $Subtitle -Color $Color
}

function Write-Rule {
    param([string]$Color = $C.Muted, [int]$Width = 76)
    Write-Host ("─" * $Width) -ForegroundColor $Color
}

function Write-Header {
    Clear-Host
    Set-TerminalLayout

    Write-Host ""
    Write-Centered "FRESH WINDOWS SETUP" $C.Accent
    Write-Centered "Automated Windows workstation bootstrapper" $C.Muted
    Write-Host ""
}

function Write-Status {
    param(
        [string]$Icon,
        [string]$Text,
        [string]$Color
    )
    Write-Host "  " -NoNewline
    Write-Host $Icon -NoNewline -ForegroundColor $Color
    Write-Host "  $Text" -ForegroundColor $Color
}

function Write-ProgressBar {
    param(
        [int]$Current,
        [int]$Total,
        [string]$Activity = ""
    )

    if ($Total -le 0) { return }

    $Percent = [math]::Min(100, [math]::Max(0, [math]::Round(($Current / $Total) * 100)))
    $Width   = 46
    $Filled  = [math]::Round(($Percent / 100) * $Width)
    $Bar     = ("█" * $Filled) + ("░" * ($Width - $Filled))

    Write-Host ""
    Write-Host "  ┌─ Progress " -NoNewline -ForegroundColor $C.Muted
    Write-Host "────────────────────────────────────────────┐" -ForegroundColor $C.Muted
    Write-Host "  │ " -NoNewline -ForegroundColor $C.Muted
    Write-Host $Bar -NoNewline -ForegroundColor $C.Accent
    Write-Host " │" -ForegroundColor $C.Muted
    Write-Host "  │ " -NoNewline -ForegroundColor $C.Muted
    Write-Host ("{0,3}%" -f $Percent) -NoNewline -ForegroundColor $C.Title
    Write-Host "    $Current / $Total" -NoNewline -ForegroundColor $C.Muted
    Write-Host (" " * [math]::Max(0, 32 - ("$Current / $Total").Length)) -NoNewline
    Write-Host "│" -ForegroundColor $C.Muted
    Write-Host "  └──────────────────────────────────────────────────────┘" -ForegroundColor $C.Muted

    if ($Activity) {
        Write-Host "  $($Icon.Arrow) " -NoNewline -ForegroundColor $C.Accent
        Write-Host $Activity -ForegroundColor $C.Title
    }

    # Machine-readable marker consumed by the WPF front-end worker monitor.
    if ($GuiWorker) {
        Write-Host "GUI_PROGRESS|$Current|$Total|$Activity"
    }
}

function Format-Time {
    param([TimeSpan]$Time)
    if ($Time.TotalHours -ge 1) { return "{0:hh\:mm\:ss}" -f $Time }
    return "{0:mm\:ss}" -f $Time
}

function Show-AppMenu {
    param([array]$List)

    $half = [math]::Ceiling($List.Count / 2)

    Write-Host ""
    Write-Host "  ┌──── APP CATALOG ───────────────────────────────────────────────────────┐" -ForegroundColor $C.Muted

    for ($i = 0; $i -lt $half; $i++) {
        $left  = $List[$i]
        $right = $List[$i + $half]

        $leftText = "{0,2}  {1}" -f $left.Number, $left.Name
        $line = "  │  " + $leftText.PadRight(38)

        if ($right) {
            $rightText = "{0,2}  {1}" -f $right.Number, $right.Name
            $line += $rightText.PadRight(36)
        } else {
            $line += (" " * 36)
        }

        Write-Host ($line + "│") -ForegroundColor $C.Title
    }

    Write-Host "  └────────────────────────────────────────────────────────────────────────┘" -ForegroundColor $C.Muted
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

function Get-InstallerFallbackUrl {
    # Returns a direct installer URL for packages whose winget install fails
    # when elevated. Currently only Spotify needs this.
    param([string]$AppId)
    switch ($AppId) {
        "Spotify.Spotify" { return "https://download.scdn.co/SpotifyFullSetupX64.exe" }
        default           { return $null }
    }
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
    if ($App.Scope) { $Arguments += @("--scope", $App.Scope) }

    try {
        & winget @Arguments 2>&1 | Tee-Object -FilePath $OutputFile | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Status -Icon $Icon.Ok -Text "$($App.Name) installed" -Color $C.Success
            return [PSCustomObject]@{ Name = $App.Name; Status = "Installed" }
        }

        # 0x8A150056 = installer prohibits elevation. Retry as the invoking user
        # via scheduled task / Start-Process -Verb Open, without the elevation context.
        if ($LASTEXITCODE -eq -1978335146) {
            Write-Status -Icon $Icon.Warn -Text "Installer refused elevation — retrying unelevated…" -Color $C.Warning
            $DirectArgs = @("install", "--id", $App.ID, "--exact", "--source", $App.Source,
                "--scope", "user", "--silent", "--accept-package-agreements",
                "--accept-source-agreements", "--disable-interactivity")
            & winget @DirectArgs 2>&1 | Tee-Object -FilePath $OutputFile -Append | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Status -Icon $Icon.Ok -Text "$($App.Name) installed (per-user)" -Color $C.Success
                return [PSCustomObject]@{ Name = $App.Name; Status = "Installed" }
            }
            # Last resort: per-machine Spotify-style Squirrel installers can be
            # launched directly; they self-install to %LOCALAPPDATA% per user.
            $FallbackUrl = Get-InstallerFallbackUrl -AppId $App.ID
            if ($FallbackUrl) {
                Write-Status -Icon $Icon.Warn -Text "Winget failed again — trying direct installer…" -Color $C.Warning
                $DirectExe = "$TempDir\$SafeName-setup.exe"
                try {
                    Invoke-WebRequest -Uri $FallbackUrl -OutFile $DirectExe -UseBasicParsing
                    Start-Process -FilePath $DirectExe -ArgumentList "/silent" -Wait
                    if (Test-Path "$env:LOCALAPPDATA\Spotify\Spotify.exe") {
                        Write-Status -Icon $Icon.Ok -Text "$($App.Name) installed (direct)" -Color $C.Success
                        return [PSCustomObject]@{ Name = $App.Name; Status = "Installed" }
                    }
                } catch {
                    Write-Status -Icon $Icon.Warn -Text "Direct installer failed — $($_.Exception.Message)" -Color $C.Warning
                }
            }
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
    if ($App.ID -eq "HERMES") { Remove-Hermes; return }
    if ($App.ID -eq "EVOFOX") { Remove-EvoFox; return }

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
        # The hard-coded link can go stale — resolve the current one from the
        # official download page (id=49117) and retry.
        Write-Status -Icon $Icon.Warn -Text "Download link stale — resolving current ODT link…" -Color $C.Warning
        try {
            $Page = Invoke-WebRequest -Uri $ODTFallbackPage -UseBasicParsing
            $FreshUrl = [regex]::Match($Page.Content, 'https://download\.microsoft\.com/download/[A-Za-z0-9\-]+/officedeploymenttool_[\w\-]+\.exe').Value
            if (-not $FreshUrl) { throw "Could not resolve a new ODT link from the download page." }
            Invoke-WebRequest -Uri $FreshUrl -OutFile $ODTInstaller -UseBasicParsing
        } catch {
            Write-Status -Icon $Icon.Fail -Text "Failed to download ODT — $($_.Exception.Message)" -Color $C.Error
            return $null
        }
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
#  HERMES AGENT (official install.ps1 from hermes-agent.nousresearch.com)
# ============================================================

function Test-HermesInstalled {
    # The installer stages the launcher in %LOCALAPPDATA%\hermes\bin
    # (hermes.cmd or hermes.exe) and adds it to the User PATH; the checkout
    # lives under %LOCALAPPDATA%\hermes\hermes-agent (per-user layout).
    if (Get-Command hermes -ErrorAction SilentlyContinue) { return $true }
    if (Test-Path "$env:LOCALAPPDATA\hermes\bin\hermes.cmd") { return $true }
    if (Test-Path "$env:LOCALAPPDATA\hermes\bin\hermes.exe") { return $true }
    return (Test-Path "$env:LOCALAPPDATA\hermes\hermes-agent")
}

function Install-Hermes {
    Write-Host ""
    Write-Box -Title "Hermes Agent" -Subtitle "Nous Research · hermes-agent.nousresearch.com" -Color $C.Accent
    Write-Host ""

    if (Test-HermesInstalled) {
        Write-Status -Icon $Icon.Skip -Text "Hermes Agent — already installed" -Color $C.Existing
        return [PSCustomObject]@{ Name = "Hermes Agent"; Status = "Already Installed" }
    }

    Write-Status -Icon $Icon.Arrow -Text "Downloading Hermes Agent installer…" -Color $C.Accent

    $HermesLog = "$LogDir\19-Hermes_Agent.log"
    $OutputFile = "$TempDir\hermes-install.ps1"

    try {
        Invoke-WebRequest -Uri $HermesInstallUrl -OutFile $OutputFile -UseBasicParsing
    } catch {
        Write-Status -Icon $Icon.Fail -Text "Failed to download Hermes installer — $($_.Exception.Message)" -Color $C.Error
        return [PSCustomObject]@{ Name = "Hermes Agent"; Status = "Failed" }
    }

    Write-Status -Icon $Icon.Arrow -Text "Installing Hermes Agent (the installer provisions uv, Python, Node.js, ripgrep and ffmpeg automatically; this can take a while)…" -Color $C.Accent

    try {
        # The installer is interactive by design (provider / portal onboarding);
        # stream its output so the prompts are visible in this console.
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $OutputFile 2>&1 |
            Tee-Object -FilePath $HermesLog
        $Exit = $LASTEXITCODE

        if (($Exit -eq 0) -and (Test-HermesInstalled)) {
            Write-Status -Icon $Icon.Ok -Text "Hermes Agent installed" -Color $C.Success
            Write-Host "  Start it with: hermes   (docs: https://hermes-agent.nousresearch.com/)" -ForegroundColor $C.Muted
            return [PSCustomObject]@{ Name = "Hermes Agent"; Status = "Installed" }
        }

        Write-Status -Icon $Icon.Fail -Text "Hermes Agent install failed (exit $Exit) — see $HermesLog" -Color $C.Error
        return [PSCustomObject]@{ Name = "Hermes Agent"; Status = "Failed" }
    } catch {
        Write-Status -Icon $Icon.Fail -Text "Hermes Agent install failed — $($_.Exception.Message)" -Color $C.Error
        return [PSCustomObject]@{ Name = "Hermes Agent"; Status = "Failed" }
    }
}

function Remove-Hermes {
    Write-Status -Icon $Icon.Arrow -Text "Removing Hermes Agent…" -Color $C.Warning

    if (-not (Test-HermesInstalled)) {
        Write-Status -Icon $Icon.Skip -Text "Hermes Agent — not installed" -Color $C.Existing
        return
    }

    try {
        # 'hermes uninstall' offers to keep ~/.hermes config for a future
        # reinstall — run it interactively so the user can answer.
        & hermes uninstall
        if ($LASTEXITCODE -eq 0) {
            Write-Status -Icon $Icon.Ok -Text "Hermes Agent removed" -Color $C.Success
        } else {
            Write-Status -Icon $Icon.Fail -Text "hermes uninstall returned exit $LASTEXITCODE" -Color $C.Error
        }
    } catch {
        Write-Status -Icon $Icon.Fail -Text "Failed to remove Hermes Agent — $($_.Exception.Message)" -Color $C.Error
    }
}

# ============================================================
#  EVOFOX PHANTOM AIR MOUSE SOFTWARE (Amkette)
# ============================================================

# ${env:ProgramFiles(x86)} — braces required because of the parentheses in the name.
$EvoFoxInstallDir = "${env:ProgramFiles(x86)}\EvoFox Phantom Air Gaming Mouse"

function Test-EvoFoxInstalled {
    # Registry is the source of truth (Inno Setup writes an Uninstall entry).
    $Keys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    try {
        $Entry = Get-ItemProperty $Keys -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -match "EvoFox Phantom" }
        if ($Entry) { return $true }
    } catch {}
    # Fallback: the config app on disk.
    return (Test-Path "$EvoFoxInstallDir\Gaming Mouse 3.0.exe")
}

function Install-EvoFox {
    Write-Host ""
    Write-Box -Title "EvoFox Phantom Air" -Subtitle "Amkette gaming mouse software" -Color $C.Accent
    Write-Host ""

    if (Test-EvoFoxInstalled) {
        Write-Status -Icon $Icon.Skip -Text "EvoFox Phantom Air software — already installed" -Color $C.Existing
        return [PSCustomObject]@{ Name = "EvoFox Phantom Air"; Status = "Already Installed" }
    }

    Write-Status -Icon $Icon.Arrow -Text "Downloading EvoFox Phantom Air software…" -Color $C.Accent

    $EvoFoxLog = "$LogDir\20-EvoFox_Phantom_Air.log"
    $OutputExe = "$TempDir\EvoFox_Phantom_Air_Gaming_Mouse.exe"

    try {
        Invoke-WebRequest -Uri $EvoFoxUrl -OutFile $OutputExe -UseBasicParsing
    } catch {
        Write-Status -Icon $Icon.Fail -Text "Failed to download — $($_.Exception.Message)" -Color $C.Error
        Write-Host "  Manual download: $EvoFoxHelpPage" -ForegroundColor $C.Muted
        return [PSCustomObject]@{ Name = "EvoFox Phantom Air"; Status = "Failed" }
    }

    Write-Status -Icon $Icon.Arrow -Text "Installing EvoFox Phantom Air software…" -Color $C.Accent

    try {
        # Inno Setup 5.5.9 installer — standard silent flags.
        # NOTE: when the software is ALREADY installed this same exe flips into
        # uninstall mode (OK = uninstall) — hence the installed-check above.
        $Process = Start-Process -FilePath $OutputExe `
            -ArgumentList "/VERYSILENT","/SUPPRESSMSGBOXES","/NORESTART","/LOG=`"$EvoFoxLog`"" `
            -Wait -PassThru

        if (($Process.ExitCode -eq 0) -and (Test-EvoFoxInstalled)) {
            Write-Status -Icon $Icon.Ok -Text "EvoFox Phantom Air software installed" -Color $C.Success
            Write-Host "  Configure the mouse with: $EvoFoxInstallDir\Gaming Mouse 3.0.exe" -ForegroundColor $C.Muted
            return [PSCustomObject]@{ Name = "EvoFox Phantom Air"; Status = "Installed" }
        }

        Write-Status -Icon $Icon.Fail -Text "Install failed (exit $($Process.ExitCode)) — see $EvoFoxLog" -Color $C.Error
        return [PSCustomObject]@{ Name = "EvoFox Phantom Air"; Status = "Failed" }
    } catch {
        Write-Status -Icon $Icon.Fail -Text "Install failed — $($_.Exception.Message)" -Color $C.Error
        return [PSCustomObject]@{ Name = "EvoFox Phantom Air"; Status = "Failed" }
    }
}

function Remove-EvoFox {
    Write-Status -Icon $Icon.Arrow -Text "Removing EvoFox Phantom Air software…" -Color $C.Warning

    if (-not (Test-EvoFoxInstalled)) {
        Write-Status -Icon $Icon.Skip -Text "EvoFox Phantom Air software — not installed" -Color $C.Existing
        return
    }

    try {
        $Keys = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        $Entry = Get-ItemProperty $Keys -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -match "EvoFox Phantom" }

        $Uninstaller = if ($Entry -and $Entry.UninstallString) {
            # Strip the surrounding quotes Inno writes into the registry value.
            $Entry.UninstallString.Trim('"')
        } else {
            "$EvoFoxInstallDir\unins000.exe"
        }

        if (-not (Test-Path $Uninstaller)) {
            Write-Status -Icon $Icon.Fail -Text "Uninstaller not found at $Uninstaller" -Color $C.Error
            return
        }

        # Inno: /SILENT shows a small progress bar, /VERYSILENT shows nothing.
        $Process = Start-Process -FilePath $Uninstaller -ArgumentList "/SILENT","/SUPPRESSMSGBOXES","/NORESTART" -Wait -PassThru
        if ($Process.ExitCode -eq 0) {
            Write-Status -Icon $Icon.Ok -Text "EvoFox Phantom Air software removed" -Color $C.Success
        } else {
            Write-Status -Icon $Icon.Fail -Text "Uninstall returned exit $($Process.ExitCode)" -Color $C.Error
        }
    } catch {
        Write-Status -Icon $Icon.Fail -Text "Failed to remove — $($_.Exception.Message)" -Color $C.Error
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
        } elseif ($App.ID -eq "HERMES") {
            Write-ProgressBar -Current $Current -Total $Total -Activity $App.Name
            $Result = Install-Hermes
        } elseif ($App.ID -eq "EVOFOX") {
            Write-ProgressBar -Current $Current -Total $Total -Activity $App.Name
            $Result = Install-EvoFox
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
    Write-Panel -Title "FULL INSTALLATION" -Subtitle "Install the complete workstation profile" -Color $C.Success
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
        Write-Panel -Title "MANUAL INSTALLATION" -Subtitle "Choose exactly which applications to install" -Color $C.Accent
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
        Write-Panel -Title "REMOVE APPLICATIONS" -Subtitle "Uninstall selected applications" -Color $C.Error
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
#  WINUTIL (Chris Titus) — tweak / debloat GUI
# ============================================================

function Start-WinUtil {
    Write-Header
    Write-Panel -Title "CHRIS TITUS WINUTIL" -Subtitle "Windows tweaks · debloat · updates config" -Color $C.Accent
    Write-Host ""
    Write-Host "  Launching WinUtil in an elevated child PowerShell session…" -ForegroundColor $C.Title
    Write-Host "  The WinUtil GUI will open in its own window. When you close it," -ForegroundColor $C.Muted
    Write-Host "  you will return to this menu." -ForegroundColor $C.Muted
    Write-Host ""

    # Run in a separate elevated window so the WPF GUI gets a clean console
    # and any tweaks it applies don't fight this script's transcript/log.
    try {
        # -Verb RunAs would prompt UAC again; this script is already elevated,
        # so the child inherits admin rights without a UAC prompt.
        $Proc = Start-Process powershell.exe -ArgumentList @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command",
            "irm $WinUtilUrl | iex"
        ) -PassThru -Wait

        if ($Proc.ExitCode -eq 0) {
            Write-Status -Icon $Icon.Ok -Text "WinUtil session ended" -Color $C.Success
        } else {
            Write-Status -Icon $Icon.Warn -Text "WinUtil exited with code $($Proc.ExitCode) (non-zero can be normal when tweaks requested a reboot)" -Color $C.Warning
        }
    } catch {
        Write-Status -Icon $Icon.Fail -Text "Failed to launch WinUtil — $($_.Exception.Message)" -Color $C.Error
        Write-Host "  You can run it manually: irm $WinUtilUrl | iex" -ForegroundColor $C.Muted
    }

    Write-Host ""
    Read-Host "Press Enter to return to the main menu"
}

# ============================================================
#  MASSGRAVE (Microsoft Activation Scripts) — activation menu
# ============================================================

function Start-MassGrave {
    Write-Header
    Write-Panel -Title "MASSGRAVE — MICROSOFT ACTIVATION SCRIPTS" -Subtitle "Windows / Office activation" -Color $C.Accent
    Write-Host ""
    Write-Host "  Launching MAS in an elevated child PowerShell session…" -ForegroundColor $C.Title
    Write-Host "  In the menu that appears, type the number corresponding" -ForegroundColor $C.Muted
    Write-Host "  to one of the Green options (recommended)." -ForegroundColor $C.Muted
    Write-Host "  When you close it, you will return to this menu." -ForegroundColor $C.Muted
    Write-Host ""

    # Run in a separate elevated window so the interactive MAS menu gets a
    # clean console and doesn't fight this script's transcript/log.
    try {
        # This script is already elevated, so the child inherits admin
        # rights without a UAC prompt.
        $Proc = Start-Process powershell.exe -ArgumentList @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command",
            "irm $MassGraveUrl | iex"
        ) -PassThru -Wait

        if ($Proc.ExitCode -eq 0) {
            Write-Status -Icon $Icon.Ok -Text "MAS session ended" -Color $C.Success
        } else {
            Write-Status -Icon $Icon.Warn -Text "MAS exited with code $($Proc.ExitCode) (non-zero can be normal)" -Color $C.Warning
        }
    } catch {
        Write-Status -Icon $Icon.Fail -Text "Failed to launch MAS — $($_.Exception.Message)" -Color $C.Error
        Write-Host "  You can run it manually: irm $MassGraveUrl | iex" -ForegroundColor $C.Muted
    }

    Write-Host ""
    Read-Host "Press Enter to return to the main menu"
}


# ============================================================
#  STARTUP CHECKS + WPF INTERACTIVE GUI
# ============================================================

function Assert-SetupEnvironment {
    if (-not (Test-Admin)) {
        Write-Host ""
        Write-Panel -Title "ADMINISTRATOR REQUIRED" -Subtitle "Please relaunch PowerShell as Administrator" -Color $C.Error
        Write-Status -Icon $Icon.Fail -Text "This script must be run as Administrator" -Color $C.Error
        Read-Host "Press Enter to exit"
        exit 1
    }

    if (-not (Test-Winget)) {
        Write-Host ""
        Write-Panel -Title "WINGET NOT FOUND" -Subtitle "Microsoft App Installer is required" -Color $C.Error
        Write-Status -Icon $Icon.Fail -Text "WinGet was not found" -Color $C.Error
        Write-Host "Install/update App Installer from Microsoft Store and try again." -ForegroundColor $C.Muted
        Read-Host "Press Enter to exit"
        exit 1
    }
}

# Worker mode: the WPF shell launches a hidden elevated PowerShell process for
# long-running installs/removals so the GUI remains responsive.
if ($GuiWorker) {
    Assert-SetupEnvironment
    Initialize-Winget

    $Selected = Read-AppSelection -Choice $WorkerSelection
    if ($Selected.Count -eq 0) {
        Write-Host "No applications selected."
        exit 2
    }

    if ($WorkerMode -eq "Install") {
        Start-Installation -SelectedApps $Selected
    } else {
        foreach ($App in $Selected) {
            Remove-App -App $App
        }
    }

    try { Stop-Transcript | Out-Null } catch {}
    exit 0
}

Assert-SetupEnvironment
Initialize-Winget

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# ---------------------------------------------------------------------------
# WPF theme helpers
# ---------------------------------------------------------------------------

$script:Gui = @{}
$script:Gui.Selected = @{}
$script:Gui.CurrentView = "Install"
$script:Gui.Worker = $null
$script:Gui.WorkerOut = $null
$script:Gui.WorkerErr = $null
$script:Gui.LastLogText = ""
$script:Gui.LastProgress = 0

function New-Brush([string]$Hex) {
    return [System.Windows.Media.BrushConverter]::new().ConvertFromString($Hex)
}

$script:Brush = @{
    Bg       = New-Brush "#070C14"
    Sidebar  = New-Brush "#0B1220"
    Panel    = New-Brush "#0D1727"
    Card     = New-Brush "#111D2E"
    Card2    = New-Brush "#132238"
    Border   = New-Brush "#223652"
    Text     = New-Brush "#F4F7FF"
    Muted    = New-Brush "#93A4C0"
    Blue     = New-Brush "#2496FF"
    Blue2    = New-Brush "#4F6BFF"
    Purple   = New-Brush "#7B3FF2"
    Green    = New-Brush "#35D07F"
    Red      = New-Brush "#F43F5E"
    Amber    = New-Brush "#F4B740"
}

function New-TextBlock {
    param([string]$Text,[double]$Size=14,[string]$Weight="Normal",[object]$Color=$script:Brush.Text)
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $Text
    $t.FontSize = $Size
    $t.Foreground = $Color
    $t.VerticalAlignment = "Center"
    $t.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI")
    if ($Weight -eq "SemiBold") { $t.FontWeight = [System.Windows.FontWeights]::SemiBold }
    elseif ($Weight -eq "Bold") { $t.FontWeight = [System.Windows.FontWeights]::Bold }
    return $t
}

function New-RoundedButton {
    param([string]$Text,[double]$Width=120,[double]$Height=40,[object]$Background=$script:Brush.Card2,[object]$Foreground=$script:Brush.Text)
    $b = New-Object System.Windows.Controls.Button
    $b.Content = $Text
    $b.Width = $Width
    $b.Height = $Height
    $b.Margin = "5"
    $b.Foreground = $Foreground
    $b.Background = $Background
    $b.BorderBrush = $script:Brush.Border
    $b.BorderThickness = "1"
    $b.FontSize = 13
    $b.FontWeight = [System.Windows.FontWeights]::SemiBold
    $b.Cursor = [System.Windows.Input.Cursors]::Hand
    $b.Template = [System.Windows.Markup.XamlReader]::Parse(@"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button">
  <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="10" Padding="12,0">
    <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
  </Border>
</ControlTemplate>
"@)
    return $b
}

function New-CardBorder {
    $b = New-Object System.Windows.Controls.Border
    $b.Background = $script:Brush.Card
    $b.BorderBrush = $script:Brush.Border
    $b.BorderThickness = "1"
    $b.CornerRadius = "11"
    $b.Margin = "5"
    $b.Padding = "10"
    return $b
}

function Get-AppGlyph([string]$Name) {
    switch -Regex ($Name) {
        "Telegram" { return "✈" }
        "PowerToys" { return "▦" }
        "Python" { return "🐍" }
        "Visual Studio Code" { return "</>" }
        "Spotify" { return "●" }
        "WhatsApp" { return "◔" }
        "Brave" { return "♢" }
        "Chrome" { return "●" }
        "^Git$" { return "◆" }
        "Cloudflare" { return "☁" }
        "Node" { return "JS" }
        "7-Zip" { return "7z" }
        "AB Download" { return "↓" }
        "VLC" { return "▲" }
        "FFmpeg" { return "F" }
        "GitHub" { return "GH" }
        "PowerShell" { return "PS" }
        "Microsoft 365" { return "M" }
        "Hermes" { return "H" }
        "EvoFox" { return "E" }
        default { return "•" }
    }
}

function Get-AppSubtitle([PSCustomObject]$App) {
    switch -Regex ($App.Name) {
        "Telegram|WhatsApp" { return "Messaging app" }
        "Brave|Chrome" { return "Web browser" }
        "Python" { return "Python runtime with pip" }
        "Visual Studio Code" { return "Code editor" }
        "Spotify" { return "Music streaming" }
        "PowerToys" { return "Windows utilities" }
        "Cloudflare" { return "Secure access client" }
        "Node" { return "JavaScript runtime" }
        "GitHub CLI" { return "GitHub command-line tools" }
        "Git" { return "Version control" }
        "7-Zip" { return "File archiver" }
        "AB Download" { return "Download manager" }
        "VLC" { return "Media player" }
        "FFmpeg" { return "Media toolkit" }
        "PowerShell" { return "Modern PowerShell shell" }
        "Microsoft 365" { return "Word · Excel · PowerPoint" }
        "Hermes" { return "Nous Research agent CLI" }
        "EvoFox" { return "Gaming mouse software" }
        default { return "Windows application" }
    }
}

function Get-AppCategory([PSCustomObject]$App) {
    switch -Regex ($App.Name) {
        'Telegram|WhatsApp|Discord' { 'Communication'; break }
        'Brave|Chrome|Cloudflare' { 'Internet'; break }
        'Python|Visual Studio|GitHub CLI|Git|Node|PowerShell|Hermes' { 'Development'; break }
        'Spotify|VLC|FFmpeg' { 'Media'; break }
        'PowerToys|7-Zip|AB Download' { 'Utilities'; break }
        'Microsoft 365' { 'Office'; break }
        'EvoFox' { 'Gaming'; break }
        default { 'Other' }
    }
}

function Get-SelectedNumbers {
    @($script:Gui.CheckBoxes | Where-Object { $_.IsChecked -eq $true } | ForEach-Object { [int]$_.Tag })
}

function Set-GuiLog([string]$Text) {
    if ($script:Gui.LogBox) {
        $script:Gui.LogBox.Text = $Text
        $script:Gui.LogBox.ScrollToEnd()
    }
}

function Set-GuiProgress([int]$Current,[int]$Total,[string]$Activity) {
    if (-not $script:Gui.ProgressBar) { return }
    $pct = if ($Total -gt 0) { [math]::Min(100,[math]::Max(0,[math]::Round(($Current/$Total)*100))) } else { 0 }
    $script:Gui.ProgressBar.Value = $pct
    $script:Gui.ProgressText.Text = "$Current / $Total  ($pct%)"
    $script:Gui.Activity.Text = if ($Activity) { $Activity } else { 'Ready' }
    $script:Gui.StatusText.Text = if ($Activity) { $Activity } else { 'Ready' }
}

function Set-AppStatus([string]$Line) {
    foreach ($state in @($script:Gui.AppStates.Values)) {
        if (-not $state -or -not $state.Status) { continue }
        $name = [string]$state.App.Name
        if ($Line -match [regex]::Escape("$name installed")) {
            $state.Status.Text = 'Installed'
            $state.Status.Foreground = $script:Brush.Green
        } elseif ($Line -match [regex]::Escape("$name — already installed")) {
            $state.Status.Text = 'Already installed'
            $state.Status.Foreground = $script:Brush.Amber
        } elseif ($Line -match [regex]::Escape("$name failed")) {
            $state.Status.Text = 'Failed'
            $state.Status.Foreground = $script:Brush.Red
        } elseif ($Line -match [regex]::Escape("Removing $name")) {
            $state.Status.Text = 'Removing...'
            $state.Status.Foreground = $script:Brush.Amber
        } elseif ($Line -match [regex]::Escape("Removed $name")) {
            $state.Status.Text = 'Removed'
            $state.Status.Foreground = $script:Brush.Green
        }
    }
}

function Set-AllChecks([bool]$State) {
    foreach ($cb in @($script:Gui.CheckBoxes)) { $cb.IsChecked = $State }
    Update-SelectionCount
}

function Update-SelectionCount {
    $count = @(Get-SelectedNumbers).Count
    if ($script:Gui.SelectionText) { $script:Gui.SelectionText.Text = "$count selected" }
    if ($script:Gui.InstallSelectedButton) { $script:Gui.InstallSelectedButton.IsEnabled = ($count -gt 0) -and (-not $script:Gui.Busy) }
    if ($script:Gui.RemoveSelectedButton) { $script:Gui.RemoveSelectedButton.IsEnabled = ($count -gt 0) -and (-not $script:Gui.Busy) }
}

function New-AppCard([PSCustomObject]$App,[bool]$RemoveMode=$false) {
    $card = New-Object System.Windows.Controls.Border
    $card.Width = 300
    $card.MinHeight = 82
    $card.Margin = '0,0,10,10'
    $card.Padding = '12'
    $card.Background = $script:Brush.Card
    $card.BorderBrush = $script:Brush.Border
    $card.BorderThickness = 1
    $card.CornerRadius = '6'
    $card.Cursor = [System.Windows.Input.Cursors]::Hand
    $card.Tag = $App.Number
    $card.ToolTip = $App.Name

    $g = New-Object System.Windows.Controls.Grid
    $g.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{Width='Auto'}))
    $g.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{Width='Auto'}))
    $g.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{Width='*'}))
    $g.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{Width='Auto'}))

    $cb = New-Object System.Windows.Controls.CheckBox
    $cb.Width = 22
    $cb.VerticalAlignment = 'Top'
    $cb.Margin = '0,3,10,0'
    $cb.Tag = $App.Number
    $cb.ToolTip = if ($RemoveMode) { "Select $($App.Name) for removal" } else { "Select $($App.Name)" }
    $cb.Add_Checked({
        $n=[int]$this.Tag
        if ($script:Gui.AppStates.ContainsKey($n)) { $script:Gui.AppStates[$n].Status.Text='Selected'; $script:Gui.AppStates[$n].Status.Foreground=$script:Brush.Text }
        Update-SelectionCount
    })
    $cb.Add_Unchecked({
        $n=[int]$this.Tag
        if ($script:Gui.AppStates.ContainsKey($n)) { $script:Gui.AppStates[$n].Status.Text='Not selected'; $script:Gui.AppStates[$n].Status.Foreground=$script:Brush.Muted }
        Update-SelectionCount
    })
    [void]$g.Children.Add($cb)

    $icon = New-Object System.Windows.Controls.Border
    $icon.Width = 42; $icon.Height = 42
    $icon.CornerRadius = '6'
    $icon.Background = $script:Brush.Card2
    $icon.Margin = '0,0,10,0'
    $icon.VerticalAlignment = 'Top'
    $glyph = New-Object System.Windows.Controls.TextBlock
    $glyph.Text = Get-AppGlyph $App.Name
    $glyph.FontSize = 15
    $glyph.FontWeight = 'Bold'
    $glyph.Foreground = $script:Brush.Text
    $glyph.HorizontalAlignment = 'Center'
    $glyph.VerticalAlignment = 'Center'
    $icon.Child = $glyph
    [System.Windows.Controls.Grid]::SetColumn($icon,1)
    [void]$g.Children.Add($icon)

    $info = New-Object System.Windows.Controls.StackPanel
    $info.Margin = '10,0,10,0'
    [System.Windows.Controls.Grid]::SetColumn($info,2)
    $title = New-TextBlock $App.Name 13 'SemiBold'
    $title.TextWrapping = 'Wrap'
    $sub = New-TextBlock (Get-AppSubtitle $App) 10 'Normal' $script:Brush.Muted
    $sub.Margin = '0,3,0,0'
    $status = New-TextBlock 'Not selected' 10 'SemiBold' $script:Brush.Muted
    $status.Margin = '0,6,0,0'
    $info.Children.Add($title) | Out-Null
    $info.Children.Add($sub) | Out-Null
    $info.Children.Add($status) | Out-Null
    [void]$g.Children.Add($info)

    $cat = New-TextBlock (Get-AppCategory $App) 9 'SemiBold' $script:Brush.Muted
    $cat.VerticalAlignment = 'Top'
    [System.Windows.Controls.Grid]::SetColumn($cat,3)
    [void]$g.Children.Add($cat)

    $card.Child = $g
    $state = [pscustomobject]@{ App=$App; Card=$card; Check=$cb; Status=$status; Category=(Get-AppCategory $App) }
    $script:Gui.AppStates[$App.Number] = $state
    $script:Gui.CheckBoxes += $cb

    $card.Add_MouseLeftButtonUp({
        param($sender,$e)
        $src = $e.OriginalSource
        while ($src) {
            if ($src -is [System.Windows.Controls.CheckBox]) { return }
            if ($src -eq $sender) { break }
            try { $src = [System.Windows.Media.VisualTreeHelper]::GetParent($src) } catch { break }
        }
        $state = $script:Gui.AppStates[[int]$sender.Tag]
        $state.Check.IsChecked = -not [bool]$state.Check.IsChecked
        $e.Handled = $true
    })
    return $card
}

function Update-AppFilter {
    $query = if ($script:Gui.SearchBox) { $script:Gui.SearchBox.Text.Trim().ToLowerInvariant() } else { '' }
    $category = if ($script:Gui.Category) { [string]$script:Gui.Category.Tag } else { 'All' }
    foreach ($state in @($script:Gui.AppStates.Values)) {
        $hay = ("$($state.App.Name) $($state.App.ID) $($state.Category)").ToLowerInvariant()
        $matchSearch = [string]::IsNullOrWhiteSpace($query) -or $hay.Contains($query)
        $matchCategory = ($category -eq 'All' -or $state.Category -eq $category)
        $state.Card.Visibility = if ($matchSearch -and $matchCategory) { 'Visible' } else { 'Collapsed' }
    }
}

function Set-GuiButtonsEnabled([bool]$Enabled) {
    $script:Gui.Busy = -not $Enabled
    foreach ($b in @($script:Gui.ActionButtons)) { if ($b) { $b.IsEnabled = $Enabled } }
    Update-SelectionCount
}

function Start-GuiWorker([string]$Mode,[array]$Numbers) {
    if ($script:Gui.Worker -and -not $script:Gui.Worker.HasExited) {
        [System.Windows.MessageBox]::Show('Another operation is already running.','Fresh Windows Setup','OK','Warning') | Out-Null
        return
    }
    if (@($Numbers).Count -eq 0) {
        [System.Windows.MessageBox]::Show('Select at least one application.','Fresh Windows Setup','OK','Warning') | Out-Null
        return
    }

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $out = Join-Path $TempDir "gui-worker-$stamp.out.log"
    $err = Join-Path $TempDir "gui-worker-$stamp.err.log"
    Remove-Item $out,$err -Force -ErrorAction SilentlyContinue
    $modeArg = if ($Mode -eq 'Remove') { 'Remove' } else { 'Install' }
    $selection = ($Numbers -join ',')
    $args = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -GuiWorker -WorkerMode $modeArg -WorkerSelection `"$selection`""
    $p = Start-Process powershell.exe -ArgumentList $args -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Hidden -PassThru
    $script:Gui.Worker = $p
    $script:Gui.WorkerOut = $out
    $script:Gui.WorkerErr = $err
    $script:Gui.LastLogText = ''
    $script:Gui.CurrentMode = $modeArg
    $script:Gui.ProgressText.Text = "0 / $(@($Numbers).Count)  (0%)"
    $script:Gui.ProgressBar.Value = 0
    $script:Gui.Activity.Text = if ($modeArg -eq 'Remove') { 'Preparing removal...' } else { 'Preparing installation...' }
    $script:Gui.StatusText.Text = $script:Gui.Activity.Text
    Set-GuiButtonsEnabled $false
}

function Update-GuiWorker {
    if (-not $script:Gui.Worker) { return }
    $parts = @()
    foreach ($f in @($script:Gui.WorkerOut,$script:Gui.WorkerErr)) {
        if ($f -and (Test-Path $f)) {
            try { $parts += @(Get-Content $f -Tail 120 -ErrorAction SilentlyContinue) } catch {}
        }
    }
    if ($parts.Count -gt 0) {
        $clean = @()
        foreach ($line in $parts) {
            if ($line -match '^GUI_PROGRESS\|(\d+)\|(\d+)\|(.*)$') {
                Set-GuiProgress ([int]$Matches[1]) ([int]$Matches[2]) $Matches[3]
            } else {
                Set-AppStatus ([string]$line)
                $clean += $line
            }
        }
        $text = ($clean -join "`r`n")
        if ($text -ne $script:Gui.LastLogText) {
            $script:Gui.LastLogText = $text
            Set-GuiLog $text
        }
    }
    if ($script:Gui.Worker.HasExited) {
        $exit = $script:Gui.Worker.ExitCode
        Set-GuiButtonsEnabled $true
        if ($exit -eq 0) {
            $script:Gui.ProgressBar.Value = 100
            $script:Gui.ProgressText.Text = 'Complete'
            $script:Gui.Activity.Text = if ($script:Gui.CurrentMode -eq 'Remove') { 'Removal completed.' } else { 'Installation completed.' }
            $script:Gui.StatusText.Text = $script:Gui.Activity.Text
        } else {
            $script:Gui.Activity.Text = "Operation failed (exit $exit)."
            $script:Gui.StatusText.Text = $script:Gui.Activity.Text
        }
        $script:Gui.Worker = $null
        $script:Gui.WorkerOut = $null
        $script:Gui.WorkerErr = $null
    }
}

function Select-Tab([string]$Name) {
    if ($script:Gui.MainTabs) { $script:Gui.MainTabs.SelectedItem = $script:Gui.TabItems[$Name] }
}

# ---------------------------------------------------------------------------
# Stable WPF shell. Layout is declared in XAML; PowerShell only owns state and
# event handlers. This mirrors the architecture used by WinUtil while keeping
# Fresh Windows Setup's feature set and installer backend intact.
# ---------------------------------------------------------------------------

$Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStartupLocation="CenterScreen"
        Width="1100" Height="680" MinWidth="860" MinHeight="540"
        Title="Fresh Windows Setup" Background="#0B0F14" WindowStyle="SingleBorderWindow" ResizeMode="CanResize"
        UseLayoutRounding="True" SnapsToDevicePixels="True">
    <Window.Resources>
        <SolidColorBrush x:Key="BG" Color="#0B0F14"/>
        <SolidColorBrush x:Key="Panel" Color="#11161D"/>
        <SolidColorBrush x:Key="Card" Color="#151B23"/>
        <SolidColorBrush x:Key="CardHover" Color="#1A222D"/>
        <SolidColorBrush x:Key="Border" Color="#293340"/>
        <SolidColorBrush x:Key="Text" Color="#F2F5F8"/>
        <SolidColorBrush x:Key="Muted" Color="#8F9BA8"/>
        <SolidColorBrush x:Key="Accent" Color="#2F81F7"/>
        <SolidColorBrush x:Key="AccentHover" Color="#4690F8"/>
        <SolidColorBrush x:Key="Green" Color="#3FB950"/>
        <SolidColorBrush x:Key="Red" Color="#F85149"/>
        <SolidColorBrush x:Key="Amber" Color="#D29922"/>
        <Style TargetType="TextBlock">
            <Setter Property="FontFamily" Value="Segoe UI"/>
            <Setter Property="Foreground" Value="{StaticResource Text}"/>
        </Style>
        <Style x:Key="TabStyle" TargetType="TabItem">
            <Setter Property="Foreground" Value="{StaticResource Muted}"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="18,11"/>
            <Setter Property="Margin" Value="0,0,4,0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabItem">
                        <Border x:Name="TabBorder" Background="Transparent" BorderBrush="Transparent" BorderThickness="0,0,0,2" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" ContentSource="Header"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="TabBorder" Property="Background" Value="#17202B"/>
                                <Setter TargetName="TabBorder" Property="BorderBrush" Value="{StaticResource Accent}"/>
                                <Setter Property="Foreground" Value="{StaticResource Text}"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="TabBorder" Property="Background" Value="#141B23"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="ActionButton" TargetType="Button">
            <Setter Property="Foreground" Value="{StaticResource Text}"/>
            <Setter Property="Background" Value="#171E27"/>
            <Setter Property="BorderBrush" Value="{StaticResource Border}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="14,8"/>
            <Setter Property="Margin" Value="0,0,8,0"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value><ControlTemplate TargetType="Button"><Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="5" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border></ControlTemplate></Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#202A36"/></Trigger>
                <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger>
            </Style.Triggers>
        </Style>
        <Style x:Key="PrimaryButton" TargetType="Button" BasedOn="{StaticResource ActionButton}">
            <Setter Property="Background" Value="{StaticResource Accent}"/>
            <Setter Property="BorderBrush" Value="{StaticResource Accent}"/>
            <Setter Property="Foreground" Value="White"/>
        </Style>
        <Style x:Key="DangerButton" TargetType="Button" BasedOn="{StaticResource ActionButton}">
            <Setter Property="Background" Value="#32181A"/>
            <Setter Property="BorderBrush" Value="#6E2927"/>
            <Setter Property="Foreground" Value="#FFB4AE"/>
        </Style>
        <Style x:Key="ChipButton" TargetType="Button" BasedOn="{StaticResource ActionButton}">
            <Setter Property="Padding" Value="12,6"/><Setter Property="Margin" Value="0,0,6,0"/><Setter Property="FontSize" Value="11"/>
        </Style>
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="{StaticResource Text}"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
        </Style>
        <Style TargetType="ScrollBar">
            <Setter Property="Width" Value="9"/>
        </Style>
    </Window.Resources>

    <Grid Background="{StaticResource BG}">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <TabControl Name="MainTabs" Grid.Row="0" Background="#0E131A" BorderThickness="0" Padding="12,0,12,0" Margin="8,8,8,0">
            <TabControl.Resources><Style TargetType="TabItem" BasedOn="{StaticResource TabStyle}"/></TabControl.Resources>
            <TabItem Name="InstallTab" Header="Install"/>
            <TabItem Name="RemoveTab" Header="Remove"/>
            <TabItem Name="SystemTab" Header="System Setup"/>
            <TabItem Name="ExportTab" Header="Export"/>
            <TabItem Name="ToolsTab" Header="Tools"/>
            <TabItem Name="LogsTab" Header="Logs"/>
            <TabItem Name="AboutTab" Header="About"/>
        </TabControl>

        <Grid Grid.Row="1" Name="PageHost" Margin="18,14,18,12">
            <Grid Name="InstallPage">
                <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
                <Grid Margin="0,0,0,12">
                    <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                    <StackPanel>
                        <TextBlock Name="PageTitle" Text="Install Applications" FontSize="24" FontWeight="Bold"/>
                        <TextBlock Name="PageSubtitle" Text="Select applications and install them through WinGet or the configured installer." FontSize="12" Foreground="{StaticResource Muted}" Margin="0,3,0,0"/>
                    </StackPanel>
                    <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                        <TextBlock Name="SelectionText" Text="0 selected" Foreground="{StaticResource Muted}" VerticalAlignment="Center" Margin="0,0,10,0"/>
                        <Button Name="SelectAllButton" Content="Select All" Style="{StaticResource ActionButton}"/>
                        <Button Name="ClearAllButton" Content="Clear" Style="{StaticResource ActionButton}"/>
                        <Button Name="InstallEverythingButton" Content="Install Everything" Style="{StaticResource PrimaryButton}"/>
                    </StackPanel>
                </Grid>
                <Grid Grid.Row="1" Margin="0,0,0,12">
                    <Grid.ColumnDefinitions><ColumnDefinition Width="280"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                    <Border Background="#111820" BorderBrush="{StaticResource Border}" BorderThickness="1" CornerRadius="5" Padding="10,6" Margin="0,0,10,0">
                        <TextBox Name="SearchBox" Text="" BorderThickness="0" Background="Transparent" Foreground="{StaticResource Text}" FontSize="12" Padding="0" ToolTip="Search applications"/>
                    </Border>
                    <ScrollViewer Grid.Column="1" HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Disabled">
                        <StackPanel Orientation="Horizontal">
                            <Button Name="ChipAll" Content="All" Tag="All" Style="{StaticResource ChipButton}"/>
                            <Button Name="ChipDevelopment" Content="Development" Tag="Development" Style="{StaticResource ChipButton}"/>
                            <Button Name="ChipInternet" Content="Internet" Tag="Internet" Style="{StaticResource ChipButton}"/>
                            <Button Name="ChipCommunication" Content="Communication" Tag="Communication" Style="{StaticResource ChipButton}"/>
                            <Button Name="ChipUtilities" Content="Utilities" Tag="Utilities" Style="{StaticResource ChipButton}"/>
                            <Button Name="ChipMedia" Content="Media" Tag="Media" Style="{StaticResource ChipButton}"/>
                            <Button Name="ChipOffice" Content="Office" Tag="Office" Style="{StaticResource ChipButton}"/>
                            <Button Name="ChipGaming" Content="Gaming" Tag="Gaming" Style="{StaticResource ChipButton}"/>
                            <Button Name="ChipOther" Content="Other" Tag="Other" Style="{StaticResource ChipButton}"/>
                        </StackPanel>
                    </ScrollViewer>
                </Grid>
                <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                    <WrapPanel Name="AppGrid"/>
                </ScrollViewer>
            </Grid>

            <Grid Name="RemovePage" Visibility="Collapsed">
                <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
                <StackPanel Margin="0,0,0,14">
                    <TextBlock Text="Remove Applications" FontSize="24" FontWeight="Bold"/>
                    <TextBlock Text="Select applications to uninstall from this Windows installation." FontSize="12" Foreground="{StaticResource Muted}" Margin="0,3,0,0"/>
                    <StackPanel Orientation="Horizontal" Margin="0,14,0,0">
                        <Button Name="RemoveSelectAllButton" Content="Select All" Style="{StaticResource ActionButton}"/>
                        <Button Name="RemoveClearAllButton" Content="Clear" Style="{StaticResource ActionButton}"/>
                        <Button Name="RemoveSelectedButton" Content="Remove Selected" Style="{StaticResource DangerButton}"/>
                    </StackPanel>
                </StackPanel>
                <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto"><WrapPanel Name="RemoveGrid"/></ScrollViewer>
            </Grid>

            <Grid Name="SystemPage" Visibility="Collapsed">
                <StackPanel>
                    <TextBlock Text="System Setup" FontSize="24" FontWeight="Bold"/>
                    <TextBlock Text="Configure the development environment and common Windows settings." FontSize="12" Foreground="{StaticResource Muted}" Margin="0,3,0,18"/>
                    <Border Background="{StaticResource Card}" BorderBrush="{StaticResource Border}" BorderThickness="1" CornerRadius="6" Padding="18" MaxWidth="850" HorizontalAlignment="Left">
                        <StackPanel>
                            <TextBlock Text="Development Environment" FontSize="17" FontWeight="SemiBold"/>
                            <TextBlock Text="Update Python tooling, configure Node/Git and apply the setup routines already present in this script." FontSize="12" Foreground="{StaticResource Muted}" TextWrapping="Wrap" Margin="0,6,0,0"/>
                            <Button Name="SystemSetupButton" Content="Run System Setup" Style="{StaticResource PrimaryButton}" Width="170" HorizontalAlignment="Left" Margin="0,18,0,0"/>
                        </StackPanel>
                    </Border>
                </StackPanel>
            </Grid>

            <Grid Name="ExportPage" Visibility="Collapsed">
                <StackPanel>
                    <TextBlock Text="Export Settings" FontSize="24" FontWeight="Bold"/>
                    <TextBlock Text="Back up useful Windows preferences for your next installation." FontSize="12" Foreground="{StaticResource Muted}" Margin="0,3,0,18"/>
                    <Border Background="{StaticResource Card}" BorderBrush="{StaticResource Border}" BorderThickness="1" CornerRadius="6" Padding="18" MaxWidth="850" HorizontalAlignment="Left">
                        <StackPanel>
                            <TextBlock Text="Windows configuration backup" FontSize="17" FontWeight="SemiBold"/>
                            <TextBlock Text="Explorer, desktop, themes, optional features and wallpaper information." FontSize="12" Foreground="{StaticResource Muted}" Margin="0,6,0,0"/>
                            <Button Name="ExportButton" Content="Export Settings" Style="{StaticResource PrimaryButton}" Width="160" HorizontalAlignment="Left" Margin="0,18,0,0"/>
                        </StackPanel>
                    </Border>
                </StackPanel>
            </Grid>

            <Grid Name="ToolsPage" Visibility="Collapsed">
                <StackPanel>
                    <TextBlock Text="Tools" FontSize="24" FontWeight="Bold"/>
                    <TextBlock Text="Launch external Windows utilities without leaving Fresh Windows Setup." FontSize="12" Foreground="{StaticResource Muted}" Margin="0,3,0,18"/>
                    <WrapPanel>
                        <Border Width="320" Height="150" Background="{StaticResource Card}" BorderBrush="{StaticResource Border}" BorderThickness="1" CornerRadius="6" Padding="16" Margin="0,0,10,10">
                            <StackPanel><TextBlock Text="Chris Titus Tech WinUtil" FontSize="16" FontWeight="SemiBold"/><TextBlock Text="Windows tweaks, debloat, fixes and updates." FontSize="11" Foreground="{StaticResource Muted}" Margin="0,5,0,0"/><Button Name="WinUtilButton" Content="Open WinUtil" Style="{StaticResource PrimaryButton}" Width="125" HorizontalAlignment="Left" Margin="0,18,0,0"/></StackPanel>
                        </Border>
                        <Border Width="320" Height="150" Background="{StaticResource Card}" BorderBrush="{StaticResource Border}" BorderThickness="1" CornerRadius="6" Padding="16" Margin="0,0,10,10">
                            <StackPanel><TextBlock Text="Microsoft Activation Scripts" FontSize="16" FontWeight="SemiBold"/><TextBlock Text="Open the MAS interactive menu." FontSize="11" Foreground="{StaticResource Muted}" Margin="0,5,0,0"/><Button Name="MASButton" Content="Open MAS" Style="{StaticResource ActionButton}" Width="125" HorizontalAlignment="Left" Margin="0,18,0,0"/></StackPanel>
                        </Border>
                    </WrapPanel>
                </StackPanel>
            </Grid>

            <Grid Name="LogsPage" Visibility="Collapsed">
                <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
                <StackPanel Margin="0,0,0,12"><TextBlock Text="Logs" FontSize="24" FontWeight="Bold"/><TextBlock Text="Recent setup transcripts and worker logs." FontSize="12" Foreground="{StaticResource Muted}" Margin="0,3,0,0"/></StackPanel>
                <TextBox Name="LogsList" Grid.Row="1" IsReadOnly="True" TextWrapping="NoWrap" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" Background="#0D1218" Foreground="{StaticResource Muted}" BorderBrush="{StaticResource Border}" BorderThickness="1" FontFamily="Cascadia Mono" FontSize="11" Padding="12"/>
            </Grid>

            <Grid Name="AboutPage" Visibility="Collapsed">
                <StackPanel>
                    <TextBlock Text="About" FontSize="24" FontWeight="Bold"/>
                    <TextBlock Text="Fresh Windows Setup" FontSize="16" FontWeight="SemiBold" Margin="0,18,0,0"/>
                    <TextBlock Text="A PowerShell + WPF workstation bootstrapper using WinGet and the existing setup routines in this repository." FontSize="12" Foreground="{StaticResource Muted}" TextWrapping="Wrap" MaxWidth="700" Margin="0,5,0,0"/>
                    <TextBlock Text="Made by Pushkar Singh" FontSize="13" FontWeight="SemiBold" Margin="0,18,0,0"/>
                    <TextBlock Text="github.com/truepushkar" FontSize="11" Foreground="{StaticResource Muted}"/>
                </StackPanel>
            </Grid>
        </Grid>

        <Border Grid.Row="2" Background="#0E131A" BorderBrush="{StaticResource Border}" BorderThickness="0,1,0,0" Padding="18,10">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <Grid Grid.Row="0">
                    <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                    <TextBlock Text="Progress" FontSize="12" FontWeight="SemiBold"/>
                    <TextBlock Name="ProgressText" Grid.Column="1" Text="0 / 0  (0%)" FontSize="11" Foreground="{StaticResource Muted}"/>
                </Grid>
                <ProgressBar Name="ProgressBar" Grid.Row="1" Height="7" Minimum="0" Maximum="100" Value="0" Margin="0,6,0,8" Background="#202833" Foreground="{StaticResource Accent}"/>
                <TextBlock Name="Activity" Grid.Row="2" Text="Ready" FontSize="12" FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/>
                <TextBlock Name="StatusText" Grid.Row="3" Text="Ready" FontSize="10" Foreground="{StaticResource Muted}" Margin="0,3,0,0" TextTrimming="CharacterEllipsis"/>
                <TextBlock Text="Status Log" Grid.Row="4" FontSize="12" FontWeight="SemiBold" Margin="0,10,0,6"/>
                <TextBox Name="LogBox" Grid.Row="5" Height="72" IsReadOnly="True" TextWrapping="NoWrap" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" Background="#090D12" Foreground="#A9B5C3" BorderBrush="{StaticResource Border}" BorderThickness="1" FontFamily="Cascadia Mono" FontSize="10" Padding="8"/>
            </Grid>
        </Border>
    </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$Xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
# XamlReader.Load does not generate named-element properties on the window the way
# compiled XAML does, so every $window.<Name> reference below would be null.
# Expose each named element via FindName to keep those references working.
$xmlDoc = [xml]$Xaml
foreach ($node in @($xmlDoc.SelectNodes("//*[@Name]"))) {
    $elName = $node.GetAttribute('Name')
    $el = $window.FindName($elName)
    if ($null -ne $el) {
        Add-Member -InputObject $window -MemberType NoteProperty -Name $elName -Value $el -Force
    }
}
# Open at ~75% of the primary screen work area, clamped to the window minimums.
$wa = [System.Windows.SystemParameters]::WorkArea
$window.Width  = [math]::Min([math]::Max($wa.Width  * 0.75, $window.MinWidth),  $wa.Width)
$window.Height = [math]::Min([math]::Max($wa.Height * 0.75, $window.MinHeight), $wa.Height)
$script:Gui.Window = $window
$script:Gui.Busy = $false
$script:Gui.AppStates = @{}
$script:Gui.CheckBoxes = @()
$script:Gui.ActionButtons = @()
$script:Gui.TabItems = @{
    Install=$window.InstallTab; Remove=$window.RemoveTab; System=$window.SystemTab;
    Export=$window.ExportTab; Tools=$window.ToolsTab; Logs=$window.LogsTab; About=$window.AboutTab
}
$script:Gui.MainTabs = $window.MainTabs
$script:Gui.AppGrid = $window.AppGrid
$script:Gui.RemoveGrid = $window.RemoveGrid
$script:Gui.SearchBox = $window.SearchBox
$script:Gui.SelectionText = $window.SelectionText
$script:Gui.ProgressBar = $window.ProgressBar
$script:Gui.ProgressText = $window.ProgressText
$script:Gui.Activity = $window.Activity
$script:Gui.StatusText = $window.StatusText
$script:Gui.LogBox = $window.LogBox

# Build both install/remove catalogs once. Pages are shown/hidden rather than rebuilt.
# New-AppCard registers each card's state (App/Card/Check/Status) in $script:Gui.AppStates
# as it is built, so consume those state objects directly. Building the remove catalog
# re-registers the same keys, so snapshot install states first.
foreach ($app in $Apps) {
    [void]$window.AppGrid.Children.Add((New-AppCard $app $false))
}
$script:Gui.InstallStates = @{}
$script:Gui.InstallChecks = @()
foreach ($app in $Apps) {
    $st = $script:Gui.AppStates[$app.Number]
    $script:Gui.InstallStates[$app.Number] = $st
    $script:Gui.InstallChecks += $st.Check
}
# Build the remove cards; they keep independent selections from the install cards.
$script:Gui.RemoveStates = @{}
$script:Gui.RemoveChecks = @()
foreach ($app in $Apps) {
    $card = New-AppCard $app $true
    [void]$window.RemoveGrid.Children.Add($card)
    $st = $script:Gui.AppStates[$app.Number]
    $script:Gui.RemoveStates[$app.Number] = $st
    $script:Gui.RemoveChecks += $st.Check
}
$script:Gui.AppStates = $script:Gui.InstallStates
$script:Gui.CheckBoxes = $script:Gui.InstallChecks

# Search/filter events.
$window.SearchBox.Add_TextChanged({
    $script:Gui.AppStates = if ($script:Gui.MainTabs.SelectedItem -eq $window.RemoveTab) { $script:Gui.RemoveStates } else { $script:Gui.InstallStates }
    Update-AppFilter
})
$chips = @($window.ChipAll,$window.ChipDevelopment,$window.ChipInternet,$window.ChipCommunication,$window.ChipUtilities,$window.ChipMedia,$window.ChipOffice,$window.ChipGaming,$window.ChipOther)
foreach ($chip in $chips) {
    $chip.Add_Click({
        $script:Gui.Category = $this
        $script:Gui.Category.Tag = [string]$this.Tag
        Update-AppFilter
    })
}
$script:Gui.Category = $window.ChipAll
$script:Gui.Category.Tag = 'All'

$window.SelectAllButton.Add_Click({ Set-AllChecks $true })
$window.ClearAllButton.Add_Click({ Set-AllChecks $false })
$window.InstallEverythingButton.Add_Click({
    $script:Gui.AppStates = $script:Gui.InstallStates
    $script:Gui.CheckBoxes = $script:Gui.InstallChecks
    Start-GuiWorker 'Install' @($Apps.Number)
})
$window.RemoveSelectAllButton.Add_Click({
    $script:Gui.AppStates = $script:Gui.RemoveStates
    $script:Gui.CheckBoxes = $script:Gui.RemoveChecks
    Set-AllChecks $true
})
$window.RemoveClearAllButton.Add_Click({
    $script:Gui.AppStates = $script:Gui.RemoveStates
    $script:Gui.CheckBoxes = $script:Gui.RemoveChecks
    Set-AllChecks $false
})
$window.RemoveSelectedButton.Add_Click({
    $script:Gui.AppStates = $script:Gui.RemoveStates
    $script:Gui.CheckBoxes = $script:Gui.RemoveChecks
    Start-GuiWorker 'Remove' (Get-SelectedNumbers)
})

$window.MainTabs.Add_SelectionChanged({
    $selected = $window.MainTabs.SelectedItem
    foreach ($p in @($window.InstallPage,$window.RemovePage,$window.SystemPage,$window.ExportPage,$window.ToolsPage,$window.LogsPage,$window.AboutPage)) { $p.Visibility='Collapsed' }
    if ($selected -eq $window.InstallTab) { $window.InstallPage.Visibility='Visible'; $script:Gui.AppStates=$script:Gui.InstallStates; $script:Gui.CheckBoxes=$script:Gui.InstallChecks; Update-AppFilter; Update-SelectionCount }
    elseif ($selected -eq $window.RemoveTab) { $window.RemovePage.Visibility='Visible'; $script:Gui.AppStates=$script:Gui.RemoveStates; $script:Gui.CheckBoxes=$script:Gui.RemoveChecks; Update-SelectionCount }
    elseif ($selected -eq $window.SystemTab) { $window.SystemPage.Visibility='Visible' }
    elseif ($selected -eq $window.ExportTab) { $window.ExportPage.Visibility='Visible' }
    elseif ($selected -eq $window.ToolsTab) { $window.ToolsPage.Visibility='Visible' }
    elseif ($selected -eq $window.LogsTab) {
        $window.LogsPage.Visibility='Visible'
        try { $files=Get-ChildItem $LogDir -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending; $window.LogsList.Text=($files | ForEach-Object { "$($_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))  $($_.Name)" }) -join "`r`n" } catch {}
    }
    elseif ($selected -eq $window.AboutTab) { $window.AboutPage.Visibility='Visible' }
})

$window.SystemSetupButton.Add_Click({
    try {
        $window.SystemSetupButton.IsEnabled=$false
        Configure-Development
        [System.Windows.MessageBox]::Show('System setup completed.','Fresh Windows Setup','OK','Information') | Out-Null
    } catch { [System.Windows.MessageBox]::Show($_.Exception.Message,'System setup failed','OK','Error') | Out-Null }
    finally { $window.SystemSetupButton.IsEnabled=$true }
})
$window.ExportButton.Add_Click({
    try {
        $dest = Join-Path $SetupRoot ('Exports\' + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        reg.exe export 'HKCU\Control Panel\Desktop' "$dest\desktop.reg" /y | Out-Null
        reg.exe export 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer' "$dest\explorer.reg" /y | Out-Null
        reg.exe export 'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes' "$dest\themes.reg" /y | Out-Null
        Get-CimInstance Win32_OptionalFeature | Where-Object InstallState -eq 1 | Select-Object Name,InstallState | Export-Csv "$dest\optional-features.csv" -NoTypeInformation
        $wall=(Get-ItemProperty 'HKCU:\Control Panel\Desktop' -ErrorAction SilentlyContinue).WallPaper
        $wall | Out-File "$dest\wallpaper.txt" -Encoding UTF8
        [System.Windows.MessageBox]::Show("Settings exported to:`n$dest",'Export complete','OK','Information') | Out-Null
    } catch { [System.Windows.MessageBox]::Show($_.Exception.Message,'Export failed','OK','Error') | Out-Null }
})
$window.WinUtilButton.Add_Click({ Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-Command','irm https://christitus.com/win | iex') -WindowStyle Normal | Out-Null })
$window.MASButton.Add_Click({ Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-Command','irm https://massgrave.dev/get | iex') -WindowStyle Normal | Out-Null })

# Confirm before closing while a worker operation is still running (native caption handles min/max/close).
$window.Add_Closing({
    param($sender,$e)
    if ($script:Gui.Worker -and -not $script:Gui.Worker.HasExited) {
        $r=[System.Windows.MessageBox]::Show('An operation is still running. Close anyway?','Fresh Windows Setup','YesNo','Warning')
        if ($r -ne 'Yes') { $e.Cancel = $true }
    }
})

$script:Gui.ActionButtons = @($window.SelectAllButton,$window.ClearAllButton,$window.InstallEverythingButton,$window.RemoveSelectAllButton,$window.RemoveClearAllButton,$window.RemoveSelectedButton)
Set-GuiButtonsEnabled $true
Set-GuiLog 'Ready. Select applications and start an operation.'

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(350)
$timer.Add_Tick({
    Update-GuiWorker
})
$timer.Start()

$window.ShowDialog() | Out-Null
try { $timer.Stop() } catch {}
try { Stop-Transcript | Out-Null } catch {}
