-- G1R Mage Balance — trader stock module
-- =============================================================================
-- Adds spell runes to a trader's LIVE stock, optionally gated by story chapter.
-- Separate from the spell-balance logic; required + driven by main.lua.
--
-- HOW IT WORKS (same technique proven by Rich Merchants / NoviceWaterMage):
--   * The live traders are TraderConfig objects in
--     FindFirstOf("TraderManager").m_InstancedTraders. FindFirstOf is a single-
--     class lookup, safe on this build (no global object-array scans, which crash).
--   * Each TraderConfig holds m_Items (a TMap item-class -> amount) = its CURRENT,
--     displayed stock. We add with  m_Items:Add(itemClass, amount).
--   * Traders are matched by a substring of their m_UniqueName (e.g. "Cronos"
--     matches "NC_KDW_Cronos_604").
--   * Current chapter is read from the live GameStory instance's Chapter field
--     (FindFirstOf("GameStory").Chapter) — a plain int read, crash-safe. An entry
--     applies only when currentChapter >= entry.chapter.
--
-- IDEMPOTENT: an entry is added only if that rune isn't already in the trader's
-- stock, so re-applying never duplicates and never fights the game's native stock.
-- Runtime-only; the trader's live stock is rebuilt each load, so main.lua re-runs
-- apply() on every load (ClientRestart) and on live chapter change.
-- =============================================================================

local log = require("lib.log")

local M = {}

-- ---- helpers (self-contained; mirror main.lua's conventions) -----------------
local function valid(o)
    if o == nil then return false end
    local ok, r = pcall(function() return o:IsValid() end)
    return ok and r == true
end
local function full_name(o)
    local ok, n = pcall(function() return o:GetFullName() end)
    return (ok and type(n) == "string") and n or "<unknown>"
end
local function unwrap(p)
    if p == nil then return nil end
    local ok, o = pcall(function() return p:get() end)
    return (ok and o ~= nil) and o or p
end

-- Resolve a rune item to its UClass (the key m_Items:Add expects).
local function rune_class(runeName)
    local c = StaticFindObject("/Script/Angelscript." .. runeName)
    if valid(c) then return c end
    local d = StaticFindObject("/Script/Angelscript.Default__" .. runeName)
    if valid(d) then
        local cls; if pcall(function() cls = d:GetClass() end) and valid(cls) then return cls end
    end
    return nil
end

-- ---- current chapter ---------------------------------------------------------
-- Read from the live GameStory instance's Chapter int (crash-safe field read).
-- Returns a number, or nil if the story isn't loaded yet (caller should retry).
function M.current_chapter()
    if type(FindFirstOf) ~= "function" then return nil end
    local ok, story = pcall(FindFirstOf, "GameStory")
    if not (ok and valid(story)) then return nil end
    local ch
    if pcall(function() ch = story.Chapter end) and type(ch) == "number" then
        return ch
    end
    return nil
end

-- ---- apply -------------------------------------------------------------------
-- Add every eligible TraderStock entry to its trader's live m_Items.
-- entries: array of { rune=, trader=, chapter=, amount= }.
-- Returns true once every eligible entry is confirmed present (so a startup retry
-- loop can stop). Entries gated to a future chapter are treated as "satisfied for
-- now" (they're not pending — they'll apply when that chapter is reached).
function M.apply(entries)
    if type(entries) ~= "table" or #entries == 0 then return true end

    if type(FindFirstOf) ~= "function" then return false end
    local ok, tm = pcall(FindFirstOf, "TraderManager")
    if not (ok and valid(tm)) then return false end          -- not ready -> retry
    local arr; pcall(function() arr = tm.m_InstancedTraders end)
    if arr == nil then return false end

    local chapter = M.current_chapter()                       -- may be nil (retry)

    -- snapshot the live trader list once
    local traders = {}
    pcall(function() arr:ForEach(function(_, ep)
        local cfg = unwrap(ep); if valid(cfg) then traders[#traders + 1] = cfg end
    end) end)
    if #traders == 0 then return false end                    -- not populated -> retry

    local allDone = true
    for _, e in ipairs(entries) do
        if type(e) == "table" and e.enabled ~= false and e.rune and e.trader then
            local minCh = tonumber(e.chapter) or 1
            local gateOpen = (chapter ~= nil) and (chapter >= minCh)

            if chapter == nil and minCh > 1 then
                -- can't read chapter yet AND this entry is chapter-gated -> retry later
                allDone = false
            elseif gateOpen then
                -- find the matching trader(s) by unique-name substring
                local item = rune_class(e.rune)
                if not valid(item) then
                    allDone = false                            -- rune class not loaded yet
                else
                    local matchedAny, addedOrPresent = false, false
                    for _, cfg in ipairs(traders) do
                        local uname = ""
                        pcall(function() uname = cfg.m_UniqueName:ToString() end)
                        if uname:find(e.trader, 1, true) then
                            matchedAny = true
                            local has = false
                            pcall(function() cfg.m_Items:ForEach(function(k, _)
                                if full_name(unwrap(k)):find(e.rune, 1, true) then has = true end
                            end) end)
                            if has then
                                addedOrPresent = true
                            else
                                local amt = tonumber(e.amount) or 1
                                local okAdd = pcall(function() cfg.m_Items:Add(item, amt) end)
                                if okAdd then
                                    local nowHas = false
                                    pcall(function() cfg.m_Items:ForEach(function(k, _)
                                        if full_name(unwrap(k)):find(e.rune, 1, true) then nowHas = true end
                                    end) end)
                                    if nowHas then
                                        addedOrPresent = true
                                        log.info(string.format("[trader] %s += %s x%d (chapter %s >= %d)",
                                            e.trader, e.rune, amt, tostring(chapter), minCh))
                                    end
                                end
                            end
                        end
                    end
                    -- if the named trader isn't loaded this session, don't block forever
                    if matchedAny and not addedOrPresent then allDone = false end
                end
            end
            -- gate not yet open (chapter < minCh): nothing to do now, not pending
        end
    end
    return allDone
end

-- ---- status (read-only) ------------------------------------------------------
-- Log each entry's gate state + whether the rune is currently in the trader's stock.
function M.status(entries)
    log.info("==== trader stock status ====")
    local chapter = M.current_chapter()
    log.info("current chapter = " .. tostring(chapter))
    if type(entries) ~= "table" then log.info("  (no TraderStock entries)"); log.info("==== end ===="); return end

    local tm; do local ok, t = pcall(FindFirstOf, "TraderManager"); if ok then tm = t end end
    local arr; if valid(tm) then pcall(function() arr = tm.m_InstancedTraders end) end

    for _, e in ipairs(entries) do
        if type(e) == "table" and e.rune and e.trader then
            local minCh = tonumber(e.chapter) or 1
            local gate = (chapter ~= nil and chapter >= minCh) and "OPEN" or "closed"
            local present = false
            if arr ~= nil then
                pcall(function() arr:ForEach(function(_, ep)
                    local cfg = unwrap(ep); if not valid(cfg) then return end
                    local uname = ""; pcall(function() uname = cfg.m_UniqueName:ToString() end)
                    if uname:find(e.trader, 1, true) then
                        pcall(function() cfg.m_Items:ForEach(function(k, _)
                            if full_name(unwrap(k)):find(e.rune, 1, true) then present = true end
                        end) end)
                    end
                end) end)
            end
            log.info(string.format("  %-22s -> %-10s ch>=%d [%s] inStock=%s",
                e.rune, e.trader, minCh, gate, tostring(present)))
        end
    end
    log.info("==== end ====")
end

return M
