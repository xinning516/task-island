import importlib.util
import json
import pathlib
import tempfile
import unittest

MODULE = pathlib.Path(__file__).resolve().parents[1] / 'integrations' / 'install.py'
spec = importlib.util.spec_from_file_location('taskislandinstaller', MODULE)
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)

class InstallTests(unittest.TestCase):
    def test_preserve_hook_config_and_idempotency(self):
        with tempfile.TemporaryDirectory() as d:
            home = pathlib.Path(d)
            codex = home / '.codex'
            codex.mkdir()
            (codex / 'hooks.json').write_text(json.dumps({'hooks':{
                'Stop':[{'hooks':[{'type':'command','command':'echo existing'}]}]
            }}))
            installer.install(home)
            installer.install(home)
            data = json.loads((codex / 'hooks.json').read_text())
            self.assertEqual(len(data['hooks']['UserPromptSubmit']), 1)
            self.assertEqual(len(data['hooks']['Stop']), 2)
            self.assertEqual(len(data['hooks']['Interrupt']), 1)
            self.assertEqual(len(data['hooks']['PermissionRequest']), 1)
            self.assertEqual(len(data['hooks']['PostToolUse']), 1)
            self.assertIn('echo existing',json.dumps(data))
            self.assertEqual((home / '.hammerspoon/init.lua').read_text().count('-- Task Island (start)'),1)
            self.assertNotIn('REPLACE_VIA_INSTALLER',(home / 'TaskIsland-Chrome-Extension/config.js').read_text())
            self.assertTrue((home / '.vscode/extensions/localtaskisland.task-island-monitor-0.1.0/extension.js').exists())

if __name__=='__main__':
    unittest.main()
