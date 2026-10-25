#!/usr/bin/env python3
"""Install Task Island into an existing Hammerspoon setup (without clobbering it).

Writes only local files. Existing Codex hooks are merged and backed up.
Run from the bundled install.command on macOS.
"""
from __future__ import annotations

import argparse
import datetime
import json
import os
from pathlib import Path
import platform
import secrets
import shlex
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]
SNIPPET = ('\n-- Task Island (start)\n'
           'taskIsland = dofile(os.getenv("HOME") .. "/.hammerspoon/task-island/task_island.lua")\n'
           '-- Task Island (end)\n')
HOOK_EVENTS = ('UserPromptSubmit', 'Stop', 'Interrupt', 'PermissionRequest', 'PostToolUse')


def backup(path: Path) -> None:
    if path.exists():
        stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
        base = path.name + '.task-island-backup-' + stamp
        dest = path.with_name(base)
        index = 2
        while dest.exists():
            dest = path.with_name(f'{base}-{index}')
            index += 1
        shutil.copy2(path, dest)
        print(f'  Saved backup: {dest}')


def copy_files(source: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    for file in source.iterdir():
        if file.is_file():
            target = destination / file.name
            # New users install once; existing users may be upgrading a customized UI.
            # Back up changed files before overwriting, but leave identical files alone.
            if target.exists() and target.read_bytes() != file.read_bytes():
                backup(target)
            if not target.exists() or target.read_bytes() != file.read_bytes():
                shutil.copy2(file, target)


def merge_codex_hooks(home: Path, hook_path: Path) -> bool:
    codex_dir = home / '.codex'
    codex_dir.mkdir(exist_ok=True)
    config_path = codex_dir / 'hooks.json'
    if config_path.exists():
        try:
            config = json.loads(config_path.read_text(encoding='utf-8'))
        except (json.JSONDecodeError, UnicodeError) as exc:
            print(f'  WARNING: Existing {config_path} is invalid: {exc}')
            print('  Skipping Codex setup rather than overwriting your hooks.')
            return False
        if not isinstance(config, dict) or not isinstance(config.get('hooks', {}), dict):
            print('  WARNING: Existing hooks.json has an unexpected format; skipping.')
            return False
        backup(config_path)
    else:
        config = {'description': 'Codex hooks (Task Island preserves other hooks).', 'hooks': {}}

    command = 'python3 ' + shlex.quote(str(hook_path))
    for evt in HOOK_EVENTS:
        groups = config.setdefault('hooks', {}).setdefault(evt, [])
        if not isinstance(groups, list):
            print(f'  WARNING: hooks.{evt} is not a list; skipping.')
            return False
        already = any(
            isinstance(group, dict) and any(
                isinstance(item, dict) and 'task-island/codex_hook.py' in str(item.get('command', ''))
                for item in group.get('hooks', []) if isinstance(group.get('hooks'), list)
            ) for group in groups
        )
        if not already:
            groups.append({'hooks': [{'type': 'command', 'command': command, 'timeout': 3}]})
    config_path.write_text(json.dumps(config, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'  Codex hooks: {config_path} (existing entries retained)')
    return True


def install(home: Path) -> None:
    print('✦  Task Island — Free multi-task status overlay')
    hammerspoon_dir = home / '.hammerspoon'
    hammerspoon_dir.mkdir(parents=True, exist_ok=True)
    island_dir = hammerspoon_dir / 'task-island'
    island_dir.mkdir(exist_ok=True)

    token_path = island_dir / 'token.txt'
    if token_path.exists():
        token = token_path.read_text(encoding='utf-8').strip()
        if len(token) < 32:
            raise RuntimeError('Existing Task Island token is unexpectedly short; please check it manually.')
    else:
        token = secrets.token_hex(32)
        token_path.write_text(token + '\n', encoding='utf-8')
        token_path.chmod(0o600)
    copy_files(ROOT / 'hammerspoon', island_dir)
    shutil.copy2(ROOT / 'integrations' / 'codex_hook.py', island_dir / 'codex_hook.py')
    print(f'  Island files: {island_dir}')

    init_path = hammerspoon_dir / 'init.lua'
    current = init_path.read_text(encoding='utf-8') if init_path.exists() else ''
    if '-- Task Island (start)' not in current:
        if init_path.exists():
            backup(init_path)
        init_path.write_text(current.rstrip('\n') + SNIPPET, encoding='utf-8')
        print('  Added Task Island to existing Hammerspoon configuration')
    else:
        print('  Hammerspoon entry already present')

    merge_codex_hooks(home, island_dir / 'codex_hook.py')

    chrome = home / 'TaskIsland-Chrome-Extension'
    copy_files(ROOT / 'chrome-extension', chrome)
    (chrome / 'config.js').write_text(
        '/* Local-only key. Do not publish this folder. */\n'
        f'const TASK_ISLAND_KEY = {json.dumps(token)};\n', encoding='utf-8')
    print(f'  Chrome extension: {chrome}')

    vscode = home / '.vscode' / 'extensions' / 'localtaskisland.task-island-monitor-0.1.0'
    copy_files(ROOT / 'vscode-extension', vscode)
    (vscode / 'config.json').write_text(json.dumps({'key': token}) + '\n', encoding='utf-8')
    print(f'  VS Code extension: {vscode} (restart VS Code)')

    print('''\n✅ Files installed. Next steps:
   1) Install Hammerspoon (free): brew install --cask hammerspoon
   2) Open Hammerspoon -> menu bar icon -> Reload Config.
   3) Chrome: chrome://extensions -> Developer mode -> Load unpacked
      Select the TaskIsland-Chrome-Extension folder in your home directory.
   4) Restart VS Code. Ensure terminal shell integration is enabled.
   5) Restart Codex or open a new session. Review/trust any new hooks.
   6) Click the ◉ menu bar icon -> Demo to test the floating island.
   Keyboard: Control + Option + Command + I = expand/collapse.
   Server: localhost:47839; no cloud or API charges.
''')


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--home', type=Path, default=Path.home(), help='Alternate home (for tests)')
    parser.add_argument('--force-nonmac', action='store_true', help='For developer testing only')
    args = parser.parse_args()
    if platform.system() != 'Darwin' and not args.force_nonmac:
        sys.exit('Install on macOS, or use --force-nonmac for a disposable test home.')
    install(args.home.expanduser().resolve())


if __name__ == '__main__':
    main()
