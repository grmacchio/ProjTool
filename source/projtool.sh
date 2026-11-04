#!/usr/bin/env bash

set -Eeuo pipefail

SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJTOOL_DIR="$(cd -- "$SOURCE_DIR/.." && pwd)"
COLLECTION_DIR="$(cd -- "$PROJTOOL_DIR/.." && pwd)"
MODE=""
TEMPLATE_TYPE=""
CITATION_IDS=()
BIBLIOGRAPHY_FILES=()

usage() {
    cat <<'EOF'
Usage: projtool COMMAND ...

Commands:
  init                Initialize the current directory from an example
  cpush               Commit and push project changes
  gpull               Pull the current repository and update its submodules
  gcpush              Check submodules, stage all changes, commit, and push
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

Prompts for the creator name, GitHub URL, and initial version (MAJOR.MINOR.PATCH).
Copies the selected example, including all output contents, into the current directory.
Renames the main TeX file and example-named media files to the project name.
Excludes TYPE.md, TYPE.pdf, README.md, and .DS_Store.
Sets up multiline section folding automatically when VS Code is installed.
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
  projtool cpush -m "Release 0.2.0" -v 0.2.0

Options:
  -m MESSAGE           Commit message
  -v VERSION           Set the version tag as MAJOR.MINOR.PATCH (three integers)

Updates the ending copyright year in LICENSE.txt and stages the license.
Commit other project changes with git add before running cpush. The commit is
pushed to origin together with an annotated version tag. Without -v, the patch
number of the nearest version tag in the current branch's history is increased
by 1 (7.5.3 becomes 7.5.4). Older v-prefixed tags are recognized when finding
the previous version; new tags never have a v prefix. If there is no previous
version tag, specify the first version with -v.
EOF
}

usage_gpull() {
    cat <<'EOF'
Usage: projtool gpull

Runs git pull --ff-only, then git submodule update --init --recursive.
Uses the root of the current Git repository, including when run from a subdirectory.
Submodules are checked out at the commits recorded by the repository and may
be left in detached HEAD state.
EOF
}

usage_gcpush() {
    cat <<'EOF'
Usage: projtool gcpush

Checks every submodule, including nested ones, before staging anything.
Each must be initialized, have no uncommitted or untracked changes, and match
its freshly fetched origin branch. The target is submodule.NAME.branch from
Git configuration or .gitmodules, falling back to origin's default branch.
A branch value of . uses the containing repository's current branch name.

Then runs git add . at the repository root, commits with the message
"Update YYYYMMDDHH" using local time (24-hour HH), and runs
git push --recurse-submodules=check. Each step must succeed before continuing.
If there is nothing to commit, the push is skipped. No version tag is created.
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
  projtool gen all
  projtool gen all -f ./examples/dissertation -w verbose
  projtool gen pdf -f ./examples/dissertation
  projtool gen pdf -f ./examples/dissertation -w verbose
  projtool gen md -f ./examples/dissertation
  projtool gen md -f ./examples/dissertation -w verbose

Actions:
  results             Write results to TARGET/output/results
  media               Generate both PDF and Markdown
  output              Generate results, PDF, and Markdown
  readme              Copy generated media and write TARGET/README.md
  all                 Generate output, copy media, and write TARGET/README.md
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
  projtool rem all
  projtool rem all -f ./examples/dissertation
  projtool rem results
  projtool rem media -f ./examples/dissertation
  projtool rem pdf -f ./examples/dissertation
  projtool rem md -f ./examples/dissertation

Scopes:
  output              Remove TARGET/output
  readme              Remove TARGET/README.md, NAME.pdf, and NAME.md
  all                 Remove output, README.md, NAME.pdf, and NAME.md
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

collect_cited_bibliographies() {
    local bibliography_file
    local citation
    local citation_list
    local document
    local existing_citation
    local found_bibliography
    local pattern='\\genREF[[:space:]]*\{cite\}[[:space:]]*\{([^}]*)\}'
    local seen
    local -a citations=()

    CITATION_IDS=()
    BIBLIOGRAPHY_FILES=()
    document="$(read_document_source)"
    while [[ "$document" =~ $pattern ]]; do
        [[ -n "$REFERENCE_LOCATION" ]] ||
            die "citations require references={REFERENCES_FOLDER} in the documentclass options"
        citation_list="${BASH_REMATCH[1]}"
        citation_list="${citation_list//$'\n'/ }"
        citation_list="${citation_list//$'\r'/ }"
        IFS=',' read -r -a citations <<< "$citation_list"
        for citation in "${citations[@]}"; do
            citation="${citation#"${citation%%[![:space:]]*}"}"
            citation="${citation%"${citation##*[![:space:]]}"}"
            [[ -n "$citation" && "$citation" != */* ]] ||
                die "invalid reference directory name in \\genREF{cite}{$citation_list}"
            seen=false
            if [[ -n "${CITATION_IDS[*]-}" ]]; then
                for existing_citation in "${CITATION_IDS[@]}"; do
                    if [[ "$citation" == "$existing_citation" ]]; then
                        seen=true
                        break
                    fi
                done
            fi
            [[ "$seen" == true ]] && continue
            [[ -d "$REFERENCE_DIR/$citation" ]] ||
                die "reference directory not found for citation: $citation"
            CITATION_IDS+=("$citation")
            found_bibliography=false
            while IFS= read -r -d '' bibliography_file; do
                BIBLIOGRAPHY_FILES+=("$bibliography_file")
                found_bibliography=true
            done < <(
                find "$REFERENCE_DIR/$citation" -type f -name '*.bib' -print0 |
                    LC_ALL=C sort -z
            )
            [[ "$found_bibliography" == true ]] ||
                die "reference file not found for citation: $citation"
        done
        document="${document#*"${BASH_REMATCH[0]}"}"
    done
}

validate_reference_keys() {
    local bibliography_file
    local entry_pattern='^[[:space:]]*@([[:alpha:]]+)[[:space:]]*[{(][[:space:]]*([^,[:space:]}]+)'
    local entry_key
    local entry_type
    local found_reference
    local line
    local line_number
    local reference_id

    [[ -n "${BIBLIOGRAPHY_FILES[*]-}" ]] || return 0
    for bibliography_file in "${BIBLIOGRAPHY_FILES[@]}"; do
        found_reference=false
        line_number=0
        reference_id="$(basename -- "$(dirname -- "$bibliography_file")")"
        while IFS= read -r line || [[ -n "$line" ]]; do
            ((line_number += 1))
            if [[ "$line" =~ $entry_pattern ]]; then
                entry_type="$(printf '%s' "${BASH_REMATCH[1]}" |
                    tr '[:upper:]' '[:lower:]')"
                case "$entry_type" in
                    comment|preamble|string)
                        ;;
                    *)
                        entry_key="${BASH_REMATCH[2]}"
                        [[ "$entry_key" == "$reference_id" ]] ||
                            die "reference key $entry_key in $bibliography_file:$line_number must match directory $reference_id"
                        found_reference=true
                        ;;
                esac
            fi
        done < "$bibliography_file"
        [[ "$found_reference" == true ]] ||
            die "no citeable reference found in $bibliography_file"
    done
}

validate_reference_fields() {
    local bibliography_file
    local -a bibliography_options=()

    [[ -n "${BIBLIOGRAPHY_FILES[*]-}" ]] || return 0
    require_command pandoc
    for bibliography_file in "${BIBLIOGRAPHY_FILES[@]}"; do
        bibliography_options+=(--bibliography="$bibliography_file")
    done
    pandoc --from=markdown --to=plain --fail-if-warnings \
        --lua-filter="$SOURCE_DIR/references.lua" \
        --metadata=reference-check:true \
        "${bibliography_options[@]}" </dev/null >/dev/null
}

read_document_source() {
    awk '
        {
            slashes = 0
            for (i = 1; i <= length($0); i++) {
                character = substr($0, i, 1)
                if (character == "%" && slashes % 2 == 0) {
                    print substr($0, 1, i - 1)
                    next
                }
                slashes = character == "\\" ? slashes + 1 : 0
            }
            print
        }
    ' "$DOCUMENT_FILE"
}

read_document_options() {
    local document
    local pattern='\\documentclass[[:space:]]*\[([^]]*)\][[:space:]]*\{template\}'
    local reference_pattern='^references[[:space:]]*=[[:space:]]*(.*)$'
    local options
    local option=""
    local character
    local depth=0
    local index
    local references_seen=false
    local -a fields=()

    TEMPLATE_TYPE=""
    REFERENCE_LOCATION=""
    document="$(read_document_source)"
    [[ "$document" =~ $pattern ]] ||
        die "expected a template documentclass with a project type"
    options="${BASH_REMATCH[1]},"
    for ((index = 0; index < ${#options}; index++)); do
        character="${options:index:1}"
        case "$character" in
            '{') depth=$((depth + 1)) ;;
            '}') depth=$((depth - 1)) ;;
        esac
        (( depth >= 0 )) || die "unbalanced documentclass options"
        if [[ "$character" == , && $depth -eq 0 ]]; then
            fields+=("$option")
            option=""
        else
            option+="$character"
        fi
    done
    [[ $depth -eq 0 ]] || die "unbalanced documentclass options"
    for option in "${fields[@]}"; do
        option="${option#"${option%%[![:space:]]*}"}"
        option="${option%"${option##*[![:space:]]}"}"
        case "$option" in
            dissertation|note|preprint|presentation)
                [[ -z "$TEMPLATE_TYPE" ]] || die "multiple project types in documentclass options"
                TEMPLATE_TYPE="$option"
                ;;
            *)
                [[ "$option" =~ $reference_pattern ]] || die "unsupported documentclass option: $option"
                [[ "$references_seen" == false ]] || die "duplicate references class option"
                REFERENCE_LOCATION="${BASH_REMATCH[1]}"
                REFERENCE_LOCATION="${REFERENCE_LOCATION%"${REFERENCE_LOCATION##*[![:space:]]}"}"
                if [[ "$REFERENCE_LOCATION" == \{*\} ]]; then
                    REFERENCE_LOCATION="${REFERENCE_LOCATION:1:${#REFERENCE_LOCATION}-2}"
                fi
                [[ -n "$REFERENCE_LOCATION" ]] || die "references folder cannot be empty"
                references_seen=true
                ;;
        esac
    done
    [[ -n "$TEMPLATE_TYPE" ]] || die "missing project type in documentclass options"
}

resolve_reference_directory() {
    local locations="${REFERENCE_LOCATION//$'\n'/ },"
    local location
    local candidate
    local windows_path='^[[:alpha:]]:/'

    REFERENCE_DIR=""
    [[ -n "$REFERENCE_LOCATION" ]] || return 0

    while [[ "$locations" == *,* ]]; do
        location="${locations%%,*}"
        locations="${locations#*,}"
        location="${location#"${location%%[![:space:]]*}"}"
        location="${location%"${location##*[![:space:]]}"}"
        [[ -n "$location" ]] || die "references folder cannot be empty"
        if [[ "$location" == /* || "$location" =~ $windows_path ]]; then
            candidate="$location"
        else
            candidate="$TARGET_DIR/$location"
        fi
        if [[ -z "$REFERENCE_DIR" && -d "$candidate" ]]; then
            REFERENCE_DIR="$(cd -- "$candidate" && pwd)"
        fi
    done
    [[ -n "$REFERENCE_DIR" ]] ||
        die "no references folder found; tried: $REFERENCE_LOCATION"
}

write_pdf_build_config() {
    local bibliography_file
    local config_file="$PDF_OUTPUT_DIR/$DOCUMENT_STEM.projtool.cfg"
    local -a bibliography_options=()

    if command -v cygpath >/dev/null 2>&1; then
        config_file="$(cygpath -m "$config_file")"
    fi

    printf '\\def\\templateReferencesPath{%s}\n' "$REFERENCE_LOCATION" \
        > "$config_file"
    if [[ -n "${BIBLIOGRAPHY_FILES[*]-}" ]]; then
        require_command bibtexu
        for bibliography_file in "${BIBLIOGRAPHY_FILES[@]}"; do
            bibliography_options+=(--bibliography="$bibliography_file")
        done
        pandoc --from=markdown --to=plain --fail-if-warnings \
            --lua-filter="$SOURCE_DIR/references.lua" \
            --metadata="reference-output:$config_file" \
            "${bibliography_options[@]}" </dev/null >/dev/null
    fi
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

    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
        die "invalid version tag: $version; use three nonnegative integers separated by dots (e.g. 0.1.0), without a v prefix"
}

next_version() {
    local project_dir="$1"
    local tag
    local version
    local patch
    local digit
    local suffix=""
    local -a matches=()

    while IFS= read -r tag; do
        if [[ "$tag" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            matches+=(--match "$tag")
        fi
    done < <(git -C "$project_dir" tag --merged HEAD)

    [[ ${#matches[@]} -gt 0 ]] ||
        die "no version tag found in commit history; specify the first version with -v MAJOR.MINOR.PATCH"
    version="$(git -C "$project_dir" describe --tags --abbrev=0 "${matches[@]}" HEAD)" ||
        die "could not determine the previous version tag"
    version="${version#v}"
    patch="${version##*.}"

    while [[ "$patch" == *9 ]]; do
        suffix="0$suffix"
        patch="${patch%?}"
    done
    if [[ -z "$patch" ]]; then
        patch=1
    else
        digit="${patch: -1}"
        patch="${patch%?}$((digit + 1))"
    fi

    printf '%s.%s%s\n' "${version%.*}" "$patch" "$suffix"
}

write_project_license() {
    local target_dir="$1"
    local project_name="$2"
    local creator_name="$3"
    local github_url="$4"
    local license_template="$PROJTOOL_DIR/LICENSE.txt"
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
    rm -f -- "$PDF_OUTPUT_DIR/$DOCUMENT_STEM.projtool.cfg"
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
        export PROJTOOL_NOTEBOOK_RUNNER="$SOURCE_DIR/run_notebook.py"
        jupyter() {
            if [[ "${1:-}" == execute ]]; then
                shift
                command python "$PROJTOOL_NOTEBOOK_RUNNER" "$@"
            else
                command jupyter "$@"
            fi
        }
        export -f jupyter
        if [[ "$VERBOSE" == true ]]; then
            bash -e ./results.sh
        else
            bash -e ./results.sh 2>&1 | sed '/^\[NbClientApp\]/d'
        fi
    )
}

render_pdf() {
    require_command latexmk
    resolve_reference_directory
    collect_cited_bibliographies
    validate_reference_keys
    validate_reference_fields
    mkdir -p -- "$PDF_OUTPUT_DIR"
    if [[ -f "$PDF_OUTPUT_DIR/$DOCUMENT_STEM.bcf" ]]; then
        local extension
        for extension in aux bbl bcf blg fdb_latexmk fls run.xml; do
            rm -f -- "$PDF_OUTPUT_DIR/$DOCUMENT_STEM.$extension"
        done
    fi
    write_pdf_build_config

    if [[ "$VERBOSE" == true ]]; then
        TEXINPUTS="$PDF_OUTPUT_DIR//:$SOURCE_DIR//:${TEXINPUTS:-}" \
            latexmk -pdf -interaction=nonstopmode -halt-on-error \
            -outdir="$PDF_OUTPUT_DIR" "$DOCUMENT_FILE"
    elif ! TEXINPUTS="$PDF_OUTPUT_DIR//:$SOURCE_DIR//:${TEXINPUTS:-}" \
        latexmk -pdf -interaction=nonstopmode -halt-on-error \
        -outdir="$PDF_OUTPUT_DIR" "$DOCUMENT_FILE" >/dev/null 2>&1; then
        die "PDF build failed; rerun with pdf -f TARGET -w verbose for details"
    fi
}

write_markdown_source() {
    awk '
        /\\begin\{(verbatim\*?|Verbatim|lstlisting|minted)\}/ {
            literal = 1
        }
        !literal && /^[[:space:]]*$/ && previous ~ /\\\\[[:blank:]\r]*(%.*)?$/ {
            print "\\par"
        }
        {
            print
            previous = $0
        }
        /\\end\{(verbatim\*?|Verbatim|lstlisting|minted)\}/ {
            literal = 0
        }
    ' "$DOCUMENT_FILE"
}

write_markdown_build_file() {
    local front_command
    local part_command='\newcommand{\genPart}[4]{\subsection{\textbf{LaTeXToPart} \textbf{#2} \textbf{#3} #1}#4}'
    local subpart_command='\newcommand{\genSubPart}[4]{\subsubsection{\textbf{LaTeXToSubPart} \textbf{#2} \textbf{#3} #1}#4}'
    local theorem_command='\newcommand{\genTHM}[6]{\paragraph{\textbf{LaTeXToTheorem} \textbf{#2} \textbf{#3} #1}#4\subparagraph{\textbf{LaTeXToProofStart} \textbf{#5} #1}#6\subparagraph{\textbf{LaTeXToProofEnd}}}'
    local definition_command='\newcommand{\genDEF}[4]{\paragraph{\textbf{LaTeXToDefinition} \textbf{#2} \textbf{#3} #1}#4}'
    local figure_command='\newcommand{\genFIG}[7]{\par\includegraphics[width=#5\textwidth]{#6}\par\paragraph{\textbf{LaTeXToFigure} \textbf{#2} \textbf{#3} #1}#7}'
    local closing_command='\newcommand{\genProofs}{\subsection{\textbf{LaTeXToProofs}}}'
    local presentation_commands=''

    MARKDOWN_BUILD_FILE="$MD_OUTPUT_DIR/$DOCUMENT_STEM.pandoc.tex"

    if [[ "$TEMPLATE_TYPE" == "preprint" ]]; then
        front_command='\newcommand{\genFront}[7]{\subsection{#1}\textbf{Intended Journal:} #2\par\textbf{Authors:} #3\par\textbf{Affiliations:} #4\par\textbf{Date:} #5\par\subsection{Abstract}#6\subsection{Acknowledgments}#7\subsection{\textbf{LaTeXToTOC}}}'
    elif [[ "$TEMPLATE_TYPE" == "note" ]]; then
        front_command='\newcommand{\genFront}[5]{\subsection{#1}\textbf{Authors:} #2\par\textbf{Affiliations:} #3\par\textbf{Date:} #4\par\subsection{Acknowledgments}#5\subsection{\textbf{LaTeXToTOC}}}'
    elif [[ "$TEMPLATE_TYPE" == "presentation" ]]; then
        front_command='\newcommand{\genFront}[5]{\subsection{\textbf{Title}: #1}\textbf{Authors:} #2\par\textbf{Affiliations:} #3\par\textbf{Acknowledgments:} #4\par\textbf{Date:} #5\par\subsection{\textbf{LaTeXToTOC}}}'
        part_command='\newcommand{\genPart}[2]{\subsection{\textbf{LaTeXToPart} \textbf{nonum} \textbf{toc} #1}#2}'
        subpart_command='\newcommand{\genSubPart}[2]{\subsubsection{\textbf{LaTeXToSubPart} \textbf{inh} \textbf{notoc} #1}#2}'
        theorem_command='\newcommand{\genTHM}[2]{\paragraph{\textbf{LaTeXToTheorem} #1}#2}'
        definition_command='\newcommand{\genDEF}[2]{\paragraph{\textbf{LaTeXToDefinition} #1}#2}'
        figure_command='\newcommand{\genFIG}[5]{\par\includegraphics[width=#3\textwidth]{#4}\par\paragraph{\textbf{LaTeXToFigure} #1}#5}'
        closing_command='\newcommand{\startAppendix}{\subsection{\textbf{LaTeXToAppendixTOC}}}'
        presentation_commands='\newcommand{\togglefalse}[1]{}\newcommand{\toggletrue}[1]{}\newcommand{\bo}[2]{\begin{#1}}\newcommand{\eo}[1]{\end{#1}}\newcommand{\bi}[2]{\begin{#1}}\newcommand{\ei}[1]{\end{#1}}\newcommand{\bitem}[1]{\item \textbf{#1}}\newcommand{\iitem}[1]{\item \textit{#1}}'
    else
        front_command='\newcommand{\genFront}[8]{\subsection{#1}\textbf{Author:} #2\par\textbf{University:} #3\par\textbf{Department:} #4\par\textbf{Advisor:} #5\par\textbf{Date:} #6\par\subsection{Abstract}#7\subsection{Acknowledgments}#8\subsection{\textbf{LaTeXToTOC}}}'
    fi

    {
        printf '\\newcommand{\\genDATE}{%s}\n' "$(date '+%Y/%m/%d')"
        printf '%s\n' \
            "$front_command" \
            "$part_command" \
            "$subpart_command" \
            "$theorem_command" \
            "$definition_command" \
            "$figure_command" \
            "$presentation_commands" \
            '\newcommand{\genMATH}[1]{\begin{projtoolmath}\begin{align*}#1\end{align*}\end{projtoolmath}}' \
            '\newcommand{\genLabel}[1]{\tag{#1}\label{projtool-eq:#1}}' \
            '\newcommand{\genREF}[2]{\href{latex-to-ref:#1}{#2}}' \
            "$closing_command"
        if [[ "$TEMPLATE_TYPE" == "presentation" ]]; then
            write_markdown_source |
                sed 's/\\item\[\]/\\item \\textbf{ProjToolEmptyItem}/g'
        else
            write_markdown_source
        fi
    } > "$MARKDOWN_BUILD_FILE"
}

render_md() {
    local md_file="$MD_OUTPUT_DIR/$DOCUMENT_STEM.md"
    local md_temp_file="$MD_OUTPUT_DIR/.$DOCUMENT_STEM.md.tmp"
    local bibliography_entry
    local -a citation_options=()
    local -a template_options=(--metadata="template-type:${TEMPLATE_TYPE:-dissertation}")
    local link_citations=true

    [[ "$TEMPLATE_TYPE" == "presentation" ]] && link_citations=false
    citation_options=(--metadata="link-citations:$link_citations")

    resolve_reference_directory
    collect_cited_bibliographies

    if [[ -n "${BIBLIOGRAPHY_FILES[*]-}" ]]; then
        require_command bibtexu
        for bibliography_entry in "${BIBLIOGRAPHY_FILES[@]}"; do
            citation_options+=(--bibliography="$bibliography_entry")
        done
    fi

    require_command pandoc
    validate_reference_keys
    validate_reference_fields
    mkdir -p -- "$MD_OUTPUT_DIR"
    write_markdown_build_file
    rm -f -- "$md_temp_file"

    if [[ "$VERBOSE" == true ]]; then
        if ! pandoc --from=latex --to=gfm --wrap=none --fail-if-warnings \
            --lua-filter="$SOURCE_DIR/markdown.lua" \
            --lua-filter="$SOURCE_DIR/references.lua" \
            "${template_options[@]}" \
            "${citation_options[@]}" \
            "$MARKDOWN_BUILD_FILE" -o "$md_temp_file"; then
            rm -f -- "$md_temp_file"
            die "Markdown build failed"
        fi
    elif ! pandoc --from=latex --to=gfm --wrap=none \
        --fail-if-warnings --lua-filter="$SOURCE_DIR/markdown.lua" \
        --lua-filter="$SOURCE_DIR/references.lua" \
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
    read_document_options
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

setup_editor_folding() {
    local code_command
    local installed_extensions

    code_command="$(command -v code || true)"
    if [[ -z "$code_command" && -x "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" ]]; then
        code_command="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
    fi
    if [[ -z "$code_command" ]]; then
        printf 'VS Code not found; editor folding setup skipped.\n'
        return
    fi

    installed_extensions="$("$code_command" --list-extensions --show-versions)" ||
        die "could not check VS Code extensions"
    if printf '%s\n' "$installed_extensions" | grep -Fqx 'projtool.projtool-folding@0.1.0'; then
        return
    fi
    "$code_command" --install-extension "$SOURCE_DIR/folding/projtool-folding.vsix" --force ||
        die "could not install VS Code folding support"
}

main_init() {
    local example_type
    local source_dir
    local target_dir
    local entry
    local name
    local destination
    local line
    local media_file
    local -a entries=()
    local target_name
    local project_stem
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
    source_dir="$PROJTOOL_DIR/examples/$example_type"
    [[ -d "$source_dir" ]] || die "example not found: $example_type"
    target_dir="$(pwd)"
    target_name="$(basename -- "$target_dir")"
    project_stem="${target_name%_template}"
    require_command git
    [[ ! -e "$target_dir/.git" ]] || die "working directory is already a Git repository"

    prompt_required "Enter Name: "
    creator_name="$PROMPT_VALUE"
    prompt_required "Enter GitHub URL: "
    github_url="$PROMPT_VALUE"
    prompt_required "Enter Version (MAJOR.MINOR.PATCH): "
    version="$PROMPT_VALUE"
    validate_version "$version"

    destination="$target_dir/LICENSE.txt"
    if [[ -e "$destination" || -L "$destination" ]]; then
        die "destination already exists: $destination"
    fi

    while IFS= read -r -d '' entry; do
        name="$(basename -- "$entry")"
        case "$name" in
            .DS_Store|README.md|"$example_type.md"|"$example_type.pdf")
                continue
                ;;
        esac
        entries+=("$entry")
    done < <(find "$source_dir" -mindepth 1 -maxdepth 1 -print0)

    for entry in "${entries[@]}"; do
        name="$(basename -- "$entry")"
        if [[ "$name" == "$example_type.tex" ]]; then
            name="$project_stem.tex"
        fi
        destination="$target_dir/$name"
        if [[ -e "$destination" || -L "$destination" ]]; then
            die "destination already exists: $destination"
        fi
    done

    setup_editor_folding

    for entry in "${entries[@]}"; do
        name="$(basename -- "$entry")"
        if [[ "$name" == "$example_type.tex" ]]; then
            name="$project_stem.tex"
        fi
        destination="$target_dir/$name"
        cp -R -p -- "$entry" "$destination"
    done

    if [[ "$project_stem" != "$example_type" && -d "$source_dir/output/media" ]]; then
        while IFS= read -r -d '' media_file; do
            name="$(basename -- "$media_file")"
            entry="$target_dir/${media_file#"$source_dir"/}"
            destination="${entry%/*}/$project_stem${name#"$example_type"}"
            if [[ ( -e "$destination" || -L "$destination" ) && ! "$entry" -ef "$destination" ]]; then
                die "destination already exists: $destination"
            fi
            mv -- "$entry" "$destination"
        done < <(find "$source_dir/output/media" \( -type f -o -type l \) \
            -name "$example_type.*" -print0)
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
                validate_version "$version"
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

    if [[ -z "$version" ]]; then
        version="$(next_version "$project_dir")"
    fi
    if git -C "$project_dir" rev-parse -q --verify "refs/tags/$version" >/dev/null; then
        die "version tag already exists: $version"
    fi

    update_license_years "$license_file"
    git -C "$project_dir" add -- LICENSE.txt

    git -C "$project_dir" commit -m "$message"

    git -C "$project_dir" tag -a "$version" -m "$project_name $version"
    git -C "$project_dir" push origin "refs/heads/$current_branch" "refs/tags/$version"

    printf '✓ changes pushed for %s (%s)\n' "$project_name" "$version"
}

check_submodules() {
    local project_dir="$1"
    local submodule_status
    local line

    submodule_status="$(git -C "$project_dir" submodule status --recursive)" ||
        die "could not inspect submodules"
    while IFS= read -r line; do
        case "$line" in
            -*) die "uninitialized submodule: ${line#* }" ;;
            U*) die "conflicted submodule: ${line#* }" ;;
        esac
    done <<< "$submodule_status"

    git -C "$project_dir" submodule foreach --quiet --recursive '
        fail() {
            printf "projtool gcpush: submodule %s: %s\n" "$displaypath" "$*" >&2
            exit 1
        }

        changes=$(git status --porcelain --untracked-files=all --ignore-submodules=none) ||
            fail "could not inspect working directory"
        [ -z "$changes" ] || fail "uncommitted or untracked changes"

        branch=$(git -C "$toplevel" config --get "submodule.$name.branch") ||
            branch=$(git -C "$toplevel" config -f .gitmodules --get "submodule.$name.branch") ||
            branch=""
        case "$branch" in
            .)
                branch=$(git -C "$toplevel" symbolic-ref --quiet --short HEAD) ||
                    fail "branch is . but the containing repository has a detached HEAD"
                ;;
            "")
                remote_head=$(git ls-remote --symref origin HEAD) ||
                    fail "could not query origin"
                branch=$(printf "%s\n" "$remote_head" |
                    while read -r marker ref target; do
                        if [ "$marker" = "ref:" ] && [ "$target" = "HEAD" ] &&
                            [ "$ref" != "${ref#refs/heads/}" ]; then
                            printf "%s\n" "${ref#refs/heads/}"
                            break
                        fi
                    done)
                [ -n "$branch" ] || fail "origin has no default branch; configure submodule.$name.branch"
                ;;
        esac
        git check-ref-format "refs/heads/$branch" >/dev/null ||
            fail "invalid target branch: $branch"
        git fetch --no-recurse-submodules origin "+refs/heads/$branch:refs/remotes/origin/$branch" ||
            fail "could not fetch origin/$branch"
        current=$(git rev-parse --verify HEAD) || fail "could not read HEAD"
        remote=$(git rev-parse --verify "refs/remotes/origin/$branch") ||
            fail "could not read origin/$branch"

        if [ "$current" != "$remote" ]; then
            if git merge-base --is-ancestor "$remote" "$current"; then
                reason="ahead of"
            elif git merge-base --is-ancestor "$current" "$remote"; then
                reason="behind"
            else
                reason="diverged from"
            fi
            fail "$reason origin/$branch"
        fi
    ' || die "submodule checks failed; staging and commit skipped"
}

main_gpull() {
    local project_dir

    if [[ $# -eq 1 && ( "$1" == -h || "$1" == --help ) ]]; then
        usage_gpull
        return
    fi
    [[ $# -eq 0 ]] || die "gpull takes no arguments"
    require_command git
    project_dir="$(git rev-parse --show-toplevel 2>/dev/null)" ||
        die "working directory is not a Git repository"

    git -C "$project_dir" pull --ff-only
    git -C "$project_dir" submodule update --init --recursive
}

main_gcpush() {
    local project_dir
    local timestamp

    if [[ $# -eq 1 && ( "$1" == -h || "$1" == --help ) ]]; then
        usage_gcpush
        return
    fi
    [[ $# -eq 0 ]] || die "gcpush takes no arguments"
    require_command git
    require_command date
    project_dir="$(git rev-parse --show-toplevel 2>/dev/null)" ||
        die "working directory is not a Git repository"
    git -C "$project_dir" symbolic-ref --quiet HEAD >/dev/null ||
        die "cannot gcpush from a detached HEAD"

    check_submodules "$project_dir"
    timestamp="$(date +%Y%m%d%H)" || die "could not determine the current date"
    [[ "$timestamp" =~ ^[0-9]{10}$ ]] || die "invalid date: $timestamp"
    git -C "$project_dir" add .
    git -C "$project_dir" commit -m "Update $timestamp"
    git -C "$project_dir" push --recurse-submodules=check
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
        all|output|results|media|readme|pdf|md) ;;
        *) die "unsupported action: $ACTION" ;;
    esac

    resolve_target "$TARGET"
    cleanup_source_build_files
    trap 'cleanup_source_build_files' EXIT

    case "$ACTION" in
        all|output)
            run_results_stage
            render_media pdf md
            if [[ "$ACTION" == all ]]; then
                write_readme
            fi
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
        all|output) OUTPUT_PATH="output" ;;
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

    if [[ "$SCOPE" != readme ]]; then
        remove_path "$TARGET_DIR/$OUTPUT_PATH"
    fi
    if [[ "$SCOPE" == all || "$SCOPE" == readme ]]; then
        remove_path "$TARGET_DIR/$DOCUMENT_STEM.pdf"
        remove_path "$TARGET_DIR/$DOCUMENT_STEM.md"
        remove_path "$TARGET_DIR/README.md"
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
    gpull) main_gpull "$@" ;;
    gcpush) main_gcpush "$@" ;;
    gen) main_gen "$@" ;;
    rem) main_rem "$@" ;;
    *)
        printf 'projtool: unsupported command: %s\n' "$MODE" >&2
        usage >&2
        exit 1
        ;;
esac
