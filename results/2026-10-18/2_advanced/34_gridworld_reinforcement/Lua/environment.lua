local M = {}
local World = {}
World.__index = World
function World:terminal(cell)
    return self.terminal_index[cell + 1] ~= nil
end
function World:ending(cell)
    return self.kinds:sub(cell + 1, cell + 1) == "G" and "goal" or "pit"
end
function World:move(cell, direction)
    local offsets = {-self.cols, 1, self.cols, -1}
    local target = cell + offsets[direction + 1]
    if self.kinds:sub(target + 1, target + 1) == "#" then
        target = cell
    end
    if self:terminal(target) then
        return target
    end
    for _ = 1, self.wind[cell % self.cols + 1] do
        local above = target - self.cols
        if self.kinds:sub(above + 1, above + 1) == "#" then
            break
        end
        target = above
        if self:terminal(target) then
            break
        end
    end
    return target
end
function M.read_world(path)
    local lines, file = {}, assert(io.open(path))
    for line in file:lines() do
        lines[#lines + 1] = line
    end
    file:close()
    local rows, cols = tonumber(lines[1]:match("%d+")), tonumber(lines[2]:match("%d+"))
    local pieces = {}
    for i = 1, rows do
        pieces[i] = lines[i + 2]
    end
    local world = setmetatable({rows = rows, cols = cols, kinds = table.concat(pieces), wind = {}, rewards = {}, states = {}, terminals = {}, state_index = {}, terminal_index = {}}, World)
    for digit in lines[rows + 3]:match("WIND (.+)"):gmatch("%d") do
        world.wind[#world.wind + 1] = tonumber(digit)
    end
    for value in lines[rows + 4]:gmatch("-?%d+") do
        world.rewards[#world.rewards + 1] = tonumber(value)
    end
    for cell = 0, rows * cols - 1 do
        local kind = world.kinds:sub(cell + 1, cell + 1)
        if kind == "G" or kind == "P" then
            world.terminals[#world.terminals + 1] = cell
            world.terminal_index[cell + 1] = #world.terminals
        elseif kind ~= "#" then
            world.states[#world.states + 1] = cell
            world.state_index[cell + 1] = #world.states
            if kind == "S" then
                world.start, world.start_state = cell, #world.states
            end
        end
    end
    return world
end
local Generator = {}
Generator.__index = Generator
function M.generator(seed)
    return setmetatable({value = seed}, Generator)
end
function Generator:draw()
    self.value = 48271 * self.value % 2147483647
    return self.value
end
local Environment = {}
Environment.__index = Environment
function Environment:slip(state)
    local cell = self.world.states[state]
    return self.world.kinds:sub(cell + 1, cell + 1) == "~" and self.ice_slip or self.floor_slip
end
function Environment:reward(cell)
    local index = self.world.terminal_index[cell + 1]
    return index and self.world.rewards[index] or self.step_reward
end
function Environment:step(generator, state, action)
    local draw, p = generator:draw() % self.slip_total, self:slip(state)
    local direction = draw < self.slip_total - 2 * p and action or draw < self.slip_total - p and (action + 1) % 4 or (action + 3) % 4
    local cell = self.moves[state][direction + 1]
    return cell, self:reward(cell)
end
function M.new(world, step_reward, slip_total, floor_slip, ice_slip)
    local self = setmetatable({world = world, step_reward = step_reward, slip_total = slip_total, floor_slip = floor_slip, ice_slip = ice_slip, moves = {}, transitions = {}}, Environment)
    for state, cell in ipairs(world.states) do
        self.moves[state], self.transitions[state] = {}, {}
        for direction = 0, 3 do
            self.moves[state][direction + 1] = world:move(cell, direction)
        end
        for action = 0, 3 do
            local p, transitions = self:slip(state), {}
            for _, outcome in ipairs({{action, slip_total - 2 * p}, {(action + 1) % 4, p}, {(action + 3) % 4, p}}) do
                if outcome[2] > 0 then
                    transitions[#transitions + 1] = {cell = self.moves[state][outcome[1] + 1], numerator = outcome[2]}
                end
            end
            self.transitions[state][action + 1] = transitions
        end
    end
    return self
end
return M
