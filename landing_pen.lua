-- Solo Teams - landing_pen.lua
-- Author: bits-orio
-- License: MIT
--
-- A shared pre-game waiting surface ("Landing Pen") where all new players
-- land before spawning into the actual game.  Players see each other in the
-- pen and click "Spawn into game" when they're ready, so everyone can start
-- at roughly the same time.

local M = {}

-- ---------------------------------------------------------------------------
-- Layout constants
-- ---------------------------------------------------------------------------

local PEN_RADIUS   = 15   -- outer circle edge (hazard ring boundary)
local RING_INNER   = 12   -- hazard concrete begins at this radius
local SPAWN_RADIUS = 5    -- radius of the ring where players are placed
local MAX_SLOTS    = 8    -- number of evenly-spaced spawn positions

-- ---------------------------------------------------------------------------
-- Surface creation
-- ---------------------------------------------------------------------------

--- Create the landing-pen surface with a circular concrete floor.
--- The surface is void-like (no autoplace), always daytime, and tiled:
---   r ≤ RING_INNER            → refined-concrete
---   RING_INNER < r ≤ PEN_RADIUS → refined-hazard-concrete-left (warning ring)
---   r > PEN_RADIUS             → lab-dark-2 (dark void background)
local function get_or_create_surface()
    if game.surfaces["landing-pen"] then
        return game.surfaces["landing-pen"]
    end

    local surface = game.create_surface("landing-pen", {
        default_enable_all_autoplace_controls = false,
    })
    surface.always_day = true

    local EXTENT = PEN_RADIUS + 4
    surface.request_to_generate_chunks({x = 0, y = 0}, math.ceil(EXTENT / 32) + 2)
    surface.force_generate_chunk_requests()

    local tiles = {}
    for x = -EXTENT, EXTENT do
        for y = -EXTENT, EXTENT do
            local r = math.sqrt(x * x + y * y)
            local name
            if r <= RING_INNER then
                name = "refined-concrete"
            elseif r <= PEN_RADIUS then
                name = "refined-hazard-concrete-left"
            else
                name = "lab-dark-2"
            end
            tiles[#tiles + 1] = {name = name, position = {x, y}}
        end
    end
    surface.set_tiles(tiles, true)

    return surface
end

--- Map a 0-based slot index to a world position on the spawn ring.
local function get_spawn_position(slot)
    local angle = slot * (2 * math.pi / MAX_SLOTS)
    return {
        x = math.floor(SPAWN_RADIUS * math.cos(angle) + 0.5),
        y = math.floor(SPAWN_RADIUS * math.sin(angle) + 0.5),
    }
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Returns true when the player has not yet clicked "Spawn into game".
function M.is_in_pen(player)
    storage.spawned_players = storage.spawned_players or {}
    return not storage.spawned_players[player.index]
end

--- Place a player into the landing pen.
--- If the player is already on the pen surface the teleport is skipped
--- (they're already in position) and only the GUI is rebuilt.
--- The teleport is deferred one tick via storage.pending_pen_tp so it is
--- safe to call from on_player_created before the character is ready.
function M.place_player(player)
    local surface = get_or_create_surface()
    storage.pen_slots = storage.pen_slots or {}

    -- Assign a unique slot if not already assigned
    if not storage.pen_slots[player.index] then
        local used = {}
        for _, s in pairs(storage.pen_slots) do used[s] = true end
        local slot = 0
        while used[slot] do slot = slot + 1 end
        storage.pen_slots[player.index] = slot
    end

    if player.surface == surface then
        -- Already in the pen (reconnect or duplicate call) – just refresh GUI
        M.build_pen_gui(player)
        M.update_pen_gui_all()
    else
        -- Queue teleport for the next tick (character may not be ready yet)
        storage.pending_pen_tp = storage.pending_pen_tp or {}
        storage.pending_pen_tp[player.index] = {
            surface  = surface,
            position = get_spawn_position(storage.pen_slots[player.index]),
        }
    end
end

--- Process deferred pen teleports.  Must be called from an on_tick handler.
function M.process_pending_teleports()
    if not storage.pending_pen_tp then return end
    if not next(storage.pending_pen_tp) then return end
    local done = {}
    for player_index, tp in pairs(storage.pending_pen_tp) do
        local player = game.get_player(player_index)
        if player and player.valid and tp.surface and tp.surface.valid then
            player.teleport(tp.position, tp.surface)
            done[#done + 1] = player_index
        end
    end
    for _, idx in ipairs(done) do
        storage.pending_pen_tp[idx] = nil
    end
    if #done > 0 then
        -- Rebuild GUIs now that the teleports have fired
        for _, idx in ipairs(done) do
            local player = game.get_player(idx)
            if player and player.connected then
                M.build_pen_gui(player)
            end
        end
        M.update_pen_gui_all()
    end
end

--- Build (or rebuild) the Landing Pen GUI for one player.
function M.build_pen_gui(player)
    local screen = player.gui.screen
    storage.pen_gui_location = storage.pen_gui_location or {}

    if screen.sb_pen_frame then
        storage.pen_gui_location[player.index] = screen.sb_pen_frame.location
        screen.sb_pen_frame.destroy()
    end

    local frame = screen.add{
        type      = "frame",
        name      = "sb_pen_frame",
        direction = "vertical",
    }

    if storage.pen_gui_location[player.index] then
        frame.location = storage.pen_gui_location[player.index]
    else
        frame.auto_center = true
    end

    -- Title bar (draggable)
    local title_bar = frame.add{type = "flow", direction = "horizontal"}
    title_bar.style.vertical_align = "center"
    title_bar.drag_target = frame
    title_bar.add{type = "label", caption = "Landing Pen", style = "frame_title"}
    local spacer = title_bar.add{type = "empty-widget", style = "draggable_space_header"}
    spacer.style.horizontally_stretchable = true
    spacer.style.height = 24
    spacer.drag_target = frame

    -- Subtitle
    local sub = frame.add{type = "label", caption = "Wait here, then spawn when ready."}
    sub.style.top_margin    = 6
    sub.style.bottom_margin = 4
    sub.style.left_margin   = 4

    -- In-pen player list
    local pen_surface = game.surfaces["landing-pen"]
    if pen_surface then
        local in_pen = {}
        for _, p in pairs(game.players) do
            if p.surface == pen_surface then
                in_pen[#in_pen + 1] = p
            end
        end
        if #in_pen > 0 then
            local hdr = frame.add{type = "label", caption = "In the pen:"}
            hdr.style.font        = "default-bold"
            hdr.style.left_margin = 4
            hdr.style.top_margin  = 4
            for _, p in ipairs(in_pen) do
                local lbl = frame.add{type = "label", caption = "  \xE2\x80\xA2 " .. p.name}
                lbl.style.left_margin = 4
                if p.index == player.index then
                    lbl.style.font_color = {1, 1, 0.6}
                elseif p.connected then
                    lbl.style.font_color = p.chat_color
                else
                    lbl.style.font_color = {0.65, 0.65, 0.65}
                end
            end
        end
    end

    -- Already-spawned player list
    storage.spawned_players = storage.spawned_players or {}
    local spawned_list = {}
    for idx in pairs(storage.spawned_players) do
        local p = game.get_player(idx)
        if p then spawned_list[#spawned_list + 1] = p.name end
    end
    if #spawned_list > 0 then
        table.sort(spawned_list)
        local hdr = frame.add{type = "label", caption = "Already spawned:"}
        hdr.style.font        = "default-bold"
        hdr.style.left_margin = 4
        hdr.style.top_margin  = 6
        for _, name in ipairs(spawned_list) do
            local lbl = frame.add{type = "label", caption = "  \xE2\x80\xA2 " .. name}
            lbl.style.font_color = {0.5, 0.5, 0.5}
            lbl.style.left_margin = 4
        end
    end

    -- Spawn button
    frame.add{type = "line"}.style.top_margin = 6
    local btn = frame.add{
        type    = "button",
        name    = "sb_spawn_btn",
        caption = "Spawn into game",
        style   = "confirm_button",
    }
    btn.style.top_margin              = 4
    btn.style.bottom_margin           = 2
    btn.style.horizontally_stretchable = true
end

--- Rebuild the Landing Pen GUI for every connected player currently in the pen.
function M.update_pen_gui_all()
    local surface = game.surfaces["landing-pen"]
    if not surface then return end
    for _, player in pairs(game.players) do
        if player.connected and player.surface == surface then
            M.build_pen_gui(player)
        end
    end
end

--- Mark the player as spawned, release their pen slot, and destroy the GUI.
--- Does NOT teleport — caller is responsible for moving the player.
function M.finish_spawn(player)
    storage.spawned_players       = storage.spawned_players or {}
    storage.spawned_players[player.index] = true

    if storage.pen_slots then
        storage.pen_slots[player.index] = nil
    end

    if player.gui.screen.sb_pen_frame then
        player.gui.screen.sb_pen_frame.destroy()
    end

    -- Update GUI for players still waiting in the pen
    M.update_pen_gui_all()
end

return M
