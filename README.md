# jetshell

My desktop shell — a hand-written [Quickshell](https://quickshell.org) config,
plus the switcher that bootstraps you into it.

The end goal is one shell I own end to end. Until it is built, a switcher lets
me hop between the three stacks that live on my machines, with the choice
persisted across reboots.

## Components

```
jetshell/
├── plugins/
│   └── agent-usage/  # AI usage, balances, limits, and model breakdowns
├── scripts/          # install/development helpers
├── switcher/         # jetshell-switch — pick the active shell, persist it
└── shell/            # the shell itself: a hand-written Quickshell config
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

### plugins/agent-usage/

A Quickshell bar widget that tracks Claude, Codex, Fireworks, DeepSeek, Ollama,
and MiniMax in one panel. It combines local opencode session statistics with
provider account details where an API exists (currently DeepSeek prepaid
balance), and retains Omarchy's subscription limits for Claude and Codex.

Install or refresh the working copy under Omarchy's plugin directory:

```bash
./scripts/install-agent-usage
```

Then add it to the bar if it is not already present:

```bash
omarchy plugin enable agent-usage
```

## Status

Work in progress — the switcher is not built yet, and the shell is an empty
scaffold.
