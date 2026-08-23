# hotkeys

> Advanced AutoHotkey system — context-aware app launching, audio switching, system automation, and safe window management for Windows.

---

## Install

Open **PowerShell** and run:

```powershell
irm https://github.com/RameshXT/hotkeys/releases/latest/download/install.ps1 | iex
```

That's it. Hotkeys are active immediately. No admin rights needed.

> **What it does automatically:**
> - Installs AutoHotkey v2.0.26 (if not already installed)
> - Downloads and verifies `hotkeys.ahk`
> - Registers `xtkeys` as a global command in your terminal
> - Creates a Startup shortcut so hotkeys launch on every login

---

## Manage

After install, use `xtkeys` from any terminal:

```
xtkeys status      → check if hotkeys are running
xtkeys update      → download latest version and restart
xtkeys restart     → restart hotkeys
xtkeys uninstall   → remove everything cleanly
xtkeys help        → show this help message
```

---

## Local Install (Developers)

If you've cloned this repo, install directly from your local folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\xtkeys.ps1 install
```

---

## Hotkey Reference

### Application & Utility Hotkeys

| Hotkey | Single Press | Double Press | Long Press / Hold |
| :--- | :--- | :--- | :--- |
| **Alt + 0** | Calculator | - | - |
| **Alt + 1** | - | Photoshop | - |
| **Alt + 7** | 7.1 Surround Sound | - | - |
| **Alt + A** | Antigravity IDE | Open in active Explorer folder | - |
| **Alt + C** | Google Chrome | - | **Incognito Mode** (Hold >600ms) |
| **Alt + E** | Outlook (Auto-Maximize) | - | - |
| **Alt + G** | Git Bash | Open in active Explorer folder | - |
| **Alt + I** | Instagram (Auto-Maximize) | - | - |
| **Alt + M** | Microsoft Store | - | - |
| **Alt + N** | Notepad | - | - |
| **Alt + O** | Command Prompt (CMD) | Open in active Explorer folder / **Admin CMD** (if no folder active) | **Admin CMD in Folder** (Hold >600ms) |
| **Alt + P** | PowerShell | Open in active Explorer folder / **Admin PowerShell** (if no folder active) | **Admin PowerShell in Folder** (Hold >600ms) |
| **Alt + Q** | Close Active Window | - | Continuous safe window close |
| **Alt + S** | Slack (Auto-Maximize) | - | - |
| **Alt + T** | Telegram | - | - |
| **Alt + U** | Ubuntu WSL | Open in active Explorer folder | - |
| **Alt + V** | VS Code | Open in active Explorer folder | - |
| **Alt + Shift + V** | Paste clipboard path as WSL | - | - |
| **Alt + W** | WhatsApp (Auto-Maximize) | - | - |
| **Alt + Y** | YouTube (Auto-Maximize) | - | - |
| **Alt + Z** | Unzip Selected ZIP | - | - |

### System & Media Hotkeys

| Hotkey | Action | Description |
| :--- | :--- | :--- |
| **Ctrl + Shift + Q** | Switch Audio | Set playback to **Sony MDRX-50** (mic: Sony) and volume to 25% |
| **Ctrl + Shift + X** | Switch Audio | Set playback to **Black Shark V2** (mic: Black Shark) |
| **Ctrl + Shift + Y** | Switch Audio | Set playback to **Resound** (mic: Sony) |
| **Ctrl + Shift + Z** | Switch Audio | Set playback to **HEAT** (mic: Sony) |
| **Ctrl + Shift + Alt + C** | Windows Cleanup | Runs background Windows Cleanup (tray notification on finish) |
| **Ctrl + Shift + Alt + U** | Windows Updater | Runs background Windows Update check (tray notification on finish) |
| **Ctrl + Shift + Alt + N** | Network Reset | Resets network adapters, flushes DNS, and renews IP |
| **Ctrl + Shift + Alt + L** | Logs Folder | Opens the logs directory in File Explorer |
| **Ctrl + Shift + Alt + Del** | Empty Recycle Bin | Empties the Recycle Bin (requires confirmation prompt) |

---

## Key Features

- **Contextual Intelligence**:
  - **Double-Tap to Folder**: `Alt + V` (VS Code), `Alt + A` (Antigravity), `Alt + G` (Git Bash), `Alt + P` (PowerShell), and `Alt + U` (Ubuntu WSL) open the application directly in your **active File Explorer directory** when double-pressed.
  - **Multi-Press & Hold Shells**: `Alt + O` (CMD) and `Alt + P` (PowerShell) open normal shell in Home (Single Press), normal shell in active Explorer folder (Double Press if active), Administrator shell in Home (Double Press if not active), or **Administrator shell in active Explorer folder** (Long Press/Hold).
  - **Long-Press Interface**: `Alt + C` launches standard Chrome on a short tap, but triggers **Incognito Mode** if held for >600ms. Also, holding `Alt + O`/`Alt + P` launches Admin shell in the active folder.
- **Safety & Protection**: `Alt + Q` (Close Window) supports continuous closing when held, but is logic-locked to **prevent accidental closure** of critical system components, showing "Nothing to close" if there is no active/non-system window.
- **Audio Output Switching**: Quickly switch audio playback and recording devices using `Ctrl + Shift + [Key]` combinations.
- **Friendly Balloon Notifications**: Automatically intercepts launch or system errors and shows clean Windows tray notifications instead of blocking error popups.
- **Self-Maintaining**: Automatically reloads and applies changes the moment you save `hotkeys.ahk`.
