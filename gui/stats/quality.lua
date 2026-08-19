-- gui/stats/quality.lua
-- Quality-chain discovery for the production stats GUI.
--
-- The chain MUST be walked via .next from "normal" -- both obvious
-- alternatives fail on real modpacks (measured, see
-- docs/PRODUCTION_STATS_PROBES.md):
--   * level-sort: levels run 0,1,2,3,5,6,7,8,10 with Quality-Plus-Plus
--     (gaps at 4/9), and the unreachable "quality-unknown" placeholder
--     also reports level 0, tying with normal.
--   * hidden-filter: base ships normal.hidden = true (the quality mod
--     flips it back), so a base-only install would drop "normal" itself.
-- The walk also excludes quality-unknown for free: nothing links to it.

local M = {}

-- Rebuilt each script load (prototype set is fixed per load; a mod change
-- reloads control.lua, so no storage cache or invalidation is needed).
local chain_cache = nil

--- Ordered quality names, walking .next from "normal". The docs declare
--- .next non-optional but it is genuinely nil-terminated -- `while q do`
--- is the correct loop, never `while q.next do`.
function M.chain()
    if chain_cache then return chain_cache end
    local out, seen = {}, {}
    local q = prototypes.quality["normal"]
    while q and not seen[q.name] do
        seen[q.name] = true
        out[#out + 1] = q.name
        q = q.next
    end
    -- A pack without a "normal" prototype is out-of-contract for the base
    -- game; fall back to a bare normal so statistics reads stay callable.
    if #out == 0 then out[1] = "normal" end
    chain_cache = out
    return chain_cache
end

--- True when the quality axis is worth surfacing at all: feature flag on
--- and more than one quality in the chain. Base-only installs get false
--- and the panel renders exactly as it always did.
function M.multi_enabled()
    return script.feature_flags.quality and #M.chain() > 1
end

return M
