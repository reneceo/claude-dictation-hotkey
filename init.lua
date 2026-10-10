-- Claude Code dictation on Right Option
--
-- The desktop app's mic button has no keyboard shortcut (anthropics/claude-code#97929).
-- It lives inside an Electron WebArea, which is invisible to the accessibility API
-- until AXManualAccessibility is set on the app -- the reason every published
-- AppleScript/Hammerspoon attempt at this has failed.
--
-- Once that flag is set, the control appears as:
--   AXGroup    desc="Press and hold to record"
--     AXCheckBox   desc="Press and hold to record"   <- supports AXPress
--     AXPopUpButton desc="Dictation settings"
--
-- We locate it by description at runtime, never by screen coordinates, so moving
-- or resizing the window doesn't break it.

require("hs.ipc")   -- lets the `hs` CLI query this config for debugging

local CLAUDE_BUNDLE = "com.anthropic.claudefordesktop"
local MIC_DESC      = "press and hold to record"
local ARM_DELAY     = 0.15   -- hold this long before recording starts (avoids
                             -- firing on Option+letter accent composition)
local RIGHT_OPTION  = 61     -- left Option is 58

local micCache   = nil
local recording  = false
local armTimer   = nil
local optDown    = false

local function findMic(el, depth)
  if not el or depth > 34 then return nil end
  local role = el:attributeValue("AXRole")
  local desc = el:attributeValue("AXDescription")
  if role == "AXCheckBox" and desc and desc:lower():find(MIC_DESC, 1, true) then
    return el
  end
  local kids = el:attributeValue("AXChildren")
  if kids then
    for _, c in ipairs(kids) do
      local hit = findMic(c, depth + 1)
      if hit then return hit end
    end
  end
  return nil
end

local function micElement()
  -- reuse the cached element while it is still alive
  if micCache and micCache:attributeValue("AXRole") == "AXCheckBox" then
    return micCache
  end
  local app = hs.application.get(CLAUDE_BUNDLE)
  if not app then return nil end
  local ax = hs.axuielement.applicationElement(app)
  if not ax then return nil end
  ax:setAttributeValue("AXManualAccessibility", true)  -- unlocks the web content
  micCache = findMic(ax, 0)
  return micCache
end

local function pressMic()
  local el = micElement()
  if not el then
    hs.alert.show("Claude mic not found")
    return false
  end
  el:performAction("AXPress")
  return true
end

local function startRecording()
  armTimer = nil
  if recording then return end
  if pressMic() then
    recording = true
    hs.alert.show("● recording", 0.4)
  end
end

local function stopRecording()
  if not recording then return end
  recording = false
  pressMic()
end

micWatcher = hs.eventtap.new({ hs.eventtap.event.types.flagsChanged }, function(e)
  if e:getKeyCode() ~= RIGHT_OPTION then return false end
  local flags = e:getFlags()
  local down  = flags.alt and not (flags.cmd or flags.ctrl or flags.shift)

  if down and not optDown then
    optDown = true
    armTimer = hs.timer.doAfter(ARM_DELAY, startRecording)
  elseif not flags.alt and optDown then
    optDown = false
    if armTimer then armTimer:stop(); armTimer = nil end
    stopRecording()
  end
  return false   -- never swallow the key; Option+letter still types accents
end)
micWatcher:start()

-- Any other key pressed while Option is held means the user is composing a
-- character, not dictating -- cancel the pending arm.
cancelWatcher = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function()
  if armTimer then armTimer:stop(); armTimer = nil end
  return false
end)
cancelWatcher:start()

hs.alert.show("Claude dictation: hold Right Option")
