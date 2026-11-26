--[[
A magazine in the off hand on every Guns of Marz and Guns of Tien magazine reload, held where the
gun takes it.

Gunworks shows the magazine in the off hand only where the reload node fires its attachToHand /
detachFromHand events, and moves the gun's own magazine part only on InsertMag. Several Guns of Marz
reload profiles fire none of the three (handgun2, MP5, left_handle_load, boltaction), so the Marz and
Tien guns on them reload with no magazine in either hand and the gun never shows empty.

Profiles. This part moves those guns, one Gunworks handler at a time, to reload profiles of its own
(AnimSets/*/actions/LugliGM*): nodes keyed on a new WeaponReloadType that play Guns of Marz clips
whose off hand does reach the magazine well, with the event timings of the Guns of Marz node that
plays the same clip, and the rack the gun had. Two guns go to an existing Guns of Marz profile
instead (RETARGETS), and the MAC10, which Guns of Marz leaves without a handler, gets one. A handler
changes only while it is still on the profile it is expected on, and only its animId and the
durations of the clips that changed; its rules, part states and sounds are kept.

Hand pose. The engine draws the prop at the hand bone times the magazine model's own Bip01_Prop2
attachment, and the gun's magazine at the gun bone times the gun model's "magazine" attachment (no
gun model here has a Bip01_Prop1 attachment, and no magazine model a "magazine" one). On one clip
the hand-to-gun transform is the same for every gun, so a pose authored for one gun (the family
reference: Guns of Marz's own magazine on its own gun) carries over to another as
    pose = refPose * refMount^-1 * gunMount,
which puts the magazine into that gun's well at InsertMag. One magazine model serves several guns
with different mounts, so the pose cannot live on the model: each (gun, magazine model) that needs
one gets a copy of the model script with that Bip01_Prop2, made at boot on every machine, and
ReloadProp names it on the prop item (InventoryItem.setStaticModel, which travels in the item's
mod data to other players). A pose is derived for a gun this part moves, for a magazine model with
no Bip01_Prop2, and for one whose Bip01_Prop2 is the family reference's copied onto another gun;
a pose the author tuned for the gun is kept.
]]
require "GreaseOfMarz_Status"
local M = LugliGreaseOfMarz

local HAND = "Bip01_Prop2"
local MOUNT = "magazine"
local CLONE_PREFIX = "LugliGMHand_"

-- Reload profile -> pose family: the Guns of Marz clip its load node plays.
local FAMILY_OF = {
    pistol_reload = "handgun", lugli_gm_grip = "handgun",
    hk_rifle = "mp5", lugli_gm_fore = "mp5", lugli_gm_mp5 = "mp5",
    ar15_rifle = "rifle", lugli_gm_left = "rifle", lugli_gm_bolt = "rifle",
    famas_rifle = "famas",
}

-- Per family, the reference magazine's Bip01_Prop2 and its gun's magazine mount (Guns of Marz:
-- GLOCK17 magazine on the pistol clip, no mount; MP5 magazine on the MP5; STANAG on the AR15 and on
-- the FAMAS).
local IDENTITY = { o = { 0, 0, 0 }, r = { 0, 0, 0 } }
local FAMILIES = {
    handgun = { pose = { o = { -0.0107, 0.0022, -0.0624 }, r = { 7.4929, -4.9199, -40.7737 } }, mount = IDENTITY },
    mp5 = { pose = { o = { 0.0327, 0.0736, -0.0009 }, r = { -76.6133, 33.9253, -94.5129 } },
        mount = { o = { 0, 0.0934, 0.0264 }, r = { 10.2946, 0, 0 } } },
    rifle = { pose = { o = { 0.0200, 0.0538, -0.0146 }, r = { -94.96, 23.43, -89.82 } },
        mount = { o = { 0, 0.1015, 0.0144 }, r = { 0, 0, 0 } } },
    famas = { pose = { o = { 0.0200, 0.0538, -0.0146 }, r = { -94.96, 23.43, -89.82 } },
        mount = { o = { 0, -0.0763, 0.0146 }, r = { 0, 0, 0 } } },
}

-- New profile -> the profile its guns must be on, the lengths of the clips its load and unload
-- nodes play, and the guns.
local MOVES = {
    lugli_gm_grip = { from = "handgun2", load = 1.466667, unload = 1.466667, guns = {
        "GunsOfTien.UZI", "GunsOfTien.MINIUZI", "GunsOfTien.MICROUZI", "GunsOfTien.TMP",
        "GunsOfTienPost93.MP7A1", "GunsOfTienPost93.MP7A2" } },
    lugli_gm_fore = { from = "handgun2", load = 1.28, unload = 1.28, guns = {
        "MarzGuns.MP5K", "MarzGuns.TEC9", "GunsOfTienPost93.VECTOR9", "GunsOfTienPost93.VECTORSDP",
        "GunsOfTien.SKORPION", "GunsOfTienPost93.KEDR" } },
    lugli_gm_mp5 = { from = "MP5", load = 1.28, unload = 1.28, guns = {
        "GunsOfTienPost93.UMP45", "GunsOfTienPost93.UMP9", "GunsOfTienPost93.VECTOR45",
        "GunsOfTienPost93.VECTORCRB" } },
    lugli_gm_left = { from = "left_handle_load", load = 2.5, unload = 2.5, guns = {
        "GunsOfTienPost93.SCARL", "GunsOfTienPost93.SCARH", "MarzGuns.AA12" } },
    lugli_gm_bolt = { from = "boltaction", load = 2.5, unload = 2.5, guns = {
        "GunsOfTienPost93.SV98", "GunsOfTienPost93.SV99" } },
}

-- Guns moved onto an existing Guns of Marz profile, with the durations of a gun already on it.
local RETARGETS = {
    { gun = "GunsOfTienPost93.GROZA2", from = "handgun2", to = "famas_rifle", like = "MarzGuns.FAMAS" },
    { gun = "GunsOfTienPost93.HK416QR22", from = "handgun2", to = "ar15_rifle", like = "MarzGuns.AR15" },
}
local DURATION_KEYS = { "loadDuration", "loadAimDuration", "loadShortDuration", "unloadDuration",
    "unloadAimDuration", "rackDuration", "rackAimDuration", "vehicleDurations", "rackOpenDuration",
    "rackOpenAimDuration", "rackCloseDuration", "rackCloseAimDuration", "loadChamberDuration",
    "loadChamberAimDuration", "clipDuration", "clipAimDuration" }

-- Guns Guns of Marz leaves without a reload handler.
local REGISTERS = {
    { gun = "MarzGuns.MAC10", profile = { animId = "lugli_gm_grip", style = "none",
        durations = { load = 1.466667, unload = 1.466667, rack = 0.999844 } } },
}

M.magHandProfiles = { moves = MOVES, retargets = RETARGETS, registers = REGISTERS, families = FAMILIES }

-- Pose math: a pose is { o = offset, r = rotate in degrees }, the transform T(o) * Rx * Ry * Rz
-- (ModelInstanceRenderData.makeAttachmentTransform: translate, then rotateXYZ).
local RAD, DEG = math.pi / 180, 180 / math.pi

local function matrix(r)
    local a, b, c = r[1] * RAD, r[2] * RAD, r[3] * RAD
    local ca, sa, cb, sb, cc, sc = math.cos(a), math.sin(a), math.cos(b), math.sin(b), math.cos(c), math.sin(c)
    return {
        { cb * cc, -cb * sc, sb },
        { sa * sb * cc + ca * sc, -sa * sb * sc + ca * cc, -sa * cb },
        { -ca * sb * cc + sa * sc, ca * sb * sc + sa * cc, ca * cb },
    }
end

local function angles(R)
    local b = math.asin(math.max(-1, math.min(1, R[1][3])))
    return { math.atan2(-R[2][3], R[3][3]) * DEG, b * DEG, math.atan2(-R[1][2], R[1][1]) * DEG }
end

local function apply(R, v)
    return {
        R[1][1] * v[1] + R[1][2] * v[2] + R[1][3] * v[3],
        R[2][1] * v[1] + R[2][2] * v[2] + R[2][3] * v[3],
        R[3][1] * v[1] + R[3][2] * v[2] + R[3][3] * v[3],
    }
end

local function compose(p, q)
    local P, Q = matrix(p.r), matrix(q.r)
    local R = {}
    for i = 1, 3 do
        R[i] = {}
        for j = 1, 3 do R[i][j] = P[i][1] * Q[1][j] + P[i][2] * Q[2][j] + P[i][3] * Q[3][j] end
    end
    local t = apply(P, q.o)
    return { o = { p.o[1] + t[1], p.o[2] + t[2], p.o[3] + t[3] }, r = angles(R) }
end

local function inverse(p)
    local R = matrix(p.r)
    local T = { { R[1][1], R[2][1], R[3][1] }, { R[1][2], R[2][2], R[3][2] }, { R[1][3], R[2][3], R[3][3] } }
    local t = apply(T, p.o)
    return { o = { -t[1], -t[2], -t[3] }, r = angles(T) }
end

-- Same transform within 0.1 mm and 0.01 degree of each matrix entry: Euler angles have several
-- spellings of one rotation, so rotations compare as matrices.
local function samePose(p, q)
    for i = 1, 3 do
        if math.abs(p.o[i] - q.o[i]) > 1e-4 then return false end
    end
    local P, Q = matrix(p.r), matrix(q.r)
    for i = 1, 3 do
        for j = 1, 3 do
            if math.abs(P[i][j] - Q[i][j]) > 2e-4 then return false end
        end
    end
    return true
end

local function derive(family, mount)
    return compose(compose(family.pose, inverse(family.mount)), mount or IDENTITY)
end

M.magHandMath = { compose = compose, inverse = inverse, samePose = samePose, derive = derive }

local function reloadAnim()
    local found, ReloadAnim = pcall(require, "WeaponSystems/Utils/ReloadAnim")
    if found and type(ReloadAnim) == "table" then return ReloadAnim end
    return nil
end

local function magazineApi()
    local found, Magazine = pcall(require, "WeaponSystems/Utils/Magazine")
    if found and type(Magazine) == "table" then return Magazine end
    return nil
end

local function check()
    local ReloadAnim = reloadAnim()
    if ReloadAnim == nil or type(ReloadAnim.handlers) ~= "table" or type(ReloadAnim.reindex) ~= "function" then
        return "Gunworks ReloadAnim.handlers or reindex not found"
    end
    if type(ReloadAnim.RegisterWeapon) ~= "function" or type(ReloadAnim.byFullType) ~= "table" then
        return "Gunworks ReloadAnim.RegisterWeapon or byFullType not found"
    end
    local Magazine = magazineApi()
    if Magazine == nil or type(Magazine.GetMagazineTypesForGun) ~= "function" then
        return "Gunworks Magazine.GetMagazineTypesForGun not found"
    end
    if ModelScript == nil or type(ModelScript.new) ~= "function" then return "ModelScript not exposed" end
    return nil
end

local function handlersOf(ReloadAnim, fullType)
    local found = {}
    for i = 1, #ReloadAnim.handlers do
        local handler = ReloadAnim.handlers[i]
        if type(handler) == "table" and handler.fullType == fullType then found[#found + 1] = handler end
    end
    return found
end

-- The one simple Gunworks handler of a gun, while it is on the profile expected; else why not.
local function movableHandler(ReloadAnim, fullType, from, to)
    if getScriptManager():getItem(fullType) == nil then return nil, nil end
    local handlers = handlersOf(ReloadAnim, fullType)
    if #handlers == 0 then return nil, fullType .. " (no Gunworks handler)" end
    if #handlers > 1 then return nil, fullType .. " (" .. #handlers .. " handlers)" end
    local handler = handlers[1]
    if handler.animId == to then return nil, nil end
    if handler.animId ~= from then return nil, fullType .. " (on " .. tostring(handler.animId) .. ")" end
    if handler.style ~= "none" then return nil, fullType .. " (style " .. tostring(handler.style) .. ")" end
    return handler, nil
end

local function moveHandlers(ReloadAnim, stats)
    local targets = {}
    for animId, move in pairs(MOVES) do
        for _, fullType in ipairs(move.guns) do
            local handler, why = movableHandler(ReloadAnim, fullType, move.from, animId)
            if handler then
                handler.animId = animId
                handler.loadDuration, handler.loadAimDuration, handler.loadShortDuration = move.load, nil, nil
                handler.unloadDuration, handler.unloadAimDuration = move.unload, nil
                stats.moved[#stats.moved + 1] = fullType
            elseif why then
                stats.kept[#stats.kept + 1] = why
            end
            targets[fullType] = animId
        end
    end
    for _, retarget in ipairs(RETARGETS) do
        local handler, why = movableHandler(ReloadAnim, retarget.gun, retarget.from, retarget.to)
        local like = handler and handlersOf(ReloadAnim, retarget.like)[1]
        if handler and like and like.animId == retarget.to then
            handler.animId = retarget.to
            for _, key in ipairs(DURATION_KEYS) do handler[key] = like[key] end
            stats.moved[#stats.moved + 1] = retarget.gun
        elseif handler then
            why = retarget.gun .. " (" .. retarget.like .. " not on " .. retarget.to .. ")"
        end
        if why then stats.kept[#stats.kept + 1] = why end
        targets[retarget.gun] = retarget.to
    end
    for _, register in ipairs(REGISTERS) do
        if getScriptManager():getItem(register.gun) ~= nil then
            if #handlersOf(ReloadAnim, register.gun) == 0 then
                ReloadAnim.RegisterWeapon(register.gun, register.profile)
                if ReloadAnim.byFullType[register.gun] then
                    stats.registered[#stats.registered + 1] = register.gun
                else
                    stats.kept[#stats.kept + 1] = register.gun .. " (Gunworks refused the profile)"
                end
            end
            targets[register.gun] = register.profile.animId
        end
    end
    ReloadAnim.reindex()
    -- The guns now on the profile this part chose for them, moved by this boot or already there.
    local changed = {}
    for fullType, animId in pairs(targets) do
        local handlers = handlersOf(ReloadAnim, fullType)
        if #handlers == 1 and handlers[1].animId == animId then changed[fullType] = true end
    end
    return changed
end

local function poseOf(attachment)
    if attachment == nil then return nil end
    local o, r = attachment:getOffset(), attachment:getRotate()
    return { o = { o:x(), o:y(), o:z() }, r = { r:x(), r:y(), r:z() } }
end

local function cloneName(gunType, model)
    return CLONE_PREFIX .. string.gsub(gunType .. "_" .. model, "[^%w]", "_")
end

-- A copy of model script ms under name, every loaded body as it is (ModelScript.LoadAttachment
-- updates an attachment by id, so later bodies override earlier ones as at boot), then the pose.
local function cloneModel(ms, name, pose)
    local bodies = ms:getLoadedScriptBodies()
    if bodies == nil or bodies:size() == 0 then return nil end
    local texts = {}
    for i = 0, bodies:size() - 1 do
        local body = bodies:get(i)
        local open = type(body) == "string" and string.find(body, "{", 1, true) or nil
        if open then texts[#texts + 1] = "model " .. name .. "\n" .. string.sub(body, open) end
    end
    if #texts == 0 then return nil end
    texts[#texts + 1] = string.format("model %s\n{\n    attachment %s\n    {\n        offset = %.6f %.6f %.6f,\n"
        .. "        rotate = %.6f %.6f %.6f,\n    }\n}\n", name, HAND,
        pose.o[1], pose.o[2], pose.o[3], pose.r[1], pose.r[2], pose.r[3])
    local copy = ModelScript.new()
    copy:setModule(ms:getModule())
    copy:InitLoadPP(name)
    for _, text in ipairs(texts) do copy:Load(name, text) end
    getScriptManager():addModelScript(copy)
    return ms:getModule():getName() .. "." .. name
end

-- Model names of the items a gun's reload can put in the hand: its Gunworks magazine profile, its own
-- MagazineType, and the hand items its profile allows instead (partState.props: Guns of Tien's scaled
-- <magazine>_Hand items). The gun is made from its script (Item.InstanceItem), without the Lua OnCreate
-- a world item gets.
local function magazineModels(Magazine, script, handler)
    local gun = script:InstanceItem(nil)
    local models, types = {}, {}
    if gun == nil or not instanceof(gun, "HandWeapon") then return models end
    for _, magType in pairs(Magazine.GetMagazineTypesForGun(gun) or {}) do types[#types + 1] = magType end
    if gun:getMagazineType() then types[#types + 1] = gun:getMagazineType() end
    local props = type(handler.partState) == "table" and handler.partState.props or nil
    for _, propType in ipairs(type(props) == "table" and props or {}) do types[#types + 1] = propType end
    local sm = getScriptManager()
    for _, magType in ipairs(types) do
        local magScript = type(magType) == "string" and sm:getItem(magType) or nil
        local model = magScript and magScript:getStaticModel() or nil
        if model ~= nil and model ~= "" then models[model] = true end
    end
    return models
end

-- Per gun on a known family, the magazine models whose pose this part derives -> the copy to draw.
local function buildPoses(ReloadAnim, Magazine, stats, changed)
    local sm = getScriptManager()
    local clones = {}
    for i = 1, #ReloadAnim.handlers do
        local handler = ReloadAnim.handlers[i]
        local gunType = type(handler) == "table" and handler.fullType or nil
        local family = gunType and FAMILIES[FAMILY_OF[handler.animId] or ""] or nil
        local script = family and sm:getItem(gunType) or nil
        local sprite = script and script:getWeaponSprite() or nil
        local gunModel = sprite and sm:getModelScript(sprite) or nil
        if gunModel and not clones[gunType] then
            local target = derive(family, poseOf(gunModel:getAttachmentById(MOUNT)))
            for model in pairs(magazineModels(Magazine, script, handler)) do
                local ms = sm:getModelScript(model)
                local current = ms and poseOf(ms:getAttachmentById(HAND)) or nil
                local wanted = ms ~= nil and (changed[gunType] or current == nil or samePose(current, family.pose))
                if wanted and (current == nil or not samePose(current, target)) then
                    local made, name = pcall(cloneModel, ms, cloneName(gunType, model), target)
                    if not made or name == nil then
                        stats.kept[#stats.kept + 1] = gunType .. ":" .. model .. " (no copy: " .. tostring(name) .. ")"
                    else
                        clones[gunType] = clones[gunType] or {}
                        clones[gunType][model] = name
                        stats.posed[#stats.posed + 1] = gunType .. ":" .. model
                    end
                end
            end
        end
    end
    return clones
end

local function install(ctx)
    local ReloadAnim, Magazine = reloadAnim(), magazineApi()
    local stats = { moved = {}, registered = {}, kept = {}, posed = {} }
    M.magHand = stats
    local changed = moveHandlers(ReloadAnim, stats)
    local clones = buildPoses(ReloadAnim, Magazine, stats, changed)
    stats.clones = clones

    -- The model a reload prop of this gun is drawn with, or nil for the item's own.
    M.magHandModel = function(gun, item)
        if gun == nil or item == nil or not instanceof(gun, "HandWeapon") then return nil end
        local byModel = clones[gun:getFullType()]
        return byModel and byModel[item:getStaticModel()] or nil
    end

    M.log("MagHand: " .. #stats.moved .. " handler(s) moved, " .. #stats.registered .. " registered, "
        .. #stats.posed .. " hand pose(s)"
        .. (#stats.kept > 0 and ("; kept: " .. table.concat(stats.kept, ", ")) or ""))
end

M.addPart("MagHand", { "SWMG", "GunsOfMarz" }, install, { check = check })
