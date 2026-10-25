(() => {
  'use strict';
  // Ignore accidental duplicate injection in the same document.
  if (globalThis.__taskIslandTrackerV031) return;
  globalThis.__taskIslandTrackerV031 = true;
  // chatgpt.com is a changing third-party web UI: DOM status detection is best-effort.
  // Observe controls and do not inspect the prompt or response text.
  let status = 'idle';
  let announced = false;
  let lastTitle = '';
  let stopSeen = false;
  let submittedAt = 0;
  let stopVanishedAt = 0;
  let previousUrl = location.href;
  let scheduled = false;
  const stopSelectors = [
    '[data-testid="stop-button"]',
    'button[aria-label="Stop streaming"]',
    'button[aria-label="Stop generating"]',
    'button[aria-label="Stop response"]',
    'button[aria-label="停止生成"]',
    'button[title="Stop generating"]'
  ];
  // Return the actual Hammerspoon response so the popup can diagnose a real page event.
  const send = (next, force = false) => {
    const rawTitle = document.title.replace(/\s*[|–—-]\s*ChatGPT\s*$/, '').trim();
    const title = rawTitle && rawTitle !== 'ChatGPT' ? `ChatGPT · ${rawTitle.slice(0,64)}` : 'ChatGPT · Browser';
    if (!force && announced && next === status && title === lastTitle) {
      return Promise.resolve({ok:true, skipped:true});
    }
    announced = true;
    status = next;
    lastTitle = title;
    return new Promise(resolve => {
      try {
        chrome.runtime.sendMessage({kind:'update',event:{status:next,title}}, response => {
          const err = chrome.runtime.lastError;
          resolve(err ? {ok:false, reason:err.message} : (response || {ok:false,reason:'No reply from extension background'}));
        });
      } catch (err) {
        resolve({ok:false, reason:String(err)});
      }
    });
  };
  const isStop = () => {
    for(const css of stopSelectors){ if(document.querySelector(css)) return true; }
    // Last-resort accessible labels in variants of the ChatGPT web UI.
    return Array.from(document.querySelectorAll('button[aria-label]'))
      .some(button => /^stop( generating| streaming| response)?$/i.test(button.getAttribute('aria-label') || ''));
  };
  const check = () => {
    scheduled = false;
    if (location.href !== previousUrl) {
      previousUrl = location.href;
      stopSeen = false;
      submittedAt = 0;
      stopVanishedAt = 0;
      send('idle');
    }
    const stop = isStop();
    if(stop) {
      stopSeen = true;
      stopVanishedAt = 0;
      send('running');
    } else if(stopSeen && status === 'running') {
      if (!stopVanishedAt) stopVanishedAt = Date.now();
      // Debounce to avoid false completion during UI reconciliation/tool transitions.
      if(Date.now() - stopVanishedAt > 900) {
        stopSeen = false;
        submittedAt = 0;
        stopVanishedAt = 0;
        send('done');
      }
    } else if (status === 'running' && submittedAt && Date.now() - submittedAt > 120000 && !stopSeen) {
      // We cannot honestly prove a response completed if no stop control appeared.
      // Drop the tentative running state instead of falsely announcing success.
      submittedAt = 0;
      send('idle');
    }
    // Announce an open but idle ChatGPT tab as its own session.
    // When a page's title changes, refresh that row without faking progress.
    if (status === 'idle' || (!stop && !stopSeen)) send(status);
  };
  const schedule = () => {
    if(scheduled) return;
    scheduled = true;
    setTimeout(check, 130);
  };
  const looksLikeComposer = (target) => {
    if(!(target instanceof Element)) return false;
    return Boolean(target.closest('#prompt-textarea,[data-testid="composer-root"],form'));
  };
  const markSubmitted = () => {
    submittedAt = Date.now();
    stopSeen = false;
    stopVanishedAt = 0;
    send('running');
    schedule();
  };
  document.addEventListener('keydown', (event) => {
    if(event.key === 'Enter' && !event.shiftKey && !event.isComposing && looksLikeComposer(event.target)) {
      const tgt = event.target;
      if(tgt.closest('[contenteditable="true"],textarea,#prompt-textarea')) markSubmitted();
    }
  }, true);
  document.addEventListener('click', (event) => {
    if(!(event.target instanceof Element)) return;
    const b = event.target.closest('button');
    if(b && (b.matches('[data-testid="send-button"]') ||
       /^(send|send message|发送)$/i.test(b.getAttribute('aria-label') || ''))) markSubmitted();
  }, true);
  // Called only when the user clicks Check this ChatGPT tab in the extension popup.
  // We force one harmless status event and report whether the local server accepted it.
  chrome.runtime.onMessage.addListener((message, sender, respond) => {
    if (!message || message.kind !== 'tracker_ping') return false;
    send(status, true).then(result => {
      respond({alive:true, ok:Boolean(result && result.ok), status,
        title:lastTitle, version:'0.3.1', reason:result && result.reason || ''});
    });
    return true;
  });
  new MutationObserver(schedule).observe(document.documentElement, {subtree:true,childList:true,attributes:true,attributeFilter:['aria-label','data-testid','disabled']});
  setInterval(schedule, 1200);
  schedule();
})();
