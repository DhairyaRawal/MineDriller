# Balancing

All numbers live in `data/balance.json`. This document explains *why* they are what they are.

## Depth model

1 tile = 25 km. The GDD's five layers map to rows:

| Layer | Rows | GDD depth | Gate |
|---|---|---|---|
| 1 Crust | 1–28 | 200–700 km | — (start) |
| 2 Upper Mantle | 28–120 | 1000–3000 km | Bit 2 (150 $) |
| 3 Lower Mantle | 120–200 | 4000–5000 km | Bit 3 (500 $) |
| 4 Upper Core | 200–280 | 5000–7000 km | Bit 4 (1600 $) |
| 5 Core | 280–360 | 8000–9000 km | Bit 5 (5000 $) |

Each layer ends in a 2-row solid band of next-tier hard rock, so bit upgrades are the hard
gates the GDD asks for ("upgrading once provides 250% more depth").

## Ore economy

GDD prices kept verbatim: Iron 2, Silver 8, Gold 25, Emerald 40, Ruby 60 (+1 ether),
Black Opal 150 (+2 ether).

Expected value of a *full* cargo bay by layer (base capacity 8, ore chance ~10–14% per solid
tile, weights from balance.json):

- L1: mostly iron/silver → **~25–35 $** per dive
- L2: silver/gold mix → **~90–130 $**
- L3: gold/emerald/ruby → **~250–330 $**
- L4: + opal at 10% → **~380–480 $**
- L5: ruby/opal heavy → **~600–800 $**

Rare-ore weights scale by `1 + local_depth_frac · rarity · 0.35` inside each layer, so the
bottom of every layer pays visibly better than the top (GDD's distribution rule) — this pulls
players toward the danger (transition bands, more enemies) right before they need the next
bit purchase.

## Upgrade costs

Geometric scaling `cost = base · 2.3^(level−1)` for 6-level tracks (2.2 for utility tracks):

- Drill Motor 60 → 138 → 317 → 730 → 1679
- Cooling 80 → 184 → 423 → 973 → 2238
- Cargo 50 → 110 → 242 → 532 → 1171
- Hull 70 → 154 → 339 → 745 → 1640
- Treads 60 → 132 → 290 → 639 → 1405
- Drill Bit (explicit list): 100, 450, 1500, 4800

**Pacing result**: with L1 dives earning ~30 $, the first upgrade (Cargo 50 $) lands on dive
2 — matching the GDD pacing chart of ~4 dives to clear the tutorial level. Each layer's
income roughly triples while next-gate cost roughly triples, holding "2–4 dives per
meaningful purchase" across the whole game (GDD level 2 chart shows 7 dives; a full bit
gate at mid-game takes ~4–5 dives if you buy nothing else).

## Heat model

- Max 100. Drilling: +14/s (×1.8 in hard rock). Cooling: 12/s (+3/level), doubled in water.
- Ambient floor: `55 · (row/360)`, reduced 8%/cooling level. At the Core with no cooling
  upgrades, 47 of your 100 heat budget is gone before you drill a single tile — the GDD's
  "cooldown bar shrinks with depth", made continuous.
- Sustainable duty cycle at level 1 ≈ 45% drilling — you drill ~4–5 tiles, pause ~3 s.
  Fully upgraded cooling ≈ 65% duty and a usable budget of ~78 even at the Core.
- Water pockets refund 30 heat instantly (exploration reward); magma adds 35 + 1 hull damage.

## Risk / penalty

Bust (overheat, hull 0, government capture, per GDD) = lose all cargo, keep money.
Death is a time-and-cargo tax, never a progression wipe — retention-friendly and matches the
GDD's penalty exactly. Hull (3–8) gives crawly/zombie contact a real but survivable cost;
Government Drillers bypass hull entirely, so layer 3+ routing stays tense at any upgrade level.

## Treasure vaults

3.5% per 16-row chunk → roughly one every ~18 chunks explored. Contents: 3–6 layer-appropriate
ores + 20–120 $ + 35% chance of 1 ether. Designed as a "secret rooms" reward (GDD level 2)
that's worth a detour but never mandatory.

## Depots

3 per layer (15 total), fixed positions rather than a chance roll — the design goal was a
reliable mid-dive safety valve, not a random find like a treasure vault. Each holds up to
`depot.capacity` (20) ore total across all types; deposited ore survives a bust but still has
to be withdrawn and carried to the surface to sell (Changes.txt's "drop ore at a safe spot").

## Ramps

`player.ramp_angle_ratio` (1.4) widens the horizontal component of a ramp's carve direction
relative to a straight 45°, giving a shallower, easier-to-walk grade; `ramp_carve_radius_mult`
(1.15) widens the carve circle only while carving a ramp, so the tunnel is a bit more
forgiving. Neither touches `ramp_speed_mult` (0.85) — geometry, not a speed buff, per explicit
design intent (see docs/DESIGN_DECISIONS.md's "no flying, ramps only" playtest fix).

## Tuning guide

Want the game harder? Raise `heat.ambient_floor_max` or lower `cool_per_sec_base`.
Want faster progression? Raise `ore_chance` per layer or lower `cost_mult` to 2.0.
Every such change is one line in balance.json; the test suite verifies cost monotonicity
and price ordering after any edit.
