#requires -Version 5.1
<#
    Fresh Windows Setup  -  Terminal Edition
    ----------------------------------------
    Version : 3.0
    Purpose : Keyboard-driven terminal UI to bulk install / remove apps on a
              freshly imaged Windows machine (WinGet + Office Deployment Tool
              + custom installers). No WPF, no windows - terminal only.

    Interactive:   .\FreshWindowsSetup.ps1
    Headless:      .\FreshWindowsSetup.ps1 -List
                   .\FreshWindowsSetup.ps1 -Install "1,2,7,18" -Yes
                   .\FreshWindowsSetup.ps1 -Full -Yes -SkipDev
                   .\FreshWindowsSetup.ps1 -Remove "5,6" -Yes

    NOTE: this file is intentionally ASCII-only (glyphs are built from char
    codes), so it works in Windows PowerShell 5.1 with or without a BOM.
#>
[CmdletBinding()]
param(
    [switch]$Full,            # install the whole catalog (headless)
    [string]$Install = "",    # install apps by number, e.g. "1,4,18" (headless)
    [string]$Remove  = "",    # remove apps by number (headless)
    [switch]$SkipDev,         # skip the development-environment step
    [switch]$Yes,             # no confirmation prompts / no Git prompts
    [switch]$List             # print the catalog and exit
)

$ErrorActionPreference = "Continue"
$ProgressPreference    = "SilentlyContinue"   # makes Invoke-WebRequest much faster on PS 5.1
$script:Version        = "3.0"

# ============================================================
#  TERMINAL / VT SETUP
# ============================================================

$ESC = [char]27
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { [Console]::InputEncoding  = [System.Text.Encoding]::UTF8 } catch {}

# Enable ANSI / VT processing on legacy conhost (Windows Terminal already has it).
try {
    Add-Type -Namespace Native -Name Con -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int h);
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out uint m);
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, uint m);
'@ -ErrorAction Stop
} catch {}
try {
    $h = [Native.Con]::GetStdHandle(-11); $m = 0
    [void][Native.Con]::GetConsoleMode($h, [ref]$m)
    [void][Native.Con]::SetConsoleMode($h, ($m -bor 4))
} catch {}

# Glyphs built from code points (keeps the script file pure ASCII).
$G = @{
    Ok    = [char]0x2714; Fail = [char]0x2716; Dot  = [char]0x2022; Arrow = [char]0x279C
    Ptr   = [char]0x25B8; On   = [char]0x25CF; Off  = [char]0x25CB; Mid   = [char]0x00B7
    Up    = [char]0x2191; Down = [char]0x2193; Ell  = [char]0x2026; Dash  = [char]0x2014
    TL = [char]0x256D; TR = [char]0x256E; BL = [char]0x2570; BR = [char]0x256F
    H  = [char]0x2500; V  = [char]0x2502; Full = [char]0x2588; Light = [char]0x2591
    Back = [char]0x2039; Fwd = [char]0x203A
}
$SpinFrames = @(0x280B,0x2819,0x2839,0x2838,0x283C,0x2834,0x2826,0x2827,0x2807,0x280F) | ForEach-Object { [string][char]$_ }

function Rgb([int]$r,[int]$g,[int]$b) { "$ESC[38;2;${r};${g};${b}m" }

$P = @{
    Reset    = "$ESC[0m"
    Bold     = "$ESC[1m"
    Accent   = (Rgb 56 189 248)
    Accent2  = (Rgb 167 139 250)
    Success  = (Rgb 74 222 128)
    Warning  = (Rgb 251 191 36)
    Existing = (Rgb 251 191 36)
    Error    = (Rgb 248 113 113)
    Muted    = (Rgb 148 163 184)
    Dim      = (Rgb 100 116 139)
    Title    = (Rgb 241 245 249)
    BgSel    = "$ESC[48;2;30;41;59m"
}

function Paint([string]$Text,[string]$Color) { "$($P[$Color])$Text$($P.Reset)" }
function Say([string]$Text = "") { [Console]::WriteLine($Text) }
function Get-VisLen([string]$s) { ([regex]::Replace($s, "\x1b\[[0-9;?]*[A-Za-z]", "")).Length }
function Pad-Vis([string]$s,[int]$w) { $n = $w - (Get-VisLen $s); if ($n -gt 0) { $s + (" " * $n) } else { $s } }
function Fit([string]$s,[int]$w) { if ($s.Length -le $w) { $s } elseif ($w -gt 1) { $s.Substring(0,$w-1) + $G.Ell } else { $s.Substring(0,[math]::Max(0,$w)) } }

function Get-W { try { [math]::Max(64,[math]::Min(100,[Console]::WindowWidth - 4)) } catch { 80 } }
function Get-H { try { [Console]::WindowHeight } catch { 30 } }

function Get-Gradient([string]$Text,[int[]]$From,[int[]]$To) {
    $sb = New-Object System.Text.StringBuilder
    $n = [math]::Max(1, $Text.Length - 1)
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $t = $i / $n
        $r = [int]($From[0] + ($To[0] - $From[0]) * $t)
        $g = [int]($From[1] + ($To[1] - $From[1]) * $t)
        $b = [int]($From[2] + ($To[2] - $From[2]) * $t)
        [void]$sb.Append("$ESC[1;38;2;${r};${g};${b}m").Append($Text[$i])
    }
    [void]$sb.Append($P.Reset)
    $sb.ToString()
}

$script:InScreen = $false
function Enter-Screen { if (-not $script:InScreen) { [Console]::Write("$ESC[?1049h$ESC[?25l"); $script:InScreen = $true } }
function Leave-Screen { if ($script:InScreen)     { [Console]::Write("$ESC[?25h$ESC[?1049l"); $script:InScreen = $false } }

function Show-Frame([array]$Lines) {
    $out = "$ESC[H" + (($Lines | ForEach-Object { "$_$ESC[K" }) -join "`n") + "$ESC[J"
    [Console]::Write($out)
}

# ============================================================
#  CONFIGURATION
# ============================================================

$SetupRoot = "$env:SystemDrive\FreshWindowsSetup"
$LogDir    = "$SetupRoot\Logs"
$TempDir   = "$SetupRoot\Temp"
New-Item -ItemType Directory -Force -Path $SetupRoot, $LogDir, $TempDir | Out-Null
$LogFile = "$LogDir\setup-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"

# Office Deployment Tool (Expand-ODT auto-resolves a fresh link if this one goes stale)
$ODTUrl          = "https://download.microsoft.com/download/6c1eeb25-cf8b-41d9-8d0d-cc1dbc032140/officedeploymenttool_20326-20112.exe"
$ODTFallbackPage = "https://www.microsoft.com/en-us/download/details.aspx?id=49117"

# Hermes Agent - official Windows installer (per-user, provisions its own deps).
$HermesInstallUrl = "https://hermes-agent.nousresearch.com/install.ps1"

# EvoFox Phantom Air wired gaming mouse software (Amkette, Inno Setup package).
$EvoFoxUrl        = "https://cdn.shopify.com/s/files/1/0676/1273/7846/files/EvoFox_Phantom_Air_Gaming_Mouse._20250620_1.exe?v=1750394461"
$EvoFoxHelpPage   = "https://www.amkette.com/pages/evofox-phantom-air-wired-gaming-mouse-help"
$EvoFoxInstallDir = "${env:ProgramFiles(x86)}\EvoFox Phantom Air Gaming Mouse"

# External tools launched from the Tools menu.
$WinUtilUrl   = "https://christitus.com/win"
$MassGraveUrl = "https://get.activated.win"

function New-App($Number,$Name,$ID,$Source,$Category,$Desc) {
    [PSCustomObject]@{ Number=$Number; Name=$Name; ID=$ID; Source=$Source; Category=$Category; Desc=$Desc }
}

$Apps = @(
    (New-App 1  "Telegram"                  "Telegram.TelegramDesktop"  "winget"    "Communication" "Messaging app")
    (New-App 2  "PowerToys"                 "Microsoft.PowerToys"       "winget"    "Utilities"     "Windows utilities")
    (New-App 3  "Python 3.14"               "Python.Python.3.14"        "winget"    "Development"   "Python runtime with pip")
    (New-App 4  "Visual Studio Code"        "Microsoft.VisualStudioCode" "winget"   "Development"   "Code editor")
    (New-App 5  "Spotify"                   "9NCBCSZSJRSB"              "msstore"   "Media"         "Music streaming (Store)")
    (New-App 6  "WhatsApp"                  "9NKSQGP7F2NH"              "msstore"   "Communication" "Messaging app (Store)")
    (New-App 7  "Brave"                     "Brave.Brave"               "winget"    "Internet"      "Web browser")
    (New-App 8  "Google Chrome"             "Google.Chrome"             "winget"    "Internet"      "Web browser")
    (New-App 9  "Git"                       "Git.Git"                   "winget"    "Development"   "Version control")
    (New-App 10 "Cloudflare WARP"           "Cloudflare.Warp"           "winget"    "Internet"      "Secure access client")
    (New-App 11 "Node.js LTS"               "OpenJS.NodeJS.LTS"         "winget"    "Development"   "JavaScript runtime")
    (New-App 12 "7-Zip"                     "7zip.7zip"                 "winget"    "Utilities"     "File archiver")
    (New-App 13 "AB Download Manager"       "amir1376.ABDownloadManager" "winget"   "Utilities"     "Download manager")
    (New-App 14 "VLC"                       "VideoLAN.VLC"              "winget"    "Media"         "Media player")
    (New-App 15 "FFmpeg"                    "Gyan.FFmpeg"               "winget"    "Media"         "Media toolkit")
    (New-App 16 "GitHub CLI"                "GitHub.cli"                "winget"    "Development"   "GitHub command-line tools")
    (New-App 17 "PowerShell 7"              "Microsoft.PowerShell"      "winget"    "Development"   "Modern PowerShell shell")
    (New-App 18 "Microsoft 365 (Word + Excel + PowerPoint)" "OFFICE"   "microsoft" "Office"        "Office Deployment Tool")
    (New-App 19 "Hermes Agent (Nous Research CLI)"          "HERMES"   "custom"    "Development"   "Nous Research agent CLI")
    (New-App 20 "EvoFox Phantom Air Mouse Software"         "EVOFOX"   "custom"    "Gaming"        "Gaming mouse software")
)

$script:Results    = @()
$script:LastFailed = @()
$script:Installed  = $null     # HashSet of installed IDs (null = unknown)

# ============================================================
#  LOGGING + STATUS LINES
# ============================================================

function Write-Log([string]$Text) {
    try { Add-Content -Path $LogFile -Value ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Text) -ErrorAction SilentlyContinue } catch {}
}

function Write-Status {
    param([string]$Icon,[string]$Text,[string]$Color = "Title")
    Say ("  " + (Paint "$Icon" $Color) + "  " + (Paint $Text $Color))
    Write-Log "$Icon $Text"
}

function Format-Time([TimeSpan]$Time) {
    if ($Time.TotalHours -ge 1) { return "{0:hh\:mm\:ss}" -f $Time }
    return "{0:mm\:ss}" -f $Time
}

function Get-Bar([int]$Current,[int]$Total,[int]$Width = 36) {
    $pct = if ($Total -gt 0) { [math]::Min(100,[math]::Max(0,[math]::Round(($Current / $Total) * 100))) } else { 0 }
    $f = [math]::Round(($pct / 100) * $Width)
    (Paint ([string]$G.Full * $f) "Accent") + (Paint ([string]$G.Light * ($Width - $f)) "Dim") + " " + (Paint ("{0,3}%" -f $pct) "Title")
}

function Write-Rule { Say ("  " + (Paint ([string]$G.H * ((Get-W) - 2)) "Dim")) }

function Write-Panel {
    param([string]$Title,[string]$Subtitle = "",[string]$Color = "Accent")
    $w = (Get-W) - 2
    $pad = { param($t) $n = $w - $t.Length; $l = [math]::Floor($n / 2); (" " * $l) + $t + (" " * ($n - $l)) }
    Say ""
    Say ("  " + (Paint ("$($G.TL)" + ([string]$G.H * $w) + "$($G.TR)") $Color))
    Say ("  " + (Paint $G.V $Color) + (Paint (& $pad $Title) "Title") + (Paint $G.V $Color))
    if ($Subtitle) { Say ("  " + (Paint $G.V $Color) + (Paint (& $pad $Subtitle) "Muted") + (Paint $G.V $Color)) }
    Say ("  " + (Paint ("$($G.BL)" + ([string]$G.H * $w) + "$($G.BR)") $Color))
    Say ""
}

# ============================================================
#  SYSTEM CHECKS
# ============================================================

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Test-Winget { $null -ne (Get-Command winget -ErrorAction SilentlyContinue) }

function Refresh-Path {
    # Pick up PATH changes made by freshly installed apps (python, node, git...).
    try {
        $m = [Environment]::GetEnvironmentVariable("Path","Machine")
        $u = [Environment]::GetEnvironmentVariable("Path","User")
        $env:Path = (($m, $u) | Where-Object { $_ }) -join ";"
    } catch {}
}

function Invoke-Winget {
    # Runs winget hidden, shows a spinner, appends output to $LogFile, returns exit code.
    param([string[]]$Arguments,[string]$LogFile = "",[string]$Label = "Working")
    $exe = (Get-Command winget -ErrorAction SilentlyContinue).Source
    if (-not $exe) { $exe = "winget" }
    $tag = [guid]::NewGuid().ToString("N")
    $out = "$TempDir\wg-$tag.out"; $err = "$TempDir\wg-$tag.err"
    $p = Start-Process -FilePath $exe -ArgumentList $Arguments -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Hidden -PassThru
    $null = $p.Handle
    $sw = [Diagnostics.Stopwatch]::StartNew(); $i = 0
    while (-not $p.HasExited) {
        [Console]::Write("`r$ESC[K  " + (Paint $SpinFrames[$i % $SpinFrames.Count] "Accent") + "  " + (Paint $Label "Title") + (Paint ("   " + (Format-Time $sw.Elapsed)) "Muted"))
        $i++; Start-Sleep -Milliseconds 90
    }
    $p.WaitForExit()
    [Console]::Write("`r$ESC[K")
    $code = $p.ExitCode
    if ($LogFile) {
        try { Get-Content $out,$err -ErrorAction SilentlyContinue | Out-File $LogFile -Append -Encoding UTF8 } catch {}
    }
    Remove-Item $out,$err -Force -ErrorAction SilentlyContinue
    return $code
}

function Initialize-Winget {
    [void](Invoke-Winget -Arguments @("source","update","--disable-interactivity") -LogFile "$LogDir\winget-source-update.log" -Label "Updating WinGet sources")
    Write-Status $G.Ok "WinGet sources updated" "Success"
}

function Test-OfficeInstalled {
    try { return [bool](Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration" -ErrorAction Stop).ProductReleaseIds } catch { return $false }
}

function Update-InstalledCache {
    # One `winget export` gives exact package IDs for everything installed - far
    # faster than running `winget list` once per app.
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $f = "$TempDir\winget-export.json"
    Remove-Item $f -Force -ErrorAction SilentlyContinue
    [void](Invoke-Winget -Arguments @("export","-o",$f,"--accept-source-agreements","--disable-interactivity") -Label "Scanning installed apps")
    $ok = $false
    if (Test-Path $f) {
        try {
            $j = Get-Content $f -Raw | ConvertFrom-Json
            foreach ($s in @($j.Sources)) { foreach ($p in @($s.Packages)) { [void]$set.Add([string]$p.PackageIdentifier) } }
            $ok = $true
        } catch {}
    }
    if (Test-OfficeInstalled)  { [void]$set.Add("OFFICE") }
    if (Test-HermesInstalled)  { [void]$set.Add("HERMES") }
    if (Test-EvoFoxInstalled)  { [void]$set.Add("EVOFOX") }
    $script:Installed = if ($ok) { $set } else { $null }
}

function Get-InstallState($App) {
    # $true / $false / $null (unknown)
    if (-not $script:Installed) { return $null }
    if ($script:Installed.Contains($App.ID)) { return $true }
    if ($App.Source -eq "msstore") { return $null }
    return $false
}

function Test-AppInstalled {
    param([string]$ID,[string]$Source)
    if ($script:Installed -and $script:Installed.Contains($ID)) { return $true }
    try {
        $o = @(winget list --id $ID --source $Source --exact --accept-source-agreements --disable-interactivity 2>$null)
        return ($LASTEXITCODE -eq 0) -and ($o -match [regex]::Escape($ID))
    } catch { return $false }
}

function Get-InstallerFallbackUrl([string]$AppId) {
    switch ($AppId) {
        { $_ -in "Spotify.Spotify","9NCBCSZSJRSB" } { return "https://download.scdn.co/SpotifyFullSetupX64.exe" }
        default { return $null }
    }
}

# ============================================================
#  INSTALL / REMOVE - SINGLE APP
# ============================================================

function New-Result($Name,$Status) { [PSCustomObject]@{ Name = $Name; Status = $Status } }

function Install-App {
    param([PSCustomObject]$App)

    if (Test-AppInstalled -ID $App.ID -Source $App.Source) {
        Write-Status $G.Dot "$($App.Name) $($G.Dash) already installed" "Existing"
        return (New-Result $App.Name "Already Installed")
    }

    Write-Status $G.Arrow "Installing $($App.Name)" "Accent"
    $safe = $App.Name -replace '[^a-zA-Z0-9]', '_'
    $log  = "$LogDir\$($App.Number)-$safe.log"
    $base = @("install","--id",$App.ID,"--exact","--source",$App.Source,"--silent",
              "--accept-package-agreements","--accept-source-agreements","--disable-interactivity")

    try {
        $code = Invoke-Winget -Arguments $base -LogFile $log -Label $App.Name
        # 0 = ok, 0x8A15002B = already installed / no applicable update
        if ($code -eq 0 -or $code -eq -1978335189) {
            Write-Status $G.Ok "$($App.Name) installed" "Success"
            return (New-Result $App.Name "Installed")
        }

        # 0x8A150056 = installer refuses elevation -> retry per-user.
        if ($code -eq -1978335146 -and $App.Source -eq "winget") {
            Write-Status "!" "Installer refused elevation $($G.Dash) retrying per-user" "Warning"
            $code = Invoke-Winget -Arguments ($base + @("--scope","user")) -LogFile $log -Label "$($App.Name) (per-user)"
            if ($code -eq 0) {
                Write-Status $G.Ok "$($App.Name) installed (per-user)" "Success"
                return (New-Result $App.Name "Installed")
            }
        }

        $url = Get-InstallerFallbackUrl -AppId $App.ID
        if ($url) {
            Write-Status "!" "WinGet failed $($G.Dash) trying direct installer" "Warning"
            $exe = "$TempDir\$safe-setup.exe"
            try {
                Invoke-WebRequest -Uri $url -OutFile $exe -UseBasicParsing
                Start-Process -FilePath $exe -ArgumentList "/silent" -Wait
                if (Test-Path "$env:LOCALAPPDATA\Spotify\Spotify.exe") {
                    Write-Status $G.Ok "$($App.Name) installed (direct)" "Success"
                    return (New-Result $App.Name "Installed")
                }
            } catch { Write-Status "!" "Direct installer failed $($G.Dash) $($_.Exception.Message)" "Warning" }
        }

        Write-Status $G.Fail ("$($App.Name) failed (exit 0x{0:X8}) $($G.Dash) log: $log" -f $code) "Error"
        return (New-Result $App.Name "Failed")
    } catch {
        Write-Status $G.Fail "$($App.Name) failed $($G.Dash) $($_.Exception.Message)" "Error"
        return (New-Result $App.Name "Failed")
    }
}

function Remove-App {
    param([PSCustomObject]$App)

    Write-Status $G.Arrow "Removing $($App.Name)" "Warning"
    switch ($App.ID) {
        "OFFICE" { return (Remove-Office) }
        "HERMES" { return (Remove-Hermes) }
        "EVOFOX" { return (Remove-EvoFox) }
    }

    if (-not (Test-AppInstalled -ID $App.ID -Source $App.Source)) {
        Write-Status $G.Dot "$($App.Name) $($G.Dash) not installed" "Existing"
        return (New-Result $App.Name "Not Installed")
    }
    $safe = $App.Name -replace '[^a-zA-Z0-9]', '_'
    $code = Invoke-Winget -Arguments @("uninstall","--id",$App.ID,"--exact","--source",$App.Source,"--silent","--accept-source-agreements","--disable-interactivity") `
                          -LogFile "$LogDir\remove-$($App.Number)-$safe.log" -Label "Removing $($App.Name)"
    if ($code -eq 0) {
        Write-Status $G.Ok "Removed $($App.Name)" "Success"
        return (New-Result $App.Name "Removed")
    }
    Write-Status $G.Fail ("Failed to remove $($App.Name) (exit 0x{0:X8})" -f $code) "Error"
    return (New-Result $App.Name "Failed")
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
    param([string]$Dest)
    New-Item -ItemType Directory -Force -Path $Dest | Out-Null
    $ODTInstaller = "$Dest\ODT.exe"

    Write-Status $G.Arrow "Downloading Office Deployment Tool$($G.Ell)" "Warning"
    try {
        Invoke-WebRequest -Uri $ODTUrl -OutFile $ODTInstaller -UseBasicParsing
    } catch {
        Write-Status "!" "Download link stale $($G.Dash) resolving current ODT link" "Warning"
        try {
            $Page = Invoke-WebRequest -Uri $ODTFallbackPage -UseBasicParsing
            $FreshUrl = [regex]::Match($Page.Content, 'https://download\.microsoft\.com/download/[A-Za-z0-9\-]+/officedeploymenttool_[\w\-]+\.exe').Value
            if (-not $FreshUrl) { throw "Could not resolve a new ODT link from the download page." }
            Invoke-WebRequest -Uri $FreshUrl -OutFile $ODTInstaller -UseBasicParsing
        } catch {
            Write-Status $G.Fail "Failed to download ODT $($G.Dash) $($_.Exception.Message)" "Error"
            return $null
        }
    }

    $ExtractDir = "$Dest\ODT"
    New-Item -ItemType Directory -Force -Path $ExtractDir | Out-Null
    $proc = Start-Process -FilePath $ODTInstaller -ArgumentList "/quiet /extract:$ExtractDir" -Wait -PassThru
    if ($proc.ExitCode -ne 0) { Write-Status $G.Fail "ODT extraction failed" "Error"; return $null }

    $SetupExe = "$ExtractDir\setup.exe"
    if (-not (Test-Path $SetupExe)) { Write-Status $G.Fail "setup.exe not found after extraction" "Error"; return $null }
    return $SetupExe
}

function Install-Office {
    if (Test-OfficeInstalled) {
        Write-Status $G.Dot "Microsoft 365 $($G.Dash) already installed" "Existing"
        return (New-Result "Microsoft 365 (Word + Excel + PowerPoint)" "Already Installed")
    }
    $name = "Microsoft 365 (Word + Excel + PowerPoint)"
    $dir = "$TempDir\Office"
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue }

    $setup = Expand-ODT -Dest $dir
    if (-not $setup) { return (New-Result $name "Failed") }

    $cfg = "$dir\configuration.xml"
    Get-OfficeConfig | Out-File -FilePath $cfg -Encoding UTF8

    Write-Status $G.Arrow "Installing Word, Excel and PowerPoint (this can take a while)$($G.Ell)" "Accent"
    $p = Start-Process -FilePath $setup -ArgumentList "/configure `"$cfg`"" -PassThru -WindowStyle Hidden
    $null = $p.Handle
    $sw = [Diagnostics.Stopwatch]::StartNew(); $i = 0
    while (-not $p.HasExited) {
        [Console]::Write("`r$ESC[K  " + (Paint $SpinFrames[$i % $SpinFrames.Count] "Accent") + "  " + (Paint "Microsoft 365" "Title") + (Paint ("   " + (Format-Time $sw.Elapsed)) "Muted"))
        $i++; Start-Sleep -Milliseconds 120
    }
    $p.WaitForExit(); [Console]::Write("`r$ESC[K")

    if ($p.ExitCode -eq 0) {
        Write-Status $G.Ok "Microsoft 365 installed" "Success"
        return (New-Result $name "Installed")
    }
    Write-Status $G.Fail "Microsoft 365 install failed (exit $($p.ExitCode))" "Error"
    return (New-Result $name "Failed")
}

function Remove-Office {
    $name = "Microsoft 365 (Word + Excel + PowerPoint)"
    $dir = "$TempDir\OfficeRemove"
    try {
        $setup = Expand-ODT -Dest $dir
        if (-not $setup) { throw "Could not prepare the Office Deployment Tool." }
        $cfg = "$dir\remove.xml"
        Get-OfficeRemoveConfig | Out-File -FilePath $cfg -Encoding UTF8
        $p = Start-Process -FilePath $setup -ArgumentList "/configure `"$cfg`"" -Wait -PassThru
        if ($p.ExitCode -eq 0) {
            Write-Status $G.Ok "Microsoft 365 removed" "Success"
            return (New-Result $name "Removed")
        }
        Write-Status $G.Fail "Office removal returned exit $($p.ExitCode)" "Error"
    } catch {
        Write-Status $G.Fail "Office removal failed $($G.Dash) $($_.Exception.Message)" "Error"
    }
    return (New-Result $name "Failed")
}

# ============================================================
#  HERMES AGENT
# ============================================================

function Test-HermesInstalled {
    if (Get-Command hermes -ErrorAction SilentlyContinue) { return $true }
    if (Test-Path "$env:LOCALAPPDATA\hermes\bin\hermes.cmd") { return $true }
    if (Test-Path "$env:LOCALAPPDATA\hermes\bin\hermes.exe") { return $true }
    return (Test-Path "$env:LOCALAPPDATA\hermes\hermes-agent")
}

function Install-Hermes {
    $name = "Hermes Agent (Nous Research CLI)"
    if (Test-HermesInstalled) {
        Write-Status $G.Dot "Hermes Agent $($G.Dash) already installed" "Existing"
        return (New-Result $name "Already Installed")
    }

    Write-Status $G.Arrow "Downloading Hermes Agent installer$($G.Ell)" "Accent"
    $log = "$LogDir\19-Hermes_Agent.log"
    $ps1 = "$TempDir\hermes-install.ps1"
    try { Invoke-WebRequest -Uri $HermesInstallUrl -OutFile $ps1 -UseBasicParsing }
    catch {
        Write-Status $G.Fail "Failed to download Hermes installer $($G.Dash) $($_.Exception.Message)" "Error"
        return (New-Result $name "Failed")
    }

    Write-Status $G.Arrow "Installing Hermes Agent (interactive onboarding may prompt below)" "Accent"
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ps1 2>&1 | Tee-Object -FilePath $log | Out-Host
        $exit = $LASTEXITCODE
        if (($exit -eq 0) -and (Test-HermesInstalled)) {
            Write-Status $G.Ok "Hermes Agent installed  (start it with: hermes)" "Success"
            return (New-Result $name "Installed")
        }
        Write-Status $G.Fail "Hermes Agent install failed (exit $exit) $($G.Dash) see $log" "Error"
    } catch {
        Write-Status $G.Fail "Hermes Agent install failed $($G.Dash) $($_.Exception.Message)" "Error"
    }
    return (New-Result $name "Failed")
}

function Remove-Hermes {
    $name = "Hermes Agent (Nous Research CLI)"
    if (-not (Test-HermesInstalled)) {
        Write-Status $G.Dot "Hermes Agent $($G.Dash) not installed" "Existing"
        return (New-Result $name "Not Installed")
    }
    try {
        & hermes uninstall | Out-Host
        if ($LASTEXITCODE -eq 0) {
            Write-Status $G.Ok "Hermes Agent removed" "Success"
            return (New-Result $name "Removed")
        }
        Write-Status $G.Fail "hermes uninstall returned exit $LASTEXITCODE" "Error"
    } catch {
        Write-Status $G.Fail "Failed to remove Hermes Agent $($G.Dash) $($_.Exception.Message)" "Error"
    }
    return (New-Result $name "Failed")
}

# ============================================================
#  EVOFOX PHANTOM AIR MOUSE SOFTWARE
# ============================================================

function Get-EvoFoxEntry {
    $Keys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    try { Get-ItemProperty $Keys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match "EvoFox Phantom" } | Select-Object -First 1 } catch { $null }
}

function Test-EvoFoxInstalled {
    if (Get-EvoFoxEntry) { return $true }
    return (Test-Path "$EvoFoxInstallDir\Gaming Mouse 3.0.exe")
}

function Install-EvoFox {
    $name = "EvoFox Phantom Air Mouse Software"
    if (Test-EvoFoxInstalled) {
        Write-Status $G.Dot "EvoFox Phantom Air software $($G.Dash) already installed" "Existing"
        return (New-Result $name "Already Installed")
    }

    Write-Status $G.Arrow "Downloading EvoFox Phantom Air software$($G.Ell)" "Accent"
    $log = "$LogDir\20-EvoFox_Phantom_Air.log"
    $exe = "$TempDir\EvoFox_Phantom_Air_Gaming_Mouse.exe"
    try { Invoke-WebRequest -Uri $EvoFoxUrl -OutFile $exe -UseBasicParsing }
    catch {
        Write-Status $G.Fail "Failed to download $($G.Dash) $($_.Exception.Message)" "Error"
        Say ("  " + (Paint "Manual download: $EvoFoxHelpPage" "Muted"))
        return (New-Result $name "Failed")
    }

    Write-Status $G.Arrow "Installing EvoFox Phantom Air software$($G.Ell)" "Accent"
    try {
        # The same exe flips into uninstall mode when already installed - hence the check above.
        $p = Start-Process -FilePath $exe -ArgumentList "/VERYSILENT","/SUPPRESSMSGBOXES","/NORESTART","/LOG=`"$log`"" -Wait -PassThru
        if (($p.ExitCode -eq 0) -and (Test-EvoFoxInstalled)) {
            Write-Status $G.Ok "EvoFox Phantom Air software installed" "Success"
            Say ("  " + (Paint "Configure the mouse with: $EvoFoxInstallDir\Gaming Mouse 3.0.exe" "Muted"))
            return (New-Result $name "Installed")
        }
        Write-Status $G.Fail "Install failed (exit $($p.ExitCode)) $($G.Dash) see $log" "Error"
    } catch {
        Write-Status $G.Fail "Install failed $($G.Dash) $($_.Exception.Message)" "Error"
    }
    return (New-Result $name "Failed")
}

function Remove-EvoFox {
    $name = "EvoFox Phantom Air Mouse Software"
    if (-not (Test-EvoFoxInstalled)) {
        Write-Status $G.Dot "EvoFox Phantom Air software $($G.Dash) not installed" "Existing"
        return (New-Result $name "Not Installed")
    }
    try {
        $entry = Get-EvoFoxEntry
        $un = if ($entry -and $entry.UninstallString) { $entry.UninstallString.Trim('"') } else { "$EvoFoxInstallDir\unins000.exe" }
        if (-not (Test-Path $un)) {
            Write-Status $G.Fail "Uninstaller not found at $un" "Error"
            return (New-Result $name "Failed")
        }
        $p = Start-Process -FilePath $un -ArgumentList "/SILENT","/SUPPRESSMSGBOXES","/NORESTART" -Wait -PassThru
        if ($p.ExitCode -eq 0) {
            Write-Status $G.Ok "EvoFox Phantom Air software removed" "Success"
            return (New-Result $name "Removed")
        }
        Write-Status $G.Fail "Uninstall returned exit $($p.ExitCode)" "Error"
    } catch {
        Write-Status $G.Fail "Failed to remove $($G.Dash) $($_.Exception.Message)" "Error"
    }
    return (New-Result $name "Failed")
}

# ============================================================
#  DEVELOPMENT ENVIRONMENT
# ============================================================

function Configure-Development {
    Write-Panel -Title "Development Environment" -Color "Accent"
    Refresh-Path
    $devLog = "$LogDir\dev-environment.log"

    if (Get-Command python -ErrorAction SilentlyContinue) {
        Write-Status $G.Arrow "Updating pip / setuptools / wheel$($G.Ell)" "Warning"
        python -m pip install --upgrade pip setuptools wheel --disable-pip-version-check -q 2>&1 | Out-File $devLog -Append

        $pk = @("requests","httpx","flask","fastapi","uvicorn","pandas","numpy","matplotlib","openpyxl","pillow","rich","python-dotenv","beautifulsoup4","lxml","psutil")
        Write-Status $G.Arrow "Installing common Python packages$($G.Ell)" "Warning"
        python -m pip install $pk --disable-pip-version-check -q 2>&1 | Out-File $devLog -Append
        Write-Status $G.Ok "Python tooling ready" "Success"
    }

    if (Get-Command node -ErrorAction SilentlyContinue) {
        Write-Status $G.Arrow "Installing pnpm and yarn$($G.Ell)" "Warning"
        npm install -g pnpm yarn 2>&1 | Out-File $devLog -Append
        Write-Status $G.Ok "pnpm / yarn ready" "Success"
    }

    if (Get-Command git -ErrorAction SilentlyContinue) {
        Write-Status $G.Arrow "Configuring Git$($G.Ell)" "Accent"
        if (-not $Yes) {
            [Console]::Write("$ESC[?25h")
            if (-not (git config --global user.name))  { $n = Read-Host "  Git user.name";  if ($n) { git config --global user.name "$n" } }
            if (-not (git config --global user.email)) { $e = Read-Host "  Git user.email"; if ($e) { git config --global user.email "$e" } }
        }
        git config --global init.defaultBranch main
        git config --global core.autocrlf true
        Write-Status $G.Ok "Git configured" "Success"
    }

    try {
        New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Value 1 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
    } catch {}
    [Environment]::SetEnvironmentVariable("PYTHONUTF8", "1", "User")
    Write-Status $G.Ok "Long paths + PYTHONUTF8 enabled" "Success"
    Write-Status $G.Ok "Development environment ready" "Success"
}

# ============================================================
#  ORCHESTRATION
# ============================================================

function Start-Installation {
    param([array]$SelectedApps,[switch]$NoDev)

    $start = Get-Date
    $total = $SelectedApps.Count
    $cur = 0
    $script:Results = @()

    foreach ($app in $SelectedApps) {
        $cur++
        Say ""
        Write-Rule
        Say ("  " + (Get-Bar $cur $total) + (Paint "   $cur/$total" "Muted") + (Paint "   elapsed $(Format-Time ((Get-Date) - $start))" "Muted"))
        Say ("  " + (Paint $G.Arrow "Accent") + " " + (Paint $app.Name "Title"))
        Say ""

        $r = switch ($app.ID) {
            "OFFICE" { Install-Office }
            "HERMES" { Install-Hermes }
            "EVOFOX" { Install-EvoFox }
            default  { Install-App -App $app }
        }
        # Guard: functions may emit stray pipeline output; keep only the result object.
        $r = @($r | Where-Object { $_ -and $_.PSObject.Properties["Status"] }) | Select-Object -Last 1
        if (-not $r) { $r = New-Result $app.Name "Failed" }
        $script:Results += $r

        $el = (Get-Date) - $start
        $eta = [TimeSpan]::FromSeconds(($el.TotalSeconds / $cur) * ($total - $cur))
        Say ("  " + (Paint "ETA $(Format-Time $eta)" "Dim"))
    }

    Refresh-Path
    if (-not $NoDev) { Write-Rule; Configure-Development }
    Show-Summary -Title "INSTALLATION COMPLETE" -Start $start
    $script:LastFailed = @($script:Results | Where-Object Status -eq "Failed" | ForEach-Object { $n = $_.Name; $Apps | Where-Object Name -eq $n })
}

function Start-Removal {
    param([array]$SelectedApps)
    $start = Get-Date; $total = $SelectedApps.Count; $cur = 0
    $script:Results = @()
    foreach ($app in $SelectedApps) {
        $cur++
        Say ""
        Write-Rule
        Say ("  " + (Get-Bar $cur $total) + (Paint "   $cur/$total" "Muted"))
        Say ""
        $r = @(Remove-App -App $app | Where-Object { $_ -and $_.PSObject.Properties["Status"] }) | Select-Object -Last 1
        if (-not $r) { $r = New-Result $app.Name "Failed" }
        $script:Results += $r
    }
    Show-Summary -Title "REMOVAL COMPLETE" -Start $start
}

function Show-Summary {
    param([string]$Title,[datetime]$Start)

    $el = (Get-Date) - $Start
    $count = { param($s) @($script:Results | Where-Object Status -eq $s).Count }
    Write-Panel -Title $Title -Subtitle "Total time $(Format-Time $el)" -Color "Success"

    Say ("  {0,-20}{1}" -f "Total selected", $script:Results.Count)
    $rows = @(
        @("Installed", "Installed", "Success"), @("Removed", "Removed", "Success"),
        @("Already installed", "Already Installed", "Existing"), @("Not installed", "Not Installed", "Existing"),
        @("Failed", "Failed", "Error")
    )
    foreach ($r in $rows) {
        $n = & $count $r[1]
        if ($n -gt 0) { Say ("  " + (Paint ("{0,-20}{1}" -f $r[0], $n) $r[2])) }
    }
    Say ""
    Write-Rule
    foreach ($r in $script:Results) {
        switch ($r.Status) {
            { $_ -in "Installed","Removed" } { Write-Status $G.Ok $r.Name "Success" }
            { $_ -in "Already Installed","Not Installed" } { Write-Status $G.Dot "$($r.Name)  ($($r.Status.ToLower()))" "Existing" }
            "Failed" { Write-Status $G.Fail $r.Name "Error" }
            default  { Write-Status "?" $r.Name "Muted" }
        }
    }
    if (@($script:Results | Where-Object Status -eq "Failed").Count -gt 0) {
        Say ""
        Say ("  " + (Paint "Some items failed. Use 'Retry failed' from the main menu. Logs: $LogDir" "Error"))
    }
    Say ("  " + (Paint "Session log: $LogFile" "Dim"))
}

function Read-AppSelection {
    # "1,4,7-9,18" -> matching apps (supports ranges)
    param([string]$Choice)
    $nums = @()
    foreach ($tok in ($Choice -split "[,\s]+" | Where-Object { $_ })) {
        if ($tok -match "^(\d+)-(\d+)$") { $nums += [int]$Matches[1]..[int]$Matches[2] }
        elseif ($tok -match "^\d+$")      { $nums += [int]$tok }
    }
    @($Apps | Where-Object { $nums -contains $_.Number })
}

# ============================================================
#  TUI: HEADER, MENU, PICKER
# ============================================================

function Get-HeaderLines {
    $w = (Get-W) - 2
    $title = "F R E S H   W I N D O W S   S E T U P"
    $sub = "v$($script:Version)  $($G.Mid)  WinGet + ODT  $($G.Mid)  $($Apps.Count) apps  $($G.Mid)  terminal edition"
    $row = { param($content,$vis)
        $n = $w - $vis; $l = [math]::Floor($n / 2)
        "  " + (Paint $G.V "Accent") + (" " * $l) + $content + (" " * ($n - $l)) + (Paint $G.V "Accent") }
    @(
        ("  " + (Paint ("$($G.TL)" + ([string]$G.H * $w) + "$($G.TR)") "Accent")),
        (& $row (Get-Gradient $title @(56,189,248) @(167,139,250)) $title.Length),
        (& $row (Paint $sub "Muted") $sub.Length),
        ("  " + (Paint ("$($G.BL)" + ([string]$G.H * $w) + "$($G.BR)") "Accent"))
    )
}

function Format-Selected([string]$Row,[int]$w) {
    $P.BgSel + $Row.Replace($P.Reset, $P.Reset + $P.BgSel) + (" " * [math]::Max(0, $w - (Get-VisLen $Row))) + $P.Reset
}

function Show-Menu {
    param([string]$Title,[string]$Subtitle = "",[array]$Items)
    $idx = 0
    while ($true) {
        $w = (Get-W) + 2
        $L = New-Object System.Collections.ArrayList
        foreach ($h in (Get-HeaderLines)) { [void]$L.Add($h) }
        [void]$L.Add("")
        [void]$L.Add("  " + (Paint $Title "Title") + $(if ($Subtitle) { "  " + (Paint $Subtitle "Muted") } else { "" }))
        [void]$L.Add("")
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $it  = $Items[$i]
            $hot = if ($it.Hot) { "[$($it.Hot)]" } else { "   " }
            $lab = $it.Label.PadRight(24)
            if ($i -eq $idx) {
                $row = "  " + (Paint $G.Ptr "Accent") + " " + (Paint $hot "Muted") + " " + "$($P.Bold)$($P.Title)$lab$($P.Reset)" + (Paint (Fit $it.Desc ($w - 38)) "Muted")
                [void]$L.Add((Format-Selected $row $w))
            } else {
                $col = if ($it.Dim) { "Dim" } else { "Title" }
                [void]$L.Add("    " + (Paint $hot "Dim") + " " + (Paint $lab $col) + (Paint (Fit $it.Desc ($w - 38)) "Dim"))
            }
        }
        [void]$L.Add("")
        [void]$L.Add("  " + (Paint "$($G.Up)$($G.Down) navigate   Enter select   hotkey jump   Esc back/quit" "Dim"))
        Show-Frame $L

        $k = [Console]::ReadKey($true)
        switch ($k.Key) {
            "UpArrow"   { $idx = ($idx - 1 + $Items.Count) % $Items.Count; continue }
            "DownArrow" { $idx = ($idx + 1) % $Items.Count; continue }
            "Home"      { $idx = 0; continue }
            "End"       { $idx = $Items.Count - 1; continue }
            "Enter"     { return $Items[$idx].Key }
            "Escape"    { return $null }
        }
        $ch = [string]$k.KeyChar
        if ($ch) { foreach ($it in $Items) { if ($it.Hot -and ($it.Hot -ieq $ch)) { return $it.Key } } }
    }
}

function Show-Picker {
    param([ValidateSet("Install","Remove")][string]$Mode)

    $cats = @("All") + @($Apps | ForEach-Object { $_.Category } | Select-Object -Unique | Sort-Object)
    $catIdx = 0; $filter = ""; $searching = $false; $cursor = 0; $top = 0; $msg = ""
    $sel = New-Object 'System.Collections.Generic.HashSet[int]'
    $accent = if ($Mode -eq "Remove") { "Error" } else { "Accent" }

    while ($true) {
        $w = (Get-W) + 2
        $cat = $cats[$catIdx]
        $vis = @($Apps | Where-Object {
            ($cat -eq "All" -or $_.Category -eq $cat) -and
            ([string]::IsNullOrWhiteSpace($filter) -or ("$($_.Name) $($_.ID) $($_.Category)").IndexOf($filter, [StringComparison]::OrdinalIgnoreCase) -ge 0)
        })
        if ($cursor -ge $vis.Count) { $cursor = [math]::Max(0, $vis.Count - 1) }
        $rows = [math]::Max(5, (Get-H) - 14)
        if ($cursor -lt $top) { $top = $cursor }
        if ($cursor -ge $top + $rows) { $top = $cursor - $rows + 1 }
        if ($top -lt 0) { $top = 0 }

        $L = New-Object System.Collections.ArrayList
        foreach ($h in (Get-HeaderLines)) { [void]$L.Add($h) }
        [void]$L.Add("")
        $ttl = if ($Mode -eq "Remove") { "Remove applications" } else { "Install applications" }
        [void]$L.Add("  " + (Paint $ttl $accent) + "   " + (Paint "$($sel.Count) selected" "Title") + (Paint "  of $($Apps.Count)" "Muted"))
        $cur = if ($searching) { "$($P.Accent)|$($P.Reset)" } else { "" }
        $fText = if ($filter -or $searching) { (Paint $filter "Title") + $cur } else { (Paint "press / to search" "Dim") }
        [void]$L.Add("  " + (Paint "Search" "Muted") + "  " + $fText)
        [void]$L.Add("  " + (Paint "Category" "Muted") + "  " + (Paint $G.Back "Dim") + " " + (Paint $cat "Accent2") + " " + (Paint $G.Fwd "Dim") + (Paint "   (Tab to change)" "Dim"))
        [void]$L.Add("")

        $nameW = $w - 44
        if ($vis.Count -eq 0) { [void]$L.Add("  " + (Paint "No applications match." "Muted")) }
        $end = [math]::Min($vis.Count, $top + $rows)
        for ($i = $top; $i -lt $end; $i++) {
            $a = $vis[$i]
            $on = $sel.Contains($a.Number)
            $mark = if ($on) { Paint $G.On "Success" } else { Paint $G.Off "Dim" }
            $st = Get-InstallState $a
            $stText = ""
            if ($Mode -eq "Install" -and $st -eq $true)  { $stText = Paint "$($G.Ok) installed" "Existing" }
            if ($Mode -eq "Remove"  -and $st -eq $false) { $stText = Paint "not installed" "Dim" }
            if ($Mode -eq "Remove"  -and $st -eq $true)  { $stText = Paint "$($G.Ok) installed" "Success" }
            $nameCol = if ($on) { "Title" } else { "Muted" }
            $ptr = if ($i -eq $cursor) { Paint $G.Ptr $accent } else { " " }
            $row = "  $ptr $mark " + (Paint ("{0,2}" -f $a.Number) "Dim") + "  " + (Paint (Fit $a.Name $nameW).PadRight($nameW) $nameCol) + " " + (Paint $a.Category.PadRight(14) "Dim") + $stText
            if ($i -eq $cursor) { $row = Format-Selected $row $w }
            [void]$L.Add($row)
        }
        for ($pad = $end - $top; $pad -lt $rows -and $vis.Count -gt 0; $pad++) { [void]$L.Add("") }

        $more = if ($vis.Count -gt $rows) { "$($top + 1)-$end of $($vis.Count)" } else { "$($vis.Count) shown" }
        [void]$L.Add("  " + (Paint $more "Dim") + $(if ($msg) { "   " + (Paint $msg "Warning") } else { "" }))
        [void]$L.Add("")
        if ($searching) {
            [void]$L.Add("  " + (Paint "type to filter   Enter/Esc finish   Backspace delete" "Dim"))
        } else {
            [void]$L.Add("  " + (Paint "Space toggle  A all  N none  / search  Tab category  R rescan  Enter confirm  Esc back" "Dim"))
        }
        Show-Frame $L
        $msg = ""

        $k = [Console]::ReadKey($true)

        if ($searching) {
            switch ($k.Key) {
                { $_ -in "Enter","Escape" } { $searching = $false; continue }
                "Backspace" { if ($filter.Length -gt 0) { $filter = $filter.Substring(0, $filter.Length - 1); $cursor = 0; $top = 0 }; continue }
                default { if ($k.KeyChar -and -not [char]::IsControl($k.KeyChar)) { $filter += $k.KeyChar; $cursor = 0; $top = 0 } }
            }
            continue
        }

        switch ($k.Key) {
            "UpArrow"   { if ($cursor -gt 0) { $cursor-- }; continue }
            "DownArrow" { if ($cursor -lt $vis.Count - 1) { $cursor++ }; continue }
            "PageUp"    { $cursor = [math]::Max(0, $cursor - $rows); continue }
            "PageDown"  { $cursor = [math]::Min([math]::Max(0, $vis.Count - 1), $cursor + $rows); continue }
            "Home"      { $cursor = 0; continue }
            "End"       { $cursor = [math]::Max(0, $vis.Count - 1); continue }
            "Spacebar"  {
                if ($vis.Count -gt 0) {
                    $n = $vis[$cursor].Number
                    if ($sel.Contains($n)) { [void]$sel.Remove($n) } else { [void]$sel.Add($n) }
                    if ($cursor -lt $vis.Count - 1) { $cursor++ }
                }
                continue
            }
            "Tab" {
                $dir = if ($k.Modifiers -band [ConsoleModifiers]::Shift) { -1 } else { 1 }
                $catIdx = ($catIdx + $dir + $cats.Count) % $cats.Count; $cursor = 0; $top = 0; continue
            }
            "Enter" {
                if ($sel.Count -eq 0) { $msg = "Select at least one app (Space)."; continue }
                return @($Apps | Where-Object { $sel.Contains($_.Number) })
            }
            "Escape" { if ($filter) { $filter = ""; $cursor = 0; $top = 0; continue } else { return $null } }
        }
        switch ([string]$k.KeyChar) {
            { $_ -ieq "a" } { foreach ($a in $vis) { [void]$sel.Add($a.Number) } }
            { $_ -ieq "n" } { $sel.Clear() }
            { $_ -ieq "q" } { return $null }
            { $_ -ieq "r" } { Show-Frame @(""); Update-InstalledCache }
            "/"             { $searching = $true }
        }
    }
}

function Show-Confirm {
    # Returns $true when confirmed. $Danger requires typing REMOVE.
    param([string]$Title,[array]$Selected,[switch]$Danger)
    $w = (Get-W) + 2
    $L = New-Object System.Collections.ArrayList
    foreach ($h in (Get-HeaderLines)) { [void]$L.Add($h) }
    [void]$L.Add("")
    [void]$L.Add("  " + (Paint $Title $(if ($Danger) { "Error" } else { "Accent" })))
    [void]$L.Add("")
    $max = [math]::Max(4, (Get-H) - 13)
    $shown = @($Selected | Select-Object -First $max)
    foreach ($a in $shown) { [void]$L.Add("    " + (Paint $G.On $(if ($Danger) { "Error" } else { "Success" })) + " " + (Paint (Fit $a.Name ($w - 10)) "Title")) }
    if ($Selected.Count -gt $shown.Count) { [void]$L.Add("    " + (Paint "$($G.Ell) and $($Selected.Count - $shown.Count) more" "Muted")) }
    [void]$L.Add("")
    if ($Danger) {
        [void]$L.Add("  " + (Paint "Type REMOVE and press Enter to confirm (anything else cancels): " "Warning"))
        Show-Frame $L
        [Console]::Write("$ESC[?25h")
        $ans = [Console]::ReadLine()
        [Console]::Write("$ESC[?25l")
        return ($ans -ceq "REMOVE")
    }
    [void]$L.Add("  " + (Paint "Start now?  [Y]es / [N]o" "Warning"))
    Show-Frame $L
    while ($true) {
        $k = [Console]::ReadKey($true)
        if ($k.Key -eq "Enter" -or $k.KeyChar -ieq "y") { return $true }
        if ($k.Key -eq "Escape" -or $k.KeyChar -ieq "n") { return $false }
    }
}

function Wait-AnyKey([string]$Text = "Press any key to return to the menu") {
    Say ""
    Say ("  " + (Paint $Text "Muted"))
    [void][Console]::ReadKey($true)
}

# ============================================================
#  OPERATIONS (leave the TUI, stream output, come back)
# ============================================================

function Invoke-Operation {
    param([ValidateSet("Install","Remove")][string]$Mode,[array]$Selected)

    if ($Mode -eq "Remove") {
        if (-not (Show-Confirm -Title "Remove $($Selected.Count) application(s)?" -Selected $Selected -Danger)) { return }
    } else {
        if (-not (Show-Confirm -Title "Install $($Selected.Count) application(s)?" -Selected $Selected)) { return }
    }

    Leave-Screen
    Clear-Host
    Write-Panel -Title $(if ($Mode -eq "Remove") { "REMOVING APPLICATIONS" } else { "INSTALLING APPLICATIONS" }) `
                -Subtitle "$($Selected.Count) selected $($G.Mid) log: $LogFile" -Color $(if ($Mode -eq "Remove") { "Error" } else { "Accent" })
    Write-Log "== $Mode : $(($Selected | ForEach-Object Name) -join ', ')"

    if ($Mode -eq "Remove") { Start-Removal -SelectedApps $Selected } else { Start-Installation -SelectedApps $Selected }

    Wait-AnyKey
    Enter-Screen
    Show-Frame @("", "  " + (Paint "Refreshing installed apps$($G.Ell)" "Muted"))
    Update-InstalledCache
}

function Invoke-ScreenTask([string]$Title,[scriptblock]$Body) {
    Leave-Screen
    Clear-Host
    Write-Panel -Title $Title -Color "Accent"
    try { & $Body } catch { Write-Status $G.Fail $_.Exception.Message "Error" }
    Wait-AnyKey
    Enter-Screen
}

function Start-ExternalTool {
    param([string]$Name,[string]$Url,[string]$Hint)
    Invoke-ScreenTask $Name {
        Say ("  " + (Paint $Hint "Muted"))
        Say ""
        Say ("  " + (Paint "This downloads and runs a remote script:" "Warning"))
        Say ("  " + (Paint "irm $Url | iex" "Title"))
        Say ""
        [Console]::Write("$ESC[?25h  Continue? [y/N] ")
        $k = [Console]::ReadKey($true); Say $k.KeyChar
        [Console]::Write("$ESC[?25l")
        if ($k.KeyChar -ine "y") { Say ("  " + (Paint "Cancelled." "Muted")); return }
        Say ("  " + (Paint "Launching in an elevated child PowerShell session$($G.Ell)" "Accent"))
        $proc = Start-Process powershell.exe -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-Command","irm $Url | iex") -PassThru -Wait
        if ($proc.ExitCode -eq 0) { Write-Status $G.Ok "$Name session ended" "Success" }
        else { Write-Status "!" "$Name exited with code $($proc.ExitCode) (non-zero can be normal)" "Warning" }
    }.GetNewClosure()
}

function Export-Settings {
    Invoke-ScreenTask "Export Settings" {
        $dest = Join-Path $SetupRoot ("Exports\" + (Get-Date -Format "yyyy-MM-dd_HH-mm-ss"))
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        Write-Status $G.Arrow "Exporting registry preferences$($G.Ell)" "Accent"
        reg.exe export 'HKCU\Control Panel\Desktop' "$dest\desktop.reg" /y | Out-Null
        reg.exe export 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer' "$dest\explorer.reg" /y | Out-Null
        reg.exe export 'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes' "$dest\themes.reg" /y | Out-Null
        Write-Status $G.Arrow "Exporting optional features and wallpaper$($G.Ell)" "Accent"
        Get-CimInstance Win32_OptionalFeature | Where-Object InstallState -eq 1 | Select-Object Name,InstallState | Export-Csv "$dest\optional-features.csv" -NoTypeInformation
        (Get-ItemProperty 'HKCU:\Control Panel\Desktop' -ErrorAction SilentlyContinue).WallPaper | Out-File "$dest\wallpaper.txt" -Encoding UTF8
        Write-Status $G.Arrow "Exporting installed app list (winget)$($G.Ell)" "Accent"
        [void](Invoke-Winget -Arguments @("export","-o","$dest\winget-apps.json","--accept-source-agreements","--disable-interactivity") -Label "winget export")
        Write-Status $G.Ok "Exported to $dest" "Success"
    }.GetNewClosure()
}

function Show-Logs {
    $files = @(Get-ChildItem $LogDir -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 12)
    if ($files.Count -eq 0) { return }
    $items = @(); $i = 0
    foreach ($f in $files) { $i++; $items += [PSCustomObject]@{ Key = $f.FullName; Label = (Fit $f.Name 24); Desc = $f.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss") + "  " + ("{0:N0} KB" -f ($f.Length / 1KB)); Hot = $(if ($i -le 9) { "$i" } else { "" }) } }
    $pick = Show-Menu -Title "Logs" -Subtitle $LogDir -Items $items
    if (-not $pick) { return }
    $w = (Get-W) + 2
    $L = New-Object System.Collections.ArrayList
    foreach ($h in (Get-HeaderLines)) { [void]$L.Add($h) }
    [void]$L.Add("")
    [void]$L.Add("  " + (Paint (Split-Path $pick -Leaf) "Accent"))
    [void]$L.Add("")
    $n = [math]::Max(5, (Get-H) - 10)
    foreach ($line in @(Get-Content $pick -Tail $n -ErrorAction SilentlyContinue)) { [void]$L.Add("  " + (Paint (Fit ([string]$line) ($w - 4)) "Muted")) }
    [void]$L.Add("")
    [void]$L.Add("  " + (Paint "Press any key to go back" "Dim"))
    Show-Frame $L
    [void][Console]::ReadKey($true)
}

# ============================================================
#  STARTUP + MAIN
# ============================================================

function Assert-SetupEnvironment {
    if ($Host.Name -match "ISE") {
        Write-Host "This terminal UI needs a real console. Run it in Windows Terminal / PowerShell, not the ISE." -ForegroundColor Red
        exit 1
    }
    if (-not (Test-Admin)) {
        Write-Panel -Title "ADMINISTRATOR REQUIRED" -Subtitle "Relaunch PowerShell as Administrator" -Color "Error"
        if (-not $Yes) { Read-Host "Press Enter to exit" | Out-Null }
        exit 1
    }
    if (-not (Test-Winget)) {
        Write-Panel -Title "WINGET NOT FOUND" -Subtitle "Install/update App Installer from the Microsoft Store" -Color "Error"
        if (-not $Yes) { Read-Host "Press Enter to exit" | Out-Null }
        exit 1
    }
}

# ---- Headless modes ----------------------------------------------------------
if ($List) {
    foreach ($a in $Apps) { Say ("{0,3}  {1,-48} {2,-14} {3}" -f $a.Number, $a.Name, $a.Category, $a.Source) }
    exit 0
}

Assert-SetupEnvironment
Write-Log "Session started (v$($script:Version))"

if ($Full -or $Install -or $Remove) {
    Write-Panel -Title "FRESH WINDOWS SETUP" -Subtitle "headless mode" -Color "Accent"
    Initialize-Winget
    Update-InstalledCache
    if ($Remove) {
        $sel = Read-AppSelection -Choice $Remove
        if ($sel.Count -eq 0) { Say "No matching applications."; exit 2 }
        if (-not $Yes) { if ((Read-Host "Type REMOVE to confirm removal of $($sel.Count) app(s)") -cne "REMOVE") { exit 0 } }
        Start-Removal -SelectedApps $sel
    } else {
        $sel = if ($Full) { $Apps } else { Read-AppSelection -Choice $Install }
        if ($sel.Count -eq 0) { Say "No matching applications."; exit 2 }
        Start-Installation -SelectedApps $sel -NoDev:$SkipDev
    }
    exit $(if (@($script:Results | Where-Object Status -eq "Failed").Count -gt 0) { 1 } else { 0 })
}

# ---- Interactive TUI -----------------------------------------------------------
Clear-Host
Write-Panel -Title "FRESH WINDOWS SETUP" -Subtitle "starting up" -Color "Accent"
Initialize-Winget
Update-InstalledCache

try {
    Enter-Screen
    while ($true) {
        $failed = @($script:LastFailed).Count
        $installedCount = if ($script:Installed) { @($Apps | Where-Object { (Get-InstallState $_) -eq $true }).Count } else { "?" }
        $items = @(
            [PSCustomObject]@{ Key="install"; Hot="I"; Label="Install applications"; Desc="Pick apps from the catalog ($installedCount of $($Apps.Count) already installed)" }
            [PSCustomObject]@{ Key="full";    Hot="F"; Label="Full installation";    Desc="Install the complete workstation profile" }
            [PSCustomObject]@{ Key="remove";  Hot="R"; Label="Remove applications";  Desc="Uninstall selected apps" }
            [PSCustomObject]@{ Key="retry";   Hot="T"; Label="Retry failed";         Desc=$(if ($failed) { "$failed app(s) failed last run" } else { "Nothing to retry" }); Dim=(-not $failed) }
            [PSCustomObject]@{ Key="dev";     Hot="D"; Label="Dev environment";      Desc="pip packages, pnpm/yarn, Git config, long paths, UTF-8" }
            [PSCustomObject]@{ Key="winutil"; Hot="W"; Label="Chris Titus WinUtil";  Desc="Tweaks, debloat and updates (remote script)" }
            [PSCustomObject]@{ Key="mas";     Hot="M"; Label="MassGrave (MAS)";      Desc="Open the Microsoft Activation Scripts menu (remote script)" }
            [PSCustomObject]@{ Key="export";  Hot="E"; Label="Export settings";      Desc="Back up Explorer/theme prefs, features and app list" }
            [PSCustomObject]@{ Key="logs";    Hot="L"; Label="View logs";            Desc="Browse recent setup logs" }
            [PSCustomObject]@{ Key="quit";    Hot="Q"; Label="Quit";                 Desc="Exit the setup tool" }
        )
        $choice = Show-Menu -Title "Main menu" -Subtitle "choose an action" -Items $items
        if (-not $choice -or $choice -eq "quit") { break }

        switch ($choice) {
            "install" { $s = Show-Picker -Mode Install; if ($s) { Invoke-Operation -Mode Install -Selected $s } }
            "full"    { Invoke-Operation -Mode Install -Selected $Apps }
            "remove"  { $s = Show-Picker -Mode Remove;  if ($s) { Invoke-Operation -Mode Remove  -Selected $s } }
            "retry"   { if ($failed) { Invoke-Operation -Mode Install -Selected @($script:LastFailed) } }
            "dev"     { Invoke-ScreenTask "Development Environment" { Configure-Development } }
            "winutil" { Start-ExternalTool -Name "Chris Titus WinUtil" -Url $WinUtilUrl -Hint "Windows tweaks, debloat, fixes and updates." }
            "mas"     { Start-ExternalTool -Name "MassGrave (MAS)" -Url $MassGraveUrl -Hint "Pick one of the green (recommended) options in the menu that opens." }
            "export"  { Export-Settings }
            "logs"    { Show-Logs }
        }
    }
} finally {
    Leave-Screen
    Write-Log "Session ended"
}
Say ("  " + (Paint "Bye. Session log: $LogFile" "Muted"))
