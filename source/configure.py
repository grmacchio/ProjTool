import argparse
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile

from install_python import inspect_python, install_packages


ROOT = Path(__file__).resolve().parent.parent
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "projtool"
WINDOWS = sys.platform == "win32"


def run(command, **kwargs):
    return subprocess.run([str(item) for item in command], check=True, **kwargs)


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
    install_packages(selected, ROOT / "source/python-requirements.txt", CONFIG)
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
    projects = sorted((ROOT / "examples").glob("*/code/julia/Project.toml"))
    environment = dict(os.environ, JULIA_PKG_GC_AUTO="false")
    run([julia, "+" + channel, "--startup-file=no", ROOT / "source/prepare_julia.jl", channel, *[project.parent for project in projects]], env=environment)
    settings["julia"] = {"executable": str(julia), "channel": channel, "version": version}
    save_settings(settings)


def register_command(settings):
    source = str(ROOT / "source")
    outside_repository(CONFIG)
    if WINDOWS:
        import ctypes
        import winreg
        with winreg.CreateKey(winreg.HKEY_CURRENT_USER, "Environment") as key:
            try:
                value, kind = winreg.QueryValueEx(key, "Path")
            except FileNotFoundError:
                value, kind = "", winreg.REG_EXPAND_SZ
            entries = [part for part in value.split(";") if part]
            if not any(os.path.normcase(os.path.expandvars(part.strip('"')).rstrip("\\/")) == os.path.normcase(source) for part in entries):
                entries.insert(0, source)
                winreg.SetValueEx(key, "Path", 0, kind, ";".join(entries))
        result = ctypes.c_size_t()
        ctypes.windll.user32.SendMessageTimeoutW(65535, 26, 0, "Environment", 2, 5000, ctypes.byref(result))
    else:
        line = f'case ":$PATH:" in *:{shlex.quote(source)}:*) ;; *) export PATH={shlex.quote(source)}:"$PATH" ;; esac'
        profile_home = Path(os.environ.get("ZDOTDIR") or Path.home())
        profiles = [profile_home / ".zprofile", profile_home / ".zshrc", Path.home() / ".bash_profile", Path.home() / ".bashrc", Path.home() / ".profile"]
        for profile in profiles:
            old = profile.read_text(encoding="utf-8") if profile.exists() else ""
            if line not in old.splitlines():
                with profile.open("a", encoding="utf-8") as stream:
                    stream.write(("\n" if old and not old.endswith("\n") else "") + line + "\n")
        atomic_write(CONFIG / "path-line", line + "\n")
        previous = set((CONFIG / "profiles").read_text(encoding="utf-8").splitlines()) if (CONFIG / "profiles").exists() else set()
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
    register_command(settings)


if __name__ == "__main__":
    try:
        main()
    except (EOFError, KeyboardInterrupt):
        print("\nSetup cancelled.", file=sys.stderr)
        sys.exit(130)
    except (RuntimeError, OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"ProjTool setup failed: {error}", file=sys.stderr)
        sys.exit(1)
