local functions = {sin = true, cos = true, tan = true, exp = true, ln = true, sqrt = true}
local function fail(s)
    error(s, 0)
end
local function rational(p, q)
    q = q or 1
    if q == 0 then
        fail("division by zero")
    end
    if q < 0 then
        p, q = -p, -q
    end
    local a, b = math.abs(p), q
    while b ~= 0 do
        a, b = b, a % b
    end
    return {p // a, q // a}
end
local function plus(a, b)
    return rational(a[1] * b[2] + b[1] * a[2], a[2] * b[2])
end
local function times(a, b)
    return rational(a[1] * b[1], a[2] * b[2])
end
local function neg(a)
    return {-a[1], a[2]}
end
local function num(p, q)
    return {kind = 5, q = type(p) == "table" and p or rational(p, q), name = "", args = {}}
end
local function node(k, a, s)
    return {kind = k, q = {0, 1}, name = s or "", args = a or {}}
end
local zero, one, minus, half = num(0), num(1), num(-1), num(1, 2)
local function compare(a, b)
    if a.kind ~= b.kind then
        return a.kind - b.kind
    end
    if a.kind == 5 then
        local d = a.q[1] * b.q[2] - b.q[1] * a.q[2]
        return d == 0 and 0 or d < 0 and -1 or 1
    end
    if a.name ~= b.name then
        return a.name < b.name and -1 or 1
    end
    for i = 1, math.min(#a.args, #b.args) do
        local c = compare(a.args[i], b.args[i])
        if c ~= 0 then
            return c
        end
    end
    return #a.args - #b.args
end
local function equal(a, b)
    return compare(a, b) == 0
end
local function integer(f)
    return f.kind == 5 and f.q[2] == 1
end
local function negative(f)
    return f.kind == 3 and f.args[2].kind == 5 and f.args[2].q[1] < 0
end
local function base(f)
    return f.kind == 3 and f.args[1] or f
end
local function exponent(f)
    return f.kind == 3 and f.args[2] or one
end
local function copy(a)
    local r = {}
    for i, v in ipairs(a) do
        r[i] = v
    end
    return r
end
local function append(a, b)
    for _, v in ipairs(b) do
        a[#a + 1] = v
    end
end
local function coefficient(f)
    if f.kind == 5 then
        return f.q, {}
    end
    if f.kind == 2 then
        if f.args[1].kind == 5 then
            local a = {}
            for i = 2, #f.args do
                a[#a + 1] = f.args[i]
            end
            return f.args[1].q, a
        end
        return {1, 1}, f.args
    end
    return {1, 1}, {f}
end
local function product(c, a)
    if #a == 0 then
        return num(c)
    end
    if c[1] ~= c[2] then
        local r = {num(c)}
        append(r, a)
        return node(2, r)
    end
    return #a == 1 and a[1] or node(2, a)
end
local function exponent_compare(a, b)
    if a.kind == 5 and b.kind ~= 5 then
        return -1
    end
    if a.kind ~= 5 and b.kind == 5 then
        return 1
    end
    return compare(a, b)
end
local function term_compare(a, b)
    local _, x = coefficient(a)
    local _, y = coefficient(b)
    local bases = {}
    for _, list in ipairs({x, y}) do
        for _, f in ipairs(list) do
            local v = base(f)
            local found = false
            for _, s in ipairs(bases) do
                if equal(s, v) then
                    found = true
                    break
                end
            end
            if not found then
                bases[#bases + 1] = v
            end
        end
    end
    table.sort(
        bases,
        function(s, t)
            return compare(s, t) < 0
        end
    )
    for _, f in ipairs(bases) do
        local u, v = zero, zero
        for _, s in ipairs(x) do
            if equal(base(s), f) then
                u = exponent(s)
            end
        end
        for _, s in ipairs(y) do
            if equal(base(s), f) then
                v = exponent(s)
            end
        end
        local c = exponent_compare(v, u)
        if c ~= 0 then
            return c
        end
    end
    return 0
end
local add, mul, power, fn
add = function(operands)
    local terms = {}
    for _, f in ipairs(operands) do
        if f.kind == 1 then
            append(terms, f.args)
        elseif f.kind == 2 and #f.args == 2 and f.args[1].kind == 5 and f.args[2].kind == 1 then
            for _, t in ipairs(f.args[2].args) do
                terms[#terms + 1] = mul {f.args[1], t}
            end
        else
            terms[#terms + 1] = f
        end
    end
    local groups = {}
    for _, f in ipairs(terms) do
        local c, m = coefficient(f)
        local found
        for _, g in ipairs(groups) do
            if #m == #g.m then
                local same = true
                for i, t in ipairs(m) do
                    if not equal(t, g.m[i]) then
                        same = false
                        break
                    end
                end
                if same then
                    found = g
                    break
                end
            end
        end
        if found then
            found.c = plus(found.c, c)
        else
            groups[#groups + 1] = {c = c, m = m}
        end
    end
    local r = {}
    for _, g in ipairs(groups) do
        if g.c[1] ~= 0 then
            r[#r + 1] = product(g.c, g.m)
        end
    end
    table.sort(
        r,
        function(a, b)
            return term_compare(a, b) < 0
        end
    )
    return #r == 0 and zero or #r == 1 and r[1] or node(1, r)
end
mul = function(operands)
    local c, groups, factors = {1, 1}, {}, {}
    for _, f in ipairs(operands) do
        append(factors, f.kind == 2 and f.args or {f})
    end
    for _, f in ipairs(factors) do
        if f.kind == 5 then
            c = times(c, f.q)
        else
            local b = base(f)
            local found
            for _, g in ipairs(groups) do
                if equal(g.b, b) then
                    found = g
                    break
                end
            end
            if found then
                found.a[#found.a + 1] = f
            else
                groups[#groups + 1] = {b = b, a = {f}}
            end
        end
    end
    if c[1] == 0 then
        return zero
    end
    local r = {}
    for _, g in ipairs(groups) do
        if #g.a == 1 then
            r[#r + 1] = g.a[1]
        else
            local xs = {}
            for _, f in ipairs(g.a) do
                xs[#xs + 1] = exponent(f)
            end
            r[#r + 1] = power(g.b, add(xs))
        end
    end
    local regroup = false
    for i, f in ipairs(r) do
        if f.kind == 2 or f.kind == 5 then
            regroup = true
        end
        for j = 1, i - 1 do
            if equal(base(f), base(r[j])) then
                regroup = true
            end
        end
    end
    if regroup then
        table.insert(r, 1, num(c))
        return mul(r)
    end
    table.sort(
        r,
        function(a, b)
            return compare(base(a), base(b)) < 0
        end
    )
    return product(c, r)
end
local function root(v, d)
    if v == 1 then
        return 1
    end
    if d > 20 then
        return nil
    end
    local r = math.floor(v ^ (1 / d) + 0.5)
    for s = math.max(0, r - 1), r + 1 do
        local a = 1
        for _ = 1, d do
            a = a * s
            if a > v then
                break
            end
        end
        if a == v then
            return s
        end
    end
end
local function rational_power(b, n)
    if n < 0 then
        b = rational(b[2], b[1])
        n = -n
    end
    local r = {1, 1}
    while n > 0 do
        if n % 2 == 1 then
            r = times(r, b)
        end
        n = n // 2
        if n > 0 then
            b = times(b, b)
        end
    end
    return num(r)
end
power = function(b, x)
    if equal(x, zero) then
        return one
    end
    if equal(x, one) then
        return b
    end
    if b.kind == 5 then
        if equal(b, one) then
            return one
        end
        if x.kind ~= 5 then
            return node(3, {b, x})
        end
        if b.q[1] == 0 then
            if x.q[1] > 0 then
                return zero
            end
            fail("division by zero")
        end
        if integer(x) then
            return rational_power(b.q, x.q[1])
        end
        if b.q[1] > 0 then
            local s, t = root(b.q[1], x.q[2]), root(b.q[2], x.q[2])
            if s and t then
                return rational_power(rational(s, t), x.q[1])
            end
        end
    elseif integer(x) then
        if b.kind == 3 then
            return power(b.args[1], mul {b.args[2], x})
        end
        if b.kind == 2 then
            local a = {}
            for _, f in ipairs(b.args) do
                a[#a + 1] = power(f, x)
            end
            return mul(a)
        end
    end
    return node(3, {b, x})
end
fn = function(s, a)
    if s == "sqrt" then
        return power(a, half)
    end
    if equal(a, zero) and (s == "sin" or s == "tan") then
        return zero
    end
    if equal(a, zero) and (s == "cos" or s == "exp") then
        return one
    end
    if equal(a, one) and s == "ln" then
        return zero
    end
    if (s == "sin" or s == "cos" or s == "tan") and coefficient(a)[1] < 0 then
        local r = fn(s, mul {minus, a})
        return s == "cos" and r or mul {minus, r}
    end
    if a.kind == 4 and ((s == "exp" and a.name == "ln") or (s == "ln" and a.name == "exp")) then
        return a.args[1]
    end
    return node(4, {a}, s)
end
local function variables(f)
    local seen = {}
    local function visit(a)
        if a.kind == 0 then
            seen[a.name] = true
        end
        for _, t in ipairs(a.args) do
            visit(t)
        end
    end
    visit(f)
    local r = {}
    for s in pairs(seen) do
        r[#r + 1] = s
    end
    table.sort(r)
    return r
end
local function contains(a, v)
    for _, t in ipairs(a) do
        if t == v then
            return true
        end
    end
    return false
end
local function derivative(f, v)
    if f.kind == 5 then
        return zero
    end
    if f.kind == 0 then
        return f.name == v and one or zero
    end
    if f.kind == 1 then
        local a = {}
        for _, t in ipairs(f.args) do
            a[#a + 1] = derivative(t, v)
        end
        return add(a)
    end
    if f.kind == 2 then
        local a = {}
        for i, t in ipairs(f.args) do
            local p = copy(f.args)
            p[i] = derivative(t, v)
            a[#a + 1] = mul(p)
        end
        return add(a)
    end
    if f.kind == 3 then
        local b, x = f.args[1], f.args[2]
        if not contains(variables(x), v) then
            return mul {x, power(b, add {x, minus}), derivative(b, v)}
        end
        if not contains(variables(b), v) then
            return mul {f, fn("ln", b), derivative(x, v)}
        end
        return mul {
            f,
            add {mul {derivative(x, v), fn("ln", b)}, mul {x, derivative(b, v), power(b, minus)}}
        }
    end
    local a, h = f.args[1]
    if f.name == "sin" then
        h = fn("cos", a)
    elseif f.name == "cos" then
        h = mul {minus, fn("sin", a)}
    elseif f.name == "tan" then
        h = power(fn("cos", a), num(-2))
    elseif f.name == "exp" then
        h = f
    else
        h = power(a, minus)
    end
    return mul {h, derivative(a, v)}
end
local function rebuild(f, a)
    if f.kind == 1 then
        return add(a)
    elseif f.kind == 2 then
        return mul(a)
    elseif f.kind == 3 then
        return power(a[1], a[2])
    else
        return fn(f.name, a[1])
    end
end
local function substitute(f, m)
    if f.kind == 0 then
        return m[f.name] or f
    end
    if f.kind == 5 then
        return f
    end
    local a = {}
    for _, t in ipairs(f.args) do
        a[#a + 1] = substitute(t, m)
    end
    return rebuild(f, a)
end
local function terms(f)
    return f.kind == 1 and f.args or {f}
end
local function distribute(a, b)
    local r = {}
    for _, x in ipairs(terms(a)) do
        for _, y in ipairs(terms(b)) do
            r[#r + 1] = mul {x, y}
        end
    end
    return add(r)
end
local function expand(f)
    if f.kind == 0 or f.kind == 5 then
        return f
    end
    local a = {}
    for _, t in ipairs(f.args) do
        a[#a + 1] = expand(t)
    end
    if f.kind == 2 then
        local r = a[1]
        for i = 2, #a do
            r = distribute(r, a[i])
        end
        return r
    end
    if f.kind == 3 and a[1].kind == 1 and integer(a[2]) and a[2].q[1] > 0 then
        local r = a[1]
        for _ = 2, a[2].q[1] do
            r = distribute(r, a[1])
        end
        return r
    end
    return rebuild(f, a)
end
local function numeric(f)
    if f.kind == 5 then
        return f.q[1] / f.q[2]
    end
    if f.kind == 1 or f.kind == 2 then
        local r = f.kind == 1 and 0 or 1
        for _, t in ipairs(f.args) do
            local a = numeric(t)
            r = f.kind == 1 and r + a or r * a
        end
        return r
    end
    if f.kind == 3 then
        local u, z = numeric(f.args[1]), numeric(f.args[2])
        local integral =
            f.args[2].kind == 5 and integer(f.args[2]) or f.args[2].kind ~= 5 and z == math.floor(z)
        if u < 0 and not integral then
            fail("domain error")
        end
        return equal(f.args[2], half) and math.sqrt(u) or u ^ z
    end
    local a = numeric(f.args[1])
    if f.name == "ln" then
        if a <= 0 then
            fail("domain error")
        end
        return math.log(a)
    end
    return math[f.name](a)
end
local show, show_power, factor
local function atomic(f)
    return f.kind == 0 or f.kind == 4 or integer(f) and f.q[1] >= 0 or
        f.kind == 3 and equal(f.args[2], half)
end
local function atom(f)
    return atomic(f) and show(f) or "(" .. show(f) .. ")"
end
show_power = function(b, x)
    return equal(x, half) and "sqrt(" .. show(b) .. ")" or atom(b) .. "^" .. atom(x)
end
factor = function(f)
    if f.kind == 1 then
        return "(" .. show(f) .. ")"
    elseif f.kind == 3 then
        return show_power(f.args[1], f.args[2])
    else
        return show(f)
    end
end
local function quotient(c, a)
    local p, q = math.abs(c[1]), c[2]
    local top, bottom = {}, {}
    if p ~= 1 then
        top[1] = string.format("%d", p)
    end
    if q ~= 1 then
        bottom[1] = string.format("%d", q)
    end
    for _, f in ipairs(a) do
        if negative(f) then
            local r = num(neg(f.args[2].q))
            bottom[#bottom + 1] = equal(r, one) and factor(f.args[1]) or show_power(f.args[1], r)
        else
            top[#top + 1] = factor(f)
        end
    end
    local s = #top == 0 and "1" or table.concat(top, "*")
    if #bottom == 1 then
        s = s .. "/" .. bottom[1]
    elseif #bottom > 1 then
        s = s .. "/(" .. table.concat(bottom, "*") .. ")"
    end
    return (c[1] < 0 and "-" or "") .. s
end
show = function(f)
    if f.kind == 5 then
        return string.format("%d", f.q[1]) ..
            (f.q[2] == 1 and "" or "/" .. string.format("%d", f.q[2]))
    end
    if f.kind == 0 then
        return f.name
    end
    if f.kind == 4 then
        return f.name .. "(" .. show(f.args[1]) .. ")"
    end
    if f.kind == 3 then
        return negative(f) and quotient({1, 1}, {f}) or show_power(f.args[1], f.args[2])
    end
    if f.kind == 2 then
        return quotient(coefficient(f))
    end
    local s = show(f.args[1])
    for i = 2, #f.args do
        local t = show(f.args[i])
        s = s .. (t:sub(1, 1) == "-" and " - " .. t:sub(2) or " + " .. t)
    end
    return s
end
local function parse(text, names)
    local tokens, p = {}, 1
    while p <= #text do
        local c = text:sub(p, p)
        if c == " " then
            p = p + 1
        else
            local t
            if c:match("%d") then
                t = text:sub(p):match("^%d+")
            elseif c:match("[a-z]") then
                t = text:sub(p):match("^[a-z][a-z0-9]*")
            elseif c:match("[A-Z]") then
                t = text:sub(p):match("^[A-Z][A-Z0-9]*")
            elseif c:match("[-+*/^()]") then
                t = c
            else
                fail("invalid character '" .. c .. "'")
            end
            tokens[#tokens + 1] = t
            p = p + #t
        end
    end
    p = 1
    local expression, term, unary, atom_tree
    local function peek()
        return tokens[p] or ""
    end
    local function unexpected()
        fail(p > #tokens and "unexpected end of expression" or "unexpected '" .. peek() .. "'")
    end
    local function accept(s)
        if peek() ~= s then
            return false
        end
        p = p + 1
        return true
    end
    local function expect(s)
        if not accept(s) then
            unexpected()
        end
    end
    atom_tree = function()
        local t = peek()
        if t == "" then
            unexpected()
        end
        if accept("(") then
            local a = expression()
            expect(")")
            return a
        end
        if not t:match("^[a-zA-Z0-9]") then
            unexpected()
        end
        p = p + 1
        if t:match("^%d") then
            return {value = num(tonumber(t))}
        end
        if t:match("^[A-Z]") then
            if not names[t] then
                fail("undefined name '" .. t .. "'")
            end
            return {value = names[t]}
        end
        if not functions[t] then
            return {value = node(0, {}, t)}
        end
        expect("(")
        local a = expression()
        expect(")")
        return {op = t, args = {a}}
    end
    unary = function()
        if accept("-") then
            return {op = "neg", args = {unary()}}
        end
        local a = atom_tree()
        if accept("^") then
            return {op = "^", args = {a, unary()}}
        end
        return a
    end
    term = function()
        local a = unary()
        while peek() == "*" or peek() == "/" do
            local op = tokens[p]
            p = p + 1
            a = {op = op, args = {a, unary()}}
        end
        return a
    end
    expression = function()
        local a = term()
        while peek() == "+" or peek() == "-" do
            local op = tokens[p]
            p = p + 1
            a = {op = op, args = {a, term()}}
        end
        return a
    end
    local function evaluate(t)
        if t.value then
            return t.value
        end
        local a = {}
        for _, s in ipairs(t.args) do
            a[#a + 1] = evaluate(s)
        end
        if t.op == "+" then
            return add(a)
        elseif t.op == "-" then
            return add {a[1], mul {minus, a[2]}}
        elseif t.op == "*" then
            return mul(a)
        elseif t.op == "/" then
            return mul {a[1], power(a[2], minus)}
        elseif t.op == "^" then
            return power(a[1], a[2])
        elseif t.op == "neg" then
            return mul {minus, a[1]}
        else
            return fn(t.op, a[1])
        end
    end
    local t = expression()
    if p <= #tokens then
        unexpected()
    end
    return evaluate(t)
end
local function variable(s)
    return s:match("^[a-z][a-z0-9]*$") ~= nil and not functions[s]
end
local function is_literal(s)
    return s:match("^-?%d+$") or s:match("^-?%d+/%d+$")
end
local function literal(s)
    if not is_literal(s) then
        fail("invalid number '" .. s .. "'")
    end
    local a, b = s:match("^(-?%d+)/(%d+)$")
    return a and num(tonumber(a), tonumber(b)) or num(tonumber(s))
end
local function trim(s)
    return (s:gsub("^ +", ""):gsub(" +$", ""))
end
local function split(s, delimiter)
    local a, p = {}, 1
    while true do
        local i = s:find(delimiter, p, true)
        if not i then
            a[#a + 1] = s:sub(p)
            return a
        end
        a[#a + 1] = s:sub(p, i - 1)
        p = i + #delimiter
    end
end
local signatures = {
    SIMPLIFY = "e",
    EXPAND = "e",
    DIFF = "ev",
    DIFFN = "evn",
    GRAD = "e",
    HESSIAN = "e",
    IMPLICIT = "evv",
    SUBST = "eve",
    EVAL = "ea",
    TANGENT = "evc",
    LIMIT = "evc",
    TAYLOR = "evcn"
}
local function command(line, names)
    local i = line:find(" ", 1, true)
    local c = i and line:sub(1, i - 1) or line
    local arg = i and line:sub(i + 1) or ""
    if c == "LET" then
        local p = arg:find("=", 1, true)
        if not p then
            fail("wrong number of arguments")
        end
        local s = trim(arg:sub(1, p - 1))
        if not s:match("^[A-Z][A-Z0-9]*$") then
            fail("invalid name '" .. s .. "'")
        end
        local f = parse(trim(arg:sub(p + 1)), names)
        names[s] = f
        return {s .. " = " .. show(f)}
    end
    local sig = signatures[c]
    if not sig then
        fail("unknown command " .. c)
    end
    local fields = i and split(arg, ";") or {}
    if c == "EVAL" and #fields ~= 1 and #fields ~= 2 or c ~= "EVAL" and #fields ~= #sig then
        fail("wrong number of arguments")
    end
    local a = {}
    for k, s in ipairs(fields) do
        s = trim(s)
        local kind = sig:sub(k, k)
        if kind == "e" then
            a[k] = parse(s, names)
        elseif kind == "v" then
            if not variable(s) then
                fail("invalid variable '" .. s .. "'")
            end
            a[k] = s
        elseif kind == "n" then
            if not s:match("^[1-8]$") then
                fail("invalid order '" .. s .. "'")
            end
            a[k] = tonumber(s)
        elseif kind == "c" then
            a[k] = literal(s)
        else
            a[k] = s
        end
    end
    local f, v, x, n = a[1], a[2], a[3], a[4]
    local out = {}
    if c == "SIMPLIFY" then
        return {"simplified: " .. show(f)}
    elseif c == "EXPAND" then
        return {"expanded: " .. show(expand(f))}
    elseif c == "DIFF" then
        return {"d/d" .. v .. " = " .. show(derivative(f, v))}
    elseif c == "DIFFN" then
        for k = 1, x do
            f = derivative(f, v)
            out[#out + 1] = "d^" .. k .. "/d" .. v .. "^" .. k .. " = " .. show(f)
        end
        return out
    end
    if c == "GRAD" or c == "HESSIAN" then
        local vs = variables(f)
        if #vs == 0 then
            return {"no variables"}
        end
        for k, s in ipairs(vs) do
            local d = derivative(f, s)
            if c == "GRAD" then
                out[#out + 1] = "d/d" .. s .. " = " .. show(d)
            else
                for j = k, #vs do
                    out[#out + 1] =
                        "d2/d" .. s .. "d" .. vs[j] .. " = " .. show(derivative(d, vs[j]))
                end
            end
        end
        return out
    end
    if c == "IMPLICIT" then
        if v == x then
            fail("same variable")
        end
        return {
            "d" ..
                x ..
                    "/d" ..
                        v ..
                            " = " ..
                                show(mul {minus, derivative(f, v), power(derivative(f, x), minus)})
        }
    end
    if c == "SUBST" then
        return {"substituted: " .. show(substitute(f, {[v] = x}))}
    end
    if c == "EVAL" then
        local values = {}
        for word in (v or ""):gmatch("[^ ]+") do
            local s, t = word:match("^([a-z][a-z0-9]*)=(.*)$")
            if not s or not variable(s) or not is_literal(t) then
                fail("invalid assignment '" .. word .. "'")
            end
            local q = literal(t)
            if values[s] then
                fail("duplicate variable " .. s)
            end
            values[s] = q
        end
        for _, s in ipairs(variables(f)) do
            if not values[s] then
                fail("no value for " .. s)
            end
        end
        local r = substitute(f, values)
        return {r.kind == 5 and "exact: " .. show(r) or string.format("approx: %.6f", numeric(r))}
    end
    local point = {[v] = x}
    if c == "TANGENT" then
        local m = substitute(derivative(f, v), point)
        local y = substitute(f, point)
        local z = node(0, {}, v)
        local t = "tangent: y = " .. show(add {mul {m, z}, y, mul {num(neg(x.q)), m}})
        if equal(m, zero) then
            return {t, "normal: " .. v .. " = " .. show(x)}
        end
        local k = power(m, minus)
        return {t, "normal: y = " .. show(add {mul {minus, k, z}, y, mul {x, k}})}
    end
    if c == "LIMIT" then
        local top, bottom = {}, {}
        for _, t in ipairs(f.kind == 2 and f.args or {f}) do
            if negative(t) then
                bottom[#bottom + 1] = power(t.args[1], num(neg(t.args[2].q)))
            else
                top[#top + 1] = t
            end
        end
        local g, h = mul(top), mul(bottom)
        for k = 0, 5 do
            local u = substitute(g, point)
            local b = substitute(h, point)
            if not equal(b, zero) then
                return {"limit: " .. show(mul {u, power(b, minus)})}
            end
            if not equal(u, zero) then
                return {"limit: unbounded"}
            end
            if k < 5 then
                g, h = derivative(g, v), derivative(h, v)
            end
        end
        return {"limit: unknown"}
    end
    local ds = {f}
    for _ = 1, n do
        ds[#ds + 1] = derivative(ds[#ds], v)
    end
    local ps, fac = {}, 1
    for k = 0, n do
        if k > 0 then
            fac = fac * k
        end
        local co = mul {substitute(ds[k + 1], point), num(1, fac)}
        ps[#ps + 1] = mul {co, power(add {node(0, {}, v), num(neg(x.q))}, num(k))}
    end
    return {"taylor: " .. show(expand(add(ps)))}
end
local names = {}
local count = tonumber(io.read("*l"))
for _ = 1, count do
    local ok, out = pcall(command, io.read("*l"), names)
    if ok then
        for _, line in ipairs(out) do
            io.write(line, "\n")
        end
    else
        io.write("error: ", out, "\n")
    end
end
