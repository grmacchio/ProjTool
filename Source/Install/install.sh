#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/projtool"
COMPONENT="${1:-all}"
PYTHON=""
CONDA=""
PROVIDER=""
BREW=""
BREW_UPDATED=false
export PYTHONDONTWRITEBYTECODE=1
unset PYTHONHOME PYTHONPATH

case "$COMPONENT" in
    -h|--help) printf '%s\n' 'Usage: bash Source/Install/install.sh [all|python|julia]'; exit 0 ;;
    all|python|julia) ;;
    *) printf 'Unknown component: %s\n' "$COMPONENT" >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { printf '%s\n' 'Too many arguments.' >&2; exit 2; }
[[ "$(uname -s)" == Darwin ]] || { printf '%s\n' 'Use this installer on macOS.' >&2; exit 1; }

ask() {
    printf '%s ' "$1"
    IFS= read -r ANSWER || { printf '\nSetup cancelled.\n' >&2; exit 130; }
}

confirm() {
    while :; do
        ask "$1 [yes/no]"
        case "$ANSWER" in
            yes|y|YES|Y) return 0 ;;
            no|n|NO|N) return 1 ;;
            *) printf '%s\n' 'Choose yes or no.' ;;
        esac
    done
}

find_brew() {
    local candidate found
    found="$(command -v brew || true)"
    if [[ ! -x "$found" ]]; then
        for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
            if [[ -x "$candidate" ]]; then found="$candidate"; break; fi
        done
    fi
    [[ -x "$found" ]] || return 1
    printf '%s\n' "$found"
}

ensure_brew() {
    local temporary
    BREW="$(find_brew || true)"
    if [[ ! -x "$BREW" ]]; then
        confirm 'Homebrew is required for current stable Git and the Homebrew Python option. Download and install Homebrew?' || {
            printf '%s\n' 'Installation denied because Homebrew is required.' >&2
            exit 1
        }
        temporary="$(mktemp -d -t projtool-homebrew)"
        curl -fSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$temporary/install.sh"
        /bin/bash "$temporary/install.sh"
        rm -rf -- "$temporary"
        BREW="$(find_brew || true)"
        [[ -x "$BREW" ]] || { printf '%s\n' 'Homebrew installation failed.' >&2; exit 1; }
    fi
    if [[ "$BREW_UPDATED" != true ]]; then
        "$BREW" update
        BREW_UPDATED=true
    fi
}

ensure_git() {
    local installed prefix
    if command -v git >/dev/null 2>&1; then
        printf '%s\n' 'Checking Git and updating to the stable Homebrew release.'
    else
        printf '%s\n' 'Git was not found. Homebrew is required to install it on macOS.'
    fi
    ensure_brew
    installed="$("$BREW" list --formula --versions git || true)"
    if [[ -n "$installed" ]]; then "$BREW" upgrade --formula git; else "$BREW" install --formula git; fi
    [[ -z "$("$BREW" outdated --formula --quiet git)" ]] || { printf '%s\n' 'Git is still outdated. Check whether the Homebrew formula is pinned.' >&2; exit 1; }
    prefix="$("$BREW" --prefix git)"
    export PROJTOOL_GIT_BIN="$prefix/bin"
    export PATH="$PROJTOOL_GIT_BIN:$PATH"
    "$PROJTOOL_GIT_BIN/git" --version
}

install_conda() {
    local architecture filename temporary checksum actual
    local destination="${1:-$HOME/miniconda3}"
    architecture="$(uname -m)"
    case "$architecture" in arm64|x86_64) ;; *) printf 'Unsupported Miniconda architecture: %s\n' "$architecture" >&2; exit 1 ;; esac
    [[ ! -e "$destination" ]] || { printf '%s already exists; refusing to overwrite it.\n' "$destination" >&2; exit 1; }
    confirm 'Conda was not found. Download and install the latest stable Miniconda?' || return 1
    filename="Miniconda3-latest-MacOSX-$architecture.sh"
    temporary="$(mktemp -d -t projtool-conda)" || exit 1
    curl -fSL https://repo.anaconda.com/miniconda/ -o "$temporary/index.html" || { rm -rf -- "$temporary"; exit 1; }
    checksum="$(sed -n "/href=\"$filename\"/,/<\/tr>/p" "$temporary/index.html" | sed -nE 's/.*<td>([0-9a-f]{64})<\/td>.*/\1/p')"
    [[ "$checksum" =~ ^[0-9a-f]{64}$ ]] || { printf '%s\n' 'Could not verify the Miniconda download checksum.' >&2; exit 1; }
    curl -fSL "https://repo.anaconda.com/miniconda/$filename" -o "$temporary/install.sh" || { rm -rf -- "$temporary"; exit 1; }
    actual="$(shasum -a 256 "$temporary/install.sh" | cut -d' ' -f1)"
    [[ "$actual" == "$checksum" ]] || { printf '%s\n' 'Miniconda download checksum mismatch.' >&2; exit 1; }
    bash "$temporary/install.sh" -b -p "$destination" || { rm -rf -- "$temporary"; exit 1; }
    rm -rf -- "$temporary"
    CONDA="$destination/bin/conda"
    "$CONDA" update --name base --override-channels --channel defaults conda || exit 1
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

if [[ "$COMPONENT" == all ]]; then ensure_git; fi

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
                if [[ ! -x "$CONDA" ]]; then install_conda || continue; fi
                PYTHON="$("$CONDA" info --base)/bin/python"
                [[ -x "$PYTHON" ]] || { printf '%s\n' 'The Conda base Python is missing.'; continue; }
                break
                ;;
            homebrew)
                ensure_brew
                if [[ -n "$("$BREW" list --formula --versions python || true)" ]]; then
                    "$BREW" upgrade --formula python
                else
                    confirm 'Install the latest stable Python with Homebrew?' || continue
                    "$BREW" install --formula python
                fi
                [[ -z "$("$BREW" outdated --formula --quiet python)" ]] || { printf '%s\n' 'Homebrew Python is still outdated. Check whether its formula is pinned.' >&2; exit 1; }
                PYTHON="$("$BREW" --prefix python)/bin/python3"
                [[ -x "$PYTHON" ]] || { printf '%s\n' 'Homebrew Python could not be located.' >&2; exit 1; }
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
    exec "$PYTHON" "$ROOT/Source/Install/Configure/configure.py" --component "$COMPONENT" --provider "$PROVIDER" --python "$PYTHON" --conda "$CONDA"
fi

if [[ -f "$CONFIG/python-executable" ]]; then IFS= read -r PYTHON < "$CONFIG/python-executable"; fi
if [[ ! -x "$PYTHON" ]]; then find_standard || PYTHON=/usr/bin/python3; fi
[[ -x "$PYTHON" ]] || { printf '%s\n' 'Run projtool update python first to configure Python.' >&2; exit 1; }
exec "$PYTHON" "$ROOT/Source/Install/Configure/configure.py" --component julia
