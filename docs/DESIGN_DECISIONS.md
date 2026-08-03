# Design decisions — GDD analysis and gaps filled

The GDD (Dhairya Sheel Rawal) is a strong vision document: a clear core loop, a genuinely
novel heat-as-cooldown pressure mechanic, layered depth gating, and good instincts about
pacing and replayability. It is not an implementation spec. This file records every place
the implementation had to interpret, extend, or deliberately deviate.

## Kept exactly as designed

- Core loop (drill → collect → surface → sell → upgrade → deeper) and both GDD loop diagrams.
- Ore ladder and prices: Iron 2$ … Black Opal 150$; ether on Ruby/Opal.
- Five layers with GDD depth ranges; rare ores concentrated near each layer's bottom.
- Cooldown bar that shrinks with depth; overheat = blown drill.
- Upgrade axes from the GDD: speed, sideways agility, hard-rock bit, cooling.
- Enemies: Government Driller, Creepy Crawly, zombie/miner threats; early layers avoidable,
  later layers blocking (spawn tables scale per layer).
- Lose condition and penalty: bust = lose all collected resources, back to surface, money kept.
- Procedural placement within fixed layer bands; hidden rooms; replayability through
  upgrade-gated re-exploration.

## Ambiguities resolved

1. **"Cooldown bar shrinks 10% per 10 km"** taken literally would zero the bar long before
   the Core. Reinterpreted as a continuous *ambient heat floor* (max 55% of the bar at
   maximum depth, reducible by Cooling upgrades). Same felt pressure, no degenerate endpoint.
2. **Upward movement**: GDD says going up differs from going down but doesn't specify how.
   Final decision (after playtest revision 2 below): no straight-up drilling and no flight —
   you carve diagonal ramps and walk them. Descent is a commitment and the route home is a
   planning problem. It can't soft-lock: worst case you carve a fresh ramp out.
3. **"Mine on foot" scenario** (one GDD sketch): cut. A second locomotion mode multiplies
   animation, controls and level-design cost for little loop value. The pod IS the character.
4. **Win condition** ("complete multiple dives, unlock next level"): implemented as
   layer-reach achievements + the codex completion goal rather than discrete levels — see
   "Levels vs. one world" below.
5. **Ether currency** (GDD lists it on rare gems without a sink): kept as a prestige
   currency, earned and displayed; EXPANSION.md reserves it for cosmetics so the economy
   stays ethical (no pay-to-win pressure).

## Structural deviations (with reasons)

- **One persistent world instead of Level 1 / Level 2**: the GDD's two levels are the same
  loop with bigger numbers. A single seeded world with five gated layers delivers the
  identical difficulty ramp without content duplication; the Daily Challenge (date-seeded
  run) provides the "fresh layout" replayability the two-level structure was reaching for.
- **Zombie Miner merges the GDD's "miner" and "zombie" enemies** — one grounded chaser
  archetype; the distinction was visual, not mechanical.
- **Government Driller as instant-bust hover enemy** rather than a drilling pursuer:
  true pathfinding-by-drilling AI is expensive and unreadable for the player; a slow,
  clearly-telegraphed "walking loss condition" produces the same fear with honest counterplay.
- **Free physical movement with organic pixel-carved digging** (revision 2): the pod is a
  circle body that carves smooth round tunnels out of a pixel field. Cell *content* is still a
  data-driven grid (which keeps ore/layer/gate balance tractable), but destruction and
  collision are per-pixel, so the world looks and feels dug rather than blocky.

## Systems the GDD implied but did not specify (designed from scratch)

- Chunk streaming + deterministic regeneration (mobile memory budget).
- Hull/damage model with invulnerability windows and fall damage (the GDD has enemies but
  no defined damage rules).
- Water pockets as an instant-cooling *reward* hazard, magma as its punishing mirror —
  both appear in GDD art without rules.
- Treasure vaults with layer-scaled loot (GDD: "hidden rooms", "narrow ways with big rewards").
- Auto-sell on surfacing + sell summary popup; HUD upgrade target with progress bar
  (GDD asks for a highlighted resource target).
- Event-driven contextual tutorial replacing a tutorial *level* (GDD Level 1).
- Save system with versioning/backup/migration, settings persistence, achievements,
  statistics, codex with real geology notes (GDD vision: "learning about Earth's geology"),
  daily challenge, haptics, left-handed mode, screen-shake toggle.

## Playtest revision 2 (post-first-build feedback)

Six issues were raised after the first playable build; all are addressed:

1. **"Shouldn't be flying."** Free flight is gone. The pod now walks and jumps under gravity.
2. **"Coming up should need a different route."** You can't drill straight up. Vertical shafts
   are one-way drops; to ascend you carve **diagonal ramps** (hold up + a direction into a
   wall) and walk them. Ramps persist, so a smart descent doubles as your route home.
3. **"The drill doesn't work after a certain depth."** That was the layer-2 hard-rock gate
   working but communicating nothing. It now shows an explicit message naming the rock and the
   exact Drill Bit level to buy, and the first bit gate was made cheaper (150→100 $) so it
   lands at GDD tutorial pacing.
4. **"Needs upgrading."** Same gate — see #3; the shop path to it is now signposted.
5. **"Add icons to upgrades."** Every shop track has a generated icon (drill, bit, snowflake,
   crate, shield, treads).
6. **"Make digging organic, not grid blocks; going up is very slow."** Terrain destruction is
   now **per-pixel** — the drill carves smooth round tunnels and caves are organically rounded.
   Ascent speed is fixed by #2: carving a fresh ramp is deliberate, but running back up an
   already-carved ramp is full walking speed, so repeat trips are fast.

## Monetization

The GDD mentions ads and monetized currency. Nothing in this build sells anything:
the economy is tuned for play, ether is ad-free, and offline play is unconditional.
EXPANSION.md sketches the ethical additions (rewarded-ad heat vent, cosmetic drill skins)
if the game ever ships commercially.
