#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COLLECTION_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
MODE=""
TEMPLATE_TYPE=""

usage() {
    cat <<'EOF'
Usage: projtool COMMAND ...

Commands:
  init                Initialize the current directory from an example
  cpush               Commit and push project changes
  gen                 Generate results, media, or a README
  rem                 Remove generated output or README files

Run "projtool COMMAND --help" for command details.
EOF
}

usage_init() {
    cat <<'EOF'
Usage: projtool init TYPE

Examples:
  projtool init dissertation
  projtool init note
  projtool init preprint
  projtool init presentation

Prompts for the creator name, GitHub URL, and initial version.
Copies the selected example into the current directory.
Renames the main TeX file to match the current directory.
Excludes output, TYPE.md, TYPE.pdf, README.md, and .DS_Store.
Creates LICENSE.txt, initializes Git, creates the initial commit and version
tag, and pushes the main branch and tag to GitHub.
Existing paths are never overwritten.
EOF
}

usage_cpush() {
    cat <<'EOF'
Usage: projtool cpush -m MESSAGE [-v VERSION]

Examples:
  projtool cpush -m "Revise introduction"
  projtool cpush -m "Release v0.2.0" -v v0.2.0

Options:
  -m MESSAGE           Commit message
  -v VERSION           Create an annotated release tag

Updates the ending copyright year in LICENSE.txt and stages the license.
Commit other project changes with git add before running cpush. The commit is
pushed to origin; with -v, the current branch and version tag are pushed
together.
EOF
}

usage_gen() {
    cat <<'EOF'
Usage: projtool gen ACTION [-f TARGET] [-w verbose]

Examples:
  projtool gen results
  projtool gen media
  projtool gen output
  projtool gen readme
  projtool gen pdf -f ./examples/dissertation
  projtool gen pdf -f ./examples/dissertation -w verbose
  projtool gen md -f ./examples/dissertation
  projtool gen md -f ./examples/dissertation -w verbose

Actions:
  results             Write results to TARGET/output/results
  media               Generate both PDF and Markdown
  output              Generate results, PDF, and Markdown
  readme              Copy generated media and write TARGET/README.md
  pdf                 Generate PDF in TARGET/output/media/pdf
  md                  Generate Markdown in TARGET/output/media/md

Options:
  -f TARGET           Read source files from TARGET; defaults to the working directory
  -w verbose          Show tool output in the terminal

Choose which code files run by listing them explicitly in TARGET/results.sh.
The script runs from TARGET and writes generated files to TARGET/output/results.
PDF and Markdown generation never run source code; run results separately when needed.
EOF
}

usage_rem() {
    cat <<'EOF'
Usage: projtool rem SCOPE [-f TARGET]

Examples:
  projtool rem output
  projtool rem readme
  projtool rem results
  projtool rem media -f ./examples/dissertation
  projtool rem pdf -f ./examples/dissertation
  projtool rem md -f ./examples/dissertation

Scopes:
  output              Remove TARGET/output
  readme              Remove TARGET/README.md, NAME.pdf, and NAME.md
  results             Remove TARGET/output/results
  media               Remove TARGET/output/media
  pdf                 Remove TARGET/output/media/pdf
  md                  Remove TARGET/output/media/md

Options:
  -f TARGET           Remove files from TARGET; defaults to the working directory
EOF
}

die() {
    printf 'projtool %s: %s\n' "$MODE" "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

prompt_required() {
    local prompt="$1"
    local value

    printf '%s' "$prompt"
    IFS= read -r value || die "input ended before all prompts were answered"
    [[ -n "$value" ]] || die "a value is required for: ${prompt%: }"
    PROMPT_VALUE="$value"
}

validate_version() {
    local version="$1"

    git check-ref-format "refs/tags/$version" >/dev/null 2>&1 ||
        die "invalid version tag: $version"
}

write_project_license() {
    local target_dir="$1"
    local project_name="$2"
    local creator_name="$3"
    local github_url="$4"
    local license_template="$SCRIPT_DIR/LICENSE.txt"
    local license_file="$target_dir/LICENSE.txt"
    local license_temp
    local current_year
    local line
    local attribution=false
    local attribution_url="$github_url"

    [[ -f "$license_template" ]] || die "missing license template: $license_template"
    current_year="$(date +%Y)"
    [[ "$current_year" =~ ^[0-9]{4}$ ]] || die "could not determine the current year"

    case "$attribution_url" in
        git@github.com:*)
            attribution_url="https://github.com/${attribution_url#git@github.com:}"
            ;;
        ssh://git@github.com/*)
            attribution_url="https://github.com/${attribution_url#ssh://git@github.com/}"
            ;;
    esac
    attribution_url="${attribution_url%.git}"

    license_temp="$(mktemp "$target_dir/.projtool-license.XXXXXX")"
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == "Copyright (c) "* ]]; then
            line="Copyright (c) $current_year-$current_year $creator_name and $project_name contributors"
        else
            line="${line//Gregory R. Macchio/$creator_name}"
            line="${line//ProjTool/$project_name}"
        fi

        if [[ "$line" == "Suggested attribution:" ]]; then
            attribution=true
        elif [[ "$attribution" == true && ( "$line" == http://* || "$line" == https://* || "$line" == git@* ) ]]; then
            if [[ "$line" == *\" ]]; then
                line="$attribution_url\""
            else
                line="$attribution_url"
            fi
            attribution=false
        fi
        printf '%s\n' "$line"
    done < "$license_template" > "$license_temp"
    chmod 0644 "$license_temp"
    mv -f -- "$license_temp" "$license_file"
}

update_license_years() {
    local license_file="$1"
    local current_year
    local license_temp
    local line
    local first_year
    local holder
    local found=false

    [[ -f "$license_file" ]] || die "missing license file: $license_file"
    current_year="$(date +%Y)"
    [[ "$current_year" =~ ^[0-9]{4}$ ]] || die "could not determine the current year"
    license_temp="$(mktemp "${license_file}.XXXXXX")"

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^Copyright\ \(c\)\ ([0-9]{4})(-[0-9]{4})?\ (.*)$ ]]; then
            first_year="${BASH_REMATCH[1]}"
            holder="${BASH_REMATCH[3]}"
            (( 10#$current_year >= 10#$first_year )) || {
                rm -f -- "$license_temp"
                die "license begins in a future year: $first_year"
            }
            line="Copyright (c) $first_year-$current_year $holder"
            found=true
        fi
        printf '%s\n' "$line"
    done < "$license_file" > "$license_temp"

    if [[ "$found" != true ]]; then
        rm -f -- "$license_temp"
        die "no copyright notice found in $license_file"
    fi
    chmod 0644 "$license_temp"
    mv -f -- "$license_temp" "$license_file"
}

resolve_target() {
    local target="$1"
    local candidate
    local -a document_candidates=()

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
    if [[ ! -f "$DOCUMENT_FILE" ]]; then
        while IFS= read -r -d '' candidate; do
            document_candidates+=("$candidate")
        done < <(find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -type f \
            -name '*.tex' ! -name '*.pandoc.tex' -print0)
        if [[ ${#document_candidates[@]} -eq 1 ]]; then
            DOCUMENT_FILE="${document_candidates[0]}"
            DOCUMENT_STEM="$(basename -- "${DOCUMENT_FILE%.tex}")"
        fi
    fi
    if [[ -f "$DOCUMENT_FILE" ]]; then
        TEMPLATE_TYPE="$(sed -nE 's/^[[:space:]]*\\documentclass\[([^]]+)\]\{template\}.*/\1/p' "$DOCUMENT_FILE")"
    fi
    OUTPUT_DIR="$TARGET_DIR/output"
    RESULTS_SCRIPT="$TARGET_DIR/results.sh"
    MEDIA_OUTPUT_DIR="$OUTPUT_DIR/media"
    PDF_OUTPUT_DIR="$MEDIA_OUTPUT_DIR/pdf"
    MD_OUTPUT_DIR="$MEDIA_OUTPUT_DIR/md"
}

cleanup_source_build_files() {
    local suffix
    local -a suffixes=(
        aux bbl bcf blg fdb_latexmk fls log nav out run.xml snm
        synctex.gz toc vrb xdv
    )

    for suffix in "${suffixes[@]}"; do
        rm -f -- "$TARGET_DIR/$DOCUMENT_STEM.$suffix"
    done
}

run_results_stage() {
    local julia_project="$TARGET_DIR/code"

    [[ -f "$RESULTS_SCRIPT" ]] || die "missing results runner: $RESULTS_SCRIPT"
    if [[ -f "$TARGET_DIR/code/julia/Project.toml" ]]; then
        julia_project="$TARGET_DIR/code/julia"
    fi

    printf '%s\n' '-> running results.sh'
    (
        cd -- "$TARGET_DIR"
        export PROJTOOL_VERBOSE="$VERBOSE"
        export JULIA_PROJECT="${JULIA_PROJECT:-$julia_project}"
        export GKSwstype="${GKSwstype:-nul}"
        if [[ "$VERBOSE" == true ]]; then
            bash -e ./results.sh
        else
            bash -e ./results.sh 2>&1 | sed '/^\[NbClientApp\]/d'
        fi
    )
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
    local front_command
    local part_command='\newcommand{\genPart}[4]{\subsection{\textbf{LaTeXToPart} \textbf{#2} \textbf{#3} #1}#4}'
    local subpart_command='\newcommand{\genSubPart}[4]{\subsubsection{\textbf{LaTeXToSubPart} \textbf{#2} \textbf{#3} #1}#4}'
    local theorem_command='\newcommand{\genTHM}[5]{\paragraph{\textbf{LaTeXToTheorem} \textbf{#2} \textbf{#3} #1}#4\paragraph{\textbf{LaTeXToProofInline}}\textbf{LaTeXToProofLink} #1\subparagraph{\textbf{LaTeXToProofStart} #1}#5\subparagraph{\textbf{LaTeXToProofEnd}}}'
    local definition_command='\newcommand{\genDEF}[4]{\paragraph{\textbf{LaTeXToDefinition} \textbf{#2} \textbf{#3} #1}#4}'
    local figure_command='\newcommand{\genFIG}[7]{\par\includegraphics[width=#5\textwidth]{#6}\par\paragraph{\textbf{LaTeXToFigure} \textbf{#2} \textbf{#3} #1}#7}'
    local back_command='\newcommand{\genBack}{\subsection{\textbf{LaTeXToReferences}}}'
    local presentation_commands=''

    MARKDOWN_BUILD_FILE="$MD_OUTPUT_DIR/$DOCUMENT_STEM.pandoc.tex"

    if [[ "$TEMPLATE_TYPE" == "preprint" ]]; then
        front_command='\newcommand{\genFront}[7]{\subsection{#1}\textbf{Intended Journal:} #2\par\textbf{Authors:} #3\par\textbf{Affiliations:} #4\par\textbf{Date:} #5\par\subsection{Abstract}#6\subsection{Acknowledgments}#7\subsection{\textbf{LaTeXToTOC}}}'
    elif [[ "$TEMPLATE_TYPE" == "note" ]]; then
        front_command='\newcommand{\genFront}[4]{\subsection{#1}\textbf{Authors:} #2\par\textbf{Affiliations:} #3\par\textbf{Date:} #4\par\subsection{\textbf{LaTeXToTOC}}}'
    elif [[ "$TEMPLATE_TYPE" == "presentation" ]]; then
        front_command='\newcommand{\genFront}[5]{\subsection{\textbf{Title}: #1}\textbf{Authors:} #2\par\textbf{Affiliations:} #3\par\textbf{Acknowledgments:} #4\par\textbf{Date:} #5\par\subsection{\textbf{LaTeXToTOC}}}'
        part_command='\newcommand{\genPart}[2]{\subsection{\textbf{LaTeXToPart} \textbf{nonum} \textbf{toc} #1}#2}'
        subpart_command='\newcommand{\genSubPart}[2]{\subsubsection{\textbf{LaTeXToSubPart} \textbf{inh} \textbf{notoc} #1}#2}'
        theorem_command='\newcommand{\genTHM}[2]{\paragraph{\textbf{LaTeXToTheorem} #1}#2}'
        definition_command='\newcommand{\genDEF}[2]{\paragraph{\textbf{LaTeXToDefinition} #1}#2}'
        figure_command='\newcommand{\genFIG}[5]{\par\includegraphics[width=#3\textwidth]{#4}\par\paragraph{\textbf{LaTeXToFigure} #1}#5}'
        back_command='\newcommand{\genBack}{\subsection{\textbf{LaTeXToAppendixTOC}}}'
        presentation_commands='\newcommand{\togglefalse}[1]{}\newcommand{\toggletrue}[1]{}\newcommand{\bo}[2]{\begin{#1}}\newcommand{\eo}[1]{\end{#1}}\newcommand{\bi}[2]{\begin{#1}}\newcommand{\ei}[1]{\end{#1}}\newcommand{\bitem}[1]{\item \textbf{#1}}\newcommand{\iitem}[1]{\item \textit{#1}}'
    else
        front_command='\newcommand{\genFront}[8]{\subsection{#1}\textbf{Author:} #2\par\textbf{University:} #3\par\textbf{Department:} #4\par\textbf{Advisor:} #5\par\textbf{Date:} #6\par\subsection{Abstract}#7\subsection{Acknowledgments}#8\subsection{\textbf{LaTeXToTOC}}}'
    fi

    {
        printf '%s\n' \
            "$front_command" \
            "$part_command" \
            "$subpart_command" \
            "$theorem_command" \
            "$definition_command" \
            "$figure_command" \
            "$presentation_commands" \
            '\newcommand{\genREF}[2]{\href{latex-to-ref:#1}{#2}}' \
            "$back_command"
        if [[ "$TEMPLATE_TYPE" == "presentation" ]]; then
            sed 's/\\item\[\]/\\item \\textbf{ProjToolEmptyItem}/g' \
                "$DOCUMENT_FILE"
        else
            cat -- "$DOCUMENT_FILE"
        fi
    } > "$MARKDOWN_BUILD_FILE"
}

render_md() {
    local md_file="$MD_OUTPUT_DIR/$DOCUMENT_STEM.md"
    local md_temp_file="$MD_OUTPUT_DIR/.$DOCUMENT_STEM.md.tmp"
    local bibliography_file="$TARGET_DIR/references.bib"
    local bibliography_entry
    local citation_style_file="$SCRIPT_DIR/references.csl"
    local reference_filter_file="$SCRIPT_DIR/format-references.lua"
    local -a bibliography_files=()
    local -a citation_options=()
    local -a template_options=(--metadata="template-type:${TEMPLATE_TYPE:-dissertation}")

    if [[ "$TEMPLATE_TYPE" == "presentation" ]]; then
        citation_options=(--metadata=link-citations:false)
    fi

    if [[ -f "$bibliography_file" ]]; then
        bibliography_files+=("$bibliography_file")
    elif [[ -d "$TARGET_DIR/references" ]]; then
        while IFS= read -r -d '' bibliography_entry; do
            bibliography_files+=("$bibliography_entry")
        done < <(
            find "$TARGET_DIR/references" -type f -name '*.bib' -print0 |
                LC_ALL=C sort -z
        )
    fi

    if [[ ${#bibliography_files[@]} -gt 0 ]]; then
        [[ -f "$citation_style_file" ]] ||
            die "missing citation style: $citation_style_file"
        [[ -f "$reference_filter_file" ]] ||
            die "missing reference filter: $reference_filter_file"
        citation_options=(
            --csl="$citation_style_file"
            --metadata=link-citations:true
            --citeproc
            --lua-filter="$reference_filter_file"
        )
        for bibliography_entry in "${bibliography_files[@]}"; do
            citation_options+=(--bibliography="$bibliography_entry")
        done
    fi

    require_command pandoc
    mkdir -p -- "$MD_OUTPUT_DIR"
    write_markdown_build_file
    rm -f -- "$md_temp_file"

    if [[ "$VERBOSE" == true ]]; then
        if ! pandoc --from=latex --to=gfm --wrap=none --fail-if-warnings \
            --lua-filter="$SCRIPT_DIR/validate-md.lua" \
            "${template_options[@]}" \
            "${citation_options[@]}" \
            "$MARKDOWN_BUILD_FILE" -o "$md_temp_file"; then
            rm -f -- "$md_temp_file"
            die "Markdown build failed"
        fi
    elif ! pandoc --from=latex --to=gfm --wrap=none \
        --fail-if-warnings --lua-filter="$SCRIPT_DIR/validate-md.lua" \
        "${template_options[@]}" \
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
    local repeatability="To ensure repeatability, see [ProjTool](https://github.com/grmacchio/LaTeXTo) on how to regenerate this project from its source files."

    [[ -f "$pdf_file" ]] && has_pdf=true
    [[ -f "$md_file" ]] && has_md=true

    case "$has_pdf:$has_md" in
        true:false)
            intro="This project includes a [PDF file](./$DOCUMENT_STEM.pdf)."
            ;;
        false:true)
            intro="This project includes a [Markdown file](./$DOCUMENT_STEM.md). The Markdown file is included below for convenience."
            ;;
        true:true)
            intro="This project includes a [PDF file](./$DOCUMENT_STEM.pdf) and [Markdown file](./$DOCUMENT_STEM.md). The Markdown file is included below for convenience."
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
    printf '%s %s\n' "$intro" "$repeatability" > "$readme_file"

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

main_init() {
    local example_type
    local source_dir
    local target_dir
    local entry
    local name
    local destination
    local line
    local -a entries=()
    local projtool_command
    local settings_file
    local settings_temp
    local target_name
    local creator_name
    local github_url
    local version

    [[ $# -eq 0 ]] && { usage_init; exit 2; }
    [[ "$1" == "-h" || "$1" == "--help" ]] && {
        usage_init
        exit 0
    }
    [[ $# -eq 1 ]] || die "init requires exactly one example type"

    example_type="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    [[ "$example_type" =~ ^[a-z0-9][a-z0-9_-]*$ ]] ||
        die "invalid example type: $1"
    source_dir="$SCRIPT_DIR/examples/$example_type"
    [[ -d "$source_dir" ]] || die "example not found: $example_type"
    target_dir="$(pwd)"
    target_name="$(basename -- "$target_dir")"
    require_command git
    [[ ! -e "$target_dir/.git" ]] || die "working directory is already a Git repository"

    prompt_required "Enter Name: "
    creator_name="$PROMPT_VALUE"
    prompt_required "Enter GitHub URL: "
    github_url="$PROMPT_VALUE"
    prompt_required "Enter Version: "
    version="$PROMPT_VALUE"
    validate_version "$version"

    destination="$target_dir/LICENSE.txt"
    if [[ -e "$destination" || -L "$destination" ]]; then
        die "destination already exists: $destination"
    fi

    while IFS= read -r -d '' entry; do
        name="$(basename -- "$entry")"
        case "$name" in
            .DS_Store|output|README.md|"$example_type.md"|"$example_type.pdf")
                continue
                ;;
        esac
        entries+=("$entry")
    done < <(find "$source_dir" -mindepth 1 -maxdepth 1 -print0)

    for entry in "${entries[@]}"; do
        name="$(basename -- "$entry")"
        if [[ "$name" == "$example_type.tex" ]]; then
            name="${target_name%_template}.tex"
        fi
        destination="$target_dir/$name"
        if [[ -e "$destination" || -L "$destination" ]]; then
            die "destination already exists: $destination"
        fi
    done

    for entry in "${entries[@]}"; do
        name="$(basename -- "$entry")"
        if [[ "$name" == "$example_type.tex" ]]; then
            name="${target_name%_template}.tex"
        fi
        destination="$target_dir/$name"
        cp -R -p -- "$entry" "$destination"
    done

    settings_file="$target_dir/.vscode/settings.json"
    if [[ -f "$settings_file" ]]; then
        settings_temp="$(mktemp "$target_dir/.projtool-settings.XXXXXX")"
        cp -p -- "$settings_file" "$settings_temp"
        projtool_command="$SCRIPT_DIR/projtool.sh"
        projtool_command="${projtool_command//\\/\\\\}"
        projtool_command="${projtool_command//\"/\\\"}"
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" == *'"command": "../../projtool.sh"'* ]]; then
                line="${line%%../../projtool.sh*}$projtool_command${line#*../../projtool.sh}"
            fi
            printf '%s\n' "$line"
        done < "$settings_file" > "$settings_temp"
        mv -f -- "$settings_temp" "$settings_file"
    fi

    write_project_license "$target_dir" "$target_name" "$creator_name" "$github_url"

    (
        cd -- "$target_dir"
        git init
        git add .
        git commit -m "Initialize commit history"
        git branch -M main
        git tag -a "$version" -m "$target_name $version"
        git remote add origin "$github_url"
        git push -u origin main "$version"
    )

    printf '✓ %s initialized in %s\n' "$example_type" "$target_dir"
}

main_cpush() {
    local message=""
    local version=""
    local project_dir
    local project_name
    local current_branch
    local license_file

    [[ $# -eq 0 ]] && { usage_cpush; exit 2; }
    [[ "$1" == "-h" || "$1" == "--help" ]] && {
        usage_cpush
        exit 0
    }

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -m|--message)
                [[ $# -ge 2 ]] || die "missing message after $1"
                message="$2"
                shift 2
                ;;
            -v|--version)
                [[ $# -ge 2 ]] || die "missing version after $1"
                version="$2"
                shift 2
                ;;
            *)
                die "unexpected argument: $1"
                ;;
        esac
    done

    [[ -n "$message" ]] || die "cpush requires -m MESSAGE"
    require_command git
    project_dir="$(git rev-parse --show-toplevel 2>/dev/null)" ||
        die "working directory is not a Git repository"
    project_name="$(basename -- "$project_dir")"
    current_branch="$(git -C "$project_dir" symbolic-ref --short HEAD 2>/dev/null)" ||
        die "cannot cpush from a detached HEAD"
    git -C "$project_dir" remote get-url origin >/dev/null 2>&1 ||
        die "Git remote not found: origin"
    license_file="$project_dir/LICENSE.txt"

    if [[ -n "$version" ]]; then
        validate_version "$version"
        if git -C "$project_dir" rev-parse -q --verify "refs/tags/$version" >/dev/null; then
            die "version tag already exists: $version"
        fi
    fi

    update_license_years "$license_file"
    git -C "$project_dir" add -- LICENSE.txt

    git -C "$project_dir" commit -m "$message"

    if [[ -n "$version" ]]; then
        git -C "$project_dir" tag -a "$version" -m "$project_name $version"
        git -C "$project_dir" push origin "$current_branch" "$version"
    else
        git -C "$project_dir" push origin "$current_branch"
    fi

    printf '✓ changes pushed for %s\n' "$project_name"
}

main_gen() {
    [[ $# -eq 0 ]] && { usage_gen; exit 2; }
    [[ "$1" == "-h" || "$1" == "--help" ]] && { usage_gen; exit 0; }

    ACTION="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    shift
    TARGET="."
    VERBOSE=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--from)
                [[ $# -ge 2 ]] || die "missing target after $1"
                TARGET="$2"
                shift 2
                ;;
            -w|--with)
                [[ $# -ge 2 ]] || die "missing modifier after $1"
                MODIFIER="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
                [[ "$MODIFIER" == "verbose" ]] || die "unsupported modifier: $2"
                VERBOSE=true
                shift 2
                ;;
            *)
                die "unexpected argument: $1"
                ;;
        esac
    done

    case "$ACTION" in
        output|results|media|readme|pdf|md) ;;
        *) die "unsupported action: $ACTION" ;;
    esac

    resolve_target "$TARGET"
    cleanup_source_build_files
    trap 'cleanup_source_build_files' EXIT

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

    SCOPE="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    shift
    TARGET="."
    DEFAULT_TARGET=true

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--from)
                [[ $# -ge 2 ]] || die "missing target after $1"
                TARGET="$2"
                DEFAULT_TARGET=false
                shift 2
                ;;
            *)
                die "unexpected argument: $1"
                ;;
        esac
    done

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

    if [[ "$DEFAULT_TARGET" == true && ! -f "$DOCUMENT_FILE" && ! -f "$RESULTS_SCRIPT" ]]; then
        die "working directory is not a ProjTool project"
    fi

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
    init) main_init "$@" ;;
    cpush) main_cpush "$@" ;;
    gen) main_gen "$@" ;;
    rem) main_rem "$@" ;;
    *)
        printf 'projtool: unsupported command: %s\n' "$MODE" >&2
        usage >&2
        exit 1
        ;;
esac
