-- Multi-Team Support - scripts/pop_text.lua
-- Animated floating notifications for spawn arrivals, team joins, milestone
-- records, and player deaths.  Four presets:
--
--   pop_text.spawn_confirm(player, pos, text_str)
--     Elastic pop + upward fade at the player's new spawn position.
--     text_str supports rich text (e.g. helpers.colored_name()).
--
--   pop_text.team_join(player, pos, text_str)
--     DI-style snap-in followed by upward-drifting horizontal jiggle.
--     text_str supports rich text.
--
--   pop_text.milestone(force, text_str)
--     Comic-book elastic pop above every connected force member, with a
--     heavy overshoot curve, damped orientation wobble, and a thin shadow.
--     text_str supports rich text (item icons render correctly).
--
--   pop_text.rip(player, pos)
--     Fast explosive red pop visible to all players on the same surface.
--
-- All presets are no-ops when the admin flag "popup_text_enabled" is false.
-- Requires pop_text.tick(now) called every game tick from control.lua.

local admin_gui = require("gui.admin")
local pop_text  = {}

local math_sin = math.sin
local math_max = math.max
local math_min = math.min

-- Reusable tables passed to the render API each tick (values are read
-- immediately by the engine, so reuse is safe).
local _pos = { x = 0, y = 0 }
local _col = { r = 1, g = 1, b = 1, a = 1 }
local _shd = { r = 0.04, g = 0.04, b = 0.04, a = 0.4 }

-- ─── Easing ───────────────────────────────────────────────────────────────

local function ease_out_quad(t)  return 1 - (1 - t) * (1 - t) end
local function ease_in_quad(t)   return t * t end
local function ease_out_cubic(t) local u = 1 - t; return 1 - u * u * u end

-- ─── Storage ──────────────────────────────────────────────────────────────

function pop_text.init_storage()
    storage.pop_texts = storage.pop_texts or {}
end

-- ─── Internal ─────────────────────────────────────────────────────────────

local function resolve(id)
    local obj = id and rendering.get_object_by_id(id)
    return (obj and obj.valid) and obj or nil
end

local function safe_destroy(id)
    local obj = resolve(id)
    if obj then obj.destroy() end
end

-- ─── Preset: spawn_confirm ────────────────────────────────────────────────

-- Fast elastic pop + upward fade at the player's new spawn position.
-- Visible only to the arriving player.
function pop_text.spawn_confirm(player, pos, text_str)
    if not admin_gui.flag("popup_text_enabled") then return end
    pop_text.init_storage()
    local surface = player.surface
    if not (surface and surface.valid) then return end

    local x, y = pos.x, pos.y - 3
    local obj = rendering.draw_text{
        text            = text_str,
        surface         = surface,
        target          = { x = x, y = y },
        color           = { r = 1, g = 1, b = 1, a = 1 },
        scale           = 0.1,
        font            = "default-large-semibold",
        alignment       = "center",
        use_rich_text   = true,
        scale_with_zoom = true,
        players         = { player.index },
    }
    if not obj then return end

    storage.pop_texts[#storage.pop_texts + 1] = {
        text_id      = obj.id,
        created_tick = game.tick,
        lifetime     = 80,
        anim_type    = "spawn",
        anchor_x     = x,
        anchor_y     = y,
        base_scale   = 1.4,
    }
end

-- ─── Preset: team_join ────────────────────────────────────────────────────

-- Snap-in pop + upward jiggle. Visible only to player.
-- Embed force color via rich text in text_str (helpers.team_tag works).
function pop_text.team_join(player, pos, text_str)
    if not admin_gui.flag("popup_text_enabled") then return end
    pop_text.init_storage()
    local surface = player.surface
    if not (surface and surface.valid) then return end

    local x, y = pos.x, pos.y - 2
    local obj = rendering.draw_text{
        text            = text_str,
        surface         = surface,
        target          = { x = x, y = y },
        color           = { r = 1, g = 1, b = 1, a = 1 },
        scale           = 1.2,
        font            = "default-bold",
        alignment       = "center",
        use_rich_text   = true,
        scale_with_zoom = true,
        players         = { player.index },
    }
    if not obj then return end

    storage.pop_texts[#storage.pop_texts + 1] = {
        text_id      = obj.id,
        created_tick = game.tick,
        lifetime     = 100,
        anim_type    = "team_join",
        anchor_x     = x,
        anchor_y     = y,
        base_scale   = 1.2,
    }
end

-- ─── Preset: milestone ────────────────────────────────────────────────────

-- Comic-book elastic pop above every connected player in the force.
-- text_str supports rich text (item icons render correctly).
-- Shadow is a single dark offset copy for a subtle thin outline.
function pop_text.milestone(force, text_str)
    if not admin_gui.flag("popup_text_enabled") then return end
    pop_text.init_storage()
    -- Single diagonal shadow for a light outline effect.
    local shadow_offsets = { {0.06, 0.06}, {-0.06, 0.06}, {0.06, -0.06}, {-0.06, -0.06} }

    for _, player in pairs(force.players) do
        if not player.connected then goto next_player end
        local surface = player.surface
        if not (surface and surface.valid) then goto next_player end

        local x, y = player.position.x, player.position.y - 5

        -- Thin shadow copies drawn first (behind main text).
        local shadow_ids = {}
        for _, off in ipairs(shadow_offsets) do
            local s = rendering.draw_text{
                text            = text_str,
                surface         = surface,
                target          = { x = x + off[1], y = y + off[2] },
                color           = { r = 0.04, g = 0.04, b = 0.04, a = 0.4 },
                scale           = 0.1,
                font            = "default-game",
                alignment       = "center",
                use_rich_text   = true,
                scale_with_zoom = true,
                players         = { player.index },
            }
            if s then shadow_ids[#shadow_ids + 1] = s.id end
        end

        local obj = rendering.draw_text{
            text            = text_str,
            surface         = surface,
            target          = { x = x, y = y },
            color           = { r = 1, g = 0.95, b = 0.15, a = 1 },
            scale           = 0.1,
            font            = "default-game",
            alignment       = "center",
            use_rich_text   = true,
            scale_with_zoom = true,
            players         = { player.index },
        }
        if obj then
            storage.pop_texts[#storage.pop_texts + 1] = {
                text_id        = obj.id,
                shadow_ids     = #shadow_ids > 0 and shadow_ids or nil,
                shadow_offsets = shadow_offsets,
                created_tick   = game.tick,
                lifetime       = 180,
                anim_type      = "milestone",
                anchor_x       = x,
                anchor_y       = y,
                base_scale     = 2.0,
                color_r        = 1,
                color_g        = 0.95,
                color_b        = 0.15,
            }
        end

        ::next_player::
    end
end

-- ─── Preset: rip ──────────────────────────────────────────────────────────

-- Fast explosive red "RIP!" pop above the death position.
-- Visible to all connected players on the same surface.
function pop_text.rip(player, pos)
    if not admin_gui.flag("popup_text_enabled") then return end
    pop_text.init_storage()
    local surface = player.surface
    if not (surface and surface.valid) then return end

    local x, y = pos.x, pos.y - 2

    local visible = {}
    for _, p in pairs(surface.players) do
        if p.connected then visible[#visible + 1] = p.index end
    end

    local obj = rendering.draw_text{
        text            = "RIP!",
        surface         = surface,
        target          = { x = x, y = y },
        color           = { r = 1, g = 0.2, b = 0.1, a = 1 },
        scale           = 0.1,
        font            = "default-game",
        alignment       = "center",
        use_rich_text   = false,
        scale_with_zoom = true,
        players         = visible,
    }
    if not obj then return end

    storage.pop_texts[#storage.pop_texts + 1] = {
        text_id      = obj.id,
        created_tick = game.tick,
        lifetime     = 70,
        anim_type    = "rip",
        anchor_x     = x,
        anchor_y     = y,
        base_scale   = 2.5,
        color_r      = 1,
        color_g      = 0.2,
        color_b      = 0.1,
    }
end

-- ─── Animation functions ──────────────────────────────────────────────────
-- Each returns: scale, alpha, dx, dy, orientation
-- orientation nil means "leave as is"; a number sets it (Factorio 0-1 range).

local function anim_spawn(entry, age, progress)
    -- Elastic pop: 0-5t snap to 2×, 5-12t elastic drop to 1×, then hold.
    local mul
    if     age < 5  then mul = 2.0 * ease_out_quad(age / 5)
    elseif age < 12 then mul = 2.0 - 1.0 * ((age - 5) / 7)
    else                 mul = 1.0
    end
    -- Gentle upward drift: 1 tile over lifetime.
    local dy    = -1.0 * ease_out_cubic(progress)
    -- Fade over the last 25% of lifetime.
    local alpha = progress < 0.75 and 1 or (1 - (progress - 0.75) / 0.25)
    return entry.base_scale * mul, alpha, 0, dy, nil
end

local function anim_team_join(entry, age, progress)
    -- Piecewise pop curve borrowed from DamageIndicator's snap-in shape:
    -- 0-4  ticks: rapid rise  0.20 → 1.85
    -- 4-10 ticks: overshoot relax  1.85 → 0.92
    -- 10-16 ticks: small bounce  0.92 → 1.05
    -- 16-22 ticks: settle  1.05 → 1.00
    local pop
    if     age < 4  then pop = 0.20 + 0.4125  * age
    elseif age < 10 then pop = 1.85 - 0.155   * (age - 4)
    elseif age < 16 then pop = 0.92 + 0.02167 * (age - 10)
    elseif age < 22 then pop = 1.05 - 0.00833 * (age - 16)
    else                 pop = 1.0
    end

    -- Upward drift: 2.5 tiles over lifetime, eases to a stop.
    local dy = -2.5 * ease_out_cubic(progress)

    -- Horizontal jiggle: sine oscillation that damps to zero by 50% of life.
    local jiggle_env = math_max(0, 1 - progress * 2)
    local dx = 0.35 * jiggle_env * math_sin(age * 0.65)

    -- Fade over the last 40% of lifetime.
    local alpha = progress < 0.60 and 1 or (1 - (progress - 0.60) / 0.40)

    return entry.base_scale * pop, alpha, dx, dy, nil
end

local function anim_milestone(entry, age, progress)
    -- Comic elastic pop:
    -- 0-6  ticks: snap from 0 to 3× (ease-out-quad)
    -- 6-16 ticks: drop through to 0.9× (linear overshoot)
    -- 16-26 ticks: bounce back to 1.65× (ease-out-quad)
    -- 26-35 ticks: settle to 1.5× (linear)
    -- 35+ ticks:   hold at 1.5×
    local mul
    if     age < 6  then mul = 3.0  * ease_out_quad(age / 6)
    elseif age < 16 then mul = 3.0  - 2.1  * ((age - 6)  / 10)
    elseif age < 26 then mul = 0.9  + 0.75 * ease_out_quad((age - 16) / 10)
    elseif age < 35 then mul = 1.65 - 0.15 * ((age - 26) / 9)
    else                 mul = 1.5
    end
    local scale = entry.base_scale * mul

    -- Orientation wobble: fast oscillation damped hard by tick 35.
    -- Values are in Factorio's 0-1 orientation range (1 full rotation).
    local env = math_max(0, 1 - age / 35)
    local orientation = env * 0.035 * math_sin(age * 1.2)
    if orientation < 0 then orientation = orientation + 1 end

    -- Fade over the last 25% of lifetime.
    local alpha = progress < 0.75 and 1 or (1 - (progress - 0.75) / 0.25)

    return scale, alpha, 0, 0, orientation
end

local function anim_rip(entry, age, progress)
    -- Explosive pop: 0-4t snap to 3.5×, 4-10t drop to 1.2×, then hold.
    local mul
    if     age < 4  then mul = 3.5 * ease_out_quad(age / 4)
    elseif age < 10 then mul = 3.5 - 2.3 * ((age - 4) / 6)
    else                 mul = 1.2
    end
    -- Fast upward drift: 3 tiles total.
    local dy    = -3.0 * ease_out_cubic(progress)
    -- Fade over the last 35% of lifetime.
    local alpha = progress < 0.65 and 1 or (1 - (progress - 0.65) / 0.35)
    return entry.base_scale * mul, alpha, 0, dy, nil
end

-- ─── Tick ─────────────────────────────────────────────────────────────────

function pop_text.tick(now)
    local entries = storage.pop_texts
    if not entries or #entries == 0 then return end

    local count = #entries
    local write = 1

    for read = 1, count do
        local e        = entries[read]
        local age      = now - e.created_tick
        local progress = math_min(1, age / e.lifetime)

        local text_obj = resolve(e.text_id)

        -- Clean up and drop if the render object is already gone.
        if not text_obj then
            if e.shadow_ids then
                for _, sid in ipairs(e.shadow_ids) do safe_destroy(sid) end
            end
            goto continue
        end

        -- Lifetime expired: destroy and drop.
        if progress >= 1 then
            text_obj.destroy()
            if e.shadow_ids then
                for _, sid in ipairs(e.shadow_ids) do safe_destroy(sid) end
            end
            goto continue
        end

        do
            local scale, alpha, dx, dy, orientation
            local at = e.anim_type
            if     at == "spawn"      then scale, alpha, dx, dy, orientation = anim_spawn(e, age, progress)
            elseif at == "team_join"  then scale, alpha, dx, dy, orientation = anim_team_join(e, age, progress)
            elseif at == "milestone"  then scale, alpha, dx, dy, orientation = anim_milestone(e, age, progress)
            elseif at == "rip"        then scale, alpha, dx, dy, orientation = anim_rip(e, age, progress)
            else
                -- Unknown type: destroy and drop.
                text_obj.destroy()
                if e.shadow_ids then
                    for _, sid in ipairs(e.shadow_ids) do safe_destroy(sid) end
                end
                goto continue
            end

            -- Update main text object.
            _pos.x = e.anchor_x + dx
            _pos.y = e.anchor_y + dy
            text_obj.target = _pos
            text_obj.scale  = scale
            _col.r = e.color_r or 1
            _col.g = e.color_g or 1
            _col.b = e.color_b or 1
            _col.a = alpha
            text_obj.color = _col
            if orientation then text_obj.orientation = orientation end

            -- Update shadows (milestone only).
            local sids     = e.shadow_ids
            local soffsets = e.shadow_offsets
            if sids and soffsets then
                _shd.a = alpha * 0.6
                for i, sid in ipairs(sids) do
                    local s = resolve(sid)
                    if s then
                        s.scale = scale * 1.015
                        s.color = _shd
                        if orientation then s.orientation = orientation end
                        local off = soffsets[i]
                        if off then
                            _pos.x = e.anchor_x + off[1]
                            _pos.y = e.anchor_y + off[2]
                            s.target = _pos
                        end
                    end
                end
            end
        end

        -- Keep this entry alive.
        entries[write] = e
        write = write + 1

        ::continue::
    end

    -- Compact the array in place (avoids table.remove O(n²)).
    for i = count, write, -1 do
        entries[i] = nil
    end
end

return pop_text
