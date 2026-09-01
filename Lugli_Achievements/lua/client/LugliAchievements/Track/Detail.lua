require "LugliAchievements/Registry"

local M = LugliAchievements
local PART = "Detail tracking"

-- These all ride actions another tracker already wraps, which is safe: Core installs one
-- wrapper per class and every callback runs behind it.

-- Reached through DAMAGE_STAT, so the gate cannot see these as literals.
local DECLARED_STATS = {
    "damage_fall",
    "damage_poison",
    "infected",
}

local DAMAGE_STAT = {
    POISON = "damage_poison", FALLDOWN = "damage_fall",
    INFECTION = "infected",
}

-- Bait is a fish the way a worm is: it comes up on the same action and goes back on the hook.
local BAIT_FISH = "Base.BaitFish"

-- A declared field on the item, so a modded bug that declares it counts too. Not a complete
-- census of what crawls: Base.Ladybug and Base.Leech are edible and carry no FoodType, so
-- neither is counted. That is the honest reading of the data rather than a hardcoded list.
local FOOD_TYPE_INSECT = "Insect"

-- Barricades declare their own build category, so they are matched on that rather than on a
-- word in the name.
local BUILD_CAT_BARRICADE = "Barricades"

-- Wallpaper and paint have a category of their own and names containing "wall". Without this a
-- survivor who redecorated one room would out-build one who put up a compound.
local BUILD_CAT_COVERING = "Wall Coverings"

local function roomIdOf(character)
    local okSq, square = pcall(function() return character:getCurrentSquare() end)
    if not okSq or square == nil then return nil end
    local okD, def = pcall(function() return square:getRoomDef() end)
    if not okD or def == nil then return nil end
    local okI, id = pcall(function() return def:getIDString() end)
    return (okI and type(id) == "string") and id or nil
end

local burnedAt = {}

local function onDamage(character, damageType)
    -- Fires for zombies too, so the player guard is not optional.
    if M.playerIndex(character) == nil or type(damageType) ~= "string" then return end
    M.addUnique(character, "damage_types", damageType)
    local stat = DAMAGE_STAT[damageType]
    if stat ~= nil then M.incStat(character, stat, 1) end
    if damageType == "FIRE" then
        burnedAt[character] = true
    end
end

--- Surviving the fire, rather than merely catching one. Checked an hour later, because being on
--- fire and living through it are different achievements.
local function onEveryHours()
    for character in pairs(burnedAt) do
        if character ~= nil then
            local ok, alive = pcall(function() return character:isAlive() end)
            if ok and alive then M.setStat(character, "survived_fire", 1) end
        end
    end
    burnedAt = {}
end

local function onFish(self)
    if self == nil or self.character == nil then return end
    if self.isFish == false then return end        -- the net also brings up rubbish
    M.incStat(self.character, "fish_caught", 1)
    if self.item ~= nil then
        local ok, full = pcall(function() return self.item:getFullType() end)
        if ok and type(full) == "string" and full ~= BAIT_FISH then
            M.addUnique(self.character, "fish_species", full)
        end
    end
end

--- A cigarette is a Food carrying the smokable tag, and the pack is a drainable that hands one
--- over, so the TAG names it rather than the type. The trait test is
--- hasTrait(CharacterTrait.SMOKER); HasTrait("Smoker") is a B41 idiom absent on this build.
local function countSmoke(character, item)
    if ItemTag == nil or ItemTag.SMOKABLE == nil then return end
    if CharacterTrait == nil or CharacterTrait.SMOKER == nil then return end
    local okTag, smokable = pcall(function() return item:hasTag(ItemTag.SMOKABLE) end)
    if not okTag or smokable ~= true then return end
    local okTrait, smoker = pcall(function()
        return character:hasTrait(CharacterTrait.SMOKER)
    end)
    -- A build that cannot answer the trait question must not credit every smoker in the game.
    if not okTrait or smoker ~= false then return end
    M.incStat(character, "smokes_nonsmoker", 1)
end

local function onEat(self)
    if self == nil or self.character == nil or self.item == nil then return end
    countSmoke(self.character, self.item)
    if instanceof ~= nil and not instanceof(self.item, "Food") then return end
    local ok, ft = pcall(function() return self.item:getFoodType() end)
    if ok and type(ft) == "string" and ft ~= "" then
        M.addUnique(self.character, "food_types", ft)
        if ft == FOOD_TYPE_INSECT then M.incStat(self.character, "insects_eaten", 1) end
    end
end

--- The plant on a harvest action is a Lua table over the object's mod data, not a Java object,
--- so it answers fields and not method calls. "none" is the empty-plot marker.
local function onHarvest(self)
    if self == nil or self.character == nil then return end
    local plant = self.plant
    if type(plant) ~= "table" then return end
    local seed = plant.typeOfSeed
    if type(seed) == "string" and seed ~= "" and seed ~= "none" then
        M.addUnique(self.character, "crop_types", seed)
    end
end

local function onTrap(self)
    if self == nil or self.character == nil or self.weapon == nil then return end
    local ok, full = pcall(function() return self.weapon:getFullType() end)
    if ok and type(full) == "string" then
        M.addUnique(self.character, "trap_types", full)
    end
end

local function onCraft(self)
    if self == nil or self.character == nil or self.craftRecipe == nil then return end
    local ok, cat = pcall(function() return self.craftRecipe:getCategory() end)
    if ok and type(cat) == "string" and string.lower(cat) == "cooking" then
        M.incStat(self.character, "meals_cooked", 1)
    end
end

--- Barricades and walls are both ISBuildAction in B42; the old ISBarricadeAction is dead. What
--- separates them is the recipe category and the entity id, neither of which is translated.
local function onBuild(self)
    if self == nil or self.character == nil then return end
    local player = self.character

    local id = roomIdOf(player)
    if id ~= nil then M.addUnique(player, "rooms_built_in", id) end
    if self.item == nil then return end

    local category = nil
    if self.item.craftRecipe then
        local okC, c = pcall(function() return self.item.craftRecipe:getCategory() end)
        if okC and type(c) == "string" then category = c end
    end
    if category == BUILD_CAT_BARRICADE then
        M.incStat(player, "barricades_built", 1)
        return
    end
    if category == BUILD_CAT_COVERING then return end

    local name = self.item.name
    if type(name) ~= "string" then return end
    name = string.lower(name)
    -- A wall frame is the skeleton a wall is later built onto, so it is not the wall.
    if string.find(name, "wall", 1, true) and not string.find(name, "frame", 1, true) then
        M.incStat(player, "walls_built", 1)
    end
end

--- ISButcherAnimal stores its subject as `body`, an IsoDeadBody, where the other three store
--- `animal`. Reading only `animal` meant butchering contributed nothing, and since butchering is
--- the only way to interact with a deer that capped the species set at nine against a target of
--- ten, taking meta_homestead and meta_all down with it.
local function onAnimal(self)
    if self == nil or self.character == nil then return end
    local species = M.animalSpecies(self.animal or self.body)
    if species ~= nil then
        M.addUnique(self.character, "animal_species", species)
    end
end

local function onSafehouse()
    M.forEachLocalPlayer(function(player) M.setStat(player, "safehouse_claimed", 1) end)
end

M.addHandler(PART, "OnPlayerGetDamage", onDamage)
M.addHandler(PART, "EveryHours", onEveryHours)
M.addHandler(PART, "OnSafehousesChanged", onSafehouse)

local h = M.addHandler(PART, "OnGameStart", function()
    M.onAction(PART, "ISPickupFishAction", onFish)
    M.onAction(PART, "ISEatFoodAction", onEat)
    M.onAction(PART, "ISHarvestPlantAction", onHarvest)
    M.onAction(PART, "ISPlaceTrap", onTrap)
    M.onAction(PART, "ISHandcraftAction", onCraft)
    M.onAction(PART, "ISBuildAction", onBuild)
    for _, cls in ipairs({ "ISPickupAnimal", "ISPetAnimal", "ISButcherAnimal", "ISMilkAnimal" }) do
        M.onAction(PART, cls, onAnimal)
    end
    M.status(PART, true)
end)

if h ~= nil then M.status(PART, nil, "checked when you load a world", "pending") end
