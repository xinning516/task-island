/* Task Island v0.3.1: separate local-server and real ChatGPT page diagnostics. */
'use strict';
const pageResult = document.getElementById('page-result');
const localResult = document.getElementById('result');
document.getElementById('version').textContent = `v${chrome.runtime.getManifest().version}`;
function show(el, message, success) {
  el.textContent = message;
  el.className = 'hint ' + (success ? 'ok' : 'bad');
}
document.getElementById('test').addEventListener('click', () => {
  localResult.textContent = 'Testing local server...';
  chrome.runtime.sendMessage({kind:'test'}, result => {
    const err = chrome.runtime.lastError;
    show(localResult, err ? `Extension error: ${err.message}` :
      result && result.ok ? '✓ Local notification delivered.' :
      `✕ No local connection (${result && (result.status || result.reason) || 'unknown'}). Reload Hammerspoon.`,
      !err && Boolean(result && result.ok));
  });
});
document.getElementById('check-page').addEventListener('click', () => {
  pageResult.textContent = 'Checking current Chrome tab...';
  chrome.tabs.query({active:true, lastFocusedWindow:true}, tabs => {
    const queryError = chrome.runtime.lastError;
    if (queryError || !tabs || !tabs.length || !Number.isInteger(tabs[0].id)) {
      show(pageResult, '✕ Cannot find this tab. Open a normal ChatGPT webpage and retry.', false);
      return;
    }
    chrome.tabs.sendMessage(tabs[0].id, {kind:'tracker_ping'}, result => {
      const err = chrome.runtime.lastError;
      if (err || !result || !result.alive) {
        show(pageResult, '✕ Webpage tracker not detected. Open https://chatgpt.com, refresh with ⌘R, then retry. If this persists, check the extension installation path.', false);
        return;
      }
      if (!result.ok) {
        show(pageResult, `Webpage tracker: ✓ Loaded
Server delivery: ✕ ${result.reason || 'not accepted'}
Reload Hammerspoon and check its Console.`, false);
        return;
      }
      show(pageResult, `✓ Webpage tracker connected!
Status: ${result.status}
${result.title || 'ChatGPT tab'}
Check the Task Island panel.`, true);
    });
  });
});
