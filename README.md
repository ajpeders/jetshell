# jetshell

My desktop shell — a [Quickshell](https://quickshell.org) shell forked from
[Omarchy](https://github.com/basecamp/omarchy)'s and growing into its own thing.

## Components

```
jetshell/
├── shell/            # the shell itself (fork of Omarchy's shell/)
├── switcher/         # jetshell-switch — test tool to hop between shells
├── plugins/
│   └── agent-usage/  # AI usage, balances, limits, and model breakdowns
└── scripts/          # install/development helpers
```

### switcher/

`jetshell-switch` moves the desktop between jetshell, stock Omarchy, and
Noctalia so the fork can be tested against the others
(`list`, `status`, `doctor`, `switch <backend>`).

### shell/

The jetshell shell proper: bar, notifications, panels, launcher, lock screen,
all hosted in one long-running Quickshell process as plugins. Currently the
unmodified Omarchy starting point — see `shell/UPSTREAM.md` for the fork point.
It still depends on Omarchy's `omarchy-*` helper programs and `OMARCHY_PATH`.

### plugins/agent-usage/

A Quickshell bar widget that tracks Claude, Codex, Fireworks, DeepSeek, Ollama,
and MiniMax in one panel. It combines local opencode session statistics with
provider account details where an API exists (currently DeepSeek prepaid
balance), and retains Omarchy's subscription limits for Claude and Codex.

## Quick start

Check which shells can run on this machine:

```bash
./switcher/jetshell-switch doctor
./switcher/tests/test-jetshell-switch
```

jetshell and stock Omarchy need Quickshell and an Omarchy tree; see
[HOWTO.md](HOWTO.md#set-up-quickshell-and-the-omarchy-tree).

Install the agent-usage plugin into Omarchy's plugin directory:

```bash
./scripts/install-agent-usage
omarchy plugin enable agent-usage
```

## Documentation

- [Architecture](ARCHITECTURE.md)
- [Roadmap](ROADMAP.md)
- [How-to guides](HOWTO.md)
