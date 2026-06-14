# Changelog

All notable changes to **G1R Mage Balance** are documented here.

## [0.7.5] — 2026-06-14

### Fixed
- **Remaining hitch on dismount / zone transitions.** v0.7.4 silenced the re-apply log
  spam, but the re-apply still did the full work (~100 object lookups + map writes) on
  every possession/streaming event, causing a one-frame hitch (e.g. dismounting). Re-applies
  now run a cheap "is it still applied?" check first and **skip the work entirely** when the
  values are still in place — which is the normal case, since CDO edits persist. Verified:
  7 streaming events in a session, **0** re-applies triggered.

## [0.7.4] — 2026-06-14

### Fixed
- **Stutter / freezes during open-world traversal (important).** The mod re-applied its
  values on every PlayerController `ClientRestart`, which fires repeatedly during level
  streaming (moving, sprinting, changing direction) — and it logged the full apply each
  time, flooding `UE4SS.log` and hitching the frame. Re-applies are now **debounced** (at
  most one per ~64s) and **silent after the first pass**. CDO edits persist, so this changes
  nothing about the balance — it just stops the spam. Reported by **loki613** and **emt1234**.

## [0.7.3] — 2026-06-14

### Changed (balance)
- **Fist of Wind — reliable knockdown.** Super-armor damage 200 → **1000**, so it now
  staggers/knocks down even high-super-armor enemies like orcs. Fist of Wind's strength is
  crowd control, not damage — this makes it a real survival tool (especially the fire-resistant
  Orc Cemetery in chapter 2). Tell me if anything still resists it (I'll raise it) or if it
  knocks down things it shouldn't late-game (I'll dial it back).

## [0.7.2] — 2026-06-14

### Changed (balance)
- **Ice Arrow** pulled back below Firebolt: `35/40/50/65` → **`25/40/45/55`**. Full parity made
  Firebolt redundant (Ice Arrow also freezes and is the pick vs fire-resistant enemies). It now
  does a little less than Firebolt — **except at circle 2 (chapter 2)**, where it stays equal, so
  the fire-resistant **Orc Cemetery** stays manageable. Restores the meaningful fire-vs-ice choice.

## [0.7.1] — 2026-06-14

Balance patch from the first big wave of v0.6/v0.7 player feedback.

### Changed (balance)
- **Firebolt mana 1 → 2** — it was by far the most mana-efficient spell (~50 dmg/mana),
  which made everything else redundant for single targets. The most-requested change.
- **Breath of Death** repositioned: mana 40 → **15**, cast 0.5 → **0.25s** — a cheap, fast
  cone nuke with its own identity, instead of a worse Fire Storm clone.
- **Uriziel 300 → 250** — still the strongest spell, but less of an auto-win on final fights.
- **Destroy Undead** keeps 999 dmg but cast 0.5 → **1.2s** — now needs a setup instead of
  run-in-and-instakill (999 trivialized the Sleeper Temple).

## [0.7.0] — 2026-06-14

### Added
- **Magic-circle learning cost (LP).** New `CircleCost` config key sets how many learning
  points each magic circle costs at trainers — a number (flat) or a per-circle table.
  Default `{ 10, 12, 15, 18, 20, 25 }` = **100 LP** total (vanilla 135): cheaper start,
  circle 6 stays a real milestone. This frees up points so a mage can fully invest in
  magic without being starved on hard, while still not being able to also master str/dex.
  Mechanism (`GE_Skill_Mage_Circle_*.SPCost`) found by **Janys27pl** ([#1](https://github.com/tailwindtom/G1R_MageBalance/pull/1)), extended here to per-circle.

### Notes
- `CircleCost` applies to all trainers; per-trainer pricing (e.g. a costlier Swamp Camp)
  is on the to-do list.

## [0.6.0] — 2026-06-14

New levers (mana, cast/charge time, projectile speed) plus a chapter-progression pass.
Full before/after in [BALANCE.md](BALANCE.md).

### Added
- **Mana cost editing** — per-spell `mana` (factor or absolute per level), writing the
  spell's `USpellConfig.m_SpellLevels[].CastManaCost`.
- **Cast / charge time editing** — per-spell `cast`. For charge spells (Fireball, Ball
  Lightning) this *is* the per-stage charge time, so you can make them charge faster.
- **Projectile speed** via `fields = { m_Speed = … }`.
- **`mb_spellcfg`** console command (cast time + mana per spell level) and **speed** added
  to `mb_scanall`.
- **BALANCE.md** — a complete vanilla → mod table (damage / mana / cast / speed).

### Balance
- **Endgame tops the chart:** Uriziel 90 → **300**, Breath of Death 150 → **300**.
- **Mana pass (conservative):** Storm Fist 3 → 15, Ice Wave 8 → 20, Fire Rain 20 → 30,
  Breath of Death 5 → 40, Uriziel 40, Destroy Undead 25 → 30, Storm of Fire 35 → 30;
  Fireball & Ball Lightning mana ×1.25. Firebolt / Ice Arrow left cheap on purpose.
- **Charge & speed:** Fireball & Ball Lightning charge ×0.7 (faster); Ball Lightning
  projectile speed 300-450 → **800**.

### Notes
- Mana values are tuned by feel (the in-game mana economy isn't fully mapped yet) and lean
  conservative; expect tweaks from feedback.

## [0.5.0] — 2026-06-14

Big coverage update: four more spells, including two that were thought impossible.

### Added
- **Chain Lightning (Blitz)** — `LightningRayDefinition` 10/25 → **60/90**. Previously
  assumed un-editable (a "ray" whose damage lives in a GameplayEffect); turns out the
  definition *does* carry the damage and editing it scales the in-game value 1:1
  (**cast-verified**: a 3× test value one-shot a normal enemy). No longer deferred.
- **Uriziel** — `UrizielWaveOfDeathVisualDefinition` 90 → **200** (6th-circle finale).
- **Fist of Wind (Windfaust)** — `WindFistDefinition` ×2.0 (20/30/40/50 → 40/60/80/100).
  This spell *does* have a damage definition (an earlier note said otherwise).
- **Destroy Undead (Untote vernichten)** — `DeathToTheUndeadDefinition` 500 → **999**
  (Gothic-2-style).
- **`mb_scanall`** console command — probes every known spell definition in one go
  (names harvested from the CXX header dump) and logs base + per-circle + super-armor.
  The `Default__` CDO exists even for spells you don't own, so it surfaces vanilla
  values for every spell at once. This is how the four spells above were found.

### Changed
- `def_variants` now also tries `_Base / _WithParalysis / _WithoutParalysis` (so Chain
  Lightning, which has no `_LvlN` variants, is covered by one config entry) and `_Lvl4`.
  Enemy `_Orc` variants are intentionally skipped.

### Testing status (honest)
- **Cast-verified:** Chain Lightning (and the previously shipped spells).
- **Written & very likely active, but not cast-tested yet:** Uriziel, Destroy Undead,
  Fist of Wind — these have the *same* structure as Chain Lightning (a damage definition
  plus a damage GameplayEffect), and Chain Lightning proved the definition wins. Community
  verification welcome. Note: Destroy Undead's felt damage is still dampened by undead
  resistance.

### Docs
- Added `FEEDBACK.md` (community feedback from Nexus + Discord, triaged by feasibility).
- Repo cleanup; `TODO.md` marks Chain Lightning as solved.

## [0.4.0] — 2026-06-14

Balance pass driven by the first wave of player feedback (Nexus + Discord).

### Added
- **Fire Storm** (`StormOfFireDefinition`) is now balanced — denerfed after the 1.01
  hotfix left it weak (+20%, 200 → 240), kept below Fire Rain so chapter progression holds.
- **Pyrokinesis** (`PyrokinesisProjectileDefinition`) now buffed (×2.5) — was dealing
  near-zero damage.
- **Death Breath** (`BreathOfDeathDefinition`) buffed (×2.0).

### Changed (balance)
- **Firebolt** nerfed at **Circle 1 only** (35 → 30); Circles 2/4/6 stay vanilla
  (40/50/65). Addresses "Firebolt outshines everything early".
- **Fireball** retuned from ×2.0 to **×1.75** (was overtuned per feedback).
- **Ice Arrow** kept at Firebolt parity (35/40/50/65).
- **Fire Rain** ×2.5 + larger area; **Ball Lightning** left vanilla.

### Notes
- Community feedback collected and triaged in `FEEDBACK.md` (what's feasible vs not).
- Next up: mana cost / cast time (`USpellConfig`) and stun/knockback tuning.

## [0.3.0-dev] — 2026-06-13

Reworked the whole damage approach and the config schema.

### Changed
- **New damage mechanism: direct definition-CDO editing.** Replaced the previous
  hit-time `DamageMultiplier` hook with editing each spell's definition CDO directly
  (`StaticFindObject("…Default__<Name>")` → write `m_DamageBase` + the per-magic-circle
  progression). Cleaner, per-spell **and** per-circle, applied once at load (re-applied on
  level/chapter change), idempotent via a vanilla snapshot.
- **New config schema — one readable block per spell** (`config.lua → Spells`):
  `{ class, damage, fields?, enabled? }`. `damage` is a multiplier **or** an absolute
  `{ base, c2, c4, c6 }` table.

### Added
- **Per-charge-level coverage** — chargeable spells (`…_Lvl1/2/3`, e.g. Feuerball,
  Kugelblitz) are all balanced by a single config entry.
- **Field overrides** (`fields = { … }`) — set any plain stat absolutely (AoE area,
  duration, speed, …), e.g. Feuerregen's rain area.
- Console commands `mb_status`, `mb_apply`, `mb_try <name>`, `mb_fields <name>`.
- Spell-name discovery: casting a spell logs `[SPELL] <class> base=…`.

### Balance (defaults)
- Feuerball ×1.5 · Feuerregen ×2.5 (+ area 1600) · Eispfeil ×1.2 ·
  Feuerpfeil / Kugelblitz left vanilla.

### Known gaps
- Non-projectile fist/breath spells (Todeshauch, Windfaust, Sturmfaust, Eiswelle) use a
  different damage path and aren't covered. Cast time / mana cost live in `USpellConfig`
  (not touched).

## [0.1.0-alpha] — 2026-06-13

First alpha. The per-spell damage-scaling mechanism works and is stable in-game.

### Added
- Per-spell damage scaling for player **spell projectiles**, configured in
  `config.lua` → `SpellDamageByClass` (class-name substring → multiplier;
  `1.0` = vanilla). Adding a spell is a one-line edit.
- `EnableSpellScaling` master switch; `ScaleDryRun` (resolve + read, no write)
  and `DebugSteps` ([DBG] breadcrumbs) for development.
- Spell-name discovery: with `Verbose`, casting a spell logs its
  `…ProjectileDefinition` class name so you can add it to the config.
- Read-only recon console commands `mb_spells`, `mb_dumpfirst`, `mb_dump`,
  `mb_find`, `mb_scan` (require ConsoleEnablerMod).

### How it works
- Hooks `/Script/G1R.ProjectileVisual:OnHitServer`; identifies the spell from the
  projectile's `m_ProjectileDefinition` and confirms the player is the caster.
- On a valid enemy hit, resolves the target's `AttributeSet_Health` and scales its
  `DamageMultiplier` to `vanilla × factor` for that hit, restoring it ~600 ms later.
- **Runtime-only:** no game files are modified. The boost lands after the game's
  armour/resistance calculation.

### Fixed / hardened
- No `:get()`/unwrap on directly-read object fields (hard crash) — only on hook
  params; object fields read via `field_fullname`.
- Skips non-character hits (props/decorations like
  `AlkimiaLightweightDecorationActor`) so a projectile hitting scenery can't crash.
- Restore guarded against targets that died after the hit.

### Known limitations / next
- Only **projectile spells** are covered. Non-projectile spells (e.g. Todeshauch /
  cone & fist spells) don't fire `OnHitServer` and need a separate path.
- Most spells' class names are not mapped yet (need the runes in a save to cast and
  capture them); only FireBolt/BallLightning are known so far.
- During the ~600 ms restore window, all incoming damage to the hit target is
  scaled (minor side effect).

### Notes
- Developed against UE4SS `3.0.1-326-g940af53` on Gothic 1 Remake
  (UE 5.4.3, build 168781). See `README.md` and `STATUS.md` for details.
