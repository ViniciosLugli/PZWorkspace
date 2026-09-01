require "LugliAchievements/Registry"

local M = LugliAchievements

-- Order here is sidebar order. `milestones` measures the other eleven and is excluded from what
-- it measures, so the capstone is not counted among the achievements it requires.
local CATEGORIES = {
    { id = "waking_up",        name = "UI_LugliAch_cat_waking_up" },
    { id = "body_count",       name = "UI_LugliAch_cat_body_count" },
    { id = "still_breathing",  name = "UI_LugliAch_cat_still_breathing" },
    { id = "autodidact",       name = "UI_LugliAch_cat_autodidact" },
    { id = "nailed_it",        name = "UI_LugliAch_cat_nailed_it" },
    { id = "homestead",        name = "UI_LugliAch_cat_homestead" },
    { id = "field_medicine",   name = "UI_LugliAch_cat_field_medicine" },
    { id = "roadside",         name = "UI_LugliAch_cat_roadside" },
    { id = "house_proud",      name = "UI_LugliAch_cat_house_proud" },
    { id = "how_you_died",     name = "UI_LugliAch_cat_how_you_died" },
    { id = "secrets",          name = "UI_LugliAch_cat_secrets" },
    { id = "milestones",       name = "UI_LugliAch_cat_milestones" },
}

for i = 1, #CATEGORIES do
    M.registerCategory(CATEGORIES[i])
end

M.status("Categories", true)
