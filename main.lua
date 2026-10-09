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
end

function CoverScene:addToMainMenu(menu_items)
    local item = {
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
                callback = function()
                    self:chooseBackground()
                end,
            },
            {
                text = _("Set cover corners"),
                keep_menu_open = true,
                callback = function()
                    self:editCorners()
                end,
            },
            {
                text = _("Preview"),
                keep_menu_open = true,
                callback = function()
                    self:showPreview()
                end,
            },
        },
    }
    -- Lives with the other sleep screen settings, where the device has such a menu.
    local sleep_screen_menu = menu_items.screensaver and menu_items.screensaver.sub_item_table
    if sleep_screen_menu then
        table.insert(sleep_screen_menu, item)
    else
        item.sorting_hint = "screen"
        menu_items.coverscene = item
    end
end

function CoverScene:chooseBackground()
    local filemanagerutil = require("apps/filemanager/filemanagerutil")
    local caller_callback = function(path)
        G_reader_settings:saveSetting("coverscene_image", path)
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

function CoverScene:editCorners()
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
