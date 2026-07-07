# Product Requirements Document (PRD)

**Objective:** Provision a private, agile Silicon Mac OS host for deploying AI- and
LLM-based services, driven by Ansible + Homebrew.

## Feature Index

| ID     | Feature                                          | Status |
| ------ | ------------------------------------------------ | ------ |
| F-01   | Colima VM resilience (self-healing LaunchDaemon) | 🏗     |

---

## [F-01] Colima VM Resilience

**Goal:** The Colima Docker VM running under `{{ colima_target_user }}` must
survive unclean host shutdowns (reboot, power loss, panic) and return to a
healthy state automatically, without manual intervention and without the
LaunchDaemon crash-looping.

### Background

On 2026-07-07 the host rebooted while the VM was running. On boot the
`com.colima.<user>` LaunchDaemon executed `colima start -f` directly, but the
Lima instance had been left `Broken` — stale `ha.sock`/`ha.pid`/`vz.pid` files
from the pre-reboot process. `colima start` cannot reconcile a Broken instance,
so it exited non-zero; `KeepAlive=true` respawned it immediately, producing a
crash loop (182 restarts) and a 19 MB debug log. Docker was unavailable and the
`hermes-agent` service stayed down until manual recovery. See
`colima-diagnosis.md`.

### Requirements

- **R1 — Self-heal stale state:** startup must clear stale Lima sockets/pids
  (force-stop the Broken instance) before `colima start`, so an unclean shutdown
  recovers automatically.
- **R2 — No crash loop:** a failed start must not tight-loop the daemon; retries
  are throttled and the host stays usable with bounded logs.
- **R3 — Do no harm:** a healthy, running VM must never be stop-started or
  otherwise disturbed by the supervisor.
- **R4 — Boot autostart preserved:** the VM must still start at boot, before
  login, under the system LaunchDaemon.
- **R5 — Idempotent provisioning:** re-running the playbook converges and
  re-bootstraps the daemon only when the supervisor, plist, or profile changes.

### Technical Spec

- `bin/colima-supervisor` — a long-running supervisor loop. Every
  `COLIMA_SUPERVISOR_INTERVAL` seconds (default 30) it checks `colima status`;
  when down it runs `limactl stop -f colima` (clears stale `*.sock`/`*.pid`;
  a no-op when already clean) then `colima start -f`. It never exits, so launchd
  supervises one healthy process instead of respawning a one-shot. (R1, R2, R3)
- `templates/colima-launchd.plist.j2` — `ProgramArguments` invokes
  `{{ colima_supervisor_path }}`; `RunAtLoad=true`, `KeepAlive=true` (restart the
  supervisor if the script itself dies), `ThrottleInterval=30` as a backstop
  against a fast-failing interpreter. (R2, R4)
- `tasks/colima.yml` — installs the supervisor to `{{ colima_supervisor_path }}`
  (`~/.colima/colima-supervisor`, owned by the target user) and re-bootstraps the
  LaunchDaemon when the script/plist/profile change. (R5)

### Acceptance Criteria

- After a hard reboot, `colima status` reports running without manual steps.
- With the instance forced into a Broken state, the supervisor restores it within
  one interval; `launchctl print system/com.colima.<user>` shows no runaway
  `runs` count.
- Starting from a healthy VM, the supervisor performs no stop/start (VM uptime is
  uninterrupted).
