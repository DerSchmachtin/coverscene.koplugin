local lfs = require("libs/libkoreader-lfs")

-- The background pictures to rotate through. A scene is { file = path, corners = { 4 points } },
-- with corners as fractions of the picture: top left, top right, bottom right, bottom left.
-- Instead of file, a scene can have bundled = the name of one of the pictures that come with
-- the plugin; without corners it uses the defaults below. disabled = true keeps a scene in the
-- list, but out of the rotation.
local Scenes = {}

local plugin_dir = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$")

local BUNDLED = {
    library = {
        file = plugin_dir .. "/library.png",
        -- the lectern's board
        corners = {
            { x = 0.3600, y = 0.4320 }, { x = 0.6400, y = 0.4320 }, { x = 0.6618, y = 0.7464 }, { x = 0.3382, y = 0.7464 },
        },
    },
    gallery = {
        file = plugin_dir .. "/gallery.png",
        -- inside the frame on the back wall
        corners = {
            { x = 0.3463, y = 0.2397 }, { x = 0.6537, y = 0.2397 }, { x = 0.6537, y = 0.5856 }, { x = 0.3463, y = 0.5856 },
        },
    },
}
-- what is in the list until it gets changed
local DEFAULT_ORDER = { "library", "gallery" }
Scenes.BUNDLED_NAMES = DEFAULT_ORDER

-- a book-shaped area in the middle, for a picture whose corners have not been set yet
local GENERIC_CORNERS = {
    { x = 0.30, y = 0.30 }, { x = 0.70, y = 0.30 }, { x = 0.70, y = 0.70 }, { x = 0.30, y = 0.70 },
}

-- Before there were several pictures, there was one, in coverscene_image and coverscene_corners.
function Scenes.migrate()
    local file = G_reader_settings:readSetting("coverscene_image")
    local corners = G_reader_settings:readSetting("coverscene_corners")
    if (file or corners) and not G_reader_settings:has("coverscene_scenes") then
        -- a picture of one's own without corners used to get the library's
        G_reader_settings:saveSetting("coverscene_scenes", {
            { file = file, bundled = not file and "library" or nil, corners = corners or BUNDLED.library.corners },
        })
    end
    G_reader_settings:delSetting("coverscene_image")
    G_reader_settings:delSetting("coverscene_corners")
    -- and for a while the library was the scene without file
    for _, scene in ipairs(G_reader_settings:readSetting("coverscene_scenes") or {}) do
        if not scene.file and not scene.bundled then
            scene.bundled = "library"
        end
    end
end

function Scenes.isCustomized()
    return G_reader_settings:has("coverscene_scenes")
end

-- The list is the stored table itself: change it in place and hand it to Scenes.save().
function Scenes.list()
    local scenes = G_reader_settings:readSetting("coverscene_scenes")
    if scenes and #scenes > 0 then
        return scenes
    end
    scenes = {}
    for i, name in ipairs(DEFAULT_ORDER) do
        scenes[i] = { bundled = name }
    end
    return scenes
end

function Scenes.save(scenes)
    local untouched = #scenes == 0 or #scenes == #DEFAULT_ORDER
    for i, scene in ipairs(scenes) do
        if scene.file or scene.corners or scene.disabled or scene.bundled ~= DEFAULT_ORDER[i] then
            untouched = false
        end
    end
    if untouched then
        G_reader_settings:delSetting("coverscene_scenes")
    else
        G_reader_settings:saveSetting("coverscene_scenes", scenes)
    end
end

function Scenes.reset()
    G_reader_settings:delSetting("coverscene_scenes")
    G_reader_settings:delSetting("coverscene_last")
end

function Scenes.getFile(scene)
    return scene.file or BUNDLED[scene.bundled].file
end

function Scenes.isUsable(scene)
    return lfs.attributes(Scenes.getFile(scene), "mode") == "file"
end

function Scenes.getCorners(scene)
    return scene.corners or (scene.file and GENERIC_CORNERS or BUNDLED[scene.bundled].corners)
end

function Scenes.isRandom()
    return G_reader_settings:readSetting("coverscene_order") == "random"
end

-- The scene for the sleep screen that is about to be shown, moving on in the rotation.
function Scenes.next()
    local usable, any_enabled = {}, false
    for _, scene in ipairs(Scenes.list()) do
        if not scene.disabled then
            any_enabled = true
            if Scenes.isUsable(scene) then
                table.insert(usable, scene)
            end
        end
    end
    if not any_enabled then
        -- all switched off: the plain cover
        return nil
    end
    if #usable == 0 then
        -- e.g. the pictures are on a card that is not there: better a bundled one than none
        local bundled = { bundled = DEFAULT_ORDER[1] }
        return Scenes.isUsable(bundled) and bundled or nil
    end

    local last = G_reader_settings:readSetting("coverscene_last") or 0
    local index
    if #usable == 1 then
        index = 1
    elseif Scenes.isRandom() then
        if last >= 1 and last <= #usable then
            -- any but the one shown last
            index = math.random(#usable - 1)
            if index >= last then
                index = index + 1
            end
        else
            index = math.random(#usable)
        end
    else
        index = last % #usable + 1
    end
    G_reader_settings:saveSetting("coverscene_last", index)
    return usable[index]
end

return Scenes
