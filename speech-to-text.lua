local M = {}

local script = os.getenv("HOME") .. "/.local/bin/speech-to-text.sh"

-- Hyper (⌃⌥⇧⌘) składa Karabiner z przytrzymanego Caps Locka.
local HYPER = { "ctrl", "alt", "shift", "cmd" }

-- Wygląd overlaya. Ta sama paleta i proporcje co ściąga w hyper.lua, żeby oba
-- wskaźniki wyglądały jak jedna rodzina.
local W, H = 240, 62
-- Odstęp od dolnej krawędzi ekranu.
local BOTTOM_MARGIN = 120
-- Rozmiar tekstu; wysokość linii potrzebna do wyrównania go z ikoną.
local TEXT_SIZE = 16
local LINE_H = 21
-- Ikona stanu — glify Nerd Fonts z Prywatnego Obszaru Użytku.
local ICON_SIZE = 23
local ICON_W = 26       -- szerokość pola ikony
local ICON_GAP = 10     -- odstęp między ikoną a tekstem
local PAD = 16          -- minimalny margines przy krawędziach płytki
-- Krycie tafli odmierzającej czas. Na tyle niskie, żeby tekst nad nią pozostał
-- czytelny, a różnica względem tła była wyraźna.
local PROGRESS_ALPHA = 0.18
-- Warianty konturowe z Material Design Icons zamiast wypełnionych z Font
-- Awesome — lżejsze i spójne z cienkimi liniami reszty overlaya.
local ICON = {
  idle    = "\u{f036e}",  -- nf-md-microphone_outline
  active  = "\u{f036e}",  -- ten sam mikrofon, odróżnia go kolor
  working = "\u{f0772}",  -- nf-md-loading
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

  -- Wskaźnik pozostałego czasu: ciemniejsza tafla na całą płytkę, cofająca się
  -- od prawej w miarę upływu nagrania. Leży nad tłem, a pod ikoną i tekstem,
  -- więc treść pozostaje czytelna niezależnie od tego, ile go zostało.
  --
  -- Kształt płytki wchodzi tu jako region przycinania, więc sama tafla ma
  -- twarde rogi — zaokrągla ją dopiero obrys płytki. Inaczej cofająca się
  -- prawa krawędź niosłaby własne zaokrąglenie w poprzek płytki.
  c[3] = { type = "rectangle", action = "clip",
           roundedRectRadii = radii }

  -- Indeks [4] używany przez setProgress().
  c[4] = { type = "rectangle", action = "fill",
           fillColor = color(S.base1, PROGRESS_ALPHA),
           frame = { x = 0, y = 0, w = 0, h = H } }

  c[5] = { type = "resetClip" }

  -- Ikona i tekst dzielą tę samą oś pionową. Tekst rysuje się od górnej
  -- krawędzi ramki, więc ramki centrujemy względem osi o wysokość linii.
  local axis = H / 2

  -- Ikona i tekst tworzą jedną grupę wyśrodkowaną w płytce — inaczej przy
  -- krótkim komunikacie zostawałaby pusta przestrzeń po prawej.
  -- Indeksy [6] i [7] są używane przez setState().
  c[6] = { type = "text", text = ICON.idle, textSize = ICON_SIZE,
           textColor = color(DOT.idle),
           textFont = "JetBrainsMonoNF-Regular",
           textAlignment = "center",
           frame = { x = 0, y = axis - ICON_SIZE * 0.72,
                     w = ICON_W, h = ICON_SIZE * 1.5 } }
  c[7] = { type = "text", text = "", textSize = TEXT_SIZE,
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
  overlay[6] = { type = "text", text = icon or ICON.idle, textSize = ICON_SIZE,
                 textColor = color(dot),
                 textFont = "JetBrainsMonoNF-Regular",
                 textAlignment = "center",
                 frame = { x = left, y = axis - ICON_SIZE * 0.72,
                           w = ICON_W, h = ICON_SIZE * 1.5 } }

  overlay[7] = { type = "text", text = text, textSize = TEXT_SIZE,
                 textColor = color(S.base01),
                 textFont = "JetBrainsMonoNF-Regular",
                 frame = { x = left + ICON_W + ICON_GAP, y = axis - LINE_H / 2,
                           w = math.min(textW, W - left - ICON_W - ICON_GAP - PAD),
                           h = LINE_H } }
end

-- Szerokość ciemniejszej tafli jako ułamek 0..1 pozostałego czasu. Bez własnego
-- zaokrąglenia — rogi bierze się z regionu przycinania ustawionego w build().
local function setProgress(fraction)
  if not overlay then return end
  overlay[4] = { type = "rectangle", action = "fill",
                 fillColor = color(S.base1, PROGRESS_ALPHA),
                 frame = { x = 0, y = 0,
                           w = math.max(0, math.min(1, fraction)) * W,
                           h = H } }
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

-- Czy nagrywanie trwa. Poza przełącznikiem zeruje to też finish() — po błędzie
-- skryptu nagrania już nie ma, więc kolejne wciśnięcie ma zaczynać od nowa,
-- a nie próbować zatrzymywać coś, co nie działa.
local recording = false

local stopClock  -- definicja niżej, przy liczniku; finish() musi go zatrzymać

-- Ile czekać, aż aplikacja odbierze ⌘V, zanim oddamy schowek. Za krótko —
-- wklei się stara zawartość; niżej niż 0.15 s potrafiło się mylić.
local PASTE_SETTLE = 0.2

-- Wkleja tekst, oddając potem schowek w stanie, w jakim był. readAllData()
-- zabiera pierwszy element ze wszystkimi jego reprezentacjami (tekst, RTF,
-- obrazek, ścieżka pliku), więc wraca nie sam tekst, jak przy pbpaste.
--
-- Menedżery schowka z historią i tak zapiszą przelotny wpis z transkrypcją —
-- tego nie da się obejść, wklejając przez schowek.
-- Ostatnia transkrypcja, do ponownego wklejenia. Przydaje się, gdy pierwsze
-- wklejenie trafiło w pole tylko do odczytu albo w niewłaściwe okno.
local lastText = nil

local function pasteText(text)
  lastText = text
  local saved = hs.pasteboard.readAllData()

  hs.pasteboard.setContents(text)
  hs.eventtap.keyStroke({ "cmd" }, "v", 0)

  hs.timer.doAfter(PASTE_SETTLE, function()
    if saved and next(saved) then
      hs.pasteboard.writeAllData(saved)
    else
      -- Pusty schowek na wejściu: zostawiamy go pustym, zamiast trzymać
      -- w nim transkrypcję.
      hs.pasteboard.clearContents()
    end
  end)
end

local function finish(code, output)
  recording = false
  stopClock()
  if code == 0 then
    if output and output ~= "" then pasteText(output) end
    hide()
  else
    setState(errors[code] or ("Błąd " .. code), DOT.active, ICON.idle)
    hide(2.5)
  end
end

-- Licznik długości nagrania. Odświeża sam tekst overlaya co sekundę; czas
-- liczymy od momentu, w którym skrypt faktycznie ruszył, a nie od wciśnięcia
-- klawisza, żeby nie pokazywać sekund, których nie ma w pliku.
local clock = nil

-- Po tylu sekundach nagranie kończy się samo. Zabezpieczenie przed dyktowaniem
-- w nieskończoność, gdy overlay zniknie z oczu albo zapomnisz go zatrzymać.
local MAX_SECONDS = 60

local stopRecording  -- definicja niżej; licznik kończy nagranie po limicie

-- Krok odświeżania paska. Co sekundę ruch byłby skokowy, więc rysujemy
-- częściej — to tylko podmiana szerokości prostokąta.
local TICK = 0.05

stopClock = function()
  if clock then clock:stop() ; clock = nil end
end

local function startRecording()
  show()
  hs.task.new(script, function()
    local since = hs.timer.secondsSinceEpoch()
    setState("Nagrywanie", DOT.active, ICON.active)
    setProgress(1)
    stopClock()
    clock = hs.timer.doEvery(TICK, function()
      local left = MAX_SECONDS - (hs.timer.secondsSinceEpoch() - since)
      if left <= 0 then
        stopRecording()
      else
        setProgress(left / MAX_SECONDS)
      end
    end)
  end, {"start"}):start()
end

stopRecording = function()
  stopClock()
  recording = false
  setState("Przetwarzam…", DOT.working, ICON.working)
  setProgress(0)
  hs.task.new(script, function(code, stdout)
    finish(code, stdout)
  end, {"stop"}):start()
end

-- Przełącznik: pierwsze wciśnięcie zaczyna nagrywanie, drugie je kończy.
-- Nie ma tu nic do przytrzymania, więc nagranie nie urywa się przez
-- przypadkowe puszczenie klawisza.
M.trigger = hs.hotkey.bind(HYPER, "q", function()
  if recording then
    stopRecording()
  else
    recording = true
    startRecording()
  end
end)

-- Ponowne wklejenie ostatniej transkrypcji — ratunek, gdy pierwsze wklejenie
-- poszło w niewłaściwe okno albo w pole tylko do odczytu.
--
-- Klawisz obok lewego Shifta. Karabiner zamienia go na non_us_backslash, co
-- przy układzie ISO daje backtick — i pod tym znakiem widzi go hs.keycodes.map.
-- Reguły Karabinera nie kaskadują, więc podmiana kończy się na tym jednym
-- kroku; sam klawisz zachowuje swój ` i ~ poza kombinacją z Hyperem.
M.repeatPaste = hs.hotkey.bind(HYPER, "`", function()
  show()
  if lastText then
    pasteText(lastText)
    setState("Wklejono ponownie", DOT.working, ICON.idle)
  else
    setState("Brak transkrypcji", DOT.idle, ICON.idle)
  end
  hide(1.2)
end)

return M
