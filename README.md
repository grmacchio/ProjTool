# ``ProjTool``

``ProjTool`` uses LaTeX to initialize, generate, and publish reproducible
research related media in form of `.pdf` or `.md`. At the moment, it supports
the following project types:

- Dissertation
- Note
- Preprint
- Presentation

## The Essentials

### Installing

Download and extract the zip downloaded from
[``ProjTool``](https://github.com/grmacchio); alternatively, clone the
repository if ``Git`` is already installed. Before running the installer
script, we invite you to take a look at [The Details](#the-details) before
proceeding.

On macOS, open a terminal in the ``ProjTool`` directory and run the following
and respond to the prompts as they appear.

```bash
bash Source/Install/install.sh
```

On Windows, open a PowerShell in the ``ProjTool`` directory and run the
following and respond to the prompts as they appear.

```powershell
.\Source\Install\install.cmd
```

### Updating

After installing ProjTool, you can update its configuration by running the
OS-specific installer again. You can also update only ``Python`` or ``Julia``
individually. See the commands below for syntax.

```sh
bash Source/Install/install.sh
bash Source/Install/install.sh python
bash Source/Install/install.sh julia
```

```powershell
.\Source\Install\install.cmd
.\Source\Install\install.cmd python
.\Source\Install\install.cmd julia
```

### Uninstalling

On macOS, run this from the ProjTool folder:

```bash
bash Source/Uninstall/uninstall.sh
```

Or, from Windows PowerShell:

```powershell
.\Source\Uninstall\uninstall.cmd
```

### Initializing a Project

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
``0.0.0``, for the project. Once the information is provided, the project will
do the following.

- Copy the desired template, in this case ``note``.
- Initialize a ``Git`` project with the entered version and GitHub repository.
- Generate a ``LICENSE.txt`` file with an MIT license for the code, a CC BY 4.0
license for the media, and exclusions for any third-party content.

The main ``TeX`` file and copied media files use a lowercase version of the
folder name: An underscore is inserted before a capital following a lowercase
letter or digit, and before a digit following a letter. Consecutive capitals
remain together. For example, ``123StudyNoteHERE123`` produces
``123_study_note_here_123.tex`` and media files with the same base name. A
trailing ``_template`` is removed before applying these rules.

The exclusions provided in ``LICENSE.txt`` are meant to clarify that any
third-party content included in the project is not covered by the project's MIT
or CC BY 4.0 licenses. Regardless, it is important not to include other peoples
papers, even if it is convenient for the reader. It is recommended one uses a
``_`` in front of any file you want to omit by ``.gitignore``, which is
already set up upon initialization.

The content copied from the desired template is self explanatory and serves as
a starting point for the project.

### Referencing

``ProjTool`` allows for one to use a custom reference directory or an ordered
list of fallback directories. The reference structure must follow the format
show in one of the ``References`` directories provided with the example
projects. The SIAM Journal on Applied Dynamical Systems is the default
reference style used in ``ProjTool``. At the top of the ``.tex`` file that
comes with any example project, the reference directory is listed at the top
when specifying the ``\documentclass`` options; See below.

```latex
\documentclass[note, references={./References1, /.../References2}]{template}
```

### Generating Project Material

To generate project material use the following commands.

| Command | Generates |
| --- | --- |
| `projtool gen results` | `Output/Results` |
| `projtool gen pdf` | `Output/Media/PDF` |
| `projtool gen md` | `Output/Media/MD` |
| `projtool gen media` | `Output/Media` |
| `projtool gen output` | `Output` |
| `projtool gen readme` | `README.md` |
| `projtool gen all` | `Output` & `README.md` |

To show the command-line build output, run ``-w verbose`` at the end of any
generation command above.

### Removing Project Material

To remove project material, use the following commands.

| Command | Removes |
| --- | --- |
| `projtool rem results` | `Output/Results` |
| `projtool rem pdf` | `Output/Media/PDF` |
| `projtool rem md` | `Output/Media/MD` |
| `projtool rem media` | `Output/Media` |
| `projtool rem output` | `Output` |
| `projtool rem readme` | `README.md` |
| `projtool rem all` | `Output` & `README.md` |


### Committing, Pushing, and Version Tagging

``ProjTool`` has a command built-in doing three ``Git`` tasks: committing,
pushing, and version tagging. This command has the following forms.

```bash
projtool cpush -m "<Commit-Message>" -v <N.N.N>
projtool cpush -m "<Commit-Message>"
```
The symbols ``<N.N.N>`` represent the version tag, e.g., ``1.2.3``. The second
aforementioned command automatically increase the version by one for the third
number, e.g., ``0.0.0`` will change to ``0.0.1``. Additionally, this command
will update the ``LICENSE.txt`` file with the new dating.

## The Details

### Mac Install Details

The installer uses ``Homebrew`` to install or update Git to its latest stable
release. If ``Homebrew`` is missing, then the installer asks permission to
download and install ``Homebrew``. Answering ``no`` denies installation because
``Homebrew`` is required for this ``Git`` setup. Existing ``Homebrew`` is
updated before installing packages. After installing ``Git``, the installer
proceeds to update/install ``Pandoc``. Finally, the installer asks to update or
install ``TinyTeX`` with all the required packages for ``ProjTool``. If the
user answers ``no``, then the installation is denied because ``TinyTeX`` is
required for ``ProjTool``.

Once ``Git``, ``Pandoc``, and ``TinyTeX`` are installed, the installer will
asks the user which Python installation to use: ``conda``, ``homebrew``, or
``standard``.

- **``Conda``:** Choose from the existing ``Conda`` environments. If ``Conda`` is
  missing, the installer offers the latest stable ``Miniconda`` at
  ``~/miniconda3``, verifies its download, and updates ``Conda`` using its
  stable default channels. ``Conda`` may ask you to accept its channel terms
  and confirm the update. Declining the download returns to ``Python``
  selection. An existing installation is not overwritten.
- **``Homebrew``:** Install or update ``Homebrew``'s stable ``Python`` formula,
  then choose an existing virtual environment by path or create the
  ``projtool`` virtual environment. If needed, the installer asks to download
  ``Homebrew`` first.
- **``Standard``:** If the standard ``Python`` installation, from
  [python.org](https://www.python.org), is missing then the user is asked if
  they would like the installer to download and install ``Python``'s newest
  stable version. After, the user is asked to choose its base environment or a
  virtual environment named ``projtool`` for ``ProjTool``'s ``Python``
  dependencies.

New virtual environments live at `~/.venvs/projtool`. An existing virtual
environment there is reused only when it belongs to the selected ``Python``
installation.

Once ``Python`` is dealt with, the installer checks for ``Juliaup``. If it is
missing, the user is asked to download it. Answering `no` denies installation
because ``Juliaup`` is required. A new installation uses stable Julia on the
``release`` channel; an existing installation lets you choose an installed
``Juliaup`` channel. Your selected channel is used to prepare the example
``Julia`` projects and to run ``ProjTool`` results. Choosing an existing
channel does not change ``Juliaup``'s global default or update its ``Julia``
runtime; use ``juliaup update <Channel>`` for that.

The installer adds the repository's ``Source/Commands`` directory to your user
``PATH``. You can then use ``projtool`` from any directory. Remember to open a
new terminal and fully restart VS Code after installation. Keep the repository
at its installed location. ``Source/Commands/projtool`` is the main ``Bash``
script. It also contains the ``Python``, ``Jupyter``, and ``Julia`` forwarding
functions used by ``results.sh`` and its child ``Bash`` scripts. These
functions use your saved runtime selections during result generation.
Selections and the ``ProjTool Jupyter`` kernel are stored in
``${XDG_CONFIG_HOME:-~/.config}/projtool``.

### Mac Uninstall Details

The uninstaller asks you to type ``DELETE``, then permanently deletes the
entire ``ProjTool`` repository, including uncommitted files, and removes its
``PATH`` entry and settings. ``Python`` installations, environments, packages,
``Juliaup``, ``Julia`` versions, and shared ``Julia`` packages are retained to
avoid interfering with unrelated code. ``Homebrew``, ``Conda``, ``Git``,
``Pandoc``, and ``TinyTeX`` are also retained. Restart terminals and VS Code
afterward.

### Windows Install Details

TBC

### Windows Uninstall Details

TBC

## The Extras 

### Artificial-Intelligence Statement

The artificial-intelligence tools provided by OpenAI were used and all
pertinent chats can be accessed upon request.

### Working With a Git Superproject

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
