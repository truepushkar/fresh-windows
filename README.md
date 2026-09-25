<div align="center">

# 🪟 Fresh Windows Setup

**An interactive, menu-driven workstation bootstrapper for freshly installed Windows 11/10 machines.**

One elevated PowerShell script installs your entire daily-driver toolkit — browsers, dev tools, messaging, Microsoft 365, and more — with live progress bars, ETAs, per-app logs, and a full summary at the end.

[![Platform](https://img.shields.io/badge/platform-Windows%2010%2F11-blue)](https://github.com/truepushkar/fresh-windows)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell)](https://github.com/PowerShell/PowerShell)
[![License](https://img.shields.io/badge/license-MIT-green)](#-license)

</div>

---

## ⚡ Quick Start

Open **PowerShell as Administrator**, then run the launcher:

```powershell
git clone https://github.com/truepushkar/fresh-windows.git
cd fresh-windows\INSTALLATION
.\Install-WindowsSetup.bat
```

Or, if you just want the raw script with no cloning:

```powershell
irm https://raw.githubusercontent.com/truepushkar/fresh-windows/main/INSTALLATION/Setup-Windows.ps1 | iex
```

> **Note:** the script refuses to run unelevated — it needs Administrator rights for machine-wide installs, registry tweaks, and launching WinUtil/MAS without a second UAC prompt.

---

## 🖥️ The Interface

A fully interactive terminal UI — no flags to memorize, no config files to edit:

```
                     FRESH WINDOWS SETUP
            Automated Windows workstation bootstrapper

  ╭──────────────────────────── MAIN MENU ────────────────────────────╮
  │                        Choose an operation                         │
  ╰────────────────────────────────────────────────────────────────────╯

  [1]  Full Installation
       Complete workstation setup

  [2]  Manual Installation
       Select applications

  [3]  Remove Applications
       Uninstall selected apps

  ...
```

Each install shows a live animated progress bar with per-app status, elapsed time, and ETA:

```
  ┌─ Progress ────────────────────────────────────────────┐
  │ ███████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
  │  33%    5 / 15                                       │
  └──────────────────────────────────────────────────────┘
  ➜ Installing Visual Studio Code…
```

---

## 📦 What It Installs

| # | App | Source |
|---|-----|--------|
| 1 | Telegram | WinGet |
| 2 | PowerToys | WinGet |
| 3 | Python 3.14 | WinGet |
| 4 | Visual Studio Code | WinGet |
| 5 | Spotify *(per-user scope)* | WinGet |
| 6 | WhatsApp | MS Store |
| 7 | Brave | WinGet |
| 8 | Google Chrome | WinGet |
| 9 | Git | WinGet |
| 10 | Cloudflare WARP | WinGet |
| 11 | Node.js LTS | WinGet |
| 12 | 7-Zip | WinGet |
| 13 | AB Download Manager | WinGet |
| 14 | VLC | WinGet |
| 15 | FFmpeg | WinGet |
| 16 | GitHub CLI | WinGet |
| 17 | PowerShell 7 | WinGet |
| 18 | Microsoft 365 (Word · Excel · PowerPoint) | Office Deployment Tool |
| 19 | Hermes Agent *(Nous Research CLI)* | Official installer |
| 20 | EvoFox Phantom Air mouse software | Amkette direct download |

**Bonus dev-environment setup** (runs automatically after installs):

- Upgrades `pip`, `setuptools`, `wheel`
- Installs common Python packages (`requests`, `flask`, `fastapi`, `pandas`, `numpy`, `rich`, …)
- Installs `pnpm` + `yarn` globally via npm
- Configures Git identity (`user.name` / `user.email`), `init.defaultBranch=main`, `core.autocrlf`
- Enables Windows **long paths** (>260 char paths)
- Sets `PYTHONUTF8=1`

---

## 🧩 Integrated Tools

Two extra entries in the main menu launch trusted external utilities (elevated, no second UAC prompt):

### [5] WinUtil — Chris Titus Tech
Tweaks, debloating, update configuration, and more, via a GUI:
> https://christitus.com/win

### [6] MassGrave — Microsoft Activation Scripts
Windows / Office activation via an interactive menu:
> https://get.activated.win

---

## ✨ Features

- 🎨 **Interactive TUI** — boxed panels, color-coded status icons, centered banner
- 📊 **Live progress** — animated bar, elapsed time, ETA, per-app install status
- 🔁 **Idempotent** — detects already-installed apps and skips them gracefully
- 🛡️ **Robust fallbacks** — Spotify handles the `0x8A150056` elevation refusal (per-user retry → direct Squirrel installer); Office auto-resolves a fresh ODT download link if the hard-coded one goes stale
- 🪵 **Full logging** — every install/uninstall writes to `C:\FreshWindowsSetup\Logs\` plus a session transcript
- ♻️ **Retry failed installs** — dedicated menu option replays only the failures
- 🧹 **Uninstall mode** — selective or bulk removal of anything the script installed (Office via ODT remove config, Hermes via `hermes uninstall`, EvoFox via its Inno uninstaller)

---

## 📁 Repo Layout

```
fresh-windows/
├── INSTALLATION/
│   ├── Install-WindowsSetup.bat   ← double-click launcher (auto-elevates via UAC)
│   └── Setup-Windows.ps1          ← the main interactive script
├── WALLPAPER/                     ← a small curated wallpaper collection
└── README.md
```

## 📋 Requirements

- Windows 10 or 11 (x64)
- **WinGet** (Microsoft "App Installer" — preinstalled on modern Windows 11; the script checks and exits with instructions if missing)
- Administrator rights (UAC prompt appears when you launch the `.bat`)

## 🔧 Customizing

Want a different app list? Edit the `$Apps` array near the top of `Setup-Windows.ps1`:

```powershell
[PSCustomObject]@{ Number = 21; Name = "OBS Studio"; ID = "OBSProject.OBS"; Source = "winget" }
```

WinGet IDs can be found with `winget search <name>`.

---

## ⚠️ Disclaimer

This project is intended for **personal use on machines you own**. The MassGrave activation option is a convenience wrapper around a third-party tool — check the legality of KMS-style activation in your jurisdiction before using it. No warranty is provided for any system changes made.

## 📄 License

MIT — do whatever you want, attribution appreciated.
