-- Klawisz wiodący (leader) na Caps Locku.
--
-- Karabiner zamienia Caps Locka na F18 (reguła w ~/.config/karabiner), więc
-- macOS nie traktuje go już specjalnie i można go tu dowolnie obsłużyć.
--
-- Zachowanie:
--   * stuknięcie Caps Locka, potem klawisz  -> akcja przypisana w M.app/M.bind
--   * zawahanie się po stuknięciu           -> ściąga z dostępnymi skrótami
--   * Escape albo 4 s bezczynności          -> wyjście z trybu
--
-- Sekwencja zamiast akordu: nie trzeba trzymać Caps Locka podczas naciskania
-- drugiego klawisza. Przytrzymanie Caps Locka to osobna funkcja — Hyper
-- (⌃⌥⇧⌘) obsługiwany w całości przez Karabinera, podobnie jak Shift+Caps Lock
-- przełączające wielkie litery.

local M = {}

-- Po tylu sekundach bezczynności tryb wygasa sam.
local TIMEOUT = 4
-- Po tylu sekundach wahania pokazujemy ściągę. Krócej niż TIMEOUT, żeby zdążyła
-- się pojawić i dać się przeczytać.
local HINT_DELAY = 0.6

-- Tryb modalny zbierający skróty. Aktywny tylko po stuknięciu leadera, więc
-- poza nim litery działają normalnie.
M.mode = hs.hotkey.modal.new()

-- Opisy skrótów do ściągi, w kolejności rejestracji.
local entries = {}

-- To samo dla akordów z przytrzymanym Hyperem — osobna lista, bo to osobny
-- zestaw skrótów: pod trzymanym Hyperem litery z M.bind nie działają.
local chords = {}

-- Kafelkowanie okien z macOS, przestawione z domyślnego fn+ctrl na Hypera.
-- Rejestruje je system, nie ta konfiguracja — są tu wyłącznie po to, żeby
-- ściąga pokazywała wszystko, co Hyper potrafi, a nie tylko nasze akordy.
-- name to nazwa z hs.keycodes.map — po niej rozpoznajemy te akordy w tapie
-- wykrywającym nieprzypisane; key służy tylko do wyświetlenia.
local system = {
  { key = "⏎", name = "return", label = "Wypełnij" },
  { key = "↑", name = "up",     label = "Wyśrodkuj" },
  { key = "↓", name = "down",   label = "Poprzednia wielkość" },
  { key = "←", name = "left",   label = "Lewa połowa" },
  { key = "→", name = "right",  label = "Prawa połowa" },
  { key = "1", name = "1",      label = "Górna lewa ćwiartka" },
  { key = "2", name = "2",      label = "Górna prawa ćwiartka" },
  { key = "3", name = "3",      label = "Dolna lewa ćwiartka" },
  { key = "4", name = "4",      label = "Dolna prawa ćwiartka" },
}

-- Hyper (⌃⌥⇧⌘) składa Karabiner z przytrzymanego Caps Locka.
local HYPER = { "ctrl", "alt", "shift", "cmd" }

local timeoutTimer = nil
local hintTimer = nil
local hint = nil

-- Definicja przy ściądze akordów niżej; M.chord musi ją chować po trafieniu.
local hideChordHint

-- Paleta Solarized Light (Ethan Schoonover). Tło jest ciepłe kremowe, nie białe
-- — to jej znak rozpoznawczy, więc trzymamy się oryginalnych wartości.
local S = {
  base3  = { red = 0.99, green = 0.96, blue = 0.89 },  -- #fdf6e3 tło
  base2  = { red = 0.93, green = 0.91, blue = 0.83 },  -- #eee8d5 tło akcentów
  base1  = { red = 0.58, green = 0.63, blue = 0.63 },  -- #93a1a1 tekst drugorzędny
  base00 = { red = 0.40, green = 0.48, blue = 0.51 },  -- #657b83 tekst główny
  base01 = { red = 0.35, green = 0.43, blue = 0.46 },  -- #586e75 tekst mocniejszy
  blue   = { red = 0.15, green = 0.55, blue = 0.82 },  -- #268bd2 akcent
}

-- Wygląd ściągi.
local ROW_H = 36        -- wysokość wiersza
local KEY_W = 30        -- bok kapsułki z klawiszem
local PAD = 20          -- margines wewnętrzny płytki
local GAP = 14          -- odstęp między kapsułką a opisem
local LABEL_W = 200     -- szerokość kolumny z opisem
local HEAD_H = 30       -- wysokość nagłówka
local COL_GAP = 26      -- odstęp między kolumnami
-- Powyżej tylu wierszy ściąga dzieli się na dwie kolumny.
local SPLIT_AT = 7

local function color(c, alpha)
  return { red = c.red, green = c.green, blue = c.blue, alpha = alpha or 1 }
end

-- Rysuje płytkę ze ściągą. rows to lista { key, label, dim } — dim oznacza
-- wiersz drugorzędny (mniejszy klawisz, przygaszone kolory).
local function buildRows(title, rows)
  -- Przy dłuższej liście dzielimy na dwie kolumny, żeby płytka nie rosła w słup.
  -- Pierwsza kolumna dostaje nadmiarowy wiersz przy nieparzystej liczbie.
  local cols = (#rows > SPLIT_AT) and 2 or 1
  local perCol = math.ceil(#rows / cols)

  local colW = KEY_W + GAP + LABEL_W
  local w = PAD * 2 + colW * cols + COL_GAP * (cols - 1)
  local h = PAD * 2 + HEAD_H + ROW_H * perCol
  local f = hs.screen.mainScreen():frame()
  local c = hs.canvas.new({
    x = f.x + (f.w - w) / 2,
    y = f.y + (f.h - h) / 2,
    w = w, h = h,
  })
  c:level(hs.canvas.windowLevels.overlay)
  c:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
  c:clickActivating(false)

  -- Płytka rysowana jako ścieżka zaokrąglonego prostokąta. Cień musi iść na
  -- osobnym elemencie pod spodem — hs.canvas liczy go od prostokątnych granic
  -- elementu, więc dołożony tutaj zostawiłby ciemne narożniki poza zaokrągleniem.
  local radii = { xRadius = 16, yRadius = 16 }

  c[#c + 1] = { type = "rectangle", action = "fill",
                roundedRectRadii = radii,
                fillColor = { alpha = 0.32, white = 0 },
                frame = { x = 3, y = 8, w = w - 6, h = h - 12 } }

  c[#c + 1] = { type = "rectangle", action = "strokeAndFill",
                roundedRectRadii = radii,
                fillColor = color(S.base2, 0.98),
                strokeColor = color(S.base1, 0.35),
                strokeWidth = 1 }

  -- Nagłówek z cienką linią oddzielającą.
  c[#c + 1] = { type = "text", text = title, textSize = 12,
                textColor = color(S.base00, 0.75),
                textFont = "JetBrainsMonoNF-Bold",
                frame = { x = PAD, y = PAD - 2, w = w - PAD * 2, h = 18 } }
  c[#c + 1] = { type = "rectangle", action = "fill",
                frame = { x = PAD, y = PAD + HEAD_H - 9, w = w - PAD * 2, h = 1 },
                fillColor = color(S.base1, 0.4) }

  for i, r in ipairs(rows) do
    local col = math.floor((i - 1) / perCol)
    local x = PAD + col * (colW + COL_GAP)
    local y = PAD + HEAD_H + ((i - 1) % perCol) * ROW_H
    local keyColor = r.dim and S.base00 or S.blue
    local labelColor = r.dim and S.base00 or S.base01

    -- kapsułka z klawiszem — jaśniejsza niż płytka, żeby się od niej odcięła
    c[#c + 1] = { type = "rectangle", action = "strokeAndFill",
                  frame = { x = x, y = y, w = KEY_W, h = ROW_H - 8 },
                  roundedRectRadii = { xRadius = 6, yRadius = 6 },
                  fillColor = color(S.base3, r.dim and 0.5 or 1),
                  strokeColor = color(S.base1, r.dim and 0.15 or 0.3),
                  strokeWidth = 1 }
    c[#c + 1] = { type = "text", text = r.key,
                  textSize = r.dim and 11 or 14,
                  textColor = color(keyColor),
                  textFont = "JetBrainsMonoNF-Bold",
                  textAlignment = "center",
                  frame = { x = x, y = y + (r.dim and 7 or 5),
                            w = KEY_W, h = ROW_H - 8 } }

    -- opis
    c[#c + 1] = { type = "text", text = r.label, textSize = 14,
                  textColor = color(labelColor),
                  textFont = "JetBrainsMonoNF-Regular",
                  frame = { x = x + KEY_W + GAP, y = y + 5,
                            w = LABEL_W, h = ROW_H - 8 } }
  end

  return c
end

-- Ściąga trybu leadera: skróty spod stuknięcia Caps Locka.
local function buildHint()
  local rows = {}
  for _, e in ipairs(entries) do
    rows[#rows+1] = { key = e.key, label = e.label, dim = false }
  end
  rows[#rows+1] = { key = "esc", label = "anuluj", dim = true }
  return buildRows("Skróty", rows)
end

local function hideHint()
  if hintTimer then hintTimer:stop() ; hintTimer = nil end
  if hint then hint:hide(0.12) ; hint:delete() ; hint = nil end
end

-- Komunikat o nieprzypisanym klawiszu ---------------------------------------
--
-- Nie ściąga, tylko wąski toast przy dolnej krawędzi — pomyłka nie zasługuje na
-- płytkę na środku ekranu. Wysokość i margines jak w overlayu dyktowania, żeby
-- oba wskaźniki wyglądały jak jedna rodzina.

local unbound = nil
local unboundTimer = nil
-- Na tyle długo, żeby dało się przeczytać, na tyle krótko, żeby nie zawadzał.
local UNBOUND_TIME = 1.2
local TOAST_H = 44
local TOAST_BOTTOM = 120
local TOAST_PAD = 18
local TOAST_TEXT = 14
-- nf-md-keyboard_off_outline — klawisz, który nic nie robi.
local TOAST_ICON = "\u{f0e4b}"
local TOAST_ICON_SIZE = 18

-- Nazwy z hs.keycodes.map bywają nieczytelne albo za długie na wąski toast.
local KEY_LABEL = {
  ["space"] = "spacja",
  ["return"] = "enter",
  ["delete"] = "backspace",
  ["forwarddelete"] = "delete",
  ["left"] = "←", ["right"] = "→", ["up"] = "↑", ["down"] = "↓",
}

local function hideUnbound()
  if unboundTimer then unboundTimer:stop() ; unboundTimer = nil end
  if unbound then unbound:hide(0.12) ; unbound:delete() ; unbound = nil end
end

local function showUnbound(key)
  hideUnbound()

  local text = "Brak skrótu: " .. key
  -- JetBrains Mono jest monospace, więc szerokość liczymy z liczby znaków.
  local textW = math.ceil(utf8.len(text) * TOAST_TEXT * 0.6) + 2
  local w = TOAST_PAD * 2 + TOAST_ICON_SIZE + 10 + textW

  local f = hs.screen.mainScreen():frame()
  local c = hs.canvas.new({
    x = f.x + (f.w - w) / 2,
    y = f.y + f.h - TOAST_H - TOAST_BOTTOM,
    w = w, h = TOAST_H,
  })
  c:level(hs.canvas.windowLevels.overlay)
  c:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
  c:clickActivating(false)

  local radii = { xRadius = TOAST_H / 2, yRadius = TOAST_H / 2 }

  c[1] = { type = "rectangle", action = "fill",
           roundedRectRadii = radii,
           fillColor = { alpha = 0.28, white = 0 },
           frame = { x = 2, y = 6, w = w - 4, h = TOAST_H - 10 } }

  c[2] = { type = "rectangle", action = "strokeAndFill",
           roundedRectRadii = radii,
           fillColor = color(S.base2, 0.98),
           strokeColor = color(S.base1, 0.35),
           strokeWidth = 1 }

  c[3] = { type = "text", text = TOAST_ICON, textSize = TOAST_ICON_SIZE,
           textColor = color(S.base00, 0.8),
           textFont = "JetBrainsMonoNF-Regular",
           textAlignment = "center",
           frame = { x = TOAST_PAD, y = (TOAST_H - TOAST_ICON_SIZE * 1.4) / 2,
                     w = TOAST_ICON_SIZE, h = TOAST_ICON_SIZE * 1.4 } }

  c[4] = { type = "text", text = text, textSize = TOAST_TEXT,
           textColor = color(S.base01),
           textFont = "JetBrainsMonoNF-Regular",
           frame = { x = TOAST_PAD + TOAST_ICON_SIZE + 10,
                     y = (TOAST_H - TOAST_TEXT * 1.35) / 2,
                     w = textW, h = TOAST_TEXT * 1.35 } }

  unbound = c
  unbound:show(0.12)
  unboundTimer = hs.timer.doAfter(UNBOUND_TIME, hideUnbound)
end

-- Definicja niżej, przy trybie; leave() musi go zatrzymać przy każdym wyjściu.
local unboundTap

local function leave()
  if timeoutTimer then timeoutTimer:stop() ; timeoutTimer = nil end
  if unboundTap then unboundTap:stop() end
  hideHint()
  M.mode:exit()
end

-- Klawisz spoza spisu kończy tryb komunikatem. Modal reaguje tylko na to, co ma
-- podpięte, więc „cokolwiek innego" trzeba złapać osobno — eventtap żyje tylko
-- na czas trybu i przechwytuje zdarzenie (zwraca true), żeby przypadkowa litera
-- nie wpadła do okna pod spodem.
--
-- Tap widzi zdarzenie przed modalem, więc przypisane klawisze musi rozpoznać
-- sam i przepuścić dalej — inaczej zjadłby własne skróty. Escape też idzie
-- dalej: ma w modalu swoje ciche wyjście. Modyfikatory lecą osobnym typem
-- zdarzenia (flagsChanged), więc samo sięgnięcie po Shift trybu nie przerwie.
unboundTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(e)
  local name = hs.keycodes.map[e:getKeyCode()]

  if name == "escape" then return false end
  for _, entry in ipairs(entries) do
    if entry.key == name then return false end
  end

  leave()
  showUnbound(KEY_LABEL[name] or name or "?")

  return true
end)

function M.mode:entered()
  if timeoutTimer then timeoutTimer:stop() end
  timeoutTimer = hs.timer.doAfter(TIMEOUT, leave)

  hideUnbound()
  unboundTap:start()

  -- Ściąga tylko dla wahających się — kto zna skrót, nie zdąży jej zobaczyć.
  hideHint()
  hintTimer = hs.timer.doAfter(HINT_DELAY, function()
    hintTimer = nil
    hint = buildHint()
    hint:show(0.12)
  end)
end

-- Escape anuluje tryb bez żadnej akcji.
M.mode:bind({}, "escape", leave)

-- Dowolna akcja pod leaderem. Każde trafienie kończy tryb.
-- Etykieta trafia do ściągi.
--
--   M.bind("h", "Okno w lewo", function() ... end)
function M.bind(key, label, action)
  entries[#entries+1] = { key = key, label = label }
  M.mode:bind({}, key, function()
    leave()
    action()
  end)
end

-- Akord z przytrzymanym Hyperem. W przeciwieństwie do M.bind nie ma tu trybu
-- do opuszczenia — Karabiner trzyma modyfikatory, a hs.hotkey łapie kombinację
-- wprost. Etykieta trafia do ściągi pokazywanej przy dłuższym przytrzymaniu.
--
--   M.chord("q", "Dyktowanie", function() ... end)
function M.chord(key, label, action)
  chords[#chords+1] = { key = key, label = label }
  return hs.hotkey.bind(HYPER, key, function()
    -- Bez tego ściąga wisiałaby aż do puszczenia Hypera, już po akcji.
    hideChordHint()
    action()
  end)
end

-- Skrót otwierający aplikację po nazwie — najczęstszy przypadek, więc ma
-- własny pomocnik zamiast powtarzanego launchOrFocus. Nazwa aplikacji służy
-- zarazem za etykietę w ściądze.
function M.app(key, name)
  M.bind(key, name, function() hs.application.launchOrFocus(name) end)
end

-- Wejście w tryb. hs.hotkey zamiast hs.eventtap z dwóch powodów: łapie tylko
-- ten jeden klawisz zamiast przepuszczać przez Lua każde wciśnięcie w systemie,
-- a callback trzyma po stronie C w rejestrze Lua, więc nie zależy od tego, czy
-- coś w Lua wciąż się do niego odwołuje.
M.trigger = hs.hotkey.bind({}, "f18", function() M.mode:enter() end)

-- Ściąga akordów -----------------------------------------------------------
--
-- Pod skrótem, a nie pod samym przytrzymaniem Hypera: Karabiner wysyła
-- modyfikatory z „lazy", czyli wstrzymuje je do wciśnięcia drugiego klawisza,
-- więc puste przytrzymanie nie daje tu żadnego zdarzenia, na którym można by
-- się zawiesić.

local chordHint = nil

hideChordHint = function()
  if chordHint then
    M.chordEscape:disable()
    chordHint:hide(0.12) ; chordHint:delete() ; chordHint = nil
  end
end

-- Escape zamyka ściągę. Jak przy dyktowaniu: skrót istnieje cały czas, ale
-- włączony jest tylko wtedy, gdy ściąga wisi — inaczej przejąłby Escape
-- w całym systemie.
M.chordEscape = hs.hotkey.new({}, "escape", function() hideChordHint() end)
M.chordEscape:disable()

-- Nieprzypisany akord Hypera -------------------------------------------------
--
-- Hyper nie ma trybu, w który dałoby się wejść i nasłuchiwać — akord jest albo
-- zarejestrowany, albo nie. Wykrycie pudła wymaga więc stałego tapa na każde
-- wciśnięcie z kompletem modyfikatorów.
--
-- Tap tylko podgląda: zwraca false, więc niczego nie przechwytuje i nie może
-- popsuć działającego skrótu. Zarejestrowane akordy trafiają tu również (bez
-- wpływu na ich działanie), stąd sprawdzanie rejestru przed pokazaniem toasta.
M.hyperTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(e)
  local f = e:getFlags()
  if not (f.ctrl and f.alt and f.shift and f.cmd) then return false end

  local name = hs.keycodes.map[e:getKeyCode()]

  for _, c in ipairs(chords) do
    if c.key == name then return false end
  end
  -- Kafelkowanie okien przechwytuje system, zanim dojdzie tutaj — a gdyby jednak
  -- doszło, to i tak działa, więc toast byłby kłamstwem.
  for _, s in ipairs(system) do
    if s.name == name then return false end
  end

  showUnbound(KEY_LABEL[name] or name or "?")
  return false
end):start()

-- Skróty ------------------------------------------------------------------

-- Ściąga akordów. Hyper+/ nie dociera tu jako akord — Karabiner gubi to jedno
-- zdarzenie po drodze (Hyper+Q przechodzi, Hyper+/ nie generuje niczego), więc
-- osobna reguła zamienia je na F19 i pod nim wisi ten skrót.
--
-- Ściąga sama siedzi w spisie, więc widać, czym ją zamknąć.
M.hintKey = hs.hotkey.bind({}, "f19", function()
  -- Drugie wciśnięcie zamyka — ściągę trzeba dać się schować tym samym skrótem,
  -- którym się ją otwiera.
  if chordHint then hideChordHint() ; return end

  local rows = {}
  for _, e in ipairs(chords) do
    rows[#rows+1] = { key = e.key, label = e.label, dim = false }
  end
  if #rows == 0 then return end
  -- Systemowe niżej i przygaszone: nie pochodzą stąd, więc nie udają naszych.
  for _, e in ipairs(system) do
    rows[#rows+1] = { key = e.key, label = e.label, dim = true }
  end
  -- Ta ściąga nie przechodzi przez M.chord, więc w rejestrze jej nie ma.
  rows[#rows+1] = { key = "/", label = "ta ściąga", dim = true }
  rows[#rows+1] = { key = "esc", label = "zamknij", dim = true }

  chordHint = buildRows("Hyper", rows)
  chordHint:show(0.12)
  M.chordEscape:enable()
end)

M.app("b", "Brave Browser")
M.app("t", "Ghostty")
M.app("z", "Zed")
M.app("p", "PhpStorm")
M.app("m", "Music")
M.app("f", "Figma")
M.app("s", "Spark Desktop")
M.app("d", "Discord")
M.app("c", "Claude")
M.app("1", "1Password")
M.app("w", "Messages")
M.app("n", "Nimble Commander")

return M
