# How-to guides

## Check which shells can run

```sh
./switcher/jetshell-switch doctor   # per-backend readiness and why not
./switcher/jetshell-switch list     # availability + running state
./switcher/jetshell-switch status   # saved selection, running backends
```

`doctor` exits non-zero only when no backend is ready.

## Switch shells

```sh
./switcher/jetshell-switch switch jetshell   # the fork
./switcher/jetshell-switch switch omarchy    # stock, for comparison
./switcher/jetshell-switch switch noctalia   # fallback
```

Run it from a terminal inside the graphical session. It will not switch away
from a locked Omarchy/jetshell session, and it restores the previous shell if
the new one does not answer within 15 s. If a switch goes wrong, `switch
noctalia` is the known-good way back.

## Reload jetshell after editing `shell/`

The shell does not hot-reload, so restart it:

```sh
./switcher/jetshell-switch restart
```

If the edited shell fails to start (e.g. a QML error), the switcher falls
back to Noctalia. Check `journalctl --user -t omarchy-shell --since -2min`
for the error, fix it, then `switch jetshell` again.

## Set up Quickshell and the Omarchy tree

jetshell and stock Omarchy need upstream Quickshell plus Omarchy's helpers. On
a non-Omarchy Arch box, `scripts/omarchy-shell.sh` unpacks them under `$HOME`:

```sh
./scripts/omarchy-shell.sh --check   # report only
./scripts/omarchy-shell.sh           # install
```

The install uses `sudo pacman` for Quickshell and downloads the Omarchy
packages. It also writes `~/.config/hypr/omarchy/omarchy-shell.lua`, which
autostarts the stock shell, and requires it from `omarchy/autostart.lua`;
remove that require if the switcher should decide which shell starts.
Noctalia 5 can stay installed alongside.

## Run the switcher tests

```sh
./switcher/tests/test-jetshell-switch
```

Everything is mocked (PATH, `/proc`, the Omarchy tree, systemd); the tests
never touch the running desktop.

## Install or refresh the agent-usage plugin

```sh
./scripts/install-agent-usage
omarchy plugin enable agent-usage   # first time only
```

The script syncs `plugins/agent-usage/` into
`~/.config/omarchy/plugins/agent-usage/` and tells the running shell to rescan
plugins.

## Add a plugin

1. Create `shell/plugins/<name>/` with a `manifest.json` (schema, `kinds`, and
   entry points are documented in `shell/OMARCHY.md`).
2. Add the QML entry point(s) named in the manifest.
3. Restart the shell, or run `omarchy-shell shell rescanPlugins`.

## Pull a fix from upstream Omarchy

1. Clone `basecamp/omarchy` in a temporary directory.
2. Diff its `shell/` between the fork point in `shell/UPSTREAM.md` and the
   upstream revision you want.
3. Apply the relevant hunks to `shell/` by hand and review conflicts with local
   changes.
4. Note what was pulled in the commit message.

## Validate changes

```sh
git diff --check
python - <<'PY'
import json
from pathlib import Path

for path in Path(".").rglob("manifest.json"):
    json.load(path.open())
    print(path)
PY
```

If `qmllint` is installed, lint changed QML files. Omarchy-specific imports may
need the full runtime to resolve.
