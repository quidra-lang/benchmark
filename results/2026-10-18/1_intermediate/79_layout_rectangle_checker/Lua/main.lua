local function words(s)
    local list = {}
    for word in s:gmatch("[^ ]+") do list[#list + 1] = word end
    return list
end
local function keys(t)
    local list = {}
    for key in pairs(t) do list[#list + 1] = key end
    table.sort(list)
    return list
end
local function copy(t) local result = {}; for k, v in pairs(t) do result[k] = v end; return result end
local function notation(r) return string.format("(%d,%d)-(%d,%d)", r.x1, r.y1, r.x2, r.y2) end
local function point(x, y) return string.format("(%d,%d)", x, y) end
local function area(r) return (r.x2 - r.x1) * (r.y2 - r.y1) end
local function encloses(a, b) return a.x1 <= b.x1 and a.y1 <= b.y1 and a.x2 >= b.x2 and a.y2 >= b.y2 end
local function compare(a, b)
    local r = {x1=math.max(a.x1, b.x1), y1=math.max(a.y1, b.y1), x2=math.min(a.x2, b.x2), y2=math.min(a.y2, b.y2)}
    r.ox, r.oy = r.x2 - r.x1, r.y2 - r.y1
    r.gap = math.max(0, -r.ox, -r.oy)
    if r.ox > 0 and r.oy > 0 then r.kind = "overlap"
    elseif r.ox == 0 and r.oy == 0 then r.kind = "corner"
    elseif r.ox >= 0 and r.oy >= 0 then r.kind = "edge"
    else r.kind = "separate"; r.direction = r.ox < 0 and r.oy < 0 and "diagonal" or r.ox < 0 and "x" or "y" end
    return r
end
local function connected(a, b)
    local r = compare(a, b)
    return a.layer == b.layer and (r.kind == "overlap" or r.kind == "edge")
end
local function margins(a, b) return {b.x1 - a.x1, b.y1 - a.y1, a.x2 - b.x2, a.y2 - b.y2} end
local function minimum(list) local value = list[1]; for _, n in ipairs(list) do value = math.min(value, n) end; return value end
local function decimal(numerator, denominator)
    local h = numerator * 100 // denominator
    return string.format("%d.%02d", h // 100, h % 100)
end
local function bounds(list)
    local r = copy(list[1])
    for _, q in ipairs(list) do r.x1, r.y1, r.x2, r.y2 = math.min(r.x1, q.x1), math.min(r.y1, q.y1), math.max(r.x2, q.x2), math.max(r.y2, q.y2) end
    return r
end
local function distinct(list)
    table.sort(list)
    local result = {}
    for _, n in ipairs(list) do if n ~= result[#result] then result[#result + 1] = n end end
    return result
end
local Grid = {}
Grid.__index = Grid
local function makeGrid(list)
    local g = setmetatable({xs={}, ys={}, counts={}}, Grid)
    for _, r in ipairs(list) do g.xs[#g.xs + 1], g.xs[#g.xs + 2] = r.x1, r.x2; g.ys[#g.ys + 1], g.ys[#g.ys + 2] = r.y1, r.y2 end
    g.xs, g.ys = distinct(g.xs), distinct(g.ys)
    if #list == 0 then return g end
    local xi, yi, diff = {}, {}, {}
    for i, x in ipairs(g.xs) do xi[x] = i end
    for i, y in ipairs(g.ys) do yi[y] = i; diff[i] = {}; for x = 1, #g.xs do diff[i][x] = 0 end end
    for _, r in ipairs(list) do
        local a, b, c, d = xi[r.x1], yi[r.y1], xi[r.x2], yi[r.y2]
        diff[b][a], diff[b][c], diff[d][a], diff[d][c] = diff[b][a] + 1, diff[b][c] - 1, diff[d][a] - 1, diff[d][c] + 1
    end
    for y = 1, #g.ys do
        for x = 1, #g.xs do diff[y][x] = diff[y][x] + (y > 1 and diff[y - 1][x] or 0) + (x > 1 and diff[y][x - 1] or 0) - (x > 1 and y > 1 and diff[y - 1][x - 1] or 0) end
        if y < #g.ys then g.counts[y] = {}; for x = 1, #g.xs - 1 do g.counts[y][x] = diff[y][x] end end
    end
    return g
end
function Grid:covered(k, window)
    local total = 0
    for y, row in ipairs(self.counts) do for x, count in ipairs(row) do
        if count >= k then
            local r = {x1=self.xs[x], y1=self.ys[y], x2=self.xs[x + 1], y2=self.ys[y + 1]}
            if window then r = compare(r, window) end
            if r.x1 < r.x2 and r.y1 < r.y2 then total = total + area(r) end
        end
    end end
    return total
end
function Grid:perimeter()
    local total = 0
    for y, row in ipairs(self.counts) do for x, count in ipairs(row) do
        if count > 0 then
            local w, h = self.xs[x + 1] - self.xs[x], self.ys[y + 1] - self.ys[y]
            if x == 1 or row[x - 1] == 0 then total = total + h end
            if x == #row or row[x + 1] == 0 then total = total + h end
            if y == 1 or self.counts[y - 1][x] == 0 then total = total + w end
            if y == #self.counts or self.counts[y + 1][x] == 0 then total = total + w end
        end
    end end
    return total
end
function Grid:empty()
    local best
    for left = 1, #self.xs - 1 do
        local blocked = {}
        for y = 1, #self.counts do blocked[y] = false end
        for right = left, #self.xs - 1 do
            for y = 1, #blocked do blocked[y] = blocked[y] or self.counts[y][right] > 0 end
            local y = 1
            while y <= #blocked do
                if blocked[y] then y = y + 1
                else
                    local start = y
                    while y <= #blocked and not blocked[y] do y = y + 1 end
                    local r = {x1=self.xs[left], y1=self.ys[start], x2=self.xs[right + 1], y2=self.ys[y]}
                    if not best or area(r) > area(best) or area(r) == area(best) and (r.x1 < best.x1 or r.x1 == best.x1 and (r.y1 < best.y1 or r.y1 == best.y1 and r.x2 - r.x1 < best.x2 - best.x1)) then best = r end
                end
            end
        end
    end
    return best
end
function Grid:holes()
    local result, seen = {}, {}
    for y, row in ipairs(self.counts) do seen[y] = {}; for x = 1, #row do seen[y][x] = false end end
    for y, row in ipairs(self.counts) do for x, count in ipairs(row) do
        if count == 0 and not seen[y][x] then
            local queue, outside = {{x, y}}, false
            seen[y][x] = true
            local h = {x1=self.xs[x], y1=self.ys[y], x2=self.xs[x + 1], y2=self.ys[y + 1], area=0, ax=self.xs[x], ay=self.ys[y]}
            local i = 1
            while i <= #queue do
                local xx, yy = queue[i][1], queue[i][2]; i = i + 1
                if xx == 1 or yy == 1 or xx == #row or yy == #self.counts then outside = true end
                h.area = h.area + (self.xs[xx + 1] - self.xs[xx]) * (self.ys[yy + 1] - self.ys[yy])
                h.x1, h.y1, h.x2, h.y2 = math.min(h.x1, self.xs[xx]), math.min(h.y1, self.ys[yy]), math.max(h.x2, self.xs[xx + 1]), math.max(h.y2, self.ys[yy + 1])
                if self.ys[yy] < h.ay or self.ys[yy] == h.ay and self.xs[xx] < h.ax then h.ax, h.ay = self.xs[xx], self.ys[yy] end
                for _, delta in ipairs({{1,0}, {-1,0}, {0,1}, {0,-1}}) do
                    local a, b = xx + delta[1], yy + delta[2]
                    if a >= 1 and a <= #row and b >= 1 and b <= #self.counts and not seen[b][a] and self.counts[b][a] == 0 then seen[b][a] = true; queue[#queue + 1] = {a, b} end
                end
            end
            if not outside then result[#result + 1] = h end
        end
    end end
    table.sort(result, function(a, b) return a.ay < b.ay or a.ay == b.ay and a.ax < b.ax end)
    return result
end
function Grid:pieces()
    local active, result = {}, {}
    for y, row in ipairs(self.counts) do
        local current, x = {}, 1
        while x <= #row do
            if row[x] == 0 then x = x + 1
            else
                local start = x; while x <= #row and row[x] > 0 do x = x + 1 end
                local key = self.xs[start] .. ":" .. self.xs[x]
                local r = active[key] or {x1=self.xs[start], y1=self.ys[y], x2=self.xs[x], y2=self.ys[y + 1]}
                r.y2 = self.ys[y + 1]; current[key] = r
            end
        end
        for key, r in pairs(active) do if not current[key] then result[#result + 1] = r end end
        active = current
    end
    for _, r in pairs(active) do result[#result + 1] = r end
    table.sort(result, function(a, b) return a.y1 < b.y1 or a.y1 == b.y1 and a.x1 < b.x1 end)
    return result
end
local function names(list)
    local result = {}; for _, r in ipairs(list) do result[#result + 1] = r.name end
    return #result > 0 and table.concat(result, " ") or "none"
end
local function nets(list)
    local result, seen = {}, {}
    for _, r in ipairs(list) do
        if not seen[r.name] then
            local group, i = {r}, 1; seen[r.name] = true
            while i <= #group do
                for _, q in ipairs(list) do if not seen[q.name] and connected(group[i], q) then seen[q.name] = true; group[#group + 1] = q end end
                i = i + 1
            end
            table.sort(group, function(a, b) return a.name < b.name end)
            result[#result + 1] = group
        end
    end
    return result
end
local function spacing(list, s)
    local result = {}
    for i, a in ipairs(list) do for j = i + 1, #list do
        local b, r = list[j], compare(a, list[j])
        if r.kind == "corner" or r.kind == "separate" and r.gap < s then result[#result + 1] = {a=a.name, b=b.name, gap=r.gap, direction=r.kind == "corner" and "corner" or r.direction} end
    end end
    table.sort(result, function(a, b) return a.gap < b.gap or a.gap == b.gap and (a.a < b.a or a.a == b.a and a.b < b.b) end)
    return result
end
local C = {rectangles={}, rules={}, history={}, output={}}
function C:emit(format, ...) self.output[#self.output + 1] = string.format(format, ...) end
function C:fail(format, ...) error("error: " .. string.format(format, ...), 0) end
function C:get(name) if not self.rectangles[name] then self:fail("unknown rectangle %s", name) end; return self.rectangles[name] end
function C:list(layer)
    local result = {}
    for _, name in ipairs(keys(self.rectangles)) do local r = self.rectangles[name]; if not layer or r.layer == layer then result[#result + 1] = r end end
    return result
end
function C:require(layer) local list = self:list(layer); if #list == 0 then self:fail("no rectangles on %s", layer) end; return list end
function C:remember(line) self.history[#self.history + 1] = {rectangles=copy(self.rectangles), command=line} end
function C:checkBounds(r) if math.abs(r.x1) > 10000 or math.abs(r.y1) > 10000 or math.abs(r.x2) > 10000 or math.abs(r.y2) > 10000 then self:fail("out of bounds") end end
function C:violationLines(list) for _, v in ipairs(list) do self:emit("%s %s gap %d %s", v.a, v.b, v.gap, v.direction) end end
function C:density(layer, list, g, w)
    local r = bounds(list)
    local columns, rows = (r.x2 - r.x1 + w - 1) // w, (r.y2 - r.y1 + w - 1) // w
    if columns > 20 or rows > 20 then self:fail("too many windows") end
    local values, lowest, highest, lowX, lowY, highX, highY = {}, nil, nil, 0, 0, 0, 0
    for y = 0, rows - 1 do
        values[y] = {}
        for x = 0, columns - 1 do
            local tile = {x1=r.x1 + x * w, y1=r.y1 + y * w, x2=r.x1 + (x + 1) * w, y2=r.y1 + (y + 1) * w}
            local v = g:covered(1, tile); values[y][x] = v
            if lowest == nil or v < lowest then lowest, lowX, lowY = v, x, y end
            if highest == nil or v > highest then highest, highX, highY = v, x, y end
        end
    end
    self:emit("density %s window %d: %dx%d", layer, w, columns, rows)
    for y = rows - 1, 0, -1 do
        local parts = {}; for x = 0, columns - 1 do parts[#parts + 1] = tostring(100 * values[y][x] // (w * w)) end
        self:emit("%s", table.concat(parts, " "))
    end
    self:emit("min %s%% at %s", decimal(100 * lowest, w * w), point(r.x1 + lowX * w, r.y1 + lowY * w))
    self:emit("max %s%% at %s", decimal(100 * highest, w * w), point(r.x1 + highX * w, r.y1 + highY * w))
end
function C:check()
    if not next(self.rules) then self:fail("no rules") end
    local rules = {}; for _, r in pairs(self.rules) do rules[#rules + 1] = r end
    table.sort(rules, function(a, b) return a.kind < b.kind or a.kind == b.kind and (a.inner < b.inner or a.inner == b.inner and a.outer < b.outer) end)
    local total = 0
    for _, r in ipairs(rules) do
        local list, lines = self:list(r.inner), {}
        if r.kind == "spacing" then for _, v in ipairs(spacing(list, r.value)) do lines[#lines + 1] = string.format("%s %s gap %d %s", v.a, v.b, v.gap, v.direction) end
        elseif r.kind == "width" then for _, q in ipairs(list) do local w = math.min(q.x2 - q.x1, q.y2 - q.y1); if w < r.value then lines[#lines + 1] = string.format("%s width %d", q.name, w) end end
        else
            local outer = self:list(r.outer)
            for _, q in ipairs(list) do
                local best
                for _, p in ipairs(outer) do local value = minimum(margins(p, q)); best = best and math.max(best, value) or value end
                if not best then lines[#lines + 1] = q.name .. " best margin none" elseif best < r.value then lines[#lines + 1] = string.format("%s best margin %d", q.name, best) end
            end
        end
        if r.kind == "enclose" then self:emit("enclose %s %s %d: %d violations", r.inner, r.outer, r.value, #lines) else self:emit("%s %s %d: %d violations", r.kind, r.inner, r.value, #lines) end
        for _, line in ipairs(lines) do self:emit("%s", line) end
        total = total + #lines
    end
    self:emit("check: %d violations in %d rules", total, #rules)
end
function C:execute(line)
    local args = words(line); local command = table.remove(args, 1)
    if command == "ADD" then
        if self.rectangles[args[1]] then self:fail("duplicate rectangle %s", args[1]) end
        local r = {name=args[1], layer=args[2], x1=tonumber(args[3]), y1=tonumber(args[4]), x2=tonumber(args[5]), y2=tonumber(args[6])}
        if r.x1 >= r.x2 or r.y1 >= r.y2 then self:fail("invalid rectangle") end
        self:checkBounds(r); self:remember(line); self.rectangles[r.name] = r
        self:emit("added %s %s %s", r.name, r.layer, notation(r)); return
    elseif command == "COPY" or command == "MOVE" or command == "RESIZE" or command == "SPLIT" or command == "LAYER" or command == "DELETE" then
        local original = self:get(args[1]); local r = copy(original)
        if command == "COPY" then
            if self.rectangles[args[2]] then self:fail("duplicate rectangle %s", args[2]) end
            r.name = args[2]
            local dx, dy = tonumber(args[3]), tonumber(args[4]); r.x1, r.x2, r.y1, r.y2 = r.x1 + dx, r.x2 + dx, r.y1 + dy, r.y2 + dy
            self:checkBounds(r); self:remember(line); self.rectangles[r.name] = r; self:emit("copied %s to %s %s", original.name, r.name, notation(r))
        elseif command == "MOVE" then
            local dx, dy = tonumber(args[2]), tonumber(args[3]); r.x1, r.x2, r.y1, r.y2 = r.x1 + dx, r.x2 + dx, r.y1 + dy, r.y2 + dy
            self:checkBounds(r); self:remember(line); self.rectangles[r.name] = r; self:emit("moved %s to %s", r.name, notation(r))
        elseif command == "RESIZE" then
            local w, h = tonumber(args[2]), tonumber(args[3]); if w <= 0 or h <= 0 then self:fail("invalid size") end
            r.x2, r.y2 = r.x1 + w, r.y1 + h
            self:checkBounds(r); self:remember(line); self.rectangles[r.name] = r; self:emit("resized %s to %s", r.name, notation(r))
        elseif command == "SPLIT" then
            if self.rectangles[args[4]] then self:fail("duplicate rectangle %s", args[4]) end
            local pos = tonumber(args[3])
            if args[2] == "x" and (pos <= r.x1 or pos >= r.x2) or args[2] == "y" and (pos <= r.y1 or pos >= r.y2) then self:fail("cut outside %s", r.name) end
            local q = copy(r); q.name = args[4]
            if args[2] == "x" then r.x2, q.x1 = pos, pos else r.y2, q.y1 = pos, pos end
            self:remember(line); self.rectangles[r.name], self.rectangles[q.name] = r, q
            self:emit("split %s at %s=%d: %s %s, %s %s", r.name, args[2], pos, r.name, notation(r), q.name, notation(q))
        elseif command == "LAYER" then
            if r.layer == args[2] then self:fail("already on %s", r.layer) end
            r.layer = args[2]; self:remember(line); self.rectangles[r.name] = r; self:emit("layer %s %s -> %s", r.name, original.layer, r.layer)
        else self:remember(line); self.rectangles[r.name] = nil; self:emit("deleted %s", r.name) end
        return
    elseif command == "UNDO" then
        if #self.history == 0 then self:fail("nothing to undo") end
        local previous = table.remove(self.history); self.rectangles = previous.rectangles; self:emit("undo: %s", previous.command); return
    elseif command == "LIST" then
        local list = self:list(); self:emit("rectangles: %d", #list)
        for _, r in ipairs(list) do self:emit("%s %s %s %dx%d", r.name, r.layer, notation(r), r.x2 - r.x1, r.y2 - r.y1) end
        return
    elseif command == "INFO" then
        local r = self:get(args[1])
        self:emit("%s %s %s %dx%d area %d", r.name, r.layer, notation(r), r.x2 - r.x1, r.y2 - r.y1, area(r))
        for _, kind in ipairs({"overlap", "edge", "corner", "encloses", "enclosed by"}) do
            local selected = {}
            for _, q in ipairs(self:list()) do if q.name ~= r.name then
                local relation = compare(r, q)
                local matched = q.layer == r.layer and relation.kind == kind
                if kind == "encloses" then matched = encloses(r, q) elseif kind == "enclosed by" then matched = encloses(q, r) end
                if matched then selected[#selected + 1] = q end
            end end
            self:emit("%s: %s", ({overlap="overlaps", edge="touches", corner="corners", encloses="encloses", ["enclosed by"]="enclosed by"})[kind], names(selected))
        end
        return
    elseif command == "LAYERS" then
        local layers = {}; for _, r in pairs(self.rectangles) do layers[r.layer] = true end
        local list = keys(layers); self:emit("layers: %d", #list)
        for _, layer in ipairs(list) do local rectangles = self:list(layer); self:emit("%s: %d rectangles, area %d, nets %d", layer, #rectangles, makeGrid(rectangles):covered(1), #nets(rectangles)) end
        return
    elseif command == "OVERLAPS" then
        local list = args[1] and self:require(args[1]) or self:list()
        local overlaps = {}
        for i, a in ipairs(list) do for j = i + 1, #list do local b, r = list[j], compare(a, list[j]); if a.layer == b.layer and r.kind == "overlap" then overlaps[#overlaps + 1] = {a=a, b=b, r=r} end end end
        table.sort(overlaps, function(a, b) return a.a.layer < b.a.layer or a.a.layer == b.a.layer and (a.a.name < b.a.name or a.a.name == b.a.name and a.b.name < b.b.name) end)
        if args[1] then self:emit("overlaps %s: %d", args[1], #overlaps)
        else self:emit("overlaps all layers: %d", #overlaps) end
        for _, p in ipairs(overlaps) do self:emit("%s%s %s %s area %d", args[1] and "" or p.a.layer .. " ", p.a.name, p.b.name, notation(p.r), p.r.ox * p.r.oy) end
        return
    elseif command == "INTERSECT" or command == "ADJACENT" or command == "ENCLOSE" or command == "PATH" then
        local a = self:get(args[1]); local b = self:get(args[2])
        if a.name == b.name then self:fail("same rectangle %s", a.name) end
        local r = compare(a, b)
        if command == "INTERSECT" then
            if r.kind == "overlap" then self:emit("intersect %s %s: %s area %d", a.name, b.name, notation(r), r.ox * r.oy)
            elseif r.kind == "edge" then self:emit("intersect %s %s: segment %s length %d", a.name, b.name, notation(r), r.ox + r.oy)
            elseif r.kind == "corner" then self:emit("intersect %s %s: point %s", a.name, b.name, point(r.x1, r.y1))
            else self:emit("intersect %s %s: none, gap %d", a.name, b.name, r.gap) end
        elseif command == "ADJACENT" then
            if r.kind == "overlap" then self:emit("adjacent %s %s: overlapping", a.name, b.name)
            elseif r.kind == "corner" then self:emit("adjacent %s %s: corner only at %s", a.name, b.name, point(r.x1, r.y1))
            elseif r.kind == "edge" then
                local direction = r.ox == 0 and (a.x2 == r.x1 and "west" or "east") or (a.y2 == r.y1 and "south" or "north")
                self:emit("adjacent %s %s: %s is %s of %s, edge %s, length %d", a.name, b.name, a.name, direction, b.name, notation(r), r.ox + r.oy)
            else self:emit("adjacent %s %s: not adjacent", a.name, b.name) end
        elseif command == "ENCLOSE" then
            local m = margins(a, b); local text = string.format("margins left %d bottom %d right %d top %d", table.unpack(m))
            if minimum(m) >= 0 then self:emit("enclose %s %s: yes, %s, min %d", a.name, b.name, text, minimum(m)) else self:emit("enclose %s %s: no, %s", a.name, b.name, text) end
        else
            if a.layer ~= b.layer then self:fail("different layers") end
            local queue, parents, i = {a}, {[a.name]=false}, 1
            while i <= #queue do for _, q in ipairs(self:list(a.layer)) do if parents[q.name] == nil and connected(queue[i], q) then parents[q.name] = queue[i].name; queue[#queue + 1] = q end end; i = i + 1 end
            if parents[b.name] == nil then self:emit("path %s %s: none", a.name, b.name)
            else local path, name = {}, b.name; while name do table.insert(path, 1, name); name = parents[name] end; self:emit("path %s %s: %s (%d steps)", a.name, b.name, table.concat(path, " -> "), #path - 1) end
        end
        return
    elseif command == "AT" then
        local x, y, parts = tonumber(args[1]), tonumber(args[2]), {}
        for _, r in ipairs(self:list()) do if x >= r.x1 and x <= r.x2 and y >= r.y1 and y <= r.y2 then
            local vertical, horizontal = x == r.x1 or x == r.x2, y == r.y1 or y == r.y2
            parts[#parts + 1] = r.name .. " " .. r.layer .. " " .. (vertical and horizontal and "corner" or (vertical or horizontal) and "edge" or "inside")
        end end
        self:emit("at %s: %s", point(x, y), #parts > 0 and table.concat(parts, ", ") or "none"); return
    elseif command == "NEAREST" then
        local r = self:get(args[1]); local nearest, gap
        for _, q in ipairs(self:list(r.layer)) do if q.name ~= r.name then local value = compare(r, q).gap; if not nearest or value < gap then nearest, gap = q, value end end end
        if nearest then self:emit("nearest %s: %s gap %d", r.name, nearest.name, gap) else self:emit("nearest %s: none", r.name) end
        return
    elseif command == "RULE" then
        local r = {kind=args[1]:lower(), inner=args[2], outer=""}
        if r.kind == "enclose" then r.outer, r.value = args[3], tonumber(args[4]); if r.inner == r.outer then self:fail("same layer %s", r.inner) end else r.value = tonumber(args[3]) end
        self.rules[r.kind .. ":" .. r.inner .. ":" .. r.outer] = r
        if r.kind == "enclose" then self:emit("rule enclose %s %s %d", r.inner, r.outer, r.value) else self:emit("rule %s %s %d", r.kind, r.inner, r.value) end
        return
    elseif command == "CHECK" then self:check(); return end
    local layer = command == "COVER" and args[2] or args[1]
    local list = self:require(layer); local g = makeGrid(list)
    if command == "AREA" then self:emit("area %s: %d", layer, g:covered(1))
    elseif command == "COVER" then local k = tonumber(args[1]); self:emit("cover %s >= %d: %d", layer, k, g:covered(k))
    elseif command == "PERIMETER" then self:emit("perimeter %s: %d", layer, g:perimeter())
    elseif command == "NETS" then
        local groups = nets(list); self:emit("nets %s: %d", layer, #groups)
        for i, group in ipairs(groups) do self:emit("net %d: %s area %d", i, names(group), makeGrid(group):covered(1)) end
    elseif command == "DRC" then local s = tonumber(args[2]); local violations = spacing(list, s); self:emit("drc %s spacing %d: %d violations", layer, s, #violations); self:violationLines(violations)
    elseif command == "BBOX" then local r = bounds(list); self:emit("bbox %s: %s %dx%d, %d rectangles, density %s%%", layer, notation(r), r.x2 - r.x1, r.y2 - r.y1, #list, decimal(100 * g:covered(1), area(r)))
    elseif command == "DENSITY" then self:density(layer, list, g, tonumber(args[2]))
    elseif command == "RENDER" then
        local r = {x1=tonumber(args[2]), y1=tonumber(args[3]), x2=tonumber(args[4]), y2=tonumber(args[5])}
        if r.x1 >= r.x2 or r.y1 >= r.y2 then self:fail("invalid window") end
        if r.x2 - r.x1 > 60 or r.y2 - r.y1 > 40 then self:fail("window too large") end
        self:emit("render %s %s", layer, notation(r))
        for y = r.y2 - 1, r.y1, -1 do
            local row = {}
            for x = r.x1, r.x2 - 1 do local count = 0; for _, q in ipairs(list) do if x >= q.x1 and x < q.x2 and y >= q.y1 and y < q.y2 then count = count + 1 end end; row[#row + 1] = count == 0 and "." or count >= 10 and "*" or tostring(count) end
            self:emit("%s", table.concat(row))
        end
    elseif command == "EMPTY" then local r = g:empty(); if r then self:emit("empty %s: %s area %d", layer, notation(r), area(r)) else self:emit("empty %s: none", layer) end
    elseif command == "HOLES" then local holes = g:holes(); self:emit("holes %s: %d", layer, #holes); for i, h in ipairs(holes) do self:emit("hole %d: area %d, bbox %s", i, h.area, notation(h)) end
    elseif command == "MERGE" then local pieces = g:pieces(); self:emit("merge %s: %d pieces", layer, #pieces); for _, r in ipairs(pieces) do self:emit("%s", notation(r)) end end
end
local count = tonumber(io.read("*l"))
for _ = 1, count do local ok, message = pcall(function() C:execute(io.read("*l")) end); if not ok then C:emit("%s", message) end end
if #C.output > 0 then io.write(table.concat(C.output, "\n"), "\n") end
