# Forever Companion

A WoW: Forever addon that tracks your character and gives advice:

- **Tracking:** equipped gear (item level, durability), bags and bank for all your characters, profession skill levels, known recipes, and the reagents those recipes use.
- **Gear:** scores items for your spec, marks upgrades on tooltips, and lists upgrades already in your bags. For your weakest slots it lists specific upgrades and where to get them: dungeon drops (from the in-game dungeon journal), gear you or your other characters can craft or still learn, and items seen on the auction house.
- **Spec and role:** your role is Tank, Healer or DPS, worked out from where your talent points are. To override it, pick a spec on the Gear page (Shadow, Holy, Fire, Feral (Bear)...) or type `/fc role healer`, `/fc role fire`, or `/fc role auto`.
- **Talents:** compares your points with a recommended leveling build, names the next talent to take, and reminds you about unspent points.
- **Questing and leveling:** XP per hour and time to level, completed quests ready to turn in, a quest log sorted by difficulty, zones for your level, and a checklist when you level up.
- **Vendor, disenchant or auction:** for every bag item, compares vendor price, auction value after the 5% cut, and expected disenchant value. Upgrades, quest items and reagents your recipes use are kept. Tooltips show the disenchant odds: each possible material, its chance, how many, and its price.

## Install

Copy the `ForeverCompanion` folder to:

```
/Applications/World of Warcraft/_forever_/Interface/AddOns/ForeverCompanion
```

Then restart the game, or type `/reload` if it's already running. The TOC targets Interface `16001`, matching client 1.60.1. If the game marks the addon "out of date" after a patch, run this in game and put the number it prints in `ForeverCompanion.toc`:

```
/dump select(4, GetBuildInfo())
```

## Use

- `/fc`: open the window (tabs: Overview, Gear, Bags, Professions, Talents, Quests). You can also bind a key under Key Bindings → AddOns.
- `/fc gear`, `/fc bags`, `/fc prof`, `/fc spec`, `/fc quests`: the same information in chat.
- `/fc price [item]`: vendor, AH and disenchant value for a shift-clicked item.
- `/fc find <name>`: which character has an item, in bags or bank.
- `/fc scan`: full auction house scan, standing at the auctioneer (the server allows one every 15 minutes).
- `/fc role tank|healer|dps|<spec>|auto`: choose the spec used for gear scoring.
- `/fc autoscan`: turn the automatic AH scan on or off.
- `/fc talentdebug`: if the Talents page is empty, run this and send the output.
- `/fc selljunk`, `/fc autosell`: sell gray items now, or every time you open a vendor.
- `/fc tooltip`, `/fc debug`: toggles.

Recipes are recorded the first time you open each profession window, and the bank when you visit it.

## Where prices come from

Prices update by themselves: every time you open the auction house a full scan runs (the server allows one per 15 minutes; a countdown button on the AH window shows when the next is allowed). Each item keeps one price per day for two weeks, and the value used is the median, so one cheap listing doesn't throw it off.

1. **TradeSkillMaster** (`dbmarket`), if it's installed.
2. **Auctionator**, if it's installed.
3. Otherwise, prices this addon records while you browse the auction house or run `/fc scan`. Prices older than 3 days are labeled "old scan".

The auction option is only recommended when it beats vendoring or disenchanting by at least 10 silver (`ahMinGain` in `Core.lua`).

## Things to know

- **The game data is Classic-era.** Disenchant results, talent builds, zone levels, armor and weapon rules, and stat weights are in `Data.lua`, based on Classic. If Forever changes any of them, edit that file. Talents the client doesn't have show as "not in this client's trees" rather than causing errors.
- **The API is modern with fallbacks.** Forever runs on the Mainline (modern) API. Every game call goes through `Compat.lua`, which uses the `C_*` version when it exists and the classic function otherwise, and events this client doesn't have are skipped.
- **Tooltip advice pauses in combat**, because Forever limits what addons can read during fights.
- **Not yet tested in game.** I wrote it but haven't loaded it in the client. On the first run, type `/fc debug` and report any errors it prints.

## Waylaid Crates and Merchant's Favor

Unfilled crates are kept when Merchant's Favor would buy a recipe that makes gear you'd use; otherwise they're marked for the auction house. Sealed crates are always kept, with where to turn them in. Materials that fill a crate you're carrying are kept too. Fill lists and Favor amounts are in `Crates.lua`, taken from community guides; edit them if the game differs.

## Dungeon loot and drop rates

With AtlasLoot Classic Forever installed, gear research lists dungeon and raid drops from AtlasLoot's loot tables, with Forever level ranges, the boss, and drop chances where AtlasLoot has them. Craftable upgrades also say where their pattern drops. For drops AtlasLoot doesn't know, Forever Companion counts the corpses you loot in dungeons and shows the drop rate it has seen after 3 or more kills.

## Leaving notes for Claude

Click **Note to Claude** in the sidebar, or type `/fc note <text>`. Notes are saved with the page you were on, your level and zone. The addon also keeps its last 40 errors (`/fc errors`) and a talent diagnostic. The game writes all of this to disk when you `/reload` or log out, to:

```
/Applications/World of Warcraft/_forever_/WTF/Account/<account>/SavedVariables/ForeverCompanion.lua
```

Then ask Claude to read your notes.
