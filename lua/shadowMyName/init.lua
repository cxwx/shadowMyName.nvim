-- shadowMyName.nvim
-- 屏蔽敏感词（用户名 / 自定义词 / 正则）：把匹配到的文本渲染成同色的色块
-- （fg == bg），从而在截图、录屏时无法被看到。
local M = {}

local hl_group = "AnonHighlight"

-- 当没有显式指定用户名时，自动从环境变量推断
local function default_username()
  return os.getenv("USER") or os.getenv("USERNAME") or "admin"
end

-- 默认配置
local defaults = {
  -- 总开关：是否启用屏蔽
  enabled = true,
  -- 用户名屏蔽
  username = {
    enabled = true, -- 是否屏蔽用户名
    name = nil,     -- 自定义用户名；nil 时自动取 $USER / $USERNAME
  },
  -- 额外要屏蔽的字面量词，例如 { "secret", "token" }
  words = {},
  -- 额外的 vim 正则，例如 { "\\d{4}-\\d{4}", "\\d{3}-\\d{4}" }
  patterns = {},
  -- 是否按“整词”匹配（前后加 \\< \\>）
  whole_word = true,
  -- 是否区分大小写
  case_sensitive = false,
  -- 在这些 filetype 下不屏蔽，例如 { "TelescopePrompt", "NvimTree" }
  filetypes = {},
  -- 屏蔽色块的样式。fg == bg 时文字完全不可见；
  -- 也可以故意设置成 fg != bg 做醒目高亮。
  highlight = {
    fg = "#00ff00",
    bg = "#00ff00",
    bold = true,
  },
}

local config = vim.deepcopy(defaults)
local augroup = nil
-- winid -> { match_id, ... }，记录每个窗口下注册的 match
local match_ids = {}

-- 把转义后的字面量 / 用户名 / 正则汇总成 vim 正则列表
local function build_match_list()
  if not config.enabled then
    return {}
  end

  local items = {}
  local cs = config.case_sensitive and "\\C" or "\\c"

  local function add_literal(text)
    if text == nil or text == "" then
      return
    end
    local p = vim.fn.escape(text, "\\^$.*~[]")
    if config.whole_word then
      p = "\\<" .. p .. "\\>"
    end
    table.insert(items, cs .. p)
  end

  if config.username.enabled then
    add_literal(config.username.name or default_username())
  end
  for _, w in ipairs(config.words or {}) do
    add_literal(w)
  end
  -- patterns 是用户提供的原始正则，原样使用
  for _, p in ipairs(config.patterns or {}) do
    if p ~= nil and p ~= "" then
      table.insert(items, p)
    end
  end

  return items
end

-- 清除某个窗口下注册的所有 match
local function clear_win(win)
  local ids = match_ids[win]
  if ids then
    for _, id in ipairs(ids) do
      pcall(vim.fn.matchdelete, id, win)
    end
  end
  match_ids[win] = {}
end

-- 重新计算某个窗口的屏蔽高亮
local function refresh_win(win)
  win = win or 0
  if win == 0 then
    win = vim.api.nvim_get_current_win()
  end
  if not vim.api.nvim_win_is_valid(win) then
    return
  end

  -- 先清掉旧的 match
  clear_win(win)

  local ok, buf = pcall(vim.api.nvim_win_get_buf, win)
  if not ok then
    return
  end

  -- filetype 排除
  local ft = vim.bo[buf].filetype
  if ft and ft ~= "" and vim.tbl_contains(config.filetypes or {}, ft) then
    return
  end

  local items = build_match_list()
  if #items == 0 then
    return
  end

  vim.api.nvim_win_call(win, function()
    for _, p in ipairs(items) do
      local ok2, id = pcall(vim.fn.matchadd, hl_group, p, 100)
      if ok2 and id then
        table.insert(match_ids[win], id)
      end
    end
  end)
end

local function refresh_all()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    refresh_win(win)
  end
end

-- 重新应用高亮组（colorscheme 切换后会清掉自定义高亮）
local function apply_highlight()
  vim.api.nvim_set_hl(0, hl_group, config.highlight or {})
end

-- public API ----------------------------------------------------------------

function M.enable()
  config.enabled = true
  refresh_all()
end

function M.disable()
  config.enabled = false
  for win in pairs(match_ids) do
    if vim.api.nvim_win_is_valid(win) then
      clear_win(win)
    end
  end
  match_ids = {}
end

function M.toggle()
  if config.enabled then
    M.disable()
  else
    M.enable()
  end
end

function M.refresh()
  refresh_all()
end

-- setup ---------------------------------------------------------------------

function M.setup(opts)
  opts = opts or {}
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)

  apply_highlight()

  -- 命令
  vim.api.nvim_create_user_command("ShadowMyNameEnable", M.enable, { desc = "Enable shadowMyName" })
  vim.api.nvim_create_user_command("ShadowMyNameDisable", M.disable, { desc = "Disable shadowMyName" })
  vim.api.nvim_create_user_command("ShadowMyNameToggle", M.toggle, { desc = "Toggle shadowMyName" })
  vim.api.nvim_create_user_command("ShadowMyNameRefresh", M.refresh, { desc = "Refresh shadowMyName highlights" })

  -- 自动事件
  augroup = vim.api.nvim_create_augroup("HighlightMyName", { clear = true })

  local refresh_events = {
    "BufReadPost",
    "BufNewFile",
    "BufWinEnter",
    "TextChanged",
    "TextChangedI",
    "WinEnter",
    "WinNew",
  }
  vim.api.nvim_create_autocmd(refresh_events, {
    group = augroup,
    pattern = "*",
    callback = function()
      refresh_win(0)
    end,
  })

  -- 窗口关闭时清理记录，避免泄漏
  vim.api.nvim_create_autocmd("WinClosed", {
    group = augroup,
    pattern = "*",
    callback = function(args)
      match_ids[tonumber(args.file)] = nil
    end,
  })

  -- 切换 colorscheme 后自定义高亮会丢失，重新设置
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = augroup,
    pattern = "*",
    callback = apply_highlight,
  })

  -- 启动后首次应用
  vim.schedule(refresh_all)
end

return M
