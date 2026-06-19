-- Multi-Team Support - data.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- Custom sprites for the welcome GUI.
-- Pattern follows RedMew (redmew-data): type="sprite", flags={"not-compressed"},
-- mipmap_count matching the pre-built horizontal mipmap sprite sheet.
--
--   sb-discord    - 847x128 Discord logo with text     -> graphics/Discord_Logo_Blurple_PMS.png
--   sb-qr-code    - 504x256 mipmap sheet (base 256x256) -> graphics/qr-code.png
--   sb-legendary  - 64x64 legendary starburst           -> graphics/legendary.png
--
-- Regenerate with: python tools/gen_qr_matrix.py "https://discord.gg/URL" --png

data:extend({
    {
        type          = "sprite",
        name          = "sb-discord",
        filename      = "__multi-team-support__/graphics/Discord_Logo_Blurple_PMS.png",
        size          = {847, 128},
        flags         = {"not-compressed"},
    },
    {
        type          = "sprite",
        name          = "sb-qr-code",
        filename      = "__multi-team-support__/graphics/qr-code.png",
        size          = 256,
        mipmap_count  = 6,
        flags         = {"not-compressed"},
    },
    {
        type          = "sprite",
        name          = "sb-legendary",
        filename      = "__multi-team-support__/graphics/legendary.png",
        size          = 64,
        flags         = {"not-compressed", "gui-icon"},
    },
})

-- Hidden passive radar that consumer mods place via mts-v1 `ensure_passive_radar`
-- to keep empty team surfaces live-viewable for spectators. See the file header.
require("prototypes.entities.passive-radar")
