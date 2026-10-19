# ``ProjTool``

``ProjTool`` uses LaTeX to initialize, generate, and publish reproducible
research related media in form of `.pdf` or `.md`. At the moment, it supports
the following project types:

- Dissertation
- Note
- Preprint
- Presentation

## Installing and Uninstalling ProjTool

### Dependencies

Before one installs ``ProjTool`` you need the following dependencies.

- [Git](https://git-scm.com/)
- LaTeX distribution that provides `pdflatex`, `latexmk`, and ``Biber``
- [Pandoc](https://pandoc.org/)
- If you want to run the example code, download
[Julia 1.10 or later](https://julialang.org/)

### Install

First, ``cd`` to the proper directory where you want to install ``ProjTool``.
After you have navigated to the desired directory, clone the repository and run
the installer as described below.

```bash
git clone https://github.com/grmacchio/ProjTool.git ProjTool
cd ProjTool
bash install.sh
```

After installation, make sure to open a new terminal so that the ``projtool``
command is available.

### Uninstall

To uninstall ``ProjTool``, navigate to the cloned repository and run:

```bash
bash uninstall.sh
```

After uninstallation, make sure to open a new terminal so that the ``projtool``
command is no longer available.

## Initializing a Project

Create a new directory with the title of your project. For our examples, we
will be using the directory named ``Project``. Throughout what follows we will
be creating a ``note``; however, this can be replaced with any of the other
supported project types mentioned at the beginning of this document. Once you
have created the project directory, you can initialize the project using
the command below.

```bash
projtool init note
```

 After running the aforementioned command the user will be
prompted to provide the creator name, GitHub URL, and initial version, e.g.
``v0.0.0``, for the project. Once the information is provided, the project will
do the following.

- Copy the desired template, in this case ``note``.
- Initialize a ``git`` project with the entered version and GitHub repository.
- Generate a ``LICENSE.txt`` file with an MIT license for the code, a CC BY 4.0
license for the media, and exclusions for any third-party content.

The content copied from the desired template is self explanatory and serves as
a starting point for the project.

## Generating Project Material

To generate project material use the following commands.

| Command | Action |
| --- | --- |
| `projtool gen results` | Run `results.sh` and update `output/results/` |
| `projtool gen pdf` | Generate only the PDF |
| `projtool gen md` | Generate only the Markdown |
| `projtool gen media` | Generate the PDF and Markdown without running code |
| `projtool gen output` | Generate results, PDF, and Markdown |
| `projtool gen readme` | Copy media to project directory and create README |
| `projtool gen all` | Generate output, copy media to project directory, and create README |

To collect all build files, run ``-w verbose`` at the end of any generation
command.

## Committing Project Material

Often one needs to update the ``LICENSE.txt`` dates, commit a version, and push
the current branch. In ``ProjTool``, this is done using the following command.

```bash
projtool cpush -m "Commit message" -v v0.0.0
```

If one does not want to commit a version, just omit everything after ``-v``. To
make an official release, of a specific version go to the "Releases" tab in
your respective GitHub repository after using ``projtool cpush`` with ``-v``.

## Removing Project Material

To remove project material, use the following commands.

| Command | Removes |
| --- | --- |
| `projtool rem results` | `output/results/` |
| `projtool rem pdf` | `output/media/pdf/` |
| `projtool rem md` | `output/media/md/` |
| `projtool rem media` | `output/media/` |
| `projtool rem output` | `output/` |
| `projtool rem readme` | Root `README.md`, PDF, and Markdown files |
| `projtool rem all` | `output/` and root `README.md`, PDF, and Markdown files |


## Important Notes

1. The exclusions provided in ``LICENSE.txt`` are meant to clarify that any
third-party content included in the project is not covered by the project's MIT
or CC BY 4.0 licenses; thus, it is important not to include other peoples
papers, even if it is convenient for the reader. It is recommended one uses a
``_`` in front of any file you want to omit by ``.gitignore``, which is
already set up upon initialization.

## Reference Fields and Formatting

The five supported entry types use the reference conventions in the
[SIADS author instructions](https://epubs.siam.org/siads/instructions-for-authors)
and [SIAM style manual, chapter 15](https://www.siam.org/media/hmbhpgm1/stylemanual-1.pdf).
ProjTool deliberately retains chronological ordering and its parenthesized type
labels; those are customizations, not SIADS requirements.

Every entry needs a title and author, except that an edited book may use an
editor instead of an author. ProjTool checks the following minimum metadata
before generating either PDF or Markdown:

| Type | Label | Additional fields |
| --- | --- | --- |
| @article | (Journal Paper) | journal, year, volume, and pages or eid |
| @book | (Book) | year, publisher, address |
| @misc | (Preprint) | Online: url, doi, or eprint, plus year when available. Institutional: year, institution, address. |
| @phdthesis | (Thesis) | year, school, address |
| @inproceedings | (Conference Paper) | year, booktitle, and publisher or organization |

The example .bib files store full names; their known journal, series, publisher,
and repository abbreviations are applied by the PDF and Markdown formatters.

Use abbreviated journal names in journal or shortjournal. An article number
belongs in eid, without a page prefix. For articles still under review or in
press, pubstate={submitted} or pubstate={inpress} replaces volume, year, and
pages in the displayed reference.

Book and thesis addresses are the publisher and university locations,
respectively. Online preprints do not require institutional details.
An unpublished manuscript may use howpublished={manuscript} with its year;
institutional preprints may include a report number in number.
Keep standalone titles in headline case and protect proper names and acronyms
with braces in article titles. Available DOI links are retained.

For ordinary conference proceedings, address is the conference location;
address and pages are optional. For a paper published in a proceedings book,
use entrysubtype={book}, publisher, address (publisher location), and pages.
Include editor and series details when applicable. For a conference paper
published in a journal, supply journal, volume, and pages or eid; it uses the
journal format while retaining (Conference Paper).

The PDF and Markdown styles retain supplied editions, editors, series, and
links. The aliases date for year, location for address, journaltitle for
journal, and institution for school are also accepted. An institutional
preprint can use organization instead of institution. Missing fields are
reported with the reference key and source file. These checks establish that
metadata is present; authors must still verify its accuracy and journal
abbreviations against the publication.

Pandoc 2.17 or later is required for reference checks in both output formats.
