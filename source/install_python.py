import json
import os
import subprocess


def python_command(selection):
    command = [selection["executable"]]
    if selection.get("conda"):
        command = [selection["conda"], "run", "--no-capture-output", "-p", selection["prefix"]] + command
    return command


def inspect_python(executable, command=None):
    probe = "import json,sys; print(json.dumps(dict(executable=sys.executable,prefix=sys.prefix,base_prefix=sys.base_prefix,version=list(sys.version_info[:3]))))"
    result = subprocess.run((command or [str(executable)]) + ["-I", "-c", probe], check=True, text=True, capture_output=True)
    info = json.loads(result.stdout.strip().splitlines()[-1])
    if info["version"] < [3, 10]:
        raise RuntimeError("ProjTool requires Python 3.10 or newer.")
    return info


def install_packages(selection, requirements, config_dir):
    command = python_command(selection)
    environment = os.environ.copy()
    for variable in ("PYTHONHOME", "PYTHONPATH", "PIP_TARGET", "PIP_PREFIX", "PIP_USER"):
        environment.pop(variable, None)
    environment["PIP_CONFIG_FILE"] = os.devnull
    environment["PYTHONNOUSERSITE"] = "1"
    pip = subprocess.run(command + ["-m", "pip", "--version"], env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if pip.returncode:
        subprocess.run(command + ["-m", "ensurepip", "--upgrade"], check=True, env=environment)
    subprocess.run(command + ["-m", "pip", "install", "--disable-pip-version-check", "--no-user", "--upgrade", "-r", str(requirements)], check=True, env=environment)
    subprocess.run(command + ["-c", "import jupyter_core, nbclient, ipykernel, numpy, matplotlib, zmq; assert zmq.has('curve'), 'ZeroMQ encryption support is required'"], check=True, env=environment)
    kernel_dir = config_dir / "share/jupyter/kernels/projtool"
    kernel_dir.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(command + ["-c", "import json; from ipykernel.kernelspec import get_kernel_dict; print(json.dumps(get_kernel_dict()))"], check=True, env=environment, text=True, capture_output=True)
    kernel = json.loads(result.stdout.strip().splitlines()[-1])
    kernel["argv"] = command + kernel["argv"][1:]
    kernel["display_name"] = "ProjTool"
    (kernel_dir / "kernel.json").write_text(json.dumps(kernel, indent=2) + "\n", encoding="utf-8")
