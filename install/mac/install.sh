#!/usr/bin/env bash

set -Eeuo pipefail

projtool_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$projtool_dir/install/windows/install.ps1")"
        ;;
    Darwin|Linux) ;;
    *) printf 'Unsupported operating system: %s\n' "$(uname -s)" >&2; exit 1 ;;
esac

state_dir="${XDG_CONFIG_HOME:-$HOME/.config}/projtool"
bin_dir="$HOME/.local/bin"
temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/projtool-install.XXXXXX")"
trap 'rm -rf -- "$temporary_dir"' EXIT

find_python() {
    local candidate
    while IFS= read -r candidate; do
        if "$candidate" -c 'import sys, venv, ensurepip; sys.exit(sys.version_info < (3, 10))' >/dev/null 2>&1; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done < <(type -a -p python3 python 2>/dev/null || true)
    return 1
}

fail() { printf '%s\n' "$*" >&2; exit 1; }

add_path() {
    [[ -d "$1" ]] || return 0
    case ":$PATH:" in *":$1:"*) ;; *) export PATH="$1:$PATH" ;; esac
}

run_privileged() {
    if [[ "$(id -u)" == 0 ]]; then "$@"; else sudo "$@"; fi
}

download() {
    curl -fL --retry 3 --connect-timeout 20 "$1" -o "$2"
}

release_asset() {
    local url
    url="$(curl -fsSL --retry 3 "https://api.github.com/repos/$1/releases/latest" |
        grep -oE '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]+"' |
        sed -E 's/^[^:]+:[[:space:]]*"(.*)"$/\1/' | grep -E "$2")" ||
        fail "Cannot identify the $1 download for this computer."
    [[ "$url" != *$'\n'* ]] || fail "Ambiguous download for $1."
    download "$url" "$3"
}

for directory in /opt/homebrew/bin /usr/local/bin /Library/TeX/texbin \
    "$HOME/.juliaup/bin" "$HOME/Library/TinyTeX/bin/universal-darwin" "$HOME/.TinyTeX/bin/$(uname -m)-linux"; do
    add_path "$directory"
done

if [[ "$(uname -s)" == Darwin ]]; then
    if ! command -v brew >/dev/null 2>&1; then
        download https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh "$temporary_dir/homebrew.sh"
        /bin/bash "$temporary_dir/homebrew.sh"
        add_path /opt/homebrew/bin
        add_path /usr/local/bin
    fi
    brew update
    for formula in git pandoc python; do
        if brew list --versions "$formula" >/dev/null 2>&1; then
            brew upgrade "$formula"
        else
            brew install "$formula"
        fi
    done
    export PATH="$(brew --prefix python)/libexec/bin:$(brew --prefix python)/bin:$(brew --prefix git)/bin:$(brew --prefix pandoc)/bin:$PATH"
else
    if command -v apt-get >/dev/null 2>&1; then
        run_privileged apt-get update
        run_privileged apt-get install -y git pandoc perl curl xz-utils python3 python3-venv
    elif command -v dnf >/dev/null 2>&1; then
        run_privileged dnf upgrade -y git pandoc python3
        run_privileged dnf install -y git pandoc perl curl xz python3 python3-pip
    elif command -v pacman >/dev/null 2>&1; then
        run_privileged pacman -Syu --needed --noconfirm git pandoc perl curl xz python python-pip
    else
        fail 'Automatic dependency installation requires apt-get, dnf, or pacman on Linux.'
    fi
fi

python_command="$(find_python)" || fail 'Python 3.10 or later with venv is required.'
tex_year="$(curl -fsSL --retry 3 https://api.github.com/repos/rstudio/tinytex-releases/releases/latest |
    "$python_command" -c 'import json,re,sys; print(re.search(r"\d{4}",json.load(sys.stdin)["tag_name"])[0])')"
if [[ "$(uname -s)" == Darwin ]]; then
    tinytex_dir="$HOME/Library/TinyTeX"
    archive_pattern='/TinyTeX-1-darwin-v[0-9.]+\.tar\.xz$'
else
    tinytex_dir="$HOME/.TinyTeX"
    case "$(uname -m)" in
        x86_64) tex_arch=x86_64 ;;
        aarch64|arm64) tex_arch=arm64 ;;
        *) fail "Unsupported TinyTeX architecture: $(uname -m)" ;;
    esac
    archive_pattern="/TinyTeX-1-linux-$tex_arch-v[0-9.]+\\.tar\\.xz$"
fi
tex_current=false
for executable in "$tinytex_dir"/bin/*/pdflatex; do
    if [[ -x "$executable" ]] && "$executable" --version | grep -Fq "TeX Live $tex_year"; then
        tex_current=true
    fi
done
if [[ "$tex_current" == false && -e "$tinytex_dir" ]]; then
    tinytex_dir="${tinytex_dir}-${tex_year}"
fi
tex_current=false
for executable in "$tinytex_dir"/bin/*/pdflatex; do
    if [[ -x "$executable" ]] && "$executable" --version | grep -Fq "TeX Live $tex_year"; then
        tex_current=true
    fi
done
if [[ "$tex_current" == false ]]; then
    [[ ! -e "$tinytex_dir" ]] || fail "An incomplete TinyTeX installation already exists: $tinytex_dir"
    release_asset rstudio/tinytex-releases "$archive_pattern" "$temporary_dir/tinytex.tar.xz"
    mkdir "$temporary_dir/tex"
    tar -xf "$temporary_dir/tinytex.tar.xz" -C "$temporary_dir/tex"
    for directory in "$temporary_dir/tex/TinyTeX" "$temporary_dir/tex/.TinyTeX"; do
        if [[ -d "$directory" ]]; then
            mkdir -p -- "$(dirname -- "$tinytex_dir")"
            mv -- "$directory" "$tinytex_dir"
            break
        fi
    done
fi
for directory in "$tinytex_dir"/bin/*; do
    [[ -d "$directory" ]] && export PATH="$directory:$PATH"
done
command -v pdflatex >/dev/null 2>&1 || fail 'TinyTeX installation could not be verified.'
tlmgr option repository https://ctan.math.illinois.edu/systems/texlive/tlnet
tlmgr update --self --all

required_packages=()
while IFS='|' read -r package probe; do
    required_packages+=("$package")
done < "$projtool_dir/source/tex-packages.txt"
tlmgr install "${required_packages[@]}"

required_julia_version="$(curl -fsSL --retry 3 https://julialang-s3.julialang.org/bin/versions.json |
    "$python_command" -c 'import json,re,sys; r=json.load(sys.stdin); print(max((v for v,d in r.items() if d.get("stable") and re.fullmatch(r"\d+\.\d+\.\d+",v)),key=lambda v:tuple(map(int,v.split(".")))))')"
if ! command -v juliaup >/dev/null 2>&1; then
    download https://install.julialang.org "$temporary_dir/juliaup.sh"
    sh "$temporary_dir/juliaup.sh" --yes --add-to-path=yes --default-channel="$required_julia_version"
    add_path "$HOME/.juliaup/bin"
fi
juliaup add "$required_julia_version"
juliaup default "$required_julia_version"
julia_default_bin="$(dirname -- "$(command -v juliaup)")"
julia_command="$("$julia_default_bin/julia" "+$required_julia_version" --startup-file=no -e 'print(Sys.BINDIR)')/julia"
[[ "$("$julia_command" --startup-file=no -e 'print(VERSION)')" == "$required_julia_version" ]] || fail 'Julia version verification failed.'
export PATH="$julia_default_bin:$PATH"
printf 'Default Julia is %s.\n' "$required_julia_version"
python_environment="${XDG_DATA_HOME:-$HOME/.local/share}/projtool/python"
"$python_command" "$projtool_dir/source/install_python.py" "$python_environment" "$projtool_dir/source/python-requirements.txt"
julia_projects=()
for kind in dissertation note preprint presentation; do
    julia_projects+=("$projtool_dir/examples/$kind/code/julia")
done
"$julia_command" --startup-file=no "$projtool_dir/source/prepare_julia.jl" "${julia_projects[@]}"

for command_name in git pandoc pdflatex latexmk bibtexu julia; do
    "$command_name" --version > "$temporary_dir/version"
    sed -n '1p' "$temporary_dir/version"
done
while IFS='|' read -r package probe; do
    [[ "$probe" == @* ]] || kpsewhich "$probe" >/dev/null || fail "LaTeX package verification failed: $package"
done < "$projtool_dir/source/tex-packages.txt"

mkdir -p -- "$bin_dir" "$state_dir"
launcher="$bin_dir/projtool"
if [[ -e "$launcher" || -L "$launcher" ]]; then
    grep -Fqx 'PROJTOOL_LAUNCHER=1' "$launcher" || fail "Refusing to replace an unrelated launcher: $launcher"
fi

dependency_path="$python_environment/bin:$bin_dir"
for command_name in git pandoc pdflatex latexmk bibtexu julia; do
    directory="$(dirname -- "$(command -v "$command_name")")"
    case ":$dependency_path:" in *":$directory:"*) ;; *) dependency_path="$dependency_path:$directory" ;; esac
done
{
    printf '#!/bin/bash\nPROJTOOL_LAUNCHER=1\nexport PATH=%q:"$PATH"\n' "$dependency_path"
    printf 'export JUPYTER_PATH=%q\n' "$python_environment/share/jupyter"
    printf 'exec /bin/bash %q "$@"\n' "$projtool_dir/source/projtool.sh"
} > "$temporary_dir/projtool"
chmod 755 "$temporary_dir/projtool"
mv -- "$temporary_dir/projtool" "$launcher"

if [[ -f "$state_dir/install" ]]; then
    {
        IFS= read -r old_profile || true
        IFS= read -r old_alias || true
    } < "$state_dir/install"
    [[ "$old_alias" == 'alias projtool='* ]] || fail 'Unrecognized previous ProjTool installation record.'
    if [[ -f "$old_profile" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ "$line" == "$old_alias" ]] || printf '%s\n' "$line"
        done < "$old_profile" > "$temporary_dir/profile"
        cat "$temporary_dir/profile" > "$old_profile"
    fi
    rm -- "$state_dir/install"
fi

dependency_state="${XDG_CONFIG_HOME:-$HOME/.config}/projtool-dependencies"
mkdir -p -- "$dependency_state"
global_python_path="$(dirname -- "$python_command")"
if [[ "$(uname -s)" == Darwin ]]; then
    global_python_path="$(brew --prefix python)/libexec/bin:$global_python_path"
fi
global_dependency_path="$python_environment/bin:$global_python_path:$julia_default_bin"
for command_name in git pandoc pdflatex latexmk bibtexu; do
    directory="$(dirname -- "$(command -v "$command_name")")"
    case ":$global_dependency_path:" in *":$directory:"*) ;; *) global_dependency_path="$global_dependency_path:$directory" ;; esac
done
printf 'case "$PATH:" in %q*) ;; *) export PATH=%q:"$PATH" ;; esac\n' "$global_dependency_path:" "$global_dependency_path" > "$dependency_state/path"
printf -v dependency_profile_line '[ ! -f %q ] || . %q' "$dependency_state/path" "$dependency_state/path"

printf 'case ":$PATH:" in *:%q:*) ;; *) export PATH=%q:"$PATH" ;; esac\n' "$bin_dir" "$bin_dir" > "$state_dir/path"
printf -v profile_line '[ ! -f %q ] || . %q' "$state_dir/path" "$state_dir/path"
printf '%s\n' "$launcher" "$profile_line" > "$state_dir/install-v2"
printf '%s\n' "$python_environment" > "$state_dir/python-environment"
touch "$state_dir/profiles"
profiles=("$HOME/.profile")
case "$(basename -- "${SHELL:-bash}")" in
    zsh) profiles+=("${ZDOTDIR:-$HOME}/.zprofile" "${ZDOTDIR:-$HOME}/.zshrc") ;;
    bash) profiles+=("$HOME/.bash_profile" "$HOME/.bashrc") ;;
    *) fail 'ProjTool currently supports bash and zsh shell setup.' ;;
esac
for profile in "$HOME/.bash_profile" "$HOME/.bashrc" "${ZDOTDIR:-$HOME}/.zprofile" "${ZDOTDIR:-$HOME}/.zshrc"; do
    [[ ! -f "$profile" ]] || profiles+=("$profile")
done
for profile in "${profiles[@]}"; do
    mkdir -p -- "$(dirname -- "$profile")"
    touch "$profile"
    if ! grep -Fqx -- "$dependency_profile_line" "$profile"; then
        printf '\n%s\n' "$dependency_profile_line" >> "$profile"
    fi
    if ! grep -Fqx -- "$profile_line" "$profile"; then
        printf '\n%s\n' "$profile_line" >> "$profile"
        printf '%s\n' "$profile" >> "$state_dir/profiles"
    fi
done
"$launcher" --help >/dev/null
printf 'Installed projtool and its dependencies. Open a new terminal and fully restart VS Code.\n'
