# omasync — SSH Sync Manager for Omablue

## Vision

A TUI tool (foot + gum) to manage file synchronization between devices over SSH
using rsync. Two scripts: `omasync-setup` for configuration and `omasync` for
running syncs. Follows existing omablue patterns (strict bash, lib.sh helpers,
`~/.config/omablue/` configs, gum for TUI).

---

## Architecture

### Scripts

| Script          | Purpose                                        |
| --------------- | ---------------------------------------------- |
| `omasync-setup` | Device registration, SSH keys, sync profiles   |
| `omasync`       | Launcher — pick device, pick profile, run sync |

### Config Layout

```
~/.config/omablue/omasync/
├── omasync.conf              # Global defaults (rsync flags, log path)
├── devices/
│   ├── pixel-phone.conf      # One file per device
│   └── thinkpad.conf
└── profiles/
    ├── music.conf             # One file per sync profile
    ├── documents.conf
    └── photos.conf
```

### Device Config Format (`devices/*.conf`)

```bash
DEVICE_NAME="Pixel Phone"
DEVICE_HOST="192.168.1.50"
DEVICE_PORT="8022"
DEVICE_USER="u0_a123"
DEVICE_KEY="$HOME/.ssh/omasync_pixel-phone"
DEVICE_TYPE="termux"           # termux | linux | macos
```

### Sync Profile Format (`profiles/*.conf`)

```bash
PROFILE_NAME="Music"
LOCAL_PATH="$HOME/Music"
REMOTE_PATH="/storage/emulated/0/Music"
DIRECTION="push"               # push | pull | both
RSYNC_EXCLUDE=".thumbnails,.cache,*.tmp"
RSYNC_DELETE="false"           # whether to use --delete
```

### Global Config (`omasync.conf`)

```bash
LOG_DIR="$HOME/.local/share/omablue/omasync/logs"
DEFAULT_SSH_DIR="$HOME/.ssh"
RSYNC_BASE_FLAGS="-avzh --progress --partial"
DRY_RUN="false"
```

---

## Roadmap

### Phase 0 — Skeleton & Foundations

Set up the file structure, shared helpers, config directory creation,
and dependency checks. No user-facing features yet — just the scaffolding
that Phase 1 and Phase 2 build on.

### Phase 1 — omasync-setup: Device Management

The guided wizard to register a new device. This is the most complex part
because it must handle SSH key generation, teach Termux/sshd setup, and
verify connectivity. Split into sub-steps:

1. **Add Device wizard** (gum input/choose prompts)
   - Device name (sanitized for filename)
   - Host/IP, port, user, device type
2. **SSH Key handling**
   - Generate dedicated keypair (`~/.ssh/omasync_<device>`)
   - Display public key with copy instructions
   - For Termux: show step-by-step guide (install openssh, add key to
     authorized_keys, start sshd)
   - For Linux/macOS: show ssh-copy-id command
3. **Connection test** — `ssh -o ConnectTimeout=5 ...`
4. **Edit / Remove device**
5. **List devices** with connection status

### Phase 2 — omasync-setup: Sync Profiles

After devices exist, users create sync profiles that define what to sync
and in which direction.

1. **Add Profile wizard**
   - Profile name
   - Local path (with validation)
   - Remote path
   - Direction (push / pull / both)
   - Exclude patterns (optional)
   - Whether to use `--delete`
2. **Edit / Remove profile**
3. **List profiles**

### Phase 3 — omasync: The Runner

The daily-use script. Launch it, pick what to sync, execute.

1. **Device selection** — gum choose from configured devices
2. **Profile selection** — gum choose (multi-select) from profiles
3. **Confirmation screen** — summary of what will happen (dry-run preview)
4. **Execution** — rsync with live progress output
5. **Result summary** — success/failure, bytes transferred, log path
6. **Quick mode** — `omasync --device pixel --profile music` for scripting

### Phase 4 — Polish & Extras

1. **Dry-run mode** — preview what rsync would do
2. **Sync logs** — timestamped logs under `LOG_DIR`
3. **Last-sync tracking** — store last sync timestamp per device+profile
4. **Scheduled syncs** — optional systemd timer generation (same pattern
   as battery-monitor)
5. **Waybar integration** — optional module showing last sync status

---

## Task Breakdown

### Phase 0 — Skeleton & Foundations

- [ ] **T01** Create config directory structure
  - Create `~/.config/omablue/omasync/`, `devices/`, `profiles/`
  - Generate default `omasync.conf` if missing
  - Create `LOG_DIR`

- [ ] **T02** Write `omasync-lib.sh` (shared helpers)
  - `load_device <name>` — source device conf with validation
  - `load_profile <name>` — source profile conf with validation
  - `list_devices` — list configured device names
  - `list_profiles` — list configured profile names
  - `test_connection <device>` — ssh connectivity check
  - `sanitize_name` — reuse from lib.sh or duplicate
  - `ensure_dirs` — create config dirs if missing
  - `load_global_config` — source omasync.conf

- [ ] **T03** Write `omasync-setup` script skeleton
  - Shebang, strict mode, PATH, dependency checks
  - Source lib.sh + omasync-lib.sh
  - Main menu (gum choose): Devices / Profiles / Quit
  - Dispatch to sub-menus

- [ ] **T04** Write `omasync` script skeleton
  - Shebang, strict mode, PATH, dependency checks
  - Source lib.sh + omasync-lib.sh
  - Argument parsing (--device, --profile, --dry-run)
  - Placeholder for interactive and CLI modes

### Phase 1 — Device Management (omasync-setup)

- [ ] **T05** Implement "Add Device" wizard
  - `gum input` for name, host, port, user
  - `gum choose` for device type (termux / linux / macos)
  - Validate inputs (no empty, valid port range)
  - Save to `devices/<sanitized-name>.conf`

- [ ] **T06** Implement SSH key generation
  - Check if key already exists, prompt to overwrite or reuse
  - `ssh-keygen -t ed25519 -f ~/.ssh/omasync_<device> -N ""`
  - Display public key with `gum style` box
  - Offer `wl-copy` to clipboard if available

- [ ] **T07** Write Termux setup guide (displayed via gum)
  - Step-by-step instructions shown with `gum style` / `gum pager`
  - Cover: `pkg install openssh`, `sshd`, `whoami`, `ifconfig`
  - Explain: `authorized_keys` location on Termux
  - Explain: default port 8022
  - Pause between steps with `gum confirm "Ready for next step?"`

- [ ] **T08** Write Linux/macOS setup guide
  - Show `ssh-copy-id` command pre-filled with device info
  - Alternative: manual key copy instructions
  - Explain: enabling sshd (`systemctl enable --now sshd`)

- [ ] **T09** Implement connection test
  - `ssh -o ConnectTimeout=5 -o BatchMode=yes -p PORT -i KEY user@host exit`
  - Show spinner with `gum spin`
  - Display result (success with green / failure with red + hint)
  - On failure: suggest common fixes (firewall, sshd not running, wrong port)

- [ ] **T10** Implement "Edit Device"
  - `gum choose` to pick device
  - Show current values, `gum input --value` to edit each field
  - Save updated config

- [ ] **T11** Implement "Remove Device"
  - `gum choose` to pick device
  - `gum confirm` before deletion
  - Remove device conf file
  - Optionally remove SSH key pair

- [ ] **T12** Implement "List Devices"
  - Table or styled list showing: name, host, port, type
  - Optional: connection status (live check with spinner)

### Phase 2 — Sync Profiles (omasync-setup)

- [ ] **T13** Implement "Add Profile" wizard
  - `gum input` for profile name
  - `gum input` for local path (validate exists)
  - `gum input` for remote path
  - `gum choose` for direction (push / pull / both)
  - `gum input` for exclude patterns (comma-separated, optional)
  - `gum confirm` for --delete flag
  - Save to `profiles/<sanitized-name>.conf`

- [ ] **T14** Implement "Edit Profile"
  - `gum choose` to pick profile
  - Show current values, allow field edits
  - Save updated config

- [ ] **T15** Implement "Remove Profile"
  - `gum choose` to pick profile
  - `gum confirm` before deletion
  - Remove profile conf file

- [ ] **T16** Implement "List Profiles"
  - Table or styled list: name, local path, remote path, direction

### Phase 3 — omasync Runner

- [ ] **T17** Implement interactive device selection
  - `gum choose` from `list_devices`
  - Verify device reachable (quick test, skippable)
  - Handle "no devices configured" → point to omasync-setup

- [ ] **T18** Implement interactive profile selection
  - `gum choose` (allow multi-select) from `list_profiles`
  - Handle "no profiles configured" → point to omasync-setup

- [ ] **T19** Build rsync command generator
  - Compose rsync command from device + profile config
  - Handle push vs pull vs both (two commands)
  - Apply excludes (`--exclude=PATTERN` for each)
  - Apply `--delete` if configured
  - Apply global `RSYNC_BASE_FLAGS`
  - Apply `--dry-run` if requested

- [ ] **T20** Implement confirmation screen
  - Show summary: device, profile(s), direction, paths
  - Show the exact rsync command(s) that will run
  - `gum confirm "Proceed?"` or `gum choose "Run / Dry-run first / Cancel"`

- [ ] **T21** Implement sync execution
  - Run rsync with live terminal output (no gum wrapping — raw output)
  - Capture exit code
  - Handle interruption (trap SIGINT → confirm cancel)

- [ ] **T22** Implement result summary
  - Show success/failure status
  - Display transfer stats (parse rsync output or use `--stats`)
  - Log output to `LOG_DIR/<device>_<profile>_<timestamp>.log`

- [ ] **T23** Implement CLI mode (non-interactive)
  - `omasync --device <name> --profile <name> [--dry-run] [--yes]`
  - Skip gum prompts, run directly
  - Useful for scripting and scheduled syncs

### Phase 4 — Polish & Extras

- [ ] **T24** Add dry-run mode
  - `--dry-run` flag on omasync
  - Show what rsync would transfer without doing it
  - Use `gum pager` for long output

- [ ] **T25** Implement sync logging
  - Timestamped log files
  - Log rotation (keep last N logs per profile)
  - `omasync --logs` to view recent logs

- [ ] **T26** Track last-sync timestamps
  - Write `last_sync` file per device+profile after success
  - Show "last synced: 2h ago" in profile list and runner

- [ ] **T27** Systemd timer generation (opt-in via omasync-setup)
  - Generate `omasync-<profile>.service` + `.timer`
  - Same hardened pattern as bluetooth-autoconnect
  - `systemctl --user enable --now`

- [ ] **T28** Waybar module (optional)
  - Custom module showing last sync status
  - Click to launch omasync in foot

---

## Dependencies

```
Required:  bash, ssh, rsync, gum
Optional:  wl-copy (clipboard), notify-send (notifications)
Already in omablue: gum (installed in setup Phase 3), foot
```

## Design Decisions

1. **Why rsync over other tools?**
   Rsync is ubiquitous, supports incremental transfer, works over SSH
   natively, and is available on Termux. No extra daemon needed.

2. **Why one file per device/profile?**
   Easy to manage, easy to delete, avoids parsing a monolithic config,
   and follows the principle of least surprise.

3. **Why foot + gum instead of rofi?**
   omasync is interactive and multi-step — it needs a terminal session
   (for SSH output, rsync progress, guided instructions). Rofi is for
   quick pick-one-option menus. gum is perfect for guided TUI flows.

4. **Why not automate Termux setup?**
   We can't SSH into a device that doesn't have SSH yet. The best we can
   do is display clear instructions and verify once the user completes
   them. The guide approach is honest and user-friendly.

5. **Config validation on load**
   Every `load_device` / `load_profile` validates keys exist and values
   are sane. Same pattern as bluetooth-autoconnect.conf loading.

## Open Questions

- Should profiles be device-specific or shared across devices?
  Current design: profiles are device-independent (remote paths may differ
  per device — we could add per-device path overrides later if needed).
- Should we support password auth as fallback or SSH keys only?
  Recommendation: keys only — simpler, more secure, rsync-friendly.
