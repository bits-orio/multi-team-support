-- Multi-Team Support - shadow_race/gui/chip.lua
-- Author: bits-orio
-- License: MIT
--
-- Shadow Race inside the team clock chip: a small button that opens the
-- picker, and under the clock a split line ("3:10 ahead of Team Red") for
-- a team that is chasing a shadow.
--
-- Driven by gui/hud_clock.lua's update_player, so it inherits every call
-- site that already keeps the team clock right (join, force change, the
-- one-second pass). A player off a team has no chip at all; a server with
-- the flag off has neither element.

local rivals   = require("shadow_race.rivals")
local recorder = require("shadow_race.recorder")

local M = {}

M.BUTTON = "mts_shadow_btn"
local TEXT = "mts_shadow_split"

--- "3:10" or "1:02:45".
function M.fmt(ticks)
    local s = math.floor(math.abs(ticks) / 60)
    local h = math.floor(s / 3600); s = s % 3600
    local m = math.floor(s / 60);   s = s % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%d:%02d", m, s)
end

--- A split as text: "level", "3:10 ahead" or "3:10 behind", with a final
--- split (past the end of an archived run) marked as such. nil gap reads
--- "no split yet".
function M.split_caption(gap, final)
    if not gap then return {"mts-gui.shadow-gap-none"} end
    local text
    if math.abs(gap) < 60 then text = {"mts-gui.shadow-gap-level"}
    elseif gap > 0 then text = {"mts-gui.shadow-gap-ahead", M.fmt(gap)}
    else text = {"mts-gui.shadow-gap-behind", M.fmt(gap)} end
    if final then return {"mts-gui.shadow-gap-final", text} end
    return text
end

--- The chip's caption for a team, or nil when it is chasing nothing.
local function caption(force_name)
    local standing = rivals.standing(force_name)
    if not standing then return nil end
    -- Auto-chase with nothing ahead of the team.
    if not standing.label then return {"mts-gui.shadow-leading"} end
    if not standing.gap then return {"mts-gui.shadow-chasing", standing.label} end
    return {"mts-gui.shadow-split", M.split_caption(standing.gap, standing.final), standing.label}
end

--- Create, update or remove the player's Shadow Race button and split
--- line. `root` is the team clock chip (gui/hud_clock.lua) and `row` its
--- name-and-clock row; force_name is the player's team. Both live inside
--- the chip, so the top bar grows by nothing: a wider bar slides the clock
--- under the centred chat switch on a narrow window.
function M.update_player(player, force_name, root, row)
    local button, line = row[M.BUTTON], root[TEXT]
    -- No run yet under Staged Start: nothing to compare until the clock runs.
    if not (rivals.enabled() and recorder.run_of(force_name)) then
        if button then button.destroy() end
        if line then line.destroy() end
        return
    end

    if not button then
        row.add{
            type = "sprite-button", name = M.BUTTON, sprite = "utility/clock",
            tooltip = {"mts-tip.shadow-button"}, style = "frame_action_button",
            index = 1,  -- left of the name: the row's right end meets the chat switch
        }
    end

    local text = not rivals.is_hidden(player.index) and caption(force_name) or nil
    if not text then
        if line then line.destroy() end
        return
    end
    if not line then
        line = root.add{type = "label", name = TEXT, tooltip = {"mts-tip.shadow-chip"}}
        line.style.font = "default-small-semibold"
    end
    line.caption = text
end

return M
