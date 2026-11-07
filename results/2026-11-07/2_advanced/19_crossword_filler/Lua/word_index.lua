local M = {uppercase = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"}

function M.is_valid_word(text) return #text >= 3 and #text <= 15 and text:match("^[A-Z]+$") ~= nil end

function M.is_valid_integer(text, low, high)
    if #text == 0 or text:sub(1, 1) == "0" or #text > #tostring(high) or not text:match("^%d+$") then return false end
    local value = tonumber(text)
    return value >= low and value <= high
end

function M.word_line_error(line)
    local _, count = line:gsub(" ", "")
    if count ~= 1 then return "bad format" end
    local word, score = line:match("^(.-) (.*)$")
    if not M.is_valid_word(word) then return "bad word" end
    if not M.is_valid_integer(score, 1, 100) then return "bad score" end
    return nil
end

function M.clue_line_error(line)
    local _, count = line:gsub("|", "")
    if count ~= 1 then return "bad format" end
    local word, clue = line:match("^(.-)|(.*)$")
    if not M.is_valid_word(word) then return "bad word" end
    if #clue < 1 or #clue > 60 or clue:sub(1, 1) == " " or clue:sub(-1) == " " then return "bad clue" end
    return nil
end

function M.matches(word, pattern)
    for position = 1, #pattern do
        local mark = pattern:sub(position, position)
        if mark ~= "." and mark ~= word:sub(position, position) then return false end
    end
    return true
end

local WordIndex = {}
WordIndex.__index = WordIndex
local function letter_key(length, position, letter) return length .. ":" .. position .. ":" .. letter end

function WordIndex.new(scores)
    local self = setmetatable({scores = scores, ranked = {}, by_length = {}, by_letter = {}}, WordIndex)
    for word in pairs(scores) do self.ranked[#self.ranked + 1] = word end
    table.sort(self.ranked, function(a, b) return scores[a] > scores[b] or scores[a] == scores[b] and a < b end)
    for _, word in ipairs(self.ranked) do
        local length = #word
        self.by_length[length] = self.by_length[length] or {}
        local bucket = self.by_length[length]
        bucket[#bucket + 1] = word
        for position = 1, length do
            local key = letter_key(length, position, word:sub(position, position))
            self.by_letter[key] = self.by_letter[key] or {}
            bucket = self.by_letter[key]
            bucket[#bucket + 1] = word
        end
    end
    return self
end

function WordIndex:candidates(pattern, min_score, used)
    local pool = self.by_length[#pattern] or {}
    for position = 1, #pattern do
        local mark = pattern:sub(position, position)
        if mark ~= "." then
            local bucket = self.by_letter[letter_key(#pattern, position, mark)] or {}
            if #bucket < #pool then pool = bucket end
        end
    end
    local result = {}
    for _, word in ipairs(pool) do
        if self.scores[word] < min_score then break end
        if not used[word] and M.matches(word, pattern) then result[#result + 1] = word end
    end
    return result
end

M.WordIndex = WordIndex
return M
