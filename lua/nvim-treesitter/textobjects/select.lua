local api = vim.api
local configs = require "nvim-treesitter.configs"
local parsers = require "nvim-treesitter.parsers"
local queries = require "nvim-treesitter.query"

local shared = require "nvim-treesitter.textobjects.shared"
local ts_utils = require "nvim-treesitter.ts_utils"

local M = {}

function M.select_textobject(query_string, keymap_mode)
  local lookahead = configs.get_module("textobjects.select").lookahead
  local lookbehind = configs.get_module("textobjects.select").lookbehind
  local include_surrounding_whitespace = configs.get_module("textobjects.select").include_surrounding_whitespace
  local bufnr, textobject =
    shared.textobject_at_point(query_string, nil, nil, { lookahead = lookahead, lookbehind = lookbehind })
  if textobject then
    if include_surrounding_whitespace then
      P(textobject)
      textobject = M.include_surrounding_whitespace(bufnr, textobject)
      P(textobject)
      return
    end
    ts_utils.update_selection(bufnr, textobject, M.detect_selection_mode(query_string, keymap_mode))
  end
end

function M.include_surrounding_whitespace(bufnr, textobject)
  -- local start_row, start_col, end_row, end_col = ts_utils.get_vim_range(textobject, bufnr)
  local start_row, start_col, end_row, end_col = unpack(textobject)
  M.set_cursor(end_row, end_col)
  -- vim.api.nvim_win_set_cursor(0, {end_row + 1, end_col})
  -- vim.fn.setpos(".", { bufnr, end_row, end_col, 0 })
  -- search to the next non-whitespace and then one character back
  vim.fn.search([[\S]])
  vim.fn.search([[.\|\n]], 'b')
  end_row, end_col = M.get_cursor()

  -- don't extend in both directions
  -- if not (end_row == textobject[3] and end_col == textobject[4]) then
  --   return {start_row, start_col, end_row, end_col + 1}
  -- end
  -- end_row, end_col = unpack(vim.api.nvim_win_get_cursor(0))

  M.set_cursor(start_row, start_col)
  -- vim.api.nvim_win_set_cursor(0, {start_row + 1, start_col})
  -- vim.fn.setpos(".", { bufnr, start_row, start_col, 0 })
  -- -- search to the next non-whitespace and then one character back
  vim.fn.search([[\S]], 'b')
  vim.fn.search([[.\|\n]])
  start_row, start_col = M.get_cursor()
  if start_col == 0 then
    start_row = start_row - 1
    start_col = #M.get_line(bufnr, start_row)
  end
  -- start_row, start_col = unpack(vim.api.nvim_win_get_cursor(0))
  return {start_row, start_col, end_row, end_col + 1}
end

function M.set_cursor(row, col)
  vim.api.nvim_win_set_cursor(0, {row + 1, col})
end

function M.get_cursor()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  return row - 1, col
end

function M.include_surrounding_whitespace_(bufnr, textobject)
  local start_row, start_col, end_row, end_col = unpack(textobject)
  local extended = false
  while M.can_expand(bufnr, end_row, end_col) do
    extended = true
    end_row, end_col = M.next_position(bufnr, end_row, end_col, true)
  end
  if extended then
    -- don't extend in both directions
    return { start_row, start_col, end_row, end_col }
  end
  local next_row, next_col = M.next_position(bufnr, start_row, start_col, false)
  while M.can_expand(bufnr, next_row, next_col) do
    start_row = next_row
    start_col = next_col
    next_row, next_col = M.next_position(bufnr, start_row, start_col, false)
  end
  return { start_row, start_col, end_row, end_col }
end

function M.can_expand(bufnr, row, col)
  -- return #M.get_line(bufnr, row) == 0 or M.is_whitespace_after(bufnr, row, col)
  return M.is_whitespace_after(bufnr, row, col)
end

function M.is_whitespace_after(bufnr, row, col)
  P(bufnr, row, col)
  if col == #M.get_line(bufnr, row) then
    if row == vim.api.nvim_buf_line_count(bufnr) then
      return false
    end
    row = row + 1
    col = 0
  end
  local char = M.get_char_after_position(bufnr, row, col)
  P(char)
  if char == nil then
    return false
  end
  if char == "" then
    return true
  end
  return string.match(char, "%s")
end

function M.get_char_after_position(bufnr, row, col)
  if row == nil then
    return nil
  end
  P(row, col)
  return vim.api.nvim_buf_get_text(bufnr, row, col, row, col + 1, {})[1]
end

function M.next_position(bufnr, row, col, forward)
  local max_col = #M.get_line(bufnr, row)
  local max_row = vim.api.nvim_buf_line_count(bufnr)
  if forward then
    if col == max_col then
      if row == max_row then
        return nil
      end
      row = row + 1
      col = 0
    else
      col = col + 1
    end
  else
    if col == 0 then
      if row == 0 then
        return nil
      end
      row = row - 1
      col = #M.get_line(bufnr, row)
    else
      col = col - 1
    end
  end
  return row, col
end

function M.get_line(bufnr, row)
  return vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
end

function M.detect_selection_mode(query_string, keymap_mode)
  -- Update selection mode with different methods based on keymapping mode
  local keymap_to_method = {
    o = "operator-pending",
    s = "visual",
    v = "visual",
    x = "visual",
  }
  local method = keymap_to_method[keymap_mode]

  local config = configs.get_module "textobjects.select"
  local selection_mode = config.selection_modes[query_string] or "v"
  if method == "visual" then
    selection_mode = vim.fn.visualmode()
  elseif method == "operator-pending" then
    local ctrl_v = vim.api.nvim_replace_termcodes("<c-v>", true, true, true)
    local t = {
      noV = "V",
      ["no" .. ctrl_v] = "<c-v>",
    }
    selection_mode = t[vim.fn.mode(1)] or selection_mode
  end

  local t = {
    v = "charwise",
    V = "linewise",
    ["<c-v>"] = "blockwise",
  }
  return t[selection_mode]
end

function M.attach(bufnr, lang)
  local buf = bufnr or api.nvim_get_current_buf()
  local config = configs.get_module "textobjects.select"
  lang = lang or parsers.get_buf_lang(buf)

  for mapping, query in pairs(config.keymaps) do
    if not queries.get_query(lang, "textobjects") then
      query = nil
    end
    if query then
      local cmd_o = ":lua require'nvim-treesitter.textobjects.select'.select_textobject('" .. query .. "', 'o')<CR>"
      api.nvim_buf_set_keymap(buf, "o", mapping, cmd_o, { silent = true, noremap = true })
      local cmd_x = ":lua require'nvim-treesitter.textobjects.select'.select_textobject('" .. query .. "', 'x')<CR>"
      api.nvim_buf_set_keymap(buf, "x", mapping, cmd_x, { silent = true, noremap = true })
    end
  end
end

function M.detach(bufnr)
  local buf = bufnr or api.nvim_get_current_buf()
  local config = configs.get_module "textobjects.select"
  local lang = parsers.get_buf_lang(bufnr)

  for mapping, query in pairs(config.keymaps) do
    if not queries.get_query(lang, "textobjects") then
      query = nil
    end
    if query then
      api.nvim_buf_del_keymap(buf, "o", mapping)
      api.nvim_buf_del_keymap(buf, "x", mapping)
    end
  end
end

M.commands = {
  TSTextobjectSelect = {
    run = M.select_textobject,
    args = {
      "-nargs=1",
      "-complete=custom,nvim_treesitter_textobjects#available_textobjects",
    },
  },
}

return M
