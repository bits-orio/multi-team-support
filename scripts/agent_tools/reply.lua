-- Multi-Team Support - scripts/agent_tools/reply.lua
-- Author: bits-orio
-- License: MIT
--
-- How an agent tool's reply has to look to reach the model whole. AI Agent
-- Bridge's service cuts any tool result past 4096 bytes of JSON and appends
-- a note, which hands the model broken JSON; its companion refuses a reply
-- past 8000 bytes outright. So a list that grows with the server is cut
-- here, by bytes, and says how many rows it shows of how many. And the
-- engine's JSON writer prints any non-integer double at full precision,
-- fifty digits of 0.79, so a fraction leaves as a short string instead.
--
-- Deliberately no `local helpers` here: size() needs the engine's own
-- helpers.table_to_json, which MTS's scripts.helpers would shadow.

local M = {}

local TICKS_PER_HOUR = 60 * 60 * 60

--- The bridge service's default cut on one tool result
--- (DefaultMaxToolResultBytes in its service/internal/agent/agent.go).
M.SERVICE_CUT = 4096

--- What fit() lets a whole reply encode to. Below SERVICE_CUT, so a reply
--- that only just fits still reaches the model as whole JSON.
M.BUDGET = 3900

--- Caller text a reply repeats back, such as a force or player name that
--- matched nothing, is clipped to this many bytes. The bridge sends a call's
--- arguments as they came, so without it a long argument could carry its
--- reply past the cut.
M.ECHO_BYTES = 64

--- Hours to two decimals, as the short string "1.79" (or the number 2 for a
--- whole one): the engine's JSON writer prints any non-integer double at
--- full precision, which the reply's reader would have to wade through.
function M.hours(ticks)
    if not ticks then return nil end
    local rounded = math.floor(ticks / TICKS_PER_HOUR * 100 + 0.5) / 100
    if rounded == math.floor(rounded) then return math.floor(rounded) end
    return (string.format("%.2f", rounded):gsub("0+$", ""))
end

--- A caller's row limit clamped to 1..max, `default` when it is missing or
--- not a number.
function M.limit(value, default, max)
    local n = math.floor(tonumber(value) or default)
    if n < 1 then n = 1 end
    if n > max then n = max end
    return n
end

--- The first n rows, in the order they are already in.
function M.cut(rows, n)
    local out = {}
    for i = 1, math.min(n, #rows) do out[i] = rows[i] end
    return out
end

--- Caller text as a reply may repeat it: at most ECHO_BYTES, cut where a
--- character ends so the JSON stays valid UTF-8. Anything not a string is
--- returned as it is.
function M.echo(text)
    if type(text) ~= "string" or #text <= M.ECHO_BYTES then return text end
    local keep = M.ECHO_BYTES
    -- A byte of the form 10xxxxxx continues the character before it.
    while keep > 0 and text:byte(keep + 1) >= 0x80 and text:byte(keep + 1) < 0xC0 do
        keep = keep - 1
    end
    return text:sub(1, keep)
end

--- Bytes of JSON the service sees for this reply: the companion encodes it
--- inside { ok = true, r = <reply> }, and the service cuts the `r` part.
function M.size(r)
    return #helpers.table_to_json(r)
end

--- The reply build(shown) makes from the most leading rows that keep the
--- WHOLE reply inside BUDGET. Measuring the whole reply rather than the rows
--- alone means the fields around the rows can never push it over. build
--- receives the rows that survive and returns the full reply, so it can say
--- how many it shows. Binary search: about seven encodes, not one per row.
function M.fit(rows, build)
    local function fits(n) return M.size(build(M.cut(rows, n))) <= M.BUDGET end
    if fits(#rows) then return build(rows) end
    local low, high = 0, #rows
    while low < high do
        local mid = math.floor((low + high + 1) / 2)
        if fits(mid) then low = mid else high = mid - 1 end
    end
    return build(M.cut(rows, low))
end

return M
