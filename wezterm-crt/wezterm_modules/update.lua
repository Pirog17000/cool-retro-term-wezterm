-- Settings > Update: install new builds published as GitHub releases.
--
-- Releases are built by .github/workflows/build-wezterm-crt.yml: the latest
-- wezterm (what the wezterm nightly builds use) with the CRT patches.  A tag
-- named crt-* starts such a build; "Build a new version" creates that tag.
--
-- GitHub access: the GitHub CLI (gh) when it is installed and logged in
-- (needed while the repository is private, and to start builds), otherwise
-- the public GitHub API with curl.
local wezterm = require 'wezterm'
local act = wezterm.action

local M = {}

-- Repository and branch the releases come from
M.repo = 'Pirog17000/cool-retro-term-wezterm'
M.branch = 'wezterm-host'
M.tag_prefix = 'crt-'

local dir = wezterm.executable_dir

local function read_json(path)
  local f = io.open(path, 'r')
  if not f then return nil end
  local text = f:read('*a')
  f:close()
  local ok, t = pcall(wezterm.json_parse, text)
  if ok and type(t) == 'table' then return t end
  return nil
end

--- Version information of this build (build_info.json next to the exe).
function M.info()
  return read_json(dir .. '/build_info.json') or {}
end

function M.version()
  return M.info().version
end

---------------------------------------------------------------------------
-- GitHub

local function run(args)
  local ok, success, stdout, stderr = pcall(wezterm.run_child_process, args)
  if not ok then return false, '', tostring(success) end
  return success, stdout or '', stderr or ''
end

local gh_checked, gh_ok
local function have_gh()
  if not gh_checked then
    gh_ok = run { 'gh', '--version' }
    gh_checked = true
  end
  return gh_ok
end

local function first_line(s)
  s = tostring(s or ''):gsub('^%s+', '')
  local line = s:match('^[^\r\n]*') or s
  if #line > 110 then line = line:sub(1, 107) .. '...' end
  return line
end

local function parse(out)
  local ok, t = pcall(wezterm.json_parse, out)
  if ok and type(t) == 'table' then return t end
  return nil, 'unexpected answer from GitHub'
end

-- GET https://api.github.com/<path>
local function api_get(path)
  if have_gh() then
    local ok, out, err = run { 'gh', 'api', path }
    if ok then return parse(out) end
    return nil, first_line(err ~= '' and err or out)
  end
  local ok, out, err = run {
    'curl.exe', '-sSfL', '-H', 'Accept: application/vnd.github+json',
    '-H', 'User-Agent: cool-retro-term-wezterm', 'https://api.github.com/' .. path,
  }
  if ok then return parse(out) end
  if (err or ''):match('404') then
    return nil, 'not found (a private repository needs the GitHub CLI: gh auth login)'
  end
  return nil, first_line(err ~= '' and err or 'request failed')
end

--- Latest published release: { tag_name, published_at, html_url, ... }
function M.latest()
  return api_get('repos/' .. M.repo .. '/releases/latest')
end

--- Start a GitHub build of the latest wezterm nightly: creates a crt-* tag
--- on the release branch.  Returns the tag or nil, error.
function M.start_build()
  if not have_gh() then
    return nil, 'needs the GitHub CLI (gh), logged in with write access to ' .. M.repo
  end
  local ref, err = api_get('repos/' .. M.repo .. '/git/ref/heads/' .. M.branch)
  if not ref then return nil, err end
  local sha = ref.object and ref.object.sha
  if not sha then return nil, 'branch ' .. M.branch .. ' not found' end
  local tag = M.tag_prefix .. os.date('!%Y%m%d-%H%M')
  local ok, out, e2 = run {
    'gh', 'api', '-X', 'POST', 'repos/' .. M.repo .. '/git/refs',
    '-f', 'ref=refs/tags/' .. tag, '-f', 'sha=' .. sha,
  }
  if not ok then return nil, first_line(e2 ~= '' and e2 or out) end
  return tag
end

--- Run update.ps1 for `tag`: it opens its own window, downloads and checks
--- the package, closes wezterm, installs and starts wezterm again.
function M.install(tag)
  local src = io.open(dir .. '/update.ps1', 'rb')
  if not src then return nil, 'update.ps1 is missing next to wezterm-gui.exe' end
  local body = src:read('*a')
  src:close()
  -- run a copy: the update replaces update.ps1 itself
  local tmp = (os.getenv('TEMP') or dir) .. '\\crt-update.ps1'
  local dst = io.open(tmp, 'wb')
  if not dst then return nil, 'cannot write ' .. tmp end
  dst:write(body)
  dst:close()
  wezterm.background_child_process {
    'powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', tmp,
    '-Dir', dir, '-Repo', M.repo, '-Tag', tag,
  }
  return true
end

---------------------------------------------------------------------------
-- Menu

local function dim(s)
  return wezterm.format { { Attribute = { Intensity = 'Half' } }, { Text = s } }
end

local function selector(window, pane, title, choices, on_pick, on_back)
  window:perform_action(
    act.InputSelector {
      title = title,
      description = title .. '      Up/Down = move, Enter = choose, Esc = back',
      alphabet = '',
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

local function short_date(s)
  local d, t = tostring(s or ''):match('^(%d+%-%d+%-%d+)[T ](%d+:%d+)')
  if d then return d .. ' ' .. t end
  return tostring(s or '')
end

--- Settings > Update.  `state` carries the result of the last action.
function M.menu(window, pane, back, state)
  state = state or {}
  local info = M.info()
  local current = info.version
  local choices = {}
  local function item(id, label) table.insert(choices, { id = id, label = label }) end
  local function note(text) item('__info', dim('  ' .. text)) end

  local latest = state.latest
  if latest and latest.tag_name and latest.tag_name ~= current then
    item('install', '  Install ' .. latest.tag_name .. '   (wezterm closes and starts again)')
  end
  item('check', '  Check for updates')
  item('build', '  Build a new version on GitHub (latest wezterm nightly)')
  item('releases', '  Open the releases page')
  item('actions', '  Open the GitHub build progress')
  item('__info', dim('  ' .. string.rep('-', 44)))
  if state.message then note(state.message) end
  if latest and latest.tag_name then
    note('Latest release: ' .. latest.tag_name .. '  (' .. short_date(latest.published_at) .. ')'
      .. (latest.tag_name == current and '  - installed' or ''))
  end
  note('Installed: ' .. (current or 'unknown (built without version information)'))
  if info.wezterm_commit then
    note('wezterm core: ' .. info.wezterm_commit:sub(1, 10) .. '  (' .. short_date(info.wezterm_date) .. ')')
  end
  if info.built then note('Built: ' .. short_date(info.built)) end
  note('Releases from github.com/' .. M.repo)

  local function again(w, p, s) M.menu(w, p, back, s) end
  selector(window, pane, 'Settings > Update', choices, function(w, p, id)
    if id == '__info' then return again(w, p, state) end
    if id == 'check' then
      local rel, err = M.latest()
      if not rel then return again(w, p, { message = 'Could not check: ' .. tostring(err) }) end
      local msg = (rel.tag_name == current) and 'You have the latest version.'
        or ('New version available: ' .. tostring(rel.tag_name))
      return again(w, p, { latest = rel, message = msg })
    elseif id == 'install' then
      local ok, err = M.install(latest.tag_name)
      if not ok then return again(w, p, { latest = latest, message = 'Could not start the update: ' .. err }) end
      return again(w, p, {
        latest = latest,
        message = 'The update window downloads ' .. latest.tag_name .. ', closes wezterm and starts it again.',
      })
    elseif id == 'build' then
      local tag, err = M.start_build()
      if not tag then return again(w, p, { message = 'Could not start a build: ' .. tostring(err) }) end
      return again(w, p, {
        message = 'Build ' .. tag .. ' started; the release appears in about an hour, then Check for updates.',
      })
    elseif id == 'releases' then
      wezterm.open_with('https://github.com/' .. M.repo .. '/releases')
      return again(w, p, state)
    elseif id == 'actions' then
      wezterm.open_with('https://github.com/' .. M.repo .. '/actions')
      return again(w, p, state)
    end
  end, back)
end

return M
