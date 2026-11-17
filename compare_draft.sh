#!/usr/bin/env bash
# compare_draft.sh — build a "changes" PDF of a LaTeX manuscript against an
# earlier git revision, with additions underlined in blue and deletions struck
# out in red (latexdiff UNDERLINE style).
#
# Usage:
#   compare_draft.sh <file.tex> [base-ref] [output.pdf]
#
#   <file.tex>    current manuscript (must be inside a git repository)
#   [base-ref]    git commit, tag or branch to compare against
#                 (default: the first commit of the repository)
#   [output.pdf]  where to write the result
#                 (default: <name>_changes_since_<ref>.pdf next to the .tex)
#
# Options (environment variables):
#   KEEP_BUILD=1      keep the temporary build folder for debugging
#   ALSO_MAIN=1       also rebuild the main PDF of <file.tex> in place
#   LATEXDIFF_OPTS    extra options appended to the latexdiff call
#
# Requirements: git, latexdiff, latexmk (or pdflatex + bibtex), TeX Live/MacTeX.

set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

[[ $# -ge 1 ]] || { sed -n '2,20p' "$0"; exit 1; }

TEX_IN=$1
[[ -f $TEX_IN ]] || die "file not found: $TEX_IN"
TEX_DIR=$(cd "$(dirname "$TEX_IN")" && pwd)
TEX_NAME=$(basename "$TEX_IN")
STEM=${TEX_NAME%.tex}

command -v latexdiff >/dev/null || die "latexdiff not found"
command -v git >/dev/null || die "git not found"

REPO=$(git -C "$TEX_DIR" rev-parse --show-toplevel 2>/dev/null) \
  || die "$TEX_DIR is not inside a git repository"
REL_PATH=$(cd "$TEX_DIR" && git ls-files --full-name "$TEX_NAME")
[[ -n $REL_PATH ]] || die "$TEX_NAME is not tracked by git"

BASE_REF=${2:-$(git -C "$REPO" rev-list --max-parents=0 HEAD | tail -1)}
git -C "$REPO" rev-parse --verify --quiet "$BASE_REF^{commit}" >/dev/null \
  || die "unknown git revision: $BASE_REF"
SHORT_REF=$(git -C "$REPO" rev-parse --short "$BASE_REF")
OUT_PDF=${3:-$TEX_DIR/${STEM}_changes_since_${SHORT_REF}.pdf}

compile() {  # compile <dir> <stem>
  local dir=$1 stem=$2
  if command -v latexmk >/dev/null; then
    (cd "$dir" && latexmk -pdf -interaction=nonstopmode -halt-on-error \
       -file-line-error "$stem.tex" >/dev/null 2>&1) || true
  else
    (cd "$dir" && {
      pdflatex -interaction=nonstopmode "$stem.tex" >/dev/null 2>&1 || true
      grep -q '\\bibdata' "$stem.aux" 2>/dev/null && bibtex "$stem" >/dev/null 2>&1 || true
      pdflatex -interaction=nonstopmode "$stem.tex" >/dev/null 2>&1 || true
      pdflatex -interaction=nonstopmode "$stem.tex" >/dev/null 2>&1 || true
    })
  fi
}

report() {  # report <label> <dir> <stem>
  local label=$1 dir=$2 stem=$3 pages errs
  if [[ -f $dir/$stem.pdf ]]; then
    pages=$(grep -a -o 'Output written on .*(\([0-9]*\) page' "$dir/$stem.log" \
            | grep -o '([0-9]*' | tr -d '(' || echo '?')
    errs=$(grep -c '^!' "$dir/$stem.log" || true)
    echo "$label: ${pages:-?} pages, ${errs} errors"
  else
    echo "$label: FAILED (see $dir/$stem.log)"; return 1
  fi
}

BUILD=$(mktemp -d "${TMPDIR:-/tmp}/compare_draft.XXXXXX")
[[ ${KEEP_BUILD:-0} == 1 ]] || trap 'rm -rf "$BUILD"' EXIT

# Copy the source folder (figures, .cls, .bst, .bib ...) without build clutter
# or previously generated output PDFs.
rsync -a --exclude='*.aux' --exclude='*.log' --exclude='*.out' \
  --exclude='*.fdb_latexmk' --exclude='*.fls' --exclude='*.synctex.gz' \
  --exclude="/${STEM}.pdf" --exclude="/${STEM}_changes*" --exclude='.git' \
  "$TEX_DIR/" "$BUILD/"

git -C "$REPO" show "$BASE_REF:$REL_PATH" > "$BUILD/__old.tex"
cp "$TEX_DIR/$TEX_NAME" "$BUILD/__new.tex"

DIFF_STEM=${STEM}_diff
# shellcheck disable=SC2086
latexdiff --type=UNDERLINE --math-markup=whole \
  --exclude-textcmd="section,subsection,subsubsection" \
  --flatten ${LATEXDIFF_OPTS:-} \
  "$BUILD/__old.tex" "$BUILD/__new.tex" > "$BUILD/$DIFF_STEM.tex" 2>"$BUILD/latexdiff.err" \
  || die "latexdiff failed: $(tail -5 "$BUILD/latexdiff.err")"

compile "$BUILD" "$DIFF_STEM"
report "DIFF" "$BUILD" "$DIFF_STEM"
mkdir -p "$(dirname "$OUT_PDF")"
cp "$BUILD/$DIFF_STEM.pdf" "$OUT_PDF"
echo "Changes PDF ($SHORT_REF -> working copy): $OUT_PDF"

if [[ ${ALSO_MAIN:-0} == 1 ]]; then
  cp "$TEX_DIR/$TEX_NAME" "$BUILD/$STEM.tex"
  compile "$BUILD" "$STEM"
  report "MAIN" "$BUILD" "$STEM"
  cp "$BUILD/$STEM.pdf" "$TEX_DIR/$STEM.pdf"
  echo "Main PDF: $TEX_DIR/$STEM.pdf"
fi
