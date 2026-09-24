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
    # Scope=user is required for per-user installers (Spotify) that fail with
    # 0x8A150056 "installer prohibits elevation" when winget runs elevated.
    [PSCustomObject]@{ Number = 5;  Name = "Spotify";                               ID = "Spotify.Spotify";           Source = "winget";  Scope = "user" }
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
#  STARTUP CHECKS
# ============================================================

if (-not (Test-Admin)) {
    Write-Host ""
    Write-Panel -Title "ADMINISTRATOR REQUIRED" -Subtitle "Please relaunch PowerShell as Administrator" -Color $C.Error
    Write-Status -Icon $Icon.Fail -Text "This script must be run as Administrator" -Color $C.Error
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

if (-not (Test-Winget)) {
    Write-Host ""
    Write-Panel -Title "WINGET NOT FOUND" -Subtitle "Microsoft App Installer is required" -Color $C.Error
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
    Write-Panel -Title "MAIN MENU" -Subtitle "Choose an operation" -Color $C.Accent

    Write-Host "  [1]  Full Installation"          -ForegroundColor $C.Success
    Write-Host "       Complete workstation setup"  -ForegroundColor $C.Muted
    Write-Host ""
    Write-Host "  [2]  Manual Installation"        -ForegroundColor $C.Accent
    Write-Host "       Select applications"         -ForegroundColor $C.Muted
    Write-Host ""
    Write-Host "  [3]  Remove Applications"        -ForegroundColor $C.Error
    Write-Host "       Uninstall selected apps"     -ForegroundColor $C.Muted
    Write-Host ""
    Write-Host "  [4]  Retry Failed Installations" -ForegroundColor $C.Warning
    Write-Host "       Retry the previous failures" -ForegroundColor $C.Muted
    Write-Host ""
    Write-Host "  [5]  WinUtil (Chris Titus)"       -ForegroundColor $C.Accent
    Write-Host "       Tweaks / debloat / updates config" -ForegroundColor $C.Muted
    Write-Host ""
    Write-Host "  [6]  MassGrave Activation"       -ForegroundColor $C.Accent
    Write-Host "       Windows / Office activation" -ForegroundColor $C.Muted
    Write-Host ""
    Write-Host "  [7]  Exit"                       -ForegroundColor $C.Muted
    Write-Host ""

    $MenuChoice = Read-Host "  Select an option"
    switch ($MenuChoice) {
        "1" { Full-Installation }
        "2" { Manual-Installation }
        "3" { Remove-Applications }
        "4" { Retry-Failed; Read-Host "`nPress Enter to continue" }
        "5" { Start-WinUtil }
        "6" { Start-MassGrave }
        "7" {
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
