'use strict';
const vscode = require('vscode');
const http = require('http');
const crypto = require('crypto');
const {key} = require('./config.json');
const WINDOW_ID = crypto.randomBytes(5).toString('hex');
let sequence = 0;
const executions = new WeakMap();
const ends = new Set();

function emit(event) {
  if (!key || key === 'REPLACE_VIA_INSTALLER') return;
  const payload = JSON.stringify({...event,source:'vscode'});
  const req = http.request({hostname:'127.0.0.1',port:47839,path:'/event',method:'POST',
    timeout:1000, headers:{'Content-Type':'application/json','Content-Length':Buffer.byteLength(payload),'X-Island-Key':key}},res=>res.resume());
  req.on('error',()=>{});req.on('timeout',()=>req.destroy());req.end(payload);
}
function title(name){return `VS Code · ${String(name||'Task').slice(0,70)}`;}
function safeCommand(command){
  // Deliberately do not surface full terminal command lines: they may contain tokens.
  const parts=String(command||'').trim().split(/\s+/);
  const executable=(parts[0]||'').split('/').pop();
  const safe=['npm','npx','pnpm','yarn','pytest','python','python3','swift','cargo','go','make','git','node','bun'];
  if(!safe.includes(executable)) return 'Terminal command';
  const action=(parts[1]||'').replace(/[^a-zA-Z-]/g,'');
  const trusted=['test','run','build','lint','check','dev','format','compile','start'];
  return action && trusted.includes(action)?`${executable} ${action}`:executable;
}
function register(context){
  context.subscriptions.push(vscode.tasks.onDidStartTask(e=>{
    const id=`vscode:${WINDOW_ID}:task-${++sequence}`;
    executions.set(e.execution,id);
    emit({id,status:'running',title:title(e.execution.task.name),detail:'VS Code task running'});
  }));
  context.subscriptions.push(vscode.tasks.onDidEndTaskProcess(e=>{
    const id=executions.get(e.execution);
    if(!id) return;
    ends.add(id);
    emit({id,status:e.exitCode===0?'done':'error',title:title(e.execution.task.name),
      detail:e.exitCode===0?'Task completed':'Task exited with error / unknown code'});
  }));
  context.subscriptions.push(vscode.tasks.onDidEndTask(e=>{
    const id=executions.get(e.execution);
    if(!id) return;
    // A process-exit event may arrive immediately before or after onDidEndTask.
    setTimeout(()=>{
      if(!ends.has(id)) emit({id,status:'idle',title:title(e.execution.task.name),detail:'Task ended (exit code unavailable; result unknown)'});
      ends.delete(id);
    },750);
  }));
  if(vscode.window.onDidStartTerminalShellExecution && vscode.window.onDidEndTerminalShellExecution){
    context.subscriptions.push(vscode.window.onDidStartTerminalShellExecution(e=>{
      const id=`vscode:${WINDOW_ID}:shell-${++sequence}`;
      executions.set(e.execution,id);
      emit({id,status:'running',title:title(e.terminal.name),
        detail:`Running ${safeCommand(e.execution.commandLine.value)}`});
    }));
    context.subscriptions.push(vscode.window.onDidEndTerminalShellExecution(e=>{
      const id=executions.get(e.execution);
      if(!id) return;
      const ok=e.exitCode===0;
      emit({id,status:ok?'done':e.exitCode===undefined?'idle':'error',
        title:title(e.terminal.name),detail:ok?'Terminal command finished':
        e.exitCode===undefined?'Command ended (exit code unknown)':'Command failed'});
    }));
  }
  const command=vscode.commands.registerCommand('taskIsland.test',()=>{
    emit({id:`vscode:${WINDOW_ID}:test`,title:'VS Code · Test notification',
      status:'done',detail:'VS Code extension connected'});
    vscode.window.showInformationMessage('Task Island: test event sent.');
  });
  context.subscriptions.push(command);
}
exports.activate=register;
exports.deactivate=()=>{};
