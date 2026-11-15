--[[
Nick's Generator Manager with Neat Rocco's UI: the Manage Power window in Neat Rocco's style.

What happens today. Nick's Manage Power window is a vanilla window (title bar, list box, text
buttons) that opens beside Neat Rocco's generator window, which Neat Rocco has restyled with every
other world-object window. It also rescans every square in range of the generator every 500 ms
while it is open: about 7.6 ms per scan on 42.22.2 (the same walk the ngm-slice part measured),
a hitch twice a second for as long as the window stays open.

What this part changes. Manage Power opens as a Neat Rocco panel: its header (title, icon,
collapse, minimum size, close), its scrolling list and rows, its icon buttons with its tooltips,
and its resize handle. Everything the window does stays Nick's: the rows, the light group, a click
claims or returns through Nick's own requests, the footer claims or returns every row, and the
server's echo refreshes the window through Nick's own list of open windows. Owners and draws are
re-read every 500 ms as before; the square walk runs on open and then every 5 s, and between walks
the rows that left (picked up, switched off, now on grid power) drop out at once. An appliance
switched on in range shows up within 5 s instead of 0.5 s.
]]
require "ModpackFixes_Status"
require "ModpackFixes/NgmNeat"
require "ModpackFixes/NgmClaims"
local M = LugliModpackFixes

local REFRESH_MS = 500
local SCAN_MS = 5000

local function tr(key, fallback)
    local ok, s = pcall(getTextOrNull, key)
    if ok and type(s) == "string" and s ~= "" then return s end
    return fallback
end

local NGM_NEEDS = { "read", "poweredObjectsInRange", "isBillable", "classify", "consumption", "objSpec",
                    "resolveOwner", "requestClaim", "requestReturn", "isActive", "fuelMult", "genKey",
                    "registerGeneratorAt", "requestRegister", "T", "geom", "getOwnerPref" }

local function needUi()
    local need = {
        { "NR_BasePanel", NR_BasePanel }, { "NR_Config", NR_Config }, { "NR_UIScale", NR_UIScale },
        { "NR_SelectableList", NR_SelectableList }, { "NR_ResizeWidget", NR_ResizeWidget },
        { "NR_CollapseUtils", NR_CollapseUtils }, { "NR_DrawUtils", NR_DrawUtils },
        { "NIScrollView", NIScrollView }, { "NI_SquareButton", NI_SquareButton },
        { "ISPanelJoypad", ISPanelJoypad }, { "ISPanel", ISPanel },
    }
    for i = 1, #need do
        if type(need[i][2]) ~= "table" then error("Neat Rocco's UI has no " .. need[i][1]) end
    end
end

-- Checkbox, disclosure arrow and label columns, from the body font Neat Rocco draws with.
local function geometry()
    local pad = NR_Config.padding
    local box = math.max(8, math.floor(NR_UIScale.getBodyFontHeight() * 0.7))
    local boxX = pad
    local discX = boxX + box + pad
    local textX = discX + box + pad
    return box, boxX, discX, textX, pad
end

local function install(ctx)
    local NGM = NicksGeneratorManager
    local Manage = type(NGM) == "table" and NGM.Manage or nil
    if type(Manage) ~= "table" or type(Manage.open) ~= "function" or type(Manage.instances) ~= "table" then
        error("Nick's Generator Manager has no Manage Power window")
    end
    for i = 1, #NGM_NEEDS do
        if type(NGM[NGM_NEEDS[i]]) ~= "function" then error("Nick's Generator Manager has no " .. NGM_NEEDS[i]) end
    end
    if type(NGM.BASE_DRAW) ~= "number" then error("Nick's Generator Manager has no base draw") end
    needUi()

    local fmtLh = M.fmtLh
    local arrowOpen = getTexture("media/ui/NeatRocco/ICON/Icon_ArrowDown.png")
    local arrowShut = getTexture("media/ui/NeatRocco/ICON/Icon_Arrow_R.png")

    local Panel = NR_BasePanel:derive("LugliNgmManagePanel")

    function Panel:new(x, y, w, h, playerNum, gx, gy, gz)
        local o = ISPanelJoypad.new(self, x, y, w, h)
        setmetatable(o, self)
        self.__index = self
        o.mpfNgmManage = true
        o.playerNum = playerNum
        o.gx, o.gy, o.gz = gx, gy, gz
        o.genKey = NGM.genKey(gx, gy, gz)
        o.rows, o.rowPanels = {}, {}
        o.objs, o.scannedAt = nil, 0
        o.allSpecs, o.lightSpecs = {}, {}
        o.active, o.lightsExpanded = false, false
        o.moveWithMouse = true
        NR_BasePanel.initBase(o)
        NR_CollapseUtils.init(o)
        return o
    end

    function Panel:getWindowTitle() return NGM.T("IGUI_NGM_WindowTitle", "Manage Power") end
    function Panel:getWindowIcon() return getTexture("media/ui/NeatRocco/CategoryIcon/Icon_Generator.png") end
    function Panel:onClickCollapse() NR_CollapseUtils.onClickCollapse(self) end
    function Panel:_onHeaderHover() NR_CollapseUtils.onHeaderHover(self) end

    -- The summary line, and the line under it that says why a change would be refused.
    local function textLines(panel)
        return panel ~= nil and panel.note ~= nil and 2 or 1
    end

    local function minHeight(panel)
        local c = NR_Config
        return c.headerHeight + c.padding + c.lineHeight * textLines(panel) + c.padding + c.itemHeight * 4
            + c.padding + c.actionBarHeight
    end

    local function iconButton(panel, x, y, size, icon, tip, onClick)
        local b = NI_SquareButton:new(x, y, size, getTexture(icon), panel, onClick)
        b:initialise()
        b.mpfTip = tip
        panel.actionBar:addChild(b)
        return b
    end

    function Panel:createChildren()
        NR_BasePanel.createChildren(self)
        local c = NR_Config
        local pad, size = c.padding, c.buttonSize
        self.scrollView = NIScrollView:new(pad, c.headerHeight + pad, self.width - pad * 2, c.itemHeight * 4)
        self.scrollView:initialise()
        self:addChild(self.scrollView)
        self.actionBar = ISPanel:new(pad, 0, self.width - pad * 2, c.actionBarHeight)
        self.actionBar:noBackground()
        self.actionBar:initialise()
        self:addChild(self.actionBar)
        local y = math.floor((c.actionBarHeight - size) / 2)
        self.btnClaim = iconButton(self, 0, y, size, "media/ui/NeatRocco/ICON/Icon_Add.png",
            NGM.T("IGUI_NGM_Claim", "Claim all"), self.onClaim)
        self.btnReturn = iconButton(self, size + pad, y, size, "media/ui/NeatRocco/ICON/Icon_Reset.png",
            NGM.T("IGUI_NGM_ReturnAuto", "Return all to auto"), self.onReturn)
        self.resizeWidget = NR_ResizeWidget.create(self, function(target, w, h) target:calculateLayout(w, h) end)
        self:calculateLayout(self.width, self.height)
        self:rebuild()
    end

    function Panel:calculateLayout(w, h)
        local c = NR_Config
        local pad, hh = c.padding, c.headerHeight
        local width = math.max(w or self.width, self.contentMinWidth or 0,
            self.header ~= nil and self.header:getMinimumWidth() or 0)
        local height = math.max(h or self.height, minHeight(self))
        if self.header ~= nil then
            self.header:setWidth(width)
            self.header:calculateLayout(width, hh)
        end
        self.summaryY = hh + pad
        local listY = self.summaryY + c.lineHeight * textLines(self) + pad
        local listH = height - listY - pad - c.actionBarHeight
        local sv = self.scrollView
        sv:setX(pad)
        sv:setY(listY)
        sv:setWidth(width - pad * 2)
        sv:setHeight(listH)
        self.actionBar:setX(pad)
        self.actionBar:setY(listY + listH + pad)
        self.actionBar:setWidth(width - pad * 2)
        self:setWidth(width)
        self:setHeight(height)
        if self.resizeWidget ~= nil then
            self.resizeWidget:setX(width - c.resizeSize)
            self.resizeWidget:setY(height - c.resizeSize)
        end
        for i = 1, #self.rowPanels do self.rowPanels[i]:setWidth(sv.width) end
    end

    function Panel:liveGen()
        local sq = NGM.read(function() return getSquare(self.gx, self.gy, self.gz) end)
        if not sq then return nil end
        return NGM.read(function() return sq:getGenerator() end)
    end

    -- Nick's square walk on open and every SCAN_MS; between walks, the objects it found that Nick
    -- would still bill, by the same predicate.
    function Panel:objects()
        local now = getTimestampMs()
        if self.objs == nil or now - self.scannedAt >= SCAN_MS then
            self.objs = NGM.read(function() return NGM.poweredObjectsInRange(self.gx, self.gy, self.gz) end) or {}
            self.scannedAt = now
            return self.objs
        end
        local allowExt = NGM.geom().allowExt
        local kept = {}
        for i = 1, #self.objs do
            local obj = self.objs[i]
            local sq = NGM.read(function() return obj:getSquare() end)
            if NGM.read(function() return obj:getObjectIndex() end) ~= -1
                and NGM.isBillable(obj, sq, allowExt) then
                kept[#kept + 1] = obj
            end
        end
        self.objs = kept
        return kept
    end

    function Panel:ownedByThis(obj)
        local o = NGM.resolveOwner(obj)
        return o ~= nil and o.gx == self.gx and o.gy == self.gy and o.gz == self.gz
    end

    -- Nick's rebuild, row for row: appliances by draw then name, then the light group and, when
    -- open, its lights.
    function Panel:rebuild()
        local gen = self:liveGen()
        if not gen then
            self:close()
            return
        end
        local mult = NGM.fuelMult()
        local active = NGM.isActive(gen)
        local objs = self:objects()

        -- What the server's ngm-claims rule would refuse, so the window does not offer it.
        local player = getSpecificPlayer(self.playerNum)
        local enforced = M.ngmClaimsEnforced()
        local blocked = enforced and M.ngmManageBlocks(player, self.gx, self.gy, self.gz) or nil

        local appliances, lights = {}, {}
        local ownedCount, ownedDraw = 0, 0
        for i = 1, #objs do
            local obj = objs[i]
            local cat, label = NGM.classify(obj)
            local draw = NGM.consumption(obj)
            local spec = NGM.objSpec(obj)
            if spec then
                local locked = blocked ~= nil
                    or (enforced and M.ngmSafehouseBlocks(player, NGM.read(function() return obj:getSquare() end)) ~= nil)
                local pref = enforced and not locked and NGM.getOwnerPref(obj) or nil
                local rec = { obj = obj, label = label, draw = draw, spec = spec, owned = self:ownedByThis(obj),
                              locked = locked,
                              returnable = not locked and (pref == nil or M.ngmManageBlocks(player, pref.gx, pref.gy, pref.gz) == nil) }
                if cat == "light" then lights[#lights + 1] = rec else appliances[#appliances + 1] = rec end
                if rec.owned then
                    ownedCount = ownedCount + 1
                    ownedDraw = ownedDraw + draw
                end
            end
        end
        table.sort(appliances, function(a, b)
            if a.draw ~= b.draw then return a.draw > b.draw end
            return a.label < b.label
        end)

        -- Return all leaves out a claim whose generator the player could not manage: the server refuses it.
        local rows, allSpecs, lightSpecs, returnSpecs, heldOut = {}, {}, {}, {}, false
        local function offerReturn(rec)
            if rec.returnable then returnSpecs[#returnSpecs + 1] = rec.spec
            elseif not rec.locked then heldOut = true end
        end
        for i = 1, #appliances do
            local a = appliances[i]
            if not a.locked then allSpecs[#allSpecs + 1] = a.spec end
            offerReturn(a)
            rows[#rows + 1] = { kind = "appliance", label = a.label, drawStr = fmtLh(a.draw * mult) .. " L/h",
                                spec = a.spec, owned = a.owned, locked = a.locked }
        end
        if #lights > 0 then
            local total, owned = 0, 0
            for i = 1, #lights do
                total = total + lights[i].draw
                if not lights[i].locked then
                    allSpecs[#allSpecs + 1] = lights[i].spec
                    lightSpecs[#lightSpecs + 1] = lights[i].spec
                end
                offerReturn(lights[i])
                if lights[i].owned then owned = owned + 1 end
            end
            rows[#rows + 1] = { kind = "lightgroup", label = NGM.T("IGUI_NGM_Lights", "Lights (%1/%2)", owned, #lights),
                                drawStr = fmtLh(total * mult) .. " L/h", owned = owned == #lights,
                                expanded = self.lightsExpanded == true, locked = #lightSpecs == 0 }
            if self.lightsExpanded then
                for i = 1, #lights do
                    local l = lights[i]
                    rows[#rows + 1] = { kind = "light", label = l.label, drawStr = fmtLh(l.draw * mult) .. " L/h",
                                        spec = l.spec, owned = l.owned, locked = l.locked }
                end
            end
        end

        self.rows, self.allSpecs, self.lightSpecs, self.returnSpecs, self.active = rows, allSpecs, lightSpecs, returnSpecs, active
        self.btnReturn.mpfTip = NGM.T("IGUI_NGM_ReturnAuto", "Return all to auto") .. (heldOut
            and " " .. tr("IGUI_LugliMPF_NgmReturnHeld", "(not what a generator you cannot manage claimed)") or "")
        local note = blocked == "far" and tr("IGUI_LugliMPF_NgmFar", "Stand within this generator's range to change what it powers.")
            or blocked == "safehouse" and tr("IGUI_LugliMPF_NgmSafehouse", "This generator is in a safehouse you are not allowed in.")
            or nil
        if note ~= self.note then
            self.note = note
            self:calculateLayout(self.width, self.height)
        end
        if not active then
            self.summary = NGM.T("IGUI_NGM_HeaderOff", "This generator is off")
        else
            self.summary = NGM.T("IGUI_NGM_Header", "This generator: %1 L/h - %2 owned",
                fmtLh((NGM.BASE_DRAW + ownedDraw) * mult), ownedCount)
        end
        self.lastRefresh = getTimestampMs()
        self:syncRows()
        self:syncButtons()
        self:fitContent()
    end

    function Panel:syncButtons()
        local claim = self.active and #self.allSpecs > 0
        local ret = self.active and #self.returnSpecs > 0
        self.btnClaim.enable, self.btnReturn.enable = claim, ret
        self.btnClaim:setActive(claim)
        self.btnReturn:setActive(ret)
    end

    function Panel:fitContent()
        local tm, font = getTextManager(), NR_UIScale.getBodyFont()
        local box, _, _, textX, pad = geometry()
        local minW = pad * 2 + math.max(tm:MeasureStringX(font, self.summary or ""), tm:MeasureStringX(font, self.note or ""))
        for i = 1, #self.rows do
            local d = self.rows[i]
            local w = textX + (d.kind == "light" and box or 0) + tm:MeasureStringX(font, d.label) + pad * 3
                + tm:MeasureStringX(font, d.drawStr) + NR_Config.scrollBarWidth + pad
            minW = math.max(minW, pad * 2 + w)
        end
        self.contentMinWidth = minW
        if minW > self.width then self:calculateLayout(minW, self.height) end
    end

    function Panel:drawRow(rowPanel)
        local d = self.rows[rowPanel.index]
        if d == nil then return end
        local font, fh = NR_UIScale.getBodyFont(), NR_UIScale.getBodyFontHeight()
        local box, boxX, discX, textX, pad = geometry()
        local h = rowPanel.height
        local ty, by = math.floor((h - fh) / 2), math.floor((h - box) / 2)
        local alpha = (self.active and not d.locked) and 0.9 or 0.5
        if alpha > 0.5 and rowPanel:isMouseOver() then rowPanel:drawRect(0, 0, rowPanel.width, h - 1, 0.06, 1, 1, 1) end
        rowPanel:drawRectBorder(boxX, by, box, box, alpha, 0.6, 0.6, 0.6)
        if d.owned then
            local sc = NR_Config.selectionColor
            rowPanel:drawRect(boxX + 2, by + 2, box - 4, box - 4, alpha, sc.r, sc.g, sc.b)
        end
        local x = textX
        if d.kind == "lightgroup" then
            local tex = d.expanded and arrowOpen or arrowShut
            if tex then rowPanel:drawTextureScaledAspect(tex, discX, by, box, box, alpha, 1, 1, 1) end
        elseif d.kind == "light" then
            x = textX + box
        end
        rowPanel:drawText(d.label, x, ty, 1, 1, 1, alpha, font)
        local w = getTextManager():MeasureStringX(font, d.drawStr)
        rowPanel:drawText(d.drawStr, rowPanel.width - w - pad - NR_Config.scrollBarWidth, ty, 0.7, 0.7, 0.7, alpha, font)
    end

    -- One row panel per row, reused across refreshes; each draws whatever row its index holds.
    function Panel:syncRows()
        local sv, ih = self.scrollView, NR_Config.itemHeight
        while #self.rowPanels < #self.rows do
            local index = #self.rowPanels + 1
            local rp
            rp = NR_SelectableList.newRow((index - 1) * ih, sv.width, ih,
                function()
                    local d = self.rows[rp.index]
                    return d ~= nil and d.owned == true
                end, nil,
                function(r) self:drawRow(r) end)
            rp.index = index
            rp.onMouseDown = function(r, x)
                self:clickRow(r.index, x)
                return true
            end
            sv:addScrollChild(rp)
            self.rowPanels[index] = rp
        end
        while #self.rowPanels > #self.rows do
            sv:removeScrollChild(table.remove(self.rowPanels))
        end
        sv:setScrollHeight(#self.rows * ih)
    end

    function Panel:clickRow(index, x)
        local d = self.rows[index]
        if d == nil then return end
        getSoundManager():playUISound("UISelectListItem")
        if d.kind == "lightgroup" then
            local box, _, discX, _, pad = geometry()
            if x >= discX - pad and x < discX + box + pad then
                self.lightsExpanded = not self.lightsExpanded
                self:rebuild()
            elseif self.active then
                self:toggleOwn(self.lightSpecs, d.owned)
            end
            return
        end
        if d.spec and self.active and not d.locked then self:toggleOwn({ d.spec }, d.owned) end
    end

    function Panel:toggleOwn(specs, owned)
        if #specs == 0 then return end
        local player = getSpecificPlayer(self.playerNum)
        if owned then NGM.requestReturn(player, specs)
        else NGM.requestClaim(player, specs, self.gx, self.gy, self.gz) end
        self:rebuild()
    end

    function Panel:onClaim()
        if #self.allSpecs == 0 then return end
        NGM.requestClaim(getSpecificPlayer(self.playerNum), self.allSpecs, self.gx, self.gy, self.gz)
        self:rebuild()
    end

    function Panel:onReturn()
        if #self.returnSpecs == 0 then return end
        NGM.requestReturn(getSpecificPlayer(self.playerNum), self.returnSpecs)
        self:rebuild()
    end

    function Panel:update()
        ISPanelJoypad.update(self)
        if not self:liveGen() then
            self:close()
            return
        end
        if getTimestampMs() - (self.lastRefresh or 0) >= REFRESH_MS then self:rebuild() end
    end

    function Panel:render()
        ISPanelJoypad.render(self)
        if not NR_CollapseUtils.isBodyVisible(self) then return end
        local font, pad = NR_UIScale.getBodyFont(), NR_Config.padding
        if self.summary then
            self:drawText(self.summary, pad, self.summaryY, 1, 1, 1, self.active and 0.9 or 0.6, font)
        end
        if self.note then
            local bad = getCore():getBadHighlitedColor()
            self:drawText(self.note, pad, self.summaryY + NR_Config.lineHeight, bad:getR(), bad:getG(), bad:getB(), 1, font)
        end
        local sv = self.scrollView
        if #self.rows == 0 then
            local msg = NGM.T("IGUI_NGM_Empty", "No powered objects in range")
            local w = getTextManager():MeasureStringX(font, msg)
            local x = math.max(sv.x, sv.x + math.floor((sv.width - w) / 2))
            local y = sv.y + math.floor((sv.height - NR_UIScale.getBodyFontHeight()) / 2)
            self:drawText(msg, x, y, 0.6, 0.6, 0.6, 0.8, font)
        end
        local hovered = self.btnClaim:isMouseOver() and self.btnClaim
            or self.btnReturn:isMouseOver() and self.btnReturn or nil
        if hovered then NR_DrawUtils.drawTooltipAtMouse(self, hovered.mpfTip) end
    end

    function Panel:close()
        self:closeBase()
        if Manage.instances[self.genKey] == self then Manage.instances[self.genKey] = nil end
    end

    -- Everything the game calls on its own goes through the breaker.
    for _, key in ipairs({ "update", "render", "rebuild", "drawRow", "clickRow", "onClaim", "onReturn" }) do
        Panel[key] = ctx.guard(Panel[key])
    end

    ctx.wrap(Manage, "open", function(callOriginal)
        return function(playerObj, gen, ...)
            local sq = gen:getSquare()
            local gx, gy, gz = sq:getX(), sq:getY(), sq:getZ()
            local key = NGM.genKey(gx, gy, gz)
            local existing = Manage.instances[key]
            NGM.registerGeneratorAt(gx, gy, gz)
            NGM.requestRegister(playerObj, gx, gy, gz)
            if existing ~= nil then
                existing:addToUIManager()
                existing:setVisible(true)
                existing:bringToTop()
                return
            end
            local pn = playerObj:getPlayerNum()
            local pad = NR_Config.padding
            local sw, sh = getPlayerScreenWidth(pn), getPlayerScreenHeight(pn)
            local w = math.min(NR_UIScale.scale(380 + 30 * getCore():getOptionFontSizeReal()), sw - pad * 2)
            local h = math.min(minHeight() + NR_Config.itemHeight * 4, sh - pad * 2)
            local win = Panel:new(getPlayerScreenLeft(pn) + math.floor((sw - w) / 2),
                getPlayerScreenTop(pn) + math.floor((sh - h) / 2), w, h, pn, gx, gy, gz)
            win:initialise()
            win:addToUIManager()
            if not ctx.enabled() then
                win:closeBase()
                return callOriginal(playerObj, gen, ...)
            end
            Manage.instances[key] = win
        end
    end)

    ctx.undo(function()
        local ours = {}
        for _, win in pairs(Manage.instances) do
            if type(win) == "table" and win.mpfNgmManage == true then ours[#ours + 1] = win end
        end
        for i = 1, #ours do pcall(ours[i].close, ours[i]) end
    end)
end

M.addPart({
    name = "ngm-manage",
    switch = "NgmManage",
    title = "Nick's Generator Manager: the Manage Power window in Neat Rocco's style",
    tip = "Nick's Manage Power window is a vanilla window next to Neat Rocco's generator window, and it rescans every square around the generator twice a second while it is open. This opens it as a Neat Rocco window with the same rows, checkboxes and buttons, and rescans every 5 seconds instead. Only active with both mods.",
    kind = "compat",
    all = { "NicksGeneratorManager", "Neat_Rocco" },
    side = "client",
    phase = "boot",
    pins = { "ngm.open", "ngm.rebuild", "ngm.menu", "ngm.echo", "nr.row", "nr.base" },
    install = install,
})
