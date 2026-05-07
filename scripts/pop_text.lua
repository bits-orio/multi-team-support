-- scripts/pop_text.lua
-- Animated floating notifications: spawn_confirm, team_join, milestone, rip.
-- Easing, animation curves, and the per-tick update loop are in pop_text_tick.lua.

local admin_gui   = require("gui.admin")
local pop_tick    = require("scripts.pop_text_tick")

local pop_text = {}

-- ─── Storage ──────────────────────────────────────────────────────────

function pop_text.init_storage()
    storage.pop_texts = storage.pop_texts or {}
end

-- ─── Preset: spawn_confirm ────────────────────────────────────────────

-- Elastic pop + upward fade at the player's spawn position. Player-only.
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

-- ─── Preset: team_join ────────────────────────────────────────────────

-- Snap-in pop + upward jiggle. Player-only.
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

-- ─── Preset: milestone ────────────────────────────────────────────────

-- Comic elastic pop above every connected force member. Supports rich text.
-- Shadow is a four-corner dark copy for a subtle outline effect.
function pop_text.milestone(force, text_str)
    if not admin_gui.flag("popup_text_enabled") then return end
    pop_text.init_storage()
    local shadow_offsets = { {0.06, 0.06}, {-0.06, 0.06}, {0.06, -0.06}, {-0.06, -0.06} }

    for _, player in pairs(force.players) do
        if not player.connected then goto next_player end
        local surface = player.surface
        if not (surface and surface.valid) then goto next_player end

        local x, y = player.position.x, player.position.y - 5

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

-- ─── Preset: rip ──────────────────────────────────────────────────────

-- Fast explosive "RIP!" pop at the death position. Visible to all on the surface.
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

-- ─── Tick (re-exported from pop_text_tick) ────────────────────────────

pop_text.tick = pop_tick.tick

return pop_text
