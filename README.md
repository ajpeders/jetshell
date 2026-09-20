# jetshell

Switch the active desktop shell between three stacks, from a CLI or an
interactive menu, with the choice persisted across reboots.

- **noctalia** — Noctalia 5 (native), `noctalia-shell.service`
- **custom** — a hand-written Quickshell config (`~/.config/quickshell/<name>/shell.qml`)
- **omarchy** — the real Omarchy shell (Quickshell + `omarchy-*` helpers), via the
  existing `scripts/omarchy-shell.sh` unpack

> Work in progress — the switcher is not built yet.
