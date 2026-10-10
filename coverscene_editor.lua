local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local Compose = require("coverscene_compose")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderImage = require("ui/renderimage")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local T = require("ffi/util").template
local _ = require("gettext")
local Screen = Device.screen

local CORNER_LABELS = { "◤", "◥", "◢", "◣" }
local STEPS = { 1, 5, 25 }
local BRIGHTNESS_STEPS = { 100, 90, 80, 70, 60, 50 }
local MAGNIFIER_ZOOM = 4

-- Full-screen editor for the four corners the cover gets warped onto, and for its brightness.
-- Tap a corner (or pick it in the bar) to select it, tap the picture to put it there,
-- fine-tune with the arrows. A magnifier shows the surroundings of the selected corner.
local CoverSceneEditor = InputContainer:extend{
    picture = nil, -- from Compose.loadPicture, owned by the editor
    geom = nil,
    cover = nil, -- owned by the editor
    corners = nil,
    brightness = 100, -- percent
    save_callback = nil, -- called with the new corners and brightness
    covers_fullscreen = true,
}

function CoverSceneEditor:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.geom.w, h = self.geom.h }
    self.canvas = Blitbuffer.new(self.dimen.w, self.dimen.h, Blitbuffer.TYPE_BBRGB32)
    self.quad = Compose.cornersToQuad(self.corners, self.geom)
    self.selected = 1
    self.move_all = false
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
        local selected = i == self.selected and not self.move_all
        corner_buttons[i] = {
            text = selected and "[ " .. label .. " ]" or label,
            font_bold = selected,
            callback = function()
                self:select(i)
            end,
        }
    end
    table.insert(corner_buttons, {
        -- moves all four corners together
        text = self.move_all and "[ " .. _("All") .. " ]" or _("All"),
        font_bold = self.move_all,
        callback = function()
            self.move_all = not self.move_all
            self:buildBar()
            self:redraw()
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
                    text = T(_("Step: %1 px"), STEPS[self.step_index]),
                    font_bold = false,
                    callback = function()
                        self.step_index = self.step_index % #STEPS + 1
                        self:buildBar()
                        self:refresh()
                    end,
                },
            },
            {
                {
                    text = T(_("Brightness: %1 %"), self.brightness),
                    font_bold = false,
                    callback = function()
                        self:nextBrightness()
                    end,
                },
                {
                    text = _("Move bar"),
                    font_bold = false,
                    callback = function()
                        self.bar_on_top = not self.bar_on_top
                        self:redraw()
                    end,
                },
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
                        self.save_callback(Compose.quadToCorners(self.quad, self.geom), self.brightness)
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

function CoverSceneEditor:select(i)
    self.selected = i
    self.move_all = false
    self:buildBar()
    self:redraw()
end

-- The next darker step, and after the darkest back to full brightness.
function CoverSceneEditor:nextBrightness()
    local next_index = 1
    for i, percent in ipairs(BRIGHTNESS_STEPS) do
        if percent < self.brightness then
            next_index = i
            break
        end
    end
    self.brightness = BRIGHTNESS_STEPS[next_index]
    self:buildBar()
    self:redraw()
end

-- Puts the selected corner at x, y; with "All", the other corners come along.
function CoverSceneEditor:moveSelected(x, y)
    local max_x, max_y = self.dimen.w - 1, self.dimen.h - 1
    if self.move_all then
        local dx, dy = x - self.quad[self.selected].x, y - self.quad[self.selected].y
        -- only as far as all four stay on the picture
        for __, p in ipairs(self.quad) do
            dx = math.max(-p.x, math.min(max_x - p.x, dx))
            dy = math.max(-p.y, math.min(max_y - p.y, dy))
        end
        for i, p in ipairs(self.quad) do
            self.quad[i] = { x = p.x + dx, y = p.y + dy }
        end
    else
        self.quad[self.selected] = {
            x = math.max(0, math.min(max_x, x)),
            y = math.max(0, math.min(max_y, y)),
        }
    end
    self:redraw()
end

function CoverSceneEditor:redraw()
    Compose.paint(self.canvas, self.picture, self.geom, self.cover, self.quad, self.brightness / 100)
    -- Corner markers: frames around the corner, so the corner pixel itself stays visible.
    local r = Screen:scaleBySize(7)
    for i, p in ipairs(self.quad) do
        local bw = (i == self.selected or self.move_all) and 3 or 1
        self.canvas:paintBorder(p.x - r - bw, p.y - r - bw, 2 * (r + bw) + 1, 2 * (r + bw) + 1, bw, Blitbuffer.COLOR_BLACK)
        self.canvas:paintBorder(p.x - r, p.y - r, 2 * r + 1, 2 * r + 1, 1, Blitbuffer.COLOR_WHITE)
    end
    self:updateMagnifier()
    self:refresh()
end

-- An enlarged view of what is around the selected corner, which the finger covers when tapping.
function CoverSceneEditor:updateMagnifier()
    if self.magnifier then
        self.magnifier:free()
    end
    local w, h = self.dimen.w, self.dimen.h
    local p = self.quad[self.selected]
    local src_size = math.floor(math.min(w, h) / 3 / MAGNIFIER_ZOOM)
    local size = src_size * MAGNIFIER_ZOOM

    -- the part of the canvas around the corner; gray where that is beyond the picture
    local crop = Blitbuffer.new(src_size, src_size, Blitbuffer.TYPE_BBRGB32)
    crop:fill(Blitbuffer.COLOR_GRAY)
    local src_x, src_y = p.x - math.floor(src_size / 2), p.y - math.floor(src_size / 2)
    local skip_x, skip_y = math.max(0, -src_x), math.max(0, -src_y)
    local crop_w = math.min(src_size, w - src_x) - skip_x
    local crop_h = math.min(src_size, h - src_y) - skip_y
    if crop_w > 0 and crop_h > 0 then
        crop:blitFrom(self.canvas, skip_x, skip_y, src_x + skip_x, src_y + skip_y, crop_w, crop_h)
    end
    self.magnifier = RenderImage:scaleBlitBuffer(crop, size, size)

    -- in the quarter of the screen across from the corner, clear of the bar
    local margin = Size.padding.large
    local bar_h = self.bar:getSize().h
    local top = self.bar_on_top and bar_h or 0
    local bottom = self.bar_on_top and h or h - bar_h
    self.magnifier_x = p.x < w / 2 and w - size - margin or margin
    self.magnifier_y = p.y < (top + bottom) / 2 and bottom - size - margin or top + margin
end

function CoverSceneEditor:refresh()
    UIManager:setDirty(self, "ui")
end

function CoverSceneEditor:paintTo(bb, x, y)
    bb:blitFrom(self.canvas, x, y, 0, 0, self.dimen.w, self.dimen.h)

    local size = self.magnifier:getWidth()
    local mx, my = x + self.magnifier_x, y + self.magnifier_y
    local border = Size.border.window
    bb:blitFrom(self.magnifier, mx, my, 0, 0, size, size)
    bb:paintBorder(mx - border, my - border, size + 2 * border, size + 2 * border, border, Blitbuffer.COLOR_BLACK)
    -- marks at the edges pointing to the corner in the middle
    local mark, half = math.floor(size / 10), math.floor(size / 2)
    bb:paintRect(mx + half, my, 1, mark, Blitbuffer.COLOR_BLACK)
    bb:paintRect(mx + half, my + size - mark, 1, mark, Blitbuffer.COLOR_BLACK)
    bb:paintRect(mx, my + half, mark, 1, Blitbuffer.COLOR_BLACK)
    bb:paintRect(mx + size - mark, my + half, mark, 1, Blitbuffer.COLOR_BLACK)

    self.bar:paintTo(bb, x, y + self:getBarY())
end

function CoverSceneEditor:onTap(arg, ges)
    local bar_y = self:getBarY()
    if ges.pos.y >= bar_y and ges.pos.y < bar_y + self.bar:getSize().h then
        return true
    end
    -- A tap on another corner selects that one.
    if not self.move_all then
        local reach = Screen:scaleBySize(25)
        local nearest, nearest_distance
        for i, p in ipairs(self.quad) do
            local distance = math.sqrt((p.x - ges.pos.x)^2 + (p.y - ges.pos.y)^2)
            if not nearest_distance or distance < nearest_distance then
                nearest, nearest_distance = i, distance
            end
        end
        if nearest ~= self.selected and nearest_distance <= reach then
            self:select(nearest)
            return true
        end
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
    self.magnifier:free()
    self.picture:free()
    self.cover:free()
    -- UIManager:close() repaints what is below, but leaves refreshing the screen to the widget.
    UIManager:setDirty(nil, function()
        return "flashui", self.dimen
    end)
end

return CoverSceneEditor
