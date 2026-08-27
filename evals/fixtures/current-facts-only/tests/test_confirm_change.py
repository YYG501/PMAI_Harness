import tempfile
import unittest
from pathlib import Path

from app.confirm_change import CONFIRMED, ChangeStore


class ChangeStoreSmokeTests(unittest.TestCase):
    def test_create_and_confirm(self):
        with tempfile.TemporaryDirectory() as directory:
            store = ChangeStore(Path(directory) / "changes.json")
            created = store.create("change-1", "更新规则", "确认一条变更")
            self.assertEqual(created.status, "待处理")

            confirmed = store.confirm("change-1")
            self.assertEqual(confirmed.status, CONFIRMED)
            self.assertEqual(store.confirm("change-1"), confirmed)


if __name__ == "__main__":
    unittest.main()
