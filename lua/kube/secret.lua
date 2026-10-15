---Secret data as editable text: one `key: "value"` per line in JSON string syntax
---(also valid YAML), `key: !!binary "base64"` for values that are not UTF-8.
local M = {}

local BINARY_TAG = "!!binary "

M.HEADER = {
  '# Decoded secret data, one `key: "value"` per line (JSON string syntax).',
  '# Values that are not UTF-8 are shown as `key: !!binary "<base64>"`.',
  "# :w updates the secret, keys removed here are deleted from it.",
}

---@param s string
---@return boolean
local function is_utf8(s)
  local i, n = 1, #s
  while i <= n do
    local c = s:byte(i)
    local len = c < 0x80 and 1
      or (c >= 0xC2 and c <= 0xDF) and 2
      or (c >= 0xE0 and c <= 0xEF) and 3
      or (c >= 0xF0 and c <= 0xF4) and 4
      or nil
    if not len or i + len - 1 > n then
      return false
    end
    for j = i + 1, i + len - 1 do
      local cc = s:byte(j)
      if cc < 0x80 or cc > 0xBF then
        return false
      end
    end
    i = i + len
  end
  return true
end

---@param data table<string, string>|nil The secret's base64 encoded `data`
---@return string[]
function M.to_lines(data)
  local lines = vim.deepcopy(M.HEADER)
  local keys = vim.tbl_keys(data or {})
  table.sort(keys)
  for _, key in ipairs(keys) do
    local value = vim.base64.decode(data[key])
    if is_utf8(value) then
      table.insert(lines, string.format("%s: %s", key, vim.json.encode(value)))
    else
      table.insert(lines, string.format("%s: %s%s", key, BINARY_TAG, vim.json.encode(data[key])))
    end
  end
  return lines
end

---@param lines string[]
---@return table<string, string>|nil data The base64 encoded data
---@return string|nil err
function M.from_lines(lines)
  local data = {}
  for lnum, line in ipairs(lines) do
    if not line:match("^%s*$") and not line:match("^%s*#") then
      local key, quoted = line:match("^([%w%-%._]+):%s*(.-)%s*$")
      local binary = quoted and vim.startswith(quoted, BINARY_TAG)
      if binary then
        quoted = vim.trim(quoted:sub(#BINARY_TAG + 1))
      end
      local ok, value = pcall(vim.json.decode, quoted or "")
      if not key or not ok or type(value) ~= "string" then
        return nil, string.format('line %d: expected `key: "value"`', lnum)
      end
      if data[key] then
        return nil, string.format("line %d: duplicate key %s", lnum, key)
      end
      if binary then
        if not pcall(vim.base64.decode, value) then
          return nil, string.format("line %d: invalid base64", lnum)
        end
        data[key] = value
      else
        data[key] = vim.base64.encode(value)
      end
    end
  end
  return data
end

---A JSON merge patch turning `old` data into `new`, nil when nothing changed.
---@param old table<string, string>
---@param new table<string, string>
---@return table|nil patch
---@return {added: string[], changed: string[], removed: string[]} changes
function M.patch(old, new)
  local changes = { added = {}, changed = {}, removed = {} }
  local data = {}
  for key, value in pairs(new) do
    if old[key] == nil then
      table.insert(changes.added, key)
      data[key] = value
    elseif old[key] ~= value then
      table.insert(changes.changed, key)
      data[key] = value
    end
  end
  for key in pairs(old) do
    if new[key] == nil then
      table.insert(changes.removed, key)
      data[key] = vim.NIL
    end
  end
  for _, keys in pairs(changes) do
    table.sort(keys)
  end
  if vim.tbl_isempty(data) then
    return nil, changes
  end
  return { data = data }, changes
end

return M
