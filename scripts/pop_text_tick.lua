-- scripts/pop_text_tick.lua
-- Easing functions, per-preset animation curves, and the per-tick update loop
-- for pop_text. The public presets and storage init live in scripts/pop_text.lua.

local M = {}

local math_sin = math.sin
local math_max = math.max
local math_min = math.min

-- Reusable tables passed to the render API each tick (values are read
-- immediately by the engine, so reuse is safe).
local _pos = { x = 0, y = 0 }
local _col = { r = 1, g = 1, b = 1, a = 1 }
local _shd = { r = 0.04, g = 0.04, b = 0.04, a = 0.4 }

-- ─── Helpers ──────────────────────────────────────────────────────────

local function resolve(id)
    local obj = id and rendering.get_object_by_id(id)
    return (obj and obj.valid) and obj or nil
end

local function safe_destroy(id)
    local obj = resolve(id)
    if obj then obj.destroy() end
end

-- ─── Easing ───────────────────────────────────────────────────────────

local function ease_out_quad(t)  return 1 - (1 - t) * (1 - t) end
local function ease_out_cubic(t) local u = 1 - t; return 1 - u * u * u end

-- ─── Animation curves ─────────────────────────────────────────────────
-- Each returns: scale, alpha, dx, dy, orientation
-- orientation nil means "leave as is"; a number sets it (0-1 range).

local function anim_spawn(entry, age, progress)
    local mul
    if     age < 5  then mul = 2.0 * ease_out_quad(age / 5)
    elseif age < 12 then mul = 2.0 - 1.0 * ((age - 5) / 7)
    else                 mul = 1.0
    end
    local dy    = -2.5 * ease_out_cubic(progress)
    local alpha = progress < 0.75 and 1 or (1 - (progress - 0.75) / 0.25)
    return entry.base_scale * mul, alpha, 0, dy, nil
end

local function anim_team_join(entry, age, progress)
    -- Piecewise snap-in curve: rapid rise → overshoot relax → small bounce → settle
    local pop
    if     age < 4  then pop = 0.20 + 0.4125  * age
    elseif age < 10 then pop = 1.85 - 0.155   * (age - 4)
    elseif age < 16 then pop = 0.92 + 0.02167 * (age - 10)
    elseif age < 22 then pop = 1.05 - 0.00833 * (age - 16)
    else                 pop = 1.0
    end
    local dy = -4.0 * ease_out_cubic(progress)
    local jiggle_env = math_max(0, 1 - progress * 2)
    local dx    = 0.35 * jiggle_env * math_sin(age * 0.65)
    local alpha = progress < 0.60 and 1 or (1 - (progress - 0.60) / 0.40)
    return entry.base_scale * pop, alpha, dx, dy, nil
end

local function anim_milestone(entry, age, progress)
    -- Comic elastic pop: snap → overshoot → bounce → settle
    local mul
    if     age < 6  then mul = 3.0  * ease_out_quad(age / 6)
    elseif age < 16 then mul = 3.0  - 2.1  * ((age - 6)  / 10)
    elseif age < 26 then mul = 0.9  + 0.75 * ease_out_quad((age - 16) / 10)
    elseif age < 35 then mul = 1.65 - 0.15 * ((age - 26) / 9)
    else                 mul = 1.5
    end
    local env = math_max(0, 1 - age / 35)
    local orientation = env * 0.035 * math_sin(age * 1.2)
    if orientation < 0 then orientation = orientation + 1 end
    local dy    = -1.5 * ease_out_cubic(progress)
    local alpha = progress < 0.75 and 1 or (1 - (progress - 0.75) / 0.25)
    return entry.base_scale * mul, alpha, 0, dy, orientation
end

--- Snap in quickly, then keep growing gently across the whole life via
--- ease_out_cubic so the text feels like it's continuously inflating
--- while the rainbow cycles. No overshoot, no wobble, just smooth growth.
local function anim_global_milestone(entry, age, progress)
    -- Quick snap from small (0.5×) up to base over the first ~8 ticks.
    local snap_t = age < 8 and age / 8 or 1
    local snap   = 0.5 + 0.5 * ease_out_quad(snap_t)
    -- Continuous growth (+0.6× across full life) for the inflating feel.
    local grow   = 0.6 * ease_out_cubic(progress)
    local mul    = snap + grow
    local dy     = -2.0 * ease_out_cubic(progress)
    local alpha  = progress < 0.85 and 1 or (1 - (progress - 0.85) / 0.15)
    return entry.base_scale * mul, alpha, 0, dy, nil
end

--- Convert a hue (0..1) to RGB at full saturation and value.
local function hsv_hue_to_rgb(h)
    h = h - math.floor(h)
    local seg = h * 6
    local i = math.floor(seg)
    local f = seg - i
    if     i == 0 then return 1,     f,     0
    elseif i == 1 then return 1 - f, 1,     0
    elseif i == 2 then return 0,     1,     f
    elseif i == 3 then return 0,     1 - f, 1
    elseif i == 4 then return f,     0,     1
    else               return 1,     0,     1 - f
    end
end

local function anim_notify(entry, age, progress)
    -- Quick snap-in over 6 ticks; then hold in place; fade only at the end.
    local pop = age < 6 and (0.5 + 0.5 * ease_out_quad(age / 6)) or 1.0
    local dy    = -0.5 * ease_out_cubic(progress)  -- barely drifts; already near top
    local alpha = progress < 0.75 and 1 or (1 - (progress - 0.75) / 0.25)
    return entry.base_scale * pop, alpha, 0, dy, nil
end

local function anim_rip(entry, age, progress)
    local mul
    if     age < 4  then mul = 3.5 * ease_out_quad(age / 4)
    elseif age < 10 then mul = 3.5 - 2.3 * ((age - 4) / 6)
    else                 mul = 1.2
    end
    local dy    = -4.5 * ease_out_cubic(progress)
    local alpha = progress < 0.65 and 1 or (1 - (progress - 0.65) / 0.35)
    return entry.base_scale * mul, alpha, 0, dy, nil
end

-- ─── Tick ─────────────────────────────────────────────────────────────

function M.tick(now)
    local entries = storage.pop_texts
    if not entries or #entries == 0 then return end

    local count = #entries
    local write = 1

    for read = 1, count do
        local e        = entries[read]
        local age      = now - e.created_tick
        local progress = math_min(1, age / e.lifetime)

        local text_obj = resolve(e.text_id)

        if not text_obj then
            if e.shadow_ids then
                for _, sid in ipairs(e.shadow_ids) do safe_destroy(sid) end
            end
            goto continue
        end

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
            if     at == "spawn"             then scale, alpha, dx, dy, orientation = anim_spawn(e, age, progress)
            elseif at == "team_join"         then scale, alpha, dx, dy, orientation = anim_team_join(e, age, progress)
            elseif at == "milestone"         then scale, alpha, dx, dy, orientation = anim_milestone(e, age, progress)
            elseif at == "global_milestone"  then scale, alpha, dx, dy, orientation = anim_global_milestone(e, age, progress)
            elseif at == "notify"            then scale, alpha, dx, dy, orientation = anim_notify(e, age, progress)
            elseif at == "rip"               then scale, alpha, dx, dy, orientation = anim_rip(e, age, progress)
            else
                text_obj.destroy()
                if e.shadow_ids then
                    for _, sid in ipairs(e.shadow_ids) do safe_destroy(sid) end
                end
                goto continue
            end

            if scale < 1e-4 then scale = 1e-4 end  -- ease_out_quad(0)=0 on first tick
            _pos.x = e.anchor_x + dx
            _pos.y = e.anchor_y + dy
            text_obj.target = _pos
            text_obj.scale  = scale
            if e.rainbow then
                -- ~3 seconds per full hue cycle (180 ticks).
                local r, g, b = hsv_hue_to_rgb(age / 180)
                _col.r = r; _col.g = g; _col.b = b
            else
                _col.r = e.color_r or 1
                _col.g = e.color_g or 1
                _col.b = e.color_b or 1
            end
            _col.a = alpha
            text_obj.color = _col
            if orientation then text_obj.orientation = orientation end

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
                            _pos.x = e.anchor_x + dx + off[1]
                            _pos.y = e.anchor_y + dy + off[2]
                            s.target = _pos
                        end
                    end
                end
            end
        end

        entries[write] = e
        write = write + 1

        ::continue::
    end

    for i = count, write, -1 do
        entries[i] = nil
    end
end

return M
