#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/projtool"
COMPONENT="${1:-all}"
PYTHON=""
CONDA=""
PROVIDER=""
export PYTHONDONTWRITEBYTECODE=1
unset PYTHONHOME PYTHONPATH

case "$COMPONENT" in
    -h|--help) printf '%s\n' 'Usage: bash install/mac/install.sh [all|python|julia]'; exit 0 ;;
    all|python|julia) ;;
    *) printf 'Unknown component: %s\n' "$COMPONENT" >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { printf '%s\n' 'Too many arguments.' >&2; exit 2; }
[[ "$(uname -s)" == Darwin ]] || { printf '%s\n' 'Use this installer on macOS.' >&2; exit 1; }

ask() {
    printf '%s ' "$1"
    IFS= read -r ANSWER || { printf '\nSetup cancelled.\n' >&2; exit 130; }
}

find_standard() {
    local candidate version
    PYTHON="$(
        for candidate in /Library/Frameworks/Python.framework/Versions/3.*/bin/python3; do
            [[ -x "$candidate" ]] || continue
            if version="$("$candidate" -I -c 'import sys; assert sys.version_info >= (3,10); print(".".join(map(str,sys.version_info[:3])))' 2>/dev/null)"; then
                printf '%s %s\n' "$version" "$candidate"
            fi
        done | sort -t. -k1,1nr -k2,2nr -k3,3nr | head -n 1 | cut -d' ' -f2-
    )"
    [[ -n "$PYTHON" ]]
}

install_standard() {
    local index version listing package temporary signature
    index="$(curl -fsSL https://www.python.org/ftp/python/)"
    package=""
    for version in $(printf '%s' "$index" | sed -nE 's/.*href="(3\.[0-9]+\.[0-9]+)\/".*/\1/p' | sort -t. -k1,1nr -k2,2nr -k3,3nr); do
        listing="$(curl -fsSL "https://www.python.org/ftp/python/$version/")"
        package="$(printf '%s' "$listing" | sed -nE "s/.*href=\"(python-${version//./\.}-macos[^\"]*\.pkg)\".*/\1/p" | head -n 1)"
        [[ -z "$package" ]] || break
    done
    [[ -n "$package" ]] || { printf '%s\n' 'Could not find a stable macOS Python installer on python.org.' >&2; return 1; }
    temporary="$(mktemp -d -t projtool-python)"
    printf 'Downloading Python %s from python.org. macOS will require administrator permission.\n' "$version"
    curl -fSL "https://www.python.org/ftp/python/$version/$package" -o "$temporary/python.pkg"
    signature="$(pkgutil --check-signature "$temporary/python.pkg")"
    [[ "$signature" == *"Python Software Foundation"* ]] || { printf '%s\n' 'The Python installer signature did not match the Python Software Foundation.' >&2; return 1; }
    sudo /usr/sbin/installer -pkg "$temporary/python.pkg" -target /
    rm -f -- "$temporary/python.pkg"
    rmdir -- "$temporary"
    find_standard || { printf '%s\n' 'Python was installed but its framework could not be located.' >&2; return 1; }
    local minor certificates
    minor="$("$PYTHON" -I -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
    certificates="/Applications/Python $minor/Install Certificates.command"
    [[ ! -f "$certificates" ]] || bash "$certificates"
}

if [[ "$COMPONENT" != julia ]]; then
    while :; do
        ask 'What Python install would you like to use? The options are conda, homebrew, or standard, where standard means you have installed Python from python.org, which can be done here for you if desired.'
        PROVIDER="$(printf '%s' "$ANSWER" | tr '[:upper:]' '[:lower:]')"
        case "$PROVIDER" in
            conda)
                CONDA="${CONDA_EXE:-}"
                if [[ ! -x "$CONDA" ]]; then CONDA="$(command -v conda || true)"; fi
                if [[ ! -x "$CONDA" ]]; then
                    for candidate in "$HOME/miniconda3/bin/conda" "$HOME/anaconda3/bin/conda" "$HOME/miniforge3/bin/conda" /opt/anaconda3/bin/conda /opt/miniconda3/bin/conda; do
                        if [[ -x "$candidate" ]]; then CONDA="$candidate"; break; fi
                    done
                fi
                if [[ ! -x "$CONDA" ]]; then printf '%s\n' 'Conda was not found on this machine.'; continue; fi
                PYTHON="$("$CONDA" info --base)/bin/python"
                [[ -x "$PYTHON" ]] || { printf '%s\n' 'The Conda base Python is missing.'; continue; }
                break
                ;;
            homebrew)
                BREW="$(command -v brew || true)"
                if [[ ! -x "$BREW" ]]; then
                    for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
                        if [[ -x "$candidate" ]]; then BREW="$candidate"; break; fi
                    done
                fi
                if [[ ! -x "$BREW" ]]; then printf '%s\n' 'Homebrew was not found on this machine.'; continue; fi
                PYTHON="$("$BREW" --prefix)/bin/python3"
                if [[ ! -x "$PYTHON" ]]; then
                    BREW_PREFIX="$("$BREW" --prefix)"
                    for candidate in "$BREW_PREFIX"/opt/python@*/bin/python3 "$BREW_PREFIX"/opt/python@*/bin/python3.[0-9]*; do
                        [[ "$(basename -- "$candidate")" =~ ^python3(\.[0-9]+)?$ && -x "$candidate" ]] || continue
                        if "$candidate" -I -c 'import sys; assert sys.version_info >= (3,10)' 2>/dev/null; then PYTHON="$candidate"; fi
                    done
                fi
                if [[ ! -x "$PYTHON" ]]; then
                    while :; do
                        ask 'Homebrew has no linked Python 3. Install Python with Homebrew? [yes/no]'
                        case "$ANSWER" in
                            yes|y) "$BREW" install python; break ;;
                            no|n) break ;;
                            *) printf '%s\n' 'Choose yes or no.' ;;
                        esac
                    done
                    [[ -x "$PYTHON" ]] || continue
                fi
                break
                ;;
            standard)
                if ! find_standard; then
                    while :; do
                        ask 'A standard Python 3.10+ installation was not found. Install the newest stable Python from python.org? [yes/no]'
                        case "$ANSWER" in
                            yes|y) install_standard; break ;;
                            no|n) break ;;
                            *) printf '%s\n' 'Choose yes or no.' ;;
                        esac
                    done
                    [[ -n "$PYTHON" ]] || continue
                fi
                break
                ;;
            *) printf '%s\n' 'Choose conda, homebrew, or standard.' ;;
        esac
    done
    exec "$PYTHON" "$ROOT/source/configure.py" --component "$COMPONENT" --provider "$PROVIDER" --python "$PYTHON" --conda "$CONDA"
fi

if [[ -f "$CONFIG/python-executable" ]]; then IFS= read -r PYTHON < "$CONFIG/python-executable"; fi
if [[ ! -x "$PYTHON" ]]; then find_standard || PYTHON=/usr/bin/python3; fi
[[ -x "$PYTHON" ]] || { printf '%s\n' 'Run projtool update python first to configure Python.' >&2; exit 1; }
exec "$PYTHON" "$ROOT/source/configure.py" --component julia
