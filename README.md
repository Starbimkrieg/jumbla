# Jumbla: Dungeon Draft

A World of Warcraft addon mini-game for flights. You draft a five-hero party,
then watch them auto-battle waves of enemies through classic dungeons. As they
go, they level up and collect gear.

> Draft / prototype. The numbers come from the headless simulator in `tools/`.
> They have not been tested in the game client yet.

## Install

Copy this folder into `World of Warcraft/_<flavor>_/Interface/AddOns/` and
rename it to **`Jumbla`** so it matches `Jumbla.toc`. Type `/jumbla` (or `/jb`)
in game to open it.

The `## Interface:` line in the TOC lists several client versions. If the
addon shows as out of date, run `/dump select(4, GetBuildInfo())` and put that
number in the TOC.

## How it plays

1. **Draft.** There are five slots: Tank, Healer, then three DPS. Each slot
   offers two options and you pick one. Tank and Healer options are two
   different tank or healer specs. Each DPS option is a different class with a
   random spec already chosen, for example *Combat Rogue* vs *Fire Mage*. You
   get **one reroll for the whole draft**, and it replaces the two options in
   the current slot. The draft is saved, so reloading doesn't give you a new
   reroll.
2. **Party.** Shows each hero's stats and gear, plus a shared bag. Click an
   item in the bag to equip it on the selected hero, or use **Auto-Equip
   Upgrades**. Items marked with a green `+` are upgrades for the selected
   hero.
3. **Dungeons.** A dungeon unlocks when your party's average level reaches its
   requirement:

   | Dungeon | Required level | Enemy levels | Waves |
   |---|---|---|---|
   | Ragefire Chasm | 10 | 10-13 | 8 (4 bosses) |
   | The Deadmines | 15 | 15-18 | 11 (7 bosses) |
   | Wailing Caverns | 20 | 21-24 | 12 (8 bosses) |

4. **Battle.** The field is 2D. Heroes are round class icons and enemies are
   round icons with a red ring (gold for bosses). Units move into range and
   fight on their own. When a unit uses an ability, its icon pops up above
   them. Cast bars, floating damage and heal numbers, and party frames are
   shown. You can pause, play at 1x/2x/4x speed, or retreat. Fallen heroes come
   back at 30% health between waves. If the whole party dies, the run is over,
   but you keep the XP and loot you earned.
5. **Flights.** The window opens automatically when you take a flight path and
   pauses when you land. Both can be turned off on the Dungeons tab.

## Rules implemented

- **Primary stats:** Agility gives melee crit, armor and dodge. Strength gives
  melee attack power and block value. Intellect gives mana and spell crit.
  Stamina gives health. Spirit gives mana and health regen.
- **Secondary stats** come from level and gear: health, mana, armor, crit,
  spell power and healing. Every hero starts at level 10, gains stats each
  level, and the level cap is 30.
- **Armor:** every armor piece has armor. Cloth, leather, mail and plate are
  roughly 1x, 2x, 4x and 7x at the same item level.
- **Weapons:** each weapon has a damage range and a swing speed. Daggers are
  about 1.6-1.9s, one-handers about 2.3-2.8s, two-handers about 2.9-3.7s, and
  there are wands, bows and guns. Shields add armor and block.
- **Abilities:** each spec has one level-10 ability, and tanks also get an AoE
  Taunt. Every ability has a resource cost and a cooldown, and most also
  trigger the 1.5s global cooldown. Ability damage grows with level, standing
  in for spell ranks.
- **Threat:** enemies attack whoever has the most threat. Tanks generate 2.5x
  threat and use Taunt when an enemy turns on someone else. Healing creates
  threat too.
- **Loot:** trash has an 18% chance to drop an item and bosses always drop.
  Items use classic "of the Bear / Owl / Eagle..." suffixes and are usually
  rolled for someone in your party. Some bosses also drop named blue items.

## Code layout

| Path | What's in it |
|---|---|
| `Core.lua` | SavedVariables (`JumblaDB`), slash commands, flight hooks |
| `Data/Classes.lua` | Classes, specs, base stats and growth, draft pools |
| `Data/Abilities.lua` | Every hero ability, plus pets (Imp, Wolf) |
| `Data/Items.lua` | Item generator, suffixes, tooltips, scoring |
| `Data/Mobs.lua` / `Data/Dungeons.lua` | Enemies, boss mechanics, waves, named loot |
| `Engine/Hero.lua` | Stat formulas, XP, equipping, the draft |
| `Engine/Combat.lua` | The battle engine, written in pure Lua with no WoW API |
| `Engine/Loot.lua` | Drops and auto-equip |
| `UI/*.lua` | Draft, Party, Dungeons and Battle views |

To add a dungeon, add an entry in `Data/Dungeons.lua` and its mobs in
`Data/Mobs.lua`, then add its key to `ns.DUNGEON_ORDER`.

## Dev tools (run outside the game with Lua 5.1)

```bash
lua5.1 tools/sim.lua 100        # simulate 100 fresh drafts RFC -> DM -> WC; win rates + per-spec DPS/HPS
lua5.1 tools/smoke.lua          # load the whole addon against a stubbed WoW API and click through every screen
```
