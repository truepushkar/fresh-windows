<div align="center">

# 🪟 Fresh Windows Setup

**A minimal, GUI-driven workstation bootstrapper for freshly installed Windows 11/10 machines.**

One elevated PowerShell script installs my entire daily-driver toolkit — browsers, dev tools, messaging, Microsoft 365, and more — through a clean WPF interface with live progress and per-app status.

[![Platform](https://img.shields.io/badge/platform-Windows%2010%2F11-blue)](https://github.com/truepushkar/fresh-windows)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell)](https://github.com/PowerShell/PowerShell)
[![License](https://img.shields.io/badge/license-MIT-green)](#-license)

</div>

---

> [!IMPORTANT]
> **This list is my personal setup.** The apps, defaults, and tweaks in this repo are exactly what I install on a fresh Windows machine — nothing more, nothing less. It is not meant to be a universal installer.
>
> **Want your own version? [Fork this repo](https://github.com/truepushkar/fresh-windows/fork) and modify it** — edit the `$Apps` array in `setup.ps1`, adjust the system setup steps, and you'll have a one-command bootstrap for *your* setup. More detail in [🔧 Making It Yours](#-making-it-yours).

---

## ⚡ Quick Start

### Run straight from GitHub (no cloning)

Open **PowerShell as Administrator** and paste:

```powershell
irm https://raw.githubusercontent.com/truepushkar/fresh-windows/main/setup.ps1 | iex
```

That's it — the GUI launches immediately.

### Or clone the repo

```powershell
git clone https://github.com/truepushkar/fresh-windows.git
cd fresh-windows
.\Install-WindowsSetup.bat
```

> **Note:** the script refuses to run unelevated — it needs Administrator rights for machine-wide installs, registry tweaks, and launching WinUtil/MAS without a second UAC prompt.

---

## 🖥️ The Interface

A minimal dark WPF window — no flags to memorize, no config files to edit:

- **Install / Remove** — checkbox grid with search and category filters; select apps, hit one button
- **System Setup** — dev-environment configuration in one click
- **Export** — back up Windows preferences for your next install
- **Tools** — launch WinUtil and MAS without leaving the app
- **Logs** — every run writes a transcript to `C:\FreshWindowsSetup\Logs\`

The bottom panel shows a live progress bar, current activity, and a streaming status log while installs run in a background worker (the window stays responsive).

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

Two entries in the Tools tab launch trusted external utilities (elevated, no second UAC prompt):

### WinUtil — Chris Titus Tech
Tweaks, debloating, update configuration, and more, via a GUI:
> https://christitus.com/win

### MassGrave — Microsoft Activation Scripts
Windows / Office activation via an interactive menu:
> https://get.activated.win

---

## ✨ Features

- 🎨 **Minimal GUI** — clean WPF interface, checkbox grid, search + category filters
- 📊 **Live progress** — animated bar, per-app install status, streaming log
- 🔄 **Non-blocking** — installs run in a background worker; the window never freezes
- 🔁 **Idempotent** — detects already-installed apps and skips them gracefully
- 🛡️ **Robust fallbacks** — Spotify handles the `0x8A150056` elevation refusal (per-user retry → direct Squirrel installer); Office auto-resolves a fresh ODT download link if the hard-coded one goes stale
- 🪵 **Full logging** — every install/uninstall writes to `C:\FreshWindowsSetup\Logs\` plus a session transcript
- 🧹 **Uninstall mode** — selective or bulk removal of anything the script installed (Office via ODT remove config, Hermes via `hermes uninstall`, EvoFox via its Inno uninstaller)

---

## 📁 Repo Layout

```
fresh-windows/
├── Install-WindowsSetup.bat   ← double-click launcher
├── setup.ps1                  ← the main script (installer + GUI)
└── README.md
```

## 📋 Requirements

- Windows 10 or 11 (x64)
- **WinGet** (Microsoft "App Installer" — preinstalled on modern Windows 11; the script checks and exits with instructions if missing)
- Administrator rights (UAC prompt appears when you launch the `.bat`)

## 🔧 Making It Yours

This repo is **my personal setup**, published so others can reuse the pattern. It is not a general-purpose installer — the app list, Git identity, Python packages, and mouse software are all specific to me.

If you want the same one-command fresh-machine bootstrap for your own toolkit:

1. **Fork the repo** (top-right button, or [direct link](https://github.com/truepushkar/fresh-windows/fork))
2. **Edit the `$Apps` array** near the top of `setup.ps1`:

   ```powershell
   [PSCustomObject]@{ Number = 21; Name = "OBS Studio"; ID = "OBSProject.OBS"; Source = "winget" }
   ```

   WinGet IDs can be found with `winget search <name>`. Remove apps you don't want; renumber as needed.
3. **Adjust the dev-environment setup** (`Configure-Development`) — the Python packages, npm globals, and Git identity are mine, so change them to yours.
4. **Commit and push** — your fork now has its own one-liner:

   ```powershell
   irm https://raw.githubusercontent.com/<you>/fresh-windows/main/setup.ps1 | iex
   ```

That's the whole point of the repo: fork it, swap in your list, and never hand-install a fresh machine again.

---

## ⚠️ Disclaimer

This project is intended for **personal use on machines you own**. The MassGrave activation option is a convenience wrapper around a third-party tool — check the legality of KMS-style activation in your jurisdiction before using it. No warranty is provided for any system changes made.

## 📄 License

MIT — do whatever you want, attribution appreciated.
