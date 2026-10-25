'use strict';
// VM-based unit test: fake VS Code lifecycle so no local editor is required.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const EventEmitter = require('node:events');
const path = require('node:path');
(async () => {
  const handlers = {};
  const requests = [];
  const vscode = {
    tasks: {
      onDidStartTask: cb => {handlers.start = cb;return {dispose(){}};},
      onDidEndTaskProcess: cb => {handlers.endProcess = cb;return {dispose(){}};},
      onDidEndTask: cb => {handlers.endTask = cb;return {dispose(){}};},
    },
    window: {showInformationMessage(){}},
    commands: {registerCommand(){return {dispose(){}};}},
  };
  const http = {request(options, cb) {
    const req = new EventEmitter();
    req.end = data => { requests.push(JSON.parse(data)); if (cb) cb({resume(){}}); };
    req.destroy = () => {};
    return req;
  }};
  const sandbox = {require(name){
    if(name==='vscode')return vscode;
    if(name==='http')return http;
    if(name==='crypto')return require('node:crypto');
    if(name==='./config.json')return {key:'LOCAL_TEST_ONLY'};
    throw new Error('Unexpected require '+name);
  }, exports:{}, setTimeout, Buffer};
  const script = path.join(__dirname,'..','vscode-extension','extension.js');
  vm.runInNewContext(fs.readFileSync(script,'utf8'),sandbox,{filename:script});
  sandbox.exports.activate({subscriptions:[]});
  const execution={task:{name:'Test without exit status'}};
  handlers.start({execution});
  handlers.endTask({execution});
  await new Promise(resolve=>setTimeout(resolve,850));
  const last = requests.at(-1);
  assert.equal(last.status,'idle');
  assert.match(last.detail,/unknown/i);
  assert.notEqual(last.status,'done');
  const execution2={task:{name:'Known exit code'}};
  handlers.start({execution:execution2});
  handlers.endProcess({execution:execution2,exitCode:0});
  assert.equal(requests.at(-1).status,'done');
  console.log('VS Code lifecycle: unknown -> idle, exit 0 -> done OK');
})().catch(e=>{console.error(e);process.exitCode=1});
