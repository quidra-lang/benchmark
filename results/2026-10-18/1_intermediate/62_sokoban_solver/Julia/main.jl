const DIRECTIONS = "udlr"
const DELTAS = ((-1, 0), (1, 0), (0, -1), (0, 1))
const TURNS = Dict(
    "ROT90" => "rlud",
    "ROT180" => "durl",
    "ROT270" => "lrdu",
    "FLIPH" => "udrl",
    "FLIPV" => "dulr",
)
const STEP_LETTERS = "udlrUDLR"
const LEVEL_CHARACTERS = "#-.\$*@+"
const MAX_SIDE = 10
const MAX_LIMIT = 100000
const NUMBER_WORD = r"^(0|[1-9][0-9]{0,5})$"
const NAME_WORD = r"^[a-z]{1,8}$"
const CELL = (:number, :number)
const COMMANDS = Dict(
    "IMPORT" => (:text,),
    "VALID" => (),
    "INFO" => (),
    "SHOW" => (),
    "EXPORT" => (),
    "MOVE" => (:steps,),
    "PUSH" => (CELL..., :direction),
    "BRING" => (CELL..., CELL...),
    "PATH" => CELL,
    "UNDO" => (:number,),
    "REDO" => (:number,),
    "RESET" => (),
    "STATUS" => (),
    "HISTORY" => (),
    "BOXES" => (),
    "REACH" => (),
    "DEADSQUARES" => (),
    "DEADLOCK" => (),
    "BOUND" => (),
    "SAVE" => (:name,),
    "RESTORE" => (:name,),
    "CHECK" => (:steps,),
    "SOLVE" => (:number,),
    "HINT" => (:number,),
    "PLAY" => (),
    "TRANSFORM" => (:transform,),
)
const CELL_COUNTS = Dict("PATH" => 1, "PUSH" => 1, "BRING" => 2)
const LEVEL_FREE_COMMANDS = ("IMPORT", "VALID")

struct CommandError <: Exception
    message::String
end

struct StepFailure <: Exception
    reason::String
end

function decode(text, allowed)
    characters = collect(text)
    pieces = String[]
    index = 1
    while index <= length(characters)
        start = index
        while index <= length(characters) && isdigit(characters[index])
            index += 1
        end
        repeats = String(characters[start:index-1])
        if length(repeats) > 2 || startswith(repeats, '0') || index > length(characters)
            return nothing
        end
        characters[index] in allowed || return nothing
        push!(pieces, repeat(characters[index], isempty(repeats) ? 1 : parse(Int, repeats)))
        index += 1
    end
    return join(pieces)
end

function encode(text)
    characters = collect(text)
    pieces = String[]
    start = 1
    while start <= length(characters)
        stop = start
        while stop <= length(characters) && characters[stop] == characters[start]
            stop += 1
        end
        run_length = stop - start
        push!(pieces, (run_length > 1 ? string(run_length) : "") * characters[start])
        start = stop
    end
    return join(pieces)
end

step_sequence(word) = lowercase(decode(word, STEP_LETTERS))

function valid_argument(kind, text)
    kind == :number && return occursin(NUMBER_WORD, text)
    kind == :steps && return decode(text, STEP_LETTERS) !== nothing
    kind == :direction && return length(text) == 1 && text[1] in DIRECTIONS
    kind == :name && return occursin(NAME_WORD, text)
    kind == :transform && return haskey(TURNS, text)
    return true
end

push_count(letters) = count(isuppercase, letters)

function turn_letters(letters, kind)
    return map(collect(letters)) do letter
        direction = TURNS[kind][findfirst(lowercase(letter), DIRECTIONS)]
        isuppercase(letter) ? uppercase(direction) : direction
    end
end

move_box(boxes, source, destination) = sort([box == source ? destination : box for box in boxes])

function counted(label, letters)
    isempty(letters) && return "$label 0"
    return "$label $(length(letters)) $(join(letters))"
end

function permutations(items)
    isempty(items) && return [Int[]]
    return [[item; tail] for item in items for tail in permutations(setdiff(items, [item]))]
end

function find_interior(height, width, walls, start)
    interior = fill(false, height * width)
    interior[start] = true
    stack = [start]
    while !isempty(stack)
        cell = pop!(stack)
        row, column = divrem(cell - 1, width)
        for (d_row, d_column) in DELTAS
            next_row, next_column = row + d_row, column + d_column
            if 0 <= next_row < height && 0 <= next_column < width
                neighbor = next_row * width + next_column + 1
                if !walls[neighbor] && !interior[neighbor]
                    interior[neighbor] = true
                    push!(stack, neighbor)
                end
            end
        end
    end
    return interior
end

struct Position
    player::Int
    boxes::Vector{Int}
end

same(a::Position, b::Position) = a.player == b.player && a.boxes == b.boxes

mutable struct Level
    height::Int
    width::Int
    size::Int
    walls::Vector{Bool}
    goals::Vector{Bool}
    interior::Vector{Bool}
    offsets::Dict{Char,Int}
    goal_cells::Vector{Int}
    reason::Union{String,Nothing}
    distances::Vector{Vector{Union{Int,Nothing}}}
    dead::Vector{Bool}
end

function Level(height, width, walls, goals, interior)
    offsets = Dict(
        direction => d_row * width + d_column
        for (direction, (d_row, d_column)) in zip(DIRECTIONS, DELTAS)
    )
    cells = height * width
    return Level(height, width, cells, walls, goals, interior, offsets, findall(goals),
                 nothing, [], fill(false, cells))
end

function cell_text(level::Level, cell)
    row, column = divrem(cell - 1, level.width)
    return "$(row + 1) $(column + 1)"
end

cell_at(level::Level, row, column) = (row - 1) * level.width + column

contains_cell(level::Level, row, column) = 1 <= row <= level.height && 1 <= column <= level.width

function on_border(level::Level, cell)
    row, column = divrem(cell - 1, level.width)
    return row in (0, level.height - 1) || column in (0, level.width - 1)
end

function invalidity(level::Level, players, boxes)
    players != 1 && return "players $players"
    isempty(boxes) && return "no boxes"
    if length(boxes) != length(level.goal_cells)
        return "boxes $(length(boxes)) goals $(length(level.goal_cells))"
    end
    for cell in 1:level.size
        if level.interior[cell] && on_border(level, cell)
            return "open $(cell_text(level, cell))"
        end
    end
    for cell in 1:level.size
        if (level.goals[cell] || cell in boxes) && !level.interior[cell]
            return "outside $(cell_text(level, cell))"
        end
    end
    return nothing
end

function analyze!(level::Level)
    level.distances = [push_distances(level, goal) for goal in level.goal_cells]
    level.dead = [
        level.interior[cell] && goal_distance(level, cell) === nothing for cell in 1:level.size
    ]
    return level
end

function push_distances(level::Level, goal)
    distance = Vector{Union{Int,Nothing}}(nothing, level.size)
    distance[goal] = 0
    queue = [goal]
    while !isempty(queue)
        cell = popfirst!(queue)
        for direction in DIRECTIONS
            offset = level.offsets[direction]
            box = cell - offset
            if level.interior[box] && level.interior[box - offset] && distance[box] === nothing
                distance[box] = distance[cell] + 1
                push!(queue, box)
            end
        end
    end
    return distance
end

function goal_distance(level::Level, cell)
    defined = [distance[cell] for distance in level.distances if distance[cell] !== nothing]
    return isempty(defined) ? nothing : minimum(defined)
end

boxes_on_goals(level::Level, boxes) = count(box -> level.goals[box], boxes)

solved(level::Level, boxes) = boxes_on_goals(level, boxes) == length(boxes)

function reachable(level::Level, player, boxes)
    seen = fill(false, level.size)
    seen[player] = true
    stack = [player]
    while !isempty(stack)
        cell = pop!(stack)
        for offset in values(level.offsets)
            neighbor = cell + offset
            if level.interior[neighbor] && !seen[neighbor] && neighbor ∉ boxes
                seen[neighbor] = true
                push!(stack, neighbor)
            end
        end
    end
    return seen
end

representative(level::Level, player, boxes) = findfirst(reachable(level, player, boxes))

function walk_path(level::Level, start, target, boxes)
    came_from = Vector{Union{Tuple{Int,Char},Nothing}}(nothing, level.size)
    queue = [start]
    while !isempty(queue)
        cell = popfirst!(queue)
        for direction in DIRECTIONS
            neighbor = cell + level.offsets[direction]
            if level.interior[neighbor] && neighbor ∉ boxes && neighbor != start &&
               came_from[neighbor] === nothing
                came_from[neighbor] = (cell, direction)
                push!(queue, neighbor)
            end
        end
    end
    directions = Char[]
    cell = target
    while cell != start
        cell, direction = came_from[cell]
        push!(directions, direction)
    end
    return join(reverse(directions))
end

function take_step(level::Level, position, direction)
    offset = level.offsets[direction]
    target = position.player + offset
    level.walls[target] && throw(StepFailure("wall"))
    if target ∉ position.boxes
        return Position(target, position.boxes), direction
    end
    beyond = target + offset
    if level.walls[beyond] || beyond in position.boxes
        throw(StepFailure("blocked"))
    end
    return Position(target, move_box(position.boxes, target, beyond)), uppercase(direction)
end

function pushable(level::Level, box, direction, boxes, reachable_cells)
    offset = level.offsets[direction]
    destination = box + offset
    return reachable_cells[box - offset] && level.interior[destination] && destination ∉ boxes
end

function side_blocked(level::Level, box, sides, boxes, assumed)
    any(side -> level.walls[side] || side in assumed, sides) && return true
    all(side -> level.dead[side], sides) && return true
    extended = [assumed; box]
    return any(side -> side in boxes && frozen(level, side, boxes, extended), sides)
end

function frozen(level::Level, box, boxes, assumed=Int[])
    horizontal = (box + level.offsets['l'], box + level.offsets['r'])
    vertical = (box + level.offsets['u'], box + level.offsets['d'])
    return side_blocked(level, box, horizontal, boxes, assumed) &&
           side_blocked(level, box, vertical, boxes, assumed)
end

function has_frozen_box(level::Level, boxes)
    return any(box -> !level.goals[box] && frozen(level, box, boxes), boxes)
end

function split_rows(level::Level, symbols)
    return [String(symbols[start:start+level.width-1]) for start in 1:level.width:level.size]
end

function cell_symbol(level::Level, cell, position)
    if level.walls[cell]
        return '#'
    elseif cell == position.player
        return level.goals[cell] ? '+' : '@'
    elseif cell in position.boxes
        return level.goals[cell] ? '*' : '$'
    end
    return level.goals[cell] ? '.' : '-'
end

function render(level::Level, position)
    return split_rows(level, [cell_symbol(level, cell, position) for cell in 1:level.size])
end

function dead_symbol(level::Level, cell)
    level.walls[cell] && return '#'
    level.goals[cell] && return '.'
    return level.dead[cell] ? 'x' : '-'
end

dead_map(level::Level) = split_rows(level, [dead_symbol(level, cell) for cell in 1:level.size])

function map_cell(level::Level, kind, cell)
    row, column = divrem(cell - 1, level.width)
    last_row, last_column = level.height - 1, level.width - 1
    if kind == "ROT90"
        return column * level.height + last_row - row + 1
    elseif kind == "ROT180"
        return (last_row - row) * level.width + last_column - column + 1
    elseif kind == "ROT270"
        return (last_column - column) * level.height + row + 1
    elseif kind == "FLIPH"
        return row * level.width + last_column - column + 1
    end
    return (last_row - row) * level.width + column + 1
end

function map_position(level::Level, kind, position)
    boxes = sort([map_cell(level, kind, box) for box in position.boxes])
    return Position(map_cell(level, kind, position.player), boxes)
end

function transformed(level::Level, kind)
    if kind in ("ROT90", "ROT270")
        height, width = level.width, level.height
    else
        height, width = level.height, level.width
    end
    walls = fill(false, level.size)
    goals = fill(false, level.size)
    interior = fill(false, level.size)
    for cell in 1:level.size
        moved = map_cell(level, kind, cell)
        walls[moved] = level.walls[cell]
        goals[moved] = level.goals[cell]
        interior[moved] = level.interior[cell]
    end
    return analyze!(Level(height, width, walls, goals, interior))
end

function build_level(rows)
    height, width = length(rows), length(rows[1])
    cells = collect(join(rows))
    walls = [symbol == '#' for symbol in cells]
    goals = [symbol in ".*+" for symbol in cells]
    players = findall(in("@+"), cells)
    boxes = findall(in("\$*"), cells)
    if length(players) == 1
        interior = find_interior(height, width, walls, players[1])
    else
        interior = fill(false, length(cells))
    end
    level = Level(height, width, walls, goals, interior)
    level.reason = invalidity(level, length(players), boxes)
    level.reason === nothing && analyze!(level)
    player = isempty(players) ? 0 : players[1]
    return level, Position(player, boxes)
end

struct SearchNode
    boxes::Vector{Int}
    representative::Int
    parent::Union{Int,Nothing}
    push::Union{Tuple{Int,Char},Nothing}
end

struct SearchResult
    outcome::String
    expanded::Int
    states::Int
    notation::String
end

SearchResult(outcome, expanded, states) = SearchResult(outcome, expanded, states, "")

function solution_pushes(nodes)
    pushes = Tuple{Int,Char}[]
    node = nodes[end]
    while node.parent !== nothing
        push!(pushes, node.push)
        node = nodes[node.parent]
    end
    return reverse(pushes)
end

function solution_notation(level::Level, position, pushes)
    pieces = String[]
    for (box, direction) in pushes
        offset = level.offsets[direction]
        push!(pieces, walk_path(level, position.player, box - offset, position.boxes))
        push!(pieces, string(uppercase(direction)))
        position = Position(box, move_box(position.boxes, box, box + offset))
    end
    return join(pieces)
end

function push_search(level::Level, start, fixed, target, pruning, limit)
    root = SearchNode(start.boxes, representative(level, start.player, start.boxes),
                      nothing, nothing)
    nodes = [root]
    known = Set([(root.boxes, root.representative)])
    expanded = 0
    while expanded < length(nodes)
        expanded == limit && return SearchResult("limit", expanded, length(nodes))
        expanded += 1
        node = nodes[expanded]
        reachable_cells = reachable(level, node.representative, node.boxes)
        for box in node.boxes
            box in fixed && continue
            for direction in DIRECTIONS
                pushable(level, box, direction, node.boxes, reachable_cells) || continue
                destination = box + level.offsets[direction]
                boxes = move_box(node.boxes, box, destination)
                if pruning && (level.dead[destination] || has_frozen_box(level, boxes))
                    continue
                end
                state = (boxes, representative(level, box, boxes))
                state in known && continue
                push!(known, state)
                push!(nodes, SearchNode(boxes, state[2], expanded, (box, direction)))
                reached = target === nothing ? solved(level, boxes) : destination == target
                if reached
                    notation = solution_notation(level, start, solution_pushes(nodes))
                    return SearchResult("found", expanded, length(nodes), notation)
                end
            end
        end
    end
    return SearchResult("no solution", expanded, length(nodes))
end

struct Snapshot
    position::Position
    history::Vector{Char}
end

struct Solution
    notation::String
    position::Position
end

mutable struct Sokoban
    level::Level
    initial::Position
    current::Position
    history::Vector{Char}
    redo_list::Vector{Char}
    snapshots::Dict{String,Snapshot}
    solution::Union{Solution,Nothing}

    function Sokoban(rows)
        game = new()
        load!(game, rows)
        return game
    end
end

emit(parts...) = println(join(parts, " "))

function load!(game::Sokoban, rows)
    game.level, game.initial = build_level(rows)
    game.current = game.initial
    game.history = Char[]
    game.redo_list = Char[]
    game.snapshots = Dict{String,Snapshot}()
    game.solution = nothing
end

function cell_argument(game::Sokoban, arguments, index)
    return cell_at(game.level, parse(Int, arguments[index]), parse(Int, arguments[index + 1]))
end

function simulate(game::Sokoban, directions)
    position = game.current
    letters = Char[]
    try
        for direction in directions
            position, letter = take_step(game.level, position, direction)
            push!(letters, letter)
        end
    catch failure
        failure isa StepFailure || rethrow()
        return position, letters, "step $(length(letters) + 1) $(failure.reason)"
    end
    return position, letters, nothing
end

function take_steps!(game::Sokoban, directions)
    game.current, letters, failure = simulate(game, directions)
    append!(game.history, letters)
    isempty(letters) || empty!(game.redo_list)
    return letters, failure
end

function progress(game::Sokoban, boxes)
    on_goals = boxes_on_goals(game.level, boxes)
    text = "goals $on_goals/$(length(boxes))"
    return on_goals == length(boxes) ? "$text solved" : text
end

function search_solution(game::Sokoban, limit)
    solved(game.level, game.current.boxes) && return ("already solved", nothing)
    result = push_search(game.level, game.current, Int[], nothing, true, limit)
    counts = "expanded $(result.expanded) states $(result.states)"
    result.outcome == "found" || return ("$(result.outcome) $counts", nothing)
    notation = result.notation
    return "solution pushes $(push_count(notation)) moves $(length(notation)) $counts", notation
end

function load_rows!(game::Sokoban, width, rows)
    for (number, row) in enumerate(rows)
        if length(row) != width || any(symbol -> symbol ∉ LEVEL_CHARACTERS, row)
            throw(CommandError("bad row $number"))
        end
    end
    load!(game, rows)
    emit("loaded", "$(length(rows))x$width")
end

function import_level!(game::Sokoban, arguments)
    rows = [decode(part, LEVEL_CHARACTERS) for part in split(arguments[1], "|")]
    if nothing in rows || length(rows) > MAX_SIDE
        throw(CommandError("bad level"))
    end
    width = length(rows[1])
    if any(row -> length(row) != width, rows) || !(1 <= width <= MAX_SIDE)
        throw(CommandError("bad level"))
    end
    load!(game, rows)
    emit("loaded", "$(length(rows))x$width")
end

function valid(game::Sokoban, arguments)
    reason = game.level.reason
    emit(reason === nothing ? "valid" : "invalid $reason")
end

function info(game::Sokoban, arguments)
    level = game.level
    emit("size", "$(level.height)x$(level.width)", "walls", count(level.walls),
         "cells", count(level.interior), "boxes", length(game.current.boxes),
         "dead", count(level.dead))
end

show_level(game::Sokoban, arguments) = foreach(emit, render(game.level, game.current))

function export_level(game::Sokoban, arguments)
    emit("level", join(encode.(render(game.level, game.current)), "|"))
end

function move!(game::Sokoban, arguments)
    letters, failure = take_steps!(game, step_sequence(arguments[1]))
    isempty(letters) || emit("moved", join(letters))
    failure === nothing || throw(CommandError(failure))
end

function push_box!(game::Sokoban, arguments)
    level, position = game.level, game.current
    box = cell_argument(game, arguments, 1)
    direction = arguments[3][1]
    offset = level.offsets[direction]
    box in position.boxes || throw(CommandError("no box"))
    destination = box + offset
    if !level.interior[destination] || destination in position.boxes
        throw(CommandError("blocked"))
    end
    if !reachable(level, position.player, position.boxes)[box - offset]
        throw(CommandError("unreachable"))
    end
    path = walk_path(level, position.player, box - offset, position.boxes)
    letters, _ = take_steps!(game, path * direction)
    emit("pushed", join(letters))
end

function bring!(game::Sokoban, arguments)
    position = game.current
    source = cell_argument(game, arguments, 1)
    target = cell_argument(game, arguments, 3)
    source in position.boxes || throw(CommandError("no box"))
    if source == target
        emit("brought", 0)
        return
    end
    fixed = filter(box -> box != source, position.boxes)
    result = push_search(game.level, position, fixed, target, false, nothing)
    result.outcome == "found" || throw(CommandError("no route"))
    take_steps!(game, lowercase(result.notation))
    emit("brought", push_count(result.notation), result.notation)
end

function path!(game::Sokoban, arguments)
    level, position = game.level, game.current
    target = cell_argument(game, arguments, 1)
    if !reachable(level, position.player, position.boxes)[target]
        throw(CommandError("unreachable"))
    end
    letters, _ = take_steps!(game, walk_path(level, position.player, target, position.boxes))
    emit(counted("path", letters))
end

function undo!(game::Sokoban, arguments)
    isempty(game.history) && throw(CommandError("nothing to undo"))
    steps = min(parse(Int, arguments[1]), length(game.history))
    for _ in 1:steps
        letter = pop!(game.history)
        direction = lowercase(letter)
        offset = game.level.offsets[direction]
        player = game.current.player
        boxes = game.current.boxes
        if isuppercase(letter)
            boxes = move_box(boxes, player + offset, player)
        end
        game.current = Position(player - offset, boxes)
        push!(game.redo_list, direction)
    end
    emit("undone", steps)
end

function redo!(game::Sokoban, arguments)
    isempty(game.redo_list) && throw(CommandError("nothing to redo"))
    steps = min(parse(Int, arguments[1]), length(game.redo_list))
    for _ in 1:steps
        game.current, letter = take_step(game.level, game.current, pop!(game.redo_list))
        push!(game.history, letter)
    end
    emit("redone", steps)
end

function reset!(game::Sokoban, arguments)
    game.current = game.initial
    game.history = Char[]
    game.redo_list = Char[]
    emit("reset")
end

function status(game::Sokoban, arguments)
    history = game.history
    emit("moves", length(history), "pushes", push_count(history),
         progress(game, game.current.boxes))
end

show_history(game::Sokoban, arguments) = emit(counted("history", game.history))

function show_boxes(game::Sokoban, arguments)
    level, position = game.level, game.current
    reachable_cells = reachable(level, position.player, position.boxes)
    emit("boxes", length(position.boxes))
    for box in position.boxes
        distance = goal_distance(level, box)
        directions = filter(DIRECTIONS) do direction
            pushable(level, box, direction, position.boxes, reachable_cells)
        end
        emit("box", cell_text(level, box), distance === nothing ? "dead" : distance,
             isempty(directions) ? "-" : directions)
    end
end

function reach(game::Sokoban, arguments)
    reachable_cells = reachable(game.level, game.current.player, game.current.boxes)
    first_cell = cell_text(game.level, findfirst(reachable_cells))
    emit("reach", count(reachable_cells), "first", first_cell)
end

function dead_squares(game::Sokoban, arguments)
    emit("dead", count(game.level.dead))
    foreach(emit, dead_map(game.level))
end

function deadlock(game::Sokoban, arguments)
    level, boxes = game.level, game.current.boxes
    for box in boxes
        if level.dead[box]
            emit("deadlock", "dead", cell_text(level, box))
            return
        end
    end
    for box in boxes
        if !level.goals[box] && frozen(level, box, boxes)
            emit("deadlock", "frozen", cell_text(level, box))
            return
        end
    end
    emit("no deadlock")
end

function bound(game::Sokoban, arguments)
    level, boxes = game.level, game.current.boxes
    best = nothing
    for order in permutations(collect(eachindex(level.goal_cells)))
        pushes = [level.distances[goal][box] for (box, goal) in zip(boxes, order)]
        nothing in pushes && continue
        if best === nothing || sum(pushes) < sum(best[2])
            best = (order, pushes)
        end
    end
    if best === nothing
        emit("bound none")
        return
    end
    order, pushes = best
    emit("bound", sum(pushes))
    for (box, goal, distance) in zip(boxes, order, pushes)
        emit("box", cell_text(level, box), "goal", cell_text(level, level.goal_cells[goal]),
             "pushes", distance)
    end
end

function save!(game::Sokoban, arguments)
    name = arguments[1]
    game.snapshots[name] = Snapshot(game.current, copy(game.history))
    emit("saved", name, "moves", length(game.history))
end

function restore!(game::Sokoban, arguments)
    name = arguments[1]
    haskey(game.snapshots, name) || throw(CommandError("no snapshot $name"))
    snapshot = game.snapshots[name]
    game.current = snapshot.position
    game.history = copy(snapshot.history)
    game.redo_list = Char[]
    emit("restored", name, "moves", length(game.history))
end

function check(game::Sokoban, arguments)
    position, letters, failure = simulate(game, step_sequence(arguments[1]))
    if failure !== nothing
        emit("check", "fail", failure)
        return
    end
    emit("check", "ok", "moves", length(letters), "pushes", push_count(letters),
         progress(game, position.boxes))
end

function solve!(game::Sokoban, arguments)
    summary, notation = search_solution(game, parse(Int, arguments[1]))
    emit(summary)
    game.solution = nothing
    if notation !== nothing
        emit(notation)
        game.solution = Solution(notation, game.current)
    end
end

function hint!(game::Sokoban, arguments)
    summary, notation = search_solution(game, parse(Int, arguments[1]))
    if notation === nothing
        emit(summary)
        return
    end
    part = notation[1:findfirst(isuppercase, notation)]
    take_steps!(game, lowercase(part))
    emit("hint", part)
end

function play!(game::Sokoban, arguments)
    solution = game.solution
    if solution === nothing || !same(solution.position, game.current)
        throw(CommandError("no solution"))
    end
    take_steps!(game, lowercase(solution.notation))
    emit("played", "pushes", push_count(solution.notation), "moves", length(solution.notation))
end

function transform!(game::Sokoban, arguments)
    kind = arguments[1]
    old = game.level
    game.level = transformed(old, kind)
    game.initial = map_position(old, kind, game.initial)
    game.current = map_position(old, kind, game.current)
    game.history = turn_letters(game.history, kind)
    game.redo_list = turn_letters(game.redo_list, kind)
    map!(values(game.snapshots)) do snapshot
        Snapshot(map_position(old, kind, snapshot.position), turn_letters(snapshot.history, kind))
    end
    solution = game.solution
    if solution !== nothing
        game.solution = Solution(join(turn_letters(solution.notation, kind)),
                                 map_position(old, kind, solution.position))
    end
    emit("transformed", "$(game.level.height)x$(game.level.width)")
end

const HANDLERS = Dict(
    "IMPORT" => import_level!,
    "VALID" => valid,
    "INFO" => info,
    "SHOW" => show_level,
    "EXPORT" => export_level,
    "MOVE" => move!,
    "PUSH" => push_box!,
    "BRING" => bring!,
    "PATH" => path!,
    "UNDO" => undo!,
    "REDO" => redo!,
    "RESET" => reset!,
    "STATUS" => status,
    "HISTORY" => show_history,
    "BOXES" => show_boxes,
    "REACH" => reach,
    "DEADSQUARES" => dead_squares,
    "DEADLOCK" => deadlock,
    "BOUND" => bound,
    "SAVE" => save!,
    "RESTORE" => restore!,
    "CHECK" => check,
    "SOLVE" => solve!,
    "HINT" => hint!,
    "PLAY" => play!,
    "TRANSFORM" => transform!,
)

function check_values(game::Sokoban, name, arguments)
    for index in 1:2:2*get(CELL_COUNTS, name, 0)
        row, column = parse(Int, arguments[index]), parse(Int, arguments[index + 1])
        contains_cell(game.level, row, column) || throw(CommandError("bad value"))
    end
    if name in ("UNDO", "REDO") && parse(Int, arguments[1]) < 1
        throw(CommandError("bad value"))
    end
    if name in ("SOLVE", "HINT") && !(1 <= parse(Int, arguments[1]) <= MAX_LIMIT)
        throw(CommandError("bad value"))
    end
end

function run_command!(game::Sokoban, name, arguments)
    haskey(COMMANDS, name) || throw(CommandError("unknown command $name"))
    kinds = COMMANDS[name]
    if length(arguments) != length(kinds) ||
       !all(valid_argument(kind, text) for (kind, text) in zip(kinds, arguments))
        throw(CommandError("bad arguments"))
    end
    if name ∉ LEVEL_FREE_COMMANDS
        game.level.reason === nothing || throw(CommandError("invalid level"))
        check_values(game, name, arguments)
    end
    HANDLERS[name](game, arguments)
end

function execute!(game::Sokoban, words, rows)
    try
        if words[1] == "LOAD"
            load_rows!(game, parse(Int, words[3]), rows)
        else
            run_command!(game, words[1], words[2:end])
        end
    catch error
        error isa CommandError || rethrow()
        emit("error:", error.message)
    end
end

function main()
    height = parse(Int, split(readline())[1])
    game = Sokoban([readline() for _ in 1:height])
    commands = parse(Int, strip(readline()))
    for _ in 1:commands
        words = split(readline(), " ")
        rows = words[1] == "LOAD" ? [readline() for _ in 1:parse(Int, words[2])] : String[]
        execute!(game, words, rows)
    end
end

main()
