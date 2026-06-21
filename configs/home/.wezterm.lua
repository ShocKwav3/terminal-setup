-- =====================================================================
--  WezTerm config
--  Sections:
--    1. Setup
--    2. Appearance   (theme, fonts, window)
--    3. Behavior     (startup, shell, tab bar toggles)
--    4. Keybindings
--    5. Styling      (tab bar + status pills — colors live here)
-- =====================================================================

-- ----------------------------------------------------------------------
-- 1. Setup
-- ----------------------------------------------------------------------
local wezterm = require("wezterm")
local config = wezterm.config_builder()

local theme = 'Tokyo Night Storm (Gogh)'

-- ----------------------------------------------------------------------
-- 2. Appearance
-- ----------------------------------------------------------------------
config.color_scheme = theme

config.font = wezterm.font("MesloLGS Nerd Font Mono")
config.font_size = 15
config.line_height = 1

config.window_background_gradient = {
    colors = {
        '#23222aff',
        '#1c1c33ff',
        '#130626ff',
    },
    orientation = 'Horizontal',
}
config.window_background_opacity = 0.7
config.macos_window_background_blur = 25

config.window_decorations = "RESIZE"
config.window_padding = {
    top = 20,
    bottom = 6,
}

-- ----------------------------------------------------------------------
-- 3. Behavior
-- ----------------------------------------------------------------------
config.initial_cols = 160
config.initial_rows = 40

-- New windows/tabs run fastfetch once, then drop into an interactive shell.
-- Splits (see keybindings) use a plain shell, so fastfetch shows once per window/tab.
config.default_prog = { '/bin/zsh', '-l', '-c', 'fastfetch; exec /bin/zsh -l' }

config.enable_tab_bar = true
config.tab_bar_at_bottom = true
config.use_fancy_tab_bar = false        -- required for custom powerline tab glyphs
config.tab_max_width = 32
config.status_update_interval = 3000    -- ms; CPU probe (top -l 2 -s 1) blocks ~1s

-- ----------------------------------------------------------------------
-- 4. Keybindings
-- ----------------------------------------------------------------------
config.keys = {
    {
        key = 't',
        mods = 'CMD|SHIFT',
        action = wezterm.action.SpawnWindow,
    },
    {
        key = 'd',
        mods = 'CMD|SHIFT',
        action = wezterm.action.SplitVertical { domain = 'CurrentPaneDomain', args = { '/bin/zsh', '-l' } },
    },
    {
        key = 'd',
        mods = 'CMD',
        action = wezterm.action.SplitHorizontal { domain = 'CurrentPaneDomain', args = { '/bin/zsh', '-l' } },
    },
    {
        key = 'w',
        mods = 'CMD',
        action = wezterm.action.CloseCurrentPane { confirm = true },
    },
}

-- ======================================================================
-- 5. Styling — tab bar + status pills (colors live here)
-- ======================================================================

-- ---- palette ---------------------------------------------------------
local BAR_BG   = '#24252f'   -- tab bar background
local TXT_DARK = '#101019'   -- text inside bright pills

local C = {
    tab    = '#8d6ebb',      -- active tab (purple, dimmed) [orig #bd93f9]
    ram    = '#CB7E85',      -- RAM (salmon, dimmed)
    cpu    = '#D0BA88',      -- CPU (gold, dimmed)
    batt   = '#7DA6D0',      -- Battery (blue, dimmed)
}

-- ---- dynamic load colors (traffic light) ----------------------------
-- brightness matched to dimmed tab (#8d6ebb, luminance ~122) [orig 88BA84/D0BA88/C7728A]
local LOAD_GREEN  = '#61855e'
local LOAD_YELLOW = '#887959'
local LOAD_RED    = '#b6687e'

-- CPU/RAM (high = bad): pct <= g -> green, <= y -> yellow, else red. nil -> green.
local function ramp(pct, g, y)
    if not pct then return LOAD_GREEN end
    if pct <= g then return LOAD_GREEN end
    if pct <= y then return LOAD_YELLOW end
    return LOAD_RED
end

-- Battery (low = bad, inverted): <=25 red, <=60 yellow, else green
local function batt_color(pct)
    if pct <= 25 then return LOAD_RED end
    if pct <= 60 then return LOAD_YELLOW end
    return LOAD_GREEN
end

-- ---- slant edge glyphs ----------------------------------------------
local SLANT_L = utf8.char(0xe0ba) -- ◢ left edge  (parallelogram lean) — status pills
local SLANT_R = utf8.char(0xe0bc) -- ◤ right edge (parallelogram lean) — status pills
local TAB_L   = utf8.char(0xe0c7) -- active tab left edge
local TAB_R   = utf8.char(0xe0c6) -- active tab right edge

-- bar background + colored new-tab (+) button
config.colors = {
    tab_bar = {
        background = BAR_BG,
        new_tab       = { fg_color = '#A6E3A1', bg_color = BAR_BG },
        new_tab_hover = { fg_color = BAR_BG,    bg_color = '#A6E3A1' },
    },
}

-- ---- helpers ---------------------------------------------------------

-- One slanted pill, rendered on the bar background, with a trailing gap.
-- Returns a list of wezterm.format elements.
local function pill(color, icon, text)
    return {
        'ResetAttributes',
        { Foreground = { Color = color } }, { Background = { Color = BAR_BG } }, { Text = SLANT_L },
        { Foreground = { Color = TXT_DARK } }, { Background = { Color = color } }, { Text = icon .. ' ' .. text },
        { Foreground = { Color = color } }, { Background = { Color = BAR_BG } }, { Text = SLANT_R },
        'ResetAttributes', -- slants give the visual separation; no extra gap
    }
end

-- ---- network icons: wifi / bluetooth, 3 states each -----------------
local INACTIVE   = '#D1D1D1'   -- off  = dim white
local WIFI_COLOR = '#79B9AF'   -- teal (dimmed)
local BT_COLOR   = '#7094CD'   -- blue (dimmed)
local BLUEUTIL   = '/opt/homebrew/bin/blueutil'

local WIFI_ICON = { off = 0xf092d, on = 0xf0929, connected = 0xf0928 }
local BT_ICON   = { off = 0xf00b2, on = 0xf00af, connected = 0xf00b1 }

-- plain colored glyph on the bar (off / on states)
local function icon_only(color, cp)
    return {
        'ResetAttributes',
        { Foreground = { Color = color } }, { Background = { Color = BAR_BG } },
        { Text = ' ' .. utf8.char(cp) .. ' ' },
    }
end

-- run a command, return stdout or nil (nil on non-zero exit)
local function run1(args)
    local ok, success, out = pcall(wezterm.run_child_process, args)
    if not ok or not success then return nil end
    return out or ''
end

local function wifi_state()
    local pw = run1({ '/usr/sbin/networksetup', '-getairportpower', 'en0' })
    if not pw or not pw:match('On') then return 'off' end
    local ip = run1({ '/usr/sbin/ipconfig', 'getifaddr', 'en0' })
    if ip and ip:match('%d+%.%d+%.%d+%.%d+') then return 'connected' end
    return 'on'
end

local function bt_state()
    local p = run1({ BLUEUTIL, '-p' })
    if not p or not p:match('1') then return 'off' end
    local c = run1({ BLUEUTIL, '--connected' })
    if c and c:gsub('%s', '') ~= '' then return 'connected' end
    return 'on'
end

local function net_render(state, color, icons)
    if state == 'off' then return icon_only(INACTIVE, icons.off) end
    if state == 'connected' then return icon_only(color, icons.connected) end
    return icon_only(color, icons.on)
end

-- RAM: "8.3 GB(51%)" via vm_stat math
local function get_mem()
    local ok, _, out = pcall(wezterm.run_child_process, { 'bash', '-c', [[
        ps=$(sysctl -n hw.pagesize); total=$(sysctl -n hw.memsize); s=$(vm_stat)
        # Activity Monitor "Memory Used" = Physical - Free - Cached(file-backed)
        free=$(awk '/Pages free/         {gsub("\\.","",$3); print $3}' <<<"$s")
        spec=$(awk '/Pages speculative/  {gsub("\\.","",$3); print $3}' <<<"$s")
        fb=$(awk   '/File-backed pages/  {gsub("\\.","",$3); print $3}' <<<"$s")
        totalpages=$(( total / ps ))
        used=$(( (totalpages - free - spec - fb) * ps ))
        pct=$(( used * 100 / total ))
        gb=$(echo "scale=1; $used/1073741824" | bc)
        printf "%s GB(%s%%)" "$gb" "$pct"
    ]] })
    if not ok or not out or out == '' then return 'N/A', nil end
    return out, tonumber(out:match('%((%d+)%%%)'))
end

-- CPU: integer system usage % (user + sys), matching Activity Monitor's CPU Load.
-- iostat over a 1s window: lighter than top (no process scan). The 1st report is
-- since-boot, the 2nd is the real delta — so read the last data line.
local function get_cpu()
    local ok, success, out = pcall(wezterm.run_child_process,
        { 'iostat', '-c', '2', '-w', '1' })
    if not ok or not success or not out then return 'N/A' end
    local last
    for line in out:gmatch('[^\n]+') do
        if line:match('^%s*[%d%.]') then last = line end -- data rows start with a number
    end
    if not last then return 'N/A' end
    local f = {}
    for tok in last:gmatch('%S+') do f[#f + 1] = tok end
    -- columns end with: ... us sy id 1m 5m 15m  → us=f[n-5], sy=f[n-4]
    local n = #f
    local used = (tonumber(f[n - 5]) or 0) + (tonumber(f[n - 4]) or 0)
    local pct = math.floor(used + 0.5)
    return tostring(pct) .. '%', pct
end

-- Battery level icons, indexed by floor(pct/10): 0=empty .. 10=full
local BATT_LEVEL = {
    [0] = 0xf008e, [1] = 0xf007a, [2] = 0xf007b, [3] = 0xf007c, [4] = 0xf007d,
    [5] = 0xf007e, [6] = 0xf007f, [7] = 0xf0080, [8] = 0xf0081, [9] = 0xf0082, [10] = 0xf0079,
}
local BATT_BOLT  = 0xf0e7    -- separate charging bolt, shown before the battery
local BATT_GREEN = '#88BA84' -- charging (dimmed)
local BATT_RED   = '#C7728A' -- low (dimmed)

-- Battery pill (icon + color react to charge level & charging state); nil if no battery
local function batt_pill()
    local b = wezterm.battery_info()
    if not b or #b == 0 then return nil end
    local info = b[1]
    local pct = math.floor((info.state_of_charge or 0) * 100 + 0.5)
    local charging = info.state == 'Charging'
    local idx = math.max(0, math.min(10, math.floor(pct / 10)))
    local icon = utf8.char(BATT_LEVEL[idx])
    if charging then icon = utf8.char(BATT_BOLT) .. ' ' .. icon end -- bolt before battery

    local color = batt_color(pct)             -- dynamic: <=25 red, <=60 yellow, else green

    return pill(color, icon, pct .. '%')
end

-- ---- tab titles: slanted purple active tab, dim inactive -------------
local function basename(p)
    if not p or p == '' then return '' end
    return (p:gsub('/+$', ''):match('[^/]+$')) or p
end

-- current folder name for a pane ('~' for home, '' if unknown)
local function pane_folder(pane)
    local cwd = pane.current_working_dir
    if not cwd then return '' end
    local path = (type(cwd) == 'userdata') and cwd.file_path
        or tostring(cwd):gsub('^file://[^/]*', '')
    if not path or path == '' then return '' end
    path = path:gsub('/+$', '')
    if path == wezterm.home_dir then return '~' end
    return basename(path)
end

-- known processes -> nerd-font glyph (extend freely). Unknown -> show name text.
local PROC_ICON = {
    vim = 0xe62b, nvim = 0xe62b, vi = 0xe62b, nano = 0xe838,
    zsh = 0xf489, bash = 0xf489, sh = 0xf489, fish = 0xf489, tmux = 0xebc8,
    node = 0xe718, deno = 0xe718,
    python = 0xe73c, python3 = 0xe73c, ipython = 0xe73c,
    ruby = 0xe739, go = 0xe65e, rust = 0xe7a8, cargo = 0xe7a8, lua = 0xe620, java = 0xe738,
    git = 0xe702, lazygit = 0xe702, tig = 0xe702, gh = 0xe709,
    docker = 0xf308, ['docker-compose'] = 0xf308, kubectl = 0xe7b2, ssh = 0xeba9,
    btop = 0xf080, htop = 0xf080, top = 0xf080,
    make = 0xe673, npm = 0xe71e, pnpm = 0xe71e, yarn = 0xe6a7,
    psql = 0xe706, mysql = 0xe704, redis = 0xe76d, brew = 0xf0fc, man = 0xf02d,
    code = 0xe70c, bat = 0xf15b, less = 0xf15b, cat = 0xf15b, fzf = 0xf422,
    curl = 0xf0ed, wget = 0xf0ed,
}

local function tab_label(tab, max_width)
    local pane = tab.active_pane
    local proc = basename(pane.foreground_process_name)
    if proc == '' then proc = basename(pane.title) end
    if proc == '' then proc = 'sh' end
    local icon = PROC_ICON[proc:lower()]
    local shown = icon and utf8.char(icon) or proc
    local folder = pane_folder(pane)
    local label = (tab.tab_index + 1) .. ': ' .. shown
    if folder ~= '' then label = label .. ' ' .. folder end
    -- keep the start (index + process), trim the folder tail if needed
    return wezterm.truncate_right(label, max_width - 4)
end

wezterm.on('format-tab-title', function(tab, tabs, _, conf, _, _)
    local is_last = tab.tab_id == tabs[#tabs].tab_id
    local trail = is_last and '  ' or '' -- small gap before the + button only

    if tab.is_active then
        local label = tab_label(tab, math.floor(conf.tab_max_width * 0.85))
        return {
            'ResetAttributes',
            { Foreground = { Color = C.tab } }, { Background = { Color = BAR_BG } }, { Text = TAB_L },
            { Foreground = { Color = TXT_DARK } }, { Background = { Color = C.tab } }, { Text = ' ' .. label .. ' ' },
            { Foreground = { Color = C.tab } }, { Background = { Color = BAR_BG } }, { Text = TAB_R },
            'ResetAttributes',
            { Background = { Color = BAR_BG } }, { Text = trail },
        }
    end
    -- inactive tabs: 40% narrower than active
    local label = tab_label(tab, math.floor(conf.tab_max_width * 0.6))
    return { { Background = { Color = BAR_BG } }, { Text = ' ' .. label .. ' ' .. trail } }
end)

-- ---- right status: RAM / CPU / Battery pills -------------------------
wezterm.on('update-right-status', function(window, _)
    local items = {}
    local function add(list) for _, e in ipairs(list) do items[#items + 1] = e end end

    -- network icons, left of the metric pills
    add(net_render(wifi_state(), WIFI_COLOR, WIFI_ICON))
    add(net_render(bt_state(), BT_COLOR, BT_ICON))

    local cpu_txt, cpu_pct = get_cpu()
    add(pill(ramp(cpu_pct, 65, 89), utf8.char(0xf4bc), cpu_txt))
    local mem_txt, mem_pct = get_mem()
    add(pill(ramp(mem_pct, 50, 89), utf8.char(0xefc5), mem_txt))
    local bp = batt_pill()
    if bp then add(bp) end

    -- right margin so the last slant isn't clipped by the window's rounded corner
    items[#items + 1] = { Background = { Color = BAR_BG } }
    items[#items + 1] = { Text = ' ' }

    window:set_right_status(wezterm.format(items))
end)

return config
