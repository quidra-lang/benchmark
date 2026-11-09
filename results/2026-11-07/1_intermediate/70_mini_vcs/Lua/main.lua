local function bad(pattern, ...)
    error(string.format(pattern, ...), 0)
end
local function split(text, limit)
    local result, start = {}, 1
    while not limit or #result + 1 < limit do
        local at = text:find(" ", start, true)
        if not at then
            break
        end
        result[#result + 1] = text:sub(start, at - 1)
        start = at + 1
    end
    result[#result + 1] = text:sub(start)
    return result
end
local function clone(files)
    local result = {}
    for path, text in pairs(files) do
        result[path] = text
    end
    return result
end
local function keys(...)
    local all, result = {}, {}
    for _, files in ipairs({...}) do
        for path in pairs(files) do
            all[path] = true
        end
    end
    for path in pairs(all) do
        result[#result + 1] = path
    end
    table.sort(result)
    return result
end
local function differing(a, b)
    local result = {}
    for _, path in ipairs(keys(a, b)) do
        if a[path] ~= b[path] then
            result[#result + 1] = path
        end
    end
    return result
end
local function same(a, b)
    return #differing(a, b) == 0
end
local function match_path(target, source, path)
    target[path] = source[path]
end
local function three_way(base, ours, theirs)
    local merged, conflicts = {}, {}
    for _, path in ipairs(keys(base, ours, theirs)) do
        if theirs[path] == base[path] or ours[path] == theirs[path] then
            merged[path] = ours[path]
        elseif ours[path] == base[path] then
            merged[path] = theirs[path]
        else
            conflicts[#conflicts + 1] = path
            merged[path] = ours[path]
        end
    end
    return merged, conflicts
end
local function distances(start)
    local result, queue, at = {[start] = 0}, {start}, 1
    while at <= #queue do
        local current = queue[at]
        at = at + 1
        for _, parent in ipairs(current.parents) do
            if result[parent] == nil then
                result[parent] = result[current] + 1
                queue[#queue + 1] = parent
            end
        end
    end
    return result
end
local function ancestor(a, b)
    return distances(b)[a] ~= nil
end
local function merge_base(a, b)
    local da, db, candidates, excluded = distances(a), distances(b), {}, {}
    for c in pairs(da) do
        if db[c] ~= nil then
            candidates[c] = true
        end
    end
    for c in pairs(candidates) do
        for _, parent in ipairs(c.parents) do
            excluded[parent] = true
        end
    end
    local best, best_distance
    for c in pairs(candidates) do
        if not excluded[c] then
            local distance = math.max(da[c], db[c])
            if not best or distance < best_distance or distance == best_distance and c.sequence > best.sequence then
                best, best_distance = c, distance
            end
        end
    end
    return best
end
local function glob(pattern, path)
    local previous = {[0] = true}
    for i = 1, #pattern do
        local c, current = pattern:sub(i, i), {}
        if c == "*" then
            current[0] = previous[0]
        end
        for j = 1, #path do
            if c == "*" then
                current[j] = previous[j] or current[j - 1]
            else
                current[j] = previous[j - 1] and (c == "?" or c == path:sub(j, j))
            end
        end
        previous = current
    end
    return previous[#path] or false
end
local function parent_tree(c)
    return c.parents[1] and c.parents[1].files or {}
end
local function reachable(roots)
    local result = {}
    for _, root in ipairs(roots) do
        for c in pairs(distances(root)) do
            result[c] = true
        end
    end
    return result
end
local Repository = {}
Repository.__index = Repository
function Repository.new()
    local r = setmetatable({commits = {}, branches = {}, tags = {}, attached = "main", work = {}, index = {}, conflicts = {}, stash = {}, ignores = {}, created = 0, output = {}}, Repository)
    r.branches.main = r:create({}, {}, "init")
    return r
end
function Repository:emit(pattern, ...)
    self.output[#self.output + 1] = string.format(pattern, ...)
end
function Repository:head()
    return self.attached and self.branches[self.attached] or self.detached
end
function Repository:move_head(c)
    if self.attached then
        self.branches[self.attached] = c
    else
        self.detached = c
    end
end
function Repository:create(parents, files, message)
    local lines = {"commit " .. self.created}
    for _, parent in ipairs(parents) do
        lines[#lines + 1] = "parent " .. parent.id
    end
    for _, path in ipairs(keys(files)) do
        lines[#lines + 1] = "file " .. path .. " " .. files[path]
    end
    lines[#lines + 1] = "message " .. message
    local text, hash = table.concat(lines, "\n") .. "\n", 0
    for i = 1, #text do
        hash = (hash * 131 + text:byte(i)) % 2147483647
    end
    local c = {id = string.format("%08x", hash), sequence = self.created, parents = {table.unpack(parents)}, files = clone(files), message = message}
    self.created = self.created + 1
    self.commits[c.id] = c
    return c
end
function Repository:record(parents, files, message)
    local c = self:create(parents, files, message)
    self:move_head(c)
    local added, modified, deleted, old = 0, 0, 0, parents[1].files
    for _, path in ipairs(differing(old, files)) do
        if old[path] == nil then
            added = added + 1
        elseif files[path] == nil then
            deleted = deleted + 1
        else
            modified = modified + 1
        end
    end
    self:emit("[%s %s] %s (%d added, %d modified, %d deleted)", self.attached or "detached HEAD", c.id, message, added, modified, deleted)
end
function Repository:revision(rev)
    local at = rev:find("~", 1, true)
    local anchor = at and rev:sub(1, at - 1) or rev
    local c
    if anchor == "HEAD" then
        c = self:head()
    else
        c = self.branches[anchor] or self.tags[anchor] or self.commits[anchor]
    end
    if at then
        for _ = 1, tonumber(rev:sub(at + 1)) do
            if c then
                c = c.parents[1]
            end
        end
    end
    if not c then
        bad("unknown revision '%s'", rev)
    end
    return c
end
function Repository:summary(c)
    local refs = {}
    if self:head() == c then
        refs[#refs + 1] = self.attached and "HEAD -> " .. self.attached or "HEAD"
    end
    for _, name in ipairs(keys(self.branches)) do
        if name ~= self.attached and self.branches[name] == c then
            refs[#refs + 1] = name
        end
    end
    for _, name in ipairs(keys(self.tags)) do
        if self.tags[name] == c then
            refs[#refs + 1] = "tag: " .. name
        end
    end
    return c.id .. (#refs == 0 and "" or " (" .. table.concat(refs, ", ") .. ")") .. " " .. c.message
end
function Repository:changes(a, b)
    local changed = differing(a, b)
    if #changed == 0 then
        self:emit("(no changes)")
        return
    end
    for _, path in ipairs(changed) do
        if a[path] == nil then
            self:emit("A %s: %s", path, b[path])
        elseif b[path] == nil then
            self:emit("D %s: %s", path, a[path])
        else
            self:emit("M %s: %s -> %s", path, a[path], b[path])
        end
    end
end
function Repository:in_progress()
    if self.pending then
        bad("%s in progress", self.pending.kind)
    end
end
function Repository:uncommitted()
    if not same(self.index, self:head().files) then
        return true
    end
    for path in pairs(self.index) do
        if self.work[path] ~= self.index[path] then
            return true
        end
    end
    return false
end
function Repository:require_clean()
    if self:uncommitted() then
        bad("uncommitted changes")
    end
end
function Repository:overwrite(selected)
    table.sort(selected)
    local head = self:head().files
    for _, path in ipairs(selected) do
        if self.index[path] ~= head[path] or self.work[path] ~= head[path] then
            bad("local changes to '%s' would be overwritten", path)
        end
    end
end
function Repository:switch_tree(files)
    local changed = differing(self:head().files, files)
    self:overwrite(changed)
    for _, path in ipairs(changed) do
        match_path(self.index, files, path)
        match_path(self.work, files, path)
    end
end
function Repository:ignored(path)
    if self.index[path] ~= nil or self.conflicts[path] then
        return false
    end
    for _, pattern in ipairs(self.ignores) do
        if glob(pattern, path) then
            return true
        end
    end
    return false
end
function Repository:apply(base, theirs, kind, target, message, parents, base_commit)
    local merged, conflicts = three_way(base, self:head().files, theirs)
    local changed = differing(self:head().files, merged)
    local selected = {table.unpack(changed)}
    for _, path in ipairs(conflicts) do
        selected[#selected + 1] = path
    end
    self:overwrite(selected)
    if kind == "merge" then
        self:emit("Merge base %s", base_commit.id)
    end
    if kind ~= "merge" and #conflicts == 0 and same(merged, self:head().files) then
        self:emit("nothing to commit")
        return
    end
    for _, path in ipairs(changed) do
        match_path(self.index, merged, path)
        match_path(self.work, merged, path)
    end
    if #conflicts == 0 then
        self:record(parents, merged, message)
        return
    end
    self.conflicts = {}
    for _, path in ipairs(conflicts) do
        self.work[path] = "<<<<<<< " .. (self:head().files[path] or "(deleted)") .. " ======= " .. (theirs[path] or "(deleted)") .. " >>>>>>>"
        self.conflicts[path] = true
        self:emit("CONFLICT %s", path)
    end
    self.pending = {kind = kind, target = target}
    if kind == "merge" then
        self:emit("Automatic merge failed; fix conflicts and then commit the result.")
    elseif kind == "revert" then
        self:emit("error: could not revert %s", target.id)
    else
        self:emit("error: could not apply %s", target.id)
    end
end
function Repository:roots(extra)
    local result = {self:head()}
    for _, c in pairs(self.branches) do
        result[#result + 1] = c
    end
    for _, c in pairs(self.tags) do
        result[#result + 1] = c
    end
    if extra then
        for _, entry in ipairs(self.stash) do
            result[#result + 1] = entry.base
        end
        if self.pending then
            result[#result + 1] = self.pending.target
        end
    end
    return result
end
function Repository:command(line)
    local w = split(line)
    local command, h = w[1], self:head()
    if command == "WRITE" then
        local args = split(line, 3)
        self.work[args[2]] = args[3]
    elseif command == "REMOVE" then
        if self.work[w[2]] == nil then
            bad("no such file '%s'", w[2])
        end
        self.work[w[2]] = nil
    elseif command == "IGNORE" then
        self.ignores[#self.ignores + 1] = w[2]
    elseif command == "ADD" then
        local path = w[2]
        if path == "ALL" then
            for _, path in ipairs(keys(self.work, self.index)) do
                if not self:ignored(path) then
                    match_path(self.index, self.work, path)
                end
            end
            self.conflicts = {}
        else
            if self.work[path] ~= nil and self:ignored(path) then
                bad("path '%s' is ignored", path)
            end
            if self.work[path] == nil and self.index[path] == nil and not self.conflicts[path] then
                bad("pathspec '%s' did not match any files", path)
            end
            match_path(self.index, self.work, path)
            self.conflicts[path] = nil
        end
    elseif command == "RM" then
        local path = w[2]
        if self.index[path] == nil then
            bad("pathspec '%s' did not match any files", path)
        end
        self.index[path], self.work[path], self.conflicts[path] = nil, nil, nil
    elseif command == "UNSTAGE" then
        local path = w[2]
        if self.index[path] == nil and h.files[path] == nil then
            bad("pathspec '%s' did not match any files", path)
        end
        match_path(self.index, h.files, path)
    elseif command == "RESTORE" or command == "CAT" then
        local path, files = w[2], command == "CAT" and self.work or self.index
        if #w == 3 then
            files = self:revision(w[3]).files
            if files[path] == nil then
                bad("path '%s' does not exist in '%s'", path, w[3])
            end
        elseif files[path] == nil then
            if command == "CAT" then
                bad("no such file '%s'", path)
            else
                bad("pathspec '%s' did not match any files", path)
            end
        end
        if command == "CAT" then
            self:emit("%s", files[path])
        else
            self.work[path] = files[path]
            if #w == 3 then
                self.index[path] = files[path]
                self.conflicts[path] = nil
            end
        end
    elseif command == "COMMIT" then
        if next(self.conflicts) then
            bad("unresolved conflicts")
        end
        local message, parents = split(line, 2)[2], {h}
        if self.pending and self.pending.kind == "merge" then
            parents[2] = self.pending.target
        elseif same(self.index, h.files) then
            self:emit("nothing to commit")
            return
        end
        self:record(parents, self.index, message)
        self.pending = nil
    elseif command == "AMEND" then
        self:in_progress()
        if #h.parents == 0 then
            bad("cannot amend the root commit")
        end
        self:record(h.parents, self.index, split(line, 2)[2])
    elseif command == "STATUS" then
        if self.attached then
            self:emit("On branch %s", self.attached)
        else
            self:emit("HEAD detached at %s", h.id)
        end
        if self.pending then
            self:emit("%s %s", ({merge = "Merging", revert = "Reverting", ["cherry-pick"] = "Cherry-picking"})[self.pending.kind], self.pending.target.id)
        end
        local printed = false
        for _, path in ipairs(keys(h.files, self.index, self.work, self.conflicts)) do
            if self.conflicts[path] then
                self:emit("UU %s", path)
                printed = true
            elseif self.index[path] ~= nil then
                local x = h.files[path] == nil and "A" or h.files[path] ~= self.index[path] and "M" or "."
                local y = self.work[path] == nil and "D" or self.work[path] ~= self.index[path] and "M" or "."
                if x ~= "." or y ~= "." then
                    self:emit("%s%s %s", x, y, path)
                    printed = true
                end
            else
                if h.files[path] ~= nil then
                    self:emit("D. %s", path)
                    printed = true
                end
                if self.work[path] ~= nil and not self:ignored(path) then
                    self:emit("?? %s", path)
                    printed = true
                end
            end
        end
        if not printed then
            self:emit("nothing to commit, working tree clean")
        end
    elseif command == "LS" then
        local files = w[2] and self:revision(w[2]).files or self.work
        local selected = keys(files)
        if #selected == 0 then
            self:emit("(empty)")
        end
        for _, path in ipairs(selected) do
            self:emit("%s %s", path, files[path])
        end
    elseif command == "DIFF" then
        if #w == 1 then
            local work = {}
            for path in pairs(self.index) do
                match_path(work, self.work, path)
            end
            self:changes(self.index, work)
        elseif #w == 2 then
            self:changes(h.files, self.index)
        else
            local a = self:revision(w[2])
            local b = self:revision(w[3])
            self:changes(a.files, b.files)
        end
    elseif command == "LOG" then
        local c, n, limit = h, 0, w[2] and tonumber(w[2]) or self.created
        while c and n < limit do
            self:emit("%s", self:summary(c))
            n = n + 1
            c = c.parents[1]
        end
    elseif command == "SHOW" then
        local c = self:revision(w[2] or "HEAD")
        self:emit("commit %s", self:summary(c))
        local parents = {}
        for _, parent in ipairs(c.parents) do
            parents[#parents + 1] = parent.id
        end
        self:emit("parents: %s", #parents == 0 and "none" or table.concat(parents, " "))
        self:changes(parent_tree(c), c.files)
    elseif command == "BLAME" then
        local path, c = w[2], h
        if h.files[path] == nil then
            bad("path '%s' does not exist in 'HEAD'", path)
        end
        local value = h.files[path]
        while c.parents[1] and c.parents[1].files[path] == value do
            c = c.parents[1]
        end
        self:emit("%s (%s) %s", c.id, c.message, value)
    elseif command == "BRANCH" or command == "TAG" then
        local refs, label = command == "TAG" and self.tags or self.branches, command == "TAG" and "tag" or "branch"
        if w[2] == "-d" then
            local name = w[3]
            local c = refs[name]
            if not c then
                bad("no such %s '%s'", label, name)
            end
            if command == "BRANCH" then
                if self.attached == name then
                    bad("cannot delete current branch '%s'", name)
                end
                if not ancestor(c, h) then
                    bad("branch '%s' is not fully merged", name)
                end
            end
            refs[name] = nil
            self:emit("Deleted %s %s (was %s)", label, name, c.id)
        else
            local name = w[2]
            if refs[name] then
                bad("%s '%s' already exists", label, name)
            end
            local c = self:revision(w[3] or "HEAD")
            refs[name] = c
            self:emit("Created %s %s at %s", label, name, c.id)
        end
    elseif command == "BRANCHES" then
        if not self.attached then
            self:emit("* (HEAD detached at %s)", h.id)
        end
        for _, name in ipairs(keys(self.branches)) do
            local c = self.branches[name]
            self:emit("%s %s %s %s", name == self.attached and "*" or " ", name, c.id, c.message)
        end
    elseif command == "TAGS" then
        local names = keys(self.tags)
        if #names == 0 then
            self:emit("(no tags)")
        end
        for _, name in ipairs(names) do
            local c = self.tags[name]
            self:emit("%s %s %s", name, c.id, c.message)
        end
    elseif command == "SWITCH" then
        local name, c = w[2], self.branches[w[2]]
        if not c then
            bad("no such branch '%s'", name)
        end
        if name == self.attached then
            self:emit("Already on '%s'", name)
            return
        end
        self:in_progress()
        self:switch_tree(c.files)
        self.attached, self.detached = name, nil
        self:emit("Switched to branch '%s'", name)
    elseif command == "DETACH" then
        local c = self:revision(w[2])
        self:in_progress()
        self:switch_tree(c.files)
        self.attached, self.detached = nil, c
        self:emit("HEAD is now at %s %s", c.id, c.message)
    elseif command == "MERGEBASE" then
        local a = self:revision(w[2])
        local b = self:revision(w[3])
        self:emit("%s", merge_base(a, b).id)
    elseif command == "MERGE" or command == "REVERT" or command == "CHERRYPICK" then
        local c = self:revision(w[2])
        self:in_progress()
        if command == "MERGE" then
            if ancestor(c, h) then
                self:emit("Already up to date")
                return
            end
            if ancestor(h, c) then
                self:switch_tree(c.files)
                self:move_head(c)
                self:emit("Fast-forward %s..%s", h.id, c.id)
                return
            end
        end
        self:require_clean()
        if command == "MERGE" then
            local base = merge_base(h, c)
            self:apply(base.files, c.files, "merge", c, "Merge " .. w[2], {h, c}, base)
        elseif command == "REVERT" then
            self:apply(c.files, parent_tree(c), "revert", c, 'Revert "' .. c.message .. '"', {h})
        else
            self:apply(parent_tree(c), c.files, "cherry-pick", c, c.message, {h})
        end
    elseif command == "REBASE" then
        local upstream = self:revision(w[2])
        self:in_progress()
        if ancestor(upstream, h) then
            self:emit("Already up to date")
            return
        end
        self:require_clean()
        local list, c = {}, h
        while not ancestor(c, upstream) do
            list[#list + 1] = c
            c = c.parents[1]
        end
        for i = 1, #list // 2 do
            list[i], list[#list + 1 - i] = list[#list + 1 - i], list[i]
        end
        local current, picks = upstream.files, {}
        for i, old in ipairs(list) do
            local merged, conflicts = three_way(parent_tree(old), current, old.files)
            if #conflicts > 0 then
                bad("could not rebase %s: conflict in '%s'", old.id, conflicts[1])
            end
            if not same(merged, current) then
                picks[i], current = merged, merged
            end
        end
        self:switch_tree(current)
        local tip = upstream
        for i, old in ipairs(list) do
            if not picks[i] then
                self:emit("skip %s %s", old.id, old.message)
            else
                local c = self:create({tip}, picks[i], old.message)
                self:emit("pick %s -> %s %s", old.id, c.id, old.message)
                tip = c
            end
        end
        self:move_head(tip)
        self:emit("HEAD is now at %s %s", tip.id, tip.message)
    elseif command == "RESET" then
        local c = self:revision(w[3])
        if w[2] == "HARD" then
            for _, path in ipairs(keys(self.index, c.files, self.conflicts)) do
                match_path(self.work, c.files, path)
            end
        end
        if w[2] ~= "SOFT" then
            self.index = clone(c.files)
        end
        self:move_head(c)
        self.conflicts, self.pending = {}, nil
        self:emit("HEAD is now at %s %s", c.id, c.message)
    elseif command == "STASH" then
        local action = w[2]
        if action == "LIST" then
            if #self.stash == 0 then
                self:emit("(no stash entries)")
            end
            for i, entry in ipairs(self.stash) do
                self:emit("stash@{%d}: %s", i - 1, entry.label)
            end
            return
        end
        if action and #self.stash == 0 then
            bad("no stash entries")
        end
        if action == "DROP" then
            local entry = table.remove(self.stash, 1)
            self:emit("Dropped stash@{0}: %s", entry.label)
            return
        end
        self:in_progress()
        if action == "POP" then
            self:require_clean()
            local entry = self.stash[1]
            local merged, conflicts = three_way(entry.base.files, h.files, entry.files)
            if #conflicts > 0 then
                bad("stash conflict in '%s'", conflicts[1])
            end
            local changed = differing(h.files, merged)
            self:overwrite(changed)
            for _, path in ipairs(changed) do
                match_path(self.work, merged, path)
            end
            table.remove(self.stash, 1)
            self:emit("Restored stash@{0}: %s", entry.label)
            self:changes(h.files, merged)
        else
            if not self:uncommitted() then
                self:emit("No local changes to save")
                return
            end
            local saved = {}
            for _, path in ipairs(keys(self.index, h.files)) do
                match_path(saved, self.work, path)
                match_path(self.work, h.files, path)
            end
            self.index = clone(h.files)
            local label = "WIP on " .. (self.attached or "(no branch)") .. ": " .. h.id .. " " .. h.message
            table.insert(self.stash, 1, {label = label, base = h, files = saved})
            self:emit("Saved stash@{0}: %s", label)
        end
    elseif command == "GRAPH" then
        local ordered = {}
        for c in pairs(reachable(self:roots(false))) do
            ordered[#ordered + 1] = c
        end
        table.sort(ordered, function(a, b)
            return a.sequence > b.sequence
        end)
        local lanes = {}
        for _, c in ipairs(ordered) do
            local at
            for i, held in ipairs(lanes) do
                if held == c then
                    at = i
                    break
                end
            end
            if not at then
                lanes[#lanes + 1] = c
                at = #lanes
            end
            local symbols, kept = {}, {}
            for i, held in ipairs(lanes) do
                symbols[i] = held == c and (i == at and "*" or "/") or "|"
                if held ~= c or i == at then
                    kept[#kept + 1] = held
                end
            end
            self:emit("%s %s", table.concat(symbols, " "), self:summary(c))
            lanes = kept
            if #c.parents == 0 then
                table.remove(lanes, at)
            else
                lanes[at] = c.parents[1]
                if c.parents[2] then
                    local found = false
                    for _, held in ipairs(lanes) do
                        if held == c.parents[2] then
                            found = true
                        end
                    end
                    if not found then
                        table.insert(lanes, at + 1, c.parents[2])
                    end
                end
            end
        end
    elseif command == "DESCRIBE" then
        local c = self:revision(w[2] or "HEAD")
        local d, best, distance = distances(c), nil, nil
        for _, name in ipairs(keys(self.tags)) do
            local n = d[self.tags[name]]
            if n ~= nil and (not best or n < distance) then
                best, distance = name, n
            end
        end
        if not best then
            bad("no tag can describe '%s'", c.id)
        end
        if distance == 0 then
            self:emit("%s", best)
        else
            self:emit("%s-%d-g%s", best, distance, c.id)
        end
    elseif command == "GC" then
        local keep, removed = reachable(self:roots(true)), 0
        for id, c in pairs(self.commits) do
            if not keep[c] then
                self.commits[id] = nil
                removed = removed + 1
            end
        end
        self:emit("Removed unreachable commits: %d", removed)
    end
end
local repository = Repository.new()
for line in io.lines() do
    if line == "EXIT" then
        break
    end
    local ok, message = pcall(Repository.command, repository, line)
    if not ok then
        repository:emit("error: %s", message)
    end
end
if #repository.output > 0 then
    io.write(table.concat(repository.output, "\n"), "\n")
end
