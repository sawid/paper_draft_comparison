# paper_draft_comparison

Build a **changes PDF** of a LaTeX manuscript against any earlier git revision.
Additions are underlined in blue and deletions struck out in red (latexdiff `UNDERLINE` style),
which is the format journals usually want for a "marked-up" revision.

## Requirements

- MacTeX / TeX Live (provides `latexdiff`, `latexmk`, `pdflatex`)
- `git`, `rsync`
- The manuscript `.tex` must be tracked in a git repository, and the base version must be committed.

## Usage

```bash
./compare_draft.sh <file.tex> [base-ref] [output.pdf]
```

| Argument | Meaning | Default |
|---|---|---|
| `file.tex` | current manuscript (working copy, uncommitted edits included) | required |
| `base-ref` | commit, tag or branch to compare against | first commit of the repo |
| `output.pdf` | where to write the result | `<name>_changes_since_<ref>.pdf` next to the .tex |

Examples

```bash
# compare against the first commit ("init")
./compare_draft.sh ~/paper/manuscript/main.tex

# compare against a tagged submission
./compare_draft.sh ~/paper/manuscript/main.tex submitted-v1

# also rebuild the normal PDF in place
ALSO_MAIN=1 ./compare_draft.sh ~/paper/manuscript/main.tex
```

Environment options

- `ALSO_MAIN=1` also compiles the main PDF and writes it next to the .tex
- `KEEP_BUILD=1` keeps the temporary build folder for debugging
- `LATEXDIFF_OPTS="..."` passes extra options to latexdiff

## How it works

1. Copies the manuscript folder (figures, `.cls`, `.bst`, `.bib`) to a temporary build folder.
2. Extracts the old `.tex` with `git show <base-ref>:<path>`.
3. Runs
   `latexdiff --type=UNDERLINE --math-markup=whole --exclude-textcmd="section,subsection,subsubsection" --flatten`.
   Section titles are excluded because markup inside headings breaks compilation,
   and `--flatten` resolves `\input`/`\include`.
4. Compiles with `latexmk` (falls back to pdflatex + bibtex) and reports pages and errors.

## Workflow tip

Commit (or tag) the version you submit, e.g. `git tag submitted-v1`,
then after revising run the script with that tag to produce the response-to-reviewers changes PDF.
