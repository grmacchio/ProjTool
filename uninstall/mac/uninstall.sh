#!/usr/bin/env bash

set -Eeuo pipefail

state_dir="${XDG_CONFIG_HOME:-$HOME/.config}/projtool"
projtool_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
if [[ -f "$state_dir/install.json" ]]; then
    exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$projtool_dir/uninstall/windows/uninstall.ps1")"
fi

remove_line() {
    local temporary_file
    [[ -f "$1" ]] || return 0
    temporary_file="$(mktemp "${TMPDIR:-/tmp}/projtool-uninstall.XXXXXX")"
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" == "$2" ]] || printf '%s\n' "$line"
    done < "$1" > "$temporary_file"
    cat "$temporary_file" > "$1"
    rm -- "$temporary_file"
}

if [[ -f "$state_dir/install-v2" ]]; then
    {
        IFS= read -r launcher || true
        IFS= read -r profile_line || true
    } < "$state_dir/install-v2"
    if [[ -e "$launcher" ]]; then
        grep -Fqx 'PROJTOOL_LAUNCHER=1' "$launcher" || {
            printf 'Refusing to remove an unrelated file: %s\n' "$launcher" >&2
            exit 1
        }
        rm -- "$launcher"
    fi
    while IFS= read -r profile; do
        remove_line "$profile" "$profile_line"
    done < "$state_dir/profiles"
    rm -- "$state_dir/install-v2" "$state_dir/path" "$state_dir/profiles"
elif [[ -f "$state_dir/install" ]]; then
    {
        IFS= read -r profile || true
        IFS= read -r alias_line || true
    } < "$state_dir/install"
    remove_line "$profile" "$alias_line"
    rm -- "$state_dir/install"
else
    printf 'projtool is not installed.\n'
    exit 0
fi
if [[ -f "$state_dir/python-environment" ]]; then
    IFS= read -r python_environment < "$state_dir/python-environment"
    if [[ -e "$python_environment" ]]; then
        [[ "$python_environment" == "${XDG_DATA_HOME:-$HOME/.local/share}/projtool/python" && -f "$python_environment/.projtool-owned" ]] || {
            printf 'Refusing to remove an unmanaged Python environment.\n' >&2
            exit 1
        }
        rm -rf -- "$python_environment"
    fi
    rm -- "$state_dir/python-environment"
fi
rmdir -- "$state_dir" 2>/dev/null || true
printf 'Uninstalled projtool. The managed Python environment was removed. Shared runtimes and packages are retained. Restart terminals and VS Code.\n'
