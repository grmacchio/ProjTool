import argparse
import csv
import hashlib
import io
import json
import lzma
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import tarfile
import urllib.error
import urllib.request
import uuid
import zipfile

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "Source/Install/Python"))
from install_python import inspect_python, install_packages


CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "projtool"
WINDOWS = sys.platform == "win32"
TEX_ADMIN_NOTICE_SHOWN = False


def native_command(command):
    command = [str(item) for item in command]
    if WINDOWS and Path(command[0]).suffix.lower() in (".bat", ".cmd"):
        script = "& " + " ".join("'" + item.replace("'", "''") + "'" for item in command)
        command = ["powershell.exe", "-NoProfile", "-Command", script + "; exit $LASTEXITCODE"]
    return command


def run(command, **kwargs):
    return subprocess.run(native_command(command), check=True, **kwargs)


def output(command):
    return run(command, text=True, capture_output=True).stdout.strip()


def ask(prompt, choices=None):
    while True:
        answer = input(prompt + " ").strip()
        if choices is None or answer.lower() in choices:
            return answer.lower() if choices else answer
        print("Choose " + ", ".join(choices) + ".")


def outside_repository(path):
    resolved = Path(path).resolve()
    if resolved == ROOT or ROOT in resolved.parents:
        raise RuntimeError(f"Keep dependencies outside the ProjTool directory so uninstall preserves them: {path}")
    return resolved


def load_settings():
    settings_file = CONFIG / "config.json"
    if settings_file.exists():
        settings = json.loads(settings_file.read_text(encoding="utf-8"))
        if Path(settings["root"]).resolve() != ROOT:
            raise RuntimeError(f"ProjTool is already configured at {settings['root']}. Run its installer instead.")
        return settings
    return {"root": str(ROOT)}


def atomic_write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent, delete=False) as stream:
        stream.write(content)
        temporary = Path(stream.name)
    temporary.replace(path)


def shell_path(value, settings):
    if not WINDOWS:
        return str(value)
    return output([settings["bash"], "-c", 'cygpath -u "$1"', "projtool", str(value)])


def save_settings(settings):
    atomic_write(CONFIG / "config.json", json.dumps(settings, indent=2) + "\n")
    variables = {"PROJTOOL_CONFIG": shell_path(CONFIG, settings)}
    if settings.get("tool_paths"):
        variables["PROJTOOL_TOOL_PATH"] = ":".join(shell_path(path, settings) for path in settings["tool_paths"])
    if "python" in settings:
        selected = settings["python"]
        variables["PROJTOOL_PYTHON"] = shell_path(selected["executable"], settings)
        variables["PROJTOOL_PYTHON_PREFIX"] = shell_path(selected["prefix"], settings)
        variables["PROJTOOL_CONDA"] = shell_path(selected["conda"], settings) if selected.get("conda") else ""
        atomic_write(CONFIG / "python-executable", selected["executable"] + "\n")
    if "julia" in settings:
        variables["PROJTOOL_JULIA"] = shell_path(settings["julia"]["executable"], settings)
        variables["PROJTOOL_JULIA_CHANNEL"] = settings["julia"]["channel"]
    atomic_write(CONFIG / "runtime.sh", "".join(f"export {key}={shlex.quote(value)}\n" for key, value in variables.items()))


def select_environment(provider, executable, conda):
    if provider == "conda":
        environments = json.loads(output([conda, "env", "list", "--json"]))["envs"]
        if not environments:
            raise RuntimeError("Conda has no environments containing Python.")
        base = output([conda, "info", "--base"])
        print("Available Conda environments:")
        for index, path in enumerate(environments, 1):
            name = "base" if Path(path) == Path(base) else Path(path).name
            print(f"  {index}. {name}: {path}")
        while True:
            answer = ask("Which Conda environment? Enter its number, name, or full path:")
            matches = [path for index, path in enumerate(environments, 1)
                       if answer in (str(index), path, "base" if Path(path) == Path(base) else Path(path).name)]
            if len(matches) == 1:
                prefix = outside_repository(matches[0])
                executable = prefix / ("python.exe" if WINDOWS else "bin/python")
                command = [conda, "run", "--no-capture-output", "-p", str(prefix), str(executable)]
                try:
                    info = inspect_python(executable, command)
                    return dict(info, provider=provider, conda=str(conda))
                except (OSError, RuntimeError, subprocess.CalledProcessError):
                    print("That environment needs a working Python 3.10 or newer. Choose another.")
            else:
                print("Choose one unambiguous environment from the list.")
    base = inspect_python(executable)
    print(f"Python {'.'.join(map(str, base['version']))}: {base['executable']}")
    if provider == "standard":
        choice = ask("Install ProjTool dependencies into the base environment or a venv called projtool? [base/venv]", ("base", "venv"))
        if choice == "base":
            outside_repository(base["prefix"])
            return dict(base, provider=provider)
        choice = "new"
    else:
        choice = ask("Use an existing venv, or create a venv called projtool? [existing/new]", ("existing", "new"))
    default = Path.home() / ".venvs/projtool"
    while True:
        prefix = outside_repository(default if choice == "new" else Path(ask("Full path to the existing venv:")).expanduser())
        target = prefix / ("Scripts/python.exe" if WINDOWS else "bin/python")
        if prefix.exists():
            if not (prefix / "pyvenv.cfg").is_file() or not target.is_file():
                if choice == "new":
                    raise RuntimeError(f"{prefix} exists but is not a working venv. Move it or repair it first; it was not deleted.")
                print("That path is not a working venv.")
                continue
            info = inspect_python(target)
            if info["prefix"] == info["base_prefix"]:
                raise RuntimeError(f"{prefix} does not run as a virtual environment.")
            if choice == "new" and Path(info["base_prefix"]).resolve() != Path(base["base_prefix"]).resolve():
                raise RuntimeError(f"{prefix} uses a different Python installation. Choose a matching venv or move it before creating projtool.")
            print(f"Using existing venv: {prefix}")
        elif choice == "new":
            print(f"Creating venv: {prefix}")
            run([executable, "-m", "venv", prefix])
            info = inspect_python(target)
        else:
            print("That venv does not exist.")
            continue
        return dict(info, provider=provider)


def configure_python(args, settings):
    selected = select_environment(args.provider, args.python, args.conda)
    print(f"Installing Python dependencies into {selected['prefix']}", flush=True)
    install_packages(selected, ROOT / "Source/Install/Python/python-requirements.txt", CONFIG)
    settings["python"] = selected
    save_settings(settings)


def find_juliaup():
    candidates = [shutil.which("juliaup"), str(Path.home() / ".juliaup/bin" / ("juliaup.exe" if WINDOWS else "juliaup"))]
    if WINDOWS:
        candidates.append(str(Path(os.environ["LOCALAPPDATA"]) / "Microsoft/WindowsApps/juliaup.exe"))
    return next((path for path in candidates if path and Path(path).is_file()), None)


def configure_julia(settings):
    juliaup = find_juliaup()
    new_install = juliaup is None
    if new_install:
        choice = ask("Juliaup is required for ProjTool. Download and install Juliaup? [yes/no]", ("yes", "no"))
        if choice == "no":
            raise RuntimeError("Installation denied because Juliaup is required.")
        print("Installing official Juliaup with the stable release channel.", flush=True)
        if WINDOWS:
            if shutil.which("winget"):
                run(["winget", "install", "--id", "9NJNWW8PVKMN", "--exact", "--source", "msstore", "--accept-source-agreements", "--accept-package-agreements"])
            else:
                run(["powershell.exe", "-NoProfile", "-Command", "$ErrorActionPreference = 'Stop'; Add-AppxPackage -AppInstallerFile https://install.julialang.org/Julia.appinstaller"])
        else:
            with tempfile.TemporaryDirectory(prefix="projtool-juliaup-") as temporary:
                installer = Path(temporary) / "install.sh"
                run(["curl", "--fail", "--silent", "--show-error", "--location", "https://install.julialang.org", "--output", installer])
                run(["sh", installer, "--yes", "--default-channel", "release"])
        juliaup = find_juliaup()
        if not juliaup:
            raise RuntimeError("Juliaup was installed but could not be located. Reopen your terminal and rerun the installer.")
    outside_repository(juliaup)
    if os.environ.get("JULIAUP_DEPOT_PATH"):
        outside_repository(os.environ["JULIAUP_DEPOT_PATH"])
    for depot in os.environ.get("JULIA_DEPOT_PATH", "").split(os.pathsep):
        if depot:
            outside_repository(depot)
    julia = Path(juliaup).with_name("julia.exe" if WINDOWS else "julia")
    if not julia.is_file():
        raise RuntimeError(f"Juliaup's Julia launcher is missing: {julia}")
    if new_install:
        run([juliaup, "add", "release"])
        run([juliaup, "default", "release"])
        channel = "release"
    else:
        status = output([juliaup, "status"])
        print("What Julia install would you like to use?\nInstalled Juliaup channels:")
        print(status)
        channels = []
        for line in status.splitlines():
            fields = line.split()
            if fields and fields[0] == "*":
                fields.pop(0)
            if len(fields) >= 2 and fields[0] != "Default" and not set(fields[0]) <= {"-"}:
                channels.append(fields[0])
        if not channels:
            print("No channels are installed. Installing the stable release channel.")
            run([juliaup, "add", "release"])
            channel = "release"
        else:
            while True:
                channel = ask("Enter an installed channel name:")
                if channel in channels:
                    break
                print("Choose one of: " + ", ".join(channels))
    version = output([julia, "+" + channel, "--startup-file=no", "-e", "print(VERSION)"])
    print(f"Preparing Julia {version} using channel {channel}.", flush=True)
    projects = sorted((ROOT / "Examples").glob("*/Code/Julia/Project.toml"))
    if not projects:
        raise RuntimeError("No example Julia projects were found under Examples/*/Code/Julia.")
    environment = dict(os.environ, JULIA_PKG_GC_AUTO="false")
    run([julia, "+" + channel, "--startup-file=no", ROOT / "Source/Install/Julia/prepare_julia.jl", channel, *[project.parent for project in projects]], env=environment)
    settings["julia"] = {"executable": str(julia), "channel": channel, "version": version}
    save_settings(settings)


def fetch(url, with_url=False):
    if not url.startswith("https://"):
        raise RuntimeError("Downloads must use HTTPS.")
    request = urllib.request.Request(url, headers={"User-Agent": "ProjTool-installer"})
    with urllib.request.urlopen(request, timeout=60) as response:
        if not response.url.startswith("https://"):
            raise RuntimeError("Refusing an insecure download redirect.")
        data = response.read()
        return (data, response.url) if with_url else data


def stable_release(repository):
    release = json.loads(fetch(f"https://api.github.com/repos/{repository}/releases/latest"))
    if release.get("draft") or release.get("prerelease") or release["tag_name"] == "daily":
        raise RuntimeError(f"No stable release found for {repository}.")
    return release


def download_asset(repository, release, pattern, directory):
    assets = [asset for asset in release["assets"] if re.fullmatch(pattern, asset["name"])]
    if len(assets) != 1:
        raise RuntimeError(f"Could not select a stable {repository} installer for this platform.")
    asset = assets[0]
    if not asset["browser_download_url"].startswith(f"https://github.com/{repository}/releases/download/"):
        raise RuntimeError("Unexpected release download location.")
    data = fetch(asset["browser_download_url"])
    digest = asset.get("digest") or ""
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", digest) or hashlib.sha256(data).hexdigest() != digest[7:]:
        raise RuntimeError(f"Cannot verify the download checksum for {asset['name']}.")
    path = Path(directory) / asset["name"]
    path.write_bytes(data)
    return path


def use_tool_paths(settings, paths):
    for path in paths:
        outside_repository(path)
    paths = [str(Path(path).absolute()) for path in paths]
    settings["tool_paths"] = list(dict.fromkeys(paths + settings.get("tool_paths", [])))
    os.environ["PATH"] = os.pathsep.join(settings["tool_paths"] + [os.environ.get("PATH", "")])


def executable(directory, name):
    for suffix in ((".exe", ".bat", ".cmd", "") if WINDOWS else ("",)):
        candidate = Path(directory) / (name + suffix)
        if candidate.is_file():
            return candidate
    return None


def configure_pandoc(settings):
    existing = shutil.which("pandoc")
    print("Updating Pandoc." if existing else "Installing Pandoc.", flush=True)
    release = stable_release("jgm/pandoc")
    current = None
    if existing:
        try:
            current = output([existing, "--version"]).splitlines()[0]
        except (OSError, subprocess.SubprocessError, IndexError):
            pass
    if current == "pandoc " + release["tag_name"].lstrip("v"):
        directory = Path(existing).parent
    elif not WINDOWS:
        brew = shutil.which("brew") or next((str(path) for path in (Path("/opt/homebrew/bin/brew"), Path("/usr/local/bin/brew")) if path.is_file()), None)
        if not brew:
            raise RuntimeError("Run the macOS installer to set up Homebrew first.")
        installed = output([brew, "list", "--formula"]).splitlines()
        run([brew, "upgrade" if "pandoc" in installed else "install", "--formula", "pandoc"])
        directory = Path(output([brew, "--prefix", "pandoc"])) / "bin"
    else:
        with tempfile.TemporaryDirectory(prefix="projtool-pandoc-") as temporary:
            installer = download_asset("jgm/pandoc", release, r"pandoc-.*-windows-x86_64\.msi", temporary)
            result = subprocess.run(["msiexec.exe", "/i", str(installer), "/passive", "/norestart"])
            if result.returncode not in (0, 3010):
                raise RuntimeError(f"Pandoc installation exited with code {result.returncode}.")
        candidates = [Path(os.environ["LOCALAPPDATA"]) / "Pandoc", Path(os.environ["ProgramFiles"]) / "Pandoc"]
        if existing:
            candidates.insert(0, Path(existing).parent)
        directory = next((path for path in candidates if executable(path, "pandoc") and
                          output([executable(path, "pandoc"), "--version"]).splitlines()[0] == "pandoc " + release["tag_name"].lstrip("v")), None)
        if directory is None:
            raise RuntimeError("The updated Pandoc executable could not be located.")
    pandoc = executable(directory, "pandoc")
    if not pandoc or output([pandoc, "--version"]).splitlines()[0] != "pandoc " + release["tag_name"].lstrip("v"):
        raise RuntimeError("Pandoc did not reach the latest stable release; check the package manager's available version or pins.")
    use_tool_paths(settings, [directory])
    run([pandoc, "--from=markdown", "--to=html"], input="ProjTool", text=True, capture_output=True)


def tex_directories(settings):
    directories = [Path(path) for path in settings.get("tool_paths", [])]
    current = shutil.which("pdflatex")
    if current:
        directories.append(Path(current).parent)
    if WINDOWS:
        roots = [Path(os.environ.get(name, str(Path.home()))) for name in ("APPDATA", "LOCALAPPDATA", "ProgramData", "ProgramFiles")]
        for root in roots:
            directories.extend([root / "TinyTeX/bin/windows", root / "MiKTeX/miktex/bin/x64", root / "Programs/MiKTeX/miktex/bin/x64"])
        directories.extend(Path(os.environ.get("SystemDrive", "C:") + "/texlive").glob("*/bin/windows"))
    else:
        directories.append(Path("/Library/TeX/texbin"))
        directories.extend((Path.home() / "Library/TinyTeX/bin").glob("*"))
        directories.extend(Path("/usr/local/texlive").glob("*/bin/*"))
    return list(dict.fromkeys(path for path in directories if executable(path, "pdflatex")))


def latex_works(directory, complete=False):
    compiler = executable(directory, "pdflatex")
    if compiler is None:
        return False
    environment = dict(os.environ, PATH=str(directory) + os.pathsep + os.environ.get("PATH", ""))
    environment["TEXINPUTS"] = str(ROOT / "Source/TeX") + "//" + os.pathsep + environment.get("TEXINPUTS", "")
    try:
        version = output([compiler, "--version"])
        flags = ["--disable-installer"] if "MiKTeX" in version else []
        with tempfile.TemporaryDirectory(prefix="projtool-tex-check-") as temporary:
            for kind in (("note", "preprint", "presentation", "dissertation") if complete else ("article",)):
                folder = Path(temporary) / kind
                folder.mkdir()
                (folder / "check.projtool.cfg").write_text(r"\def\templateReferencesPath{.}" + "\n")
                documentclass = r"\documentclass{article}" if kind == "article" else rf"\documentclass[{kind}, references={{.}}]{{template}}"
                body = r"\begin{frame}ProjTool: $x^2$.\end{frame}" if kind == "presentation" else r"ProjTool: $x^2$."
                (folder / "check.tex").write_text(documentclass + "\n" + r"\begin{document}" + body + r"\end{document}" + "\n")
                run([compiler, *flags, "-interaction=nonstopmode", "-halt-on-error", "-no-shell-escape", "check.tex"], cwd=folder, env=environment, capture_output=True, timeout=90)
                if not (folder / "check.pdf").read_bytes().startswith(b"%PDF"):
                    return False
    except (OSError, subprocess.SubprocessError) as error:
        if complete:
            detail = getattr(error, "stdout", b"") or str(error)
            print(detail.decode(errors="replace")[-4000:] if isinstance(detail, bytes) else str(detail)[-4000:], file=sys.stderr)
        return False
    return True


def tex_repository():
    errors = []
    for repository in ("https://mirror.ctan.org/systems/texlive/tlnet", "https://ctan.math.illinois.edu/systems/texlive/tlnet"):
        try:
            suffix = "/tlpkg/texlive.tlpdb.xz"
            data, resolved = fetch(repository + suffix, with_url=True)
            if not resolved.endswith(suffix):
                raise RuntimeError("The TeX Live mirror returned an unexpected database location.")
            database = lzma.decompress(data).decode()
            year = re.search(r"^depend release/(\d{4})$", database, re.MULTILINE)
            if not year:
                raise RuntimeError("The TeX Live repository does not identify a stable release.")
            return resolved[:-len(suffix)], int(year[1])
        except (OSError, ValueError, lzma.LZMAError) as error:
            errors.append(str(error))
    raise RuntimeError("Could not read a stable TeX Live repository: " + "; ".join(errors))


def unpack_tar(archive, destination):
    destination = Path(destination).resolve()
    with tarfile.open(archive) as stream:
        for member in stream.getmembers():
            path = (destination / member.name).resolve()
            if not path.is_relative_to(destination) or member.isdev() or member.isfifo():
                raise RuntimeError("Unsafe path in downloaded archive.")
            if member.issym() or member.islnk():
                parent = path.parent if member.issym() else destination
                if not (parent / member.linkname).resolve().is_relative_to(destination):
                    raise RuntimeError("Unsafe link in downloaded archive.")
        if hasattr(tarfile, "data_filter"):
            stream.extractall(destination, filter="data")
        else:
            stream.extractall(destination)


def unpack_zip(archive, destination):
    destination = Path(destination).resolve()
    with zipfile.ZipFile(archive) as stream:
        for member in stream.infolist():
            path = (destination / member.filename).resolve()
            if not path.is_relative_to(destination) or (member.external_attr >> 16) & 0o170000 == 0o120000:
                raise RuntimeError("Unsafe path in downloaded archive.")
        stream.extractall(destination)


def install_tinytex():
    release = stable_release("rstudio/tinytex-releases")
    default = (Path(os.environ["APPDATA"]) / "TinyTeX") if WINDOWS else (Path.home() / "Library/TinyTeX")
    if WINDOWS and not re.fullmatch(r"[!-~]+", str(default)):
        default = Path(os.environ["ProgramData"]) / "TinyTeX"
    target = outside_repository(default if not default.exists() else default.with_name("TinyTeX-" + release["tag_name"]))
    if target.exists():
        candidates = list((target / "bin").glob("*"))
        working = next((directory for directory in candidates if latex_works(directory)), None)
        if working:
            return working
        target = target.with_name(target.name + "-" + uuid.uuid4().hex[:8])
    print(f"Installing stable TinyTeX {release['tag_name']} at {target}.", flush=True)
    with tempfile.TemporaryDirectory(prefix="projtool-tinytex-") as temporary:
        pattern = r"TinyTeX-1-windows-v.*\.exe" if WINDOWS else r"TinyTeX-1-darwin-v.*\.tar\.xz"
        archive = download_asset("rstudio/tinytex-releases", release, pattern, temporary)
        if WINDOWS:
            run([archive, "-y"], cwd=temporary)
        else:
            unpack_tar(archive, temporary)
        extracted = next((path for path in Path(temporary).iterdir() if path.is_dir() and (path / "tlpkg/texlive.tlpdb").is_file()), None)
        if extracted is None:
            raise RuntimeError("The TinyTeX archive has no TeX Live installation.")
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(extracted), target)
    directory = next((path for path in (target / "bin").iterdir() if executable(path, "tlmgr")), None)
    if directory is None:
        raise RuntimeError("TinyTeX's package manager is missing.")
    return directory


def managed_tex_run(command, directory, **kwargs):
    global TEX_ADMIN_NOTICE_SHOWN
    command = native_command(command)
    if os.access(directory, os.W_OK):
        return run(command, **kwargs)
    if not TEX_ADMIN_NOTICE_SHOWN:
        print(f"Administrator permission is required to change TeX files at {directory}.", flush=True)
        if not WINDOWS:
            print("Enter your Mac administrator login password if prompted. Nothing appears while you type. Press Control+C to cancel.", flush=True)
        else:
            print("Windows will ask you to approve the TeX update.", flush=True)
        TEX_ADMIN_NOTICE_SHOWN = True
    if not WINDOWS:
        return run(["sudo", "-p", "ProjTool: Mac administrator password (typing is hidden): ", *command], **kwargs)
    arguments = subprocess.list2cmdline([str(item) for item in command[1:]])
    quote = lambda value: "'" + str(value).replace("'", "''") + "'"
    launcher = ("$p = Start-Process -FilePath " + quote(command[0]) + " -ArgumentList " + quote(arguments) +
                " -Verb RunAs -Wait -PassThru; exit $p.ExitCode")
    return run(["powershell.exe", "-NoProfile", "-Command", launcher], **kwargs)


def upgrade_texlive_year(directory, root, repository, year):
    updated = None
    if (root / ".tinytex").exists() or "tinytex" in root.name.lower():
        updated = install_tinytex()
        if not re.search(r"TeX Live.*version " + str(year) + r"\b", output([executable(updated, "tlmgr"), "--version"])):
            updated = None
    if updated is None:
        target = root.with_name(str(year)) if root.name.isdigit() else root.with_name(root.name + "-" + str(year))
        outside_repository(target)
        if target.exists():
            updated = next((path for path in (target / "bin").glob("*") if executable(path, "tlmgr") and executable(path, "kpsewhich")), None)
            if updated is None or not (target / "tlpkg/texlive.tlpdb").is_file():
                raise RuntimeError(f"The upgrade destination exists without a usable TeX Live package manager: {target}")
            version = output([executable(updated, "tlmgr"), "--version"])
            actual_root = Path(output([executable(updated, "kpsewhich"), "-var-value=TEXMFROOT"]))
            if not re.search(r"TeX Live.*version " + str(year) + r"\b", version) or actual_root.resolve() != target.resolve():
                raise RuntimeError(f"The existing upgrade destination does not contain TeX Live {year}: {target}")
            print(f"Resuming TeX Live {year} at {target}; only ProjTool's required packages will be installed or updated.", flush=True)
        else:
            print(f"Installing TeX Live {year} at {target} for ProjTool. The older installation at {root} will be kept.", flush=True)
            with tempfile.TemporaryDirectory(prefix="projtool-texlive-") as temporary:
                filename = "install-tl.zip" if WINDOWS else "install-tl-unx.tar.gz"
                archive = Path(temporary) / filename
                archive.write_bytes(fetch(repository + "/" + filename))
                (unpack_zip if WINDOWS else unpack_tar)(archive, temporary)
                installer = next(Path(temporary).glob("install-tl-*/install-tl"), None)
                if installer is None:
                    raise RuntimeError("The TeX Live download has no installer.")
                profile = Path(temporary) / "texlive.profile"
                profile.write_text(f"selected_scheme scheme-infraonly\nTEXDIR {target.as_posix()}\noption_doc 0\noption_src 0\n")
                perl = root / "tlpkg/tlperl/bin/perl.exe" if WINDOWS else Path("/usr/bin/perl")
                if not perl.is_file():
                    raise RuntimeError("Perl is required to upgrade TeX Live to its current annual release.")
                managed_tex_run([perl, installer, "-no-gui", "-profile", profile, "-repository", repository], root.parent)
            updated = next((path for path in (target / "bin").iterdir() if executable(path, "tlmgr")), None)
            if updated is None:
                raise RuntimeError("The upgraded TeX Live package manager is missing.")
    print(f"Preserving the previous TeX installation at {root}.", flush=True)
    manager = executable(updated, "tlmgr")
    old_local = root / "texmf-local"
    new_root = Path(output([executable(updated, "kpsewhich"), "-var-value=TEXMFROOT"]))
    if old_local.is_dir() and old_local.resolve() != (new_root / "texmf-local").resolve():
        if os.access(new_root, os.W_OK):
            shutil.copytree(old_local, new_root / "texmf-local", dirs_exist_ok=True)
        elif WINDOWS:
            quote = lambda value: "'" + str(value).replace("'", "''") + "'"
            script = "$ErrorActionPreference = 'Stop'; Copy-Item -LiteralPath " + quote(old_local) + " -Destination " + quote(new_root) + " -Recurse -Force"
            managed_tex_run(["powershell.exe", "-NoProfile", "-Command", script], new_root)
        else:
            managed_tex_run(["mkdir", "-p", new_root / "texmf-local"], new_root)
            managed_tex_run(["cp", "-R", str(old_local) + "/.", new_root / "texmf-local"], new_root)
        managed_tex_run([manager, "conf", "texmf", "TEXMFLOCAL", new_root / "texmf-local"], updated)
        managed_tex_run([executable(updated, "mktexlsr")], updated)
    return updated


def texlive_packages(manager, repository, requirements):
    platform = output([manager, "print-platform"])
    data = output([manager, "--repository", repository, "info", "--only-remote", "--data", "name,depends"])
    dependencies = {row[0]: row[1].split(":") if len(row) > 1 and row[1] else []
                    for row in csv.reader(io.StringIO(data)) if row}
    pending = list(requirements)
    selected = set()
    while pending:
        name = pending.pop().replace(".ARCH", "." + platform)
        if name in selected:
            continue
        if name.startswith(("scheme-", "collection-")):
            raise RuntimeError(f"Refusing to expand ProjTool's package list to a full TeX collection: {name}")
        if name not in dependencies:
            raise RuntimeError(f"Required TeX package is unavailable from the selected mirror: {name}")
        selected.add(name)
        pending.extend(dependencies[name])
    return sorted(selected)


def configure_tex(settings):
    directory = next((path for path in tex_directories(settings) if latex_works(path)), None)
    if directory is None:
        directory = install_tinytex()
    else:
        print(f"Updating the working TeX distribution at {directory}.", flush=True)
    use_tool_paths(settings, [directory])
    manager = executable(directory, "tlmgr")
    requirements = [line.split("|", 1) for line in (ROOT / "Source/Install/TeX/tex-packages.txt").read_text().splitlines() if line.strip()]
    print(f"Preparing {len(requirements)} ProjTool TeX requirements and their dependencies.", flush=True)
    if manager:
        repository, year = tex_repository()
        print(f"Using one TeX download mirror throughout this update: {repository}", flush=True)
        root = Path(output([executable(directory, "kpsewhich"), "-var-value=TEXMFROOT"]))
        version = output([manager, "--version"])
        match = re.search(r"TeX Live.*version (\d{4})", version)
        if not match:
            raise RuntimeError("Could not determine the installed TeX Live release.")
        if int(match[1]) < year:
            directory = upgrade_texlive_year(directory, root, repository, year)
            use_tool_paths(settings, [directory])
            manager = executable(directory, "tlmgr")
        elif int(match[1]) > year:
            raise RuntimeError("The installed TeX Live release is newer than the stable repository; refusing to downgrade it.")
        managed_tex_run([manager, "--repository", repository, "update", "--self"], directory)
        packages = texlive_packages(manager, repository, [package for package, probe in requirements])
        print(f"Selected {len(packages)} TeX packages, including dependencies. Unrelated installed packages will be left alone.", flush=True)
        for action in ("install", "update"):
            for start in range(0, len(packages), 100):
                managed_tex_run([manager, "--repository", repository, action, *packages[start:start + 100]], directory)
        final_version = output([manager, "--version"])
        if not re.search(r"TeX Live.*version " + str(year) + r"\b", final_version):
            raise RuntimeError("TeX Live did not reach the current stable annual release.")
    else:
        miktex = executable(directory, "miktex")
        mpm = executable(directory, "mpm")
        if not miktex or not mpm:
            raise RuntimeError(f"The working TeX installation at {directory} has no supported update manager.")
        repository = output([mpm, "--repository-release-state=stable", "--pick-repository-url"])
        prefix = [miktex] if os.access(directory, os.W_OK) else [miktex, "--admin"]
        for action in ("update-package-database", "update"):
            managed_tex_run([*prefix, "packages", action, "--repository", repository], directory)
        packages = [package for package, probe in requirements if not probe.startswith("@")]
        managed_tex_run([*prefix, "packages", "install", "--repository", repository, *packages, "latexmk"], directory)
        if not all(executable(directory, name) for name in ("latexmk", "bibtexu")):
            managed_tex_run([*prefix, "packages", "upgrade", "--repository", repository, "complete"], directory)
        managed_tex_run([*prefix, "packages", "check-update", "--repository", repository], directory)
    for name in ("pdflatex", "latexmk", "bibtexu", "kpsewhich"):
        tool = executable(directory, name)
        if not tool:
            raise RuntimeError(f"The TeX installation is missing {name}.")
        run([tool, "--version"], capture_output=True)
    if not latex_works(directory, complete=True):
        raise RuntimeError("The updated TeX distribution cannot compile ProjTool's templates.")
    settings["tex_directory"] = str(directory)


def configure_dependencies(settings):
    git_directory = os.environ.get("PROJTOOL_GIT_BIN")
    if git_directory:
        paths = [git_directory]
        if WINDOWS:
            paths.append(str(Path(git_directory).parent / "usr/bin"))
        use_tool_paths(settings, paths)
    git = shutil.which("git")
    if not git:
        raise RuntimeError("Git is missing. Run the native ProjTool installer first.")
    version = output([git, "--version"])
    if not WINDOWS:
        versions = re.findall(r'href="git-(\d+\.\d+\.\d+)\.tar\.xz"', fetch("https://www.kernel.org/pub/software/scm/git/").decode())
        if not versions:
            raise RuntimeError("Could not determine the latest stable Git release.")
        latest = max(versions, key=lambda value: tuple(map(int, value.split("."))))
        if version != "git version " + latest:
            raise RuntimeError(f"Git {latest} is the latest stable release, but {version} is selected. Homebrew may be pinned or its formula may not yet be updated.")
    print(version, flush=True)
    configure_pandoc(settings)
    configure_tex(settings)
    save_settings(settings)


def register_command(settings):
    source = str(ROOT / "Source/Commands")
    outside_repository(CONFIG)
    if WINDOWS:
        import ctypes
        import winreg
        with winreg.CreateKey(winreg.HKEY_CURRENT_USER, "Environment") as key:
            try:
                value, kind = winreg.QueryValueEx(key, "Path")
            except FileNotFoundError:
                value, kind = "", winreg.REG_EXPAND_SZ
            legacy = os.path.normcase(str(ROOT / "source"))
            entries = [part for part in value.split(";") if part and os.path.normcase(os.path.expandvars(part.strip('"')).rstrip("\\/")) != legacy]
            if not any(os.path.normcase(os.path.expandvars(part.strip('"')).rstrip("\\/")) == os.path.normcase(source) for part in entries):
                entries.insert(0, source)
            if ";".join(entries) != value:
                winreg.SetValueEx(key, "Path", 0, kind, ";".join(entries))
        result = ctypes.c_size_t()
        ctypes.windll.user32.SendMessageTimeoutW(65535, 26, 0, "Environment", 2, 5000, ctypes.byref(result))
    else:
        line = f'case ":$PATH:" in *:{shlex.quote(source)}:*) ;; *) export PATH={shlex.quote(source)}:"$PATH" ;; esac'
        profile_home = Path(os.environ.get("ZDOTDIR") or Path.home())
        profiles = [profile_home / ".zprofile", profile_home / ".zshrc", Path.home() / ".bash_profile", Path.home() / ".bashrc", Path.home() / ".profile"]
        previous = set((CONFIG / "profiles").read_text(encoding="utf-8").splitlines()) if (CONFIG / "profiles").exists() else set()
        old_line = (CONFIG / "path-line").read_text(encoding="utf-8").rstrip("\n") if (CONFIG / "path-line").exists() else ""
        for profile in {Path(path) for path in previous} | set(profiles):
            if old_line and old_line != line and profile.exists():
                text = profile.read_text(encoding="utf-8")
                updated = "".join(part for part in text.splitlines(keepends=True) if part.rstrip("\r\n") != old_line)
                if updated != text:
                    profile.write_text(updated, encoding="utf-8")
        for profile in profiles:
            old = profile.read_text(encoding="utf-8") if profile.exists() else ""
            if line not in old.splitlines():
                with profile.open("a", encoding="utf-8") as stream:
                    stream.write(("\n" if old and not old.endswith("\n") else "") + line + "\n")
        atomic_write(CONFIG / "path-line", line + "\n")
        atomic_write(CONFIG / "profiles", "\n".join(sorted(previous | {str(path) for path in profiles})) + "\n")
    atomic_write(CONFIG / "root", str(ROOT) + "\n")
    save_settings(settings)
    print("ProjTool is configured. Open a new terminal and restart VS Code to use projtool.")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--component", choices=("all", "python", "julia"), default="all")
    parser.add_argument("--provider", choices=("conda", "homebrew", "standard"))
    parser.add_argument("--python")
    parser.add_argument("--conda")
    parser.add_argument("--bash")
    args = parser.parse_args()
    outside_repository(CONFIG)
    settings = load_settings()
    if args.bash:
        settings["bash"] = args.bash
    if args.component in ("all", "python"):
        if not args.provider or not args.python:
            parser.error("Python setup requires --provider and --python.")
        configure_python(args, settings)
    if args.component in ("all", "julia"):
        configure_julia(settings)
    if args.component == "all":
        configure_dependencies(settings)
    register_command(settings)


if __name__ == "__main__":
    try:
        main()
    except (EOFError, KeyboardInterrupt):
        print("\nSetup cancelled.", file=sys.stderr)
        sys.exit(130)
    except (RuntimeError, OSError, ValueError, subprocess.SubprocessError, tarfile.TarError, zipfile.BadZipFile) as error:
        print(f"ProjTool setup failed: {error}", file=sys.stderr)
        sys.exit(1)
