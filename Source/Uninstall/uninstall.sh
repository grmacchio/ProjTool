#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/projtool"
[[ "$ROOT" != / && "$ROOT" != "$HOME" && -f "$ROOT/Source/Commands/projtool" && -f "$ROOT/Source/Install/install.sh" ]] || { printf '%s\n' 'Could not identify the ProjTool repository safely.' >&2; exit 1; }
if [[ -f "$CONFIG/root" ]]; then
    IFS= read -r REGISTERED < "$CONFIG/root"
    [[ "$REGISTERED" == "$ROOT" ]] || { printf 'A different ProjTool directory is registered: %s\n' "$REGISTERED" >&2; exit 1; }
fi
printf 'This will permanently delete %s and everything inside it, including uncommitted files.\n' "$ROOT"
printf '%s ' 'Type DELETE to uninstall ProjTool:'
IFS= read -r ANSWER
[[ "$ANSWER" == DELETE ]] || { printf '%s\n' 'Uninstall cancelled.'; exit 0; }

if [[ -f "$CONFIG/path-line" && -f "$CONFIG/profiles" ]]; then
    IFS= read -r PATH_LINE < "$CONFIG/path-line"
    while IFS= read -r PROFILE; do
        [[ -f "$PROFILE" ]] || continue
        TEMPORARY="$(mktemp -t projtool-profile)"
        PROJTOOL_PATH_LINE="$PATH_LINE" awk '$0 != ENVIRON["PROJTOOL_PATH_LINE"]' "$PROFILE" > "$TEMPORARY"
        cat "$TEMPORARY" > "$PROFILE"
        rm -f -- "$TEMPORARY"
    done < "$CONFIG/profiles"
fi
cd -- "$HOME"
rm -rf -- "$ROOT"
if [[ -f "$CONFIG/root" ]]; then rm -rf -- "$CONFIG"; fi
printf '%s\n' 'The ProjTool directory is deleted and the projtool command is no longer in PATH.' 'The dependencies are not deleted so as not to interfere with unrelated code on your machine.' 'Open a new terminal and restart VS Code to refresh PATH.'
