#!/usr/bin/env bash

set -Eeuo pipefail

state_dir="${XDG_CONFIG_HOME:-$HOME/.config}/projtool"
state_file="$state_dir/install"

if [[ ! -f "$state_file" ]]; then
    printf 'projtool is not installed.\n'
    exit 0
fi

{
    IFS= read -r rc_file || true
    IFS= read -r alias_line || true
} < "$state_file"

if [[ -f "$rc_file" ]]; then
    permissions="$(stat -f '%Lp' "$rc_file" 2>/dev/null || stat -c '%a' "$rc_file")"
    temporary_file="$(mktemp "${rc_file}.tmp.XXXXXX")"

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" == "$alias_line" ]] || printf '%s\n' "$line"
    done < "$rc_file" > "$temporary_file"

    chmod "$permissions" "$temporary_file"
    mv -f -- "$temporary_file" "$rc_file"
fi

rm -f -- "$state_file"
rmdir -- "$state_dir" 2>/dev/null || true

printf 'Uninstalled projtool. Open a new terminal or run: unalias projtool\n'
