import tempfile
import unittest
from pathlib import Path

from app.confirm_change import CONFIRMED, PENDING, ChangeStore


class ChangeStoreTests(unittest.TestCase):
    def test_create_view_and_confirm(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "changes.json"
            store = ChangeStore(path, clock=lambda: "2026-08-26T00:00:00+00:00")

            created = store.create("change-1", "更新规则", "确认一次变更")
            self.assertEqual(created.status, PENDING)
            self.assertEqual(store.get("change-1").summary, "确认一次变更")

            confirmed = store.confirm("change-1")
            self.assertEqual(confirmed.status, CONFIRMED)
            self.assertEqual(confirmed.confirmed_at, "2026-08-26T00:00:00+00:00")
            self.assertEqual(store.confirm("change-1"), confirmed)

    def test_keep_pending_does_not_change_record(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "changes.json"
            store = ChangeStore(path)
            created = store.create("change-2", "暂缓变更", "保留待处理状态")

            pending = store.keep_pending("change-2")
            self.assertEqual(pending, created)
            self.assertEqual(store.get("change-2").status, PENDING)


if __name__ == "__main__":
    unittest.main()
