struct CircuitError <: Exception
    message::String
end
circuit_error(message) = throw(CircuitError(message))

function fraction_text(value)
    p, q = numerator(value), denominator(value)
    q == 1 ? string(p) : string(p, "/", q)
end
function value_text(value)
    p, q = numerator(value), denominator(value)
    scaled = div(abs(p) * 1000000, q)
    decimal = (p < 0 ? "-" : "") * string(div(scaled, 1000000)) * "." *
        lpad(string(rem(scaled, 1000000)), 6, '0')
    fraction_text(value) * " (" * decimal * ")"
end
function parse_value(text)
    multiplier = 1 // 1
    for (suffix, scale) in (("meg", 1000000 // 1), ("k", 1000 // 1),
            ("m", 1 // 1000), ("u", 1 // 1000000))
        if endswith(text, suffix)
            text = text[1:end - length(suffix)]
            multiplier = scale
            break
        end
    end
    occursin(r"^-?[0-9]+(?:\.[0-9]+|/[0-9]+)?$", text) || return nothing
    if occursin('/', text)
        parts = split(text, '/')
        p, q = parse(Int, parts[1]), parse(Int, parts[2])
        q == 0 && return nothing
        value = p // q
    elseif occursin('.', text)
        parts = split(text, '.')
        q = 10 ^ length(parts[2])
        p = abs(parse(Int, parts[1])) * q + parse(Int, parts[2])
        value = (startswith(text, "-") ? -p : p) // q
    else
        value = parse(Int, text) // 1
    end
    value * multiplier
end
function required_value(text)
    value = parse_value(text)
    value === nothing && circuit_error("invalid value $text")
    value
end
function solve_system(matrix, rhs)
    n = length(rhs)
    rows = hcat(matrix, rhs)
    for k in 1:n
        pivot = 0
        for i in k:n
            if rows[i, k] != 0
                pivot = i
                break
            end
        end
        pivot == 0 && return nothing
        if pivot != k
            saved = rows[k, :]
            rows[k, :] = rows[pivot, :]
            rows[pivot, :] = saved
        end
        divisor = rows[k, k]
        for j in 1:n + 1
            rows[k, j] /= divisor
        end
        for i in 1:n
            (i == k || rows[i, k] == 0) && continue
            factor = rows[i, k]
            for j in 1:n + 1
                rows[i, j] -= factor * rows[k, j]
            end
        end
    end
    rows[:, n + 1]
end
function reached_nodes(start, edges)
    reached = Set([String(start)])
    pending = [String(start)]
    head = 1
    while head <= length(pending)
        node = pending[head]
        head += 1
        for edge in edges
            a, b = edge[1], edge[2]
            (a == node || b == node) || continue
            other = a == node ? b : a
            if !(other in reached)
                push!(reached, other)
                push!(pending, other)
            end
        end
    end
    reached
end
mutable struct CircuitGroups
    parent::Dict{String,String}
end
CircuitGroups(nodes) = CircuitGroups(Dict(node => node for node in nodes))
function group_of(groups, node)
    parent = groups.parent[node]
    parent == node && return parent
    root = group_of(groups, parent)
    groups.parent[node] = root
    root
end
function join_groups!(groups, a, b)
    a, b = group_of(groups, a), group_of(groups, b)
    if isless(a, b)
        groups.parent[b] = a
    else
        groups.parent[a] = b
    end
end

mutable struct CircuitElement
    name::String
    kind::Char
    nodes::Vector{String}
    value::Rational{Int}
    reference::String
end
mutable struct Circuit
    elements::Vector{CircuitElement}
end
Circuit() = Circuit(CircuitElement[])
const VOLTAGE_KINDS = ('V', 'E', 'H')
const COMMAND_COUNTS = Dict(".OP" => 0, ".CURRENT" => 1, ".VOLTAGE" => 2, ".POWER" => 0,
    ".KCL" => 1, ".THEVENIN" => 2, ".NORTON" => 2, ".MAXPOWER" => 2, ".TF" => 2,
    ".SENS" => 1, ".ZPARAM" => 4, ".SUPERPOSITION" => 1, ".SWEEP" => 5, ".MATRIX" => 0,
    ".REQ" => 2, ".REDUCE" => 2, ".CHECK" => 0, ".ALTER" => 2, ".DELETE" => 1,
    ".CLEAR" => 0, ".NODES" => 0, ".PRINT" => 0)
const ANALYSES = Set([".OP", ".CURRENT", ".VOLTAGE", ".POWER", ".KCL", ".THEVENIN",
    ".NORTON", ".MAXPOWER", ".TF", ".SENS", ".ZPARAM", ".SUPERPOSITION"])

function circuit_nodes(c)
    sort(unique([node for item in c.elements for node in item.nodes if node != "0"]))
end
voltage_sources(c) = [item for item in c.elements if item.kind in VOLTAGE_KINDS]
function required_element(c, name)
    for item in c.elements
        item.name == name && return item
    end
    circuit_error("unknown element $name")
end
function require_node(c, name)
    (name == "0" || name in circuit_nodes(c)) || circuit_error("unknown node $name")
end
function add_element!(c, fields)
    name = fields[1]
    kind = name[1]
    kind in ('R', 'V', 'I', 'E', 'G', 'F', 'H') || circuit_error("unknown element type $name")
    count = kind in ('E', 'G') ? 6 : kind in ('F', 'H') ? 5 : 4
    length(fields) == count || circuit_error("wrong field count for $name")
    any(item -> item.name == name, c.elements) && circuit_error("duplicate element $name")
    terminals = String.(fields[2:(kind in ('E', 'G') ? 5 : 3)])
    for node in terminals
        occursin(r"^(?:0|[a-z][a-z0-9]{0,7})$", node) || circuit_error("invalid node $node")
    end
    reference = kind in ('F', 'H') ? String(fields[4]) : ""
    if !isempty(reference) && !any(item -> item.name == reference && item.kind == 'V', c.elements)
        circuit_error("unknown voltage source $reference")
    end
    value = required_value(fields[end])
    kind == 'R' && value <= 0 && circuit_error("nonpositive resistance $name")
    push!(c.elements, CircuitElement(name, kind, terminals, value, reference))
    String[]
end
grounded_nodes(c) = reached_nodes("0", [item.nodes[1:2] for item in c.elements if item.kind in ('R', 'V', 'E', 'H')])
function voltage_loops(c)
    groups = CircuitGroups(["0"; circuit_nodes(c)])
    result = String[]
    for item in voltage_sources(c)
        a, b = item.nodes[1:2]
        group_of(groups, a) == group_of(groups, b) && push!(result, item.name)
        join_groups!(groups, a, b)
    end
    result
end
function check_structure(c)
    nodes = circuit_nodes(c)
    isempty(nodes) && circuit_error("no nodes")
    grounded = grounded_nodes(c)
    for node in nodes
        node in grounded || circuit_error("floating node $node")
    end
    loops = voltage_loops(c)
    isempty(loops) || circuit_error("voltage source loop at $(loops[1])")
end
function add_rhs!(rhs, index, row, value)
    row != "0" && (rhs[index[row]] += value)
end
function circuit_equations(c, overrides=Dict{String,Rational{Int}}())
    labels = [circuit_nodes(c); [item.name for item in voltage_sources(c)]]
    index = Dict(name => i for (i, name) in enumerate(labels))
    n = length(labels)
    matrix = fill(0 // 1, n, n)
    rhs = fill(0 // 1, n)
    function put(row, column, value)
        if row != "0" && column != "0"
            matrix[index[row], index[column]] += value
        end
    end
    for item in c.elements
        a, b = item.nodes[1:2]
        value = get(overrides, item.name, item.value)
        name = item.name
        if item.kind == 'R'
            g = inv(value)
            put(a, a, g)
            put(b, b, g)
            put(a, b, -g)
            put(b, a, -g)
        elseif item.kind == 'I'
            add_rhs!(rhs, index, a, -value)
            add_rhs!(rhs, index, b, value)
        elseif item.kind == 'G'
            x, y = item.nodes[3:4]
            put(a, x, value)
            put(b, y, value)
            put(a, y, -value)
            put(b, x, -value)
        elseif item.kind == 'F'
            put(a, item.reference, value)
            put(b, item.reference, -value)
        else
            put(a, name, 1)
            put(name, a, 1)
            put(b, name, -1)
            put(name, b, -1)
            if item.kind == 'V'
                add_rhs!(rhs, index, name, value)
            elseif item.kind == 'E'
                x, y = item.nodes[3:4]
                put(name, x, -value)
                put(name, y, value)
            else
                put(name, item.reference, -value)
            end
        end
    end
    matrix, rhs, labels, index
end
potential(solution, index, node) = node == "0" ? 0 // 1 : solution[index[node]]
function element_current(item, solution, index)
    a, b = item.nodes[1:2]
    kind = item.kind
    kind == 'R' && return (potential(solution, index, a) - potential(solution, index, b)) / item.value
    kind in VOLTAGE_KINDS && return solution[index[item.name]]
    kind == 'I' && return item.value
    kind == 'G' && return item.value *
        (potential(solution, index, item.nodes[3]) - potential(solution, index, item.nodes[4]))
    item.value * solution[index[item.reference]]
end
function injection_solution(matrix, index, a, b)
    rhs = fill(0 // 1, size(matrix, 1))
    add_rhs!(rhs, index, a, 1)
    add_rhs!(rhs, index, b, -1)
    solve_system(matrix, rhs)
end
function source_solution(matrix, index, item, unit=false)
    rhs = fill(0 // 1, size(matrix, 1))
    value = unit ? 1 // 1 : item.value
    if item.kind == 'V'
        add_rhs!(rhs, index, item.name, value)
    else
        a, b = item.nodes[1:2]
        add_rhs!(rhs, index, a, -value)
        add_rhs!(rhs, index, b, value)
    end
    solve_system(matrix, rhs)
end
function analyze_circuit(c, command, args)
    if command == ".CURRENT"
        required_element(c, args[1])
    elseif command in (".VOLTAGE", ".THEVENIN", ".NORTON", ".MAXPOWER", ".ZPARAM")
        for node in args
            require_node(c, node)
        end
    elseif command in (".KCL", ".SENS", ".SUPERPOSITION")
        require_node(c, args[1])
    elseif command == ".TF"
        require_node(c, args[1])
        item = required_element(c, args[2])
        item.kind in ('V', 'I') || circuit_error("not an independent source $(item.name)")
    end
    check_structure(c)
    matrix, rhs, labels, index = circuit_equations(c)
    solution = solve_system(matrix, rhs)
    solution === nothing && circuit_error("singular matrix")
    voltage(node, values=solution) = potential(values, index, node)
    lines = String[]
    if command == ".OP"
        for node in circuit_nodes(c)
            push!(lines, "V($node) = " * value_text(voltage(node)))
        end
        for item in voltage_sources(c)
            push!(lines, "I($(item.name)) = " * value_text(solution[index[item.name]]))
        end
    elseif command == ".CURRENT"
        push!(lines, "I($(args[1])) = " * value_text(element_current(required_element(c, args[1]), solution, index)))
    elseif command == ".VOLTAGE"
        push!(lines, "V($(args[1]),$(args[2])) = " * value_text(voltage(args[1]) - voltage(args[2])))
    elseif command == ".POWER"
        absorbed = delivered = total = 0 // 1
        for item in c.elements
            power = (voltage(item.nodes[1]) - voltage(item.nodes[2])) * element_current(item, solution, index)
            power > 0 && (absorbed += power)
            power < 0 && (delivered -= power)
            total += power
            push!(lines, "P($(item.name)) = " * value_text(power))
        end
        append!(lines, ["absorbed = " * value_text(absorbed),
            "delivered = " * value_text(delivered), "total = " * value_text(total)])
    elseif command == ".KCL"
        a = args[1]
        total = 0 // 1
        for item in c.elements
            x, y = item.nodes[1:2]
            (x == a || y == a) || continue
            value = x == y ? 0 // 1 : (x == a ? 1 : -1) * element_current(item, solution, index)
            total += value
            push!(lines, "I($(item.name)) leaving $a = " * value_text(value))
        end
        push!(lines, "sum = " * value_text(total))
    elseif command in (".THEVENIN", ".NORTON", ".MAXPOWER")
        a, b = args
        vth = voltage(a) - voltage(b)
        z = injection_solution(matrix, index, a, b)
        rth = voltage(a, z) - voltage(b, z)
        if command == ".NORTON"
            rth == 0 && circuit_error("zero thevenin resistance")
            append!(lines, ["In = " * value_text(vth / rth), "Rn = " * value_text(rth)])
        elseif command == ".MAXPOWER"
            rth <= 0 && circuit_error("nonpositive thevenin resistance")
            append!(lines, ["RL = " * value_text(rth), "Pmax = " * value_text(vth * vth / (4 * rth))])
        else
            append!(lines, ["Vth = " * value_text(vth), "Rth = " * value_text(rth)])
        end
    elseif command == ".TF"
        a, name = args
        item = required_element(c, name)
        z = source_solution(matrix, index, item, true)
        push!(lines, "gain = " * value_text(voltage(a, z)))
        if item.kind == 'V'
            j = z[index[name]]
            push!(lines, j == 0 ? "input resistance = INFINITE" : "input resistance = " * value_text(-inv(j)))
        else
            push!(lines, "input resistance = " * value_text(voltage(item.nodes[2], z) - voltage(item.nodes[1], z)))
        end
        push!(lines, "output resistance = " * value_text(voltage(a, injection_solution(matrix, index, a, "0"))))
    elseif command == ".SENS"
        a = args[1]
        for item in c.elements
            d = fill(0 // 1, length(rhs))
            x, y = item.nodes[1:2]
            if item.kind == 'R'
                t = element_current(item, solution, index) / item.value
                add_rhs!(d, index, x, t)
                add_rhs!(d, index, y, -t)
            elseif item.kind == 'I'
                add_rhs!(d, index, x, -1)
                add_rhs!(d, index, y, 1)
            elseif item.kind in ('G', 'F')
                t = item.kind == 'G' ? voltage(item.nodes[3]) - voltage(item.nodes[4]) : solution[index[item.reference]]
                add_rhs!(d, index, x, -t)
                add_rhs!(d, index, y, t)
            elseif item.kind == 'V'
                add_rhs!(d, index, item.name, 1)
            elseif item.kind == 'E'
                add_rhs!(d, index, item.name, voltage(item.nodes[3]) - voltage(item.nodes[4]))
            else
                add_rhs!(d, index, item.name, solution[index[item.reference]])
            end
            push!(lines, "dV($a)/d$(item.name) = " * value_text(voltage(a, solve_system(matrix, d))))
        end
    elseif command == ".ZPARAM"
        a, b, x, y = args
        z1 = injection_solution(matrix, index, a, b)
        z2 = injection_solution(matrix, index, x, y)
        append!(lines, ["z11 = " * value_text(voltage(a, z1) - voltage(b, z1)),
            "z12 = " * value_text(voltage(a, z2) - voltage(b, z2)),
            "z21 = " * value_text(voltage(x, z1) - voltage(y, z1)),
            "z22 = " * value_text(voltage(x, z2) - voltage(y, z2))])
    elseif command == ".SUPERPOSITION"
        a = args[1]
        total = 0 // 1
        for item in c.elements
            item.kind in ('V', 'I') || continue
            value = voltage(a, source_solution(matrix, index, item))
            total += value
            push!(lines, "$(item.name): V($a) = " * value_text(value))
        end
        push!(lines, "total: V($a) = " * value_text(total))
    end
    lines
end

function equivalent_resistance(c, a, b)
    groups = CircuitGroups(["0"; circuit_nodes(c)])
    for item in c.elements
        item.kind == 'V' && join_groups!(groups, item.nodes[1], item.nodes[2])
    end
    a, b = group_of(groups, a), group_of(groups, b)
    a == b && return ["Req = 0 (0.000000)"]
    edges = Tuple{String,String,Rational{Int}}[]
    for item in c.elements
        item.kind == 'R' || continue
        x, y = group_of(groups, item.nodes[1]), group_of(groups, item.nodes[2])
        x != y && push!(edges, (x, y, inv(item.value)))
    end
    connected = reached_nodes(a, edges)
    b in connected || return ["Req = INFINITE"]
    labels = sort([node for node in connected if node != b])
    index = Dict(node => i for (i, node) in enumerate(labels))
    matrix = fill(0 // 1, length(labels), length(labels))
    rhs = fill(0 // 1, length(labels))
    rhs[index[a]] = 1 // 1
    for (x, y, g) in edges
        x in connected || continue
        x != b && (matrix[index[x], index[x]] += g)
        y != b && (matrix[index[y], index[y]] += g)
        if x != b && y != b
            matrix[index[x], index[y]] -= g
            matrix[index[y], index[x]] -= g
        end
    end
    ["Req = " * value_text(solve_system(matrix, rhs)[index[a]])]
end
function reduce_resistors(c, a, b)
    a == b && return ["Req = 0 (0.000000)"]
    resistors = [item for item in c.elements if item.kind == 'R']
    connected = reached_nodes(a, [item.nodes for item in resistors])
    b in connected || return ["Req = INFINITE"]
    filter!(item -> item.nodes[1] in connected, resistors)
    lines = String[]
    serial = 0
    while true
        self = findfirst(item -> item.nodes[1] == item.nodes[2], resistors)
        if self !== nothing
            push!(lines, "remove $(resistors[self].name)")
            deleteat!(resistors, self)
            continue
        end
        degree = Dict{String,Int}()
        for item in resistors, node in item.nodes
            degree[node] = get(degree, node, 0) + 1
        end
        internal = sort([node for node in keys(degree) if node != a && node != b])
        leaf = findfirst(node -> degree[node] == 1, internal)
        if leaf !== nothing
            i = findfirst(item -> internal[leaf] in item.nodes, resistors)
            push!(lines, "remove $(resistors[i].name)")
            deleteat!(resistors, i)
            continue
        end
        pair = nothing
        for i in eachindex(resistors)
            for j in i + 1:length(resistors)
                if sort(resistors[i].nodes) == sort(resistors[j].nodes)
                    pair = (i, j)
                    break
                end
            end
            pair !== nothing && break
        end
        if pair !== nothing
            x, y = resistors[pair[1]], resistors[pair[2]]
            value = x.value * y.value / (x.value + y.value)
            terminals = x.nodes
            operator = "||"
        else
            middle = findfirst(node -> degree[node] == 2, internal)
            middle === nothing && break
            node = internal[middle]
            pair = findall(item -> node in item.nodes, resistors)
            x, y = resistors[pair[1]], resistors[pair[2]]
            terminals = [x.nodes[1] == node ? x.nodes[2] : x.nodes[1],
                y.nodes[1] == node ? y.nodes[2] : y.nodes[1]]
            value = x.value + y.value
            operator = "+"
        end
        serial += 1
        name = "#$serial"
        push!(lines, "$name = $(x.name) $operator $(y.name) = " * value_text(value))
        deleteat!(resistors, [pair[1], pair[2]])
        push!(resistors, CircuitElement(name, 'R', terminals, value, ""))
    end
    push!(lines, length(resistors) == 1 ? "Req = " * value_text(resistors[1].value) :
        "not series-parallel: $(length(resistors)) resistors remain")
    lines
end
function circuit_command!(c, fields)
    command = fields[1]
    args = fields[2:end]
    haskey(COMMAND_COUNTS, command) || circuit_error("unknown command $command")
    length(args) == COMMAND_COUNTS[command] || circuit_error("wrong argument count for $command")
    command in ANALYSES && return analyze_circuit(c, command, args)
    if command in (".REQ", ".REDUCE")
        for node in args
            require_node(c, node)
        end
        return command == ".REQ" ? equivalent_resistance(c, args[1], args[2]) : reduce_resistors(c, args[1], args[2])
    elseif command == ".SWEEP"
        item = required_element(c, args[1])
        from = required_value(args[2])
        to = required_value(args[3])
        step = required_value(args[4])
        require_node(c, args[5])
        step <= 0 && circuit_error("invalid sweep step")
        from > to && circuit_error("invalid sweep range")
        range = (to - from) / step
        point_count = fld(numerator(range), denominator(range)) + 1
        point_count > 20 && circuit_error("too many sweep points")
        item.kind == 'R' && from <= 0 && circuit_error("nonpositive resistance $(item.name)")
        check_structure(c)
        lines = String[]
        for k in 0:point_count - 1
            x = from + k * step
            matrix, rhs, labels, index = circuit_equations(c, Dict(item.name => x))
            solution = solve_system(matrix, rhs)
            result = solution === nothing ? "singular matrix" : "V($(args[5])) = " * value_text(potential(solution, index, args[5]))
            push!(lines, "$(item.name) = $(fraction_text(x)): $result")
        end
        return lines
    elseif command == ".MATRIX"
        check_structure(c)
        matrix, rhs, labels, index = circuit_equations(c)
        unknowns = [["V($node)" for node in circuit_nodes(c)]; ["I($(item.name))" for item in voltage_sources(c)]]
        lines = ["unknowns: " * join(unknowns, " ")]
        for i in eachindex(labels)
            push!(lines, labels[i] * ": " * join(fraction_text.(matrix[i, :]), " ") * " | " * fraction_text(rhs[i]))
        end
        return lines
    elseif command == ".CHECK"
        nodes = circuit_nodes(c)
        isempty(nodes) && return ["no nodes"]
        lines = String[]
        for node in nodes
            degree = sum((count(==(node), item.nodes[1:2]) for item in c.elements); init=0)
            degree < 2 && push!(lines, "dangling node $node")
        end
        grounded = grounded_nodes(c)
        for node in nodes
            node in grounded || push!(lines, "floating node $node")
        end
        append!(lines, ["voltage source loop at $name" for name in voltage_loops(c)])
        if isempty(lines)
            matrix, rhs, labels, index = circuit_equations(c)
            solve_system(matrix, rhs) === nothing && push!(lines, "singular matrix")
        end
        return isempty(lines) ? ["ok"] : lines
    elseif command == ".ALTER"
        item = required_element(c, args[1])
        value = required_value(args[2])
        item.kind == 'R' && value <= 0 && circuit_error("nonpositive resistance $(item.name)")
        line = "altered $(item.name): $(fraction_text(item.value)) -> $(fraction_text(value))"
        item.value = value
        return [line]
    elseif command == ".DELETE"
        item = required_element(c, args[1])
        for other in c.elements
            if other.kind in ('F', 'H') && other.reference == item.name
                circuit_error("$(item.name) is referenced by $(other.name)")
            end
        end
        filter!(other -> other !== item, c.elements)
        return ["deleted $(item.name)"]
    elseif command == ".CLEAR"
        line = "cleared $(length(c.elements)) elements"
        empty!(c.elements)
        return [line]
    elseif command == ".NODES"
        isempty(c.elements) && return ["no nodes"]
        nodes = sort(unique([node for item in c.elements for node in item.nodes]))
        return [node * ": " * join((item.name for item in c.elements if node in item.nodes), " ") for node in nodes]
    end
    isempty(c.elements) && return ["empty netlist"]
    lines = String[]
    for item in c.elements
        words = [item.name; item.nodes]
        !isempty(item.reference) && push!(words, item.reference)
        push!(words, fraction_text(item.value))
        push!(lines, join(words, " "))
    end
    lines
end
function main()
    circuit = Circuit()
    for (number, line) in enumerate(eachline())
        line == ".END" && break
        startswith(line, "*") && continue
        try
            fields = split(line, ' ')
            lines = startswith(line, ".") ? circuit_command!(circuit, fields) : add_element!(circuit, fields)
            for output in lines
                println(output)
            end
        catch error
            error isa CircuitError || rethrow()
            println("error: line $number: ", error.message)
        end
    end
end
main()
