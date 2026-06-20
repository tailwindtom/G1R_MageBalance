# Balance Sheet — G1R Mage Balance

Three baselines side by side:
- **Vanilla (pre-patch)** — the values up to game patch 1.01.
- **Vanilla (2026-06-20 patch)** — the devs rebalanced several spells in this patch (see below).
- **Mod** — what this mod sets (on top of the current/patch vanilla).

Damage is `base / 2nd / 4th / 6th circle` where a spell scales, else a flat number. Charge
spells (Fireball, Ball Lightning) show a factor since the value differs per charge level.
AoE / DoT / channel spells hit multiple times or targets, so real output is above the single
number. **Legend:** 🔼 buff · 🔽 nerf · `=` unchanged.

## What the 2026-06-20 patch changed (devs, not us)

The devs' own rebalance — interestingly it overlaps a lot with this mod:

| Spell | pre-patch | 2026-06-20 patch |
|---|---|---|
| Fireball (base, per lvl) | 60 / 90 / 120 | **90 / 110 / 130** (+ new 6th-circle values) 🔼 |
| Ball Lightning (base, per lvl) | 50 / 70 / 90 / 120 | **70 / 90 / 110 / 150** (+ new 6th-circle) 🔼 |
| Chain Lightning | 10 / 25 | **20 / 35 / 45** 🔼 (their "it's too weak" fix) |
| Fire Rain | 45 | **50** 🔼 |
| Pyrokinesis | 20 (flat) | **20 / 35** (added 2nd-circle) 🔼 |
| Ice Block | 60 / 80 | **60 / 80 / 100** (added 4th-circle) 🔼 |
| Storm Fist — mana | 3 | **10** 🔽 |
| Ice Wave — mana | 8 | **15** 🔽 |
| Breath of Death — mana | 5 | **15** 🔽 |
| Storm of Fire — mana | 35 | **30** 🔽 |

Everything else (Firebolt, Ice Arrow, Uriziel, Destroy Undead, Fist of Wind, and all those spells' damage) is unchanged by the patch.

## Damage — vanilla (pre-patch) → vanilla (patch) → mod

| C | Spell | pre-patch | patch | mod |
|:--:|---|---|---|---|
| 1 | Firebolt | 35/40/50/65 | `=` | **30**/40/50/65 |
| 1 | Ice Arrow | 20/30/40/50 | `=` | **25/40/45/55** |
| 2 | Fist of Wind | 20/30/40/50 | `=` | **40/60/80/100** (×2) |
| 3 | Fireball *(charge, L1 base)* | 60 | 🔼 90 | **×1.25** → ~112 |
| 3 | Ball Lightning *(charge, L1 base)* | 50 | 🔼 70 | **×1.0** (takes the patch buff) |
| 3 | Pyrokinesis | 20 | 🔼 20/35 | **×2.5** → 50/87 |
| 3 | Ice Block | 60/80 | 🔼 60/80/100 | `=` (untouched) |
| 4 | Storm of Fire | 200/250 | `=` | **240/300** (×1.2) |
| 4 | Storm Fist | 120/160 | `=` | `=` (mana-only change) |
| 4 | Chain Lightning | 10/25 | 🔼 20/35/45 | **×3** → 60/105/135 |
| 5 | Fire Rain | 45 | 🔼 50 | **×2.5** → 125 (+ bigger area) |
| 5 | Ice Wave | 120/150 | `=` | `=` (mana-only change) |
| 5 | Destroy Undead | 500 | `=` | **999** |
| 6 | Uriziel | 90 | `=` | **250** |
| 6 | Breath of Death | 150 | `=` | **300** (×2) |

## Mana — vanilla (pre-patch) → vanilla (patch) → mod

| Spell | pre-patch | patch | mod |
|---|---|---|---|
| Firebolt | 1 | `=` | **2** |
| Ice Arrow | 1 | `=` | 1 |
| Fist of Wind | 2 | `=` | 2 |
| Fireball | 5/2/2 | `=` | **×1.25** |
| Ball Lightning | 5/1/1/2 | `=` | **×1.25** |
| Pyrokinesis | 5 | `=` | 5 |
| Ice Block | 3 | `=` | 3 |
| Storm of Fire | 35 | 🔽 30 | 30 *(= patch now)* |
| Storm Fist | 3 | 🔽 10 | **15** |
| Chain Lightning | 5 | `=` | 5 |
| Fire Rain | 20 | `=` | **30** |
| Ice Wave | 8 | 🔽 15 | **20** |
| Destroy Undead | 25 | `=` | **30** |
| Uriziel | 40 | `=` | 40 |
| Breath of Death | 5 | 🔽 15 | 15 *(= patch now)* |

## Cast / charge time, speed, other (mod)

| Spell | change |
|---|---|
| Fireball | charge **×0.7** (faster) |
| Ball Lightning | charge **×0.7** · projectile speed 300-450 → **800** |
| Breath of Death | cast 0.5 → **0.25** (fast cone nuke) |
| Destroy Undead | cast 0.5 → **2.0** (needs a setup, no run-in-instakill) |
| Fist of Wind | super-armor 200 → **1000** (reliable knockdown incl. orcs) |
| Fire Rain | area 800/800 → **1600/1600** |
| **Magic circles (LP)** | 10/15/20/25/30/35 (135) → **10/12/15/18/20/25 (100)** |

### Notes
- **Firebolt / Ice Arrow** stay the cheap early bread-and-butter; later spells win through area,
  burst, range and crowd control.
- Two mod mana values (Storm of Fire 30, Breath of Death 15) now **match the patch** — the devs
  arrived at the same numbers. They're kept explicit so they stay pinned regardless of future patches.
- Mana is tuned conservatively and may still change with feedback.

*Everything here is one readable block per spell in
[`Scripts/config.lua`](G1R_MageBalance/Scripts/config.lua). Use `mb_scanall` (damage/speed/stun)
and `mb_spellcfg` (mana/cast) in-game to see live values — with the mod disabled they show the
current vanilla, which is how the patch diff above was produced.*

## License

MIT — see [LICENSE](LICENSE).
