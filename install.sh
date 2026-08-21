#!/usr/bin/env bash

set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
projtool_path="$script_dir/projtool.sh"
shell_name="$(basename -- "${SHELL:-}")"

case "$shell_name" in
    zsh)
        rc_file="${ZDOTDIR:-$HOME}/.zshrc"
        ;;
    bash)
        if [[ "$(uname -s)" == "Darwin" ]]; then
            rc_file="$HOME/.bash_profile"
        else
            rc_file="$HOME/.bashrc"
        fi
        ;;
    *)
        printf 'Unsupported shell: %s. Use zsh or bash.\n' "${SHELL:-unknown}" >&2
        exit 1
        ;;
esac

[[ -x "$projtool_path" ]] || {
    printf 'projtool.sh is missing or not executable: %s\n' "$projtool_path" >&2
    exit 1
}

printf -v escaped_path '%q' "$projtool_path"
alias_line="alias projtool=$escaped_path"
state_dir="${XDG_CONFIG_HOME:-$HOME/.config}/projtool"
state_file="$state_dir/install"

mkdir -p -- "$(dirname -- "$rc_file")" "$state_dir"
touch -- "$rc_file"

if [[ -f "$state_file" ]]; then
    {
        IFS= read -r installed_rc || true
        IFS= read -r installed_alias || true
    } < "$state_file"

    if [[ "$installed_rc" == "$rc_file" && "$installed_alias" == "$alias_line" ]] &&
        grep -Fqx -- "$alias_line" "$rc_file"; then
        printf 'projtool is already installed.\n'
        exit 0
    fi

    printf 'A different projtool installation exists. Run its uninstall.sh first.\n' >&2
    exit 1
fi

if grep -Eq '^[[:space:]]*alias[[:space:]]+projtool=' "$rc_file"; then
    printf 'An existing projtool alias is already defined in %s.\n' "$rc_file" >&2
    exit 1
fi

if [[ -s "$rc_file" ]]; then
    printf '\n' >> "$rc_file"
fi
printf '%s\n' "$alias_line" >> "$rc_file"
printf '%s\n%s\n' "$rc_file" "$alias_line" > "$state_file"

printf 'Installed projtool in %s.\n' "$rc_file"
printf 'Open a new terminal or run: source %q\n' "$rc_file"
