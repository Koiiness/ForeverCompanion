# Forever Companion

A World of Warcraft: **Forever** addon that helps you enjoy the game without grinding past the fun. It tells you the next good thing to do, which gear is worth chasing and why, what to do with every item in your bags, and how to make gold without going broke. It also teaches newer players as they go.

Built for the Forever client 1.60.1 (Interface 16001). Version 0.2.0.

## Install

### 1. Download

On this page, click the green **Code** button, then **Download ZIP**, and unzip the file. You'll get a folder called `ForeverCompanion-main`, and inside it another folder called **`ForeverCompanion`**. That inner folder is the addon.

### 2. Copy the addon into WoW

Copy the inner **`ForeverCompanion`** folder (not `ForeverCompanion-main`) into your Forever AddOns folder:

- **Mac:** `/Applications/World of Warcraft/_forever_/Interface/AddOns/`
- **Windows:** `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\`

If the `AddOns` folder doesn't exist yet, create it. You know it's right when this file exists:

```
.../_forever_/Interface/AddOns/ForeverCompanion/ForeverCompanion.toc
```

Can't find your WoW folder? In the Battle.net app, select WoW Forever, click the gear next to Play, and choose **Show in Finder** (Mac) or **Show in Explorer** (Windows).

### 3. Turn it on

Start the game (or type `/reload` if it's running). On the character screen, click **AddOns** (bottom left) and make sure **Forever Companion** is ticked. If it says "Out of date", tick **Load out of date AddOns**.

### 4. Open it

Click the book icon on your minimap, or type `/fc`.

### Optional add-ons that make it better

All of these are free on CurseForge, and Forever Companion works without them:

- **[AtlasLoot Classic Forever](https://www.curseforge.com/wow/addons/atlasloot-forever)** adds dungeon and raid drops, drop rates, and where crafting patterns drop.
- **[Questie](https://github.com/Questie/Questie/releases)** adds quests you haven't picked up yet whose rewards are upgrades, good zones to quest in, and where to buy patterns and materials.
- **TradeSkillMaster** or **Auctionator** provide auction prices. Without them, Forever Companion scans the auction house itself whenever you open it (at most once every 15 minutes, the server's limit).

## Your first five minutes

1. **Open the addon** (`/fc` or the minimap button). The **Next up** card at the top suggests the one best thing to do right now.
2. **Open the auction house once.** A price scan runs by itself, and from then on the addon knows what your items are worth.
3. **Open each of your profession windows once**, and **visit your bank once**, so your recipes and stored items are included.
4. **Visit your class trainer once.** The addon then knows what training costs are coming, and keeps that gold aside in your safety net.
5. **Check Settings** (gear icon at the bottom of the sidebar): solo or group leveling, tips on or off, Touch mode, and more.

Log in on each of your characters once, and the Money page can plan across all of them.

## What it does

- **Next up and your plan.** One clear suggestion at the top of Overview. Below it: turn-ins, the best zone to quest in at your level, quests and dungeons with upgrades for you, and what your next level brings.
- **Gear.** Upgrades in your bags (tap to equip), what to chase for your weakest slots (quest, dungeon with drop chance, crafting, or the auction house), gear coming in the next few levels, and why each item is better for your spec (e.g. "+12 Intellect, +6 Spirit"). Set bonuses and unique items are taken into account.
- **Bags.** For every item: auction it, disenchant it (with the odds for each material), sell it to a vendor, or keep it. Potions, buff food, profession tools and the materials you use are always kept. Handles Waylaid Crates and Merchant's Favor.
- **Money.** A **safety net** that keeps gold aside for training and repairs, a savings goal (a mount at 40 by default), and gold ideas across your characters: what to sell, greens to mail to your enchanter, profitable crafts (with how you'd get the materials), and what your gatherers can farm. It skips grinding ideas unless you ask for them.
- **Professions.** Recipes that give skill-ups, with the materials you have and still need, what to do with what you make, and recipes worth learning with where to get them (trainer and cost, vendor, or drop).
- **Talents.** The best next talent from a Forever leveling build (Discipline Priest so far; more can be added in `Data.lua`).
- **Quests.** XP per hour, time to level, your quest log sorted by how good it is for you, and zones for your level.
- **Celebrations.** A card with a sound when you get a real upgrade (tap **Equip**) or level up. Small upgrades get a quiet chat line. Nothing pops up during combat.
- **Tips for newer players.** A short tip the first time something comes up. **Got it** hides it for good, and Settings has an **I know WoW** switch.

Type `/fc help` in game for every command.

## Updating

Download the ZIP again and replace the `ForeverCompanion` folder in your AddOns folder with the new one. Your settings, notes and saved data are kept; they live in a separate folder (`WTF`).

## Feedback: send notes to the author

1. In game, click **Leave a note** in the sidebar (or type `/fc note something looks off here`). Each note remembers which page you were on, your level and your zone.
2. When you're ready to send, open **Settings → Data → Share notes and errors** (or type `/fc share`). A window opens with your notes and any recent addon errors, already selected.
3. Press **Cmd+C** (Mac) or **Ctrl+C** (Windows), then paste it into Discord and send it to Koiiness.
4. Back in the window, click **Clear notes I've sent** so you don't send the same ones twice.

## Troubleshooting

- **It doesn't show up in the AddOns list.** The folder is probably nested one level too deep. You need `AddOns/ForeverCompanion/ForeverCompanion.toc`, not `AddOns/ForeverCompanion-main/ForeverCompanion/...`.
- **"Out of date".** Tick **Load out of date AddOns** on the AddOns screen.
- **Prices are missing.** Open the auction house once and wait a few seconds for the scan.
- **Dungeon drops or quest suggestions are missing.** Install AtlasLoot Classic Forever and Questie (see above).
- **The spec it uses is wrong.** Pick yours on the Gear page under **Spec & stats**.
- **Something errors or looks wrong.** Send your notes as above. They include the addon's recent errors.

## License

MIT. See [LICENSE](LICENSE).
