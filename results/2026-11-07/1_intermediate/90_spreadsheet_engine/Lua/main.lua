local EMPTY, INVALID = {"Z"}, {"X"}
local function num(n)
    return {"N", n}
end
local function text(s)
    return {"S", s}
end
local function err(s)
    return {"E", s}
end
local function fail(s)
    error(s, 0)
end
local function ref(c, r, f)
    return {"R", c, r, f or 0}
end
local function id(r)
    return r[3] * 26 + r[2] + 1
end
local function label(i)
    i = i - 1
    return string.char(65 + i % 26) .. (i // 26 + 1)
end
local function inside(r)
    return r[2] >= 0 and r[2] < 26 and r[3] >= 0 and r[3] < 99
end
local function range(a, b)
    local c, r, f, d, t, g = a[2], a[3], a[4], b[2], b[3], b[4]
    local ac, ar, bc, br = f & 1, f & 2, g & 1, g & 2
    if c > d then
        c, d, ac, bc = d, c, bc, ac
    end
    if r > t then
        r, t, ar, br = t, r, br, ar
    end
    return {"G", ref(c, r, ac | ar), ref(d, t, bc | br)}
end
local function address(s)
    local c, r = s:match("^([A-Z])([1-9]%d?)$")
    if not c then
        fail("bad address")
    end
    return ref(c:byte() - 65, tonumber(r) - 1)
end
local function area(s)
    local p = s:find(":", 1, true)
    if not p then
        local a = address(s)
        return range(a, a)
    end
    local a = address(s:sub(1, p - 1))
    local b = address(s:sub(p + 1))
    return range(a, b)
end
local function cells(g)
    local out = {}
    for r = g[2][3], g[3][3] do
        for c = g[2][2], g[3][2] do
            out[#out + 1] = r * 26 + c + 1
        end
    end
    return out
end
local function contains(g, r)
    return r[2] >= g[2][2] and r[2] <= g[3][2] and r[3] >= g[2][3] and r[3] <= g[3][3]
end
local levels = {
    {["="] = true, ["<>"] = true, ["<"] = true, ["<="] = true, [">"] = true, [">="] = true},
    {["&"] = true},
    {["+"] = true, ["-"] = true},
    {["*"] = true, ["/"] = true}
}
local function prec(op)
    for i, x in ipairs(levels) do
        if x[op] then
            return i
        end
    end
    return 0
end
local function parse(s)
    local ts, i = {}, 2
    local function syntax(p)
        fail("syntax error at " .. p)
    end
    while i <= #s do
        local p, ch = i, s:sub(i, i)
        if ch == " " then
            i = i + 1
        elseif ch:match("%d") then
            local w = s:sub(i):match("^%d+")
            if #w >= 10 then
                syntax(p)
            end
            ts[#ts + 1] = {num(tonumber(w)), p}
            i = i + #w
        elseif ch == '"' then
            local j = s:find('"', i + 1, true)
            if not j then
                syntax(p)
            end
            ts[#ts + 1] = {text(s:sub(i + 1, j - 1)), p}
            i = j + 1
        elseif ch:match("[A-Za-z$]") then
            local w = s:sub(i):match("^[A-Za-z0-9$]+"):upper()
            i = i + #w
            local ac, c, ar, r = w:match("^(%$?)([A-Z])(%$?)([1-9]%d?)$")
            local x
            if c then
                x =
                    ref(
                    c:byte() - 65,
                    tonumber(r) - 1,
                    (ac ~= "" and 1 or 0) | (ar ~= "" and 2 or 0)
                )
            elseif w:match("^[A-Z][A-Z0-9]*$") then
                x = {s:sub(i):match("^ *%(") and "C" or "W", w}
            else
                syntax(p)
            end
            ts[#ts + 1] = {x, p}
        else
            local op = s:sub(i, i + 1)
            if op ~= "<>" and op ~= "<=" and op ~= ">=" then
                op = ch
            end
            if not ("+-*/&(),:=<>"):find(ch, 1, true) then
                syntax(p)
            end
            ts[#ts + 1] = {{"T", op}, p}
            i = i + #op
        end
    end
    ts[#ts + 1] = {{"END"}, #s + 1}
    i = 1
    local function take(op)
        if ts[i][1][1] == "T" and ts[i][1][2] == op then
            i = i + 1
            return true
        end
        return false
    end
    local function expect(op)
        if not take(op) then
            syntax(ts[i][2])
        end
    end
    local expression, primary
    expression = function(level)
        level = level or 1
        if level == 5 then
            return primary()
        end
        local a = expression(level + 1)
        while ts[i][1][1] == "T" and levels[level][ts[i][1][2]] do
            local op = ts[i][1][2]
            i = i + 1
            a = {"B", op, a, expression(level + 1)}
        end
        return a
    end
    primary = function()
        if take("-") then
            return {"U", primary()}
        end
        local x, p = ts[i][1], ts[i][2]
        i = i + 1
        if x[1] == "N" or x[1] == "S" or x[1] == "W" then
            return x
        end
        if x[1] == "R" then
            if not take(":") then
                return x
            end
            if ts[i][1][1] ~= "R" then
                syntax(ts[i][2])
            end
            local b = ts[i][1]
            i = i + 1
            return range(x, b)
        end
        if x[1] == "C" then
            expect("(")
            local args = {}
            if not take(")") then
                args[#args + 1] = expression()
                while take(",") do
                    args[#args + 1] = expression()
                end
                expect(")")
            end
            return {"F", x[2], args}
        end
        if x[1] == "T" and x[2] == "(" then
            local a = expression()
            expect(")")
            return a
        end
        syntax(p)
    end
    local tree = expression()
    if ts[i][1][1] ~= "END" then
        syntax(ts[i][2])
    end
    return tree
end
local canonical
canonical = function(x)
    local k = x[1]
    if k == "N" then
        return tostring(x[2])
    elseif k == "S" then
        return '"' .. x[2] .. '"'
    elseif k == "W" then
        return x[2]
    elseif k == "X" then
        return "#REF!"
    elseif k == "R" then
        return (x[4] & 1 ~= 0 and "$" or "") ..
            string.char(65 + x[2]) .. (x[4] & 2 ~= 0 and "$" or "") .. (x[3] + 1)
    elseif k == "G" then
        return canonical(x[2]) .. ":" .. canonical(x[3])
    elseif k == "F" then
        local a = {}
        for i, v in ipairs(x[3]) do
            a[i] = canonical(v)
        end
        return x[2] .. "(" .. table.concat(a, ",") .. ")"
    elseif k == "U" then
        local a = canonical(x[2])
        return "-" .. (x[2][1] == "B" and "(" .. a .. ")" or a)
    else
        local a, b = canonical(x[3]), canonical(x[4])
        if x[3][1] == "B" and prec(x[3][2]) < prec(x[2]) then
            a = "(" .. a .. ")"
        end
        if x[4][1] == "B" and prec(x[4][2]) <= prec(x[2]) then
            b = "(" .. b .. ")"
        end
        return a .. x[2] .. b
    end
end
local function display(x)
    return x == EMPTY and "" or tostring(x[2])
end
local function notation(x)
    if x == EMPTY then
        return "(empty)"
    elseif x[1] == "=" then
        return "=" .. canonical(x[2])
    elseif x[1] == "S" then
        return '"' .. x[2] .. '"'
    else
        return display(x)
    end
end
local function number(x)
    if x == EMPTY then
        return num(0)
    elseif x[1] == "S" or x[1] == "G" then
        return err("#VALUE!")
    else
        return x
    end
end
local function string_value(x)
    if x == EMPTY then
        return text("")
    elseif x[1] == "N" then
        return text(tostring(x[2]))
    elseif x[1] == "G" then
        return err("#VALUE!")
    else
        return x
    end
end
local function quotient(a, b)
    local q = math.abs(a) // math.abs(b)
    return (a < 0) == (b < 0) and q or -q
end
local function rewrite(x, f)
    local k = x[1]
    if k == "R" or k == "G" then
        return f(x)
    elseif k == "F" then
        local a = {}
        for i, v in ipairs(x[3]) do
            a[i] = rewrite(v, f)
        end
        return {"F", x[2], a}
    elseif k == "B" then
        return {"B", x[2], rewrite(x[3], f), rewrite(x[4], f)}
    elseif k == "U" or k == "=" then
        return {k, rewrite(x[2], f)}
    else
        return x
    end
end
local function dependencies(x, out)
    out = out or {}
    local k = x[1]
    if k == "R" then
        out[id(x)] = true
    elseif k == "G" then
        for _, i in ipairs(cells(x)) do
            out[i] = true
        end
    elseif k == "F" then
        for _, a in ipairs(x[3]) do
            dependencies(a, out)
        end
    elseif k == "B" then
        dependencies(x[3], out)
        dependencies(x[4], out)
    elseif k == "U" or k == "=" then
        dependencies(x[2], out)
    end
    return out
end
local function grid()
    local a = {}
    for i = 1, 2574 do
        a[i] = EMPTY
    end
    return a
end
local contents, values, deps, history = grid(), grid(), {}, {}
for i = 1, 2574 do
    deps[i] = {}
end
local evaluate, call
local aggregate = {
    SUM = true,
    MIN = true,
    MAX = true,
    COUNT = true,
    AVERAGE = true,
    AND = true,
    OR = true,
    CONCAT = true
}
evaluate = function(x)
    local k = x[1]
    if k == "N" or k == "S" or k == "G" then
        return x
    elseif k == "R" then
        return values[id(x)]
    elseif k == "W" then
        return err("#NAME?")
    elseif k == "X" then
        return err("#REF!")
    elseif k == "U" then
        local a = number(evaluate(x[2]))
        return a[1] == "E" and a or num(-a[2])
    elseif k == "F" then
        return call(x[2], x[3])
    end
    local a, b = evaluate(x[3]), evaluate(x[4])
    local op = x[2]
    if a[1] == "E" then
        return a
    elseif b[1] == "E" then
        return b
    end
    if prec(op) == 1 then
        if a[1] == "G" or b[1] == "G" then
            return err("#VALUE!")
        end
        local blank = (a[1] == "S" or b[1] == "S") and text("") or num(0)
        if a == EMPTY then
            a = blank
        end
        if b == EMPTY then
            b = blank
        end
        local c
        if a[1] ~= b[1] then
            c = a[1] == "N" and -1 or 1
        elseif a[2] == b[2] then
            c = 0
        elseif a[2] < b[2] then
            c = -1
        else
            c = 1
        end
        local yes =
            (op == "=" and c == 0) or (op == "<>" and c ~= 0) or (op == "<" and c < 0) or
            (op == "<=" and c <= 0) or
            (op == ">" and c > 0) or
            (op == ">=" and c >= 0)
        return num(yes and 1 or 0)
    end
    a = op == "&" and string_value(a) or number(a)
    b = op == "&" and string_value(b) or number(b)
    if a[1] == "E" then
        return a
    elseif b[1] == "E" then
        return b
    end
    if op == "&" then
        return text(a[2] .. b[2])
    elseif op == "+" then
        return num(a[2] + b[2])
    elseif op == "-" then
        return num(a[2] - b[2])
    elseif op == "*" then
        return num(a[2] * b[2])
    end
    return b[2] == 0 and err("#DIV/0!") or num(quotient(a[2], b[2]))
end
call = function(name, args)
    if aggregate[name] then
        if #args == 0 then
            return err("#VALUE!")
        end
        local items, ns = {}, {}
        for _, a in ipairs(args) do
            local v = evaluate(a)
            if v[1] == "G" then
                for _, i in ipairs(cells(v)) do
                    items[#items + 1] = values[i]
                end
            else
                items[#items + 1] = v
            end
        end
        for _, v in ipairs(items) do
            if v[1] == "N" then
                ns[#ns + 1] = v[2]
            end
        end
        if name == "COUNT" then
            return num(#ns)
        end
        for _, v in ipairs(items) do
            if v[1] == "E" then
                return v
            end
        end
        if name == "CONCAT" then
            local a = {}
            for i, v in ipairs(items) do
                a[i] = string_value(v)[2]
            end
            return text(table.concat(a))
        end
        local sum, lo, hi, all, any = 0, ns[1] or 0, ns[1] or 0, true, false
        for _, n in ipairs(ns) do
            sum = sum + n
            lo = math.min(lo, n)
            hi = math.max(hi, n)
            all = all and n ~= 0
            any = any or n ~= 0
        end
        if name == "SUM" then
            return num(sum)
        elseif name == "MIN" then
            return num(lo)
        elseif name == "MAX" then
            return num(hi)
        end
        if #ns == 0 then
            return err(name == "AVERAGE" and "#DIV/0!" or "#VALUE!")
        end
        if name == "AVERAGE" then
            return num(quotient(sum, #ns))
        end
        local yes
        if name == "AND" then
            yes = all
        else
            yes = any
        end
        return num(yes and 1 or 0)
    end
    if name == "IF" then
        if #args ~= 2 and #args ~= 3 then
            return err("#VALUE!")
        end
        local c = number(evaluate(args[1]))
        if c[1] == "E" then
            return c
        end
        if c[2] ~= 0 then
            return evaluate(args[2])
        elseif #args == 3 then
            return evaluate(args[3])
        else
            return num(0)
        end
    end
    if name ~= "ABS" and name ~= "NOT" and name ~= "LEN" then
        return err("#NAME?")
    end
    if #args ~= 1 then
        return err("#VALUE!")
    end
    local v = evaluate(args[1])
    v = name == "LEN" and string_value(v) or number(v)
    if v[1] == "E" then
        return v
    end
    return num(
        name == "LEN" and #v[2] or name == "ABS" and math.abs(v[2]) or (v[2] == 0 and 1 or 0)
    )
end
local function recalculate()
    local indices, low, stack, on, cyclic, serial = {}, {}, {}, {}, {}, 0
    for i = 1, 2574 do
        deps[i] = contents[i][1] == "=" and dependencies(contents[i][2]) or {}
        values[i] = contents[i][1] == "=" and EMPTY or contents[i]
    end
    local visit
    visit = function(i)
        indices[i] = serial
        low[i] = serial
        serial = serial + 1
        stack[#stack + 1] = i
        on[i] = true
        for j in pairs(deps[i]) do
            if contents[j][1] == "=" then
                if not indices[j] then
                    visit(j)
                    low[i] = math.min(low[i], low[j])
                elseif on[j] then
                    low[i] = math.min(low[i], indices[j])
                end
            end
        end
        if low[i] == indices[i] then
            local part, j = {}, nil
            repeat
                j = table.remove(stack)
                on[j] = nil
                part[#part + 1] = j
            until j == i
            if #part > 1 or deps[i][i] then
                for _, v in ipairs(part) do
                    cyclic[v] = true
                end
            end
        end
    end
    for i = 1, 2574 do
        if contents[i][1] == "=" and not indices[i] then
            visit(i)
        end
    end
    local done, calculate = {}
    calculate = function(i)
        if contents[i][1] ~= "=" or done[i] then
            return
        end
        done[i] = true
        if cyclic[i] then
            values[i] = err("#CYCLE!")
            return
        end
        for j in pairs(deps[i]) do
            calculate(j)
        end
        local v = evaluate(contents[i][2])
        values[i] = v == EMPTY and num(0) or v[1] == "G" and err("#VALUE!") or v
    end
    for i = 1, 2574 do
        calculate(i)
    end
end
local function replace(next_grid)
    local old = values
    values = grid()
    contents = next_grid
    recalculate()
    local count = 0
    for i = 1, 2574 do
        if notation(old[i]) ~= notation(values[i]) then
            count = count + 1
        end
    end
    return count
end
local function describe(i)
    return label(i) .. ": " .. notation(contents[i]) .. " -> " .. notation(values[i])
end
local function format(xs)
    local a = {}
    for i in pairs(xs) do
        a[#a + 1] = i
    end
    table.sort(a)
    for j, i in ipairs(a) do
        a[j] = label(i)
    end
    return #a == 0 and "none" or table.concat(a, ",")
end
local function execute(line)
    local name, rest = line:match("^(%S+) ?(.*)$")
    if name == "SHOW" then
        return {describe(id(address(rest)))}
    end
    if name == "LIST" then
        local out = {}
        for i = 1, 2574 do
            if contents[i] ~= EMPTY then
                out[#out + 1] = describe(i)
            end
        end
        return #out == 0 and {"(no cells)"} or out
    end
    if name == "DEPS" then
        local i = id(address(rest))
        local ds = {}
        for j = 1, 2574 do
            if deps[j][i] then
                ds[j] = true
            end
        end
        return {rest .. ": precedents=" .. format(deps[i]) .. " dependents=" .. format(ds)}
    end
    if name == "PRINT" then
        local g = area(rest)
        local rw = #tostring(g[3][3] + 1)
        local ws = {}
        local sep = "+" .. string.rep("-", rw) .. "+"
        local head = "|" .. string.rep(" ", rw) .. "|"
        for c = g[2][2], g[3][2] do
            local w = 1
            for r = g[2][3], g[3][3] do
                w = math.max(w, #display(values[r * 26 + c + 1]))
            end
            ws[#ws + 1] = w
            sep = sep .. string.rep("-", w) .. "+"
            head = head .. string.char(65 + c) .. string.rep(" ", w - 1) .. "|"
        end
        local out = {sep, head, sep}
        for r = g[2][3], g[3][3] do
            local s = "|" .. string.format("%" .. rw .. "d", r + 1) .. "|"
            for j, w in ipairs(ws) do
                local v = values[r * 26 + g[2][2] + j]
                local t = display(v)
                local pad = string.rep(" ", w - #t)
                s = s .. (v[1] == "N" and pad .. t or t .. pad) .. "|"
            end
            out[#out + 1] = s
        end
        out[#out + 1] = sep
        return out
    end
    if name == "UNDO" then
        if #history == 0 then
            fail("nothing to undo")
        end
        local e = table.remove(history)
        return {"UNDO " .. e[1] .. " changed=" .. replace(e[2])}
    end
    local next_grid, target = {}, nil
    for i = 1, 2574 do
        next_grid[i] = contents[i]
    end
    if name == "SET" then
        local a, s = rest:match("^(%S+) (.*)$")
        target = id(address(a))
        if s:sub(1, 1) == "=" then
            next_grid[target] = {"=", parse(s)}
        elseif s:match('^"[^"]*"$') then
            next_grid[target] = text(s:sub(2, -2))
        elseif s == "0" or (s:match("^%-?[1-9]%d*$") and #(s:gsub("^-", "")) <= 9) then
            next_grid[target] = num(tonumber(s))
        else
            fail("bad value")
        end
    elseif name == "CLEAR" then
        for _, i in ipairs(cells(area(rest))) do
            next_grid[i] = EMPTY
        end
    elseif name == "COPY" or name == "MOVE" then
        local a, b = rest:match("^(%S+) (%S+)$")
        local source = area(a)
        local dest = address(b)
        local dc, dr = dest[2] - source[2][2], dest[3] - source[2][3]
        local function shift(r, rel)
            return ref(
                r[2] + (rel and r[4] & 1 ~= 0 and 0 or dc),
                r[3] + (rel and r[4] & 2 ~= 0 and 0 or dr),
                r[4]
            )
        end
        local destination = range(shift(source[2], false), shift(source[3], false))
        if not inside(destination[2]) or not inside(destination[3]) then
            fail("out of grid")
        end
        local function transform(x)
            if x[1] == "R" then
                if name == "COPY" then
                    local r = shift(x, true)
                    return inside(r) and r or INVALID
                end
                return contains(source, x) and shift(x, false) or
                    contains(destination, x) and INVALID or
                    x
            end
            if name == "MOVE" and not (contains(source, x[2]) and contains(source, x[3])) then
                return x
            end
            local u, v = shift(x[2], name == "COPY"), shift(x[3], name == "COPY")
            return inside(u) and inside(v) and range(u, v) or INVALID
        end
        if name == "MOVE" then
            for i = 1, 2574 do
                next_grid[i] = rewrite(next_grid[i], transform)
            end
        end
        local moving = {}
        for _, i in ipairs(cells(source)) do
            moving[#moving + 1] = {
                i,
                name == "COPY" and rewrite(contents[i], transform) or next_grid[i]
            }
        end
        if name == "MOVE" then
            for _, e in ipairs(moving) do
                next_grid[e[1]] = EMPTY
            end
        end
        for _, e in ipairs(moving) do
            next_grid[e[1] + dr * 26 + dc] = e[2]
        end
    elseif name == "INSERTROW" or name == "DELETEROW" or name == "INSERTCOL" or name == "DELETECOL" then
        local row, insert = name:sub(-3) == "ROW", name:sub(1, 6) == "INSERT"
        if not (row and rest:match("^[1-9]%d?$") or not row and rest:match("^[A-Z]$")) then
            fail("bad address")
        end
        local at = row and tonumber(rest) - 1 or rest:byte() - 65
        local limit = row and 99 or 26
        local function axis(x)
            return x[row and 3 or 2]
        end
        local function change(x, v)
            return row and ref(x[2], v, x[4]) or ref(v, x[3], x[4])
        end
        if insert then
            for i = 1, 2574 do
                if contents[i] ~= EMPTY and (row and (i - 1) // 26 or (i - 1) % 26) == limit - 1 then
                    fail("last " .. (row and "row" or "column") .. " not empty")
                end
            end
        end
        local function transform(x)
            if x[1] == "R" then
                local v = axis(x)
                if not insert and v == at then
                    return INVALID
                end
                local n = v + (insert and (v >= at and 1 or 0) or (v > at and -1 or 0))
                return n >= limit and INVALID or change(x, n)
            end
            local a, b = axis(x[2]), axis(x[3])
            if not insert and a == at and b == at then
                return INVALID
            end
            local u = a + (insert and (a >= at and 1 or 0) or (a > at and -1 or 0))
            local v = b + (insert and (b >= at and 1 or 0) or (b >= at and -1 or 0))
            return v >= limit and INVALID or range(change(x[2], u), change(x[3], v))
        end
        next_grid = grid()
        for i = 1, 2574 do
            if contents[i] ~= EMPTY then
                local r = ref((i - 1) % 26, (i - 1) // 26)
                local v = axis(r)
                if insert or v ~= at then
                    local t =
                        change(r, v + (insert and (v >= at and 1 or 0) or (v > at and -1 or 0)))
                    next_grid[id(t)] = rewrite(contents[i], transform)
                end
            end
        end
    else
        fail("unknown command")
    end
    history[#history + 1] = {name, contents}
    local count = replace(next_grid)
    return {
        name ..
            (name == "SET" and " " .. label(target) .. "=" .. notation(values[target]) or "") ..
                " changed=" .. count
    }
end
local n = tonumber(io.read("*l"))
for _ = 1, n do
    local line = io.read("*l")
    local ok, out = pcall(execute, line)
    if ok then
        for _, s in ipairs(out) do
            io.write(s, "\n")
        end
    else
        io.write("ERROR ", out, "\n")
    end
end
