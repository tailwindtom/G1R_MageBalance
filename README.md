# G1R Mage Balance — Gothic 1 Remake (UE4SS Lua Mod)

Rebalances **mage spell damage** (and other spell stats) at runtime. **No game files are
modified** — values are changed in memory at load and revert when you close the game.
Everything is configured in one readable table: **one block per spell**.

> **Status: working (v0.9.0).** Tunes **damage, mana cost, cast/charge time, projectile
> speed** and **reliable freeze** per spell. See **[BALANCE.md](BALANCE.md)** for the complete vanilla → mod table.
> Balances projectile spells (incl. chargeable ones like
> Fireball) and AoE/special spells whose definition exposes a damage map — **Fire Rain and
> Death Breath included**. A couple of spells use a different damage path (see
> [Limitations](#limitations)); planned work is tracked in [TODO.md](TODO.md).

---

## Features

- **Per-spell damage scaling** — a simple multiplier, or absolute per-magic-circle values.
- **Per-magic-circle aware** — vanilla scales damage at the 2nd / 4th / 6th circle; the mod
  scales each breakpoint, so buffs hold across all circles.
- **Chargeable spells handled** — spells with per-charge-level definitions (`_Lvl1/2/3`,
  e.g. Feuerball, Kugelblitz) are all covered by a single config entry.
- **Field overrides** — optionally set any plain stat on a spell (AoE area, duration,
  speed, stagger, …), not just damage.
- **Idempotent & save-safe** — vanilla values are snapshotted once and the target is always
  `vanilla × factor` (or your absolute values); re-applied after each level/chapter load,
  never stacks.
- **Runtime-only** — touches nothing on disk.

## Requirements

- Gothic 1 Remake
- **UE4SS — latest *experimental* build, from GitHub:**
  [UE4SS-RE/RE-UE4SS · experimental-latest](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/experimental-latest)
  > ⚠️ **Get UE4SS from GitHub, not from Nexus Mods.** The Nexus uploads are often
  > outdated and cause crashes/incompatibilities on the current game build (UE 5.4.3).
  > Always grab the newest experimental build from the GitHub link above.
  > Developed/tested against `3.0.1-968-gcfe10f22`.
- *(optional)* **ConsoleEnablerMod** (ships with UE4SS) — for the in-game `mb_*` commands.

## Installation

1. Install **UE4SS** (latest experimental from GitHub) into
   `…\Gothic 1 Remake\G1R\Binaries\Win64\` — so `dwmapi.dll` sits next to
   `G1R-Win64-Shipping.exe` and you have a `Win64\ue4ss\` folder.
2. Copy the `G1R_MageBalance` folder into **`…\Win64\ue4ss\Mods\`**. The included
   `enabled.txt` activates it.
   > Older UE4SS builds used `…\Win64\Mods\` (no `ue4ss\`). If that's your layout,
   > put it there instead — use whichever folder your other mods already live in.
3. Start the game. The log is at `…\Win64\ue4ss\UE4SS.log`.

---

## Configuration

Everything lives in **`Scripts/config.lua` → `Spells`**. One readable block per spell:

```lua
Spells = {
    Feuerpfeil = { class = "FireBoltProjectileDefinition",    damage = 1.0 },         -- vanilla
    Feuerball  = { class = "FireBallProjectileDefinition",    damage = 2.0 },         -- chargeable; x2
    Kugelblitz = { class = "BallLightningDefinition",         damage = 1.0 },
    Feuerregen = { class = "FireRainDefinition",              damage = 2.5,           -- AoE, flat dmg
                   fields = { m_XOffset = 1600, m_YOffset = 1600 } },                 -- + bigger area
    Eispfeil   = { class = "IceBoltProjectileDefinition",     damage = { base = 35, c2 = 40, c4 = 50, c6 = 65 } }, -- absolute (Firebolt parity)
    Todeshauch = { class = "BreathOfDeathDefinition",         damage = 2.0 },         -- breath/AoE
    Pyrokinese = { class = "PyrokinesisProjectileDefinition", damage = 2.5 },
}
```

Each block:

| key | meaning |
|---|---|
| `class` | the spell's definition class name (without `Default__`). Per-charge-level variants `_Lvl1/_Lvl2/_Lvl3` are covered automatically. |
| `damage` | **number** = multiplier on vanilla base + per-circle values (`1.0` = unchanged), **or table** `{ base=, c2=, c4=, c6= }` = absolute values (omitted entries keep vanilla). |
| `fields` | *(optional)* absolute overrides for non-damage stats, e.g. `m_Speed` (projectile speed); field names from `mb_fields`. |
| `spellConfig` | *(optional)* the spell's `USpellConfig` class name (from `mb_spellcfg`) — required only to change mana/cast time (a separate object). |
| `mana` | *(optional)* change cast mana cost. **number** = factor, **table** = absolute per spell level `{ [1]=, [2]=, … }`. Needs `spellConfig`. |
| `cast` | *(optional)* change cast / charge time (same two forms as `mana`). For charge spells this is the per-stage charge time. Needs `spellConfig`. |
| `freezeGE` + `reliableFreeze` | *(optional, ice spells)* **guaranteed freeze.** Vanilla ice damage adds a freeze *stack* that only freezes once it overflows, so a single cast often fails on tougher foes. Set `freezeGE` to the spell's ice damage GameplayEffect (Ice Block `"GE_IceBlock_Freeze_Damage"`, Ice Bolt `"GE_IceBolt_Damage"`, Ice Wave `"GE_IceWave_Freeze_Damage"`) and `reliableFreeze = true` to freeze on **every** hit. |
| `enabled` | *(optional)* `false` to skip the spell. |

Leave a spell vanilla with `damage = 1.0` and no `fields` (or comment the block out).

### Magic circle learning cost

A separate top-level key sets how many learning points (LP) each magic circle costs at
trainers:

```lua
CircleCost = { 10, 12, 15, 18, 20, 25 },  -- per circle (progressive); 100 LP total
-- CircleCost = 15,    -- or a flat number for all circles
-- CircleCost = nil,   -- or vanilla (10/15/20/25/30/35 = 135)
```

### Adding a spell

1. Cast it once in-game. `UE4SS.log` logs `[SPELL] <Name>Definition base=…`.
2. Add a block using that class name. Done.

(Or probe a guessed name with `mb_try <name>`, and list a definition's tunable fields with
`mb_fields <name>`.)

### Absolute / per-circle example

```lua
Blitz = { class = "…", damage = { base = 80, c2 = 95, c4 = 115, c6 = 150 } },
```

---

## How it works

Spell damage is stored on the spell's **definition CDO** (e.g.
`/Script/Angelscript.Default__FireBallProjectileDefinition`), reached with
`StaticFindObject`. There the mod edits:

- **`m_DamageBase`** — base damage (a map keyed by damage-type tag), and
- **`m_DamageMagicCircleProgression`** — the per-circle breakpoints (2nd/4th/6th).

It snapshots the vanilla values once, then writes `vanilla × factor` (or your absolute
values), and re-applies ~4 s after each `ClientRestart` (level/chapter load). Field
overrides assign plain numeric properties directly. Chargeable spells keep one definition
per charge level (`_Lvl1/2/3`); one config entry covers them all.

## Console commands

Require **ConsoleEnablerMod**.

| command | effect |
|---|---|
| `mb_status` | dump every configured spell's current base + per-circle damage |
| `mb_scanall` | probe **all** known spell definitions (even ones you don't own): damage + super-armor + projectile speed |
| `mb_spellcfg` | probe **mana cost + cast/charge time** for every spell (per spell level) |
| `mb_apply` | re-apply the config now |
| `mb_try <name>` | safely probe whether `Default__<name>…` definitions exist |
| `mb_fields <name>` | list a definition's properties (to find tunable fields) |
| `mb_freeze [set]` | dump each ice GE's freeze-overflow flag; `mb_freeze set` flips it live (reliable-freeze testing) |

## Limitations

- Covers spells whose definition exposes `m_DamageBase` — projectiles, charge spells,
  AoE/breath spells (Fire Rain, Death Breath), the beam spell **Chain Lightning**, the
  **wind** spells (Fist of Wind), **Uriziel** and **Destroy Undead**. Use `mb_scanall`
  to list every known spell definition and its current values.
- **Stun / knockback** (`m_SuperArmorDamageBase`) is tunable via `fields` (e.g. Fist of Wind).
- **Reliable freeze** (`freezeGE` + `reliableFreeze`) works for the ice spells; the freeze
  *duration* itself lives in a GameplayEffect and isn't tuned yet.
- **Initial cast speed** can't be changed — the initial cast windup is montage/animation-driven
  (no play-rate field). `cast` only affects per-stage charge time. (GitHub #9.)
- **Per-trainer** magic-circle cost (e.g. a pricier Swamp Camp) isn't separated yet —
  `CircleCost` applies to every trainer. See the [to-do list](TODO.md).

## Building / dev notes

See [STATUS.md](STATUS.md) for the reverse-engineering notes, the data model, the
hard-won UE4SS crash rules, and what's still open. `DebugSteps = true` in `config.lua`
enables `[DBG]` breadcrumbs before each risky engine call (crash tracing).

## Credits

**Created and maintained by [tailwindtom](https://github.com/tailwindtom)** — versions 0.1–0.6 built solo.

Built on and helped by:

- **[DoctorKalle](https://www.nexusmods.com/gothic1remake/mods/178)** — author of
  **NoviceWaterMage**, who worked out how Gothic 1 Remake stores spell damage on the
  definition CDOs. The runtime CDO-editing technique this mod is built on is theirs.
- **[Janys27pl](https://github.com/Janys27pl)** — found the magic-circle learning-cost
  mechanism (`GE_Skill_Mage_Circle_*.SPCost`) and contributed it ([#1](https://github.com/tailwindtom/G1R_MageBalance/pull/1)).
- **[DannyKickem](https://www.youtube.com/@DannyKickem)** — the detailed, spell-by-spell
  balance feedback that kicked off the whole project.
- The **Gothic 1 Remake modding community** and the **UE4SS** team — and everyone who
  tests, reports and helps tune the numbers.

Contributions welcome — open an issue or PR.

## License

MIT — see [LICENSE](LICENSE).
