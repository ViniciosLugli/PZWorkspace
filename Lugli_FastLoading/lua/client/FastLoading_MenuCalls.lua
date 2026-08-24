-- Stops the options screen making redundant blocking round-trips to the render thread.
--
-- Opening the options screen parked the main thread in RenderContextQueueItem.waitUntilFinished
-- for seconds. Every decoded texture queues a GL upload onto that same FIFO and the render thread
-- drains it on a 10 ms budget per loop, so the queue runs thousands deep while assets stream and
-- a blocking caller waits behind all of it.
--
-- WHY LUA AND NOT A @Patch: the Java version targeted org.lwjglx.input.Keyboard.initKeyNames and
-- ZombieBuddy never retransformed it -- 89 classes were patched that boot and this was not one,
-- and the advice's own unconditional log line never appeared. Both callers are Lua, so overriding
-- them there always works and needs no patch slot.
--
-- NEITHER OVERRIDE CHANGES AN OUTCOME.
--   onKeyboardLayoutChanged rebuilds a key-name table from glfwGetKeyName. MainOptions calls it on
--   EVERY open purely in case the player switched QWERTY/AZERTY between screens; re-running it
--   seconds later cannot produce a different answer.
--
-- NOT DONE HERE: apply() also calls setResolutionAndFullScreen unconditionally, and the engine
-- early-outs on the far side after paying for the trip. Skipping that from Lua looked easy and is
-- not: the function reads the TARGET resolution from its combo box, so a guard comparing against
-- the CURRENT display state would swallow a real resolution change. A slow apply is a far smaller
-- fault than a settings screen that silently ignores you.

local KEY_LAYOUT_TTL_MS = 10000

local lastLayoutAt = 0

-- The table is ALREADY BUILT before the menu exists: org.lwjglx.input.Keyboard.create() calls
-- initKeyNames() at boot. So the options screen's call is redundant every time, including the
-- first, which is the slowest of all because it lands while the asset backlog is still
-- draining. Skipping it is safe only if the table really is populated, so that is checked
-- rather than assumed: a key with a known name must come back non-empty.
local function keyNamesReady()
    if type(getKeyName) ~= "function" then return false end
    local ok, name = pcall(getKeyName, Keyboard and Keyboard.KEY_A or 30)
    return ok and type(name) == "string" and name ~= ""
end

local function installed(t, key)
    if t["__fastloading_" .. key] then return true end
    t["__fastloading_" .. key] = true
    return false
end

local function install()
    if type(MainOptions) ~= "table" then return end

    if type(MainOptions.onKeyboardLayoutChanged) == "function"
            and not installed(MainOptions, "keylayout") then
        local orig = MainOptions.onKeyboardLayoutChanged
        MainOptions.onKeyboardLayoutChanged = function(self)
            local now = getTimestampMs()
            if lastLayoutAt == 0 and keyNamesReady() then
                lastLayoutAt = now         -- boot already built it; nothing to redo
                return
            end
            if lastLayoutAt ~= 0 and now - lastLayoutAt < KEY_LAYOUT_TTL_MS then
                return
            end
            lastLayoutAt = now
            return orig(self)
        end
    end

end

Events.OnGameBoot.Add(install)
Events.OnMainMenuEnter.Add(install)
