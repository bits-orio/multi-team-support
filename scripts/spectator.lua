-- scripts/spectator.lua
-- Facade: re-exports all spectator API from sub-modules so callers keep
-- the same require path ("scripts.spectator").

local core   = require("scripts.spectator.core")
local ops    = require("scripts.spectator.ops")
local events = require("scripts.spectator.events")

local spectator = {}

-- Setup
spectator.init         = core.init
spectator.setup_force  = core.setup_force
spectator.init_storage = core.init_storage
spectator.track_home_zoom = core.track_home_zoom

-- State queries
spectator.is_spectating       = core.is_spectating
spectator.get_real_force      = core.get_real_force
spectator.get_effective_force = core.get_effective_force
spectator.get_target          = core.get_target
spectator.needs_spectator_mode = core.needs_spectator_mode
spectator.resolve_view_for    = core.resolve_view_for

-- Operations
spectator.enter           = ops.enter
spectator.exit            = ops.exit
spectator.exit_all_for_force = ops.exit_all_for_force
spectator.switch_target   = ops.switch_target
spectator.enter_from_remote = ops.enter_from_remote
spectator.enter_friend_view = ops.enter_friend_view

-- Event handlers
spectator.on_controller_changed    = events.on_controller_changed
spectator.on_player_changed_surface = events.on_player_changed_surface
spectator.on_friend_changed        = events.on_friend_changed
spectator.on_player_left           = events.on_player_left
spectator.on_player_joined         = events.on_player_joined

-- Chat
spectator.get_chat_prefix = events.get_chat_prefix

return spectator
