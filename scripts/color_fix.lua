-- scripts/color_fix.lua
-- Keep player colours READABLE, NON-BROWN and DISTINCT from each other.
--
--   * dark colours (low luminance) are brightened toward white -- hard to read
--     against the dark chat / GUI background otherwise;
--   * brown / muddy-orange colours are pushed to a vivid orange -- they blend
--     into Factorio's terrain otherwise;
--   * a colour that clashes with another player's is moved to the colour furthest
--     from everyone else's, picked from a palette spread across the readable gamut
--     (rotating a single player's own hue just makes clashing players pile up in
--     the same gap, so we sample the WHOLE gamut instead).
--
-- Live changes arrive via Factorio 2.1's on_player_color_changed
-- (events/player_lifecycle.lua). Our own corrective writes echo back through
-- that same event: storage.color_fix_last holds the last colour we set (or
-- verified as fine) per player, stored BEFORE the write, and on_color_changed
-- skips any change that matches it -- correct whether the engine dispatches
-- the event synchronously inside the assignment or deferred later in the tick.
-- Joins are handled on on_player_joined_game (a join is not a colour change,
-- but the arriving colour may still need fixing and seeds color_fix_last).

local helpers     = require("scripts.helpers")
local admin_flags = require("scripts.admin_flags")

local M = {}

-- ── Tunables ──────────────────────────────────────────────────────────
local DARK     = 0.50    -- perceived luminance below this is "too dark"
local TARGET   = 0.65    -- brighten a dark colour up to this luminance
local BHMIN    = 20      -- brown = orange hue band (degrees) ...
local BHMAX    = 50
local BSMIN    = 0.15    -- ... with at least this saturation ...
local BVMAX    = 0.80    -- ... and value below this (a vivid orange has V~1)
local BSAT     = 0.60    -- browns are rebuilt at this minimum saturation ...
local BTV      = 1.00    -- ... and full value -> a bright distinct orange
local MINDIST2 = 0.0625  -- colours closer than sqrt(0.0625)=0.25 (RGB) clash
local LREAD    = 0.55    -- palette colours must be at least this readable

-- ── Colour maths ──────────────────────────────────────────────────────
local function lum(c) return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b end

local function normalize(c)
    local a = c.a or 1
    if math.max(c.r, c.g, c.b, a) > 1 then
        return { r = c.r / 255, g = c.g / 255, b = c.b / 255, a = a / 255 }
    end
    return { r = c.r, g = c.g, b = c.b, a = a }
end

local function rgb2hsv(c)
    local mx = math.max(c.r, c.g, c.b)
    local mn = math.min(c.r, c.g, c.b)
    local d = mx - mn
    local h = 0
    if d > 0 then
        if mx == c.r then h = ((c.g - c.b) / d) % 6
        elseif mx == c.g then h = (c.b - c.r) / d + 2
        else h = (c.r - c.g) / d + 4 end
        h = h * 60
        if h < 0 then h = h + 360 end
    end
    local s = 0
    if mx > 0 then s = d / mx end
    return h, s, mx
end

local function hsv2rgb(h, s, v, a)
    local c = v * s
    local x = c * (1 - math.abs((h / 60) % 2 - 1))
    local m = v - c
    local r, g, b
    if h < 60 then r, g, b = c, x, 0
    elseif h < 120 then r, g, b = x, c, 0
    elseif h < 180 then r, g, b = 0, c, x
    elseif h < 240 then r, g, b = 0, x, c
    elseif h < 300 then r, g, b = x, 0, c
    else r, g, b = c, 0, x end
    return { r = r + m, g = g + m, b = b + m, a = a }
end

local function brighten(c, t)
    local L = lum(c)
    if L >= t then return c end
    local k = (t - L) / (1 - L)
    return { r = c.r + k * (1 - c.r), g = c.g + k * (1 - c.g), b = c.b + k * (1 - c.b), a = c.a }
end

local function dist2(a, b)
    local dr = a.r - b.r local dg = a.g - b.g local db = a.b - b.b
    return dr * dr + dg * dg + db * db
end

local function differs(a, b)
    return math.abs(a.r - b.r) + math.abs(a.g - b.g) + math.abs(a.b - b.b) > 0.001
end

-- Palette of distinct, readable colours spread across the gamut. Built once.
local palette = {}
for hue = 0, 359, 12 do
    local svs = { { 0.55, 0.90 }, { 0.80, 1.00 }, { 0.95, 0.80 }, { 0.35, 1.00 } }
    for _, sv in ipairs(svs) do
        local cand = hsv2rgb(hue, sv[1], sv[2], 0.5)
        if lum(cand) >= LREAD then palette[#palette + 1] = cand end
    end
end

local function mindist(c, taken)
    local md = 1e9
    for _, t in pairs(taken) do
        local d = dist2(c, t)
        if d < md then md = d end
    end
    return md
end

-- The palette colour furthest from everything in `taken`.
local function farthest(taken, alpha)
    local best, score = palette[1], -1
    for _, cand in ipairs(palette) do
        local md = mindist(cand, taken)
        if md > score then score = md best = cand end
    end
    return { r = best.r, g = best.g, b = best.b, a = alpha }
end

-- Brighten darks, push browns to vivid orange. Returns (colour, reason).
local function readable(c)
    local h, s, v = rgb2hsv(c)
    if h >= BHMIN and h <= BHMAX and s >= BSMIN and v <= BVMAX then
        -- Rebuild as a vivid orange. A RED-leaning brown can still come out below
        -- the readability floor (red has low luminance), so lift it to TARGET --
        -- this also keeps the result stable (it won't re-trigger the dark rule).
        local nc = hsv2rgb(h, math.max(s, BSAT), BTV, c.a)
        if lum(nc) < TARGET then nc = brighten(nc, TARGET) end
        return nc, "brown"
    elseif lum(c) < DARK then
        return brighten(c, TARGET), "dark"
    end
    return c, "keep"
end

-- Colours of every player EXCEPT `skip_index` (the live set to differ from).
local function other_colours(skip_index)
    local out = {}
    for _, q in pairs(game.players) do
        if q.index ~= skip_index then out[#out + 1] = normalize(q.color) end
    end
    return out
end

-- ── Public ────────────────────────────────────────────────────────────

--- Make ONE player's colour readable, non-brown and distinct from everyone
--- else. Sets both color (map tint) and chat_color (name). Returns (colour,
--- reason) if it changed, else nil. Idempotent -- a good colour is left alone.
function M.fix_player(player)
    if not (player and player.valid) then return nil end
    storage.color_fix_last = storage.color_fix_last or {}
    local c = normalize(player.color)
    local nc, why = readable(c)
    local taken = other_colours(player.index)
    if mindist(nc, taken) < MINDIST2 then
        nc = farthest(taken, c.a)
        why = (why == "keep") and "clash" or (why .. "+clash")
    end
    if differs(nc, c) then
        -- Store BEFORE writing: the writes below fire on_player_color_changed,
        -- and the echo suppression in on_color_changed compares against this --
        -- under synchronous dispatch the nested handler runs mid-assignment.
        storage.color_fix_last[player.index] = nc
        player.color = nc
        player.chat_color = nc
        return nc, why
    end
    storage.color_fix_last[player.index] = c
    return nil
end

local function notify(player, nc)
    player.print("Your colour was adjusted to stay readable and distinct from other players.", { color = nc })
end

--- On-join: brighten/de-brown/de-clash immediately so a dark or duplicate name
--- never shows. Gated by the "Readable Player Colours" admin flag.
function M.on_joined(player)
    if not admin_flags.flag("color_fix_enabled") then return end
    local nc = M.fix_player(player)
    if nc then notify(player, nc) end
end

--- on_player_color_changed entry (2.1). Skips the echo of our own write --
--- the new colour equals what fix_player stored moments ago -- and re-fixes
--- anything else. fix_player is idempotent, so even a leaked echo terminates
--- in one no-op pass rather than oscillating.
function M.on_color_changed(player)
    if not admin_flags.flag("color_fix_enabled") then return end
    if not (player and player.valid) then return end
    storage.color_fix_last = storage.color_fix_last or {}
    local last = storage.color_fix_last[player.index]
    if last and not differs(normalize(player.color), last) then return end
    local nc = M.fix_player(player)
    if nc and player.connected then notify(player, nc) end
end

--- Admin "/mts-fixcolors": re-spread EVERY player from scratch in one clean pass
--- (first of any clash keeps its colour, the rest fan out). Announces a summary.
function M.fix_all(caller)
    storage.color_fix_last = storage.color_fix_last or {}
    local taken, names = {}, {}
    for _, p in pairs(game.players) do
        local c = normalize(p.color)
        local nc = readable(c)
        if mindist(nc, taken) < MINDIST2 then nc = farthest(taken, c.a) end
        taken[#taken + 1] = nc
        storage.color_fix_last[p.index] = nc
        if differs(nc, c) then
            p.color = nc
            p.chat_color = nc
            names[#names + 1] = p.name
        end
    end
    if #names > 0 then
        helpers.broadcast("[colour] Adjusted unreadable / clashing colours for: " .. table.concat(names, ", "))
    end
    if caller then caller.print(("Adjusted %d player(s)."):format(#names)) end
    return #names
end

return M
