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
        -- Space Age requires planet variants to be pre-created per team, capping at 20.
        -- Without Space Age the only limit is Factorio's 64-force hard cap minus the
        -- 4 reserved forces (player, enemy, neutral, spectator), leaving 60 slots.
        maximum_value = mods["space-age"] and 20 or 60,
        order = "a-a",
    },
    {
        type = "string-setting",
        name = "mts_discord_url",
        setting_type = "runtime-global",
        default_value = "https://discord.gg/tWz4FT74pH",
        allow_blank = true,
        order = "b-a",
    },
})
