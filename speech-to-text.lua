local M = {}

local script = os.getenv("HOME") .. "/.local/bin/speech-to-text.sh"

-- Wirtualny keyCode lewego Ctrl. Prawy to 62.
local LCTRL = 59
-- Maksymalna przerwa między stuknięciami, żeby uznać je za dublet.
local DOUBLE_TAP_GAP = 0.35

local W, H, MARGIN = 190, 46, 14
local overlay = nil

local errors = {
  [10] = "Brak nagrania",
  [11] = "Nic nie rozpoznano",
  [12] = "Brak sox (rec)",
  [13] = "Błąd whispera",
  [14] = "Brak uprawnień",
}

local function build()
  local f = hs.screen.mainScreen():frame()
  local c = hs.canvas.new({ x = f.x + f.w - W - MARGIN, y = f.y + MARGIN, w = W, h = H })
  c:level(hs.canvas.windowLevels.overlay)
  c:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
  c:clickActivating(false)
  c[1] = { type = "rectangle", action = "fill",
           roundedRectRadii = { xRadius = 12, yRadius = 12 },
           fillColor = { red = 0, green = 0, blue = 0, alpha = 0.78 } }
  c[2] = { type = "circle", action = "fill",
           center = { x = 26, y = 23 }, radius = 7,
           fillColor = { red = 0.55, green = 0.55, blue = 0.6, alpha = 1 } }
  c[3] = { type = "text", text = "Czekaj…", textSize = 15,
           textColor = { white = 1 },
           frame = { x = 44, y = 13, w = W - 52, h = 24 } }
  return c
end

local function show()
  if overlay then overlay:delete() end
  overlay = build()
  overlay:show(0.12)
end

local function setState(text, r, g, b)
  if not overlay then return end
  overlay[2].fillColor = { red = r, green = g, blue = b, alpha = 1 }
  overlay[3].text = text
end

local function hide(delay)
  if not overlay then return end
  local o = overlay
  overlay = nil
  hs.timer.doAfter(delay or 0, function() o:hide(0.15) ; o:delete() end)
end

local function finish(code)
  if code == 0 then
    hide()
  else
    setState(errors[code] or ("Błąd " .. code), 0.98, 0.3, 0.3)
    hide(2.5)
  end
end

local function startRecording()
  show()
  hs.task.new(script, function()
    setState("Nagrywanie", 0.94, 0.27, 0.27)
  end, {"start"}):start()
end

local function stopRecording()
  setState("Przetwarzam…", 0.98, 0.75, 0.18)
  hs.task.new(script, function(code) finish(code) end, {"stop"}):start()
end

-- Podwójne stuknięcie lewego Ctrl, gdzie drugie zostaje przytrzymane:
-- nagrywanie startuje przy drugim wciśnięciu i kończy się przy jego puszczeniu.
--
-- Stany:
--   idle    – nic się nie dzieje
--   armed   – było pierwsze pełne stuknięcie (down+up), czekamy na drugie
--   holding – drugie wciśnięcie trwa, nagrywanie w toku
local state = "idle"
local armTimer = nil
-- Czy od ostatniego wciśnięcia Ctrl padł jakiś inny klawisz. Dzięki temu
-- Ctrl+C i spółka nie uzbrajają mechanizmu — liczy się tylko czysty Ctrl.
local usedAsModifier = false

local function disarm()
  if armTimer then armTimer:stop() ; armTimer = nil end
  state = "idle"
end

M.tap = hs.eventtap.new({
  hs.eventtap.event.types.flagsChanged,
  hs.eventtap.event.types.keyDown,
}, function(e)
  if e:getType() == hs.eventtap.event.types.keyDown then
    usedAsModifier = true
    return false
  end

  if e:getKeyCode() ~= LCTRL then return false end

  local down = e:getFlags().ctrl or false

  if down then
    usedAsModifier = false
    if state == "armed" then
      state = "holding"
      startRecording()
    end
    -- Wciśnięcie w stanie idle samo w sobie nic nie znaczy; dopiero
    -- czyste puszczenie uzbraja mechanizm (patrz niżej).
  else
    if state == "holding" then
      disarm()
      stopRecording()
    elseif state == "idle" and not usedAsModifier then
      state = "armed"
      if armTimer then armTimer:stop() end
      armTimer = hs.timer.doAfter(DOUBLE_TAP_GAP, function()
        armTimer = nil
        if state == "armed" then state = "idle" end
      end)
    end
  end

  return false -- nie zjadamy zdarzenia, Ctrl działa normalnie
end)

M.tap:start()

return M
