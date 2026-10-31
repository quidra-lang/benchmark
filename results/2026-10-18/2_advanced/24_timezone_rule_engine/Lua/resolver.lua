local day_rules = require("day_rules")
local M = {}
function M.period(start, offset, dst, abbreviation) return {start = start, offset = offset, dst = dst, abbreviation = abbreviation} end
local Timeline = {}
Timeline.__index = Timeline
function Timeline.new(periods) return setmetatable({periods = periods}, Timeline) end
function Timeline:index_at(time)
    local low, high = 1, #self.periods + 1
    while low < high do
        local middle = (low + high) // 2
        if middle <= #self.periods and self.periods[middle].start <= time then low = middle + 1 else high = middle end
    end
    return low - 1
end
function Timeline:period_at(time) return self.periods[self:index_at(time)] end
function Timeline:end_of(index) return self.periods[index + 1] and self.periods[index + 1].start or day_rules.POS_INFINITY end
function Timeline:nearby(first_local, last_local) return self:index_at(first_local - 57600), self:index_at(last_local + 57600) end
function Timeline:candidates(local_time)
    local found = {}
    local first, last = self:nearby(local_time, local_time)
    for index = first, last do
        local time = local_time - self.periods[index].offset
        if self.periods[index].start <= time and time < self:end_of(index) then found[#found + 1] = index end
    end
    return found
end
function Timeline:skipping_transition(local_time)
    local first, last = self:nearby(local_time, local_time)
    for index = math.max(2, first), last do
        local start = self.periods[index].start
        if start + self.periods[index - 1].offset <= local_time and local_time < start + self.periods[index].offset then return index end
    end
end
M.Timeline = Timeline
return M
