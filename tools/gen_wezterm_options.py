#!/usr/bin/env python3
"""Generate wezterm-crt/wezterm_modules/options_catalog.lua.

The catalog lists every field of wezterm's Config struct with its type, the
allowed values of enums and flag sets, the default from the documentation, a
category and a description.  The settings menu (options.lua) uses it to edit
any option without touching Lua.

Sources (all from the pinned wezterm submodule):
  config/src/*.rs, wezterm-input-types, bidi, wezterm-escape-parser
                               struct fields, enums, bitflags, doc comments
  docs/config/lua/config/*.md  defaults and descriptions

Run from the repository root:  python tools/gen_wezterm_options.py
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W = os.path.join(ROOT, 'third_party', 'wezterm')
OUT = os.path.join(ROOT, 'wezterm-crt', 'wezterm_modules', 'options_catalog.lua')
DOCS = os.path.join(W, 'docs', 'config', 'lua', 'config')
SRC_DIRS = ['config/src', 'wezterm-input-types/src', 'bidi/src', 'wezterm-escape-parser/src']

# Fields that are not user options here
SKIP = {'resolved_palette', 'crt'}

# Structs whose fields are offered one by one (path "parent.field")
EXPAND = {'WindowPadding', 'HsbTransform', 'WindowContentAlignment', 'WindowFrameConfig',
          'VisualBell', 'Palette', 'TabBarColors', 'TabBarColor'}

CATEGORIES = [
    ('Window', [
        'initial_cols', 'initial_rows', 'window_padding.*', 'window_content_alignment.*',
        'adjust_window_size_when_changing_font_size', 'use_resize_increments',
        'window_close_confirmation', 'quit_when_all_windows_are_closed', 'win32_system_backdrop',
        'win32_acrylic_accent_color', 'dpi', 'dpi_by_screen']),
    ('Title bar and window frame', [
        'window_decorations', 'integrated_title_buttons', 'integrated_title_button_alignment',
        'integrated_title_button_style', 'integrated_title_button_color', 'window_frame.*']),
    ('Tab bar', [
        'enable_tab_bar', 'use_fancy_tab_bar', 'tab_bar_at_bottom', 'hide_tab_bar_if_only_one_tab',
        'show_tabs_in_tab_bar', 'show_tab_index_in_tab_bar', 'show_new_tab_button_in_tab_bar',
        'show_close_tab_button_in_tabs', 'tab_max_width', 'tab_and_split_indices_are_zero_based',
        'mouse_wheel_scrolls_tabs', 'switch_to_last_active_tab_when_closing_tab',
        'prefer_to_spawn_tabs', 'tab_bar_style', 'status_update_interval']),
    ('Fonts and text rendering', [
        'font', 'font_size', 'line_height', 'cell_width', 'font_dirs', 'font_rules', 'font_locator',
        'font_rasterizer', 'font_colr_rasterizer', 'font_shaper', 'harfbuzz_features',
        'freetype_load_target', 'freetype_render_target', 'freetype_load_flags',
        'freetype_interpreter_version', 'freetype_pcf_long_family_names', 'display_pixel_geometry',
        'allow_square_glyphs_to_overflow_width', 'custom_block_glyphs',
        'anti_alias_custom_block_glyphs', 'warn_about_missing_glyphs',
        'sort_fallback_fonts_by_coverage', 'search_font_dirs_for_fallback',
        'use_cap_height_to_scale_fallback_fonts', 'ignore_svg_fonts', 'underline_thickness',
        'underline_position', 'strikethrough_position', 'experimental_pixel_positioning',
        'use_box_model_render']),
    ('Colors', [
        'color_scheme', 'color_scheme_dirs', 'color_schemes', 'colors.*', 'bold_brightens_ansi_colors',
        'text_min_contrast_ratio', 'foreground_text_hsb.*']),
    ('Tab bar colors', ['colors.tab_bar.*']),
    ('Background and transparency', [
        'window_background_opacity', 'text_background_opacity', 'window_background_image',
        'window_background_image_hsb.*', 'window_background_gradient', 'background']),
    ('Cursor and blinking', [
        'default_cursor_style', 'cursor_blink_rate', 'cursor_blink_ease_in', 'cursor_blink_ease_out',
        'cursor_thickness', 'force_reverse_video_cursor', 'reverse_video_cursor_min_contrast',
        'animation_fps', 'text_blink_rate', 'text_blink_ease_in', 'text_blink_ease_out',
        'text_blink_rate_rapid', 'text_blink_rapid_ease_in', 'text_blink_rapid_ease_out']),
    ('Scrollback and scroll bar', [
        'scrollback_lines', 'enable_scroll_bar', 'min_scroll_bar_height', 'scroll_to_bottom_on_input',
        'alternate_buffer_wheel_scroll_speed']),
    ('Keyboard', [
        'keys', 'key_tables', 'leader', 'disable_default_key_bindings', 'key_map_preference',
        'use_dead_keys', 'send_composed_key_when_left_alt_is_pressed',
        'send_composed_key_when_right_alt_is_pressed', 'treat_left_ctrlalt_as_altgr',
        'swap_backspace_and_delete', 'enable_csi_u_key_encoding', 'enable_kitty_keyboard',
        'allow_win32_input_mode', 'use_ime', 'ime_preedit_rendering', 'debug_key_events',
        'ui_key_cap_rendering']),
    ('Mouse, selection and clipboard', [
        'mouse_bindings', 'disable_default_mouse_bindings', 'bypass_mouse_reporting_modifiers',
        'hide_mouse_cursor_when_typing', 'swallow_mouse_click_on_window_focus',
        'selection_word_boundary', 'hyperlink_rules', 'quote_dropped_files',
        'canonicalize_pasted_newlines']),
    ('Panes', [
        'inactive_pane_hsb.*', 'unzoom_on_switch_pane', 'pane_focus_follows_mouse',
        'swallow_mouse_click_on_pane_focus']),
    ('Quick select, launcher and palettes', [
        'quick_select_alphabet', 'quick_select_patterns', 'disable_default_quick_select_patterns',
        'quick_select_remove_styling', 'launcher_alphabet', 'launch_menu', 'command_palette_*',
        'char_select_*', 'pane_select_*', 'palette_max_key_assigments_for_action']),
    ('Shell and programs', [
        'default_prog', 'default_cwd', 'default_gui_startup_args', 'set_environment_variables', 'term',
        'exit_behavior', 'exit_behavior_messaging', 'clean_exit_codes',
        'skip_close_confirmation_for_processes_named', 'detect_password_input', 'default_domain',
        'default_workspace']),
    ('Terminal emulation and Unicode', [
        'unicode_version', 'treat_east_asian_ambiguous_width_as_wide', 'cell_widths',
        'normalize_output_to_unicode_nfc', 'bidi_enabled', 'bidi_direction', 'enable_kitty_graphics',
        'enable_title_reporting', 'enq_answerback', 'enable_checksum_rectangular_area',
        'log_unknown_escape_sequences', 'allow_download_protocols', 'notification_handling']),
    ('Bell', ['audible_bell', 'visual_bell.*']),
    ('Multiplexer and domains', [
        'unix_domains', 'ssh_domains', 'ssh_backend', 'tls_servers', 'tls_clients', 'wsl_domains',
        'exec_domains', 'serial_ports', 'default_mux_server_domain', 'mux_enable_ssh_agent',
        'default_ssh_auth_sock', 'mux_env_remove', 'mux_output_parser_buffer_size',
        'mux_output_parser_coalesce_delay_ms', 'ratelimit_mux_line_prefetches_per_second',
        'daemon_options']),
    ('GPU and performance', [
        'front_end', 'webgpu_power_preference', 'webgpu_force_fallback_adapter',
        'webgpu_preferred_adapter', 'prefer_egl', 'max_fps', 'shape_cache_size',
        'line_state_cache_size', 'line_quad_cache_size', 'line_to_ele_shape_cache_size',
        'glyph_cache_image_cache_size', 'periodic_stat_logging']),
    ('Updates and config reload', [
        'automatically_reload_config', 'check_for_updates', 'check_for_updates_interval_seconds',
        'show_update_window']),
    ('macOS / Linux only', [
        'macos_window_background_blur', 'kde_window_background_blur', 'wayland_window_background_blur',
        'native_macos_fullscreen_mode', 'macos_fullscreen_extend_behind_notch',
        'macos_forward_to_ime_modifier_mask', 'enable_wayland', 'enable_zwlr_output_manager',
        'xim_im_name', 'xcursor_theme', 'xcursor_size', 'tiling_desktop_environments', 'ulimit_nofile',
        'ulimit_nproc']),
]

# When a change takes effect, if not right away
APPLIES = {}
for k in ['initial_cols', 'initial_rows', 'default_prog', 'default_cwd', 'set_environment_variables',
          'term', 'default_domain', 'default_workspace', 'scrollback_lines']:
    APPLIES[k] = 'new'
for k in ['front_end', 'webgpu_power_preference', 'webgpu_force_fallback_adapter',
          'webgpu_preferred_adapter', 'prefer_egl', 'enable_wayland', 'default_gui_startup_args',
          'daemon_options', 'ulimit_nofile', 'ulimit_nproc', 'unix_domains', 'ssh_domains',
          'tls_servers', 'tls_clients', 'wsl_domains', 'exec_domains', 'serial_ports',
          'mux_enable_ssh_agent', 'default_mux_server_domain', 'ssh_backend']:
    APPLIES[k] = 'restart'

# Lists that are added to what wezterm.lua (and the CRT module) already set
APPEND = {'font_dirs', 'color_scheme_dirs'}

# Notes shown with options that interact with the CRT setup
NOTES = {
    'font': 'Overrides the CRT profile font (Settings > Font).',
    'font_size': 'Overrides the size the CRT module picks for the font.',
    'line_height': 'Overrides the CRT profile line spacing.',
    'window_padding.left': 'Overrides the padding the CRT module derives from the screen radius.',
    'window_padding.right': 'Overrides the padding the CRT module derives from the screen radius.',
    'window_padding.top': 'Overrides the padding the CRT module derives from the screen radius.',
    'window_padding.bottom': 'Overrides the padding the CRT module derives from the screen radius.',
    'front_end': 'CRT effects are drawn by the OpenGL front end only.',
    'default_cursor_style': 'Overrides the cursor style of the CRT profile.',
    'freetype_load_target': 'The CRT module uses Mono for pixel fonts.',
    'freetype_render_target': 'The CRT module uses Mono for pixel fonts.',
}

# Descriptions for options that have no page of their own in the documentation
DESCRIPTIONS = {
    'color_scheme_dirs': 'Directories searched for color scheme files (TOML), in addition to the built-in schemes.',
    'dpi_by_screen': 'DPI to assume per screen, keyed by the screen name; overrides the DPI the system reports.',
    'pane_select_font_size': 'Font size of the pane selection labels (PaneSelect).',
    'pane_select_fg_color': 'Text color of the pane selection labels (PaneSelect).',
    'pane_select_bg_color': 'Background color of the pane selection labels (PaneSelect).',
    'enable_kitty_graphics': 'Allow programs to show images with the kitty graphics protocol.',
    'font_colr_rasterizer': 'Rasterizer used for color (COLR) emoji fonts.',
    'exec_domains': 'Exec domains: run each new pane through a Lua callback that can rewrite the command.',
    'keys': 'Key bindings: a list of { key, mods, action } entries.',
    'disable_default_key_bindings': 'Turn off all of the default key bindings; only the keys you define stay.',
    'leader': 'Leader key: a modal key combination that enables LEADER bindings for a short time.',
    'mouse_bindings': 'Mouse bindings: a list of { event, mods, action } entries.',
    'send_composed_key_when_left_alt_is_pressed': 'With left Alt held, send the character the keyboard layout composes instead of Alt+key.',
    'send_composed_key_when_right_alt_is_pressed': 'With right Alt (AltGr) held, send the character the keyboard layout composes instead of Alt+key.',
    'enable_zwlr_output_manager': 'Wayland: use the zwlr output manager protocol to get screen names and scaling.',
    'text_background_opacity': 'Opacity of the background color of text cells (0..1), separate from window_background_opacity.',
    'use_dead_keys': 'Dead keys produce diacritics (e.g. ^ then e gives a circumflex e); off makes them regular keys.',
    'use_box_model_render': 'Render with the box model (experimental layout engine).',
    'check_for_updates_interval_seconds': 'How often to check for a new wezterm release, in seconds.',
    'enq_answerback': 'Text sent back to a program that sends the ENQ control character.',
    'experimental_pixel_positioning': 'Position glyphs at fractional pixel positions (experimental).',
    'ignore_svg_fonts': 'Skip fonts that contain SVG glyphs.',
    'bidi_enabled': 'Enable bidirectional text (right-to-left scripts such as Arabic and Hebrew).',
    'bidi_direction': 'Paragraph direction used for bidirectional text.',
    'sort_fallback_fonts_by_coverage': 'Order fallback fonts by how many of the needed glyphs they contain.',
    'search_font_dirs_for_fallback': 'Search font_dirs as well when looking for fallback fonts.',
    'shape_cache_size': 'Size of the text shaping cache (entries).',
    'line_state_cache_size': 'Size of the line state cache (entries).',
    'line_quad_cache_size': 'Size of the line geometry cache (entries).',
    'line_to_ele_shape_cache_size': 'Size of the line to element shape cache (entries).',
    'glyph_cache_image_cache_size': 'Size of the glyph image cache (entries).',
    'allow_download_protocols': 'Allow programs to send files to wezterm for download through escape sequences.',
    'xcursor_theme': 'X11/Wayland: mouse cursor theme.',
    'xcursor_size': 'X11/Wayland: mouse cursor size.',
    'palette_max_key_assigments_for_action': 'How many key bindings the command palette shows next to an action.',
}

# Flag names wezterm accepts when parsing these types from a string
FLAG_NAMES = {'Modifiers': ['SHIFT', 'ALT', 'CTRL', 'SUPER', 'LEADER']}

# Enum values that this (Windows) build rejects
ENUM_EXCLUDE = {'IntegratedTitleButtonStyle': {'MacOsNative'}}

INT_TYPES = {'u8', 'u16', 'u32', 'u64', 'usize', 'i64', 'i32', 'isize'}


def read(path):
    with open(path, encoding='utf-8') as f:
        return f.read()


def block_after(text, start):
    """Text between the brace that opens at/after `start` and its match."""
    i = text.index('{', start)
    depth = 0
    for j in range(i, len(text)):
        c = text[j]
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                return text[i + 1:j]
    raise ValueError('unbalanced')


def strip_line_comment(line):
    return re.sub(r'//.*$', '', line)


enums, flags, structs = {}, {}, {}


def parse_sources():
    for d in SRC_DIRS:
        base = os.path.join(W, d)
        for dirpath, _dirs, files in os.walk(base):
            for fn in files:
                if not fn.endswith('.rs'):
                    continue
                text = read(os.path.join(dirpath, fn))
                for m in re.finditer(r'pub enum (\w+)\s*(?:<[^>]*>)?\s*\{', text):
                    name = m.group(1)
                    if name in enums:
                        continue
                    body = block_after(text, m.start())
                    variants = []
                    depth = 0
                    for raw in body.split('\n'):
                        line = strip_line_comment(raw).strip()
                        if depth == 0 and line and not line.startswith('#'):
                            vm = re.match(r'^([A-Z]\w*)\s*(=\s*[^,]+)?\s*,?$', line)
                            if vm:
                                variants.append(vm.group(1))
                        depth += line.count('{') + line.count('(') - line.count('}') - line.count(')')
                    enums[name] = variants
                for m in re.finditer(r'pub struct (\w+)\s*:\s*u\d+\s*\{', text):
                    name = m.group(1)
                    body = block_after(text, m.start())
                    flags.setdefault(name, re.findall(r'const (\w+)\s*=', body))
                for m in re.finditer(r'pub struct (\w+)\s*\{', text):
                    name = m.group(1)
                    if name in structs:
                        continue
                    body = block_after(text, m.start())
                    structs[name] = parse_fields(body)


def parse_fields(body):
    fields = []
    doc = []
    attrs = []
    depth = 0
    for raw in body.split('\n'):
        line = raw.strip()
        if depth == 0:
            if line.startswith('///'):
                doc.append(line[3:].strip())
                continue
            if line.startswith('#['):
                attrs.append(line)
            fm = re.match(r'^pub (\w+)\s*:\s*(.+?),?$', line)
            if fm:
                fields.append({'name': fm.group(1), 'type': fm.group(2).strip().rstrip(','),
                               'doc': ' '.join(doc), 'attrs': ' '.join(attrs)})
                doc, attrs = [], []
                continue
            if line and not line.startswith('#') and not line.startswith('//') and not line.startswith(')'):
                if not line.startswith('validate') and not line.startswith('default'):
                    doc, attrs = [], []
        depth += line.count('(') - line.count(')')
    return fields


def last_seg(t):
    return t.split('::')[-1].strip()


def classify(t):
    """Return a type spec dict for a Rust type."""
    t = t.strip()
    spec = {}
    m = re.match(r'^Option<(.+)>$', t)
    if m:
        inner = classify(m.group(1))
        inner['nullable'] = True
        return inner
    m = re.match(r'^Vec<(.+)>$', t)
    if m:
        item = classify(m.group(1))
        if item['t'] in ('string', 'path', 'int', 'enum'):
            return {'t': 'list', 'item': item}
        return {'t': 'complex'}
    m = re.match(r'^HashMap<String,\s*(.+)>$', t)
    if m:
        item = classify(m.group(1))
        if item['t'] in ('string', 'float', 'int'):
            return {'t': 'map', 'item': item}
        return {'t': 'complex'}
    name = last_seg(t)
    if name == 'bool':
        return {'t': 'bool'}
    if name in ('f32', 'f64'):
        return {'t': 'float'}
    if name in INT_TYPES:
        return {'t': 'int'}
    if name == 'String':
        return {'t': 'string'}
    if name == 'PathBuf':
        return {'t': 'path'}
    if name == 'RgbaColor':
        return {'t': 'color'}
    if name == 'ColorSpec':
        return {'t': 'colorspec'}
    if name == 'Dimension':
        return {'t': 'dimension'}
    if name == 'TextStyle':
        return {'t': 'font'}
    if name == 'GpuInfo':
        return {'t': 'gpu'}
    if name == 'IntegratedTitleButtonColor':
        return {'t': 'color', 'extra': ['auto']}
    if name == 'EasingFunction':
        return {'t': 'enum', 'values': enums[name]}
    if name in flags:
        vals = FLAG_NAMES.get(name) or [v for v in flags[name] if v not in ('NONE', 'DEFAULT')]
        empty = 'NONE' if 'NONE' in flags[name] else ('DEFAULT' if 'DEFAULT' in flags[name] else '')
        return {'t': 'flags', 'values': vals, 'empty': empty}
    if name in EXPAND:
        return {'t': 'struct', 'struct': name}
    if name in enums and enums[name]:
        return {'t': 'enum', 'values': [v for v in enums[name] if v not in ENUM_EXCLUDE.get(name, ())]}
    return {'t': 'complex'}


def clean_md(s):
    s = re.sub(r'\{\{.*?\}\}', '', s)
    s = re.sub(r'!\[[^\]]*\]\([^)]*\)', '', s)
    s = re.sub(r'\[([^\]]+)\]\([^)]*\)', r'\1', s)
    s = s.replace('`', '').replace('**', '').replace('*', '')
    s = re.sub(r'<[^>]+>', '', s)
    return re.sub(r'\s+', ' ', s).strip()


def read_doc(name):
    path = os.path.join(DOCS, name + '.md')
    if not os.path.exists(path):
        return None, None
    text = read(path)
    text = re.sub(r'^---\n.*?\n---\n', '', text, flags=re.S)
    default = None
    hm = re.search(r'^#\s+`([^`]+)`', text, flags=re.M)
    if hm:
        dm = re.match(r'^\s*\w+\s*=\s*(.+)$', hm.group(1))
        if dm:
            default = dm.group(1).strip()
    paras = []
    cur = []
    in_code = False
    for line in text.split('\n'):
        st = line.strip()
        if st.startswith('```'):
            in_code = not in_code
            if cur:
                paras.append(' '.join(cur))
                cur = []
            continue
        if in_code or st.startswith('#') or st.startswith('!!!') or st.startswith('|'):
            if cur:
                paras.append(' '.join(cur))
                cur = []
            continue
        if not st:
            if cur:
                paras.append(' '.join(cur))
                cur = []
            continue
        cur.append(st)
    if cur:
        paras.append(' '.join(cur))
    paras = [clean_md(p) for p in paras]
    paras = [p for p in paras if p and not p.startswith('Since:') and len(p) > 3]
    text = ' '.join(paras[:3])
    return default, text


def lua_str(s):
    s = s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', ' ')
    return '"' + s + '"'


def lua_val(v):
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return lua_str(v)
    if isinstance(v, list):
        return '{ ' + ', '.join(lua_val(x) for x in v) + ' }'
    if isinstance(v, dict):
        parts = []
        for k in sorted(v):
            parts.append(f'{k} = {lua_val(v[k])}')
        return '{ ' + ', '.join(parts) + ' }'
    raise TypeError(v)


def main():
    parse_sources()
    cfg_text = read(os.path.join(W, 'config', 'src', 'config.rs'))
    cfg = parse_fields(block_after(cfg_text, cfg_text.index('pub struct Config {')))
    names = [f['name'] for f in cfg]
    assert 'font_size' in names and 'ulimit_nproc' in names, 'Config parse failed'

    options = {}

    def add(path, f, spec, parent_doc=None):
        if spec['t'] == 'struct':
            for sf in structs[spec['struct']]:
                sspec = classify(sf['type'])
                add(path + '.' + sf['name'], sf, sspec, parent_doc or f)
            return
        top = path.split('.')[0]
        default, doc = (read_doc(path) if '.' not in path else (None, None))
        if not doc:
            doc = DESCRIPTIONS.get(path) or (clean_md(f['doc']) if f['doc'] else '')
        if not doc and parent_doc is not None:
            pd = read_doc(top)[1] or clean_md(parent_doc.get('doc', ''))
            first = re.split(r'(?<=[.!?])\s', pd, maxsplit=1)[0] if pd else ''
            parent = path.rsplit('.', 1)[0]
            field = path.split('.')[-1].replace('_', ' ')
            doc = f'{field[:1].upper() + field[1:]}: field of {parent}. {first}'.strip()
        e = dict(spec)
        e['doc'] = doc or ''
        if default:
            e['default'] = default
        if path in APPLIES or top in APPLIES:
            e['applies'] = APPLIES.get(path, APPLIES.get(top))
        if path in APPEND:
            e['append'] = True
        if path in NOTES:
            e['note'] = NOTES[path]
        if '.' not in path and os.path.exists(os.path.join(DOCS, path + '.md')):
            e['url'] = 'https://wezterm.org/config/lua/config/' + path + '.html'
        elif '.' in path and os.path.exists(os.path.join(DOCS, top + '.md')):
            e['url'] = 'https://wezterm.org/config/lua/config/' + top + '.html'
        options[path] = e

    for f in cfg:
        if f['name'] in SKIP:
            continue
        add(f['name'], f, classify(f['type']))

    # Assign categories
    assigned = {}
    cats = []
    for cname, pats in CATEGORIES:
        keys = []
        for pat in pats:
            if pat.endswith('.*'):
                prefix = pat[:-1]
                ms = [k for k in options if k.startswith(prefix)]
            elif pat.endswith('_*'):
                prefix = pat[:-1]
                ms = [k for k in options if k.startswith(prefix) and '.' not in k]
            else:
                ms = [pat] if pat in options else []
                if not ms:
                    sys.exit(f'unknown option in categories: {pat}')
            for k in ms:
                if k in assigned:
                    continue  # first (more specific listed later wins below)
                keys.append(k)
                assigned[k] = cname
        cats.append([cname, keys])
    # "colors.*" grabs colors.tab_bar.* first; move those to their own category
    by_name = {c[0]: c for c in cats}
    tb = [k for k in by_name['Colors'][1] if k.startswith('colors.tab_bar.')]
    by_name['Colors'][1] = [k for k in by_name['Colors'][1] if not k.startswith('colors.tab_bar.')]
    by_name['Tab bar colors'][1] = tb + by_name['Tab bar colors'][1]
    missing = [k for k in options if k not in assigned]
    if missing:
        sys.exit('options without a category: ' + ', '.join(missing))

    top_level = [f['name'] for f in cfg if f['name'] not in SKIP]
    n_edit = sum(1 for k, e in options.items() if e['t'] != 'complex')
    n_complex = sum(1 for e in options.values() if e['t'] == 'complex')

    out = []
    out.append('-- Generated by tools/gen_wezterm_options.py from the wezterm sources and')
    out.append('-- documentation.  Do not edit by hand.')
    out.append('--')
    out.append(f'-- {len(top_level)} wezterm options; structured ones (window_padding, window_frame,')
    out.append(f'-- colors, ...) are split into fields: {len(options)} entries, {n_edit} editable in the')
    out.append(f'-- menu, {n_complex} complex ones (key bindings, domains, ...) live in wezterm.lua.')
    out.append('local M = {}')
    out.append(f'M.top_level_count = {len(top_level)}')
    out.append('M.categories = {')
    for cname, keys in cats:
        out.append(f'  {{ name = {lua_str(cname)}, keys = {{')
        for k in keys:
            out.append(f'    {lua_str(k)},')
        out.append('  } },')
    out.append('}')
    out.append('M.options = {')
    for cname, keys in cats:
        for k in keys:
            out.append(f'  [{lua_str(k)}] = {lua_val(options[k])},')
    out.append('}')
    out.append('return M')
    with open(OUT, 'w', encoding='utf-8', newline='\n') as fo:
        fo.write('\n'.join(out) + '\n')

    from collections import Counter
    print(f'{len(top_level)} top-level options, {len(options)} entries, {n_edit} editable, {n_complex} complex')
    print(Counter(e['t'] for e in options.values()))
    for cname, keys in cats:
        print(f'  {cname}: {len(keys)}')
    print('complex:', ', '.join(k for k, e in options.items() if e['t'] == 'complex'))
    print('no doc:', ', '.join(k for k, e in options.items() if not e['doc']))


if __name__ == '__main__':
    main()
