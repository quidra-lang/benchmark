local priorities = {"LOW", "MEDIUM", "HIGH", "CRITICAL"}
local kinds = {"BUG", "TASK", "STORY"}
local workflows = {
    BUG = {"OPEN", "TRIAGED", "IN_PROGRESS", "REVIEW", "RESOLVED", "CLOSED", "REOPENED"},
    TASK = {"OPEN", "IN_PROGRESS", "DONE"},
    STORY = {"BACKLOG", "READY", "IN_PROGRESS", "REVIEW", "DONE"},
}
local transitions = {
    BUG = {"OPEN:TRIAGED", "TRIAGED:IN_PROGRESS", "IN_PROGRESS:REVIEW", "REVIEW:IN_PROGRESS",
        "REVIEW:RESOLVED", "RESOLVED:CLOSED", "RESOLVED:REOPENED", "CLOSED:REOPENED", "REOPENED:IN_PROGRESS"},
    TASK = {"OPEN:IN_PROGRESS", "IN_PROGRESS:OPEN", "IN_PROGRESS:DONE"},
    STORY = {"BACKLOG:READY", "READY:BACKLOG", "READY:IN_PROGRESS", "IN_PROGRESS:REVIEW", "REVIEW:IN_PROGRESS", "REVIEW:DONE"},
}
local done_states = {RESOLVED = true, CLOSED = true, DONE = true}
local estimates = {[0] = true, [1] = true, [2] = true, [3] = true, [5] = true, [8] = true, [13] = true, [21] = true}
local equality = {"=", "!="}
local ordered = {"=", "!=", "<", "<=", ">", ">="}
local field_operators = {
    id = ordered, type = equality, status = equality, priority = ordered,
    assignee = equality, reviewer = equality, estimate = ordered, sprint = equality,
    comments = ordered, blocked = equality, done = equality, title = {"~"},
}
local none_fields = {assignee = true, reviewer = true, estimate = true, sprint = true}

local function fail(message)
    error({message = message}, 0)
end

local function contains(list, value)
    for _, item in ipairs(list) do
        if item == value then return true end
    end
    return false
end

local function sorted_keys(map)
    local result = {}
    for key in pairs(map) do result[#result + 1] = key end
    table.sort(result)
    return result
end

local function display(value)
    if value == nil then return "-" end
    return tostring(value)
end

local function yes_no(value)
    return value and "yes" or "no"
end

local function done(issue)
    return done_states[issue.state] == true
end

local function points(issue)
    return issue.estimate or 0
end

local function level(issue)
    for index, priority in ipairs(priorities) do
        if issue.priority == priority then return index end
    end
end

local function number_list(set)
    local numbers = sorted_keys(set)
    if #numbers == 0 then return "-" end
    for index, number in ipairs(numbers) do numbers[index] = tostring(number) end
    return table.concat(numbers, ",")
end

local function split(line)
    local words = {}
    for word in line:gmatch("[^ ]+") do words[#words + 1] = word end
    return words
end

local Tracker = {}
Tracker.__index = Tracker

function Tracker.new()
    return setmetatable({day = 1, users = {}, issues = {}, sprints = {}, sprint_order = {}}, Tracker)
end

function Tracker:emit(...)
    local parts = table.pack(...)
    for index = 1, parts.n do parts[index] = tostring(parts[index]) end
    self.output[#self.output + 1] = table.concat(parts, " ", 1, parts.n)
end

function Tracker:issue(text)
    local issue = self.issues[tonumber(text)]
    if not issue then fail("unknown issue") end
    return issue
end

function Tracker:user(spec)
    if spec == "-" then return nil end
    if not self.users[spec] then fail("unknown user") end
    return spec
end

function Tracker:sprint(name)
    local sprint = self.sprints[name]
    if not sprint then fail("unknown sprint") end
    return sprint
end

function Tracker:not_done(issue)
    if done(issue) then fail("issue done") end
end

function Tracker:ordered_issues()
    local result = {}
    for _, number in ipairs(sorted_keys(self.issues)) do result[#result + 1] = self.issues[number] end
    return result
end

function Tracker:unfinished(issue)
    local result = {}
    for _, number in ipairs(sorted_keys(issue.blockers)) do
        if not done(self.issues[number]) then result[#result + 1] = number end
    end
    return result
end

function Tracker:blocked(issue)
    return not done(issue) and #self:unfinished(issue) > 0
end

function Tracker:wip(user)
    local count = 0
    for _, issue in pairs(self.issues) do
        if issue.assignee == user and issue.state == "IN_PROGRESS" then count = count + 1 end
    end
    return count
end

function Tracker:active_sprint()
    for _, sprint in ipairs(self.sprint_order) do
        if sprint.phase == "ACTIVE" then return sprint end
    end
end

function Tracker:members(sprint)
    local result = {}
    for _, issue in ipairs(self:ordered_issues()) do
        if issue.sprint == sprint.name then result[#result + 1] = issue end
    end
    return result
end

function Tracker:remaining(sprint)
    local total = 0
    for _, issue in ipairs(self:members(sprint)) do
        if not done(issue) then total = total + points(issue) end
    end
    return total
end

function Tracker:summary(sprint)
    local members, total = self:members(sprint), 0
    for _, issue in ipairs(members) do total = total + points(issue) end
    return "issues " .. #members .. " points " .. total
end

function Tracker:record(issue, text)
    issue.history[#issue.history + 1] = "day " .. self.day .. " " .. text
end

function Tracker:blocked_states(numbers)
    local before = {}
    for _, number in ipairs(numbers) do before[number] = self:blocked(self.issues[number]) end
    return before
end

function Tracker:notify(before)
    for _, number in ipairs(sorted_keys(before)) do
        local after = self:blocked(self.issues[number])
        if after ~= before[number] then self:emit(after and "BLOCKED" or "UNBLOCKED", number) end
    end
end

function Tracker:change_state(issue, target)
    local before = self:blocked_states(sorted_keys(issue.blocks))
    self:emit("MOVE", issue.number, issue.state, target)
    self:record(issue, "MOVE " .. issue.state .. " " .. target)
    issue.state = target
    self:notify(before)
end

function Tracker:reaches(start, goal)
    local pending, visited = {start.number}, {}
    while #pending > 0 do
        local number = table.remove(pending)
        if number == goal.number then return true end
        if not visited[number] then
            visited[number] = true
            for blocked in pairs(self.issues[number].blocks) do pending[#pending + 1] = blocked end
        end
    end
    return false
end

function Tracker:set_person(command, args)
    local issue = self:issue(args[1])
    local user = self:user(args[2])
    self:not_done(issue)
    if command == "ASSIGN" then
        if issue.assignee == user then fail("no change") end
        if user == nil and (issue.state == "IN_PROGRESS" or issue.state == "REVIEW") then fail("assignee required") end
        if issue.state == "IN_PROGRESS" and self:wip(user) >= 3 then fail("wip limit " .. args[2]) end
        if issue.state == "REVIEW" and user == issue.reviewer then fail("reviewer is assignee") end
        issue.assignee = user
    else
        if issue.reviewer == user then fail("no change") end
        if user == nil and issue.state == "REVIEW" then fail("reviewer required") end
        if issue.state == "REVIEW" and user == issue.assignee then fail("reviewer is assignee") end
        issue.reviewer = user
    end
    self:record(issue, command .. " " .. args[2])
    self:emit(command, issue.number, args[2])
end

function Tracker:move(args)
    local issue, target = self:issue(args[1]), args[2]
    if issue.duplicate ~= nil then fail("duplicate of " .. issue.duplicate) end
    if not contains(workflows[issue.kind], target) then fail("bad state") end
    if not contains(transitions[issue.kind], issue.state .. ":" .. target) then
        fail("cannot move " .. issue.state .. " to " .. target)
    end
    if target == "IN_PROGRESS" then
        local active = self:active_sprint()
        if issue.kind == "STORY" and (not active or issue.sprint ~= active.name) then fail("not in active sprint") end
        if issue.assignee == nil then fail("no assignee") end
        if self:wip(issue.assignee) >= 3 then fail("wip limit " .. issue.assignee) end
    elseif target == "REVIEW" then
        if issue.reviewer == nil then fail("no reviewer") end
        if issue.reviewer == issue.assignee then fail("reviewer is assignee") end
    end
    if target == "DONE" or target == "RESOLVED" then
        local blockers = self:unfinished(issue)
        if #blockers > 0 then fail("blocked by " .. blockers[1]) end
    end
    if target == "READY" and issue.estimate == nil then fail("no estimate") end
    self:change_state(issue, target)
end

function Tracker:link(command, args)
    local relation = args[2]
    if relation ~= "BLOCKS" and (command == "UNLINK" or relation ~= "DUPLICATES") then fail("bad link") end
    local source = self:issue(args[1])
    local target = self:issue(args[3])
    if command == "UNLINK" then
        if not source.blocks[target.number] then fail("no link") end
        local before = self:blocked_states({target.number})
        source.blocks[target.number], target.blockers[source.number] = nil, nil
        self:record(source, "UNLINK BLOCKS " .. target.number)
        self:record(target, "UNLINK BLOCKED_BY " .. source.number)
        self:emit("UNLINK", source.number, "BLOCKS", target.number)
        self:notify(before)
        return
    end
    if source == target then fail("self link") end
    if relation == "BLOCKS" then
        if source.blocks[target.number] then fail("link exists") end
        if self:reaches(target, source) then fail("cycle") end
        self:not_done(target)
        local before = self:blocked_states({target.number})
        source.blocks[target.number], target.blockers[source.number] = true, true
        self:record(source, "LINK BLOCKS " .. target.number)
        self:record(target, "LINK BLOCKED_BY " .. source.number)
        self:emit("LINK", source.number, relation, target.number)
        self:notify(before)
    else
        if source.kind ~= target.kind then fail("type mismatch") end
        self:not_done(source)
        if target.duplicate ~= nil then fail("target is duplicate") end
        source.duplicate = target.number
        target.duplicates[source.number] = true
        self:record(source, "LINK DUPLICATES " .. target.number)
        self:record(target, "LINK DUPLICATED_BY " .. source.number)
        self:emit("LINK", source.number, relation, target.number)
        self:change_state(source, source.kind == "BUG" and "CLOSED" or "DONE")
        if source.sprint ~= nil and self.sprints[source.sprint].phase ~= "ENDED" then
            self:record(source, "SPRINT REMOVE " .. source.sprint)
            source.sprint = nil
        end
    end
end

function Tracker:sprint_command(args)
    local action, name = args[1], args[2]
    if action == "NEW" then
        if self.sprints[name] then fail("sprint exists") end
        local sprint = {name = name, phase = "PLANNED", velocity = 0, records = {}}
        self.sprints[name] = sprint
        self.sprint_order[#self.sprint_order + 1] = sprint
        self:emit("SPRINT", "NEW", name)
        return
    end
    local sprint = self:sprint(name)
    if action == "ADD" or action == "REMOVE" then
        local issue = self:issue(args[3])
        if sprint.phase == "ENDED" then fail("sprint ended") end
        if action == "ADD" then
            self:not_done(issue)
            if issue.sprint ~= nil and self.sprints[issue.sprint].phase ~= "ENDED" then fail("in sprint " .. issue.sprint) end
            if issue.state == "BACKLOG" then fail("not ready") end
            issue.sprint = name
        else
            if issue.sprint ~= name then fail("not in sprint") end
            self:not_done(issue)
            issue.sprint = nil
        end
        self:record(issue, "SPRINT " .. action .. " " .. name)
        self:emit("SPRINT", action, name, issue.number, self:summary(sprint))
    elseif action == "START" then
        if sprint.phase ~= "PLANNED" then fail("sprint not planned") end
        local active = self:active_sprint()
        if active then fail("sprint active " .. active.name) end
        if #self:members(sprint) == 0 then fail("sprint empty") end
        sprint.phase, sprint.start = "ACTIVE", self.day
        sprint.records[self.day] = self:remaining(sprint)
        self:emit("SPRINT", "START", name, "day", self.day, self:summary(sprint), "remaining", self:remaining(sprint))
    else
        if sprint.phase ~= "ACTIVE" then fail("sprint not active") end
        sprint.records[self.day] = self:remaining(sprint)
        local finished, returned, velocity = {}, {}, 0
        for _, issue in ipairs(self:members(sprint)) do
            if done(issue) then
                finished[#finished + 1] = issue
                velocity = velocity + points(issue)
            else
                returned[#returned + 1] = issue
            end
        end
        sprint.velocity, sprint.phase, sprint.finish = velocity, "ENDED", self.day
        self:emit("SPRINT", "END", name, "day", self.day, "velocity", velocity, "done", #finished, "returned", #returned)
        for _, issue in ipairs(returned) do
            issue.sprint = nil
            self:record(issue, "SPRINT RETURN " .. name)
            self:emit("RETURNED", issue.number)
        end
    end
end

function Tracker:condition(token)
    local field = token:match("^[a-z]*")
    local rest = token:sub(#field + 1)
    local operator
    for _, candidate in ipairs({">=", "<=", "!=", "=", "<", ">", "~"}) do
        if rest:sub(1, #candidate) == candidate then
            operator = candidate
            break
        end
    end
    local text = operator and rest:sub(#operator + 1) or ""
    if field == "" or not operator or text == "" then fail("syntax near " .. token) end
    if not field_operators[field] then fail("unknown field " .. field) end
    if not contains(field_operators[field], operator) then fail("bad operator " .. token) end
    local value
    if text == "-" and none_fields[field] and contains(equality, operator) then
        value = nil
    elseif (field == "id" or field == "estimate" or field == "comments") and #text <= 6 and text:match("^[0-9]+$") then
        value = tonumber(text)
    elseif field == "priority" and contains(priorities, text) then
        for index, priority in ipairs(priorities) do if priority == text then value = index end end
    elseif field == "type" and workflows[text] then
        value = text
    elseif field == "status" then
        for _, states in pairs(workflows) do if contains(states, text) then value = text end end
        if value == nil then fail("bad value " .. token) end
    elseif (field == "assignee" or field == "reviewer") and self.users[text] then
        value = text
    elseif field == "sprint" and self.sprints[text] then
        value = text
    elseif (field == "blocked" or field == "done") and (text == "yes" or text == "no") then
        value = text
    elseif field == "title" then
        value = text:lower()
    else
        fail("bad value " .. token)
    end
    return {field = field, operator = operator, value = value}
end

function Tracker:compile_query(text)
    local tokens, position = {}, 1
    while position <= #text do
        local character = text:sub(position, position)
        if character == " " then
            position = position + 1
        elseif character == "(" or character == ")" then
            tokens[#tokens + 1] = character
            position = position + 1
        else
            local token = text:sub(position):match("^[^ ()]+")
            tokens[#tokens + 1] = token
            position = position + #token
        end
    end
    local conditions, operand, depth = {}, true, 0
    for index, token in ipairs(tokens) do
        if operand then
            if token == "(" then
                depth = depth + 1
            elseif token == "AND" or token == "OR" or token == ")" then
                fail("syntax near " .. token)
            elseif token ~= "NOT" then
                conditions[index] = self:condition(token)
                operand = false
            end
        elseif token == "AND" or token == "OR" then
            operand = true
        elseif token == ")" and depth > 0 then
            depth = depth - 1
        else
            fail("syntax near " .. token)
        end
    end
    if operand or depth ~= 0 then fail("syntax at end") end
    local output, operators = {}, {}
    local precedence = {OR = 1, AND = 2, NOT = 3}
    for index, token in ipairs(tokens) do
        if conditions[index] then
            output[#output + 1] = conditions[index]
        elseif token == "(" or token == "NOT" then
            operators[#operators + 1] = token
        elseif token == ")" then
            while operators[#operators] ~= "(" do output[#output + 1] = table.remove(operators) end
            table.remove(operators)
        else
            while #operators > 0 and operators[#operators] ~= "(" and precedence[operators[#operators]] >= precedence[token] do
                output[#output + 1] = table.remove(operators)
            end
            operators[#operators + 1] = token
        end
    end
    while #operators > 0 do output[#output + 1] = table.remove(operators) end
    return output
end

function Tracker:field_value(issue, field)
    if field == "id" then return issue.number end
    if field == "type" then return issue.kind end
    if field == "status" then return issue.state end
    if field == "priority" then return level(issue) end
    if field == "blocked" then return yes_no(self:blocked(issue)) end
    if field == "done" then return yes_no(done(issue)) end
    if field == "title" then return issue.title:lower() end
    return issue[field]
end

function Tracker:matches(issue, program)
    local stack = {}
    for _, node in ipairs(program) do
        if node == "NOT" then
            local value = table.remove(stack)
            stack[#stack + 1] = not value
        elseif node == "AND" or node == "OR" then
            local right, left = table.remove(stack), table.remove(stack)
            if node == "AND" then
                stack[#stack + 1] = left and right
            else
                stack[#stack + 1] = left or right
            end
        else
            local actual = self:field_value(issue, node.field)
            local expected, operator = node.value, node.operator
            local value
            if operator == "=" then value = actual == expected
            elseif operator == "!=" then value = actual ~= expected
            elseif operator == "~" then value = actual:find(expected, 1, true) ~= nil
            elseif actual == nil then value = false
            elseif operator == "<" then value = actual < expected
            elseif operator == "<=" then value = actual <= expected
            elseif operator == ">" then value = actual > expected
            else value = actual >= expected end
            stack[#stack + 1] = value
        end
    end
    return stack[1]
end

function Tracker:query(text)
    local program, matches = self:compile_query(text), {}
    for _, issue in pairs(self.issues) do
        if self:matches(issue, program) then matches[#matches + 1] = issue end
    end
    table.sort(matches, function(a, b)
        if level(a) ~= level(b) then return level(a) > level(b) end
        return a.number < b.number
    end)
    self:emit("QUERY", #matches)
    for _, issue in ipairs(matches) do
        self:emit(issue.number, issue.kind, issue.priority, issue.state, display(issue.assignee), display(issue.estimate), issue.title)
    end
end

function Tracker:show(issue)
    self:emit("ISSUE", issue.number, issue.kind, issue.priority, issue.state, "blocked", yes_no(self:blocked(issue)))
    self:emit("TITLE", issue.title)
    self:emit("PEOPLE", "assignee", display(issue.assignee), "reviewer", display(issue.reviewer))
    self:emit("PLAN", "estimate", display(issue.estimate), "sprint", display(issue.sprint), "comments", issue.comments)
    self:emit("LINKS", "blocks", number_list(issue.blocks), "blocked_by", number_list(issue.blockers),
        "duplicate_of", display(issue.duplicate), "duplicated_by", number_list(issue.duplicates))
end

function Tracker:board()
    self:emit("BOARD")
    local total, finished = 0, 0
    for _, issue in pairs(self.issues) do
        total = total + 1
        if done(issue) then finished = finished + 1 end
    end
    for _, kind in ipairs(kinds) do
        local parts = {kind}
        for _, state in ipairs(workflows[kind]) do
            local count = 0
            for _, issue in pairs(self.issues) do
                if issue.kind == kind and issue.state == state then count = count + 1 end
            end
            parts[#parts + 1], parts[#parts + 2] = state, count
        end
        self:emit(table.unpack(parts))
    end
    self:emit("TOTAL", total, "open", total - finished, "done", finished)
end

function Tracker:workload()
    local users = sorted_keys(self.users)
    self:emit("WORKLOAD", #users)
    for _, user in ipairs(users) do
        local assigned, progress, review, reviewing, total = 0, 0, 0, 0, 0
        for _, issue in pairs(self.issues) do
            if issue.assignee == user and not done(issue) then
                assigned = assigned + 1
                total = total + points(issue)
                if issue.state == "IN_PROGRESS" then progress = progress + 1 end
                if issue.state == "REVIEW" then review = review + 1 end
            end
            if issue.reviewer == user and issue.state == "REVIEW" then reviewing = reviewing + 1 end
        end
        self:emit(user, "assigned", assigned, "in_progress", progress, "review", review, "reviewing", reviewing, "points", total)
    end
end

function Tracker:list_sprints()
    self:emit("SPRINTS", #self.sprint_order)
    for _, sprint in ipairs(self.sprint_order) do
        if sprint.phase == "PLANNED" then
            self:emit(sprint.name, sprint.phase, self:summary(sprint))
        elseif sprint.phase == "ACTIVE" then
            self:emit(sprint.name, sprint.phase, "start", sprint.start, self:summary(sprint), "remaining", self:remaining(sprint))
        else
            self:emit(sprint.name, sprint.phase, "start", sprint.start, "end", sprint.finish, "velocity", sprint.velocity)
        end
    end
end

function Tracker:burndown(sprint)
    if sprint.phase == "PLANNED" then fail("sprint not started") end
    local last = sprint.phase == "ACTIVE" and self.day or sprint.finish
    self:emit("BURNDOWN", sprint.name, sprint.phase, "days", last - sprint.start + 1)
    local value = 0
    for day = sprint.start, last do
        if sprint.records[day] ~= nil then value = sprint.records[day] end
        self:emit("day", day, value)
    end
end

function Tracker:process(command, args)
    if command == "DAY" then
        local day = tonumber(args[1])
        if day < self.day then fail("day backwards") end
        self.day = day
        self:emit("DAY", day)
    elseif command == "USER" then
        if self.users[args[1]] then fail("user exists") end
        self.users[args[1]] = true
        self:emit("USER", args[1])
    elseif command == "CREATE" then
        local number, kind, priority = tonumber(args[1]), args[2], args[3]
        if self.issues[number] then fail("issue exists") end
        if not workflows[kind] then fail("bad type") end
        if not contains(priorities, priority) then fail("bad priority") end
        local issue = {number = number, kind = kind, priority = priority, title = table.concat(args, " ", 4),
            state = workflows[kind][1], comments = 0, blocks = {}, blockers = {}, duplicates = {}, history = {}}
        self.issues[number] = issue
        self:record(issue, "CREATE " .. kind .. " " .. priority)
        self:emit("CREATE", number, kind, priority, issue.state)
    elseif command == "PRIORITY" then
        local issue, priority = self:issue(args[1]), args[2]
        if not contains(priorities, priority) then fail("bad priority") end
        self:not_done(issue)
        if issue.priority == priority then fail("no change") end
        local old = issue.priority
        issue.priority = priority
        self:record(issue, "PRIORITY " .. old .. " " .. priority)
        self:emit("PRIORITY", issue.number, old, priority)
    elseif command == "ASSIGN" or command == "REVIEWER" then
        self:set_person(command, args)
    elseif command == "ESTIMATE" then
        local issue, estimate = self:issue(args[1]), tonumber(args[2])
        if not estimates[estimate] then fail("bad estimate") end
        self:not_done(issue)
        if issue.estimate == estimate then fail("no change") end
        local old = display(issue.estimate)
        issue.estimate = estimate
        self:record(issue, "ESTIMATE " .. old .. " " .. estimate)
        self:emit("ESTIMATE", issue.number, old, estimate)
    elseif command == "COMMENT" then
        local issue = self:issue(args[1])
        local user = self:user(args[2])
        issue.comments = issue.comments + 1
        self:record(issue, "COMMENT " .. user .. " " .. table.concat(args, " ", 3))
        self:emit("COMMENT", issue.number, issue.comments)
    elseif command == "MOVE" then self:move(args)
    elseif command == "LINK" or command == "UNLINK" then self:link(command, args)
    elseif command == "SPRINT" then self:sprint_command(args)
    elseif command == "QUERY" then self:query(table.concat(args, " "))
    elseif command == "SHOW" then self:show(self:issue(args[1]))
    elseif command == "HISTORY" then
        local issue = self:issue(args[1])
        self:emit("HISTORY", issue.number, #issue.history)
        for _, line in ipairs(issue.history) do self:emit(line) end
    elseif command == "BOARD" then self:board()
    elseif command == "WORKLOAD" then self:workload()
    elseif command == "SPRINTS" then self:list_sprints()
    elseif command == "BURNDOWN" then self:burndown(self:sprint(args[1])) end
end

function Tracker:execute(line)
    self.output = {}
    local words = split(line)
    local command = table.remove(words, 1)
    local ok, err = pcall(function() self:process(command, words) end)
    if not ok then
        if type(err) ~= "table" or not err.message then error(err, 0) end
        self:emit("ERROR", err.message)
    end
    local active = self:active_sprint()
    if active then active.records[self.day] = self:remaining(active) end
    return self.output
end

local tracker = Tracker.new()
local count = tonumber(io.read("*l"))
for _ = 1, count do
    local line = io.read("*l"):gsub("\r$", "")
    for _, output in ipairs(tracker:execute(line)) do io.write(output, "\n") end
end
