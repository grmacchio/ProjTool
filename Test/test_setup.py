import contextlib
import hashlib
import io
import json
import lzma
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import tarfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Source/Install/Configure"))
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
        invocation = run.call_args.args[0]
        self.assertEqual(invocation[3], configure.ROOT / "Source/Install/Julia/prepare_julia.jl")
        self.assertEqual(set(invocation[5:]), {configure.ROOT / f"Examples/{name}/Code/Julia" for name in ("Dissertation", "Note", "Preprint", "Presentation")})
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

    def test_missing_juliaup_decline_stops_install_after_python(self):
        with patch.object(sys, "argv", ["configure.py", "--provider", "standard", "--python", self.base["executable"]]), patch.object(configure, "configure_python") as python, patch.object(configure, "find_juliaup", return_value=None), patch.object(configure, "run") as run, patch.object(configure, "register_command") as register:
            def decline(prompt):
                python.assert_called_once()
                run.assert_not_called()
                self.assertIn("Juliaup is required", prompt)
                return "no"

            with patch("builtins.input", side_effect=decline):
                with self.assertRaisesRegex(RuntimeError, "Installation denied because Juliaup is required"):
                    configure.main()
            run.assert_not_called()
            register.assert_not_called()

    def test_missing_juliaup_download_requires_explicit_yes(self):
        launcher_dir = self.home / "juliaup/bin"
        launcher_dir.mkdir(parents=True)
        (launcher_dir / "julia").touch()
        juliaup = str(launcher_dir / "juliaup")
        settings = {"root": str(configure.ROOT)}
        answers = iter(("", "maybe", "YES"))
        with patch.object(configure, "find_juliaup", side_effect=[None, juliaup]), patch.object(configure, "output", return_value="1.13.4"), patch.object(configure, "run") as run:
            def consent(prompt):
                run.assert_not_called()
                return next(answers)

            with patch("builtins.input", side_effect=consent) as question:
                configure.configure_julia(settings)
            self.assertEqual(question.call_count, 3)
            self.assertEqual(run.call_args_list[0].args[0][0], "curl")
            self.assertEqual(run.call_args_list[1].args[0][0], "sh")
            self.assertEqual(run.call_args_list[1].args[0][-3:], ["--yes", "--default-channel", "release"])
        self.assertEqual(settings["julia"]["channel"], "release")

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
        self.assertEqual(result.stdout.strip().split(":"), [str(root / "Source/Commands"), "/usr/bin", "/bin"])

    def test_dependencies_inside_repository_are_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "outside the ProjTool directory"):
            configure.outside_repository(configure.ROOT / ".venv")

    def test_path_registration_replaces_previous_location(self):
        root = self.home / "project"
        root.mkdir()
        settings = {"root": str(root)}
        previous_line = f'export PATH={shlex.quote(str(root / "source"))}:"$PATH"'
        self.config.mkdir(parents=True)
        (self.config / "path-line").write_text(previous_line + "\n")
        profile = self.home / ".zshrc"
        profile.write_text('export KEEP_ME=yes\n' + previous_line + '\n')
        (self.config / "profiles").write_text(str(profile) + "\n")
        with patch.object(configure, "ROOT", root):
            configure.register_command(settings)
        self.assertNotIn(previous_line, profile.read_text())
        self.assertIn('export KEEP_ME=yes\n', profile.read_text())
        self.assertIn(str(root / "Source/Commands"), profile.read_text())

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


class DependencySetupTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="projtool-dependencies-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name).resolve()
        for mocked in (patch.object(configure, "WINDOWS", False), patch.object(Path, "home", return_value=self.directory),
                       patch.dict(os.environ, {}, clear=False),
                       patch.object(configure, "run", side_effect=AssertionError("Unmocked external command")),
                       patch.object(configure.urllib.request, "urlopen", side_effect=AssertionError("Unmocked network request"))):
            mocked.start()
            self.addCleanup(mocked.stop)

    def tools(self, directory, windows=False):
        directory.mkdir(parents=True, exist_ok=True)
        for name in ("pdflatex", "latexmk", "bibtexu", "kpsewhich", "tlmgr", "mktexlsr"):
            suffix = ".bat" if windows and name == "tlmgr" else ".exe" if windows else ""
            (directory / (name + suffix)).touch()
        return directory

    def tinytex(self, root, windows=False):
        directory = self.tools(root / "bin" / ("windows" if windows else "universal-darwin"), windows)
        (root / "tlpkg").mkdir(exist_ok=True)
        (root / "tlpkg/texlive.tlpdb").touch()
        (root / ".tinytex").touch()
        return directory

    @contextlib.contextmanager
    def tex_update(self, windows=False, query=None, works=True):
        with contextlib.ExitStack() as stack:
            for mocked in (patch.object(configure, "WINDOWS", windows),
                           patch.dict(os.environ, {name: str(self.directory) for name in ("APPDATA", "LOCALAPPDATA", "ProgramData")}),
                           patch.object(configure.shutil, "which", return_value=None),
                           patch("builtins.input", return_value="yes"),
                           patch.object(configure, "tex_repository", return_value=("https://one-mirror.invalid/tlnet", 2026)),
                           patch.object(configure, "output", side_effect=query or (lambda command: "TeX Live version 2026" if "--version" in command else "/found/package.sty")),
                           patch.object(configure, "run"),
                           patch.object(configure, "latex_works", return_value=works)):
                stack.enter_context(mocked)
            updates = stack.enter_context(patch.object(configure, "managed_tex_run"))
            packages = stack.enter_context(patch.object(configure, "texlive_packages", return_value=["latex-bin", "latexmk", "ec"]))
            yield updates, packages

    def test_tinytex_decline_stops_setup_on_both_platforms_before_tex_actions(self):
        for windows in (False, True):
            with self.subTest(windows=windows), patch.object(configure, "WINDOWS", windows), patch.object(sys, "argv", ["configure.py", "--provider", "standard", "--python", "/fake/python"]), patch.object(configure, "load_settings", return_value={}), patch.object(configure, "configure_python"), patch.object(configure, "configure_julia"), patch.object(configure, "configure_pandoc"), patch.object(configure.shutil, "which", return_value="/fake/git"), patch.object(configure, "output", return_value="git version 2.56.1"), patch.object(configure, "fetch", return_value=b'<a href="git-2.56.1.tar.xz">stable</a>'), patch.object(configure, "tex_repository") as repository, patch.object(configure, "tinytex_directories") as discover, patch.object(configure, "install_tinytex") as install, patch.object(configure, "save_settings") as save, patch.object(configure, "register_command") as register, patch("builtins.input", return_value="no") as answer:
                with self.assertRaisesRegex(RuntimeError, "Installation denied because TinyTeX is required for ProjTool"):
                    configure.main()
                self.assertIn("Install or update TinyTeX with all required ProjTool packages?", answer.call_args.args[0])
                for action in (repository, discover, install, save, register):
                    action.assert_not_called()

    def test_tinytex_requires_explicit_yes(self):
        with self.tex_update(), patch("builtins.input", side_effect=["", "maybe", "NO"]) as answer, patch.object(configure, "tex_repository") as repository:
            with self.assertRaisesRegex(RuntimeError, "Installation denied"):
                configure.configure_tex({})
        self.assertEqual(answer.call_count, 3)
        repository.assert_not_called()

    def test_fresh_and_existing_tinytex_install_all_requirements_on_both_platforms(self):
        for windows in (False, True):
            for existing in (False, True):
                with self.subTest(windows=windows, existing=existing), self.tex_update(windows) as (updates, packages):
                    root = self.directory / f"selected-{windows}-{existing}"
                    directory = self.tinytex(root, windows)
                    settings = {"tex_directory": str(directory)} if existing else {}
                    with patch.object(configure, "install_tinytex", return_value=directory) as install:
                        configure.configure_tex(settings)
                    self.assertEqual(install.call_count, int(not existing))
                    commands = [call.args[0] for call in updates.call_args_list]
                    self.assertEqual(commands[0][-2:], ["update", "--self"])
                    self.assertEqual(commands[1][3:], ["install", "latex-bin", "latexmk", "ec"])
                    self.assertEqual(commands[2][3:], ["update", "latex-bin", "latexmk", "ec"])
                    self.assertTrue(all(command[2] == "https://one-mirror.invalid/tlnet" for command in commands))
                    self.assertFalse(any("--all" in command for command in commands))
                    requirements = [line.split("|")[0] for line in (configure.ROOT / "Source/Install/TeX/tex-packages.txt").read_text().splitlines()]
                    self.assertEqual(packages.call_args.args[2], requirements)
                    configure.latex_works.assert_called_once_with(directory, complete=True)
                    self.assertEqual(settings["tex_directory"], str(directory))
                    self.assertEqual(settings["tool_paths"][0], str(directory))

    def test_texlive_and_miktex_are_not_used_in_place_of_tinytex(self):
        for windows in (False, True):
            with self.subTest(windows=windows), self.tex_update(windows):
                generic = self.tools(self.directory / f"texlive-{windows}/2026/bin/native", windows)
                (generic.parents[1] / "tlpkg").mkdir()
                (generic.parents[1] / "tlpkg/texlive.tlpdb").touch()
                miktex = self.tools(self.directory / f"MiKTeX-{windows}/bin/native", windows)
                directory = self.tinytex(self.directory / f"new-tinytex-{windows}", windows)
                settings = {"tex_directory": str(generic), "tool_paths": [str(generic), str(miktex)]}
                with patch.object(configure.shutil, "which", return_value=str(configure.executable(generic, "tlmgr"))), patch.object(configure, "install_tinytex", return_value=directory) as install:
                    configure.configure_tex(settings)
                install.assert_called_once()
                self.assertEqual(settings["tex_directory"], str(directory))
                self.assertTrue(configure.executable(generic, "pdflatex").is_file())

    def test_older_tinytex_uses_new_bundle_and_preserves_previous_files(self):
        for windows in (False, True):
            old = self.tinytex(self.directory / f"old-{windows}", windows)
            new = self.tinytex(self.directory / f"new-{windows}", windows)
            keep = old.parents[1] / "custom.sty"
            keep.write_text("custom content")
            def query(command):
                if "--version" in command:
                    return "TeX Live version " + ("2025" if Path(command[0]).parent == old else "2026")
                return "/found/package.sty"
            with self.subTest(windows=windows), self.tex_update(windows, query), patch.object(configure, "install_tinytex", return_value=new) as install:
                settings = {"tex_directory": str(old)}
                configure.configure_tex(settings)
            install.assert_called_once()
            self.assertEqual(settings["tex_directory"], str(new))
            self.assertEqual(keep.read_text(), "custom content")

    def test_newer_tinytex_is_not_downgraded(self):
        directory = self.tinytex(self.directory / "future")
        with self.tex_update(query=lambda command: "TeX Live version 2027") as (updates, packages), patch.object(configure, "install_tinytex") as install:
            with self.assertRaisesRegex(RuntimeError, "refusing to downgrade"):
                configure.configure_tex({"tex_directory": str(directory)})
        install.assert_not_called()
        updates.assert_not_called()

    def test_incompatible_stable_bundle_stops_before_package_updates(self):
        directory = self.tinytex(self.directory / "release")
        with self.tex_update(query=lambda command: "TeX Live version 2025") as (updates, packages), patch.object(configure, "install_tinytex", return_value=directory):
            with self.assertRaisesRegex(RuntimeError, "matching TinyTeX release"):
                configure.configure_tex({})
        updates.assert_not_called()

    def test_failed_compile_missing_fonts_and_failed_update_prevent_success(self):
        directory = self.tinytex(self.directory / "failure")
        for failure, message in (("compile", "cannot compile"), ("font", "ecrm2074.tfm"), ("update", "download failed")):
            def query(command):
                if failure == "font" and command[-1] == "ecrm2074.tfm":
                    return ""
                return "TeX Live version 2026" if "--version" in command else "/found/package.sty"
            with self.subTest(failure=failure), self.tex_update(query=query, works=failure != "compile") as (updates, packages), patch.object(configure, "install_tinytex", return_value=directory):
                if failure == "update":
                    updates.side_effect = RuntimeError("download failed")
                settings = {}
                with self.assertRaisesRegex(RuntimeError, message):
                    configure.configure_tex(settings)
                self.assertNotIn("tex_directory", settings)

    def test_tinytex_discovery_finds_default_custom_and_versioned_roots(self):
        for windows in (False, True):
            with self.subTest(windows=windows), self.tex_update(windows):
                parent = self.directory if windows else self.directory / "Library"
                default = self.tinytex(parent / "TinyTeX", windows)
                versioned = self.tinytex(parent / "TinyTeX-v2026.11", windows)
                custom = self.tinytex(self.directory / f"custom-{windows}", windows)
                settings = {"tex_directory": str(custom), "tool_paths": [str(custom)]}
                self.assertEqual(configure.tinytex_directories(settings), [custom, default, versioned])

    def test_partial_tinytex_is_resumed_without_another_download(self):
        root = self.directory / "Library/TinyTeX-v2026.11"
        directory = self.tinytex(root)
        (directory / "pdflatex").unlink()
        (self.directory / "Library/TinyTeX").mkdir()
        with patch.object(configure, "stable_release", return_value={"tag_name": "v2026.11"}), patch.object(configure, "download_asset") as download, patch.object(configure, "output", return_value="TeX Live version 2026"):
            self.assertEqual(configure.install_tinytex(), directory)
        download.assert_not_called()

    def test_template_checks_compile_all_types_and_large_fonts(self):
        directory = self.tools(self.directory / "compiler")
        kinds = []
        def compile_document(command, cwd, **kwargs):
            kinds.append(cwd.name)
            source = (cwd / "check.tex").read_text()
            self.assertIn("\\Huge", source)
            self.assertIn("-no-shell-escape", command)
            self.assertEqual(Path(command[0]).parent, directory)
            (cwd / "check.pdf").write_bytes(b"%PDF-1.4")
        with patch.object(configure, "run", side_effect=compile_document):
            self.assertTrue(configure.latex_works(directory, complete=True))
        self.assertEqual(kinds, ["note", "preprint", "presentation", "dissertation"])

    def test_unstable_releases_and_unverified_downloads_are_rejected(self):
        for release in ({"tag_name": "daily"}, {"tag_name": "v1", "prerelease": True}, {"tag_name": "v1", "draft": True}):
            with self.subTest(release=release), patch.object(configure, "fetch", return_value=json.dumps(release).encode()):
                with self.assertRaisesRegex(RuntimeError, "stable release"):
                    configure.stable_release("example/tool")
        release = {"assets": [{"name": "tool.zip", "browser_download_url": "https://github.com/example/tool/releases/download/v1/tool.zip", "digest": "sha256:" + "0" * 64}]}
        with patch.object(configure, "fetch", return_value=b"changed download"):
            with self.assertRaisesRegex(RuntimeError, "checksum"):
                configure.download_asset("example/tool", release, r"tool\.zip", self.directory)
        self.assertFalse((self.directory / "tool.zip").exists())

    def test_downloaded_archive_cannot_escape_destination(self):
        archive = self.directory / "unsafe.tar"
        with tarfile.open(archive, "w") as stream:
            member = tarfile.TarInfo("../escaped")
            member.size = 1
            stream.addfile(member, io.BytesIO(b"x"))
        with self.assertRaisesRegex(RuntimeError, "Unsafe path"):
            configure.unpack_tar(archive, self.directory / "unpack")
        self.assertFalse((self.directory / "escaped").exists())


    def test_tinytex_uses_stable_archive_and_preserves_existing_directory(self):
        archive = io.BytesIO()
        with tarfile.open(fileobj=archive, mode="w:xz") as stream:
            for name in ("TinyTeX/tlpkg/texlive.tlpdb", "TinyTeX/bin/universal-darwin/tlmgr"):
                member = tarfile.TarInfo(name)
                member.size = 1
                member.mode = 0o755
                stream.addfile(member, io.BytesIO(b"x"))
        data = archive.getvalue()
        release = {"tag_name": "v2026.11", "assets": [{"name": "TinyTeX-0-darwin-v2026.11.tar.xz", "browser_download_url": "https://github.com/rstudio/tinytex-releases/releases/download/v2026.11/TinyTeX-0-darwin-v2026.11.tar.xz", "digest": "sha256:" + hashlib.sha256(data).hexdigest()}]}
        old = self.directory / "Library/TinyTeX/keep.txt"
        old.parent.mkdir(parents=True)
        old.write_text("keep")
        with patch.object(configure, "stable_release", return_value=release), patch.object(configure, "fetch", return_value=data):
            directory = configure.install_tinytex()
        self.assertEqual(directory, self.directory / "Library/TinyTeX-v2026.11/bin/universal-darwin")
        self.assertEqual(old.read_text(), "keep")


    def test_windows_tinytex_uses_stable_self_extracting_archive(self):
        release = {"tag_name": "v2026.11"}
        def extract(command, cwd):
            self.assertEqual(command[1:], ["-y"])
            root = Path(cwd) / "TinyTeX"
            self.tools(root / "bin/windows", windows=True)
            (root / "tlpkg").mkdir()
            (root / "tlpkg/texlive.tlpdb").touch()
        with patch.object(configure, "WINDOWS", True), patch.dict(os.environ, {"APPDATA": str(self.directory), "ProgramData": str(self.directory)}), patch.object(configure, "stable_release", return_value=release), patch.object(configure, "download_asset", return_value=self.directory / "stable.exe") as download, patch.object(configure, "run", side_effect=extract):
            directory = configure.install_tinytex()
        self.assertEqual(directory, self.directory / "TinyTeX/bin/windows")
        self.assertIn("windows", download.call_args.args[2])

    def test_mac_pandoc_installs_or_upgrades_and_checks_stable_version(self):
        prefix = self.directory / "pandoc"
        (prefix / "bin").mkdir(parents=True)
        (prefix / "bin/pandoc").touch()
        for installed in (False, True):
            def query(command):
                if "list" in command:
                    return "git\npandoc" if installed else "git"
                if "--prefix" in command:
                    return str(prefix)
                return "pandoc 3.14"
            with self.subTest(installed=installed), patch.object(configure.shutil, "which", side_effect=lambda name: "/fake/bin/brew" if name == "brew" else None), patch.object(configure, "stable_release", return_value={"tag_name": "3.14"}), patch.object(configure, "output", side_effect=query), patch.object(configure, "run") as run:
                settings = {}
                configure.configure_pandoc(settings)
            self.assertEqual(run.call_args_list[0].args[0][1], "upgrade" if installed else "install")
            self.assertIn(str(prefix / "bin"), settings["tool_paths"])

    def test_windows_pandoc_accepts_reboot_exit_and_uses_updated_executable(self):
        directory = self.directory / "Pandoc"
        directory.mkdir()
        (directory / "pandoc.exe").touch()
        with patch.object(configure, "WINDOWS", True), patch.dict(os.environ, {"LOCALAPPDATA": str(self.directory), "ProgramFiles": str(self.directory)}), patch.object(configure.shutil, "which", return_value=None), patch.object(configure, "stable_release", return_value={"tag_name": "3.14"}), patch.object(configure, "download_asset", return_value=self.directory / "pandoc.msi"), patch.object(configure.subprocess, "run", return_value=subprocess.CompletedProcess([], 3010)), patch.object(configure, "output", return_value="pandoc 3.14"), patch.object(configure, "run"):
            settings = {}
            configure.configure_pandoc(settings)
        self.assertIn(str(directory), settings["tool_paths"])

    def test_full_setup_orders_python_julia_dependencies_then_registration(self):
        sequence = Mock()
        with patch.object(sys, "argv", ["configure.py", "--provider", "standard", "--python", "/fake/python"]), patch.object(configure, "load_settings", return_value={}), patch.object(configure, "configure_python", sequence.python), patch.object(configure, "configure_julia", sequence.julia), patch.object(configure, "configure_dependencies", sequence.dependencies), patch.object(configure, "register_command", sequence.register):
            configure.main()
        self.assertEqual([call[0] for call in sequence.mock_calls], ["python", "julia", "dependencies", "register"])

    def test_current_pandoc_does_not_reinstall(self):
        directory = self.directory / "Pandoc"
        directory.mkdir()
        pandoc = directory / "pandoc"
        pandoc.touch()
        with patch.object(configure.shutil, "which", return_value=str(pandoc)), patch.object(configure, "stable_release", return_value={"tag_name": "3.14"}), patch.object(configure, "output", return_value="pandoc 3.14"), patch.object(configure, "run") as run, patch.object(configure, "download_asset") as download:
            configure.configure_pandoc({})
        download.assert_not_called()
        self.assertEqual(run.call_count, 1)
        self.assertIn("--to=html", run.call_args.args[0])

    def test_outdated_git_prevents_reporting_complete(self):
        with patch.object(configure.shutil, "which", return_value="/fake/git"), patch.object(configure, "output", return_value="git version 2.55.0"), patch.object(configure, "fetch", return_value=b'<a href="git-2.56.1.tar.xz">stable</a><a href="git-2.57.0-rc1.tar.xz">preview</a>'), patch.object(configure, "configure_pandoc") as pandoc, patch.object(configure, "save_settings") as save:
            with self.assertRaisesRegex(RuntimeError, "2.56.1 is the latest stable release"):
                configure.configure_dependencies({})
        pandoc.assert_not_called()
        save.assert_not_called()

    def test_saved_tool_paths_preserve_stable_symlinks(self):
        real = self.directory / "Cellar/tool/1/bin"
        real.mkdir(parents=True)
        alias = self.directory / "opt/tool"
        alias.parent.mkdir()
        alias.symlink_to(real.parent)
        settings = {"root": str(configure.ROOT)}
        with patch.object(configure, "CONFIG", self.directory / "config"):
            configure.use_tool_paths(settings, [alias / "bin"])
            configure.save_settings(settings)
        self.assertEqual(settings["tool_paths"], [str(alias / "bin")])
        self.assertIn(str(alias / "bin"), (self.directory / "config/runtime.sh").read_text())

    def test_tex_mirror_redirect_is_resolved_once(self):
        response = Mock()
        response.url = "https://one-mirror.invalid/tlnet/tlpkg/texlive.tlpdb.xz"
        response.read.return_value = lzma.compress(b"name 00texlive.config\ndepend release/2026\n")
        with patch.object(configure.urllib.request, "urlopen", return_value=contextlib.nullcontext(response)):
            repository, year = configure.tex_repository()
        self.assertEqual((repository, year), ("https://one-mirror.invalid/tlnet", 2026))
        self.assertNotIn("mirror.ctan.org", repository)

    def test_tex_package_selection_follows_dependencies_without_unrelated_packages(self):
        data = "latex-bin,latex:pdftex.ARCH\nlatex,core\ncore,latex\npdftex.universal-darwin,\nchess,\ncollection-full,chess:latex\n"
        def query(command):
            return "universal-darwin" if "print-platform" in command else data
        with patch.object(configure, "output", side_effect=query):
            packages = configure.texlive_packages("tlmgr", "https://one-mirror.invalid", ["latex-bin"])
        self.assertEqual(packages, ["core", "latex", "latex-bin", "pdftex.universal-darwin"])


    def test_mac_tex_password_prompt_explains_administrator_access(self):
        messages = io.StringIO()
        with patch.object(configure.os, "access", return_value=False), patch.object(configure, "TEX_ADMIN_NOTICE_SHOWN", False), patch.object(configure, "run") as run, contextlib.redirect_stdout(messages):
            configure.managed_tex_run(["tlmgr", "update", "--self"], self.directory)
        self.assertIn("Mac administrator login password", messages.getvalue())
        self.assertIn("Nothing appears while you type", messages.getvalue())
        self.assertEqual(run.call_args.args[0][:2], ["sudo", "-p"])
        self.assertIn("typing is hidden", run.call_args.args[0][2])


class MacBootstrapTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="projtool-bootstrap-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name).resolve()
        self.calls = self.directory / "calls"
        self.environment = dict(os.environ, PATH="/usr/bin:/bin:/usr/sbin:/sbin", PROJTOOL_TEST_CALLS=str(self.calls))
        self.installer = configure.ROOT / "Source/Install/install.sh"

    def executable(self, path, body):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("#!/bin/bash\nset -eu\n" + body + "\n")
        path.chmod(0o755)
        return path

    def functions(self, body, answer=""):
        prefix = self.installer.read_text().split('if [[ "$COMPONENT" == all ]]; then ensure_git; fi')[0]
        script = self.directory / "functions.sh"
        script.write_text(prefix + "\n" + body)
        return subprocess.run(["/bin/bash", str(script), "python"], input=answer, text=True, capture_output=True, env=self.environment)

    def test_missing_homebrew_requires_consent_before_download(self):
        result = self.functions('find_brew() { return 1; }\ncurl() { exit 91; }\nensure_brew', "no\n")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Installation denied because Homebrew is required", result.stderr)

    def test_homebrew_consent_installs_and_updates_once(self):
        brew = self.executable(self.directory / "brew", 'printf "%s\\n" "$*" >> "$PROJTOOL_TEST_CALLS"')
        marker = self.directory / "installed"
        fake = self.executable(self.directory / "download.sh", "touch " + shlex.quote(str(marker)))
        body = f'''find_brew() {{ [[ -f {shlex.quote(str(marker))} ]] || return 1; printf '%s\\n' {shlex.quote(str(brew))}; }}
curl() {{ [[ "$2" == https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh ]] || exit 91; cp {shlex.quote(str(fake))} "$4"; }}
ensure_brew
ensure_brew
'''
        result = self.functions(body, "yes\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls.read_text().splitlines(), ["update"])

    def test_homebrew_python_install_and_upgrade_use_only_mock_commands(self):
        prefix = self.directory / "python prefix"
        self.executable(prefix / "bin/python3", 'printf "python %s\\n" "$*" >> "$PROJTOOL_TEST_CALLS"')
        for installed in (False, True):
            with self.subTest(installed=installed):
                self.calls.unlink(missing_ok=True)
                listing = 'printf "python 3.15.2\\n"' if installed else ":"
                self.executable(self.directory / "bin/brew", f'''printf 'brew %s\\n' "$*" >> "$PROJTOOL_TEST_CALLS"
case "$1" in
    list) {listing} ;;
    --prefix) printf '%s\\n' {shlex.quote(str(prefix))} ;;
    update|upgrade|install|outdated) ;;
    *) exit 91 ;;
esac''')
                environment = dict(self.environment, PATH=str(self.directory / "bin") + ":" + self.environment["PATH"])
                result = subprocess.run(["/bin/bash", str(self.installer), "python"], input="homebrew\nyes\n", text=True, capture_output=True, env=environment)
                self.assertEqual(result.returncode, 0, result.stderr)
                calls = self.calls.read_text()
                self.assertIn("brew upgrade --formula python" if installed else "brew install --formula python", calls)
                self.assertIn("brew outdated --formula --quiet python", calls)
                self.assertIn("--provider homebrew", calls)

    def test_conda_download_is_verified_and_failed_download_stops_setup(self):
        conda = self.executable(self.directory / "fake-conda", 'printf "conda %s\\n" "$*" >> "$PROJTOOL_TEST_CALLS"')
        installer = self.executable(self.directory / "fake-installer", f'''[[ "$1" == -b && "$2" == -p ]]
mkdir -p "$3/bin"
cp {shlex.quote(str(conda))} "$3/bin/conda"''')
        index = self.directory / "index.html"
        checksum = hashlib.sha256(installer.read_bytes()).hexdigest()
        architecture = os.uname().machine
        index.write_text(f'<tr>\n<td><a href="Miniconda3-latest-MacOSX-{architecture}.sh">installer</a></td>\n<td>{checksum}</td>\n</tr>')
        body = f'''curl() {{
case "$2" in
    https://repo.anaconda.com/miniconda/) cp {shlex.quote(str(index))} "$4" ;;
    https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-*.sh) cp {shlex.quote(str(installer))} "$4" ;;
    *) exit 91 ;;
esac
}}
install_conda {shlex.quote(str(self.directory / 'conda prefix'))} || printf 'unexpected continuation'
'''
        result = self.functions(body, "yes\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("conda update --name base --override-channels --channel defaults conda", self.calls.read_text())
        self.calls.unlink()
        result = self.functions(f'curl() {{ return 22; }}\ninstall_conda {shlex.quote(str(self.directory / "failed-conda"))} || printf "unexpected continuation"', "yes\n")
        self.assertEqual(result.returncode, 1)
        self.assertNotIn("unexpected continuation", result.stdout)
        self.assertFalse(self.calls.exists())


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
        self.command = configure.ROOT / "Source/Commands/projtool"
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
            ["python", str(configure.ROOT / "Source/Commands/Jupyter/run_notebook.py"), "--kernel_name=projtool", "a notebook.ipynb"],
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

    def test_saved_dependency_path_is_used_in_a_new_process(self):
        self.variables["PROJTOOL_TOOL_PATH"] = str(self.bin)
        pandoc = self.bin / "pandoc"
        pandoc.write_text("#!/bin/bash\nprintf selected > selected-pandoc\n")
        pandoc.chmod(0o755)
        result = self.run_results("pandoc --version\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.project / "selected-pandoc").read_text(), "selected")

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
        self.assertIn("Run the ProjTool installer with the python argument first.", result.stderr)
        self.assertFalse(self.calls.exists())

    def initialize_project(self, project, template="note"):
        executable = self.bin / "git"
        executable.write_text("#!/usr/bin/env bash\nexit 0\n")
        executable.chmod(0o755)
        executable = self.bin / "code"
        executable.write_text("#!/usr/bin/env bash\nprintf '%s\\n' 'projtool.projtool-folding@0.1.0'\n")
        executable.chmod(0o755)
        environment = dict(self.environment, PATH=str(self.bin) + os.pathsep + self.environment["PATH"])
        project.mkdir(parents=True)
        return subprocess.run([str(self.command), "init", template], cwd=project,
                              env=environment, input="Test Author\nhttps://example.invalid/test.git\n1.0.0\n",
                              text=True, capture_output=True)

    def test_init_finds_capitalized_examples_and_preserves_layout(self):
        for name in ("Dissertation", "Note", "Preprint", "Presentation"):
            with self.subTest(example=name):
                project = self.directory / ("Init" + name)
                result = self.initialize_project(project, name.lower())
                self.assertEqual(result.returncode, 0, result.stderr)
                stem = "init_" + name.lower()
                self.assertTrue((project / (stem + ".tex")).is_file())
                self.assertTrue((project / "Code/Python/code.ipynb").is_file())
                self.assertTrue((project / "References/2001Author/2001author.bib").is_file())
                names = {path.name for path in project.iterdir()}
                self.assertTrue({"Code", "References", "Output"}.issubset(names))
                self.assertNotIn("README.md", names)
                self.assertNotIn(name.lower() + ".md", names)
                source_pdf = configure.ROOT / "Examples" / name / "Output/Media/PDF" / (name.lower() + ".pdf")
                copied_pdf = project / "Output/Media/PDF" / (stem + ".pdf")
                self.assertEqual(copied_pdf.is_file(), source_pdf.is_file())
                if source_pdf.is_file():
                    self.assertEqual(copied_pdf.read_bytes(), source_pdf.read_bytes())

    def test_init_normalizes_document_and_all_copied_media_names(self):
        examples = {
            "123StudyNoteHERE123": "123_study_note_here_123",
            "StudyNoteHERE": "study_note_here",
            "123": "123",
            "3P": "3_p",
            "Po": "po",
            "oo": "oo",
            "yP": "y_p",
            "HERE": "here",
            "P1": "p_1",
            "p1": "p_1",
            "A1B2C3": "a_1_b_2_c_3",
            "ABcDEf12G3h": "abc_def_12_g_3h",
            "123lower": "123lower",
            "study_note_here_123": "study_note_here_123",
            "A_B-C": "a_b-c",
            "Project With Spaces": "project with spaces",
            "123StudyNoteHERE123_template": "123_study_note_here_123",
        }
        source = configure.ROOT / "Examples/Note"
        media = source / "Output/Media"
        for index, (name, stem) in enumerate(examples.items()):
            with self.subTest(project=name):
                project = self.directory / str(index) / name
                result = self.initialize_project(project)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(list(project.glob("*.tex")), [project / (stem + ".tex")])
                self.assertEqual((project / (stem + ".tex")).read_bytes(), (source / "note.tex").read_bytes())
                expected = {}
                for path in media.rglob("*"):
                    if path.is_file():
                        relative = path.relative_to(media)
                        if path.name.startswith("note."):
                            relative = relative.with_name(stem + path.name[len("note"):])
                        expected[relative] = path.read_bytes()
                copied = {path.relative_to(project / "Output/Media"): path.read_bytes()
                          for path in (project / "Output/Media").rglob("*") if path.is_file()}
                self.assertEqual(copied, expected)

    def test_generation_selects_normalized_document_with_multiple_tex_files(self):
        project = self.directory / "123StudyNoteHERE123"
        result = self.initialize_project(project)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        (project / "section.tex").write_text("included source")
        (project / (project.name + ".tex")).write_text("old source")
        result = subprocess.run([str(self.command), "gen", "readme", "-f", str(project)],
                                env=self.environment, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        intro = (project / "README.md").read_text().splitlines()[0]
        self.assertIn("./Output/Media/PDF/123_study_note_here_123.pdf", intro)
        self.assertIn("./Output/Media/MD/123_study_note_here_123.md", intro)

    def test_generation_preserves_existing_document_names_with_multiple_tex_files(self):
        for name in ("LegacyProject", "LegacyProject_template"):
            with self.subTest(project=name):
                project = self.directory / name
                project.mkdir()
                (project / "LegacyProject.tex").write_text("source")
                (project / "section.tex").write_text("included source")
                media = project / "Output/Media/MD"
                media.mkdir(parents=True)
                (media / "LegacyProject.md").write_text("existing media")
                result = subprocess.run([str(self.command), "gen", "readme", "-f", str(project)],
                                        env=self.environment, text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("./Output/Media/MD/LegacyProject.md", (project / "README.md").read_text())

    def test_rem_output_preserves_project_sources(self):
        output = self.project / "Output/Results"
        output.mkdir(parents=True)
        (output / "generated.txt").write_text("generated")
        code = self.project / "Code"
        code.mkdir()
        source = code / "keep.py"
        source.write_text("print('keep')\n")
        result = subprocess.run([str(self.command), "rem", "output", "-f", str(self.project)],
                                env=self.environment, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.project / "Output").exists())
        self.assertTrue(source.is_file())

    def test_rem_all_reports_relative_paths_for_present_and_absent_files(self):
        document = self.project / "dissertation.tex"
        document.write_text("source")
        output = self.project / "Output/Results"
        output.mkdir(parents=True)
        (output / "result.txt").write_text("result")
        (self.project / "README.md").write_text("generated")
        root_files = {self.project / name for name in ("dissertation.pdf", "dissertation.md")}
        for path in root_files:
            path.write_text("unrelated root file")
        expected = (
            "-> Removing: Output.\n"
            "-> Removing: README.md.\n"
            "✓ Done.\n"
        )
        for state in ("present", "absent"):
            with self.subTest(state=state):
                result = subprocess.run([str(self.command), "rem", "all", "-f", str(self.project)],
                                        env=self.environment, text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, expected)
                self.assertEqual(set(self.project.iterdir()), root_files | {document})
                for path in root_files:
                    self.assertEqual(path.read_text(), "unrelated root file")

    def test_readme_links_to_media_without_copying_and_rebases_images(self):
        for formats in (("pdf",), ("md",), ("pdf", "md")):
            with self.subTest(formats=formats):
                project = self.directory / ("readme " + " ".join(formats))
                project.mkdir()
                (project / "dissertation.tex").write_text("source")
                sources = {}
                for format in formats:
                    path = project / "Output/Media" / format.upper() / ("dissertation." + format)
                    path.parent.mkdir(parents=True)
                    content = "%PDF-example" if format == "pdf" else (
                        '![Plot](../../Results/Julia/exp.png)\n'
                        '<img src="../../Results/Python/quadratic.png">\n'
                    )
                    path.write_text(content)
                    sources[path] = content
                before = {path for path in project.rglob("*") if path.is_file()}
                result = subprocess.run([str(self.command), "gen", "readme", "-f", str(project)],
                                        env=self.environment, text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, "-> Generating: README.md.\n✓ Done.\n")
                readme = project / "README.md"
                self.assertEqual({path for path in project.rglob("*") if path.is_file()}, before | {readme})
                content = readme.read_text()
                intro = content.splitlines()[0]
                for format in ("pdf", "md"):
                    link = f"(./Output/Media/{format.upper()}/dissertation.{format})"
                    if format in formats:
                        self.assertIn(link, intro)
                    else:
                        self.assertNotIn(link, intro)
                if "md" in formats:
                    self.assertIn("![Plot](./Output/Results/Julia/exp.png)", content)
                    self.assertIn('<img src="./Output/Results/Python/quadratic.png">', content)
                for path, original in sources.items():
                    self.assertEqual(path.read_text(), original)

    def test_readme_without_media_does_not_report_success(self):
        result = subprocess.run([str(self.command), "gen", "readme", "-f", str(self.project)],
                                env=self.environment, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no generated PDF or Markdown", result.stderr)
        self.assertNotIn("✓ Done.", result.stdout)
        self.assertFalse((self.project / "README.md").exists())


if __name__ == "__main__":
    with contextlib.redirect_stdout(io.StringIO()):
        unittest.main()
