-- Every wezterm option in the settings menu (gear button > All wezterm options).
--
-- The catalog (options_catalog.lua, generated from the wezterm sources) lists
-- each option with its type, allowed values, default and description.  Values
-- picked in the menu are saved next to the executable in wezterm_options.json
-- and applied on top of wezterm.lua by crt.setup(), so no Lua editing is
-- needed.  wezterm validates every value as it is set: a value it rejects is
-- reported in the menu and never reaches the configuration.
local wezterm = require 'wezterm'
local act = wezterm.action

local M = {}
M.path = wezterm.executable_dir .. '/wezterm_options.json'

-- Stored for optional settings that are switched off ("no value").
local UNSET = '__unset__'

local function catalog() return require 'options_catalog' end

---------------------------------------------------------------------------
-- Storage

function M.load()
  local f = io.open(M.path, 'r')
  if not f then return {} end
  local text = f:read('*a')
  f:close()
  if text:match('^%s*$') then return {} end
  local ok, t = pcall(wezterm.json_parse, text)
  if ok and type(t) == 'table' then return t end
  wezterm.log_warn('options: ignoring unreadable ' .. M.path)
  return {}
end

local function encode(t)
  if next(t) == nil then return '{}\n' end
  local ok, s = pcall(function() return wezterm.serde.json_encode_pretty(t) end)
  if ok and s then return s .. '\n' end
  return wezterm.json_encode(t) .. '\n'
end

function M.save(t)
  local f, err = io.open(M.path, 'w')
  if not f then
    wezterm.log_error('options: cannot write ' .. M.path .. ': ' .. tostring(err))
    return false
  end
  f:write(encode(t))
  f:close()
  wezterm.reload_configuration()
  return true
end

local function store(key, value)
  local o = M.load()
  o[key] = value
  return M.save(o)
end

--- Remove `keys` from the saved options without reloading the
--- configuration (the caller saves something else that reloads it).
function M.forget(keys)
  local o = M.load()
  local found = false
  for _, k in ipairs(keys) do
    if o[k] ~= nil then
      o[k] = nil
      found = true
    end
  end
  if not found then return end
  local f = io.open(M.path, 'w')
  if f then
    f:write(encode(o))
    f:close()
  end
end

-- Options the main settings menu owns (Settings > Font, Font size, Line
-- spacing): not listed here, so each setting has one place, and not applied
-- from wezterm_options.json (crt.apply reads the values older versions
-- saved there).
M.owned = { font = true, font_size = true, line_height = true }

-- `keys` without the owned ones
local function listed(keys)
  local r = {}
  for _, k in ipairs(keys) do
    if not M.owned[k] then table.insert(r, k) end
  end
  return r
end

---------------------------------------------------------------------------
-- Applying values to a config

local function deep_copy(v)
  if type(v) ~= 'table' then return v end
  local r = {}
  for k, x in pairs(v) do r[k] = deep_copy(x) end
  return r
end

local function split(path)
  local segs = {}
  for s in path:gmatch('[^.]+') do table.insert(segs, s) end
  return segs
end

local function get_path(t, path)
  for _, s in ipairs(split(path)) do
    if type(t) ~= 'table' then return nil end
    t = t[s]
  end
  return t
end

-- Structures whose fields wezterm requires together: when only one field is
-- set here, the others start from wezterm's defaults.
local SEED = {
  window_content_alignment = { horizontal = 'Left', vertical = 'Top' },
  ['colors.tab_bar.active_tab'] = { bg_color = '#000000', fg_color = '#c0c0c0' },
  ['colors.tab_bar.inactive_tab'] = { bg_color = '#333333', fg_color = '#808080' },
  ['colors.tab_bar.inactive_tab_hover'] = { bg_color = '#1f1f1f', fg_color = '#909090' },
  ['colors.tab_bar.new_tab'] = { bg_color = '#333333', fg_color = '#808080' },
  ['colors.tab_bar.new_tab_hover'] = { bg_color = '#1f1f1f', fg_color = '#909090' },
}

local function seed(t, prefix)
  for k, v in pairs(SEED[prefix] or {}) do
    if t[k] == nil then t[k] = v end
  end
end

-- The top-level key and value that set `path` (a.b.c) to `value` on top of
-- what `config` already has.  Parent tables are copied, not changed.
local function build(config, path, value)
  local segs = split(path)
  if #segs == 1 then return path, value end
  local root = deep_copy(config[segs[1]])
  if type(root) ~= 'table' then root = {} end
  seed(root, segs[1])
  local t = root
  local prefix = segs[1]
  for i = 2, #segs - 1 do
    if type(t[segs[i]]) ~= 'table' then t[segs[i]] = {} end
    t = t[segs[i]]
    prefix = prefix .. '.' .. segs[i]
    seed(t, prefix)
  end
  t[segs[#segs]] = value
  return segs[1], root
end

-- Stored value -> value for the config
local function to_config(e, v, config, key)
  if v == UNSET then return nil end
  local t = e.t
  if t == 'int' then
    if type(v) == 'number' then return math.tointeger(v) or math.floor(v) end
    return v -- not a number: let wezterm reject it
  elseif t == 'font' then
    return wezterm.font(v)
  elseif t == 'colorspec' then
    return { Color = v }
  elseif t == 'list' and e.append then
    local r = deep_copy(get_path(config, key)) or {}
    for _, x in ipairs(v) do table.insert(r, x) end
    return r
  elseif t == 'list' and e.item and e.item.t == 'int' then
    local r = {}
    for _, x in ipairs(v) do table.insert(r, math.tointeger(x) or x) end
    return r
  end
  return v
end

-- Set one option on a config; returns nil or the error wezterm reported.
-- config_builder() only validates keys that are not set yet, so the value is
-- checked on a fresh builder first and the config is changed only when
-- wezterm accepts it.
local function try_set(config, key, e, v)
  local ok, err = pcall(function()
    local top, value = build(config, key, to_config(e, v, config, key))
    local check = wezterm.config_builder()
    check[top] = value
    config[top] = value
  end)
  if ok then return nil end
  -- keep wezterm's explanation, drop the Lua traceback
  local msg = tostring(err)
  msg = msg:match('from_dynamic: (.-)\n') or msg:match('^[^\n]*')
  msg = msg:gsub('^Error processing ', ''):gsub('^Config::', '')
  return msg
end

--- Apply the options saved in the menu to `config` (called by crt.setup).
function M.apply(config)
  local f = io.open(M.path, 'r')
  if not f then return config end -- nothing saved yet (the menu reloads itself)
  f:close()
  wezterm.add_to_config_reload_watch_list(M.path) -- pick up hand edits too
  local o = M.load()
  if next(o) == nil then return config end
  local cat = catalog()
  local keys = {}
  for k in pairs(o) do table.insert(keys, k) end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local e = cat.options[k]
    if M.owned[k] then
      -- applied by crt.apply (older versions saved these here)
    elseif not e or e.t == 'complex' then
      wezterm.log_warn('options: ignoring unknown option ' .. k)
    else
      local err = try_set(config, k, e, o[k])
      if err then wezterm.log_warn('options: ignoring ' .. k .. ': ' .. err) end
    end
  end
  return config
end

-- Check a value the way wezterm will see it; nil when it is accepted.
local function validate(key, e, v)
  local c = wezterm.config_builder()
  return try_set(c, key, e, v)
end

---------------------------------------------------------------------------
-- Formatting

local function show(v, e)
  if v == nil then return '-' end
  if v == UNSET then return 'none' end
  if type(v) == 'number' then
    if math.type(v) == 'integer' then return tostring(v) end
    return string.format('%g', v)
  end
  if type(v) == 'table' then
    if e and e.t == 'font' then
      local f = v.font and v.font[1] or v[1]
      if type(f) == 'table' and f.family then return f.family end
    end
    if e and e.t == 'gpu' then return tostring(v.name or '?') end
    if e and e.t == 'colorspec' and v.Color then return tostring(v.Color) end
    if #v > 0 then
      local parts = {}
      for _, x in ipairs(v) do table.insert(parts, show(x)) end
      return table.concat(parts, ', ')
    end
    local parts = {}
    for k, x in pairs(v) do
      if type(x) ~= 'table' then table.insert(parts, tostring(k) .. '=' .. show(x)) end
    end
    table.sort(parts)
    if #parts == 0 then return '{}' end
    return '{' .. table.concat(parts, ', ') .. '}'
  end
  return tostring(v)
end

local function clip(s, n)
  if #s <= n then return s end
  return s:sub(1, n - 3) .. '...'
end

local function dim(s)
  return wezterm.format { { Attribute = { Intensity = 'Half' } }, { Text = s } }
end

local function first_sentence(s)
  s = s or ''
  local f = s:match('^(.-[%.!?])%s') or s
  return f
end

local function wrap(text, width)
  local lines, line = {}, ''
  for word in tostring(text):gmatch('%S+') do
    if #line > 0 and #line + #word + 1 > width then
      table.insert(lines, line)
      line = word
    else
      line = (#line > 0) and (line .. ' ' .. word) or word
    end
  end
  if #line > 0 then table.insert(lines, line) end
  return lines
end

local function text_width(pane)
  local ok, d = pcall(function() return pane:get_dimensions() end)
  local cols = (ok and d and d.cols) or 100
  return math.max(40, math.min(120, cols - 10))
end

local APPLIES = {
  new = 'Takes effect in new tabs and windows.',
  restart = 'Takes effect after restarting wezterm.',
}

---------------------------------------------------------------------------
-- Menu plumbing

local HINT = '      Up/Down = move, Enter = choose, Esc = back, / = search'

local function selector(window, pane, crumbs, choices, on_pick, on_back, fuzzy)
  window:perform_action(
    act.InputSelector {
      title = crumbs,
      description = crumbs .. HINT,
      alphabet = '', -- no number labels: arrow keys only
      choices = choices,
      fuzzy = fuzzy or false,
      action = wezterm.action_callback(function(w, p, id, _label)
        if id then
          on_pick(w, p, id)
        elseif on_back then
          on_back(w, p)
        end
      end),
    },
    pane
  )
end

local function prompt(window, pane, description, initial, on_line, on_back)
  window:perform_action(
    act.PromptInputLine {
      description = description,
      initial_value = initial,
      action = wezterm.action_callback(function(w, p, line)
        if line == nil then
          on_back(w, p)
        else
          on_line(w, p, line)
        end
      end),
    },
    pane
  )
end

-- Current value: the one saved in the menu, else what the running config has.
local function current(window, o, key)
  if o[key] ~= nil then return o[key], true end
  local ok, cfg = pcall(function() return window:effective_config() end)
  if not ok then return nil, false end
  return get_path(cfg, key), false
end

local function changed_count(o, keys)
  local n = 0
  for _, k in ipairs(keys) do
    if o[k] ~= nil then n = n + 1 end
  end
  return n
end

local function option_row(window, o, key, e, cfg)
  local v = o[key]
  local set = v ~= nil
  if not set then v = get_path(cfg, key) end
  local value = (e.t == 'complex') and '(wezterm.lua)' or clip(show(v, e), 22)
  local mark = set and '* ' or '  '
  return mark .. string.format('%-46s %-22s ', key, value) .. dim(clip(first_sentence(e.doc), 90))
end

---------------------------------------------------------------------------
-- Editors

local editor -- forward

local function parse_input(e, line)
  local s = line:gsub('^%s+', ''):gsub('%s+$', '')
  local t = e.t
  if t == 'int' then
    local n = math.tointeger(tonumber(s))
    if not n then return nil, 'Needs a whole number.' end
    return n
  elseif t == 'float' then
    local n = tonumber(s)
    if not n then return nil, 'Needs a number.' end
    return n
  elseif t == 'dimension' then
    local n = tonumber(s)
    if n then return n end
    local compact = s:gsub('%s', '')
    if compact:match('^%-?[%d%.]+cell$') or compact:match('^%-?[%d%.]+pt$')
      or compact:match('^%-?[%d%.]+px$') or compact:match('^%-?[%d%.]+%%$') then
      return compact
    end
    return nil, 'Use pixels (8) or a unit: 1cell, 0.5cell, 10pt, 8px, 5%.'
  elseif t == 'color' or t == 'colorspec' then
    for _, x in ipairs(e.extra or {}) do
      if s:lower() == x:lower() then return x end
    end
    if s == '' then return nil, 'Needs a color such as #ff8100 or a CSS color name.' end
    return s
  elseif t == 'font' then
    if s == '' then return nil, 'Needs a font family name.' end
    return s
  end
  return line
end

-- The list or map an edit starts from.  Lists that are added to wezterm.lua's
-- (font_dirs, color_scheme_dirs) only hold the items added in this menu.
local function list_base(window, key, e)
  local o = M.load()
  local cur
  if e.append then
    cur = o[key]
  else
    cur = current(window, o, key)
  end
  if type(cur) ~= 'table' then return {} end
  return deep_copy(cur)
end

local function value_prompt(window, pane, key, e, crumbs, back, err)
  local o = M.load()
  local v = current(window, o, key)
  local initial = ''
  if v ~= nil and v ~= UNSET and type(v) ~= 'table' then initial = show(v, e) end
  if e.t == 'font' and type(v) == 'table' then initial = show(v, e) end
  local lines = { crumbs .. ' > ' .. key, '' }
  for _, l in ipairs(wrap(e.doc, 100)) do table.insert(lines, l) end
  if e.default then table.insert(lines, 'Default: ' .. e.default) end
  table.insert(lines, '')
  if err then table.insert(lines, 'Not accepted: ' .. err) end
  table.insert(lines, 'Type the new ' .. e.t .. ' value. Enter = save, Esc = back.')
  prompt(window, pane, table.concat(lines, '\n'), initial, function(w, p, line)
    local value, perr = parse_input(e, line)
    if value == nil then return value_prompt(w, p, key, e, crumbs, back, perr) end
    local verr = validate(key, e, value)
    if verr then return value_prompt(w, p, key, e, crumbs, back, verr) end
    store(key, value)
    back(w, p)
  end, function(w, p) editor(w, p, key, crumbs, back) end)
end

local function list_add_prompt(window, pane, key, e, crumbs, back, err)
  local item = e.item or { t = 'string' }
  local lines = { crumbs .. ' > ' .. key, '' }
  if e.t == 'map' then
    table.insert(lines, 'Add an entry as NAME=VALUE.')
  else
    table.insert(lines, 'Add an item (' .. item.t .. ').')
  end
  if err then table.insert(lines, 'Not accepted: ' .. err) end
  table.insert(lines, 'Enter = add, Esc = back.')
  prompt(window, pane, table.concat(lines, '\n'), '', function(w, p, line)
    local list = list_base(w, key, e)
    if e.t == 'map' then
      local name, value = line:match('^%s*([^=]-)%s*=%s*(.-)%s*$')
      if not name or name == '' then return list_add_prompt(w, p, key, e, crumbs, back, 'Use NAME=VALUE.') end
      if item.t ~= 'string' then
        value = tonumber(value)
        if not value then return list_add_prompt(w, p, key, e, crumbs, back, 'The value must be a number.') end
      end
      list[name] = value
    else
      local value, perr = parse_input(item, line)
      if value == nil then return list_add_prompt(w, p, key, e, crumbs, back, perr) end
      table.insert(list, value)
    end
    local verr = validate(key, e, list)
    if verr then return list_add_prompt(w, p, key, e, crumbs, back, verr) end
    store(key, list)
    editor(w, p, key, crumbs, back)
  end, function(w, p) editor(w, p, key, crumbs, back) end)
end

-- Installed font families, from `wezterm ls-fonts --list-system`.
local function system_fonts()
  local exe = wezterm.executable_dir .. '/wezterm.exe'
  local ok, success, stdout = pcall(wezterm.run_child_process, { exe, 'ls-fonts', '--list-system' })
  if not ok or not success then return {} end
  local seen, list = {}, {}
  for fam in stdout:gmatch('wezterm%.font%("([^"]+)"') do
    if not seen[fam] then
      seen[fam] = true
      table.insert(list, fam)
    end
  end
  table.sort(list, function(a, b) return a:lower() < b:lower() end)
  return list
end

local function font_picker(window, pane, key, e, crumbs, back)
  local fams = system_fonts()
  local choices = {}
  for _, f in ipairs(fams) do table.insert(choices, { id = f, label = f }) end
  if #choices == 0 then
    table.insert(choices, { id = '__none', label = '(no fonts found)' })
  end
  selector(window, pane, crumbs .. ' > ' .. key .. ' > installed fonts', choices, function(w, p, id)
    if id ~= '__none' then store(key, id) end
    back(w, p)
  end, function(w, p) editor(w, p, key, crumbs, back) end, true)
end

local function gpu_picker(window, pane, key, e, crumbs, back)
  local ok, gpus = pcall(function() return wezterm.gui.enumerate_gpus() end)
  local choices = {}
  if ok and gpus then
    for i, g in ipairs(gpus) do
      table.insert(choices, {
        id = tostring(i),
        label = string.format('%s  (%s, %s)', tostring(g.name), tostring(g.backend), tostring(g.device_type)),
      })
    end
  end
  if #choices == 0 then table.insert(choices, { id = '__none', label = '(no adapters reported)' }) end
  selector(window, pane, crumbs .. ' > ' .. key .. ' > adapters', choices, function(w, p, id)
    if id ~= '__none' then store(key, gpus[tonumber(id)]) end
    back(w, p)
  end, function(w, p) editor(w, p, key, crumbs, back) end)
end

local function flag_set(s)
  local set = {}
  for f in tostring(s or ''):gmatch('[^|]+') do
    f = f:gsub('^%s+', ''):gsub('%s+$', '')
    if f ~= '' then set[f] = true end
  end
  return set
end

editor = function(window, pane, key, crumbs, back)
  local e = catalog().options[key]
  local o = M.load()
  local v, is_set = current(window, o, key)
  local t = e.t
  local here = crumbs .. ' > ' .. key
  local width = text_width(pane)
  local choices = {}
  local function item(id, label) table.insert(choices, { id = id, label = label }) end
  local function info(text)
    for _, l in ipairs(wrap(text, width)) do item('__info', dim('    ' .. l)) end
  end
  -- '>' marks the value in effect
  local function mark(x)
    if x == UNSET then return (v == nil or v == UNSET) and '> ' or '  ' end
    return (v == x) and '> ' or '  '
  end

  -- Actions first, so the cursor starts on them
  if t == 'bool' then
    item('true', mark(true) .. 'true')
    item('false', mark(false) .. 'false')
  elseif t == 'enum' then
    for _, x in ipairs(e.values) do item('=' .. x, mark(x) .. x) end
  elseif t == 'flags' then
    local set = flag_set(v)
    for _, x in ipairs(e.values) do
      item('flag:' .. x, (set[x] and '  [x] ' or '  [ ] ') .. x)
    end
  elseif t == 'list' or t == 'map' then
    local base = list_base(window, key, e)
    if t == 'list' then
      for i, x in ipairs(base) do item('del:' .. i, '  - ' .. show(x) .. dim('   (Enter = remove)')) end
    else
      local names = {}
      for k in pairs(base) do table.insert(names, k) end
      table.sort(names)
      for _, k in ipairs(names) do
        item('del:' .. k, '  - ' .. k .. ' = ' .. show(base[k]) .. dim('   (Enter = remove)'))
      end
    end
    if e.item and e.item.t == 'enum' then
      for _, x in ipairs(e.item.values) do item('add:' .. x, '  + add ' .. x) end
    else
      item('__add', (t == 'map') and '  + Add NAME=VALUE ...' or '  + Add ...')
    end
    item('__clear', e.append and '  Remove all added items' or '  Clear the list')
  elseif t == 'gpu' then
    item('__gpu', '  Choose an adapter ...')
  elseif t == 'complex' then
    item('__edit', '  Edit wezterm.lua (opens Notepad)')
  else
    item('__input', '  Enter a value ...   ' .. dim('(' .. t .. ')'))
    if t == 'font' then item('__fonts', '  Pick an installed font ...') end
    for _, x in ipairs(e.extra or {}) do item('=' .. x, mark(x) .. x) end
  end
  if e.nullable and t ~= 'complex' then item('__unset', mark(UNSET) .. 'none (no value)') end
  if is_set then item('__reset', '  Reset: use the value from wezterm.lua / the default') end
  if e.url then item('__docs', '  Open the documentation in the browser') end

  -- Then the description
  item('__info', dim('  ' .. string.rep('-', math.min(width, 60))))
  if t == 'complex' then
    info('Current: set in wezterm.lua')
  else
    info('Current: ' .. show(v, e) .. (is_set and '   (set in this menu)' or ''))
  end
  if e.default then info('Default: ' .. e.default) end
  if e.applies then info(APPLIES[e.applies]) end
  if e.append then info('Items added here are appended to the ones wezterm.lua sets.') end
  if e.note then info('Note: ' .. e.note) end
  info(e.doc ~= '' and e.doc or key)

  local function again(w, p) editor(w, p, key, crumbs, back) end
  selector(window, pane, here, choices, function(w, p, id)
    if id == '__info' then return again(w, p) end
    if id == 'true' or id == 'false' then
      store(key, id == 'true')
      return back(w, p)
    end
    if id:sub(1, 1) == '=' then
      store(key, id:sub(2))
      return back(w, p)
    end
    if id:sub(1, 5) == 'flag:' then
      local f = id:sub(6)
      local set = flag_set((current(w, M.load(), key)))
      set[f] = not set[f] or nil
      local parts = {}
      for _, x in ipairs(e.values) do
        if set[x] then table.insert(parts, x) end
      end
      local value = (#parts > 0) and table.concat(parts, '|') or e.empty
      local err = validate(key, e, value)
      if err then
        wezterm.log_warn('options: ' .. key .. ': ' .. err)
      else
        store(key, value)
      end
      return again(w, p)
    end
    if id:sub(1, 4) == 'del:' then
      local list = list_base(w, key, e)
      local which = id:sub(5)
      if t == 'list' then
        table.remove(list, tonumber(which))
      else
        list[which] = nil
      end
      store(key, list)
      return again(w, p)
    end
    if id:sub(1, 4) == 'add:' then
      local list = list_base(w, key, e)
      table.insert(list, id:sub(5))
      store(key, list)
      return again(w, p)
    end
    if id == '__add' then return list_add_prompt(w, p, key, e, crumbs, back) end
    if id == '__clear' then
      store(key, {})
      return again(w, p)
    end
    if id == '__input' then return value_prompt(w, p, key, e, crumbs, back) end
    if id == '__fonts' then return font_picker(w, p, key, e, crumbs, back) end
    if id == '__gpu' then return gpu_picker(w, p, key, e, crumbs, back) end
    if id == '__unset' then
      store(key, UNSET)
      return back(w, p)
    end
    if id == '__reset' then
      store(key, nil)
      return back(w, p)
    end
    if id == '__docs' then
      wezterm.open_with(e.url)
      return again(w, p)
    end
    if id == '__edit' then
      wezterm.background_child_process { 'notepad.exe', wezterm.config_file }
      return
    end
  end, back)
end

---------------------------------------------------------------------------
-- Lists of options

local root -- forward

local function options_list(window, pane, crumbs, keys, back, fuzzy)
  local cat = catalog()
  local o = M.load()
  local ok, cfg = pcall(function() return window:effective_config() end)
  if not ok then cfg = {} end
  local choices = {}
  for _, k in ipairs(keys) do
    local e = cat.options[k]
    if fuzzy then
      local v = o[k]
      if v == nil then v = get_path(cfg, k) end
      local value = (e.t == 'complex') and '(wezterm.lua)' or clip(show(v, e), 22)
      table.insert(choices, {
        id = k,
        label = string.format('%s%-46s %-22s %s', o[k] ~= nil and '* ' or '  ', k, value,
          clip(first_sentence(e.doc), 80)),
      })
    else
      table.insert(choices, { id = k, label = option_row(window, o, k, e, cfg) })
    end
  end
  local function again(w, p) options_list(w, p, crumbs, keys, back, fuzzy) end
  selector(window, pane, crumbs, choices, function(w, p, id)
    editor(w, p, id, crumbs, again)
  end, back, fuzzy)
end

local function all_keys()
  local cat = catalog()
  local keys = {}
  for _, c in ipairs(cat.categories) do
    for _, k in ipairs(listed(c.keys)) do table.insert(keys, k) end
  end
  return keys
end

root = function(window, pane, back)
  local cat = catalog()
  local o = M.load()
  local all = all_keys()
  local n_changed = changed_count(o, all)
  local crumbs = 'Settings > wezterm settings'
  local choices = {}
  -- the categories first, then search and the wezterm.lua tools
  for i, c in ipairs(cat.categories) do
    local keys = listed(c.keys)
    local n = changed_count(o, keys)
    table.insert(choices, {
      id = 'cat:' .. i,
      label = string.format('  %-38s %3d', c.name, #keys) .. dim(n > 0 and string.format('   %d changed', n) or ''),
    })
  end
  table.insert(choices, { id = '__sep', label = dim('  ' .. string.rep('-', 44)) })
  table.insert(choices, { id = '__search', label = string.format('  Search all %d settings ...', #all) })
  if n_changed > 0 then
    table.insert(choices, { id = '__changed', label = string.format('  Changed settings (%d)', n_changed) })
  end
  table.insert(choices, { id = '__edit', label = '  Edit wezterm.lua (key bindings, domains, ...)' })
  table.insert(choices, { id = '__reload', label = '  Reload configuration' })
  table.insert(choices, { id = '__palette', label = '  All commands (command palette)' })
  local function again(w, p) root(w, p, back) end
  selector(window, pane, crumbs, choices, function(w, p, id)
    if id == '__sep' then
      return again(w, p)
    elseif id == '__search' then
      return options_list(w, p, crumbs .. ' > search', all_keys(), again, true)
    elseif id == '__changed' then
      local o2 = M.load()
      local keys = {}
      for _, k in ipairs(all_keys()) do
        if o2[k] ~= nil then table.insert(keys, k) end
      end
      return options_list(w, p, crumbs .. ' > changed', keys, again)
    elseif id == '__edit' then
      wezterm.background_child_process { 'notepad.exe', wezterm.config_file }
    elseif id == '__reload' then
      w:perform_action(act.ReloadConfiguration, p)
    elseif id == '__palette' then
      w:perform_action(act.ActivateCommandPalette, p)
    else
      local i = tonumber(id:match('^cat:(%d+)$'))
      local c = cat.categories[i]
      return options_list(w, p, crumbs .. ' > ' .. c.name, listed(c.keys), again)
    end
  end, back)
end

--- Open the settings (all categories); `back(window, pane)` is called on Esc.
function M.menu(window, pane, back)
  root(window, pane, back)
end

--- Number of settings changed in the menu.
function M.changed()
  return changed_count(M.load(), all_keys())
end

--- Ask, then reset every setting changed in the menu; returns to `back`.
function M.reset_menu(window, pane, back)
  local n = M.changed()
  if n == 0 then
    return selector(window, pane, 'Settings > Reset settings', {
      { id = 'ok', label = '  Nothing to reset: no setting was changed in the menu' },
    }, function(w, p) back(w, p) end, back)
  end
  selector(window, pane, 'Settings > Reset settings', {
    { id = 'no', label = '  No, keep them' },
    { id = 'yes', label = string.format('  Yes, reset %d changed settings to wezterm.lua / defaults', n) },
  }, function(w, p, ans)
    if ans == 'yes' then M.save({}) end
    back(w, p)
  end, back)
end

--- Number of options in the catalog (for the menu label).
function M.count()
  local n = catalog().top_level_count
  for k in pairs(M.owned) do
    if catalog().options[k] then n = n - 1 end
  end
  return n
end

--- Installed font families (slow: runs `wezterm ls-fonts`).
M.system_fonts = system_fonts

-- Exposed for tests
M._validate = validate
M._parse_input = parse_input
M._show = show
M._UNSET = UNSET

return M
