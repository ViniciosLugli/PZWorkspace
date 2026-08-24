-- Tells the asset gate that the front end is up.
--
-- Every retired texture queues a GL upload onto the render thread's invoke queue, and anything
-- that needs a synchronous answer from that thread -- Keyboard.initKeyNames when the options
-- screen opens, Core.setDisplayMode when it is applied -- waits behind the whole backlog. While
-- the menu is up the gate therefore caps how far the render thread may fall behind.
--
-- It must NOT cap during boot or a world load, where a deep queue costs nothing and parking a
-- decode worker would only slow the load. OnFETick fires at the front end and nowhere else, so a
-- heartbeat clears itself the instant a world starts loading. OnGameStart is far too late: it
-- fires after the load this must not affect.

local function beat()
    if type(FastLoading_MenuBeat) == "function" then
        FastLoading_MenuBeat()
    end
end

Events.OnFETick.Add(beat)
