import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import pytest  # noqa: E402


@pytest.fixture(autouse=True)
def _no_cover_lookup(monkeypatch):
    """Testlarda internetga chiqmaymiz / в тестах не ходим в интернет."""
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    import cover
    monkeypatch.setattr(cover, "find_online", lambda *a, **k: None)
