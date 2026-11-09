local parser = require("document_parser")
local M = {}
function M.is_letter(character)
    return character:match("^[A-Za-z]$") ~= nil
end
local Dictionary = {}
Dictionary.__index = Dictionary
function Dictionary:register(spelling)
    local parts, position, points = parser.split(spelling, "-"), 0, {}
    for i = 1, #parts - 1 do
        position = position + #parts[i]
        points[#points + 1] = position
    end
    self.words[table.concat(parts)] = points
end
function Dictionary:split_points(word)
    local first, last, points = 1, #word, {}
    while first <= #word and not M.is_letter(word:sub(first, first)) do
        first = first + 1
    end
    while last >= first and not M.is_letter(word:sub(last, last)) do
        last = last - 1
    end
    local core = word:sub(first, last)
    if core:match("^[A-Za-z]+$") then
        for _, position in ipairs(self.words[core:lower()] or {}) do
            if position >= self.left_min and #core - position >= self.right_min then
                points[first - 1 + position] = true
            end
        end
    end
    for position = 2, #word - 1 do
        if word:sub(position, position) == "-" and M.is_letter(word:sub(position - 1, position - 1)) and M.is_letter(word:sub(position + 1, position + 1)) then
            points[position] = false
        end
    end
    local positions, result = {}, {}
    for position in pairs(points) do
        positions[#positions + 1] = position
    end
    table.sort(positions)
    for _, position in ipairs(positions) do
        result[#result + 1] = {position, points[position]}
    end
    return result
end
function M.new(lines, additions, left_min, right_min)
    local self = setmetatable({words = {}, left_min = left_min, right_min = right_min}, Dictionary)
    for _, word in ipairs(lines) do
        self:register(word)
    end
    for _, word in ipairs(additions) do
        self:register(word)
    end
    return self
end
return M
