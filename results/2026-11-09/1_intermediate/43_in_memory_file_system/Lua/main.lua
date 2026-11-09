local function ascii_less(a, b)
    for i = 1, math.min(#a, #b) do
        local x, y = a:byte(i), b:byte(i)
        if x ~= y then return x < y end
    end
    return #a < #b
end

local function slice(values, first, last)
    local result = {}
    for i = first or 1, last or #values do result[#result + 1] = values[i] end
    return result
end

local function split(text, separator)
    local result, at = {}, 1
    while true do
        local found = text:find(separator, at, true)
        if not found then result[#result + 1] = text:sub(at); return result end
        result[#result + 1] = text:sub(at, found - 1)
        at = found + #separator
    end
end

local function options(args)
    local flags, at = {}, 1
    while at <= #args and args[at]:sub(1, 1) == "-" do
        for i = 2, #args[at] do flags[args[at]:sub(i, i)] = true end
        at = at + 1
    end
    return flags, slice(args, at)
end

local function last_component(path) return path:match("([^/]*)$") end
local function join_path(path, name) return path == "/" and "/" .. name or path .. "/" .. name end
local function invalid_source(path)
    local name = last_component(path)
    return name == "" or name == "." or name == ".."
end
local function children(node, hidden)
    local result = {}
    for name, child in pairs(node.entries) do
        if hidden or name:sub(1, 1) ~= "." then result[#result + 1] = child end
    end
    table.sort(result, function(a, b) return ascii_less(a.name, b.name) end)
    return result
end
local function size(node)
    if node.kind == "l" then return #node.target end
    local count = 0
    if node.kind == "d" then
        for _ in pairs(node.entries) do count = count + 1 end
    else
        for _, line in ipairs(node.lines) do count = count + #line + 1 end
    end
    return count
end
local function links(node)
    if node.kind ~= "d" then return 1 end
    local count = 2
    for _, child in pairs(node.entries) do
        if child.kind == "d" then count = count + 1 end
    end
    return count
end
local function descendant(node, ancestor)
    while true do
        if node == ancestor then return true end
        if node.parent == node then return false end
        node = node.parent
    end
end
local function absolute(node)
    local parts = {}
    while node.parent ~= node do
        table.insert(parts, 1, node.name)
        node = node.parent
    end
    return "/" .. table.concat(parts, "/")
end

local MISSING = "No such file or directory"
local NOT_DIRECTORY = "Not a directory"
local LOOP = "Too many levels of symbolic links"
local Shell = {}
Shell.__index = Shell

function Shell.new(terminal)
    local root = { kind = "d", inode = 1, modified = 0, name = "", entries = {} }
    root.parent = root
    return setmetatable({ root = root, current = root, terminal = terminal, clock = 0, next_inode = 2 }, Shell)
end

function Shell:add(parent, name, node)
    parent.entries[name] = node
    parent.modified = self.clock
    node.parent, node.name = parent, name
end

function Shell:create(parent, name, kind, payload)
    local node = { kind = kind, inode = self.next_inode, modified = self.clock }
    self.next_inode = self.next_inode + 1
    if kind == "d" then node.entries = {}
    elseif kind == "f" then node.lines = payload or {}
    else node.target = payload end
    self:add(parent, name, node)
    return node
end

function Shell:detach(node)
    node.parent.entries[node.name] = nil
    node.parent.modified = self.clock
end

function Shell:write(file, lines, append)
    if append then
        local combined = slice(file.lines)
        for _, line in ipairs(lines) do combined[#combined + 1] = line end
        file.lines = combined
    else
        file.lines = lines
    end
    file.modified = self.clock
end

function Shell:resolve(path, follow, parents)
    if follow == nil then follow = true end
    local expansions = 0
    local function walk(text, base, follow_final, original)
        local node = text:sub(1, 1) == "/" and self.root or base
        local parts = {}
        for part in text:gmatch("[^/]+") do parts[#parts + 1] = part end
        for i, part in ipairs(parts) do
            if node.kind ~= "d" then return { reason = NOT_DIRECTORY } end
            if part == ".." then
                node = node.parent
            elseif part ~= "." then
                local last = i == #parts
                local child = node.entries[part]
                if not child then
                    if original and last then return { reason = MISSING, parent = node, name = part } end
                    if original and parents then child = self:create(node, part, "d")
                    else return { reason = MISSING } end
                end
                if child.kind == "l" and (not last or follow_final) then
                    expansions = expansions + 1
                    if expansions > 8 then return { reason = LOOP } end
                    local result = walk(child.target, node, true, false)
                    if not result.node then return result end
                    child = result.node
                end
                node = child
            end
        end
        return { node = node }
    end
    return walk(path, self.current, follow, true)
end

function Shell:clone(source, parent, name)
    local node = self:create(parent, name, source.kind, source.kind == "f" and source.lines or source.target)
    if source.kind == "d" then
        for _, child in ipairs(children(source, true)) do self:clone(child, node, child.name) end
    end
end

function Shell:move(source_path, destination)
    local function problem(path, reason)
        self.terminal("mv: cannot move '" .. source_path .. "' to '" .. path .. "': " .. reason)
    end
    if invalid_source(source_path) then problem(destination, "Invalid argument"); return end
    local source_result = self:resolve(source_path, false)
    local source = source_result.node
    if not source then self.terminal("mv: cannot stat '" .. source_path .. "': " .. source_result.reason); return end
    local parent, name, display
    local destination_node = self:resolve(destination).node
    if destination_node and destination_node.kind == "d" then
        parent, name = destination_node, last_component(source_path)
        display = join_path(destination, name)
    else
        local result = self:resolve(destination, false)
        if result.parent then parent, name = result.parent, result.name
        elseif result.node then parent, name = result.node.parent, result.node.name
        else problem(destination, result.reason); return end
        display = destination
    end
    local existing = parent.entries[name]
    if source.kind == "d" and descendant(parent, source) then
        self.terminal("mv: cannot move '" .. source_path .. "' to a subdirectory of itself, '" .. display .. "'")
    elseif existing == source then
        self.terminal("mv: '" .. source_path .. "' and '" .. display .. "' are the same file")
    elseif existing and source.kind == "d" and existing.kind ~= "d" then
        self.terminal("mv: cannot overwrite non-directory '" .. display .. "' with directory '" .. source_path .. "'")
    elseif existing and source.kind ~= "d" and existing.kind == "d" then
        self.terminal("mv: cannot overwrite directory '" .. display .. "' with non-directory '" .. source_path .. "'")
    elseif existing and existing.kind == "d" and next(existing.entries) then
        problem(display, "Directory not empty")
    elseif existing == self.current then
        problem(display, "Device or resource busy")
    else
        if existing then self:detach(existing) end
        self:detach(source)
        self:add(parent, name, source)
    end
end

function Shell:copy(source_path, destination, recursive)
    local function problem(path, reason)
        self.terminal("cp: cannot copy '" .. source_path .. "' to '" .. path .. "': " .. reason)
    end
    if invalid_source(source_path) then problem(destination, "Invalid argument"); return end
    local source_result = self:resolve(source_path)
    local source = source_result.node
    if not source then self.terminal("cp: cannot stat '" .. source_path .. "': " .. source_result.reason); return end
    if source.kind == "d" and not recursive then
        self.terminal("cp: -r not specified; omitting directory '" .. source_path .. "'"); return
    end
    local result = self:resolve(destination)
    if not result.node and not result.parent then problem(destination, result.reason); return end
    local display = result.node and result.node.kind == "d" and join_path(destination, last_component(source_path)) or destination
    local target = self:resolve(display, source.kind ~= "d")
    if source.kind == "d" then
        if target.node then problem(display, "File exists")
        elseif descendant(target.parent, source) then
            self.terminal("cp: cannot copy a directory, '" .. source_path .. "', into itself, '" .. display .. "'")
        else self:clone(source, target.parent, target.name) end
    elseif target.parent then
        self:create(target.parent, target.name, "f", source.lines)
    elseif target.node == source then
        self.terminal("cp: '" .. source_path .. "' and '" .. display .. "' are the same file")
    elseif target.node and target.node.kind == "d" then
        self.terminal("cp: cannot overwrite directory '" .. display .. "' with non-directory '" .. source_path .. "'")
    elseif target.node then
        self:write(target.node, source.lines)
    else problem(display, target.reason) end
end

function Shell:read_inputs(command, paths, input, consume)
    if #paths == 0 then consume(input, nil); return end
    for _, path in ipairs(paths) do
        local result = self:resolve(path)
        if not result.node then self.terminal(command .. ": " .. path .. ": " .. result.reason)
        elseif result.node.kind == "d" then self.terminal(command .. ": " .. path .. ": Is a directory")
        else consume(result.node.lines, path) end
    end
end

function Shell:walk(node, path, visit, maximum, depth)
    depth = depth or 0
    visit(node, path, depth)
    if node.kind == "d" and (not maximum or depth < maximum) then
        for _, child in ipairs(children(node, true)) do self:walk(child, join_path(path, child.name), visit, maximum, depth + 1) end
    end
end

local function glob_match(pattern, text)
    local previous = {}
    for i = 1, #text + 1 do previous[i] = i == 1 end
    for j = 1, #pattern do
        local character, following = pattern:sub(j, j), {}
        following[1] = character == "*" and previous[1]
        for i = 1, #text do
            if character == "*" then following[i + 1] = previous[i + 1] or following[i]
            else following[i + 1] = previous[i] and (character == "?" or character == text:sub(i, i)) end
        end
        previous = following
    end
    return previous[#text + 1]
end

local function numeric_prefix(text)
    local negative = text:sub(1, 1) == "-"
    local at, value = negative and 2 or 1, 0
    while at <= #text do
        local digit = text:byte(at) - 48
        if digit < 0 or digit > 9 then break end
        value, at = value * 10 + digit, at + 1
    end
    return negative and -value or value
end

local function lower(text)
    return (text:gsub("[A-Z]", function(character) return string.char(character:byte() + 32) end))
end

function Shell:list(args, output)
    local flags, paths = options(args)
    if #paths == 0 then paths = { "." } end
    for _, path in ipairs(paths) do
        local result = self:resolve(path, not flags.l)
        local node = result.node
        if not node then
            self.terminal("ls: cannot access '" .. path .. "': " .. result.reason)
        else
            local entries = {}
            local function add(name, item)
                entries[#entries + 1] = { name = name, node = item, order = #entries + 1 }
            end
            if node.kind == "d" then
                if #paths >= 2 then output(path .. ":") end
                if flags.a then add(".", node); add("..", node.parent) end
                for _, child in ipairs(children(node, flags.a)) do add(child.name, child) end
            else add(path, node) end
            if flags.t then
                table.sort(entries, function(a, b)
                    if a.node.modified ~= b.node.modified then return a.node.modified > b.node.modified end
                    return a.order < b.order
                end)
            end
            local widths = { 0, 0, 0 }
            for _, entry in ipairs(entries) do
                for i, number in ipairs({ links(entry.node), size(entry.node), entry.node.modified }) do
                    widths[i] = math.max(widths[i], #tostring(number))
                end
            end
            for i = 1, #entries do
                local entry = entries[flags.r and #entries + 1 - i or i]
                if not flags.l then output(entry.name)
                else
                    local item = entry.node
                    local line = item.kind == "f" and "-" or item.kind
                    for j, number in ipairs({ links(item), size(item), item.modified }) do
                        local text = tostring(number)
                        line = line .. " " .. string.rep(" ", widths[j] - #text) .. text
                    end
                    line = line .. " " .. entry.name
                    if item.kind == "l" then line = line .. " -> " .. item.target end
                    output(line)
                end
            end
        end
    end
end

function Shell:find(args, output)
    local at, path = 1, "."
    if args[1] and args[1]:sub(1, 1) ~= "-" then path, at = args[1], 2 end
    local tests = {}
    while at <= #args do tests[args[at]], at = args[at + 1], at + 2 end
    local result = self:resolve(path)
    if not result.node then self.terminal("find: '" .. path .. "': " .. result.reason); return end
    local maximum = tests["-maxdepth"] and tonumber(tests["-maxdepth"], 10)
    self:walk(result.node, path, function(node, display, depth)
        local name = depth == 0 and (path == "/" and "/" or last_component(path)) or node.name
        if (not tests["-name"] or glob_match(tests["-name"], name)) and
            (not tests["-type"] or tests["-type"] == node.kind) then output(display) end
    end, maximum)
end

function Shell:disk_usage(args, output)
    local flags, paths = options(args)
    if #paths == 0 then paths = { "." } end
    local function report(node, path, show)
        local total = node.kind == "d" and 0 or size(node)
        if node.kind == "d" then
            for _, child in ipairs(children(node, true)) do
                total = total + report(child, join_path(path, child.name), not flags.s and (child.kind == "d" or flags.a))
            end
        end
        if show then output(total .. " " .. path) end
        return total
    end
    for _, path in ipairs(paths) do
        local result = self:resolve(path)
        if not result.node then self.terminal("du: cannot access '" .. path .. "': " .. result.reason)
        else report(result.node, path, true) end
    end
end

function Shell:tree(args, output)
    local flags, paths = options(args)
    local path = paths[1] or "."
    local result = self:resolve(path)
    if not result.node then self.terminal("tree: " .. path .. ": " .. result.reason); return end
    if result.node.kind ~= "d" then self.terminal("tree: " .. path .. ": Not a directory"); return end
    local directories, files = 0, 0
    local function draw(directory, prefix)
        local items = children(directory, flags.a)
        for i, node in ipairs(items) do
            local last = i == #items
            local line = prefix .. (last and "`-- " or "|-- ") .. node.name
            if node.kind == "l" then line = line .. " -> " .. node.target end
            output(line)
            if node.kind == "d" then
                directories = directories + 1
                draw(node, prefix .. (last and "    " or "|   "))
            else files = files + 1 end
        end
    end
    output(path)
    draw(result.node, "")
    output(directories .. " " .. (directories == 1 and "directory" or "directories") ..
        ", " .. files .. " " .. (files == 1 and "file" or "files"))
end

function Shell:word_count(args, input, output)
    local flags, paths = options(args)
    if not next(flags) then flags = { l = true, w = true, c = true } end
    local totals = { 0, 0, 0 }
    local function report(counts, name)
        local values = {}
        for i, flag in ipairs({ "l", "w", "c" }) do
            if flags[flag] then values[#values + 1] = tostring(counts[i]) end
        end
        output(table.concat(values, " ") .. (name and " " .. name or ""))
    end
    self:read_inputs("wc", paths, input, function(lines, name)
        local counts = { #lines, 0, 0 }
        for _, line in ipairs(lines) do
            local inside = false
            for i = 1, #line do
                local nonspace = line:byte(i) ~= 32
                if nonspace and not inside then counts[2] = counts[2] + 1 end
                inside = nonspace
            end
            counts[3] = counts[3] + #line + 1
        end
        for i = 1, 3 do totals[i] = totals[i] + counts[i] end
        report(counts, name)
    end)
    if #paths >= 2 then report(totals, "total") end
end

function Shell:ends(command, args, input, output)
    local explicit = args[1] == "-n"
    local count = explicit and args[2] or "10"
    local special = count:sub(1, 1) == "-" or count:sub(1, 1) == "+"
    local amount = tonumber(special and count:sub(2) or count, 10)
    self:read_inputs(command, slice(args, explicit and 3 or 1), input, function(lines)
        local first, last = 1, #lines
        if command == "head" then
            last = special and math.max(0, #lines - amount) or math.min(#lines, amount)
        else
            first = special and math.min(#lines + 1, math.max(1, amount)) or math.max(1, #lines - amount + 1)
        end
        for i = first, last do output(lines[i]) end
    end)
end

function Shell:grep(args, input, output)
    local flags, rest = options(args)
    local pattern = flags.i and lower(rest[1]) or rest[1]
    local paths = slice(rest, 2)
    local function consume(lines, name)
        local prefix = (#paths >= 2 or flags.r) and name .. ":" or ""
        local selected = 0
        for i, line in ipairs(lines) do
            local compared = flags.i and lower(line) or line
            local matched = compared:find(pattern, 1, true) ~= nil
            if matched ~= (not not flags.v) then
                selected = selected + 1
                if not flags.c then output(prefix .. (flags.n and i .. ":" or "") .. line) end
            end
        end
        if flags.c then output(prefix .. selected) end
    end
    if not flags.r then self:read_inputs("grep", paths, input, consume)
    else
        for _, path in ipairs(#paths == 0 and { "." } or paths) do
            local result = self:resolve(path)
            if not result.node then self.terminal("grep: " .. path .. ": " .. result.reason)
            else
                self:walk(result.node, path, function(node, display)
                    if node.kind == "f" then consume(node.lines, display) end
                end)
            end
        end
    end
end

function Shell:sort_lines(args, input, output)
    local flags, paths = options(args)
    local lines = {}
    self:read_inputs("sort", paths, input, function(part)
        for _, line in ipairs(part) do lines[#lines + 1] = line end
    end)
    table.sort(lines, function(a, b)
        if flags.n then
            local x, y = numeric_prefix(a), numeric_prefix(b)
            if x ~= y then return x < y end
        end
        return ascii_less(a, b)
    end)
    for i = 1, #lines do output(lines[flags.r and #lines + 1 - i or i]) end
end

function Shell:unique(args, input, output)
    local flags, paths = options(args)
    self:read_inputs("uniq", paths, input, function(lines)
        local first = 1
        while first <= #lines do
            local after = first + 1
            while after <= #lines and lines[after] == lines[first] do after = after + 1 end
            output((flags.c and (after - first) .. " " or "") .. lines[first])
            first = after
        end
    end)
end

function Shell:execute(text, input, output)
    local words = {}
    for word in text:gmatch("[^ ]+") do words[#words + 1] = word end
    local command, args = words[1], slice(words, 2)
    if command == "pwd" then output(absolute(self.current))
    elseif command == "echo" then output(text:sub(6))
    elseif command == "cd" then
        local back = args[1] == "-"
        if back and not self.previous then self.terminal("cd: OLDPWD not set"); return end
        local path = back and self.previous or args[1] or "/"
        local result = self:resolve(path)
        if not result.node then self.terminal("cd: " .. path .. ": " .. result.reason)
        elseif result.node.kind ~= "d" then self.terminal("cd: " .. path .. ": Not a directory")
        else
            self.previous, self.current = absolute(self.current), result.node
            if back then output(absolute(self.current)) end
        end
    elseif command == "mkdir" then
        local flags, paths = options(args)
        for _, path in ipairs(paths) do
            local result = self:resolve(path, false, flags.p)
            local reason
            if result.parent then self:create(result.parent, result.name, "d")
            elseif not result.node then reason = result.reason
            elseif flags.p then
                local followed = self:resolve(path).node
                if not followed or followed.kind ~= "d" then reason = "File exists" end
            else reason = "File exists" end
            if reason then self.terminal("mkdir: cannot create directory '" .. path .. "': " .. reason) end
        end
    elseif command == "touch" then
        for _, path in ipairs(args) do
            local result = self:resolve(path)
            if result.parent then self:create(result.parent, result.name, "f")
            elseif result.node then result.node.modified = self.clock
            else self.terminal("touch: cannot touch '" .. path .. "': " .. result.reason) end
        end
    elseif command == "cat" then
        self:read_inputs(command, args, input, function(lines)
            for _, line in ipairs(lines) do output(line) end
        end)
    elseif command == "ls" then self:list(args, output)
    elseif command == "stat" then
        for _, path in ipairs(args) do
            local result = self:resolve(path, false)
            local node = result.node
            if not node then self.terminal("stat: cannot stat '" .. path .. "': " .. result.reason)
            else
                local kind
                if node.kind == "d" then kind = "directory"
                elseif node.kind == "l" then kind = "symbolic link"
                else kind = #node.lines == 0 and "regular empty file" or "regular file" end
                output(path .. ": " .. kind .. ", size " .. size(node) .. ", inode " .. node.inode ..
                    ", links " .. links(node) .. ", modified " .. node.modified)
            end
        end
    elseif command == "rm" or command == "rmdir" then
        local flags, paths = {}, args
        if command == "rm" then flags, paths = options(args) end
        local function remove(path)
            local function problem(reason)
                self.terminal(command == "rm" and "rm: cannot remove '" .. path .. "': " .. reason
                    or "rmdir: failed to remove '" .. path .. "': " .. reason)
            end
            local last = last_component(path)
            if last == "." or last == ".." then
                if command == "rm" then self.terminal("rm: refusing to remove '.' or '..' directory: skipping '" .. path .. "'")
                else problem("Invalid argument") end
                return
            end
            local result = self:resolve(path, false)
            local node = result.node
            if not node then
                if not (command == "rm" and flags.f and result.reason == MISSING) then problem(result.reason) end
            elseif command == "rm" and node.kind == "d" and not flags.r then problem("Is a directory")
            elseif command == "rmdir" and node.kind ~= "d" then problem("Not a directory")
            elseif descendant(self.current, node) then problem("Device or resource busy")
            elseif command == "rmdir" and next(node.entries) then problem("Directory not empty")
            else self:detach(node) end
        end
        for _, path in ipairs(paths) do remove(path) end
    elseif command == "mv" or command == "cp" then
        local flags, paths = {}, args
        if command == "cp" then flags, paths = options(args) end
        local destination = paths[#paths]
        if #paths >= 3 then
            local node = self:resolve(destination).node
            if not node or node.kind ~= "d" then
                self.terminal(command .. ": target '" .. destination .. "' is not a directory"); return
            end
        end
        for i = 1, #paths - 1 do
            if command == "mv" then self:move(paths[i], destination)
            else self:copy(paths[i], destination, flags.r) end
        end
    elseif command == "ln" then
        local target, path = args[2], args[3]
        local result = self:resolve(path, false)
        if result.parent then self:create(result.parent, result.name, "l", target)
        else
            self.terminal("ln: failed to create symbolic link '" .. path .. "': " .. (result.node and "File exists" or result.reason))
        end
    elseif command == "readlink" or command == "realpath" then
        local path = args[1]
        local result = self:resolve(path, command == "realpath")
        if not result.node then self.terminal(command .. ": " .. path .. ": " .. result.reason)
        elseif command == "realpath" then output(absolute(result.node))
        elseif result.node.kind == "l" then output(result.node.target)
        else self.terminal("readlink: " .. path .. ": Invalid argument") end
    elseif command == "find" then self:find(args, output)
    elseif command == "du" then self:disk_usage(args, output)
    elseif command == "tree" then self:tree(args, output)
    elseif command == "wc" then self:word_count(args, input, output)
    elseif command == "head" or command == "tail" then self:ends(command, args, input, output)
    elseif command == "grep" then self:grep(args, input, output)
    elseif command == "sort" then self:sort_lines(args, input, output)
    elseif command == "uniq" then self:unique(args, input, output)
    else self.terminal(command .. ": command not found") end
end

function Shell:process(line)
    self.clock = self.clock + 1
    self.terminal(absolute(self.current) .. "$ " .. line)
    local pipeline, redirect = line, nil
    local marker = line:find(" >", 1, true)
    if marker then
        pipeline = line:sub(1, marker - 1)
        local append = line:sub(marker + 2, marker + 2) == ">"
        local path = line:sub(marker + (append and 4 or 3))
        local result = self:resolve(path)
        if result.parent then redirect = self:create(result.parent, result.name, "f")
        elseif result.node and result.node.kind == "f" then
            redirect = result.node
            if not append then self:write(redirect, {}) end
        else
            self.terminal("sh: " .. path .. ": " .. (result.node and "Is a directory" or result.reason))
            return
        end
    end
    local commands, input = split(pipeline, " | "), {}
    for i, command in ipairs(commands) do
        local output = {}
        local emit = i == #commands and not redirect and self.terminal or function(text) output[#output + 1] = text end
        self:execute(command, input, emit)
        input = output
    end
    if redirect and #input > 0 then self:write(redirect, input, true) end
end

local shell = Shell.new(function(line) io.write(line, "\n") end)
for raw_line in io.lines() do
    local line = raw_line:gsub("\r$", "")
    if line == "exit" then break end
    shell:process(line)
end
