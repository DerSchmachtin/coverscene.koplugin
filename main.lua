local Device = require("device")
local DocumentRegistry = require("document/documentregistry")
local InfoMessage = require("ui/widget/infomessage")
local RenderImage = require("ui/renderimage")
local Screensaver = require("ui/screensaver")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local _ = require("gettext")
local Screen = Device.screen

-- The bundled picture, used until another one is chosen.
local DEFAULT_IMAGE = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") .. "/library.png"
-- top left, top right, bottom right, bottom left, as fractions of the background picture;
-- these are the lectern's board in the bundled picture.
local DEFAULT_CORNERS = {
    { x = 0.3600, y = 0.4320 }, { x = 0.6400, y = 0.4320 }, { x = 0.6618, y = 0.7464 }, { x = 0.3382, y = 0.7464 },
}

local function isEnabled()
    return G_reader_settings:isTrue("coverscene_enabled")
end

local function getBackgroundFile()
    local file = G_reader_settings:readSetting("coverscene_image")
    if file and lfs.attributes(file, "mode") == "file" then
        return file
    end
    if lfs.attributes(DEFAULT_IMAGE, "mode") == "file" then
        return DEFAULT_IMAGE
    end
end

local function getCorners()
    return G_reader_settings:readSetting("coverscene_corners") or DEFAULT_CORNERS
end

-- The sleep screen is always shown in portrait, whatever the current rotation.
local function getPortraitSize()
    local w, h = Screen:getWidth(), Screen:getHeight()
    if w > h then
        w, h = h, w
    end
    return w, h
end

local function compose(cover_bb)
    local bg_file = getBackgroundFile()
    if not bg_file then return end
    local w, h = getPortraitSize()
    local ok, canvas = pcall(require("coverscene_compose").render, bg_file, cover_bb, getCorners(), w, h)
    if not ok then
        logger.warn("CoverScene: compositing failed:", canvas)
        return
    end
    return canvas
end

-- Screensaver is a singleton, while plugins get instantiated once per FileManager/ReaderUI.
if not Screensaver._coverscene_orig_setup then
    Screensaver._coverscene_orig_setup = Screensaver.setup
    Screensaver.setup = function(self, event, event_message)
        Screensaver._coverscene_orig_setup(self, event, event_message)
        -- Only step in when the stock "book cover" mode really ended up with a cover,
        -- so that its exclusions and fallbacks keep working.
        if isEnabled() and self.screensaver_type == "cover" and self.image then
            local canvas = compose(self.image)
            if canvas then
                self.image:free()
                self.image = canvas
            end
        end
    end
end

local CoverScene = WidgetContainer:extend{
    name = "coverscene",
    is_doc_only = false,
}

function CoverScene:init()
    self.ui.menu:registerToMainMenu(self)
    -- Up to v2025.10 KOReader creates the sleep screen menu only after the plugins have added
    -- their items, and the menu sorter takes it out of menu_items again. So the item is put in
    -- at the moment the sleep screen menu gets assigned.
    setmetatable(self.ui.menu.menu_items, {
        __newindex = function(menu_items, id, item)
            if id == "screensaver" and type(item) == "table" and item.sub_item_table then
                table.insert(item.sub_item_table, self:genMenuItem())
            end
            rawset(menu_items, id, item)
        end,
    })
end

function CoverScene:addToMainMenu(menu_items)
    -- Devices without a sleep screen menu still get the item, for the preview.
    if not Device:supportsScreensaver() then
        local item = self:genMenuItem()
        item.sorting_hint = "screen"
        menu_items.coverscene = item
    end
end

function CoverScene:genMenuItem()
    return {
        text = _("Book cover in background picture"),
        sub_item_table = {
            {
                text = _("Place book cover into background picture"),
                help_text = _("Needs the sleep screen wallpaper to be set to 'Show book cover on sleep screen'."),
                checked_func = isEnabled,
                callback = function()
                    G_reader_settings:flipNilOrFalse("coverscene_enabled")
                end,
            },
            {
                text = _("Choose background picture"),
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    self:chooseBackground(touchmenu_instance)
                end,
            },
            {
                text = _("Set cover corners"),
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    self:editCorners(touchmenu_instance)
                end,
            },
            {
                text = _("Preview"),
                keep_menu_open = true,
                callback = function()
                    self:showPreview()
                end,
            },
            {
                text = _("Reset to default"),
                help_text = _("Goes back to the bundled library picture and its cover corners."),
                keep_menu_open = true,
                enabled_func = function()
                    return G_reader_settings:has("coverscene_image") or G_reader_settings:has("coverscene_corners")
                end,
                callback = function(touchmenu_instance)
                    self:resetToDefault(touchmenu_instance)
                end,
            },
        },
    }
end

function CoverScene:chooseBackground(touchmenu_instance)
    local filemanagerutil = require("apps/filemanager/filemanagerutil")
    local caller_callback = function(path)
        G_reader_settings:saveSetting("coverscene_image", path)
        if touchmenu_instance then touchmenu_instance:updateItems() end
    end
    local file_filter = function(filename)
        return DocumentRegistry:isImageFile(filename)
    end
    filemanagerutil.showChooseDialog(_("Current background picture:"), caller_callback,
        G_reader_settings:readSetting("coverscene_image"), nil, file_filter)
end

-- The cover of the current (or last) book, or a checkerboard to stand in for it.
function CoverScene:getSampleCover()
    local cover_bb
    local lastfile = G_reader_settings:readSetting("lastfile")
    if self.ui.document or (lastfile and lfs.attributes(lastfile, "mode") == "file") then
        cover_bb = self.ui.bookinfo:getCoverImage(self.ui.document, lastfile)
    end
    return cover_bb or RenderImage:renderCheckerboard(600, 900)
end

function CoverScene:editCorners(touchmenu_instance)
    local bg_file = getBackgroundFile()
    if not bg_file then
        UIManager:show(InfoMessage:new{ text = _("Please choose a background picture first.") })
        return
    end
    if Screen:getWidth() > Screen:getHeight() then
        UIManager:show(InfoMessage:new{ text = _("Please rotate the screen to portrait to set the corners.") })
        return
    end
    local Compose = require("coverscene_compose")
    local background, geom = Compose.prepareBackground(bg_file, Screen:getWidth(), Screen:getHeight())
    if not background then
        UIManager:show(InfoMessage:new{ text = _("Could not render the background picture.") })
        return
    end
    UIManager:show(require("coverscene_editor"):new{
        background = background,
        geom = geom,
        cover = self:getSampleCover(),
        corners = getCorners(),
        save_callback = function(corners)
            G_reader_settings:saveSetting("coverscene_corners", corners)
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    })
end

function CoverScene:resetToDefault(touchmenu_instance)
    local ConfirmBox = require("ui/widget/confirmbox")
    UIManager:show(ConfirmBox:new{
        text = _("Go back to the bundled library picture and its cover corners?"),
        ok_text = _("Reset"),
        ok_callback = function()
            G_reader_settings:delSetting("coverscene_image")
            G_reader_settings:delSetting("coverscene_corners")
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    })
end

function CoverScene:showPreview()
    if not getBackgroundFile() then
        UIManager:show(InfoMessage:new{ text = _("Please choose a background picture first.") })
        return
    end
    local cover_bb = self:getSampleCover()
    local canvas = compose(cover_bb)
    cover_bb:free()
    if not canvas then
        UIManager:show(InfoMessage:new{ text = _("Could not render the background picture.") })
        return
    end
    local ImageViewer = require("ui/widget/imageviewer")
    UIManager:show(ImageViewer:new{
        image = canvas,
        with_title_bar = false,
        fullscreen = true,
    })
end

return CoverScene
