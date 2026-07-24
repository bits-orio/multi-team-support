-- Multi-Team Support - settings.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- Startup settings for the mod. These are configured before the game starts
-- and cannot be changed during gameplay.

data:extend({
    {
        type = "int-setting",
        name = "mts_max_teams",
        setting_type = "startup",
        -- Space Age requires planet variants to be pre-created per team, capping at 20.
        -- Without Space Age the only limit is Factorio's 64-force hard cap minus the
        -- 4 reserved forces (player, enemy, neutral, spectator), leaving 60 slots.
        -- Default to the ceiling in both modes. Only affects installs where the
        -- admin never stored a value; existing servers keep their saved setting.
        default_value = mods["space-age"] and 20 or 60,
        minimum_value = 2,
        maximum_value = mods["space-age"] and 20 or 60,
        order = "a-a",
    },
    {
        -- Passivize radars: keep their local reveal, drop the wide rotating
        -- sector scan that permanently charts chunks; the base-game radar also
        -- drops to 50 kW (modded radars keep their own power cost). On a
        -- multi-team server every team carpets its territory with radars, and
        -- each active radar charts a ~14-chunk-radius disc forever -- the union
        -- across 20 teams is a major save-size / UPS sink. Startup because
        -- reveal distances are immutable prototype fields (no runtime toggle is
        -- possible). Implemented in prototypes/entities/passivize-radars.lua
        -- (data-final-fixes).
        type = "bool-setting",
        name = "mts_passive_radars",
        setting_type = "startup",
        default_value = true,
        order = "a-b",
    },
    {
        type = "string-setting",
        name = "mts_discord_url",
        setting_type = "runtime-global",
        default_value = "https://discord.gg/tWz4FT74pH",
        allow_blank = true,
        order = "b-a",
    },
    {
        -- Only consulted when ClaustOrephobic (zzz-claustorephobic) is active:
        -- how far out (in tiles, diagonally from spawn) the guaranteed spawn
        -- crude-oil node is placed. 64 tiles = about 2 chunks.
        type = "int-setting",
        name = "mts_claust_oil_distance_tiles",
        setting_type = "runtime-global",
        default_value = 64,
        minimum_value = 0,
        maximum_value = 1024,
        order = "b-b",
    },
})
