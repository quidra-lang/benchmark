local DIRECTIONS = { "u", "d", "l", "r" }
local TURNS = {
  ROT90 = "rlud", ROT180 = "durl", ROT270 = "lrdu", FLIPH = "udrl", FLIPV = "dulr",
}
local LEVEL_CHARACTERS = "#-.$*@+"
local STEP_CHARACTERS = "udlrUDLR"
local COMMANDS = {
  IMPORT = { "text" }, VALID = {}, INFO = {}, SHOW = {}, EXPORT = {},
  MOVE = { "steps" }, PUSH = { "number", "number", "direction" },
  BRING = { "number", "number", "number", "number" }, PATH = { "number", "number" },
  UNDO = { "number" }, REDO = { "number" }, RESET = {}, STATUS = {}, HISTORY = {},
  BOXES = {}, REACH = {}, DEADSQUARES = {}, DEADLOCK = {}, BOUND = {},
  SAVE = { "name" }, RESTORE = { "name" }, CHECK = { "steps" },
  SOLVE = { "number" }, HINT = { "number" }, PLAY = {}, TRANSFORM = { "transform" },
}

local function split(text, separator)
  local parts, start = {}, 1
  while true do
    local stop = text:find(separator, start, true)
    parts[#parts + 1] = text:sub(start, stop and stop - 1 or #text)
    if not stop then return parts end
    start = stop + 1
  end
end

local function contains(items, item)
  for _, value in ipairs(items) do
    if value == item then return true end
  end
  return false
end

local function copy(items)
  return { table.unpack(items) }
end

local function count(set)
  local result = 0
  for _, value in pairs(set) do
    if value then result = result + 1 end
  end
  return result
end

local function first(set, size)
  for cell = 1, size do
    if set[cell] then return cell end
  end
end

local function decode(text, allowed)
  local parts, index = {}, 1
  while index <= #text do
    local start = index
    while index <= #text and text:sub(index, index):match("%d") do index = index + 1 end
    local digits = text:sub(start, index - 1)
    if #digits > 2 or digits:sub(1, 1) == "0" or index > #text then return nil end
    local letter = text:sub(index, index)
    if not allowed:find(letter, 1, true) then return nil end
    parts[#parts + 1] = letter:rep(digits == "" and 1 or tonumber(digits))
    index = index + 1
  end
  return table.concat(parts)
end

local function encode(text)
  local parts, index = {}, 1
  while index <= #text do
    local stop = index + 1
    while stop <= #text and text:sub(stop, stop) == text:sub(index, index) do stop = stop + 1 end
    local run = stop - index
    parts[#parts + 1] = (run > 1 and tostring(run) or "") .. text:sub(index, index)
    index = stop
  end
  return table.concat(parts)
end

local function push_count(letters)
  local _, pushes = letters:gsub("[UDLR]", "")
  return pushes
end

local function move_box(boxes, source, destination)
  local result = {}
  for index, box in ipairs(boxes) do result[index] = box == source and destination or box end
  table.sort(result)
  return result
end

local function same_position(a, b)
  if a.player ~= b.player or #a.boxes ~= #b.boxes then return false end
  for index, box in ipairs(a.boxes) do
    if box ~= b.boxes[index] then return false end
  end
  return true
end

local function fail(message)
  error({ message = message }, 0)
end

local Level = {}
Level.__index = Level

function Level.new(height, width, walls, goals, interior)
  local self = setmetatable({
    height = height, width = width, size = height * width, walls = walls, goals = goals,
    interior = interior, offsets = { u = -width, d = width, l = -1, r = 1 },
    goal_cells = {}, distances = {}, dead = {},
  }, Level)
  for cell = 1, self.size do
    if goals[cell] then self.goal_cells[#self.goal_cells + 1] = cell end
  end
  return self
end

function Level:cell_text(cell)
  return ((cell - 1) // self.width + 1) .. " " .. ((cell - 1) % self.width + 1)
end

function Level:analyze()
  self.distances, self.dead = {}, {}
  for index, goal in ipairs(self.goal_cells) do
    local distance, queue = { [goal] = 0 }, { goal }
    local head = 1
    while head <= #queue do
      local cell = queue[head]
      head = head + 1
      for _, direction in ipairs(DIRECTIONS) do
        local offset = self.offsets[direction]
        local box = cell - offset
        if self.interior[box] and self.interior[box - offset] and distance[box] == nil then
          distance[box] = distance[cell] + 1
          queue[#queue + 1] = box
        end
      end
    end
    self.distances[index] = distance
  end
  for cell = 1, self.size do
    if self.interior[cell] and self:goal_distance(cell) == nil then self.dead[cell] = true end
  end
end

function Level:goal_distance(cell)
  local best
  for _, distance in ipairs(self.distances) do
    if distance[cell] ~= nil and (best == nil or distance[cell] < best) then best = distance[cell] end
  end
  return best
end

function Level:on_goals(boxes)
  local result = 0
  for _, box in ipairs(boxes) do
    if self.goals[box] then result = result + 1 end
  end
  return result
end

function Level:solved(boxes)
  return self:on_goals(boxes) == #boxes
end

function Level:reachable(player, boxes)
  local seen, queue, head = { [player] = true }, { player }, 1
  while head <= #queue do
    local cell = queue[head]
    head = head + 1
    for _, direction in ipairs(DIRECTIONS) do
      local neighbor = cell + self.offsets[direction]
      if self.interior[neighbor] and not seen[neighbor] and not contains(boxes, neighbor) then
        seen[neighbor] = true
        queue[#queue + 1] = neighbor
      end
    end
  end
  return seen
end

function Level:representative(player, boxes)
  return first(self:reachable(player, boxes), self.size)
end

function Level:walk_path(start, target, boxes)
  local came, queue, head = { [start] = true }, { start }, 1
  while head <= #queue do
    local cell = queue[head]
    head = head + 1
    for _, direction in ipairs(DIRECTIONS) do
      local neighbor = cell + self.offsets[direction]
      if self.interior[neighbor] and not contains(boxes, neighbor) and not came[neighbor] then
        came[neighbor] = { cell, direction }
        queue[#queue + 1] = neighbor
      end
    end
  end
  local reversed = {}
  while target ~= start do
    local entry = came[target]
    reversed[#reversed + 1] = entry[2]
    target = entry[1]
  end
  local path = {}
  for index = #reversed, 1, -1 do path[#path + 1] = reversed[index] end
  return table.concat(path)
end

function Level:step(position, direction)
  local offset = self.offsets[direction]
  local target = position.player + offset
  if self.walls[target] then return nil, "wall" end
  if not contains(position.boxes, target) then
    return { player = target, boxes = position.boxes }, direction
  end
  local beyond = target + offset
  if self.walls[beyond] or contains(position.boxes, beyond) then return nil, "blocked" end
  return { player = target, boxes = move_box(position.boxes, target, beyond) }, direction:upper()
end

function Level:pushable(box, direction, boxes, reachable)
  local offset = self.offsets[direction]
  return reachable[box - offset] and self.interior[box + offset] and not contains(boxes, box + offset)
end

function Level:side_blocked(box, a, b, boxes, assumed)
  if self.walls[a] or self.walls[b] or assumed[a] or assumed[b] then return true end
  if self.dead[a] and self.dead[b] then return true end
  local extended = {}
  for cell in pairs(assumed) do extended[cell] = true end
  extended[box] = true
  return (contains(boxes, a) and self:frozen(a, boxes, extended))
    or (contains(boxes, b) and self:frozen(b, boxes, extended))
end

function Level:frozen(box, boxes, assumed)
  return self:side_blocked(box, box - 1, box + 1, boxes, assumed)
    and self:side_blocked(box, box - self.width, box + self.width, boxes, assumed)
end

function Level:has_frozen_box(boxes)
  for _, box in ipairs(boxes) do
    if not self.goals[box] and self:frozen(box, boxes, {}) then return true end
  end
  return false
end

function Level:rows(position, dead_map)
  local rows = {}
  for row = 1, self.height do
    local symbols = {}
    for column = 1, self.width do
      local cell = (row - 1) * self.width + column
      local symbol
      if self.walls[cell] then symbol = "#"
      elseif dead_map then symbol = self.goals[cell] and "." or (self.dead[cell] and "x" or "-")
      elseif cell == position.player then symbol = self.goals[cell] and "+" or "@"
      elseif contains(position.boxes, cell) then symbol = self.goals[cell] and "*" or "$"
      else symbol = self.goals[cell] and "." or "-" end
      symbols[column] = symbol
    end
    rows[row] = table.concat(symbols)
  end
  return rows
end

function Level:map_cell(kind, cell)
  local row, column = (cell - 1) // self.width, (cell - 1) % self.width
  if kind == "ROT90" then return column * self.height + self.height - row end
  if kind == "ROT180" then return (self.height - 1 - row) * self.width + self.width - column end
  if kind == "ROT270" then return (self.width - 1 - column) * self.height + row + 1 end
  if kind == "FLIPH" then return row * self.width + self.width - column end
  return (self.height - 1 - row) * self.width + column + 1
end

function Level:map_position(kind, position)
  local boxes = {}
  for index, box in ipairs(position.boxes) do boxes[index] = self:map_cell(kind, box) end
  table.sort(boxes)
  return { player = self:map_cell(kind, position.player), boxes = boxes }
end

local function build_level(rows)
  local height, width = #rows, #rows[1]
  local walls, goals, boxes, players = {}, {}, {}, {}
  for row, text in ipairs(rows) do
    for column = 1, width do
      local cell, symbol = (row - 1) * width + column, text:sub(column, column)
      if symbol == "#" then walls[cell] = true end
      if symbol == "." or symbol == "*" or symbol == "+" then goals[cell] = true end
      if symbol == "$" or symbol == "*" then boxes[#boxes + 1] = cell end
      if symbol == "@" or symbol == "+" then players[#players + 1] = cell end
    end
  end
  local interior = {}
  if #players == 1 then
    local queue, head = { players[1] }, 1
    interior[players[1]] = true
    while head <= #queue do
      local cell = queue[head]
      head = head + 1
      local row, column = (cell - 1) // width, (cell - 1) % width
      for _, delta in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
        local r, c = row + delta[1], column + delta[2]
        local neighbor = r * width + c + 1
        if r >= 0 and r < height and c >= 0 and c < width and not walls[neighbor] and not interior[neighbor] then
          interior[neighbor] = true
          queue[#queue + 1] = neighbor
        end
      end
    end
  end
  local level = Level.new(height, width, walls, goals, interior)
  if #players ~= 1 then level.reason = "players " .. #players
  elseif #boxes == 0 then level.reason = "no boxes"
  elseif #boxes ~= #level.goal_cells then level.reason = "boxes " .. #boxes .. " goals " .. #level.goal_cells
  else
    for cell = 1, level.size do
      local row, column = (cell - 1) // width, (cell - 1) % width
      if interior[cell] and (row == 0 or row == height - 1 or column == 0 or column == width - 1) then
        level.reason = "open " .. level:cell_text(cell)
        break
      end
    end
    if not level.reason then
      for cell = 1, level.size do
        if (goals[cell] or contains(boxes, cell)) and not interior[cell] then
          level.reason = "outside " .. level:cell_text(cell)
          break
        end
      end
    end
  end
  if not level.reason then level:analyze() end
  return level, { player = players[1], boxes = boxes }
end

local function state_key(boxes, representative)
  return table.concat(boxes, ",") .. ":" .. representative
end

local function push_search(level, start, fixed, target, pruning, limit)
  local representative = level:representative(start.player, start.boxes)
  local nodes = { { boxes = start.boxes, representative = representative } }
  local known = { [state_key(start.boxes, representative)] = true }
  local expanded = 0
  while expanded < #nodes do
    if expanded == limit then return { outcome = "limit", expanded = expanded, states = #nodes } end
    local parent = expanded + 1
    local node = nodes[parent]
    expanded = expanded + 1
    local reachable = level:reachable(node.representative, node.boxes)
    for _, box in ipairs(node.boxes) do
      if not contains(fixed, box) then
        for _, direction in ipairs(DIRECTIONS) do
          if level:pushable(box, direction, node.boxes, reachable) then
            local destination = box + level.offsets[direction]
            local boxes = move_box(node.boxes, box, destination)
            if not pruning or (not level.dead[destination] and not level:has_frozen_box(boxes)) then
              local next_rep = level:representative(box, boxes)
              local key = state_key(boxes, next_rep)
              if not known[key] then
                known[key] = true
                nodes[#nodes + 1] = { boxes = boxes, representative = next_rep, parent = parent, box = box, direction = direction }
                if (target and destination == target) or (not target and level:solved(boxes)) then
                  local reversed, index = {}, #nodes
                  while nodes[index].parent do
                    reversed[#reversed + 1] = nodes[index]
                    index = nodes[index].parent
                  end
                  local position, pieces = start, {}
                  for i = #reversed, 1, -1 do
                    local push = reversed[i]
                    local offset = level.offsets[push.direction]
                    pieces[#pieces + 1] = level:walk_path(position.player, push.box - offset, position.boxes)
                    pieces[#pieces + 1] = push.direction:upper()
                    position = { player = push.box, boxes = move_box(position.boxes, push.box, push.box + offset) }
                  end
                  return { outcome = "found", expanded = expanded, states = #nodes, notation = table.concat(pieces) }
                end
              end
            end
          end
        end
      end
    end
  end
  return { outcome = "no solution", expanded = expanded, states = #nodes }
end

local Game = {}
Game.__index = Game

function Game:emit(...)
  local parts = { ... }
  for index, part in ipairs(parts) do parts[index] = tostring(part) end
  self.output[#self.output + 1] = table.concat(parts, " ")
end

function Game:load(rows)
  self.level, self.initial = build_level(rows)
  self.current = self.initial
  self.history, self.redo_list, self.snapshots, self.solution = "", "", {}, nil
end

function Game:simulate(directions)
  local position, letters = self.current, {}
  for index = 1, #directions do
    local next_position, letter = self.level:step(position, directions:sub(index, index):lower())
    if not next_position then
      return position, table.concat(letters), "step " .. index .. " " .. letter
    end
    position, letters[#letters + 1] = next_position, letter
  end
  return position, table.concat(letters)
end

function Game:take_steps(directions)
  local position, letters, failure = self:simulate(directions)
  self.current, self.history = position, self.history .. letters
  if #letters > 0 then self.redo_list = "" end
  return letters, failure
end

function Game:cell(arguments, index)
  return (tonumber(arguments[index]) - 1) * self.level.width + tonumber(arguments[index + 1])
end

function Game:progress(boxes)
  local goals = self.level:on_goals(boxes)
  return "goals " .. goals .. "/" .. #boxes .. (goals == #boxes and " solved" or "")
end

function Game:search_solution(limit)
  if self.level:solved(self.current.boxes) then return "already solved" end
  local result = push_search(self.level, self.current, {}, nil, true, limit)
  local counts = "expanded " .. result.expanded .. " states " .. result.states
  if result.outcome ~= "found" then return result.outcome .. " " .. counts end
  local notation = result.notation
  return "solution pushes " .. push_count(notation) .. " moves " .. #notation .. " " .. counts, notation
end

local function counted(label, letters)
  return label .. " " .. #letters .. (#letters > 0 and " " .. letters or "")
end

local function turn_letters(letters, kind)
  return (letters:gsub(".", function(letter)
    local index = ("udlr"):find(letter:lower(), 1, true)
    local turned = TURNS[kind]:sub(index, index)
    return letter == letter:upper() and turned:upper() or turned
  end))
end

function Game:process(name, a)
  local level, position = self.level, self.current
  if name == "IMPORT" then
    local rows = {}
    for _, part in ipairs(split(a[1], "|")) do
      local row = decode(part, LEVEL_CHARACTERS)
      if not row then fail("bad level") end
      rows[#rows + 1] = row
    end
    if #rows > 10 or #rows[1] < 1 or #rows[1] > 10 then fail("bad level") end
    for _, row in ipairs(rows) do if #row ~= #rows[1] then fail("bad level") end end
    self:load(rows)
    self:emit("loaded", #rows .. "x" .. #rows[1])
  elseif name == "VALID" then self:emit(level.reason and "invalid " .. level.reason or "valid")
  elseif name == "INFO" then
    self:emit("size", level.height .. "x" .. level.width, "walls", count(level.walls), "cells", count(level.interior), "boxes", #position.boxes, "dead", count(level.dead))
  elseif name == "SHOW" then
    for _, row in ipairs(level:rows(position)) do self:emit(row) end
  elseif name == "EXPORT" then
    local rows = level:rows(position)
    for index, row in ipairs(rows) do rows[index] = encode(row) end
    self:emit("level", table.concat(rows, "|"))
  elseif name == "MOVE" then
    local letters, failure = self:take_steps(decode(a[1], STEP_CHARACTERS))
    if #letters > 0 then self:emit("moved", letters) end
    if failure then fail(failure) end
  elseif name == "PUSH" then
    local box, direction = self:cell(a, 1), a[3]
    local offset = level.offsets[direction]
    if not contains(position.boxes, box) then fail("no box") end
    if not level.interior[box + offset] or contains(position.boxes, box + offset) then fail("blocked") end
    if not level:reachable(position.player, position.boxes)[box - offset] then fail("unreachable") end
    local letters = self:take_steps(level:walk_path(position.player, box - offset, position.boxes) .. direction)
    self:emit("pushed", letters)
  elseif name == "BRING" then
    local source, target = self:cell(a, 1), self:cell(a, 3)
    if not contains(position.boxes, source) then fail("no box") end
    if source == target then self:emit("brought", 0); return end
    local fixed = {}
    for _, box in ipairs(position.boxes) do if box ~= source then fixed[#fixed + 1] = box end end
    local result = push_search(level, position, fixed, target, false)
    if result.outcome ~= "found" then fail("no route") end
    self:take_steps(result.notation)
    self:emit("brought", push_count(result.notation), result.notation)
  elseif name == "PATH" then
    local target = self:cell(a, 1)
    if not level:reachable(position.player, position.boxes)[target] then fail("unreachable") end
    local letters = self:take_steps(level:walk_path(position.player, target, position.boxes))
    self:emit(counted("path", letters))
  elseif name == "UNDO" then
    if #self.history == 0 then fail("nothing to undo") end
    local n = math.min(tonumber(a[1]), #self.history)
    for _ = 1, n do
      local letter = self.history:sub(-1)
      self.history = self.history:sub(1, -2)
      local direction, player = letter:lower(), self.current.player
      local offset, boxes = level.offsets[direction], self.current.boxes
      if letter ~= direction then boxes = move_box(boxes, player + offset, player) end
      self.current = { player = player - offset, boxes = boxes }
      self.redo_list = self.redo_list .. direction
    end
    self:emit("undone", n)
  elseif name == "REDO" then
    if #self.redo_list == 0 then fail("nothing to redo") end
    local n = math.min(tonumber(a[1]), #self.redo_list)
    for _ = 1, n do
      local direction = self.redo_list:sub(-1)
      self.redo_list = self.redo_list:sub(1, -2)
      local next_position, letter = level:step(self.current, direction)
      self.current, self.history = next_position, self.history .. letter
    end
    self:emit("redone", n)
  elseif name == "RESET" then
    self.current, self.history, self.redo_list = self.initial, "", ""
    self:emit("reset")
  elseif name == "STATUS" then
    self:emit("moves", #self.history, "pushes", push_count(self.history), self:progress(position.boxes))
  elseif name == "HISTORY" then self:emit(counted("history", self.history))
  elseif name == "BOXES" then
    local reachable = level:reachable(position.player, position.boxes)
    self:emit("boxes", #position.boxes)
    for _, box in ipairs(position.boxes) do
      local directions = ""
      for _, direction in ipairs(DIRECTIONS) do
        if level:pushable(box, direction, position.boxes, reachable) then directions = directions .. direction end
      end
      local distance = level:goal_distance(box)
      self:emit("box", level:cell_text(box), distance == nil and "dead" or distance, directions == "" and "-" or directions)
    end
  elseif name == "REACH" then
    local reachable = level:reachable(position.player, position.boxes)
    self:emit("reach", count(reachable), "first", level:cell_text(first(reachable, level.size)))
  elseif name == "DEADSQUARES" then
    self:emit("dead", count(level.dead))
    for _, row in ipairs(level:rows(position, true)) do self:emit(row) end
  elseif name == "DEADLOCK" then
    for _, box in ipairs(position.boxes) do
      if level.dead[box] then self:emit("deadlock dead", level:cell_text(box)); return end
    end
    for _, box in ipairs(position.boxes) do
      if not level.goals[box] and level:frozen(box, position.boxes, {}) then
        self:emit("deadlock frozen", level:cell_text(box)); return
      end
    end
    self:emit("no deadlock")
  elseif name == "BOUND" then
    local best, best_total, order, used = nil, nil, {}, {}
    local function assign(index, total)
      if index > #position.boxes then
        if best_total == nil or total < best_total then best, best_total = copy(order), total end
        return
      end
      for goal = 1, #level.goal_cells do
        local distance = level.distances[goal][position.boxes[index]]
        if not used[goal] and distance ~= nil then
          used[goal], order[index] = true, goal
          assign(index + 1, total + distance)
          used[goal] = nil
        end
      end
    end
    assign(1, 0)
    if not best then self:emit("bound none"); return end
    self:emit("bound", best_total)
    for index, box in ipairs(position.boxes) do
      local goal = best[index]
      self:emit("box", level:cell_text(box), "goal", level:cell_text(level.goal_cells[goal]), "pushes", level.distances[goal][box])
    end
  elseif name == "SAVE" then
    self.snapshots[a[1]] = { position = position, history = self.history }
    self:emit("saved", a[1], "moves", #self.history)
  elseif name == "RESTORE" then
    local snapshot = self.snapshots[a[1]]
    if not snapshot then fail("no snapshot " .. a[1]) end
    self.current, self.history, self.redo_list = snapshot.position, snapshot.history, ""
    self:emit("restored", a[1], "moves", #self.history)
  elseif name == "CHECK" then
    local result, letters, failure = self:simulate(decode(a[1], STEP_CHARACTERS))
    if failure then self:emit("check fail", failure)
    else self:emit("check ok moves", #letters, "pushes", push_count(letters), self:progress(result.boxes)) end
  elseif name == "SOLVE" or name == "HINT" then
    local summary, notation = self:search_solution(tonumber(a[1]))
    if name == "SOLVE" then
      self:emit(summary)
      self.solution = notation and { notation = notation, position = position } or nil
      if notation then self:emit(notation) end
    elseif not notation then self:emit(summary)
    else
      local first_push = notation:find("[UDLR]")
      local part = notation:sub(1, first_push)
      self:take_steps(part)
      self:emit("hint", part)
    end
  elseif name == "PLAY" then
    if not self.solution or not same_position(position, self.solution.position) then fail("no solution") end
    local notation = self.solution.notation
    self:take_steps(notation)
    self:emit("played pushes", push_count(notation), "moves", #notation)
  elseif name == "TRANSFORM" then
    local kind, walls, goals, interior = a[1], {}, {}, {}
    for cell = 1, level.size do
      local moved = level:map_cell(kind, cell)
      walls[moved], goals[moved], interior[moved] = level.walls[cell], level.goals[cell], level.interior[cell]
    end
    local rotated = kind == "ROT90" or kind == "ROT270"
    self.level = Level.new(rotated and level.width or level.height, rotated and level.height or level.width, walls, goals, interior)
    self.level:analyze()
    self.initial, self.current = level:map_position(kind, self.initial), level:map_position(kind, position)
    self.history, self.redo_list = turn_letters(self.history, kind), turn_letters(self.redo_list, kind)
    for _, snapshot in pairs(self.snapshots) do
      snapshot.position, snapshot.history = level:map_position(kind, snapshot.position), turn_letters(snapshot.history, kind)
    end
    if self.solution then
      self.solution.position, self.solution.notation = level:map_position(kind, self.solution.position), turn_letters(self.solution.notation, kind)
    end
    self:emit("transformed", self.level.height .. "x" .. self.level.width)
  end
end

local function valid_argument(kind, text)
  if kind == "number" then
    return #text <= 6 and text:match("^%d+$") ~= nil and (#text == 1 or text:sub(1, 1) ~= "0")
  elseif kind == "steps" then return decode(text, STEP_CHARACTERS) ~= nil
  elseif kind == "direction" then return #text == 1 and ("udlr"):find(text, 1, true) ~= nil
  elseif kind == "name" then return #text <= 8 and text:match("^[a-z]+$") ~= nil
  elseif kind == "transform" then return TURNS[text] ~= nil end
  return true
end

function Game:execute(words, rows)
  local ok, problem = pcall(function()
    local name = words[1]
    if name == "LOAD" then
      local width = tonumber(words[3])
      for index, row in ipairs(rows) do
        if #row ~= width or row:find("[^#%-%.$*@+]") then fail("bad row " .. index) end
      end
      self:load(rows)
      self:emit("loaded", #rows .. "x" .. width)
      return
    end
    local kinds = COMMANDS[name]
    if not kinds then fail("unknown command " .. name) end
    if #words ~= #kinds + 1 then fail("bad arguments") end
    local arguments = {}
    for index, kind in ipairs(kinds) do
      arguments[index] = words[index + 1]
      if not valid_argument(kind, arguments[index]) then fail("bad arguments") end
    end
    if name ~= "IMPORT" and name ~= "VALID" then
      if self.level.reason then fail("invalid level") end
      local cells = name == "BRING" and 2 or ((name == "PUSH" or name == "PATH") and 1 or 0)
      for index = 1, cells * 2, 2 do
        local row, column = tonumber(arguments[index]), tonumber(arguments[index + 1])
        if row < 1 or row > self.level.height or column < 1 or column > self.level.width then fail("bad value") end
      end
      if (name == "UNDO" or name == "REDO") and tonumber(arguments[1]) < 1 then fail("bad value") end
      if (name == "SOLVE" or name == "HINT") and (tonumber(arguments[1]) < 1 or tonumber(arguments[1]) > 100000) then fail("bad value") end
    end
    self:process(name, arguments)
  end)
  if not ok then
    if type(problem) ~= "table" then error(problem, 0) end
    self:emit("error:", problem.message)
  end
end

local function main()
  local header = split(io.read("l"), " ")
  local rows = {}
  for index = 1, tonumber(header[1]) do rows[index] = io.read("l") end
  local game = setmetatable({ output = {} }, Game)
  game:load(rows)
  local commands = tonumber(io.read("l"))
  for _ = 1, commands do
    local words, loaded = split(io.read("l"), " "), {}
    if words[1] == "LOAD" then
      for index = 1, tonumber(words[2]) do loaded[index] = io.read("l") end
    end
    game:execute(words, loaded)
  end
  io.write(table.concat(game.output, "\n"), "\n")
end

main()
