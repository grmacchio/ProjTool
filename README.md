# ``ProjTool``

``ProjTool`` uses LaTeX to initialize, generate, and publish reproducible
research related media in form of `.pdf` or `.md`. At the moment, it supports
the following project types:

- Dissertation
- Note
- Preprint
- Presentation

## Installing and Uninstalling ProjTool

### Install

Download and extract
[ProjTool](https://github.com/grmacchio/ProjTool/archive/refs/heads/main.zip),
or clone the repository if Git is already installed. On macOS or Linux, open
a terminal in the ProjTool folder and run:

```bash
bash install/mac/install.sh
```

On Windows, open PowerShell in the ProjTool folder and run the command below.
It also installs Git Bash when needed, so no tools need to be installed
beforehand:

```powershell
.\install\windows\install.cmd
```

The installer installs missing Git, Pandoc, LaTeX, Julia, and Python
dependencies. It prepares the Julia packages and a dedicated Python environment
containing Jupyter, NumPy, and Matplotlib, so `projtool gen all` needs no
manual package setup. First-time downloads and compilation can take several
minutes.

The installer adds a real `projtool` command to your user PATH. You can then
use `projtool` from any directory; on Windows, PowerShell, Command Prompt, and
Git Bash are supported. Remember to open a new terminal and fully restart VS
Code after installation.

### Uninstall

On macOS or Linux, run this from the ProjTool folder:

```bash
bash uninstall/mac/uninstall.sh
```

Or, from Windows PowerShell:

```powershell
.\uninstall\windows\uninstall.cmd
```

The uninstaller removes the ProjTool launcher, its PATH setup, and its
dedicated Python environment. Shared runtimes and the Julia package cache are
retained. Restart terminals and VS Code afterward.

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

When VS Code is installed, `projtool init` automatically sets up multiline
section folding. No separate editor setup is needed.

 After running the aforementioned command the user will be
prompted to provide the creator name, GitHub URL, and initial version, e.g.
``0.0.0``, for the project. Once the information is provided, the project will
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
| `projtool gen all` | Generate output, copy media, and create README |

To collect all build files, run ``-w verbose`` at the end of any generation
command.

## Reference Locations

Set `references` in the main TeX file to one folder or an ordered list of
fallback folders:

```latex
\documentclass[note, references={/Users/name/Library/Mobile Documents/com~apple~CloudDocs/References/Formatted, C:/Users/name/iCloudDrive/References/Formatted}]{template}
```

ProjTool uses the first existing folder for both PDF and Markdown references.
It reports all attempted locations if none exists. Each folder must contain
all cited references; missing citations do not cause a switch to another folder.
Relative paths are resolved from the project directory. Use forward slashes
in Windows paths, preserve spaces in folder names, and separate locations with
commas. A single location such as `references={./references}` still works.

## Committing Project Material

Often one needs to update the ``LICENSE.txt`` dates, commit a version, and push
the current branch. In ``ProjTool``, this is done using the following command.

```bash
projtool cpush -m "Commit message" -v 0.0.0
```

The version must be three nonnegative integers separated by dots, without a
``v`` prefix. Each successful ``cpush`` creates an annotated version tag and
pushes both the current branch and that tag to ``origin``.

Omit ``-v VERSION`` to increase the patch number of the nearest version tag in
the current branch's history by 1. For example, ``7.5.3`` becomes ``7.5.4``:

```bash
projtool cpush -m "Commit message"
```

## Working with a Git Superproject

Run these commands from the git superproject repository. The following command
runs `git pull --ff-only`, followed by `git submodule update --init
--recursive` only if the pull succeeds.

```bash
projtool gpull
```

The following command ensures every submodule is initialized, has no
uncommitted or untracked changes, and matches its fetched remote branch
exactly, then `git add .` is run, the changes are committed, and finally
`git push --recurse-submodules=check` is run.

```bash
projtool gcpush
```

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
| `projtool rem all` | `output/` & root `README.md`, PDF, and Markdown files |

## Important Notes

1. The exclusions provided in ``LICENSE.txt`` are meant to clarify that any
third-party content included in the project is not covered by the project's MIT
or CC BY 4.0 licenses; thus, it is important not to include other peoples
papers, even if it is convenient for the reader. It is recommended one uses a
``_`` in front of any file you want to omit by ``.gitignore``, which is
already set up upon initialization.
