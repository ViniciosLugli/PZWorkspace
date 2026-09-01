# Lugli - Achievements

Project Zomboid **B42** has no achievements. This adds 250+ of them, earned by what your survivor
actually does. Every one is listed in [the roster](#the-roster) at the end, with the icon, name,
description and goal the game shows.

Needs [NeatUI Framework](https://steamcommunity.com/sharedfiles/filedetails/?id=3508537032) for the
window and the toast. Pure Lua otherwise, no jar.

**It changes nothing about how the game plays.** No items, no XP, no loot, no spawns, no recipes.
It watches, it counts, and it tells you.

![The categories, and a sample of the art](art/ach-categories.png)

![The achievements window](art/window.png)

## Where progress lives

Per world by default: one collection shared by every survivor in the save, so a death does not
restart it. That is also what lets an achievement be earned **by** dying, at the moment the
character earning it stops existing, and lets the ledger record who got there first.

A tickbox in the mod options switches to per character. Switching deletes nothing: the two are
separate stores, and turning it back brings the old one straight back.

Both are `ModData` tables of the mod's own. Nothing else in the save is touched, and the per-world
store is `GlobalModData`, which only crosses the wire if a mod asks it to. This one never does.

## Adding your own

```lua
LugliAchievements.register{
    id          = "yourmod_thing_10",
    name        = "UI_YourMod_thing_10_name",
    description = "UI_YourMod_thing_10_desc",
    category    = "yourmod_cat",
    stat        = "yourmod_things",
    target      = 10,
    tier        = "silver",
    source      = "YourMod",
}

LugliAchievements.incStat(player, "yourmod_things", 1)
```

It appears in the window, tracks itself, saves itself and raises its own toast.

`icon` is optional: leave it out and the id decides the path. `registerCategory` adds a category.
First registration of an id wins; a duplicate is rejected and logged with both sources. A condition
that is not a running total is a stat set to 1 with `target = 1`.

Achievements are indexed by the stat they watch, so `incStat` only ever wakes the handful watching
that stat, never the whole roster.

## Reliability

Every achievement is checked against the trackers at build time, so one watching a counter nothing
writes cannot ship. Two offline suites run in the game's own Kahlua VM against the real shipped
files, with mutation tests proving the suites can fail.

Timed-action wrappers call through first and count afterwards inside `pcall`, so a counting bug
cannot break the action it watches. A part that fails to install says so on the main menu.

## Compatibility

- **Mid-save:** anything the game still knows about is credited on the next load, so days survived
  and recipes known come across immediately. Counters that only existed because the mod was
  watching, like kills and things built, start from zero. Skill levels register on the next level.
- **Removal:** safe. The save loads normally; reinstall and your progress is still there.
- **Multiplayer:** every player keeps their own collection against a server. Nobody else's kills
  unlock yours.
- **Dedicated server:** nothing loads. `client/` does not run in a server process, so no tracker
  registers, the roster is never built, and nothing is written to server state. Verified against a
  real headless server.
- English and Brazilian Portuguese, both complete. A build gate refuses a language missing a key.

## The roster

Every achievement that ships, with the icon, name, description and goal the game itself uses.
The tables below are generated from the mod's own definitions and its English translations, so
they cannot drift from what you actually play.

<!-- BEGIN ROSTER: generated from the shipped definitions. Do not edit by hand. -->

| | Category | Achievements | Bronze | Silver | Gold |
|---|---|--:|--:|--:|--:|
| <img src="assets/media/ui/achievements/cat/waking_up.png" width="28" alt=""> | [Waking Up](#waking-up) | 12 | 12 | 0 | 0 |
| <img src="assets/media/ui/achievements/cat/body_count.png" width="28" alt=""> | [Body Count](#body-count) | 31 | 5 | 23 | 3 |
| <img src="assets/media/ui/achievements/cat/still_breathing.png" width="28" alt=""> | [Still Breathing](#still-breathing) | 19 | 5 | 12 | 2 |
| <img src="assets/media/ui/achievements/cat/autodidact.png" width="28" alt=""> | [Autodidact](#autodidact) | 18 | 4 | 10 | 4 |
| <img src="assets/media/ui/achievements/cat/nailed_it.png" width="28" alt=""> | [Nailed It](#nailed-it) | 25 | 8 | 15 | 2 |
| <img src="assets/media/ui/achievements/cat/homestead.png" width="28" alt=""> | [Homestead](#homestead) | 35 | 10 | 21 | 4 |
| <img src="assets/media/ui/achievements/cat/field_medicine.png" width="28" alt=""> | [Field Medicine](#field-medicine) | 14 | 5 | 8 | 1 |
| <img src="assets/media/ui/achievements/cat/roadside.png" width="28" alt=""> | [Roadside Attractions](#roadside-attractions) | 28 | 11 | 12 | 5 |
| <img src="assets/media/ui/achievements/cat/house_proud.png" width="28" alt=""> | [House Proud](#house-proud) | 31 | 10 | 17 | 4 |
| <img src="assets/media/ui/achievements/cat/how_you_died.png" width="28" alt=""> | [This Is How You Died](#this-is-how-you-died) | 17 | 13 | 4 | 0 |
| <img src="assets/media/ui/achievements/cat/secrets.png" width="28" alt=""> | [Secrets](#secrets) | 16 | 7 | 6 | 3 |
| <img src="assets/media/ui/achievements/cat/milestones.png" width="28" alt=""> | [Milestones](#milestones) | 12 | 0 | 0 | 12 |
| | **Total** | **258** | **90** | **128** | **40** |

### Waking Up

| | Achievement | How you get it | Goal | Tier |
|---|---|---|---|---|
| <img src="assets/media/ui/achievements/small/waking_smash_1.png" width="40" alt=""> | **Fresh Air** | Smash your first window. Nobody is coming to bill you for it | once | Bronze |
| <img src="assets/media/ui/achievements/small/waking_window_1.png" width="40" alt=""> | **In Through The Out** | Climb through your first window | once | Bronze |
| <img src="assets/media/ui/achievements/small/waking_fence_1.png" width="40" alt=""> | **Fence Sitter** | Climb over your first fence | once | Bronze |
| <img src="assets/media/ui/achievements/small/waking_burden_1.png" width="40" alt=""> | **Load Bearing** | Become overburdened for the first time | once | Bronze |
| <img src="assets/media/ui/achievements/small/waking_forage_1.png" width="40" alt=""> | **Ground Score** | Forage your first item off the ground | once | Bronze |
| <img src="assets/media/ui/achievements/small/waking_craft_1.png" width="40" alt=""> | **Hand Made** | Craft your first item | once | Bronze |
| <img src="assets/media/ui/achievements/small/waking_build_1.png" width="40" alt=""> | **First Fixture** | Build your first thing | once | Bronze |
| <img src="assets/media/ui/achievements/small/waking_drive_1.png" width="40" alt=""> | **Learner Plates** | Get into a vehicle | once | Bronze |
| <img src="assets/media/ui/achievements/small/waking_read_1.png" width="40" alt=""> | **Chapter One** | Finish reading your first book | once | Bronze |
| <img src="assets/media/ui/achievements/small/waking_rope_1.png" width="40" alt=""> | **Rope Access** | Tie your first sheet rope | once | Bronze |
| <img src="assets/media/ui/achievements/small/waking_day_2.png" width="40" alt=""> | **Day Two** | Live to see a second morning | once | Bronze |
| <img src="assets/media/ui/achievements/small/waking_map_1.png" width="40" alt=""> | **You Are Here** | Read a map | once | Bronze |

### Body Count

| | Achievement | How you get it | Goal | Tier |
|---|---|---|---|---|
| <img src="assets/media/ui/achievements/small/combat_kill_1.png" width="40" alt=""> | **First Blood** | Kill your first zombie. There are a few more | once | Bronze |
| <img src="assets/media/ui/achievements/small/combat_kill_100.png" width="40" alt=""> | **Getting The Hang** | Kill one hundred zombies | 100 zombies | Silver |
| <img src="assets/media/ui/achievements/small/combat_kill_1000.png" width="40" alt=""> | **Thinning The Herd** | Kill one thousand zombies | 1,000 zombies | Silver |
| <img src="assets/media/ui/achievements/small/combat_kill_5000.png" width="40" alt=""> | **Population Control** | Kill five thousand zombies | 5,000 zombies | Gold |
| <img src="assets/media/ui/achievements/small/combat_kill_10000.png" width="40" alt=""> | **Hero Syndrome** | Kill ten thousand zombies. You were going to clear Louisville | 10,000 zombies | Gold |
| <img src="assets/media/ui/achievements/small/combat_axe_250.png" width="40" alt=""> | **Timber** | Kill 250 zombies with an axe | 250 zombies | Silver |
| <img src="assets/media/ui/achievements/small/combat_blunt_250.png" width="40" alt=""> | **Blunt Instrument** | Kill 250 zombies with a blunt weapon | 250 zombies | Silver |
| <img src="assets/media/ui/achievements/small/combat_smallblunt_150.png" width="40" alt=""> | **Pocket Percussion** | Kill 150 zombies with a small blunt weapon | 150 zombies | Silver |
| <img src="assets/media/ui/achievements/small/combat_longblade_150.png" width="40" alt=""> | **Clean Sweep** | Kill 150 zombies with a long blade | 150 zombies | Silver |
| <img src="assets/media/ui/achievements/small/combat_smallblade_150.png" width="40" alt=""> | **Up Close** | Kill 150 zombies with a small blade | 150 zombies | Silver |
| <img src="assets/media/ui/achievements/small/combat_spear_100.png" width="40" alt=""> | **Arms Length** | Kill 100 zombies with a spear | 100 zombies | Silver |
| <img src="assets/media/ui/achievements/small/combat_unarmed_25.png" width="40" alt=""> | **Bare Hands** | Kill 25 zombies with your hands | 25 zombies | Silver |
| <img src="assets/media/ui/achievements/small/combat_improvised_100.png" width="40" alt=""> | **Whatever Was Handy** | Kill 100 zombies with an improvised weapon | 100 zombies | Silver |
| <img src="assets/media/ui/achievements/small/combat_allclasses_8.png" width="40" alt=""> | **Full Toolbox** | Kill a zombie with all eight weapon classes | 8 | Silver |
| <img src="assets/media/ui/achievements/small/combat_downed_100.png" width="40" alt=""> | **Double Tap** | Finish off one hundred downed zombies | 100 zombies | Silver |
| <img src="assets/media/ui/achievements/small/combat_onehit_100.png" width="40" alt=""> | **One And Done** | Kill one hundred zombies in a single hit | 100 zombies | Silver |
| <img src="assets/media/ui/achievements/small/combat_head_500.png" width="40" alt=""> | **Aim For The Head** | Land five hundred hits on the head | 500 | Silver |
| <img src="assets/media/ui/achievements/small/combat_crit_250.png" width="40" alt=""> | **Weak Point** | Land 250 critical hits | 250 | Silver |
| <img src="assets/media/ui/achievements/small/combat_walkaway_1.png" width="40" alt=""> | **You Can Just Walk** | Survive a day with no kills after your first hundred | once | Bronze |
| <img src="assets/media/ui/achievements/small/noise_shot_1.png" width="40" alt=""> | **Loud Noises** | Fire a gun. Everyone heard that | once | Bronze |
| <img src="assets/media/ui/achievements/small/noise_shot_100.png" width="40" alt=""> | **Trigger Discipline** | Fire one hundred shots | 100 shots | Silver |
| <img src="assets/media/ui/achievements/small/noise_shot_1000.png" width="40" alt=""> | **Ammo Economy** | Fire one thousand shots | 1,000 shots | Silver |
| <img src="assets/media/ui/achievements/small/noise_gunkill_1.png" width="40" alt=""> | **Point Blank** | Kill a zombie with a firearm | once | Bronze |
| <img src="assets/media/ui/achievements/small/noise_gunkill_500.png" width="40" alt=""> | **Gun Nut** | Kill 500 zombies with firearms | 500 zombies | Gold |
| <img src="assets/media/ui/achievements/small/noise_guns_22.png" width="40" alt=""> | **The Whole Armoury** | Fire all twenty two firearms | 22 | Silver |
| <img src="assets/media/ui/achievements/small/noise_reload_100.png" width="40" alt=""> | **Muscle Memory** | Reload one hundred times | 100 | Silver |
| <img src="assets/media/ui/achievements/small/noise_rack_50.png" width="40" alt=""> | **Rack And Ruin** | Rack a weapon fifty times | 50 | Silver |
| <img src="assets/media/ui/achievements/small/noise_upgrade_10.png" width="40" alt=""> | **Aftermarket** | Fit ten weapon upgrades | 10 | Silver |
| <img src="assets/media/ui/achievements/small/noise_boom_1.png" width="40" alt=""> | **We Need More Boom** | Set off your first explosive | once | Bronze |
| <img src="assets/media/ui/achievements/small/noise_boom_25.png" width="40" alt=""> | **Demolition Permit** | Set off twenty five explosives | 25 | Silver |
| <img src="assets/media/ui/achievements/small/noise_alarm_10.png" width="40" alt=""> | **Ringing Endorsement** | Trip ten house alarms and live | 10 | Silver |

### Still Breathing

| | Achievement | How you get it | Goal | Tier |
|---|---|---|---|---|
| <img src="assets/media/ui/achievements/small/survive_days_7.png" width="40" alt=""> | **Nine To Five** | Survive seven days. A full working week, and no weekend | 7 days | Silver |
| <img src="assets/media/ui/achievements/small/survive_days_28.png" width="40" alt=""> | **Twenty Eight Days** | Survive twenty eight days, when the horde peaks | 28 days | Silver |
| <img src="assets/media/ui/achievements/small/survive_days_90.png" width="40" alt=""> | **Seasonal Worker** | Survive ninety days | 90 days | Silver |
| <img src="assets/media/ui/achievements/small/survive_days_180.png" width="40" alt=""> | **Half A Year Gone** | Survive one hundred and eighty days | 180 days | Silver |
| <img src="assets/media/ui/achievements/small/survive_days_365.png" width="40" alt=""> | **Anniversary** | Survive a full year with one survivor | 365 days | Gold |
| <img src="assets/media/ui/achievements/small/survive_days_730.png" width="40" alt=""> | **Two Years Gone** | Survive two years with one survivor | 730 days | Gold |
| <img src="assets/media/ui/achievements/small/survive_heli_1.png" width="40" alt=""> | **Helicopter Parenting** | Live through the helicopter. It was never a rescue | once | Bronze |
| <img src="assets/media/ui/achievements/small/survive_winter_1.png" width="40" alt=""> | **First Frost** | Survive into winter | once | Bronze |
| <img src="assets/media/ui/achievements/small/survive_seasons_4.png" width="40" alt=""> | **Round The Sun** | See all four seasons on one character | 4 | Silver |
| <img src="assets/media/ui/achievements/small/survive_blizzard_1.png" width="40" alt=""> | **Whiteout** | Live through a blizzard | once | Bronze |
| <img src="assets/media/ui/achievements/small/survive_tropical_1.png" width="40" alt=""> | **Weather The Storm** | Live through a tropical storm | once | Bronze |
| <img src="assets/media/ui/achievements/small/survive_thunder_50.png" width="40" alt=""> | **Counting Seconds** | Be outdoors for fifty thunder strikes | 50 | Silver |
| <img src="assets/media/ui/achievements/small/survive_nodamage_7.png" width="40" alt=""> | **Untouchable** | Go seven days without taking a hit | 7 days | Silver |
| <img src="assets/media/ui/achievements/small/survive_moodles_8.png" width="40" alt=""> | **How Did We Get Here** | Carry eight negative moodles at once | 8 | Silver |
| <img src="assets/media/ui/achievements/small/survive_sleep_50.png" width="40" alt=""> | **Sleep Tight** | Climb into a bed fifty times | 50 | Silver |
| <img src="assets/media/ui/achievements/small/survive_rest_100.png" width="40" alt=""> | **Take Five** | Rest one hundred times | 100 | Silver |
| <img src="assets/media/ui/achievements/small/survive_water_500.png" width="40" alt=""> | **Staying Hydrated** | Drink five hundred times | 500 | Silver |
| <img src="assets/media/ui/achievements/small/survive_noxious_1.png" width="40" alt=""> | **Something Died** | Get the noxious smell moodle | once | Bronze |
| <img src="assets/media/ui/achievements/small/survive_awake_72.png" width="40" alt=""> | **Wired** | Stay awake for three days straight | 72 | Silver |

### Autodidact

| | Achievement | How you get it | Goal | Tier |
|---|---|---|---|---|
| <img src="assets/media/ui/achievements/small/learn_level_10.png" width="40" alt=""> | **Master Of One** | Take any skill to level ten | 10 | Silver |
| <img src="assets/media/ui/achievements/small/learn_perks3_10.png" width="40" alt=""> | **Jack Of All Trades** | Reach level three in ten different skills | 10 | Silver |
| <img src="assets/media/ui/achievements/small/learn_perks5_5.png" width="40" alt=""> | **Well Rounded** | Reach level five in five different skills | 5 | Silver |
| <img src="assets/media/ui/achievements/small/learn_perks10_3.png" width="40" alt=""> | **Overqualified** | Reach level ten in three different skills | 3 | Gold |
| <img src="assets/media/ui/achievements/small/learn_perks1_35.png" width="40" alt=""> | **Dabbler** | Reach level one in all thirty five skills | 35 | Gold |
| <img src="assets/media/ui/achievements/small/learn_books_10.png" width="40" alt=""> | **Well Read** | Finish ten books | 10 books | Bronze |
| <img src="assets/media/ui/achievements/small/learn_books_50.png" width="40" alt=""> | **Library Card** | Finish fifty books | 50 books | Silver |
| <img src="assets/media/ui/achievements/small/learn_books_120.png" width="40" alt=""> | **Every Last Volume** | Finish all one hundred and twenty skill books | 120 books | Gold |
| <img src="assets/media/ui/achievements/small/learn_mag_50.png" width="40" alt=""> | **Back Issues** | Read fifty recipe magazines | 50 magazines | Silver |
| <img src="assets/media/ui/achievements/small/learn_recipes_50.png" width="40" alt=""> | **Recipe Collector** | Know fifty recipes | 50 recipes | Bronze |
| <img src="assets/media/ui/achievements/small/learn_recipes_300.png" width="40" alt=""> | **Encyclopedic** | Know three hundred recipes | 300 recipes | Gold |
| <img src="assets/media/ui/achievements/small/learn_research_25.png" width="40" alt=""> | **Reverse Engineer** | Research twenty five recipes | 25 | Silver |
| <img src="assets/media/ui/achievements/small/learn_carpentry_10.png" width="40" alt=""> | **Measure Twice** | Reach Carpentry level ten | 10 | Silver |
| <img src="assets/media/ui/achievements/small/learn_doctor_5.png" width="40" alt=""> | **Barely Qualified** | Reach First Aid level five | 5 | Bronze |
| <img src="assets/media/ui/achievements/small/learn_mechanics_7.png" width="40" alt=""> | **Grease Under Nails** | Reach Mechanics level seven | 7 | Silver |
| <img src="assets/media/ui/achievements/small/learn_blacksmith_7.png" width="40" alt=""> | **Village Smithy** | Reach Blacksmith level seven | 7 | Silver |
| <img src="assets/media/ui/achievements/small/learn_lose_1.png" width="40" alt=""> | **Use It Or Lose It** | Lose a skill level | once | Bronze |
| <img src="assets/media/ui/achievements/small/learn_xp_100000.png" width="40" alt=""> | **Serious Dedication** | Earn one hundred thousand XP | 100,000 | Silver |

### Nailed It

| | Achievement | How you get it | Goal | Tier |
|---|---|---|---|---|
| <img src="assets/media/ui/achievements/small/fire_light_1.png" width="40" alt=""> | **Prometheus** | Light your first fire | once | Bronze |
| <img src="assets/media/ui/achievements/small/fire_literature_1.png" width="40" alt=""> | **Burning The Books** | Light a fire with a book | once | Bronze |
| <img src="assets/media/ui/achievements/small/fire_petrol_10.png" width="40" alt=""> | **Accelerant** | Light ten fires with petrol | 10 | Silver |
| <img src="assets/media/ui/achievements/small/fire_out_25.png" width="40" alt=""> | **Fire Marshal** | Put out twenty five fires | 25 | Silver |
| <img src="assets/media/ui/achievements/small/fire_candle_50.png" width="40" alt=""> | **Candlelight** | Snuff out fifty candles | 50 | Silver |
| <img src="assets/media/ui/achievements/small/fire_ashes_25.png" width="40" alt=""> | **Cold Hearth** | Clear ashes twenty five times | 25 | Silver |
| <img src="assets/media/ui/achievements/small/fire_bbq_100.png" width="40" alt=""> | **Grill Master** | Light or refuel a barbecue one hundred times | 100 | Silver |
| <img src="assets/media/ui/achievements/small/fire_molotov_25.png" width="40" alt=""> | **Cocktail Hour** | Throw twenty five molotovs | 25 | Silver |
| <img src="assets/media/ui/achievements/small/fire_selfless_1.png" width="40" alt=""> | **This Is Fine** | Set yourself alight and survive it | once | Bronze |
| <img src="assets/media/ui/achievements/small/build_things_10.png" width="40" alt=""> | **Some Assembly** | Build ten things | 10 things | Bronze |
| <img src="assets/media/ui/achievements/small/build_things_100.png" width="40" alt=""> | **Contractor** | Build one hundred things | 100 things | Silver |
| <img src="assets/media/ui/achievements/small/build_things_500.png" width="40" alt=""> | **Zoning Violation** | Build five hundred things | 500 things | Gold |
| <img src="assets/media/ui/achievements/small/build_barricade_10.png" width="40" alt=""> | **Board Meeting** | Put up ten barricades | 10 | Bronze |
| <img src="assets/media/ui/achievements/small/build_barricade_50.png" width="40" alt=""> | **Squatters Rights** | Put up fifty barricades | 50 | Silver |
| <img src="assets/media/ui/achievements/small/build_wall_25.png" width="40" alt=""> | **Wall To Wall** | Build twenty five walls | 25 | Silver |
| <img src="assets/media/ui/achievements/small/build_gen_1.png" width="40" alt=""> | **Let There Be Light** | Hook up and start a generator | once | Bronze |
| <img src="assets/media/ui/achievements/small/build_gen_5.png" width="40" alt=""> | **Grid Independence** | Start five generators | 5 | Silver |
| <img src="assets/media/ui/achievements/small/build_safehouse_1.png" width="40" alt=""> | **Home Sweet Home** | Claim a safehouse | once | Bronze |
| <img src="assets/media/ui/achievements/small/build_craft_100.png" width="40" alt=""> | **Cottage Industry** | Craft one hundred items | 100 items | Silver |
| <img src="assets/media/ui/achievements/small/build_craft_1000.png" width="40" alt=""> | **Wax On** | Craft one thousand items | 1,000 items | Gold |
| <img src="assets/media/ui/achievements/small/build_rooms_10.png" width="40" alt=""> | **Interior Design** | Build in ten different rooms | 10 | Silver |
| <img src="assets/media/ui/achievements/small/build_dismantle_100.png" width="40" alt=""> | **Salvage Rights** | Dismantle one hundred things | 100 | Silver |
| <img src="assets/media/ui/achievements/small/build_padlock_10.png" width="40" alt=""> | **Keep Out** | Fit ten padlocks | 10 | Silver |
| <img src="assets/media/ui/achievements/small/build_stairs_1.png" width="40" alt=""> | **Going Down** | Dig a staircase | once | Bronze |
| <img src="assets/media/ui/achievements/small/build_plumb_5.png" width="40" alt=""> | **Indoor Plumbing** | Plumb five things | 5 | Silver |

### Homestead

| | Achievement | How you get it | Goal | Tier |
|---|---|---|---|---|
| <img src="assets/media/ui/achievements/small/farm_harvest_1.png" width="40" alt=""> | **Green Thumb** | Harvest your first crop | once | Bronze |
| <img src="assets/media/ui/achievements/small/farm_harvest_50.png" width="40" alt=""> | **Subsistence** | Harvest fifty crops | 50 crops | Silver |
| <img src="assets/media/ui/achievements/small/farm_plant_25.png" width="40" alt=""> | **Seed Money** | Plant twenty five seeds | 25 | Silver |
| <img src="assets/media/ui/achievements/small/farm_crops_12.png" width="40" alt=""> | **Crop Rotation** | Grow all twelve kinds of crop | 12 | Silver |
| <img src="assets/media/ui/achievements/small/farm_water_100.png" width="40" alt=""> | **Watering Can** | Water a plant one hundred times | 100 | Silver |
| <img src="assets/media/ui/achievements/small/farm_compost_25.png" width="40" alt=""> | **Rot Economy** | Add to a compost heap twenty five times | 25 | Silver |
| <img src="assets/media/ui/achievements/small/farm_scythe_100.png" width="40" alt=""> | **Reaper** | Scythe one hundred times | 100 | Silver |
| <img src="assets/media/ui/achievements/small/farm_tree_100.png" width="40" alt=""> | **Deforestation** | Chop down one hundred trees | 100 | Silver |
| <img src="assets/media/ui/achievements/small/farm_fish_1.png" width="40" alt=""> | **Hooked** | Catch your first fish | once | Bronze |
| <img src="assets/media/ui/achievements/small/farm_fish_50.png" width="40" alt=""> | **Gone Fishing** | Catch fifty fish | 50 fish | Silver |
| <img src="assets/media/ui/achievements/small/farm_species_20.png" width="40" alt=""> | **Something Is Biting** | Catch twenty different fish species | 20 | Silver |
| <img src="assets/media/ui/achievements/small/farm_net_25.png" width="40" alt=""> | **Net Profit** | Check a fishing net twenty five times | 25 | Silver |
| <img src="assets/media/ui/achievements/small/farm_trap_1.png" width="40" alt=""> | **Set A Trap** | Place your first trap | once | Bronze |
| <img src="assets/media/ui/achievements/small/farm_traps_6.png" width="40" alt=""> | **Whole Trapline** | Use all six kinds of trap | 6 | Silver |
| <img src="assets/media/ui/achievements/small/farm_foodtypes_20.png" width="40" alt=""> | **A Balanced Diet** | Eat twenty different kinds of food | 20 | Bronze |
| <img src="assets/media/ui/achievements/small/farm_foodtypes_40.png" width="40" alt=""> | **Adventurous Palate** | Eat forty different kinds of food | 40 | Gold |
| <img src="assets/media/ui/achievements/small/farm_cook_100.png" width="40" alt=""> | **Cutting Onions** | Cook one hundred meals | 100 | Silver |
| <img src="assets/media/ui/achievements/small/farm_forage_500.png" width="40" alt=""> | **Forager** | Forage five hundred items | 500 items | Gold |
| <img src="assets/media/ui/achievements/small/animal_pet_1.png" width="40" alt=""> | **Good Boy** | Pet an animal. It has been a long apocalypse | once | Bronze |
| <img src="assets/media/ui/achievements/small/animal_feed_50.png" width="40" alt=""> | **Feeding Time** | Feed an animal by hand fifty times | 50 | Silver |
| <img src="assets/media/ui/achievements/small/animal_milk_1.png" width="40" alt=""> | **Got Milk** | Milk an animal | once | Bronze |
| <img src="assets/media/ui/achievements/small/animal_milk_100.png" width="40" alt=""> | **Dairy Farmer** | Milk animals one hundred times | 100 | Gold |
| <img src="assets/media/ui/achievements/small/animal_shear_25.png" width="40" alt=""> | **Shear Delight** | Shear twenty five animals | 25 | Silver |
| <img src="assets/media/ui/achievements/small/animal_egg_100.png" width="40" alt=""> | **Eggcellent** | Collect one hundred eggs | 100 | Silver |
| <img src="assets/media/ui/achievements/small/animal_butcher_1.png" width="40" alt=""> | **Nose To Tail** | Butcher your first animal | once | Bronze |
| <img src="assets/media/ui/achievements/small/animal_butcher_50.png" width="40" alt=""> | **The Whole Herd** | Butcher fifty animals | 50 | Gold |
| <img src="assets/media/ui/achievements/small/animal_leather_25.png" width="40" alt=""> | **Tanner** | Take leather from twenty five animals | 25 | Silver |
| <img src="assets/media/ui/achievements/small/animal_bones_50.png" width="40" alt=""> | **Bone Collector** | Take bones from fifty animals | 50 | Silver |
| <img src="assets/media/ui/achievements/small/animal_hutch_1.png" width="40" alt=""> | **Coop Deville** | Put an animal in a hutch | once | Bronze |
| <img src="assets/media/ui/achievements/small/animal_lure_10.png" width="40" alt=""> | **Come Here Often** | Lure ten animals | 10 | Silver |
| <img src="assets/media/ui/achievements/small/animal_trailer_1.png" width="40" alt=""> | **Livestock Transport** | Move an animal in a trailer | once | Bronze |
| <img src="assets/media/ui/achievements/small/animal_species_10.png" width="40" alt=""> | **Menagerie** | Handle ten kinds of animal | 10 | Silver |
| <img src="assets/media/ui/achievements/small/animal_track_25.png" width="40" alt=""> | **Tracker** | Inspect twenty five animal tracks | 25 | Silver |
| <img src="assets/media/ui/achievements/small/animal_hook_10.png" width="40" alt=""> | **Hung Out To Dry** | Hang ten animals on a butcher hook | 10 | Silver |
| <img src="assets/media/ui/achievements/small/farm_insect_1.png" width="40" alt=""> | **Protein Is Protein** | Eat an insect. It was that or nothing | once | Bronze |

### Field Medicine

| | Achievement | How you get it | Goal | Tier |
|---|---|---|---|---|
| <img src="assets/media/ui/achievements/small/med_bandage_1.png" width="40" alt=""> | **Just A Scratch** | Apply your first bandage | once | Bronze |
| <img src="assets/media/ui/achievements/small/med_bandage_50.png" width="40" alt=""> | **Walking Wounded** | Apply fifty bandages | 50 | Silver |
| <img src="assets/media/ui/achievements/small/med_stitch_5.png" width="40" alt=""> | **Needlework** | Stitch five wounds | 5 | Silver |
| <img src="assets/media/ui/achievements/small/med_splint_1.png" width="40" alt=""> | **Field Expedient** | Splint a fracture | once | Bronze |
| <img src="assets/media/ui/achievements/small/med_bullet_1.png" width="40" alt=""> | **Bite The Bullet** | Dig a bullet out of yourself | once | Bronze |
| <img src="assets/media/ui/achievements/small/med_glass_10.png" width="40" alt=""> | **Crunchy Underfoot** | Pull glass out of yourself ten times | 10 | Silver |
| <img src="assets/media/ui/achievements/small/med_cataplasm_10.png" width="40" alt=""> | **Old Remedies** | Apply ten herbal cataplasms | 10 | Silver |
| <img src="assets/media/ui/achievements/small/med_pills_100.png" width="40" alt=""> | **Better Living** | Take one hundred pills | 100 | Silver |
| <img src="assets/media/ui/achievements/small/med_check_50.png" width="40" alt=""> | **Second Opinion** | Check yourself over fifty times | 50 | Silver |
| <img src="assets/media/ui/achievements/small/med_poison_1.png" width="40" alt=""> | **Tastes Funny** | Poison yourself | once | Bronze |
| <img src="assets/media/ui/achievements/small/med_fall_10.png" width="40" alt=""> | **Gravity Always Wins** | Take fall damage ten times | 10 | Silver |
| <img src="assets/media/ui/achievements/small/med_damage_types_10.png" width="40" alt=""> | **Comprehensive** | Take ten of the thirteen kinds of damage | 10 | Gold |
| <img src="assets/media/ui/achievements/small/med_infected_1.png" width="40" alt=""> | **Positive Result** | Catch the Knox infection and know it | once | Bronze |
| <img src="assets/media/ui/achievements/small/med_fracture_1.png" width="40" alt=""> | **Knitted Back** | Break a bone and heal it all the way | once | Silver |

### Roadside Attractions

| | Achievement | How you get it | Goal | Tier |
|---|---|---|---|---|
| <img src="assets/media/ui/achievements/small/road_drive_100.png" width="40" alt=""> | **Sunday Driver** | Drive one hundred kilometres | 100,000 metres | Bronze |
| <img src="assets/media/ui/achievements/small/road_drive_1000.png" width="40" alt=""> | **The Long Haul** | Drive one thousand kilometres | 1,000,000 metres | Gold |
| <img src="assets/media/ui/achievements/small/road_vehicles_10.png" width="40" alt=""> | **Test Drive** | Drive ten different vehicles | 10 | Silver |
| <img src="assets/media/ui/achievements/small/road_enters_100.png" width="40" alt=""> | **Commuter** | Get into a vehicle one hundred times | 100 | Silver |
| <img src="assets/media/ui/achievements/small/road_seat_10.png" width="40" alt=""> | **Shotgun** | Change seats ten times | 10 | Silver |
| <img src="assets/media/ui/achievements/small/road_repair_1.png" width="40" alt=""> | **Hands Dirty** | Fit or remove your first vehicle part | once | Bronze |
| <img src="assets/media/ui/achievements/small/road_repair_25.png" width="40" alt=""> | **Full Service** | Fit or remove twenty five vehicle parts | 25 | Silver |
| <img src="assets/media/ui/achievements/small/road_fuel_100.png" width="40" alt=""> | **Pump Action** | Add fuel one hundred times | 100 | Silver |
| <img src="assets/media/ui/achievements/small/road_battery_10.png" width="40" alt=""> | **Jump Start** | Charge a car battery ten times | 10 | Silver |
| <img src="assets/media/ui/achievements/small/road_fumes_1.png" width="40" alt=""> | **Running On Fumes** | Drive below five percent fuel | once | Bronze |
| <img src="assets/media/ui/achievements/small/see_louisville_1.png" width="40" alt=""> | **Louisville Or Bust** | Reach Louisville. All roads lead there eventually | once | Bronze |
| <img src="assets/media/ui/achievements/small/see_regions_9.png" width="40" alt=""> | **Every Last Corner** | Visit all nine named regions | 9 | Silver |
| <img src="assets/media/ui/achievements/small/see_airport_1.png" width="40" alt=""> | **Departures** | Reach the Louisville airport | once | Bronze |
| <img src="assets/media/ui/achievements/small/see_rooms_100.png" width="40" alt=""> | **Nosy** | See one hundred rooms | 100 | Bronze |
| <img src="assets/media/ui/achievements/small/see_rooms_1000.png" width="40" alt=""> | **Is It A Bird** | See one thousand rooms | 1,000 | Gold |
| <img src="assets/media/ui/achievements/small/see_roomkinds_50.png" width="40" alt=""> | **Every Kind Of Room** | See fifty different kinds of room | 50 | Silver |
| <img src="assets/media/ui/achievements/small/see_buildings_10.png" width="40" alt=""> | **House Hunting** | Fully explore ten buildings | 10 | Bronze |
| <img src="assets/media/ui/achievements/small/see_buildings_50.png" width="40" alt=""> | **Estate Agent** | Fully explore fifty buildings | 50 | Gold |
| <img src="assets/media/ui/achievements/small/see_shops_25.png" width="40" alt=""> | **Window Shopping** | Enter twenty five shops | 25 | Silver |
| <img src="assets/media/ui/achievements/small/see_bathroom_100.png" width="40" alt=""> | **Room With A View** | Enter one hundred bathrooms | 100 | Silver |
| <img src="assets/media/ui/achievements/small/see_church_10.png" width="40" alt=""> | **Sanctuary** | Enter ten churches | 10 | Silver |
| <img src="assets/media/ui/achievements/small/see_prison_1.png" width="40" alt=""> | **Correctional** | Reach the prison cells | once | Bronze |
| <img src="assets/media/ui/achievements/small/see_spiffo_1.png" width="40" alt=""> | **Mans Best Friend** | Find your first Spiffo plush | once | Bronze |
| <img src="assets/media/ui/achievements/small/see_bigspiffo_1.png" width="40" alt=""> | **Idol Of The Far Gone** | Find a Big Spiffo | once | Bronze |
| <img src="assets/media/ui/achievements/small/see_toys_10.png" width="40" alt=""> | **Playtime** | Collect ten different toys | 10 toys | Silver |
| <img src="assets/media/ui/achievements/small/see_toys_26.png" width="40" alt=""> | **The Whole Toybox** | Collect all twenty six toys | 26 toys | Gold |
| <img src="assets/media/ui/achievements/small/road_walk_10.png" width="40" alt=""> | **Cardio** | Cover ten kilometres on foot | 10,000 metres | Bronze |
| <img src="assets/media/ui/achievements/small/road_walk_100.png" width="40" alt=""> | **Comfortable Shoes** | Cover one hundred kilometres on foot | 100,000 metres | Gold |

### House Proud

| | Achievement | How you get it | Goal | Tier |
|---|---|---|---|---|
| <img src="assets/media/ui/achievements/small/grave_bury_1.png" width="40" alt=""> | **Full Honours** | Bury a corpse | once | Bronze |
| <img src="assets/media/ui/achievements/small/grave_bury_50.png" width="40" alt=""> | **Gravedigger** | Bury fifty corpses | 50 | Silver |
| <img src="assets/media/ui/achievements/small/grave_burn_100.png" width="40" alt=""> | **Ashes To Ashes** | Burn one hundred corpses | 100 | Silver |
| <img src="assets/media/ui/achievements/small/grave_window_10.png" width="40" alt=""> | **Out The Window** | Throw ten corpses through a window | 10 | Silver |
| <img src="assets/media/ui/achievements/small/grave_fence_10.png" width="40" alt=""> | **Over The Fence** | Throw ten corpses over a fence | 10 | Silver |
| <img src="assets/media/ui/achievements/small/grave_move_25.png" width="40" alt=""> | **Body Of Work** | Drag twenty five corpses somewhere else | 25 | Silver |
| <img src="assets/media/ui/achievements/small/grave_container_5.png" width="40" alt=""> | **Bin Day** | Put five corpses in a container | 5 | Silver |
| <img src="assets/media/ui/achievements/small/hoard_container_100.png" width="40" alt=""> | **Antique Roadshow** | Carry one hundred kilos at once | 100 | Bronze |
| <img src="assets/media/ui/achievements/small/hoard_container_150.png" width="40" alt=""> | **Structural Concerns** | Carry one hundred and fifty kilos at once | 150 | Gold |
| <img src="assets/media/ui/achievements/small/hoard_types_100.png" width="40" alt=""> | **Collector** | Hold one hundred different item types | 100 types | Bronze |
| <img src="assets/media/ui/achievements/small/hoard_types_500.png" width="40" alt=""> | **Completionist** | Hold five hundred different item types | 500 types | Gold |
| <img src="assets/media/ui/achievements/small/hoard_found_1000.png" width="40" alt=""> | **Magpie** | Pick up one thousand items | 1,000 items | Bronze |
| <img src="assets/media/ui/achievements/small/hoard_found_10000.png" width="40" alt=""> | **Serious Hoarding** | Pick up ten thousand items | 10,000 items | Gold |
| <img src="assets/media/ui/achievements/small/hoard_macho_1.png" width="40" alt=""> | **Macho Man** | Carry forty kilos in both hands at once | once | Bronze |
| <img src="assets/media/ui/achievements/small/hoard_overburden_50.png" width="40" alt=""> | **One More Trip** | Get yourself overburdened fifty times | 50 | Silver |
| <img src="assets/media/ui/achievements/small/hoard_consolidate_100.png" width="40" alt=""> | **Every Last Drop** | Consolidate drainables one hundred times | 100 | Silver |
| <img src="assets/media/ui/achievements/small/hoard_dump_50.png" width="40" alt=""> | **Tip It Out** | Dump a container fifty times | 50 | Silver |
| <img src="assets/media/ui/achievements/small/hoard_sledge_1.png" width="40" alt=""> | **Key To The City** | Find a sledgehammer | once | Bronze |
| <img src="assets/media/ui/achievements/small/house_blood_1.png" width="40" alt=""> | **Spot Of Bother** | Mop up your first bloodstain | once | Bronze |
| <img src="assets/media/ui/achievements/small/house_blood_500.png" width="40" alt=""> | **Out Damned Spot** | Mop up five hundred bloodstains | 500 | Gold |
| <img src="assets/media/ui/achievements/small/house_graffiti_25.png" width="40" alt=""> | **Nothing To See** | Clean twenty five pieces of graffiti | 25 | Silver |
| <img src="assets/media/ui/achievements/small/house_wash_self_50.png" width="40" alt=""> | **Personal Hygiene** | Wash yourself fifty times | 50 | Silver |
| <img src="assets/media/ui/achievements/small/house_wash_clothes_100.png" width="40" alt=""> | **Laundry Day** | Wash one hundred pieces of clothing | 100 | Silver |
| <img src="assets/media/ui/achievements/small/house_repair_50.png" width="40" alt=""> | **Running Repairs** | Repair fifty pieces of clothing | 50 | Silver |
| <img src="assets/media/ui/achievements/small/house_haircut_1.png" width="40" alt=""> | **New Look** | Cut your own hair | once | Bronze |
| <img src="assets/media/ui/achievements/small/house_dye_1.png" width="40" alt=""> | **Dyeing Wish** | Dye your hair | once | Bronze |
| <img src="assets/media/ui/achievements/small/house_beard_10.png" width="40" alt=""> | **Well Groomed** | Trim your beard ten times | 10 | Silver |
| <img src="assets/media/ui/achievements/small/house_makeup_1.png" width="40" alt=""> | **Face The Day** | Put on makeup | once | Bronze |
| <img src="assets/media/ui/achievements/small/house_curtain_50.png" width="40" alt=""> | **Net Curtains** | Open or close fifty curtains | 50 | Silver |
| <img src="assets/media/ui/achievements/small/house_light_100.png" width="40" alt=""> | **Lights Out** | Flick a light switch one hundred times | 100 | Silver |
| <img src="assets/media/ui/achievements/small/house_write_10.png" width="40" alt=""> | **Dear Diary** | Write on ten notes | 10 | Silver |

### This Is How You Died

| | Achievement | How you get it | Goal | Tier |
|---|---|---|---|---|
| <img src="assets/media/ui/achievements/small/died_1.png" width="40" alt=""> | **The First Time** | Die. It happens to everyone eventually | once | Bronze |
| <img src="assets/media/ui/achievements/small/died_day_1.png" width="40" alt=""> | **Short Career** | Die on your first day | once | Bronze |
| <img src="assets/media/ui/achievements/small/died_bathroom.png" width="40" alt=""> | **Beware Of Bathrooms** | Die in a bathroom. They were in there together | once | Bronze |
| <img src="assets/media/ui/achievements/small/died_crash.png" width="40" alt=""> | **Mach Jesus** | Die of a vehicle crash | once | Bronze |
| <img src="assets/media/ui/achievements/small/died_fire.png" width="40" alt=""> | **Well Done** | Die on fire | once | Bronze |
| <img src="assets/media/ui/achievements/small/died_fall.png" width="40" alt=""> | **We Need To Go Deeper** | Die from a fall | once | Bronze |
| <img src="assets/media/ui/achievements/small/died_thirst.png" width="40" alt=""> | **Forgot To Pause** | Die of thirst | once | Bronze |
| <img src="assets/media/ui/achievements/small/died_hunger.png" width="40" alt=""> | **Empty Larder** | Die of hunger | once | Bronze |
| <img src="assets/media/ui/achievements/small/died_poison.png" width="40" alt=""> | **Into The Wild** | Die of poison. The Herbalist would have flagged it | once | Bronze |
| <img src="assets/media/ui/achievements/small/died_sick.png" width="40" alt=""> | **The Slow News** | Die of the Knox infection | once | Bronze |
| <img src="assets/media/ui/achievements/small/died_bleed.png" width="40" alt=""> | **Twenty Seconds** | Bleed to death | once | Bronze |
| <img src="assets/media/ui/achievements/small/died_cold.png" width="40" alt=""> | **Cold Comfort** | Die of hypothermia | once | Bronze |
| <img src="assets/media/ui/achievements/small/died_outside_town.png" width="40" alt=""> | **Miles From Anywhere** | Die outside every named region | once | Silver |
| <img src="assets/media/ui/achievements/small/died_animal.png" width="40" alt=""> | **Ended By Livestock** | Die with an animal as the last thing that hurt you | once | Silver |
| <img src="assets/media/ui/achievements/small/died_after_year.png" width="40" alt=""> | **The Long Goodbye** | Die having survived a full year | once | Silver |
| <img src="assets/media/ui/achievements/small/died_zombified.png" width="40" alt=""> | **Member Of The Horde** | Die knowing you will be getting back up | once | Silver |
| <img src="assets/media/ui/achievements/small/died_bleach.png" width="40" alt=""> | **The Easy Way Out** | Drink bleach and let it finish the job | once | Bronze |

### Secrets

| | Achievement | How you get it | Goal | Tier |
|---|---|---|---|---|
| <img src="assets/media/ui/achievements/small/combat_nogun_500.png" width="40" alt=""> | **Silence Is Golden** | Kill 500 zombies without ever firing a gun | 500 zombies | Silver |

<details>
<summary><b>15 hidden achievements.</b> These show only a teaser in game until you trip over them. Open at your own risk.</summary>

| | Achievement | How you get it | Goal | Tier |
|---|---|---|---|---|
| <img src="assets/media/ui/achievements/small/secret_lifeandliving.png" width="40" alt=""> | **Glued To The Set** | Somebody kept broadcasting after the world stopped watching | 12 days | Gold |
| <img src="assets/media/ui/achievements/small/secret_tv_10.png" width="40" alt=""> | **Couch Potato** | Every channel still has something to say | 10 | Silver |
| <img src="assets/media/ui/achievements/small/secret_radio_5.png" width="40" alt=""> | **Airwaves** | Somewhere out there, a voice is still on the air | 5 | Silver |
| <img src="assets/media/ui/achievements/small/secret_military_1.png" width="40" alt=""> | **Classified** | Some numbers were never meant for civilians | once | Bronze |
| <img src="assets/media/ui/achievements/small/secret_offgrid.png" width="40" alt=""> | **Off The Grid** | The lights were always going to go out | 30 days | Gold |
| <img src="assets/media/ui/achievements/small/secret_nowater.png" width="40" alt=""> | **Rationing** | The taps run dry eventually. What then | 30 days | Gold |
| <img src="assets/media/ui/achievements/small/secret_sprinter.png" width="40" alt=""> | **Was That A Sprinter** | Something moved faster than it had any right to | once | Bronze |
| <img src="assets/media/ui/achievements/small/secret_fakedead.png" width="40" alt=""> | **Playing Possum** | Not all of them are finished | once | Bronze |
| <img src="assets/media/ui/achievements/small/secret_naked_50.png" width="40" alt=""> | **Nothing To Wear** | Clothing turns out to be optional | 50 zombies | Silver |
| <img src="assets/media/ui/achievements/small/secret_blizzard_out.png" width="40" alt=""> | **Cold Open** | Shelter is a choice, and you can make the wrong one | once | Bronze |
| <img src="assets/media/ui/achievements/small/secret_pacifist_30.png" width="40" alt=""> | **Doors And Corners** | Some survivors barely swing at all | 30 days | Silver |
| <img src="assets/media/ui/achievements/small/secret_basement_1.png" width="40" alt=""> | **Any News About Him** | Not every house ends at the ground floor | once | Bronze |
| <img src="assets/media/ui/achievements/small/secret_startled_1.png" width="40" alt=""> | **Necrophobia** | Something is going to make you jump | once | Bronze |
| <img src="assets/media/ui/achievements/small/secret_wizard_1.png" width="40" alt=""> | **You Shall Not Pass** | There is a hat out there worth finding | once | Bronze |
| <img src="assets/media/ui/achievements/small/secret_smoke_10.png" width="40" alt=""> | **Social Smoker** | A habit you did not start with | 10 | Silver |

</details>

### Milestones

| | Achievement | How you get it | Goal | Tier |
|---|---|---|---|---|
| <img src="assets/media/ui/achievements/small/meta_waking_up.png" width="40" alt=""> | **First Week Done** | Finish every achievement in Waking Up | once | Gold |
| <img src="assets/media/ui/achievements/small/meta_body_count.png" width="40" alt=""> | **Nothing Left To Kill** | Finish every achievement in Body Count | once | Gold |
| <img src="assets/media/ui/achievements/small/meta_still_breathing.png" width="40" alt=""> | **Still Here** | Finish every achievement in Still Breathing | once | Gold |
| <img src="assets/media/ui/achievements/small/meta_autodidact.png" width="40" alt=""> | **Nothing Left To Read** | Finish every achievement in Autodidact | once | Gold |
| <img src="assets/media/ui/achievements/small/meta_nailed_it.png" width="40" alt=""> | **Everything Built** | Finish every achievement in Nailed It | once | Gold |
| <img src="assets/media/ui/achievements/small/meta_homestead.png" width="40" alt=""> | **Larder Full** | Finish every achievement in Homestead | once | Gold |
| <img src="assets/media/ui/achievements/small/meta_field_medicine.png" width="40" alt=""> | **Fully Stocked** | Finish every achievement in Field Medicine | once | Gold |
| <img src="assets/media/ui/achievements/small/meta_roadside.png" width="40" alt=""> | **Whole County Seen** | Finish every achievement in Roadside Attractions | once | Gold |
| <img src="assets/media/ui/achievements/small/meta_house_proud.png" width="40" alt=""> | **Spotless** | Finish every achievement in House Proud | once | Gold |
| <img src="assets/media/ui/achievements/small/meta_how_you_died.png" width="40" alt=""> | **Every Way Out** | Finish every achievement in This Is How You Died | once | Gold |
| <img src="assets/media/ui/achievements/small/meta_secrets.png" width="40" alt=""> | **Nothing Left Hidden** | Finish every achievement in Secrets | once | Gold |
| <img src="assets/media/ui/achievements/small/meta_all.png" width="40" alt=""> | **Knox County Complete** | Finish every other category in this save | 11 | Gold |

<!-- END ROSTER -->

## Layout

```
art/           the preview, the icon and the screenshots this page uses
assets/media/  the 258 achievement icons, the category art and the translations
lua/           the mod source: engine in shared/, trackers and UI in client/
mod.info       the in-game manifest
workshop.txt   the Steam listing, BBCode
```

MIT. Part of [PZWorkspace](https://github.com/ViniciosLugli/PZWorkspace).
