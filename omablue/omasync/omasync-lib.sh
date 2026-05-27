#!/usr/bin/env bash
# --- Omasync Shared Library ---
# Sourced by omasync and omasync-setup.
# Do NOT execute this file directly.

# =============================================================================
# XDG Paths & Constants
# =============================================================================

OMASYNC_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omablue/omasync"
OMASYNC_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/omablue/omasync"

# Defaults (overridden by omasync.conf)
LOG_DIR="$OMASYNC_DATA_DIR/logs"
DEFAULT_SSH_DIR="$HOME/.ssh"
RSYNC_BASE_FLAGS="-avzh --progress --partial"
DRY_RUN="false"
LOG_KEEP_COUNT=10

# Gum styling
readonly GUM_SUCCESS_FG="46"
readonly GUM_ERROR_FG="196"
readonly GUM_WARN_FG="214"
readonly GUM_INFO_FG="39"
readonly GUM_ACCENT_FG="212"

# =============================================================================
# Output Helpers
# =============================================================================

msg()  { printf '%s\n' "$1"; }
ok()   { if has_gum; then gum style --foreground "$GUM_SUCCESS_FG" "✓ $1"; else printf '  [OK] %s\n' "$1"; fi; }
warn() { if has_gum; then gum style --foreground "$GUM_WARN_FG" "⚠ $1"; else printf '  [!!] %s\n' "$1" >&2; fi; }
err()  { if has_gum; then gum style --foreground "$GUM_ERROR_FG" --bold "✗ $1"; else printf '  [ERROR] %s\n' "$1" >&2; fi; }
die()  { err "$1"; exit 1; }

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

# =============================================================================
# Gum Wrappers (POSIX fallback when gum unavailable)
# =============================================================================

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

gum_or_multi_select() {
  local prompt="$1"; shift
  if has_gum; then
    printf '%s\n' "$@" | gum choose --no-limit --header "$prompt"
  else
    echo "$prompt (enter numbers separated by spaces):" >&2
    local i=1
    for opt in "$@"; do
      echo "  $i) $opt" >&2
      ((i++))
    done
    read -rp "> " choices
    for num in $choices; do
      local idx=$((num - 1))
      local args=("$@")
      [[ $idx -ge 0 && $idx -lt ${#args[@]} ]] && echo "${args[$idx]}"
    done
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

gum_or_password() {
  local prompt="$1"
  if has_gum; then
    gum input --password --placeholder "$prompt"
  else
    read -rsp "$prompt: " reply; echo >&2
    echo "$reply"
  fi
}

# =============================================================================
# Dependency Checks
# =============================================================================

check_dependencies() {
  local missing=()
  for cmd in ssh rsync; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    die "Required tools not found: ${missing[*]}"
  fi

  if ! has_gum; then
    warn "gum not installed — TUI features will be limited"
  fi
}

# =============================================================================
# Directory & Config Initialization
# =============================================================================

ensure_dirs() {
  mkdir -p "$OMASYNC_CONFIG_DIR"/{devices,profiles}
  mkdir -p "$OMASYNC_DATA_DIR/logs"
  mkdir -p "${DEFAULT_SSH_DIR}"
}

generate_default_config() {
  local config="$OMASYNC_CONFIG_DIR/omasync.conf"
  [[ -f "$config" ]] && return 0

  cat > "$config" << 'CONF'
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
CONF
}

# =============================================================================
# Config Loading (safe whitelist-only parsing — no source/eval)
# =============================================================================

_parse_value() {
  # Strip surrounding quotes and expand $HOME
  local val="$1"
  val="${val#\"}"
  val="${val%\"}"
  val="${val#\'}"
  val="${val%\'}"
  val="${val//\$HOME/$HOME}"
  echo "$val"
}

load_global_config() {
  local config="$OMASYNC_CONFIG_DIR/omasync.conf"
  [[ -f "$config" ]] || { err "Global config not found: $config"; return 1; }

  while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
    key=$(echo "$key" | xargs)
    value=$(_parse_value "$(echo "$value" | xargs)")
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
  DEVICE_TAILSCALE="false"

  while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
    key=$(echo "$key" | xargs)
    value=$(_parse_value "$(echo "$value" | xargs)")
    case "$key" in
      DEVICE_NAME)      DEVICE_NAME="$value" ;;
      DEVICE_HOST)      DEVICE_HOST="$value" ;;
      DEVICE_PORT)      [[ "$value" =~ ^[0-9]+$ ]] && DEVICE_PORT="$value" ;;
      DEVICE_USER)      DEVICE_USER="$value" ;;
      DEVICE_KEY)       DEVICE_KEY="$value" ;;
      DEVICE_TYPE)      [[ "$value" =~ ^(termux|linux|macos)$ ]] && DEVICE_TYPE="$value" ;;
      DEVICE_TAILSCALE) [[ "$value" =~ ^(true|false)$ ]] && DEVICE_TAILSCALE="$value" ;;
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

  # Reset profile vars
  PROFILE_NAME="" LOCAL_PATH="" REMOTE_PATH=""
  DIRECTION="push" RSYNC_EXCLUDE="" RSYNC_DELETE="false"

  while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
    key=$(echo "$key" | xargs)
    value=$(_parse_value "$(echo "$value" | xargs)")
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

# =============================================================================
# Listing Helpers
# =============================================================================

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

# =============================================================================
# Name Sanitization
# =============================================================================

sanitize_name() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-_'
}

# =============================================================================
# SSH Helpers
# =============================================================================

build_ssh_opts() {
  # Build SSH options array. Sets SSH_OPTS as a global array.
  local device="$1"
  load_device "$device" || return 1

  local socket_dir="/tmp/omasync-${USER}"
  mkdir -p "$socket_dir" && chmod 700 "$socket_dir"

  SSH_OPTS=(
    -o "ControlMaster=auto"
    -o "ControlPath=${socket_dir}/%r@%h:%p"
    -o "ControlPersist=600"
    -o "ServerAliveInterval=30"
    -o "ServerAliveCountMax=3"
    -o "ConnectTimeout=10"
    -o "StrictHostKeyChecking=accept-new"
    -o "Compression=no"
  )

  [[ -n "$DEVICE_KEY" && -f "$DEVICE_KEY" ]] && SSH_OPTS+=(-i "$DEVICE_KEY")
  [[ -n "$DEVICE_PORT" ]] && SSH_OPTS+=(-p "$DEVICE_PORT")
}

test_connection() {
  local device="$1"
  load_device "$device" || return 1

  local ssh_opts=(-o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new)
  [[ -n "$DEVICE_KEY" && -f "$DEVICE_KEY" ]] && ssh_opts+=(-i "$DEVICE_KEY")
  [[ -n "$DEVICE_PORT" ]] && ssh_opts+=(-p "$DEVICE_PORT")

  ssh "${ssh_opts[@]}" "${DEVICE_USER}@${DEVICE_HOST}" exit 2>/dev/null
}

generate_device_key() {
  local device_name="$1"
  local key_path="${DEFAULT_SSH_DIR}/omasync_${device_name}"

  if [[ -f "$key_path" ]]; then
    if ! gum_or_confirm "Key already exists at $key_path. Overwrite?"; then
      ok "Keeping existing key"
      echo "$key_path"
      return 0
    fi
  fi

  mkdir -p "$DEFAULT_SSH_DIR"
  chmod 700 "$DEFAULT_SSH_DIR"

  local passphrase=""
  if gum_or_confirm "Protect key with a passphrase? (recommended for security)"; then
    passphrase=$(gum_or_password "Enter passphrase")
  fi

  if has_gum; then
    gum spin --title "Generating SSH key..." -- \
      ssh-keygen -t ed25519 -f "$key_path" -N "$passphrase" -C "omasync@${device_name}"
  else
    ssh-keygen -t ed25519 -f "$key_path" -N "$passphrase" -C "omasync@${device_name}"
  fi

  chmod 600 "$key_path"
  chmod 644 "${key_path}.pub"

  local pub_key
  pub_key=$(<"${key_path}.pub")

  if has_gum; then
    gum style --border double --padding "1 2" --border-foreground "$GUM_ACCENT_FG" \
      "Public key:" "" "$pub_key"
  else
    echo ""
    echo "Public key:"
    echo "$pub_key"
    echo ""
  fi

  if command -v wl-copy &>/dev/null; then
    echo "$pub_key" | wl-copy
    ok "Public key copied to clipboard"
  else
    msg "Copy the key above and paste it on your remote device."
  fi

  echo "$key_path"
}

# =============================================================================
# Termux / Linux / macOS Setup Guides
# =============================================================================

show_termux_guide() {
  local pub_key="$1"
  local guide
  guide=$(cat << EOF
On your device, open Termux and run:

  1. pkg install openssh
  2. mkdir -p ~/.ssh
  3. echo '$pub_key' >> ~/.ssh/authorized_keys
  4. chmod 600 ~/.ssh/authorized_keys
  5. sshd

Termux uses port 8022 by default.
Find your IP: ifconfig | grep inet
EOF
)

  if has_gum; then
    gum style --border rounded --padding "1 2" --border-foreground "$GUM_INFO_FG" "$guide"
  else
    echo "$guide"
  fi
}

show_linux_guide() {
  local pub_key_path="$1"
  local user="$2"
  local host="$3"
  local port="$4"

  local cmd="ssh-copy-id -i ${pub_key_path} -p ${port} ${user}@${host}"
  local guide
  guide=$(cat << EOF
Deploy the key automatically:

  $cmd

Or manually append the public key to ~/.ssh/authorized_keys on the remote host.
EOF
)

  if has_gum; then
    gum style --border rounded --padding "1 2" --border-foreground "$GUM_INFO_FG" "$guide"
  else
    echo "$guide"
  fi
}

# =============================================================================
# Tailscale DNS Resolution
# =============================================================================

resolve_host() {
  local device="$1"
  load_device "$device" || return 1

  local resolved_host="$DEVICE_HOST"

  if [[ "$DEVICE_TAILSCALE" == "true" ]] && \
     [[ ! "$DEVICE_HOST" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && \
     command -v tailscale &>/dev/null; then

    local ts_ip
    ts_ip=$(tailscale ip "$DEVICE_HOST" 2>/dev/null | head -1) || true

    if [[ -n "$ts_ip" ]]; then
      resolved_host="$ts_ip"
    elif command -v jq &>/dev/null; then
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

# =============================================================================
# Rsync Command Builder
# =============================================================================

build_rsync_cmd() {
  local device="$1" profile="$2" direction_override="${3:-}"

  load_device "$device" || return 1
  load_profile "$profile" || return 1

  local direction="${direction_override:-$DIRECTION}"

  # Resolve host (Tailscale DNS or direct)
  local host
  host=$(resolve_host "$device")

  # Build SSH command string for rsync -e
  local ssh_cmd="ssh -p ${DEVICE_PORT}"
  [[ -n "$DEVICE_KEY" && -f "$DEVICE_KEY" ]] && ssh_cmd+=" -i ${DEVICE_KEY}"

  local socket_dir="/tmp/omasync-${USER}"
  mkdir -p "$socket_dir" && chmod 700 "$socket_dir"
  ssh_cmd+=" -o ControlMaster=auto"
  ssh_cmd+=" -o ControlPath=${socket_dir}/%r@%h:%p"
  ssh_cmd+=" -o ControlPersist=600"
  ssh_cmd+=" -o ServerAliveInterval=30"
  ssh_cmd+=" -o ServerAliveCountMax=3"
  ssh_cmd+=" -o Compression=no"

  # Build rsync flags as array
  local -a flags
  IFS=' ' read -ra flags <<< "$RSYNC_BASE_FLAGS"

  # Add excludes
  if [[ -n "$RSYNC_EXCLUDE" ]]; then
    IFS=',' read -ra excludes <<< "$RSYNC_EXCLUDE"
    for pattern in "${excludes[@]}"; do
      pattern=$(echo "$pattern" | xargs)
      [[ -n "$pattern" ]] && flags+=(--exclude="$pattern")
    done
  fi

  # Delete handling (never in bidirectional mode)
  [[ "$RSYNC_DELETE" == "true" && "$direction" != "both" ]] && flags+=(--delete)

  # Bidirectional uses --update
  [[ "$direction" == "both" ]] && flags+=(--update)

  # Dry run
  [[ "$DRY_RUN" == "true" ]] && flags+=(--dry-run)

  local remote="${DEVICE_USER}@${host}:${REMOTE_PATH}/"
  local local_path="${LOCAL_PATH}/"

  # Store command parts in global arrays for safe execution
  RSYNC_CMD_FLAGS=("${flags[@]}")
  RSYNC_CMD_SSH="$ssh_cmd"

  case "$direction" in
    push)
      RSYNC_CMD_PAIRS=("$local_path" "$remote")
      ;;
    pull)
      RSYNC_CMD_PAIRS=("$remote" "$local_path")
      ;;
    both)
      # Two operations: pull first, then push
      RSYNC_CMD_PAIRS=("$remote" "$local_path" "$local_path" "$remote")
      ;;
  esac
}

execute_rsync() {
  # Execute rsync using the arrays set by build_rsync_cmd
  local src="$1" dest="$2"
  rsync "${RSYNC_CMD_FLAGS[@]}" -e "$RSYNC_CMD_SSH" "$src" "$dest"
}

# =============================================================================
# Sync Execution & Logging
# =============================================================================

execute_sync() {
  local device="$1" profile="$2"
  local timestamp
  timestamp=$(date +%Y%m%d-%H%M%S)
  local log_file="${LOG_DIR}/${device}_${profile}_${timestamp}.log"

  mkdir -p "$LOG_DIR"

  build_rsync_cmd "$device" "$profile" || return 1

  local exit_code=0
  local pair_count=${#RSYNC_CMD_PAIRS[@]}
  local i=0

  while [[ $i -lt $pair_count ]]; do
    local src="${RSYNC_CMD_PAIRS[$i]}"
    local dest="${RSYNC_CMD_PAIRS[$((i+1))]}"
    ((i+=2))

    local display_cmd="rsync ${RSYNC_CMD_FLAGS[*]} -e \"$RSYNC_CMD_SSH\" \"$src\" \"$dest\""
    echo "$ $display_cmd" | tee -a "$log_file"
    echo "" | tee -a "$log_file"

    rsync "${RSYNC_CMD_FLAGS[@]}" -e "$RSYNC_CMD_SSH" "$src" "$dest" 2>&1 | tee -a "$log_file"
    local rc=${PIPESTATUS[0]}

    if [[ $rc -ne 0 ]]; then
      exit_code=$rc
      err "rsync exited with code $rc"
    fi
  done

  # Update last-sync timestamp on success
  if [[ $exit_code -eq 0 ]]; then
    local ts_file="$OMASYNC_DATA_DIR/${device}_${profile}.last_sync"
    date -Iseconds > "$ts_file"
  fi

  rotate_logs "$device" "$profile"

  return $exit_code
}

# =============================================================================
# Log Rotation
# =============================================================================

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

# =============================================================================
# Last Sync Tracking
# =============================================================================

get_last_sync() {
  local device="$1" profile="${2:-}"
  local ts_file

  if [[ -n "$profile" ]]; then
    ts_file="$OMASYNC_DATA_DIR/${device}_${profile}.last_sync"
  else
    # Find most recent last_sync for this device
    local latest=""
    local latest_time=0
    for f in "$OMASYNC_DATA_DIR/${device}_"*.last_sync; do
      [[ -f "$f" ]] || continue
      local t
      t=$(date -d "$(<"$f")" +%s 2>/dev/null) || continue
      if [[ $t -gt $latest_time ]]; then
        latest_time=$t
        latest="$f"
      fi
    done
    ts_file="$latest"
  fi

  [[ -n "$ts_file" && -f "$ts_file" ]] || { echo "never synced"; return; }

  local ts
  ts=$(<"$ts_file")
  local epoch_then epoch_now diff
  epoch_then=$(date -d "$ts" +%s 2>/dev/null) || { echo "never synced"; return; }
  epoch_now=$(date +%s)
  diff=$((epoch_now - epoch_then))

  if [[ $diff -lt 60 ]]; then
    echo "just now"
  elif [[ $diff -lt 3600 ]]; then
    echo "$((diff / 60))m ago"
  elif [[ $diff -lt 86400 ]]; then
    echo "$((diff / 3600))h ago"
  else
    echo "$((diff / 86400))d ago"
  fi
}

# =============================================================================
# Profile Validation
# =============================================================================

validate_profile() {
  local name="$1"
  load_profile "$name" || return 1

  if [[ "$DIRECTION" != "pull" && ! -d "$LOCAL_PATH" ]]; then
    warn "Local path does not exist: $LOCAL_PATH"
    warn "It will be created on first pull, or create it manually"
  fi

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

# =============================================================================
# Save Config Helpers
# =============================================================================

save_device_config() {
  local file_name="$1"
  local name="$2" host="$3" port="$4" user="$5" key="$6" type="$7" tailscale="${8:-false}"
  local conf="$OMASYNC_CONFIG_DIR/devices/${file_name}.conf"

  cat > "$conf" << EOF
# Device: $name
# Created by omasync-setup on $(date +%Y-%m-%d)

DEVICE_NAME="$name"
DEVICE_HOST="$host"
DEVICE_PORT="$port"
DEVICE_USER="$user"
DEVICE_KEY="$key"
DEVICE_TYPE="$type"
DEVICE_TAILSCALE="$tailscale"
EOF
}

save_profile_config() {
  local file_name="$1"
  local name="$2" local_path="$3" remote_path="$4" direction="$5" exclude="$6" delete="$7"
  local conf="$OMASYNC_CONFIG_DIR/profiles/${file_name}.conf"

  cat > "$conf" << EOF
# Sync Profile: $name
# Created by omasync-setup on $(date +%Y-%m-%d)

PROFILE_NAME="$name"
LOCAL_PATH="$local_path"
REMOTE_PATH="$remote_path"
DIRECTION="$direction"
RSYNC_EXCLUDE="$exclude"
RSYNC_DELETE="$delete"
EOF
}

# =============================================================================
# Initialization (run on source)
# =============================================================================

omasync_init() {
  ensure_dirs
  generate_default_config
  load_global_config
}
