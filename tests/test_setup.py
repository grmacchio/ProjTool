import contextlib
import io
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "source"))
import configure


class MacSetupTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="projtool-test-")
        self.addCleanup(self.temporary.cleanup)
        self.home = Path(self.temporary.name)
        self.config = self.home / "config/projtool"
        for mocked in (patch.object(configure, "CONFIG", self.config),
                       patch.object(configure, "WINDOWS", False),
                       patch.object(Path, "home", return_value=self.home),
                       patch.dict(os.environ, {"ZDOTDIR": str(self.home)}, clear=False)):
            mocked.start()
            self.addCleanup(mocked.stop)
        self.base = {"executable": "/Library/Frameworks/Python.framework/Versions/3.15/bin/python3",
                     "prefix": "/Library/Frameworks/Python.framework/Versions/3.15",
                     "base_prefix": "/Library/Frameworks/Python.framework/Versions/3.15", "version": [3, 15, 2]}

    def test_base_choice_does_not_create_a_venv(self):
        with patch.object(configure, "inspect_python", return_value=self.base), patch("builtins.input", return_value="base"), patch.object(configure, "run") as run:
            selected = configure.select_environment("standard", self.base["executable"], None)
        self.assertEqual(selected["prefix"], self.base["prefix"])
        self.assertFalse((self.home / ".venvs").exists())
        run.assert_not_called()

    def test_existing_unrelated_directory_is_preserved(self):
        directory = self.home / ".venvs/projtool"
        directory.mkdir(parents=True)
        sentinel = directory / "keep.txt"
        sentinel.write_text("unrelated work")
        with patch.object(configure, "inspect_python", return_value=self.base), patch("builtins.input", return_value="venv"), patch.object(configure, "run") as run:
            with self.assertRaisesRegex(RuntimeError, "not a working venv"):
                configure.select_environment("standard", self.base["executable"], None)
        self.assertEqual(sentinel.read_text(), "unrelated work")
        run.assert_not_called()

    def test_python_update_preserves_julia_selection(self):
        settings = {"root": str(configure.ROOT), "julia": {"channel": "keep-me", "executable": "/opt/juliaup/julia"}}
        configure.save_settings(settings)
        with patch.object(sys, "argv", ["configure.py", "--component", "python", "--provider", "standard", "--python", self.base["executable"]]), patch.object(configure, "select_environment", return_value=dict(self.base, provider="standard")), patch.object(configure, "install_packages"), patch.object(configure, "configure_julia") as julia:
            configure.main()
        self.assertEqual(configure.load_settings()["julia"], settings["julia"])
        julia.assert_not_called()

    def test_julia_selection_launches_the_selected_channel(self):
        launcher_dir = self.home / "juliaup/bin"
        launcher_dir.mkdir(parents=True)
        (launcher_dir / "julia").touch()
        settings = {"root": str(configure.ROOT), "python": dict(self.base, provider="standard")}
        status = " Default Channel Version Update\n----------------------\n * release 1.13.4+0\n   1.13.3 1.13.3+0\n"
        with patch.object(configure, "find_juliaup", return_value=str(launcher_dir / "juliaup")), patch.object(configure, "output", side_effect=[status, "1.13.3"]) as output, patch("builtins.input", side_effect=["invalid", "1.13.3"]), patch.object(configure, "run") as run:
            configure.configure_julia(settings)
        self.assertEqual(output.call_args.args[0][1], "+1.13.3")
        self.assertEqual(run.call_args.args[0][1], "+1.13.3")
        self.assertEqual(configure.load_settings()["python"], settings["python"])
        self.assertEqual(configure.load_settings()["julia"]["channel"], "1.13.3")

    def test_julia_only_does_not_run_python_setup(self):
        settings = {"root": str(configure.ROOT), "python": dict(self.base, provider="standard")}
        configure.save_settings(settings)
        with patch.object(sys, "argv", ["configure.py", "--component", "julia"]), patch.object(configure, "configure_python") as python, patch.object(configure, "configure_julia") as julia:
            configure.main()
        python.assert_not_called()
        julia.assert_called_once()
        self.assertEqual(configure.load_settings()["python"], settings["python"])

    def test_path_registration_is_repeatable_and_quotes_spaces(self):
        root = self.home / "a project with 'quotes'"
        root.mkdir()
        settings = {"root": str(root)}
        with patch.object(configure, "ROOT", root):
            configure.register_command(settings)
            configure.register_command(settings)
        line = (self.config / "path-line").read_text().strip()
        profile = self.home / ".zshrc"
        self.assertEqual(profile.read_text().splitlines().count(line), 1)
        result = subprocess.run(["/bin/zsh", "-fc", '. "$1"; . "$1"; print -r -- "$PATH"', "test", str(profile)], env={"PATH": "/usr/bin:/bin"}, check=True, capture_output=True, text=True)
        self.assertEqual(result.stdout.strip().split(":"), [str(root / "source"), "/usr/bin", "/bin"])

    def test_dependencies_inside_repository_are_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "outside the ProjTool directory"):
            configure.outside_repository(configure.ROOT / ".venv")

    def test_existing_venv_keeps_its_own_python(self):
        prefix = self.home / "existing-venv"
        (prefix / "bin").mkdir(parents=True)
        (prefix / "bin/python").touch()
        (prefix / "pyvenv.cfg").write_text("home = /a/different/python/bin\n")
        existing = dict(self.base, prefix=str(prefix), executable=str(prefix / "bin/python"), base_prefix="/a/different/python", version=[3, 13, 0])
        with patch.object(configure, "inspect_python", side_effect=[self.base, existing]), patch("builtins.input", side_effect=["existing", str(prefix)]), patch.object(configure, "run") as run:
            selected = configure.select_environment("homebrew", self.base["executable"], None)
        self.assertEqual(selected["executable"], existing["executable"])
        self.assertEqual(selected["version"], [3, 13, 0])
        run.assert_not_called()


class ProjToolCommandTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="projtool-command-test-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.project = self.directory / "project with spaces"
        self.project.mkdir()
        self.config = self.directory / "settings/projtool"
        self.config.mkdir(parents=True)
        self.calls = self.directory / "calls.jsonl"
        self.command = configure.ROOT / "source/projtool"
        self.bin = self.directory / "selected binaries"
        self.bin.mkdir()
        recorder = (
            "import json,os,sys; "
            "f=open(os.environ['PROJTOOL_TEST_CALLS'],'a'); "
            "f.write(json.dumps(sys.argv[1:])+'\\n'); f.close(); "
            "sys.exit(23 if '--fail' in sys.argv else 0)"
        )
        for name in ("python", "julia", "conda"):
            executable = self.bin / name
            executable.write_text(f"#!/usr/bin/env bash\nexec {shlex.quote(sys.executable)} -B -c {shlex.quote(recorder)} {name} \"$@\"\n")
            executable.chmod(0o755)
        decoys = self.directory / "unselected binaries"
        decoys.mkdir()
        for name in ("python", "python3", "jupyter", "julia"):
            executable = decoys / name
            executable.write_text("#!/usr/bin/env bash\nprintf 'Unselected runtime used\\n' >&2\nexit 99\n")
            executable.chmod(0o755)
        self.environment = dict(os.environ, XDG_CONFIG_HOME=str(self.config.parent),
                                PROJTOOL_TEST_CALLS=str(self.calls),
                                PATH=str(decoys) + os.pathsep + os.environ["PATH"])
        self.variables = {"PROJTOOL_CONFIG": str(self.config),
                          "PROJTOOL_PYTHON": str(self.bin / "python"),
                          "PROJTOOL_PYTHON_PREFIX": str(self.directory / "selected environment"),
                          "PROJTOOL_CONDA": "",
                          "PROJTOOL_JULIA": str(self.bin / "julia"),
                          "PROJTOOL_JULIA_CHANNEL": "chosen-channel"}

    def run_results(self, script, verbose=True):
        (self.config / "runtime.sh").write_text("".join(f"export {key}={shlex.quote(value)}\n" for key, value in self.variables.items()))
        (self.project / "results.sh").write_text(script)
        arguments = [str(self.command), "gen", "results", "-f", str(self.project)]
        if verbose:
            arguments += ["-w", "verbose"]
        return subprocess.run(arguments, env=self.environment, text=True, capture_output=True)

    def read_calls(self):
        return [json.loads(line) for line in self.calls.read_text().splitlines()]

    def test_saved_runtimes_arguments_and_child_bash(self):
        (self.project / "nested.sh").write_text("python3 'nested argument'\njulia --version\n")
        result = self.run_results(
            'python "a b" \'literal $HOME\' ""\n'
            'python3 --version\n'
            'jupyter --paths\n'
            'jupyter execute --kernel_name=projtool "a notebook.ipynb"\n'
            'julia "code with spaces.jl"\n'
            'bash ./nested.sh\n'
            'printf "%s" "$PATH" > observed-path\n'
            'printf done > completed\n'
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.read_calls(), [
            ["python", "a b", "literal $HOME", ""],
            ["python", "--version"],
            ["python", "-m", "jupyter", "--paths"],
            ["python", str(configure.ROOT / "source/run_notebook.py"), "--kernel_name=projtool", "a notebook.ipynb"],
            ["julia", "+chosen-channel", "code with spaces.jl"],
            ["python", "nested argument"],
            ["julia", "+chosen-channel", "--version"],
        ])
        self.assertEqual((self.project / "completed").read_text(), "done")
        self.assertEqual((self.project / "observed-path").read_text(), self.environment["PATH"])

    def test_conda_forwarding_uses_saved_environment(self):
        self.variables["PROJTOOL_CONDA"] = str(self.bin / "conda")
        result = self.run_results("python3 'a script.py'\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.read_calls(), [["conda", "run", "--no-capture-output", "-p",
                                            self.variables["PROJTOOL_PYTHON_PREFIX"],
                                            self.variables["PROJTOOL_PYTHON"], "a script.py"]])

    def test_runtime_failure_stops_results(self):
        for command in ("python", "python3", "julia", "jupyter"):
            for verbose in (False, True):
                with self.subTest(command=command, verbose=verbose):
                    result = self.run_results(f"{command} --fail\nprintf done > completed\n", verbose=verbose)
                    self.assertEqual(result.returncode, 23, result.stderr)
                    self.assertFalse((self.project / "completed").exists())

    def test_missing_selection_does_not_fall_back_to_path(self):
        self.variables["PROJTOOL_PYTHON"] = ""
        result = self.run_results("python3 --version\n")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Run projtool update python first.", result.stderr)
        self.assertFalse(self.calls.exists())


if __name__ == "__main__":
    with contextlib.redirect_stdout(io.StringIO()):
        unittest.main()
