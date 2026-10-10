local Blitbuffer = require("ffi/blitbuffer")
local RenderImage = require("ui/renderimage")
local ffi = require("ffi")

local Compose = {}

-- Whether a picture has see-through parts. MuPDF hands out pictures with an alpha channel as
-- BB8A or BBRGB32, with premultiplied alpha.
local function hasTransparency(bb)
    local bbtype = bb:getType()
    local pixel_size
    if bbtype == Blitbuffer.TYPE_BBRGB32 then
        pixel_size = 4
    elseif bbtype == Blitbuffer.TYPE_BB8A then
        pixel_size = 2
    else
        return false
    end
    local data, stride = ffi.cast("uint8_t *", bb.data), tonumber(bb.stride)
    local w, h = bb:getWidth(), bb:getHeight()
    for y = 0, h - 1 do
        local alpha = data + y * stride + pixel_size - 1
        for x = 0, w - 1 do
            if alpha[x * pixel_size] ~= 0xFF then
                return true
            end
        end
    end
    return false
end

-- Loads the background picture scaled to fill a w x h screen. Returns it and the geometry needed
-- to crop it centered and to map picture positions to screen pixels. geom.see_through tells that
-- the picture has transparent parts, and so goes over the cover instead of under it.
function Compose.loadPicture(bg_file, w, h)
    local picture = RenderImage:renderImageFile(bg_file, false)
    if not picture then return end

    local scale = math.max(w / picture:getWidth(), h / picture:getHeight())
    local geom = {
        w = w,
        h = h,
        scaled_w = math.ceil(picture:getWidth() * scale),
        scaled_h = math.ceil(picture:getHeight() * scale),
    }
    geom.off_x = math.floor((geom.scaled_w - w) / 2)
    geom.off_y = math.floor((geom.scaled_h - h) / 2)
    picture = RenderImage:scaleBlitBuffer(picture, geom.scaled_w, geom.scaled_h)
    geom.see_through = hasTransparency(picture)
    return picture, geom
end

-- Paints the scene onto canvas (BBRGB32, geom.w x geom.h): the picture from Compose.loadPicture
-- and cover_bb stretched onto the quad. brightness (0..1) darkens the cover.
function Compose.paint(canvas, picture, geom, cover_bb, quad, brightness)
    if geom.see_through then
        canvas:fill(Blitbuffer.COLOR_WHITE)
        Compose.warp(canvas, cover_bb, quad, brightness)
        canvas:pmulalphablitFrom(picture, 0, 0, geom.off_x, geom.off_y, geom.w, geom.h)
    else
        canvas:blitFrom(picture, 0, 0, geom.off_x, geom.off_y, geom.w, geom.h)
        Compose.warp(canvas, cover_bb, quad, brightness)
    end
end

-- Corners are stored as fractions (0..1) of the background picture, in the order
-- top left, top right, bottom right, bottom left; a quad is the same in screen pixels.
function Compose.cornersToQuad(corners, geom)
    local quad = {}
    for i, c in ipairs(corners) do
        quad[i] = {
            x = math.floor(c.x * geom.scaled_w - geom.off_x + 0.5),
            y = math.floor(c.y * geom.scaled_h - geom.off_y + 0.5),
        }
    end
    return quad
end

function Compose.quadToCorners(quad, geom)
    local corners = {}
    for i, p in ipairs(quad) do
        corners[i] = {
            x = (p.x + geom.off_x) / geom.scaled_w,
            y = (p.y + geom.off_y) / geom.scaled_h,
        }
    end
    return corners
end

-- Projective mapping from quad pixels back to the unit square (0,0)-(1,1), as the 9 coefficients of
--   u = (A*x + B*y + C) / (G*x + H*y + I),  v = (D*x + E*y + F) / (G*x + H*y + I)
-- Returns nil for a degenerate quad.
function Compose.inverseHomography(quad)
    local x0, y0 = quad[1].x, quad[1].y
    local x1, y1 = quad[2].x, quad[2].y
    local x2, y2 = quad[3].x, quad[3].y
    local x3, y3 = quad[4].x, quad[4].y
    local dx1, dx2, sx = x1 - x2, x3 - x2, x0 - x1 + x2 - x3
    local dy1, dy2, sy = y1 - y2, y3 - y2, y0 - y1 + y2 - y3
    local den = dx1 * dy2 - dx2 * dy1
    if den == 0 then return end
    -- unit square to quad
    local g = (sx * dy2 - dx2 * sy) / den
    local h = (dx1 * sy - sx * dy1) / den
    local a, b, c = x1 - x0 + g * x1, x3 - x0 + h * x3, x0
    local d, e, f = y1 - y0 + g * y1, y3 - y0 + h * y3, y0
    -- and its adjugate for the way back
    return e - f * h, c * h - b, b * f - c * e,
           f * g - d, a - c * g, c * d - a * f,
           d * h - e * g, b * g - a * h, a * e - b * d
end

local function dist(p, q)
    return math.sqrt((p.x - q.x)^2 + (p.y - q.y)^2)
end

-- Draws cover_bb onto canvas (BBRGB32), stretched so that its corners land on the quad's corners.
-- brightness (0..1, 1 if left out) darkens it. cover_bb is left untouched.
function Compose.warp(canvas, cover_bb, quad, brightness)
    local A, B, C, D, E, F, G, H, I = Compose.inverseHomography(quad)
    if not A then return end
    brightness = brightness or 1

    -- Bring the cover to about its on-screen size first with the good scaler,
    -- so that bilinear sampling below is enough.
    local src_w = math.max(1, math.floor(math.max(dist(quad[1], quad[2]), dist(quad[4], quad[3])) + 0.5))
    local src_h = math.max(1, math.floor(math.max(dist(quad[1], quad[4]), dist(quad[2], quad[3])) + 0.5))
    local scaled = RenderImage:scaleBlitBuffer(cover_bb, src_w, src_h, false)
    local src = Blitbuffer.new(src_w, src_h, Blitbuffer.TYPE_BBRGB32)
    src:blitFrom(scaled, 0, 0, 0, 0, src_w, src_h)
    if scaled ~= cover_bb then
        scaled:free()
    end

    local canvas_w, canvas_h = canvas:getWidth(), canvas:getHeight()
    local min_x = math.max(0, math.min(quad[1].x, quad[2].x, quad[3].x, quad[4].x) - 1)
    local max_x = math.min(canvas_w - 1, math.max(quad[1].x, quad[2].x, quad[3].x, quad[4].x) + 1)
    local min_y = math.max(0, math.min(quad[1].y, quad[2].y, quad[3].y, quad[4].y) - 1)
    local max_y = math.min(canvas_h - 1, math.max(quad[1].y, quad[2].y, quad[3].y, quad[4].y) + 1)

    local src_data, src_stride = ffi.cast("uint8_t *", src.data), tonumber(src.stride)
    local dst_data, dst_stride = ffi.cast("uint8_t *", canvas.data), tonumber(canvas.stride)
    local floor, min = math.floor, math.min
    for y = min_y, max_y do
        local py = y + 0.5
        local dst_row = dst_data + y * dst_stride
        for x = min_x, max_x do
            local px = x + 0.5
            local w = G * px + H * py + I
            if w ~= 0 then
                -- position in the source, in pixel-center coordinates
                local u = (A * px + B * py + C) / w * src_w - 0.5
                local v = (D * px + E * py + F) / w * src_h - 0.5
                -- fades out over the last pixel, to smooth the cover's edges
                local cov_x = min(u + 1, src_w - u, 1)
                local cov_y = min(v + 1, src_h - v, 1)
                if cov_x > 0 and cov_y > 0 then
                    local u0, v0 = floor(u), floor(v)
                    local fu, fv = u - u0, v - v0
                    local xa = u0 < 0 and 0 or (u0 > src_w - 1 and src_w - 1 or u0)
                    local xb = u0 + 1 < 0 and 0 or (u0 + 1 > src_w - 1 and src_w - 1 or u0 + 1)
                    local ya = v0 < 0 and 0 or (v0 > src_h - 1 and src_h - 1 or v0)
                    local yb = v0 + 1 < 0 and 0 or (v0 + 1 > src_h - 1 and src_h - 1 or v0 + 1)
                    local p_aa = src_data + ya * src_stride + xa * 4
                    local p_ba = src_data + ya * src_stride + xb * 4
                    local p_ab = src_data + yb * src_stride + xa * 4
                    local p_bb = src_data + yb * src_stride + xb * 4
                    local dst = dst_row + x * 4
                    local cov = cov_x * cov_y
                    for ch = 0, 2 do
                        local top = p_aa[ch] + (p_ba[ch] - p_aa[ch]) * fu
                        local bottom = p_ab[ch] + (p_bb[ch] - p_ab[ch]) * fu
                        local value = (top + (bottom - top) * fv) * brightness
                        dst[ch] = floor(dst[ch] + (value - dst[ch]) * cov + 0.5)
                    end
                    dst[3] = 0xFF
                end
            end
        end
    end
    src:free()
end

-- Returns a new w x h BlitBuffer: the background picture with cover_bb warped onto the given corners.
function Compose.render(bg_file, cover_bb, corners, w, h, brightness)
    local picture, geom = Compose.loadPicture(bg_file, w, h)
    if not picture then return end
    local canvas = Blitbuffer.new(w, h, Blitbuffer.TYPE_BBRGB32)
    Compose.paint(canvas, picture, geom, cover_bb, Compose.cornersToQuad(corners, geom), brightness)
    picture:free()
    return canvas
end

return Compose
