-- Data: static tables. Everything here is based on Classic-era values and is
-- meant to be edited if WoW Forever's numbers turn out to differ.
local _, ns = ...
local D = {}
ns.Data = D

----------------------------------------------------------------------
-- Professions (enUS names, used when the client only offers skill lines)
----------------------------------------------------------------------
D.ProfessionNames = {
    ["Alchemy"] = true, ["Blacksmithing"] = true, ["Enchanting"] = true, ["Engineering"] = true,
    ["Herbalism"] = true, ["Leatherworking"] = true, ["Mining"] = true, ["Skinning"] = true,
    ["Tailoring"] = true, ["Cooking"] = true, ["Fishing"] = true, ["First Aid"] = true,
}

-- Trainer tiers: max skill -> character level needed for the next tier.
D.ProfessionTiers = {
    { max = 75,  next = "Journeyman (150)", level = 10 },
    { max = 150, next = "Expert (225)",     level = 20 },
    { max = 225, next = "Artisan (300)",    level = 35 },
}

----------------------------------------------------------------------
-- Disenchanting (Classic table). Probabilities for armor; weapons swap
-- dust and essence odds.
----------------------------------------------------------------------
local STRANGE, SOUL, VISION, DREAM, ILLUSION = 10940, 11083, 11137, 11176, 16204
local LMAGIC, GMAGIC, LASTRAL, GASTRAL = 10938, 10939, 10998, 11082
local LMYSTIC, GMYSTIC, LNETHER, GNETHER, LETERNAL, GETERNAL = 11134, 11135, 11174, 11175, 16202, 16203
local SGLIM, LGLIM, SGLOW, LGLOW, SRAD, LRAD, SBRIL, LBRIL, NEXUS = 10978, 11084, 11138, 11139, 11177, 11178, 14343, 14344, 20725

D.Disenchant = {
    -- min, max ilvl, enchanting skill, dust {id,min,max}, essence {id,min,max}, shard id
    { 5,  15, 1,   { STRANGE, 1, 2 },  { LMAGIC, 1, 2 },   nil   },
    { 16, 20, 1,   { STRANGE, 2, 3 },  { GMAGIC, 1, 2 },   SGLIM },
    { 21, 25, 25,  { STRANGE, 4, 6 },  { LASTRAL, 1, 2 },  SGLIM },
    { 26, 30, 50,  { SOUL, 1, 2 },     { GASTRAL, 1, 2 },  LGLIM },
    { 31, 35, 75,  { SOUL, 2, 5 },     { LMYSTIC, 1, 2 },  SGLOW },
    { 36, 40, 100, { VISION, 1, 2 },   { GMYSTIC, 1, 2 },  LGLOW },
    { 41, 45, 125, { VISION, 2, 5 },   { LNETHER, 1, 2 },  SRAD  },
    { 46, 50, 150, { DREAM, 1, 2 },    { GNETHER, 1, 2 },  LRAD  },
    { 51, 55, 175, { DREAM, 2, 5 },    { LETERNAL, 1, 2 }, SBRIL },
    { 56, 60, 200, { ILLUSION, 1, 2 }, { GETERNAL, 1, 2 }, LBRIL },
    { 61, 999, 225, { ILLUSION, 2, 5 }, { GETERNAL, 2, 3 }, LBRIL },
}
D.NexusCrystal = NEXUS
D.DEOdds = { armor = { dust = 0.75, essence = 0.20, shard = 0.05 },
             weapon = { dust = 0.20, essence = 0.75, shard = 0.05 } }

----------------------------------------------------------------------
-- Gear: equip location -> inventory slot(s)
----------------------------------------------------------------------
D.EquipSlots = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}
D.SlotNames = {
    [1] = "Head", [2] = "Neck", [3] = "Shoulder", [5] = "Chest", [6] = "Waist", [7] = "Legs",
    [8] = "Feet", [9] = "Wrist", [10] = "Hands", [11] = "Ring 1", [12] = "Ring 2",
    [13] = "Trinket 1", [14] = "Trinket 2", [15] = "Back", [16] = "Main hand", [17] = "Off hand",
    [18] = "Ranged",
}
D.SlotOrder = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }

-- Best armor type per class: { [armorSubclassID] = minimum level }.
-- 1 cloth, 2 leather, 3 mail, 4 plate.
D.ArmorBest = {
    WARRIOR = { [3] = 1, [4] = 40 }, PALADIN = { [3] = 1, [4] = 40 },
    HUNTER = { [2] = 1, [3] = 40 },  SHAMAN = { [2] = 1, [3] = 40 },
    ROGUE = { [2] = 1 }, DRUID = { [2] = 1 },
    PRIEST = { [1] = 1 }, MAGE = { [1] = 1 }, WARLOCK = { [1] = 1 },
}

-- Weapon subclass IDs each class can learn. 0 1h axe, 1 2h axe, 2 bow, 3 gun,
-- 4 1h mace, 5 2h mace, 6 polearm, 7 1h sword, 8 2h sword, 10 staff,
-- 13 fist, 15 dagger, 16 thrown, 18 crossbow, 19 wand, 20 fishing pole.
local function set(...) local t = {} for _, v in ipairs({ ... }) do t[v] = true end t[20] = true return t end
D.WeaponSkills = {
    WARRIOR = set(0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18),
    PALADIN = set(0, 1, 4, 5, 6, 7, 8),
    HUNTER  = set(0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18),
    ROGUE   = set(2, 3, 4, 7, 13, 15, 16, 18),
    PRIEST  = set(4, 10, 15, 19),
    SHAMAN  = set(0, 1, 4, 5, 10, 13, 15),
    MAGE    = set(7, 10, 15, 19),
    WARLOCK = set(7, 10, 15, 19),
    DRUID   = set(4, 5, 10, 13, 15),
}
D.DualWield = { WARRIOR = 20, ROGUE = 1, HUNTER = 20 }  -- class -> level learned

----------------------------------------------------------------------
-- Stat weights. Keys: str agi sta int spi ap rap sp heal crit hit
-- (crit/hit per 1%), haste mastery vers (ratings), armor, def, dodge,
-- parry, block, mp5, dps (weapon DPS). Rough leveling values.
----------------------------------------------------------------------
D.Weights = {
    GENERIC = {
        tank   = { sta = 1.0, str = 0.6, agi = 0.6, armor = 0.03, def = 1.0, dodge = 12, parry = 10, block = 4, dps = 1.5 },
        dps    = { str = 1.0, agi = 1.0, sta = 0.4, ap = 0.5, crit = 12, hit = 12, haste = 0.6, mastery = 0.5, vers = 0.5, dps = 3.0 },
        ranged = { agi = 1.0, sta = 0.4, int = 0.3, rap = 0.45, ap = 0.45, crit = 12, hit = 12, haste = 0.5, dps = 3.0 },
        caster = { int = 0.9, spi = 0.4, sta = 0.4, sp = 1.0, crit = 10, hit = 12, haste = 0.6, mp5 = 1.0 },
        heal   = { int = 1.0, spi = 0.6, sta = 0.3, heal = 0.9, sp = 0.9, mp5 = 1.5, crit = 6, haste = 0.5 },
    },
    WARRIOR = {
        dps  = { str = 1.0, agi = 0.6, sta = 0.5, ap = 0.5, crit = 14, hit = 14, armor = 0.005, dps = 4.0 },
        tank = { sta = 1.0, str = 0.5, agi = 0.6, armor = 0.04, def = 1.2, dodge = 12, parry = 10, block = 4, dps = 1.5 },
    },
    PALADIN = {
        dps  = { str = 1.0, int = 0.3, sta = 0.5, agi = 0.4, ap = 0.5, crit = 12, hit = 12, sp = 0.3, dps = 4.0 },
        tank = { sta = 1.0, str = 0.4, def = 1.2, armor = 0.04, block = 4, dodge = 10, parry = 10, sp = 0.5 },
        heal = { int = 1.0, spi = 0.3, sta = 0.3, heal = 0.9, sp = 0.9, mp5 = 1.5, crit = 8 },
    },
    HUNTER = {
        ranged = { agi = 1.0, int = 0.35, sta = 0.4, rap = 0.45, ap = 0.45, crit = 12, hit = 14, dps = 3.0 },
    },
    ROGUE = {
        dps = { agi = 1.0, str = 0.55, sta = 0.4, ap = 0.5, crit = 14, hit = 14, haste = 0.6, dps = 4.0 },
    },
    PRIEST = {
        caster = { int = 0.8, spi = 0.8, sta = 0.5, sp = 1.0, crit = 8, hit = 12, mp5 = 1.0 },
        heal   = { int = 1.0, spi = 0.8, sta = 0.3, heal = 0.9, sp = 0.9, mp5 = 1.5, crit = 6 },
    },
    SHAMAN = {
        dps    = { str = 1.0, agi = 0.7, int = 0.4, sta = 0.5, ap = 0.5, crit = 12, hit = 12, dps = 4.0 },
        caster = { int = 0.9, spi = 0.3, sta = 0.4, sp = 1.0, crit = 10, hit = 12, mp5 = 1.2 },
        heal   = { int = 1.0, spi = 0.4, sta = 0.3, heal = 0.9, sp = 0.9, mp5 = 1.6, crit = 6 },
    },
    MAGE = {
        caster = { int = 0.8, spi = 0.5, sta = 0.5, sp = 1.0, crit = 10, hit = 14, mp5 = 0.8 },
    },
    WARLOCK = {
        caster = { int = 0.6, spi = 0.5, sta = 0.8, sp = 1.0, crit = 6, hit = 14, mp5 = 0.6 },
    },
    DRUID = {
        dps    = { agi = 1.0, str = 1.0, sta = 0.5, ap = 0.5, crit = 12, hit = 12, armor = 0.01 },
        tank   = { sta = 1.0, agi = 0.8, armor = 0.05, str = 0.5, dodge = 12, def = 1.0 },
        caster = { int = 0.9, spi = 0.4, sta = 0.4, sp = 1.0, crit = 10, hit = 12, mp5 = 1.0 },
        heal   = { int = 1.0, spi = 0.8, sta = 0.3, heal = 0.9, sp = 0.9, mp5 = 1.5 },
    },
}

-- Specs per class. role is what you see (Tank / Healer / DPS); w picks the
-- stat weights above (melee "dps", "caster", "ranged", "tank", "heal");
-- tree is the talent tab it lives in.
local function spec(name, role, w, tree) return { name = name, role = role, w = w, tree = tree } end
D.Specs = {
    WARRIOR = { spec("Arms", "DPS", "dps", 1), spec("Fury", "DPS", "dps", 2), spec("Protection", "Tank", "tank", 3) },
    PALADIN = { spec("Holy", "Healer", "heal", 1), spec("Protection", "Tank", "tank", 2), spec("Retribution", "DPS", "dps", 3) },
    HUNTER  = { spec("Beast Mastery", "DPS", "ranged", 1), spec("Marksmanship", "DPS", "ranged", 2), spec("Survival", "DPS", "ranged", 3) },
    ROGUE   = { spec("Assassination", "DPS", "dps", 1), spec("Combat", "DPS", "dps", 2), spec("Subtlety", "DPS", "dps", 3) },
    PRIEST  = { spec("Discipline", "Healer", "heal", 1), spec("Holy", "Healer", "heal", 2), spec("Shadow", "DPS", "caster", 3) },
    SHAMAN  = { spec("Elemental", "DPS", "caster", 1), spec("Enhancement", "DPS", "dps", 2), spec("Restoration", "Healer", "heal", 3) },
    MAGE    = { spec("Arcane", "DPS", "caster", 1), spec("Fire", "DPS", "caster", 2), spec("Frost", "DPS", "caster", 3) },
    WARLOCK = { spec("Affliction", "DPS", "caster", 1), spec("Demonology", "DPS", "caster", 2), spec("Destruction", "DPS", "caster", 3) },
    DRUID   = { spec("Balance", "DPS", "caster", 1), spec("Feral (Cat)", "DPS", "dps", 2), spec("Feral (Bear)", "Tank", "tank", 2),
                spec("Restoration", "Healer", "heal", 3) },
}

----------------------------------------------------------------------
-- Recommended leveling builds (Classic). Trees may change in Forever:
-- missing talent names are shown as "not found" rather than as errors.
----------------------------------------------------------------------
D.LevelingBuilds = {
    WARRIOR = { tree = 1, name = "Arms (two-hander)",
        key = { "Improved Heroic Strike", "Deflection", "Tactical Mastery", "Deep Wounds",
                "Two-Handed Weapon Specialization", "Impale", "Sweeping Strikes", "Mortal Strike" },
        notes = "Use the best two-hander you can find. Fury dual-wield is fine at 60 with gear." },
    PALADIN = { tree = 3, name = "Retribution",
        key = { "Benediction", "Improved Judgement", "Improved Seal of the Crusader", "Deflection",
                "Vindication", "Conviction", "Seal of Command", "Two-Handed Weapon Specialization",
                "Sanctity Aura", "Vengeance", "Repentance" },
        notes = "Seal of Command + slow two-hander. Pick up Consecration in Holy late if you like." },
    HUNTER = { tree = 1, name = "Beast Mastery",
        key = { "Improved Aspect of the Hawk", "Endurance Training", "Thick Hide", "Unleashed Fury",
                "Ferocity", "Intimidation", "Bestial Discipline", "Frenzy", "Bestial Wrath" },
        notes = "Your pet tanks; keep it fed and its abilities trained." },
    ROGUE = { tree = 2, name = "Combat",
        key = { "Improved Sinister Strike", "Lightning Reflexes", "Precision", "Dual Wield Specialization",
                "Blade Flurry", "Sword Specialization", "Weapon Expertise", "Aggression", "Adrenaline Rush" },
        notes = "Slow main hand for Sinister Strike, fast off-hand." },
    PRIEST = { tree = 3, name = "Shadow (with Wand Specialization)",
        key = { "Wand Specialization", "Spirit Tap", "Improved Shadow Word: Pain", "Shadow Focus",
                "Mind Flay", "Shadow Reach", "Vampiric Embrace", "Shadowform" },
        notes = "Spirit Tap + wand finishes keep downtime low." },
    SHAMAN = { tree = 2, name = "Enhancement",
        key = { "Ancestral Knowledge", "Shield Specialization", "Thundering Strikes", "Two-Handed Axes and Maces",
                "Flurry", "Parry", "Weapon Mastery", "Stormstrike" },
        notes = "Two-handed weapon with Windfury/Rockbiter." },
    MAGE = { tree = 3, name = "Frost",
        key = { "Improved Frostbolt", "Elemental Precision", "Ice Shards", "Permafrost",
                "Piercing Ice", "Shatter", "Ice Block", "Ice Barrier" },
        notes = "AoE-pull with Blizzard once you have Improved Blizzard and Frost Nova." },
    WARLOCK = { tree = 1, name = "Affliction",
        key = { "Improved Corruption", "Fel Concentration", "Nightfall", "Grim Reach",
                "Siphon Life", "Shadow Mastery", "Dark Pact" },
        notes = "Voidwalker early; Drain Life + DoTs means almost no downtime." },
    DRUID = { tree = 2, name = "Feral",
        key = { "Ferocity", "Feral Instinct", "Thick Hide", "Sharpened Claws", "Feral Charge",
                "Blood Frenzy", "Primal Fury", "Savage Fury", "Heart of the Wild", "Leader of the Pack" },
        notes = "Cat form for solo, Bear for dungeons. Furor in Restoration is a strong first pick." },
}

----------------------------------------------------------------------
-- Leveling zones (Classic). faction: "Alliance", "Horde" or nil = both.
----------------------------------------------------------------------
D.Zones = {
    { "Elwynn Forest", 1, 10, "Alliance" }, { "Dun Morogh", 1, 10, "Alliance" }, { "Teldrassil", 1, 10, "Alliance" },
    { "Durotar", 1, 10, "Horde" }, { "Mulgore", 1, 10, "Horde" }, { "Tirisfal Glades", 1, 10, "Horde" },
    { "Westfall", 10, 20, "Alliance" }, { "Loch Modan", 10, 20, "Alliance" }, { "Darkshore", 10, 20, "Alliance" },
    { "The Barrens", 10, 25, "Horde" }, { "Silverpine Forest", 10, 20, "Horde" },
    { "Redridge Mountains", 15, 25, "Alliance" }, { "Stonetalon Mountains", 15, 27 },
    { "Ashenvale", 18, 30 }, { "Duskwood", 18, 30, "Alliance" }, { "Wetlands", 20, 30, "Alliance" },
    { "Hillsbrad Foothills", 20, 30 }, { "Thousand Needles", 25, 35 },
    { "Alterac Mountains", 30, 40 }, { "Arathi Highlands", 30, 40 }, { "Desolace", 30, 40 },
    { "Stranglethorn Vale", 30, 45 }, { "Dustwallow Marsh", 35, 45 }, { "Badlands", 35, 45 },
    { "Swamp of Sorrows", 35, 45 }, { "Feralas", 40, 50 }, { "Tanaris", 40, 50 },
    { "The Hinterlands", 40, 50 }, { "Searing Gorge", 43, 50 }, { "Azshara", 45, 55 },
    { "Blasted Lands", 45, 55 }, { "Felwood", 48, 55 }, { "Un'Goro Crater", 48, 55 },
    { "Burning Steppes", 50, 58 }, { "Western Plaguelands", 51, 58 }, { "Eastern Plaguelands", 53, 60 },
    { "Winterspring", 55, 60 }, { "Silithus", 55, 60 },
}

----------------------------------------------------------------------
-- Dungeons (Classic level ranges). Used to label dungeon-journal loot
-- with a level and as a fallback list when the journal isn't available.
----------------------------------------------------------------------
D.Dungeons = {
    { "Ragefire Chasm", 13, 18, "Horde" }, { "Wailing Caverns", 17, 24 }, { "The Deadmines", 17, 26, "Alliance" },
    { "Shadowfang Keep", 22, 30 }, { "Blackfathom Deeps", 24, 32 }, { "The Stockade", 24, 32, "Alliance" },
    { "Gnomeregan", 29, 38 }, { "Razorfen Kraul", 29, 38 }, { "Scarlet Monastery", 30, 45 },
    { "Razorfen Downs", 37, 46 }, { "Uldaman", 41, 51 }, { "Zul'Farrak", 42, 46 }, { "Maraudon", 46, 55 },
    { "Sunken Temple", 50, 56 }, { "Blackrock Depths", 52, 60 }, { "Lower Blackrock Spire", 55, 60 },
    { "Dire Maul", 55, 60 }, { "Scholomance", 58, 60 }, { "Stratholme", 58, 60 },
}

----------------------------------------------------------------------
-- Classic talent names per tree, in talent-tab order. Used to work out
-- your spec from the talents you've taken, whatever the talent window
-- looks like. Talents Forever renamed are simply not counted.
----------------------------------------------------------------------
local TALENTS = {
    WARRIOR = {
        "Improved Heroic Strike;Deflection;Improved Rend;Improved Charge;Tactical Mastery;Improved Thunder Clap;Improved Overpower;Anger Management;Deep Wounds;Two-Handed Weapon Specialization;Impale;Axe Specialization;Sweeping Strikes;Mace Specialization;Sword Specialization;Polearm Specialization;Improved Hamstring;Mortal Strike",
        "Booming Voice;Cruelty;Improved Demoralizing Shout;Unbridled Wrath;Improved Cleave;Piercing Howl;Blood Craze;Improved Battle Shout;Dual Wield Specialization;Improved Execute;Enrage;Improved Slam;Death Wish;Improved Intercept;Improved Berserker Rage;Flurry;Bloodthirst",
        "Shield Specialization;Anticipation;Improved Bloodrage;Toughness;Iron Will;Last Stand;Improved Shield Block;Improved Revenge;Defiance;Improved Sunder Armor;Improved Disarm;Improved Taunt;Improved Shield Wall;Concussion Blow;Improved Shield Bash;One-Handed Weapon Specialization;Shield Slam",
    },
    PALADIN = {
        "Divine Strength;Divine Intellect;Spiritual Focus;Improved Seal of Righteousness;Healing Light;Consecration;Improved Lay on Hands;Unyielding Faith;Illumination;Improved Blessing of Wisdom;Divine Favor;Lasting Judgement;Holy Power;Holy Shock",
        "Improved Devotion Aura;Redoubt;Precision;Guardian's Favor;Toughness;Blessing of Kings;Improved Righteous Fury;Shield Specialization;Blessing of Sanctuary;Reckoning;One-Handed Weapon Specialization;Improved Concentration Aura;Improved Hammer of Justice;Holy Shield",
        "Improved Blessing of Might;Benediction;Improved Judgement;Improved Seal of the Crusader;Deflection;Vindication;Conviction;Seal of Command;Pursuit of Justice;Eye for an Eye;Improved Retribution Aura;Two-Handed Weapon Specialization;Sanctity Aura;Vengeance;Repentance",
    },
    HUNTER = {
        "Improved Aspect of the Hawk;Endurance Training;Improved Eyes of the Beast;Improved Aspect of the Monkey;Thick Hide;Improved Revive Pet;Pathfinding;Bestial Swiftness;Unleashed Fury;Improved Mend Pet;Ferocity;Spirit Bond;Intimidation;Bestial Discipline;Frenzy;Bestial Wrath",
        "Improved Concussive Shot;Efficiency;Improved Hunter's Mark;Lethal Shots;Aimed Shot;Improved Arcane Shot;Hawk Eye;Improved Serpent Sting;Mortal Shots;Scatter Shot;Barrage;Improved Scorpid Sting;Ranged Weapon Specialization;Trueshot Aura",
        "Monster Slaying;Humanoid Slaying;Deflection;Entrapment;Savage Strikes;Improved Wing Clip;Clever Traps;Survivalist;Deterrence;Trap Mastery;Surefooted;Improved Feign Death;Killer Instinct;Counterattack;Lightning Reflexes;Wyvern Sting",
    },
    ROGUE = {
        "Improved Eviscerate;Remorseless Attacks;Malice;Ruthlessness;Murder;Improved Slice and Dice;Relentless Strikes;Improved Expose Armor;Lethality;Vile Poisons;Improved Poisons;Cold Blood;Improved Kidney Shot;Seal Fate;Vigor",
        "Improved Gouge;Improved Sinister Strike;Lightning Reflexes;Improved Backstab;Deflection;Precision;Endurance;Riposte;Improved Sprint;Improved Kick;Dagger Specialization;Dual Wield Specialization;Mace Specialization;Blade Flurry;Sword Specialization;Fist Weapon Specialization;Weapon Expertise;Aggression;Adrenaline Rush",
        "Master of Deception;Opportunity;Sleight of Hand;Elusiveness;Camouflage;Initiative;Ghostly Strike;Improved Ambush;Setup;Improved Sap;Serrated Blades;Heightened Senses;Preparation;Dirty Deeds;Hemorrhage;Deadliness;Premeditation",
    },
    PRIEST = {
        "Unbreakable Will;Wand Specialization;Silent Resolve;Improved Power Word: Fortitude;Improved Power Word: Shield;Martyrdom;Inner Focus;Meditation;Improved Inner Fire;Mental Agility;Improved Mana Burn;Mental Strength;Divine Spirit;Force of Will;Power Infusion",
        "Healing Focus;Improved Renew;Holy Specialization;Spell Warding;Divine Fury;Holy Nova;Blessed Recovery;Inspiration;Holy Reach;Improved Healing;Searing Light;Improved Prayer of Healing;Spirit of Redemption;Spiritual Guidance;Spiritual Healing;Lightwell",
        "Spirit Tap;Blackout;Shadow Affinity;Improved Shadow Word: Pain;Shadow Focus;Improved Psychic Scream;Improved Mind Blast;Mind Flay;Improved Fade;Shadow Reach;Shadow Weaving;Silence;Vampiric Embrace;Improved Vampiric Embrace;Darkness;Shadowform",
    },
    SHAMAN = {
        "Convection;Concussion;Earth's Grasp;Elemental Warding;Call of Flame;Elemental Focus;Reverberation;Call of Thunder;Improved Fire Totems;Eye of the Storm;Elemental Devastation;Storm Reach;Elemental Fury;Lightning Mastery;Elemental Mastery",
        "Ancestral Knowledge;Shield Specialization;Guardian Totems;Thundering Strikes;Improved Ghost Wolf;Improved Lightning Shield;Enhancing Totems;Two-Handed Axes and Maces;Anticipation;Flurry;Toughness;Improved Weapon Totems;Elemental Weapons;Parry;Weapon Mastery;Stormstrike",
        "Improved Healing Wave;Tidal Focus;Improved Reincarnation;Ancestral Healing;Totemic Focus;Nature's Guidance;Healing Focus;Totemic Mastery;Healing Grace;Restorative Totems;Tidal Mastery;Healing Way;Nature's Swiftness;Purification;Mana Tide Totem",
    },
    MAGE = {
        "Arcane Subtlety;Arcane Focus;Improved Arcane Missiles;Wand Specialization;Magic Absorption;Arcane Concentration;Magic Attunement;Improved Arcane Explosion;Arcane Resilience;Improved Mana Shield;Improved Counterspell;Arcane Meditation;Presence of Mind;Arcane Mind;Arcane Instability;Arcane Power",
        "Improved Fireball;Impact;Ignite;Flame Throwing;Improved Fire Blast;Incinerate;Improved Flamestrike;Pyroblast;Burning Soul;Improved Scorch;Improved Fire Ward;Master of Elements;Critical Mass;Blast Wave;Fire Power;Combustion",
        "Frost Warding;Improved Frostbolt;Elemental Precision;Ice Shards;Frostbite;Improved Frost Nova;Permafrost;Piercing Ice;Cold Snap;Improved Blizzard;Arctic Reach;Frost Channeling;Shatter;Ice Block;Improved Cone of Cold;Winter's Chill;Ice Barrier",
    },
    WARLOCK = {
        "Suppression;Improved Corruption;Improved Curse of Weakness;Improved Drain Soul;Improved Life Tap;Improved Drain Life;Improved Curse of Agony;Fel Concentration;Amplify Curse;Grim Reach;Nightfall;Improved Drain Mana;Siphon Life;Curse of Exhaustion;Improved Curse of Exhaustion;Shadow Mastery;Dark Pact",
        "Improved Healthstone;Improved Imp;Demonic Embrace;Improved Health Funnel;Improved Voidwalker;Fel Intellect;Improved Succubus;Fel Domination;Fel Stamina;Master Summoner;Unholy Power;Improved Enslave Demon;Demonic Sacrifice;Improved Firestone;Master Demonologist;Soul Link;Improved Spellstone",
        "Improved Shadow Bolt;Cataclysm;Bane;Aftermath;Improved Firebolt;Improved Lash of Pain;Devastation;Shadowburn;Intensity;Destructive Reach;Improved Searing Pain;Pyroclasm;Improved Immolate;Ruin;Emberstorm;Conflagrate",
    },
    DRUID = {
        "Improved Wrath;Nature's Grasp;Improved Nature's Grasp;Improved Entangling Roots;Improved Moonfire;Natural Weapons;Natural Shapeshifter;Improved Thorns;Omen of Clarity;Nature's Reach;Vengeance;Improved Starfire;Nature's Grace;Moonglow;Moonfury;Moonkin Form",
        "Ferocity;Feral Aggression;Feral Instinct;Brutal Impact;Thick Hide;Feline Swiftness;Feral Charge;Sharpened Claws;Improved Shred;Predatory Strikes;Blood Frenzy;Primal Fury;Savage Fury;Faerie Fire (Feral);Heart of the Wild;Leader of the Pack",
        "Improved Mark of the Wild;Furor;Improved Healing Touch;Nature's Focus;Improved Enrage;Reflection;Insect Swarm;Subtlety;Tranquil Spirit;Improved Rejuvenation;Nature's Swiftness;Gift of Nature;Improved Tranquility;Improved Regrowth;Swiftmend",
    },
}
-- D.TalentTree[class][lowercase talent name] = tree index
D.TalentTree = {}
for class, trees in pairs(TALENTS) do
    local map = {}
    for tree, list in ipairs(trees) do
        for name in list:gmatch("[^;]+") do map[name:lower()] = tree end
    end
    D.TalentTree[class] = map
end

----------------------------------------------------------------------
-- WoW Forever talent builds: the order to spend points, one entry per
-- pick ("Talent:points"). Used to say which talent is best to take next.
-- Add more specs in the same format.
----------------------------------------------------------------------
D.ForeverBuilds = {
    PRIEST = {
        Discipline = {
            name = "Discipline leveling (10-60)",
            source = "kami-labs.fr, based on Icy Veins' Forever leveling guide",
            order = "Wand Specialization:2,Spirit Tap:5,Twilight Focus:3,Power in Light:5,Mental Strength:3,Meditation:3,"
                .. "Mental Strength:2,Improved Power Word: Shield:3,Soul Warding:1,Mental Agility:1,Penance:1,Renewed Hope:4,"
                .. "Divine Aegis:1,Renewed Hope:1,Divine Aegis:2,Mental Agility:1,Power Infusion:1,Holy Specialization:5,"
                .. "Divine Fury:5,Mental Agility:1,Inner Focus:1",
            notes = {
                ["Spirit Tap"] = "Shadow talent the guide takes early: big mana and health regen after kills while leveling.",
                ["Twilight Focus"] = "Worth more when leveling solo than in groups.",
                ["Penance"] = "Key Discipline ability.",
                ["Renewed Hope"] = "Only procs from direct (non-periodic) heals.",
                ["Divine Aegis"] = "Only procs from direct (non-periodic) heals; strong for keeping one target alive.",
                ["Power Infusion"] = "Guides rate it a weak capstone; take it after the core talents.",
            },
        },
    },
}

-- Forever-only talents and which classic tree they sit in (1, 2, 3).
D.ForeverTalentTree = {
    PRIEST = {
        ["power in light"] = 1, ["twin disciplines"] = 1, ["soul warding"] = 1, ["penance"] = 1,
        ["renewed hope"] = 1, ["divine aegis"] = 1, ["holy precision"] = 1, ["litany of light"] = 1,
        ["twilight focus"] = 2, ["holy binding"] = 2, ["prayer of mending"] = 2,
        ["dark inspiration"] = 3, ["devouring contagion"] = 3, ["early demise"] = 3, ["improved mind flay"] = 3,
    },
}
for class, map in pairs(D.ForeverTalentTree) do
    D.TalentTree[class] = D.TalentTree[class] or {}
    for name, tree in pairs(map) do D.TalentTree[class][name] = tree end
end

-- Display names for the stat keys used in scoring.
D.StatNames = {
    str = "Strength", agi = "Agility", sta = "Stamina", int = "Intellect", spi = "Spirit",
    ap = "Attack Power", rap = "Ranged Attack Power", sp = "Spell Power", heal = "Healing",
    crit = "Crit", hit = "Hit", haste = "Haste", mastery = "Mastery", vers = "Versatility",
    armor = "Armor", def = "Defense", dodge = "Dodge", parry = "Parry", block = "Block",
    mp5 = "Mana per 5", dps = "Weapon DPS",
}
D.PercentStats = { crit = true, hit = true, dodge = true, parry = true, block = true }
