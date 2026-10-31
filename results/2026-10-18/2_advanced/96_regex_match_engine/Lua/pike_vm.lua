local C = require("charset")
local P = {}
P.__index = P
local function copy(captures) return { table.unpack(captures) } end
function P.new(program, flags, groups, text, full)
    return setmetatable({ program = program, flags = flags, groups = groups, text = text, full = full, steps = 0 }, P)
end
function P:add(threads, marks, pc, captures, position)
    local pending = { { pc, captures } }
    while #pending > 0 do
        local entry = table.remove(pending)
        local current, stored = entry[1], entry[2]
        if not marks[current] then
            marks[current], self.steps = true, self.steps + 1
            local ins = self.program[current + 1]
            if ins.op == "JMP" then pending[#pending + 1] = { ins.x, stored }
            elseif ins.op == "SPLIT" then
                pending[#pending + 1], pending[#pending + 2] = { ins.y, stored }, { ins.x, stored }
            elseif ins.op == "SAVE" then
                local updated = copy(stored)
                updated[ins.slot + 1] = position
                pending[#pending + 1] = { current + 1, updated }
            elseif ins.op == "ASSERT" then
                if C.assertion(ins.kind, self.text, position, self.flags) then pending[#pending + 1] = { current + 1, stored } end
            else threads[#threads + 1] = { current, copy(stored) } end
        end
    end
end
function P:search(start)
    start = start or 0
    local threads, marks, cursor, matched = {}, {}, start, false
    while true do
        if not matched and (not self.full or cursor == start) then
            local captures = {}
            for i = 1, 2 * self.groups + 2 do captures[i] = false end
            self:add(threads, marks, 0, captures, cursor)
        end
        local following, next_marks = {}, {}
        for _, thread in ipairs(threads) do
            self.steps = self.steps + 1
            local pc, captures = thread[1], thread[2]
            local ins = self.program[pc + 1]
            if ins.op == "MATCH" then
                if not self.full or cursor == #self.text then matched = captures; break end
            elseif C.test(ins, self.text, cursor, self.flags) then
                self:add(following, next_marks, pc + 1, captures, cursor + 1)
            end
        end
        if cursor == #self.text or (#following == 0 and (matched or self.full)) then return matched end
        threads, marks, cursor = following, next_marks, cursor + 1
    end
end
return P
