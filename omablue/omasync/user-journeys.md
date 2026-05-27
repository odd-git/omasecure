# OmaSync User Journeys

> Step-by-step walkthroughs of every major user interaction in OmaSync

---

## 1. Document Overview

This document maps the complete user experience for OmaSync — from first device registration through daily sync operations. Each journey describes exactly what the user sees, types, and decides at every step, along with error states and recovery paths.

**Target audience:** Users of OmaSync on the Omablue desktop environment (Secureblue/Fedora Atomic with Sway).

**How to use this document:**
- **First-time users** — read Journeys 2–4 in order (device setup → profile creation → first sync)
- **Returning users** — jump to Journey 5 for the daily sync workflow
- **Troubleshooting** — see Section 7 for error scenarios and resolutions
- **Developers** — cross-reference with `master-plan.md` Section 2.6 (TUI flow) and Section 3 (UX design)

---

## 2. User Journey: Device Discovery and Registration

**Scenario:** A user needs to add a new device to sync files with.

### 2.1 Entry Point

The user launches the setup wizard:

```
$ omasync-setup
```

The main menu appears via `gum choose`:

```
     Omasync Setup

   > 󰒍  Manage Devices
     󰐕  Manage Sync Profiles
     󰗠  Test Connection
        Quit
```

The user selects **Manage Devices** → **Add New Device**.

### 2.2 Discovery Method Selection

The system presents a choice:

```
How would you like to add a device?

  > 󰒍  Scan network for SSH devices
    󰏗  Discover via Tailscale
       Enter details manually
```

#### Option A: Network Scanning

**User action:** Selects "Scan network for SSH devices"

**System behavior:**
1. Detects the local subnet from the active network interface (e.g., `192.168.1.0/24`)
2. Displays a spinner: `Scanning for SSH-enabled devices on 192.168.1.0/24...`
3. Scans common SSH ports (22, 8022) using a lightweight TCP probe
4. Presents discovered devices:

```
Found 3 SSH-enabled devices:

  > 192.168.1.50:8022    (responds on Termux port)
    192.168.1.101:22      (standard SSH)
    192.168.1.120:22      (standard SSH)
```

**User action:** Selects a device from the list. Host and port are pre-filled in the registration form.

**Error state — no devices found:**

```
┌─── No Devices Found ──────────────────────────┐
│ No SSH-enabled devices detected on the local   │
│ network.                                       │
│                                                │
│ Possible causes:                               │
│  • Target device is on a different network     │
│  • SSH/sshd is not running on the device       │
│  • Firewall blocking port 22 or 8022           │
│                                                │
│ > Enter details manually                       │
│   Scan again                                   │
│   Cancel                                       │
└────────────────────────────────────────────────┘
```

#### Option B: Tailscale Discovery

**Prerequisite:** Tailscale installed and authenticated.

**System behavior:**
1. Runs `tailscale status` to list online peers
2. Presents online devices:

```
Tailscale devices online:

  > pixel-phone     100.64.1.50    android
    thinkpad         100.64.1.101   linux
```

**User action:** Selects a device. Name, host (Tailscale IP), and type are pre-filled. `DEVICE_TAILSCALE` is set to `"true"` automatically.

**Error state — Tailscale unavailable:** Falls back silently to manual entry with a note: `Tailscale not available. Enter device details manually.`

#### Option C: Manual Entry

**System behavior:** Prompts for each field using `gum input`:

| Prompt | Input Method | Validation | Example |
|--------|-------------|------------|---------|
| Device name | `gum input --placeholder "Device name"` | Non-empty, sanitized to `[a-z0-9-_]` | `pixel-phone` |
| Host or IP | `gum input --placeholder "Hostname or IP"` | Non-empty, no whitespace | `192.168.1.50` |
| SSH port | `gum input --value "22"` | Integer 1–65535 | `8022` |
| Username | `gum input --placeholder "SSH username"` | Non-empty, no whitespace | `u0_a123` |
| Device type | `gum choose` | One of: `termux`, `linux`, `macos` | `termux` |

**Decision point:** If a device with the same name already exists, the user is prompted: `Device "pixel-phone" already exists. Overwrite? [y/N]`

### 2.3 SSH Key Generation and Setup

Immediately after device details are saved, the system handles SSH keys.

**Step 1 — Key check:**
- If `~/.ssh/omasync_pixel-phone` exists: `Key already exists. Reuse existing key? [Y/n]`
- If no key exists: proceeds to generation

**Step 2 — Passphrase decision:**

```
Protect key with a passphrase? (recommended for security)

  > Yes
    No — passwordless (for automated syncs)
```

**Step 3 — Key generation:**

A spinner appears: `Generating SSH key...`

The system runs: `ssh-keygen -t ed25519 -f ~/.ssh/omasync_pixel-phone -N "<passphrase>" -C "omasync@pixel-phone"`

**Step 4 — Public key display:**

```
┌─── Public Key ───────────────────────────────────┐
│                                                   │
│ ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI...         │
│ omasync@pixel-phone                               │
│                                                   │
│ ✓ Copied to clipboard                             │
└───────────────────────────────────────────────────┘
```

If `wl-copy` is available, the key is automatically copied. Otherwise the user sees: `Copy the key above and paste it on your remote device.`

**Step 5 — Setup guide (based on device type):**

For **Termux** devices:

```
┌─── Termux Setup Guide ────────────────────────────┐
│                                                    │
│ On your Pixel Phone, open Termux and run:          │
│                                                    │
│  1. pkg install openssh                            │
│  2. mkdir -p ~/.ssh                                │
│  3. echo '<public-key>' >> ~/.ssh/authorized_keys  │
│  4. chmod 600 ~/.ssh/authorized_keys               │
│  5. sshd                                           │
│                                                    │
│ Termux uses port 8022 by default.                  │
│ Find your IP: ifconfig | grep inet                 │
│                                                    │
│ Ready to test connection? [Y/n]                    │
└────────────────────────────────────────────────────┘
```

For **Linux/macOS** devices, the system shows:

```
Deploy the key automatically:

  ssh-copy-id -i ~/.ssh/omasync_pixel-phone.pub -p 22 mino@192.168.1.101

Or manually append the public key to ~/.ssh/authorized_keys on the remote host.
```

### 2.4 Connection Testing

**User action:** Confirms "Ready to test connection"

**System behavior:**
1. Spinner: `Testing connection to pixel-phone...`
2. Runs: `ssh -o ConnectTimeout=5 -o BatchMode=yes -p 8022 -i ~/.ssh/omasync_pixel-phone u0_a123@192.168.1.50 exit`

**Success:**

```
✓ Connected to pixel-phone!

Device saved: ~/.config/omablue/omasync/devices/pixel-phone.conf
```

**Failure:**

```
┌─── Connection Failed ─────────────────────────────┐
│ ✗ Cannot reach pixel-phone (192.168.1.50:8022)    │
│                                                    │
│ Possible causes:                                   │
│  • Device is offline or on a different network     │
│  • sshd is not running (Termux: run 'sshd')       │
│  • Firewall blocking port 8022                     │
│  • Key not added to authorized_keys                │
│  • Wrong username or IP address                    │
│                                                    │
│ > Try again                                        │
│   Save device anyway (test later)                  │
│   Cancel                                           │
└────────────────────────────────────────────────────┘
```

**Recovery:** The user can save the device without a successful test and re-test later via the main menu's "Test Connection" option.

---

## 3. User Journey: Profile Path Selection

**Scenario:** A user creates a sync profile defining what files to sync and where.

### 3.1 Profile Creation Initiation

**Navigation:** `omasync-setup` → **Manage Sync Profiles** → **Add New Profile**

**Step 1 — Profile name:**

```
Profile name: music
```

Input via `gum input --placeholder "Profile name" --char-limit 64`. The name is sanitized to lowercase alphanumeric with hyphens (e.g., `My Music!` becomes `my-music`).

### 3.2 Local Path Selection

The system presents a choice for specifying the local path:

```
Local path — how would you like to specify it?

  > 󰉋  Browse with file manager
       Type path manually
```

#### Option A: File Manager Browse

**User action:** Selects "Browse with file manager"

**System behavior:**
1. Opens the system file chooser dialog via `zenity --file-selection --directory --title="Select local sync folder"` (falls back to `gum file` or manual input if zenity is unavailable)
2. The user navigates to the desired directory in the graphical picker and clicks **Select**
3. The selected path appears in the terminal:

```
Local path: /home/mino/Music ✓
```

**Validation:** The system checks that the path exists. For `push` and `both` directions, a missing path triggers a warning: `Path does not exist. It will be created on first pull, or create it now? [Y/n]`

#### Option B: Manual Entry

**User action:** Types the path directly:

```
Local path: /home/mino/Music
```

Input via `gum input --placeholder "/home/user/Music" --value "$HOME/"`. Tab completion is not available inside gum, which is why the file manager option exists.

### 3.3 Remote Path Entry

The remote path must be entered manually — there is no way to browse a remote filesystem before SSH is active.

```
Remote path: /storage/emulated/0/Music
```

**Path format examples by device type:**
- Termux: `/storage/emulated/0/Music` or `/data/data/com.termux/files/home/docs`
- Linux: `/home/user/Music`
- macOS: `/Users/user/Music`

**Validation:** Non-empty, no whitespace in path. The system does not verify remote path existence at this point (verified during sync).

### 3.4 Sync Direction Selection

```
Sync direction:

  > 󰁝  Push   (local → remote)
    󰁅  Pull   (remote → local)
    󰓦  Both   (bidirectional — pull first, then push)
```

Each option includes a brief explanation. Selecting **Both** triggers an additional note:

```
Note: Bidirectional sync uses "last-writer-wins" (--update flag).
If the same file is modified on both sides between syncs, the newer
version wins. This is NOT merge-based conflict resolution.
```

See `master-plan.md` Section 2.4 for the bidirectional data flow.

### 3.5 Optional Configuration

**Exclude patterns:**

```
Exclude patterns (comma-separated, optional):
  .thumbnails,.cache,*.tmp
```

Input via `gum input --placeholder ".thumbnails,.cache,*.tmp"`. Empty input means no excludes. Patterns containing `..` are rejected (path traversal prevention).

**Delete flag:**

```
Use --delete? This removes files on the destination that
don't exist on the source.

  ⚠ WARNING: This can permanently delete files on the
  remote device if they were removed locally.

  [y/N]
```

Default is **No**. If the user enables this, the confirmation screen during sync will highlight it prominently.

### 3.6 Confirmation and Save

```
┌─── Profile Summary ───────────────────────────────┐
│ Name:       Music                                  │
│ Local:      /home/mino/Music                       │
│ Remote:     /storage/emulated/0/Music              │
│ Direction:  push (local → remote)                  │
│ Excludes:   .thumbnails, .cache, *.tmp             │
│ Delete:     no                                     │
└────────────────────────────────────────────────────┘

Save this profile? [Y/n]
```

**On confirm:** `✓ Profile saved: ~/.config/omablue/omasync/profiles/music.conf`

**On cancel:** Returns to the Manage Profiles menu. No file is written.

---

## 4. User Journey: Managing Existing Devices

**Scenario:** A user needs to view, edit, or remove a previously configured device.

### 4.1 Viewing the Device List

**Navigation:** `omasync-setup` → **Manage Devices** → **List Devices**

**System output (with devices configured):**

```
┌─── Configured Devices ────────────────────────────┐
│                                                    │
│  Name            Host              Port   Type     │
│  ──────────────  ────────────────  ─────  ──────   │
│  pixel-phone     192.168.1.50      8022   termux   │
│  thinkpad        thinkpad          22     linux    │
│                                                    │
└────────────────────────────────────────────────────┘
```

**Empty state (no devices):**

```
No devices configured yet.

Run "Add New Device" to get started, or add a device
config file manually to:
  ~/.config/omablue/omasync/devices/
```

### 4.2 Editing a Device

**Navigation:** `omasync-setup` → **Manage Devices** → **Edit Device**

**Step 1:** System presents device list via `gum choose`:

```
Select device to edit:

  > pixel-phone
    thinkpad
```

**Step 2:** Current values are shown as pre-filled fields. The user edits only the fields they want to change:

```
Device name:  pixel-phone           (read-only — rename not supported)
Host or IP:   [192.168.1.50]        ← gum input --value "192.168.1.50"
SSH port:     [8022]                ← gum input --value "8022"
Username:     [u0_a123]            ← gum input --value "u0_a123"
Device type:  [termux]             ← gum choose (current highlighted)
```

**Step 3:** Summary and confirm:

```
Save changes to pixel-phone? [Y/n]
```

**On confirm:** Config file at `~/.config/omablue/omasync/devices/pixel-phone.conf` is overwritten with updated values.

### 4.3 Removing a Device

**Navigation:** `omasync-setup` → **Manage Devices** → **Remove Device**

**Step 1:** Select device via `gum choose`.

**Step 2:** Confirmation with impact warning:

```
Remove device "pixel-phone"?

This will delete:
  • ~/.config/omablue/omasync/devices/pixel-phone.conf

Also delete the SSH keypair?
  • ~/.ssh/omasync_pixel-phone
  • ~/.ssh/omasync_pixel-phone.pub

  > Remove device only (keep SSH keys)
    Remove device AND SSH keys
    Cancel
```

**Step 3:** On confirm:
- Device config file deleted
- SSH keys deleted (if selected)
- Sync logs for this device are **preserved** (not deleted) — the user can clean them up manually

**On cancel:** Returns to Manage Devices menu. Nothing is deleted.

---

## 5. User Journey: Running a Sync Operation

**Scenario:** A user wants to sync files with a configured device.

### 5.1 Interactive Mode

**User action:** Runs `omasync` with no arguments.

**Step 1 — Device selection:**

```
Select device:

  > 󰂱  Pixel Phone   (termux)    last sync: 2h ago
    󰂱  ThinkPad       (linux)     last sync: 1d ago
```

Devices with a recent last-sync timestamp show the relative time. Devices never synced show `never synced`.

**Step 2 — Profile selection (multi-select):**

```
Select profile(s) — space to toggle, enter to confirm:

  > [x] Music        ~/Music → .../Music           push
    [ ] Documents    ~/Docs  → .../Documents        both
    [ ] Photos       ~/Pics  → .../Photos           pull
```

The user presses **Space** to toggle profiles, **Enter** to confirm. At least one profile must be selected.

**Step 3 — Confirmation screen:**

```
┌─── Sync Summary ───────────────────────────────────┐
│ Device:     Pixel Phone (192.168.1.50:8022)         │
│ Profiles:   Music                                   │
│ Direction:  push (local → remote)                   │
│ Source:     /home/mino/Music/                        │
│ Dest:       u0_a123@192.168.1.50:.../Music/         │
│ Flags:      -avzh --progress --partial              │
│ Delete:     no                                      │
└─────────────────────────────────────────────────────┘

  > Run sync
    Dry-run first (preview only)
    Cancel
```

**Step 4 — Sync execution:**

Raw rsync output streams directly to the terminal (no gum wrapping — preserves progress bars):

```
sending incremental file list
album/song1.flac
     15,234,567 100%   12.5MB/s    0:00:01
album/song2.flac
      8,901,234 100%   10.2MB/s    0:00:00

sent 24,135,801 bytes  received 52 bytes  16,090,568.67 bytes/sec
total size is 24,135,000  speedup is 1.00
```

**Cancellation:** Pressing **Ctrl+C** triggers a SIGINT trap. Rsync's `--partial` flag preserves partially transferred files for resume on next run.

**Step 5 — Result summary:**

```
┌─── Result ──────────────────────────────────────────┐
│ ✓ Sync completed successfully                        │
│ Transferred: 24.1 MB (2 files)                       │
│ Duration:    3s                                      │
│ Log: ~/.local/share/omablue/omasync/logs/            │
│      pixel-phone_music_20260213-1430.log             │
└──────────────────────────────────────────────────────┘
```

### 5.2 CLI Mode (Non-Interactive)

For scripting, cron, and systemd timers:

```bash
omasync --device pixel-phone --profile music --yes
```

**Available flags:**

| Flag | Purpose |
|------|---------|
| `--device <name>` | Select device (skips device menu) |
| `--profile <name>` | Select profile (skips profile menu) |
| `--dry-run` | Preview changes without transferring |
| `--yes` | Skip confirmation prompt |
| `--verbose` | Show full rsync command and SSH debug info |
| `--help` | Display usage information |

CLI mode produces the same rsync output and logging as interactive mode but exits automatically on completion. Exit code 0 = success, non-zero = failure.

**Systemd timer example** (see `master-plan.md` Section 4, Phase 5):

```bash
# Enable a daily sync for pixel-phone music
systemctl --user enable --now omasync@pixel-phone_music.timer
```

---

## 6. Edge Cases and Error Scenarios

| Scenario | Detection | User Message | Resolution |
|----------|-----------|-------------|------------|
| Network scan finds no SSH devices | Scan returns empty results | "No SSH-enabled devices detected on the local network" | Check that sshd is running on target; try manual entry |
| SSH connection fails during testing | SSH exit code ≠ 0 | "Cannot reach device — Is it online? Is sshd running?" | Verify IP, port, sshd status; re-deploy key |
| Remote path doesn't exist | rsync exit code 23 | "Remote path not found. Create it on the device first." | SSH into device and `mkdir -p <path>` |
| Permission denied on local path | Pre-sync `[[ -r ]]` check | "Cannot read local path — check permissions" | `chmod` or run as correct user |
| Permission denied on remote path | rsync exit code 23 | "Permission denied on remote — check remote user access" | Fix remote permissions or change DEVICE_USER |
| Bidirectional conflict (same file changed both sides) | Cannot detect — rsync uses mtime | No error (newer file wins silently) | Use dry-run to preview; consider Unison for merge-based sync |
| Device offline during scheduled sync | SSH connection timeout | Logged to systemd journal: "Cannot reach device" | Sync retries on next timer interval; `Persistent=true` catches up |
| Disk full on remote | rsync exit code 11 | "Transfer failed — not enough disk space on remote" | Free space on remote device |
| Disk full locally | rsync exit code 11 | "Transfer failed — not enough local disk space" | Free local disk space |
| Stale SSH multiplexed socket | SSH timeout after initial success | Transparent — socket auto-removed, new connection established | Automatic recovery; no user action needed |
| `gum` not installed | `command -v gum` fails at startup | "gum not found — using basic prompts" | All prompts fall back to POSIX `read`/`select`; TUI is degraded but functional |

---

## 7. User Flow Diagrams

### Device Setup Flow

```
omasync-setup → Manage Devices → Add New Device
                                       │
                        ┌──────────────┼──────────────┐
                        ▼              ▼              ▼
                  Scan Network    Tailscale       Manual Entry
                        │         Discovery            │
                        ▼              │               ▼
                  [Devices Found?]     ▼         Enter: name, host,
                   │          │   Select device   port, user, type
                   No         Yes      │               │
                   │          │        ▼               │
                   ▼          └──► Pre-fill form ◄─────┘
              Show hints               │
              + retry/manual           ▼
                                 Save device config
                                       │
                                       ▼
                              Generate SSH keypair
                                       │
                                       ▼
                              Display public key
                              + clipboard copy
                                       │
                           ┌───────────┼───────────┐
                           ▼                       ▼
                     Termux guide            Linux/macOS guide
                     (manual key             (ssh-copy-id
                      deployment)             command)
                           │                       │
                           └───────────┬───────────┘
                                       ▼
                              Test SSH connection
                                       │
                              ┌────────┼────────┐
                              ▼                 ▼
                          ✓ Success         ✗ Failure
                              │                 │
                              ▼           ┌─────┼─────┐
                          Device saved    ▼           ▼
                                      Try again   Save anyway
```

### Profile Creation Flow

```
omasync-setup → Manage Profiles → Add New Profile
                                       │
                                       ▼
                                Enter profile name
                                       │
                                       ▼
                              Select local path method
                               │                │
                               ▼                ▼
                         File manager      Manual entry
                         (zenity/gum)      (gum input)
                               │                │
                               └──────┬─────────┘
                                      ▼
                              Enter remote path (manual)
                                      │
                                      ▼
                              Select direction
                              (push / pull / both)
                                      │
                                      ▼
                              Configure excludes (optional)
                                      │
                                      ▼
                              Enable --delete? (default: no)
                                      │
                                      ▼
                              Preview summary → [Save? Y/n]
                                      │
                              ┌───────┼───────┐
                              ▼               ▼
                         ✓ Saved          Cancelled
```

### Sync Execution Flow

```
omasync
   │
   ├──── Interactive mode (no args) ────────────┐
   │                                             │
   │     Select device (gum choose)              │
   │            │                                │
   │     Select profile(s) (gum choose multi)    │
   │            │                                │
   │     Confirmation screen                     │
   │       │          │          │               │
   │     Run sync   Dry-run   Cancel             │
   │       │          │          │               │
   │       ▼          ▼       Return             │
   │                                             │
   ├──── CLI mode (--device X --profile Y) ──────┤
   │                                             │
   │     Load device + profile configs           │
   │            │                                │
   │     [--yes?] ── No ──► Confirmation screen  │
   │       │                                     │
   │      Yes                                    │
   │       │                                     │
   └───────┴─────────────────────────────────────┘
                        │
                        ▼
               Resolve host (Tailscale DNS → fallback)
                        │
                        ▼
               Build rsync command
                        │
                  ┌─────┼─────┐
                  ▼           ▼
              push/pull     both
              (1 command)   (pull then push)
                  │           │
                  └─────┬─────┘
                        ▼
               Execute rsync (raw terminal output)
                        │
                  ┌─────┼─────┐
                  ▼           ▼
              ✓ Success   ✗ Failure
                  │           │
                  ▼           ▼
           Update         Show error
           last-sync      + hints
           timestamp           │
                  │           ▼
                  └─────┬─────┘
                        ▼
               Write log file
               Rotate old logs
                        │
                        ▼
               Display result summary
```
