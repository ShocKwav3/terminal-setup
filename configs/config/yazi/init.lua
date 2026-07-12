-- ============================================================================
-- Retro BIOS chrome for Yazi
-- Dresses Yazi's shell as a Pentium-era firmware SETUP screen. Three looks are
-- supported and auto-selected from the active flavour in theme.toml. The names
-- are an unaffiliated homage — no real firmware vendor is referenced:
--   mega-bios     -> MEGA BIOS  (grey title bar, double-line frame, "640K OK")
--   laurel-bios   -> LAUREL BIOS (yellow-on-blue title, single-line cyan frame)
--   firebird-bios -> FIREBIRD   (reversed grey menu bar, single-line frame)
--
-- Only wraps EXTRA chrome around the stock components (Tabs, Tab, Status, Modal
-- stay as-is), so navigation/behaviour is unchanged. Colours live in the
-- matching flavors/<name>.yazi/flavor.toml.
-- ============================================================================

local BLUE   = "#0000a8"
local GREY   = "#c6c6c6"
local WHITE  = "#ffffff"
local CYAN   = "#54fefe"
local GREEN  = "#54fe54"
local YELLOW = "#fefe54"

-- --- Per-BIOS chrome presets ------------------------------------------------
local PRESETS = {
	["mega-bios"] = {
		tag = " MEGA BIOS SETUP", bar_bg = GREY, bar_fg = BLUE,
		frame = "DOUBLE",
		legend = "ESC:Back  hjkl:Move  Space:Sel  y:Yank  x:Cut  p:Paste  d:Trash  /:Find  q:Quit",
		legend_fg = CYAN,
		post = " 640K OK ", post_fg = GREEN,
	},
	["laurel-bios"] = {
		tag = " LAUREL BIOS SETUP", bar_bg = BLUE, bar_fg = YELLOW,
		frame = "PLAIN",
		legend = "Esc:Quit  ↑↓→←:Move  Enter:Select  Space:Mark  /:Find  q:Quit",
		legend_fg = CYAN,
		post = " F10:SAVE & EXIT ", post_fg = YELLOW,
	},
	["firebird-bios"] = {
		tag = " FIREBIRD BIOS", bar_bg = GREY, bar_fg = BLUE,
		frame = "PLAIN",
		legend = "F1:Help  ↑↓:Select Item  Enter:Open  Esc:Exit  /:Find  q:Quit",
		legend_fg = WHITE,
		post = " NUM ", post_fg = GREEN,
	},
}

-- Read the active flavour name straight from theme.toml so the chrome tracks
-- whatever `dark = "..."` is set to. Falls back to MEGA if it can't be read.
local function active_flavor()
	local ok, name = pcall(function()
		local home = os.getenv("YAZI_CONFIG_HOME")
		if home then
			home = home .. "/theme.toml"
		else
			home = (os.getenv("HOME") or "") .. "/.config/yazi/theme.toml"
		end
		local f = io.open(home, "r")
		if not f then return nil end
		local s = f:read("*a")
		f:close()
		return s:match('dark%s*=%s*"([^"]+)"')
	end)
	return ok and name or nil
end

local P = PRESETS[active_flavor() or ""] or PRESETS["mega-bios"]

-- --- Small helpers ----------------------------------------------------------
local function ulen(s) return utf8.len(s) or #s end

local function seg3(w, l, c, r)
	l, c, r = l or "", c or "", r or ""
	local ll, cl, rl = ulen(l), ulen(c), ulen(r)
	if ll + cl + rl >= w then
		return string.sub(l, 1, w), "", ""
	end
	local cstart = math.floor((w - cl) / 2)
	local rstart = w - rl
	local gap1 = math.max(0, cstart - ll)
	local gap2 = math.max(0, rstart - (ll + gap1 + cl))
	return l .. string.rep(" ", gap1), c .. string.rep(" ", gap2), r
end

local function bar(area, bg, segs)
	local spans = {}
	for _, s in ipairs(segs) do
		spans[#spans + 1] = ui.Span(s[1]):fg(s[2]):bg(bg):bold()
	end
	return ui.Line(spans):area(area)
end

local function clock()
	local ok, t = pcall(os.date, "%H:%M:%S")
	return ok and tostring(t) or ""
end

local function cwd()
	local ok, p = pcall(function() return tostring(cx.active.current.cwd) end)
	return ok and p or ""
end

local function inset(a)
	return ui.Rect { x = a.x + 1, y = a.y + 1, w = a.w - 2, h = a.h - 2 }
end

-- --- Extend Root: banner (path) row + framed panes + stock status row -------
function Root:layout()
	self._chunks = ui.Layout()
		:direction(ui.Layout.VERTICAL)
		:constraints({
			ui.Constraint.Length(1),
			ui.Constraint.Length(Tabs.height()),
			ui.Constraint.Fill(1),
			ui.Constraint.Length(1),
		})
		:split(self._area)
end

function Root:build()
	local c = self._chunks
	self._banner = c[1]
	self._status = c[4]

	local pane = c[3]
	if pane.w > 2 and pane.h > 2 then
		self._box = pane
		pane = inset(pane)
	else
		self._box = nil
	end

	self._children = {
		Tabs:new(c[2]),
		Tab:new(pane, cx.active),
		Status:new(c[4], cx.active),
		Modal:new(self._area),
	}
end

function Root:redraw()
	local els = {}

	-- Top: firmware title bar — tag | current path | clock
	local left = P.tag
	local right = clock() .. " "
	local avail = self._banner.w - ulen(left) - ulen(right) - 2
	local path = cwd()
	if avail > 1 and ulen(path) > avail then
		-- Keep the last (avail-1) CHARACTERS, cutting on a UTF-8 boundary so a
		-- multibyte char in the cwd is never split into a garbage glyph.
		local keep = avail - 1
		local off = utf8.offset(path, -keep) or (#path - keep + 1)
		path = "…" .. string.sub(path, off)
	end
	local bl, bc, br = seg3(self._banner.w, left, path, right)
	els[#els + 1] = bar(self._banner, P.bar_bg,
		{ { bl, P.bar_fg }, { bc, P.bar_fg }, { br, P.bar_fg } })

	-- Frame around the panes (border type per BIOS; skip silently on mismatch)
	if self._box then
		local ok, border = pcall(function()
			return ui.Border(ui.Edge.ALL):area(self._box)
				:type(ui.Border[P.frame] or ui.Border.PLAIN):style(th.mgr.border_style)
		end)
		if ok then els[#els + 1] = border end
	end

	for _, child in ipairs(self._children) do
		els = ya.list_merge(els, ui.redraw(child))
	end

	-- Center the key legend in the status row (drawn on top, in the gap
	-- between the stock mode/size on the left and position/POST on the right).
	els[#els + 1] = ui.Line { ui.Span(P.legend):fg(P.legend_fg) }
		:area(self._status):align(ui.Align.CENTER)

	return els
end

-- --- POST tail on the right of the stock status row -------------------------
Status:children_add(function()
	return ui.Line { ui.Span(P.post):fg(P.post_fg):bold() }
end, 9000, Status.RIGHT)
