# Omasync Master Plan — SSH Sync Manager for Omablue

> Comprehensive implementation plan for secure file synchronization over SSH with Gum TUI

---

## 1. Executive Summary

Omasync is a file synchronization tool built for the Omablue desktop environment on Secureblue. It provides secure, user-friendly file transfer between devices using rsync over SSH, with Tailscale DNS integration for seamless device discovery across networks. The system consists of two bash scripts — `omasync-setup` (configuration wizard) and `omasync` (sync runner) — following the established Omablue patterns of strict bash, modular config files, and `gum` for terminal UI.

The architecture is deliberately simple: bash scripts, one-file-per-device/profile configuration, and no daemons. SSH connection multiplexing provides performance without complexity, while dedicated per-device keypairs enable granular access control. The config format uses sourced bash variables (matching `bluetooth-autoconnect.conf` and other Omablue configs), keeping the toolchain minimal and consistent.

Gum serves as the primary TUI layer, providing interactive menus, styled output, input forms, confirmation dialogs, and progress spinners. Every interactive operation has a corresponding CLI flag for scripting and systemd timer integration, ensuring the tool works in both human-interactive and automated contexts.

---

## 2. Technical Architecture

### 2.1 Component Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                           USER LAYER                                │
│                                                                     │
│   ┌──────────────────┐          ┌──────────────────┐                │
│   │  omasync-setup   │          │     omasync       │                │
│   │  (config wizard) │          │  (sync runner)    │                │
│   │                  │          │                   │                │
│   │  - Add device    │          │  - Select device  │                │
│   │  - Manage keys   │          │  - Select profile │                │
│   │  - Add profile   │          │  - Execute rsync  │                │
│   │  - Test conn.    │          │  - View logs      │                │
│   └───────┬──────────┘          └───────┬───────────┘                │
│           │                             │                           │
│   ┌───────▼─────────────────────────────▼───────────┐               │
│   │              omasync-lib.sh                      │               │
│   │  (shared: config loading, validation, helpers)   │               │
│   └───────┬──────────────────────────────┬──────────┘               │
│           │                              │                          │
├───────────┼──────────────────────────────┼──────────────────────────┤
│           │        TUI LAYER             │                          │
│   ┌───────▼──────────────────────────────▼──────────┐               │
│   │                   gum                            │               │
│   │  choose | input | confirm | spin | style | ...   │               │
│   └─────────────────────────────────────────────────┘               │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                         TRANSPORT LAYER                             │
│                                                                     │
│   ┌──────────────┐  ┌──────────────┐  ┌────────────────────┐       │
│   │     SSH       │  │    rsync      │  │   Tailscale DNS    │       │
│   │              │  │              │  │                    │       │
│   │  - Multiplex │  │  - -avzh     │  │  - MagicDNS       │       │
│   │  - ed25519   │  │  - --partial │  │  - tailscale ip   │       │
│   │  - Agent     │  │  - --delete  │  │  - Fallback to IP │       │
│   └──────────────┘  └──────────────┘  └────────────────────┘       │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                        CONFIG LAYER                                 │
│                                                                     │
│   ~/.config/omablue/omasync/                                       │
│   ├── omasync.conf            (global defaults)                    │
│   ├── devices/                                                     │
│   │   ├── pixel-phone.conf    (per-device SSH config)              │
│   │   └── thinkpad.conf                                            │
│   └── profiles/                                                    │
│       ├── music.conf          (per-sync-job definition)            │
│       └── documents.conf                                           │
│                                                                     │
│   ~/.ssh/                                                          │
│   ├── omasync_pixel-phone     (per-device private key)             │
│   └── omasync_pixel-phone.pub                                      │
│                                                                     │
│   ~/.local/share/omablue/omasync/logs/                             │
│   └── pixel-phone_music_20260213-1430.log                          │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.2 Data Flow — Push Sync

```
User runs: omasync --device pixel --profile music

  1. Load global config          → ~/.config/omablue/omasync/omasync.conf
  2. Load device config          → ~/.config/omablue/omasync/devices/pixel-phone.conf
  3. Load profile config         → ~/.config/omablue/omasync/profiles/music.conf
  4. Resolve host                → Try Tailscale DNS → Fallback to DEVICE_HOST
  5. Check SSH multiplexed conn  → Reuse or establish new
  6. Build rsync command:
     rsync -avzh --progress --partial \
       --exclude='.thumbnails' --exclude='.cache' --exclude='*.tmp' \
       -e "ssh -p 8022 -i ~/.ssh/omasync_pixel-phone \
           -o ControlMaster=auto \
           -o ControlPath=/tmp/omasync-%r@%h:%p \
           -o ControlPersist=600" \
       ~/Music/ u0_a123@192.168.1.50:/storage/emulated/0/Music/
  7. Execute with live output
  8. Log result to LOG_DIR
  9. Update last-sync timestamp
```

### 2.3 Data Flow — Pull Sync

Same as push but rsync source/destination are swapped:

```
rsync [flags] -e "ssh [opts]" user@host:/remote/path/ ~/local/path/
```

### 2.4 Data Flow — Bidirectional Sync

Bidirectional ("both") sync runs as two sequential operations with safety guards:

```
  1. Pull first   → rsync [flags] --update  remote → local
  2. Then push    → rsync [flags] --update  local → remote
```

The `--update` flag ensures only newer files overwrite older ones, preventing data loss. This is a "last-writer-wins" strategy — not true merge-based sync (which would require tools like Unison). This trade-off is documented clearly to users.

### 2.5 Security Boundaries and Trust Model

```
Trust Boundary 1: Local Machine
  - Private keys stored in ~/.ssh/ with mode 600
  - Config files in ~/.config/omablue/ with mode 644
  - No secrets stored in config files (keys referenced by path)
  - Passphrases optional but recommended for keys

Trust Boundary 2: SSH Transport
  - All data encrypted in transit via SSH
  - Host verification via known_hosts (strict by default)
  - Per-device dedicated keypairs (compromise of one key ≠ all)
  - Connection multiplexing via Unix socket (mode 600)

Trust Boundary 3: Remote Host
  - Key authorized via authorized_keys (principle of least privilege)
  - Remote user should be limited to file access needed for sync
  - No root access required or recommended

Tailscale adds:
  - WireGuard encryption layer beneath SSH
  - Device identity verified by Tailscale coordination server
  - Private network addressing (100.x.y.z) not routable on public internet
```

### 2.6 TUI Interaction Flow

```
                    ┌─────────────────────┐
                    │    omasync-setup     │
                    └──────────┬──────────┘
                               │
                    ┌──────────▼──────────┐
                    │     Main Menu        │
                    │  (gum choose)        │
                    │                      │
                    │  > Manage Devices    │
                    │    Manage Profiles   │
                    │    Test Connection   │
                    │    Quit              │
                    └──────┬───┬───┬──────┘
                      ┌────┘   │   └────┐
                      ▼        ▼        ▼
              ┌──────────┐ ┌────────┐ ┌──────────┐
              │ Devices  │ │Profiles│ │  Test    │
              │          │ │        │ │          │
              │ Add      │ │ Add    │ │ Pick dev │
              │ Edit     │ │ Edit   │ │ SSH test │
              │ Remove   │ │ Remove │ │ Show     │
              │ List     │ │ List   │ │ result   │
              └──────────┘ └────────┘ └──────────┘

                    ┌─────────────────────┐
                    │      omasync        │
                    └──────────┬──────────┘
                               │
              Interactive      │      CLI mode
              ┌────────────────┼────────────────┐
              ▼                │                ▼
    ┌──────────────┐           │      omasync --device X
    │ Pick device  │           │               --profile Y
    │ (gum choose) │           │               [--dry-run]
    └──────┬───────┘           │               [--yes]
           ▼                   │
    ┌──────────────┐           │
    │ Pick profile │           │
    │ (gum choose  │           │
    │  multi)      │           │
    └──────┬───────┘           │
           ▼                   │
    ┌──────────────┐           │
    │ Confirm      │◄──────────┘
    │ (gum choose: │
    │  Run/Dry/X)  │
    └──────┬───────┘
           ▼
    ┌──────────────┐
    │ Execute sync │
    │ (raw rsync   │
    │  output)     │
    └──────┬───────┘
           ▼
    ┌──────────────┐
    │ Summary      │
    │ (gum style)  │
    └──────────────┘
```

---

## 3. User Experience Design

### 3.1 Main Menu Structure

**omasync-setup:**
```
┌───────────────────────────────────┐
│        Omasync Setup              │
│                                   │
│   > 󰒍  Manage Devices             │
│     󰐕  Manage Sync Profiles       │
│     󰗠  Test Connection            │
│        Quit                       │
└───────────────────────────────────┘
```

**omasync (interactive):**
```
┌───────────────────────────────────┐
│        Omasync                    │
│                                   │
│   Select device:                  │
│   > 󰂱  Pixel Phone (termux)       │
│     󰂱  ThinkPad (linux)           │
│     󰂲  MacBook (offline)          │
│                                   │
│   Select profile(s):              │
│   > [x] Music (push)             │
│     [x] Documents (both)         │
│     [ ] Photos (pull)            │
│                                   │
│   ┌─── Confirm ──────────────┐   │
│   │ Device:  Pixel Phone     │   │
│   │ Profiles: Music, Docs    │   │
│   │ Direction: push, both    │   │
│   │                          │   │
│   │ > Run sync               │   │
│   │   Dry-run first          │   │
│   │   Cancel                 │   │
│   └──────────────────────────┘   │
└───────────────────────────────────┘
```

### 3.2 Key User Workflows

#### Workflow 1: First-Time Setup (Add Device)

```
$ omasync-setup

  ┌─────────────────────────────────┐
  │ > Manage Devices                │
  └─────────────────────────────────┘

  ┌─────────────────────────────────┐
  │ > Add New Device                │
  │   (no devices configured yet)  │
  └─────────────────────────────────┘

  Device name: pixel-phone          ← gum input
  Host or IP:  192.168.1.50         ← gum input
  SSH port:    8022                  ← gum input --value "22"
  Username:    u0_a123              ← gum input
  Device type: > termux             ← gum choose
               linux
               macos

  ┌─── SSH Key ────────────────────┐
  │ Generating ed25519 keypair...  │  ← gum spin
  │                                │
  │ ✓ Created:                     │
  │   ~/.ssh/omasync_pixel-phone   │
  │                                │
  │ Public key (copied to clip):   │
  │ ┌────────────────────────────┐ │
  │ │ ssh-ed25519 AAAA...xyz    │ │  ← gum style --border double
  │ │ omasync@pixel-phone       │ │
  │ └────────────────────────────┘ │
  └────────────────────────────────┘

  ┌─── Termux Setup Guide ────────┐
  │                                │
  │ On your Pixel Phone, open      │
  │ Termux and run these commands: │
  │                                │
  │ 1. pkg install openssh         │
  │ 2. mkdir -p ~/.ssh             │
  │ 3. Paste the public key into:  │
  │    ~/.ssh/authorized_keys      │
  │ 4. Start SSH:  sshd            │
  │ 5. Find IP:    ifconfig        │
  │                                │
  │ Note: Termux uses port 8022    │
  │ by default.                    │
  │                                │
  │ Ready to test? [Y/n]           │  ← gum confirm
  └────────────────────────────────┘

  Testing connection...             ← gum spin
  ✓ Connected to pixel-phone!       ← gum style --foreground 46

  Device saved: ~/.config/omablue/omasync/devices/pixel-phone.conf
```

#### Workflow 2: Create Sync Profile

```
$ omasync-setup → Manage Sync Profiles → Add New Profile

  Profile name:    music                     ← gum input
  Local path:      /home/mino/Music          ← gum input
  Remote path:     /storage/emulated/0/Music ← gum input
  Sync direction:  > push                    ← gum choose
                     pull
                     both (bidirectional)
  Exclude patterns: .thumbnails,.cache,*.tmp ← gum input (optional)
  Use --delete?    [y/N]                     ← gum confirm

  ✓ Profile saved: ~/.config/omablue/omasync/profiles/music.conf
```

#### Workflow 3: Run Sync

```
$ omasync

  Select device:
  > Pixel Phone     (termux)   last sync: 2h ago
    ThinkPad         (linux)    last sync: 1d ago

  Select profile(s) — space to toggle, enter to confirm:
  > [x] Music        ~/Music → /storage/.../Music      push
    [ ] Documents    ~/Docs  → /storage/.../Docs       both
    [ ] Photos       ~/Pics  → /storage/.../Photos     pull

  ┌─── Sync Summary ───────────────────────────┐
  │ Device:    Pixel Phone (192.168.1.50:8022)  │
  │ Profile:   Music                            │
  │ Direction: push (local → remote)            │
  │ Source:    ~/Music/                          │
  │ Dest:      /storage/emulated/0/Music/       │
  │ Flags:     -avzh --progress --partial       │
  │ Delete:    no                               │
  └─────────────────────────────────────────────┘

  > Run sync
    Dry-run first
    Cancel

  --- rsync output (raw terminal) ---
  sending incremental file list
  album/song1.flac
        15,234,567 100%   12.5MB/s    0:00:01
  album/song2.flac
         8,901,234 100%   10.2MB/s    0:00:00

  sent 24,135,801 bytes  received 52 bytes

  ┌─── Result ─────────────────────────────────┐
  │ ✓ Sync completed successfully               │
  │ Transferred: 24.1 MB                        │
  │ Log: ~/.local/share/.../pixel-phone_music_  │
  │      20260213-1430.log                      │
  └─────────────────────────────────────────────┘
```

### 3.3 Error Handling UX

Errors are displayed using `gum style` with red foreground and a border, followed by actionable hints:

```
┌─── Connection Failed ─────────────────────────────────┐
│ ✗ Cannot reach pixel-phone (192.168.1.50:8022)        │
│                                                        │
│ Possible causes:                                       │
│  • Device is offline or not on the same network        │
│  • sshd is not running (Termux: run 'sshd')           │
│  • Firewall blocking port 8022                         │
│  • Wrong IP address — check with 'ifconfig' on device │
│                                                        │
│ Try again? [Y/n]                                       │
└────────────────────────────────────────────────────────┘
```

### 3.4 Accessibility

- All operations are keyboard-navigable (gum's defaults)
- No color-only indicators — always text + icon alongside color
- CLI mode (`--device`, `--profile`) for screen reader compatibility
- Clear sequential flow — no parallel information requiring visual scanning

---

## 4. Implementation Phases

### Phase 0: Skeleton & Foundations

**Goals:** File structure, shared library, script scaffolding, dependency checks.

**Deliverables:**
- `omasync-lib.sh` — shared helpers (config loading, validation, device/profile listing)
- `omasync-setup` — skeleton with main menu dispatch
- `omasync` — skeleton with argument parsing
- Default `omasync.conf` generation
- Directory creation (`devices/`, `profiles/`, `LOG_DIR`)

**Dependencies:** None (foundation)
**Complexity:** Simple
**Testing:**
- Verify directory creation is idempotent
- Verify config loading with valid/invalid/missing files
- Verify dependency checks report missing tools clearly

**Key Implementation Details:**

```bash
# omasync-lib.sh — Config loading (safe, no arbitrary code execution)

OMASYNC_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omablue/omasync"
OMASYNC_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/omablue/omasync"

load_global_config() {
  local config="$OMASYNC_CONFIG_DIR/omasync.conf"
  [[ -f "$config" ]] || { err "Global config not found: $config"; return 1; }

  while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
    key=$(echo "$key" | xargs)
    value=$(echo "$value" | xargs | sed 's/^"//;s/"$//')
    case "$key" in
      LOG_DIR)          LOG_DIR="$value" ;;
      DEFAULT_SSH_DIR)  DEFAULT_SSH_DIR="$value" ;;
      RSYNC_BASE_FLAGS) RSYNC_BASE_FLAGS="$value" ;;
      DRY_RUN)          [[ "$value" =~ ^(true|false)$ ]] && DRY_RUN="$value" ;;
      LOG_KEEP_COUNT)   [[ "$value" =~ ^[0-9]+$ ]] && LOG_KEEP_COUNT="$value" ;;
    esac
  done < "$config"
}

load_device() {
  local name="$1"
  local conf="$OMASYNC_CONFIG_DIR/devices/${name}.conf"
  [[ -f "$conf" ]] || { err "Device not found: $name"; return 1; }

  # Reset device vars
  DEVICE_NAME="" DEVICE_HOST="" DEVICE_PORT="22"
  DEVICE_USER="" DEVICE_KEY="" DEVICE_TYPE="linux"

  while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
    key=$(echo "$key" | xargs)
    value=$(echo "$value" | xargs | sed 's/^"//;s/"$//')
    # Expand $HOME in value
    value="${value//\$HOME/$HOME}"
    case "$key" in
      DEVICE_NAME) DEVICE_NAME="$value" ;;
      DEVICE_HOST) DEVICE_HOST="$value" ;;
      DEVICE_PORT) [[ "$value" =~ ^[0-9]+$ ]] && DEVICE_PORT="$value" ;;
      DEVICE_USER) DEVICE_USER="$value" ;;
      DEVICE_KEY)  DEVICE_KEY="$value" ;;
      DEVICE_TYPE) [[ "$value" =~ ^(termux|linux|macos)$ ]] && DEVICE_TYPE="$value" ;;
    esac
  done < "$conf"

  # Validate required fields
  [[ -n "$DEVICE_NAME" ]] || { err "Device $name: missing DEVICE_NAME"; return 1; }
  [[ -n "$DEVICE_HOST" ]] || { err "Device $name: missing DEVICE_HOST"; return 1; }
  [[ -n "$DEVICE_USER" ]] || { err "Device $name: missing DEVICE_USER"; return 1; }
}

load_profile() {
  local name="$1"
  local conf="$OMASYNC_CONFIG_DIR/profiles/${name}.conf"
  [[ -f "$conf" ]] || { err "Profile not found: $name"; return 1; }

  PROFILE_NAME="" LOCAL_PATH="" REMOTE_PATH=""
  DIRECTION="push" RSYNC_EXCLUDE="" RSYNC_DELETE="false"

  while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
    key=$(echo "$key" | xargs)
    value=$(echo "$value" | xargs | sed 's/^"//;s/"$//')
    value="${value//\$HOME/$HOME}"
    case "$key" in
      PROFILE_NAME)  PROFILE_NAME="$value" ;;
      LOCAL_PATH)    LOCAL_PATH="$value" ;;
      REMOTE_PATH)   REMOTE_PATH="$value" ;;
      DIRECTION)     [[ "$value" =~ ^(push|pull|both)$ ]] && DIRECTION="$value" ;;
      RSYNC_EXCLUDE) RSYNC_EXCLUDE="$value" ;;
      RSYNC_DELETE)  [[ "$value" =~ ^(true|false)$ ]] && RSYNC_DELETE="$value" ;;
    esac
  done < "$conf"

  [[ -n "$PROFILE_NAME" ]] || { err "Profile $name: missing PROFILE_NAME"; return 1; }
  [[ -n "$LOCAL_PATH" ]]   || { err "Profile $name: missing LOCAL_PATH"; return 1; }
  [[ -n "$REMOTE_PATH" ]]  || { err "Profile $name: missing REMOTE_PATH"; return 1; }
}

list_devices() {
  local dir="$OMASYNC_CONFIG_DIR/devices"
  [[ -d "$dir" ]] || return 1
  local files=("$dir"/*.conf)
  [[ -e "${files[0]}" ]] || return 1
  for f in "${files[@]}"; do
    basename "$f" .conf
  done
}

list_profiles() {
  local dir="$OMASYNC_CONFIG_DIR/profiles"
  [[ -d "$dir" ]] || return 1
  local files=("$dir"/*.conf)
  [[ -e "${files[0]}" ]] || return 1
  for f in "${files[@]}"; do
    basename "$f" .conf
  done
}

sanitize_name() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-_'
}

test_connection() {
  local device="$1"
  load_device "$device" || return 1

  local ssh_opts=(-o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new)
  [[ -n "$DEVICE_KEY" && -f "$DEVICE_KEY" ]] && ssh_opts+=(-i "$DEVICE_KEY")
  [[ -n "$DEVICE_PORT" ]] && ssh_opts+=(-p "$DEVICE_PORT")

  ssh "${ssh_opts[@]}" "${DEVICE_USER}@${DEVICE_HOST}" exit 2>/dev/null
}

ensure_dirs() {
  mkdir -p "$OMASYNC_CONFIG_DIR"/{devices,profiles}
  mkdir -p "$OMASYNC_DATA_DIR/logs"
  mkdir -p "${DEFAULT_SSH_DIR:-$HOME/.ssh}"
}

# Gum wrapper — falls back to basic prompts if gum is unavailable
has_gum() { command -v gum &>/dev/null; }

gum_or_read() {
  local prompt="$1" default="${2:-}"
  if has_gum; then
    gum input --placeholder "$prompt" --value "$default"
  else
    read -rp "$prompt [$default]: " reply
    echo "${reply:-$default}"
  fi
}

gum_or_select() {
  local prompt="$1"; shift
  if has_gum; then
    printf '%s\n' "$@" | gum choose --header "$prompt"
  else
    echo "$prompt" >&2
    select opt in "$@"; do echo "$opt"; break; done
  fi
}

gum_or_confirm() {
  local prompt="$1"
  if has_gum; then
    gum confirm "$prompt"
  else
    read -rp "$prompt [y/N] " reply
    [[ "${reply,,}" == "y" ]]
  fi
}
```

---

### Phase 1: SSH Connection Management + Device Setup Wizard

**Goals:** Device registration, SSH key generation, connection testing, setup guides.

**Deliverables:**
- Add Device wizard (T05)
- SSH key generation (T06)
- Termux setup guide (T07)
- Linux/macOS setup guide (T08)
- Connection test (T09)
- Edit/Remove/List devices (T10, T11, T12)

**Dependencies:** Phase 0
**Complexity:** Moderate

**SSH Connection Multiplexing Strategy:**

SSH multiplexing allows a single TCP connection to carry multiple SSH sessions, dramatically speeding up repeated rsync operations. Configuration:

```bash
# SSH options applied to every omasync connection
build_ssh_opts() {
  local device="$1"
  load_device "$device"

  local socket_dir="/tmp/omasync-${USER}"
  mkdir -p "$socket_dir" && chmod 700 "$socket_dir"

  local opts=(
    -o "ControlMaster=auto"
    -o "ControlPath=${socket_dir}/%r@%h:%p"
    -o "ControlPersist=600"           # Keep master alive 10 min after last session
    -o "ServerAliveInterval=30"       # Ping every 30s to detect dead connections
    -o "ServerAliveCountMax=3"        # 3 missed pings = disconnect
    -o "ConnectTimeout=10"            # 10s connect timeout
    -o "StrictHostKeyChecking=accept-new"  # Accept new hosts, reject changed
    -o "BatchMode=yes"                # No interactive prompts during sync
    -o "Compression=no"               # rsync handles compression
  )

  [[ -n "$DEVICE_KEY" && -f "$DEVICE_KEY" ]] && opts+=(-i "$DEVICE_KEY")
  [[ -n "$DEVICE_PORT" ]] && opts+=(-p "$DEVICE_PORT")

  printf '%s ' "${opts[@]}"
}
```

**Key Management Reference:**

| Aspect | Decision | Rationale |
|--------|----------|-----------|
| Key type | ed25519 | Fastest, smallest, most secure. RSA fallback for legacy devices |
| Key per | Device | Compromise of one device key doesn't affect others |
| Naming | `~/.ssh/omasync_<device-name>` | Clear provenance, easy to audit |
| Permissions | Key: 600, .ssh dir: 700 | Standard SSH requirement |
| Passphrase | Optional, prompted | Recommended for security, not required for automation |
| ssh-agent | Integrated | Avoids repeated passphrase prompts during session |

```bash
# Key generation implementation
generate_device_key() {
  local device_name="$1"
  local key_path="${DEFAULT_SSH_DIR}/omasync_${device_name}"

  # Check if key already exists
  if [[ -f "$key_path" ]]; then
    if ! gum_or_confirm "Key already exists at $key_path. Overwrite?"; then
      ok "Keeping existing key"
      return 0
    fi
  fi

  # Ensure .ssh directory exists with correct permissions
  mkdir -p "$DEFAULT_SSH_DIR"
  chmod 700 "$DEFAULT_SSH_DIR"

  # Ask about passphrase
  local passphrase=""
  if gum_or_confirm "Protect key with a passphrase? (recommended)"; then
    if has_gum; then
      passphrase=$(gum input --password --placeholder "Enter passphrase")
    else
      read -rsp "Enter passphrase: " passphrase; echo
    fi
  fi

  # Generate ed25519 key
  if has_gum; then
    gum spin --title "Generating SSH key..." -- \
      ssh-keygen -t ed25519 -f "$key_path" -N "$passphrase" \
        -C "omasync@${device_name}"
  else
    ssh-keygen -t ed25519 -f "$key_path" -N "$passphrase" \
      -C "omasync@${device_name}"
  fi

  chmod 600 "$key_path"
  chmod 644 "${key_path}.pub"

  # Display public key
  local pub_key
  pub_key=$(cat "${key_path}.pub")

  if has_gum; then
    gum style --border double --padding "1 2" --border-foreground 212 \
      "Public key:" "" "$pub_key"

    # Copy to clipboard if wl-copy available
    if command -v wl-copy &>/dev/null; then
      echo "$pub_key" | wl-copy
      ok "Public key copied to clipboard"
    fi
  else
    echo ""
    echo "Public key:"
    echo "$pub_key"
    echo ""
  fi
}
```

**Remote Key Deployment:**

```bash
deploy_key_to_remote() {
  local device_name="$1"
  load_device "$device_name"

  local pub_key_path="${DEVICE_KEY}.pub"
  [[ -f "$pub_key_path" ]] || { err "Public key not found: $pub_key_path"; return 1; }

  local pub_key
  pub_key=$(cat "$pub_key_path")

  case "$DEVICE_TYPE" in
    linux|macos)
      msg "Deploying key via ssh-copy-id..."
      if has_gum; then
        gum spin --title "Deploying key to $DEVICE_NAME..." -- \
          ssh-copy-id -i "$pub_key_path" -p "$DEVICE_PORT" \
            "${DEVICE_USER}@${DEVICE_HOST}"
      else
        ssh-copy-id -i "$pub_key_path" -p "$DEVICE_PORT" \
          "${DEVICE_USER}@${DEVICE_HOST}"
      fi
      ;;
    termux)
      # ssh-copy-id may not work on Termux — manual approach
      msg "For Termux, add this key manually:"
      show_termux_guide "$pub_key"
      ;;
  esac
}

# Idempotent key check — verify key is already deployed
verify_key_deployed() {
  local device_name="$1"
  load_device "$device_name"

  local pub_key
  pub_key=$(cat "${DEVICE_KEY}.pub" 2>/dev/null) || return 1

  # Extract just the key data (type + base64)
  local key_data
  key_data=$(echo "$pub_key" | awk '{print $1, $2}')

  # Check if key exists in remote authorized_keys
  ssh -o ConnectTimeout=5 -o BatchMode=yes \
    -p "$DEVICE_PORT" -i "$DEVICE_KEY" \
    "${DEVICE_USER}@${DEVICE_HOST}" \
    "grep -qF '$key_data' ~/.ssh/authorized_keys 2>/dev/null" 2>/dev/null
}
```

**Known Hosts Strategy:**

We use `StrictHostKeyChecking=accept-new` which:
- Automatically accepts a host key the first time (no manual `yes` prompt)
- Rejects connections if the host key **changes** (protects against MITM)
- Stores keys in the user's `~/.ssh/known_hosts` (standard location)

This is the right trade-off for a consumer sync tool: secure enough to detect MITM attacks on known hosts, but not so strict that first-connection requires manual intervention.

---

### Phase 2: Sync Profile Management

**Goals:** Profile creation, editing, deletion, listing with gum TUI.

**Deliverables:**
- Add Profile wizard (T13)
- Edit/Remove/List profiles (T14, T15, T16)

**Dependencies:** Phase 0 (Phase 1 for testing with real devices)
**Complexity:** Simple

Profile validation:

```bash
validate_profile() {
  local name="$1"
  load_profile "$name" || return 1

  # Validate local path exists (for push and both)
  if [[ "$DIRECTION" != "pull" && ! -d "$LOCAL_PATH" ]]; then
    warn "Local path does not exist: $LOCAL_PATH"
    warn "It will be created on first pull, or create it manually"
  fi

  # Validate exclude patterns (no path traversal)
  if [[ -n "$RSYNC_EXCLUDE" ]]; then
    IFS=',' read -ra excludes <<< "$RSYNC_EXCLUDE"
    for pattern in "${excludes[@]}"; do
      if [[ "$pattern" == *".."* ]]; then
        err "Invalid exclude pattern (contains ..): $pattern"
        return 1
      fi
    done
  fi

  return 0
}
```

---

### Phase 3: Rsync Integration & Sync Runner

**Goals:** Build rsync commands, execute sync with live progress, log results.

**Deliverables:**
- Rsync command generator (T19)
- Confirmation screen (T20)
- Sync execution with live output (T21)
- Result summary and logging (T22)
- CLI mode (T23)

**Dependencies:** Phase 0, Phase 1, Phase 2
**Complexity:** Complex

**Rsync Flag Strategy:**

| Scenario | Flags | Rationale |
|----------|-------|-----------|
| Base (always) | `-avzh --progress --partial` | Archive mode, compress, human-readable, resume partial |
| Initial sync | Base + `--info=progress2` | Whole-transfer progress for large initial syncs |
| Incremental | Base (default) | Per-file progress suitable for small updates |
| With deletion | Base + `--delete` | Remove files on dest that don't exist on source |
| Bidirectional | Base + `--update` | Only overwrite if source is newer |
| Dry run | Base + `--dry-run` | Preview changes without executing |
| Bandwidth limit | Base + `--bwlimit=KBPS` | Throttle for mobile/metered connections |

**Rsync command builder:**

```bash
build_rsync_cmd() {
  local device="$1" profile="$2" direction_override="${3:-}"

  load_device "$device"
  load_profile "$profile"

  local direction="${direction_override:-$DIRECTION}"

  # Build SSH command string
  local ssh_cmd="ssh"
  ssh_cmd+=" -p ${DEVICE_PORT}"
  [[ -n "$DEVICE_KEY" && -f "$DEVICE_KEY" ]] && ssh_cmd+=" -i ${DEVICE_KEY}"

  # Multiplexing options
  local socket_dir="/tmp/omasync-${USER}"
  mkdir -p "$socket_dir" && chmod 700 "$socket_dir"
  ssh_cmd+=" -o ControlMaster=auto"
  ssh_cmd+=" -o ControlPath=${socket_dir}/%r@%h:%p"
  ssh_cmd+=" -o ControlPersist=600"
  ssh_cmd+=" -o ServerAliveInterval=30"
  ssh_cmd+=" -o ServerAliveCountMax=3"
  ssh_cmd+=" -o Compression=no"

  # Build rsync flags
  local -a flags
  IFS=' ' read -ra flags <<< "$RSYNC_BASE_FLAGS"

  # Add excludes
  if [[ -n "$RSYNC_EXCLUDE" ]]; then
    IFS=',' read -ra excludes <<< "$RSYNC_EXCLUDE"
    for pattern in "${excludes[@]}"; do
      pattern=$(echo "$pattern" | xargs)  # trim whitespace
      [[ -n "$pattern" ]] && flags+=(--exclude="$pattern")
    done
  fi

  # Delete handling
  [[ "$RSYNC_DELETE" == "true" && "$direction" != "both" ]] && flags+=(--delete)

  # Bidirectional uses --update
  [[ "$direction" == "both" ]] && flags+=(--update)

  # Dry run
  [[ "$DRY_RUN" == "true" ]] && flags+=(--dry-run)

  # Build source and destination
  local remote="${DEVICE_USER}@${DEVICE_HOST}:${REMOTE_PATH}/"
  local local_path="${LOCAL_PATH}/"

  local -a cmd=(rsync "${flags[@]}" -e "$ssh_cmd")

  case "$direction" in
    push) cmd+=("$local_path" "$remote") ;;
    pull) cmd+=("$remote" "$local_path") ;;
    both)
      # Return two commands separated by newline
      echo "rsync ${flags[*]} -e \"$ssh_cmd\" \"$remote\" \"$local_path\""
      echo "rsync ${flags[*]} -e \"$ssh_cmd\" \"$local_path\" \"$remote\""
      return
      ;;
  esac

  printf '%s ' "${cmd[@]}"
}
```

**Sync execution with logging:**

```bash
execute_sync() {
  local device="$1" profile="$2"
  local timestamp
  timestamp=$(date +%Y%m%d-%H%M%S)
  local log_file="${LOG_DIR}/${device}_${profile}_${timestamp}.log"

  mkdir -p "$LOG_DIR"

  # Build command(s)
  local cmds
  cmds=$(build_rsync_cmd "$device" "$profile")

  local exit_code=0

  while IFS= read -r cmd; do
    [[ -z "$cmd" ]] && continue

    echo "$ $cmd" | tee -a "$log_file"
    echo "" | tee -a "$log_file"

    # Execute rsync with live output (no gum wrapping — raw terminal)
    eval "$cmd" 2>&1 | tee -a "$log_file"
    local rc=${PIPESTATUS[0]}

    if [[ $rc -ne 0 ]]; then
      exit_code=$rc
      err "rsync exited with code $rc"
    fi
  done <<< "$cmds"

  # Update last-sync timestamp
  if [[ $exit_code -eq 0 ]]; then
    local ts_file="$OMASYNC_DATA_DIR/${device}_${profile}.last_sync"
    date -Iseconds > "$ts_file"
  fi

  # Rotate logs
  rotate_logs "$device" "$profile"

  return $exit_code
}

rotate_logs() {
  local device="$1" profile="$2"
  local pattern="${LOG_DIR}/${device}_${profile}_*.log"
  local count=${LOG_KEEP_COUNT:-10}

  local -a logs
  mapfile -t logs < <(ls -t $pattern 2>/dev/null)

  if [[ ${#logs[@]} -gt $count ]]; then
    for (( i=count; i<${#logs[@]}; i++ )); do
      rm -f "${logs[$i]}"
    done
  fi
}
```

**Conflict Resolution for Bidirectional Sync:**

True bidirectional sync with conflict resolution requires tracking file states between syncs (like Unison does). Rsync alone cannot merge conflicts. Our strategy:

1. **`--update` flag**: Only overwrite files if the source is newer (based on mtime)
2. **Pull first, then push**: Ensures remote changes arrive before we push local changes
3. **No `--delete` in bidirectional mode**: Prevents accidental deletion of files that exist only on one side
4. **Clear documentation**: Users are warned that bidirectional mode is "last-writer-wins" — not merge-based

**Trade-off:** This approach is simple and safe but won't handle true conflicts (same file modified on both sides between syncs). For that, we would need Unison — documented as a Future Enhancement.

---

### Phase 4: Tailscale DNS Integration

**Goals:** Resolve device hostnames via Tailscale MagicDNS, with graceful fallback.

**Deliverables:**
- Tailscale hostname resolution
- DNS caching
- Fallback mechanism
- Integration with device config

**Dependencies:** Phase 1
**Complexity:** Simple

**How Tailscale MagicDNS Works:**

Tailscale assigns each device a name in the tailnet's DNS namespace. With MagicDNS enabled:
- Devices are reachable as `<hostname>` (short name) within the tailnet
- Or as `<hostname>.<tailnet-name>.ts.net` (FQDN)
- Each device also gets a stable 100.x.y.z IP address
- `tailscale status` lists all devices with their names and IPs
- `tailscale ip <hostname>` resolves a device name to its Tailscale IP

**Implementation:**

```bash
# Tailscale DNS resolution with fallback
resolve_host() {
  local device="$1"
  load_device "$device"

  local resolved_host="$DEVICE_HOST"

  # If host looks like a Tailscale name (not an IP), try resolving
  if [[ ! "$DEVICE_HOST" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && \
     command -v tailscale &>/dev/null; then

    # Try tailscale DNS resolution
    local ts_ip
    ts_ip=$(tailscale ip "$DEVICE_HOST" 2>/dev/null | head -1) || true

    if [[ -n "$ts_ip" ]]; then
      resolved_host="$ts_ip"
    else
      # Check if device is in tailscale status
      ts_ip=$(tailscale status --json 2>/dev/null | \
        jq -r --arg name "$DEVICE_HOST" \
        '.Peer[] | select(.HostName == $name) | .TailscaleIPs[0]' 2>/dev/null) || true

      if [[ -n "$ts_ip" && "$ts_ip" != "null" ]]; then
        resolved_host="$ts_ip"
      fi
    fi
  fi

  echo "$resolved_host"
}

# Check if a device is reachable via Tailscale
is_tailscale_available() {
  command -v tailscale &>/dev/null && \
    tailscale status &>/dev/null 2>&1
}

# List Tailscale devices for discovery
list_tailscale_devices() {
  if ! is_tailscale_available; then
    return 1
  fi

  tailscale status --json 2>/dev/null | \
    jq -r '.Peer[] | select(.Online == true) | "\(.HostName)\t\(.TailscaleIPs[0])\t\(.OS)"' 2>/dev/null
}
```

**Device Config Enhancement:**

Add an optional `DEVICE_TAILSCALE` field:

```bash
DEVICE_NAME="ThinkPad"
DEVICE_HOST="thinkpad"              # Tailscale hostname or IP
DEVICE_PORT="22"
DEVICE_USER="mino"
DEVICE_KEY="$HOME/.ssh/omasync_thinkpad"
DEVICE_TYPE="linux"
DEVICE_TAILSCALE="true"             # Try Tailscale resolution first
```

When `DEVICE_TAILSCALE=true`, the sync runner:
1. Tries `tailscale ip <DEVICE_HOST>` first
2. Falls back to DNS/IP resolution of `DEVICE_HOST`
3. Caches the resolved IP for the duration of the session

**Edge Cases:**
- **Tailscale not installed:** Silent fallback to DEVICE_HOST as-is
- **Tailscale not running:** Silent fallback
- **Device offline on Tailscale:** `tailscale ip` fails, fallback to DEVICE_HOST
- **Duplicate hostnames:** Tailscale handles this by appending a suffix; we use the IP from `tailscale status --json`

---

### Phase 5: Polish & Extras

**Goals:** Dry-run mode, logging, last-sync tracking, systemd timers, Waybar integration.

**Deliverables:**
- Dry-run mode (T24)
- Sync logging with rotation (T25)
- Last-sync tracking (T26)
- Systemd timer generation (T27)
- Waybar module (T28)

**Dependencies:** Phase 3
**Complexity:** Moderate

**Systemd Timer Generation:**

Follows the same pattern as `omablue-bluetooth-autoconnect`. The template files already exist at `config/systemd/user/omasync@.service` and `omasync@.timer`.

```bash
setup_systemd_timer() {
  local device="$1" profile="$2"
  local instance="${device}_${profile}"
  local service_dir="$HOME/.config/systemd/user"

  mkdir -p "$service_dir"

  # Generate service unit
  cat > "${service_dir}/omasync@${instance}.service" << EOF
[Unit]
Description=Omasync Sync — ${device}/${profile}
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=%h/.local/share/omablue/bin/omasync --device ${device} --profile ${profile} --yes
StandardOutput=journal
StandardError=journal

Nice=19
IOSchedulingClass=idle

[Install]
WantedBy=default.target
EOF

  # Generate timer unit
  local schedule
  schedule=$(gum_or_select "Sync frequency:" \
    "hourly" "daily" "weekly" "custom")

  local on_calendar="$schedule"
  if [[ "$schedule" == "custom" ]]; then
    on_calendar=$(gum_or_read "OnCalendar expression (e.g. *-*-* 08:00:00)")
  fi

  cat > "${service_dir}/omasync@${instance}.timer" << EOF
[Unit]
Description=Omasync Timer — ${device}/${profile}

[Timer]
OnCalendar=${on_calendar}
Persistent=true
RandomizedDelaySec=60

[Install]
WantedBy=timers.target
EOF

  systemctl --user daemon-reload
  systemctl --user enable --now "omasync@${instance}.timer"
  ok "Scheduled sync: ${device}/${profile} (${on_calendar})"
}
```

---

## 5. Gum Integration Specifications

### 5.1 Gum Command Mapping

| Operation | Gum Component | Example |
|-----------|--------------|---------|
| Main menu | `gum choose` | `gum choose "Manage Devices" "Manage Profiles" "Test Connection" "Quit"` |
| Text input | `gum input` | `gum input --placeholder "Device name" --char-limit 64` |
| Password input | `gum input --password` | `gum input --password --placeholder "Passphrase (optional)"` |
| Multi-select | `gum choose --no-limit` | `printf '%s\n' "${profiles[@]}" \| gum choose --no-limit --header "Select profiles"` |
| Yes/No confirm | `gum confirm` | `gum confirm "Delete device pixel-phone?"` |
| Long-running ops | `gum spin` | `gum spin --title "Testing connection..." -- ssh [opts] exit` |
| Styled output | `gum style` | `gum style --border double --foreground 212 --padding "1 2" "Success"` |
| Display guide | `gum format` | `cat termux-guide.md \| gum format` |
| Long output | `gum pager` | `rsync --dry-run ... \| gum pager` |
| Filter/search | `gum filter` | `list_devices \| gum filter --placeholder "Search devices..."` |

### 5.2 Styling Conventions

```bash
# Color scheme (consistent across all omasync TUI)
readonly GUM_SUCCESS_FG="46"      # Green
readonly GUM_ERROR_FG="196"       # Red
readonly GUM_WARN_FG="214"        # Orange
readonly GUM_INFO_FG="39"         # Blue
readonly GUM_ACCENT_FG="212"      # Pink/magenta (borders, highlights)

# Styled output helpers
show_success() {
  if has_gum; then
    gum style --foreground "$GUM_SUCCESS_FG" "✓ $1"
  else
    echo "✓ $1"
  fi
}

show_error() {
  if has_gum; then
    gum style --foreground "$GUM_ERROR_FG" --bold "✗ $1"
  else
    echo "✗ $1" >&2
  fi
}

show_box() {
  local title="$1"; shift
  if has_gum; then
    gum style --border rounded --border-foreground "$GUM_ACCENT_FG" \
      --padding "1 2" --margin "1 0" "$@"
  else
    echo "--- $title ---"
    printf '%s\n' "$@"
    echo "---"
  fi
}
```

### 5.3 Error Handling Patterns

```bash
# Gum exit codes:
#   0 = success (selection made, confirm=yes)
#   1 = cancelled (Ctrl+C, Esc, confirm=no)
#   130 = SIGINT

# Standard pattern for interruptible gum prompts:
device=$(gum choose --header "Select device" "${devices[@]}") || {
  msg "Cancelled"
  return 0
}

# Pattern for confirmation with fallback:
if ! gum_or_confirm "Proceed with sync?"; then
  msg "Cancelled"
  return 0
fi
```

### 5.4 Fallback When Gum Not Installed

Every gum interaction has a POSIX-compatible fallback via the `gum_or_*` wrapper functions defined in Phase 0. The `check_dependencies` function warns if gum is missing:

```bash
check_dependencies() {
  local missing=()
  for cmd in ssh rsync; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    die "Required tools not found: ${missing[*]}"
  fi

  if ! command -v gum &>/dev/null; then
    warn "gum not installed — TUI features will be limited"
    warn "Install via: brew install gum"
  fi
}
```

---

## 6. Configuration File Specifications

### 6.1 Format Decision: Bash-Sourced Key=Value

**Chosen format:** Bash key=value files (same as existing Omablue configs)

**Rationale:**
- Consistent with `bluetooth-autoconnect.conf`, `omasync.conf` already in the project
- No external parser needed (no jq/yq dependency for config)
- Safe loading via whitelist-only `case` parsing (no `source` of untrusted files)
- Simple to edit by hand
- Variable expansion works naturally (`$HOME`)

**Why not TOML/YAML/JSON:**
- Would require `jq`, `yq`, or `tomlq` as additional dependencies
- Breaks consistency with existing Omablue config patterns
- Overkill for flat key=value config with no nesting needed

### 6.2 Example Configuration Files

**Global Config — `~/.config/omablue/omasync/omasync.conf`:**

```bash
# omasync — Global Configuration
# This file is loaded by omasync and omasync-setup

# Directory for sync logs
LOG_DIR="$HOME/.local/share/omablue/omasync/logs"

# Default SSH key directory
DEFAULT_SSH_DIR="$HOME/.ssh"

# Base rsync flags (applied to every sync)
RSYNC_BASE_FLAGS="-avzh --progress --partial"

# Global dry-run override (normally controlled per-run via --dry-run)
DRY_RUN="false"

# Number of sync logs to keep per device+profile pair
LOG_KEEP_COUNT=10
```

**Device Config — `~/.config/omablue/omasync/devices/pixel-phone.conf`:**

```bash
# Device: Pixel Phone (Termux)
# Created by omasync-setup on 2026-02-13

DEVICE_NAME="Pixel Phone"
DEVICE_HOST="192.168.1.50"
DEVICE_PORT="8022"
DEVICE_USER="u0_a123"
DEVICE_KEY="$HOME/.ssh/omasync_pixel-phone"
DEVICE_TYPE="termux"
DEVICE_TAILSCALE="false"
```

**Profile Config — `~/.config/omablue/omasync/profiles/music.conf`:**

```bash
# Sync Profile: Music
# Created by omasync-setup on 2026-02-13

PROFILE_NAME="Music"
LOCAL_PATH="$HOME/Music"
REMOTE_PATH="/storage/emulated/0/Music"
DIRECTION="push"
RSYNC_EXCLUDE=".thumbnails,.cache,*.tmp"
RSYNC_DELETE="false"
```

### 6.3 Validation Rules

| Field | Type | Rules |
|-------|------|-------|
| `DEVICE_NAME` | String | Required, non-empty |
| `DEVICE_HOST` | String | Required, non-empty, no whitespace |
| `DEVICE_PORT` | Integer | 1–65535, defaults to 22 |
| `DEVICE_USER` | String | Required, non-empty, no whitespace |
| `DEVICE_KEY` | Path | Optional, must be readable file if set |
| `DEVICE_TYPE` | Enum | `termux`, `linux`, `macos` |
| `DEVICE_TAILSCALE` | Bool | `true` or `false`, defaults to `false` |
| `PROFILE_NAME` | String | Required, non-empty |
| `LOCAL_PATH` | Path | Required, valid directory for push/both |
| `REMOTE_PATH` | Path | Required, non-empty |
| `DIRECTION` | Enum | `push`, `pull`, `both` |
| `RSYNC_EXCLUDE` | String | Comma-separated patterns, no `..` |
| `RSYNC_DELETE` | Bool | `true` or `false`, defaults to `false` |

### 6.4 Migration Path

Since this is a new feature, no migration needed. Future config changes should:
1. Add new fields with defaults (backward-compatible)
2. The whitelist-based loader ignores unknown fields automatically
3. If a breaking change is needed, bump a `CONFIG_VERSION` field and add migration logic

---

## 7. Security Considerations

### 7.1 Threat Model

| Threat | Likelihood | Impact | Mitigation |
|--------|-----------|--------|------------|
| SSH key stolen from disk | Low | High | File permissions (600), optional passphrase, per-device keys |
| MITM on first connection | Low | High | `StrictHostKeyChecking=accept-new` — TOFU model |
| MITM on subsequent connection | Very Low | High | Known hosts verification rejects changed keys |
| Config file tampering | Low | Medium | Whitelist-based config loading, no `source`/`eval` |
| Path traversal in exclude patterns | Low | Low | Validation rejects `..` in patterns |
| Passphrase exposure in process list | Medium | Medium | Use `ssh-agent` instead of passing via CLI args |
| Multiplexed socket hijacking | Very Low | High | Socket in user-owned dir with mode 700 |
| Sync deletes important files | Medium | High | `--delete` requires explicit opt-in, dry-run available |
| Connection credential logging | Low | Medium | No passwords in logs, keys referenced by path only |

### 7.2 Key Mitigations

1. **No `source` or `eval` on config files** — Whitelist-only `case` statement parsing prevents arbitrary code execution via malicious config values
2. **Per-device SSH keys** — Compromise of one device's key doesn't grant access to others
3. **SSH multiplexing sockets** — Created in `/tmp/omasync-$USER/` with mode 700 on the directory
4. **No secrets in config files** — Keys are referenced by filesystem path, never embedded
5. **Passphrase input via `gum input --password`** — Input is masked, not echoed, not logged
6. **BatchMode=yes during sync** — Prevents interactive password prompts that could hang
7. **Connection timeout (10s) + keepalive (30s)** — Prevents indefinite hangs
8. **`--delete` requires explicit opt-in** — Not enabled by default, confirmation dialog in TUI

### 7.3 Audit Logging

- Every sync operation is logged to `$LOG_DIR/<device>_<profile>_<timestamp>.log`
- Logs include: rsync command (with keys referenced by path, not content), full rsync output, exit code
- Log rotation keeps last N logs per device+profile pair (configurable, default 10)
- Systemd journal captures timer-based sync output via `StandardOutput=journal`

---

## 8. Error Handling and Edge Cases

### 8.1 Common Failure Scenarios

| Scenario | Detection | Recovery | User Message |
|----------|-----------|----------|--------------|
| Device unreachable | SSH exit code ≠ 0 | Retry prompt, check connection hints | "Cannot reach device. Is it online? Is sshd running?" |
| SSH key rejected | SSH auth failure | Show key deployment instructions | "Authentication failed. Re-deploy your SSH key?" |
| Remote path doesn't exist | rsync exit code 23 | Offer to create it remotely | "Remote path not found. Create it?" |
| Local path doesn't exist | Pre-check `[[ -d ]]` | Offer to create it | "Local path not found. Create it?" |
| Disk full (local or remote) | rsync exit code 11/23 | Show space info | "Transfer failed — not enough disk space" |
| Rsync interrupted (Ctrl+C) | Trap SIGINT | `--partial` preserves progress | "Sync interrupted. Partial files preserved for resume." |
| No devices configured | Empty devices dir | Direct to omasync-setup | "No devices configured. Run omasync-setup first." |
| No profiles configured | Empty profiles dir | Direct to omasync-setup | "No profiles configured. Run omasync-setup first." |
| Gum not installed | `command -v gum` | Fallback to basic prompts | "gum not found — using basic prompts. Install via: brew install gum" |
| Tailscale not available | `command -v tailscale` | Silent fallback to DEVICE_HOST | (no user message — transparent fallback) |
| Stale multiplexed connection | SSH timeout/error | Remove socket, reconnect | (automatic — transparent to user) |

### 8.2 Rsync Exit Codes Reference

| Code | Meaning | Action |
|------|---------|--------|
| 0 | Success | Report success |
| 1 | Syntax error | Bug — log and report |
| 2 | Protocol incompatibility | Version mismatch — warn |
| 3 | Errors selecting I/O files | Permission issue — hint |
| 5 | Error starting client-server | SSH problem — check connection |
| 10 | Error in socket I/O | Connection dropped — offer retry |
| 11 | Error in file I/O | Disk full / permission — hint |
| 12 | Error in rsync protocol | Connection issue — offer retry |
| 23 | Partial transfer (some errors) | Warn, show which files failed |
| 24 | Partial transfer (vanished files) | Files changed during sync — informational |
| 30 | Timeout | Connection too slow — suggest bandwidth limit |

### 8.3 Debugging

```bash
# Verbose mode (add to omasync CLI)
omasync --device pixel --profile music --verbose

# Shows:
# - Resolved host (Tailscale DNS or direct)
# - Full rsync command before execution
# - SSH multiplexing state
# - Rsync verbose output (-vv)
```

---

## 9. Testing Strategy

### 9.1 Unit Test Areas

Since this is a bash project, "unit tests" means testing individual functions:

- **Config loading:** Valid configs, missing fields, empty files, malicious values
- **Name sanitization:** Spaces, special chars, unicode, empty strings
- **Rsync command building:** Push, pull, both, with/without excludes, with/without delete
- **Tailscale resolution:** Available, unavailable, device not found
- **Log rotation:** Correct number of logs kept, oldest deleted first

Testing framework: Simple bash test functions or [bats](https://github.com/bats-core/bats-core) if desired.

### 9.2 Integration Test Scenarios

| Test | Setup | Expected |
|------|-------|----------|
| Full push sync | Local device via localhost | Files appear at destination |
| Full pull sync | Local device via localhost | Files appear locally |
| Bidirectional sync | Local device, files on both sides | Both sides updated |
| Sync with excludes | Files matching exclude patterns | Excluded files not transferred |
| Sync with --delete | Extra files on destination | Extra files removed |
| Dry-run mode | Any sync scenario | No files modified, output shown |
| Connection failure | Invalid host | Error message shown, no crash |
| Interrupted sync | Ctrl+C during transfer | Partial files preserved |
| CLI mode | `omasync --device X --profile Y --yes` | Runs without prompts |

### 9.3 TUI Testing

Manual testing checklist:
- [ ] Every gum prompt can be cancelled with Ctrl+C without crash
- [ ] Every menu returns to parent on cancel
- [ ] Fallback prompts work when gum is absent
- [ ] Long device/profile names display correctly
- [ ] Connection test spinner works (doesn't hang on failure)
- [ ] Rsync progress output is readable (not garbled by gum)
- [ ] Error messages include actionable hints

### 9.4 Platform Testing

- [ ] Linux (Fedora/secureblue) — primary target
- [ ] macOS — verify rsync flags compatibility (system rsync is old, brew rsync recommended)
- [ ] WSL — verify SSH agent forwarding works
- [ ] Termux (as remote target) — verify sshd + rsync work

---

## 10. Future Enhancements (v2.0+)

1. **Unison integration** — True bidirectional sync with conflict detection and merge
2. **Sync dashboard** — `gum table` showing all devices, profiles, last sync times, status
3. **Real-time file watching** — `inotifywait` triggers sync on file changes
4. **Bandwidth scheduling** — Different `--bwlimit` values for different times of day
5. **Sync groups** — Run multiple device+profile combinations in one command
6. **Encrypted backups** — Integrate with `age` or `gpg` for encrypted sync
7. **Notification integration** — Desktop notifications on sync completion/failure
8. **SSH config generation** — Write `~/.ssh/config` entries for omasync devices
9. **Remote storage quota check** — Pre-sync check of available space on remote
10. **Profile templates** — Pre-built profiles for common scenarios (phone photos, music library, documents)

---

## Appendix A: SSH Reference

### Key Configuration Directives (ssh_config)

```
# Connection multiplexing
ControlMaster auto          # Reuse existing connections
ControlPath /tmp/omasync-%r@%h:%p  # Socket path (%r=user, %h=host, %p=port)
ControlPersist 600          # Keep master alive 600s after last session

# Keepalive
ServerAliveInterval 30      # Send keepalive every 30 seconds
ServerAliveCountMax 3       # Disconnect after 3 missed keepalives

# Security
StrictHostKeyChecking accept-new  # Accept new hosts, reject changed
IdentitiesOnly yes          # Only use specified key, not all from agent

# Performance
Compression no              # Let rsync handle compression
ConnectTimeout 10           # 10 second connection timeout
BatchMode yes               # No interactive prompts
```

### Key Generation Commands

```bash
# Ed25519 (recommended — fastest, smallest, most secure)
ssh-keygen -t ed25519 -f ~/.ssh/omasync_device -C "omasync@device"

# RSA (fallback for legacy systems)
ssh-keygen -t rsa -b 4096 -f ~/.ssh/omasync_device -C "omasync@device"

# Add key to agent (avoids repeated passphrase prompts)
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/omasync_device
```

## Appendix B: Rsync Reference

### Common Flag Sets

```bash
# Base flags (every sync)
-a          # Archive: -rlptgoD (recursive, links, perms, times, group, owner, devices)
-v          # Verbose output
-z          # Compress during transfer
-h          # Human-readable numbers
--progress  # Per-file progress
--partial   # Keep partial files (resume interrupted transfers)

# Additions for specific scenarios
--delete          # Remove files on dest not on source
--update          # Skip files newer on dest (for bidirectional)
--dry-run         # Preview only, don't modify
--info=progress2  # Whole-transfer progress (good for initial syncs)
--bwlimit=1000    # Limit bandwidth to 1000 KB/s
--stats           # Show transfer statistics at end
--exclude=PATTERN # Skip files matching pattern
--exclude-from=FILE # Read exclude patterns from file

# SSH transport
-e "ssh -p PORT -i KEY -o ControlMaster=auto ..."
```

## Appendix C: Tailscale CLI Reference

```bash
# Check Tailscale status
tailscale status                    # List all devices, IPs, status
tailscale status --json             # JSON output for programmatic use

# Resolve device to IP
tailscale ip <hostname>             # Returns Tailscale IP for device
tailscale ip -4 <hostname>          # IPv4 only

# Check if Tailscale is running
tailscale status &>/dev/null        # Exit code 0 = running

# JSON structure (relevant fields):
# {
#   "Peer": {
#     "<node-id>": {
#       "HostName": "device-name",
#       "DNSName": "device-name.tailnet.ts.net",
#       "TailscaleIPs": ["100.x.y.z"],
#       "Online": true,
#       "OS": "linux"
#     }
#   }
# }
```

## Appendix D: Task Checklist

Cross-reference with `task-omasync.md`:

| Task | Phase | Description | Complexity |
|------|-------|-------------|------------|
| T01 | 0 | Config directory structure | Simple |
| T02 | 0 | omasync-lib.sh helpers | Moderate |
| T03 | 0 | omasync-setup skeleton | Simple |
| T04 | 0 | omasync skeleton | Simple |
| T05 | 1 | Add Device wizard | Moderate |
| T06 | 1 | SSH key generation | Moderate |
| T07 | 1 | Termux setup guide | Simple |
| T08 | 1 | Linux/macOS setup guide | Simple |
| T09 | 1 | Connection test | Simple |
| T10 | 1 | Edit Device | Simple |
| T11 | 1 | Remove Device | Simple |
| T12 | 1 | List Devices | Simple |
| T13 | 2 | Add Profile wizard | Simple |
| T14 | 2 | Edit Profile | Simple |
| T15 | 2 | Remove Profile | Simple |
| T16 | 2 | List Profiles | Simple |
| T17 | 3 | Interactive device selection | Simple |
| T18 | 3 | Interactive profile selection | Simple |
| T19 | 3 | Rsync command generator | Complex |
| T20 | 3 | Confirmation screen | Simple |
| T21 | 3 | Sync execution | Moderate |
| T22 | 3 | Result summary + logging | Moderate |
| T23 | 3 | CLI mode | Moderate |
| T24 | 4 | Dry-run mode | Simple |
| T25 | 4 | Sync logging + rotation | Simple |
| T26 | 4 | Last-sync tracking | Simple |
| T27 | 4 | Systemd timer generation | Moderate |
| T28 | 4 | Waybar module | Simple |
