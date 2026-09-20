# jetshell

My desktop shell — a hand-written [Quickshell](https://quickshell.org) config,
plus the switcher that bootstraps you into it.

The end goal is one shell I own end to end. Until it is built, a switcher lets
me hop between the three stacks that live on my machines, with the choice
persisted across reboots.

## Components

```
jetshell/
├── switcher/   # jetshell-switch — pick the active shell, persist the choice
└── shell/      # the shell itself: a hand-written Quickshell config
```

### switcher/

Switches the active desktop shell between three stacks, from a CLI or an
interactive menu:

- **noctalia** — Noctalia 5 (native), `noctalia-shell.service`
- **custom** — the jetshell shell in `shell/` (`~/.config/quickshell/<name>/shell.qml`)
- **omarchy** — the real Omarchy shell (Quickshell + `omarchy-*` helpers), via
  the existing `scripts/omarchy-shell.sh` unpack in the dotfiles repo

### shell/

The jetshell shell proper. Hand-written Quickshell (bar, notifications, panels,
launcher). Work in progress — nothing here yet.

## Companion

- **[agent-usage](https://git.thelunadog.com/alex/agent-usage)** — a Quickshell
  bar-widget that tracks AI coding-usage (Claude, Codex, Fireworks, DeepSeek,
  Ollama, MiniMax) in one panel. Kept as a separate repo; it installs as a
  normal shell plugin under `~/.config/omarchy/plugins/`.

## Status

Work in progress — the switcher is not built yet, and the shell is an empty
scaffold.
