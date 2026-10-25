"""Check lifecycle statuses without exposing payload fields."""
import importlib.util
from pathlib import Path
import unittest

HOOK = Path(__file__).resolve().parents[1] / "integrations" / "codex_hook.py"
spec = importlib.util.spec_from_file_location("taskislandhook", HOOK)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class CodexEventTests(unittest.TestCase):
    def test_permissions_do_not_auto_approve(self):
        payload = {"hook_event_name": "PermissionRequest", "session_id": "session-1", "cwd": "/tmp/demo", "prompt": "PRIVATE", "tool_input": {"command": "SECRET"}}
        event = module.event_from_hook(payload)
        self.assertEqual(event["status"], "waiting")
        self.assertEqual(event["source"], "codex")
        self.assertNotIn("PRIVATE", repr(event))
        self.assertNotIn("SECRET", repr(event))

    def test_resume_after_approval(self):
        event = module.event_from_hook({"hook_event_name": "PostToolUse", "session_id": "s"})
        self.assertEqual(event["status"], "running")

    def test_unknown_event_ignored(self):
        self.assertIsNone(module.event_from_hook({"hook_event_name": "Unexpected"}))


if __name__ == "__main__":
    unittest.main()
