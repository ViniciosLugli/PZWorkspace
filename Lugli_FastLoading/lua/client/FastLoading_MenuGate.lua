-- Tells the Java side that the front end is up (lugli.fastloading.AssetThrottle.atMenu).
--
-- Every menu-scoped rule keys off this heartbeat: DemandPriority promoting the texture the player
-- just asked for, and the menu budget and upload cap, both off by default. It is also the
-- backstop that retires the loading screen if the MainScreenState.enter patch never ran.
--
-- None of them may act during boot or a world load, where a deep queue costs nothing and
-- reordering or parking work would only slow the load. OnFETick fires at the front end and
-- nowhere else, so the heartbeat goes stale the instant a world starts loading. OnGameStart is
-- far too late: it fires after the load this must not affect.

local function beat()
    if type(FastLoading_MenuBeat) == "function" then
        FastLoading_MenuBeat()
    end
end

Events.OnFETick.Add(beat)
