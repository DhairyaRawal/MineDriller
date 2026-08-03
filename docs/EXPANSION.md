# Expansion guide

Architecture notes for the next features, in rough priority order. Everything below slots
into existing seams — no rewrites required.

## Bosses / mini-bosses (GDD: "battling lava near core layer")
Add a `Boss` subclass of `EnemyBase` with a multi-phase FSM and a health pool (enemies
currently die only by despawn; give `EnemyBase` an optional `hp` + a player attack, e.g.
"drill dash" consuming heat). Spawn deterministically at fixed rows (e.g. row 355 lava
guardian gating a Core vault). Hook the kill to a new achievement + codex entry.

## Mission system
A `MissionManager` autoload listening to existing `Events` signals is enough — the signal
bus already reports ores, depth, sells, treasures, busts. Define missions as entries in
balance.json (`{type: "collect", ore: "gold", count: 10, reward: 50}`), persist progress in
`GameState.to_dict()` (bump `SaveManager.SAVE_VERSION` and add a migration step).

## Ether sink: cosmetics
`Balance` gains a `cosmetics` table (drill skins = tint/palette swaps of player.png, trail
particles). Store owned/equipped ids in GameState; apply in `Player._ready()`. Keeps ether
prestige-only — no gameplay power (see monetization stance in DESIGN_DECISIONS.md).

## NPCs / surface town (GDD level 2)
The surface strip is plain world space — add sprites + a `talk` Area trigger showing a
UIKit modal. Good home for mission givers and the codex librarian.

## Localization
UI strings are currently English literals in the UI scripts. Migrate by wrapping user-facing
strings in `tr()` and adding CSV translations (`Project Settings → Localization`); UIKit
factories make the sweep mechanical. Keep balance.json names as keys, not display strings.

## Rewarded ads (ethical, optional)
Single sensible hook: an "Emergency Vent" offer on the bust screen (watch ad → survive with
heat 50, once per dive). Gate behind a `Monetization` autoload with a null backend by
default so the open-source build stays ad-free.

## Cloud save
`SaveManager` already funnels every write through `save_now()`; add an abstract
`CloudBackend` (upload the same JSON blob, last-write-wins with `saved_at` timestamp) and
call it there. Save format is versioned, so migrations work across devices.

## Multiplayer community digs (GDD vision)
Biggest lift. Realistic first step: async leaderboards on the Daily Challenge (the
date-seed system already guarantees identical worlds for all players on a given day) —
submit `daily_best` to any backend.

## Content: more hazards
Gas pockets (invert controls briefly), cave-ins (timed falling tiles above the player),
crystal batteries (temporary cooling boost). Each is one new TileType in
`MineWorld.cell_info` + one effect branch in `Player._process_environment`.
