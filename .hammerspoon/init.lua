-- Send the currently focused window to the back
local function sendFocusedWindowToBack()
  local win = hs.window.focusedWindow()

  if not win then
    hs.alert.show("No focused window")
    return
  end

  win:sendToBack()
end

-- Hotkey: Cmd + Ctrl + Alt + B
hs.hotkey.bind({"cmd", "alt"}, "B", sendFocusedWindowToBack)

-- Toggle between the current app and the previously foreground app.
-- Bound to the ISO §/± key, usually keyCode 10 on Mac keyboards.

local currentApp = hs.application.frontmostApplication()
local previousApp = nil

local function sameApp(a, b)
  return a and b and a:pid() == b:pid()
end

local appWatcher = hs.application.watcher.new(function(appName, eventType, app)
  if eventType ~= hs.application.watcher.activated then
    return
  end

  if not app then
    return
  end

  if currentApp and not sameApp(currentApp, app) then
    previousApp = currentApp
  end

  currentApp = app
end)

appWatcher:start()

local function bringPreviousApp()
  if previousApp and previousApp:isRunning() then
    previousApp:activate()
  else
    hs.alert.show("No previous app")
  end
end

local previousAppKey = hs.eventtap.new(
  { hs.eventtap.event.types.keyDown },
  function(event)
    local keyCode = event:getKeyCode()

    -- ISO §/± key is usually keyCode 10
    if keyCode == 10 then
      bringPreviousApp()
      return true
    end

    return false
  end
)

previousAppKey:start()

require("hs.ipc")

local function postSystemKey(key, count)
  count = count or 1

  for _ = 1, count do
    hs.eventtap.event.newSystemKeyEvent(key, true):post()
    hs.timer.usleep(15000)
    hs.eventtap.event.newSystemKeyEvent(key, false):post()
    hs.timer.usleep(15000)
  end
end

function nativeVolumeUp()
  postSystemKey("SOUND_UP")
end

function nativeVolumeDown()
  postSystemKey("SOUND_DOWN")
end

function nativeMute()
  postSystemKey("MUTE")
end
