# Omablue Setup Guide for Virgin Secureblue Sericea

This guide walks you through setting up Omablue on a freshly installed Secureblue Sericea (Sway) system.

## What is Omablue?

Omablue is a **complete Sway desktop environment configuration** for Secureblue that includes:
- Sway window manager config with keybindings
- Waybar (status bar) with custom styling
- Rofi (application launcher)
- Foot (terminal), Dunst (notifications), and other utilities
- Curated themes (Catppuccin by default)
- Helper scripts for system management

## Prerequisites

Before running setup, ensure your fresh Secureblue system has:

1. **Homebrew installed** (required for CLI tools)
   - Instructions: https://brew.sh
   - Install with: `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
   - Verify: `brew --version`

2. **Git** (should already be in the image, but verify)
   - Verify: `git --version`

3. **Basic connectivity** (internet access for downloading packages)

> **Note:** Do NOT use `sudo` or `rpm-ostree install`. Omablue deploys entirely to your home directory using Homebrew.

---

## Step-by-Step Setup

### Option A: Interactive Setup (Recommended)

**1. Clone the Omablue repository** to your home directory:

```bash
git clone https://github.com/odd-git/omablue ~/.local/share/omablue-repo
cd ~/.local/share/omablue-repo
```

Or if you already have it:
```bash
cd ~/path/to/omablue  # wherever you cloned it
```

**2. Run the setup script:**

```bash
just setup-omablue
```

Or directly:
```bash
bash setup/omablue-setup.sh
```

**3. Follow the prompts:**
- Phase 0: Preflight checks (ensures brew, git, sway are available)
- Phase 1: Backup existing configs (if any)
- Phase 2: Deploy files (scripts, themes, configs)
- Phase 3: Install Homebrew dependencies (gum, fzf, jq, btop)
- Phase 4: Configure shell PATH
- Phase 5: Set default theme (Catppuccin)
- Phase 6: Optional battery monitor service (say yes if on laptop)
- Phase 7: Optional Bluetooth auto-connect service (say yes for auto-reconnecting devices)
- Phase 8: Reload Sway and show summary

**4. Reload your shell:**
```bash
source ~/.bashrc
# or
source ~/.zshrc
```

**5. Restart Sway** (or log out and back in):
- Press `Super+E` to reload (if already running Sway)
- Or log out and back in

---

### Option B: System-wide via ujust

If you want Omablue recipes available system-wide via `ujust`:

**1. Set up as above, then:**
```bash
ln -sf ~/.local/share/omablue-repo/justfile ~/.justfile
```

**2. Use ujust:**
```bash
ujust --choose     # Browse recipes interactively
ujust setup-omablue  # Or run directly
```

---

## What Gets Installed

### Files Deployed

| Location | Contents | Purpose |
|---|---|---|
| `~/.local/share/omablue/bin/` | omablue-* scripts | Helper commands |
| `~/.local/share/omablue/themes/` | Theme definitions | Catppuccin + others |
| `~/.local/share/omablue/assets/` | Images, icons | UI assets |
| `~/.config/sway/` | Sway config | Window manager configuration |
| `~/.config/waybar/` | Waybar config | Status bar |
| `~/.config/rofi/` | Rofi config + themes | Application launcher |
| `~/.config/foot/` | Terminal config | Foot terminal settings |
| `~/.config/dunst/` | Notification daemon | Dunst config |
| `~/.config/swaylock/` | Lock screen | Swaylock settings |
| `~/.config/Thunar/` | File manager | Thunar preferences |
| `~/.config/gtk-3.0/` | GTK theme | GTK settings |
| `~/.config/nvim/` | Neovim config | Vim/Nvim setup (LazyVim) |
| `~/.config/omablue/` | Theme state + BT config | Current theme, generated files, auto-connect config |
| `~/.config/systemd/user/` | systemd user units | Battery monitor and BT auto-connect timers |

### Homebrew Packages Installed

- `gum` — interactive TUI dialogs
- `fzf` — fuzzy finder for menus
- `jq` — JSON parser (optional, for webapp-install)
- `btop` — system monitor TUI (optional)

### Backups Created

Before deploying new configs, your existing ones are backed up:
```
~/.config-backup-omablue-<YYYYMMDD-HHMMSS>/
```

You can restore them anytime if needed.

---

## After Setup: Key Commands

### Main Menu
```bash
omablue-menu
# Or: Super+Esc (in Sway)
```
Opens Rofi app launcher with all installed applications.

### Change Theme
```bash
omablue-theme-selector
```
Browse and switch between available themes interactively.

### System Monitor
```bash
btop
```
TUI system monitor (CPU, memory, processes).

### Update Omablue
```bash
just update-omablue
# Or: bash setup/omablue-update.sh
```
Pulls latest changes from repo, re-deploys configs, regenerates themes.

### Uninstall Omablue
```bash
just uninstall-omablue
# Or: bash setup/omablue-uninstall.sh
```
Removes Omablue (keeps your config backups for recovery).

---

## Sway Keybindings Quick Reference

| Binding | Action |
|---|---|
| `Super+Esc` | Open app menu (Rofi) |
| `Super+Return` | Open terminal (Foot) |
| `Super+E` | Toggle file manager (Thunar) |
| `Super+B` | Toggle browser (Trivalent) |
| `Super+F` | Toggle floating window |
| `Super+V` | Toggle split vertical |
| `Super+H` | Toggle split horizontal |
| `Super+[1-9]` | Switch to workspace |
| `Super+Shift+[1-9]` | Move window to workspace |
| `Super+Left/Right/Up/Down` | Move focus (vim keys: h/l/j/k work too) |
| `Alt+Tab` | Cycle windows |
| `Super+Shift+E` | Exit Sway |
| `Super+L` | Lock screen (Swaylock) |

See `~/.config/sway/` for the full config.

---

## Troubleshooting

### "brew not found"
**Problem:** Setup script exits with "Homebrew (brew) not found"

**Solution:** Install Homebrew first:
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
```

Then run setup again.

### "swaymsg not found"
**Problem:** Not on a Sway-based system or Sway not started

**Solution:** Ensure you're on Secureblue Sericea (Sway variant). If using a different desktop (GNOME, Plasma), Omablue won't work.

### Configs not appearing
**Problem:** Files deployed but changes not visible

**Solution:** Reload Sway:
```bash
swaymsg reload
```

Or log out and back in.

### Shell PATH not updated
**Problem:** `omablue-*` commands not found after setup

**Solution:** Manually source your shell rc file:
```bash
source ~/.bashrc    # for bash
# or
source ~/.zshrc     # for zsh
```

Or open a new terminal window.

### Bluetooth auto-connect not working
**Problem:** Devices don't reconnect automatically

**Solution:** Ensure the device is trusted:
```bash
bluetoothctl trust <MAC_ADDRESS>
```
Devices paired via `omablue-bluetooth > Pair New Device` are trusted automatically. Devices paired before Omablue may need to be trusted manually.

Check if the timer is running:
```bash
systemctl --user status omablue-bluetooth-autoconnect.timer
```

To disable/enable:
```bash
systemctl --user stop omablue-bluetooth-autoconnect.timer    # disable
systemctl --user start omablue-bluetooth-autoconnect.timer   # enable
```

### Want to restore old configs
**Problem:** Setup overwrote your existing configs and you want them back

**Solution:** Your backups are in `~/.config-backup-omablue-<timestamp>/`:
```bash
ls ~/.config-backup-omablue-*  # List backups

# Restore a specific backup:
cp -r ~/.config-backup-omablue-20250209-120000/sway ~/.config/
```

---

## Updating Later

To keep Omablue up to date:

```bash
cd ~/.local/share/omablue-repo
just update-omablue
```

This:
1. Pulls latest from git
2. Re-deploys all files
3. Regenerates theme files
4. Reloads Sway

Safe to run multiple times.

---

## Next Steps

1. **Customize keybindings:** Edit `~/.config/sway/keys`
2. **Adjust Waybar:** Edit `~/.config/waybar/config.jsonc` and `style.css`
3. **Install additional apps:** Use Flatpak for GUI apps, Homebrew for CLI tools
4. **Set up shell:** Configure `~/.bashrc` or `~/.zshrc` (Omablue adds PATH but doesn't touch other settings)
5. **Add fonts:** Install Nerd Fonts via Homebrew: `brew install font-jetbrains-mono-nerd-font`

---

## Security Notes

This setup follows Secureblue's security principles:

- ✅ No `sudo`/`su` used (everything runs as your user)
- ✅ No system packages modified (all in your home directory)
- ✅ No root filesystem changes (Sway's immutability preserved)
- ✅ Encrypted backups of your configs created before changes
- ✅ All scripts pass `shellcheck` and use strict error handling
- ✅ Input sanitization on theme names and file operations

---

## Getting Help

- **Omablue repo:** https://github.com/odd-git/omablue
- **Secureblue docs:** https://secureblue.dev
- **Sway docs:** https://swaywm.org
- **Universal Blue:** https://universal-blue.org
