# Architecture

## Overview

jetshell is a single long-running Quickshell instance that hosts the whole
desktop: bar, panels, overlays, notifications, lock screen, OSD, and polkit
agent. It started as a fork of Omarchy's `shell/` directory (fork point in
`shell/UPSTREAM.md`) and is expected to diverge from it.

## One process, many plugins

Everything runs **inside** the shell as a plugin rather than as separate
`quickshell -p ...` processes:

- shared services and singletons exist once
- summoning a panel is an IPC call into the running process, not a cold start
- plugins are discovered from disk, so new ones need no core changes

Key pieces in `shell/`:

- `shell.qml` — entry point (`ShellRoot`); loads config and mounts plugins
- `services/PluginRegistry.qml` — discovers and validates plugin manifests
- `services/BarWidgetRegistry.qml` — registry for bar widgets
- `plugins/<name>/manifest.json` — declares each plugin's `kinds`
  (`bar`, `bar-widget`, `panel`, `overlay`, `menu`, `service`) and entry points
- `Ui/`, `Commons/` — shared QML components and style

Services and keep-loaded panels mount at startup; other panels, overlays, and
menus load on demand. Full plugin contract: `shell/OMARCHY.md` and
`shell/plugins/README.md`.

## Configuration

`shell.qml` reads layout and plugin settings from
`~/.config/omarchy/shell.json`, falling back to
`$OMARCHY_PATH/config/omarchy/shell.json`, then to a built-in default.
User plugins are discovered under `~/.config/omarchy/plugins/<id>/`.

## Omarchy runtime dependency

The shell is not yet standalone. It relies on:

- `OMARCHY_PATH` (set by Omarchy's uwsm session) for default config
- ~90 distinct `omarchy-*` helper programs it shells out to — the most used
  being `omarchy-shell` (IPC/control), `omarchy-menu`, network, weather,
  notification, lock, and theme helpers

Reducing this dependency — owning config paths and replacing helpers the shell
needs — is how jetshell becomes its own thing.

## Test switcher

`switcher/jetshell-switch` moves the desktop between three backends so the fork
can be compared with the stock shell:

| Backend    | Started by                                     | Detected by                       |
|------------|------------------------------------------------|-----------------------------------|
| `jetshell` | `omarchy-launch-shell`, `OMARCHY_PATH=overlay` | `quickshell -p <overlay>/shell`   |
| `omarchy`  | `omarchy-launch-shell`, `OMARCHY_PATH=tree`    | `quickshell -p <tree>/shell`      |
| `noctalia` | `systemctl --user` `noctalia-shell.service`    | `systemctl --user is-active`      |

**Why an overlay:** `omarchy-shell` sends every IPC call to
`qs ipc -p "$OMARCHY_PATH/shell"`, so helpers only reach whichever shell lives at
that path. The jetshell overlay (`$XDG_STATE_HOME/jetshell/omarchy-root`)
links every entry of the real Omarchy tree except `shell/`, which points at this
repo's `shell/`. Helpers, keybinds, and menus then drive the fork without
modification.

The real tree is found at `$JETSHELL_OMARCHY_ROOT`, `$OMARCHY_PATH` (unless it is
the overlay), `/usr/share/omarchy`, or the `scripts/omarchy-shell.sh` unpack at
`~/.local/share/omarchy-shell/usr/share/omarchy`. Running shells are detected by
reading `/proc/*/cmdline` for the `-p` argument — never by broad process-name
matching — so stock Omarchy and jetshell are told apart.

Noctalia 5 is a native binary, not built on `noctalia-qs`, so it coexists with
upstream Quickshell on one machine.

`switch <backend>`:

1. Validate the target (`doctor`'s checks); fail before touching anything.
2. Refuse if a running Omarchy-based shell reports `lock isLocked` = `true`.
3. For jetshell, rebuild the overlay (staged, then swapped in).
4. Stop each running backend and wait until it is gone. Quickshell backends
   are stopped by PID: when the parent is `omarchy-launch-shell`, the
   supervisor is signalled instead, since it would relaunch a killed shell.
5. Start the target (`setsid -f omarchy-launch-shell` or `systemctl --user
   start`) and wait for readiness (`omarchy-shell shell ping` = `ok`, or the
   service is active).
6. On success, write `$XDG_STATE_HOME/jetshell/active` atomically. On
   failure, stop the target and restart the previous backends.

`restart` runs steps 2–5 on the single running backend; if a Quickshell
backend fails to return it starts Noctalia instead and leaves the saved
selection unchanged.

Timeouts: `JETSHELL_START_TIMEOUT` (15 s), `JETSHELL_STOP_TIMEOUT` (10 s).

## agent-usage plugin

`plugins/agent-usage/` is a third-party-style plugin (id `agent-usage`)
developed outside `shell/`. `scripts/install-agent-usage` syncs it to
`~/.config/omarchy/plugins/agent-usage/` and asks the running shell to
rescan plugins. Its Python collector (`collectors/collect.py`) gathers usage
data the QML panel displays. It overlaps with the first-party
`shell/plugins/agents/` (`omarchy.agents`) inherited from the fork.

## Key decisions

- **Fork, not vendor.** `shell/` is edited directly; upstream fixes are
  cherry-picked by diffing against the recorded fork point.
- **Keep the upstream plugin contract** for now so Omarchy plugins keep working
  while the shell diverges.
