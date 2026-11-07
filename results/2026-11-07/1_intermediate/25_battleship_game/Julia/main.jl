@enum Phase::UInt8 SETUP BATTLE OVER
@enum Strategy::UInt8 HUNT PROB RANDOM
@enum CellView::UInt8 REEF UNATTACKED MISS_VIEW HIT_VIEW SUNK_VIEW
@enum ShotResult::UInt8 ALREADY MISS HIT SUNK
@enum OutputMode::UInt8 NORMAL SINKS_ONLY QUIET

const SHIP_NAMES = ("CARRIER", "BATTLESHIP", "CRUISER", "SUBMARINE", "DESTROYER")
const SHIP_LENGTHS = (5, 4, 3, 3, 2)
const SHIP_SYMBOLS = ('C', 'B', 'R', 'S', 'D')
const STRATEGIES = (HUNT, PROB, RANDOM)
const STRATEGY_BY_NAME = Dict(string(strategy) => strategy for strategy in STRATEGIES)
const SETUP_COMMANDS = Set(split("PLACE REMOVE AUTOPLACE LAYOUT REEF SALVO CHAIN TOUCH"))
const TURN_COMMANDS = Set(split("FIRE AI TORPEDO SONAR"))
const PLAYER_COMMANDS = Set(split("PLACE REMOVE AUTOPLACE LAYOUT FIRE AI TORPEDO SONAR RESIGN CONTROL SEED HINT DENSITY SHOW RADAR EXPORT FLEET"))

struct CommandError <: Exception
    reason::String
end
fail(reason::AbstractString) = throw(CommandError(String(reason)))
emit(parts...) = println(join(string.(parts), " "))
coordinate(cell::Int) = string('A' + div(cell - 1, 10), (cell - 1) % 10 + 1)
parse_cell(text::String) = Int(text[1] - 'A') * 10 + parse(Int, text[2:end])
ship_number(name::String) = something(findfirst(==(name), SHIP_NAMES))
advance(state::Int64)::Int64 = 48271 * state % 2147483647
switch_name(value::Bool) = value ? "ON" : "OFF"

function neighbor(cell::Int, dr::Int, dc::Int)::Int
    row, column = div(cell - 1, 10) + dr, (cell - 1) % 10 + dc
    0 <= row < 10 && 0 <= column < 10 ? row * 10 + column + 1 : 0
end

adjacent(first::Int, second::Int) =
    abs(div(first - 1, 10) - div(second - 1, 10)) <= 1 && abs((first - 1) % 10 - (second - 1) % 10) <= 1

struct Ship
    start::Int
    stride::Int
end
ship_cells(ship::Ship, size::Int) = ship.start:ship.stride:ship.start + (size - 1) * ship.stride
in_bounds(ship::Ship, size::Int) = (ship.stride == 1 ? (ship.start - 1) % 10 : div(ship.start - 1, 10)) + size <= 10
ship_range(ship::Ship, size::Int) = string(coordinate(ship.start), "-", coordinate(ship.start + (size - 1) * ship.stride))
touching(first::Ship, first_size::Int, second::Ship, second_size::Int) =
    any(a -> any(b -> adjacent(a, b), ship_cells(second, second_size)), ship_cells(first, first_size))

const PLACEMENTS = [[Ship(start, stride) for start in 1:100 for stride in (1, 10)
                     if in_bounds(Ship(start, stride), size)] for size in SHIP_LENGTHS]

mutable struct Statistics
    shots::Int64
    hits::Int64
    sinks::Int64
    turns::Int64
    streak::Int64
    longest::Int64
    wins::Int64
end
Statistics() = Statistics(0, 0, 0, 0, 0, 0, 0)

mutable struct Player
    fleet::Vector{Union{Nothing,Ship}}
    board::Vector{Int}
    attacked::BitVector
    candidates::Vector{Int}
    random::Int64
    controller::Union{Nothing,Strategy}
    torpedo_used::Bool
    sonar_used::Bool
    statistics::Statistics
end
Player(seed::Int64) = Player(Union{Nothing,Ship}[nothing for _ in 1:5], zeros(Int, 100),
    falses(100), Int[], seed, nothing, false, false, Statistics())

mutable struct Game
    players::NTuple{2,Player}
    reefs::BitVector
    salvo::Bool
    chain::Bool
    touch::Bool
    phase::Phase
    current::Int
    winner::Union{Nothing,Int}
end
Game() = Game((Player(Int64(1)), Player(Int64(2))), falses(100), false, false, false, SETUP, 1, nothing)

function clear_fleet!(player::Player)
    fill!(player.fleet, nothing)
    fill!(player.board, 0)
end

function put_ship!(player::Player, number::Int, ship::Ship)
    player.fleet[number] = ship
    player.board[ship_cells(ship, SHIP_LENGTHS[number])] .= number
end

function attacked_count(player::Player, number::Int)::Int
    ship = player.fleet[number]
    ship === nothing ? 0 : count(cell -> player.attacked[cell], ship_cells(ship, SHIP_LENGTHS[number]))
end
is_sunk(player::Player, number::Int) = player.fleet[number] !== nothing && attacked_count(player, number) == SHIP_LENGTHS[number]
placed_count(player::Player) = count(ship -> ship !== nothing, player.fleet)
afloat_count(player::Player) = count(number -> player.fleet[number] !== nothing && !is_sunk(player, number), 1:5)
defeated(player::Player) = all(number -> is_sunk(player, number), 1:5)
allowance(game::Game, player::Int) = game.salvo ? afloat_count(game.players[player]) : 1

function placement_problem(game::Game, player::Player, number::Int, ship::Ship)::Union{Nothing,String}
    size = SHIP_LENGTHS[number]
    in_bounds(ship, size) || return "out of bounds"
    cells = ship_cells(ship, size)
    any(cell -> game.reefs[cell], cells) && return "on reef"
    for other in 1:5
        any(cell -> player.board[cell] == other, cells) && return "overlaps $(SHIP_NAMES[other])"
    end
    if !game.touch
        for other in 1:5
            placed = player.fleet[other]
            if placed !== nothing && touching(ship, size, placed, SHIP_LENGTHS[other])
                return "touches $(SHIP_NAMES[other])"
            end
        end
    end
    nothing
end

function placement_output(game::Game, player::Int)
    for number in 1:5
        ship = something(game.players[player].fleet[number])
        emit("PLACED", player, SHIP_NAMES[number], ship_range(ship, SHIP_LENGTHS[number]))
    end
end

function auto_place!(game::Game, player::Int, seed::Int64)::Int64
    owner = game.players[player]
    owner.random = seed
    clear_fleet!(owner)
    attempts = Int64(0)
    for number in 1:5
        size = SHIP_LENGTHS[number]
        while owner.fleet[number] === nothing
            attempts += 1
            owner.random = advance(owner.random)
            stride = iseven(owner.random) ? 1 : 10
            owner.random = advance(owner.random)
            index = Int(owner.random % (10 * (11 - size)))
            start = stride == 1 ? div(index, 11 - size) * 10 + index % (11 - size) + 1 : index + 1
            ship = Ship(start, stride)
            placement_problem(game, owner, number, ship) === nothing && put_ship!(owner, number, ship)
        end
    end
    attempts
end

function layout_fleet(game::Game, layout::String)::Vector{Ship}
    chars = collect(replace(layout, "/" => ""))
    fleet = Ship[]
    for number in 1:5
        cells = findall(==(SHIP_SYMBOLS[number]), chars)
        length(cells) == SHIP_LENGTHS[number] || fail("$(SHIP_NAMES[number]) has $(length(cells)) cells")
        ship = Ship(cells[1], cells[2] - cells[1])
        if !(ship.stride in (1, 10)) || !in_bounds(ship, length(cells)) || cells != ship_cells(ship, length(cells))
            fail("$(SHIP_NAMES[number]) not straight")
        end
        any(cell -> game.reefs[cell], cells) && fail("$(SHIP_NAMES[number]) on reef")
        push!(fleet, ship)
    end
    if !game.touch
        for first in 1:4, second in first+1:5
            touching(fleet[first], SHIP_LENGTHS[first], fleet[second], SHIP_LENGTHS[second]) &&
                fail("$(SHIP_NAMES[first]) touches $(SHIP_NAMES[second])")
        end
    end
    fleet
end

struct View
    cells::Vector{CellView}
    excluded::BitVector
    remaining::BitVector
end

function view_of(game::Game, player::Int)::View
    opponent = game.players[3 - player]
    remaining = BitVector([!is_sunk(opponent, number) for number in 1:5])
    cells = fill(UNATTACKED, 100)
    for cell in 1:100
        number = opponent.board[cell]
        cells[cell] = game.reefs[cell] ? REEF : !opponent.attacked[cell] ? UNATTACKED :
            number == 0 ? MISS_VIEW : remaining[number] ? HIT_VIEW : SUNK_VIEW
    end
    excluded = falses(100)
    if !game.touch
        for cell in findall(==(SUNK_VIEW), cells), dr in -1:1, dc in -1:1
            dr == dc == 0 && continue
            other = neighbor(cell, dr, dc)
            other != 0 && (excluded[other] = true)
        end
    end
    View(cells, excluded, remaining)
end
candidate(view::View, cell::Int) = 1 <= cell <= 100 && view.cells[cell] == UNATTACKED && !view.excluded[cell]

function density(view::View)::Vector{Int}
    scores = zeros(Int, 100)
    for number in 1:5
        view.remaining[number] || continue
        for ship in PLACEMENTS[number]
            cells = ship_cells(ship, SHIP_LENGTHS[number])
            all(cell -> !view.excluded[cell] && view.cells[cell] in (UNATTACKED, HIT_VIEW), cells) || continue
            weight = 1 + 10 * count(cell -> view.cells[cell] == HIT_VIEW, cells)
            scores[cells] .+= weight
        end
    end
    scores
end

function best_cell(view::View, scores::Vector{Int})::Int
    cells = findall(==(UNATTACKED), view.cells)
    cells[argmax(scores[cells])]
end

struct Choice
    cell::Int
    info::Union{String,Int}
    next_random::Int64
end

function choose(game::Game, player::Int, strategy::Strategy)::Choice
    view = view_of(game, player)
    owner = game.players[player]
    if strategy == PROB
        scores = density(view)
        cell = best_cell(view, scores)
        return Choice(cell, scores[cell], owner.random)
    elseif strategy == RANDOM
        cells = [cell for cell in 1:100 if candidate(view, cell)]
        next = advance(owner.random)
        return Choice(cells[Int(next % length(cells)) + 1], length(cells), next)
    end
    for cell in findall(==(HIT_VIEW), view.cells), (dr, dc) in ((0, 1), (1, 0))
        front = neighbor(cell, dr, dc)
        (front == 0 || view.cells[front] != HIT_VIEW) && continue
        while front != 0 && view.cells[front] == HIT_VIEW
            front = neighbor(front, dr, dc)
        end
        for target in (front, neighbor(cell, -dr, -dc))
            candidate(view, target) && return Choice(target, "LINE", owner.random)
        end
    end
    for cell in Iterators.reverse(owner.candidates)
        candidate(view, cell) && return Choice(cell, "STACK", owner.random)
    end
    shortest = minimum(SHIP_LENGTHS[number] for number in 1:5 if view.remaining[number])
    cell = something(findfirst(cell -> candidate(view, cell) && (div(cell - 1, 10) + (cell - 1) % 10) % shortest == 0, 1:100))
    Choice(cell, "PARITY", owner.random)
end

struct Shot
    result::ShotResult
    ship::Union{Nothing,Int}
end
is_hit(shot::Shot) = shot.result == HIT || shot.result == SUNK
shot_text(shot::Shot) = shot.result == SUNK ? "SUNK $(SHIP_NAMES[something(shot.ship)])" : string(shot.result)

function record_shot!(statistics::Statistics, shot::Shot)
    statistics.shots += 1
    if is_hit(shot)
        statistics.hits += 1
        statistics.streak += 1
        statistics.longest = max(statistics.longest, statistics.streak)
    else
        statistics.streak = 0
    end
    shot.result == SUNK && (statistics.sinks += 1)
end

function shoot!(game::Game, player::Int, cell::Int)::Shot
    owner, opponent = game.players[player], game.players[3 - player]
    number = opponent.board[cell]
    result = ALREADY
    if !opponent.attacked[cell]
        opponent.attacked[cell] = true
        result = number == 0 ? MISS : is_sunk(opponent, number) ? SUNK : HIT
    end
    if result == HIT
        for (dr, dc) in ((0, -1), (1, 0), (0, 1), (-1, 0))
            other = neighbor(cell, dr, dc)
            other != 0 && push!(owner.candidates, other)
        end
    end
    shot = Shot(result, number == 0 ? nothing : number)
    record_shot!(owner.statistics, shot)
    shot
end

function finish_turn!(game::Game, player::Int, hit::Bool, mode::OutputMode)
    statistics = game.players[player].statistics
    statistics.turns += 1
    if defeated(game.players[3 - player])
        game.phase = OVER
        game.winner = player
        statistics.wins += 1
        mode == NORMAL && emit("WINNER", player)
    else
        game.current = game.chain && hit ? player : 3 - player
    end
end

function shooting_turn!(game::Game, player::Int, strategy::Union{Nothing,Strategy}, cells::Vector{Int}=Int[], mode::OutputMode=NORMAL)
    hit = false
    for index in 1:allowance(game, player)
        if strategy === nothing
            cell = cells[index]
        else
            choice = choose(game, player, strategy)
            cell = choice.cell
            game.players[player].random = choice.next_random
        end
        shot = shoot!(game, player, cell)
        hit |= is_hit(shot)
        mode == NORMAL && emit("SHOT", player, coordinate(cell), shot_text(shot))
        if mode == SINKS_ONLY && shot.result == SUNK
            emit("SINK", player, SHIP_NAMES[something(shot.ship)], game.players[player].statistics.shots)
        end
        defeated(game.players[3 - player]) && break
    end
    finish_turn!(game, player, hit, mode)
end

function automatic!(game::Game)
    while game.phase == BATTLE
        player = game.current
        strategy = game.players[player].controller
        strategy === nothing && break
        shooting_turn!(game, player, strategy)
    end
end

function torpedo_turn!(game::Game, player::Int, row::Int, side::String)
    owner, opponent = game.players[player], game.players[3 - player]
    owner.torpedo_used = true
    columns = side == "W" ? (1:10) : (10:-1:1)
    result = "MISS"
    hit = false
    stopped_ship = false
    for column in columns
        cell = (row - 1) * 10 + column
        if game.reefs[cell]
            result = "REEF $(coordinate(cell))"
            break
        elseif opponent.board[cell] != 0
            shot = shoot!(game, player, cell)
            result = "$(shot_text(shot)) $(coordinate(cell))"
            hit = is_hit(shot)
            stopped_ship = true
            break
        end
        opponent.attacked[cell] = true
    end
    stopped_ship || record_shot!(owner.statistics, Shot(MISS, nothing))
    emit("TORPEDO", player, 'A' + row - 1, side, result)
    finish_turn!(game, player, hit, NORMAL)
end

function sonar_turn!(game::Game, player::Int, center::Int)
    game.players[player].sonar_used = true
    opponent = game.players[3 - player]
    detected = count(cell -> adjacent(cell, center) && opponent.board[cell] != 0 && !opponent.attacked[cell], 1:100)
    emit("SONAR", player, coordinate(center), detected)
    finish_turn!(game, player, false, NORMAL)
end

function board_output(game::Game, player::Int, radar::Bool)
    view = view_of(game, player)
    owner = game.players[player]
    chars = fill('.', 100)
    symbols = ('~', '.', 'o', 'x', '#')
    for cell in 1:100
        number = owner.board[cell]
        chars[cell] = if radar
            symbols[Int(view.cells[cell]) + 1]
        elseif game.reefs[cell]
            '~'
        elseif number != 0
            owner.attacked[cell] ? lowercase(SHIP_SYMBOLS[number]) : SHIP_SYMBOLS[number]
        else
            owner.attacked[cell] ? 'o' : '.'
        end
    end
    emit(radar ? "RADAR" : "BOARD", player)
    emit("  1 2 3 4 5 6 7 8 9 10")
    for row in 1:10
        emit('A' + row - 1, chars[(row - 1) * 10 + 1:row * 10]...)
    end
end

function export_fleet(player::Player)::String
    chars = [number == 0 ? '.' : SHIP_SYMBOLS[number] for number in player.board]
    join((join(chars[(row - 1) * 10 + 1:row * 10]) for row in 1:10), "/")
end

function fleet_output(game::Game, player::Int)
    owner = game.players[player]
    emit("FLEET", player, "afloat", afloat_count(owner))
    for number in 1:5
        ship = owner.fleet[number]
        if ship === nothing
            emit(SHIP_NAMES[number], "unplaced")
        else
            emit(SHIP_NAMES[number], ship_range(ship, SHIP_LENGTHS[number]), "$(attacked_count(owner, number))/$(SHIP_LENGTHS[number])",
                 is_sunk(owner, number) ? "SUNK" : "AFLOAT")
        end
    end
end

function density_output(game::Game, player::Int)
    view = view_of(game, player)
    scores = density(view)
    emit("DENSITY", player)
    emit(" " * join(lpad(string(column), 5) for column in 1:10))
    for row in 1:10
        values = [view.cells[cell] == UNATTACKED ? string(scores[cell]) : view.cells[cell] == REEF ? "~" : "-"
                  for cell in (row - 1) * 10 + 1:row * 10]
        emit(string('A' + row - 1) * join(lpad(value, 5) for value in values))
    end
    cell = best_cell(view, scores)
    emit("BEST", coordinate(cell), scores[cell])
end

function status_output(game::Game)
    prefix = "STATUS $(game.phase) salvo $(switch_name(game.salvo)) chain $(switch_name(game.chain)) touch $(switch_name(game.touch)) reefs $(count(game.reefs))"
    first, second = game.players
    if game.phase == SETUP
        emit(prefix, "placed", placed_count(first), placed_count(second))
    elseif game.phase == BATTLE
        emit(prefix, "turn", game.current, "shots", allowance(game, game.current), "afloat", afloat_count(first), afloat_count(second))
    else
        emit(prefix, "winner", something(game.winner), "afloat", afloat_count(first), afloat_count(second))
    end
end

function statistics_output(game::Game)
    for player in 1:2
        statistics = game.players[player].statistics
        accuracy = statistics.shots == 0 ? "-" : "$(div(statistics.hits * 100, statistics.shots))%"
        emit("STATS", player, "shots", statistics.shots, "hits", statistics.hits, "sunk", statistics.sinks,
             "turns", statistics.turns, "streak", statistics.longest, "accuracy", accuracy, "wins", statistics.wins)
    end
end

function play_match(current::Game, first_seed::Int64, second_seed::Int64, strategies::NTuple{2,Strategy}, mode::OutputMode=QUIET)::Game
    game = Game()
    game.salvo, game.chain, game.touch = current.salvo, current.chain, current.touch
    game.reefs = copy(current.reefs)
    auto_place!(game, 1, first_seed)
    auto_place!(game, 2, second_seed)
    game.phase = BATTLE
    while game.phase == BATTLE
        player = game.current
        shooting_turn!(game, player, strategies[player], Int[], mode)
    end
    game
end

function series_output(game::Game, count::Int, seed::Int64, strategies::NTuple{2,Strategy})
    wins, shots = zeros(Int64, 2), zeros(Int64, 2)
    fastest = Union{Nothing,Int64}[nothing, nothing]
    generator = seed
    for _ in 1:count
        first_seed = advance(generator)
        generator = advance(first_seed)
        trial = play_match(game, first_seed, generator, strategies)
        winner = something(trial.winner)
        wins[winner] += 1
        shots .+= [player.statistics.shots for player in trial.players]
        winning_shots = trial.players[winner].statistics.shots
        best = fastest[winner]
        fastest[winner] = best === nothing ? winning_shots : min(best, winning_shots)
    end
    emit("SERIES", count, "wins", wins..., "shots", shots..., "fastest", something(fastest[1], "-"), something(fastest[2], "-"))
end

function tourney_output(game::Game, count::Int, seed::Int64)
    wins, shots = zeros(Int64, 3), zeros(Int64, 3)
    generator = seed
    for first in 1:3, second in 1:3
        first == second && continue
        for _ in 1:count
            first_seed = advance(generator)
            generator = advance(first_seed)
            trial = play_match(game, first_seed, generator, (STRATEGIES[first], STRATEGIES[second]))
            wins[something(trial.winner) == 1 ? first : second] += 1
            shots[first] += trial.players[1].statistics.shots
            shots[second] += trial.players[2].statistics.shots
        end
    end
    ranking = sort(collect(1:3); by=number -> (-wins[number], shots[number], string(STRATEGIES[number])))
    emit("TOURNEY", count)
    for (rank, number) in enumerate(ranking)
        emit(rank, STRATEGIES[number], "wins", wins[number], "shots", shots[number])
    end
end

function execute!(game::Game, tokens::Vector{String})::Game
    command = tokens[1]
    if command == "NEW"
        replacement = Game()
        for player in 1:2
            replacement.players[player].statistics.wins = game.players[player].statistics.wins
        end
        emit("NEW")
        return replacement
    end
    player = command in PLAYER_COMMANDS ? parse(Int, tokens[2]) : 0
    command in SETUP_COMMANDS && game.phase != SETUP && fail("setup closed")
    if command in TURN_COMMANDS
        game.phase == OVER && fail("game over")
        game.phase == SETUP && any(owner -> placed_count(owner) < 5, game.players) && fail("fleets not ready")
        player == game.current || fail("not your turn")
        cells = Int[]
        if command == "FIRE"
            expected = allowance(game, player)
            length(tokens) - 2 == expected || fail("expected $expected shots")
            cells = parse_cell.(tokens[3:end])
            for cell in cells
                game.reefs[cell] && fail("reef at $(coordinate(cell))")
            end
        elseif command == "TORPEDO"
            game.players[player].torpedo_used && fail("torpedo used")
        elseif command == "SONAR"
            game.players[player].sonar_used && fail("sonar used")
        end
        game.phase = BATTLE
        if command == "FIRE"
            shooting_turn!(game, player, nothing, cells)
        elseif command == "AI"
            shooting_turn!(game, player, STRATEGY_BY_NAME[tokens[3]])
        elseif command == "TORPEDO"
            torpedo_turn!(game, player, Int(tokens[3][1] - 'A') + 1, tokens[4])
        else
            sonar_turn!(game, player, parse_cell(tokens[3]))
        end
        automatic!(game)
        return game
    end
    if command == "PLACE" || command == "REMOVE"
        number = ship_number(tokens[3])
        owner = game.players[player]
        if command == "PLACE"
            owner.fleet[number] === nothing || fail("$(SHIP_NAMES[number]) already placed")
            ship = Ship(parse_cell(tokens[4]), tokens[5] == "H" ? 1 : 10)
            problem = placement_problem(game, owner, number, ship)
            problem === nothing || fail(problem)
            put_ship!(owner, number, ship)
            emit("PLACED", player, SHIP_NAMES[number], ship_range(ship, SHIP_LENGTHS[number]))
        else
            ship = owner.fleet[number]
            ship === nothing && fail("$(SHIP_NAMES[number]) not placed")
            owner.board[ship_cells(ship, SHIP_LENGTHS[number])] .= 0
            owner.fleet[number] = nothing
            emit("REMOVED", player, SHIP_NAMES[number])
        end
    elseif command == "AUTOPLACE"
        attempts = auto_place!(game, player, parse(Int64, tokens[3]))
        emit("AUTOPLACE", player, "attempts", attempts)
        placement_output(game, player)
    elseif command == "LAYOUT"
        fleet = layout_fleet(game, tokens[3])
        clear_fleet!(game.players[player])
        for number in 1:5
            put_ship!(game.players[player], number, fleet[number])
        end
        emit("LAYOUT", player)
        placement_output(game, player)
    elseif command == "REEF"
        cell = parse_cell(tokens[2])
        game.reefs[cell] && fail("reef exists at $(coordinate(cell))")
        for owner in 1:2
            number = game.players[owner].board[cell]
            number != 0 && fail("$(coordinate(cell)) occupied by $owner $(SHIP_NAMES[number])")
        end
        game.reefs[cell] = true
        emit("REEF", coordinate(cell))
    elseif command in ("SALVO", "CHAIN", "TOUCH")
        enabled = tokens[2] == "ON"
        if command == "SALVO"
            game.salvo = enabled
        elseif command == "CHAIN"
            game.chain = enabled
        else
            game.touch = enabled
        end
        emit(command, tokens[2])
    elseif command == "CONTROL"
        game.players[player].controller = tokens[3] == "HUMAN" ? nothing : STRATEGY_BY_NAME[tokens[3]]
        emit("CONTROL", player, tokens[3])
    elseif command == "SEED"
        game.players[player].random = parse(Int64, tokens[3])
        emit("SEED", player, game.players[player].random)
    elseif command == "RESIGN"
        game.phase == BATTLE || fail("not in battle")
        game.phase = OVER
        game.winner = 3 - player
        game.players[3 - player].statistics.wins += 1
        emit("RESIGN", player)
        emit("WINNER", 3 - player)
    elseif command == "HINT"
        game.phase == OVER && fail("game over")
        choice = choose(game, player, STRATEGY_BY_NAME[tokens[3]])
        emit("HINT", player, tokens[3], coordinate(choice.cell), choice.info)
    elseif command == "DENSITY"
        game.phase == OVER && fail("game over")
        density_output(game, player)
    elseif command == "SHOW" || command == "RADAR"
        board_output(game, player, command == "RADAR")
    elseif command == "EXPORT"
        emit("EXPORT", player, export_fleet(game.players[player]))
    elseif command == "FLEET"
        fleet_output(game, player)
    elseif command == "STATUS"
        status_output(game)
    elseif command == "STATS"
        statistics_output(game)
    elseif command == "MATCH"
        strategies = (STRATEGY_BY_NAME[tokens[4]], STRATEGY_BY_NAME[tokens[5]])
        emit("MATCH", 1, strategies[1], 2, strategies[2])
        trial = play_match(game, parse(Int64, tokens[2]), parse(Int64, tokens[3]), strategies, SINKS_ONLY)
        first, second = trial.players
        emit("RESULT winner", something(trial.winner), "shots", first.statistics.shots, second.statistics.shots,
             "hits", first.statistics.hits, second.statistics.hits)
    elseif command == "SERIES"
        series_output(game, parse(Int, tokens[2]), parse(Int64, tokens[3]), (STRATEGY_BY_NAME[tokens[4]], STRATEGY_BY_NAME[tokens[5]]))
    elseif command == "TOURNEY"
        tourney_output(game, parse(Int, tokens[2]), parse(Int64, tokens[3]))
    end
    game
end

function main()
    command_count = parse(Int, readline())
    game = Game()
    for _ in 1:command_count
        tokens = String.(split(readline(), ' '))
        try
            game = execute!(game, tokens)
        catch error
            error isa CommandError || rethrow()
            emit("ERROR", error.reason)
        end
    end
end

main()
