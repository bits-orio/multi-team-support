-- scripts/locale_audit.lua
-- /mts-debug locale: runtime missing-key detector (docs/locale/PLAN.md §6.2).
--
-- Requests a translation of every mts-* key — from the generated manifest
-- scripts/locale_keys.lua, since the control stage cannot read cfg files —
-- for the invoking player, and reports any the engine cannot resolve
-- (what players would see as "Unknown key: '...'"). Catches typo'd or
-- mis-sectioned keys against the player's actual runtime locale merge.
--
-- Scope note: a key missing from a non-English locale but present in en
-- falls back to en and still resolves, so this does NOT measure per-language
-- completeness — that is a static cfg-set comparison for the phase-2
-- tooling. Output stays English (debug surface, locale policy).

local KEYS = require("scripts.locale_keys")

local M = {}

function M.start(player)
    if storage.locale_audit then
        -- Self-healing: a previous audit whose requester disconnected before
        -- every on_string_translated arrived would otherwise block forever.
        player.print("[mts-debug] Discarding a previous unfinished locale audit.")
        storage.locale_audit = nil
    end
    local requests = {}
    for i, key in ipairs(KEYS) do requests[i] = {key} end
    local ids = player.request_translations(requests)
    if not ids then
        player.print("[mts-debug] request_translations did nothing — player not connected?")
        return
    end
    local pending = {}
    for i, id in ipairs(ids) do pending[id] = KEYS[i] end
    storage.locale_audit = {
        pending      = pending,
        remaining    = #ids,
        failures     = {},
        player_index = player.index,
    }
    player.print("[mts-debug] Locale audit: requested " .. #ids
        .. " keys for locale '" .. player.locale .. "'...")
end

local function on_string_translated(event)
    local audit = storage.locale_audit
    if not audit then return end
    local key = audit.pending[event.id]
    if not key then return end  -- someone else's request_translation traffic
    audit.pending[event.id] = nil
    audit.remaining = audit.remaining - 1
    if not event.translated then
        audit.failures[#audit.failures + 1] = key
    end
    if audit.remaining > 0 then return end

    storage.locale_audit = nil
    local player = game.get_player(audit.player_index)
    if not (player and player.valid) then return end
    if #audit.failures == 0 then
        player.print("[mts-debug] Locale audit passed: all " .. #KEYS
            .. " mts-* keys resolve for locale '" .. player.locale .. "'.")
    else
        player.print("[mts-debug] Locale audit: " .. #audit.failures
            .. " of " .. #KEYS .. " keys FAILED to resolve:\n  "
            .. table.concat(audit.failures, "\n  "))
    end
end

function M.register()
    script.on_event(defines.events.on_string_translated, on_string_translated)
end

return M
