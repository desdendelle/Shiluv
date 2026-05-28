from __future__ import annotations

import os
from pathlib import Path


def test_run_dev_server_uses_renamed_backend_package() -> None:
    script_path = Path(__file__).resolve().parents[1] / "run_dev_server"
    script_text = script_path.read_text(encoding="utf-8")

    assert os.access(script_path, os.X_OK)
    assert "dev_server.main:app" in script_text
    assert "python -m uvicorn" in script_text
    assert 'PYTHONPATH="$script_dir' in script_text
    assert "shiluv_api" not in script_text
