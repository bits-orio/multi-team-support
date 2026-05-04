-- Multi-Team Support - settings.lua
-- Author: bits-orio
-- License: MIT
--
-- Startup settings for the mod. These are configured before the game starts
-- and cannot be changed during gameplay.

data:extend({
    {
        type = "int-setting",
        name = "mts_max_teams",
        setting_type = "startup",
        default_value = 20,
        minimum_value = 2,
        maximum_value = 20,
        order = "a-a",
    },
    {
        type = "string-setting",
        name = "mts_discord_url",
        setting_type = "runtime-global",
        default_value = "",
        allow_blank = true,
        order = "b-a",
    },
})
