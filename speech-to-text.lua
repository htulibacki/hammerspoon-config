local M = {}

local script = os.getenv("HOME") .. "/.local/bin/speech-to-text.sh"

-- Wirtualny keyCode lewego Ctrl. Prawy to 62.
local LCTRL = 59
-- Maksymalna przerwa między stuknięciami, żeby uznać je za dublet.
local DOUBLE_TAP_GAP = 0.35

-- Wygląd overlaya. Ta sama paleta i proporcje co ściąga w hyper.lua, żeby oba
-- wskaźniki wyglądały jak jedna rodzina.
local W, H = 240, 62
-- Odstęp od dolnej krawędzi ekranu.
local BOTTOM_MARGIN = 120
-- Rozmiar tekstu; wysokość linii potrzebna do wyrównania go z ikoną.
local TEXT_SIZE = 16
local LINE_H = 21
-- Ikona stanu — glify Nerd Fonts z Prywatnego Obszaru Użytku.
local ICON_SIZE = 19
local ICON_W = 22       -- szerokość pola ikony
local ICON_GAP = 10     -- odstęp między ikoną a tekstem
local PAD = 16          -- minimalny margines przy krawędziach płytki
local ICON = {
  idle    = "\u{f130}",  -- nf-fa-microphone
  active  = "\u{f130}",  -- ten sam mikrofon, odróżnia go kolor
  working = "\u{f110}",  -- nf-fa-spinner
}
local S = {
  base3  = { red = 0.99, green = 0.96, blue = 0.89 },  -- #fdf6e3
  base2  = { red = 0.93, green = 0.91, blue = 0.83 },  -- #eee8d5
  base1  = { red = 0.58, green = 0.63, blue = 0.63 },  -- #93a1a1
  base01 = { red = 0.35, green = 0.43, blue = 0.46 },  -- #586e75
}

local function color(c, alpha)
  return { red = c.red, green = c.green, blue = c.blue, alpha = alpha or 1 }
end

-- Kolory stanów z palety Solarized — na kremowym tle jaskrawe barwy raziłyby.
local DOT = {
  idle    = { red = 0.58, green = 0.63, blue = 0.63 },  -- base1
  active  = { red = 0.86, green = 0.20, blue = 0.18 },  -- red #dc322f
  working = { red = 0.71, green = 0.54, blue = 0.00 },  -- yellow #b58900
}

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
  local c = hs.canvas.new({
    x = f.x + (f.w - W) / 2,
    y = f.y + f.h - H - BOTTOM_MARGIN,
    w = W, h = H,
  })
  c:level(hs.canvas.windowLevels.overlay)
  c:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
  c:clickActivating(false)

  local radii = { xRadius = 16, yRadius = 16 }

  -- Cień na osobnym elemencie pod płytką: hs.canvas liczy go od prostokątnych
  -- granic, więc dodany do samej płytki zostawiłby ciemne narożniki.
  c[1] = { type = "rectangle", action = "fill",
           roundedRectRadii = radii,
           fillColor = { alpha = 0.32, white = 0 },
           frame = { x = 3, y = 8, w = W - 6, h = H - 12 } }

  c[2] = { type = "rectangle", action = "strokeAndFill",
           roundedRectRadii = radii,
           fillColor = color(S.base2, 0.98),
           strokeColor = color(S.base1, 0.35),
           strokeWidth = 1 }

  -- Ikona i tekst dzielą tę samą oś pionową. Tekst rysuje się od górnej
  -- krawędzi ramki, więc ramki centrujemy względem osi o wysokość linii.
  local axis = H / 2

  -- Ikona i tekst tworzą jedną grupę wyśrodkowaną w płytce — inaczej przy
  -- krótkim komunikacie zostawałaby pusta przestrzeń po prawej.
  -- Indeksy [3] i [4] są używane przez setState().
  c[3] = { type = "text", text = ICON.idle, textSize = ICON_SIZE,
           textColor = color(DOT.idle),
           textFont = "JetBrainsMonoNF-Regular",
           textAlignment = "center",
           frame = { x = 0, y = axis - ICON_SIZE * 0.72,
                     w = ICON_W, h = ICON_SIZE * 1.5 } }
  c[4] = { type = "text", text = "", textSize = TEXT_SIZE,
           textColor = color(S.base01),
           textFont = "JetBrainsMonoNF-Regular",
           frame = { x = 0, y = axis - LINE_H / 2, w = W, h = LINE_H } }

  return c
end

local show  -- setState() jest niżej, a show() go potrzebuje

-- Ustawia komunikat i przesuwa ikonę z tekstem tak, by razem stały na środku.
local function setState(text, dot, icon)
  if not overlay then return end

  -- JetBrains Mono jest monospace, więc szerokość liczymy z liczby znaków.
  -- Pomiar przez hs.drawing/styledtext bywa zawodny przy fontach Nerd Fonts.
  local textW = math.ceil(utf8.len(text) * TEXT_SIZE * 0.6) + 2

  -- Szerokość grupy: ikona + odstęp + tekst, wyśrodkowana w płytce.
  local left = math.max(PAD, (W - (ICON_W + ICON_GAP + textW)) / 2)

  local axis = H / 2

  -- Elementy podmieniamy w całości. Przypisanie pojedynczego pola (frame.x)
  -- każe hs.canvas dobrać brakujące wartości domyślne i kończy się błędem.
  overlay[3] = { type = "text", text = icon or ICON.idle, textSize = ICON_SIZE,
                 textColor = color(dot),
                 textFont = "JetBrainsMonoNF-Regular",
                 textAlignment = "center",
                 frame = { x = left, y = axis - ICON_SIZE * 0.72,
                           w = ICON_W, h = ICON_SIZE * 1.5 } }

  overlay[4] = { type = "text", text = text, textSize = TEXT_SIZE,
                 textColor = color(S.base01),
                 textFont = "JetBrainsMonoNF-Regular",
                 frame = { x = left + ICON_W + ICON_GAP, y = axis - LINE_H / 2,
                           w = math.min(textW, W - left - ICON_W - ICON_GAP - PAD),
                           h = LINE_H } }
end

show = function()
  if overlay then overlay:delete() end
  overlay = build()
  setState("Czekaj…", DOT.idle, ICON.idle)
  overlay:show(0.12)
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
    setState(errors[code] or ("Błąd " .. code), DOT.active, ICON.idle)
    hide(2.5)
  end
end

local function startRecording()
  show()
  hs.task.new(script, function()
    setState("Nagrywanie", DOT.active, ICON.active)
  end, {"start"}):start()
end

-- Dozorca pilnujacy, czy Ctrl nadal jest wcisniety w trakcie nagrywania.
-- Zadeklarowany tu, bo stopRecording() musi go zatrzymac.
local holdWatch = nil

local function stopRecording()
  if holdWatch then holdWatch:stop() ; holdWatch = nil end
  setState("Przetwarzam…", DOT.working, ICON.working)
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
      -- Dozorca na wypadek zgubionego zdarzenia puszczenia (zdarza sie przy
      -- szybkim dublecie, gdy "up" trafia w moment startu nagrywania).
      -- Timer zatrzymuje samo stopRecording(), nie ten callback.
      if holdWatch then holdWatch:stop() end
      holdWatch = hs.timer.doEvery(0.1, function()
        if state == "holding" and not hs.eventtap.checkKeyboardModifiers().ctrl then
          disarm()
          stopRecording()
        end
      end)
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
