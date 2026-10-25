-- Task Island v0.3 · Compact multi-session UI for macOS (Hammerspoon)
-- Existing event API and integrations are unchanged. All events stay on localhost.
local M = {}
local HOME = os.getenv("HOME") or ""
local BASE = HOME .. "/.hammerspoon/task-island"
local PORT, MAX_TASKS = 47839, 30
local MINI_W, TINY_W, MINI_H = 210, 168, 41
local FULL_W, FULL_MAX_H = 344, 372
local tasks = {}
local expanded, pinned, hovering = false, false, false  -- v0.1 expanded state intentionally ignored
local muted = hs.settings.get("taskIsland.muted") or false
local hoverEnabled = hs.settings.get("taskIsland.compact.hoverEnabled") ~= false
local tiny = hs.settings.get("taskIsland.compact.tiny") or false
-- Save background transparency independently from app integrations.
local islandOpacity = tonumber(hs.settings.get("taskIsland.visual.opacity")) or 0.978
if islandOpacity < 0.4 or islandOpacity > 1.0 then islandOpacity = 0.978 end
local visible = true
-- Source visibility is display-only: events continue to be tracked locally.
local shown = {
  codex=hs.settings.get("taskIsland.source.codex") ~= false,
  vscode=hs.settings.get("taskIsland.source.vscode") ~= false,
  chatgpt=hs.settings.get("taskIsland.source.chatgpt") ~= false,
}
local flash, flashSequence = nil, 0
local hoverTimer, leaveTimer = nil, nil
local hoverSuppressedUntil = 0
-- v0.5 · Remember manual placement on this or another display.
local POSITION_KEY = "taskIsland.ui.position"
local savedPosition = hs.settings.get(POSITION_KEY)
if type(savedPosition) ~= "table"
   or type(savedPosition.cx) ~= "number"
   or type(savedPosition.y) ~= "number"
   or savedPosition.cx ~= savedPosition.cx or savedPosition.y ~= savedPosition.y then
  savedPosition = nil
end
local dragActive, dragTap, dragStartMouse, dragStartFrame, dragFrame = false, nil, nil, nil, nil
local function clamp(value, bottom, top)
  if top < bottom then return bottom end
  return math.max(bottom, math.min(top, value))
end
local function screenAtPoint(point)
  if not point or type(point.x) ~= "number" or type(point.y) ~= "number" then return nil end
  for _, screen in ipairs(hs.screen.allScreens()) do
    local f = screen:fullFrame()
    if point.x >= f.x and point.x < f.x + f.w
       and point.y >= f.y and point.y < f.y + f.h then
      return screen
    end
  end
  return nil
end

local function readfile(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local result = f:read("*a")
  f:close()
  return result
end
local secret = readfile(BASE .. "/token.txt")
if not secret then
  hs.alert.show("Task Island: token.txt missing. Run original installer first.")
  return M
end
secret = secret:gsub("%s+$", "")

local allowed = {codex=true, vscode=true, chatgpt=true}
local statuses = {running=true, done=true, waiting=true, error=true, idle=true, closed=true}
local rank = {waiting=1, error=2, running=3, done=4, idle=5}
local function clean(value, length)
  if type(value) ~= "string" then return "" end
  return value:sub(1, length):gsub("[%c]", " ")
end
local function tableRows()
  local rows = {}
  for _, task in pairs(tasks) do
    if shown[task.source] then rows[#rows + 1] = task end
  end
  table.sort(rows, function(a, b)
    if rank[a.status] ~= rank[b.status] then return rank[a.status] < rank[b.status] end
    return a.updatedAt > b.updatedAt
  end)
  while #rows > MAX_TASKS do table.remove(rows) end
  return rows
end
local function currentFrame()
  local savedScreen = savedPosition and screenAtPoint({x=savedPosition.cx, y=savedPosition.y})
  local bounds = (savedScreen or hs.screen.mainScreen()):frame()
  local count = #tableRows()
  local w = expanded and FULL_W or (tiny and TINY_W or MINI_W)
  local h = expanded and math.min(FULL_MAX_H, 96 + math.min(count, 5) * 50) or MINI_H
  if expanded and count == 0 then h = 160 end
  -- If a new GPT event arrives during dragging, keep the dragged window position.
  if dragActive and dragFrame then
    return {x=dragFrame.x, y=dragFrame.y, w=w, h=h}
  end
  local center = (savedScreen and savedPosition.cx) or (bounds.x + bounds.w / 2)
  local top = (savedScreen and savedPosition.y) or (bounds.y + 5)
  return {
    x=math.floor(clamp(center - w / 2, bounds.x, bounds.x + bounds.w - w)),
    y=math.floor(clamp(top, bounds.y, bounds.y + bounds.h - h)), w=w, h=h
  }
end

local bridge = hs.webview.usercontent.new("taskIslandBridge")
local html = readfile(BASE .. "/dashboard.html")
if not html then
  hs.alert.show("Task Island: dashboard.html missing")
  return M
end
local view = hs.webview.new(currentFrame(), {
  javaScriptEnabled = true,
  developerExtrasEnabled = false,
}, bridge)
  :windowStyle({"borderless"})
  :transparent(true)
  :shadow(false)
  :level(hs.drawing.windowLevels.floating)
  :behaviorAsLabels({"canJoinAllSpaces", "fullScreenAuxiliary"})
  :html(html)
  :show()

local function sendUI()
  if not view then return end
  local state = {
    expanded=expanded, pinned=pinned, tiny=tiny, muted=muted,
    hoverEnabled=hoverEnabled, flash=flash, tasks=tableRows(), opacity=islandOpacity, visibleSources=shown
  }
  view:evaluateJavaScript("window.updateTaskIsland && window.updateTaskIsland(" .. hs.json.encode(state) .. ");")
end
local function resize()
  view:frame(currentFrame())
  sendUI()
end
local function showExpanded(value)
  if expanded == value then return end
  expanded = value
  resize()
end
local function cancelTimer(timer)
  if timer then timer:stop() end
end
local function toggle()
  cancelTimer(hoverTimer)
  cancelTimer(leaveTimer)
  if expanded then
    pinned, hovering = false, false
    hoverSuppressedUntil = hs.timer.secondsSinceEpoch() + 1.1
    showExpanded(false)
  else
    pinned = true
    showExpanded(true)
  end
  sendUI()
end
local function toggleSound()
  muted = not muted
  hs.settings.set("taskIsland.muted", muted)
  sendUI()
end
-- This changes ONLY the dark panel background; foreground text stays opaque.
local function setIslandOpacity(value)
  local nextValue = tonumber(value)
  if not nextValue then return end
  islandOpacity = math.max(0.4, math.min(1.0, nextValue))
  hs.settings.set("taskIsland.visual.opacity", islandOpacity)
  sendUI()
end
local function makeOpacityMenu()
  local choices = {}
  for _, percent in ipairs({100, 98, 90, 80, 70, 60, 50, 40}) do
    local target = percent / 100
    choices[#choices + 1] = {
      title=string.format("%d%%", percent),
      checked=math.abs(islandOpacity - target) < 0.005,
      fn=function() setIslandOpacity(target) end,
    }
  end
  choices[#choices + 1] = {title="-"}
  choices[#choices + 1] = {title="Custom... (40-100%)", fn=function()
    local button, value = hs.dialog.textPrompt(
      "Task Island opacity", "Enter 40 to 100 (%):",
      tostring(math.floor(islandOpacity * 100 + 0.5)), "Apply", "Cancel")
    if button ~= "Apply" then return end
    local digits = tostring(value or ""):match("^%s*(%d+%.?%d*)%%?%s*$")
    local number = tonumber(digits)
    if number and number >= 40 and number <= 100 then
      setIslandOpacity(number / 100)
    else
      hs.alert.show("Enter an opacity between 40 and 100%.")
    end
  end}
  return choices
end
local function setTiny(value)
  tiny = value
  hs.settings.set("taskIsland.compact.tiny", tiny)
  resize()
end
local function setShown(source, value)
  if not allowed[source] then return end
  shown[source] = value
  hs.settings.set("taskIsland.source." .. source, value)
  if flash and flash.source == source and not value then flash = nil end
  if expanded then resize() else sendUI() end
end
local function setHoverEnabled(value)
  hoverEnabled = value
  hs.settings.set("taskIsland.compact.hoverEnabled", hoverEnabled)
  if not hoverEnabled and not pinned then
    cancelTimer(hoverTimer)
    cancelTimer(leaveTimer)
    showExpanded(false)
  end
  sendUI()
end
local function mouseEntered()
  hovering = true
  cancelTimer(leaveTimer)
  if not hoverEnabled or pinned or expanded or hs.timer.secondsSinceEpoch() < hoverSuppressedUntil then return end
  cancelTimer(hoverTimer)
  hoverTimer = hs.timer.doAfter(0.27, function()
    if hovering and hoverEnabled and not pinned then showExpanded(true) end
  end)
end
local function mouseLeft()
  if dragActive then return end
  hovering = false
  cancelTimer(hoverTimer)
  if pinned or not expanded then return end
  cancelTimer(leaveTimer)
  leaveTimer = hs.timer.doAfter(0.65, function()
    if not hovering and not pinned then showExpanded(false) end
  end)
end
-- Drag only from the empty titlebar grip; status rows and buttons keep normal clicks.
-- Observe global mouse-drag/up events only during a drag gesture.
local function finishDrag(mouse)
  if not dragActive then return end
  dragActive = false
  if dragTap then dragTap:stop(); dragTap = nil end
  local f = view:frame()
  local screen = screenAtPoint(mouse) or screenAtPoint({x=f.x+f.w/2, y=f.y+f.h/2})
                 or hs.screen.mainScreen()
  local bounds = screen:frame()  -- Keep the entire island away from the Dock and menu bar.
  local x = math.floor(clamp(f.x, bounds.x, bounds.x + bounds.w - f.w))
  local y = math.floor(clamp(f.y, bounds.y, bounds.y + bounds.h - f.h))
  view:topLeft({x=x, y=y})
  savedPosition = {cx=x + f.w / 2, y=y}
  hs.settings.set(POSITION_KEY, savedPosition)
  dragFrame, dragStartFrame, dragStartMouse = nil, nil, nil
  -- The hover-out timer was suppressed during dragging; restore it if needed.
  local p = mouse or hs.mouse.absolutePosition()
  hovering = (p.x >= x and p.x < x + f.w and p.y >= y and p.y < y + f.h)
  if expanded and not pinned and not hovering then
    cancelTimer(leaveTimer)
    leaveTimer = hs.timer.doAfter(1.2, function()
      if not hovering and not pinned and not dragActive then showExpanded(false) end
    end)
  end
end
local function beginDrag()
  if dragActive or not expanded then return end
  cancelTimer(hoverTimer)
  cancelTimer(leaveTimer)
  dragStartMouse = hs.mouse.absolutePosition()
  dragStartFrame = view:frame()
  dragFrame = {x=dragStartFrame.x, y=dragStartFrame.y}
  dragActive = true
  local types = hs.eventtap.event.types
  local ok, tap = pcall(function()
    return hs.eventtap.new({types.leftMouseDragged, types.leftMouseUp}, function(event)
      if not dragActive then return false end
      if event:getType() == types.leftMouseUp then
        finishDrag(event:location())
      else
        local point = event:location()
        local x = math.floor(dragStartFrame.x + point.x - dragStartMouse.x + 0.5)
        local y = math.floor(dragStartFrame.y + point.y - dragStartMouse.y + 0.5)
        dragFrame = {x=x, y=y}
        view:topLeft({x=x, y=y})
      end
      return false  -- Do not consume OS mouse events.
    end)
  end)
  if not ok or not tap then
    dragActive, dragFrame = false, nil
    hs.alert.show("Task Island: Unable to start mouse drag (check Hammerspoon permissions)")
    return
  end
  dragTap = tap
  local started = pcall(function() dragTap:start() end)
  if not started or not dragTap:isEnabled() then
    dragTap:stop(); dragTap = nil
    dragActive, dragFrame = false, nil
    hs.alert.show("Task Island: Enable Hammerspoon Accessibility to drag")
  end
end
local function resetIslandPosition()
  if dragActive then finishDrag(hs.mouse.absolutePosition()) end
  savedPosition = nil
  hs.settings.clear(POSITION_KEY)
  resize()
end
local function soundFor(status)
  if muted or not ({waiting=true, done=true, error=true})[status] then return end
  local name = status == "done" and "Glass" or status == "waiting" and "Funk" or "Basso"
  local sound = hs.sound.getByName(name)
  if sound then sound:play() end
end
local function flashStatus(source, status)
  flashSequence = flashSequence + 1
  local seq = flashSequence
  flash = {source=source, status=status}
  hs.timer.doAfter(4.2, function()
    if flashSequence == seq then flash = nil; sendUI() end
  end)
end
local function onEvent(event)
  if type(event) ~= "table" then return false, "bad JSON" end
  local source = clean(event.source, 30):lower()
  local id = clean(event.id, 180)
  local status = clean(event.status, 20):lower()
  if not allowed[source] or id == "" or not statuses[status] then
    return false, "invalid source/id/status"
  end
  local old = tasks[id]
  if status == "closed" then
    -- Chrome tab closed: remove that tab only. Other ChatGPT tabs are unaffected.
    if old and old.source == source then tasks[id] = nil end
    if expanded then resize() else sendUI() end
    return true, "removed"
  end
  local now = os.time() * 1000
  local title = clean(event.title, 130)
  if title == "" then title = source end
  local task = {
    id=id, source=source, title=title, detail=clean(event.detail, 180),
    status=status, url=clean(event.url, 350),
    startedAt=(old and old.startedAt or now), updatedAt=now
  }
  if status == "running" and (not old or old.status ~= "running") then task.startedAt = now end
  tasks[id] = task
  local total = 0
  for _ in pairs(tasks) do total = total + 1 end
  if total > MAX_TASKS then
    local evictId, evictTime = nil, math.huge
    for key, candidate in pairs(tasks) do
      if key ~= id and candidate.status ~= "running" and candidate.status ~= "waiting"
         and candidate.updatedAt < evictTime then
        evictId, evictTime = key, candidate.updatedAt
      end
    end
    if evictId then tasks[evictId] = nil end
  end
  if shown[source] and (not old or old.status ~= status) then
    soundFor(status)
    if status == "done" or status == "waiting" or status == "error" then
      flashStatus(source, status) -- brief inline notice without expanding the island
    end
  end
  if expanded then resize() else sendUI() end
  return true, "ok"
end
local function clearDone()
  for id, task in pairs(tasks) do
    if task.status ~= "running" and task.status ~= "waiting" then tasks[id] = nil end
  end
  if expanded then resize() else sendUI() end
end
local function safeOpen(task)
  if task.source == "chatgpt" then
    if task.url:match("^https://chatgpt%.com/") then
      hs.urlevent.openURL(task.url)
    else
      hs.urlevent.openURL("https://chatgpt.com/")
    end
  elseif task.source == "codex" then
    hs.application.launchOrFocus("Codex")
  else
    hs.application.launchOrFocus("Visual Studio Code")
  end
end

bridge:setCallback(function(msg)
  local body = msg and msg.body or {}
  if type(body) ~= "table" then return end
  if body.action == "toggle" then toggle()
  elseif body.action == "hoverIn" then mouseEntered()
  elseif body.action == "hoverOut" then mouseLeft()
  elseif body.action == "pin" then
    pinned = not pinned
    if pinned then showExpanded(true) end
    sendUI()
  elseif body.action == "dragStart" then beginDrag()
  elseif body.action == "dragStop" then finishDrag(hs.mouse.absolutePosition())
  elseif body.action == "sound" then toggleSound()
  elseif body.action == "clear" then clearDone()
  elseif body.action == "open" and type(body.id) == "string" then
    local task = tasks[body.id]
    if task then safeOpen(task) end
  end
end)

-- Keep the existing localhost protocol so no hooks/extensions require reinstalling.
local server = hs.httpserver.new(false, false)
server:setInterface("127.0.0.1")
server:setPort(PORT)
server:maxBodySize(16384)
server:setCallback(function(method, path, headers, body)
  local responseHeaders = {
    ["Content-Type"] = "application/json; charset=utf-8",
    ["Cache-Control"] = "no-store",
    ["Access-Control-Allow-Origin"] = "*",
    ["Access-Control-Allow-Headers"] = "Content-Type, X-Island-Key",
    ["Access-Control-Allow-Methods"] = "POST, GET, OPTIONS"
  }
  if method == "OPTIONS" then return "", 204, responseHeaders end
  if method == "GET" and path == "/health" then
    return '{"ok":true,"name":"Task Island"}', 200, responseHeaders
  end
  if method ~= "POST" or path ~= "/event" then
    return '{"error":"not found"}', 404, responseHeaders
  end
  local key = (headers["X-Island-Key"] or headers["x-island-key"] or "")
  if key ~= secret then return '{"error":"unauthorized"}', 401, responseHeaders end
  local ok, obj = pcall(hs.json.decode, body or "")
  if not ok then return '{"error":"invalid JSON"}', 400, responseHeaders end
  local success, info = onEvent(obj)
  if not success then return hs.json.encode({error=info}), 400, responseHeaders end
  return '{"ok":true}', 200, responseHeaders
end)
server:start()

local menu = hs.menubar.new()
menu:setTitle("◉")
menu:setTooltip("Task Island · Compact multi-task monitor")
menu:setMenu(function()
  return {
    {title=expanded and "Collapse island" or "Expand (pin) island", fn=toggle},
    {title=visible and "Hide island" or "Show island", fn=function()
      visible = not visible
      if visible then view:show() else view:hide() end
    end},
    {title=hoverEnabled and "✓ Expand on hover" or "Expand on hover", fn=function()
      setHoverEnabled(not hoverEnabled)
    end},
    {title=tiny and "✓ Extra-small pill (168px)" or "Extra-small pill (168px)", fn=function()
      setTiny(not tiny)
    end},
    {title="── Display sources ──", disabled=true},
    {title=shown.codex and "✓ Show Codex" or "Show Codex", fn=function()
      setShown("codex", not shown.codex)
    end},
    {title=shown.vscode and "✓ Show VS Code" or "Show VS Code", fn=function()
      setShown("vscode", not shown.vscode)
    end},
    {title=shown.chatgpt and "✓ Show ChatGPT" or "Show ChatGPT", fn=function()
      setShown("chatgpt", not shown.chatgpt)
    end},
    {title=string.format("Island opacity (%d%%)", math.floor(islandOpacity * 100 + 0.5)),
      menu=makeOpacityMenu()},
    {title="Reset island position (top center)", fn=resetIslandPosition},
    {title=muted and "Unmute sounds" or "Mute sounds", fn=toggleSound},
    {title="Clear completed", fn=clearDone},
    {title="Demo: show three tasks", fn=function()
      onEvent({source="codex", id="demo-codex", title="Codex · Refactor", detail="Editing files", status="running"})
      onEvent({source="vscode", id="demo-vscode", title="VS Code · Tests", detail="Running npm test", status="running"})
      onEvent({source="chatgpt", id="demo-gpt", title="ChatGPT · Research", detail="Answer is ready", status="done"})
      if not visible then visible = true; view:show() end
    end},
    {title="Demo: three ChatGPT tabs", fn=function()
      onEvent({source="chatgpt", id="demo-gpt-research", title="ChatGPT · Research", detail="Tab A · Generating", status="running"})
      onEvent({source="chatgpt", id="demo-gpt-coding", title="ChatGPT · Coding", detail="Tab B · Generating", status="running"})
      onEvent({source="chatgpt", id="demo-gpt-writing", title="ChatGPT · Writing", detail="Tab C · Generating", status="running"})
      if not visible then visible = true; view:show() end
    end},
    {title="Local server: 127.0.0.1:" .. PORT, disabled=true}
  }
end)

hs.hotkey.bind({"cmd", "ctrl", "alt"}, "I", function()
  if not visible then visible = true; view:show() end
  toggle()
end)

-- CSS updates the elapsed timers every second. Refresh only when tasks expire.
local ticker = hs.timer.doEvery(15, function()
  local now, changed = os.time() * 1000, false
  for id, task in pairs(tasks) do
    if (task.status == "done" or task.status == "error" or task.status == "idle")
       and (now - task.updatedAt) > 45 * 60 * 1000 then
      tasks[id] = nil
      changed = true
    end
  end
  if changed then
    if expanded then resize() else sendUI() end
  end
end)
hs.timer.doAfter(0.8, sendUI)
M.server, M.view, M.menu, M.ticker = server, view, menu, ticker
M.toggle, M.onEvent, M.setShown = toggle, onEvent, setShown
return M
