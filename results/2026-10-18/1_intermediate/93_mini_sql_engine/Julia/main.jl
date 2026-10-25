struct SqlError <: Exception
    reason::String
end
fail(s) = throw(SqlError(s))
const RESERVED = Set(split("SELECT DISTINCT FROM AS JOIN INNER LEFT OUTER ON WHERE GROUP BY HAVING ORDER ASC DESC LIMIT OFFSET INSERT INTO VALUES UPDATE SET DELETE CREATE TABLE DROP PRIMARY KEY NOT NULL INT TEXT AND OR IS IN BETWEEN LIKE COUNT SUM MIN MAX AVG EXIT"))
const AGGREGATES = ["COUNT", "SUM", "MIN", "MAX", "AVG"]
const COMPARISONS = ["=", "<>", "!=", "<", "<=", ">", ">="]
struct Token
    kind::String
    text::String
    key::String
end
function tokenize(source)
    pattern = r"[ \n]+|--[^\n]*|'[^']*'|[0-9]+|[A-Za-z_][A-Za-z0-9_]*|<>|!=|<=|>=|\|\||[(),.;*/%+\-=<>]"
    tokens = Token[]
    i = 1
    while i <= lastindex(source)
        m = match(pattern, source, i)
        (m === nothing || m.offset != i) && fail("unexpected character '$(source[i])'")
        text = String(m.match)
        i += ncodeunits(text)
        (startswith(text, " ") || startswith(text, "\n") || startswith(text, "--")) && continue
        kind = startswith(text, "'") ? "string" : isdigit(text[1]) ? "integer" : (isletter(text[1]) || text[1] == '_') ? (uppercase(text) in RESERVED ? "keyword" : "name") : "symbol"
        push!(tokens, Token(kind, text, kind == "keyword" ? uppercase(text) : text))
    end
    tokens
end
mutable struct SqlExpr
    kind::String
    op::String
    children::Vector{SqlExpr}
    literal::Any
    table::Union{Nothing,String}
    column::String
    written::String
    index::Int
    negated::Bool
    distinct::Bool
end
SqlExpr(kind; op="", children=SqlExpr[], literal=nothing, table=nothing, column="", written="") = SqlExpr(kind, op, children, literal, table, column, written, 0, false, false)
hasaggregate(e) = e.kind == "aggregate" || any(hasaggregate, e.children)
struct Column
    name::String
    type::String
    notnull::Bool
    keys::Int
end
mutable struct Table
    name::String
    columns::Vector{Column}
    rows::Vector{Vector{Any}}
end
Table(name, columns) = Table(name, columns, Vector{Any}[])
struct TableRef
    name::String
    alias::Union{Nothing,String}
end
scopename(r) = something(r.alias, r.name)
struct Join
    table::TableRef
    outer::Bool
    condition::SqlExpr
end
struct Item
    expr::SqlExpr
    alias::Union{Nothing,String}
    heading::String
end
struct Order
    expr::SqlExpr
    tokens::Vector{Token}
    descending::Bool
end
Base.@kwdef mutable struct Statement
    command::String = ""
    name::String = ""
    columns::Vector{Column} = Column[]
    names::Union{Nothing,Vector{String}} = nothing
    tuples::Vector{Vector{SqlExpr}} = Vector{SqlExpr}[]
    assignments::Vector{Tuple{String,SqlExpr}} = Tuple{String,SqlExpr}[]
    whereexpr::Union{Nothing,SqlExpr} = nothing
    having::Union{Nothing,SqlExpr} = nothing
    distinct::Bool = false
    items::Union{Nothing,Vector{Item}} = nothing
    source::Union{Nothing,TableRef} = nothing
    joins::Vector{Join} = Join[]
    grouping::Vector{SqlExpr} = SqlExpr[]
    orders::Vector{Order} = Order[]
    limit::Union{Nothing,Int} = nothing
    offset::Int = 0
end
mutable struct Parser
    tokens::Vector{Token}
    pos::Int
end
Parser(tokens) = Parser(tokens, 1)
parser_peek(p) = p.tokens[min(p.pos, length(p.tokens))]
at(p, keys) = parser_peek(p).kind in ("keyword", "symbol") && parser_peek(p).key in keys
function parser_take!(p)
    t = parser_peek(p)
    p.pos += 1
    t
end
function accept!(p, key)
    at(p, (key,)) || return false
    p.pos += 1
    true
end
syntax(p) = fail("syntax error at '$(parser_peek(p).text)'")
expect!(p, key) = accept!(p, key) || syntax(p)
function parsename!(p)
    parser_peek(p).kind == "name" || syntax(p)
    parser_take!(p).text
end
function parseinteger!(p)
    parser_peek(p).kind == "integer" || syntax(p)
    parse(Int, parser_take!(p).text)
end
function parselist!(p, f)
    a = [f()]
    while accept!(p, ",")
        push!(a, f())
    end
    a
end
function parenthesized!(p, f)
    expect!(p, "(")
    a = parselist!(p, f)
    expect!(p, ")")
    a
end
function parsealias!(p)
    accept!(p, "AS") && return parsename!(p)
    parser_peek(p).kind == "name" ? parser_take!(p).text : nothing
end
function parseref!(p)
    first = parsename!(p)
    if accept!(p, ".")
        c = parsename!(p)
        return SqlExpr("column", table=first, column=c, written=first * "." * c)
    end
    SqlExpr("column", column=first, written=first)
end
function parsetableref!(p)
    n = parsename!(p)
    TableRef(n, parsealias!(p))
end
parseclause!(p, key) = accept!(p, key) ? parseexpr!(p) : nothing
function parsestatement!(p)
    s = Statement()
    if accept!(p, "CREATE")
        s.command = "CREATE"
        expect!(p, "TABLE")
        s.name = parsename!(p)
        s.columns = parenthesized!(p, function ()
            n = parsename!(p)
            at(p, ("INT", "TEXT")) || syntax(p)
            type = parser_take!(p).key
            keys = 0
            nn = false
            while at(p, ("PRIMARY", "NOT"))
                if accept!(p, "PRIMARY")
                    expect!(p, "KEY")
                    keys += 1
                else
                    expect!(p, "NOT")
                    expect!(p, "NULL")
                    nn = true
                end
            end
            Column(n, type, nn || keys > 0, keys)
        end)
    elseif accept!(p, "DROP")
        s.command = "DROP"
        expect!(p, "TABLE")
        s.name = parsename!(p)
    elseif accept!(p, "INSERT")
        s.command = "INSERT"
        expect!(p, "INTO")
        s.name = parsename!(p)
        at(p, ("(",)) && (s.names = parenthesized!(p, () -> parsename!(p)))
        expect!(p, "VALUES")
        s.tuples = parselist!(p, () -> parenthesized!(p, () -> parseexpr!(p)))
    elseif accept!(p, "UPDATE")
        s.command = "UPDATE"
        s.name = parsename!(p)
        expect!(p, "SET")
        s.assignments = parselist!(p, function ()
            n = parsename!(p)
            expect!(p, "=")
            (n, parseexpr!(p))
        end)
        s.whereexpr = parseclause!(p, "WHERE")
    elseif accept!(p, "DELETE")
        s.command = "DELETE"
        expect!(p, "FROM")
        s.name = parsename!(p)
        s.whereexpr = parseclause!(p, "WHERE")
    elseif accept!(p, "SELECT")
        s.command = "SELECT"
        s.distinct = accept!(p, "DISTINCT")
        if !accept!(p, "*")
            s.items = parselist!(p, function ()
                start = p.pos
                e = parseexpr!(p)
                tokens = p.tokens[start:p.pos-1]
                alias = parsealias!(p)
                heading = ""
                for i in eachindex(tokens)
                    i > 1 && tokens[i].kind != "symbol" && tokens[i-1].kind != "symbol" && (heading *= " ")
                    heading *= tokens[i].text
                end
                Item(e, alias, something(alias, e.kind == "column" && tokens[1].kind == "name" ? e.column : heading))
            end)
        end
        expect!(p, "FROM")
        s.source = parsetableref!(p)
        while at(p, ("JOIN", "LEFT", "INNER"))
            outer = accept!(p, "LEFT")
            accept!(p, outer ? "OUTER" : "INNER")
            expect!(p, "JOIN")
            t = parsetableref!(p)
            expect!(p, "ON")
            push!(s.joins, Join(t, outer, parseexpr!(p)))
        end
        s.whereexpr = parseclause!(p, "WHERE")
        if accept!(p, "GROUP")
            expect!(p, "BY")
            s.grouping = parselist!(p, () -> parseref!(p))
        end
        s.having = parseclause!(p, "HAVING")
        if accept!(p, "ORDER")
            expect!(p, "BY")
            s.orders = parselist!(p, function ()
                start = p.pos
                e = parseexpr!(p)
                tokens = p.tokens[start:p.pos-1]
                descending = accept!(p, "DESC")
                descending || accept!(p, "ASC")
                Order(e, tokens, descending)
            end)
        end
        if accept!(p, "LIMIT")
            s.limit = parseinteger!(p)
            accept!(p, "OFFSET") && (s.offset = parseinteger!(p))
        end
    elseif accept!(p, "EXIT")
        s.command = "EXIT"
    end
    expect!(p, ";")
    s
end
function parsebinary!(p, ops, operand)
    e = operand()
    while at(p, ops)
        op = parser_take!(p).key
        e = SqlExpr("binary", op=op, children=[e, operand()])
    end
    e
end
parseexpr!(p) = parsebinary!(p, ("OR",), () -> parseand!(p))
parseand!(p) = parsebinary!(p, ("AND",), () -> parsenot!(p))
parsenot!(p) = accept!(p, "NOT") ? SqlExpr("unary", op="NOT", children=[parsenot!(p)]) : parsecomparison!(p)
function parsecomparison!(p)
    e = parseadditive!(p)
    if at(p, COMPARISONS)
        op = parser_take!(p).key
        return SqlExpr("binary", op=op, children=[e, parseadditive!(p)])
    end
    if accept!(p, "IS")
        n = accept!(p, "NOT")
        expect!(p, "NULL")
        r = SqlExpr("isnull", children=[e])
        r.negated = n
        return r
    end
    n = accept!(p, "NOT")
    r = nothing
    if accept!(p, "IN")
        r = SqlExpr("in", children=[e; parenthesized!(p, () -> parseexpr!(p))])
    elseif accept!(p, "BETWEEN")
        low = parseadditive!(p)
        expect!(p, "AND")
        r = SqlExpr("between", children=[e, low, parseadditive!(p)])
    elseif accept!(p, "LIKE")
        r = SqlExpr("like", children=[e, parseadditive!(p)])
    elseif n
        syntax(p)
    end
    r === nothing && return e
    r.negated = n
    r
end
parseadditive!(p) = parsebinary!(p, ("+", "-", "||"), () -> parsemultiplicative!(p))
parsemultiplicative!(p) = parsebinary!(p, ("*", "/", "%"), () -> parseunary!(p))
parseunary!(p) = accept!(p, "-") ? SqlExpr("unary", op="-", children=[parseunary!(p)]) : parseprimary!(p)
function parseprimary!(p)
    parser_peek(p).kind == "integer" && return SqlExpr("literal", literal=parse(Int64, parser_take!(p).text))
    if parser_peek(p).kind == "string"
        t = parser_take!(p).text
        return SqlExpr("literal", literal=t[2:end-1])
    end
    accept!(p, "NULL") && return SqlExpr("literal")
    parser_peek(p).kind == "name" && return parseref!(p)
    if at(p, AGGREGATES)
        n = parser_take!(p).key
        expect!(p, "(")
        e = SqlExpr("aggregate", op=n)
        if !(n == "COUNT" && accept!(p, "*"))
            e.distinct = accept!(p, "DISTINCT")
            e.children = [parseexpr!(p)]
        end
        expect!(p, ")")
        return e
    end
    if accept!(p, "(")
        e = parseexpr!(p)
        expect!(p, ")")
        return e
    end
    syntax(p)
end
struct Entry
    name::String
    table::Table
    offset::Int
end
mutable struct Scope
    entries::Vector{Entry}
    width::Int
end
Scope() = Scope(Entry[], 0)
function add!(scope, name, table)
    any(e -> e.name == name, scope.entries) && fail("duplicate table name $name")
    push!(scope.entries, Entry(name, table, scope.width))
    scope.width += length(table.columns)
end
function resolve!(scope, e)
    selected = scope.entries
    if e.table !== nothing
        selected = filter(entry -> entry.name == e.table, selected)
        isempty(selected) && fail("unknown table $(e.table)")
    end
    candidates = Tuple{Int,String}[]
    for entry in selected, (i, c) in enumerate(entry.table.columns)
        c.name == e.column && push!(candidates, (entry.offset+i, c.type))
    end
    isempty(candidates) && fail("unknown column $(e.written)")
    length(candidates) > 1 && fail("ambiguous column $(e.column)")
    e.index = candidates[1][1]
    candidates[1][2]
end
valuetype(v) = v === nothing ? "NULL" : v isa Integer ? "INT" : "TEXT"
written(v) = v === nothing ? "NULL" : string(v)
function require(a, b, op)
    (a == b || a == "NULL" || b == "NULL") || fail("type mismatch for $op")
end
function check(e, scope, allowed=false, grouped=nothing, inside=false)
    e.kind == "literal" && return valuetype(e.literal)
    if e.kind == "column"
        t = resolve!(scope, e)
        grouped !== nothing && !inside && !(e.index in grouped) && fail("column $(e.written) is not grouped")
        return t
    end
    if e.kind == "aggregate"
        (!allowed || inside) && fail("misuse of aggregate $(e.op)")
        isempty(e.children) && return "INT"
        t = check(e.children[1], scope, allowed, grouped, true)
        e.op in ("SUM", "AVG") && require(t, "INT", e.op)
        return e.op in ("MIN", "MAX") ? t : "INT"
    end
    types = [check(c, scope, allowed, grouped, inside) for c in e.children]
    if e.kind == "unary"
        require(types[1], "INT", e.op)
    elseif e.kind == "binary"
        if e.op in COMPARISONS
            require(types[1], types[2], e.op)
        else
            t = e.op == "||" ? "TEXT" : "INT"
            for a in types
                require(a, t, e.op)
            end
            return t
        end
    elseif e.kind in ("in", "between")
        for t in types[2:end]
            require(t, types[1], e.kind == "in" ? "IN" : "BETWEEN")
        end
    elseif e.kind == "like"
        for t in types
            require(t, "TEXT", "LIKE")
        end
    end
    "INT"
end
function condition(e, scope, clause, allowed=false, grouped=nothing)
    e === nothing || require(check(e, scope, allowed, grouped), "INT", clause)
end
truth(v) = v !== nothing && v != 0
logicalnot(v) = v === nothing ? nothing : Int(!truth(v))
function compare(a, b)
    a == b && return 0
    a === nothing && return -1
    b === nothing && return 1
    a < b ? -1 : 1
end
function operation(op, a, b)
    op == "AND" && return a == 0 || b == 0 ? 0 : (a === nothing || b === nothing ? nothing : 1)
    op == "OR" && return truth(a) || truth(b) ? 1 : (a === nothing || b === nothing ? nothing : 0)
    (a === nothing || b === nothing) && return nothing
    op == "+" && return a + b
    op == "-" && return a - b
    op == "*" && return a * b
    op == "/" && return b == 0 ? nothing : div(a, b)
    op == "%" && return b == 0 ? nothing : rem(a, b)
    op == "||" && return a * b
    op == "=" && return Int(a == b)
    op in ("!=", "<>") && return Int(a != b)
    op == "<" && return Int(a < b)
    op == "<=" && return Int(a <= b)
    op == ">" && return Int(a > b)
    Int(a >= b)
end
function likematch(text, pattern)
    a = collect(text)
    matched = [true; falses(length(a))]
    for c in pattern
        if c == '%'
            for i in 2:length(matched)
                matched[i] = matched[i] || matched[i-1]
            end
        else
            for i in length(matched):-1:2
                matched[i] = matched[i-1] && (c == '_' || c == a[i-1])
            end
            matched[1] = false
        end
    end
    matched[end]
end
function evaluate(e, row, group=Vector{Any}[])
    e.kind == "literal" && return e.literal
    e.kind == "column" && return row[e.index]
    if e.kind == "aggregate"
        isempty(e.children) && return length(group)
        values = filter(!isnothing, [evaluate(e.children[1], r) for r in group])
        e.distinct && (values = unique(values))
        e.op == "COUNT" && return length(values)
        isempty(values) && return nothing
        e.op == "MIN" && return minimum(values)
        e.op == "MAX" && return maximum(values)
        total = sum(values)
        return e.op == "AVG" ? div(total, length(values)) : total
    end
    v = [evaluate(c, row, group) for c in e.children]
    result = nothing
    if e.kind == "unary"
        return e.op == "NOT" ? logicalnot(v[1]) : v[1] === nothing ? nothing : -v[1]
    elseif e.kind == "binary"
        return operation(e.op, v[1], v[2])
    elseif e.kind == "isnull"
        result = Int(v[1] === nothing)
    elseif e.kind == "in"
        result = v[1] === nothing ? nothing : v[1] in v[2:end] ? 1 : nothing in v[2:end] ? nothing : 0
    elseif e.kind == "between"
        result = operation("AND", operation(">=", v[1], v[2]), operation("<=", v[1], v[3]))
    elseif e.kind == "like"
        result = any(isnothing, v) ? nothing : Int(likematch(v[1], v[2]))
    end
    e.negated ? logicalnot(result) : result
end
const DATABASE = Dict{String,Table}()
lookup(n) = haskey(DATABASE, n) ? DATABASE[n] : fail("unknown table $n")
function targets(names, t)
    indices = Int[]
    for n in names
        i = findfirst(c -> c.name == n, t.columns)
        i === nothing && fail("unknown column $n")
        i in indices && fail("duplicate column $n")
        push!(indices, i)
    end
    indices
end
function constraints(t, checked)
    key = findfirst(c -> c.keys > 0, t.columns)
    for i in checked
        for (j, c) in enumerate(t.columns)
            c.notnull && t.rows[i][j] === nothing && fail("NULL value in column $(c.name)")
        end
        if key !== nothing && any(j -> j != i && t.rows[j][key] == t.rows[i][key], eachindex(t.rows))
            fail("duplicate primary key $(written(t.rows[i][key]))")
        end
    end
end
countmessage(n, verb) = println("$n $(n == 1 ? "row" : "rows") $verb.")
function printtable(items, types, rows)
    headings = [i.heading for i in items]
    widths = length.(headings)
    for r in rows, i in eachindex(widths)
        widths[i] = max(widths[i], length(written(r[i])))
    end
    separator = "+" * join([repeat("-", w+2) * "+" for w in widths])
    line(values, data) = "|" * join([" " * (data && types[i] == "INT" ? lpad(values[i], widths[i]) : rpad(values[i], widths[i])) * " |" for i in eachindex(values)])
    println(separator)
    println(line(headings, false))
    println(separator)
    for r in rows
        println(line(written.(r), true))
    end
    println(separator)
    println("($(length(rows)) $(length(rows) == 1 ? "row" : "rows"))")
end
function executeselect(s)
    scope = Scope()
    tables = Table[]
    refs = [s.source; [j.table for j in s.joins]]
    for (i, r) in enumerate(refs)
        t = lookup(r.name)
        add!(scope, scopename(r), t)
        push!(tables, t)
        i > 1 && condition(s.joins[i-1].condition, scope, "ON")
    end
    condition(s.whereexpr, scope, "WHERE")
    for e in s.grouping
        resolve!(scope, e)
    end
    aggregate = !isempty(s.grouping) || s.having !== nothing || (s.items !== nothing && any(i -> hasaggregate(i.expr), s.items)) || any(o -> hasaggregate(o.expr), s.orders)
    grouped = aggregate ? Set(e.index for e in s.grouping) : nothing
    items = s.items
    if items === nothing
        items = Item[]
        for entry in scope.entries, c in entry.table.columns
            push!(items, Item(SqlExpr("column", table=entry.name, column=c.name, written=c.name), nothing, c.name))
        end
    end
    types = [check(i.expr, scope, true, grouped) for i in items]
    condition(s.having, scope, "HAVING", true, grouped)
    keys = SqlExpr[]
    for order in s.orders
        if length(order.tokens) == 1 && order.tokens[1].kind == "integer"
            k = parse(Int, order.tokens[1].text)
            1 <= k <= length(items) || fail("ORDER BY position $k is out of range")
            push!(keys, items[k].expr)
        else
            index = length(order.tokens) == 1 && order.tokens[1].kind == "name" ? findfirst(i -> i.alias == order.tokens[1].text, items) : nothing
            if index !== nothing
                push!(keys, items[index].expr)
            else
                check(order.expr, scope, true, grouped)
                push!(keys, order.expr)
            end
        end
    end
    rows = tables[1].rows
    for (j, join) in enumerate(s.joins)
        next = Vector{Any}[]
        for l in rows
            matched = false
            for r in tables[j+1].rows
                combined = [l; r]
                if truth(evaluate(join.condition, combined))
                    push!(next, combined)
                    matched = true
                end
            end
            !matched && join.outer && push!(next, [l; fill(nothing, length(tables[j+1].columns))])
        end
        rows = next
    end
    s.whereexpr !== nothing && (rows = filter(r -> truth(evaluate(s.whereexpr, r)), rows))
    groups = Vector{Vector{Any}}[]
    if aggregate
        if isempty(s.grouping)
            push!(groups, rows)
        else
            indices = Dict{Tuple,Int}()
            for r in rows
                key = Tuple(r[e.index] for e in s.grouping)
                if haskey(indices, key)
                    push!(groups[indices[key]], r)
                else
                    indices[key] = length(groups)+1
                    push!(groups, [r])
                end
            end
        end
    else
        groups = [[r] for r in rows]
    end
    results = Tuple{Vector{Any},Vector{Any},Int}[]
    for group in groups
        row = isempty(group) ? Any[nothing for _ in 1:scope.width] : group[1]
        s.having !== nothing && !truth(evaluate(s.having, row, group)) && continue
        push!(results, (Any[evaluate(i.expr, row, group) for i in items], Any[evaluate(k, row, group) for k in keys], length(results)))
    end
    if !isempty(keys)
        sort!(results, lt=function (a, b)
            for i in eachindex(keys)
                c = compare(a[2][i], b[2][i])
                c != 0 && return s.orders[i].descending ? c > 0 : c < 0
            end
            a[3] < b[3]
        end)
    end
    if s.distinct
        seen = Set{Tuple}()
        filter!(results) do r
            key = Tuple(r[1])
            key in seen && return false
            push!(seen, key)
            true
        end
    end
    selected = collect(Iterators.take(Iterators.drop(results, s.offset), something(s.limit, length(results))))
    printtable(items, types, [r[1] for r in selected])
end
function execute(s)
    s.command in ("", "EXIT") && return
    if s.command == "SELECT"
        executeselect(s)
        return
    end
    if s.command == "CREATE"
        haskey(DATABASE, s.name) && fail("table $(s.name) already exists")
        seen = Set{String}()
        keys = 0
        for c in s.columns
            c.name in seen && fail("duplicate column $(c.name)")
            push!(seen, c.name)
            keys += c.keys
            keys > 1 && fail("multiple primary keys")
        end
        DATABASE[s.name] = Table(s.name, s.columns)
        println("Table $(s.name) created.")
        return
    end
    original = lookup(s.name)
    t = Table(original.name, original.columns, [copy(r) for r in original.rows])
    if s.command == "DROP"
        delete!(DATABASE, s.name)
        println("Table $(s.name) dropped.")
        return
    end
    scope = Scope()
    add!(scope, t.name, t)
    if s.command == "INSERT"
        columns = targets(s.names === nothing ? [c.name for c in t.columns] : s.names, t)
        for tuple in s.tuples
            length(tuple) == length(columns) || fail("expected $(length(columns)) values, got $(length(tuple))")
            for (e, i) in zip(tuple, columns)
                require(check(e, Scope()), t.columns[i].type, "column $(t.columns[i].name)")
            end
        end
        start = length(t.rows)+1
        for tuple in s.tuples
            row = Any[nothing for _ in t.columns]
            for (e, i) in zip(tuple, columns)
                row[i] = evaluate(e, Any[])
            end
            push!(t.rows, row)
        end
        constraints(t, start:length(t.rows))
        DATABASE[s.name] = t
        countmessage(length(s.tuples), "inserted")
        return
    end
    assigned = Int[]
    if s.command == "UPDATE"
        assigned = targets([a[1] for a in s.assignments], t)
        for (assignment, i) in zip(s.assignments, assigned)
            require(check(assignment[2], scope), t.columns[i].type, "column $(t.columns[i].name)")
        end
    end
    condition(s.whereexpr, scope, "WHERE")
    affected = filter(i -> s.whereexpr === nothing || truth(evaluate(s.whereexpr, t.rows[i])), eachindex(t.rows))
    if s.command == "DELETE"
        removed = Set(affected)
        t.rows = [r for (i, r) in enumerate(t.rows) if !(i in removed)]
    else
        for i in affected
            before = copy(t.rows[i])
            for (assignment, j) in zip(s.assignments, assigned)
                t.rows[i][j] = evaluate(assignment[2], before)
            end
        end
        constraints(t, affected)
    end
    DATABASE[s.name] = t
    countmessage(length(affected), s.command == "DELETE" ? "deleted" : "updated")
end
function main()
    source = read(stdin, String)
    start = 1
    quoted = false
    comment = false
    for i in eachindex(source)
        c = source[i]
        if comment
            c == '\n' && (comment = false)
        elseif c == '\''
            quoted = !quoted
        elseif !quoted && c == '-' && i < lastindex(source) && source[i+1] == '-'
            comment = true
        elseif !quoted && c == ';'
            try
                s = parsestatement!(Parser(tokenize(source[start:i])))
                s.command == "EXIT" && break
                execute(s)
            catch e
                e isa SqlError || rethrow()
                println("ERROR: $(e.reason)")
            end
            start = i+1
        end
    end
end
main()
