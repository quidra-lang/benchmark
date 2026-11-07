local M = {}
local GridState = {}
GridState.__index = GridState

function GridState.new(letters, words)
    local used = {}
    for _, word in ipairs(words) do if word then used[word] = true end end
    return setmetatable({letters = letters, words = words, used = used}, GridState)
end

function GridState:copy()
    local letters, words = {}, {}
    for index, letter in ipairs(self.letters) do letters[index] = letter end
    for index, word in ipairs(self.words) do words[index] = word end
    return GridState.new(letters, words)
end

function GridState:pattern(slot)
    local letters = {}
    for _, cell in ipairs(slot.cells) do letters[#letters + 1] = self.letters[cell] end
    return table.concat(letters)
end

function GridState:assign(slot, word)
    local filled = {}
    for position, cell in ipairs(slot.cells) do
        if self.letters[cell] == "." then self.letters[cell] = word:sub(position, position) filled[#filled + 1] = cell end
    end
    self.words[slot.index], self.used[word] = word, true
    return filled
end

function GridState:unassign(slot, filled)
    for _, cell in ipairs(filled) do self.letters[cell] = "." end
    self.used[self.words[slot.index]], self.words[slot.index] = nil, false
end

local Attempt = {}
Attempt.__index = Attempt

function Attempt.new(layout, index, initial, min_score, budget)
    local failures = {}
    for position = 1, #layout.slots do failures[position] = 0 end
    return setmetatable({layout = layout, index = index, state = initial:copy(), min_score = min_score,
        budget = budget, nodes = 0, backtracks = 0, prunes = 0, dead_ends = 0, sequence = {}, max_depth = 0,
        best = initial:copy(), failures = failures, trace = {}}, Attempt)
end

function Attempt:candidates(slot)
    return self.index:candidates(self.state:pattern(slot), self.min_score, self.state.used)
end

function Attempt:choose_slot()
    local chosen, chosen_words
    for _, slot in ipairs(self.layout.slots) do
        if not self.state.words[slot.index] then
            local words = self:candidates(slot)
            if chosen == nil or #words < #chosen_words then chosen, chosen_words = slot, words end
        end
    end
    return chosen, chosen_words
end

function Attempt:wiped_out_slot(slot)
    for _, index in ipairs(slot.crossings) do
        local crossing = self.layout.slots[index]
        if not self.state.words[index] and #self:candidates(crossing) == 0 then return crossing end
    end
    return nil
end

function Attempt:search()
    local slot, words = self:choose_slot()
    if slot == nil then return "complete" end
    if #words == 0 then
        self.dead_ends, self.failures[slot.index] = self.dead_ends + 1, self.failures[slot.index] + 1
        return "fail"
    end
    for _, word in ipairs(words) do
        if self.nodes == self.budget then return "abort" end
        self.nodes = self.nodes + 1
        local filled = self.state:assign(slot, word)
        self.sequence[#self.sequence + 1] = slot
        local wiped = self:wiped_out_slot(slot)
        if self.nodes <= 10 then self.trace[#self.trace + 1] = slot.label .. "=" .. word .. (wiped and "!" or "") end
        local result
        if wiped then
            self.prunes, self.failures[wiped.index] = self.prunes + 1, self.failures[wiped.index] + 1
            result = "fail"
        else
            if #self.sequence > self.max_depth then self.max_depth, self.best = #self.sequence, self.state:copy() end
            result = self:search()
        end
        if result ~= "fail" then return result end
        self.state:unassign(slot, filled)
        table.remove(self.sequence)
        self.backtracks = self.backtracks + 1
    end
    return "fail"
end

function Attempt:run() self.outcome = ({complete = "filled", fail = "unfillable", abort = "budget"})[self:search()] end
function Attempt:final_state() return self.outcome == "filled" and self.state or self.best end

M.GridState, M.Attempt = GridState, Attempt
return M
