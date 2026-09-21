# switcher

`jetshell-switch` — a testing tool that switches the desktop between:

- **jetshell** — the fork in `../shell/`, run with Omarchy's helpers
- **omarchy** — the stock Omarchy shell, for comparison
- **noctalia** — Noctalia 5 (`noctalia-shell.service`), a known-good fallback

```sh
./jetshell-switch list      # availability and running state
./jetshell-switch status    # saved selection and what is running
./jetshell-switch doctor    # why a backend is unavailable
./jetshell-switch switch jetshell|omarchy|noctalia
./tests/test-jetshell-switch
```

`switch` validates the target, refuses while an Omarchy-based shell is locked,
stops only the running backend, waits for the target to answer, and rolls back
if it does not. The selection is saved only after a successful switch.
