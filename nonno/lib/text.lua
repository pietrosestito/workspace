-- 5x7 bitmap font shared with the NES games (uppercase only).
local T = {}
local glyphs, font

local ACCENTS = { ["à"] = "A'", ["è"] = "E'", ["é"] = "E'", ["ì"] = "I'", ["ò"] = "O'", ["ù"] = "U'",
                  ["À"] = "A'", ["È"] = "E'", ["É"] = "E'", ["\""] = "''" }

function T.init()
    glyphs = love.filesystem.read("assets/font.txt")
    font = love.graphics.newImageFont("assets/font.png", glyphs, 1)
    love.graphics.setFont(font)
end

-- uppercase, accents to apostrophes, unknown characters to spaces
function T.clean(s)
    for k, v in pairs(ACCENTS) do s = s:gsub(k, v) end
    s = s:upper()
    return (s:gsub(".", function(c) return glyphs:find(c, 1, true) and c or " " end))
end

function T.width(s) return #s * 6 end

-- text with a 1-px black shadow; colour is {r,g,b}
function T.print(s, x, y, col)
    s = T.clean(s)
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.print(s, math.floor(x) + 1, math.floor(y) + 1)
    love.graphics.setColor(col or { 1, 1, 1 })
    love.graphics.print(s, math.floor(x), math.floor(y))
    love.graphics.setColor(1, 1, 1, 1)
end

function T.center(s, y, col)
    T.print(s, math.floor((320 - T.width(T.clean(s))) / 2), y, col)
end

-- greedy word wrap to a width in characters
function T.wrap(s, cols)
    local lines, line = {}, ""
    for word in T.clean(s):gmatch("%S+") do
        if #line == 0 then line = word
        elseif #line + 1 + #word <= cols then line = line .. " " .. word
        else lines[#lines + 1] = line; line = word end
    end
    if #line > 0 then lines[#lines + 1] = line end
    return lines
end

return T
