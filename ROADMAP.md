# Roadmap

## Current status

- `shell/` is an unmodified fork of Omarchy's shell at
  `e38c1d1289252d2adb96372eeac48d02e489c5b7` (imported 2026-09-20).
- `switcher/jetshell-switch` inspects and switches between jetshell, stock
  Omarchy, and Noctalia, with rollback and a lock check. Tested with mocks
  only; not yet run against real shells.
- `plugins/agent-usage/` is working and installs into Omarchy's plugin
  directory.
- The shell still requires Omarchy's `OMARCHY_PATH` and `omarchy-*` helpers.

## Next

1. **Set up the test machine** — install Quickshell and the Omarchy tree
   (`scripts/omarchy-shell.sh`) without its unconditional autostart, and run
   `switch` against real shells.
2. **Session startup** — start the saved backend at login instead of
   hard-coded autostarts.
3. **Fold in agent-usage** — decide whether `plugins/agent-usage/` replaces the
   inherited `shell/plugins/agents/` and move it into the shell.

## Later

- Interactive picker (e.g. `wofi`) for the switcher.
- Own config and plugin paths (e.g. `~/.config/jetshell/`) instead of
  `~/.config/omarchy/`.
- Replace the `omarchy-*` helpers the shell depends on, starting with
  `omarchy-shell` IPC/control.
- Prune first-party plugins that aren't wanted.
- Periodically review upstream Omarchy `shell/` changes worth cherry-picking.
