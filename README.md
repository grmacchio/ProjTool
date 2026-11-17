# ``ProjTool``

``ProjTool`` uses LaTeX to initialize, generate, and publish reproducible
research related media in form of `.pdf` or `.md`. At the moment, it supports
the following project types:

- Dissertation
- Note
- Preprint
- Presentation

## Installing and Uninstalling ProjTool

### Install Commands

Download and extract the zip downloaded from
[ProjTool](https://github.com/grmacchio); alternatively, clone the repository
if Git is already installed. Before running the installer script, we invite
you to take a look at [Install Details](#install-details) before proceeding.

On macOS, open a terminal in the ProjTool directory and run the following and
respond to the prompts as they appear.

```bash
bash Source/Install/install.sh
```

On Windows, open a PowerShell in the ProjTool directory and run the following
and respond to the prompts as they appear.

```powershell
.\Source\Install\install.cmd
```

### Uninstall Commands

On macOS, run this from the ProjTool folder:

```bash
bash Source/Uninstall/uninstall.sh
```

Or, from Windows PowerShell:

```powershell
.\Source\Uninstall\uninstall.cmd
```

The uninstaller asks you to type `DELETE`, then permanently deletes the entire
ProjTool repository, including uncommitted files, and removes its PATH entry and
settings. Python installations, environments, packages, Juliaup, Julia versions,
and shared Julia packages are retained to avoid interfering with unrelated code.
Homebrew, Conda, Git, Pandoc, and TeX distributions are also retained.
Restart terminals and VS Code afterward.

### Install Details

The installer installs or updates
[Git for Windows](https://git-scm.com/install/windows), because ProjTool uses
its Bash shell to run commands:


On macOS, the installer uses Homebrew to install or update Git to its latest
stable release. If Homebrew is missing, it asks permission to download and
install it. Answering `no` denies installation because Homebrew is required
for this Git setup. Existing Homebrew is updated before installing packages.
Apple's Git is left in place; ProjTool uses the updated Homebrew Git.

The installer asks which Python installation to use: ``conda``, ``homebrew``
(macOS only), or ``standard``.

- **Conda:** Choose from the existing Conda environments. If Conda is missing,
  the installer offers the latest stable Miniconda at `~/miniconda3`
  (`%USERPROFILE%\miniconda3` on Windows), verifies its download, and updates
  Conda using its stable default channels. Conda may ask you to accept its
  channel terms and confirm the update. Declining the download returns to
  Python selection. An existing installation is never overwritten.
- **Homebrew:** Install or update Homebrew's stable Python formula, then choose
  an existing virtual environment by path or create the `projtool` virtual
  environment. If needed, the installer asks to download Homebrew first.
- **Standard:** If the standard Python installation, from
  [python.org](https://www.python.org), is missing then the user is asked if
  they would like the installer to download and install Python's newest stable
  version. After, the user is asked to choose its base environment or a virtual
  environment named `projtool` for ProjTool's Python dependencies.

New virtual environments live at
`~/.venvs/projtool` (on Windows, `%USERPROFILE%\.venvs\projtool`). An existing
virtual environment there is reused only when it belongs to the selected Python
installation.

Once Python is dealt with, the installer checks for Juliaup. If it is missing,
the user is asked to download it. Answering `no` denies installation because
Juliaup is required. A new installation uses stable Julia on the `release`
channel; an existing installation lets you choose an installed Juliaup
channel. Your selected channel is used to prepare the example
Julia projects and to run ProjTool results. Choosing an existing channel does
not change Juliaup's global default or update its Julia runtime; use `juliaup
update <Channel>` for that.

Python packages from `Source/Install/Python/python-requirements.txt` and the example Julia
packages are installed or updated in the selected environments. Shared base or
Conda environments will therefore have their packages changed. First-time
downloads and compilation can take several minutes.

The full installer also installs or updates Pandoc to the latest stable release
and tests the available LaTeX distributions by compiling a small document:

- A working TeX Live, MacTeX, or TinyTeX installation is updated from the stable
  TeX Live repository. An older annual release is upgraded alongside the old
  installation. The new release receives ProjTool's required packages and their
  dependencies, without copying the old installation's entire package list.
  The old installation and its local custom files are preserved; ProjTool
  selects the new release after verification. Interrupted annual installations
  can resume using their existing package manager.
- A working MiKTeX installation is updated from its stable package repository.
- If no working distribution is found, the latest stable monthly
  [TinyTeX release](https://github.com/rstudio/tinytex-releases/releases/latest)
  is installed, on either macOS or Windows. An existing directory is preserved
  by using a separate destination when necessary.

The 25 direct TeX requirements come from `Source/Install/TeX/tex-packages.txt`;
TeX also installs their dependencies. TeX Live updates use one resolved mirror
for the whole run and update only these packages and the package manager.
Unrelated installed packages are left alone. The
installer checks Git and Pandoc versions, verifies the required TeX commands,
and compiles all four ProjTool template types before reporting success. A failed
download, update, or check stops setup with an error; completed updates are
not rolled back. Before changing a protected system TeX installation, ProjTool
explains the administrator request. On macOS, enter your administrator login
password when prompted; no characters appear while typing.

The installer adds the repository's `Source/Commands` directory to your user PATH. You can then
use `projtool` from any directory; on Windows, PowerShell, Command Prompt, and
Git Bash are supported. Remember to open a new terminal and fully restart VS
Code after installation. Keep the repository at its installed location.

`Source/Commands/projtool` is the main Bash script. It also contains the Python, Jupyter,
and Julia forwarding functions used by `results.sh` and its child Bash scripts.
These functions use your saved runtime selections during result generation.
Windows starts the same script through `projtool.cmd` and `projtool.ps1`.

Selections and the ProjTool Jupyter kernel are stored in
`${XDG_CONFIG_HOME:-~/.config}/projtool` (`%USERPROFILE%\.config\projtool` on
Windows unless `XDG_CONFIG_HOME` is set). Selected Python and Julia runtimes are
applied when ProjTool runs results; your terminal's Python and Julia defaults
are not switched. The selected Git, Pandoc, and TeX directories are also saved
there so ProjTool can find them in a new terminal.

### Update

```sh
projtool update
projtool update python
projtool update julia
```

The first command repeats Python and Julia selection and updates Git, Pandoc,
and TeX. The other commands repeat
only the named component's setup. Each installs or updates that component's
packages, and saves its new selection. Updating one component preserves the
other component's selection.

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
| `projtool gen results` | Run `results.sh` and update `Output/Results/` |
| `projtool gen pdf` | Generate only the PDF |
| `projtool gen md` | Generate only the Markdown |
| `projtool gen media` | Generate the PDF and Markdown without running code |
| `projtool gen output` | Generate results, PDF, and Markdown |
| `projtool gen readme` | Create README with links to media in `Output/Media/` |
| `projtool gen all` | Generate output and create README |

README generation leaves the PDF and Markdown in `Output/Media/PDF/` and
`Output/Media/MD/`. It includes the Markdown content in `README.md` with image
paths adjusted for the project directory.

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
commas. A single location such as `references={./References}` still works.

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
| `projtool rem results` | `Output/Results/` |
| `projtool rem pdf` | `Output/Media/PDF/` |
| `projtool rem md` | `Output/Media/MD/` |
| `projtool rem media` | `Output/Media/` |
| `projtool rem output` | `Output/` |
| `projtool rem readme` | Root `README.md` |
| `projtool rem all` | `Output/` & root `README.md` |

`projtool rem all` reports `Removing: Output.` and `Removing: README.md.`
before reporting `✓ Done.`.

## Important Notes

1. The exclusions provided in ``LICENSE.txt`` are meant to clarify that any
third-party content included in the project is not covered by the project's MIT
or CC BY 4.0 licenses; thus, it is important not to include other peoples
papers, even if it is convenient for the reader. It is recommended one uses a
``_`` in front of any file you want to omit by ``.gitignore``, which is
already set up upon initialization.
