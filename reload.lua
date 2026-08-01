local M = {}

M.watcher = hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", function(files)
  for _, f in pairs(files) do
    if f:sub(-4) == ".lua" then hs.reload() ; return end
  end
end):start()

return M
