-- Multi-Team Support - data.lua
-- Author: bits-orio
-- License: MIT
--
-- Custom sprites for the welcome GUI.
-- Pattern follows RedMew (redmew-data): type="sprite", flags={"not-compressed"},
-- mipmap_count matching the pre-built horizontal mipmap sprite sheet.
--
--   sb-discord  - 847x128 Discord logo with text     -> graphics/Discord_Logo_Blurple_PMS.png
--   sb-qr-code  - 504x256 mipmap sheet (base 256x256) -> graphics/qr-code.png
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
})
