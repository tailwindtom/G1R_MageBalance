-- G1R Mage Balance — UE4SS Lua mod for Gothic 1 Remake
-- =============================================================================
-- Rebalances mage spell damage by editing each spell's projectile-definition CDO
-- directly, the same way NoviceWaterMage does (credit to its author for proving
-- the technique):
--
--   * Get the CDO via  StaticFindObject("/Script/Angelscript.Default__<Name>")
--     — the "Default__" object IS the class-default object (FindAllOf skips these).
--   * Base damage lives in  m_DamageBase  (a TMap keyed by the damage-type tag).
--     Read with  v:get(), write with  v:set(x)  on the ForEach value param.
--   * Per-circle scaling lives in  m_DamageMagicCircleProgression :
--       Map{ tag -> { m_DamageByMagicCircle : Array of { m_CircleTag, m_Damage } } }
--     Array index 1 = 2nd circle, 2 = 4th, 3 = 6th. Write  e:get().m_Damage = x.
--   * NEVER touch the map KEY (the FGameplayTag) — reading it (:get()/:ToString())
--     raises an uncatchable C++ error. We only ever use the value.
--
-- Per spell we snapshot the VANILLA values once, then write vanilla x factor, so
-- re-applying never stacks (idempotent). Runtime-only; reverts on game close.
-- Config: config.lua -> Spells (one readable block per spell).
-- =============================================================================

local config = require("config")
local log = require("lib.log")
local traderstock = require("lib.traderstock")

-- ---- helpers ----------------------------------------------------------------
local function valid(o)
    if o == nil then return false end
    local ok, r = pcall(function() return o:IsValid() end)
    return ok and r == true
end
local function full_name(o)
    local ok, n = pcall(function() return o:GetFullName() end)
    return (ok and type(n) == "string") and n or "<unknown>"
end
local function class_name(o)
    local ok, c = pcall(function() return o:GetClass():GetFName():ToString() end)
    return (ok and type(c) == "string") and c or "?"
end
local function unwrap(p)  -- only for hook params (RemoteUnrealParam), never for plain object fields
    if p == nil then return nil end
    local ok, o = pcall(function() return p:get() end)
    return (ok and o ~= nil) and o or p
end
local function dbg(msg) if config.DebugSteps == true then log.info("[DBG] " .. tostring(msg)) end end

local function run_later(ms, fn)
    if type(ExecuteWithDelay) == "function" then ExecuteWithDelay(ms, fn) else fn() end
end
local function on_game_thread(fn)
    if type(ExecuteInGameThread) == "function" then ExecuteInGameThread(fn) else fn() end
end

-- =============================================================================
-- Damage read / write on a projectile-definition CDO
-- =============================================================================

-- Read vanilla damage: base (number) + per-circle values [1]=c2,[2]=c4,[3]=c6.
-- m_DamageBase value can be a plain float (v:get() -> number) or a struct holding
-- m_Damage; we detect which so we can write it back the same way.
local function read_damage(cdo)
    local base, baseKind
    pcall(function()
        cdo.m_DamageBase:ForEach(function(_, v)
            if base ~= nil then return end
            local raw = v:get()
            if type(raw) == "number" then
                base, baseKind = raw, "num"
            else
                local d; if pcall(function() d = raw.m_Damage end) and type(d) == "number" then
                    base, baseKind = d, "struct"
                end
            end
        end)
    end)
    local circles = {}
    pcall(function()
        cdo.m_DamageMagicCircleProgression:ForEach(function(_, v)
            local arr; pcall(function() arr = v:get().m_DamageByMagicCircle end)
            if arr ~= nil then
                arr:ForEach(function(idx, e)
                    local d; pcall(function() d = e:get().m_Damage end)
                    if type(d) == "number" then circles[idx] = d end
                end)
            end
        end)
    end)
    return base, baseKind, circles
end

local function write_damage(cdo, base, baseKind, circles)
    if type(base) == "number" then
        pcall(function()
            cdo.m_DamageBase:ForEach(function(_, v)
                if baseKind == "num" then
                    v:set(base)
                else
                    pcall(function() v:get().m_Damage = base end)
                end
            end)
        end)
    end
    if circles then
        pcall(function()
            cdo.m_DamageMagicCircleProgression:ForEach(function(_, v)
                local arr; pcall(function() arr = v:get().m_DamageByMagicCircle end)
                if arr ~= nil then
                    arr:ForEach(function(idx, e)
                        if type(circles[idx]) == "number" then
                            pcall(function() e:get().m_Damage = circles[idx] end)
                        end
                    end)
                end
            end)
        end)
    end
end

-- =============================================================================
-- Apply
-- =============================================================================
-- Per-CDO vanilla snapshot, persisted across the session so re-applying always
-- computes vanilla x factor (never stacks). Hot-reload is off on this build.
local vanilla = _G.__MB_vanilla or {}
_G.__MB_vanilla = vanilla

-- After the first apply pass we go silent: re-applies (on level/chapter load, and
-- on open-world streaming events) must NOT spam the log — logging every time caused
-- hard frame stutter / freezes for players. CDO edits persist, so re-applies only
-- re-assert the same values; there's nothing useful to log on them.
local quiet = false

local function cdo_for(defName)
    return StaticFindObject("/Script/Angelscript.Default__" .. defName)
end

-- Some spells have one definition per RUNE LEVEL (e.g. FireBallProjectileDefinition_Lvl1
-- / _Lvl2 / _Lvl3). A config key uses the BASE name; we apply to the base CDO and
-- every _LvlN variant that exists, so all upgrade levels are balanced by one entry.
local function def_variants(defName)
    return {
        defName,
        defName .. "_Lvl1", defName .. "_Lvl2", defName .. "_Lvl3", defName .. "_Lvl4",
        -- Chain Lightning has no _LvlN; its player CDOs are these instead:
        defName .. "_Base", defName .. "_WithParalysis", defName .. "_WithoutParalysis",
    }
end

-- Apply a damage spec to one concrete CDO (snapshots vanilla once, idempotent).
-- damage is either a NUMBER (multiplier on vanilla) or a TABLE { base,c2,c4,c6 }
-- of ABSOLUTE values (omitted entries keep vanilla). label = readable spell name.
local function apply_def(cdo, name, damage, label)
    local key = full_name(cdo)
    if vanilla[key] == nil then
        local b, bk, c = read_damage(cdo)
        vanilla[key] = { base = b, baseKind = bk, circles = c }
        dbg(string.format("snapshot %s base=%s circles=%s/%s/%s", name,
            tostring(b), tostring(c[1]), tostring(c[2]), tostring(c[3])))
    end
    local v = vanilla[key]
    local nb, nc
    if type(damage) == "table" then
        -- absolute values; nil entries keep vanilla
        nb = (damage.base ~= nil) and damage.base or v.base
        nc = { damage.c2 or v.circles[1], damage.c4 or v.circles[2], damage.c6 or v.circles[3] }
    else
        local factor = tonumber(damage) or 1.0
        if factor == 1.0 then return end   -- nothing to change
        nb = (type(v.base) == "number") and (v.base * factor) or nil
        nc = {}
        for i, cv in pairs(v.circles) do nc[i] = cv * factor end
    end
    write_damage(cdo, nb, v.baseKind, nc)
    if not quiet then
        log.info(string.format("applied %-12s %-30s base %s->%s  c2/4/6 ->%s/%s/%s",
            tostring(label or ""), name, tostring(v.base), tostring(nb),
            tostring(nc[1]), tostring(nc[2]), tostring(nc[3])))
    end
end

-- Set plain numeric/bool fields directly on a CDO (absolute values, idempotent —
-- no vanilla snapshot needed). For non-damage tweaks: AoE area, lifetime, speed,
-- rain pattern, etc. Only assigns scalar values; never touches maps/structs.
local function apply_fields(cdo, fields, name)
    for fieldName, value in pairs(fields) do
        local before, ok
        pcall(function() before = cdo[fieldName] end)
        ok = pcall(function() cdo[fieldName] = value end)
        local after; pcall(function() after = cdo[fieldName] end)
        if ok and after ~= nil then
            if not quiet then log.info(string.format("  field %s.%s  %s -> %s", name, fieldName, tostring(before), tostring(after))) end
        elseif not quiet then
            log.warn(string.format("  field %s.%s set FAILED (before=%s)", name, fieldName, tostring(before)))
        end
    end
end

-- Apply one spell entry (class + damage + optional fields) to every matching CDO
-- (base + _LvlN). Returns true if at least one CDO was found.
local function apply_spell(class, damage, fields, label)
    local foundAny = false
    for _, name in ipairs(def_variants(class)) do
        local cdo = cdo_for(name)
        if valid(cdo) then
            foundAny = true
            apply_def(cdo, name, damage, label)
            if type(fields) == "table" then pcall(apply_fields, cdo, fields, name) end
        end
    end
    return foundAny
end

-- ---- cast time + mana cost (a SEPARATE object: the spell's USpellConfig) -----
-- Named by the block's `spellConfig` key. Values live in m_SpellLevels (array of
-- FSpellLevelRange{ CastTime, CastManaCost, ManaCostSc }, one per spell level).
-- We snapshot vanilla once, then write vanilla×factor (number) or absolute
-- per-level values (table). Idempotent. Array elements written via e:get() —
-- the same safe path as the per-circle damage progression.
local function read_levels_raw(cfg)
    local out = {}
    pcall(function()
        cfg.m_SpellLevels:ForEach(function(idx, e)
            local t = {}
            pcall(function() t.mana = e:get().CastManaCost end)
            pcall(function() t.cast = e:get().CastTime end)
            pcall(function() t.sc = e:get().ManaCostSc end)   -- per-repeat/hold cost (Firebolt etc.)
            out[idx] = t
        end)
    end)
    return out
end
-- spec: NUMBER = factor on vanilla; TABLE = absolute per level (spec[idx]).
-- Returns nil to keep vanilla (factor 1.0, or no absolute entry for that level).
local function level_target(spec, idx, vanillaVal)
    if type(spec) == "table" then return spec[idx] end
    local f = tonumber(spec) or 1.0
    if f == 1.0 then return nil end
    return (type(vanillaVal) == "number") and (vanillaVal * f) or nil
end
local function apply_spellcfg(spell, label)
    local cfgName = spell.spellConfig
    if not cfgName or (spell.mana == nil and spell.cast == nil) then return true end
    local cdo = cdo_for(cfgName)
    if not valid(cdo) then return false end
    local key = full_name(cdo)
    if vanilla[key] == nil then vanilla[key] = { levels = read_levels_raw(cdo) } end
    local van = vanilla[key].levels or {}
    pcall(function()
        cdo.m_SpellLevels:ForEach(function(idx, e)
            if spell.mana ~= nil then
                local t = level_target(spell.mana, idx, van[idx] and van[idx].mana)
                if type(t) == "number" then pcall(function() e:get().CastManaCost = t end) end
                -- Repeatable spells (Firebolt, Ice Arrow, Pyrokinesis, Chain Lightning)
                -- charge ManaCostSc for EVERY shot after the first. Without this, only
                -- the first shot costs the new amount and repeats stay at vanilla. Only
                -- touch it when the spell actually uses it (vanilla > 0).
                local vsc = van[idx] and van[idx].sc
                if type(vsc) == "number" and vsc > 0 then
                    local tsc = level_target(spell.mana, idx, vsc)
                    if type(tsc) == "number" then pcall(function() e:get().ManaCostSc = tsc end) end
                end
            end
            if spell.cast ~= nil then
                local t = level_target(spell.cast, idx, van[idx] and van[idx].cast)
                if type(t) == "number" then pcall(function() e:get().CastTime = t end) end
            end
        end)
    end)
    if not quiet then
        log.info(string.format("applied %-12s %-30s mana=%s cast=%s", tostring(label or ""), cfgName,
            type(spell.mana) == "table" and "abs" or tostring(spell.mana),
            type(spell.cast) == "table" and "abs" or tostring(spell.cast)))
    end
    return true
end

-- ---- magic-circle learning cost (LP) ----------------------------------------
-- The LP a trainer charges to teach each circle lives on the GameplayEffect
-- Default__GE_Skill_Mage_Circle_<N> in its SPCost field. config.CircleCost:
--   number = same cost for all 6 circles (flat)
--   table  = per-circle absolute { c1, c2, c3, c4, c5, c6 }
--   nil    = leave vanilla (10/15/20/25/30/35)
-- Direct absolute write → idempotent, no snapshot needed.
-- (Mechanism discovered by Janys27pl, PR #1; extended here to per-circle.)
local function apply_circle_costs()
    local cc = config.CircleCost
    if cc == nil then return 0 end
    local pending = 0
    for i = 1, 6 do
        local cost = (type(cc) == "table") and cc[i] or cc
        if type(cost) == "number" then
            local cdo = cdo_for("GE_Skill_Mage_Circle_" .. i)
            if valid(cdo) then
                local before; pcall(function() before = cdo.SPCost end)
                if pcall(function() cdo.SPCost = cost end) then
                    if not quiet then log.info(string.format("circle %d SPCost %s -> %s", i, tostring(before), tostring(cost))) end
                end
            else
                pending = pending + 1
            end
        end
    end
    return pending
end

-- Apply every spell block in config.Spells. Returns true once all spells that
-- actually change something have been found (so the startup retry loop can stop).
local function apply_all()
    local pending = 0
    for niceName, spell in pairs(config.Spells or {}) do
        if type(spell) == "table" and spell.enabled ~= false then
            if spell.class then
                local found = apply_spell(spell.class, spell.damage, spell.fields, niceName)
                local changes = (spell.damage ~= nil and spell.damage ~= 1.0) or spell.fields ~= nil
                if not found and changes then pending = pending + 1 end
            end
            if spell.spellConfig and (spell.mana ~= nil or spell.cast ~= nil) then
                if not apply_spellcfg(spell, niceName) then pending = pending + 1 end
            end
        end
    end
    pending = pending + apply_circle_costs()
    return pending == 0
end

-- Cheap "is it still applied?" guard for re-applies. CDO edits PERSIST, so re-running
-- the full apply on every possession/streaming event (dismounting a mount, crossing a
-- zone, …) is wasted work that hitches the frame. This reads back one already-changed
-- spell: if its edit is still in place, we skip the whole expensive apply (the normal
-- case → no hitch). Only if a value was actually reset to vanilla do we re-apply.
local function reapply_if_reset()
    local stillApplied = false
    for _, spell in pairs(config.Spells or {}) do
        if type(spell) == "table" and spell.class and spell.enabled ~= false then
            local cdo = cdo_for(spell.class) or cdo_for(spell.class .. "_Lvl1")
            if valid(cdo) then
                local v = vanilla[full_name(cdo)]
                local cur = read_damage(cdo)
                if v and type(v.base) == "number" and type(cur) == "number" then
                    if math.abs(cur - v.base) > 0.01 then stillApplied = true; break end
                end
            end
        end
    end
    if stillApplied then return end   -- our edits persisted → nothing to do, no frame hitch
    apply_all()                       -- a reset was detected (rare) → re-apply
end

-- =============================================================================
-- Status dump (read-only): current base/circle damage of configured spells
-- =============================================================================
local function dump_status()
    log.info("==== spell damage status ====")
    for niceName, spell in pairs(config.Spells or {}) do
        if type(spell) == "table" and spell.class then
            local anyFound = false
            for _, name in ipairs(def_variants(spell.class)) do
                local cdo = cdo_for(name)
                if valid(cdo) then
                    anyFound = true
                    local b, _, c = read_damage(cdo)
                    log.info(string.format("  %-12s %-30s base=%s  c2/4/6=%s/%s/%s",
                        niceName, name, tostring(b),
                        tostring(c[1]), tostring(c[2]), tostring(c[3])))
                end
            end
            if not anyFound then
                log.info(string.format("  %-12s %-30s (no CDO loaded)", niceName, spell.class))
            end
        end
    end
    log.info("==== end ====")
end

-- =============================================================================
-- Spell-name discovery: log a [SPELL] line the first time each projectile spell
-- is cast, so you can find a new spell's class name + vanilla base for the config.
-- =============================================================================
local seen_spell = _G.__MB_seen_spell or {}
_G.__MB_seen_spell = seen_spell
local function on_cast_capture(_, _, defParam)
    if config.Verbose ~= true then return end
    local def = unwrap(defParam)
    if not valid(def) then return end
    local cls = class_name(def)
    if seen_spell[cls] then return end
    seen_spell[cls] = true
    local b = read_damage(def)
    log.info(string.format("[SPELL] %-34s base=%s   (add to config.Spells to balance)", cls, tostring(b)))
end

-- =============================================================================
-- Wiring
-- =============================================================================
print(string.format("[%s v%s] loaded\n", config.ModName, config.Version))

if config.Enabled ~= false then
    -- Startup: retry applying until all configured spells' CDOs are loaded, then stop.
    -- Use a shared global flag: apply_all runs on the game thread (a different
    -- execution context than the LoopAsync callback), so a plain local "done" can
    -- lag and the loop logs/stops late. A _G flag is visible everywhere; the guard
    -- inside the deferred fn makes "stopped" log exactly once and stops cleanly.
    _G.__MB_done = false
    local attempts = 0
    if type(LoopAsync) == "function" then
        LoopAsync(2000, function()
            if _G.__MB_done then return true end
            attempts = attempts + 1
            pcall(function() on_game_thread(function()
                if _G.__MB_done then return end
                local ok = apply_all()
                quiet = true   -- only the first pass logs; every later apply is silent (anti-stutter)
                if ok then
                    _G.__MB_done = true
                    log.info("all configured spells applied; startup loop stopped.")
                end
            end) end)
            if attempts >= 45 then           -- ~90s cap; spells you don't own may never load
                if not _G.__MB_done then log.info("startup loop stopped (cap); some spell CDOs not loaded yet — will retry on level load.") end
                return true
            end
            return _G.__MB_done
        end)
    else
        run_later(3000, function() on_game_thread(function() apply_all(); quiet = true end) end)
    end

    -- Re-apply after a level/chapter load — but DEBOUNCED. This hook fires repeatedly
    -- during open-world streaming; re-running apply_all (and logging) every time caused
    -- hard frame stutter / multi-second freezes. Collapse bursts to at most one SILENT
    -- re-apply, then a long cooldown. CDO edits persist, so a missed re-apply is harmless.
    local reapply_busy = false
    pcall(RegisterHook, "/Script/Engine.PlayerController:ClientRestart", function()
        if reapply_busy then return end
        reapply_busy = true
        run_later(4000, function()
            pcall(function() on_game_thread(reapply_if_reset) end)   -- cheap guard: skips the work unless a value was actually reset (no frame hitch on dismount/zone-cross)
            run_later(60000, function() reapply_busy = false end)    -- 60s cooldown before another re-apply can be queued
        end)
    end)

    -- Live chapter transition (no level reload): re-assert spell/CDO values. Chapter-
    -- gated trader stock is handled lazily by the trade hook on the next trade open.
    pcall(RegisterHook, "/Script/G1R.GameStory:BP_HandleChapterChanged", function()
        run_later(2000, function() pcall(function() on_game_thread(apply_all) end) end)
    end)

    -- Discovery hook: capture spell class names on cast (arg3 = projectile definition).
    pcall(RegisterHook, "/Script/G1R.GameplayAbilitySpellCommonProjectile:IsAccesible_Scriptable",
        function(self, a1, a2, a3) pcall(on_cast_capture, self, a1, a3) end)

    -- Trader rune stock is inserted lazily when a trade starts, not during save
    -- load/startup. This avoids doing TraderManager writes in the CDO retry loop.
    traderstock.install_trade_hook(config.TraderStock)

end

-- Console commands (need ConsoleEnablerMod):
pcall(RegisterConsoleCommandHandler, "mb_apply", function(_, _, ar)
    on_game_thread(function() apply_all() end)
    if ar then pcall(function() ar:Log("[Mage Balance] applied -> UE4SS.log") end) end
    return true
end)
pcall(RegisterConsoleCommandHandler, "mb_status", function(_, _, ar)
    on_game_thread(function() dump_status() end)
    if ar then pcall(function() ar:Log("[Mage Balance] status -> UE4SS.log") end) end
    return true
end)
pcall(RegisterConsoleCommandHandler, "mb_traders", function(_, _, ar)
    on_game_thread(function() traderstock.status(config.TraderStock) end)
    if ar then pcall(function() ar:Log("[Mage Balance] traders -> UE4SS.log") end) end
    return true
end)
pcall(RegisterConsoleCommandHandler, "mb_trader_apply", function(_, _, ar)
    on_game_thread(function() traderstock.apply(config.TraderStock) end)
    if ar then pcall(function() ar:Log("[Mage Balance] trader apply -> UE4SS.log") end) end
    return true
end)

-- =============================================================================
-- mb_scanall : one-shot probe of EVERY known player damage-spell definition.
-- Class names were harvested from the CXX header dump (all classes deriving from
-- USpellProjectileDefinition / UWindProjectile_Base). The Default__ CDO exists in
-- memory whether or not you own the rune, so this reads vanilla damage for spells
-- you don't have yet (Uriziel, the wind runes, Chain Lightning, …).
-- Crash-safe: every probe + read is pcall'd; missing CDOs are skipped; damage maps
-- are read via the same safe path as mb_status (never touches a map key). Pure
-- read-only — changes nothing.
-- =============================================================================
local MB_SCAN = {
    -- { friendly label, definition object name (no "U" prefix, no "Default__") }
    { "Firebolt",        "FireBoltProjectileDefinition" },
    { "Fireball L1",     "FireBallProjectileDefinition_Lvl1" },
    { "Fireball L2",     "FireBallProjectileDefinition_Lvl2" },
    { "Fireball L3",     "FireBallProjectileDefinition_Lvl3" },
    { "BallLightning B", "BallLightningDefinition_Base" },
    { "BallLightning L1","BallLightningDefinition_Lvl1" },
    { "BallLightning L2","BallLightningDefinition_Lvl2" },
    { "BallLightning L3","BallLightningDefinition_Lvl3" },
    { "BallLightning L4","BallLightningDefinition_Lvl4" },
    { "Icebolt",         "IceBoltProjectileDefinition" },
    { "Iceblock",        "IceBlockProjectileDefinition" },
    { "IceWave",         "IceWaveProjectileDefinition" },
    { "FireRain",        "FireRainDefinition" },
    { "StormOfFire",     "StormOfFireDefinition" },
    { "DestroyUndead",   "DeathToTheUndeadDefinition" },
    { "Pyrokinesis",     "PyrokinesisProjectileDefinition" },
    { "Pyrokinesis Base","PyrokinesisProjectileDefinitionBase" },
    { "BreathOfDeath",   "BreathOfDeathDefinition" },
    { "StormFist",       "StormFistDefinition" },
    { "WindFist",        "WindFistDefinition" },
    { "Uriziel",         "UrizielWaveOfDeathVisualDefinition" },
    { "ChainLtg Base",   "LightningRayDefinition_Base" },
    { "ChainLtg +Para",  "LightningRayDefinition_WithParalysis" },
    { "ChainLtg -Para",  "LightningRayDefinition_WithoutParalysis" },
}
local function read_scalar(cdo, field)
    local v; if pcall(function() v = cdo[field] end) and type(v) == "number" then return v end
    return nil
end
local function scan_all()
    log.info("==== mb_scanall: probing all known spell definitions ====")
    local found, missing = 0, 0
    for _, row in ipairs(MB_SCAN) do
        local label, name = row[1], row[2]
        local cdo = cdo_for(name)
        if valid(cdo) then
            found = found + 1
            local b, bk, c = read_damage(cdo)
            local sa = read_scalar(cdo, "m_SuperArmorDamageBase")
            local spd = read_scalar(cdo, "m_Speed")
            local hasDmg = (b ~= nil) or (c[1] ~= nil)
            log.info(string.format("[SCAN] %-17s %-38s base=%-6s c2/4/6=%s/%s/%s  superArmor=%-6s speed=%-7s %s",
                label, name, tostring(b),
                tostring(c[1]), tostring(c[2]), tostring(c[3]), tostring(sa), tostring(spd),
                hasDmg and "" or "(no damage in def -> likely GameplayEffect)"))
        else
            missing = missing + 1
            log.info(string.format("[SCAN] %-17s %-38s (no CDO loaded)", label, name))
        end
    end
    log.info(string.format("==== mb_scanall done: %d found, %d not loaded ====", found, missing))
end
pcall(RegisterConsoleCommandHandler, "mb_scanall", function(_, _, ar)
    on_game_thread(function() pcall(scan_all) end)
    if ar then pcall(function() ar:Log("[Mage Balance] scanall -> UE4SS.log") end) end
    return true
end)

-- =============================================================================
-- mb_spellcfg : probe CAST TIME + MANA COST for every spell. These live in a
-- DIFFERENT object than the damage definition: the spell's USpellConfig CDO ->
-- m_SpellLevels (TArray<FSpellLevelRange{ CastTime, CastManaCost, ManaCostSc }>,
-- one entry per spell level). Read-only, crash-safe (each access pcall'd; array
-- elements read via e:get() like the per-circle damage path).
-- =============================================================================
local MB_CFG = {
    -- { friendly label, USpellConfig object name (no "U" prefix, no "Default__") }
    { "Firebolt",      "ProjectileSpellConfig_FireBolt" },
    { "Fireball",      "ProjectileSpellConfig_FireBall" },
    { "BallLightning", "ProjectileSpellConfig_BallLightning" },
    { "Icebolt",       "ProjectileSpellConfig_IceBolt" },
    { "FireRain",      "FireRainSpellConfig" },
    { "StormOfFire",   "StormOfFireSpellConfig" },
    { "DestroyUndead", "DeathToTheUndeadSpellConfig" },
    { "Pyrokinesis",   "PyrokinesisSpellConfig" },
    { "BreathOfDeath", "BreathOfDeathSpellConfig" },
    { "StormFist",     "StormFistSpellConfig" },
    { "WindFist",      "FistOfWindSpellConfig" },
    { "IceBlock",      "IceBlockSpellConfig" },
    { "IceWave",       "IceWaveSpellConfig" },
    { "Uriziel",       "UrizielWaveOfDeathSpellConfig" },
    { "ChainLightning","ChainLightningSpellConfig" },
    { "Light",         "LightSpellConfig" },
}
local function read_levels(cfg)
    local out = {}
    pcall(function()
        cfg.m_SpellLevels:ForEach(function(idx, e)
            local ct, cm, ms
            pcall(function() ct = e:get().CastTime end)
            pcall(function() cm = e:get().CastManaCost end)
            pcall(function() ms = e:get().ManaCostSc end)
            out[#out + 1] = string.format("L%d cast=%s mana=%s(sc%s)", idx, tostring(ct), tostring(cm), tostring(ms))
        end)
    end)
    return out
end
local function scan_cfg()
    log.info("==== mb_spellcfg: cast time + mana cost per spell ====")
    local found, missing = 0, 0
    for _, row in ipairs(MB_CFG) do
        local label, name = row[1], row[2]
        local cdo = cdo_for(name)
        if valid(cdo) then
            found = found + 1
            local lv = read_levels(cdo)
            if #lv > 0 then
                log.info(string.format("[CFG] %-15s %-34s %s", label, name, table.concat(lv, " | ")))
            else
                log.info(string.format("[CFG] %-15s %-34s (no m_SpellLevels / empty)", label, name))
            end
        else
            missing = missing + 1
            log.info(string.format("[CFG] %-15s %-34s (no CDO loaded)", label, name))
        end
    end
    log.info(string.format("==== mb_spellcfg done: %d found, %d not loaded ====", found, missing))
end
pcall(RegisterConsoleCommandHandler, "mb_spellcfg", function(_, _, ar)
    on_game_thread(function() pcall(scan_cfg) end)
    if ar then pcall(function() ar:Log("[Mage Balance] spellcfg -> UE4SS.log") end) end
    return true
end)

-- mb_try <NameBase> : safely probe StaticFindObject for a spell definition by name
-- (tries common suffix variants) and dump its damage if found. No hot hook → no
-- crash. Use to locate non-projectile-cast spells, e.g.  mb_try FireRain
local function console_args(a, b)
    if type(a) == "string" and a:find("%s") then
        local t = {}; for tok in a:gmatch("%S+") do t[#t + 1] = tok end; table.remove(t, 1); return t
    end
    for _, v in ipairs({ b, a }) do
        if type(v) == "table" then
            local t = {}
            for _, p in ipairs(v) do
                if type(p) == "string" then t[#t + 1] = p
                else local s; if pcall(function() s = p:ToString() end) and type(s) == "string" then t[#t + 1] = s end end
            end
            if #t > 0 then return t end
        end
    end
    return {}
end
-- SAFE existence probe only: report which Default__<name><suffix> objects exist
-- and their CLASS — does NOT read the damage maps (reading an unexpected object's
-- m_DamageBase can hard-crash). Use it to locate a spell's real definition object;
-- once we know it's a *ProjectileDefinition, balance it via config + mb_status.
pcall(RegisterConsoleCommandHandler, "mb_try", function(a, b, ar)
    local base = console_args(a, b)[1]
    on_game_thread(function()
        if not base or base == "" then log.warn("usage: mb_try <NameBase>   e.g. mb_try FireRain") return end
        local suffixes = { "", "ProjectileDefinition", "ProjectileDefinition_Lvl1",
            "ProjectileDefinition_Lvl2", "ProjectileDefinition_Lvl3",
            "Definition", "Definition_Lvl1", "Definition_Lvl2", "Definition_Lvl3",
            "Definition_Base", "ProjectileDefinition_Base" }
        local found = false
        for _, suf in ipairs(suffixes) do
            local name = base .. suf
            local cdo = StaticFindObject("/Script/Angelscript.Default__" .. name)
            if valid(cdo) then
                found = true
                log.info(string.format("[TRY] FOUND  Default__%-36s  class=%s", name, class_name(cdo)))
            end
        end
        if not found then log.info("[TRY] nothing found for base '" .. tostring(base) .. "' (case-sensitive!)") end
    end)
    if ar then pcall(function() ar:Log("[Mage Balance] try -> UE4SS.log") end) end
    return true
end)

-- mb_fields <DefName> : SAFE reflection dump of a definition CDO's properties —
-- names + types, and VALUES only for plain numeric props. Does NOT read maps,
-- structs or call :get() (those can hard-crash). Use to discover which field a
-- non-projectile spell (e.g. FireRainDefinition) stores its damage in.
local MB_NUMERIC = {
    FloatProperty = true, DoubleProperty = true, IntProperty = true, Int8Property = true,
    Int16Property = true, Int64Property = true, UInt16Property = true, UInt32Property = true,
    UInt64Property = true, ByteProperty = true, BoolProperty = true,
}
local function dump_fields(obj)
    local cls
    if not pcall(function() cls = obj:GetClass() end) or not valid(cls) then return end
    log.info("---- fields of " .. class_name(obj) .. " ----")
    local seen, struct, guard = {}, cls, 0
    while valid(struct) and guard < 40 do
        guard = guard + 1
        pcall(function()
            struct:ForEachProperty(function(prop)
                local pn
                if not pcall(function() pn = prop:GetFName():ToString() end) or not pn or seen[pn] then return end
                seen[pn] = true
                local pt = "?"; pcall(function() pt = prop:GetClass():GetFName():ToString() end)
                if MB_NUMERIC[pt] then
                    local val; local ok = pcall(function() val = obj[pn] end)
                    log.info(string.format("   %-34s %-16s = %s", pn, pt, ok and tostring(val) or "?"))
                else
                    log.info(string.format("   %-34s %-16s", pn, pt))   -- map/struct/object: type only (safe)
                end
            end)
        end)
        local parent; if not pcall(function() parent = struct:GetSuperStruct() end) then break end
        struct = parent
    end
    log.info("---- end ----")
end
pcall(RegisterConsoleCommandHandler, "mb_fields", function(a, b, ar)
    local name = console_args(a, b)[1]
    on_game_thread(function()
        if not name or name == "" then log.warn("usage: mb_fields <DefName>   e.g. mb_fields FireRainDefinition") return end
        local cdo = StaticFindObject("/Script/Angelscript.Default__" .. name)
        if valid(cdo) then dump_fields(cdo) else log.warn("mb_fields: not found: " .. name) end
    end)
    if ar then pcall(function() ar:Log("[Mage Balance] fields -> UE4SS.log") end) end
    return true
end)

log.info("ready. Console: mb_apply, mb_status, mb_traders, mb_trader_apply, mb_scanall, mb_spellcfg, mb_try <name>, mb_fields <name>. Cast -> [SPELL].")
