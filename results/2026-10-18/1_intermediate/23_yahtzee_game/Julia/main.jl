@enum Category::Int8 ONES=1 TWOS THREES FOURS FIVES SIXES THREEKIND FOURKIND FULLHOUSE SMALL LARGE YAHTZEE CHANCE
@enum BotStrategy::UInt8 KIND STRAIGHT HIGH UPPER
@enum JokerRule::UInt8 FORCED FREE OFF

const CATEGORY_NAMES = string.(instances(Category))
const STRATEGIES = Dict(string(strategy) => strategy for strategy in instances(BotStrategy))
const JOKER_RULES = Dict(string(rule) => rule for rule in instances(JokerRule))
const COMMANDS = Set(split("RULE GAME BOT LOAD ROLL HOLD KEEP SCORE WHATIF UNDO REDO SUGGEST ODDS ADVISE AUTO STATUS CARD BONUS STATS LOG FACES STANDINGS END RECORDS SIM"))
const Dice = NTuple{5,Int}
const Holds = NTuple{5,Bool}
const Counts = NTuple{6,Int}
const NO_HOLDS = ntuple(_ -> false, 5)
const PATTERNS = [ntuple(index -> mask & (1 << (5 - index)) != 0, 5) for mask in 0:31]

struct CommandError <: Exception
    reason::String
end
fail(reason::AbstractString) = throw(CommandError(String(reason)))
emit(parts...) = println(join(string.(parts), " "))

function integer_word(text::String, minimum::Int64, maximum::Int64)::Int64
    occursin(r"^-?(0|[1-9][0-9]*)$", text) && text != "-0" || fail("bad value $text")
    value = parse(Int64, text)
    minimum <= value <= maximum || fail("bad value $text")
    value
end

function player_name(text::String)::String
    occursin(r"^[A-Z]{1,8}$", text) || fail("bad name $text")
    text
end

function strategy_word(text::String)::BotStrategy
    haskey(STRATEGIES, text) || fail("bad strategy $text")
    STRATEGIES[text]
end

function category_word(text::String)::Category
    index = findfirst(==(text), CATEGORY_NAMES)
    index === nothing && fail("bad category $text")
    Category(index)
end

function hold_pattern(text::String)::Holds
    occursin(r"^[01]{5}$", text) || fail("bad pattern $text")
    ntuple(index -> text[index] == '1', 5)
end

face_words(tokens::Vector{String}) = Int[integer_word(token, 1, 6) for token in tokens]
faces_text(dice) = dice === nothing || isempty(dice) ? "-" : join(dice, " ")
pattern_text(holds::Holds) = join(mark ? "1" : "0" for mark in holds)
held_faces(dice::Dice, holds::Holds) = [dice[index] for index in 1:5 if holds[index]]
face_counts(dice)::Counts = ntuple(face -> count(==(face), dice), 6)
most_frequent(counts::Counts)::Int = findlast(==(maximum(counts)), counts)

function fraction(numerator::Int64, denominator::Int64)::String
    divisor = gcd(numerator, denominator)
    top, bottom = div(numerator, divisor), div(denominator, divisor)
    bottom == 1 ? string(top) : "$top/$bottom"
end

function average(total::Int64, sample_count::Int)::String
    value = sample_count == 0 ? Int64(0) : div(100 * total, sample_count)
    string(div(value, 100), ".", lpad(string(value % 100), 2, '0'))
end

struct Rules
    rolls::Int
    joker::JokerRule
end
Rules() = Rules(3, FORCED)

mutable struct Player
    name::String
    strategy::BotStrategy
    boxes::Vector{Union{Nothing,Int64}}
    yahtzee_bonus::Int64
end
Player(name::String, strategy::BotStrategy=KIND) = Player(name, strategy, Union{Nothing,Int64}[nothing for _ in 1:13], 0)

upper_subtotal(player::Player)::Int64 = sum(something(score, Int64(0)) for score in view(player.boxes, 1:6))
upper_bonus(player::Player)::Int64 = upper_subtotal(player) >= 63 ? 35 : 0
player_total(player::Player)::Int64 = sum(something(score, Int64(0)) for score in player.boxes) + upper_bonus(player) + player.yahtzee_bonus
player_round(player::Player)::Int = count(score -> score !== nothing, player.boxes) + 1

function normal_score(category::Category, counts::Counts)::Int64
    index = Int(category)
    index <= 6 && return index * counts[index]
    total = sum(face * counts[face] for face in 1:6)
    largest = maximum(counts)
    if category == THREEKIND
        return largest >= 3 ? total : 0
    elseif category == FOURKIND
        return largest >= 4 ? total : 0
    elseif category == FULLHOUSE
        return 3 in counts && 2 in counts ? 25 : 0
    elseif category == SMALL || category == LARGE
        run_length = category == SMALL ? 4 : 5
        has_run = any(start -> all(face -> counts[face] > 0, start:(start + run_length - 1)), 1:(7 - run_length))
        return has_run ? (category == SMALL ? 30 : 40) : 0
    elseif category == YAHTZEE
        return largest == 5 ? 50 : 0
    end
    total
end

struct CandidateScores
    joker::Bool
    allowed::BitVector
    points::Vector{Int64}
    best::Category
    requirement::String
end

function candidates(player::Player, counts::Counts, joker_rule::JokerRule)::CandidateScores
    allowed = BitVector(isnothing.(player.boxes))
    joker = joker_rule != OFF && 5 in counts && player.boxes[Int(YAHTZEE)] !== nothing
    requirement = ""
    if joker && joker_rule == FORCED
        face = most_frequent(counts)
        if player.boxes[face] === nothing
            fill!(allowed, false)
            allowed[face] = true
            requirement = CATEGORY_NAMES[face]
        elseif any(view(allowed, 7:13))
            allowed[1:6] .= false
            requirement = "lower box"
        end
    end
    points = zeros(Int64, 13)
    best_category = ONES
    best_points = Int64(-1)
    for category in instances(Category)
        index = Int(category)
        allowed[index] || continue
        score = normal_score(category, counts)
        if joker
            category == FULLHOUSE && (score = 25)
            category == SMALL && (score = 30)
            category == LARGE && (score = 40)
        end
        points[index] = score
        if score > best_points
            best_points = score
            best_category = category
        end
    end
    CandidateScores(joker, allowed, points, best_category, requirement)
end

struct Turn
    player::Int
    rolls::Int
    dice::Union{Nothing,Dice}
    holds::Holds
end
Turn(player::Int) = Turn(player, 0, nothing, NO_HOLDS)

struct ScoreEntry
    turn::Turn
    category::Category
    points::Int64
    yahtzee_bonus::Int64
    joker::Bool
end

struct RedoEntry
    resume::Union{Nothing,Turn}
    score::ScoreEntry
end

mutable struct Game
    state::Int64
    players::Vector{Player}
    rules::Rules
    turn::Union{Nothing,Turn}
    loaded::Vector{Int}
    loaded_head::Int
    face_totals::Vector{Int64}
    entries::Vector{ScoreEntry}
    redo::Vector{RedoEntry}
    silent::Bool
end
Game(seed::Int64, players::Vector{Player}, rules::Rules; silent::Bool=false) =
    Game(seed, players, rules, Turn(1), Int[], 1, zeros(Int64, 6), ScoreEntry[], RedoEntry[], silent)

game_emit(game::Game, parts...) = game.silent ? nothing : emit(parts...)
turn_check(game::Game) = game.turn === nothing ? fail("game over") : nothing
function rolled_check(game::Game)
    turn_check(game)
    game.turn.rolls == 0 && fail("not rolled")
    nothing
end
function rolls_left_check(game::Game)
    rolled_check(game)
    game.turn.rolls == game.rules.rolls && fail("no rolls left")
    nothing
end

function ranking(game::Game)::Vector{Int}
    sort!(collect(eachindex(game.players)); by=seat -> (-player_total(game.players[seat]), seat))
end

function turn_text(game::Game)::String
    game.turn === nothing && return "game over"
    player = game.players[game.turn.player]
    "turn $(player_round(player)) $(player.name)"
end

function roll_face!(game::Game)::Int
    if game.loaded_head <= length(game.loaded)
        face = game.loaded[game.loaded_head]
        game.loaded_head += 1
    else
        game.state = 48271 * game.state % 2147483647
        face = Int(game.state % 6) + 1
    end
    game.face_totals[face] += 1
    face
end

function roll_dice!(game::Game)
    current = game.turn::Turn
    dice = current.dice === nothing ? zeros(Int, 5) : collect(current.dice)
    for die in 1:5
        if current.rolls == 0 || !current.holds[die]
            dice[die] = roll_face!(game)
        end
    end
    game.turn = Turn(current.player, current.rolls + 1, Tuple(dice), current.holds)
    empty!(game.redo)
    game_emit(game, game.players[current.player].name, "roll", "$(game.turn.rolls):", faces_text(game.turn.dice))
end

function set_holds!(game::Game, holds::Holds)
    current = game.turn::Turn
    game.turn = Turn(current.player, current.rolls, current.dice, holds)
    empty!(game.redo)
    game_emit(game, game.players[current.player].name, "holds", pattern_text(holds) * ":", faces_text(held_faces(current.dice, holds)))
end

function score_details(game::Game, category::Category)::ScoreEntry
    current = game.turn::Turn
    player = game.players[current.player]
    counts = face_counts(current.dice)
    options = candidates(player, counts, game.rules.joker)
    bonus = 5 in counts && player.boxes[Int(YAHTZEE)] == 50 ? 100 : 0
    ScoreEntry(current, category, options.points[Int(category)], bonus, options.joker)
end

function score_check(game::Game, category::Category)
    rolled_check(game)
    player = game.players[game.turn.player]
    player.boxes[Int(category)] !== nothing && fail("$category already used")
    options = candidates(player, face_counts(game.turn.dice), game.rules.joker)
    options.allowed[Int(category)] || fail("joker requires $(options.requirement)")
    nothing
end

function score_text(game::Game, entry::ScoreEntry; hypothetical::Bool=false)::String
    player = game.players[entry.turn.player]
    upper = upper_subtotal(player)
    after = upper + (Int(entry.category) <= 6 ? entry.points : 0)
    added_upper = upper < 63 <= after ? 35 : 0
    verb = hypothetical ? "would score" : "scores"
    text = "$(player.name) $verb $(entry.points) in $(entry.category)"
    entry.joker && (text *= " joker")
    entry.yahtzee_bonus > 0 && (text *= " ybonus 100")
    added_upper > 0 && (text *= " ubonus 35")
    text * " total $(player_total(player) + entry.points + entry.yahtzee_bonus + added_upper)"
end

function enter_score!(game::Game, category::Category)
    entry = score_details(game, category)
    game_emit(game, score_text(game, entry))
    player = game.players[entry.turn.player]
    player.boxes[Int(category)] = entry.points
    player.yahtzee_bonus += entry.yahtzee_bonus
    push!(game.entries, entry)
    empty!(game.redo)
    game.turn = length(game.entries) == 13 * length(game.players) ? nothing : Turn(mod1(entry.turn.player + 1, length(game.players)))
    game_emit(game, turn_text(game))
end

function bot_holds(strategy::BotStrategy, dice::Dice)::Holds
    strategy == HIGH && return ntuple(index -> dice[index] >= 5, 5)
    counts = face_counts(dice)
    if strategy == STRAIGHT
        best_start, best_length = 0, 0
        for start in 1:6
            run_length = 0
            while start + run_length <= 6 && counts[start + run_length] > 0
                run_length += 1
            end
            if run_length >= best_length
                best_start, best_length = start, run_length
            end
        end
        if best_length >= 3
            marks = falses(5)
            for face in best_start:(best_start + best_length - 1)
                marks[findfirst(==(face), dice)] = true
            end
            return Tuple(marks)
        end
    end
    target = most_frequent(counts)
    ntuple(index -> dice[index] == target, 5)
end

function bot_turn!(game::Game)
    game.turn.rolls == 0 && roll_dice!(game)
    strategy = game.players[game.turn.player].strategy
    while game.turn.rolls < game.rules.rolls
        holds = bot_holds(strategy, game.turn.dice)
        all(holds) && break
        set_holds!(game, holds)
        roll_dice!(game)
    end
    counts = face_counts(game.turn.dice)
    options = candidates(game.players[game.turn.player], counts, game.rules.joker)
    face = most_frequent(counts)
    category = strategy == UPPER && counts[face] >= 3 && options.allowed[face] ? Category(face) : options.best
    enter_score!(game, category)
end

struct Outcome
    counts::Counts
    weight::Int64
end

function distribution(total::Int)::Vector{Outcome}
    outcomes = Outcome[]
    counts = zeros(Int, 6)
    function visit(remaining::Int, face::Int)
        if face == 6
            counts[face] = remaining
            weight = div(factorial(total), prod(factorial(count) for count in counts))
            push!(outcomes, Outcome(Tuple(counts), weight))
            return
        end
        for frequency in 0:remaining
            counts[face] = frequency
            visit(remaining - frequency, face + 1)
        end
    end
    visit(total, 1)
    outcomes
end

combined(held::Counts, rolled::Counts)::Counts = ntuple(face -> held[face] + rolled[face], 6)

struct RollTables
    outcomes::Vector{Vector{Outcome}}
    full::Vector{Counts}
    held::Vector{Counts}
    held_index::Dict{Counts,Int}
    next_states::Vector{Vector{Int}}
    weights::Vector{Vector{Int64}}
    subsets::Vector{Vector{Int}}
end

function RollTables()
    outcomes = distribution.(0:5)
    full = [outcome.counts for outcome in outcomes[6]]
    held = [outcome.counts for group in outcomes for outcome in group]
    full_index = Dict(state => index for (index, state) in enumerate(full))
    held_index = Dict(state => index for (index, state) in enumerate(held))
    next_states, weights = Vector{Int}[], Vector{Int64}[]
    for state in held
        kept = sum(state)
        rolled = outcomes[6 - kept]
        push!(next_states, [full_index[combined(state, outcome.counts)] for outcome in rolled])
        push!(weights, Int64[outcome.weight * 6^kept for outcome in rolled])
    end
    subsets = [findall(state -> all(state[face] <= dice[face] for face in 1:6), held) for dice in full]
    RollTables(outcomes, full, held, held_index, next_states, weights, subsets)
end

function print_odds(game::Game, tables::RollTables, holds::Holds)
    current = game.turn::Turn
    player = game.players[current.player]
    held = face_counts(held_faces(current.dice, holds))
    rolled = 5 - sum(held)
    denominator = Int64(6)^rolled
    totals, chances = zeros(Int64, 13), zeros(Int64, 13)
    best_total = Int64(0)
    for outcome in tables.outcomes[rolled + 1]
        options = candidates(player, combined(held, outcome.counts), game.rules.joker)
        totals .+= outcome.weight .* options.points
        chances .+= outcome.weight .* (options.points .> 0)
        best_total += outcome.weight * options.points[Int(options.best)]
    end
    emit("odds", pattern_text(holds), "outcomes", denominator)
    for category in instances(Category)
        index = Int(category)
        if player.boxes[index] === nothing
            emit(category, "expect", fraction(totals[index], denominator), "chance", fraction(chances[index], denominator))
        end
    end
    emit("best expect", fraction(best_total, denominator))
end

function print_advice(game::Game, tables::RollTables)
    current = game.turn::Turn
    player = game.players[current.player]
    values = Int64[]
    for counts in tables.full
        options = candidates(player, counts, game.rules.joker)
        push!(values, options.points[Int(options.best)])
    end
    remaining = game.rules.rolls - current.rolls
    expected = zeros(Int64, length(tables.held))
    for depth in 1:remaining
        for index in eachindex(tables.held)
            expected[index] = sum(weight * values[state] for (weight, state) in zip(tables.weights[index], tables.next_states[index]))
        end
        if depth < remaining
            values = Int64[maximum(expected[subset]) for subset in tables.subsets]
        end
    end
    choices = Int64[expected[tables.held_index[face_counts(held_faces(current.dice, holds))]] for holds in PATTERNS]
    chosen = argmax(choices)
    holds = PATTERNS[chosen]
    emit("advise", pattern_text(holds) * ":", faces_text(held_faces(current.dice, holds)),
         "expect", fraction(choices[chosen], Int64(7776)^remaining))
end

function card_row(heading::String, players::Vector{Player}, cells::Vector{String})
    text = rpad(heading, 9)
    for (player, cell) in zip(players, cells)
        text *= " " * lpad(cell, max(4, length(player.name)))
    end
    emit(text)
end

function print_card(game::Game)
    card_row("CATEGORY", game.players, [player.name for player in game.players])
    for category in instances(Category)
        index = Int(category)
        cells = [player.boxes[index] === nothing ? "-" : string(player.boxes[index]) for player in game.players]
        card_row(string(category), game.players, cells)
    end
    card_row("UPPER", game.players, [string(upper_subtotal(player)) for player in game.players])
    card_row("BONUS", game.players, [string(upper_bonus(player)) for player in game.players])
    card_row("YBONUS", game.players, [string(player.yahtzee_bonus) for player in game.players])
    card_row("TOTAL", game.players, [string(player_total(player)) for player in game.players])
end

function print_stats(game::Game)
    for seat in eachindex(game.players)
        entries = filter(entry -> entry.turn.player == seat, game.entries)
        turns = length(entries)
        rolls = sum((entry.turn.rolls for entry in entries); init=0)
        zeros = count(entry -> entry.points == 0, entries)
        yahtzees = count(entry -> 5 in face_counts(entry.turn.dice), entries)
        total = sum((entry.points for entry in entries); init=Int64(0))
        emit("stats", game.players[seat].name, "turns", turns, "rolls", rolls, "zeros", zeros,
             "yahtzees", yahtzees, "average", average(total, turns))
    end
end

mutable struct Record
    games::Int
    wins::Int
    best::Int64
    total::Int64
end
Record() = Record(0, 0, 0, 0)

function record_game!(records::Dict{String,Record}, game::Game)
    winner = ranking(game)[1]
    for seat in eachindex(game.players)
        player = game.players[seat]
        record = get!(Record, records, player.name)
        record.games += 1
        record.wins += seat == winner
        record.best = max(record.best, player_total(player))
        record.total += player_total(player)
    end
end

function print_records(records::Dict{String,Record})
    isempty(records) && emit("no records")
    names = sort!(collect(keys(records)); by=name -> (-records[name].wins, -records[name].best, name))
    for name in names
        record = records[name]
        emit("record", name, "games", record.games, "wins", record.wins, "best", record.best,
             "average", average(record.total, record.games))
    end
end

mutable struct SimulationTotal
    wins::Int
    total::Int64
    best::Int64
    bonus::Int
    yahtzee::Int
end
SimulationTotal() = SimulationTotal(0, 0, 0, 0, 0)

function simulate(seed::Int64, sample_count::Int, strategies::Vector{BotStrategy}, rules::Rules)
    totals = [SimulationTotal() for _ in strategies]
    names = ["A", "B", "C", "D", "E", "F"]
    generator = seed
    for _ in 1:sample_count
        players = [Player(names[seat], strategies[seat]) for seat in eachindex(strategies)]
        game = Game(generator, players, rules; silent=true)
        while game.turn !== nothing
            bot_turn!(game)
        end
        generator = game.state
        totals[ranking(game)[1]].wins += 1
        for seat in eachindex(strategies)
            player = game.players[seat]
            totals[seat].total += player_total(player)
            totals[seat].best = max(totals[seat].best, player_total(player))
            totals[seat].bonus += upper_bonus(player) == 35
            totals[seat].yahtzee += player.boxes[Int(YAHTZEE)] == 50
        end
    end
    emit("sim seed", seed, "games", sample_count, "players", length(strategies))
    for seat in eachindex(strategies)
        result = totals[seat]
        emit("seat", seat, strategies[seat], "wins", result.wins, "average", average(result.total, sample_count),
             "best", result.best, "bonus", result.bonus, "yahtzee", result.yahtzee)
    end
end

mutable struct Program
    rules::Rules
    game::Union{Nothing,Game}
    records::Dict{String,Record}
    tables::RollTables
end
Program() = Program(Rules(), nothing, Dict{String,Record}(), RollTables())

function require_game(program::Program)::Game
    program.game === nothing && fail("no game")
    program.game
end

function game_command!(program::Program, tokens::Vector{String})
    op = tokens[1]
    if op == "BOT"
        name = player_name(tokens[2])
        strategy = strategy_word(tokens[3])
    elseif op == "LOAD" || op == "KEEP"
        faces = face_words(tokens[2:end])
    elseif op == "HOLD" || op == "ODDS"
        holds = hold_pattern(tokens[2])
    elseif op == "SCORE" || op == "WHATIF"
        category = category_word(tokens[2])
    elseif op == "AUTO"
        turn_count = Int(integer_word(tokens[2], 1, 100))
    end
    game = require_game(program)
    if op == "BOT"
        seat = findfirst(player -> player.name == name, game.players)
        seat === nothing && fail("no player $name")
        game.players[seat].strategy = strategy
        emit("bot", name, strategy)
    elseif op == "LOAD"
        append!(game.loaded, faces)
        emit("loaded", length(game.loaded) - game.loaded_head + 1)
    elseif op == "ROLL"
        turn_check(game)
        game.turn.rolls == game.rules.rolls && fail("no rolls left")
        all(game.turn.holds) && fail("all dice held")
        roll_dice!(game)
    elseif op == "HOLD"
        rolls_left_check(game)
        set_holds!(game, holds)
    elseif op == "KEEP"
        rolls_left_check(game)
        marks = falses(5)
        for face in faces
            die = findfirst(index -> !marks[index] && game.turn.dice[index] == face, 1:5)
            die === nothing && fail("not showing $face")
            marks[die] = true
        end
        set_holds!(game, Tuple(marks))
    elseif op == "SCORE" || op == "WHATIF"
        score_check(game, category)
        if op == "WHATIF"
            emit(score_text(game, score_details(game, category); hypothetical=true))
        else
            enter_score!(game, category)
        end
    elseif op == "UNDO"
        isempty(game.entries) && fail("nothing to undo")
        entry = pop!(game.entries)
        push!(game.redo, RedoEntry(game.turn, entry))
        player = game.players[entry.turn.player]
        player.boxes[Int(entry.category)] = nothing
        player.yahtzee_bonus -= entry.yahtzee_bonus
        game.turn = entry.turn
        emit("undo", player.name, entry.category, entry.points)
    elseif op == "REDO"
        isempty(game.redo) && fail("nothing to redo")
        saved = pop!(game.redo)
        entry = saved.score
        player = game.players[entry.turn.player]
        player.boxes[Int(entry.category)] = entry.points
        player.yahtzee_bonus += entry.yahtzee_bonus
        push!(game.entries, entry)
        game.turn = saved.resume
        emit("redo", player.name, entry.category, entry.points)
    elseif op == "SUGGEST"
        rolled_check(game)
        player = game.players[game.turn.player]
        options = candidates(player, face_counts(game.turn.dice), game.rules.joker)
        parts = String["suggest"]
        for box in instances(Category)
            if player.boxes[Int(box)] === nothing
                append!(parts, [string(box), string(options.points[Int(box)])])
            end
        end
        emit(join(parts, " "), "best", options.best, options.points[Int(options.best)])
    elseif op == "ODDS"
        rolls_left_check(game)
        print_odds(game, program.tables, holds)
    elseif op == "ADVISE"
        rolls_left_check(game)
        print_advice(game, program.tables)
    elseif op == "AUTO"
        turn_check(game)
        empty!(game.redo)
        for _ in 1:turn_count
            game.turn === nothing && break
            bot_turn!(game)
        end
    elseif op == "STATUS"
        if game.turn === nothing
            emit("status game over")
        else
            current = game.turn
            player = game.players[current.player]
            emit("status round", player_round(player), "player", player.name, "rolls", current.rolls,
                 "dice", faces_text(current.dice), "holds", pattern_text(current.holds))
        end
    elseif op == "CARD"
        print_card(game)
    elseif op == "BONUS"
        for player in game.players
            upper = upper_subtotal(player)
            maximum_upper = upper + sum((5 * face for face in 1:6 if player.boxes[face] === nothing); init=Int64(0))
            status = upper >= 63 ? "made" : maximum_upper < 63 ? "lost" : "open"
            emit("bonus", player.name, "upper", upper, "need", max(63 - upper, 0), "max", maximum_upper, status)
        end
    elseif op == "STATS"
        print_stats(game)
    elseif op == "LOG"
        isempty(game.entries) && emit("no scores")
        for (index, entry) in enumerate(game.entries)
            text = "log $index $(game.players[entry.turn.player].name) $(faces_text(entry.turn.dice)) $(entry.category) $(entry.points)"
            entry.joker && (text *= " joker")
            entry.yahtzee_bonus > 0 && (text *= " ybonus 100")
            emit(text)
        end
    elseif op == "FACES"
        total = sum(game.face_totals)
        chi = total == 0 ? "0" : fraction(6 * sum(value -> value * value, game.face_totals) - total * total, total)
        emit("faces", faces_text(game.face_totals), "total", total, "chi2", chi)
    elseif op == "STANDINGS" || op == "END"
        order = ranking(game)
        finished = game.turn === nothing
        op == "END" && emit("end", finished ? "final" : "abandoned")
        leader = player_total(game.players[order[1]])
        for (rank, seat) in enumerate(order)
            player = game.players[seat]
            if op == "STANDINGS"
                emit("standing", rank, player.name, player_total(player), "behind", leader - player_total(player))
            else
                emit("rank", rank, player.name, player_total(player))
            end
        end
        if op == "END"
            finished && record_game!(program.records, game)
            program.game = nothing
        end
    end
    nothing
end

function execute!(program::Program, tokens::Vector{String})
    op = tokens[1]
    op in COMMANDS || fail("unknown command $op")
    if op == "RULE"
        rule, value = tokens[2], tokens[3]
        rule in ("ROLLS", "JOKER") || fail("unknown rule $rule")
        if rule == "ROLLS"
            changed = Rules(Int(integer_word(value, 1, 4)), program.rules.joker)
        else
            haskey(JOKER_RULES, value) || fail("bad value $value")
            changed = Rules(program.rules.rolls, JOKER_RULES[value])
        end
        program.game !== nothing && fail("game in progress")
        program.rules = changed
        emit("rule", rule, value)
    elseif op == "GAME"
        seed = integer_word(tokens[2], 1, 2147483646)
        names = tokens[3:end]
        foreach(player_name, names)
        length(names) > 6 && fail("too many players")
        program.game !== nothing && fail("game in progress")
        seen = Set{String}()
        for name in names
            name in seen && fail("duplicate name $name")
            push!(seen, name)
        end
        program.game = Game(seed, Player.(names), program.rules)
        emit("game seed", seed, "players", join(names, " "))
        emit("turn 1", names[1])
    elseif op == "RECORDS"
        print_records(program.records)
    elseif op == "SIM"
        seed = integer_word(tokens[2], 1, 2147483646)
        sample_count = Int(integer_word(tokens[3], 1, 50))
        strategies = strategy_word.(tokens[4:end])
        length(strategies) > 6 && fail("too many players")
        simulate(seed, sample_count, strategies, program.rules)
    else
        game_command!(program, tokens)
    end
    nothing
end

function main()
    command_count = parse(Int, readline())
    program = Program()
    for _ in 1:command_count
        tokens = String.(split(readline(), ' '))
        try
            execute!(program, tokens)
        catch problem
            problem isa CommandError || rethrow()
            emit("error:", problem.reason)
        end
    end
end
main()
