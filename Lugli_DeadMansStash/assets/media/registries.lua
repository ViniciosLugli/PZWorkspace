--[[
    DeadMansStash registries

    NOT a normal Lua file and NOT under media/lua/. ModRegistries.init() runs
    <mod>/<versionDir>/media/registries.lua, else <mod>/common/media/registries.lua, before
    ScriptManager.Load() (ModRegistries.java:14-18, 42.22.2), which is the only moment a trait can
    be registered before the character_trait_definition that names it is parsed. A definition
    naming an unregistered id gets null with no error.

    The id must carry a namespace: register() passes allowDefaultNamespace = false. Gates.lua
    resolves the same id through CharacterTrait.get(ResourceLocation.of(id)).
]]

CharacterTrait.register("lugli_dms:dms_locksmith")
