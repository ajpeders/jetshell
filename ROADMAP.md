# Roadmap

## Current status

- `shell/` is an unmodified fork of Omarchy's shell at
  `e38c1d1289252d2adb96372eeac48d02e489c5b7` (imported 2026-09-20).
- `switcher/jetshell-switch` inspects and switches between jetshell, stock
  Omarchy, and Noctalia, with rollback and a lock check; `restart` reloads the
  running shell and `start` brings up the saved shell at login.
- `plugins/agent-usage/` is working and installs into Omarchy's plugin
  directory.
- The shell still requires Omarchy's `OMARCHY_PATH` and `omarchy-*` helpers.

## Next

1. **Test jetshell for real** — Quickshell and the Omarchy tree are installed;
   switch to jetshell and exercise the wallpaper/Settings work on
   `wip/settings-panel`.
2. **Commit the login hook** — `hypr/config/autostart.lua` in the dotfiles
   repo calls `jetshell-switch start`; that edit is not committed yet.
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
