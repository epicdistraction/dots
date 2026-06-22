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
