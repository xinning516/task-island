'use strict';
importScripts('config.js'); // Installer writes a random, local-only shared key here.

async function sendToIsland(event) {
  try {
    const response = await fetch('http://127.0.0.1:47839/event', {
      method:'POST',
      headers:{'Content-Type':'application/json','X-Island-Key':TASK_ISLAND_KEY},
      body:JSON.stringify(event),
    });
    return {ok:response.ok, status:response.status};
  } catch (err) {
    return {ok:false, reason:'Task Island / Hammerspoon is not running'};
  }
}

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (!message || !['update','test'].includes(message.kind)) return;
  const tabId = sender.tab ? sender.tab.id : 'test';
  if (message.kind === 'test') {
    sendToIsland({source:'chatgpt',id:'chatgpt:test',status:'done',
      title:'ChatGPT · Test notification',detail:'Chrome extension connected',url:'https://chatgpt.com/'})
      .then(sendResponse);
    return true;
  }
  const pageUrl = sender.url || (sender.tab && sender.tab.url) || '';
  if (!sender.tab || !/^https:\/\/chatgpt\.com\//.test(pageUrl)) return;
  const evt = message.event || {};
  // Never send the prompt, the answer, or page content. Only a short title and state.
  const status = String(evt.status || 'idle');
  if (!['running','done','idle','error'].includes(status)) return;
  sendToIsland({
    source:'chatgpt', id:`chatgpt:tab-${tabId}`, status,
    title: String(evt.title || `ChatGPT · Tab ${tabId}`).trim() === 'ChatGPT · Browser'
      ? `ChatGPT · Tab ${tabId}` : String(evt.title || `ChatGPT · Tab ${tabId}`).slice(0,100),
    detail: `Tab ${tabId} · ` + (status === 'running' ? 'Generating response' :
      status === 'done' ? 'Answer finished' : 'Chat opened'),
    url:pageUrl
  }).then(sendResponse);
  return true;
});

// A closed tab must disappear immediately without removing other GPT sessions.
// This event does not require reading the tab's URL or requesting tab history.
chrome.tabs.onRemoved.addListener(tabId => {
  sendToIsland({source:'chatgpt',id:`chatgpt:tab-${tabId}`,status:'closed'});
});
