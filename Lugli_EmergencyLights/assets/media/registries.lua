--[[
    EmergencyLights registries
    GENERATED FILE. Edit the generator that writes it, never this.

    NOT a normal Lua file and NOT under media/lua/. ModRegistries.init() runs
    <mod>/media/registries.lua immediately before ScriptManager.Load()
    (GameWindow.java:201-203), which is the only moment an AmmoType can be created
    before the item scripts that name it are parsed.

    AmmoType.register(id, itemKey) stores exactly ONE item key per type
    (AmmoType.java:54-56), and a script naming an unregistered id gets null with no
    error: the gun simply never loads. The id must carry a namespace, because
    register() passes allowDefaultNamespace = false.

    THE LAST-MOD-WINS TRAP DOES NOT APPLY TO THIS FILE, which is worth knowing
    because the boot log says otherwise. Six installed mods ship a
    media/registries.lua and each one logs 'overrides media/registries.lua', since
    they do collide in ZomboidFileSystem's lowercased file map. But
    ModRegistries.init() never consults that map: it walks getModIDs() and builds
    each path directly as new File(mod.getVersionDir() + "/media/registries.lua").
    So every mod's file runs, ours included, and the override lines are noise.
]]

LugliEmergencyLights_FlareCartridge = AmmoType.register("lugli:flare_cartridge", "LugliEmergencyLights.FlareCartridge")
