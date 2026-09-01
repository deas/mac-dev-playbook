# Operator tasks for host services that Ansible provisions but does not converge
# on demand. Lint, tests and provisioning stay in the Makefile (`make preflight`).

# Keep in sync with the hermes_* vars in default.config.yml.
hermes_user := "apfelmus"
hermes_home := "/Users/apfelmus/hermes-daten"
hermes_bin := "/Users/apfelmus/.local/bin/hermes"
hermes_label := "ai.hermes.gateway-de.contentreich"
hermes_dashboard_label := "de.contentreich.hermes-dashboard"

# List the available recipes.
default:
    @just --list

# Show both Hermes agents' launchd state and the installed version.
hermes-status:
    @for label in {{ hermes_label }} {{ hermes_dashboard_label }}; do \
        echo "== $label"; \
        sudo -u {{ hermes_user }} launchctl print "gui/$(id -u {{ hermes_user }})/$label" 2>/dev/null | grep -E '^[[:space:]](state|pid|runs) ' || echo "  not loaded"; \
    done
    @sudo -u {{ hermes_user }} -H {{ hermes_bin }} --version | head -1

# Check for a Hermes update without touching the running gateway.
hermes-check:
    @sudo -u {{ hermes_user }} -H env HERMES_HOME={{ hermes_home }} {{ hermes_bin }} update --check

# Restart the gateway without updating.
hermes-restart:
    @sudo -u {{ hermes_user }} launchctl kickstart -k "gui/$(id -u {{ hermes_user }})/{{ hermes_label }}"
    @just hermes-status

# Restart the dashboard without updating.
hermes-dashboard-restart:
    @sudo -u {{ hermes_user }} launchctl kickstart -k "gui/$(id -u {{ hermes_user }})/{{ hermes_dashboard_label }}"
    @just hermes-status

# Stop both agents, update Hermes, start them again (args go to `hermes update`).
hermes-update *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail

    # launchctl, not `hermes gateway stop/start/restart`: those act on hermes' own
    # ai.hermes.gateway label, which tasks/hermes.yml deliberately removes -- the
    # label above only shares its prefix, and hermes derives no label from it. With
    # that plist gone they fall through to a SIGTERM on the pid and KeepAlive
    # respawns the job -- a bounce, not a stop. `hermes update` skips its own
    # service restart for the same reason (hermes_cli/update_cmd.py gates it on
    # that plist existing), so the restart has to happen here or the gateway keeps
    # serving the old code.
    #
    # The dashboard comes down too. `hermes update` calls
    # _kill_stale_dashboard_processes to avoid a new JS bundle on disk talking to
    # an old Python backend in memory; under KeepAlive that kill is just a respawn
    # onto half-updated files. Booting the label out is the honest stop.

    user={{ hermes_user }}
    labels=({{ hermes_label }} {{ hermes_dashboard_label }})
    uid=$(id -u "$user")

    loaded() { sudo -u "$user" launchctl print "gui/$uid/$1" >/dev/null 2>&1; }

    # launchd tears a job down asynchronously, so bootstrapping too soon after a
    # bootout returns "Bootstrap failed: 5: Input/output error" (upstream #11323).
    start_one() {
      local label=$1
      if loaded "$label"; then return 0; fi
      for _ in 1 2 3 4 5; do
        if sudo -u "$user" launchctl bootstrap "gui/$uid" \
            "/Users/$user/Library/LaunchAgents/$label.plist"; then
          return 0
        fi
        sleep 3
      done
      return 1
    }

    start() {
      local rc=0
      for label in "${labels[@]}"; do
        start_one "$label" || { echo "!! failed to start $label" >&2; rc=1; }
      done
      return $rc
    }

    on_exit() {
      local rc=$?
      if (( rc != 0 )); then
        echo "!! update failed (exit $rc) -- restarting on the old code" >&2
        start || echo "!! restart failed. Recover with: just hermes-restart" >&2
      fi
    }
    trap on_exit EXIT

    echo "==> before: $(sudo -u "$user" -H {{ hermes_bin }} --version | head -1)"

    for label in "${labels[@]}"; do
      if ! loaded "$label"; then
        echo "==> $label is not loaded; updating anyway"
        continue
      fi
      echo "==> stopping $label"
      sudo -u "$user" launchctl bootout "gui/$uid/$label" || true
      for _ in $(seq 1 20); do
        loaded "$label" || break
        sleep 1
      done
      if loaded "$label"; then
        echo "!! $label did not unload; aborting before the update" >&2
        exit 1
      fi
    done

    # HERMES_HOME is unset in apfelmus' login shell -- only the plists set it.
    # Without it here the pre-update backup and config migration would target
    # ~/.hermes, which on this host is a different state tree.
    echo "==> updating hermes"
    sudo -u "$user" -H env HERMES_HOME={{ hermes_home }} {{ hermes_bin }} update {{ ARGS }}

    echo "==> starting ${labels[*]}"
    start

    echo "==> after:  $(sudo -u "$user" -H {{ hermes_bin }} --version | head -1)"
    just hermes-status
