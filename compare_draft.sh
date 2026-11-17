#!/usr/bin/env bash
# compare_draft.sh — build a "changes" PDF of a LaTeX manuscript against an
# earlier git revision, with additions underlined in blue and deletions struck
# out in red (latexdiff UNDERLINE style).
#
# Usage:
#   compare_draft.sh <file.tex> [base-ref] [--new <new-ref>] [output.pdf]
#
#   <file.tex>        manuscript (must be tracked in a git repository)
#   [base-ref]        old side: git commit, tag or branch
#                     (default: the first commit of the repository)
#   [--new <new-ref>] new side: git commit, tag or branch
#                     (default: the current file on disk, uncommitted edits included)
#   [output.pdf]      where to write the result (default, next to the .tex:
#                     <name>_changes_since_<base>.pdf, or
#                     <name>_changes_<base>_to_<new>.pdf with --new)
#
# Options (environment variables):
#   KEEP_BUILD=1      keep the temporary build folder for debugging
#   ALSO_MAIN=1       also rebuild the main PDF of <file.tex> in place
#   LATEXDIFF_OPTS    extra options appended to the latexdiff call
#
# Requirements: git, latexdiff, latexmk (or pdflatex + bibtex), TeX Live/MacTeX.

set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

usage() { sed -n '2,23p' "$0"; exit 1; }

NEW_REF=""
POS=()
while [[ $# -gt 0 ]]; do
  case $1 in
    --new) [[ $# -ge 2 ]] || die "--new needs a git revision"; NEW_REF=$2; shift 2 ;;
    --new=*) NEW_REF=${1#--new=}; shift ;;
    -h|--help) usage ;;
    *) POS+=("$1"); shift ;;
  esac
done
[[ ${#POS[@]} -ge 1 && ${#POS[@]} -le 3 ]] || usage
[[ -z $NEW_REF || ${ALSO_MAIN:-0} != 1 ]] || die "ALSO_MAIN=1 only works without --new"

TEX_IN=${POS[0]}
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

check_ref() {
  git -C "$REPO" rev-parse --verify --quiet "$1^{commit}" >/dev/null \
    || die "unknown git revision: $1"
  git -C "$REPO" cat-file -e "$1:$REL_PATH" 2>/dev/null \
    || die "$REL_PATH does not exist in revision $1"
}

BASE_REF=${POS[1]:-$(git -C "$REPO" rev-list --max-parents=0 HEAD | tail -1)}
check_ref "$BASE_REF"
SHORT_REF=$(git -C "$REPO" rev-parse --short "$BASE_REF")
if [[ -n $NEW_REF ]]; then
  check_ref "$NEW_REF"
  SHORT_NEW=$(git -C "$REPO" rev-parse --short "$NEW_REF")
  DEFAULT_OUT=$TEX_DIR/${STEM}_changes_${SHORT_REF}_to_${SHORT_NEW}.pdf
  NEW_LABEL=$SHORT_NEW
else
  DEFAULT_OUT=$TEX_DIR/${STEM}_changes_since_${SHORT_REF}.pdf
  NEW_LABEL="working copy"
fi
OUT_PDF=${POS[2]:-$DEFAULT_OUT}

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

# With --new, overlay the tracked files (figures, .bib, \input files ...) of
# that revision, so the PDF matches it exactly. Untracked support files such
# as a .cls still come from the working folder.
REL_DIR=$(dirname "$REL_PATH")
if [[ -n $NEW_REF ]]; then
  STRIP=0; [[ $REL_DIR != . ]] && STRIP=$(awk -F/ '{print NF}' <<<"$REL_DIR")
  git -C "$REPO" archive --format=tar "$NEW_REF" -- "$REL_DIR" \
    | tar -x -C "$BUILD" --strip-components="$STRIP"
  git -C "$REPO" show "$NEW_REF:$REL_PATH" > "$BUILD/__new.tex"
else
  cp "$TEX_DIR/$TEX_NAME" "$BUILD/__new.tex"
fi
git -C "$REPO" show "$BASE_REF:$REL_PATH" > "$BUILD/__old.tex"

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
echo "Changes PDF ($SHORT_REF -> $NEW_LABEL): $OUT_PDF"

if [[ ${ALSO_MAIN:-0} == 1 ]]; then
  cp "$TEX_DIR/$TEX_NAME" "$BUILD/$STEM.tex"
  compile "$BUILD" "$STEM"
  report "MAIN" "$BUILD" "$STEM"
  cp "$BUILD/$STEM.pdf" "$TEX_DIR/$STEM.pdf"
  echo "Main PDF: $TEX_DIR/$STEM.pdf"
fi
