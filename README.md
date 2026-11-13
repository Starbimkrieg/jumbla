# Jumbla: Dungeon Draft

A World of Warcraft addon mini-game for flights. You draft a five-hero party,
then watch them auto-battle waves of enemies through classic dungeons. As they
go, they level up and collect gear.

> Draft / prototype. The numbers come from the headless simulator in `tools/`.
> They have not been tested in the game client yet.

## Install and test in game

1. **Get the files.** Either run `./tools/package.sh`, which builds `dist/Jumbla.zip` with a correctly named
   `Jumbla` folder inside, or download this branch from GitHub (Code > Download ZIP) and rename the extracted folder
   to `Jumbla`.
2. **Put the folder in your AddOns directory.** Use the flavor you play:
   - Retail: `World of Warcraft/_retail_/Interface/AddOns/Jumbla/`
   - Classic Era / Anniversary: `World of Warcraft/_classic_era_/Interface/AddOns/Jumbla/`
   - Progression Classic: `World of Warcraft/_classic_/Interface/AddOns/Jumbla/`
   - WoW Forever: `World of Warcraft/_forever_/Interface/AddOns/Jumbla/` (interface 16001)

   `Jumbla.toc` must sit directly inside `Jumbla/`, not in a nested `Jumbla/Jumbla/`.
3. **Start the game, or `/reload` if you're already logged in.** On the character select screen, open **AddOns** and
   check that *Jumbla: Dungeon Draft* is enabled. If it says "Out of date", either tick **Load out of date AddOns**,
   or run `/dump select(4, GetBuildInfo())` in game and put that number on the `## Interface:` line of `Jumbla.toc`.
4. **Open it with `/jumbla` or `/jb`.** It also opens by itself when you take a flight path.
5. **See errors.** Run `/console scriptErrors 1` once so Lua errors pop up, or install BugGrabber + BugSack. After
   you edit a file, `/reload` picks up the change. Adding new files needs a full game restart.
6. **Reset everything.** Run `/jumbla reset`. Saved data lives in
   `WTF/Account/<ACCOUNT>/SavedVariables/Jumbla.lua`.

## How it plays

1. **Draft.** There are five slots: Tank, Healer, then three DPS. Each slot
   offers two options and you pick one. Tank and Healer options are two
   different tank or healer specs. Each DPS option is a different class with a
   random spec already chosen, for example *Combat Rogue* vs *Fire Mage*. You
   get **one reroll for the whole draft**, and it replaces the two options in
   the current slot. The draft is saved, so reloading doesn't give you a new
   reroll.
2. **Party.** Shows each hero's stats and gear, plus a shared bag and your
   gold. In the bag, left-click an item to equip it on the selected hero,
   right-click to put a one-hander in the off hand, and Shift+Right-click to
   sell. **Auto-Equip Upgrades** does it for you, and a green `+` marks an
   upgrade. Use **Weapon Skills** on the stats panel to see and train skills.
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

- **Primary stats:** Agility gives melee crit, armor and dodge. Strength gives block value. Intellect gives mana and
  spell crit. Stamina gives health. Spirit gives mana and health regen.
- **Attack power:** for Agility specs (all Rogues and Hunters, and Feral Druids) it's 2 per Agility plus 1 per
  Strength. For everyone else it's 2 per Strength.
- **Defense rating** comes from gear ("of Defense") and gives +0.25% block chance per point when a shield is
  equipped. Base block chance with a shield is 5%. Shield Block adds +15% block chance and extra block value for
  5 seconds.
- **Secondary stats** come from level and gear: health, mana, armor, crit, spell power and healing. Heroes start at
  level 10. The level cap is currently 30.
- **Armor progression:** cloth, leather, mail and plate are roughly 1x, 2x, 4x and 7x armor at the same item level.
  Warriors and Paladins wear mail and unlock plate at 40. Hunters and Shamans wear leather and unlock mail at 40.
  Rogues and Druids wear leather, and Mages, Priests and Warlocks wear cloth. Loot only rolls armor someone in the
  party can wear now.
- **Weapons:** every weapon has a damage range and a swing speed. Shields add armor and block.
- **Dual wield:** Rogues can dual wield from level 10, and Warriors and Hunters from level 20. Off-hand swings run on
  their own timer and do 50% damage. White (auto-attack) swings miss 16% more often while dual wielding.
- **Weapon skills (melee classes: Warrior, Paladin, Rogue, Hunter, Shaman, Druid):** each hero starts with their
  spec's preferred weapon skill maxed (max = 5 x level). Training another type the class can use costs
  `50s + 5s x level`, starts at 1, and rises as the hero fights with it. Each point below max adds +0.1% miss and
  -0.04% crit. Mages, Priests and Warlocks can use any weapon their class allows without training.
- **Gold** drops from kills, and items sell from the bag (Shift+Right-click, or **Sell Unusable**). It's spent on
  weapon training.
- **Abilities:** each spec has one level-10 ability, and tanks also get an AoE Taunt. Every ability has a resource
  cost and a cooldown, and most also trigger the 1.5s global cooldown. Warriors and Guardian Druids use rage, and
  Rogues and Feral Druids use energy. Fury uses **Bloodthirst** (an instant strike for 45% of attack power plus a
  bonus, healing for 20% of the damage dealt). Fire Mages use **Fireball** (a hit plus a short burn).
- **Threat:** enemies attack whoever has the most threat. Tanks generate 2.5x threat and Taunt anything that turns on
  someone else. Healing creates threat too.
- **Revives and wipes:** fallen heroes come back at 30% health between waves. If the whole party dies, the run ends,
  but you keep the XP, gold and loot you earned.
- **Loot:** trash has an 18% chance to drop an item and bosses always drop. Items use classic suffixes and are mostly
  rolled for a party member's armor type and trained weapons. Some bosses also drop named blue items.

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
./tools/package.sh              # build dist/Jumbla.zip for installing
```
