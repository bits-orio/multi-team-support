-- Multi-Team Support - prototypes/styles.lua
-- GUI styles for the center-top chat mode switch (gui/chat_switch.lua) and
-- the translucent top-bar team chip (gui/hud_clock.lua).
--
-- Three segment-button styles: an active GLOBAL fill (green — the encouraged
-- default), an active TEAM fill (blue), and a shared dark inactive state that
-- only looks pressable on hover. Fills are the vanilla 9-slice button base
-- tinted (no new sprites); per-state font colors are why these must be
-- data-stage styles — runtime can only set the base font color.
--
-- The active segment uses the same set for default/hovered/clicked so it
-- doesn't invite a second click; select-not-cycle semantics live in the
-- runtime handler.

local styles = data.raw["gui-style"].default

-- HUD chip font: default-bold with a semi-transparent black border. Factorio
-- has no blurred text shadows; a soft-alpha border renders as a faint dark
-- halo — the closest available thing — keeping force-colored text readable
-- over bright terrain and busy bases behind the translucent panel.
data:extend({
    {
        type         = "font",
        name         = "mts-hud-bold",
        from         = "default-bold",
        size         = 14,
        border       = true,
        border_color = {r = 0, g = 0, b = 0, a = 0.6},
    },
})

-- Base positions of the vanilla button 9-slice on gui.png (core style.lua):
-- default {0,17}, hovered {34,17}, clicked {51,17}.
local function seg(pos, tint)
    return { base = { position = pos, corner_size = 8, tint = tint } }
end

local function active_segment(name, tint, font_color)
    styles[name] = {
        type   = "button_style",
        parent = "button",
        font   = "default-bold",
        width  = 88,
        height = 28,
        default_font_color = font_color,
        hovered_font_color = font_color,
        clicked_font_color = font_color,
        default_graphical_set = seg({0, 17}, tint),
        hovered_graphical_set = seg({0, 17}, tint),
        clicked_graphical_set = seg({0, 17}, tint),
    }
end

active_segment("mts_chat_seg_global_active",
    {r = 0.40, g = 0.85, b = 0.40}, {r = 0.05, g = 0.14, b = 0.05})
active_segment("mts_chat_seg_team_active",
    {r = 0.45, g = 0.72, b = 1.00}, {r = 0.03, g = 0.10, b = 0.16})

-- Shared translucent panel background: the vanilla frame base at partial
-- alpha, no drop shadow. Factorio tints are PREMULTIPLIED-alpha: rgb must be
-- scaled by a, or the panel renders washed-out/milky instead of dark glass.
local TRANSLUCENT_PANEL = {
    base = { position = {0, 0}, corner_size = 8,
             tint = {r = 0.45, g = 0.45, b = 0.45, a = 0.45} },
}

-- Minimal translucent panel for the top-bar team chip (gui/hud_clock.lua).
styles["mts_hud_chip_frame"] = {
    type   = "frame_style",
    parent = "frame",
    top_padding    = 1,
    bottom_padding = 2,
    left_padding   = 6,
    right_padding  = 6,
    graphical_set  = TRANSLUCENT_PANEL,
}

-- Same translucent panel for the center-top chat switch container.
styles["mts_chat_switch_frame"] = {
    type   = "frame_style",
    parent = "frame",
    padding       = 2,
    graphical_set = TRANSLUCENT_PANEL,
}

styles["mts_chat_seg_inactive"] = {
    type   = "button_style",
    parent = "button",
    font   = "default-bold",
    width  = 88,
    height = 28,
    default_font_color = {r = 0.58, g = 0.56, b = 0.51},
    hovered_font_color = {r = 0.87, g = 0.85, b = 0.80},
    clicked_font_color = {r = 0.87, g = 0.85, b = 0.80},
    default_graphical_set = seg({0, 17},  {r = 0.30, g = 0.29, b = 0.27}),
    hovered_graphical_set = seg({34, 17}, {r = 0.44, g = 0.42, b = 0.39}),
    clicked_graphical_set = seg({51, 17}, {r = 0.44, g = 0.42, b = 0.39}),
}
