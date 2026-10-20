local directionNames = {"north", "south", "east", "west", "up", "down"}
local directions = {}
for index, name in ipairs(directionNames) do directions[name], directions[name:sub(1, 1)] = index, index end
local aliases = {
    go = "go walk run", look = "look l", examine = "examine x inspect read", take = "take get grab", drop = "drop discard",
    put = "put insert place", inventory = "inventory inv i", open = "open", close = "close shut", unlock = "unlock", lock = "lock",
    use = "use apply", light = "light ignite", extinguish = "extinguish douse snuff", wait = "wait z", score = "score", save = "save",
    restore = "restore load", verbose = "verbose", brief = "brief",
}
local verbs = {}
for verb, names in pairs(aliases) do for word in names:gmatch("[^ ]+") do verbs[word] = verb end end
local noObjects = {look = true, inventory = true, wait = true, score = true, save = true, restore = true, verbose = true, brief = true}
local actions = {go = true, take = true, drop = true, put = true, open = true, close = true, unlock = true, lock = true,
    use = true, light = true, extinguish = true, wait = true}
local function fail(reason)
    error({command_error = true, lines = type(reason) == "table" and reason or {reason}}, 0)
end
local function words(line)
    local result = {}
    for word in line:gmatch("[^ ]+") do result[#result + 1] = word end
    return result
end
local function normalized(line)
    line = line:gsub("[A-Z]", function(letter) return string.char(letter:byte() + 32) end)
    local result = {}
    for word in line:gmatch("[^ ]+") do
        if word ~= "the" and word ~= "a" and word ~= "an" then result[#result + 1] = word end
    end
    return result
end
local function slice(values, first, last)
    local result = {}
    for i = first, last or #values do result[#result + 1] = values[i] end
    return result
end
local function append(result, values) for _, value in ipairs(values) do result[#result + 1] = value end end
local function copy(values)
    local result = {}
    for key, value in pairs(values) do result[key] = value end
    return result
end
local function asciiLess(a, b)
    for i = 1, math.min(#a, #b) do if a:byte(i) ~= b:byte(i) then return a:byte(i) < b:byte(i) end end
    return #a < #b
end
local function only(phrase, word) return #phrase == 1 and phrase[1] == word end
local function place(kind, id) return {kind = kind, id = id, key = kind .. ":" .. (id or "")} end
local function newState()
    return {room = "", places = {}, containers = {}, fuel = {}, lit = {}, exits = {}, flags = {}, visited = {},
        bonus = 0, moves = 0, darkness = 0, ended = "none"}
end
local function copyState(state)
    local result = copy(state)
    for _, field in ipairs({"places", "containers", "fuel", "lit", "flags", "visited"}) do result[field] = copy(state[field]) end
    result.exits = {}
    for room, exits in pairs(state.exits) do result.exits[room] = copy(exits) end
    return result
end

local Adventure = {}
Adventure.__index = Adventure
function Adventure.new(definitions)
    local self = setmetatable({rooms = {}, items = {}, ids = {}, rules = {}, enterRules = {}, vocabulary = {},
        state = newState(), verbose = false}, Adventure)
    for _, line in ipairs(definitions) do self:define(line) end
    for id, item in pairs(self.items) do
        self.ids[#self.ids + 1] = id
        for word in pairs(item.nouns) do self.vocabulary[word] = true end
        for word in pairs(item.nameWords) do self.vocabulary[word] = true end
    end
    table.sort(self.ids, asciiLess)
    self.state.visited[self.state.room] = true
    return self
end
function Adventure:setExit(room, direction, destination, key)
    if not self.state.exits[room] then self.state.exits[room] = {} end
    self.state.exits[room][direction] = {destination = destination, key = key, locked = key ~= nil}
end
function Adventure:define(line)
    local w = words(line)
    local kind, id = w[1], w[2]
    local function text(first) return table.concat(w, " ", first) end
    if kind == "ROOM" then
        local dark = w[3] == "DARK"
        self.rooms[id] = {name = text(dark and 4 or 3), dark = dark, description = {}}
    elseif kind == "DESC" then
        local description = self.rooms[id].description
        description[#description + 1] = text(3)
    elseif kind == "EXIT" then
        self:setExit(id, directions[w[3]], w[4], #w > 4 and w[6] or nil)
    elseif kind == "ITEM" then
        local item = {name = "", weight = tonumber(w[4], 10), points = 0, light = false, fixed = false,
            nouns = {[id] = true}, nameWords = {}, details = {}}
        if w[3] == "PLAYER" then self.state.places[id] = place("player")
        elseif w[3] == "NOWHERE" then self.state.places[id] = place("nowhere")
        else self.state.places[id] = place("room", w[3]) end
        self.state.containers[id], self.state.fuel[id], self.state.lit[id] = "open", 0, false
        local index = 5
        if w[index] == "TREASURE" then item.points = tonumber(w[index + 1], 10); index = index + 2 end
        if w[index] == "LIGHT" then item.light = true; self.state.fuel[id] = tonumber(w[index + 1], 10); index = index + 2 end
        if w[index] == "CONTAINER" then
            item.capacity = tonumber(w[index + 1], 10); index = index + 2
            if w[index] == "CLOSED" then self.state.containers[id] = "closed"; index = index + 1 end
            if w[index] == "LOCKED" then item.key = w[index + 1]; self.state.containers[id] = "locked"; index = index + 2 end
        end
        if w[index] == "FIXED" then item.fixed = true; index = index + 1 end
        item.name = text(index)
        for i = index, #w do item.nameWords[w[i]] = true end
        self.items[id] = item
    elseif kind == "INSIDE" then self.state.places[id] = place("inside", w[3])
    elseif kind == "ALIAS" then self.items[id].nouns[w[3]] = true
    elseif kind == "DETAIL" then
        local details = self.items[id].details
        details[#details + 1] = text(3)
    elseif kind == "RULE" or kind == "ENTER" then
        local index = kind == "RULE" and 4 or 3
        local flag, whenOn = nil, true
        if w[index] == "IF" or w[index] == "UNLESS" then
            whenOn, flag = w[index] == "IF", w[index + 1]; index = index + 2
        end
        local effect = {kind = w[index]}
        index = index + 1
        if effect.kind == "MESSAGE" then effect.text = text(index)
        elseif effect.kind == "OPEN" then effect.room, effect.direction, effect.destination = w[index], directions[w[index + 1]], w[index + 2]
        elseif effect.kind == "REMOVE" then effect.item, effect.place = w[index], place("nowhere")
        elseif effect.kind == "ADD" then effect.item, effect.place = w[index], place("room", w[index + 1])
        elseif effect.kind == "SET" or effect.kind == "CLEAR" then effect.flag = w[index]
        else effect.amount = tonumber(w[index], 10) end
        local rule = {first = id, second = kind == "RULE" and w[3] or nil, flag = flag, whenOn = whenOn, effect = effect}
        local target = kind == "RULE" and self.rules or self.enterRules
        target[#target + 1] = rule
    elseif kind == "TROPHY" then self.trophy = id
    elseif kind == "START" then self.state.room = id
    elseif kind == "MAXWEIGHT" then self.maxWeight = tonumber(id, 10) end
end
function Adventure:contents(target)
    local result = {}
    for _, id in ipairs(self.ids) do if self.state.places[id].key == target.key then result[#result + 1] = id end end
    return result
end
function Adventure:children()
    local result = {}
    for _, id in ipairs(self.ids) do
        local key = self.state.places[id].key
        if not result[key] then result[key] = {} end
        result[key][#result[key] + 1] = id
    end
    return result
end
function Adventure:isOpen(id) return self.items[id].capacity ~= nil and self.state.containers[id] == "open" end
function Adventure:reachable(root)
    local children, result = self:children(), {}
    local function visit(target)
        for _, id in ipairs(children[target.key] or {}) do
            result[id] = true
            if self:isOpen(id) then visit(place("inside", id)) end
        end
    end
    visit(root)
    return result
end
function Adventure:carried() return self:reachable(place("player")) end
function Adventure:isCarried(id) return self:carried()[id] == true end
function Adventure:roomItems() return self:reachable(place("room", self.state.room)) end
function Adventure:nearby()
    local result = self:carried()
    for id in pairs(self:roomItems()) do result[id] = true end
    return result
end
function Adventure:isLit()
    if not self.rooms[self.state.room].dark then return true end
    for id in pairs(self:nearby()) do if self.state.lit[id] then return true end end
    return false
end
function Adventure:visible() return self:isLit() and self:nearby() or self:carried() end
function Adventure:weights()
    local children, result = self:children(), {}
    local function total(id)
        if result[id] ~= nil then return result[id] end
        local weight = self.items[id].weight
        for _, child in ipairs(children[place("inside", id).key] or {}) do weight = weight + total(child) end
        result[id] = weight
        return weight
    end
    for _, id in ipairs(self.ids) do total(id) end
    return result
end
function Adventure:totalWeight(id) return self:weights()[id] end
function Adventure:contentWeight(id) return self:totalWeight(id) - self.items[id].weight end
function Adventure:carriedWeight()
    local weights, result = self:weights(), 0
    for _, id in ipairs(self:contents(place("player"))) do result = result + weights[id] end
    return result
end
function Adventure:nestedIn(id, ancestor)
    local target = self.state.places[id]
    while target.kind == "inside" do
        if target.id == ancestor then return true end
        target = self.state.places[target.id]
    end
    return false
end
function Adventure:score()
    local stored, treasures, points = 0, 0, 0
    for _, id in ipairs(self.ids) do
        local item = self.items[id]
        if item.points > 0 then
            treasures = treasures + 1
            local target = self.state.places[id]
            while target.kind == "inside" do target = self.state.places[target.id] end
            if target.kind == "room" and target.id == self.trophy then stored = stored + 1; points = points + item.points end
        end
    end
    return {stored = stored, treasures = treasures, points = points, total = points + self.state.bonus}
end
function Adventure:display(id)
    local item, annotations = self.items[id], {}
    if item.capacity then annotations[#annotations + 1] = self.state.containers[id] end
    if item.light and self.state.lit[id] then annotations[#annotations + 1] = "lit" end
    return item.name .. (#annotations > 0 and " (" .. table.concat(annotations, ", ") .. ")" or "")
end
function Adventure:tree(root)
    local children, lines = self:children(), {}
    local function visit(target, depth)
        for _, id in ipairs(children[target.key] or {}) do
            lines[#lines + 1] = string.rep("  ", depth) .. self:display(id)
            if self:isOpen(id) then visit(place("inside", id), depth + 1) end
        end
    end
    visit(root, 1)
    return lines
end
function Adventure:describe(full)
    if not self:isLit() then return {"It is pitch dark."} end
    if full == nil then full = true end
    local room, lines = self.rooms[self.state.room], {}
    lines[#lines + 1] = room.name
    if full then append(lines, room.description) end
    local exits = {}
    for direction, name in ipairs(directionNames) do
        local exit = (self.state.exits[self.state.room] or {})[direction]
        if exit then exits[#exits + 1] = name .. (exit.locked and " (locked)" or "") end
    end
    lines[#lines + 1] = "Exits: " .. (#exits > 0 and table.concat(exits, ", ") or "none")
    local floor = place("room", self.state.room)
    if #self:contents(floor) > 0 then lines[#lines + 1] = "You see:"; append(lines, self:tree(floor)) end
    return lines
end
function Adventure:resolve(phrase)
    local visible = self:visible()
    if only(phrase, "it") then
        if not self.pronoun then fail('I don\'t know what "it" refers to.') end
        if not visible[self.pronoun] then fail("You can't see any such thing.") end
        return self.pronoun
    end
    for _, word in ipairs(phrase) do if not self.vocabulary[word] then fail('I don\'t know the word "' .. word .. '".') end end
    local matches = {}
    for _, id in ipairs(self.ids) do
        local item, matchesWords = self.items[id], true
        if visible[id] and item.nouns[phrase[#phrase]] then
            for i = 1, #phrase - 1 do if not item.nameWords[phrase[i]] then matchesWords = false; break end end
            if matchesWords then matches[#matches + 1] = id end
        end
    end
    if #matches == 0 then fail("You can't see any such thing.") end
    if #matches > 1 then
        local names = {}
        for _, id in ipairs(matches) do names[#names + 1] = self.items[id].name end
        fail("Which do you mean: " .. table.concat(names, ", ") .. "?")
    end
    self.pronoun = matches[1]
    return matches[1]
end
function Adventure:runRules(rules, first, second)
    local lines, executed = {}, 0
    for _, rule in ipairs(rules) do
        if rule.first == first and rule.second == second and (rule.flag == nil or (self.state.flags[rule.flag] == true) == rule.whenOn) then
            executed = executed + 1
            local effect = rule.effect
            if effect.kind == "MESSAGE" then lines[#lines + 1] = effect.text
            elseif effect.kind == "OPEN" then self:setExit(effect.room, effect.direction, effect.destination)
            elseif effect.kind == "REMOVE" or effect.kind == "ADD" then self.state.places[effect.item] = effect.place
            elseif effect.kind == "SET" or effect.kind == "CLEAR" then self.state.flags[effect.flag] = effect.kind == "SET" or nil
            else self.state.bonus = self.state.bonus + effect.amount end
        end
    end
    return lines, executed
end
function Adventure:requireContainer(id)
    local item = self.items[id]
    if not item.capacity then fail("The " .. item.name .. " is not a container.") end
    if not self:isOpen(id) then fail("The " .. item.name .. " is closed.") end
end
function Adventure:take(first, second)
    if not self:isLit() then fail("It is pitch dark.") end
    local container, source = nil, place("room", self.state.room)
    if second then container = self:resolve(second); self:requireContainer(container); source = place("inside", container) end
    if only(first, "all") then
        local candidates = {}
        for _, id in ipairs(self:contents(source)) do if not self.items[id].fixed then candidates[#candidates + 1] = id end end
        if #candidates == 0 then
            fail(container and "There is nothing in the " .. self.items[container].name .. " to take." or "There is nothing here to take.")
        end
        local lines, taken = {}, false
        for _, id in ipairs(candidates) do
            local outcome = "You can't carry any more."
            if self:isCarried(id) or self:carriedWeight() + self:totalWeight(id) <= self.maxWeight then
                self.state.places[id], outcome, taken = place("player"), "Taken.", true
            end
            lines[#lines + 1] = self.items[id].name .. ": " .. outcome
        end
        if not taken then fail(lines) end
        return lines
    end
    local id = self:resolve(first)
    local item = self.items[id]
    if container and self.state.places[id].key ~= source.key then fail("The " .. item.name .. " is not in the " .. self.items[container].name .. ".") end
    if self.state.places[id].kind == "player" then fail("You already have the " .. item.name .. ".") end
    if item.fixed then fail("The " .. item.name .. " is fixed in place.") end
    if not self:isCarried(id) and self:carriedWeight() + self:totalWeight(id) > self.maxWeight then fail("You can't carry any more.") end
    self.state.places[id] = place("player")
    return {"Taken."}
end
function Adventure:drop(phrase)
    if only(phrase, "all") then
        local candidates, lines = self:contents(place("player")), {}
        if #candidates == 0 then fail("You are empty-handed.") end
        for _, id in ipairs(candidates) do
            self.state.places[id] = place("room", self.state.room)
            lines[#lines + 1] = self.items[id].name .. ": Dropped."
        end
        return lines
    end
    local id = self:resolve(phrase)
    if not self:isCarried(id) then fail("You aren't carrying the " .. self.items[id].name .. ".") end
    self.state.places[id] = place("room", self.state.room)
    return {"Dropped."}
end
function Adventure:putItem(id, container)
    local item, target = self.items[id], self.items[container]
    if self:nestedIn(container, id) then return "The " .. target.name .. " is inside the " .. item.name .. "." end
    if self.state.places[id].key == place("inside", container).key then return "The " .. item.name .. " is already in the " .. target.name .. "." end
    local weight = self:contentWeight(container) + (self:nestedIn(id, container) and 0 or self:totalWeight(id))
    if weight > target.capacity then return "The " .. item.name .. " doesn't fit in the " .. target.name .. "." end
    self.state.places[id] = place("inside", container)
    return nil
end
function Adventure:put(first, second)
    if only(first, "all") then
        local target = self:resolve(second)
        self:requireContainer(target)
        local candidates = {}
        for _, id in ipairs(self:contents(place("player"))) do if id ~= target then candidates[#candidates + 1] = id end end
        if #candidates == 0 then fail("You have nothing to put in the " .. self.items[target].name .. ".") end
        local lines, succeeded = {}, false
        for _, id in ipairs(candidates) do
            local reason = self:putItem(id, target)
            if not reason then succeeded = true end
            lines[#lines + 1] = self.items[id].name .. ": " .. (reason or "Done.")
        end
        if not succeeded then fail(lines) end
        return lines
    end
    local id = self:resolve(first)
    local target = self:resolve(second)
    local name = self.items[id].name
    if not self:isCarried(id) then fail("You aren't carrying the " .. name .. ".") end
    if id == target then fail("You can't put the " .. name .. " inside itself.") end
    self:requireContainer(target)
    local reason = self:putItem(id, target)
    if reason then fail(reason) end
    return {"You put the " .. name .. " in the " .. self.items[target].name .. "."}
end
function Adventure:keyCheck(key, phrase)
    if phrase then
        local id = self:resolve(phrase)
        local name = self.items[id].name
        if not self:isCarried(id) then fail("You aren't carrying the " .. name .. ".") end
        if id ~= key then fail("The " .. name .. " doesn't fit.") end
        return {}
    end
    if not self:isCarried(key) then fail("You don't have the right key.") end
    return {"(with the " .. self.items[key].name .. ")"}
end
function Adventure:lockObject(first, second, locking)
    local direction = #first == 1 and directions[first[1]] or nil
    local lines
    if direction then
        local room, name = self.state.room, directionNames[direction]
        local exit = (self.state.exits[room] or {})[direction]
        if not exit then fail("There is no exit " .. name .. ".") end
        if not exit.key then fail("The way " .. name .. " has no lock.") end
        if exit.locked == locking then fail("The way " .. name .. " is " .. (locking and "already locked." or "not locked.")) end
        lines = self:keyCheck(exit.key, second)
        self.state.exits[room][direction] = {destination = exit.destination, key = exit.key, locked = locking}
        local opposite = ((direction - 1) ~ 1) + 1
        local back = (self.state.exits[exit.destination] or {})[opposite]
        if back and back.destination == room and back.key == exit.key then
            self.state.exits[exit.destination][opposite] = {destination = back.destination, key = back.key, locked = locking}
        end
    else
        local id = self:resolve(first)
        local item, value = self.items[id], self.state.containers[id]
        if not item.capacity or not item.key then fail("The " .. item.name .. " has no lock.") end
        if (value == "locked") == locking then fail("The " .. item.name .. " is " .. (locking and "already locked." or "not locked.")) end
        if locking and value == "open" then fail("You must close the " .. item.name .. " first.") end
        lines = self:keyCheck(item.key, second)
        self.state.containers[id] = locking and "locked" or "closed"
    end
    lines[#lines + 1] = locking and "Locked." or "Unlocked."
    return lines
end
function Adventure:execute(verb, first, second)
    if verb == "look" then return self:describe()
    elseif verb == "inventory" then
        local player, lines = place("player"), {"You are carrying:"}
        if #self:contents(player) == 0 then return {"You are empty-handed."} end
        append(lines, self:tree(player)); lines[#lines + 1] = "Total weight: " .. self:carriedWeight() .. "/" .. self.maxWeight
        return lines
    elseif verb == "wait" then return {"Time passes."}
    elseif verb == "score" then
        local score = self:score()
        return {"You have scored " .. score.total .. " points (treasure " .. score.points .. ", bonus " .. self.state.bonus .. ") in " .. self.state.moves .. " moves.",
            "Treasures stored: " .. score.stored .. " of " .. score.treasures .. "."}
    elseif verb == "save" then self.saved = copyState(self.state); return {"Game saved."}
    elseif verb == "restore" then
        if not self.saved then fail("There is no saved game.") end
        self.state = copyState(self.saved)
        local lines = {"Game restored."}; append(lines, self:describe()); return lines
    elseif verb == "verbose" then self.verbose = true; return {"Verbose mode."}
    elseif verb == "brief" then self.verbose = false; return {"Brief mode."}
    elseif verb == "take" then return self:take(first, second)
    elseif verb == "drop" then return self:drop(first)
    elseif verb == "put" then return self:put(first, second)
    elseif verb == "unlock" or verb == "lock" then return self:lockObject(first, second, verb == "lock")
    elseif verb == "use" then
        local id = self:resolve(first)
        local target = self:resolve(second)
        if not self:isCarried(id) then fail("You aren't carrying the " .. self.items[id].name .. ".") end
        local lines, executed = self:runRules(self.rules, id, target)
        if executed == 0 then fail("Nothing happens.") end
        return #lines > 0 and lines or {"Done."}
    end
    local id = self:resolve(first)
    local item, value = self.items[id], self.state.containers[id]
    if verb == "examine" then
        local lines = #item.details > 0 and copy(item.details) or {"You see nothing special about the " .. item.name .. "."}
        if item.light then lines[#lines + 1] = "It is " .. (self.state.lit[id] and "lit" or "unlit") .. " (fuel " .. self.state.fuel[id] .. ")." end
        if item.capacity then
            if value ~= "open" then lines[#lines + 1] = "It is " .. value .. "."
            elseif #self:contents(place("inside", id)) == 0 then lines[#lines + 1] = "It is empty."
            else lines[#lines + 1] = "It contains:"; append(lines, self:tree(place("inside", id))) end
        end
        if item.points > 0 then lines[#lines + 1] = "It is a treasure worth " .. item.points .. " points." end
        lines[#lines + 1] = "It weighs " .. self:totalWeight(id) .. "."
        return lines
    elseif verb == "open" then
        if not item.capacity then fail("You can't open the " .. item.name .. ".") end
        if value == "open" then fail("The " .. item.name .. " is already open.") end
        if value == "locked" then fail("The " .. item.name .. " is locked.") end
        self.state.containers[id] = "open"
        local names = {}
        for _, child in ipairs(self:contents(place("inside", id))) do names[#names + 1] = self.items[child].name end
        return #names > 0 and {"Opening the " .. item.name .. " reveals " .. table.concat(names, ", ") .. "."} or {"Opened."}
    elseif verb == "close" then
        if not item.capacity then fail("You can't close the " .. item.name .. ".") end
        if value ~= "open" then fail("The " .. item.name .. " is already closed.") end
        self.state.containers[id] = "closed"
        return {"Closed."}
    elseif verb == "light" then
        if not item.light then fail("You can't light the " .. item.name .. ".") end
        if self.state.lit[id] then fail("The " .. item.name .. " is already lit.") end
        if self.state.fuel[id] == 0 then fail("The " .. item.name .. " has no fuel.") end
        self.state.lit[id] = true
        return {"The " .. item.name .. " is now lit."}
    elseif verb == "extinguish" then
        if not item.light then fail("You can't extinguish the " .. item.name .. ".") end
        if not self.state.lit[id] then fail("The " .. item.name .. " is not lit.") end
        self.state.lit[id] = false
        return {"The " .. item.name .. " is now out."}
    end
end
function Adventure:endTurn(baseline)
    self.state.moves = self.state.moves + 1
    local nearby, lines = self:nearby(), {}
    for _, id in ipairs(self.ids) do
        if self.state.lit[id] then
            self.state.fuel[id] = self.state.fuel[id] - 1
            if self.state.fuel[id] == 0 then
                self.state.lit[id] = false
                if nearby[id] then lines[#lines + 1] = "The " .. self.items[id].name .. " goes out." end
            end
        end
    end
    local lit = self:isLit()
    if baseline and not lit then lines[#lines + 1] = "It is now pitch dark."
    elseif not baseline and lit then append(lines, self:describe()) end
    self.state.darkness = lit and 0 or self.state.darkness + 1
    if self.state.darkness == 2 then lines[#lines + 1] = "You hear something moving in the dark." end
    if self.state.darkness == 3 then self.state.ended = "dead" end
    local score = self:score()
    if self.state.ended == "none" and score.treasures > 0 and score.stored == score.treasures then self.state.ended = "won" end
    if self.state.ended ~= "none" then
        lines[#lines + 1] = self.state.ended == "dead" and "*** You have died ***" or "*** You have won ***"
        lines[#lines + 1] = "You scored " .. score.total .. " points in " .. self.state.moves .. " moves."
    end
    return lines
end
function Adventure:interpret(line)
    local w = normalized(line)
    if #w == 0 then fail("I beg your pardon?") end
    if directions[w[1]] then table.insert(w, 1, "go") end
    local verb = verbs[w[1]]
    if not verb then fail('I don\'t know the verb "' .. w[1] .. '".') end
    if self.state.ended ~= "none" and verb ~= "restore" then fail("The game is over.") end
    local rest = slice(w, 2)
    if verb == "look" and #rest > 0 then
        if rest[1] ~= "at" then fail("I don't understand that.") end
        verb, rest = "examine", slice(rest, 2)
    end
    local first, second = rest, nil
    if noObjects[verb] then
        if #rest > 0 then fail("I don't understand that.") end
    else
        if #rest == 0 then fail(verb == "go" and "Which way do you want to go?" or "What do you want to " .. verb .. "?") end
        if verb == "go" then
            if #rest ~= 1 or not directions[rest[1]] then fail("I don't understand that.") end
        else
            local prepositions
            if verb == "put" then prepositions = {["in"] = true, into = true}
            elseif verb == "use" then prepositions = {on = true, with = true}
            elseif verb == "unlock" or verb == "lock" then prepositions = {with = true}
            elseif verb == "take" then prepositions = {from = true} end
            if prepositions then
                local index
                for i, word in ipairs(rest) do if prepositions[word] then index = i; break end end
                if index then
                    if index == 1 or index == #rest then fail("I don't understand that.") end
                    first, second = slice(rest, 1, index - 1), slice(rest, index + 1)
                elseif verb == "put" or verb == "use" then fail("I don't understand that.") end
            end
        end
    end
    local baseline, lines = self:isLit(), nil
    if verb == "go" then
        local direction = directions[rest[1]]
        local exit = (self.state.exits[self.state.room] or {})[direction]
        if not exit then fail("You can't go that way.") end
        if exit.locked then fail("The way " .. directionNames[direction] .. " is locked.") end
        self.state.room = exit.destination
        baseline = self:isLit()
        lines = self:describe(self.verbose or not self.state.visited[self.state.room])
        self.state.visited[self.state.room] = true
        local extra = self:runRules(self.enterRules, self.state.room)
        append(lines, extra)
    else lines = self:execute(verb, first, second) end
    if actions[verb] then append(lines, self:endTurn(baseline)) end
    return lines
end
function Adventure:command(line)
    local ok, result = pcall(function()
        local w = normalized(line)
        if w[1] == "again" or w[1] == "g" then
            if #w ~= 1 then fail("I don't understand that.") end
            if not self.previous then fail("There is nothing to repeat.") end
            return self:interpret(self.previous)
        end
        self.previous = line
        return self:interpret(line)
    end)
    if ok then return result end
    if type(result) == "table" and result.command_error then return result.lines end
    error(result, 0)
end
function Adventure:finalScore() return "Final score: " .. self:score().total .. " points in " .. self.state.moves .. " moves." end

local function readLine()
    local line = io.read("l")
    if line then return (line:gsub("\r$", "")) end
end
local function writeLines(lines) for _, line in ipairs(lines) do io.write(line, "\n") end end
local definitions = {}
while true do
    local line = readLine()
    if not line or line == "BEGIN" then break end
    definitions[#definitions + 1] = line
end
local adventure = Adventure.new(definitions)
writeLines(adventure:describe())
while true do
    local line = readLine()
    if not line then break end
    if line == "QUIT" then io.write(adventure:finalScore(), "\n"); break end
    io.write("> ", line, "\n")
    writeLines(adventure:command(line))
end
