import asyncio
import logging
import sys
from pathlib import Path

import nbformat
from nbclient import NotebookClient
from nbclient.cli import NbClientApp
from traitlets import default
from traitlets.config import Config


def execute(client):
    if sys.platform != "win32":
        asyncio.run(client.async_execute())
    elif hasattr(asyncio, "Runner"):
        with asyncio.Runner(loop_factory=asyncio.SelectorEventLoop) as runner:
            runner.run(client.async_execute())
    else:
        loop = asyncio.SelectorEventLoop()
        asyncio.set_event_loop(loop)
        try:
            loop.run_until_complete(client.async_execute())
        finally:
            try:
                loop.run_until_complete(loop.shutdown_asyncgens())
                loop.run_until_complete(loop.shutdown_default_executor())
            finally:
                asyncio.set_event_loop(None)
                loop.close()


class ProjToolNotebookApp(NbClientApp):
    @default("log_level")
    def _log_level_default(self):
        return logging.WARNING

    def run_notebook(self, notebook_path):
        self.log.info(f"Executing {notebook_path}")
        input_path = Path(notebook_path).with_suffix(".ipynb")
        if self.inplace:
            output_path = input_path
        elif self.output_base:
            output_path = input_path.parent.joinpath(
                self.output_base.format(notebook_name=input_path.stem)
            ).with_suffix(".ipynb")
        else:
            output_path = None
        if output_path and not output_path.parent.is_dir():
            raise ValueError(f"Cannot write to directory={output_path.parent} that does not exist")

        with input_path.open(encoding="utf-8") as stream:
            notebook = nbformat.read(stream, as_version=4)
        config = Config(self.config)
        config.KernelManager.transport_encryption = "required"
        client = NotebookClient(
            notebook,
            timeout=self.timeout,
            startup_timeout=self.startup_timeout,
            skip_cells_with_tag=self.skip_cells_with_tag,
            allow_errors=self.allow_errors,
            kernel_name=self.kernel_name,
            resources={"metadata": {"path": input_path.parent.absolute()}},
            config=config,
        )
        execute(client)
        if output_path:
            self.log.info(f"Save executed results to {output_path}")
            nbformat.write(notebook, output_path)


if __name__ == "__main__":
    ProjToolNotebookApp.launch_instance()
