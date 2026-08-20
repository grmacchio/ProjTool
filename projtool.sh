#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COLLECTION_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
RESULTS_WORK_DIR=""
MODE=""

usage() {
    cat <<'EOF'
Usage: projtool.sh COMMAND ...

Commands:
  gen                 Generate results, media, or a README
  rem                 Remove generated output or README files

Run "projtool.sh gen --help" or "projtool.sh rem --help" for details.
EOF
}

usage_gen() {
    cat <<'EOF'
Usage: projtool.sh gen ACTION -f TARGET [-w verbose]

Examples:
  projtool.sh gen results -f ./examples/dissertation
  projtool.sh gen media -f ./examples/dissertation
  projtool.sh gen output -f ./examples/dissertation
  projtool.sh gen readme -f ./examples/dissertation
  projtool.sh gen pdf -f ./examples/dissertation
  projtool.sh gen pdf -f ./examples/dissertation -w verbose
  projtool.sh gen md -f ./examples/dissertation
  projtool.sh gen md -f ./examples/dissertation -w verbose

Actions:
  results             Write results to TARGET/output/results
  media               Generate both PDF and Markdown
  output              Generate results, PDF, and Markdown
  readme              Copy generated media and write TARGET/README.md
  pdf                 Generate PDF in TARGET/output/media/pdf
  md                  Generate Markdown in TARGET/output/media/md

Options:
  -f TARGET           Read source files from TARGET
  -w verbose          Show tool output in the terminal

Choose which code files run by listing them explicitly in TARGET/results.sh.
PDF and Markdown generation never run source code; run results separately when needed.
EOF
}

usage_rem() {
    cat <<'EOF'
Usage: projtool.sh rem SCOPE -f TARGET

Examples:
  projtool.sh rem output -f ./examples/dissertation
  projtool.sh rem readme -f ./examples/dissertation
  projtool.sh rem results -f ./examples/dissertation
  projtool.sh rem media -f ./examples/dissertation
  projtool.sh rem pdf -f ./examples/dissertation
  projtool.sh rem md -f ./examples/dissertation

Scopes:
  output              Remove TARGET/output
  readme              Remove TARGET/README.md, NAME.pdf, and NAME.md
  results             Remove TARGET/output/results
  media               Remove TARGET/output/media
  pdf                 Remove TARGET/output/media/pdf
  md                  Remove TARGET/output/media/md
EOF
}

die() {
    printf 'projtool %s: %s\n' "$MODE" "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

resolve_target() {
    local target="$1"

    if [[ -d "$target" ]]; then
        TARGET_DIR="$(cd -- "$target" && pwd)"
    elif [[ -d "$COLLECTION_DIR/$target" ]]; then
        TARGET_DIR="$(cd -- "$COLLECTION_DIR/$target" && pwd)"
    else
        die "target not found: $target"
    fi

    TARGET_NAME="$(basename -- "$TARGET_DIR")"
    DOCUMENT_STEM="${TARGET_NAME%_template}"
    DOCUMENT_FILE="$TARGET_DIR/$DOCUMENT_STEM.tex"
    OUTPUT_DIR="$TARGET_DIR/output"
    RESULTS_OUTPUT_DIR="$OUTPUT_DIR/results"
    RESULTS_SCRIPT="$TARGET_DIR/results.sh"
    MEDIA_OUTPUT_DIR="$OUTPUT_DIR/media"
    PDF_OUTPUT_DIR="$MEDIA_OUTPUT_DIR/pdf"
    MD_OUTPUT_DIR="$MEDIA_OUTPUT_DIR/md"
}

cleanup_results_work() {
    if [[ -n "$RESULTS_WORK_DIR" && -d "$RESULTS_WORK_DIR" ]]; then
        rm -rf -- "$RESULTS_WORK_DIR"
    fi
}

run_results_stage() {
    local file
    local result

    [[ -f "$RESULTS_SCRIPT" ]] || die "missing results runner: $RESULTS_SCRIPT"
    mkdir -p -- "$RESULTS_OUTPUT_DIR"
    RESULTS_WORK_DIR="$(mktemp -d "$OUTPUT_DIR/.results.XXXXXX")"

    while IFS= read -r file; do
        ln -s -- "$file" "$RESULTS_WORK_DIR/$(basename -- "$file")"
    done < <(find "$TARGET_DIR" -maxdepth 1 -type f -print | LC_ALL=C sort)

    printf '%s\n' '-> running results.sh'
    (cd -- "$RESULTS_WORK_DIR" && bash ./results.sh)

    while IFS= read -r result; do
        mv -f -- "$result" "$RESULTS_OUTPUT_DIR/"
    done < <(find "$RESULTS_WORK_DIR" -mindepth 1 -maxdepth 1 ! -type l -print)

    cleanup_results_work
    RESULTS_WORK_DIR=""
}

render_pdf() {
    require_command latexmk
    mkdir -p -- "$PDF_OUTPUT_DIR"

    if [[ "$VERBOSE" == true ]]; then
        TEXINPUTS="$SCRIPT_DIR//:${TEXINPUTS:-}" \
            latexmk -pdf -interaction=nonstopmode -halt-on-error \
            -outdir="$PDF_OUTPUT_DIR" "$DOCUMENT_FILE"
    elif ! TEXINPUTS="$SCRIPT_DIR//:${TEXINPUTS:-}" \
        latexmk -pdf -interaction=nonstopmode -halt-on-error \
        -outdir="$PDF_OUTPUT_DIR" "$DOCUMENT_FILE" >/dev/null 2>&1; then
        die "PDF build failed; rerun with pdf -f TARGET -w verbose for details"
    fi
}

write_markdown_build_file() {
    MARKDOWN_BUILD_FILE="$MD_OUTPUT_DIR/$DOCUMENT_STEM.pandoc.tex"

    {
        printf '%s\n' \
        '\newcommand{\genFront}[8]{\subsection{\textbf{Title}: #1}\textbf{Author:} #2\par\textbf{University:} #3\par\textbf{Department:} #4\par\textbf{Advisor:} #5\par\textbf{Date:} #6\par\subsection{\textbf{Abstract}}#7\subsection{\textbf{Acknowledgments}}#8\subsection{\textbf{LaTeXToTOC}}}' \
            '\newcommand{\genPart}[4]{\subsection{\textbf{LaTeXToPart} \textbf{#2} \textbf{#3} #1}#4}' \
            '\newcommand{\genSubPart}[4]{\subsubsection{\textbf{LaTeXToSubPart} \textbf{#2} \textbf{#3} #1}#4}' \
            '\newcommand{\genTHM}[5]{\paragraph{\textbf{LaTeXToTheorem} \textbf{#2} \textbf{#3} #1}#4\paragraph{\textbf{LaTeXToProofInline}}\textbf{LaTeXToProofLink} #1\subparagraph{\textbf{LaTeXToProofStart} #1}#5\subparagraph{\textbf{LaTeXToProofEnd}}}' \
            '\newcommand{\genDEF}[4]{\paragraph{\textbf{LaTeXToDefinition} \textbf{#2} \textbf{#3} #1}#4}' \
            '\newcommand{\genFIG}[7]{\par\includegraphics[width=#5\textwidth]{#6}\par\paragraph{\textbf{LaTeXToFigure} \textbf{#2} \textbf{#3} #1}#7}' \
            '\newcommand{\genRef}[2]{\href{latex-to-ref:#1}{#2}}' \
            '\newcommand{\genBack}{\subsection{\textbf{LaTeXToReferences}}}'
        cat -- "$DOCUMENT_FILE"
    } > "$MARKDOWN_BUILD_FILE"
}

render_md() {
    local md_file="$MD_OUTPUT_DIR/$DOCUMENT_STEM.md"
    local md_temp_file="$MD_OUTPUT_DIR/.$DOCUMENT_STEM.md.tmp"
    local bibliography_file="$TARGET_DIR/references.bib"
    local citation_style_file="$SCRIPT_DIR/references.csl"
    local reference_filter_file="$SCRIPT_DIR/format-references.lua"
    local -a citation_options=()

    if [[ -f "$bibliography_file" ]]; then
        [[ -f "$citation_style_file" ]] ||
            die "missing citation style: $citation_style_file"
        [[ -f "$reference_filter_file" ]] ||
            die "missing reference filter: $reference_filter_file"
        citation_options=(
            --bibliography="$bibliography_file"
            --csl="$citation_style_file"
            --metadata=link-citations:true
            --citeproc
            --lua-filter="$reference_filter_file"
        )
    fi

    require_command pandoc
    mkdir -p -- "$MD_OUTPUT_DIR"
    write_markdown_build_file
    rm -f -- "$md_temp_file"

    if [[ "$VERBOSE" == true ]]; then
        if ! pandoc --from=latex --to=gfm --wrap=none --fail-if-warnings \
            --lua-filter="$SCRIPT_DIR/validate-md.lua" \
            "${citation_options[@]}" \
            "$MARKDOWN_BUILD_FILE" -o "$md_temp_file"; then
            rm -f -- "$md_temp_file"
            die "Markdown build failed"
        fi
    elif ! pandoc --from=latex --to=gfm --wrap=none \
        --fail-if-warnings --lua-filter="$SCRIPT_DIR/validate-md.lua" \
        "${citation_options[@]}" \
        "$MARKDOWN_BUILD_FILE" -o "$md_temp_file" >/dev/null; then
        rm -f -- "$md_temp_file"
        die "Markdown build failed"
    fi

    if ! mv -f -- "$md_temp_file" "$md_file"; then
        rm -f -- "$md_temp_file"
        die "could not publish Markdown file: $md_file"
    fi
}

render_media() {
    local format

    [[ -f "$DOCUMENT_FILE" ]] || die "missing document source: $DOCUMENT_FILE"
    for format in "$@"; do
        printf '%s\n' "-> generating $DOCUMENT_STEM as $format"
        (cd -- "$TARGET_DIR" && "render_$format")
    done
}

write_readme() {
    local pdf_file="$PDF_OUTPUT_DIR/$DOCUMENT_STEM.pdf"
    local md_file="$MD_OUTPUT_DIR/$DOCUMENT_STEM.md"
    local target_pdf="$TARGET_DIR/$DOCUMENT_STEM.pdf"
    local target_md="$TARGET_DIR/$DOCUMENT_STEM.md"
    local readme_file="$TARGET_DIR/README.md"
    local has_pdf=false
    local has_md=false
    local intro

    [[ -f "$pdf_file" ]] && has_pdf=true
    [[ -f "$md_file" ]] && has_md=true

    case "$has_pdf:$has_md" in
        true:false)
            intro="The media developed in the project includes a [PDF file](./$DOCUMENT_STEM.pdf)."
            ;;
        false:true)
            intro="The media developed in the project includes a [Markdown file](./$DOCUMENT_STEM.md). The contents of the Markdown file can also be found below."
            ;;
        true:true)
            intro="The media developed in the project includes a [PDF file](./$DOCUMENT_STEM.pdf) and [Markdown file](./$DOCUMENT_STEM.md). The contents of the Markdown file can also be found below."
            ;;
        false:false)
            die "no generated PDF or Markdown found in $MEDIA_OUTPUT_DIR"
            ;;
    esac

    [[ "$has_pdf" == true ]] && cp -f -- "$pdf_file" "$target_pdf"
    if [[ "$has_md" == true ]]; then
        sed -e 's#](../../results/#](./output/results/#g' \
            -e 's#src="../../results/#src="./output/results/#g' \
            "$md_file" > "$target_md"
    fi
    printf '%s\n' "$intro" > "$readme_file"

    if [[ "$has_md" == true ]]; then
        printf '\n' >> "$readme_file"
        cat -- "$target_md" >> "$readme_file"
    fi
}

remove_path() {
    local path="$1"

    if [[ -e "$path" || -L "$path" ]]; then
        printf '%s\n' "-> removing $path"
        rm -rf -- "$path"
    else
        printf '%s\n' "-> already absent: $path"
    fi
}

main_gen() {
    [[ $# -eq 0 ]] && { usage_gen; exit 2; }
    [[ "$1" == "-h" || "$1" == "--help" ]] && { usage_gen; exit 0; }
    [[ $# -eq 3 || $# -eq 5 ]] || { usage_gen >&2; exit 2; }

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
        output|results|media|readme|pdf|md) ;;
        *) die "unsupported action: $ACTION" ;;
    esac

    resolve_target "$TARGET"
    trap cleanup_results_work EXIT

    case "$ACTION" in
        output)
            run_results_stage
            render_media pdf md
            ;;
        results)
            run_results_stage
            ;;
        media)
            render_media pdf md
            ;;
        readme)
            write_readme
            ;;
        pdf|md)
            render_media "$ACTION"
            ;;
    esac

    printf '✓ %s generated for %s\n' "$ACTION" "$TARGET_NAME"
}

main_rem() {
    [[ $# -eq 0 ]] && { usage_rem; exit 2; }
    [[ "$1" == "-h" || "$1" == "--help" ]] && { usage_rem; exit 0; }
    [[ $# -eq 3 ]] || { usage_rem >&2; exit 2; }

    SCOPE="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    [[ "$2" == "-f" || "$2" == "--from" ]] || die "expected -f TARGET"
    TARGET="$3"

    case "$SCOPE" in
        output) OUTPUT_PATH="output" ;;
        readme) ;;
        results) OUTPUT_PATH="output/results" ;;
        media) OUTPUT_PATH="output/media" ;;
        pdf) OUTPUT_PATH="output/media/pdf" ;;
        md) OUTPUT_PATH="output/media/md" ;;
        *) die "unsupported scope: $SCOPE" ;;
    esac

    resolve_target "$TARGET"

    if [[ "$SCOPE" == readme ]]; then
        remove_path "$TARGET_DIR/$DOCUMENT_STEM.pdf"
        remove_path "$TARGET_DIR/$DOCUMENT_STEM.md"
        remove_path "$TARGET_DIR/README.md"
    else
        remove_path "$TARGET_DIR/$OUTPUT_PATH"
    fi

    printf '✓ %s removed from %s\n' "$SCOPE" "$TARGET_NAME"
}

[[ $# -eq 0 ]] && { usage; exit 2; }
[[ "$1" == "-h" || "$1" == "--help" ]] && { usage; exit 0; }

MODE="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
shift

case "$MODE" in
    gen) main_gen "$@" ;;
    rem) main_rem "$@" ;;
    *)
        printf 'projtool: unsupported command: %s\n' "$MODE" >&2
        usage >&2
        exit 1
        ;;
esac
