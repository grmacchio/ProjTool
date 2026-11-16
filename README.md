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
or clone the repository if Git is already installed. On macOS, open
a terminal in the ProjTool folder and run:

```bash
bash install/mac/install.sh
```

On Windows, open PowerShell in the ProjTool folder and run the command below.
The installer also installs [Git for Windows](https://git-scm.com/install/windows)
if missing, because ProjTool uses its Bash shell to run commands:

```powershell
.\install\windows\install.cmd
```

The installer asks which Python installation to use:

- **Conda:** choose from the existing Conda environments. Missing Conda returns
  you to the installation question; ProjTool does not install Conda.
- **Homebrew (macOS):** choose an existing venv by path or create `projtool`.
  Missing Homebrew returns you to the installation question.
- **Standard:** use Python from [python.org](https://www.python.org). If missing,
  you can download and install its newest stable version. Choose its base
  environment or a venv named `projtool` for ProjTool's Python dependencies.

Python must be 3.10 or newer. New venvs live at `~/.venvs/projtool` (on Windows,
`%USERPROFILE%\.venvs\projtool`). An existing venv there is reused only when it
belongs to the selected Python installation. ProjTool never deletes or rebuilds
an existing environment. Environments must be outside the ProjTool repository.

Next, choose an installed Juliaup channel. If Juliaup is missing, the installer
installs it with stable Julia on the `release` channel. Your selected channel is
used to prepare the example Julia projects and to run ProjTool results. Choosing
an existing channel does not change Juliaup's global default or update its Julia
runtime; use `juliaup update CHANNEL` for that.

Python packages from `source/python-requirements.txt` and the example Julia
packages are installed or updated in the selected environments. Shared base or
Conda environments will therefore have their packages changed. First-time
downloads and compilation can take several minutes. Git, Pandoc, and a working
LaTeX installation are separate prerequisites for the commands that need them
(Git is installed automatically on Windows if missing).

The installer adds the repository's `source` directory to your user PATH. You can then
use `projtool` from any directory; on Windows, PowerShell, Command Prompt, and
Git Bash are supported. Remember to open a new terminal and fully restart VS
Code after installation. Keep the repository at its installed location.

`source/projtool` is the main Bash script. It also contains the Python, Jupyter,
and Julia forwarding functions used by `results.sh` and its child Bash scripts.
These functions use your saved runtime selections during result generation.
Windows starts the same script through `projtool.cmd` and `launch.ps1`.

Selections and the ProjTool Jupyter kernel are stored in
`${XDG_CONFIG_HOME:-~/.config}/projtool` (`%USERPROFILE%\.config\projtool` on
Windows unless `XDG_CONFIG_HOME` is set). Selected Python and Julia runtimes are
applied when ProjTool runs results; your terminal's Python and Julia defaults
are not switched.

### Update

```sh
projtool update
projtool update python
projtool update julia
```

The first command repeats both selection questions. The other commands repeat
only the named component's setup. Each installs or updates that component's
packages, and saves its new selection. Updating one component preserves the
other component's selection.

### Uninstall

On macOS, run this from the ProjTool folder:

```bash
bash uninstall/mac/uninstall.sh
```

Or, from Windows PowerShell:

```powershell
.\uninstall\windows\uninstall.cmd
```

The uninstaller asks you to type `DELETE`, then permanently deletes the entire
ProjTool repository, including uncommitted files, and removes its PATH entry and
settings. Python installations, environments, packages, Juliaup, Julia versions,
and shared Julia packages are retained to avoid interfering with unrelated code.
Restart terminals and VS Code afterward.

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
