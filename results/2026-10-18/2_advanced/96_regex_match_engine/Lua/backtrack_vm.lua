local C = require("charset")
local B = {}
B.__index = B
local function captures_copy(captures) return { table.unpack(captures) } end
local function empty_captures(groups)
    local captures = {}
    for i = 1, groups * 2 + 2 do captures[i] = false end
    return captures
end
function B.new(program, flags, groups, text, full)
    return setmetatable({ program = program, flags = flags, groups = groups, text = text, full = full, steps = 0 }, B)
end
function B:execute(initial_pc, start, captures, partial)
    local stack = { { initial_pc, start, captures_copy(captures), {} } }
    while #stack > 0 do
        local state = table.remove(stack)
        local pc, position, stored, visited = state[1], state[2], state[3], state[4]
        while true do
            self.steps = self.steps + 1
            if self.steps > 200000 then error({ category = "regex_limit" }, 0) end
            local ins = self.program[pc + 1]
            local op = ins.op
            if op == "CHAR" or op == "ANY" or op == "CLASS" then
                if not C.test(ins, self.text, position, self.flags) then break end
                pc, position, visited = pc + 1, position + 1, {}
            elseif op == "SPLIT" then
                if visited[pc] then break end
                local updated = {}
                for value in pairs(visited) do updated[value] = true end
                updated[pc] = true
                stack[#stack + 1] = { ins.y, position, captures_copy(stored), updated }
                visited, pc = updated, ins.x
            elseif op == "JMP" then pc = ins.x
            elseif op == "SAVE" then stored[ins.slot + 1], pc = position, pc + 1
            elseif op == "ASSERT" then
                if not C.assertion(ins.kind, self.text, position, self.flags) then break end
                pc = pc + 1
            elseif op == "BACKREF" then
                local first, last = stored[2 * ins.group + 1], stored[2 * ins.group + 2]
                if first == false or last == false or first > last then break end
                local length, success = last - first, true
                if position + length > #self.text then break end
                for i = 0, length - 1 do
                    if not C.equal(self.text:byte(position + i + 1), self.text:byte(first + i + 1), self.flags) then success = false; break end
                end
                if not success then break end
                position, pc = position + length, pc + 1
                if length > 0 then visited = {} end
            elseif op == "LOOK" then
                local next_captures, next_position = self:execute(pc + 1, position, stored, true)
                if ins.kind == "NOT" then
                    if next_captures then break end
                else
                    if not next_captures then break end
                    stored = next_captures
                    if ins.kind == "ATOMIC" then
                        if next_position > position then visited = {} end
                        position = next_position
                    end
                end
                pc = ins.x
            elseif op == "MATCH" then
                if partial or not self.full or position == #self.text then return stored, position end
                break
            end
        end
    end
end
function B:search(start)
    start = start or 0
    local first, last = self.full and 0 or start, self.full and 0 or #self.text
    for position = first, last do
        local result = self:execute(0, position, empty_captures(self.groups), false)
        if result then return result end
    end
end
return B
