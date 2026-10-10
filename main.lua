local Device = require("device")
local ConfirmBox = require("ui/widget/confirmbox")
local DocumentRegistry = require("document/documentregistry")
local InfoMessage = require("ui/widget/infomessage")
local RenderImage = require("ui/renderimage")
local Scenes = require("coverscene_scenes")
local Screensaver = require("ui/screensaver")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local ffiUtil = require("ffi/util")
local _ = require("gettext")
local T = ffiUtil.template
local Screen = Device.screen

Scenes.migrate()

local function isEnabled()
    return G_reader_settings:isTrue("coverscene_enabled")
end

-- The sleep screen is always shown in portrait, whatever the current rotation.
local function getPortraitSize()
    local w, h = Screen:getWidth(), Screen:getHeight()
    if w > h then
        w, h = h, w
    end
    return w, h
end

local function compose(cover_bb, scene)
    local w, h = getPortraitSize()
    local ok, canvas = pcall(require("coverscene_compose").render,
        Scenes.getFile(scene), cover_bb, Scenes.getCorners(scene), w, h)
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
            local scene = Scenes.next()
            local canvas = scene and compose(self.image, scene)
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

local BUNDLED_NAMES = {
    library = _("Library (bundled)"),
    gallery = _("Gallery (bundled)"),
}

function CoverScene:genMenuItem()
    return {
        text = _("Book cover in background picture"),
        sub_item_table_func = function()
            return self:genMenuTable()
        end,
    }
end

function CoverScene:genMenuTable()
    local menu_table = {
        {
            text = _("Place book cover into background picture"),
            help_text = _("Needs the sleep screen wallpaper to be set to 'Show book cover on sleep screen'."),
            checked_func = isEnabled,
            callback = function()
                G_reader_settings:flipNilOrFalse("coverscene_enabled")
            end,
        },
        {
            text = _("Background pictures"),
            sub_item_table_func = function()
                return self:genPicturesMenuTable()
            end,
            separator = true,
        },
    }
    table.insert(menu_table, {
        text_func = function()
            return T(_("Order of pictures: %1"), Scenes.isRandom() and _("random") or _("in turn"))
        end,
        help_text = _("With several background pictures, each sleep screen shows another one."),
        enabled_func = function()
            return #Scenes.list() > 1
        end,
        sub_item_table = {
            {
                text = _("In turn"),
                radio = true,
                checked_func = function() return not Scenes.isRandom() end,
                callback = function() G_reader_settings:delSetting("coverscene_order") end,
            },
            {
                text = _("Random"),
                radio = true,
                checked_func = Scenes.isRandom,
                callback = function() G_reader_settings:saveSetting("coverscene_order", "random") end,
            },
        },
    })
    table.insert(menu_table, {
        text = _("Reset to default"),
        help_text = _("Goes back to the bundled pictures alone, with their cover corners."),
        keep_menu_open = true,
        enabled_func = Scenes.isCustomized,
        callback = function(touchmenu_instance)
            UIManager:show(ConfirmBox:new{
                text = _("Go back to the bundled pictures alone, with their cover corners?"),
                ok_text = _("Reset"),
                ok_callback = function()
                    Scenes.reset()
                    touchmenu_instance:updateItems()
                end,
            })
        end,
    })
    return menu_table
end

-- The list of background pictures, and the ways to add one.
function CoverScene:genPicturesMenuTable()
    local scenes = Scenes.list()
    local menu_table = {}
    for __, scene in ipairs(scenes) do
        table.insert(menu_table, self:genSceneMenuItem(menu_table, scenes, scene))
    end
    for __, name in ipairs(Scenes.BUNDLED_NAMES) do
        local in_list = false
        for ___, scene in ipairs(scenes) do
            in_list = in_list or scene.bundled == name
        end
        if not in_list then
            table.insert(menu_table, {
                text = T(_("Add %1"), BUNDLED_NAMES[name]),
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    table.insert(scenes, { bundled = name })
                    Scenes.save(scenes)
                    self:refillMenuTable(menu_table)
                    touchmenu_instance:updateItems()
                end,
            })
        end
    end
    table.insert(menu_table, {
        text = _("Add background picture"),
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            self:addScene(menu_table, touchmenu_instance)
        end,
    })
    return menu_table
end

local function getSceneName(scene)
    if not scene.file then
        return BUNDLED_NAMES[scene.bundled]
    end
    local name = ffiUtil.basename(scene.file)
    return Scenes.isUsable(scene) and name or T(_("%1 (missing)"), name)
end

function CoverScene:genSceneMenuItem(menu_table, scenes, scene)
    return {
        text = getSceneName(scene),
        checked_func = function() return not scene.disabled end,
        sub_item_table = {
            {
                text = _("Use this picture"),
                help_text = _("A picture that is not used stays in the list with its cover corners, but is not shown on the sleep screen."),
                checked_func = function() return not scene.disabled end,
                callback = function()
                    scene.disabled = not scene.disabled or nil
                    Scenes.save(scenes)
                end,
                separator = true,
            },
            {
                text = _("Set cover corners"),
                keep_menu_open = true,
                enabled_func = function() return Scenes.isUsable(scene) end,
                callback = function()
                    self:editCorners(scenes, scene)
                end,
            },
            {
                text = _("Preview"),
                keep_menu_open = true,
                enabled_func = function() return Scenes.isUsable(scene) end,
                callback = function()
                    self:showPreview(scene)
                end,
            },
            {
                text = _("Remove"),
                keep_menu_open = true,
                -- removing the last one would bring back the bundled ones
                enabled_func = function() return scene.file ~= nil or #scenes > 1 end,
                callback = function(touchmenu_instance)
                    UIManager:show(ConfirmBox:new{
                        text = T(_("Remove %1 from the background pictures?\nThe picture file is kept."), getSceneName(scene)),
                        ok_text = _("Remove"),
                        ok_callback = function()
                            for i, other in ipairs(scenes) do
                                if other == scene then
                                    table.remove(scenes, i)
                                    break
                                end
                            end
                            Scenes.save(scenes)
                            self:refillMenuTable(menu_table)
                            touchmenu_instance:backToUpperMenu()
                        end,
                    })
                end,
            },
        },
    }
end

-- The menu holds on to the table it is showing, so that one gets the new items.
function CoverScene:refillMenuTable(menu_table)
    local items = self:genPicturesMenuTable()
    for i = #menu_table, 1, -1 do
        menu_table[i] = nil
    end
    for i, item in ipairs(items) do
        menu_table[i] = item
    end
end

function CoverScene:addScene(menu_table, touchmenu_instance)
    local scenes = Scenes.list()
    local dir = G_reader_settings:readSetting("coverscene_last_dir")
    if not dir or lfs.attributes(dir, "mode") ~= "directory" then
        dir = G_reader_settings:readSetting("home_dir") or require("apps/filemanager/filemanagerutil").getDefaultDir()
    end
    UIManager:show(require("ui/widget/pathchooser"):new{
        select_directory = false,
        select_file = true,
        show_files = true,
        file_filter = function(filename)
            return DocumentRegistry:isImageFile(filename)
        end,
        path = dir,
        onConfirm = function(path)
            G_reader_settings:saveSetting("coverscene_last_dir", ffiUtil.dirname(path))
            local scene
            for __, other in ipairs(scenes) do
                if other.file == path then
                    scene = other
                end
            end
            if not scene then
                scene = { file = path }
                table.insert(scenes, scene)
                Scenes.save(scenes)
                self:refillMenuTable(menu_table)
                touchmenu_instance:updateItems()
            end
            -- once the file chooser is gone
            UIManager:nextTick(function()
                self:editCorners(scenes, scene)
            end)
        end,
    })
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

function CoverScene:editCorners(scenes, scene)
    if Screen:getWidth() > Screen:getHeight() then
        UIManager:show(InfoMessage:new{ text = _("Please rotate the screen to portrait to set the corners.") })
        return
    end
    local Compose = require("coverscene_compose")
    local background, geom = Compose.prepareBackground(Scenes.getFile(scene), Screen:getWidth(), Screen:getHeight())
    if not background then
        UIManager:show(InfoMessage:new{ text = _("Could not render the background picture.") })
        return
    end
    UIManager:show(require("coverscene_editor"):new{
        background = background,
        geom = geom,
        cover = self:getSampleCover(),
        corners = Scenes.getCorners(scene),
        save_callback = function(corners)
            scene.corners = corners
            Scenes.save(scenes)
        end,
    })
end

function CoverScene:showPreview(scene)
    local cover_bb = self:getSampleCover()
    local canvas = compose(cover_bb, scene)
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
