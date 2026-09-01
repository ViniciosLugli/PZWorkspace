-- Each row watches whether one of the other eleven categories is finished, and the last watches
-- whether all of them are. The Meta tracker excludes this category from what it measures, or the
-- capstone would be counted among the achievements it asks you to complete.
require "LugliAchievements/Categories"

local M = LugliAchievements

local DEFS = {
    {
        id = "meta_waking_up",
        name = "UI_LugliAch_meta_waking_up_name",
        description = "UI_LugliAch_meta_waking_up_desc",
        category = "milestones",
        stat = "cat_done_waking_up",
        target = 1,
        tier = "gold",
    },
    {
        id = "meta_body_count",
        name = "UI_LugliAch_meta_body_count_name",
        description = "UI_LugliAch_meta_body_count_desc",
        category = "milestones",
        stat = "cat_done_body_count",
        target = 1,
        tier = "gold",
    },
    {
        id = "meta_still_breathing",
        name = "UI_LugliAch_meta_still_breathing_name",
        description = "UI_LugliAch_meta_still_breathing_desc",
        category = "milestones",
        stat = "cat_done_still_breathing",
        target = 1,
        tier = "gold",
    },
    {
        id = "meta_autodidact",
        name = "UI_LugliAch_meta_autodidact_name",
        description = "UI_LugliAch_meta_autodidact_desc",
        category = "milestones",
        stat = "cat_done_autodidact",
        target = 1,
        tier = "gold",
    },
    {
        id = "meta_nailed_it",
        name = "UI_LugliAch_meta_nailed_it_name",
        description = "UI_LugliAch_meta_nailed_it_desc",
        category = "milestones",
        stat = "cat_done_nailed_it",
        target = 1,
        tier = "gold",
    },
    {
        id = "meta_homestead",
        name = "UI_LugliAch_meta_homestead_name",
        description = "UI_LugliAch_meta_homestead_desc",
        category = "milestones",
        stat = "cat_done_homestead",
        target = 1,
        tier = "gold",
    },
    {
        id = "meta_field_medicine",
        name = "UI_LugliAch_meta_field_medicine_name",
        description = "UI_LugliAch_meta_field_medicine_desc",
        category = "milestones",
        stat = "cat_done_field_medicine",
        target = 1,
        tier = "gold",
    },
    {
        id = "meta_roadside",
        name = "UI_LugliAch_meta_roadside_name",
        description = "UI_LugliAch_meta_roadside_desc",
        category = "milestones",
        stat = "cat_done_roadside",
        target = 1,
        tier = "gold",
    },
    {
        id = "meta_house_proud",
        name = "UI_LugliAch_meta_house_proud_name",
        description = "UI_LugliAch_meta_house_proud_desc",
        category = "milestones",
        stat = "cat_done_house_proud",
        target = 1,
        tier = "gold",
    },
    {
        id = "meta_how_you_died",
        name = "UI_LugliAch_meta_how_you_died_name",
        description = "UI_LugliAch_meta_how_you_died_desc",
        category = "milestones",
        stat = "cat_done_how_you_died",
        target = 1,
        tier = "gold",
    },
    {
        id = "meta_secrets",
        name = "UI_LugliAch_meta_secrets_name",
        description = "UI_LugliAch_meta_secrets_desc",
        category = "milestones",
        stat = "cat_done_secrets",
        target = 1,
        tier = "gold",
    },
    {
        id = "meta_all",
        name = "UI_LugliAch_meta_all_name",
        description = "UI_LugliAch_meta_all_desc",
        category = "milestones",
        stat = "cats_done",
        target = 11,
        tier = "gold",
    },
}

for i = 1, #DEFS do
    M.register(DEFS[i])
end

M.status("Milestones definitions", true)
