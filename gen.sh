#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COLLECTION_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR=""
RETAIN_BUILD=false

usage() {
    cat <<'EOF'
Usage: gen ACTION -f TARGET [-w verbose]

Examples:
  gen results -f dissertation_template
  gen pdf -f dissertation_template
  gen pdf -f dissertation_template -w verbose
  gen md -f dissertation_template
  gen md -f dissertation_template -w verbose

Actions:
  results             Run TARGET/code_assets with terminal output shown
  pdf                 Run code assets and generate TARGET/media/NAME.pdf
  md                  Run code assets and generate TARGET/media/NAME.md

Options:
  -f TARGET           Read files from TARGET
  -w verbose          Show tool output and retain TARGET/build

Without -w verbose, pdf and md suppress tool output and remove temporary build files.
EOF
}

die() {
    printf 'gen: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

cleanup_current_build() {
    if [[ "$RETAIN_BUILD" != true && -n "$BUILD_DIR" && -d "$BUILD_DIR" ]]; then
        rm -rf -- "$BUILD_DIR"
    fi
}

run_code_file() {
    local file="$1"

    case "$file" in
        *.jl)    printf '→ running code_assets/%s\n' "$(basename -- "$file")"; require_command julia;   julia "$file" ;;
        *.py)    printf '→ running code_assets/%s\n' "$(basename -- "$file")"; require_command python3; python3 "$file" ;;
        *.R|*.r) printf '→ running code_assets/%s\n' "$(basename -- "$file")"; require_command Rscript; Rscript "$file" ;;
        *.sh)    printf '→ running code_assets/%s\n' "$(basename -- "$file")"; require_command bash;    bash "$file" ;;
        *.bash)  printf '→ running code_assets/%s\n' "$(basename -- "$file")"; require_command bash;    bash "$file" ;;
        *.zsh)   printf '→ running code_assets/%s\n' "$(basename -- "$file")"; require_command zsh;     zsh "$file" ;;
        *)
            if [[ -x "$file" ]]; then
                printf '→ running code_assets/%s\n' "$(basename -- "$file")"
                "$file"
            fi
            ;;
    esac
}

run_code_stage() {
    local show_output="$1"
    local code_count=0
    local file

    while IFS= read -r file; do
        code_count=$((code_count + 1))
        if [[ "$show_output" == true ]]; then
            (cd -- "$TARGET_DIR" && run_code_file "$file")
        elif ! (cd -- "$TARGET_DIR" && run_code_file "$file") \
            >/dev/null 2>&1; then
            die "code asset failed: $(basename -- "$file"); rerun with -w verbose for details"
        fi
    done < <(find "$CODE_DIR" -maxdepth 1 -type f ! -name '.*' -print | LC_ALL=C sort)

    if (( code_count == 0 )) && [[ "$show_output" == true ]]; then
        printf '→ code_assets/ is empty\n'
    fi
}

render_tex_pdf() {
    local source="$1"
    local stem="$2"
    local verbose="$3"

    require_command latexmk
    if [[ "$verbose" == true ]]; then
        TEXINPUTS="$SCRIPT_DIR//:${TEXINPUTS:-}" \
            latexmk -pdf -interaction=nonstopmode -halt-on-error \
            -outdir="$BUILD_DIR" "$source"
    elif ! TEXINPUTS="$SCRIPT_DIR//:${TEXINPUTS:-}" \
        latexmk -pdf -interaction=nonstopmode -halt-on-error \
        -outdir="$BUILD_DIR" "$source" >/dev/null 2>&1; then
        die "PDF build failed; rerun with pdf -f TARGET -w verbose for details"
    fi

    mv -- "$BUILD_DIR/$stem.pdf" "$MEDIA_DIR/$stem.pdf"
}

render_document() {
    local file="$1"
    local output_format="$2"
    local verbose="$3"
    local name stem
    name="$(basename -- "$file")"
    stem="${name%.*}"

    if [[ "$verbose" == true ]]; then
        printf '→ generating %s as %s\n' "$name" "$output_format"
    fi
    case "$output_format:$file" in
        pdf:*.tex)
            render_tex_pdf "$file" "$stem" "$verbose"
            ;;
        md:*.tex)
            require_command pandoc
            if [[ "$verbose" == true ]]; then
                pandoc --from=latex --to=gfm --wrap=none \
                    "$file" -o "$MEDIA_DIR/$stem.md"
            elif ! pandoc --from=latex --to=gfm --wrap=none \
                "$file" -o "$MEDIA_DIR/$stem.md" >/dev/null 2>&1; then
                die "Markdown build failed; rerun with md -f TARGET -w verbose for details"
            fi
            ;;
        *)
            die "cannot render $name as $output_format"
            ;;
    esac
}

run_build() {
    local verbose="$1"
    shift
    local output_format

    [[ -d "$CODE_DIR" ]] || die "missing directory: $CODE_DIR"
    [[ -f "$DOCUMENT_FILE" ]] || die "missing document source: $DOCUMENT_FILE"
    mkdir -p -- "$MEDIA_DIR"

    if [[ "$verbose" == true ]]; then
        BUILD_DIR="$TARGET_DIR/build"
        RETAIN_BUILD=true
        mkdir -p -- "$BUILD_DIR"
    else
        BUILD_DIR="$(mktemp -d "$MEDIA_DIR/.gen.XXXXXX")"
        RETAIN_BUILD=false
    fi

    run_code_stage "$verbose"

    for output_format in "$@"; do
        (cd -- "$TARGET_DIR" && render_document "$DOCUMENT_FILE" "$output_format" "$verbose")
    done

    if [[ "$RETAIN_BUILD" != true ]]; then
        cleanup_current_build
    fi
    BUILD_DIR=""
    RETAIN_BUILD=false
}

[[ $# -eq 0 ]] && { usage; exit 2; }
[[ "$1" == "-h" || "$1" == "--help" ]] && { usage; exit 0; }
[[ $# -eq 3 || $# -eq 5 ]] || { usage >&2; exit 2; }

ACTION="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
[[ "$2" == "-f" || "$2" == "--from" ]] || die "expected -f TARGET"
TARGET="$3"
VERBOSE=false

if [[ $# -eq 5 ]]; then
    [[ "$4" == "-w" || "$4" == "--with" ]] || die "expected -w verbose"
    MODIFIER="$(printf '%s' "$5" | tr '[:upper:]' '[:lower:]')"
    [[ "$MODIFIER" == "verbose" ]] || die "unsupported modifier: $5"
    VERBOSE=true
fi

case "$ACTION" in
    results)
        [[ "$VERBOSE" == false ]] || die "results always shows code output and does not accept -w verbose"
        ;;
    pdf|md) ;;
    *) die "unsupported action: $ACTION" ;;
esac

if [[ -d "$TARGET" ]]; then
    TARGET_DIR="$(cd -- "$TARGET" && pwd)"
elif [[ -d "$COLLECTION_DIR/$TARGET" ]]; then
    TARGET_DIR="$(cd -- "$COLLECTION_DIR/$TARGET" && pwd)"
else
    die "target not found: $TARGET"
fi

TARGET_NAME="$(basename -- "$TARGET_DIR")"
DOCUMENT_STEM="${TARGET_NAME%_template}"
DOCUMENT_FILE="$TARGET_DIR/$DOCUMENT_STEM.tex"
CODE_DIR="$TARGET_DIR/code_assets"
MEDIA_DIR="$TARGET_DIR/media"

trap cleanup_current_build EXIT

case "$ACTION" in
    results)
        [[ -d "$CODE_DIR" ]] || die "missing directory: $CODE_DIR"
        run_code_stage true
        printf '✓ %s results generated\n' "$TARGET_NAME"
        ;;
    pdf)
        run_build "$VERBOSE" pdf
        ;;
    md)
        run_build "$VERBOSE" md
        ;;
esac

case "$ACTION" in
    pdf|md)
        if [[ "$VERBOSE" == true ]]; then
            printf '✓ %s generated as %s verbose\n' "$TARGET_NAME" "$ACTION"
        else
            printf '✓ %s generated as %s\n' "$TARGET_NAME" "$ACTION"
        fi
        ;;
esac
