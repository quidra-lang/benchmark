local Canvas = {}

function Canvas.walk(box, x, y, callback, level, role)
    level, role = level or 0, role or ""
    callback(box, x, y, level, role)
    for _, child in ipairs(box.children) do Canvas.walk(child.box, x + child.x, y + child.y, callback, level + 1, child.role) end
end

function Canvas.draw(roots, width, height)
    local grid = {}
    for y = 0, height - 1 do
        grid[y] = {}
        for x = 0, width - 1 do grid[y][x] = " " end
    end
    for _, root in ipairs(roots) do
        Canvas.walk(root.box, root.x, root.y, function(box, x, y)
            for _, string in ipairs(box.strings) do
                for i = 1, #string.text do
                    local character = string.text:sub(i, i)
                    if character ~= " " then grid[y + string.y][x + string.x + i - 1] = character end
                end
            end
        end)
    end
    local lines = {}
    for y = 0, height - 1 do
        local characters = {}
        for x = 0, width - 1 do characters[#characters + 1] = grid[y][x] end
        lines[#lines + 1] = (table.concat(characters):gsub(" +$", ""))
    end
    return lines
end

function Canvas.box_lines(roots)
    local entries = {}
    for _, root in ipairs(roots) do
        Canvas.walk(root.box, root.x, root.y, function(box, x, y, level, role)
            local line = string.rep("  ", level) .. role .. box.description
                .. string.format(" x=%d y=%d w=%d h=%d b=%d", x, y, box.width, box.height, box.baseline)
            entries[#entries + 1] = {line = line, level = level, kind = box.description:match("^(%S+)")}
        end)
    end
    return entries
end

return Canvas
