-- wezterm + cool-retro-term CRT look.
--
-- This file sits next to wezterm-gui.exe, so the build is portable.  Edit it
-- and save: wezterm reloads the configuration on the fly.
-- Every regular wezterm option works here: https://wezterm.org/config/files.html
local wezterm = require 'wezterm'
local crt = require 'crt' -- wezterm_modules/crt.lua: profiles + bundled fonts

local config = wezterm.config_builder()

-- The CRT effects are implemented in the OpenGL renderer.
config.front_end = 'OpenGL'

-- Shell
config.default_prog = { 'powershell.exe', '-NoLogo' }

-- This build is a fork; do not offer upstream wezterm updates.
config.check_for_updates = false

config.hide_tab_bar_if_only_one_tab = true
config.initial_cols = 110
config.initial_rows = 32

-- Pick any cool-retro-term profile:
--   Default Amber, Monochrome Green, Deep Blue, Commodore 64, Commodore PET,
--   Apple ][, Atari 400, IBM VGA 8x16, IBM 3278 Reborn, Neon Cyan,
--   Ghost Terminal, Plasma, Boring, E-Ink
-- and override any effect value (0..1 slider units, as in cool-retro-term):
--   bloom, burn_in, static_noise, jitter, glowing_line, flickering,
--   horizontal_sync, screen_curvature, rgb_shift, brightness, contrast,
--   chroma_color, saturation_color, ambient_light, frame_size,
--   frame_shininess, screen_radius, rasterization (0..4),
--   font_color, background_color, frame_color ("#rrggbb"),
--   pixel_size, bloom_quality, burn_in_quality, fps, enabled
crt.apply(config, {
  profile = 'Default Amber',
})

return config
