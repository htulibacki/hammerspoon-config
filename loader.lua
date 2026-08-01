return function(mod)
  local ok, err = pcall(require, mod)
  if not ok then
    local msg = tostring(err):gsub("^.-%.hammerspoon/", "")
    hs.alert.show("⚠️ Błąd modułu: " .. mod .. "\n" .. msg, 6)
    print("BŁĄD w " .. mod .. ": " .. tostring(err))
  end
  return ok
end
