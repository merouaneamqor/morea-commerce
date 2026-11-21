"""Exercise the real startup wrapper with a stub bundle executable, without Rails or external services."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class RenderMemoryDefaultsTest(unittest.TestCase):
    def start(self, growth_factor=None):
        with tempfile.TemporaryDirectory() as directory:
            bundle = Path(directory) / "bundle"
            bundle.write_text('#!/bin/sh\nprintf "%s\\n" "$RUBY_GC_HEAP_GROWTH_FACTOR"\n')
            bundle.chmod(0o755)
            environment = os.environ.copy()
            environment["PATH"] = directory + os.pathsep + environment["PATH"]
            environment.pop("RUBY_GC_HEAP_GROWTH_FACTOR", None)
            if growth_factor is not None:
                environment["RUBY_GC_HEAP_GROWTH_FACTOR"] = growth_factor
            result = subprocess.run(
                ["bash", "bin/render-start.sh"],
                cwd=Path(__file__).resolve().parents[1],
                env=environment,
                text=True,
                capture_output=True,
                timeout=10,
                check=True,
            )
            return result.stdout.splitlines()

    def test_runner_worker_and_web_inherit_the_memory_default(self):
        self.assertEqual(self.start(), ["1.1"] * 3)

    def test_explicit_tuning_is_preserved_for_every_process(self):
        self.assertEqual(self.start("1.3"), ["1.3"] * 3)


if __name__ == "__main__":
    unittest.main()
