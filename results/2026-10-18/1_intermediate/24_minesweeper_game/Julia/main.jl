@enum Safety::UInt8 BLOCK CELL_SAFETY NO_SAFETY
@enum GameState::UInt8 READY PLAYING WON LOST
@enum Mark::UInt8 UNMARKED FLAGGED QUESTIONED
@enum MoveKind::UInt8 REVEAL_MOVE=1 FLAG_MOVE UNFLAG_MOVE QUESTION_MOVE CHORD_MOVE AUTO_REVEAL AUTO_FLAG GUESS

const ARITY = Dict("NEW" => 4, "PRESET" => 2, "LAYOUT" => 2, "SAFETY" => 1, "RESTART" => 0,
    "REVEAL" => 2, "FLAG" => 2, "UNFLAG" => 2, "QUESTION" => 2, "CHORD" => 2,
    "UNDO" => 0, "SHOW" => 0, "STATUS" => 0, "CELL" => 2, "HISTORY" => 1,
    "REPLAY" => 1, "HINT" => 0, "AUTO" => 0, "ANALYZE" => 0, "PROB" => 2,
    "FRONTIER" => 0, "SOLVE" => 0, "BOARDINFO" => 0, "STATS" => 0)
const PRESETS = Dict("beginner" => (9, 9, 10), "intermediate" => (16, 16, 40), "expert" => (30, 16, 99))
const SAFETY_MODES = Dict("block" => BLOCK, "cell" => CELL_SAFETY, "none" => NO_SAFETY)
const CELL_COMMANDS = Set(split("REVEAL FLAG UNFLAG QUESTION CHORD CELL PROB"))
const ACTIVE_COMMANDS = Set(split("REVEAL FLAG UNFLAG QUESTION CHORD UNDO HINT AUTO ANALYZE PROB FRONTIER SOLVE"))
const UNDO_COMMANDS = Set(split("REVEAL FLAG UNFLAG QUESTION CHORD AUTO SOLVE"))
const MOVE_NAMES = ("reveal", "flag", "unflag", "question", "chord", "auto-reveal", "auto-flag", "guess")

struct CommandError <: Exception
    reason::String
end
fail(reason::AbstractString) = throw(CommandError(String(reason)))
emit(parts...) = println(join(string.(parts), " "))

function number_word(text::String)::Int64
    occursin(r"^(0|[1-9][0-9]{0,9})$", text) || fail("bad arguments")
    parse(Int64, text)
end

function fraction(numerator::Int, denominator::Int)::String
    divisor = gcd(numerator, denominator)
    string(div(numerator, divisor), "/", div(denominator, divisor))
end

struct Move
    kind::MoveKind
    cell::Int
end

struct UndoRecord
    command::String
    revealed::BitVector
    marks::Vector{Mark}
    moves::Vector{Move}
end

mutable struct Board
    width::Int
    height::Int
    mine_count::Int
    seed::Int64
    placed::Bool
    mines::BitVector
    numbers::Vector{Int}
    revealed::BitVector
    marks::Vector{Mark}
    neighbors::Vector{Vector{Int}}
    state::GameState
    exploded::Union{Nothing,Int}
    moves::Vector{Move}
    undos::Vector{UndoRecord}
end

function Board(width::Int, height::Int, mine_count::Int, seed::Int64)
    cell_count = width * height
    neighbors = [Int[] for _ in 1:cell_count]
    for cell in 1:cell_count
        column, row = (cell - 1) % width, div(cell - 1, width)
        for dy in -1:1, dx in -1:1
            x, y = column + dx, row + dy
            if (dx != 0 || dy != 0) && 0 <= x < width && 0 <= y < height
                push!(neighbors[cell], x + width * y + 1)
            end
        end
    end
    Board(width, height, mine_count, seed, false, falses(cell_count), zeros(Int, cell_count),
          falses(cell_count), fill(UNMARKED, cell_count), neighbors, READY, nothing, Move[], UndoRecord[])
end

cell_text(board::Board, cell::Int) = string((cell - 1) % board.width, ",", div(cell - 1, board.width))
size_text(board::Board) = "$(board.width)x$(board.height)"
remaining_mines(board::Board)::Int = board.mine_count - count(==(FLAGGED), board.marks)
revealed_count(board::Board)::Int = count(board.revealed)
safe_count(board::Board)::Int = board.width * board.height - board.mine_count
is_unknown(board::Board, cell::Int)::Bool = !board.revealed[cell] && board.marks[cell] != FLAGGED
unknown_cells(board::Board)::Vector{Int} = [cell for cell in eachindex(board.mines) if is_unknown(board, cell)]
finished(board::Board)::Bool = board.state == WON || board.state == LOST
record_move!(board::Board, kind::MoveKind, cell::Int) = push!(board.moves, Move(kind, cell))

function compute_numbers!(board::Board)
    for cell in eachindex(board.numbers)
        board.numbers[cell] = count(neighbor -> board.mines[neighbor], board.neighbors[cell])
    end
end

function place_mines!(board::Board, first_cell::Int, safety::Safety)
    x, y = (first_cell - 1) % board.width, div(first_cell - 1, board.width)
    choices = collect(eachindex(board.mines))
    if safety == CELL_SAFETY
        filter!(cell -> cell != first_cell, choices)
    elseif safety == BLOCK
        filter!(cell -> abs((cell - 1) % board.width - x) >= 2 ||
                        abs(div(cell - 1, board.width) - y) >= 2, choices)
    end
    generator = board.seed
    for _ in 1:board.mine_count
        generator = 48271 * generator % 2147483647
        index = Int(generator % length(choices)) + 1
        board.mines[choices[index]] = true
        deleteat!(choices, index)
    end
    compute_numbers!(board)
    board.placed = true
    board.state = PLAYING
end

function reset_board!(board::Board)
    fill!(board.revealed, false)
    fill!(board.marks, UNMARKED)
    empty!(board.moves)
    empty!(board.undos)
    board.exploded = nothing
    board.state = board.placed ? PLAYING : READY
end

function reveal_cell!(board::Board, cell::Int, safety::Safety)::Int
    board.placed || place_mines!(board, cell, safety)
    if board.mines[cell]
        board.state = LOST
        board.exploded = cell
        return 0
    end
    board.revealed[cell] = true
    board.marks[cell] = UNMARKED
    queue = Int[cell]
    head = 1
    while head <= length(queue)
        current = queue[head]
        head += 1
        board.numbers[current] == 0 || continue
        for neighbor in board.neighbors[current]
            if is_unknown(board, neighbor)
                board.revealed[neighbor] = true
                board.marks[neighbor] = UNMARKED
                push!(queue, neighbor)
            end
        end
    end
    length(queue)
end

function chord_cells!(board::Board, cell::Int, safety::Safety)::Int
    opened = 0
    for neighbor in board.neighbors[cell]
        is_unknown(board, neighbor) || continue
        opened += reveal_cell!(board, neighbor, safety)
        board.state == LOST && break
    end
    opened
end

function win_check!(board::Board)
    if board.state == PLAYING && revealed_count(board) == safe_count(board)
        board.state = WON
        board.marks[board.mines] .= FLAGGED
    end
end

function show_board(board::Board)
    symbols = Vector{Char}(undef, length(board.mines))
    for cell in eachindex(symbols)
        symbols[cell] = if board.state == LOST && board.mines[cell]
            cell == board.exploded ? '!' : board.marks[cell] == FLAGGED ? 'F' : '*'
        elseif board.state == LOST && board.marks[cell] == FLAGGED
            'X'
        elseif board.revealed[cell]
            board.numbers[cell] == 0 ? '.' : Char(Int('0') + board.numbers[cell])
        else
            board.marks[cell] == FLAGGED ? 'F' : board.marks[cell] == QUESTIONED ? '?' : '#'
        end
    end
    for row in 0:(board.height - 1)
        emit(join(view(symbols, (row * board.width + 1):((row + 1) * board.width))))
    end
end

function finish_output(board::Board)
    if board.state == LOST
        emit("boom", cell_text(board, something(board.exploded)))
        show_board(board)
    elseif board.state == WON
        emit("win moves", length(board.moves))
    end
end

struct Constraint
    cell::Int
    unknown::Vector{Int}
    remaining::Int
end

function constraints(board::Board)::Vector{Constraint}
    result = Constraint[]
    for cell in eachindex(board.mines)
        board.revealed[cell] && board.numbers[cell] > 0 || continue
        neighbors = board.neighbors[cell]
        unknown = [neighbor for neighbor in neighbors if is_unknown(board, neighbor)]
        isempty(unknown) && continue
        flags = count(neighbor -> board.marks[neighbor] == FLAGGED, neighbors)
        push!(result, Constraint(cell, unknown, board.numbers[cell] - flags))
    end
    result
end

struct Deduction
    safe::Dict{Int,String}
    mines::Dict{Int,String}
end
Deduction() = Deduction(Dict{Int,String}(), Dict{Int,String}())
has_deduction(found::Deduction) = !isempty(found.safe) || !isempty(found.mines)

function add_reasons!(reasons::Dict{Int,String}, cells::Vector{Int}, reason::String)
    for cell in cells
        get!(reasons, cell, reason)
    end
end

function deduction(board::Board)::Deduction
    known = constraints(board)
    result = Deduction()
    for clue in known
        clue.remaining == 0 && add_reasons!(result.safe, clue.unknown, "single $(cell_text(board, clue.cell))")
    end
    has_deduction(result) && return result
    for clue in known
        clue.remaining == length(clue.unknown) && add_reasons!(result.mines, clue.unknown, "single $(cell_text(board, clue.cell))")
    end
    has_deduction(result) && return result
    for left in known, right in known
        length(left.unknown) < length(right.unknown) || continue
        all(cell -> cell in right.unknown, left.unknown) || continue
        difference = [cell for cell in right.unknown if !(cell in left.unknown)]
        needed = right.remaining - left.remaining
        reason = "subset $(cell_text(board, left.cell)) $(cell_text(board, right.cell))"
        if needed == 0
            add_reasons!(result.safe, difference, reason)
        elseif needed == length(difference)
            add_reasons!(result.mines, difference, reason)
        end
    end
    if !has_deduction(result) && board.state == PLAYING && remaining_mines(board) == 0
        add_reasons!(result.safe, unknown_cells(board), "count")
    end
    result
end

mutable struct AutoTotals
    rounds::Int
    flagged::Int
    opened::Int
end
AutoTotals() = AutoTotals(0, 0, 0)

function auto_play!(board::Board, safety::Safety)::AutoTotals
    totals = AutoTotals()
    while board.state == PLAYING
        found = deduction(board)
        has_deduction(found) || break
        totals.rounds += 1
        for cell in sort!(collect(keys(found.safe)))
            board.revealed[cell] && continue
            record_move!(board, AUTO_REVEAL, cell)
            totals.opened += reveal_cell!(board, cell, safety)
            win_check!(board)
            finished(board) && return totals
        end
        for cell in sort!(collect(keys(found.mines)))
            is_unknown(board, cell) || continue
            board.marks[cell] = FLAGGED
            totals.flagged += 1
            record_move!(board, AUTO_FLAG, cell)
        end
    end
    totals
end

struct Component
    cells::Vector{Int}
    configs::Int
    hits::Vector{Int}
    minimum::Int
    maximum::Int
end

mutable struct ConfigurationSearch
    order::Vector{Int}
    touched::Vector{Vector{Int}}
    required::Vector{Int}
    left::Vector{Int}
    assigned::Vector{Int}
    choice::BitVector
    configs::Int
    hits::Vector{Int}
    minimum::Int
    maximum::Int
end

function search_configurations!(search::ConfigurationSearch, depth::Int, total::Int)
    if depth > length(search.order)
        search.configs += 1
        search.hits .+= search.choice
        search.minimum = min(search.minimum, total)
        search.maximum = max(search.maximum, total)
        return
    end
    position = search.order[depth]
    involved = search.touched[position]
    search.left[involved] .-= 1
    for value in 0:1
        search.choice[position] = value == 1
        search.assigned[involved] .+= value
        if all(index -> search.assigned[index] <= search.required[index] <= search.assigned[index] + search.left[index], involved)
            search_configurations!(search, depth + 1, total + value)
        end
        search.assigned[involved] .-= value
    end
    search.left[involved] .+= 1
end

function count_component(cells::Vector{Int}, clues::Vector{Constraint})::Component
    positions = Dict(cell => index for (index, cell) in enumerate(cells))
    local_sets = [[positions[cell] for cell in clue.unknown] for clue in clues]
    touched = [Int[] for _ in cells]
    for (index, local_set) in enumerate(local_sets), cell in local_set
        push!(touched[cell], index)
    end
    required = [clue.remaining for clue in clues]
    left = length.(local_sets)
    order = sortperm(eachindex(cells); by = cell -> (-length(touched[cell]), cell))
    search = ConfigurationSearch(order, touched, required, left, zeros(Int, length(clues)),
                                 falses(length(cells)), 0, zeros(Int, length(cells)), length(cells), 0)
    if all(index -> 0 <= required[index] <= left[index], eachindex(required))
        search_configurations!(search, 1, 0)
    end
    Component(cells, search.configs, search.hits, search.minimum, search.maximum)
end

struct Frontier
    mask::BitVector
    components::Vector{Component}
end

function frontier(board::Board, target::Union{Nothing,Int}=nothing)::Frontier
    known = constraints(board)
    incident = [Int[] for _ in board.mines]
    for (index, clue) in enumerate(known), cell in clue.unknown
        push!(incident[cell], index)
    end
    mask = BitVector(length.(incident) .> 0)
    result = Frontier(mask, Component[])
    target !== nothing && !mask[target] && return result
    visited = falses(length(mask))
    expanded = falses(length(known))
    for root in findall(mask)
        visited[root] && continue
        queue = Int[root]
        visited[root] = true
        clue_ids = Int[]
        head = 1
        while head <= length(queue)
            cell = queue[head]
            head += 1
            for index in incident[cell]
                expanded[index] && continue
                expanded[index] = true
                push!(clue_ids, index)
                for neighbor in known[index].unknown
                    visited[neighbor] && continue
                    visited[neighbor] = true
                    push!(queue, neighbor)
                end
            end
        end
        cells = sort!(queue)
        if target === nothing || target in cells
            push!(result.components, count_component(cells, known[clue_ids]))
            target !== nothing && break
        end
    end
    result
end

function guess_cell(board::Board)::Union{Nothing,Int}
    boundary = frontier(board)
    numerators = zeros(Int, length(board.mines))
    denominators = zeros(Int, length(board.mines))
    unknown = unknown_cells(board)
    for cell in unknown
        boundary.mask[cell] && continue
        numerators[cell] = max(remaining_mines(board), 0)
        denominators[cell] = length(unknown)
    end
    for component in boundary.components
        component.configs == 0 && continue
        numerators[component.cells] .= component.hits
        denominators[component.cells] .= component.configs
    end
    chosen = nothing
    for cell in eachindex(denominators)
        denominators[cell] == 0 && continue
        if chosen === nothing || numerators[cell] * denominators[chosen] < numerators[chosen] * denominators[cell]
            chosen = cell
        end
    end
    chosen
end

function solve_board!(board::Board, safety::Safety)
    totals = AutoTotals()
    guesses = 0
    while true
        part = auto_play!(board, safety)
        totals.rounds += part.rounds
        totals.flagged += part.flagged
        totals.opened += part.opened
        finished(board) && break
        cell = guess_cell(board)
        cell === nothing && break
        guesses += 1
        record_move!(board, GUESS, cell)
        totals.opened += reveal_cell!(board, cell, safety)
        win_check!(board)
        finished(board) && break
    end
    (; guesses, rounds = totals.rounds, flagged = totals.flagged, opened = totals.opened)
end

function replay_board(board::Board, move_count::Int, safety::Safety)::Board
    replay = deepcopy(board)
    reset_board!(replay)
    for index in 1:move_count
        move = board.moves[index]
        if move.kind in (REVEAL_MOVE, AUTO_REVEAL, GUESS)
            reveal_cell!(replay, move.cell, safety)
        elseif move.kind == CHORD_MOVE
            chord_cells!(replay, move.cell, safety)
        elseif move.kind in (FLAG_MOVE, AUTO_FLAG)
            replay.marks[move.cell] = FLAGGED
        elseif move.kind == UNFLAG_MOVE
            replay.marks[move.cell] = UNMARKED
        else
            replay.marks[move.cell] = replay.marks[move.cell] == QUESTIONED ? UNMARKED : QUESTIONED
        end
        win_check!(replay)
    end
    replay
end

function board_info(board::Board)
    blank = .!board.mines .& (board.numbers .== 0)
    visited, covered = falses(length(blank)), falses(length(blank))
    openings = 0
    largest = 0
    for root in findall(blank)
        visited[root] && continue
        openings += 1
        queue = Int[root]
        visited[root] = true
        coverage = falses(length(blank))
        coverage[root] = true
        head = 1
        while head <= length(queue)
            cell = queue[head]
            head += 1
            for neighbor in board.neighbors[cell]
                coverage[neighbor] = true
                if blank[neighbor] && !visited[neighbor]
                    visited[neighbor] = true
                    push!(queue, neighbor)
                end
            end
        end
        covered .|= coverage
        largest = max(largest, count(coverage))
    end
    bv = openings + count(cell -> !board.mines[cell] && !covered[cell], eachindex(board.mines))
    emit("3bv", bv, "openings", openings, "largest", largest, "mines", board.mine_count, "safe", safe_count(board))
end

mutable struct Statistics
    played::Int
    won::Int
    lost::Int
    streak::Int
    best::Int
    fastest::Union{Nothing,Int}
end
Statistics() = Statistics(0, 0, 0, 0, 0, nothing)

mutable struct Program
    board::Union{Nothing,Board}
    safety::Safety
    stats::Statistics
end
Program() = Program(nothing, BLOCK, Statistics())

function update_statistics!(stats::Statistics, board::Board)
    stats.played += 1
    if board.state == WON
        stats.won += 1
        stats.streak += 1
        stats.best = max(stats.best, stats.streak)
        stats.fastest = stats.fastest === nothing ? length(board.moves) : min(stats.fastest, length(board.moves))
    else
        stats.lost += 1
        stats.streak = 0
    end
end

function layout_command!(app::Program, width::Int, height::Int, rows::Vector{String})
    for (index, row) in enumerate(rows)
        ncodeunits(row) == width && all(character -> character == '*' || character == '.', row) || fail("bad row $index")
    end
    mines = BitVector([character == '*' for row in rows for character in row])
    mine_count = count(mines)
    0 < mine_count < width * height || fail("bad mine count $mine_count")
    board = Board(width, height, mine_count, Int64(0))
    board.mines = mines
    compute_numbers!(board)
    board.placed = true
    board.state = PLAYING
    app.board = board
    emit("layout", size_text(board), "mines", mine_count)
end

function execute!(app::Program, words::Vector{String})
    command = words[1]
    arguments = words[2:end]
    haskey(ARITY, command) || fail("unknown command $command")
    length(arguments) == ARITY[command] || fail("bad arguments")
    values = Int64[]
    if command == "PRESET"
        haskey(PRESETS, arguments[1]) || fail("bad arguments")
        push!(values, number_word(arguments[2]))
    elseif command == "SAFETY"
        haskey(SAFETY_MODES, arguments[1]) || fail("bad arguments")
    else
        values = number_word.(arguments)
    end
    if command == "NEW" || command == "PRESET"
        if command == "NEW"
            width, height, mines, seed = values
        else
            width, height, mines = PRESETS[arguments[1]]
            seed = values[1]
        end
        1 <= width <= 30 && 1 <= height <= 30 && 1 <= mines <= width * height - 9 &&
            1 <= seed <= 2147483646 || fail("bad value")
        app.board = Board(Int(width), Int(height), Int(mines), seed)
        emit("new", size_text(app.board), "mines", mines)
        return
    end
    command == "HISTORY" && values[1] == 0 && fail("bad value")
    if command == "SAFETY"
        app.safety = SAFETY_MODES[arguments[1]]
        emit("safety", arguments[1])
        return
    elseif command == "STATS"
        stats = app.stats
        rate = stats.played == 0 ? "-" : string(div(100 * stats.won, stats.played), "%")
        emit("stats played", stats.played, "won", stats.won, "lost", stats.lost, "rate", rate,
             "streak", stats.streak, "best", stats.best, "fastest", something(stats.fastest, "-"))
        return
    end
    board = app.board
    board === nothing && fail("no game")
    cell = 0
    if command in CELL_COMMANDS
        values[1] < board.width && values[2] < board.height || fail("out of range")
        cell = Int(values[1] + board.width * values[2]) + 1
    end
    command in ACTIVE_COMMANDS && finished(board) && fail("game over")
    command in ("ANALYZE", "BOARDINFO") && !board.placed && fail("not started")
    before = command in UNDO_COMMANDS ? UndoRecord(lowercase(command), copy(board.revealed), copy(board.marks), copy(board.moves)) : nothing
    if command == "RESTART"
        reset_board!(board)
        emit("restart", size_text(board), "mines", board.mine_count)
    elseif command == "REVEAL"
        board.revealed[cell] && fail("already revealed")
        board.marks[cell] == FLAGGED && fail("flagged")
        record_move!(board, REVEAL_MOVE, cell)
        opened = reveal_cell!(board, cell, app.safety)
        if board.state != LOST
            emit("revealed", opened)
            win_check!(board)
        end
        finish_output(board)
    elseif command == "FLAG"
        board.revealed[cell] && fail("already revealed")
        board.marks[cell] == FLAGGED && fail("already flagged")
        board.marks[cell] = FLAGGED
        record_move!(board, FLAG_MOVE, cell)
        emit("flagged", cell_text(board, cell), "left", remaining_mines(board))
    elseif command == "UNFLAG"
        board.revealed[cell] && fail("already revealed")
        board.marks[cell] == FLAGGED || fail("not flagged")
        board.marks[cell] = UNMARKED
        record_move!(board, UNFLAG_MOVE, cell)
        emit("unflagged", cell_text(board, cell), "left", remaining_mines(board))
    elseif command == "QUESTION"
        board.revealed[cell] && fail("already revealed")
        record_move!(board, QUESTION_MOVE, cell)
        board.marks[cell] = board.marks[cell] == QUESTIONED ? UNMARKED : QUESTIONED
        emit(board.marks[cell] == UNMARKED ? "unmarked" : "questioned", cell_text(board, cell), "left", remaining_mines(board))
    elseif command == "CHORD"
        board.revealed[cell] || fail("not revealed")
        board.numbers[cell] > 0 || fail("no number")
        neighbors = board.neighbors[cell]
        flags = count(neighbor -> board.marks[neighbor] == FLAGGED, neighbors)
        flags == board.numbers[cell] || fail("flags $flags of $(board.numbers[cell])")
        any(neighbor -> is_unknown(board, neighbor), neighbors) || fail("nothing to reveal")
        record_move!(board, CHORD_MOVE, cell)
        opened = chord_cells!(board, cell, app.safety)
        if board.state != LOST
            emit("chorded", opened)
            win_check!(board)
        end
        finish_output(board)
    elseif command == "UNDO"
        isempty(board.undos) && fail("nothing to undo")
        saved = pop!(board.undos)
        board.revealed = copy(saved.revealed)
        board.marks = copy(saved.marks)
        board.moves = copy(saved.moves)
        emit("undo", saved.command, "moves", length(board.moves))
    elseif command == "SHOW"
        show_board(board)
    elseif command == "STATUS"
        emit("status", lowercase(string(board.state)), "left", remaining_mines(board), "moves", length(board.moves),
             "revealed", "$(revealed_count(board))/$(safe_count(board))")
    elseif command == "CELL"
        neighbors = board.neighbors[cell]
        if board.revealed[cell]
            emit("cell", cell_text(board, cell), "number", board.numbers[cell],
                 "flags", count(neighbor -> board.marks[neighbor] == FLAGGED, neighbors),
                 "unknown", count(neighbor -> is_unknown(board, neighbor), neighbors))
        else
            mark = board.marks[cell] == FLAGGED ? "flag" : board.marks[cell] == QUESTIONED ? "question" : "none"
            emit("cell", cell_text(board, cell), "hidden mark", mark,
                 "open", count(neighbor -> board.revealed[neighbor], neighbors))
        end
    elseif command == "HISTORY"
        move_count = length(board.moves)
        emit("history", move_count)
        for index in max(1, move_count - values[1] + 1):move_count
            move = board.moves[index]
            emit(index, MOVE_NAMES[Int(move.kind)], cell_text(board, move.cell))
        end
    elseif command == "REPLAY"
        values[1] <= length(board.moves) || fail("no move $(values[1])")
        emit("replay", "$(values[1])/$(length(board.moves))")
        show_board(replay_board(board, Int(values[1]), app.safety))
    elseif command == "HINT"
        found = deduction(board)
        if !isempty(found.safe)
            target = minimum(keys(found.safe))
            emit("hint safe", cell_text(board, target), "by", found.safe[target])
        elseif !isempty(found.mines)
            target = minimum(keys(found.mines))
            emit("hint mine", cell_text(board, target), "by", found.mines[target])
        else
            emit("hint none")
        end
    elseif command == "AUTO"
        totals = auto_play!(board, app.safety)
        emit("auto rounds", totals.rounds, "flagged", totals.flagged, "revealed", totals.opened)
        finish_output(board)
    elseif command == "ANALYZE"
        trial = deepcopy(board)
        totals = auto_play!(trial, app.safety)
        if trial.state == LOST
            emit("analyze boom", cell_text(trial, something(trial.exploded)), "rounds", totals.rounds)
        elseif trial.state == WON
            emit("analyze clear rounds", totals.rounds)
        else
            emit("analyze stuck rounds", totals.rounds, "revealed", "$(revealed_count(trial))/$(safe_count(trial))")
        end
    elseif command == "PROB"
        board.revealed[cell] && fail("already revealed")
        board.marks[cell] == FLAGGED && fail("flagged")
        boundary = frontier(board, cell)
        if !boundary.mask[cell]
            emit("prob", cell_text(board, cell), "unconstrained")
        else
            component = only(boundary.components)
            if component.configs == 0
                emit("prob", cell_text(board, cell), "inconsistent")
            else
                index = findfirst(==(cell), component.cells)
                emit("prob", cell_text(board, cell), fraction(component.hits[index], component.configs),
                     "size", length(component.cells), "configs", component.configs)
            end
        end
    elseif command == "FRONTIER"
        boundary = frontier(board)
        emit("frontier", count(boundary.mask), "components", length(boundary.components))
        for component in boundary.components
            prefix = "component $(cell_text(board, first(component.cells))) size $(length(component.cells))"
            if component.configs == 0
                emit(prefix, "inconsistent")
            else
                emit(prefix, "configs", component.configs, "min", component.minimum, "max", component.maximum)
            end
        end
    elseif command == "SOLVE"
        result = solve_board!(board, app.safety)
        emit("solve guesses", result.guesses, "rounds", result.rounds, "flagged", result.flagged, "revealed", result.opened)
        finish_output(board)
    elseif command == "BOARDINFO"
        board_info(board)
    end
    if before !== nothing && length(board.moves) > length(before.moves)
        push!(board.undos, before)
        finished(board) && update_statistics!(app.stats, board)
    end
end

function main()
    command_count = parse(Int, readline())
    app = Program()
    for _ in 1:command_count
        words = String.(split(readline(), ' '))
        rows = words[1] == "LAYOUT" ? [readline() for _ in 1:parse(Int, words[3])] : String[]
        try
            if words[1] == "LAYOUT"
                layout_command!(app, parse(Int, words[2]), parse(Int, words[3]), rows)
            else
                execute!(app, words)
            end
        catch error
            error isa CommandError || rethrow()
            emit("error:", error.reason)
        end
    end
end

main()
