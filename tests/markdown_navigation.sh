#!/usr/bin/env bash

set -Eeuo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/projtool navigation.XXXXXX")"
trap 'rm -rf -- "$test_dir"' EXIT
cat > "$test_dir/navigation.tex" <<'TEX'
\documentclass[note]{template}
\begin{document}
\genFront{Navigation}{Author}{Affiliation}{Date}{Thanks}
\genPart{Haller's Group}{num}{toc}{
    \genSubPart{Email}{num}{toc}{First.}
    \genSubPart{Email 2}{num}{toc}{Second.}
    \genSubPart{Email}{num}{toc}{Third.}
}
\genPart{Haller's Group}{num}{toc}{
    \genSubPart{Email}{num}{toc}{Fourth.}
}
\end{document}
TEX
bash "$project_dir/projtool.sh" gen md -f "$test_dir"
markdown="$test_dir/output/media/md/navigation.md"
for identifier in chapter-haller-s-group chapter-haller-s-group-2 section-email section-email-2 section-email-3 section-email-4; do
    grep -Fq "<a id=\"$identifier\"></a>" "$markdown"
done
grep -Fq '](#chapter-haller-s-group-2)' "$markdown"
if grep -q $'\xef\xbf\xbd' "$markdown"; then
    printf 'Malformed UTF-8 in generated navigation.\n' >&2
    exit 1
fi
duplicates="$(sed -n 's/.*<a id="\([^"]*\)".*/\1/p' "$markdown" | LC_ALL=C sort | uniq -d)"
[[ -z "$duplicates" ]]
printf 'Markdown navigation tests passed.\n'
