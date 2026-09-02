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

-  Copy the desired template, in this case ``note``.
- Initialize a ``git`` project with the entered version and GitHub repository.
- Generate a ``LICENSE.txt`` file with an MIT license for the code, a CC BY 4.0
license for the media, and exclusions for any third-party content.

The content copied from the desired template is self explanatory and serves as
a starting point for the project.

References use the SIAM Journal on Applied Dynamical Systems format and are
listed chronologically. The supported BibTeX types are `@misc` for preprints,
`@article` for papers, `@book` for books, and `@phdthesis` for theses. Keep each
BibTeX file below `references/`; every rendered entry begins with `(Preprint)`,
`(Paper)`, `(Book)`, or `(Thesis)`.

Use these minimal fields:

- `@article`: `author`, `title`, `journal`, `volume`, `year`, and `pages`
- `@book`: `author`, `title`, `publisher`, `address`, and `year`
- `@misc`: `author`, `title`, `year`, and `url`
- `@phdthesis`: `author`, `title`, `school`, `address`, and `year`

## Generating Project Material

To generate project material use the following commands.

| Command | Action |
| --- | --- |
| `projtool gen results` | Run `results.sh` and update `output/results/` |
| `projtool gen pdf` | Generate only the PDF |
| `projtool gen md` | Generate only the Markdown |
| `projtool gen media` | Generate the PDF and Markdown without running code |
| `projtool gen output` | Generate results, PDF, and Markdown |
| `projtool gen readme` | Publish media and create the project README |

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
| `projtool rem output` | The entire `output/` directory |
| `projtool rem readme` | Root `README.md`, PDF, and Markdown files |


## Important Notes

1. The exclusions provided in ``LICENSE.txt`` are meant to clarify that any
third-party content included in the project is not covered by the project's MIT
or CC BY 4.0 licenses; thus, it is important not to include other peoples
papers, even if it is convenient for the reader. It is recommended one uses a
``_`` in front of any file you want to omit by ``.gitignore``, which is
already set up upon initialization.
