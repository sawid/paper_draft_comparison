# paper_draft_comparison

Build a **changes PDF** of a LaTeX manuscript between two versions:
an earlier git revision and either your current file or another git revision.
Additions are underlined in blue and deletions struck out in red (latexdiff `UNDERLINE` style),
which is the format journals usually want for a "marked-up" revision.

## Requirements

- MacTeX / TeX Live (provides `latexdiff`, `latexmk`, `pdflatex`)
- `git`, `rsync`
- The manuscript `.tex` must be tracked in a git repository, and the base version must be committed.

## Usage

```bash
./compare_draft.sh <file.tex> [base-ref] [--new <new-ref>] [output.pdf]
```

| Argument | Meaning | Default |
|---|---|---|
| `file.tex` | manuscript tracked in git | required |
| `base-ref` | old side: commit, tag or branch | first commit of the repo |
| `--new <new-ref>` | new side: commit, tag or branch | current file on disk (uncommitted edits included) |
| `output.pdf` | where to write the result | next to the .tex, `<name>_changes_since_<base>.pdf` or, with `--new`, `<name>_changes_<base>_to_<new>.pdf` |

Examples

```bash
# compare against the first commit ("init")
./compare_draft.sh ~/paper/manuscript/main.tex

# compare against a tagged submission
./compare_draft.sh ~/paper/manuscript/main.tex submitted-v1

# compare two commits (commit-1 -> commit-2), working files untouched
./compare_draft.sh ~/paper/manuscript/main.tex a1b2c3d --new e4f5g6h
./compare_draft.sh ~/paper/manuscript/main.tex submitted-v1 --new submitted-v2

# also rebuild the normal PDF in place
ALSO_MAIN=1 ./compare_draft.sh ~/paper/manuscript/main.tex
```

Environment options

- `ALSO_MAIN=1` also compiles the main PDF and writes it next to the .tex (not with `--new`)
- `KEEP_BUILD=1` keeps the temporary build folder for debugging
- `LATEXDIFF_OPTS="..."` passes extra options to latexdiff

## How it works

1. Copies the manuscript folder (figures, `.cls`, `.bst`, `.bib`) to a temporary build folder.
2. Extracts the old `.tex` with `git show <base-ref>:<path>`. The new `.tex` is the file on disk,
   or with `--new` it is read from `git show <new-ref>:<path>` and that revision's tracked files
   (figures, `.bib`, `\input` files) are used, so the PDF matches commit-2 exactly.
   Your working files are never changed.
3. Runs
   `latexdiff --type=UNDERLINE --math-markup=whole --exclude-textcmd="section,subsection,subsubsection" --flatten`.
   Section titles are excluded because markup inside headings breaks compilation,
   and `--flatten` resolves `\input`/`\include`.
4. Compiles with `latexmk` (falls back to pdflatex + bibtex) and reports pages and errors.

## Workflow tip

Commit (or tag) the version you submit, e.g. `git tag submitted-v1`,
then after revising run the script with that tag to produce the response-to-reviewers changes PDF.
