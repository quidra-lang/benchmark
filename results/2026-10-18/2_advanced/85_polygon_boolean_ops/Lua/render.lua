local Rational = require("rational")
local Rings = require("rings")
local Render = {}

function Render.grid(polygons, operands, x0, y0, width, height, columns, rows)
    local sequence, lines, counts = {}, {}, {["#"] = 0, a = 0, b = 0, ["+"] = 0}
    for _, polygon in ipairs(polygons) do for _, ring in ipairs(polygon) do sequence[#sequence + 1] = ring end end
    for row = 0, rows - 1 do
        local cells = {}
        for column = 0, columns - 1 do
            local point = Rational.point(2 * x0 + (2 * column + 1) * width,
                2 * y0 + (2 * (rows - 1 - row) + 1) * height, 2)
            local character = "."
            if Rings.interior(sequence, point) then character = "#"
            elseif operands then
                local first, second = Rings.interior(operands[1].rings, point), Rings.interior(operands[2].rings, point)
                character = first and second and "+" or first and "a" or second and "b" or "."
            end
            cells[#cells + 1] = character
            if counts[character] then counts[character] = counts[character] + 1 end
        end
        lines[#lines + 1] = table.concat(cells)
    end
    return lines, counts
end

return Render
