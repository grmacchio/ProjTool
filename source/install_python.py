import os
import shutil
import subprocess
import sys
import uuid
import venv
from pathlib import Path

def remove_environment(path):
    target = str(path.resolve())
    if sys.platform == "win32":
        target = "\\\\?\\" + target
    shutil.rmtree(target)


prefix = Path(sys.argv[1])
requirements = Path(sys.argv[2])
marker = prefix / ".projtool-owned"
executable = prefix / ("Scripts/python.exe" if sys.platform == "win32" else "bin/python")
if prefix.exists() and not marker.is_file():
    raise RuntimeError(f"Refusing to modify an unmanaged Python environment: {prefix}")
current = subprocess.run(
    [str(executable), "-c", "import sys; print(sys.version.split()[0])"],
    text=True, capture_output=True,
) if executable.is_file() else None
rebuild = current is None or current.returncode != 0 or current.stdout.strip() != sys.version.split()[0]
pip_environment = os.environ.copy()
pip_environment.setdefault("PYYAML_FORCE_LIBYAML", "0")
backup = None
created = False
if rebuild and prefix.exists():
    backup = prefix.with_name(prefix.name + ".backup-" + uuid.uuid4().hex)
    prefix.rename(backup)
try:
    if not prefix.exists():
        created = True
        venv.EnvBuilder(with_pip=True, upgrade_deps=True).create(prefix)
        marker.write_text("ProjTool managed Python environment\n", encoding="utf-8")
    subprocess.run([str(executable), "-m", "pip", "install", "--disable-pip-version-check",
                    "--upgrade", "--upgrade-strategy", "eager", "-r", str(requirements)], check=True, env=pip_environment)
    subprocess.run([str(executable), "-m", "ipykernel", "install", "--prefix", str(prefix),
                    "--name", "projtool", "--display-name", "ProjTool"], check=True)
    subprocess.run([str(executable), "-c",
                    "import jupyter_core, nbclient, ipykernel, numpy, matplotlib, zmq; "
                    "assert zmq.has('curve'), 'The installed ZeroMQ library lacks encryption support'"], check=True)
except BaseException:
    if created and prefix.exists():
        remove_environment(prefix)
    if backup:
        backup.rename(prefix)
    raise
else:
    if backup:
        remove_environment(backup)
