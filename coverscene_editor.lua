local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local Compose = require("coverscene_compose")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local T = require("ffi/util").template
local _ = require("gettext")
local Screen = Device.screen

local CORNER_LABELS = { "◤", "◥", "◢", "◣" }
local STEPS = { 1, 5, 25 }

-- Full-screen editor for the four corners the cover gets warped onto.
-- Pick a corner in the bar, tap the picture to put it there, fine-tune with the arrows.
local CoverSceneEditor = InputContainer:extend{
    background = nil, -- BBRGB32 from Compose.prepareBackground, owned by the editor
    geom = nil,
    cover = nil, -- owned by the editor
    corners = nil,
    save_callback = nil, -- called with the new corners
    covers_fullscreen = true,
}

function CoverSceneEditor:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.background:getWidth(), h = self.background:getHeight() }
    self.canvas = Blitbuffer.new(self.dimen.w, self.dimen.h, Blitbuffer.TYPE_BBRGB32)
    self.quad = Compose.cornersToQuad(self.corners, self.geom)
    self.selected = 1
    self.step_index = 1
    self.bar_on_top = false

    self.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = self.dimen } },
    }
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end

    self:buildBar()
    self:redraw()
end

function CoverSceneEditor:buildBar()
    local corner_buttons = {}
    for i, label in ipairs(CORNER_LABELS) do
        corner_buttons[i] = {
            text = i == self.selected and "[ " .. label .. " ]" or label,
            font_bold = i == self.selected,
            callback = function()
                self.selected = i
                self:buildBar()
                self:redraw()
            end,
        }
    end
    table.insert(corner_buttons, {
        text = T(_("Step: %1 px"), STEPS[self.step_index]),
        font_bold = false,
        callback = function()
            self.step_index = self.step_index % #STEPS + 1
            self:buildBar()
            self:refresh()
        end,
    })
    table.insert(corner_buttons, {
        text = _("Move bar"),
        font_bold = false,
        callback = function()
            self.bar_on_top = not self.bar_on_top
            self:refresh()
        end,
    })

    local function nudgeButton(text, dx, dy)
        return {
            text = text,
            callback = function()
                local step = STEPS[self.step_index]
                self:moveSelected(self.quad[self.selected].x + dx * step, self.quad[self.selected].y + dy * step)
            end,
        }
    end
    local button_table = ButtonTable:new{
        width = self.dimen.w - 2 * (Size.border.window + Size.padding.default),
        buttons = {
            corner_buttons,
            {
                nudgeButton("◁", -1, 0),
                nudgeButton("△", 0, -1),
                nudgeButton("▽", 0, 1),
                nudgeButton("▷", 1, 0),
                {
                    text = _("Cancel"),
                    font_bold = false,
                    callback = function()
                        UIManager:close(self)
                    end,
                },
                {
                    text = _("Save"),
                    callback = function()
                        self.save_callback(Compose.quadToCorners(self.quad, self.geom))
                        UIManager:close(self)
                    end,
                },
            },
        },
        zero_sep = true,
        show_parent = self,
    }
    self.bar = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = Size.border.window,
        padding = Size.padding.default,
        margin = 0,
        button_table,
    }
    self[1] = self.bar
end

function CoverSceneEditor:getBarY()
    return self.bar_on_top and 0 or self.dimen.h - self.bar:getSize().h
end

function CoverSceneEditor:moveSelected(x, y)
    self.quad[self.selected] = {
        x = math.max(0, math.min(self.dimen.w - 1, x)),
        y = math.max(0, math.min(self.dimen.h - 1, y)),
    }
    self:redraw()
end

function CoverSceneEditor:redraw()
    self.canvas:blitFrom(self.background, 0, 0, 0, 0, self.dimen.w, self.dimen.h)
    Compose.warp(self.canvas, self.cover, self.quad)
    -- Corner markers: frames around the corner, so the corner pixel itself stays visible.
    local r = Screen:scaleBySize(7)
    for i, p in ipairs(self.quad) do
        local bw = i == self.selected and 3 or 1
        self.canvas:paintBorder(p.x - r - bw, p.y - r - bw, 2 * (r + bw) + 1, 2 * (r + bw) + 1, bw, Blitbuffer.COLOR_BLACK)
        self.canvas:paintBorder(p.x - r, p.y - r, 2 * r + 1, 2 * r + 1, 1, Blitbuffer.COLOR_WHITE)
    end
    self:refresh()
end

function CoverSceneEditor:refresh()
    UIManager:setDirty(self, "ui")
end

function CoverSceneEditor:paintTo(bb, x, y)
    bb:blitFrom(self.canvas, x, y, 0, 0, self.dimen.w, self.dimen.h)
    self.bar:paintTo(bb, x, y + self:getBarY())
end

function CoverSceneEditor:onTap(arg, ges)
    local bar_y = self:getBarY()
    if ges.pos.y >= bar_y and ges.pos.y < bar_y + self.bar:getSize().h then
        return true
    end
    self:moveSelected(ges.pos.x, ges.pos.y)
    return true
end

function CoverSceneEditor:onClose()
    UIManager:close(self)
    return true
end

function CoverSceneEditor:onCloseWidget()
    self.canvas:free()
    self.background:free()
    self.cover:free()
    -- UIManager:close() repaints what is below, but leaves refreshing the screen to the widget.
    UIManager:setDirty(nil, function()
        return "flashui", self.dimen
    end)
end

return CoverSceneEditor
