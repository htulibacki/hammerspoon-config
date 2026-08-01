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

local timeoutTimer = nil
local hintTimer = nil
local hint = nil

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

local function buildHint()
  local rows = {}
  for _, e in ipairs(entries) do
    rows[#rows+1] = { key = e.key, label = e.label, dim = false }
  end
  rows[#rows+1] = { key = "esc", label = "anuluj", dim = true }

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
  c[#c + 1] = { type = "text", text = "Skróty", textSize = 12,
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

local function hideHint()
  if hintTimer then hintTimer:stop() ; hintTimer = nil end
  if hint then hint:hide(0.12) ; hint:delete() ; hint = nil end
end

local function leave()
  if timeoutTimer then timeoutTimer:stop() ; timeoutTimer = nil end
  hideHint()
  M.mode:exit()
end

function M.mode:entered()
  if timeoutTimer then timeoutTimer:stop() end
  timeoutTimer = hs.timer.doAfter(TIMEOUT, leave)

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

-- Skrót otwierający aplikację po nazwie — najczęstszy przypadek, więc ma
-- własny pomocnik zamiast powtarzanego launchOrFocus. Nazwa aplikacji służy
-- zarazem za etykietę w ściądze.
function M.app(key, name)
  M.bind(key, name, function() hs.application.launchOrFocus(name) end)
end

-- Wirtualny keyCode F18. Nie myl z numerem klawisza funkcyjnego.
local F18 = 79

M.tap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(e)
  if e:getKeyCode() ~= F18 then return false end
  M.mode:enter()
  return true
end)

M.tap:start()

-- Skróty ------------------------------------------------------------------

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
M.app("x", "CleanShot X")
M.app("n", "Nimble Commander")

return M
