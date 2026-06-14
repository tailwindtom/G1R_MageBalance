-- G1R Mage Balance — configuration
-- =============================================================================
-- Edit the Spells table below. One readable block per spell — that's all you ever
-- touch. Runtime-only; reverts on game close. No game files are modified.
--
-- Each spell block:
--   class   = the spell's definition class name (without "Default__"). Per-level
--             chargeable spells are covered automatically (_Lvl1/_Lvl2/_Lvl3).
--             Discover a class name by casting the spell -> see "[SPELL] <name>"
--             in UE4SS.log, or probe with the  mb_try <name>  console command.
--   damage  = how to change damage. Two forms:
--               • a NUMBER  = multiplier on vanilla base + per-circle values
--                             (1.0 = unchanged). Easiest; scales uniformly.
--               • a TABLE   = ABSOLUTE values: { base=, c2=, c4=, c6= }
--                             (any omitted entry keeps vanilla). For precise
--                             per-magic-circle control.
--   fields  = OPTIONAL absolute overrides for non-damage stats (AoE area,
--             duration, speed, stagger, ...). Field names come from  mb_fields.
--   spellConfig = OPTIONAL the spell's USpellConfig class name (see  mb_spellcfg).
--             Only needed to change mana / cast time — those live in a SEPARATE
--             object than damage. e.g. "StormFistSpellConfig".
--   mana    = OPTIONAL change CAST MANA COST. NUMBER = factor on vanilla, or
--             TABLE = absolute per spell level { [1]=, [2]=, ... }. Needs spellConfig.
--   cast    = OPTIONAL change CAST TIME (same two forms as mana). Needs spellConfig.
--   enabled = OPTIONAL false to skip this spell entirely.
--
-- To leave a spell vanilla: damage = 1.0 and no fields (or just comment it out).
-- =============================================================================

return {
    ModName = "G1R Mage Balance",
    Version = "0.7.5",
    Enabled = true,

    Spells = {
        -- name           class (definition)                damage / fields
        Feuerpfeil = { class = "FireBoltProjectileDefinition", damage = { base = 30, c2 = 40, c4 = 50, c6 = 65 }, -- C1 nerf (35->30), rest vanilla
                       spellConfig = "ProjectileSpellConfig_FireBolt", mana = { 2 } },    -- mana 1 -> 2: halves its mana-efficiency (was by far the most efficient spell -> Firebolt-spam fix)
        Feuerball  = { class = "FireBallProjectileDefinition", damage = 1.75,            -- chargeable _Lvl1/2/3; +75%
                       spellConfig = "ProjectileSpellConfig_FireBall", cast = 0.7, mana = 1.25 }, -- charge x0.7, mana x1.25 (vanilla 5/2/2)
        Kugelblitz = { class = "BallLightningDefinition",      damage = 1.0,             -- damage okay per feedback
                       fields = { m_Speed = 800 },                                       -- faster orb (vanilla 300-450, was sluggish)
                       spellConfig = "ProjectileSpellConfig_BallLightning", cast = 0.7, mana = 1.25 }, -- charge x0.7, mana x1.25 (strong now: faster + zippier)
        Feuerregen = { class = "FireRainDefinition",           damage = 2.5,             -- AoE, flat damage (no circle scaling)
                       fields = { m_XOffset = 1600, m_YOffset = 1600 },                  -- bigger rain area (vanilla 800/800)
                       spellConfig = "FireRainSpellConfig", mana = { 30 } },             -- mana 20 -> 30 (OP AoE-DoT, conservative bump)
        Eispfeil   = { class = "IceBoltProjectileDefinition",  damage = { base = 25, c2 = 40, c4 = 45, c6 = 55 } }, -- below Firebolt (it also freezes / beats fire-resistant foes), BUT = Firebolt at circle 2 (ch.2) so the fire-resistant Orc Cemetery stays doable; vanilla 20/30/40/50
        Todeshauch = { class = "BreathOfDeathDefinition",      damage = 2.0,             -- 300 dmg (vanilla 150)
                       spellConfig = "BreathOfDeathSpellConfig", mana = { 15 }, cast = { 0.25 } }, -- own niche: cheap+fast cone nuke (not a Firestorm clone). mana 5->15, cast 0.5->0.25
        Pyrokinese = { class = "PyrokinesisProjectileDefinition", damage = 2.5 },        -- projectile
        Feuersturm = { class = "StormOfFireDefinition",        damage = 1.2,             -- Firestorm: 200->240 (stays below Firerain's total output)
                       spellConfig = "StormOfFireSpellConfig", mana = { 30 } },          -- mana 35 -> 30 (slight relief)
        Uriziel    = { class = "UrizielWaveOfDeathVisualDefinition", damage = { base = 250 }, -- 6th-circle finale (vanilla 90); tops the chart but not insta-win (was 300)
                       spellConfig = "UrizielWaveOfDeathSpellConfig", mana = { 40 } },   -- mana 40 (krass aber teuer)
        Blitz      = { class = "LightningRayDefinition",        damage = { base = 60, c2 = 90 } }, -- Chain Lightning C4 (vanilla 10/25 "lachhaft"); hits _Base/_WithParalysis/_WithoutParalysis. CONFIRMED: def-write scales in-game damage 1:1
        Windfaust  = { class = "WindFistDefinition",            damage = 2.0,             -- Fist of Wind (CC spell): 20/30/40/50 -> 40/60/80/100
                       fields = { m_SuperArmorDamageBase = 1000 } },                      -- reliable knockdown incl. orcs (vanilla 200 was too low to stagger them); raise if some still resist, lower if it over-knocks late-game
        UntoteVernichten = { class = "DeathToTheUndeadDefinition", damage = { base = 999 }, -- Destroy Undead, Gothic-2-style (vanilla 500 flat)
                       spellConfig = "DeathToTheUndeadSpellConfig", mana = { 30 },       -- mana 25 -> 30
                       cast = { 1.2 } },                                                 -- cast 0.5 -> 1.2: needs a setup, no more run-in-instakill (feedback)

        -- Mana nerfs (damage left VANILLA on purpose) — feedback: these two are far too cheap:
        Sturmfaust = { class = "StormFistDefinition",         damage = 1.0,
                       spellConfig = "StormFistSpellConfig",  mana = { 15 } },            -- mana 3 -> 15 (120/160 AoE + 250 stun for 3 mana was absurd)
        Eiswelle   = { class = "IceWaveProjectileDefinition", damage = 1.0,
                       spellConfig = "IceWaveSpellConfig",    mana = { 20 } },            -- mana 8 -> 20 (AoE stunlock)

        -- Left fully vanilla (uncomment + tune if wanted; values from mb_scanall / mb_spellcfg):
        -- Eisblock   = { class = "IceBlockProjectileDefinition", damage = 1.0 },         -- 60/80 freeze utility, mana 3
        -- Damage absolute example:  Beispiel = { class = "X", damage = { base = 80, c2 = 95, c4 = 115, c6 = 150 } },
        -- Mana/cast example:        X = { class="X", spellConfig="XSpellConfig", mana = { 12 }, cast = 0.5 },
    },

    -- ---- magic-circle learning cost (LP) --------------------------------------
    -- How many learning points a trainer charges per magic circle.
    --   • a TABLE  { c1, c2, c3, c4, c5, c6 }  = per-circle cost (progressive)
    --   • a NUMBER = same cost for every circle (flat)
    --   • nil      = keep vanilla (10/15/20/25/30/35 = 135 total)
    -- Applies to all trainers. (Mechanism: Janys27pl, PR #1.)
    CircleCost = { 10, 12, 15, 18, 20, 25 },   -- progressive, 100 LP total (cheap start, circle 6 stays a milestone)

    -- ---- diagnostics ----------------------------------------------------------
    Verbose    = true,   -- log each spell's class + base damage on first cast ([SPELL] lines)
    DebugSteps = false,  -- DEV: [DBG] breadcrumbs before risky calls (crash tracing)
}
