local M = {}

M.setup = function()
  vim.api.nvim_set_hl(0, "AnonHighlight", { fg = "#00ff00", bg = "#00ff00", bold = true })

  local myname = os.getenv("USER") or "admin"
  local group = vim.api.nvim_create_augroup("HighlightMyName", { clear = true })

  local match_id = nil

  local function refresh_highlights()
    if match_id then
    pcall(vim.fn.matchdelete, match_id)
    match_id = nil
  end
  local ok, id = pcall(vim.fn.matchadd, "AnonHighlight", "\\<" .. myname .. "\\>", 100)
  if ok then match_id = id end
end

vim.api.nvim_create_autocmd({"BufReadPost", "BufNewFile", "TextChanged", "TextChangedI"}, {
  group = group,
  pattern = "*",
    callback = refresh_highlights
})

end

return M
