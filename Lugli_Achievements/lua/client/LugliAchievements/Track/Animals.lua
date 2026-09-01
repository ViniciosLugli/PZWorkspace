require "LugliAchievements/Registry"

local M = LugliAchievements

M.countActions("Animal husbandry", {
    { "ISPetAnimal", "animals_petted" },
    { "ISFeedAnimalFromHand", "animals_fed" },
    { "ISMilkAnimal", "animals_milked" },
    { "ISShearAnimal", "animals_sheared" },
    { "ISHutchGrabEgg", "eggs_collected" },
    { "ISButcherAnimal", "animals_butchered" },
    { "ISRemoveLeatherFromAnimal", "leather_taken" },
    { "ISGetAnimalBones", "bones_taken" },
    { "ISPutAnimalInHutch", "animals_hutched" },
    { "ISLureAnimal", "animals_lured" },
    { "ISAddAnimalInTrailer", "animals_trailered" },
    { "ISInspectAnimalTrackAction", "tracks_read" },
    { "ISPutAnimalOnHook", "animals_hooked" },
})
