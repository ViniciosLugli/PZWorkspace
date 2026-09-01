require "LugliAchievements/Registry"

local M = LugliAchievements
local PART = "Backfill"

-- One handler rather than one per tracker: several handlers on the same event have no ordering
-- guarantee between them, and the backfill has to run after everything is registered.
local h = M.addHandler(PART, "OnCreatePlayer", function(playerIndex, player)
    if player == nil then return end
    -- Silently: the backfill is the mod catching up with what the player had already done, not
    -- them earning something. Announcing it is a wall of toasts, 48 of them on a mature save,
    -- at the moment the world appears.
    local wasQuiet = M.toastQuiet
    M.toastQuiet = true
    local ok, fired = pcall(M.recheckAll, player)
    M.toastQuiet = wasQuiet
    if ok and fired > 0 then
        M.log("boot", "backfilled " .. fired .. " achievement(s) this character had already met")
    end
end)

if h ~= nil then M.status(PART, true) end
