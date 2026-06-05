-- gui/lfm_hint.lua
-- One-time toast shown to new team leaders who haven't enabled recruiting yet.
-- Auto-closes after DURATION_TICKS; also has a manual close button.

local M = {}

local FRAME_NAME     = "sb_lfm_hint_frame"
local DURATION_TICKS = 2 * 60 * 60  -- 2 minutes

-- ─── Show ─────────────────────────────────────────────────────────────

function M.show_for_leader(player)
    if not (player and player.valid and player.connected) then return end
    -- Skip if this team has already recruited at some point.
    local fn = player.force and player.force.name
    storage.lfm_ever_recruited = storage.lfm_ever_recruited or {}
    if storage.lfm_ever_recruited[fn] then return end

    if player.gui.screen[FRAME_NAME] then
        player.gui.screen[FRAME_NAME].destroy()
    end

    local frame = player.gui.screen.add{type = "frame", name = FRAME_NAME, direction = "vertical"}
    frame.location              = {x = 5, y = 65}
    frame.style.minimal_width   = 320
    frame.style.maximal_width   = 400

    -- ── Title row ───────────────────────────────────────────────────
    local title_row = frame.add{type = "flow", direction = "horizontal"}
    title_row.style.vertical_align      = "center"
    title_row.style.bottom_margin       = 4

    local title = title_row.add{
        type    = "label",
        caption = "[img=utility/custom_tag_icon]  Team Settings — Recruiting",
    }
    title.style.font                     = "default-bold"
    title.style.horizontally_stretchable = true

    title_row.add{type = "empty-widget"}.style.horizontally_stretchable = true

    title_row.add{
        type   = "sprite-button",
        name   = "sb_lfm_hint_close",
        sprite = "utility/close",
        style  = "close_button",
    }

    frame.add{type = "line"}

    -- ── Message ─────────────────────────────────────────────────────
    local msg = frame.add{type = "label"}
    msg.caption = "[img=utility/warning_icon]  Your team isn't recruiting yet!\n"
        .. "New players in the landing pen can't see it.\n"
        .. "Open [img=utility/custom_tag_icon] Team Settings → Recruiting\n"
        .. "and click \"Start recruiting\" to appear in their list."
    msg.style.single_line   = false
    msg.style.maximal_width = 380
    msg.style.top_margin    = 4
    msg.style.bottom_margin = 2

    -- ── Schedule auto-close ─────────────────────────────────────────
    storage.lfm_hint_close_tick = storage.lfm_hint_close_tick or {}
    storage.lfm_hint_close_tick[player.index] = game.tick + DURATION_TICKS
end

-- ─── Close ────────────────────────────────────────────────────────────

function M.close(player)
    if not (player and player.valid) then return end
    storage.lfm_hint_close_tick = storage.lfm_hint_close_tick or {}
    storage.lfm_hint_close_tick[player.index] = nil
    if player.connected and player.gui.screen[FRAME_NAME] then
        player.gui.screen[FRAME_NAME].destroy()
    end
end

-- ─── Tick (auto-close) ────────────────────────────────────────────────

-- Called every tick from events/ticks.lua. Destroys expired toast frames.
function M.tick(current_tick)
    if not (storage.lfm_hint_close_tick and next(storage.lfm_hint_close_tick)) then return end
    local done = {}
    for idx, close_tick in pairs(storage.lfm_hint_close_tick) do
        if current_tick >= close_tick then done[#done + 1] = idx end
    end
    for _, idx in ipairs(done) do
        storage.lfm_hint_close_tick[idx] = nil
        local player = game.get_player(idx)
        if player and player.valid and player.connected
           and player.gui.screen[FRAME_NAME] then
            player.gui.screen[FRAME_NAME].destroy()
        end
    end
end

return M
