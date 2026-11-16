SandboxVars = {
    VERSION = 6,
    -- Changing this also sets the "Population Multiplier" in Advanced Zombie Options. Default = Normal
    -- 1 = Insane
    -- 2 = Very High
    -- 3 = High
    -- 4 = Normal
    -- 5 = Low
    -- 6 = None
    Zombies = 4,
    -- How zombies are distributed across the map. Default = Urban Focused
    -- 1 = Urban Focused
    -- 2 = Uniform
    Distribution = 1,
    -- Controls whether some randomization is applied to zombie distribution.
    ZombieVoronoiNoise = true,
    -- How frequently new zombies are added to the world. Default = None
    -- 1 = High
    -- 2 = Normal
    -- 3 = Low
    -- 4 = None
    ZombieRespawn = 4,
    -- Zombie allowed to migrate to empty cells.
    ZombieMigrate = true,
    -- Default = 1 Hour, 30 Minutes
    -- 1 = 15 Minutes
    -- 2 = 30 Minutes
    -- 3 = 1 Hour
    -- 4 = 1 Hour, 30 Minutes
    -- 5 = 2 Hours
    -- 6 = 3 Hours
    -- 7 = 4 Hours
    -- 8 = 5 Hours
    -- 9 = 6 Hours
    -- 10 = 7 Hours
    -- 11 = 8 Hours
    -- 12 = 9 Hours
    -- 13 = 10 Hours
    -- 14 = 11 Hours
    -- 15 = 12 Hours
    -- 16 = 13 Hours
    -- 17 = 14 Hours
    -- 18 = 15 Hours
    -- 19 = 16 Hours
    -- 20 = 17 Hours
    -- 21 = 18 Hours
    -- 22 = 19 Hours
    -- 23 = 20 Hours
    -- 24 = 21 Hours
    -- 25 = 22 Hours
    -- 26 = 23 Hours
    -- 27 = Real-time
    DayLength = 4,
    StartYear = 1,
    -- Month in which the game starts. Default = July
    -- 1 = January
    -- 2 = February
    -- 3 = March
    -- 4 = April
    -- 5 = May
    -- 6 = June
    -- 7 = July
    -- 8 = August
    -- 9 = September
    -- 10 = October
    -- 11 = November
    -- 12 = December
    StartMonth = 7,
    -- Day of the month in which the games starts.
    StartDay = 9,
    -- Hour of the day in which the game starts. Default = 9 AM
    -- 1 = 7 AM
    -- 2 = 9 AM
    -- 3 = 12 PM
    -- 4 = 2 PM
    -- 5 = 5 PM
    -- 6 = 9 PM
    -- 7 = 12 AM
    -- 8 = 2 AM
    -- 9 = 5 AM
    StartTime = 2,
    -- Whether the time of day changes naturally, or it's always day/night. Default = Normal
    -- 1 = Normal
    -- 2 = Endless Day
    -- 3 = Endless Night
    DayNightCycle = 1,
    -- Whether weather changes or remains at a single state. Default = Normal
    -- 1 = Normal
    -- 2 = No Weather
    -- 3 = Endless Rain
    -- 4 = Endless Storm
    -- 5 = Endless Snow
    -- 6 = Endless Blizzard
    ClimateCycle = 1,
    -- Whether fog occurs naturally, never occurs, or is always present. Default = Normal
    -- 1 = Normal
    -- 2 = No Fog
    -- 3 = Endless Fog
    FogCycle = 1,
    -- How long after the default start date (July 9, 1993) that plumbing fixtures (eg. sinks) stop being infinite sources of water. Default = 0 - 30 Days
    -- 1 = Instant
    -- 2 = 0 - 30 Days
    -- 3 = 0 - 2 Months
    -- 4 = 0 - 6 Months
    -- 5 = 0 - 1 Year
    -- 6 = 0 - 5 Years
    -- 7 = 2 - 6 Months
    -- 8 = 6 - 12 Months
    -- 9 = Disabled
    WaterShut = 2,
    -- How long after the default start date (July 9, 1993) that the world's electricity turns off for good. Default = 14 - 30 Days
    -- 1 = Instant
    -- 2 = 14 - 30 Days
    -- 3 = 14 Days - 2 Months
    -- 4 = 14 Days - 6 Months
    -- 5 = 14 Days - 1 Year
    -- 6 = 14 Days - 5 Years
    -- 7 = 2 - 6 Months
    -- 8 = 6 - 12 Months
    -- 9 = Disabled
    ElecShut = 2,
    -- How long alarm batteries can last for after the power shuts off. Default = 0 - 30 Days
    -- 1 = Instant
    -- 2 = 0 - 30 Days
    -- 3 = 0 - 2 Months
    -- 4 = 0 - 6 Months
    -- 5 = 0 - 1 Year
    -- 6 = 0 - 5 Years
    AlarmDecay = 2,
    -- How long after the default start date (July 9, 1993) that plumbing fixtures (eg. sinks) stop being infinite sources of water. Min: -1 Max: 2147483647 Default: 14
    WaterShutModifier = 14,
    -- How long after the default start date (July 9, 1993) that the world's electricity turns off for good. Min: -1 Max: 2147483647 Default: 14
    ElecShutModifier = 14,
    -- How long alarm batteries can last for after the power shuts off. Min: -1 Max: 2147483647 Default: 14
    AlarmDecayModifier = 14,
    -- Any food that can rot or spoil. Min: 0.00 Max: 4.00 Default: 0.80
    FoodLootNew = 0.3,
    -- All other items that can be read, including books, fliers, and newspapers. Min: 0.00 Max: 4.00 Default: 0.60
    LiteratureLootNew = 0.3,
    -- Books that provide skill XP multipliers. Min: 0.00 Max: 4.00 Default: 0.60
    SkillBookLoot = 0.3,
    -- Items that teach recipes. Min: 0.00 Max: 4.00 Default: 0.60
    RecipeResourceLoot = 0.3,
    -- Medicine, bandages and first aid tools. Min: 0.00 Max: 4.00 Default: 0.60
    MedicalLootNew = 0.3,
    -- Fishing Rods, Tents, camping gear etc. Min: 0.00 Max: 4.00 Default: 0.60
    SurvivalGearsLootNew = 0.3,
    -- Canned and dried food, beverages. Min: 0.00 Max: 4.00 Default: 0.60
    CannedFoodLootNew = 0.3,
    -- Weapons that are not tools in other categories. Min: 0.00 Max: 4.00 Default: 0.60
    WeaponLootNew = 0.3,
    -- Also includes weapon attachments. Min: 0.00 Max: 4.00 Default: 1.20
    RangedWeaponLootNew = 0.2,
    -- Loose ammo, boxes and magazines. Min: 0.00 Max: 4.00 Default: 0.60
    AmmoLootNew = 0.4,
    -- Vehicle parts and the tools needed to install them. Min: 0.00 Max: 4.00 Default: 0.60
    MechanicsLootNew = 0.3,
    -- Everything else. Also affects foraging for all items in Town/Road zones. Min: 0.00 Max: 4.00 Default: 0.80
    OtherLootNew = 0.3,
    -- All wearable items that are not containers. Min: 0.00 Max: 4.00 Default: 0.60
    ClothingLootNew = 0.3,
    -- Backpacks and other wearable/equippable containers, eg. cases. Min: 0.00 Max: 4.00 Default: 0.60
    ContainerLootNew = 0.3,
    -- Keys for buildings/cars, key rings, and locks. Min: 0.00 Max: 4.00 Default: 0.40
    KeyLootNew = 0.1,
    -- VHS tapes and CDs. Min: 0.00 Max: 4.00 Default: 0.60
    MediaLootNew = 0.3,
    -- Spiffo items, plushies, and other collectible keepsake items eg. Photos. Min: 0.00 Max: 4.00 Default: 0.60
    MementoLootNew = 0.3,
    -- Items that are used in cooking, including those (eg. knives) which can be weapons. Does not include food. Includes both usable and unusable items. Min: 0.00 Max: 4.00 Default: 0.60
    CookwareLootNew = 0.3,
    -- Items and weapons that are used as ingredients for crafting or building. This is a general category that does not include items belonging to other categories such as Cookware or Medical. Does not include Tools. Min: 0.00 Max: 4.00 Default: 0.60
    MaterialLootNew = 0.3,
    -- Items and weapons which are used in both animal and plant agriculture, such as Seeds, Trowels, or Shovels. Min: 0.00 Max: 4.00 Default: 0.60
    FarmingLootNew = 0.3,
    -- Items and weapons which are Tools but don't fit in other categories such as Mechanics or Farming. Min: 0.00 Max: 4.00 Default: 0.60
    ToolLootNew = 0.3,
    -- <BHC> [!] It is recommended that you DO NOT change this. [!] <RGB:1,1,1>   Can be used to adjust the number of rolls made on loot tables when spawning loot. Will not reduce the number of rolls below 1. Can negatively affect performance if set to high values. It is highly recommended that this not be changed. Min: 0.10 Max: 100.00 Default: 1.00
    RollsMultiplier = 1.0,
    -- A comma-separated list of item types that won't spawn as ordinary loot.
    LootItemRemovalList = "",
    -- If enabled, items on the Loot Item Removal List, or that have their rarity set to 'None', will not spawn in randomised world stories.
    RemoveStoryLoot = false,
    -- If enabled, items on the Loot Item Removal List, or that have their rarity set to 'None', will not spawn worn by, or attached to, zombies.
    RemoveZombieLoot = false,
    -- If greater than 0, the spawn of loot is increased relative to the number of nearby zombies,  with the effect multiplied by this number. Min: 0 Max: 20 Default: 0
    ZombiePopLootEffect = 0,
    -- Min: 0.00 Max: 0.20 Default: 0.05
    InsaneLootFactor = 0.05,
    -- Min: 0.05 Max: 0.60 Default: 0.20
    ExtremeLootFactor = 0.2,
    -- Min: 0.20 Max: 1.00 Default: 0.60
    RareLootFactor = 0.6,
    -- Min: 0.60 Max: 2.00 Default: 1.00
    NormalLootFactor = 1.0,
    -- Min: 1.00 Max: 3.00 Default: 2.00
    CommonLootFactor = 2.0,
    -- Min: 2.00 Max: 4.00 Default: 3.00
    AbundantLootFactor = 3.0,
    -- The global temperature. Default = Normal
    -- 1 = Very Cold
    -- 2 = Cold
    -- 3 = Normal
    -- 4 = Hot
    -- 5 = Very Hot
    Temperature = 3,
    -- How often it rains. Default = Normal
    -- 1 = Very Dry
    -- 2 = Dry
    -- 3 = Normal
    -- 4 = Rainy
    -- 5 = Very Rainy
    Rain = 3,
    -- Number of days until the erosion system (which adds vines, long grass, new trees etc. to the world) will reach 100% growth. Default = Slow (200 Days)
    -- 1 = Very Fast (20 Days)
    -- 2 = Fast (50 Days)
    -- 3 = Normal (100 Days)
    -- 4 = Slow (200 Days)
    -- 5 = Very Slow (500 Days)
    ErosionSpeed = 4,
    -- For a custom Erosion Speed. Zero means use the Erosion Speed option. Maximum is 36,500 days (approximately 100 years). Min: -1 Max: 36500 Default: 0
    ErosionDays = 0,
    -- The speed of plant growth. Default = Normal
    -- 1 = Very Fast
    -- 2 = Fast
    -- 3 = Normal
    -- 4 = Slow
    -- 5 = Very Slow
    Farming = 3,
    -- How long it takes for food to break down in a composter. Default = 2 Weeks
    -- 1 = 1 Week
    -- 2 = 2 Weeks
    -- 3 = 3 Weeks
    -- 4 = 4 Weeks
    -- 5 = 6 Weeks
    -- 6 = 8 Weeks
    -- 7 = 10 Weeks
    -- 8 = 12 Weeks
    CompostTime = 2,
    -- How fast the player's hunger, thirst, and fatigue will decrease. Default = Normal
    -- 1 = Very Fast
    -- 2 = Fast
    -- 3 = Normal
    -- 4 = Slow
    -- 5 = Very Slow
    StatsDecrease = 3,
    -- The abundance of items found in Foraging mode. Default = Normal
    -- 1 = Very Poor
    -- 2 = Poor
    -- 3 = Normal
    -- 4 = Abundant
    -- 5 = Very Abundant
    NatureAbundance = 3,
    -- How likely the player is to activate a house alarm when breaking into a new house. Default = Sometimes
    -- 1 = Never
    -- 2 = Extremely Rare
    -- 3 = Rare
    -- 4 = Sometimes
    -- 5 = Often
    -- 6 = Very Often
    Alarm = 4,
    -- How frequently the doors of homes and buildings will be locked when discovered. Default = Very Often
    -- 1 = Never
    -- 2 = Extremely Rare
    -- 3 = Rare
    -- 4 = Sometimes
    -- 5 = Often
    -- 6 = Very Often
    LockedHouses = 6,
    -- Spawn with Chips, a Water Bottle, a Small Backpack, a Baseball Bat, and a Hammer.
    StarterKit = false,
    -- Nutritional value of food affects the player's condition. Turning this off will stop the player gaining or losing weight.
    Nutrition = true,
    -- How fast that food will spoil, inside or outside of a fridge. Default = Normal
    -- 1 = Very Fast
    -- 2 = Fast
    -- 3 = Normal
    -- 4 = Slow
    -- 5 = Very Slow
    FoodRotSpeed = 3,
    -- How effective a fridge will be at keeping food fresh for longer. Default = Normal
    -- 1 = Very Low
    -- 2 = Low
    -- 3 = Normal
    -- 4 = High
    -- 5 = Very High
    -- 6 = No decay
    FridgeFactor = 3,
    -- When greater than 0, loot will not respawn in zones that have been visited within this number of in-game hours. Min: 0 Max: 2147483647 Default: 0
    SeenHoursPreventLootRespawn = 0,
    -- When greater than 0, after X hours, all containers in towns and trailer parks in the world will respawn loot. To spawn loot a container must have been looted at least once. Loot respawn is not impacted by visibility or subsequent looting. Min: 0 Max: 2147483647 Default: 0
    HoursForLootRespawn = 0,
    -- Containers with a number of items greater, or equal to, this setting will not respawn. Min: 0 Max: 2147483647 Default: 5
    MaxItemsForLootRespawn = 5,
    -- Items will not respawn in buildings that players have barricaded or built in.
    ConstructionPreventsLootRespawn = true,
    -- A comma-separated list of item types that will be removed after HoursForWorldItemRemoval hours.
    WorldItemRemovalList = "Base.Hat, Base.Glasses, Base.Maggots, Base.Slug, Base.Slug2, Base.Snail, Base.Worm, Base.Dung_Mouse, Base.Dung_Rat",
    -- Number of hours since an item was dropped on the ground before it is removed.  Items are removed the next time that part of the map is loaded.   Zero means items are not removed. Min: 0.00 Max: 2147483647.00 Default: 24.00
    HoursForWorldItemRemoval = 24.0,
    -- If true, any items *not* in WorldItemRemovalList will be removed.
    ItemRemovalListBlacklistToggle = false,
    -- How long after the end of the world to begin. This will affect starting world erosion and food spoilage. Does not affect the starting date. Default = 0
    -- 1 = 0
    -- 2 = 1
    -- 3 = 2
    -- 4 = 3
    -- 5 = 4
    -- 6 = 5
    -- 7 = 6
    -- 8 = 7
    -- 9 = 8
    -- 10 = 9
    -- 11 = 10
    -- 12 = 11
    -- 13 = 12
    TimeSinceApo = 1,
    -- How much water plants will lose per day, and their ability to avoid disease. Default = Normal
    -- 1 = Very High
    -- 2 = High
    -- 3 = Normal
    -- 4 = Low
    -- 5 = Very Low
    PlantResilience = 3,
    -- The yield of plants when harvested. Default = Normal
    -- 1 = Very Poor
    -- 2 = Poor
    -- 3 = Normal
    -- 4 = Abundant
    -- 5 = Very Abundant
    PlantAbundance = 3,
    -- Recovery from being tired after performing actions. Default = Normal
    -- 1 = Very Fast
    -- 2 = Fast
    -- 3 = Normal
    -- 4 = Slow
    -- 5 = Very Slow
    EndRegen = 3,
    -- How regularly a helicopter passes over the Event Zone. Default = Once
    -- 1 = Never
    -- 2 = Once
    -- 3 = Sometimes
    -- 4 = Often
    Helicopter = 2,
    -- How often zombie-attracting metagame events like distant gunshots will occur. Default = Sometimes
    -- 1 = Never
    -- 2 = Sometimes
    -- 3 = Often
    MetaEvent = 2,
    -- How often events during the player's sleep, like nightmares, occur. Default = Never
    -- 1 = Never
    -- 2 = Sometimes
    -- 3 = Often
    SleepingEvent = 1,
    -- How much fuel is consumed by generators per in-game hour. Min: 0.00 Max: 100.00 Default: 0.10
    GeneratorFuelConsumption = 0.1,
    -- The chance of electrical generators spawning on the map. Default = Rare
    -- 1 = None (not recommended)
    -- 2 = Insanely Rare
    -- 3 = Extremely Rare
    -- 4 = Rare
    -- 5 = Normal
    -- 6 = Common
    -- 7 = Abundant
    GeneratorSpawning = 3,
    -- How often a looted map will have notes on it, written by a deceased survivor. Default = Sometimes
    -- 1 = Never
    -- 2 = Extremely Rare
    -- 3 = Rare
    -- 4 = Sometimes
    -- 5 = Often
    -- 6 = Very Often
    AnnotatedMapChance = 4,
    -- Adds free points during character creation. Min: -100 Max: 100 Default: 0
    CharacterFreePoints = 0,
    -- Gives player-built constructions extra hit points so they are  more resistant to zombie damage. Default = Normal
    -- 1 = Very Low
    -- 2 = Low
    -- 3 = Normal
    -- 4 = High
    -- 5 = Very High
    ConstructionBonusPoints = 3,
    -- The level of ambient lighting at night. Default = Normal
    -- 1 = Pitch Black
    -- 2 = Dark
    -- 3 = Normal
    -- 4 = Bright
    NightDarkness = 3,
    -- The time from dusk to dawn. Default = Normal
    -- 1 = Always Night
    -- 2 = Long
    -- 3 = Normal
    -- 4 = Short
    -- 5 = Always Day
    NightLength = 3,
    -- If survivors can get broken limbs from impacts, zombie damage, falls etc.
    BoneFracture = true,
    -- The impact that injuries have on your body, and their healing time. Default = Normal
    -- 1 = Low
    -- 2 = Normal
    -- 3 = High
    InjurySeverity = 2,
    -- How long, in hours, before dead zombie bodies disappear from the world.  If 0, maggots will not spawn on corpses. Min: -1.00 Max: 2147483647.00 Default: 216.00
    HoursForCorpseRemoval = 216.0,
    -- The impact that nearby decaying bodies has on the player's health and emotions. Default = Normal
    -- 1 = None
    -- 2 = Low
    -- 3 = Normal
    -- 4 = High
    -- 5 = Insane
    DecayingCorpseHealthImpact = 3,
    -- Whether nearby "living" zombies have the same impact on the player's health and emotions.
    ZombieHealthImpact = false,
    -- How much blood is sprayed on floors and walls by injuries. Default = Normal
    -- 1 = None
    -- 2 = Low
    -- 3 = Normal
    -- 4 = High
    -- 5 = Ultra Gore
    BloodLevel = 3,
    -- How quickly clothing degrades, becomes dirty, and bloodied. Default = Normal
    -- 1 = Disabled
    -- 2 = Slow
    -- 3 = Normal
    -- 4 = Fast
    ClothingDegradation = 3,
    -- If fires spread when started.
    FireSpread = true,
    -- Number of in-game days before rotten food is removed from the map.  -1 means rotten food is never removed. Min: -1 Max: 2147483647 Default: -1
    DaysForRottenFoodRemoval = -1,
    -- If enabled, generators will work on exterior tiles.  This will allow, for example, the powering of gas pumps.
    AllowExteriorGenerator = true,
    -- Maximum intensity of fog. Default = Normal
    -- 1 = Normal
    -- 2 = Moderate
    -- 3 = Low
    -- 4 = None
    MaxFogIntensity = 1,
    -- Maximum intensity of rain. Default = Normal
    -- 1 = Normal
    -- 2 = Moderate
    -- 3 = Low
    MaxRainFxIntensity = 1,
    -- If snow will accumulate on the ground.  If disabled, snow will still show on vegetation and rooftops.
    EnableSnowOnGround = true,
    -- If melee attacking slows you down.
    AttackBlockMovements = true,
    -- The chance of finding randomized buildings on the map (eg. burnt out houses,  ones containing loot stashes or dead bodies). Default = Rare
    -- 1 = Never
    -- 2 = Extremely Rare
    -- 3 = Rare
    -- 4 = Sometimes
    -- 5 = Often
    -- 6 = Very Often
    -- 7 = Always Tries
    SurvivorHouseChance = 3,
    -- The chance of road stories (eg. police roadblocks) spawning. Default = Rare
    -- 1 = Never
    -- 2 = Extremely Rare
    -- 3 = Rare
    -- 4 = Sometimes
    -- 5 = Often
    -- 6 = Very Often
    -- 7 = Always Tries
    VehicleStoryChance = 3,
    -- The chance of stories specific to map zones (eg. a campsite in a forest) spawning. Default = Rare
    -- 1 = Never
    -- 2 = Extremely Rare
    -- 3 = Rare
    -- 4 = Sometimes
    -- 5 = Often
    -- 6 = Very Often
    -- 7 = Always Tries
    ZoneStoryChance = 3,
    -- Allows you to select from every piece of clothing in the game when customizing your character
    AllClothesUnlocked = false,
    -- If tainted water will show a warning marking it as such.
    EnableTaintedWaterText = true,
    -- If vehicles will spawn.
    EnableVehicles = true,
    -- How frequently vehicles can be discovered on the map. Default = Low
    -- 1 = None
    -- 2 = Very Low
    -- 3 = Low
    -- 4 = Normal
    -- 5 = High
    CarSpawnRate = 3,
    -- General engine loudness to zombies. Min: 0.00 Max: 100.00 Default: 1.00
    ZombieAttractionMultiplier = 1.0,
    -- Whether found vehicles are locked, need keys to start etc.
    VehicleEasyUse = false,
    -- How full the gas tank of discovered vehicles will be. Default = Low
    -- 1 = Very Low
    -- 2 = Low
    -- 3 = Normal
    -- 4 = High
    -- 5 = Very High
    -- 6 = Full
    InitialGas = 2,
    -- If enabled, gas pumps will never run out of fuel
    FuelStationGasInfinite = false,
    -- The minimum amount of gasoline that can spawn in gas pumps. Check the "Advanced" box below to use a custom amount. Min: 0.00 Max: 1.00 Default: 0.00
    FuelStationGasMin = 0.0,
    -- The maximum amount of gasoline that can spawn in gas pumps. Check the "Advanced" box below to use a custom amount. Min: 0.00 Max: 1.00 Default: 0.80
    FuelStationGasMax = 0.8,
    -- The chance, as a percentage, that individual gas pumps will initially have no fuel. Min: 0 Max: 100 Default: 20
    FuelStationGasEmptyChance = 20,
    -- How likely cars will be locked Default = Sometimes
    -- 1 = Never
    -- 2 = Extremely Rare
    -- 3 = Rare
    -- 4 = Sometimes
    -- 5 = Often
    -- 6 = Very Often
    LockedCar = 4,
    -- How gas-hungry vehicles are. Min: 0.00 Max: 100.00 Default: 1.00
    CarGasConsumption = 1.0,
    -- General condition discovered vehicles will be in. Default = Normal
    -- 1 = Very Low
    -- 2 = Low
    -- 3 = Normal
    -- 4 = High
    -- 5 = Very High
    CarGeneralCondition = 3,
    -- The amount of damage dealt to vehicles that crash. Default = Normal
    -- 1 = Very Low
    -- 2 = Low
    -- 3 = Normal
    -- 4 = High
    -- 5 = Very High
    CarDamageOnImpact = 3,
    -- Damage received by the player from being crashed into. Default = None
    -- 1 = None
    -- 2 = Low
    -- 3 = Normal
    -- 4 = High
    -- 5 = Very High
    DamageToPlayerFromHitByACar = 1,
    -- If traffic jams consisting of wrecked cars  will appear on main roads.
    TrafficJam = true,
    -- How frequently discovered vehicles have active alarms. Default = Rare
    -- 1 = Never
    -- 2 = Extremely Rare
    -- 3 = Rare
    -- 4 = Sometimes
    -- 5 = Often
    -- 6 = Very Often
    CarAlarm = 3,
    -- If the player can get injured from being in a car accident.
    PlayerDamageFromCrash = true,
    -- How many in-game hours before a wailing siren shuts off. Min: 0.00 Max: 168.00 Default: 0.00
    SirenShutoffHours = 0.0,
    -- The chance of finding a vehicle with gas in its tank. Default = Normal
    -- 1 = Low
    -- 2 = Normal
    -- 3 = High
    ChanceHasGas = 2,
    -- Whether a player can discover a car that has been cared for  after the Knox infection struck. Default = Low
    -- 1 = None
    -- 2 = Low
    -- 3 = Normal
    -- 4 = High
    RecentlySurvivorVehicles = 2,
    -- If certain melee weapons will be able to strike multiple zombies in one hit.
    MultiHitZombies = false,
    -- Chance of being bitten when a zombie attacks from behind. Default = High
    -- 1 = Low
    -- 2 = Medium
    -- 3 = High
    RearVulnerability = 3,
    -- If zombies will head towards the sound of vehicle sirens.
    SirenEffectsZombies = true,
    -- Speed at which animals stats (hunger, thirst etc.) reduce. Default = Normal
    -- 1 = Ultra Fast
    -- 2 = Very Fast
    -- 3 = Fast
    -- 4 = Normal
    -- 5 = Slow
    -- 6 = Very Slow
    AnimalStatsModifier = 4,
    -- Speed at which animals stats (hunger, thirst etc.) reduce while in meta. Default = Normal
    -- 1 = Ultra Fast
    -- 2 = Very Fast
    -- 3 = Fast
    -- 4 = Normal
    -- 5 = Slow
    -- 6 = Very Slow
    AnimalMetaStatsModifier = 4,
    -- How long animals will be pregnant for before giving birth. Default = Normal
    -- 1 = Ultra Fast
    -- 2 = Very Fast
    -- 3 = Fast
    -- 4 = Normal
    -- 5 = Slow
    -- 6 = Very Slow
    AnimalPregnancyTime = 4,
    -- Speed at which animals age. Default = Normal
    -- 1 = Ultra Fast
    -- 2 = Very Fast
    -- 3 = Fast
    -- 4 = Normal
    -- 5 = Slow
    -- 6 = Very Slow
    AnimalAgeModifier = 4,
    -- Default = Normal
    -- 1 = Ultra Fast
    -- 2 = Very Fast
    -- 3 = Fast
    -- 4 = Normal
    -- 5 = Slow
    -- 6 = Very Slow
    AnimalMilkIncModifier = 4,
    -- Default = Normal
    -- 1 = Ultra Fast
    -- 2 = Very Fast
    -- 3 = Fast
    -- 4 = Normal
    -- 5 = Slow
    -- 6 = Very Slow
    AnimalWoolIncModifier = 4,
    -- The chance of finding animals in farm. Default = Often
    -- 1 = Never
    -- 2 = Extremely Rare
    -- 3 = Rare
    -- 4 = Sometimes
    -- 5 = Often
    -- 6 = Very Often
    -- 7 = Always
    AnimalRanchChance = 5,
    -- The number of hours grass will regrow after being  eaten by an animal or cut by the player. Min: 1 Max: 9999 Default: 240
    AnimalGrassRegrowTime = 240,
    -- If a meta (ie. not actually visible in-game) fox may attack  your chickens if the hutch's door is left open at night.
    AnimalMetaPredator = false,
    -- If on, animals will only mate during their breeding season (if any).  Otherwise they can reproduce/lay eggs all year round.
    AnimalMatingSeason = true,
    -- How long before baby animals will hatch from eggs. Default = Normal
    -- 1 = Ultra Fast
    -- 2 = Very Fast
    -- 3 = Fast
    -- 4 = Normal
    -- 5 = Slow
    -- 6 = Very Slow
    AnimalEggHatch = 4,
    -- If true, animal calls will attract nearby zombies.
    AnimalSoundAttractZombies = true,
    -- The chance of animals leaving tracks. Default = Sometimes
    -- 1 = Never
    -- 2 = Extremely Rare
    -- 3 = Rare
    -- 4 = Sometimes
    -- 5 = Often
    -- 6 = Very Often
    AnimalTrackChance = 4,
    -- The chance of creating a path for animals to be hunted. Default = Sometimes
    -- 1 = Never
    -- 2 = Extremely Rare
    -- 3 = Rare
    -- 4 = Sometimes
    -- 5 = Often
    -- 6 = Very Often
    AnimalPathChance = 4,
    -- The frequency and intensity of eg. rats in infested buildings. Min: 0 Max: 50 Default: 25
    MaximumRatIndex = 25,
    -- How long it takes for the Maximum Vermin Index to be reached. Min: 0 Max: 365 Default: 90
    DaysUntilMaximumRatIndex = 90,
    -- If a piece of media hasn't been fully seen or read, this setting determines whether it's displayed fully, displayed as "???", or hidden completely. Default = Completely hidden
    -- 1 = Fully revealed
    -- 2 = Shown as ???
    -- 3 = Completely hidden
    MetaKnowledge = 3,
    -- If true, you will be able to see any recipes that can be done with a station, even if you haven't learnt them yet.
    SeeNotLearntRecipe = true,
    -- If a building has more than this amount of rooms it will not be looted. Min: 0 Max: 200 Default: 50
    MaximumLootedBuildingRooms = 50,
    -- If poison can be added to food. Default = True
    -- 1 = True
    -- 2 = False
    -- 3 = Only bleach poisoning is disabled
    EnablePoisoning = 1,
    -- If/when maggots can spawn in corpses. Default = In and Around Bodies
    -- 1 = In and Around Bodies
    -- 2 = In Bodies Only
    -- 3 = Never
    MaggotSpawn = 1,
    -- The higher the value, the longer lightbulbs last before breaking.  If 0, lightbulbs will never break.  Does not affect vehicle headlights. Min: 0.00 Max: 1000.00 Default: 2.00
    LightBulbLifespan = 2.0,
    -- The abundance of fish in rivers and lakes. Default = Poor
    -- 1 = Very Poor
    -- 2 = Poor
    -- 3 = Normal
    -- 4 = Abundant
    -- 5 = Very Abundant
    FishAbundance = 2,
    -- When a skill is at this level or above, television/VHS/other media  will not provide XP for it. Min: 0 Max: 10 Default: 3
    LevelForMediaXPCutoff = 3,
    -- When a skill is at this level or above, scrapping furniture does not provide XP for the relevant skill. Does not apply to Electrical. Min: 0 Max: 10 Default: 0
    LevelForDismantleXPCutoff = 0,
    -- Number of days before old blood splats are removed. Removal happens when map chunks are loaded. 0 means they will never disappear. Min: 0 Max: 365 Default: 0
    BloodSplatLifespanDays = 0,
    -- Number of days before one can benefit from reading previously read literature items. Min: 1 Max: 365 Default: 45
    LiteratureCooldown = 45,
    -- If there are diminishing returns on bonus trait points provided from selecting multiple negative traits. Default = None
    -- 1 = None
    -- 2 = 1 point penalty for every 3 negative traits selected
    -- 3 = 1 point penalty for every 2 negative traits selected
    -- 4 = 1 point penalty for every negative trait selected after the first
    NegativeTraitsPenalty = 1,
    -- The number of in-game minutes it takes to read one page of a skill book. Min: 0.00 Max: 60.00 Default: 2.00
    MinutesPerPage = 0.21,
    -- When enabled, crops and herbs grown inside buildings will die. Does not affect houseplants.
    KillInsideCrops = true,
    -- When enabled, the growth of plants is affected by seasons.
    PlantGrowingSeasons = true,
    -- <BHC> [!] It is recommended that you DO NOT change this. Changing this can result in performance issues. [!] <RGB:1,1,1>   When enabled, dirt can be placed, and farming performed on other than the ground level.
    PlaceDirtAboveground = false,
    -- The speed of plant growth. Min: 0.10 Max: 100.00 Default: 1.00
    FarmingSpeedNew = 1.0,
    -- The abundance of harvested crops. Min: 0.10 Max: 10.00 Default: 1.00
    FarmingAmountNew = 1.0,
    -- The chance that any building will already be looted when found. Check the "Advanced" box below to use a custom number. Min: 0 Max: 200 Default: 25
    MaximumLooted = 25,
    -- How long it takes for Maximum Looted Building Chance to be reached. Min: 0 Max: 3650 Default: 90
    DaysUntilMaximumLooted = 90,
    -- The chance that any rural building will already be looted when found. Check the "Advanced" box below to use a custom number. Min: 0.00 Max: 2.00 Default: 0.50
    RuralLooted = 0.5,
    -- The maximum loot that won't spawn when Days Until Maximum Diminished Loot is reached. Check the "Advanced" box below to use an exact percentage. Min: 0 Max: 100 Default: 20
    MaximumDiminishedLoot = 20,
    -- How long it takes for Maximum Diminished Loot Percentage to be reached. Min: 0 Max: 3650 Default: 3650
    DaysUntilMaximumDiminishedLoot = 3650,
    -- Functions as a multiplier when applying muscle strain from swinging weapons or carrying heavy loads. Min: 0.00 Max: 10.00 Default: 0.70
    MuscleStrainFactor = 0.7,
    -- Functions as a multiplier when applying discomfort from worn items. Min: 0.00 Max: 10.00 Default: 0.80
    DiscomfortFactor = 0.8,
    -- If greater than zero damage can be taken from serious wound infections. Min: 0.00 Max: 10.00 Default: 1.00
    WoundInfectionFactor = 1.0,
    -- If true clothing with randomized tints will not be so dark to be virtually black.
    NoBlackClothes = true,
    -- Disables the failure chances when climbing sheet ropes or over walls.
    EasyClimbing = false,
    -- The maximum hours of fuel that can be placed in a campfire, wood stove etc. Min: 1 Max: 168 Default: 8
    MaximumFireFuelHours = 8,
    -- Replaces Chance-To-Hit mechanics with Chance-To-Damage calculations.  This mode prioritizes player aiming. Default = Zombies only
    -- 1 = Disabled
    -- 2 = Zombies only
    -- 3 = All types of target
    FirearmUseDamageChance = 2,
    -- A multiplier for the distance at which zombies can hear gunshots. Min: 0.20 Max: 2.00 Default: 1.00
    FirearmNoiseMultiplier = 1.0,
    -- Multiplier for firearm jamming chance. 0 disables jamming. Min: 0.00 Max: 10.00 Default: 1.00
    FirearmJamMultiplier = 1.0,
    -- Multiplier for Moodle effects on hit chance. 0 disables Moodle penalty. Min: 0.00 Max: 10.00 Default: 1.00
    FirearmMoodleMultiplier = 1.0,
    -- Multiplier for the effects of weather (wind, rain and fog) on hit chance. 0 disables weather effect. Min: 0.00 Max: 10.00 Default: 1.00
    FirearmWeatherMultiplier = 1.0,
    -- Enable to have headgear like welding masks affect hit chance
    FirearmHeadGearEffect = true,
    -- Chance to turn a dirt floor into a clay floor. Applies to lakes. Min: 0.00 Max: 1.00 Default: 0.05
    ClayLakeChance = 0.05,
    -- Chance to turn a dirt floor into a clay floor. Applies to rivers. Min: 0.00 Max: 1.00 Default: 0.05
    ClayRiverChance = 0.05,
    -- Min: 1 Max: 100 Default: 20
    GeneratorTileRange = 20,
    -- How many levels both above and below a generator it can provide with electricity. Min: 1 Max: 15 Default: 3
    GeneratorVerticalPowerRange = 3,
    -- Min: 0.00 Max: 500.00 Default: 30.00
    CSP_XPSimpleBase = 30.0,
    -- Min: 0.00 Max: 500.00 Default: 60.00
    CSP_XPIntermediateBase = 60.0,
    -- Min: 0.00 Max: 500.00 Default: 100.00
    CSP_XPAdvancedBase = 100.0,
    -- Min: 0 Max: 100 Default: 10
    HephasVitamins_HealPercent = 10,
    -- Min: 0 Max: 100 Default: 5
    HephasVitamins_HealAmount = 5,
    -- Min: 0.00 Max: 1.00 Default: 0.50
    HephasVitamins_UseDelta = 0.5,
    -- Min: 0 Max: 100 Default: 10
    HephasVitamins_FatigueChange = 10,
    -- Min: 0 Max: 100 Default: 1
    HephasVitamins_StressChange = 1,
    HephasVitamins_EnableSayings = true,
    Basement = {
        -- How frequently basements spawn at random locations. Default = Sometimes
        -- 1 = Never
        -- 2 = Extremely Rare
        -- 3 = Rare
        -- 4 = Sometimes
        -- 5 = Often
        -- 6 = Very Often
        -- 7 = Always
        SpawnFrequency = 4,
    },
    Map = {
        -- If enabled, a mini-map window will be available.
        AllowMiniMap = true,
        -- If enabled, the world map can be accessed.
        AllowWorldMap = true,
        -- If enabled, the world map will be completely filled in on starting the game.
        MapAllKnown = true,
        -- If enabled, maps can't be read unless there's a source of light available.
        MapNeedsLight = true,
    },
    ZombieLore = {
        -- How fast zombies move. Default = Random
        -- 1 = Sprinters
        -- 2 = Fast Shamblers
        -- 3 = Shamblers
        -- 4 = Random
        Speed = 4,
        -- If Random Speed is enabled, this controls what percentage of zombies are Sprinters. Check the "Advanced" box below to use a custom percentage. Min: 0 Max: 100 Default: 0
        SprinterPercentage = 2,
        -- The damage zombies inflict per attack. Default = Normal
        -- 1 = Superhuman
        -- 2 = Normal
        -- 3 = Weak
        -- 4 = Random
        Strength = 2,
        -- The difficulty of killing a zombie. Default = Random
        -- 1 = Tough
        -- 2 = Normal
        -- 3 = Fragile
        -- 4 = Random
        Toughness = 4,
        -- How the Knox Virus spreads. Default = Blood and Saliva
        -- 1 = Blood and Saliva
        -- 2 = Saliva Only
        -- 3 = Everyone's Infected
        -- 4 = None
        Transmission = 1,
        -- How quickly the infection takes effect. Default = 2-3 Days
        -- 1 = Instant
        -- 2 = 0-30 Seconds
        -- 3 = 0-1 Minutes
        -- 4 = 0-12 Hours
        -- 5 = 2-3 Days
        -- 6 = 1-2 Weeks
        -- 7 = Never
        Mortality = 4,
        -- How quickly infected corpses rise as zombies. Default = 0-1 Minutes
        -- 1 = Instant
        -- 2 = 0-30 Seconds
        -- 3 = 0-1 Minutes
        -- 4 = 0-12 Hours
        -- 5 = 2-3 Days
        -- 6 = 1-2 Weeks
        Reanimate = 3,
        -- Zombie intelligence. Default = Basic Navigation
        -- 1 = Navigate and Use Doors
        -- 2 = Navigate
        -- 3 = Basic Navigation
        -- 4 = Random
        Cognition = 3,
        -- Min: 0 Max: 100 Default: 0
        DoorOpeningPercentage = 33,
        -- How often zombies can crawl under parked vehicles. Default = Often
        -- 1 = Crawlers Only
        -- 2 = Extremely Rare
        -- 3 = Rare
        -- 4 = Sometimes
        -- 5 = Often
        -- 6 = Very Often
        -- 7 = Always
        CrawlUnderVehicle = 5,
        -- How long zombies remember a player after seeing or hearing them. Default = Normal
        -- 1 = Long
        -- 2 = Normal
        -- 3 = Short
        -- 4 = None
        -- 5 = Random
        -- 6 = Random between Normal and None
        Memory = 2,
        -- Zombie vision radius. Default = Random between Normal and Poor
        -- 1 = Eagle
        -- 2 = Normal
        -- 3 = Poor
        -- 4 = Random
        -- 5 = Random between Normal and Poor
        Sight = 2,
        -- Zombie hearing radius. Default = Random between Normal and Poor
        -- 1 = Pinpoint
        -- 2 = Normal
        -- 3 = Poor
        -- 4 = Random
        -- 5 = Random between Normal and Poor
        Hearing = 2,
        -- Activates the new advanced stealth mechanics, which allows you to hide from zombies behind cars, takes traits and weather into account, and much more.
        SpottedLogic = true,
        -- If zombies that have not seen/heard player can attack doors and constructions while roaming.
        ThumpNoChasing = false,
        -- If zombies can destroy player constructions and defenses.
        ThumpOnConstruction = true,
        -- Whether zombies are more "active" during the day or night.  "Active" zombies will use the speed set in the "Speed" setting.  "Inactive" zombies will be slower, and tend not to give chase. Default = Both
        -- 1 = Both
        -- 2 = Night
        -- 3 = Day
        ActiveOnly = 1,
        -- If zombies trigger house alarms when breaking through windows or doors.
        TriggerHouseAlarm = true,
        -- If multiple attacking zombies can drag you down and kill you.  Dependent on zombie strength.
        ZombiesDragDown = true,
        -- If crawler zombies beside a player contribute to the chance of being dragged down and killed by a group of zombies.
        ZombiesCrawlersDragDown = false,
        -- If zombies have a chance to lunge at you after climbing over a fence or through a window if you're too close.
        ZombiesFenceLunge = true,
        -- Serves as a multiplier when determining the effectiveness of armor worn by zombies. Min: 0.00 Max: 100.00 Default: 2.00
        ZombiesArmorFactor = 2.0,
        -- The maximum defense percentage that any worn protective garments can provide to a zombie. Min: 0 Max: 100 Default: 85
        ZombiesMaxDefense = 85,
        -- Percentage chance of having a random attached weapon. Min: 0 Max: 100 Default: 6
        ChanceOfAttachedWeapon = 6,
        -- How much damage zombies take when falling from height. Min: 0.00 Max: 100.00 Default: 1.00
        ZombiesFallDamage = 1.0,
        -- Whether some dead-looking zombies will reanimate and attack the player. Default = World Zombies
        -- 1 = World Zombies
        -- 2 = World and Combat Zombies
        -- 3 = Never
        DisableFakeDead = 1,
        -- Zombies will not spawn where players spawn. Default = Inside the building and around it
        -- 1 = Inside the building and around it
        -- 2 = Inside the building
        -- 3 = Inside the room
        -- 4 = Zombies can spawn anywhere
        PlayerSpawnZombieRemoval = 1,
        -- How many zombies it takes to damage a tall fence. Min: -1 Max: 100 Default: 25
        FenceThumpersRequired = 25,
        -- How quickly zombies damage tall fences. Min: 0.01 Max: 100.00 Default: 1.00
        FenceDamageMultiplier = 1.0,
    },
    ZombieConfig = {
        -- Set by the "Zombie Count" population option, or by a custom number here. Insane = 2.5, Very High = 1.6, High = 1.2, Normal = 0.65, Low = 0.15, None = 0.0. Min: 0.00 Max: 4.00 Default: 0.65
        PopulationMultiplier = 0.8,
        -- A multiplier for the desired zombie population at the start of the game. Insane = 3.0, Very High = 2.0, High = 1.5, Normal = 1.0, Low = 0.5, None = 0.0. Min: 0.00 Max: 4.00 Default: 1.00
        PopulationStartMultiplier = 1.0,
        -- A multiplier for the desired zombie population on the peak day. Insane = 3.0, Very High = 2.0, High = 1.5, Normal = 1.0, Low = 0.5, None = 0.0. Min: 0.00 Max: 4.00 Default: 1.50
        PopulationPeakMultiplier = 1.5,
        -- The day when the population reaches its peak. Min: 1 Max: 365 Default: 28
        PopulationPeakDay = 28,
        -- The number of hours that must pass before zombies may respawn in a cell. If 0, spawning is disabled. Min: 0.00 Max: 8760.00 Default: 0.00
        RespawnHours = 0.0,
        -- The number of hours that a chunk must be unseen before zombies may respawn in it. Min: 0.00 Max: 8760.00 Default: 0.00
        RespawnUnseenHours = 0.0,
        -- The fraction of a cell's desired population that may respawn every RespawnHours. Min: 0.00 Max: 1.00 Default: 0.00
        RespawnMultiplier = 0.0,
        -- The number of hours that must pass before zombies migrate  to empty parts of the same cell. If 0, migration is disabled. Min: 0.00 Max: 8760.00 Default: 12.00
        RedistributeHours = 12.0,
        -- The distance a zombie will try to walk towards the last sound it heard. Min: 10 Max: 1000 Default: 100
        FollowSoundDistance = 100,
        -- The size of groups real zombies form when idle. 0 means zombies don't form groups. Groups don't form inside buildings or forest zones. Min: 0 Max: 1000 Default: 20
        RallyGroupSize = 20,
        -- The amount, as a percentage, that zombie groups can vary in size from the default (both larger and smaller).   For example, at 50% variance with a default group size of 20, groups will vary in size from 10-30. Min: 0 Max: 100 Default: 50
        RallyGroupSizeVariance = 50,
        -- The distance real zombies travel to form groups when idle. Min: 5 Max: 50 Default: 20
        RallyTravelDistance = 20,
        -- The distance between zombie groups. Min: 5 Max: 25 Default: 15
        RallyGroupSeparation = 15,
        -- How close members of a zombie group stay to the group's "leader". Min: 1 Max: 10 Default: 3
        RallyGroupRadius = 3,
        -- Controls the maximum number of zombies tracked before cleanup occurs. 0 means zombies will not be cleaned up. The default value (300) is strongly recommended. Increasing this value or setting to 0 may cause severe performance problems. For troubleshooting and bug-report purposes, please reproduce any issue with the default setting before submitting a report. Min: 0 Max: 5000 Default: 300
        ZombiesCountBeforeDelete = 300,
    },
    MultiplierConfig = {
        -- The rate at which all skills level up. Min: 0.00 Max: 1000.00 Default: 1.00
        Global = 1.0,
        -- When enabled, all skills will use the Global Multiplier.
        GlobalToggle = true,
        -- Rate at which Fitness skill levels up. Min: 0.00 Max: 1000.00 Default: 1.00
        Fitness = 1.0,
        -- Rate at which Strength skill levels up. Min: 0.00 Max: 1000.00 Default: 1.00
        Strength = 1.0,
        -- Rate at which Sprinting skill levels up. Min: 0.00 Max: 1000.00 Default: 1.00
        Sprinting = 1.0,
        -- Rate at which Lightfooted skill levels up. Min: 0.00 Max: 1000.00 Default: 1.00
        Lightfoot = 1.0,
        -- Rate at which Nimble skill levels up. Min: 0.00 Max: 1000.00 Default: 1.00
        Nimble = 1.0,
        -- Rate at which Sneaking skill levels up. Min: 0.00 Max: 1000.00 Default: 1.00
        Sneak = 1.0,
        -- Rate at which Axe skill levels up. Min: 0.00 Max: 1000.00 Default: 1.00
        Axe = 1.0,
        -- Rate at which Long Blunt skill levels up. Min: 0.00 Max: 1000.00 Default: 1.00
        Blunt = 1.0,
        -- Rate at which Short Blunt skill levels up. Min: 0.00 Max: 1000.00 Default: 1.00
        SmallBlunt = 1.0,
        -- Rate at which Long Blade skill levels up. Min: 0.00 Max: 1000.00 Default: 1.00
        LongBlade = 1.0,
        -- Rate at which Short Blade skill levels up. Min: 0.00 Max: 1000.00 Default: 1.00
        SmallBlade = 1.0,
        -- Rate at which Spear skill levels up. Min: 0.00 Max: 1000.00 Default: 1.00
        Spear = 1.0,
        -- Rate at which Maintenance skill levels up. Min: 0.00 Max: 1000.00 Default: 1.00
        Maintenance = 1.0,
        -- Rate at which Carpentry skill levels up. Min: 0.00 Max: 1000.00 Default: 1.00
        Woodwork = 1.0,
        -- Rate at which Cooking skill levels up. Min: 0.00 Max: 1000.00 Default: 1.00
        Cooking = 1.0,
        -- Rate at which Agriculture skill levels up. Min: 0.00 Max: 1000.00 Default: 1.00
        Farming = 1.0,
        -- Rate at which First Aid skill levels up. Min: 0.00 Max: 1000.00 Default: 1.00
        Doctor = 1.0,
        -- Rate at which Electrical skill levels up. Min: 0.00 Max: 1000.00 Default: 1.00
        Electricity = 1.0,
        -- Rate at which Welding skill levels up. Min: 0.00 Max: 1000.00 Default: 1.00
        MetalWelding = 1.0,
        -- Rate at which Mechanics skill levels up. Min: 0.00 Max: 1000.00 Default: 1.00
        Mechanics = 1.0,
        -- Rate at which Tailoring skill levels up. Min: 0.00 Max: 1000.00 Default: 1.00
        Tailoring = 1.0,
        -- Rate at which Aiming skill levels up. Min: 0.00 Max: 1000.00 Default: 1.00
        Aiming = 1.0,
        -- Rate at which Reloading skill levels up. Min: 0.00 Max: 1000.00 Default: 1.00
        Reloading = 1.0,
        -- Rate at which Fishing skill levels up. Min: 0.00 Max: 1000.00 Default: 1.00
        Fishing = 1.0,
        -- Rate at which Trapping skill levels up. Min: 0.00 Max: 1000.00 Default: 1.00
        Trapping = 1.0,
        -- Rate at which Foraging skill levels up. Min: 0.00 Max: 1000.00 Default: 1.00
        PlantScavenging = 1.0,
        -- Rate at which Knapping skill levels up. Min: 0.00 Max: 1000.00 Default: 1.00
        FlintKnapping = 1.0,
        -- Rate at which Masonry skill levels up. Min: 0.00 Max: 1000.00 Default: 1.00
        Masonry = 1.0,
        -- Rate at which Pottery skill levels up. Min: 0.00 Max: 1000.00 Default: 1.00
        Pottery = 1.0,
        -- Rate at which Carving skill levels up. Min: 0.00 Max: 1000.00 Default: 1.00
        Carving = 1.0,
        -- Rate at which Animal Care skill levels up. Min: 0.00 Max: 1000.00 Default: 1.00
        Husbandry = 1.0,
        -- Rate at which Tracking skill levels up. Min: 0.00 Max: 1000.00 Default: 1.00
        Tracking = 1.0,
        -- Rate at which Blacksmithing skill levels up. Min: 0.00 Max: 1000.00 Default: 1.00
        Blacksmith = 1.0,
        -- Rate at which Butchering skill levels up. Min: 0.00 Max: 1000.00 Default: 1.00
        Butchering = 1.0,
        -- Rate at which Glassmaking skill levels up. Min: 0.00 Max: 1000.00 Default: 1.00
        Glassmaking = 1.0,
        -- Min: 0.00 Max: 1000.00 Default: 1.00
        Lockpicking = 1.0,
    },
    VFluidLib = {
        -- Min: 2 Max: 40 Default: 6
        TransferRange = 6,
        MountedHandContainers = false,
        DrinkHarmful = false,
        PumpsEnabled = false,
        HitchedRefuel = false,
        ServiceOverride = false,
        TankCleaning = 3,
        VanillaRules = false,
        -- Min: 0 Max: 100 Default: 35
        SpawnOrigin = 35,
        -- Min: 0 Max: 100 Default: 10
        SpawnFlavor = 10,
        -- Min: 0 Max: 100 Default: 30
        SpawnMixSmall = 30,
        -- Min: 0 Max: 100 Default: 23
        SpawnMixMedium = 23,
        -- Min: 0 Max: 100 Default: 2
        SpawnMixLarge = 2,
    },
    SPNCharCustom = {
        AllowCustomisationChange = 4,
        AdminLockedCustomisation = "",
        -- Min: 0 Max: 20 Default: 10
        BodyHairGrowth = 10,
        -- Min: 0 Max: 20 Default: 6
        StubbleHeadGrowth = 6,
        -- Min: 0 Max: 20 Default: 3
        StubbleBeardGrowth = 3,
        BodyHairGrowthEnabled = 1,
        MuscleVisuals = 1,
        -- Min: 0.10 Max: 1.00 Default: 0.50
        MissingEyeVisionModifier = 0.5,
        WashMakeup = true,
    },
    HB = {
        PermanentCasings = true,
        CustomIcons = true,
        CasingSounds = true,
        BanditsCasings = false,
        ManualRacking = false,
    },
    MarzGuns = {
        VanillaWeaponReplacement = true,
        VanillaAmmoReplacement = true,
        VanillaAttachmentReplacement = true,
        -- Min: 0.00 Max: 100.00 Default: 1.00
        LootMultiplier = 1.0,
        SpawnHighCapMags = true,
        SpawnExplosives = true,
        AutoRequipt = false,
    },
    ammomakerOptions = {
        Primers = false,
        -- Min: 1 Max: 10 Default: 1
        CraftingSpeed = 1,
        -- Min: 10 Max: 100 Default: 10
        ProduceAmmoBulkSize = 10,
        -- Min: 10 Max: 100 Default: 10
        DisassembleAmmoBulkSize = 10,
        -- Min: 10 Max: 100 Default: 10
        MakePrimerBulkSize = 10,
        -- Min: 1 Max: 100 Default: 20
        NitreYield = 10,
        -- Min: 1 Max: 5 Default: 1
        BirdExYield = 1,
        -- Min: 1 Max: 365 Default: 7
        NitreBedDays = 7,
        -- Min: 1 Max: 10 Default: 1
        NitreBedYield = 1,
        -- Min: 1 Max: 200 Default: 8
        BirdExSpawnMin = 8,
        -- Min: 1 Max: 200 Default: 24
        BirdExSpawnMax = 24,
        -- Min: 1 Max: 10 Default: 1
        BirdFeatherSpawnMin = 1,
        -- Min: 1 Max: 10 Default: 3
        BirdFeatherSpawnMax = 3,
        -- Min: 1 Max: 20 Default: 1
        CasingsSpawnMin = 1,
        -- Min: 1 Max: 20 Default: 3
        CasingsSpawnMax = 3,
        -- Min: 0 Max: 720 Default: 168
        DroppedCasingsLifetime = 168,
        -- Min: 0 Max: 100 Default: 10
        OldCasingsPercentage = 10,
        DropCasingsReload = false,
        CasingModelsCalibre = true,
        CasingIconsCalibre = true,
        CollectAdditionalSeeds = true,
        BrassDoorknobs = true,
        AllowConvertRecipes = false,
        ShowHiddenRecipes = false,
        SpawnRecipeMagazines = true,
        SpawnRegularAmmoParts = true,
        SpawnBoxedAmmoParts = true,
        SpawnOldAmmoParts = true,
        SpawnBaggedAmmoParts = true,
        SpawnMilitaryAmmoParts = true,
        -- Min: 0 Max: 10 Default: 2
        RollsMilitaryArmystorage = 2,
        -- Min: 1 Max: 10 Default: 4
        ChanceMilitaryArmystorage = 4,
        -- Min: 1 Max: 100 Default: 2
        MaxMilitaryArmystorage = 2,
        -- Min: 0 Max: 10 Default: 2
        RollsMilitaryArmysurplus = 2,
        -- Min: 1 Max: 10 Default: 3
        ChanceMilitaryArmysurplus = 3,
        -- Min: 1 Max: 100 Default: 1
        MaxMilitaryArmysurplus = 1,
        -- Min: 0 Max: 10 Default: 3
        RollsOldArmytent = 3,
        -- Min: 1 Max: 10 Default: 3
        ChanceOldArmytent = 3,
        -- Min: 1 Max: 100 Default: 10
        MaxOldArmytent = 10,
        -- Min: 0 Max: 10 Default: 3
        RollsRegularGunstorage = 3,
        -- Min: 1 Max: 10 Default: 5
        ChanceRegularGunstorage = 5,
        -- Min: 1 Max: 100 Default: 10
        MaxRegularGunstorage = 10,
        -- Min: 0 Max: 10 Default: 2
        RollsBoxGunstorage = 2,
        -- Min: 1 Max: 10 Default: 4
        ChanceBoxGunstorage = 4,
        -- Min: 1 Max: 100 Default: 2
        MaxBoxGunstorage = 2,
        -- Min: 0 Max: 10 Default: 2
        RollsOldGunstorage = 2,
        -- Min: 1 Max: 10 Default: 3
        ChanceOldGunstorage = 3,
        -- Min: 1 Max: 100 Default: 10
        MaxOldGunstorage = 10,
        -- Min: 0 Max: 10 Default: 2
        RollsBagGunstorage = 2,
        -- Min: 1 Max: 10 Default: 3
        ChanceBagGunstorage = 3,
        -- Min: 1 Max: 100 Default: 1
        MaxBagGunstorage = 1,
        -- Min: 0 Max: 10 Default: 3
        RollsRegularGunstore = 3,
        -- Min: 1 Max: 10 Default: 5
        ChanceRegularGunstore = 5,
        -- Min: 1 Max: 100 Default: 10
        MaxRegularGunstore = 10,
        -- Min: 0 Max: 10 Default: 2
        RollsBoxGunstore = 2,
        -- Min: 1 Max: 10 Default: 4
        ChanceBoxGunstore = 4,
        -- Min: 1 Max: 100 Default: 2
        MaxBoxGunstore = 2,
        -- Min: 0 Max: 10 Default: 3
        RollsRegularGunstorestorage = 3,
        -- Min: 1 Max: 10 Default: 5
        ChanceRegularGunstorestorage = 5,
        -- Min: 1 Max: 100 Default: 10
        MaxRegularGunstorestorage = 10,
        -- Min: 0 Max: 10 Default: 2
        RollsBoxGunstorestorage = 2,
        -- Min: 1 Max: 10 Default: 5
        ChanceBoxGunstorestorage = 5,
        -- Min: 1 Max: 100 Default: 2
        MaxBoxGunstorestorage = 2,
        -- Min: 0 Max: 10 Default: 2
        RollsOldGunstorestorage = 2,
        -- Min: 1 Max: 10 Default: 3
        ChanceOldGunstorestorage = 3,
        -- Min: 1 Max: 100 Default: 10
        MaxOldGunstorestorage = 10,
        -- Min: 0 Max: 10 Default: 2
        RollsBagGunstorestorage = 2,
        -- Min: 1 Max: 10 Default: 3
        ChanceBagGunstorestorage = 3,
        -- Min: 1 Max: 100 Default: 1
        MaxBagGunstorestorage = 1,
        -- Min: 0 Max: 10 Default: 2
        RollsRegularOutdoorsupply = 2,
        -- Min: 1 Max: 10 Default: 4
        ChanceRegularOutdoorsupply = 4,
        -- Min: 1 Max: 100 Default: 5
        MaxRegularOutdoorsupply = 5,
        -- Min: 0 Max: 10 Default: 1
        RollsBoxOutdoorsupply = 1,
        -- Min: 1 Max: 10 Default: 3
        ChanceBoxOutdoorsupply = 3,
        -- Min: 1 Max: 100 Default: 1
        MaxBoxOutdoorsupply = 1,
        -- Min: 0 Max: 10 Default: 4
        RollsRegularPolicearchive = 4,
        -- Min: 1 Max: 10 Default: 2
        ChanceRegularPolicearchive = 2,
        -- Min: 1 Max: 100 Default: 4
        MaxRegularPolicearchive = 4,
        -- Min: 0 Max: 10 Default: 4
        RollsOldPolicearchive = 4,
        -- Min: 1 Max: 10 Default: 2
        ChanceOldPolicearchive = 2,
        -- Min: 1 Max: 100 Default: 4
        MaxOldPolicearchive = 4,
        -- Min: 0 Max: 10 Default: 4
        RollsBagPolicearchive = 4,
        -- Min: 1 Max: 10 Default: 1
        ChanceBagPolicearchive = 1,
        -- Min: 1 Max: 100 Default: 2
        MaxBagPolicearchive = 2,
        -- Min: 0 Max: 10 Default: 4
        RollsRegularPolicegunstorage = 4,
        -- Min: 1 Max: 10 Default: 2
        ChanceRegularPolicegunstorage = 2,
        -- Min: 1 Max: 100 Default: 4
        MaxRegularPolicegunstorage = 4,
        -- Min: 0 Max: 10 Default: 4
        RollsOldPolicegunstorage = 4,
        -- Min: 1 Max: 10 Default: 2
        ChanceOldPolicegunstorage = 2,
        -- Min: 1 Max: 100 Default: 4
        MaxOldPolicegunstorage = 4,
        -- Min: 0 Max: 10 Default: 3
        RollsBagPolicegunstorage = 3,
        -- Min: 1 Max: 10 Default: 1
        ChanceBagPolicegunstorage = 1,
        -- Min: 1 Max: 100 Default: 2
        MaxBagPolicegunstorage = 2,
        -- Min: 0 Max: 10 Default: 4
        RollsRegularSafehouseLoot = 4,
        -- Min: 1 Max: 10 Default: 3
        ChanceRegularSafehouseLoot = 3,
        -- Min: 1 Max: 100 Default: 20
        MaxRegularSafehouseLoot = 20,
        -- Min: 0 Max: 10 Default: 4
        RollsRegularSafehouseLootLate = 4,
        -- Min: 1 Max: 10 Default: 3
        ChanceRegularSafehouseLootLate = 3,
        -- Min: 1 Max: 100 Default: 20
        MaxRegularSafehouseLootLate = 20,
        -- Min: 0 Max: 10 Default: 4
        RollsRegularSafehouseLootMid = 4,
        -- Min: 1 Max: 10 Default: 3
        ChanceRegularSafehouseLootMid = 3,
        -- Min: 1 Max: 100 Default: 20
        MaxRegularSafehouseLootMid = 20,
    },
    GunsOfTien = {
        RealisticPiercing = true,
        ModdedSlotsUpright = true,
        SubsonicRackRule = 2,
        BeltLinks = true,
        FirearmCritRule = 1,
        -- Min: 0 Max: 100 Default: 50
        FirearmCritLead = 50,
        -- Min: 0 Max: 100 Default: 0
        FirearmMinimumDamage = 0,
    },
    DAMN = {
        AllowPowerChadSpawns = true,
        AllowPro440Spawns = true,
        AllowDemonChildSpawns = false,
        AllowEV6spawns = true,
        AllowTBCspawns = true,
        AllowUBCspawns = true,
        AllowWreckyMcChevySpawns = true,
        AllowShitSpawns = true,
        AllowCloudSpawns = true,
        AllowManlyMANSpawns = true,
        AllowGreatScottSpawns = false,
        AllowOinkerSpawns = true,
        AllowMrBusSpawns = true,
        AllowChonkerSpawns = true,
        AllowCashcowSpawns = true,
        AllowMcBoxySpawns = true,
        AllowSuckyMcSuckfaceSpawns = true,
        AllowBushmasterSpawns = true,
        AllowContainerSpawns = true,
        AllowBabySpawns = true,
    },
    CF8KSweeper = {
        AllowTiles = true,
        SpriteWhitelist = "brokenglass_1_;trash_01_;d_trash_;street_decoration_01_26;street_decoration_01_27;damaged_objects_01_26;damaged_objects_01_27;damaged_objects_01_18;damaged_objects_01_19;damaged_objects_01_20;damaged_objects_01_21",
        AllowBlood = true,
        AllowGrime = true,
        AllowAshes = true,
        AllowItems = true,
        AllowCorpses = true,
        AllowUserAutoDelete = false,
    },
    JordanalSpawns = {
        -- Min: 0.00 Max: 100.00 Default: 0.04
        SWAT_UnitChance = 0.04,
        -- Min: 0.00 Max: 100.00 Default: 0.02
        SWAT_UnitChance_General = 0.02,
        -- Min: 0.00 Max: 100.00 Default: 0.04
        THORNUnitChance = 0.04,
    },
    B42PackMule = {
        Attachment1 = true,
        Attachment2 = true,
        Satchel1 = true,
        Satchel2 = false,
        Bracelet = true,
        Watch = true,
        Exclusion1 = true,
        Canteen = true,
        Ear = true,
        Shoulder = true,
        Back1 = false,
        Back2 = false,
        Pouch1 = false,
        Wallet1 = false,
        Exclusion2 = false,
        WalletFix = true,
        Pouch2 = false,
        Wallet2 = false,
        Vest1 = false,
        Vest2 = false,
        Vest3 = false,
        Vest4 = false,
        Webbing1 = false,
        Webbing2 = false,
        Webbing3 = false,
        Webbing4 = false,
        Webbing5 = false,
    },
    B42Survival = {
        LearnedRecipe = true,
        TorchSmoking = true,
    },
    BCGRareWeapons = {
        -- Min: 0 Max: 3650 Default: 0
        VikingAxeMinDays = 0,
        -- Min: 0 Max: 3650 Default: 0
        ReinforcedBaseballBatMinDays = 0,
        -- Min: 0 Max: 3650 Default: 0
        KatanaMinDays = 0,
    },
    BetterFireExtinguishers = {
        -- Min: 1 Max: 10 Default: 2
        SprayDurationMultiplier = 2,
    },
    CauseOfDeath = {
        Enabled = true,
        ShowCrashSpeed = true,
        ShowKillerName = true,
        ShowBleachCause = true,
        LogDeaths = true,
    },
    ChevalDeFrise = {
        -- Min: 1 Max: 99999 Default: 200
        WoodBaseHealth = 200,
        -- Min: 1 Max: 99999 Default: 1000
        MetalBaseHealth = 1000,
    },
    CocaColaICEFreezer = {
        -- Min: 0 Max: 100 Default: 100
        Chance = 100,
    },
    CyesPushDoors = {
        -- Min: 0.00 Max: 2.00 Default: 1.00
        ZombieDamageMultiplier = 1.0,
        -- Min: 0.25 Max: 2.00 Default: 1.00
        ZombiesAffectedMultiplier = 1.0,
        -- Min: 0.50 Max: 2.00 Default: 1.00
        DoorBlockCapacityMultiplier = 1.0,
        -- Min: 0 Max: 100 Default: 35
        ZombieKnockdownChance = 35,
        -- Min: 0.00 Max: 3.00 Default: 1.00
        DoorWearMultiplier = 1.0,
        -- Min: 0.00 Max: 3.00 Default: 1.00
        ForcedOpeningDoorWearMultiplier = 1.0,
        -- Min: 0.25 Max: 3.00 Default: 1.00
        GarageDoorWearMultiplier = 1.0,
        -- Min: 0.00 Max: 3.00 Default: 1.00
        GarageFailureChanceMultiplier = 1.0,
        -- Min: 0.00 Max: 3.00 Default: 1.00
        EnduranceCostMultiplier = 1.0,
        -- Min: 0.00 Max: 2.00 Default: 1.00
        ForcedOpeningFractureRiskMultiplier = 1.0,
        -- Min: 0.00 Max: 3.00 Default: 1.00
        ArmStrainGainMultiplier = 1.0,
        -- Min: 0.25 Max: 5.00 Default: 1.00
        ArmStrainUsageLimitMultiplier = 1.0,
        -- Min: 0.25 Max: 3.00 Default: 1.00
        GarageArmStrainMultiplier = 1.0,
        -- Min: 0.00 Max: 2.00 Default: 1.00
        ArmStrainPenaltyMultiplier = 1.0,
        -- Min: 0.25 Max: 3.00 Default: 1.00
        ArmStrainRecoveryMultiplier = 1.0,
        DamagePlayers = true,
        KnockDownPlayers = true,
        -- Min: 0 Max: 100 Default: 25
        PlayerKnockdownChance = 25,
        AffectCrawlers = true,
        AllowImpactsFromBothSides = false,
        HideIndividualOptions = false,
        GlobalImpactFeedback = true,
    },
    DGMC_Bolt_Cutters = {
        Allow_Garage_Doors = true,
        Allow_Fence_Gates = true,
        Allow_Fences = true,
        -- Min: 0 Max: 100 Default: 0
        Fence_Wire_Chance = 0,
        Allow_Shutters = true,
        -- Min: 0 Max: 10 Default: 3
        Easy_Strength_Req = 3,
        -- Min: 0 Max: 10 Default: 5
        Medium_Strength_Req = 5,
        -- Min: 0 Max: 10 Default: 7
        Hard_Strength_Req = 7,
        -- Min: 0 Max: 60 Default: 22
        Base_Duration = 22,
        -- Min: 0.00 Max: 40.00 Default: 4.00
        Base_Muscle_Strain = 4.0,
        Debug_Logging = false,
    },
    DGMC_Cleaning_Wipes = {
        Clean_Body = true,
        Clean_Clothing = true,
        Clean_Weapons = true,
        Remove_Makeup = true,
        -- Min: 0.00 Max: 10.00 Default: 1.00
        Speed_Mult = 1.0,
        -- Min: 0 Max: 100 Default: 25
        Wetness = 25,
        Debug_Logging = false,
    },
    BetterContainers = {
        ProximityEnabled = true,
        ForceCorpseOnly = false,
        AllowToggleProximity = true,
        AllowSwitchMode = true,
        AutoLockEnabled = true,
        AllowToggleAutoLock = true,
    },
    BetterItemInfo = {
        EnableSpoilageInfo = true,
        EnableNutritionInfo = true,
        EnableWeaponStats = true,
        FoodLevelRequirement = true,
        WeaponLevelRequirement = true,
        MaintenanceLevelRequirement = true,
    },
    Explosives = {
        VanillaBallisticsEnabled = false,
        -- Min: 0.01 Max: 5.00 Default: 1.00
        LootMultiplier = 1.0,
        FireDamageEnabled = true,
        -- Min: 0.50 Max: 5.00 Default: 1.00
        FireDamageMultiplier = 1.0,
        DelayedFuseEnabled = false,
        -- Min: 0.50 Max: 10.00 Default: 4.00
        DelayedFuseSeconds = 4.0,
        DebugSpawnKeyEnabled = false,
    },
    FancyHandwork = {
        -- Min: 0 Max: 11 Default: 3
        ExperiencedAim = 3,
        -- Min: 0.01 Max: 60.00 Default: 1.00
        TurnDelaySec = 1.0,
        DisableTurn = 2,
        TurnBehavior = 2,
        HideDoorProgressBar = false,
        HideVehicleWalkProgressBar = false,
        EnableLeftHandAiming = true,
    },
    FastHoodOpening = {
        -- Min: 0.10 Max: 30.00 Default: 0.70
        HoodTime = 0.7,
    },
    GasPumpIndicator = {
        ShowFuelAmount = true,
    },
    grin = {
        -- Min: 0 Max: 100 Default: 100
        grin_normal = 90,
        -- Min: 0 Max: 100 Default: 25
        grin_lift = 25,
    },
    H_E_C_U = {
        EmptyBox0 = false,
        ClothingCategoryDivider = false,
        ClothingSelection = true,
        -- Min: 0.01 Max: 100.00 Default: 1.00
        ClothingSpawnMult = 1.0,
        ClothingMoreSpawns = 1,
        ClothingMoreSpawnsCustom = "",
        EmptyBox0 = false,
        ZedsCategoryDivider = false,
        ZedsCustomSpawn = true,
        -- Min: 0.01 Max: 100.00 Default: 1.00
        ZedSpawnMult = 1.0,
        ZedsMoreSpawns = 1,
        ZedsMoreSpawnsCustom = "",
        ZedAttachedItems = true,
        ZedAttachedItemsRifleCustom = "",
        ZedAttachedItemsRifleVanilla = true,
        ZedAddedItems = true,
        ZedAddedSounds = true,
        EmptyBox0 = false,
        AttachmentsCategoryDivider = false,
        BackpackBackSlot = true,
        BeltSlots = true,
    },
    HIC = {
        MoodleActive = true,
        -- Min: 0 Max: 100 Default: 15
        MinimalCondition = 15,
        -- Min: 1 Max: 10 Default: 2
        Radius = 2,
        -- Min: 1 Max: 10 Default: 1
        SleepRadius = 1,
        CheckForTraits = true,
        -- Min: 0 Max: 100 Default: 60
        TraitCoefficient = 60,
        ZombieMemory = false,
    },
    ISIL = {
        ExtendedMode = false,
        EnableDurability = true,
        CaliberBasedWear = true,
        -- Min: 0 Max: 100 Default: 60
        ProfessionalNoiseReduction = 60,
        -- Min: 0 Max: 100 Default: 40
        MetalPipeNoiseReduction = 40,
        -- Min: 0 Max: 100 Default: 30
        HandTorchNoiseReduction = 30,
        -- Min: 0 Max: 100 Default: 20
        WaterBottleNoiseReduction = 20,
        -- Min: 1 Max: 10000 Default: 500
        ProfessionalDurability = 500,
        -- Min: 1 Max: 10000 Default: 100
        MetalPipeDurability = 100,
        -- Min: 1 Max: 10000 Default: 20
        HandTorchDurability = 20,
        -- Min: 1 Max: 10000 Default: 5
        WaterBottleDurability = 5,
    },
    JullesLiquidTankers = {
        -- Min: 0 Max: 1000 Default: 100
        SpawnPercent = 100,
        -- Min: 100 Max: 10000 Default: 2000
        TankCapacity = 2000,
        -- Min: 2 Max: 10 Default: 6
        HoseReach = 6,
        SpawnConstruction = true,
        Propane = true,
        -- Min: 20 Max: 20000 Default: 3000
        PropaneDepotCapacity = 3000,
        LiveryPlain = true,
        LiveryFossoil = true,
        LiveryOvo = true,
        LiveryUncloggers = true,
        LiveryMccoy = true,
        LiveryAirport = true,
        LiveryFire = true,
        LiveryRanger = true,
        LiveryArmy = true,
        LiveryKnoxdisti = true,
        LiveryScarletoak = true,
        LiveryMassgenfac = true,
        LiverySpiffo = true,
        LiveryCharlemange = true,
        LiveryGenuinebeer = true,
        LiveryCitr8 = true,
        LiveryKimble = true,
        LiveryMarchridge = true,
        LiveryKnobcreek = true,
        LiveryDirectflame = true,
    },
    KI5GF = {
        FixKat1Suspension = false,
    },
    KillCount = {
        doExport = false,
        includePostDeathUI = true,
        -- Min: 0 Max: 10000000 Default: 500
        MaxUpdateDelay = 1000,
        shareOnServer = true,
        keepTrackOfDead = true,
    },
    LanternsOnTheFloorFix = {
        -- Min: 0.00 Max: 1.00 Default: 0.50
        FlameR = 0.5,
        -- Min: 0.00 Max: 1.00 Default: 0.40
        FlameG = 0.4,
        -- Min: 0.00 Max: 1.00 Default: 0.33
        FlameB = 0.33,
        -- Min: 25 Max: 300 Default: 100
        FloorLightSize = 100,
    },
    DynamicBackpacks = {
        KnivesCanRemove = true,
        -- Min: 0 Max: 10 Default: 1
        BaseUpgradeSlots = 1,
        -- Min: -20 Max: 10 Default: 1
        BackSlotModifier = 1,
        -- Min: -20 Max: 10 Default: 0
        FannySlotModifier = 0,
        -- Min: -20 Max: 10 Default: 0
        OtherSlotModifier = 0,
        -- Min: 0 Max: 10 Default: 10
        TailoringModifier = 10,
        -- Min: 0.00 Max: 1.00 Default: 0.10
        ClothCapacityPercentage = 0.1,
        -- Min: -100 Max: 100 Default: 1
        ClothCapacityBonus = 1,
        -- Min: 0.01 Max: 1.00 Default: 0.15
        ClothReductionPercentage = 0.15,
        -- Min: 0.00 Max: 100.00 Default: 1.00
        ClothLootSpawns = 1.0,
        -- Min: 0.00 Max: 1.00 Default: 0.20
        JeanCapacityPercentage = 0.2,
        -- Min: -100 Max: 100 Default: 1
        JeanCapacityBonus = 1,
        -- Min: 0.01 Max: 1.00 Default: 0.25
        JeanReductionPercentage = 0.25,
        -- Min: 0.00 Max: 100.00 Default: 1.00
        JeanLootSpawns = 1.0,
        -- Min: 0.00 Max: 1.00 Default: 0.25
        LeatherCapacityPercentage = 0.25,
        -- Min: -100 Max: 100 Default: 2
        LeatherCapacityBonus = 2,
        -- Min: 0.01 Max: 1.00 Default: 0.35
        LeatherReductionPercentage = 0.35,
        -- Min: 0.00 Max: 100.00 Default: 1.00
        LeatherLootSpawns = 1.0,
        -- Min: 0.00 Max: 1.00 Default: 0.35
        MilitaryCapacityPercentage = 0.35,
        -- Min: -100 Max: 100 Default: 2
        MilitaryCapacityBonus = 2,
        -- Min: 0.01 Max: 1.00 Default: 0.50
        MilitaryReductionPercentage = 0.5,
        -- Min: 0.00 Max: 100.00 Default: 1.00
        MilitaryLootSpawns = 1.0,
    },
    LightSwitchBacklight = {
        WallSwitchesOnly = true,
    },
    M13ReadingTweaks = {
        RWW = true,
        RB = true,
        -- Min: 0.00 Max: 100.00 Default: 50.00
        RBD = 50.0,
        -- Min: 0.01 Max: 100.00 Default: 2.00
        PSM = 2.0,
    },
    MGRS = {
        style = 1,
    },
    MHP = {
        EnableReplaceBandage = true,
        ShowSafeRemoveIndicator = true,
        ShowStitchInspectIndicator = true,
    },
    MonsterBlackFridge = {
        -- Min: 1 Max: 11 Default: 5
        Distribution = 5,
    },
    MWPWeapons = {
        SpawnRate = 3,
        -- Min: 0.00 Max: 10.00 Default: 1.00
        CustomSpawnMultiplier = 1.0,
    },
    NeatCrafting = {
        CraftDirectFromAccessibleContainers = false,
    },
    NeatLockpicking = {
        EnableHotwire = true,
        EnableWindowLockpick = false,
        -- Min: 3 Max: 10 Default: 6
        PinCount = 6,
        -- Min: 0 Max: 100 Default: 50
        BreakChanceAtZeroSkill = 50,
        -- Min: 0 Max: 100 Default: 5
        BreakChanceMinimum = 5,
        NoiseOnFail = true,
        ResetPinsOnBreak = true,
        -- Min: 0.10 Max: 5.00 Default: 1.00
        BrokenLockpickDuration = 1.0,
        -- Min: 1 Max: 10 Default: 4
        RandomPinCountMin = 4,
        -- Min: 1 Max: 10 Default: 7
        RandomPinCountMax = 7,
        -- Min: 3 Max: 10 Default: 8
        ReinforcedDoorPinCount = 8,
        -- Min: 90 Max: 900 Default: 180
        NormalDoorArrowSpeed = 180,
        -- Min: 180 Max: 1800 Default: 360
        ReinforcedDoorArrowSpeed = 360,
        ReinforcedReverseArrowOnHit = true,
        -- Min: 1 Max: 100 Default: 10
        ReinforcedYellowHitValue = 10,
        -- Min: 1 Max: 100 Default: 20
        ReinforcedGreenHitValue = 20,
        CrowbarProgressDecayEnabled = true,
        -- Min: 0.50 Max: 10.00 Default: 2.00
        CrowbarProgressDecayInterval = 2.0,
        -- Min: 1 Max: 10 Default: 1
        CrowbarProgressDecayAmount = 1,
        -- Min: 0.10 Max: 3.00 Default: 0.50
        CrowbarExhaustionMultiplier = 0.5,
        PinResistanceEnabled = false,
    },
    VMZ = {
        RoadStories = true,
        -- Min: 0.00 Max: 5.00 Default: 1.00
        RoadStoriesMultiplier = 1.0,
        -- Min: 0 Max: 1000 Default: 5
        RoadStoriesMinDay = 5,
        -- Min: 0 Max: 1000 Default: 90
        RoadStoriesMaxDay = 90,
        SpecCar = false,
        -- Min: 0 Max: 100 Default: 16
        SpawnRate = 16,
        -- Min: 0 Max: 100 Default: 50
        VehiCond = 50,
        -- Min: 0 Max: 100 Default: 0
        PartDamage = 0,
        -- Min: 0 Max: 100 Default: 70
        KeySpawn = 70,
    },
    NestedHealthInfo = {
        -- Min: 0 Max: 10 Default: 3
        DoctorLevelForInfo = 2,
    },
    StartingInjuriesMod = {
        EnableBlackoutExplosions = true,
        EnableBandageAssistance = false,
        allscratchedup = true,
        housefire = true,
        bleedingout = true,
        squalor = true,
        headshot = true,
        skullfracture = true,
        brokenarm = true,
        brokenleg = true,
        blackout = true,
        crushedhands = true,
        mauled = true,
        carcrash = true,
        burnpatient = true,
        flamingwreckage = true,
        leftfordead = true,
    },
    Collections = {
        -- Min: 0.00 Max: 100.00 Default: 1.00
        RequiredBooks = 1.0,
        ComicsSection = false,
        AnthroComics = true,
        -- Min: 0.00 Max: 100.00 Default: 1.00
        AnthroComicSpawnRate = 1.0,
        Manga = true,
        -- Min: 0.00 Max: 100.00 Default: 1.00
        MangaSpawnRate = 1.0,
        ContemporaryComics = true,
        -- Min: 0.00 Max: 100.00 Default: 1.00
        ContemporaryComicsSpawnRate = 1.0,
        VintageComics = true,
        -- Min: 0.00 Max: 100.00 Default: 1.00
        VintageComicsSpawnRate = 1.0,
        ComicBox = true,
        -- Min: 0.00 Max: 100.00 Default: 1.00
        ComicBoxSpawnRate = 1.0,
        MedalsSection = false,
        Medals = true,
        -- Min: 0.00 Max: 100.00 Default: 1.00
        MedalsSpawnRate = 1.0,
        MedalsRare = true,
        -- Min: 0.00 Max: 100.00 Default: 1.00
        MedalsRareSpawnRate = 1.0,
        MedalsSilly = true,
        -- Min: 0.00 Max: 100.00 Default: 1.00
        MedalsSillySpawnRate = 1.0,
        CansSection = false,
        Cans = true,
        -- Min: 0.00 Max: 100.00 Default: 1.00
        CansSpawnRate = 1.0,
        HeadwearSection = false,
        Helm = true,
        -- Min: 0.00 Max: 100.00 Default: 1.00
        HelmSpawnRate = 1.0,
        Hat = true,
        -- Min: 0.00 Max: 100.00 Default: 1.00
        HatSpawnRate = 1.0,
        Starship = true,
        -- Min: 0.00 Max: 100.00 Default: 1.00
        StarshipSpawn = 1.0,
        UniformSection = false,
        UniformEnable = true,
        -- Min: 0.00 Max: 100.00 Default: 1.00
        UniformSpawnRate = 1.0,
    },
    PompsItems = {
        ZombieLoot = true,
        -- Min: 0.00 Max: 100.00 Default: 1.00
        ZombieLootSpawnRate = 1.0,
        StallionMilk = true,
        EasterStuff = true,
        -- Min: 0.00 Max: 100.00 Default: 1.00
        CandySpawnRate = 1.0,
        -- Min: 0.00 Max: 100.00 Default: 1.00
        SnacksSpawnRate = 1.0,
        -- Min: 0.00 Max: 100.00 Default: 1.00
        CannedGoodsSpawnRate = 1.0,
        -- Min: 0.00 Max: 100.00 Default: 1.00
        RefrigeratedGoodsSpawnRate = 1.0,
        -- Min: 0.00 Max: 100.00 Default: 1.00
        FrozenGoodsSpawnRate = 1.0,
        -- Min: 0.00 Max: 100.00 Default: 1.00
        MiscSpawnRate = 1.0,
        -- Min: 0.00 Max: 100.00 Default: 1.00
        DrinksSpawnRate = 1.0,
        -- Min: 0.00 Max: 100.00 Default: 1.00
        EnergyDrinkSpawnRate = 1.0,
        -- Min: 0.00 Max: 100.00 Default: 1.00
        LiquorSpawnRate = 1.0,
        -- Min: 0.00 Max: 100.00 Default: 1.00
        FNAFSpawnRate = 1.0,
        -- Min: 0.00 Max: 100.00 Default: 1.00
        FNAFZombieSpawnRate = 1.0,
    },
    ProjectCook = {
        AllowFrozenCooking = false,
    },
    PropaneExchangeCabinet = {
        Enabled = true,
        -- Min: 0 Max: 100 Default: 50
        SpawnChance = 30,
        -- Min: 0 Max: 6 Default: 6
        MaxTanks = 6,
        -- Min: 0 Max: 100 Default: 55
        FillWeightFull = 55,
        -- Min: 0 Max: 100 Default: 15
        FillWeightEmpty = 15,
        -- Min: 0 Max: 100 Default: 25
        MagazineChance = 25,
        MagazineOnePerSave = true,
        RemoveNewCabinets = false,
    },
    PushVehicle = {
        AllowSidePushing = true,
        -- Min: 0.00 Max: 10.00 Default: 1.00
        StaminaCostMultiplier = 1.0,
        -- Min: 0.00 Max: 10.00 Default: 1.00
        PushCooldownSeconds = 1.0,
        -- Min: 0 Max: 100000 Default: 0
        MaximumPushableWeight = 0,
    },
    RainCleansBlood = {
        -- Min: 10 Max: 2000 Default: 300
        TilesPerMinuteNearPlayer = 300,
        -- Min: 0.05 Max: 0.95 Default: 0.25
        WeatherThreshold = 0.25,
        AlsoCleanAsh = true,
        AlsoCleanDroppings = true,
        AlsoCleanInside = false,
        AlsoCleanVehicles = true,
        -- Min: 0.10 Max: 1.00 Default: 0.10
        VehicleCleanSpeed = 0.1,
        AlsoCleanClothes = true,
        -- Min: 1.00 Max: 10.00 Default: 1.00
        ClothesCleanSpeed = 1.0,
        AlwaysClean = false,
    },
    RealisticRecipes = {
        Enable_MakeBeefJerky = true,
        Enable_MakeVinegar = true,
        Enable_MakeFrenchFries = true,
        Enable_MakeJamFruit = true,
        Enable_MakeJamMarmalade = true,
        Enable_MakePasta = true,
        Enable_MakePancakeMix = true,
        Enable_MakeWoodenMallet = true,
        Enable_MakeFunnel = true,
        Enable_MakeRollingPin = true,
        Enable_MakeLongStickFromBranch = true,
        Enable_MakeLongStickFromLargeBranch = true,
        Enable_MakeLongHandleFromBranches = true,
        Enable_MakeTreeBranchFromTwigs = true,
        Enable_MakeCheese = true,
        Enable_MakeYeast = true,
        Enable_MakeVinegarBeer = true,
        Enable_MakeVinegarCider = true,
        Enable_MakeVinegarChampagne = true,
        Enable_MakeRopeFromTwine = true,
        Enable_MakeRopeFromRags = true,
        Enable_MakeTwineFromRags = true,
        Enable_MakeCheeseFromCannedMilk = true,
        Enable_MakeGravyRoux = true,
        Enable_MakeMarinara = true,
        Enable_MakeCandleTallow = true,
        Enable_MakeJamApple = true,
        Enable_MakeJamPear = true,
        Enable_MakeVinegarAged = true,
        Enable_MakeVinegarBoxed = true,
        Enable_MakeFlourFromWheat = true,
        Enable_MakeDough = true,
        Enable_MakeTortilla = true,
        Enable_MakeCornmeal = true,
        Enable_MakeCornbread = true,
        Enable_MakePopcorn = true,
        Enable_MakeJamGrape = true,
        Enable_MakeJamPineapple = true,
        Enable_MakeJamBanana = true,
        Enable_MakeMarmaladeLime = true,
        Enable_MakeKetchup = true,
        Enable_MakeSeasoningSalt = true,
        Enable_MakeCheeseFromPowderMilk = true,
        Enable_MakeRippedSheetsFromRoll = true,
        Enable_MakeDenimStripsFromRoll = true,
        Enable_MakeCheeseCloth = true,
        Enable_MakeSterilizeRippedSheets = true,
        Enable_MakeBroom = true,
        Enable_MakeMop = true,
        Enable_MakeCheeseGrater = true,
        Enable_MakeFishingHookWire = true,
        Enable_MakeKitchenTongs = true,
        Enable_MakeSheetRopeFromRags = true,
        Enable_MakeGaffhook = true,
        Enable_MakeGlueFromBones = true,
        Enable_MakeButter = true,
        Enable_MakeRiceVinegarSeasoned = true,
        Enable_MakeBrush = true,
        Enable_MakeFeedingBottle = true,
        Enable_MakeImprovedSpear = true,
        Enable_ForgeKatanaBlade = true,
        Enable_AssembleKatana = true,
        Enable_MakeMasterworkSpear = true,
        Enable_MakeKatanaHandle = true,
        Enable_MakeBaseballBat = true,
        Enable_MakeMetalBaseballBat = true,
        Enable_ForgeViseGrips = true,
        Enable_ForgeSheetMetalSnips = true,
        Enable_ForgePliers = true,
        Enable_ForgeCalipers = true,
        Enable_MakeWeldingMask = true,
        Enable_MakeLongSpear = true,
        Enable_AssembleSledgehammer = true,
        Enable_AssembleBallPeenHammer = true,
        Enable_AssembleSmithingHammer = true,
        Enable_AssembleClubHammer = true,
        Enable_AssembleHammer = true,
        Enable_MakePickles = true,
        Enable_MakeTofu = true,
        Enable_MakePeanutButter = true,
        Enable_MakeMayo = true,
        Enable_MakeSugarFromBeets = true,
        Enable_SqueezeOrangeJuice = true,
        Enable_MakeTortillaChips = true,
        Enable_MakePretzel = true,
        Enable_MakeCrackers = true,
        Enable_SaltCureHam = true,
        Enable_SaltCureBacon = true,
        Enable_DehydrateLegumes = true,
        Enable_MakeTomatoPaste = true,
        Enable_MakeAnimalFeed = true,
        Enable_ForgeScrews = true,
        Enable_ForgeWire = true,
        Enable_ForgeHeavyChain = true,
        Enable_ForgePadlock = true,
        Enable_ForgeGardenSaw = true,
        Enable_ForgeHacksawBlade = true,
        Enable_ForgeKettle = true,
        Enable_ForgeSutureNeedle = true,
        Enable_ForgeRakeHead = true,
        Enable_AssembleLeafRake = true,
        Enable_AssembleWoodAxe = true,
        Enable_AssembleMachete = true,
        Enable_CarveMortarPestle = true,
        Enable_ChopTwigsFromBranch = true,
        Enable_CarveBobber = true,
        Enable_CarveComb = true,
        Enable_MakeStrainer = true,
        Enable_ForgeShovel = true,
        Enable_MakeRagFilter = true,
        Enable_SewBathTowel = true,
        Enable_SewOvenMitt = true,
        Enable_SewBriefcase = true,
        Enable_SewSatchel = true,
        Enable_CarveKnittingNeedlesWood = true,
        Enable_SewBandana = true,
        Enable_WrapBurlapGloves = true,
        Enable_MakeTireFlipFlops = true,
        Enable_SewSlippers = true,
        Enable_AssembleFirstAidKit = true,
        Enable_AssembleSewingKit = true,
        Enable_MakeToolbox = true,
        Enable_MakePencil = true,
        Enable_MakeNotebook = true,
        Enable_ForgeMacheteBladeNoTang = true,
        Enable_ForgeFireAxeHead = true,
        Enable_AssembleFireAxe = true,
        Enable_AssembleHandAxe = true,
        Enable_AssemblePickAxe = true,
        Enable_MakeCrudeMachete = true,
        Enable_HatchetSawblade = true,
        Enable_ForgeBarbell = true,
        Enable_AssembleIronMace = true,
        Enable_AssembleLongMace = true,
        Enable_ForgeRailroadSpikePuller = true,
        Enable_ForgePipeWrench = true,
        Enable_ForgeBoltCutters = true,
        Enable_ForgeTireIron = true,
        Enable_ForgeNightstick = true,
        Enable_GrindSpikeKnife = true,
        Enable_ForgeGardenForkHead = true,
        Enable_AssembleGardenFork = true,
        Enable_AssembleSpadeForged = true,
        Enable_AssembleGardenHoeForged = true,
        Enable_AssembleRake = true,
        Enable_AssembleBallPeenHammerForged = true,
        Enable_AssembleClubHammerForged = true,
        Enable_AssembleHammerForged = true,
        Enable_AssembleWoodAxeForged = true,
        Enable_CarveGavel = true,
        Enable_ForgeMetalPipe = true,
        Enable_ForgeRailroadSpike = true,
        Enable_ForgeNutsBolts = true,
        Enable_ForgeCircularSawblade = true,
        Enable_ForgeSmallSawblade = true,
        Enable_MakeKeyBlank = true,
        Enable_ExtractAluminum = true,
        Enable_FillClaybag = true,
        Enable_MakeMayonnaise = true,
        Enable_MakeChocolate = true,
        Enable_MakeChocolateChips = true,
        Enable_MakeGravyMix = true,
        Enable_MakeTortillaChipsFromScratch = true,
        Enable_MakeSausage = true,
        Enable_MakeMincedMeat = true,
        Enable_MakeSourCream = true,
        Enable_MakeBouillonCube = true,
        Enable_MakeRockCandy = true,
        Enable_MakeSimpleSyrup = true,
        Enable_MakeIcecream = true,
        Enable_SewLeatherSatchel = true,
        Enable_SewHideSatchel = true,
        Enable_SewSchoolbag = true,
        Enable_SewDuffelBag = true,
        Enable_SewHikingBag = true,
        Enable_SewBigHikingBag = true,
    },
    ReBandaged = {
        AutoPick = true,
        AutoDisinfect = false,
        AutoSearch = true,
        AutoTranslate = false,
        OnlyDirty = false,
        SpecifyPick = false,
    },
    RoomOcclusionB42 = {
        -- Min: 0.00 Max: 1.00 Default: 0.30
        FadeSeconds = 0.3,
        -- Min: 0.00 Max: 1.00 Default: 1.00
        Blackness = 1.0,
        BridgeEnabled = true,
        -- Min: 5 Max: 40 Default: 20
        ScanRadius = 20,
    },
    SaucedCarts = {
        EnableMod = true,
        EnableCorpseStorage = false,
        ProtectFromWorldCleanup = false,
        -- Min: 0 Max: 500 Default: 100
        SpawnRate = 100,
        -- Min: 25 Max: 400 Default: 100
        CapacityMultiplier = 100,
        -- Min: 25 Max: 400 Default: 100
        DurabilityMultiplier = 100,
        -- Min: 1 Max: 5 Default: 1
        MaxCartsPerBuilding = 1,
        -- Min: 0 Max: 100 Default: 95
        WeightReduction = 95,
        -- Min: 0 Max: 500 Default: 100
        SpeedPenaltyMultiplier = 100,
        -- Min: 25 Max: 400 Default: 100
        RepairAmountMultiplier = 100,
        -- Min: 25 Max: 400 Default: 100
        RepairTimeMultiplier = 100,
        MaintenanceSkillBonus = true,
        EnableDebugLogs = false,
        StrictShopOnly = false,
        OutdoorSpawnDensity = 3,
        LoadedCartSpawns = 1,
    },
    ShelterHoldBeehive = {
        EnableZombees = true,
        EnableBeeStingPain = true,
        HideInvalidBaitHiveBaits = false,
        -- Min: -50.00 Max: 50.00 Default: 12.00
        HoneybeeMinTemperature = 12.0,
        -- Min: -50.00 Max: 60.00 Default: 32.00
        HoneybeeMaxTemperature = 32.0,
        -- Min: -50.00 Max: 50.00 Default: 5.00
        BumblebeeMinTemperature = 5.0,
        -- Min: -50.00 Max: 60.00 Default: 35.00
        BumblebeeMaxTemperature = 35.0,
        -- Min: 0.00 Max: 5.00 Default: 1.00
        HoneyProductionSpeedMultiplier = 1.0,
        -- Min: 0 Max: 10 Default: 2
        PlantGrowthBoostRadius = 2,
        -- Min: 0.00 Max: 5.00 Default: 1.00
        BeeForagingAbundanceMultiplier = 1.0,
    },
    ZCollision = {
        -- Min: 3 Max: 15 Default: 6
        MaxHitboxes = 6,
        -- Min: 3 Max: 15 Default: 6
        MaxDistanceFromPlayer = 6,
        -- Min: 0.01 Max: 0.99 Default: 0.46
        BaseRadius = 0.46,
        -- Min: 0.01 Max: 0.99 Default: 0.05
        BasePushForce = 0.05,
        -- Min: 0.01 Max: 0.99 Default: 0.65
        StunRadius = 0.65,
        -- Min: 0.01 Max: 0.99 Default: 0.19
        StunPushForce = 0.19,
        -- Min: 0.01 Max: 0.99 Default: 0.75
        FallingRadius = 0.75,
        -- Min: 0.01 Max: 0.99 Default: 0.24
        FallingPushForce = 0.24,
        DebugMode = false,
    },
    STA_PryOpen = {
        PryEnablePity = false,
        -- Min: 0.01 Max: 1.00 Default: 0.25
        PryChanceBase = 0.25,
        PryEnableSoftMin = false,
        -- Min: 0.00 Max: 1.00 Default: 0.50
        PryBonusSoftMin = 0.5,
        -- Min: 0.00 Max: 1.00 Default: 0.03
        PryBonusSkillStrength = 0.03,
        -- Min: 0.00 Max: 1.00 Default: 0.03
        PryBonusSkillCarpentry = 0.03,
        -- Min: 0.00 Max: 1.00 Default: 0.03
        PryBonusSkillBlacksmith = 0.03,
        -- Min: 0.00 Max: 1.00 Default: 0.03
        PryBonusSkillMechanics = 0.03,
        -- Min: 0.00 Max: 1.00 Default: 0.15
        PryBonusTraitBurglar = 0.15,
        -- Min: 0.00 Max: 5.00 Default: 0.20
        PryBonusSkillNimble = 0.2,
        -- Min: 0.00 Max: 5.00 Default: 1.00
        PryBonusTraitDextrous = 1.0,
        PryEnableBuilding = true,
        -- Min: 0 Max: 10 Default: 3
        PryLevelBuilding = 3,
        -- Min: 0.01 Max: 5.00 Default: 1.00
        PryChanceMultiplierBuilding = 1.0,
        -- Min: 1 Max: 30 Default: 8
        PryTimeBuilding = 8,
        PryEnableWindow = true,
        -- Min: 0 Max: 10 Default: 2
        PryLevelWindow = 2,
        -- Min: 0.01 Max: 5.00 Default: 1.10
        PryChanceMultiplierWindow = 1.1,
        -- Min: 1 Max: 30 Default: 6
        PryTimeWindow = 6,
        PryEnableGarage = true,
        -- Min: 0 Max: 10 Default: 6
        PryLevelGarage = 6,
        -- Min: 0.01 Max: 5.00 Default: 0.85
        PryChanceMultiplierGarage = 0.85,
        -- Min: 1 Max: 30 Default: 10
        PryTimeGarage = 10,
        PryEnableSecure = true,
        -- Min: 0 Max: 10 Default: 8
        PryLevelSecure = 8,
        -- Min: 0.01 Max: 5.00 Default: 0.80
        PryChanceMultiplierSecure = 0.8,
        -- Min: 1 Max: 30 Default: 14
        PryTimeSecure = 14,
        PryEnableVehicle = true,
        -- Min: 0 Max: 10 Default: 3
        PryLevelVehicle = 3,
        -- Min: 0.01 Max: 5.00 Default: 1.00
        PryChanceMultiplierVehicle = 1.0,
        -- Min: 1 Max: 30 Default: 10
        PryTimeVehicle = 10,
        PryEnableTrunk = true,
        -- Min: 0 Max: 10 Default: 2
        PryLevelTrunk = 2,
        -- Min: 0.01 Max: 5.00 Default: 1.05
        PryChanceMultiplierTrunk = 1.05,
        -- Min: 1 Max: 30 Default: 8
        PryTimeTrunk = 8,
        -- Min: 0.00 Max: 1.00 Default: 0.30
        PryChanceBreakWindow = 0.3,
        -- Min: 0.00 Max: 1.00 Default: 0.20
        PryChanceBreakVehicleWindow = 0.2,
        -- Min: 0.00 Max: 1.00 Default: 0.15
        PryChanceBreakVehicleLock = 0.15,
        -- Min: 0.00 Max: 1.00 Default: 0.08
        PryChanceInjury = 0.08,
        -- Min: 0.00 Max: 1.00 Default: 0.05
        PryBonusTraitSkin = 0.05,
        -- Min: 0.00 Max: 1.00 Default: 0.65
        PryChanceInjurySeverity01 = 0.65,
        -- Min: 0.00 Max: 1.00 Default: 0.30
        PryChanceInjurySeverity02 = 0.3,
        -- Min: 0.00 Max: 1.00 Default: 0.05
        PryChanceInjurySeverity03 = 0.05,
        -- Min: 5 Max: 100 Default: 15
        PryNoiseRadius = 15,
        -- Min: 0.00 Max: 10.00 Default: 0.50
        PryBonusSkillSneak = 0.5,
        PryEnableAlarmSuccess = false,
        PryEnableAlarmForce = false,
        -- Min: 0.00 Max: 1.00 Default: 0.12
        PryChanceAlarm = 0.12,
        -- Min: 0.00 Max: 1.00 Default: 0.01
        PryBonusSkillElectricity = 0.01,
        PryToolItemsList = "",
        PryToolTagsList = "base:crowbar:1.0;",
    },
    TacHold = {
        -- Min: 0 Max: 10 Default: 0
        AimingRequirement = 2,
        -- Min: 0 Max: 10 Default: 0
        PistolAimingRequirement = 2,
    },
    TienCoolers = {
        -- Min: 0.00 Max: 1.00 Default: 0.50
        CoolStrength = 0.5,
        -- Min: 1.00 Max: 1000.00 Default: 48.00
        IceLifeHours = 48.0,
        -- Min: 0.01 Max: 1.00 Default: 0.20
        IceLifeOutsideMult = 0.2,
        -- Min: 0.25 Max: 72.00 Default: 7.00
        FreezeHours = 7.0,
        -- Min: 0.10 Max: 10.00 Default: 5.00
        WaterPerBag = 5.0,
        ReworkedIce = false,
        UseColdpacks = true,
        -- Min: 0.00 Max: 1.00 Default: 0.40
        ColdpackPower = 0.4,
        SpawnIceInLoot = true,
        ShowColdTint = true,
        RenameCoolers = true,
    },
    LugliHW = {
        -- Min: 0 Max: 100 Default: 100
        Realism = 100,
        BulkFloor = 3,
        -- Min: 1.00 Max: 2.50 Default: 1.50
        Scale = 1.5,
        -- Min: 0 Max: 400 Default: 25
        MaxIncrease = 25,
        VanillaStamina = false,
    },
    UltimateMarksman = {
        -- Min: 0.00 Max: 1000.00 Default: 1.00
        LootSpawnMult = 1.0,
        -- Min: 0.00 Max: 1000.00 Default: 1.00
        CrudeCrossbowSpawnMult = 1.0,
        -- Min: 0.00 Max: 1000.00 Default: 1.00
        ImprovedCrossbowSpawnMult = 1.0,
        -- Min: 0.00 Max: 1000.00 Default: 1.00
        CompoundCrossbowSpawnMult = 1.0,
        -- Min: 0.00 Max: 1000.00 Default: 1.00
        HandCrossbowSpawnMult = 1.0,
        -- Min: 0 Max: 100 Default: 40
        BoltWBaseBreakChance = 40,
        -- Min: 0 Max: 100 Default: 3
        BoltWBreakChanceScaling = 3,
        -- Min: 0 Max: 100 Default: 50
        BoltSWBaseBreakChance = 50,
        -- Min: 0 Max: 100 Default: 3
        BoltSWBreakChanceScaling = 3,
        -- Min: 0.00 Max: 10.00 Default: 1.00
        BowDrawFatigueMult = 1.0,
        -- Min: 0.00 Max: 10.00 Default: 1.00
        BowHoldFatigueMult = 1.0,
        -- Min: 0.10 Max: 10.00 Default: 1.00
        CraftedBowDurabilityMult = 1.0,
        -- Min: 0 Max: 100 Default: 45
        ArrowRecoveryChance = 45,
    },
    UndeadSurvivor = {
        -- Min: 0.00 Max: 100.00 Default: 0.04
        StalkerChance = 0.04,
        -- Min: 0 Max: 3650 Default: 180
        StalkerMinDays = 180,
        -- Min: 0.00 Max: 100.00 Default: 0.04
        NomadChance = 0.04,
        -- Min: 0 Max: 3650 Default: 0
        NomadMinDays = 0,
        -- Min: 0.00 Max: 100.00 Default: 0.04
        PrepperChance = 0.04,
        -- Min: 0 Max: 3650 Default: 0
        PrepperMinDays = 0,
        -- Min: 0.00 Max: 100.00 Default: 0.04
        HeadhunterChance = 0.04,
        -- Min: 0 Max: 3650 Default: 90
        HeadhunterMinDays = 90,
        -- Min: 0.00 Max: 100.00 Default: 0.08
        AmazonaChance = 0.08,
        -- Min: 0 Max: 3650 Default: 180
        AmazonaMinDays = 180,
    },
    UnseasonalWeather = {
        Enabled = true,
        -- Min: 0 Max: 100 Default: 25
        DailyEventChance = 25,
        -- Min: 1 Max: 48 Default: 3
        MinDuration = 3,
        -- Min: 1 Max: 72 Default: 8
        MaxDuration = 8,
        -- Min: 0.20 Max: 3.00 Default: 1.00
        IntensityMultiplier = 1.0,
        HardcoreWinterTemps = false,
        HardcoreSummerTemps = false,
        ContinuousHardcoreTemps = false,
        DryEvents = false,
        EnhancedRainExposure = true,
        RoomWideIndoorHeat = false,
        PauseWhileDriving = true,
        LightningAttractsZombiesGlobal = false,
        ClockUIEnabled = true,
    },
    UW_RadioForecasting = {
        Enabled = true,
        UseNightWindow = false,
        WalkieHints = true,
        DebugLogging = false,
    },
    UsefulBarrels = {
        DebugMode = false,
        -- Min: 1 Max: 9999 Default: 400
        BarrelCapacity = 400,
        RequirePipeWrench = true,
        RequireHoseForTake = true,
        RequireFunnelForFill = false,
        -- Min: 1.00 Max: 2.00 Default: 1.25
        FunnelSpeedUpFillModifier = 1.25,
        AllowIndustrial = true,
        AllowFuel = true,
        AllowHazardous = true,
        AllowWater = true,
        AllowAlcoholic = false,
        AllowBeverage = false,
        AllowMedical = false,
        AllowColors = false,
        AllowDyes = false,
        AllowHairDyes = false,
        AllowPaint = false,
        AllowPoisons = false,
        EnableGeneratorRefuel = true,
        GeneratorRefuelRequiresHose = true,
        EnableCarRefuel = true,
        CarRefuelRequiresHose = true,
        EnableFillBarrelFromVehicles = true,
        FillBarrelFromVehiclesRequiresHose = true,
        InitialFluid = true,
        InitialFluidPool = "Acid Water TaintedWater Petrol Petrol Bleach PotentPoison",
        -- Min: 0 Max: 9999 Default: 54
        InitialFluidMaxAmount = 54,
        -- Min: 0.00 Max: 100.00 Default: 25.00
        InitialFluidSpawnChance = 25.0,
        RequireWeldingMask = true,
        RequireBlowTorch = true,
    },
    VFluidKI5 = {
        -- Min: 0 Max: 1000 Default: 100
        SweeperWaterPerHour = 100,
        EnableM49A2C = true,
        EnableM50A3 = true,
        EnableM967Trailer = true,
        EnableIsoTanker = true,
        EnablePierceArrow = true,
        EnablePierceQuint = true,
        EnableP19AUSMC = true,
        EnableP19AKYFD = true,
        EnableP19AFRTR55 = true,
        EnableElgin = true,
        EnableElginSpec = true,
        EnableDorothy = true,
        EnableWreckerC30CC = true,
        EnableWreckerK30CC = true,
        EnableWreckerC30SC = true,
        EnableWreckerK30SC = true,
        EnableType2VanApoc = true,
        EnableManKat1 = true,
    },
    WashSmart = {
        AllowTaintedWater = true,
        -- Min: 0.50 Max: 10.00 Default: 4.00
        BandageWaterPerItem = 4.0,
    },
    WaterPurificationPlus = {
        -- Min: 0 Max: 1440 Default: 30
        BleachPurifyMinutes = 30,
    },
    workingSeatbelt = {
        -- Min: 0 Max: 100 Default: 50
        seatbeltDamageReduction = 50,
        -- Min: 0 Max: 100 Default: 50
        seatbeltFractureReduction = 50,
        seatbeltCausesChestFracture = true,
        -- Min: 0 Max: 100 Default: 50
        chanceChestFracture = 50,
        -- Min: 0 Max: 100 Default: 60
        chestFractureMinimumCrashStrength = 60,
        -- Min: 0 Max: 100 Default: 3
        chestFractureTime = 3,
        exitVehicleAutoUnfasten = true,
        switchSeatAutoUnfasten = true,
        seatbeltWarningIndicator = true,
        seatbeltWarningChime = true,
        playersToggleChime = true,
        -- Min: 0 Max: 100 Default: 15
        chimeMinimumSpeed = 15,
        airbagModule = true,
        loreFriendlyAirbags = false,
        -- Min: 0 Max: 100 Default: 50
        airbagMinimumCrashStrength = 50,
        -- Min: 0 Max: 100 Default: 50
        airbagDamageReduction = 50,
        -- Min: 0 Max: 100 Default: 50
        airbagFractureReduction = 50,
        airbagsAffectedByCondition = true,
        airbagDeploymentAlert = true,
        canPlayerBeEjected = false,
        -- Min: 0 Max: 100 Default: 65
        ejectMinimumCrashStrength = 65,
        -- Min: 0 Max: 100 Default: 85
        ejectDamage = 85,
    },
    ZeroToChad = {
        EnablePanicCap = true,
        -- Min: 1 Max: 100000 Default: 100
        KillsPerStep = 100,
        -- Min: 0 Max: 100 Default: 8
        CapPerStep = 8,
        EnableBrave = true,
        -- Min: 1 Max: 100000 Default: 500
        BraveKills = 500,
        EnableDesensitized = true,
        -- Min: 1 Max: 100000 Default: 1000
        DesensitizedKills = 1000,
        CureClumsy = true,
        ShowNotifications = true,
        FixVanillaKills = true,
    },
    MorePlushies = {
        Loot = 3,
        CommonPlushies = true,
        -- Min: 1 Max: 100 Default: 50
        CommonPlushiesRates = 50,
        UncommonPlushies = true,
        -- Min: 1 Max: 100 Default: 40
        UncommonPlushiesRates = 40,
        RarePlushies = true,
        -- Min: 1 Max: 100 Default: 30
        RarePlushiesRates = 30,
        VeryRarePlushies = true,
        -- Min: 1 Max: 100 Default: 15
        VeryRarePlushiesRates = 15,
        LocationsToy = true,
        LocationsGeneral = true,
        LocationsIncidental = true,
    },
    HugThePlushie = {
        -- Min: -100.00 Max: 100.00 Default: -2.22
        UnhappinessPerMinute = -2.22,
        -- Min: 0.00 Max: 100.00 Default: 0.00
        UnhappinessLimit = 0.0,
        -- Min: -100.00 Max: 100.00 Default: -5.00
        StressPerMinute = -5.0,
        -- Min: 0.00 Max: 100.00 Default: 0.00
        StressLimit = 0.0,
        -- Min: 0.00 Max: 1.00 Default: 0.20
        MoodDecreaseModifier = 0.2,
        PassiveEffect = true,
        -- Min: -100.00 Max: 100.00 Default: -0.10
        PassiveUnhappinessPerMinute = -0.1,
        -- Min: 0.00 Max: 100.00 Default: 40.00
        PassiveUnhappinessLimit = 40.0,
        -- Min: -100.00 Max: 100.00 Default: -0.13
        PassiveStressPerMinute = -0.125,
        -- Min: 0.00 Max: 100.00 Default: 40.00
        PassiveStressLimit = 40.0,
        -- Min: 0.00 Max: 1.00 Default: 0.85
        PassiveMoodDecreaseModifier = 0.85,
    },
    CurlUp = {
        -- Min: -100.00 Max: 100.00 Default: -1.66
        UnhappinessPerMinute = -1.66,
        -- Min: 0.00 Max: 100.00 Default: 30.00
        UnhappinessLimit = 30.0,
        -- Min: -100.00 Max: 100.00 Default: -3.33
        StressPerMinute = -3.33,
        -- Min: 0.00 Max: 100.00 Default: 0.00
        StressLimit = 0.0,
        -- Min: 24.90 Max: 41.10 Default: 36.50
        TemperatureThreshold = 36.5,
        -- Min: 1.00 Max: 10.30 Default: 3.00
        WarmUpRate = 3.0,
        ForceVignette = false,
        -- Min: 0.00 Max: 1.00 Default: 0.99
        ForcedVignetteAlpha = 0.99,
        -- Min: 0 Max: 60000 Default: 2000
        ForcedVignetteFadeInTime = 2000,
        -- Min: 0 Max: 60000 Default: 500
        ForcedVignetteFadeOutTime = 500,
    },
    TrueSleep = {
        -- Min: 1.00 Max: 60.00 Default: 14.00
        SleepSpeed = 14.0,
        -- Min: 0 Max: 90 Default: 15
        NapFloorPercent = 15,
        CompensateVanilla = true,
        -- Min: 0.00 Max: 10.00 Default: 1.00
        EnduranceMult = 1.0,
        WakeWhenRested = true,
        ShowHud = true,
        -- Min: 0.10 Max: 2.00 Default: 0.60
        FloorMult = 0.6,
        -- Min: 0.10 Max: 2.00 Default: 0.90
        BadBedMult = 0.9,
        -- Min: 0.10 Max: 2.00 Default: 1.00
        AverageBedMult = 1.0,
        -- Min: 0.10 Max: 2.00 Default: 1.10
        GoodBedMult = 1.1,
        -- Min: 0.00 Max: 0.50 Default: 0.05
        PillowBonus = 0.05,
    },
    BadlandsPower = {
        -- Min: 0 Max: 90 Default: 33
        WorldShare = 33,
    },
    SmartRadialMenu = {
        EnableRipAllClothing = false,
        EnableWringOutAllClothes = false,
        EnableReloadUnloadAllMagazines = false,
        EnableStopAllRingingAlarms = false,
    },
    WoundExpansion = {
        enabled = true,
        preset = 2,
        -- Min: 0.00 Max: 30.00 Default: 12.00
        skinFreeze = 12.0,
        -- Min: 500 Max: 8000 Default: 2200
        infectionBase = 2200,
        -- Min: 0.00 Max: 10.00 Default: 1.00
        lootAmount = 1.0,
        minigames = true,
        minigameJoint = true,
        minigameDebris = true,
        minigameSuture = true,
        minigameSurgery = true,
        minigameBone = true,
        -- Min: 0 Max: 10 Default: 6
        internalBleedFirstAid = 6,
        skinMarks = true,
        tocTourniquet = true,
        allowAbrasion = true,
        allowPuncture = true,
        allowAvulsion = true,
        allowFrostbite = true,
        allowSprain = true,
        allowDislocation = true,
        allowConcussion = true,
        allowJointDamage = true,
        allowNerveDamage = true,
        allowSwollen = true,
        allowInflamed = true,
        allowReopened = true,
        allowNecrotic = true,
        allowPoorlyStitched = true,
        allowOverBandaged = true,
        allowBruised = true,
        allowNumb = true,
        allowEmbeddedDebris = true,
        allowTornBandage = true,
        allowDirty = true,
        allowInternalBleeding = true,
        allowMaggots = true,
        allowSepticFever = false,
        allowScar = true,
    },
    ZomVisFix = {
        AffectZombieVision = true,
        HardMode = false,
    },
    LugliEL = {
        -- Min: 0.25 Max: 72.00 Default: 4.00
        GlowStickHours = 4.0,
        -- Min: 0.25 Max: 72.00 Default: 8.00
        ChemLightHours = 8.0,
        -- Min: 0.25 Max: 72.00 Default: 0.50
        RoadFlareHours = 0.5,
        -- Min: 1 Max: 40 Default: 5
        GlowStickRadius = 5,
        -- Min: 1 Max: 40 Default: 10
        ChemLightRadius = 10,
        -- Min: 1 Max: 40 Default: 15
        RoadFlareRadius = 15,
        -- Min: 0.10 Max: 1.50 Default: 1.00
        LightIntensity = 1.0,
        -- Min: 0.00 Max: 1.00 Default: 0.45
        LightSaturation = 0.45,
        LightFlicker = true,
        LightIncidence = true,
        -- Min: 0.25 Max: 2.00 Default: 1.00
        ThrowRangeMult = 1.0,
        -- Min: 0 Max: 60 Default: 3
        CrackNoise = 3,
        -- Min: 0 Max: 60 Default: 5
        ThrowNoise = 5,
        -- Min: 0 Max: 120 Default: 12
        FlareNoise = 12,
        -- Min: 0 Max: 200 Default: 30
        FlareGunNoise = 30,
        -- Min: 0 Max: 200 Default: 20
        AerialNoise = 20,
        -- Min: 10 Max: 60 Default: 30
        AerialShotRange = 30,
        -- Min: 30 Max: 3600 Default: 300
        AerialSeconds = 300,
        -- Min: 4 Max: 20 Default: 20
        AerialLightRadius = 20,
        -- Min: 10 Max: 400 Default: 150
        AerialRange = 150,
        FlareFire = true,
        CarriedFlareSound = true,
        MapMarker = true,
        MapRangeCircle = false,
        -- Min: 0.00 Max: 4.00 Default: 1.00
        LootMultiplier = 1.0,
        -- Min: 4 Max: 32 Default: 10
        SweepRadius = 10,
        -- Min: 0.25 Max: 5.00 Default: 1.00
        SweepSeconds = 1.0,
        DebugLog = false,
        DebugRanges = false,
    },
    ZombiesHearYourMicrophone = {
        respectEnableVOIP = true,
        -- Min: 1.50 Max: 100.00 Default: 1.50
        multiplier = 1.5,
        -- Min: 0.00 Max: 1.00 Default: 0.66
        sneakReduce = 0.66,
        skillsInfluence = 1,
        traitsInfluence = 1,
    },
    LugliModpackFixes = {
        BiiTooltip = true,
        BpHotbar = true,
        BpNeat = true,
        CleanUIBlink = true,
        DbuCeiling = true,
        DbuRestore = true,
        ExBandolier = true,
        FhKeys = true,
        GydeHandy = true,
        HotbarEquip = true,
        ImpSpawn = true,
        NgmClaims = true,
        NgmInfo = true,
        NgmManage = true,
        NgmNeat = true,
        NgmSlice = true,
        P4Place = true,
        ReloadStrap = true,
        SeatView = true,
        SgKills = true,
        SgTank = true,
        SlingStop = true,
        SrvProf = true,
        TileProps = true,
        UsDrops = true,
        UsItems = true,
        UsmilSeats = true,
        VehicleLoot = true,
        VmzLegacy = true,
    },
}
