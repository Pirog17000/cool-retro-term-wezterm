-- cool-retro-term look for wezterm: profiles, fonts, title bar styling and the
-- settings menu opened by the gear button in the title bar.
--
--   local crt = require 'crt'
--   crt.apply(config, { profile = 'Monochrome Green' })
--   crt.setup(config)          -- settings menu + keybinding
--
-- The CRT effect values themselves are rendered by the wezterm binary
-- (config.crt).  Choices made in the settings menu are saved next to the
-- executable in crt_state.json and win over the values in wezterm.lua.
local wezterm = require 'wezterm'
local act = wezterm.action
local data = require 'crt_data'
local options = require 'options' -- every other wezterm option, see options.lua
local update = require 'update' -- Settings > Update, see update.lua

local M = {}
M.fonts = data.fonts
M.font_ids = data.font_ids
M.profiles = data.profiles
M.profile_names = data.profile_names

-- Effects editable from the menu: key in config.crt, label
M.effects = {
  { 'bloom', 'Bloom' },
  { 'burn_in', 'Burn-in' },
  { 'static_noise', 'Static noise' },
  { 'jitter', 'Jitter' },
  { 'glowing_line', 'Glowing line' },
  { 'flickering', 'Flickering' },
  { 'horizontal_sync', 'Horizontal sync' },
  { 'rgb_shift', 'RGB shift' },
  { 'brightness', 'Brightness' },
  { 'contrast', 'Contrast' },
  { 'chroma_color', 'Chroma color' },
  { 'saturation_color', 'Saturation' },
  { 'ambient_light', 'Ambient light' },
  { 'frame_shininess', 'Frame shininess' },
  { 'pointer_reflection', 'Pointer reflection' },
  -- the screen shape, kept together at the end of the sliders
  { 'screen_curvature', 'Screen curvature', shape = true },
  { 'frame_size', 'Frame size', shape = true },
  { 'screen_radius', 'Screen radius', shape = true },
}

-- Effects that are not part of cool-retro-term's profiles: their defaults
M.effect_defaults = { pointer_reflection = 0.5 }

M.rasterization_names = { [0] = 'None', 'Scanlines', 'Pixels', 'Sub-pixels', 'Modern' }

M.phosphors = {
  { 'Amber', '#ff8100' },
  { 'Green', '#0ccc68' },
  { 'Apple green', '#4dff6b' },
  { 'Light blue', '#7fb4ff' },
  { 'Cyan', '#52f7ff' },
  { 'Pink', '#ff9bd6' },
  { 'White', '#ffffff' },
}

-- Keys of crt.apply() options that are not config.crt fields
local LOCAL_KEYS = {
  profile = true, font = true, font_family = true, cell_height = true, font_size = true,
  line_spacing = true, style_window = true,
}

local function lint(a, b, t) return (1 - t) * a + t * b end

local function parse_hex(s)
  s = s:gsub('#', '')
  return {
    tonumber(s:sub(1, 2), 16) / 255,
    tonumber(s:sub(3, 4), 16) / 255,
    tonumber(s:sub(5, 6), 16) / 255,
  }
end

local function to_hex(c)
  local function b(v) return math.max(0, math.min(255, math.floor(v * 255 + 0.5))) end
  return string.format('#%02x%02x%02x', b(c[1]), b(c[2]), b(c[3]))
end

local function mix(a, b, t)
  return { lint(a[1], b[1], t), lint(a[2], b[2], t), lint(a[3], b[3], t) }
end

local function copy(t)
  local r = {}
  for k, v in pairs(t or {}) do r[k] = v end
  return r
end

---------------------------------------------------------------------------
-- Persistent state (settings menu)

M.state_path = wezterm.executable_dir .. '/crt_state.json'

function M.load_state()
  local f = io.open(M.state_path, 'r')
  if not f then return {} end
  local text = f:read('*a')
  f:close()
  local ok, t = pcall(wezterm.json_parse, text)
  if ok and type(t) == 'table' then return t end
  wezterm.log_warn('crt: ignoring unreadable ' .. M.state_path)
  return {}
end

local function write_state(t)
  local f, err = io.open(M.state_path, 'w')
  if not f then
    wezterm.log_error('crt: cannot write ' .. M.state_path .. ': ' .. tostring(err))
    return false
  end
  f:write(wezterm.json_encode(t))
  f:close()
  return true
end

function M.save_state(t)
  if write_state(t) then wezterm.reload_configuration() end
end

local function update_state(fn)
  local s = M.load_state()
  fn(s)
  M.save_state(s)
end

---------------------------------------------------------------------------
-- Colors

--- Phosphor colors exactly as cool-retro-term derives them from a profile.
function M.phosphor_colors(p)
  local font = parse_hex(p.font_color or '#ff8100')
  local bg = parse_hex(p.background_color or '#000000')
  local saturated = mix(font, { 1, 1, 1 }, (p.saturation_color or 0.2) * 0.5)
  local k = 0.7 + (p.contrast or 0.8) * 0.3
  return mix(bg, saturated, k), mix(saturated, bg, k)
end

--- Title bar (tab bar + window buttons) in the profile's colors, drawn
--- without CRT effects above the screen.
function M.style_window(config, p, f)
  local fg, bg = M.phosphor_colors(p)
  local bar = to_hex(mix(bg, fg, 0.06))
  local bar_inactive = to_hex(mix(bg, fg, 0.03))
  local tab_active = to_hex(mix(bg, fg, 0.22))
  local tab_inactive = to_hex(mix(bg, fg, 0.10))
  local tab_hover = to_hex(mix(bg, fg, 0.32))
  local text = to_hex(fg)
  local text_dim = to_hex(mix(bg, fg, 0.6))

  config.window_frame = config.window_frame or {}
  local wf = config.window_frame
  wf.font = wf.font or wezterm.font_with_fallback { f.family, 'Consolas' }
  wf.font_size = wf.font_size or 11
  wf.active_titlebar_bg = wf.active_titlebar_bg or bar
  wf.inactive_titlebar_bg = wf.inactive_titlebar_bg or bar_inactive
  wf.active_titlebar_fg = wf.active_titlebar_fg or text
  wf.inactive_titlebar_fg = wf.inactive_titlebar_fg or text_dim
  wf.button_fg = wf.button_fg or text
  wf.button_bg = wf.button_bg or bar
  wf.button_hover_fg = wf.button_hover_fg or to_hex(bg)
  wf.button_hover_bg = wf.button_hover_bg or text

  config.colors = config.colors or {}
  config.colors.tab_bar = config.colors.tab_bar or {
    background = bar,
    inactive_tab_edge = bar,
    active_tab = { bg_color = tab_active, fg_color = text },
    inactive_tab = { bg_color = tab_inactive, fg_color = text_dim },
    inactive_tab_hover = { bg_color = tab_hover, fg_color = text },
    new_tab = { bg_color = bar, fg_color = text_dim },
    new_tab_hover = { bg_color = tab_hover, fg_color = text },
  }
  config.integrated_title_button_color = config.integrated_title_button_color or text
end

---------------------------------------------------------------------------
-- Font, font size, line spacing
--
-- One place for them: the main settings menu (and Ctrl+= / Ctrl+- / Ctrl+0
-- for the size) saves them in crt_state.json.  Older versions kept font,
-- font_size and line_height under All settings (wezterm_options.json); those
-- values still count until the menu saves its own.

local function num(v)
  if math.abs(v - math.floor(v + 0.5)) < 1e-6 then return string.format('%d', math.floor(v + 0.5)) end
  return string.format('%.1f', v)
end

--- The font to use: an installed family (opts.font_family), else a bundled
--- font (opts.font, an id from crt_data.fonts), else the profile's font.
function M.font_for(p, opts)
  if opts.font_family then
    return { name = opts.font_family, family = opts.font_family, scaled = false, installed = true }
  end
  return M.fonts[opts.font or p.font] or M.fonts.TERMINESS_SCALED
end

--- The sizes a font can take, in points, and their names.  Pixel fonts go
--- in whole and half multiples of their design size up to 96 px cells
--- (whole multiples keep every pixel sharp); other fonts in points.
function M.size_steps(f)
  local steps, names = {}, {}
  if f.scaled then
    local kmax = math.max(2, math.min(16, math.floor(2 * 96 / f.pixel_size)))
    for k = 2, kmax do
      local px = f.pixel_size * k / 2
      table.insert(steps, px * 0.75)
      table.insert(names, string.format('%s px  (x%s)', num(px), num(k / 2)))
    end
  else
    for pt = 6, 40 do
      table.insert(steps, pt)
      table.insert(names, pt .. ' pt')
    end
  end
  return steps, names
end

local function nearest(steps, v)
  local best, dist = 1, math.huge
  for i, s in ipairs(steps) do
    local d = math.abs(s - v)
    if d < dist then best, dist = i, d end
  end
  return best
end

--- Index into size_steps(f) of the size in effect.
function M.size_index(f, opts)
  local steps = M.size_steps(f)
  if opts.font_size then return nearest(steps, opts.font_size) end
  if f.scaled then
    local scale = math.max(1, math.floor((opts.cell_height or 24) / f.pixel_size + 0.5))
    return math.min(#steps, 2 * scale - 1)
  end
  return nearest(steps, 13)
end

-- Text settings older versions saved under All settings
local LEGACY_TEXT = { 'font', 'font_size', 'line_height' }

--- Font, font size and line spacing in effect: the menu's (crt_state.json),
--- else the ones older versions saved (wezterm_options.json), else `base`
--- (wezterm.lua's crt.apply options).
function M.text_opts(state, base)
  base = base or {}
  local t = {
    font = base.font, font_family = base.font_family, font_size = base.font_size,
    cell_height = base.cell_height, line_spacing = base.line_spacing,
  }
  local legacy = options.load()
  if type(legacy.font) == 'string' and legacy.font ~= '' then
    t.font, t.font_family = nil, legacy.font
  end
  if type(legacy.font_size) == 'number' then t.font_size = legacy.font_size end
  if type(legacy.line_height) == 'number' then t.line_spacing = legacy.line_height - 1 end
  if state.font or state.font_family then
    t.font, t.font_family = state.font, state.font_family
  end
  if state.font_size then t.font_size = state.font_size end
  if state.line_spacing then t.line_spacing = state.line_spacing end
  return t
end

-- Change the text settings in crt_state.json; the values older versions
-- saved move over first, so they are not lost.
local function save_text(fn)
  local s = M.load_state()
  local legacy = options.load()
  if s.font == nil and s.font_family == nil and type(legacy.font) == 'string' and legacy.font ~= '' then
    s.font_family = legacy.font
  end
  if s.font_size == nil and type(legacy.font_size) == 'number' then s.font_size = legacy.font_size end
  if s.line_spacing == nil and type(legacy.line_height) == 'number' then
    s.line_spacing = legacy.line_height - 1
  end
  fn(s)
  options.forget(LEGACY_TEXT)
  M.save_state(s)
end

---------------------------------------------------------------------------
-- Applying a profile

--- Apply a cool-retro-term profile to a wezterm config.
--- opts.profile    : profile name (default "Default Amber")
--- opts.font       : font id from crt_data.fonts to override the profile font
--- opts.font_family: an installed font family instead
--- opts.font_size  : font size in points (pixel fonts take the nearest whole
---                   or half multiple of their design size)
--- opts.cell_height: without font_size: cell height in pixels for pixel
---                   fonts (default 24, a whole multiple is taken)
--- opts.line_spacing: extra space between lines (profile default)
--- opts.style_window = false keeps wezterm's default title bar colors
--- Any other key is copied into config.crt (effect overrides).
--- Values saved by the settings menu (crt_state.json) take precedence.
function M.apply(config, opts)
  opts = copy(opts)
  local state = M.load_state()
  if state.profile and state.profile ~= opts.profile then
    -- a different profile chosen in the menu replaces wezterm.lua's overrides
    opts = { cell_height = opts.cell_height, font_size = opts.font_size, style_window = opts.style_window }
  end
  M.base_opts = copy(opts) -- what wezterm.lua asks for (the menu shows it)
  for k, v in pairs(state) do opts[k] = v end
  wezterm.add_to_config_reload_watch_list(M.state_path)

  config.crt = config.crt or {}
  local name = opts.profile or config.crt.profile or 'Default Amber'
  local p = M.profiles[name]
  if not p then
    wezterm.log_warn('crt: unknown profile ' .. tostring(name) .. ', using Default Amber')
    name = 'Default Amber'
    p = M.profiles[name]
  end
  config.crt.profile = name
  for k, v in pairs(opts) do
    if not LOCAL_KEYS[k] then config.crt[k] = v end
  end

  -- effective values for colors (profile + overrides)
  local eff = copy(p)
  for k, v in pairs(config.crt) do eff[k] = v end

  local text = M.text_opts(state, M.base_opts)
  local f = M.font_for(p, text)
  config.font_dirs = config.font_dirs or {}
  table.insert(config.font_dirs, wezterm.executable_dir .. '/fonts')
  config.font = wezterm.font_with_fallback { f.family, 'Consolas' }

  local steps = M.size_steps(f)
  local size = M.size_index(f, text)
  config.font_size = steps[size]
  if f.scaled and size % 2 == 1 then
    -- a whole multiple of the design size: every font pixel stays sharp
    config.freetype_load_target = 'Mono'
    config.freetype_render_target = 'Mono'
  end

  if opts.style_window ~= false then
    M.style_window(config, eff, f)
  end

  config.line_height = 1.0 + (text.line_spacing or p.line_spacing or 0)
  local radius = lint(4.0, 120.0, eff.screen_radius or 0.2)
  local pad = math.floor(lint(1.0, 40.0, p.margin or 0.5) + (1.0 - math.sqrt(0.5)) * radius)
  config.window_padding = { left = pad, right = pad, top = pad, bottom = pad }
  config.default_cursor_style = p.blinking_cursor and 'BlinkingBlock' or 'SteadyBlock'
  return config
end

---------------------------------------------------------------------------
-- Settings menu
--
-- Navigation: arrow keys (or j/k) move, Enter picks, Esc goes one level up
-- (Esc in the main menu closes it), / searches.  After a value is picked the
-- menu returns to the list it came from, so several values can be tuned in a
-- row.  The main menu holds only the main categories.
--
-- Choices with a `slider` (value, min, max, step, names) show a bar that
-- Left/Right move while the menu stays open (Shift: finer); every change
-- goes to on_adjust(window, pane, id, value) and is applied at once.

local function selector(window, pane, title, choices, on_pick, on_back, on_adjust, fuzzy)
  local esc = on_back and 'Esc = back' or 'Esc = close'
  local keys = on_adjust and 'Up/Down = move, Left/Right = adjust, Enter = choose, '
    or 'Up/Down = move, Enter = choose, '
  window:perform_action(
    act.InputSelector {
      title = title,
      description = title .. '      ' .. keys .. esc .. ', / = search',
      alphabet = '', -- no number labels: arrow keys only
      choices = choices,
      fuzzy = fuzzy or false,
      action = wezterm.action_callback(function(w, p, id, _label, value)
        if value ~= nil then
          if on_adjust and id then on_adjust(w, p, id, value) end
        elseif id then
          on_pick(w, p, id)
        elseif on_back then
          on_back(w, p)
        end
      end),
    },
    pane
  )
end

local function fmt(v)
  if type(v) ~= 'number' then return tostring(v) end
  return string.format('%.2f', v)
end

-- Current settings.  The saved state is read directly so labels are right
-- even while the configuration is still being reloaded after a change.
local function current(window)
  local cfg = window:effective_config()
  local crt = cfg.crt or {}
  local state = M.load_state()
  local name = state.profile or crt.profile or 'Default Amber'
  if not M.profiles[name] then name = 'Default Amber' end
  local p = M.profiles[name]
  local eff = copy(p)
  for k, v in pairs(M.effect_defaults) do
    if eff[k] == nil then eff[k] = v end
  end
  if crt.profile == name then
    for k, v in pairs(crt) do
      if v ~= nil then eff[k] = v end
    end
  end
  for k, v in pairs(state) do eff[k] = v end
  eff.enabled = eff.enabled ~= false
  return name, p, eff, state
end

local menu, effects_menu -- forward declarations

local function profiles_menu(window, pane)
  local name = current(window)
  local choices = {}
  for _, n in ipairs(M.profile_names) do
    table.insert(choices, { id = n, label = (n == name and '> ' or '  ') .. n })
  end
  selector(window, pane, 'Settings > Profile', choices, function(w, p, id)
    -- a new profile starts from its own values (and its font); the text
    -- size and line spacing chosen in the menu stay
    save_text(function(s)
      local keep = { profile = id, font_size = s.font_size, line_spacing = s.line_spacing }
      for k in pairs(s) do s[k] = nil end
      for k, v in pairs(keep) do s[k] = v end
    end)
    menu(w, p)
  end, menu)
end

-- The font, its sizes and the line spacing as the menu shows them
local function text_now(window)
  local _, p, _, state = current(window)
  local t = M.text_opts(state, M.base_opts)
  local f = M.font_for(p, t)
  local steps, names = M.size_steps(f)
  return {
    p = p, t = t, f = f, steps = steps, names = names,
    size = M.size_index(f, t),
    spacing = t.line_spacing or p.line_spacing or 0,
  }
end

local function installed_fonts_menu(window, pane, back)
  local cur = text_now(window).t.font_family
  local choices = {}
  for _, fam in ipairs(options.system_fonts()) do
    table.insert(choices, { id = fam, label = (fam == cur and '> ' or '  ') .. fam })
  end
  if #choices == 0 then table.insert(choices, { id = '__none', label = '  (no fonts found)' }) end
  selector(window, pane, 'Settings > Font > Installed fonts', choices, function(w, p2, id)
    if id ~= '__none' then
      save_text(function(s)
        s.font = nil
        s.font_family = id
      end)
    end
    back(w, p2)
  end, back, nil, true)
end

local function fonts_menu(window, pane, back)
  back = back or menu
  local now = text_now(window)
  local cur = not now.t.font_family and (now.t.font or now.p.font) or nil
  local state = M.load_state()
  local own = state.font or state.font_family or now.t.font_family
  local choices = {
    { id = '__profile', label = (own and '  ' or '> ') .. 'profile default (' .. M.fonts[now.p.font].name .. ')' },
  }
  for _, id in ipairs(M.font_ids) do
    local f = M.fonts[id]
    table.insert(choices, { id = id, label = ((own and id == cur) and '> ' or '  ') .. f.name })
  end
  table.insert(choices, {
    id = '__installed',
    label = (now.t.font_family and '> ' or '  ') .. 'Installed fonts ...'
      .. (now.t.font_family and ('   ' .. now.t.font_family) or ''),
  })
  selector(window, pane, 'Settings > Font', choices, function(w, p2, id)
    if id == '__installed' then
      return installed_fonts_menu(w, p2, function(w2, p3) fonts_menu(w2, p3, back) end)
    end
    save_text(function(s)
      s.font = (id ~= '__profile') and id or nil
      s.font_family = nil
    end)
    back(w, p2)
  end, back)
end

local function size_menu(window, pane, back)
  back = back or menu
  local now = text_now(window)
  local own = now.t.font_size ~= nil
  local choices = { { id = '__default', label = (own and '  ' or '> ') .. 'default' } }
  for i, n in ipairs(now.names) do
    table.insert(choices, { id = tostring(i), label = ((own and i == now.size) and '> ' or '  ') .. n })
  end
  selector(window, pane, 'Settings > Font size', choices, function(w, p2, id)
    save_text(function(s) s.font_size = (id ~= '__default') and now.steps[tonumber(id)] or nil end)
    back(w, p2)
  end, back)
end

local SPACINGS = { 0, 0.05, 0.1, 0.15, 0.2, 0.25, 0.3, 0.4, 0.5 }

local function spacing_menu(window, pane, back)
  back = back or menu
  local now = text_now(window)
  local own = now.t.line_spacing ~= nil
  local choices = {
    { id = '__profile', label = (own and '  ' or '> ') .. string.format('profile default (%.2f)', now.p.line_spacing or 0) },
  }
  for _, v in ipairs(SPACINGS) do
    local mark = (own and math.abs(now.spacing - v) < 0.001) and '> ' or '  '
    table.insert(choices, { id = tostring(v), label = mark .. string.format('%.2f', v) })
  end
  selector(window, pane, 'Settings > Line spacing', choices, function(w, p2, id)
    save_text(function(s) s.line_spacing = (id ~= '__profile') and tonumber(id) or nil end)
    back(w, p2)
  end, back)
end

-- Keyboard shortcuts (shown in the menu; set up in M.setup)
M.shortcuts = {
  { 'F12, Ctrl+Shift+,', 'this menu' },
  { 'Ctrl+= / Ctrl+-', 'font size (the window keeps its size)' },
  { 'Ctrl+0', 'default font size' },
  { 'Ctrl+V', 'paste; an image goes to Claude Code (its Alt+V)' },
  { 'Ctrl+C', 'copy the selection; without one, Ctrl+C as usual' },
  { 'Shift+Enter', 'new line in Claude Code and PowerShell' },
  { 'F11, Alt+Enter', 'full screen' },
  { 'Ctrl+Shift+C / V', 'copy / paste' },
  { 'Ctrl+Shift+F', 'search the scrollback' },
  { 'Ctrl+Shift+T / W', 'new tab / close the tab' },
  { 'Ctrl+Shift+P', 'all commands' },
}

local function keys_menu(window, pane)
  local choices = {}
  for i, s in ipairs(M.shortcuts) do
    table.insert(choices, { id = tostring(i), label = string.format('  %-19s %s', s[1], s[2]) })
  end
  selector(window, pane, 'Settings > Shortcuts', choices, function(w, p2) menu(w, p2) end, menu)
end

local VALUES = { 0, 0.05, 0.1, 0.15, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0 }

local function value_menu(window, pane, key, label)
  local _, p, eff = current(window)
  local cur = eff[key]
  local choices = {
    { id = '__profile', label = string.format('  profile default (%s)', fmt(p[key] or M.effect_defaults[key])) },
  }
  for _, v in ipairs(VALUES) do
    local mark = (type(cur) == 'number' and math.abs(cur - v) < 0.001) and '> ' or '  '
    table.insert(choices, { id = tostring(v), label = mark .. fmt(v) })
  end
  selector(window, pane, 'Settings > CRT effects > ' .. label, choices, function(w, p2, id)
    update_state(function(s)
      s[key] = (id ~= '__profile') and tonumber(id) or nil
    end)
    effects_menu(w, p2)
  end, function(w, p2) effects_menu(w, p2) end)
end

local function rasterization_menu(window, pane)
  local _, _, eff = current(window)
  local choices = { { id = '__profile', label = '  profile default' } }
  for i = 0, 4 do
    table.insert(choices, {
      id = tostring(i),
      label = (eff.rasterization == i and '> ' or '  ') .. M.rasterization_names[i],
    })
  end
  selector(window, pane, 'Settings > CRT effects > Rasterization', choices, function(w, p, id)
    update_state(function(s) s.rasterization = (id ~= '__profile') and tonumber(id) or nil end)
    effects_menu(w, p)
  end, function(w, p) effects_menu(w, p) end)
end

local function phosphor_menu(window, pane)
  local _, p, eff = current(window)
  local choices = { { id = '__profile', label = '  profile default (' .. p.font_color .. ')' } }
  for _, ph in ipairs(M.phosphors) do
    local mark = (tostring(eff.font_color):lower() == ph[2]) and '> ' or '  '
    table.insert(choices, { id = ph[2], label = mark .. ph[1] .. '  ' .. ph[2] })
  end
  selector(window, pane, 'Settings > CRT effects > Phosphor color', choices, function(w, p2, id)
    update_state(function(s) s.font_color = (id ~= '__profile') and id or nil end)
    effects_menu(w, p2)
  end, function(w, p2) effects_menu(w, p2) end)
end

-- Swatches of the terminal palette.  The menu is drawn on the CRT screen,
-- so they show how the effects (chroma, saturation, contrast, phosphor ...)
-- change the colors while the sliders move.
local NORMAL_COLORS = { 'Black', 'Maroon', 'Green', 'Olive', 'Navy', 'Purple', 'Teal', 'Silver' }
local BRIGHT_COLORS = { 'Grey', 'Red', 'Lime', 'Yellow', 'Blue', 'Fuchsia', 'Aqua', 'White' }

-- One row (two rows of blocks would touch and merge): normal, then bright.
local function swatches()
  local items = { { Text = string.format('%-19s ', 'Colors') } }
  for i, names in ipairs { NORMAL_COLORS, BRIGHT_COLORS } do
    if i > 1 then table.insert(items, { Text = ' ' }) end
    for _, n in ipairs(names) do
      table.insert(items, { Foreground = { AnsiColor = n } })
      table.insert(items, { Text = '\u{2588}\u{2588} ' })
    end
  end
  table.insert(items, 'ResetAttributes')
  return wezterm.format(items)
end

-- The phosphor color as the screen shows it: the shader tints everything
-- with the phosphor, so a white square comes out exactly in that color.
local function phosphor_square()
  return wezterm.format { { Foreground = { Color = '#ffffff' } }, { Text = '\u{2588}\u{2588}' }, 'ResetAttributes' }
end

effects_menu = function(window, pane)
  local _, _, eff = current(window)
  local choices = {
    { id = '__toggle', label = string.format('%-19s %s', 'CRT effects', eff.enabled and 'ON   (turn off)' or 'OFF  (turn on)') },
    { id = '__colors', label = swatches() },
  }
  local function add_sliders(shape)
    for _, e in ipairs(M.effects) do
      if (e.shape or false) == shape then
        table.insert(choices, {
          id = e[1],
          label = e[2], -- the slider column follows the widest label
          slider = { value = tonumber(eff[e[1]]) or 0, min = 0, max = 1, step = 0.05 },
        })
      end
    end
  end
  add_sliders(false)
  local raster_names = {}
  for i = 0, 4 do raster_names[i + 1] = M.rasterization_names[i] end
  table.insert(choices, {
    id = '__raster',
    label = 'Rasterization',
    slider = { value = eff.rasterization or 0, min = 0, max = 4, step = 1, names = raster_names },
  })
  add_sliders(true) -- screen curvature, frame size, screen radius
  table.insert(choices, {
    id = '__phosphor',
    label = string.format('%-19s %s  ', 'Phosphor color', tostring(eff.font_color)) .. phosphor_square(),
  })
  table.insert(choices, {
    id = '__reset',
    label = string.format('%-19s %s', 'Reset CRT', 'profile, font, text size and effects back to wezterm.lua'),
  })
  selector(window, pane, 'Settings > CRT effects', choices, function(w, p, id)
    if id == '__toggle' then
      update_state(function(s) s.enabled = not eff.enabled end)
      return effects_menu(w, p)
    end
    if id == '__reset' then
      options.forget(LEGACY_TEXT)
      M.save_state {}
      return effects_menu(w, p)
    end
    if id == '__raster' then return rasterization_menu(w, p) end
    if id == '__colors' then return effects_menu(w, p) end -- swatches: nothing to pick
    if id == '__phosphor' then return phosphor_menu(w, p) end
    for _, e in ipairs(M.effects) do
      if e[1] == id then return value_menu(w, p, e[1], e[2]) end
    end
  end, menu, function(w, _p, id, value)
    -- A slider moved: shown at once in this window (no configuration reload
    -- per step, that takes too long), and saved; the file watcher reloads
    -- the configuration, for all windows, once the slider rests.
    local s = M.load_state()
    if id == '__raster' then
      s.rasterization = math.floor(value + 0.5)
    else
      s[id] = value
    end
    write_state(s)
    local preview = {}
    for k, v in pairs(s) do
      if not LOCAL_KEYS[k] then preview[k] = v end
    end
    w:set_crt_preview(preview)
  end)
end

menu = function(window, pane)
  local name, _, eff = current(window)
  local now = text_now(window)
  local choices = {
    { id = 'profile', label = 'Profile ........ ' .. name },
    { id = 'font', label = 'Font ........... ' .. now.f.name },
    -- slider labels are 15 wide: the bar starts where the values do
    { id = 'font_size', label = 'Font size .....',
      slider = { value = now.size, min = 1, max = #now.steps, step = 1, names = now.names } },
    { id = 'line_spacing', label = 'Line spacing ..',
      slider = { value = now.spacing, min = 0, max = 0.5, step = 0.05 } },
    { id = 'effects', label = 'CRT effects .... ' .. (eff.enabled and 'ON' or 'OFF') .. ', bloom, noise, curvature, frame ...' },
    { id = 'fullscreen', label = 'Full screen .... F11 / Alt+Enter' },
    { id = 'keys', label = 'Shortcuts ...... F12 menu, Ctrl+V paste, Shift+Enter new line, Ctrl+= / Ctrl+- size ...' },
    { id = 'settings', label = 'All settings ... every other wezterm setting (' .. options.count() .. '), by category' },
    { id = 'reset_settings', label = 'Reset settings . ' .. (function()
      local n = options.changed()
      return n > 0 and (n .. ' changed in All settings, back to wezterm.lua / defaults') or 'nothing changed in All settings'
    end)() },
    { id = 'update', label = 'Update ......... ' .. (update.version() or 'check for a new version') },
  }
  selector(window, pane, 'Settings', choices, function(w, p2, id)
    if id == 'profile' then
      profiles_menu(w, p2)
    elseif id == 'font' then
      fonts_menu(w, p2)
    elseif id == 'font_size' then
      size_menu(w, p2)
    elseif id == 'line_spacing' then
      spacing_menu(w, p2)
    elseif id == 'effects' then
      effects_menu(w, p2)
    elseif id == 'fullscreen' then
      w:toggle_fullscreen()
    elseif id == 'keys' then
      keys_menu(w, p2)
    elseif id == 'settings' then
      options.menu(w, p2, menu)
    elseif id == 'reset_settings' then
      options.reset_menu(w, p2, menu)
    elseif id == 'update' then
      update.menu(w, p2, menu)
    end
  end, nil, function(w, _p, id, value)
    -- a slider moved: saved and applied at once (the window keeps its size)
    if id == 'font_size' then
      local steps = text_now(w).steps
      local i = math.max(1, math.min(#steps, math.floor(value + 0.5)))
      save_text(function(s) s.font_size = steps[i] end)
    elseif id == 'line_spacing' then
      save_text(function(s) s.line_spacing = math.floor(value * 100 + 0.5) / 100 end)
    end
  end)
end

M.open_menu = function(window, pane) menu(window, pane) end

--- Ctrl+= / Ctrl+- / Ctrl+0: the next font size up (dir 1), down (-1) or
--- the default (0).  Saved like the menu's slider; the window keeps its size
--- and the number of rows and columns follows.
function M.step_font_size(window, pane, dir)
  if dir == 0 then
    window:perform_action(act.ResetFontSize, pane) -- wezterm's own zoom, if any
    return save_text(function(s) s.font_size = nil end)
  end
  local now = text_now(window)
  local i = math.max(1, math.min(#now.steps, now.size + dir))
  if i ~= now.size then save_text(function(s) s.font_size = now.steps[i] end) end
end

---------------------------------------------------------------------------
-- Keys for programs in the pane

-- Programs that take Shift+Enter as ESC CR (Meta+Enter: a new line, what
-- Claude Code's /terminal-setup binds) and paste images on their own key
-- (Claude Code on Windows: Alt+V).  Matched by the name of the program in
-- the pane or one it was started from; node / bun by their script path.
M.tui_apps = {
  claude = { image_paste = { key = 'v', mods = 'ALT' } },
}

local function exe_name(info)
  return ((info.name or ''):lower():gsub('%.exe$', ''))
end

local function app_of(info)
  local n = exe_name(info)
  if M.tui_apps[n] then return n end
  if n == 'node' or n == 'bun' then
    local args = table.concat(info.argv or {}, ' '):lower()
    for app in pairs(M.tui_apps) do
      if args:find(app, 1, true) then return app end
    end
  end
  return nil
end

--- The program the keys go to.  Windows has no foreground process group, so
--- the newest program on the pane's console counts, and from it up to the
--- shell the first one listed in M.tui_apps (a command Claude Code runs
--- still means Claude Code).  Returns the app (or nil) and the newest
--- program's name.
function M.pane_app(pane)
  local ok, info = pcall(function() return pane:get_foreground_process_info() end)
  if not ok or not info then return nil, nil end
  local newest = exe_name(info)
  local cur = info
  for _ = 1, 16 do
    local app = app_of(cur)
    if app then return app, newest end
    if not cur.ppid or cur.ppid == 0 then break end
    local ok2, parent = pcall(wezterm.procinfo.get_info_for_pid, cur.ppid)
    if not ok2 or not parent or exe_name(parent) == 'wezterm-gui' then break end
    cur = parent
  end
  return nil, newest
end

-- Shift+Enter: a new line.  Claude Code gets ESC CR; everything else the
-- key itself (PowerShell adds a line to the command).
local function new_line(window, pane)
  if M.pane_app(pane) then
    window:perform_action(act.SendString '\x1b\r', pane)
  else
    window:perform_action(act.SendKey { key = 'Enter', mods = 'SHIFT' }, pane)
  end
end

local SHELLS = { powershell = true, pwsh = true }

-- Ctrl+V: paste.  Text is pasted by the terminal, except at a PowerShell
-- prompt, which pastes on its own (multi-line text stays in the prompt
-- instead of running line by line).  Without text in the clipboard (an
-- image) the program reads it on its own key.
local function paste(window, pane)
  local app, newest = M.pane_app(pane)
  local ok, has_text = pcall(function() return window:clipboard_has_text() end)
  if not ok then has_text = true end
  if not has_text then
    local key = app and M.tui_apps[app].image_paste or { key = 'v', mods = 'CTRL' }
    return window:perform_action(act.SendKey(key), pane)
  end
  if not app and SHELLS[newest] then
    return window:perform_action(act.SendKey { key = 'v', mods = 'CTRL' }, pane)
  end
  window:perform_action(act.PasteFrom 'Clipboard', pane)
end

-- Ctrl+C: copy the selection; without one, Ctrl+C goes to the program.
local function copy(window, pane)
  local sel = window:get_selection_text_for_pane(pane)
  if sel and sel ~= '' then
    window:perform_action(act.CopyTo 'Clipboard', pane)
    window:perform_action(act.ClearSelection, pane)
  else
    window:perform_action(act.SendKey { key = 'c', mods = 'CTRL' }, pane)
  end
end

M._keys = { new_line = new_line, paste = paste, copy = copy } -- for tests

-- Add a key binding unless wezterm.lua already binds that key.
local function bind(config, key, mods, action)
  for _, k in ipairs(config.keys) do
    if k.key == key and (k.mods or 'NONE') == mods then return end
  end
  table.insert(config.keys, { key = key, mods = mods, action = action })
end

--- Register the settings menu (gear button, F12, Ctrl+Shift+,), the keys
--- above, and apply the options saved in the menu.
function M.setup(config)
  wezterm.on('settings-button-click', function(window, pane)
    M.open_menu(window, pane)
    return false -- handled, do not open the command palette
  end)
  wezterm.on('crt-open-settings', function(window, pane)
    M.open_menu(window, pane)
  end)
  config.keys = config.keys or {}
  local cb = wezterm.action_callback
  bind(config, 'F12', 'NONE', act.EmitEvent 'crt-open-settings')
  bind(config, ',', 'CTRL|SHIFT', act.EmitEvent 'crt-open-settings')
  bind(config, 'Enter', 'SHIFT', cb(new_line))
  -- letters by position too, so they work with any keyboard layout
  local paste_cb, copy_cb = cb(paste), cb(copy)
  for _, k in ipairs { 'v', 'phys:V' } do bind(config, k, 'CTRL', paste_cb) end
  for _, k in ipairs { 'c', 'phys:C' } do bind(config, k, 'CTRL', copy_cb) end
  local bigger = cb(function(w, p) M.step_font_size(w, p, 1) end)
  local smaller = cb(function(w, p) M.step_font_size(w, p, -1) end)
  local reset = cb(function(w, p) M.step_font_size(w, p, 0) end)
  for _, k in ipairs { '=', '+', 'Add' } do bind(config, k, 'CTRL', bigger) end
  for _, k in ipairs { '=', '+' } do bind(config, k, 'CTRL|SHIFT', bigger) end
  for _, k in ipairs { '-', 'Subtract' } do bind(config, k, 'CTRL', smaller) end
  for _, k in ipairs { '0', 'Numpad0' } do bind(config, k, 'CTRL', reset) end
  bind(config, '0', 'CTRL|SHIFT', reset)
  -- Ctrl+Shift+- (Ctrl+_) goes to the program: undo in Claude Code
  bind(config, '-', 'CTRL|SHIFT', act.DisableDefaultAssignment)
  -- a font size change keeps the window size (wezterm's default grows or
  -- shrinks the window with the text)
  if config.adjust_window_size_when_changing_font_size == nil then
    config.adjust_window_size_when_changing_font_size = false
  end
  -- Values changed in All settings (wezterm_options.json) win over what
  -- wezterm.lua set before this call.
  options.apply(config)
  return config
end

return M
