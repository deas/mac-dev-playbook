# Colima VM Recovery Diagnosis — `apfelmus`

**Date:** 2026-07-07
**Symptom:** Colima VM not running under user `apfelmus`; `colima status` reported `colima is not running`.

## Root Cause

The host **rebooted around 17:06** (all `apfelmus` system processes date to 17:06–17:07). The VM had been healthy until **17:04** (hostagent log showed normal time-sync activity up to that point).

On reboot, the `com.colima.apfelmus` system LaunchDaemon tried to start colima (`colima start -f`), but the Lima instance was left in a **`Broken`** state:

- Stale `ha.pid`, `vz.pid` (both pointing at dead PID **765**), `ha.sock`, and `ssh.sock` remained under `/Users/apfelmus/.colima/_lima/colima/` from the pre-reboot process.
- Colima found the orphaned instance (`Using the existing instance "colima"`) but could not reconcile it — every start failed with:

  ```
  failed to get Info from ".../ha.sock": ... dial unix .../ha.sock: connect: connection refused
  error starting vm: error at 'starting': exit status 1
  ```

- The daemon **crash-looped 182 times** (exit code 1, retry ~every 10s).

The underlying VM definition, profile, and **20 GiB disk image were intact** — no data loss.

## Evidence

| Check | Result |
|-------|--------|
| `launchctl print system/com.colima.apfelmus` | `runs = 182`, `last exit code = 1`, `state spawn scheduled` |
| `colima.log` | repeated `connection refused` on `ha.sock`, then `exit status 1` |
| `ha.stderr.log` | healthy until 17:04, then silent (VM died at reboot) |
| `ha.pid` / `vz.pid` | both `765` (dead process) |
| `limactl list` (LIMA_HOME=`~/.colima/_lima`) | instance `colima` → **Broken** |
| `disk` file | 20G present, intact |

## Fix Applied

1. **Stop the crash loop:**
   ```bash
   sudo launchctl bootout system/com.colima.apfelmus
   ```
2. **Clear the stale Broken instance** (removes stale `*.pid`/`*.sock`, no data loss):
   ```bash
   sudo -u apfelmus env LIMA_HOME=/Users/apfelmus/.colima/_lima \
     limactl stop -f colima
   ```
   → instance transitioned to clean `Stopped`.
3. **Re-bootstrap the daemon** (restores launchd supervision as designed):
   ```bash
   sudo launchctl bootstrap system /Library/LaunchDaemons/com.colima.apfelmus.plist
   ```

## Verified Result

- `colima status` → **running** (macOS Virtualization.Framework, aarch64, docker runtime)
- `colima list` → profile `default` **Running**, 2 CPU / 4 GiB / 100 GiB disk
- Daemon → `state = running`, `runs = 1`, never exited (loop gone)
- **`hermes-agent` container auto-restarted** and is Up; ports `8642` and `9119` forwarded

## Gotchas

- **Inspect as `apfelmus` with `-H`:** from the `devops` account use `sudo -u apfelmus -H ...`. Without `-H`, `HOME` stays `/Users/devops` and colima/docker read the wrong config and falsely report "not running".
- **Colima's Lima instances live under `~/.colima/_lima`** (set `LIMA_HOME`), not the default `~/.lima` — a plain `limactl list` shows "No instance found".
