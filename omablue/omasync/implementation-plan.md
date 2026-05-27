# Omasync Implementation Plan

> Detailed implementation plan for the Omasync SSH Sync Manager — derived from `master-plan.md` and `task-omasync.md`

---

## 1. Executive Summary

Omasync is a bash-based file synchronization tool for the Omablue desktop environment that provides secure rsync-over-SSH file transfer with a gum-powered TUI. The project delivers two scripts — `omasync-setup` (configuration wizard) and `omasync` (sync runner) — plus a shared library, following established Omablue conventions (strict bash, one-file-per-config, XDG paths).

### High-Level Timeline

| Phase | Name | Duration | Target |
|-------|------|----------|--------|
| 0 | Skeleton & Foundations | 3 days | Week 1 |
| 1 | SSH & Device Management | 5 days | Week 1–2 |
| 2 | Sync Profile Management | 2 days | Week 2 |
| 3 | Rsync Integration & Runner | 5 days | Week 2–3 |
| 4 | Tailscale DNS Integration | 2 days | Week 3 |
| 5 | Polish & Extras | 3 days | Week 3–4 |
| — | **Total** | **~20 working days** | **4 weeks** |

### Expected Outcomes

- Fully functional TUI for managing devices, profiles, and running syncs
- CLI mode for scripting and systemd timer automation
- Secure per-device SSH key management with Tailscale DNS fallback
- Logging, dry-run, and Waybar integration

---

## 2. Implementation Phases

### Phase 0: Skeleton & Foundations

**Duration:** 3 days
**Goal:** File structure, shared library, script scaffolding, dependency checks

#### Deliverables

| # | Deliverable | Description |
|---|-------------|-------------|
| D0.1 | `omasync-lib.sh` | Shared helpers: config loading, validation, device/profile listing, gum wrappers |
| D0.2 | `omasync-setup` skeleton | Main menu dispatch with gum choose, strict mode, PATH setup |
| D0.3 | `omasync` skeleton | Argument parsing (`--device`, `--profile`, `--dry-run`, `--yes`), interactive/CLI mode branch |
| D0.4 | Default config generation | Auto-create `omasync.conf` and directory tree on first run |

#### Success Criteria

- Running `omasync-setup` shows the main menu and exits cleanly on Quit/Ctrl+C
- Running `omasync` with no args enters interactive mode; with `--help` shows usage
- `omasync-lib.sh` functions load/validate existing `omasync.conf` correctly
- All config directories created idempotently (`devices/`, `profiles/`, `logs/`)
- Missing dependency (ssh, rsync, gum) reported clearly at startup

#### Resource Requirements

- **Developer:** 1 (you — bash scripting)
- **Tools:** bash, ssh, rsync, gum (already available on Secureblue/Omablue)
- **Reference:** Existing `omablue-bluetooth`, `setup/lib.sh` for patterns

#### Dependencies & Prerequisites

- None (foundation phase)
- Existing `config/omablue/omasync/omasync.conf` already created — use as template

---

### Phase 1: SSH Connection Management & Device Setup

**Duration:** 5 days
**Goal:** Device registration, SSH key generation, setup guides, connection testing

#### Deliverables

| # | Deliverable | Task Refs | Description |
|---|-------------|-----------|-------------|
| D1.1 | Add Device wizard | T05 | Guided gum input flow: name, host, port, user, type |
| D1.2 | SSH key generation | T06 | ed25519 keypair per device, passphrase optional, clipboard copy |
| D1.3 | Termux setup guide | T07 | Step-by-step gum-formatted instructions for Termux SSH setup |
| D1.4 | Linux/macOS setup guide | T08 | ssh-copy-id command pre-filled, manual fallback |
| D1.5 | Connection test | T09 | SSH connectivity check with spinner, error hints |
| D1.6 | Edit Device | T10 | Pick device, edit fields with pre-filled values |
| D1.7 | Remove Device | T11 | Confirmation dialog, optional key cleanup |
| D1.8 | List Devices | T12 | Styled table with name, host, port, type |

#### Success Criteria

- Can add a new device through the wizard and see its `.conf` file in `devices/`
- SSH keypair generated at `~/.ssh/omasync_<device>` with correct permissions (600/644)
- Public key displayed and copied to clipboard (if wl-copy available)
- Termux guide shown for termux-type devices; ssh-copy-id for linux/macos
- Connection test passes for a reachable device, shows actionable error for unreachable ones
- Edit preserves existing values, Remove cleans up config + optionally keys

#### Resource Requirements

- **Developer:** 1
- **Tools:** ssh-keygen, wl-copy (optional), gum
- **Test device:** A secondary machine or Termux instance for SSH testing

#### Dependencies & Prerequisites

- Phase 0 complete (lib.sh, script skeletons, directory structure)

---

### Phase 2: Sync Profile Management

**Duration:** 2 days
**Goal:** Profile creation, editing, deletion, listing

#### Deliverables

| # | Deliverable | Task Refs | Description |
|---|-------------|-----------|-------------|
| D2.1 | Add Profile wizard | T13 | Guided flow: name, local/remote paths, direction, excludes, --delete |
| D2.2 | Edit Profile | T14 | Pick profile, edit fields with pre-filled values |
| D2.3 | Remove Profile | T15 | Confirmation dialog, remove `.conf` file |
| D2.4 | List Profiles | T16 | Styled table: name, local path, remote path, direction |

#### Success Criteria

- Can create a profile and verify `.conf` file in `profiles/`
- Path validation warns if local path doesn't exist (for push/both directions)
- Exclude patterns validated (no `..` path traversal)
- Edit/Remove work correctly with confirmation dialogs
- All gum prompts handle Ctrl+C gracefully (return to parent menu)

#### Resource Requirements

- **Developer:** 1
- **Tools:** gum, filesystem access

#### Dependencies & Prerequisites

- Phase 0 complete (config loading, directory structure)
- Phase 1 recommended (to test profiles against real devices) but not blocking

---

### Phase 3: Rsync Integration & Sync Runner

**Duration:** 5 days
**Goal:** Build rsync commands, execute syncs with live progress, log results

#### Deliverables

| # | Deliverable | Task Refs | Description |
|---|-------------|-----------|-------------|
| D3.1 | Interactive device selection | T17 | gum choose from configured devices, handle empty state |
| D3.2 | Interactive profile selection | T18 | gum choose with multi-select, handle empty state |
| D3.3 | Rsync command generator | T19 | Compose rsync from device + profile config, handle push/pull/both |
| D3.4 | Confirmation screen | T20 | Summary box with device, profiles, direction, paths, flags |
| D3.5 | Sync execution | T21 | Raw rsync output (no gum wrapping), SIGINT handling |
| D3.6 | Result summary + logging | T22 | Success/failure, transfer stats, log to file |
| D3.7 | CLI mode | T23 | `--device`, `--profile`, `--dry-run`, `--yes` — no prompts |

#### Success Criteria

- Interactive mode: select device → select profile(s) → confirm → execute → summary
- Push sync transfers files local → remote correctly
- Pull sync transfers files remote → local correctly
- Bidirectional sync runs pull-then-push with `--update` flag
- Rsync excludes applied correctly; `--delete` only when configured
- CLI mode runs end-to-end without any prompts (suitable for cron/systemd)
- Sync log written to `$LOG_DIR/<device>_<profile>_<timestamp>.log`
- Ctrl+C during sync handled gracefully (partial files preserved via `--partial`)

#### Resource Requirements

- **Developer:** 1
- **Tools:** rsync, ssh, gum
- **Test setup:** Two machines (or localhost-to-localhost) with SSH access

#### Dependencies & Prerequisites

- Phase 0 (lib.sh), Phase 1 (devices configured), Phase 2 (profiles configured)

---

### Phase 4: Tailscale DNS Integration

**Duration:** 2 days
**Goal:** Resolve device hostnames via Tailscale MagicDNS with graceful fallback

#### Deliverables

| # | Deliverable | Description |
|---|-------------|-------------|
| D4.1 | `resolve_host()` function | Try Tailscale DNS → fallback to DEVICE_HOST |
| D4.2 | `DEVICE_TAILSCALE` config field | New field in device configs to enable Tailscale resolution |
| D4.3 | Tailscale device discovery | `list_tailscale_devices()` for setup wizard integration |
| D4.4 | Session-level DNS caching | Cache resolved IPs for the session duration |

#### Success Criteria

- Devices with `DEVICE_TAILSCALE="true"` resolved via `tailscale ip` first
- Fallback to direct DEVICE_HOST when Tailscale unavailable/device offline
- No errors when Tailscale is not installed (silent fallback)
- Add Device wizard offers Tailscale device discovery when Tailscale is available

#### Resource Requirements

- **Developer:** 1
- **Tools:** tailscale CLI (optional — graceful degradation)

#### Dependencies & Prerequisites

- Phase 1 (device config structure)
- Tailscale installed and configured on at least one device (for testing)

---

### Phase 5: Polish & Extras

**Duration:** 3 days
**Goal:** Dry-run mode, logging, last-sync tracking, systemd timers, Waybar

#### Deliverables

| # | Deliverable | Task Refs | Description |
|---|-------------|-----------|-------------|
| D5.1 | Dry-run mode | T24 | `--dry-run` flag, preview output via gum pager |
| D5.2 | Sync logging + rotation | T25 | Timestamped logs, keep last N per device+profile pair |
| D5.3 | Last-sync tracking | T26 | Timestamp file per device+profile, "2h ago" display |
| D5.4 | Systemd timer generation | T27 | Template service + timer units, `systemctl --user enable` |
| D5.5 | Waybar module | T28 | Custom module showing last sync status, click to launch |

#### Success Criteria

- `--dry-run` shows what rsync would transfer without modifying files
- Log rotation keeps exactly N most recent logs (configurable via `LOG_KEEP_COUNT`)
- Last-sync timestamp shown in device/profile selection menus
- Systemd timer created and enabled for a device+profile pair
- Waybar module displays sync status and opens omasync on click

#### Resource Requirements

- **Developer:** 1
- **Tools:** systemctl, waybar config (jsonc)

#### Dependencies & Prerequisites

- Phase 3 (sync execution must work before adding polish)
- Existing systemd templates in `config/systemd/user/` (already created)

---

## 3. Detailed Action Items

### Phase 0 — Skeleton & Foundations

| Task | Description | Effort | Start | End | Status Method |
|------|-------------|--------|-------|-----|---------------|
| T01 | Create config directory structure and default `omasync.conf` generation | 2h | Day 1 | Day 1 | `ls` dirs + verify conf |
| T02 | Write `omasync-lib.sh` — config loading, validation, gum wrappers, all shared helpers | 6h | Day 1 | Day 2 | Source lib + run each function |
| T03 | Write `omasync-setup` skeleton — shebang, strict mode, main menu, sub-menu dispatch | 3h | Day 2 | Day 2 | Run script, navigate menus |
| T04 | Write `omasync` skeleton — argument parsing, interactive/CLI mode branching | 3h | Day 2 | Day 3 | `--help` output + interactive launch |

**Owner:** Solo developer
**Tracking:** Task checkboxes in `task-omasync.md`

### Phase 1 — Device Management

| Task | Description | Effort | Start | End | Status Method |
|------|-------------|--------|-------|-----|---------------|
| T05 | Add Device wizard — gum inputs, validation, save config | 4h | Day 4 | Day 4 | Add a test device via TUI |
| T06 | SSH key generation — ed25519, passphrase prompt, clipboard | 3h | Day 4 | Day 5 | Verify keypair at ~/.ssh/ |
| T07 | Termux setup guide — gum styled instructions | 2h | Day 5 | Day 5 | View guide in terminal |
| T08 | Linux/macOS setup guide — ssh-copy-id pre-filled | 1h | Day 5 | Day 5 | View guide in terminal |
| T09 | Connection test — SSH check with spinner + error hints | 2h | Day 6 | Day 6 | Test against live + dead hosts |
| T10 | Edit Device — pick, edit fields, save | 2h | Day 7 | Day 7 | Edit a field, verify conf |
| T11 | Remove Device — confirm, delete conf + optional keys | 1h | Day 7 | Day 7 | Remove device, verify cleanup |
| T12 | List Devices — styled table output | 1h | Day 8 | Day 8 | List with 2+ devices |

### Phase 2 — Sync Profiles

| Task | Description | Effort | Start | End | Status Method |
|------|-------------|--------|-------|-----|---------------|
| T13 | Add Profile wizard — all fields, validation, save | 3h | Day 9 | Day 9 | Add a test profile via TUI |
| T14 | Edit Profile — pick, edit fields, save | 2h | Day 9 | Day 10 | Edit a field, verify conf |
| T15 | Remove Profile — confirm, delete conf | 1h | Day 10 | Day 10 | Remove profile, verify cleanup |
| T16 | List Profiles — styled table output | 1h | Day 10 | Day 10 | List with 2+ profiles |

### Phase 3 — Sync Runner

| Task | Description | Effort | Start | End | Status Method |
|------|-------------|--------|-------|-----|---------------|
| T17 | Interactive device selection with empty-state handling | 1h | Day 11 | Day 11 | Select device in TUI |
| T18 | Interactive profile selection (multi-select) | 1h | Day 11 | Day 11 | Select profiles in TUI |
| T19 | Rsync command generator — push/pull/both, excludes, delete | 6h | Day 11 | Day 12 | Print generated commands, verify flags |
| T20 | Confirmation screen — summary box, run/dry-run/cancel | 2h | Day 12 | Day 12 | View confirmation screen |
| T21 | Sync execution — raw rsync output, SIGINT trap | 4h | Day 13 | Day 13 | Run a real sync |
| T22 | Result summary + logging — stats, log file | 3h | Day 14 | Day 14 | Check log file after sync |
| T23 | CLI mode — `--device X --profile Y --yes` | 3h | Day 14 | Day 15 | Run from command line |

### Phase 4 — Tailscale Integration

| Task | Description | Effort | Start | End | Status Method |
|------|-------------|--------|-------|-----|---------------|
| T-TS1 | `resolve_host()` with Tailscale DNS + fallback | 3h | Day 16 | Day 16 | Resolve a Tailscale hostname |
| T-TS2 | `DEVICE_TAILSCALE` config field + loader update | 1h | Day 16 | Day 16 | Load device with field set |
| T-TS3 | Tailscale device discovery in setup wizard | 2h | Day 17 | Day 17 | Discover devices in Add Device |
| T-TS4 | Session-level DNS caching | 1h | Day 17 | Day 17 | Verify cached resolution |

### Phase 5 — Polish & Extras

| Task | Description | Effort | Start | End | Status Method |
|------|-------------|--------|-------|-----|---------------|
| T24 | Dry-run mode — `--dry-run` flag + gum pager | 2h | Day 18 | Day 18 | Run dry-run, verify no changes |
| T25 | Sync logging + rotation | 2h | Day 18 | Day 18 | Verify log rotation |
| T26 | Last-sync tracking — timestamp file + relative display | 2h | Day 19 | Day 19 | Verify "2h ago" display |
| T27 | Systemd timer generation | 3h | Day 19 | Day 19 | Enable timer, verify schedule |
| T28 | Waybar module | 2h | Day 20 | Day 20 | Verify Waybar display + click |

---

## 4. Risk Assessment and Mitigation

### Phase 0: Skeleton & Foundations

| Risk | Level | Mitigation |
|------|-------|------------|
| Config parsing breaks on edge-case values (quotes, special chars, spaces) | Medium | Whitelist-only `case` parsing; extensive test cases for malformed input |
| `gum` not installed on target system | Low | All gum interactions have POSIX fallbacks via `gum_or_*` wrappers |
| XDG directory overrides cause unexpected paths | Low | Use `${XDG_CONFIG_HOME:-$HOME/.config}` pattern consistently |

### Phase 1: SSH & Device Management

| Risk | Level | Mitigation |
|------|-------|------------|
| ssh-keygen fails on immutable filesystem (Secureblue) | Medium | `~/.ssh` is in user home (writable); test on Secureblue early |
| Termux SSH setup too complex for users | Medium | Detailed step-by-step guide with `gum` formatting; test with real Termux device |
| wl-copy not available (clipboard fails silently) | Low | Check `command -v wl-copy` before use; always display key as text fallback |
| Host key changes trigger SSH rejection | Medium | `StrictHostKeyChecking=accept-new` — TOFU model; show clear error with re-key instructions |
| User enters invalid port/host during wizard | Low | Input validation: port range 1–65535, non-empty host, sanitized device name |

### Phase 2: Sync Profiles

| Risk | Level | Mitigation |
|------|-------|------------|
| Local path doesn't exist yet | Low | Warn but allow — path created on first pull |
| Exclude pattern contains `..` (path traversal) | Low | Validation rejects patterns with `..` |
| User enables `--delete` without understanding implications | Medium | Confirmation dialog explicitly explains `--delete` behavior; dry-run offered first |

### Phase 3: Rsync Runner

| Risk | Level | Mitigation |
|------|-------|------------|
| `--delete` destroys user data unexpectedly | High | Explicit opt-in per profile; confirmation screen; dry-run offered before every destructive sync |
| rsync hangs on network timeout | Medium | SSH `ConnectTimeout=10`, `ServerAliveInterval=30`, `ServerAliveCountMax=3` |
| Bidirectional sync causes data loss (same file modified both sides) | Medium | `--update` flag (last-writer-wins); clear documentation; recommend Unison for true merge |
| `eval` of rsync command introduces injection risk | Medium | Build command as array, not string; avoid eval where possible |
| Large initial sync takes very long | Low | `--partial` for resume; `--info=progress2` for whole-transfer progress |

### Phase 4: Tailscale DNS

| Risk | Level | Mitigation |
|------|-------|------------|
| Tailscale not installed or not running | Low | Silent fallback to DEVICE_HOST; no errors |
| Tailscale DNS returns stale IP (device moved) | Low | Session-level cache only (not persistent); re-resolve each session |
| `jq` not installed (needed for `tailscale status --json`) | Medium | Check `command -v jq`; fallback to `tailscale ip` (simpler, no jq needed) |

### Phase 5: Polish & Extras

| Risk | Level | Mitigation |
|------|-------|------------|
| Systemd timer runs when device is offline | Medium | Sync exits gracefully on connection failure; systemd logs the failure |
| Log rotation deletes important logs | Low | Configurable `LOG_KEEP_COUNT` (default 10); oldest deleted first |
| Waybar module stale after failed sync | Low | Module reads last-sync timestamp; shows "failed" status from exit code |

---

## 5. Resource Allocation

### Team & Roles

| Role | Person | Responsibility |
|------|--------|---------------|
| Developer | mino | All implementation, testing, documentation |
| Reviewer | — | Self-review; consider sharing with Omablue community for feedback |

### Budget Breakdown

This is a personal/open-source project — no monetary budget. Cost is measured in time:

| Phase | Estimated Hours |
|-------|----------------|
| Phase 0 | 14h |
| Phase 1 | 16h |
| Phase 2 | 7h |
| Phase 3 | 20h |
| Phase 4 | 7h |
| Phase 5 | 11h |
| **Total** | **~75h** |

### Tools & Technology

| Tool | Purpose | Status |
|------|---------|--------|
| bash (5.x) | Script runtime | Installed |
| ssh / ssh-keygen | Connection + key management | Installed |
| rsync | File synchronization | Installed |
| gum | TUI components (menus, inputs, spinners, styling) | Installed via Omablue setup |
| wl-copy | Clipboard (Wayland) | Installed |
| tailscale | VPN + DNS resolution | Installed (optional) |
| jq | JSON parsing for Tailscale status | Needs verification |
| systemctl | Timer/service management | Installed (systemd) |
| waybar | Status bar integration | Installed |
| foot | Terminal emulator (for launching omasync) | Installed |

### Training Requirements

- None — all tools are already in the Omablue stack
- Reference: `omablue-bluetooth` and `omablue-bluetooth-autoconnect` as pattern examples for script structure, gum usage, and systemd integration

---

## 6. Communication Plan

### Stakeholders

| Stakeholder | Interest | Communication Method |
|-------------|----------|---------------------|
| mino (developer/user) | Primary user; all decisions | Direct (self) |
| Omablue community | Potential users | Git commits, README updates |
| Future contributors | Code understanding | In-code comments, this plan, task checklist |

### Update Frequency

| Milestone | Update Action |
|-----------|---------------|
| Phase completion | Update `task-omasync.md` checkboxes; git commit |
| Feature working | Manual testing on real devices; note results |
| Blockers encountered | Document in `task-omasync.md` under "Open Questions" |
| v1.0 ready | Update `README.md`; tag release |

### Key Decision Points

| Decision | When | Context |
|----------|------|---------|
| Profiles: device-specific vs shared? | Before Phase 2 | Master plan notes this as open question. Current design: shared. Decide before implementing. |
| Password auth fallback? | Before Phase 1 | Recommendation: keys only. Confirm before implementing. |
| `eval` for rsync command execution? | During Phase 3 (T19/T21) | Security concern. Prefer array-based execution if possible. |
| Unison integration scope | After v1.0 | Future enhancement — don't scope now |

---

## 7. Success Metrics and KPIs

### Phase-Level Metrics

| Phase | Metric | Target |
|-------|--------|--------|
| 0 | Scripts launch without error; dirs created | 100% pass |
| 1 | Can add device + generate key + test connection end-to-end | Works on 1+ real device |
| 2 | Can create/edit/remove profiles through TUI | All CRUD operations work |
| 3 | Can sync files between two machines (push, pull, both) | Verified transfer + logs |
| 4 | Tailscale DNS resolves correctly; fallback works when unavailable | Both paths tested |
| 5 | Timers fire on schedule; Waybar shows status; dry-run previews correctly | All 5 extras working |

### Overall KPIs

| KPI | Measurement | Target |
|-----|-------------|--------|
| Functionality | All 28 tasks in checklist complete | 28/28 |
| Reliability | Ctrl+C never crashes; errors show hints | 0 unhandled crashes |
| Security | No `source`/`eval` on config; keys at 600; no secrets in logs | Pass audit checklist |
| UX | Every gum prompt has Ctrl+C handling + non-gum fallback | 100% coverage |
| CLI parity | Every interactive operation has a CLI equivalent | All operations scriptable |

### Monitoring & Reporting

| Activity | Frequency |
|----------|-----------|
| Update task checkboxes in `task-omasync.md` | After each task completion |
| Run manual test suite (Section 9 of master plan) | After each phase |
| Review security checklist (Section 7 of master plan) | Before declaring phase complete |
| Full end-to-end test (localhost + real device) | After Phase 3, and before v1.0 |

### Adjustment Triggers

| Trigger | Action |
|---------|--------|
| SSH key management too complex for Termux | Simplify guide; consider password auth as opt-in fallback |
| `eval` of rsync command causes security concern | Refactor to array-based execution (avoid eval entirely) |
| Bidirectional sync causes data loss in testing | Add mandatory dry-run before first bidirectional sync; document limitations more prominently |
| Phase takes >2x estimated time | Re-evaluate scope; consider deferring non-critical deliverables to Phase 5 |
| gum version incompatibility | Pin minimum gum version; add version check in `check_dependencies()` |

---

## 8. Gap Analysis

### Gaps Between Master Plan and Implementation

| Gap | Description | Recommendation |
|-----|-------------|----------------|
| **`eval` security risk** | Phase 3 rsync command builder uses `eval "$cmd"` to execute the built command string. This is a potential injection vector if config values contain shell metacharacters. | Refactor `build_rsync_cmd()` to return an array, not a string. Execute via `"${cmd[@]}"` instead of `eval`. |
| **SSH agent integration** | Master plan mentions ssh-agent for passphrase-protected keys but no implementation is provided. Without it, every sync with a passphrase-protected key will prompt. | Add `ssh-add` integration in Phase 1 (T06). Check if key is already in agent before syncing. |
| **jq dependency for Tailscale** | Phase 4 uses `jq` to parse `tailscale status --json`, but jq isn't listed in the dependency check. | Add `jq` to optional dependency check. Provide fallback using `tailscale ip` (which doesn't need jq). |
| **Error recovery for `--delete`** | `--delete` can remove files on the destination that don't exist on source, but there's no undo mechanism. | Add a mandatory dry-run preview before any sync with `--delete` enabled (at least on first run). |
| **No bandwidth limiting config** | Master plan mentions `--bwlimit` in the rsync flag table but no config field exists in profile or global config. | Add optional `RSYNC_BWLIMIT` field to global config or profile config. |
| **Profiles are device-independent** | Open question in `task-omasync.md`: remote paths may differ per device. No mechanism for per-device path overrides. | Decide before Phase 2. Simplest approach: keep profiles shared, add optional `REMOTE_PATH_OVERRIDE` per device+profile if needed later. |
| **No `omasync --logs` subcommand** | T25 mentions `omasync --logs` to view recent logs, but no implementation detail is provided. | Add `--logs [device] [profile]` flag to `omasync` that lists/views recent log files via `gum pager`. |

### Assumptions Made

| # | Assumption | Recommendation |
|---|-----------|----------------|
| 1 | The developer has SSH access to at least one remote device for testing during Phase 1–3 | Set up localhost SSH (`sshd` on the local machine) as a minimum test target |
| 2 | `gum` is version 0.13+ (for all features used, especially `gum choose --no-limit`) | Add version check: `gum --version` in `check_dependencies()` |
| 3 | rsync is GNU rsync 3.x (not macOS system rsync 2.x) on the local machine | Secureblue ships modern rsync — verify with `rsync --version` |
| 4 | Tailscale is already configured and authenticated (omasync doesn't handle Tailscale setup) | Document this prerequisite in the Tailscale section |
| 5 | User's `~/.ssh` directory is writable (relevant on immutable distros like Secureblue) | Verify early in Phase 1; user home is writable on Secureblue |
| 6 | Profiles are shared across all devices (same profile can be used with any device) | Confirm this design choice before Phase 2 implementation |
| 7 | No Windows/WSL target support in v1.0 | WSL listed in platform testing but no WSL-specific handling in master plan |

---

## 9. Quick Wins (First 30 Days)

### Quick Win 1: Skeleton + First Device (Days 1–5)

Complete Phase 0 + the "Add Device" wizard (T05) + SSH key generation (T06) + connection test (T09). This gives you a working `omasync-setup` that can register a real device and verify connectivity. **Immediate value:** You can test SSH connections to your devices and have keys managed consistently.

### Quick Win 2: First Working Sync (Days 6–12)

With a device configured, implement a minimal "Add Profile" (T13) + the rsync command generator (T19) + basic sync execution (T21). Skip the full TUI polish — just get `omasync --device pixel --profile music --yes` working from the command line. **Immediate value:** You can sync files between your machines right away, even before the TUI is polished.

### Quick Win 3: Systemd Automated Sync (Days 13–15)

Once CLI mode works, wire up systemd timer generation (T27) using the existing templates in `config/systemd/user/`. This turns your manual sync into an automated scheduled job. **Immediate value:** Set-and-forget file sync running on a timer, with journal logging for debugging.

---

## 10. Recommended Next Steps

1. **Resolve open questions** before starting Phase 2:
   - Profiles: device-specific vs shared? (Recommendation: shared, with per-device overrides later)
   - Password auth: keys only? (Recommendation: yes, keys only for v1.0)

2. **Set up a localhost SSH test environment** for development — avoids needing a second device for every test cycle

3. **Start with Phase 0 + Quick Win 1** — get the skeleton and first device working in the first week

4. **Address the `eval` security concern early** (during T19/T21) — design the rsync command builder to use arrays from the start rather than refactoring later

5. **Add `jq` to optional dependencies** and implement the Tailscale fallback path (no-jq) from the beginning
