#!/bin/bash
# Omarchy's shell (bar, notifications, OSD, menu, lock) on a Hyprland box that
# is not running Omarchy.
# Usage: bash omarchy-shell.sh [--dir PATH] [--replace-noctalia] [--check] [--uninstall]
#
# The Omarchy shell is not a standalone Quickshell config: its QML shells out to
# ~60 of the omarchy-* helpers that ship beside it, so the tooling has to come
# along. It does not, however, need the omarchy *package* installed. OMARCHY_PATH
# is just a variable, so this unpacks the upstream packages under $HOME and points
# OMARCHY_PATH there -- no pacman repo, no keyring, no /etc drop-ins, and no sddm
# or uwsm dragged in as dependencies.
#
# Two packages are needed, not one:
#   omarchy           usr/bin/omarchy-* (the real programs) + shell/, themes/,
#                     install/, migrations/, and the bin/ symlink farm
#   omarchy-settings  config/, default/, applications/, the logo and icon
# Splitting them is why $OMARCHY_PATH/default exists on a real box. Unpacking
# only the first gets a tree whose helpers cannot find their defaults.
#
# The unpacked layout is kept as the packages ship it:
#   $DIR/usr/bin              the 428 real programs
#   $DIR/usr/share/omarchy    OMARCHY_PATH
# because $OMARCHY_PATH/bin is a symlink farm into /usr/bin. Those links are
# absolute as packaged, so every one of them dangles on a box with no omarchy
# package; they get repointed at $DIR/usr/bin after unpacking.
#
# Re-run to update: package versions are compared against the repo db and
# nothing is downloaded when they already match.
#
#   --dir PATH          where to unpack (default ~/.local/share/omarchy-shell).
#                       Never ~/.local/share/omarchy: install.sh --install-omarchy
#                       keeps its omarchy-mac git checkout there.
#   --replace-noctalia  do the one destructive step: remove noctalia-qs and
#                       install upstream quickshell. Without it, a box running
#                       Noctalia is reported and left alone.
#   --check             report what is and is not in place, change nothing.
#                       Exits non-zero if any part is missing.
#   --uninstall         remove the tree, the launcher and the Hyprland glue.
#
# On a machine with the real omarchy package this exits early: it is already there.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_error()  { echo -e "${RED}[✗]${NC} $1"; }
print_info()   { echo -e "${YELLOW}[i]${NC} $1"; }
print_phase()  { echo -e "\n${BOLD}== $1 ==${NC}"; }

PKG_BASE="https://pkgs.omarchy.org/edge"
PACKAGES=(omarchy omarchy-settings)
INSTALL_DIR="$HOME/.local/share/omarchy-shell"
LAUNCHER="$HOME/.local/bin/omarchy-shell-start"
HYPR_DIR="$HOME/.config/hypr"
HYPR_ENTRY="$HYPR_DIR/hyprland.lua"
HYPR_OMARCHY_DIR="$HYPR_DIR/omarchy"
HYPR_SNIPPET="$HYPR_OMARCHY_DIR/omarchy-shell.lua"
SNIPPET_REQUIRE_LINE='pcall(require, "hypr.omarchy.omarchy-shell")'
STAMP_NAME=".omarchy-shell-versions"

REPLACE_NOCTALIA=0
MODE=install

while [ $# -gt 0 ]; do
    case "$1" in
        --dir)
            [ $# -ge 2 ] || { print_error "--dir needs a path"; exit 1; }
            INSTALL_DIR="$2"; shift 2 ;;
        --replace-noctalia) REPLACE_NOCTALIA=1; shift ;;
        --check)     MODE=check; shift ;;
        --uninstall) MODE=uninstall; shift ;;
        --help|-h)
            # Print the whole leading comment block, so editing the header
            # above cannot silently truncate --help.
            awk 'NR>1 { if (/^#/) { sub(/^# ?/, ""); print } else { exit } }' "$0"
            exit 0 ;;
        *) print_error "Unknown argument: $1 (try --help)"; exit 1 ;;
    esac
done

OMARCHY_ROOT="$INSTALL_DIR/usr/share/omarchy"
STAMP="$INSTALL_DIR/$STAMP_NAME"

TMPDIR_SELF=""
# The explicit return matters: a trap's last command sets the script's exit
# status, and a bare [ -n "$unset" ] test would make every path that never
# downloaded anything -- --check, --uninstall, the early "already installed"
# exit -- report failure.
cleanup() {
    [ -n "$TMPDIR_SELF" ] && rm -rf "$TMPDIR_SELF"
    return 0
}
trap cleanup EXIT

# ---------------------------------------------------------------- preflight --

phase_preflight() {
    print_phase "Preflight"

    if [ ! -f /etc/arch-release ]; then
        print_error "This script requires Arch Linux (/etc/arch-release not found)"
        exit 1
    fi

    if [ "$EUID" -eq 0 ]; then
        print_error "Run this as your regular user, not root."
        exit 1
    fi

    local missing=() tool
    for tool in curl bsdtar sha256sum; do
        command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        print_error "Missing required tools: ${missing[*]}"
        print_error "  sudo pacman -S --needed curl libarchive coreutils"
        exit 1
    fi

    # The omarchy-mac checkout lives here and is a git repo, not a package tree.
    if [ "$INSTALL_DIR" = "$HOME/.local/share/omarchy" ]; then
        print_error "$INSTALL_DIR is where install.sh --install-omarchy keeps its"
        print_error "omarchy-mac checkout. Pick another --dir."
        exit 1
    fi

    if pacman -Qq omarchy >/dev/null 2>&1; then
        print_info "The omarchy package is installed ($(pacman -Q omarchy | awk '{print $2}'))."
        print_info "This box already has the shell at /usr/share/omarchy; nothing to do."
        exit 0
    fi

    print_status "Arch Linux, non-root, no omarchy package"
}

# --------------------------------------------------------------- quickshell --

# noctalia-qs declares both Provides: quickshell and Conflicts: quickshell, and
# is built against an older Qt. Leave it installed and the Omarchy shell dies at
# startup with a symbol lookup error -- silently, because Hyprland is fine and
# the desktop just comes up with no bar. The two cannot coexist.
phase_quickshell() {
    print_phase "Quickshell"

    if pacman -Qq noctalia-qs >/dev/null 2>&1; then
        if [ "$REPLACE_NOCTALIA" -ne 1 ]; then
            print_error "noctalia-qs is installed. It conflicts with quickshell and there is"
            print_error "no way to run both shells on one machine."
            print_error "Re-run with --replace-noctalia to swap it, or by hand:"
            print_error "  sudo pacman -Rdd noctalia-qs && sudo pacman -S quickshell"
            exit 1
        fi
        print_info "Removing noctalia-qs and installing upstream quickshell"
        sudo pacman -Rdd --noconfirm noctalia-qs
        sudo pacman -S --needed --noconfirm quickshell
    elif ! pacman -Qq quickshell >/dev/null 2>&1; then
        print_info "Installing quickshell"
        sudo pacman -S --needed --noconfirm quickshell
    fi

    if ! quickshell --version >/dev/null 2>&1; then
        print_error "quickshell is installed but will not run (likely a Qt mismatch):"
        quickshell --version 2>&1 | head -2
        exit 1
    fi

    print_status "quickshell OK ($(quickshell --version 2>/dev/null | head -1))"
}

# -------------------------------------------------------------------- fetch --

# Pulls FILENAME, VERSION and SHA256SUM for one package out of an extracted repo
# db. The directory glob is anchored on a digit so that asking for "omarchy" does
# not also match omarchy-settings or omarchy-keyring; %NAME% is checked anyway.
read_pkg_entry() {
    local dbdir="$1" want="$2" desc
    for desc in "$dbdir/$want"-[0-9]*/desc; do
        [ -f "$desc" ] || continue
        awk -v want="$want" '
            /^%NAME%$/      { getline v; name = v }
            /^%FILENAME%$/  { getline v; file = v }
            /^%VERSION%$/   { getline v; ver  = v }
            /^%SHA256SUM%$/ { getline v; sum  = v }
            END { if (name == want && file && ver && sum) print file "\t" ver "\t" sum }
        ' "$desc"
    done
}

# $OMARCHY_PATH/bin ships as absolute symlinks into /usr/bin, which is where the
# package puts the real programs. Nothing there exists on a box without the
# package, so aim them at the copy that was just unpacked. Relative, so moving
# the tree later does not break it again.
repoint_bin_symlinks() {
    local bindir="$1" entry target count=0
    for entry in "$bindir"/*; do
        [ -L "$entry" ] || continue
        target="$(readlink "$entry")"
        case "$target" in
            /usr/bin/*)
                ln -sfn "../../../bin/${target#/usr/bin/}" "$entry"
                count=$((count + 1)) ;;
        esac
    done
    printf '%s\n' "$count"
}

phase_fetch() {
    print_phase "Omarchy tree"

    local arch repo
    arch="$(uname -m)"
    repo="$PKG_BASE/$arch"
    TMPDIR_SELF="$(mktemp -d)"

    print_info "Reading $repo/omarchy.db"
    if ! curl -fsSL -o "$TMPDIR_SELF/omarchy.db" "$repo/omarchy.db"; then
        print_error "Could not fetch the package db for $arch from $repo"
        exit 1
    fi
    mkdir -p "$TMPDIR_SELF/db"
    bsdtar -xf "$TMPDIR_SELF/omarchy.db" -C "$TMPDIR_SELF/db"

    local pkg entry filenames=() versions=() shas=() stamp_lines=""
    for pkg in "${PACKAGES[@]}"; do
        entry="$(read_pkg_entry "$TMPDIR_SELF/db" "$pkg" | head -1)"
        if [ -z "$entry" ]; then
            print_error "No $pkg package in the $arch repo db."
            exit 1
        fi
        filenames+=("$(printf '%s' "$entry" | cut -f1)")
        versions+=("$(printf '%s' "$entry" | cut -f2)")
        shas+=("$(printf '%s' "$entry" | cut -f3)")
        stamp_lines+="$pkg $(printf '%s' "$entry" | cut -f2)"$'\n'
    done

    # Both sides through command substitution: it strips trailing newlines, and
    # $stamp_lines carries one that the file on disk does not read back with.
    if [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$(printf '%s' "$stamp_lines")" ]; then
        print_status "Already up to date ($(tr '\n' ' ' < "$STAMP"))"
        return 0
    fi

    # Unpack both packages over one staging prefix, so the result has the same
    # layout a real install has. Only usr/bin and usr/share/omarchy: the /etc
    # payload is what makes a full Omarchy box, and is what we are not doing.
    local i stage="$TMPDIR_SELF/stage"
    mkdir -p "$stage"
    for i in "${!PACKAGES[@]}"; do
        print_info "Downloading ${PACKAGES[$i]} ${versions[$i]}"
        if ! curl -fL --progress-bar -o "$TMPDIR_SELF/${filenames[$i]}" "$repo/${filenames[$i]}"; then
            print_error "Download failed: $repo/${filenames[$i]}"
            exit 1
        fi
        if ! printf '%s  %s\n' "${shas[$i]}" "$TMPDIR_SELF/${filenames[$i]}" | sha256sum -c --status -; then
            print_error "Checksum mismatch on ${filenames[$i]}; refusing to unpack it."
            exit 1
        fi
        # Neither package carries both paths, so a missing one is not an error.
        bsdtar -xf "$TMPDIR_SELF/${filenames[$i]}" -C "$stage" usr/bin usr/share/omarchy 2>/dev/null || true
    done
    print_status "Checksums verified"

    if [ ! -d "$stage/usr/share/omarchy/shell" ] || [ ! -d "$stage/usr/bin" ]; then
        print_error "The unpacked tree has no shell/ or no usr/bin; aborting."
        exit 1
    fi
    if [ ! -d "$stage/usr/share/omarchy/default" ]; then
        print_error "The unpacked tree has no default/; omarchy-settings did not unpack."
        exit 1
    fi

    local repointed
    repointed="$(repoint_bin_symlinks "$stage/usr/share/omarchy/bin")"
    print_status "Repointed $repointed helper symlinks into the tree"

    printf '%s' "$stamp_lines" > "$stage/$STAMP_NAME"

    # Swap in place: a half-written tree is a shell that will not start.
    mkdir -p "$(dirname "$INSTALL_DIR")"
    rm -rf "$INSTALL_DIR.new" "$INSTALL_DIR.old"
    mv "$stage" "$INSTALL_DIR.new"
    [ -d "$INSTALL_DIR" ] && mv "$INSTALL_DIR" "$INSTALL_DIR.old"
    mv "$INSTALL_DIR.new" "$INSTALL_DIR"
    rm -rf "$INSTALL_DIR.old"

    print_status "Unpacked to $INSTALL_DIR"
}

# ----------------------------------------------------------------- launcher --

# The shell finds its helpers on PATH, so PATH has to be right for every process
# it spawns. Hyprland's `env =` lines take a literal value -- it does not expand
# $PATH -- so a wrapper is the honest way to prepend rather than clobber.
phase_launcher() {
    print_phase "Launcher"

    mkdir -p "$(dirname "$LAUNCHER")"
    cat > "$LAUNCHER" <<EOF
#!/bin/bash
# Generated by omarchy-shell.sh. Re-run that script rather than editing this.
export OMARCHY_PATH="$OMARCHY_ROOT"
export PATH="\$OMARCHY_PATH/bin:\$PATH"
exec omarchy-launch-shell
EOF
    chmod +x "$LAUNCHER"
    print_status "Wrote $LAUNCHER"
}

# ------------------------------------------------------------ hyprland glue --

phase_hyprland() {
    print_phase "Hyprland"

    mkdir -p "$HYPR_OMARCHY_DIR"
    cat > "$HYPR_SNIPPET" <<EOF
-- Generated by omarchy-shell.sh. Re-run that script rather than editing this.
-- The launcher sets OMARCHY_PATH and PATH before exec'ing omarchy-launch-shell,
-- which supervises Quickshell and logs it to the journal under omarchy-shell.
if hyprland and hyprland.exec_on_once then
    hyprland.exec_on_once("$LAUNCHER")
end
EOF
    print_status "Wrote $HYPR_SNIPPET"

    local autostart="$HYPR_OMARCHY_DIR/autostart.lua"
    if [ -f "$autostart" ]; then
        if grep -qF -- "$SNIPPET_REQUIRE_LINE" "$autostart"; then
            print_status "autostart.lua already requires the snippet"
        else
            printf '\n%s\n' "$SNIPPET_REQUIRE_LINE" >> "$autostart"
            print_status "Added the guarded require to autostart.lua"
        fi
    else
        print_info "No $autostart; add a Hyprland-0.56 exec-once for $LAUNCHER"
        print_info "from whatever config your compositor does load."
    fi
}

# -------------------------------------------------------------- conflicts --

# Everything the Omarchy shell now owns that the Noctalia stack also runs. These
# are one-line edits in tracked dotfiles, so report them rather than rewriting
# the user's config out from under git.
report_conflicts() {
    print_phase "Still to do by hand"

    local autostart="$HYPR_DIR/config/autostart.lua"
    if [ -f "$autostart" ]; then
        if grep -q 'noctalia-shell.service' "$autostart"; then
            print_info "Remove the noctalia-shell.service exec in $autostart"
        fi
        if grep -q 'hypridle-power.sh' "$autostart"; then
            print_info "Remove hypridle-power.sh in $autostart -- the shell's idle"
            print_info "  plugin watches Wayland idle itself and calls omarchy-system-lock,"
            print_info "  so two idle managers would race to lock the screen. Timings move"
            print_info "  to omarchy/shell.json (idle.screensaver, idle.lock)."
        fi
        if grep -qE 'polkit-gnome|cliphist' "$autostart"; then
            print_info "polkit-gnome and cliphist are redundant now; the shell ships both."
        fi
    fi

    print_info "Nothing binds the menu yet. In hypr/omarchy/bindings.lua:"
    print_info "  o.bind(\"SUPER + SPACE\", \"Omarchy menu\", \"omarchy-menu toggle\")"
    print_info "For omarchy-* commands in an interactive shell, add to zsh/.zshrc:"
    print_info "  export OMARCHY_PATH=$OMARCHY_ROOT"
    print_info "  export PATH=\$OMARCHY_PATH/bin:\$PATH"

    echo
    print_info "'omarchy theme set' is safe here. It renders into"
    print_info "  ~/.local/state/omarchy/current/theme/ and your tracked terminal"
    print_info "  configs include that directory, so it never overwrites anything in"
    print_info "  this repo. The shell falls back to its built-in palette when no"
    print_info "  theme is set, so it works fine untheme'd."
}

# --------------------------------------------------------------------- check --

# Exits non-zero if anything is missing, so it can gate a script.
do_check() {
    print_phase "Status"
    local ok=0

    if pacman -Qq omarchy >/dev/null 2>&1; then
        print_status "omarchy package installed; the shell lives at /usr/share/omarchy"
        return 0
    fi

    if [ -d "$OMARCHY_ROOT/shell" ]; then
        print_status "Tree at $INSTALL_DIR ($(tr '\n' ' ' < "$STAMP" 2>/dev/null || echo 'version unknown'))"
        local dangling
        dangling="$(find "$OMARCHY_ROOT/bin" -xtype l 2>/dev/null | wc -l)"
        if [ "$dangling" -eq 0 ]; then
            print_status "Helper symlinks resolve"
        else
            print_error "$dangling helper symlinks dangle; re-run to repair"; ok=1
        fi
        if [ -d "$OMARCHY_ROOT/default" ]; then
            print_status "default/ present (omarchy-settings)"
        else
            print_error "No default/; omarchy-settings is missing"; ok=1
        fi
    else
        print_error "No shell tree at $INSTALL_DIR"; ok=1
    fi

    if [ -x "$LAUNCHER" ]; then
        print_status "Launcher at $LAUNCHER"
    else
        print_error "No launcher at $LAUNCHER"; ok=1
    fi

    if [ -f "$HYPR_ENTRY" ]; then
        if grep -qF -- "$SNIPPET_REQUIRE_LINE" "$HYPR_OMARCHY_DIR/autostart.lua" 2>/dev/null; then
            print_status "autostart.lua requires the snippet"
        else
            print_error "autostart.lua does not require $HYPR_SNIPPET"; ok=1
        fi
    else
        print_info "No Lua entry point at $HYPR_ENTRY; Hyprland wiring not checked"
    fi

    if pacman -Qq noctalia-qs >/dev/null 2>&1; then
        print_error "noctalia-qs is installed; the Omarchy shell cannot run alongside it"; ok=1
    elif quickshell --version >/dev/null 2>&1; then
        print_status "quickshell OK ($(quickshell --version 2>/dev/null | head -1))"
    else
        print_error "quickshell is missing or will not run"; ok=1
    fi

    return "$ok"
}

# ----------------------------------------------------------------- uninstall --

do_uninstall() {
    print_phase "Uninstall"

    rm -rf "$INSTALL_DIR" "$INSTALL_DIR.new" "$INSTALL_DIR.old"
    print_status "Removed $INSTALL_DIR"

    rm -f "$LAUNCHER" "$HYPR_SNIPPET"
    print_status "Removed the launcher and the Hyprland snippet"

    local autostart="$HYPR_OMARCHY_DIR/autostart.lua"
    if [ -f "$autostart" ] && grep -qF -- "$SNIPPET_REQUIRE_LINE" "$autostart"; then
        local tmp
        tmp="$(mktemp)"
        grep -vF -- "$SNIPPET_REQUIRE_LINE" "$autostart" > "$tmp"
        cat "$tmp" > "$autostart"
        rm -f "$tmp"
        print_status "Dropped the require from autostart.lua"
    fi

    print_info "quickshell was left installed. To go back to Noctalia:"
    print_info "  sudo pacman -Rdd quickshell && paru -S noctalia-qs"
    print_info "and re-enable the exec-once lines in hypr/config/autostart.lua"
    print_info "(or the Lua equivalent in your dotfiles)."
}

# ---------------------------------------------------------------------- main --

case "$MODE" in
    check)     do_check ;;
    uninstall) do_uninstall ;;
    install)
        phase_preflight
        phase_quickshell
        phase_fetch
        phase_launcher
        phase_hyprland
        report_conflicts
        echo
        print_status "Done. Log out and back in, or run: $LAUNCHER"
        ;;
esac
