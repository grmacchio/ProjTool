#!/usr/bin/env bash

set -Eeuo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/projtool references.XXXXXX")"
trap 'rm -rf -- "$test_dir"' EXIT
mkdir -p "$test_dir/project" "$test_dir/empty"
cp -R "$project_dir/examples/note/references" "$test_dir/project/first references"
cp -R "$project_dir/examples/note/references" "$test_dir/project/second references"

write_document() {
    printf '\\documentclass[note, references={%s}]{template}\n\\begin{document}\n\\genREF{cite}{2001author, 2002author}\n\\end{document}\n' "$1" > "$test_dir/project/project.tex"
}

build() {
    bash "$project_dir/projtool.sh" gen "${1:-md}" -f "$test_dir/project" > "$test_dir/build.log" 2>&1 || {
        cat "$test_dir/build.log"
        return 1
    }
    grep -q 'ref-2001author' "$test_dir/project/output/media/md/project.md"
    grep -q 'ref-2002author' "$test_dir/project/output/media/md/project.md"
}

expect_failure() {
    if bash "$project_dir/projtool.sh" gen md -f "$test_dir/project" > "$test_dir/build.log" 2>&1; then
        printf 'Unexpected success: %s\n' "$1" >&2
        exit 1
    fi
    grep -Fq "$1" "$test_dir/build.log"
}

write_document './first references'
build
write_document './missing, ./also missing, ./second references'
build media
[[ -s "$test_dir/project/output/media/pdf/project.pdf" ]]
write_document $'./missing,\n    ./first references,\n    ./second references'
build media
write_document "$test_dir/project/first references, ./missing"
build
write_document './missing, ./also missing'
expect_failure 'no references folder found; tried: ./missing, ./also missing'
write_document './first references, '
expect_failure 'references folder cannot be empty'
write_document '../empty, ./first references'
expect_failure 'reference directory not found for citation: 2001author'
write_document 'C:/projtool-nonexistent-references, ./first references'
build
printf 'Reference location tests passed.\n'
