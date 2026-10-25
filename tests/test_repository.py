"""Fast smoke tests for safely publishable Task Island source."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class PublicRepositoryTests(unittest.TestCase):
    def test_no_packaged_runtime_secrets(self):
        self.assertFalse(list(ROOT.rglob('token.txt')))
        self.assertFalse(list(ROOT.rglob('config.js')))
        self.assertFalse(list(ROOT.rglob('config.json')))
        self.assertIn('token.txt', (ROOT / '.gitignore').read_text())
        self.assertIn('config.js', (ROOT / '.gitignore').read_text())
        self.assertIn('config.json', (ROOT / '.gitignore').read_text())

    def test_integrated_island_features(self):
        lua = (ROOT / 'hammerspoon/task_island.lua').read_text()
        html = (ROOT / 'hammerspoon/dashboard.html').read_text()
        for key in ('makeOpacityMenu', 'taskIsland.ui.position', 'beginDrag',
                    'Reset island position', 'Show VS Code', 'source.chatgpt'):
            self.assertIn(key, lua)
        for key in ('.drag-handle{', '--island-opacity', 'window.updateTaskIsland'):
            self.assertIn(key, html)

    def test_chrome_live_tracker_present(self):
        data=json.loads((ROOT/'chrome-extension/manifest.json').read_text())
        self.assertEqual(data['version'], '0.3.1')
        self.assertEqual(data['manifest_version'], 3)
        self.assertTrue(any('https://chatgpt.com/*' in s['matches']
                            for s in data['content_scripts']))
        self.assertIn('tracker_ping', (ROOT/'chrome-extension/content.js').read_text())

    def test_permission_hook_and_conservative_vscode_status(self):
        self.assertIn("'PermissionRequest'", (ROOT/'integrations/install.py').read_text())
        self.assertIn("'PostToolUse'", (ROOT/'integrations/install.py').read_text())
        self.assertIn("status:'idle'", (ROOT/'vscode-extension/extension.js').read_text())

if __name__ == '__main__':
    unittest.main()
