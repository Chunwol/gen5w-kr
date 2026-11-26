"""Test scratch space inside the checkout, with inherited directory permissions."""
from pathlib import Path
import shutil
import uuid

class TemporaryDirectory:
    def __init__(self, prefix='test-', dir=None):
        base = Path(dir) if dir else Path(__file__).resolve().parent
        base.mkdir(parents=True, exist_ok=True)
        self.name = str(base / (prefix + uuid.uuid4().hex))
        Path(self.name).mkdir()
    def __enter__(self):
        return self.name
    def __exit__(self, *exc):
        shutil.rmtree(self.name)
