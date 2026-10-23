local output = {}
local function emit(format, ...)
    output[#output + 1] = string.format(format, ...)
end

local function words(text)
    local result = {}
    for word in text:gmatch("%S+") do result[#result + 1] = word end
    return result
end

local function split(text, separator)
    local result, start = {}, 1
    while true do
        local first, last = text:find(separator, start, true)
        if not first then result[#result + 1] = text:sub(start); return result end
        result[#result + 1] = text:sub(start, first - 1)
        start = last + 1
    end
end

local precedence = {{["||"]=true}, {["&&"]=true}, {["=="]=true,["!="]=true,["<"]=true,["<="]=true,[">"]=true,[">="]=true}, {["+"]=true,["-"]=true}, {["*"]=true,["/"]=true,["%"]=true}}
local function parse_expression(text)
    local tokens, position, i = {}, 1, 1
    while i <= #text do
        local c = text:sub(i, i)
        if c == " " then i = i + 1
        else
            local start = i
            if c:match("%d") then
                repeat i = i + 1 until i > #text or not text:sub(i, i):match("%d")
            elseif c:match("[A-Za-z_]") then
                repeat i = i + 1 until i > #text or not text:sub(i, i):match("[A-Za-z0-9_]")
            else
                i = i + 1
                local pair = text:sub(start, i)
                if pair == "||" or pair == "&&" or pair == "==" or pair == "!=" or pair == "<=" or pair == ">=" then i = i + 1 end
            end
            tokens[#tokens + 1] = text:sub(start, i - 1)
        end
    end
    local binary, unary
    unary = function()
        local token = tokens[position]
        position = position + 1
        if token == "!" or token == "-" then return {op="unary" .. token, left=unary()} end
        if token == "(" then
            local result = binary(1)
            position = position + 1
            return result
        end
        if token == "in" then
            local name = tokens[position + 1]
            position = position + 3
            return {op="in", name=name}
        end
        if token:match("^%d") then return {op="number", value=tonumber(token)} end
        return {op="variable", name=token}
    end
    binary = function(level)
        if level > #precedence then return unary() end
        local result = binary(level + 1)
        while precedence[level][tokens[position]] do
            local op = tokens[position]
            position = position + 1
            result = {op=op, left=result, right=binary(level + 1)}
        end
        return result
    end
    return binary(1)
end

local function parse_actions(text)
    local actions = {}
    if not text or text == "" then return actions end
    for _, item in ipairs(split(text, "; ")) do
        local action = {}
        if item:sub(1, 6) == "raise " then
            action.kind, action.name = "raise", item:match("^raise (%S+)")
            local expression = item:match("^raise %S+ (.+)$")
            if expression then action.value = parse_expression(expression) end
        elseif item:sub(1, 5) == "send " then
            local name, delay, expression = item:match("^send (%S+) (%d+)(.*)$")
            action.kind, action.name, action.delay = "send", name, tonumber(delay)
            if expression ~= "" then action.value = parse_expression(expression:sub(2)) end
        elseif item:sub(1, 7) == "cancel " then
            action.kind, action.name = "cancel", item:sub(8)
        elseif item:sub(1, 4) == "log " then
            action.kind, action.text = "log", ""
            local tail = item:sub(5)
            if tail:sub(1, 1) == '"' then
                local last = tail:find('"', 2, true)
                action.text = tail:sub(2, last - 1)
                if last < #tail then action.value = parse_expression(tail:sub(last + 2)) end
            else action.value = parse_expression(tail) end
        else
            local separator = item:find(" = ", 1, true)
            action.kind, action.name = "assign", item:sub(1, separator - 1)
            action.value = parse_expression(item:sub(separator + 3))
        end
        actions[#actions + 1] = action
    end
    return actions
end

local Chart = {}
Chart.__index = Chart
function Chart.new()
    local root = {name="", kind="root", children={}, child_states={}, depth=0, transitions={}}
    return setmetatable({root=root, states={}, names={}, variables={}, variable_names={}, document={}, active={}, history={}, queue={}, queue_head=1, reservations={}, time=0, creation=0, data=0, macrosteps=0, microsteps=0, trace=false, halted=false}, Chart)
end

function Chart:descendant(state, ancestor)
    while state ~= self.root do
        state = state.parent
        if state == ancestor then return true end
    end
    return false
end
function Chart:compound(state)
    return state == self.root or state.kind == "state" and #state.child_states > 0
end
function Chart:parallel(state)
    return state.kind == "parallel" and #state.child_states > 0
end

function Chart:reference(expression)
    if not expression then return end
    if expression.op == "variable" and expression.name ~= "_data" and self.variables[expression.name] == nil then return "unknown variable " .. expression.name end
    if expression.op == "in" and not self.names[expression.name] then return "unknown state " .. expression.name end
    return self:reference(expression.left) or self:reference(expression.right)
end
function Chart:action_references(actions)
    for _, action in ipairs(actions) do
        if action.kind == "assign" and self.variables[action.name] == nil then return "unknown variable " .. action.name end
        local problem = self:reference(action.value)
        if problem then return problem end
    end
end

function Chart:parse_transition(text)
    local source, tail = text:match("^on (%S+) (.+)$")
    local transition = {source=self.names[source], mode="internal", actions={}}
    local bracket = 0
    for i = 1, #tail - 2 do
        local c = tail:sub(i, i)
        if c == "[" then bracket = bracket + 1 elseif c == "]" then bracket = bracket - 1 end
        if bracket == 0 and tail:sub(i, i + 2) == " / " then
            transition.actions = parse_actions(tail:sub(i + 3))
            tail = tail:sub(1, i - 1)
            break
        end
    end
    local opening = tail:find(" [", 1, true)
    if opening then
        local closing = tail:find("]", opening + 2, true)
        transition.guard = parse_expression(tail:sub(opening + 2, closing - 1))
        tail = tail:sub(1, opening - 1) .. tail:sub(closing + 1)
    end
    for _, arrow in ipairs({" -> ", " ~> "}) do
        local position = tail:find(arrow, 1, true)
        if position then
            transition.mode = arrow == " -> " and "external" or "local"
            transition.target_name = tail:sub(position + 4)
            transition.target = self.names[transition.target_name]
            tail = tail:sub(1, position - 1)
            break
        end
    end
    if tail == "always" then transition.kind = "always"
    elseif tail:sub(1, 6) == "after " then transition.kind, transition.delay = "timer", tonumber(tail:sub(7))
    else transition.kind, transition.descriptors = "event", split(tail, "|") end
    return transition
end

function Chart:define(definitions)
    for _, definition in ipairs(definitions) do
        local fields = words(definition.text)
        local kind, name = fields[1], fields[2]
        definition.kind = kind
        if kind == "state" or kind == "parallel" or kind == "final" or kind == "history" then
            local parent_name = fields[3] ~= "initial" and fields[3] or nil
            local parent = parent_name and self.names[parent_name] or self.root
            if self.names[name] then definition.error = "duplicate state " .. name
            elseif parent_name and not self.names[parent_name] then definition.error = "unknown state " .. parent_name
            elseif parent.kind == "final" or parent.kind == "history" then definition.error = parent.name .. " cannot have children"
            else
                local state = {name=name, kind=kind, parent=parent, depth=parent.depth + 1, children={}, child_states={}, entries={}, exits={}, transitions={}, entered=0, taken=0, dwell=0, entry_time=0}
                if kind == "state" then
                    for i = 3, #fields do if fields[i] == "initial" then state.initial_name = fields[i + 1]; break end end
                elseif kind == "history" then state.deep, state.default_name = fields[4] == "deep", fields[5] end
                definition.state = state
                self.names[name], self.states[#self.states + 1] = state, state
                parent.children[#parent.children + 1] = state
                if kind ~= "history" then parent.child_states[#parent.child_states + 1] = state end
            end
        elseif kind == "var" then
            if self.variables[name] ~= nil then definition.error = "duplicate variable " .. name
            else self.variables[name] = tonumber(fields[3]); self.variable_names[#self.variable_names + 1] = name end
        end
    end
    for _, definition in ipairs(definitions) do
        if not definition.error then
            local fields, kind, state = words(definition.text), definition.kind, definition.state
            if kind == "state" and state.initial_name then
                local child = self.names[state.initial_name]
                if not child then definition.error = "unknown state " .. state.initial_name
                elseif child.parent ~= state or child.kind == "history" then definition.error = child.name .. " is not a child of " .. state.name end
            elseif kind == "final" or kind == "history" then
                if state.parent.kind ~= "state" or #state.parent.child_states == 0 then definition.error = state.name .. " needs a compound parent"
                elseif kind == "history" and state.default_name then
                    local target = self.names[state.default_name]
                    if not target then definition.error = "unknown state " .. state.default_name
                    elseif not self:descendant(target, state.parent) or target.kind == "history" then definition.error = target.name .. " is not a descendant of " .. state.parent.name end
                end
            elseif kind == "entry" or kind == "exit" then
                state = self.names[fields[2]]
                if not state then definition.error = "unknown state " .. fields[2]
                elseif state.kind == "history" then definition.error = state.name .. " cannot have actions"
                else
                    local separator = definition.text:find(" / ", 1, true)
                    local actions = parse_actions(definition.text:sub(separator + 3))
                    definition.error = self:action_references(actions)
                    if not definition.error then
                        local lists = kind == "entry" and state.entries or state.exits
                        lists[#lists + 1] = actions
                    end
                end
            elseif kind == "on" then
                state = self.names[fields[2]]
                if not state then definition.error = "unknown state " .. fields[2]
                elseif state.kind == "final" or state.kind == "history" then definition.error = state.name .. " cannot have transitions"
                else
                    local transition = self:parse_transition(definition.text)
                    definition.error = self:reference(transition.guard)
                    if not definition.error and transition.target_name and not transition.target then definition.error = "unknown state " .. transition.target_name end
                    if not definition.error then definition.error = self:action_references(transition.actions) end
                    if not definition.error then state.transitions[#state.transitions + 1] = transition end
                end
            end
        end
    end
    local valid = true
    for _, definition in ipairs(definitions) do
        if definition.error then emit("error line %d: %s", definition.line, definition.error); valid = false end
    end
    if not valid then return false end
    self.root.initial = self.root.child_states[1]
    for _, state in ipairs(self.states) do state.initial = state.initial_name and self.names[state.initial_name] or state.child_states[1] end
    for _, state in ipairs(self.states) do
        if state.kind == "history" then state.default_target = state.default_name and self.names[state.default_name] or state.parent.initial end
    end
    local function visit(state)
        self.document[#self.document + 1] = state
        for _, child in ipairs(state.children) do visit(child) end
    end
    for _, child in ipairs(self.root.children) do visit(child) end
    table.sort(self.variable_names)
    return true
end

function Chart:warn()
    local reachable = {[self.root.initial]=true}
    local changed = true
    while changed do
        changed = false
        local function add(state)
            if state ~= self.root and not reachable[state] then reachable[state], changed = true, true end
        end
        for _, state in ipairs(self.document) do
            if reachable[state] then
                add(state.parent)
                if self:compound(state) then add(state.initial) end
                if self:parallel(state) then for _, child in ipairs(state.child_states) do add(child) end end
                for _, transition in ipairs(state.transitions) do
                    if transition.target then add(transition.target.kind == "history" and transition.target.default_target or transition.target) end
                end
            end
        end
    end
    for _, state in ipairs(self.document) do if state.kind ~= "history" and not reachable[state] then emit("warning: unreachable state %s", state.name) end end
end

local function truth(value) return value and 1 or 0 end
local function quotient(a, b)
    local result = math.abs(a) // math.abs(b)
    return (a < 0) ~= (b < 0) and -result or result
end
function Chart:evaluate(expression)
    local op = expression.op
    if op == "number" then return expression.value end
    if op == "variable" then return expression.name == "_data" and self.data or self.variables[expression.name] end
    if op == "in" then return truth(self.active[self.names[expression.name]]) end
    local a = self:evaluate(expression.left)
    if a == nil then return end
    if op == "unary!" then return truth(a == 0) elseif op == "unary-" then return -a end
    if op == "&&" and a == 0 then return 0 elseif op == "||" and a ~= 0 then return 1 end
    local b = self:evaluate(expression.right)
    if b == nil then return end
    if op == "+" then return a + b elseif op == "-" then return a - b elseif op == "*" then return a * b
    elseif op == "/" or op == "%" then if b == 0 then return end; local q = quotient(a, b); return op == "/" and q or a - q * b
    elseif op == "==" then return truth(a == b) elseif op == "!=" then return truth(a ~= b)
    elseif op == "<" then return truth(a < b) elseif op == "<=" then return truth(a <= b)
    elseif op == ">" then return truth(a > b) elseif op == ">=" then return truth(a >= b)
    else return truth(b ~= 0) end
end

function Chart:enqueue(name, value) self.queue[#self.queue + 1] = {name=name, value=value} end
function Chart:reserve(reservation)
    self.creation = self.creation + 1
    reservation.order = self.creation
    self.reservations[#self.reservations + 1] = reservation
end
function Chart:perform(actions)
    for _, action in ipairs(actions) do
        local value = 0
        if action.value then value = self:evaluate(action.value) end
        if value == nil then self:enqueue("error.execution", 0); return end
        if action.kind == "assign" then self.variables[action.name] = value
        elseif action.kind == "raise" then self:enqueue(action.name, value)
        elseif action.kind == "send" then self:reserve({due=self.time + action.delay, event={name=action.name, value=value}})
        elseif action.kind == "cancel" then
            local kept = {}
            for _, reservation in ipairs(self.reservations) do if reservation.timer or reservation.event.name ~= action.name then kept[#kept + 1] = reservation end end
            self.reservations = kept
        elseif action.kind == "log" then emit("%s", action.text .. (action.value and tostring(value) or "")) end
    end
end

function Chart:targets(transition)
    local target = transition.target
    if target.kind ~= "history" then return {target} end
    return self.history[target] or {target.default_target}
end
function Chart:transition_set(transition)
    local selected = {transition=transition, exits={}}
    if transition.mode == "internal" then return selected end
    local targets = self:targets(transition)
    local function contains_targets(state)
        for _, target in ipairs(targets) do if not self:descendant(target, state) then return false end end
        return true
    end
    if transition.mode == "local" and self:compound(transition.source) and contains_targets(transition.source) then selected.scope = transition.source
    else
        local scope = transition.source.parent
        while not (self:compound(scope) and contains_targets(scope)) do scope = scope.parent end
        selected.scope = scope
    end
    for _, state in ipairs(self.document) do if self.active[state] and self:descendant(state, selected.scope) then selected.exits[state] = true end end
    return selected
end
local function matches(transition, trigger)
    if transition.kind ~= trigger.kind then return false end
    if trigger.kind == "always" then return true end
    if trigger.kind == "timer" then return transition == trigger.timer end
    for _, descriptor in ipairs(transition.descriptors) do
        local name = trigger.event.name
        if descriptor == "*" or descriptor == name or name:sub(1, #descriptor + 1) == descriptor .. "." then return true end
    end
    return false
end
function Chart:select_transitions(trigger)
    local result, seen, occupied = {}, {}, {}
    for _, atomic in ipairs(self.document) do
        if self.active[atomic] and #atomic.child_states == 0 then
            local state, found = atomic, nil
            while state ~= self.root and not found do
                for _, transition in ipairs(state.transitions) do
                    if matches(transition, trigger) then
                        local value = 1
                        if transition.guard then value = self:evaluate(transition.guard) end
                        if value == nil then self:enqueue("error.execution", 0)
                        elseif value ~= 0 then found = transition; break end
                    end
                end
                state = state.parent
            end
            if found and not seen[found] then
                seen[found] = true
                local selected, conflict = self:transition_set(found), false
                for state in pairs(selected.exits) do if occupied[state] then conflict = true; break end end
                if not conflict then
                    result[#result + 1] = selected
                    for state in pairs(selected.exits) do occupied[state] = true end
                end
            end
        end
    end
    return result
end

function Chart:expand(entries)
    local changed = true
    while changed do
        changed = false
        local function add(state) if not entries[state] then entries[state], changed = true, true end end
        for _, state in ipairs(self.document) do
            if entries[state] then
                if self:parallel(state) then for _, child in ipairs(state.child_states) do add(child) end
                elseif self:compound(state) then
                    local has_child = false
                    for _, child in ipairs(state.child_states) do if entries[child] then has_child = true; break end end
                    if not has_child then add(state.initial) end
                end
            end
        end
    end
end
function Chart:complete(state)
    if self:compound(state) then
        for _, child in ipairs(state.child_states) do if child.kind == "final" and self.active[child] then return true end end
    elseif self:parallel(state) then
        for _, child in ipairs(state.child_states) do if not self:complete(child) then return false end end
        return true
    end
    return false
end
function Chart:enter(entries)
    for _, state in ipairs(self.document) do
        if entries[state] then
            self.active[state] = true
            state.entered, state.entry_time = state.entered + 1, self.time
            for _, transition in ipairs(state.transitions) do if transition.kind == "timer" then self:reserve({due=self.time + transition.delay, timer=transition}) end end
            for _, actions in ipairs(state.entries) do self:perform(actions) end
            if state.kind == "final" then
                local parent = state.parent
                self:enqueue("done.state." .. parent.name, 0)
                local grandparent = parent.parent
                if self:parallel(grandparent) and self:complete(grandparent) then self:enqueue("done.state." .. grandparent.name, 0) end
            end
        end
    end
end
function Chart:list(set, reverse)
    local names = {}
    if reverse then
        for i = #self.document, 1, -1 do local state = self.document[i]; if set[state] then names[#names + 1] = state.name end end
    else for _, state in ipairs(self.document) do if set[state] then names[#names + 1] = state.name end end end
    return #names == 0 and "-" or table.concat(names, ",")
end
function Chart:microstep(trigger, transitions)
    local exits, entries = {}, {}
    for _, selected in ipairs(transitions) do for state in pairs(selected.exits) do exits[state] = true end end
    for _, history in ipairs(self.document) do
        if history.kind == "history" and exits[history.parent] then
            local recorded = {}
            for _, state in ipairs(self.document) do
                if self.active[state] and (history.deep and #state.child_states == 0 and self:descendant(state, history.parent) or not history.deep and state.parent == history.parent) then recorded[#recorded + 1] = state end
            end
            self.history[history] = recorded
        end
    end
    for _, selected in ipairs(transitions) do
        if selected.transition.mode ~= "internal" then
            for _, target in ipairs(self:targets(selected.transition)) do
                entries[target] = true
                local parent = target.parent
                while parent ~= self.root and self:descendant(parent, selected.scope) do entries[parent] = true; parent = parent.parent end
            end
        end
    end
    self:expand(entries)
    if self.trace then
        local sources, display = {}, "always"
        for _, selected in ipairs(transitions) do sources[#sources + 1] = selected.transition.source.name end
        if trigger.kind == "timer" then display = string.format("after(%d)@%s", trigger.timer.delay, trigger.timer.source.name)
        elseif trigger.kind == "event" then display = trigger.event.name .. (trigger.event.value ~= 0 and "=" .. trigger.event.value or "") end
        emit("[t=%d] %s (%s): exit %s; enter %s", self.time, display, table.concat(sources, ","), self:list(exits, true), self:list(entries, false))
    end
    for i = #self.document, 1, -1 do
        local state = self.document[i]
        if exits[state] then
            for _, actions in ipairs(state.exits) do self:perform(actions) end
            self.active[state] = nil
            state.dwell = state.dwell + self.time - state.entry_time
            local kept = {}
            for _, reservation in ipairs(self.reservations) do if not reservation.timer or reservation.timer.source ~= state then kept[#kept + 1] = reservation end end
            self.reservations = kept
        end
    end
    for _, selected in ipairs(transitions) do
        self:perform(selected.transition.actions)
        selected.transition.source.taken = selected.transition.source.taken + 1
    end
    self:enter(entries)
end
function Chart:macrostep(start, trigger)
    self.macrosteps = self.macrosteps + 1
    local count = 0
    local function perform(selected_trigger, transitions)
        if #transitions == 0 then return true end
        if count == 1000 then emit("LIVELOCK t=%d", self.time); self.halted = true; return false end
        count, self.microsteps = count + 1, self.microsteps + 1
        self:microstep(selected_trigger, transitions)
        return true
    end
    self.data = 0
    if start then
        local entries = {[self.root.initial]=true}
        self:expand(entries)
        self:enter(entries)
    else
        if trigger.kind == "event" then self.data = trigger.event.value end
        if not perform(trigger, self:select_transitions(trigger)) then return end
    end
    while true do
        self.data = 0
        local always = {kind="always"}
        local transitions = self:select_transitions(always)
        if #transitions > 0 then
            if not perform(always, transitions) then return end
        else
            if self.queue_head > #self.queue then return end
            local event = self.queue[self.queue_head]
            self.queue_head = self.queue_head + 1
            self.data = event.value
            local next_trigger = {kind="event", event=event}
            if not perform(next_trigger, self:select_transitions(next_trigger)) then return end
        end
    end
end

local function reservation_less(a, b) return a.due < b.due or a.due == b.due and a.order < b.order end
function Chart:dump()
    emit("dump t=%d", self.time)
    for _, state in ipairs(self.document) do if self.active[state] then emit("%s%s", string.rep(" ", 2 * state.depth), state.name) end end
    for _, name in ipairs(self.variable_names) do emit("  var %s = %d", name, self.variables[name]) end
    for _, state in ipairs(self.document) do
        if self.history[state] then
            local names = {}
            for _, target in ipairs(self.history[state]) do names[#names + 1] = target.name end
            emit("  history %s = %s", state.name, #names == 0 and "-" or table.concat(names, ","))
        end
    end
    local reservations = {}
    for i, reservation in ipairs(self.reservations) do reservations[i] = reservation end
    table.sort(reservations, reservation_less)
    for _, reservation in ipairs(reservations) do
        if reservation.timer then emit("  timer %d after(%d)@%s", reservation.due, reservation.timer.delay, reservation.timer.source.name)
        else emit("  send %d %s %d", reservation.due, reservation.event.name, reservation.event.value) end
    end
end
function Chart:script(text)
    if self.halted then return end
    local fields = words(text)
    if fields[1] == "event" then self:macrostep(false, {kind="event", event={name=fields[2], value=tonumber(fields[3]) or 0}})
    elseif fields[1] == "tick" then
        local finish = self.time + tonumber(fields[2])
        while not self.halted do
            local best
            for i, reservation in ipairs(self.reservations) do if reservation.due <= finish and (not best or reservation_less(reservation, self.reservations[best])) then best = i end end
            if not best then break end
            local reservation = table.remove(self.reservations, best)
            self.time = reservation.due
            self:macrostep(false, reservation.timer and {kind="timer", timer=reservation.timer} or {kind="event", event=reservation.event})
        end
        if not self.halted then self.time = finish end
    elseif fields[1] == "set" then
        if self.variables[fields[2]] ~= nil then self.variables[fields[2]] = tonumber(fields[3]) else emit("error: unknown variable %s", fields[2]) end
    elseif fields[1] == "trace" then self.trace = fields[2] == "on"
    elseif fields[1] == "eval" then
        local raw = text:sub(6)
        local expression = parse_expression(raw)
        local problem = self:reference(expression)
        if problem then emit("error: %s", problem)
        else
            self.data = 0
            local value = self:evaluate(expression)
            if value == nil then emit("error: division by zero") else emit("%s -> %d", raw, value) end
        end
    elseif fields[1] == "dump" then self:dump() end
end
function Chart:statistics()
    emit("end t=%d macrosteps=%d microsteps=%d", self.time, self.macrosteps, self.microsteps)
    for _, state in ipairs(self.document) do
        if state.kind ~= "history" then emit("  %s entered=%d taken=%d time=%d", state.name, state.entered, state.taken, state.dwell + (self.active[state] and self.time - state.entry_time or 0)) end
    end
end

local input = {}
for line in io.lines() do input[#input + 1] = line:gsub("\r$", "") end
local position = 2
for _ = 1, tonumber(input[1]) do
    emit("chart %s", input[position]:sub(7))
    position = position + 1
    local definitions = {}
    while input[position] ~= "RUN" do definitions[#definitions + 1] = {text=input[position], line=position}; position = position + 1 end
    position = position + 1
    local chart = Chart.new()
    local valid = chart:define(definitions)
    if valid then chart:warn(); chart:macrostep(true) end
    while input[position] ~= "END" do if valid then chart:script(input[position]) end; position = position + 1 end
    position = position + 1
    if valid then chart:statistics() end
end
io.write(table.concat(output, "\n"), "\n")
