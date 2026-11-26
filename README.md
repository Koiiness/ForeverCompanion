# Forever Companion

A World of Warcraft: **Forever** addon that tracks your character and tells you what to do next: which quests and dungeons have upgrades for you, what to do with every item in your bags, what to craft, and which talent to take.

Built for the Forever client 1.60.1 (Interface 16001).

## What it does

- **Your plan.** The Overview page lists the quests to pick up, finish or turn in, and the dungeons to run, ranked by the upgrades they hold for your spec.
- **Gear.** Scores items for your spec (Tank, Healer or DPS, detected from your talents), shows the stat changes behind every upgrade, accounts for set bonuses, and lists the best upgrade per slot from quests, dungeons, the auction house and crafting.
- **Bags.** For every item: keep, sell to a vendor, disenchant (with the odds for each material) or put on the auction house. Consumables, profession tools and materials you use are kept. Handles Waylaid Crates and Merchant's Favor.
- **Money.** A gold plan across all your characters: what each can cash in, unbound greens to mail to your enchanter, the most profitable recipes any of them knows, and the best-paying herbs, ore and leather each gatherer can farm. A **safety net** keeps gold aside for upcoming class training and repairs, tracks a savings goal (a mount at 40 by default), and never suggests spending what you need.
- **Settings.** Solo or group leveling, how much gold to keep aside, your savings goal, celebrations and sound, tooltips, touch mode, the minimap button, and resetting saved data.
- **Professions.** Skill-up recipes with materials you have or still need, what to do with the result, money makers, and recipes worth getting with where to get them.
- **Talents.** The best next talent from a Forever leveling build (Discipline Priest so far; more specs can be added in `Data.lua`).
- **Quests.** XP per hour, time to level, a quest log sorted by difficulty, and zones for your level.
- **Tracking.** Gear, bags and bank across all your characters (`/fc find <item>`), with prices from your own auction house scans.
- **Celebrations.** A card with a sound when you get an upgrade (tap Equip to wear it), when you pick up gear for a few levels from now, and when you level up. `/fc celebrate` turns them off; `/fc testcard` shows a sample.
- **Coming soon.** Gear that unlocks in the next few levels (Gear page), and what your next level brings at the top of your plan.
- **Tips for newer players.** A short tip the first time something comes up, with Got it so it never returns; Settings has an "I know WoW" switch to hide them all.

## Install

1. Download this repository (green **Code** button, then **Download ZIP**) and unzip it.
2. Copy the inner `ForeverCompanion` folder into:
   - Mac: `/Applications/World of Warcraft/_forever_/Interface/AddOns/`
   - Windows: `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\`
3. Restart the game, or type `/reload`.

Type `/fc` or click the minimap button to open it. `/fc help` lists every command.

On a touch screen, turn on **Touch mode** in the sidebar (or `/fc touch`) for a bigger window. You can drag any list to scroll.

## Works better with (optional)

- **[AtlasLoot Classic Forever](https://www.curseforge.com/wow/addons/atlasloot-forever)**: dungeon and raid drops, drop rates, and where patterns drop.
- **[Questie](https://github.com/Questie/Questie/releases)**: quests you haven't picked up yet whose rewards are upgrades.
- **TradeSkillMaster** or **Auctionator**: auction prices. Without them, Forever Companion scans the auction house itself each time you open it (once every 15 minutes, the server's limit).

## Good to know

- Open each of your profession windows once so recipes are recorded, and visit your bank once so it's included.
- Prices fill in the first time you open the auction house.
- Some game data (disenchant results, crate fill lists, leveling builds) comes from community guides and lives in `Data.lua` and `Crates.lua`, so it's easy to correct.
- Something wrong? `/fc errors` shows any errors the addon caught, and `/fc note <text>` saves a note with the page you were on.

## License

MIT. See [LICENSE](LICENSE).
