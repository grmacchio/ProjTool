import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("pandoc"), "Pandoc is required for Markdown rendering tests")
class MarkdownTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="projtool-markdown-test-")
        self.addCleanup(temporary.cleanup)
        self.project = Path(temporary.name)

    def render(self, body, template="note", stem="document"):
        source = self.project / (stem + ".tex")
        source.write_text(
            "\\documentclass[" + template + "]{template}\n"
            "\\begin{document}\n" + body + "\n\\end{document}\n"
        )
        result = subprocess.run(
            [str(ROOT / "Source/Commands/projtool"), "gen", "md",
             "-f", str(self.project), "-w", "verbose"],
            env=dict(os.environ, XDG_CONFIG_HOME=str(self.project / "config")),
            text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return (self.project / "Output/Media/MD" / (stem + ".md")).read_text()

    def test_normalized_project_name_is_used_with_multiple_tex_sources(self):
        self.project = self.project / "123StudyNoteHERE123"
        self.project.mkdir()
        (self.project / "section.tex").write_text("included source")
        markdown = self.render("Normalized document.", stem="123_study_note_here_123")
        self.assertIn("Normalized document.", markdown)
        self.assertTrue((self.project / "Output/Media/MD/123_study_note_here_123.pandoc.tex").is_file())

    def test_bracketed_text_after_noindent_survives_conversion(self):
        body = r"""
\noindent [Standalone] Opening text.

\noindent \textbf{Subject:} \\
\noindent [SIAM DS27] Invitation to Speak on Spectral Reduction \\

\noindent \textbf{Content:} \\
Dear colleagues,
"""
        for template in ("note", "dissertation", "preprint", "presentation"):
            with self.subTest(template=template):
                markdown = self.render(body, template)
                self.assertIn(r"\[Standalone\] Opening text.", markdown)
                self.assertIn(
                    "**Subject:**\\\n"
                    r"\[SIAM DS27\] Invitation to Speak on Spectral Reduction",
                    markdown,
                )
                self.assertIn("**Content:**\\\nDear colleagues,", markdown)

    def test_line_spacing_and_literal_noindent_are_preserved(self):
        markdown = self.render(r"""
\noindent \textbf{Subject:} \\[1ex]
\noindent [SIAM DS27] Invitation

\verb|\noindent [Inline code]|

\begin{verbatim}
\noindent [Code block]
\end{verbatim}
""")
        self.assertIn("**Subject:**\\\n" + r"\[SIAM DS27\] Invitation", markdown)
        self.assertNotIn("1ex", markdown)
        self.assertIn(r"`\noindent [Inline code]`", markdown)
        self.assertIn(r"    \noindent [Code block]", markdown)


if __name__ == "__main__":
    unittest.main()
