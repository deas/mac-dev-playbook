# Operator tasks for host services that Ansible provisions but does not converge
# on demand. Lint, tests and provisioning stay in the Makefile (`make preflight`).

# Keep in sync with the hermes_* vars in default.config.yml.
hermes_user := "apfelmus"
hermes_home := "/Users/apfelmus/hermes-docker-daten"
hermes_bin := "/Users/apfelmus/.local/bin/hermes"
hermes_label := "de.contentreich.hermes-gateway"

# List the available recipes.
default:
    @just --list

# Show the Hermes gateway's launchd state and installed version.
hermes-status:
    @sudo -u {{ hermes_user }} launchctl print "gui/$(id -u {{ hermes_user }})/{{ hermes_label }}" 2>/dev/null | grep -E '^[[:space:]](state|pid|runs) ' || echo "{{ hermes_label }}: not loaded"
    @sudo -u {{ hermes_user }} -H {{ hermes_bin }} --version | head -1

# Check for a Hermes update without touching the running gateway.
hermes-check:
    @sudo -u {{ hermes_user }} -H env HERMES_HOME={{ hermes_home }} {{ hermes_bin }} update --check

# Restart the gateway without updating.
hermes-restart:
    @sudo -u {{ hermes_user }} launchctl kickstart -k "gui/$(id -u {{ hermes_user }})/{{ hermes_label }}"
    @just hermes-status

# Stop the gateway, update Hermes, start it again (args go to `hermes update`).
hermes-update *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail

    # launchctl, not `hermes gateway stop/start/restart`: those act on hermes' own
    # ai.hermes.gateway label, which tasks/hermes.yml deliberately removes. With
    # that plist gone they fall through to a SIGTERM on the pid and KeepAlive
    # respawns the job -- a bounce, not a stop. `hermes update` skips its own
    # service restart for the same reason (hermes_cli/update_cmd.py gates it on
    # that plist existing), so the restart has to happen here or the gateway keeps
    # serving the old code.

    user={{ hermes_user }}
    label={{ hermes_label }}
    uid=$(id -u "$user")
    target="gui/$uid/$label"
    plist="/Users/$user/Library/LaunchAgents/$label.plist"

    loaded() { sudo -u "$user" launchctl print "$target" >/dev/null 2>&1; }

    # launchd tears a job down asynchronously, so bootstrapping too soon after a
    # bootout returns "Bootstrap failed: 5: Input/output error" (upstream #11323).
    start() {
      if loaded; then return 0; fi
      for _ in 1 2 3 4 5; do
        if sudo -u "$user" launchctl bootstrap "gui/$uid" "$plist"; then return 0; fi
        sleep 3
      done
      return 1
    }

    on_exit() {
      local rc=$?
      if (( rc != 0 )); then
        echo "!! update failed (exit $rc) -- restarting the gateway on the old code" >&2
        start || echo "!! restart failed. Recover with: just hermes-restart" >&2
      fi
    }
    trap on_exit EXIT

    echo "==> before: $(sudo -u "$user" -H {{ hermes_bin }} --version | head -1)"

    if loaded; then
      echo "==> stopping $label"
      sudo -u "$user" launchctl bootout "$target" || true
      for _ in $(seq 1 20); do
        loaded || break
        sleep 1
      done
      if loaded; then
        echo "!! $label did not unload; aborting before the update" >&2
        exit 1
      fi
    else
      echo "==> $label is not loaded; updating anyway"
    fi

    # HERMES_HOME is unset in apfelmus' login shell -- only the plist sets it.
    # Without it here the pre-update backup and config migration would target
    # ~/.hermes, which on this host is a different state tree.
    echo "==> updating hermes"
    sudo -u "$user" -H env HERMES_HOME={{ hermes_home }} {{ hermes_bin }} update {{ ARGS }}

    echo "==> starting $label"
    start

    echo "==> after:  $(sudo -u "$user" -H {{ hermes_bin }} --version | head -1)"
    sudo -u "$user" launchctl print "$target" | grep -E '^[[:space:]](state|pid|runs) '
