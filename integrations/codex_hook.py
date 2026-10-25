#!/usr/bin/env python3
"""Tiny Codex lifecycle hook. Never includes prompt or response text.

Codex Stop hooks expect JSON on stdout; printing {} is a neutral response.
Failures are deliberately swallowed so code agents are not interrupted.
"""
import json
import os
import pathlib
import sys
import urllib.request

BASE = pathlib.Path.home() / '.hammerspoon' / 'task-island'


def event_from_hook(data):
    name = data.get('hook_event_name', '')
    status = {
        'UserPromptSubmit': 'running',
        'PostToolUse': 'running',
        'Stop': 'done',
        'PermissionRequest': 'waiting',
        'Interrupt': 'idle',
    }.get(name)
    if not status:
        return None
    sid = str(data.get('session_id') or 'unknown')[:130]
    cwd = str(data.get('cwd') or '')
    project = os.path.basename(cwd.rstrip('/')) or 'Session'
    detail = {
        'running': 'Processing request',
        'done': 'Codex turn completed',
        'waiting': 'Needs approval',
        'idle': 'Task interrupted',
    }[status]
    return {
        'source': 'codex', 'id': 'codex:' + sid,
        'status': status, 'title': 'Codex · ' + project[:80],
        'detail': detail,
    }


def main():
    try:
        payload = json.load(sys.stdin)
        event = event_from_hook(payload)
        if event:
            token = (BASE / 'token.txt').read_text(encoding='utf-8').strip()
            req = urllib.request.Request('http://127.0.0.1:47839/event',
                data=json.dumps(event).encode('utf-8'),
                headers={'Content-Type': 'application/json', 'X-Island-Key': token},
                method='POST')
            with urllib.request.urlopen(req, timeout=0.7) as response:
                response.read()
    except Exception:
        pass
    # Stop (also SubagentStop) must output valid JSON even when our server is down.
    print('{}')


if __name__ == '__main__':
    main()
