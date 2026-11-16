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
  { 'screen_curvature', 'Screen curvature' },
  { 'rgb_shift', 'RGB shift' },
  { 'brightness', 'Brightness' },
  { 'contrast', 'Contrast' },
  { 'chroma_color', 'Chroma color' },
  { 'saturation_color', 'Saturation' },
  { 'ambient_light', 'Ambient light' },
  { 'frame_size', 'Frame size' },
  { 'frame_shininess', 'Frame shininess' },
  { 'screen_radius', 'Screen radius' },
}

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
  profile = true, font = true, cell_height = true, font_size = true, style_window = true,
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

function M.save_state(t)
  local f, err = io.open(M.state_path, 'w')
  if not f then
    wezterm.log_error('crt: cannot write ' .. M.state_path .. ': ' .. tostring(err))
    return
  end
  f:write(wezterm.json_encode(t))
  f:close()
  wezterm.reload_configuration()
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
-- Applying a profile

--- Apply a cool-retro-term profile to a wezterm config.
--- opts.profile    : profile name (default "Default Amber")
--- opts.font       : font id from crt_data.fonts to override the profile font
--- opts.cell_height: target cell height in pixels for pixel fonts (default 24)
--- opts.font_size  : font size in points for vector fonts (default 13)
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

  local f = M.fonts[opts.font or p.font] or M.fonts.TERMINESS_SCALED
  config.font_dirs = config.font_dirs or {}
  table.insert(config.font_dirs, wezterm.executable_dir .. '/fonts')
  config.font = wezterm.font_with_fallback { f.family, 'Consolas' }

  if f.scaled then
    -- Pixel fonts look right at integer multiples of their design size.
    local target = opts.cell_height or 24
    local scale = math.max(1, math.floor(target / f.pixel_size + 0.5))
    config.font_size = f.pixel_size * scale * 0.75
    config.freetype_load_target = 'Mono'
    config.freetype_render_target = 'Mono'
  else
    config.font_size = opts.font_size or 13
  end

  if opts.style_window ~= false then
    M.style_window(config, eff, f)
  end

  config.line_height = 1.0 + (p.line_spacing or 0)
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

local function selector(window, pane, title, choices, on_pick, on_back)
  local esc = on_back and 'Esc = back' or 'Esc = close'
  window:perform_action(
    act.InputSelector {
      title = title,
      description = title .. '      Up/Down = move, Enter = choose, ' .. esc .. ', / = search',
      alphabet = '', -- no number labels: arrow keys only
      choices = choices,
      fuzzy = false,
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
    M.save_state { profile = id } -- a new profile starts from its own values
    menu(w, p)
  end, menu)
end

local function fonts_menu(window, pane)
  local _, p, _, state = current(window)
  local cur = state.font or p.font
  local choices = { { id = '__profile', label = '  (profile default)' } }
  for _, id in ipairs(M.font_ids) do
    local f = M.fonts[id]
    table.insert(choices, { id = id, label = (id == cur and '> ' or '  ') .. f.name })
  end
  selector(window, pane, 'Settings > Font', choices, function(w, p2, id)
    update_state(function(s) s.font = (id ~= '__profile') and id or nil end)
    menu(w, p2)
  end, menu)
end

local VALUES = { 0, 0.05, 0.1, 0.15, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0 }

local function value_menu(window, pane, key, label)
  local _, p, eff = current(window)
  local cur = eff[key]
  local choices = {
    { id = '__profile', label = string.format('  profile default (%s)', fmt(p[key])) },
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

effects_menu = function(window, pane)
  local _, _, eff = current(window)
  local choices = {
    { id = '__toggle', label = string.format('%-18s %s', 'CRT effects', eff.enabled and 'ON   (turn off)' or 'OFF  (turn on)') },
  }
  for _, e in ipairs(M.effects) do
    table.insert(choices, { id = e[1], label = string.format('%-18s %s', e[2], fmt(eff[e[1]])) })
  end
  table.insert(choices, {
    id = '__raster',
    label = string.format('%-18s %s', 'Rasterization', M.rasterization_names[eff.rasterization or 0]),
  })
  table.insert(choices, {
    id = '__phosphor',
    label = string.format('%-18s %s', 'Phosphor color', tostring(eff.font_color)),
  })
  table.insert(choices, {
    id = '__reset',
    label = string.format('%-18s %s', 'Reset CRT', 'profile, font and effects back to wezterm.lua'),
  })
  selector(window, pane, 'Settings > CRT effects', choices, function(w, p, id)
    if id == '__toggle' then
      update_state(function(s) s.enabled = not eff.enabled end)
      return effects_menu(w, p)
    end
    if id == '__reset' then
      M.save_state {}
      return effects_menu(w, p)
    end
    if id == '__raster' then return rasterization_menu(w, p) end
    if id == '__phosphor' then return phosphor_menu(w, p) end
    for _, e in ipairs(M.effects) do
      if e[1] == id then return value_menu(w, p, e[1], e[2]) end
    end
  end, menu)
end

menu = function(window, pane)
  local name, p, eff, state = current(window)
  local font = M.fonts[state.font or p.font]
  local choices = {
    { id = 'profile', label = 'Profile ........ ' .. name },
    { id = 'font', label = 'Font ........... ' .. (font and font.name or '?') },
    { id = 'effects', label = 'CRT effects .... ' .. (eff.enabled and 'ON' or 'OFF') .. ', bloom, noise, curvature, frame ...' },
    { id = 'fullscreen', label = 'Full screen .... F11 / Alt+Enter' },
    { id = 'settings', label = 'Settings ....... all wezterm settings (' .. options.count() .. ') by category' },
    { id = 'reset_settings', label = 'Reset settings . ' .. (function()
      local n = options.changed()
      return n > 0 and (n .. ' changed, back to wezterm.lua / defaults') or 'nothing changed'
    end)() },
  }
  selector(window, pane, 'Settings', choices, function(w, p2, id)
    if id == 'profile' then
      profiles_menu(w, p2)
    elseif id == 'font' then
      fonts_menu(w, p2)
    elseif id == 'effects' then
      effects_menu(w, p2)
    elseif id == 'fullscreen' then
      w:toggle_fullscreen()
    elseif id == 'settings' then
      options.menu(w, p2, menu)
    elseif id == 'reset_settings' then
      options.reset_menu(w, p2, menu)
    end
  end, nil)
end

M.open_menu = function(window, pane) menu(window, pane) end

--- Register the settings menu (gear button in the title bar and
--- Ctrl+Shift+, as a keyboard shortcut) and apply the options saved in it.
function M.setup(config)
  wezterm.on('settings-button-click', function(window, pane)
    M.open_menu(window, pane)
    return false -- handled, do not open the command palette
  end)
  wezterm.on('crt-open-settings', function(window, pane)
    M.open_menu(window, pane)
  end)
  config.keys = config.keys or {}
  table.insert(config.keys, { key = ',', mods = 'CTRL|SHIFT', action = act.EmitEvent 'crt-open-settings' })
  -- Values changed in the Settings submenu (wezterm_options.json) win over
  -- what wezterm.lua set before this call.
  options.apply(config)
  return config
end

return M
