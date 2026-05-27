# Omablue Quick Start (30 seconds)

## TL;DR

On a fresh Secureblue Sericea system:

### 1. Install Homebrew (one-time)
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
```

### 2. Clone Omablue
```bash
git clone https://github.com/odd-git/omablue ~/omablue
cd ~/omablue
```

### 3. Run Setup
```bash
just setup-omablue
```

(Or: `bash setup/omablue-setup.sh`)

### 4. Reload Shell & Sway
```bash
source ~/.bashrc
swaymsg reload
```

### 5. Done!
Press `Super+Esc` to open the menu. All keybindings are in `~/.config/sway/keys`.

---

## What Happens

- ✅ Backs up your existing configs
- ✅ Installs Homebrew packages (gum, fzf, jq, btop)
- ✅ Deploys Sway, Waybar, Rofi, Foot, Dunst configs
- ✅ Applies Catppuccin theme
- ✅ Makes omablue-* commands available
- ✅ Reloads Sway

**Everything goes to `~/.local/share/omablue/` and `~/.config/`**

No system files modified. No root needed.

---

## Key Commands

| Command | What it does |
|---|---|
| `just setup-omablue` | Full setup |
| `just update-omablue` | Update from git |
| `just uninstall-omablue` | Remove Omablue |
| `omablue-menu` | Open app launcher |
| `omablue-theme-selector` | Change theme |
| `swaymsg reload` | Reload Sway config |

---

## Troubleshooting

**"brew not found"**
→ Install Homebrew first (see step 1)

**"swaymsg not found"**
→ Not on Sway. Need Secureblue Sericea variant.

**Commands not found after setup**
→ Run: `source ~/.bashrc`

**Config changes not showing**
→ Run: `swaymsg reload`

---

See `SETUP-GUIDE.md` for detailed instructions.
