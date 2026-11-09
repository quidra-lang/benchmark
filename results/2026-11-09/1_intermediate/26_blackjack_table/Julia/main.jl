@enum Phase Idle Insurance Playing
@enum Finish Pending Ordinary Bust Surrendered Charlie
@enum Action Hit Stand DoubleDown SplitHand Surrender
@enum DealerRule S17 H17
@enum DoubleRule AnyDouble Hard9 Hard10
@enum BlackjackPay ThreeToTwo SixToFive
@enum Outcome Blackjack Win Lose Push Busted SurrenderLoss CharlieWin

const COMMANDS = Set(["SHOE", "RULE", "RULES", "PLAYER", "LEAVE", "REBUY", "BET", "SIDE", "DEAL", "INSURANCE", "HIT", "STAND", "DOUBLE", "SPLIT", "SURRENDER", "HINT", "AUTO", "STATUS", "COUNT", "STATS"])
const ACTIONS = Dict("HIT" => Hit, "STAND" => Stand, "DOUBLE" => DoubleDown, "SPLIT" => SplitHand, "SURRENDER" => Surrender)
const ACTION_NAMES = Dict(Hit => "hit", Stand => "stand", DoubleDown => "double", SplitHand => "split", Surrender => "surrender")
const RESULT_NAMES = Dict(Blackjack => "blackjack", Win => "win", Lose => "lose", Push => "push", Busted => "bust", SurrenderLoss => "surrender", CharlieWin => "charlie")
const IDLE_COMMANDS = Set(["SHOE", "RULE", "PLAYER", "LEAVE", "REBUY", "BET", "SIDE", "DEAL"])
const PLAYER_COMMANDS = Set(["LEAVE", "REBUY", "BET", "SIDE", "INSURANCE", "HIT", "STAND", "DOUBLE", "SPLIT", "SURRENDER", "AUTO"])
const RULE_NAMES = ("DEALER", "PEN", "MIN", "MAX", "BJ", "DAS", "DOUBLE", "HANDS", "RSA", "SURRENDER", "CHARLIE", "SIDEMAX")
const STAT_NAMES = (:rounds, :hands, :wins, :losses, :pushes, :blackjacks, :busts, :surrenders, :doubles, :splits)
const RANKS = "A23456789TJQK"
const SUITS = "CDHS"

struct CommandError <: Exception
    message::String
end
fail(message::AbstractString) = throw(CommandError(String(message)))
emit(values...) = println(join(string.(values), ' '))
signed_text(value::Integer) = value >= 0 ? "+$value" : string(value)

Base.@kwdef mutable struct Rules
    dealer::DealerRule = S17
    pen::Int = 75
    minimum::Int64 = 10
    maximum::Int64 = 500
    bj::BlackjackPay = ThreeToTwo
    das::Bool = true
    doubling::DoubleRule = AnyDouble
    hands::Int = 4
    rsa::Bool = false
    surrender::Bool = true
    charlie::Int = 0
    side_maximum::Int64 = 25
end

Base.@kwdef mutable struct Hand
    cards::Vector{Int} = Int[]
    bet::Int64 = 0
    split::Bool = false
    split_aces::Bool = false
    finish::Finish = Pending
end

Base.@kwdef mutable struct Statistics
    rounds::Int = 0
    hands::Int = 0
    wins::Int = 0
    losses::Int = 0
    pushes::Int = 0
    blackjacks::Int = 0
    busts::Int = 0
    surrenders::Int = 0
    doubles::Int = 0
    splits::Int = 0
end

Base.@kwdef mutable struct Player
    name::String
    bankroll::Int64
    bet::Int64 = 0
    side::Int64 = 0
    insurance::Int64 = 0
    net::Int64 = 0
    hands::Vector{Hand} = Hand[]
    stats::Statistics = Statistics()
end

Base.@kwdef mutable struct Shoe
    decks::Int
    random_state::Int64
    cards::Vector{Int} = Int[]
    drawn::Int = 0
    running::Int = 0
end

struct Turn
    seat::Int
    index::Int
end

Base.@kwdef mutable struct Table
    rules::Rules = Rules()
    players::Vector{Union{Nothing,Player}} = Union{Nothing,Player}[nothing for _ in 1:7]
    shoe::Union{Nothing,Shoe} = nothing
    phase::Phase = Idle
    round::Int = 0
    participants::Vector{Int} = Int[]
    insurance_turn::Int = 1
    current::Union{Nothing,Turn} = nothing
    dealer::Hand = Hand()
    hole_visible::Bool = false
    dealer_natural::Bool = false
    dealer_blackjacks::Int = 0
    dealer_busts::Int = 0
end

player_at(table::Table, seat::Int)::Player = table.players[seat]::Player
shoe_of(table::Table)::Shoe = table.shoe::Shoe
current_turn(table::Table)::Turn = table.current::Turn
seated(table::Table) = findall(!isnothing, table.players)
function find_player(table::Table, name::AbstractString)
    findfirst(player -> !isnothing(player) && player.name == name, table.players)
end
function lookup_player(table::Table, name::AbstractString)::Int
    seat = find_player(table, name)
    isnothing(seat) && fail("unknown player $name")
    seat
end
function integer_word(word::AbstractString, low::Integer, high::Integer)::Int64
    occursin(r"^(0|[1-9][0-9]{0,9})$", word) || fail("bad value $word")
    value = parse(Int64, word)
    low <= value <= high || fail("bad value $word")
    value
end
function parse_switch(word::AbstractString)
    word in ("ON", "OFF") || fail("bad value $word")
    word == "ON"
end
function change_rule(original::Rules, name::AbstractString, word::AbstractString)
    name in RULE_NAMES || fail("unknown rule $name")
    changed = deepcopy(original)
    if name == "DEALER"
        word in ("S17", "H17") || fail("bad value $word")
        changed.dealer = word == "H17" ? H17 : S17
    elseif name == "PEN"
        changed.pen = integer_word(word, 50, 90)
    elseif name == "MIN"
        changed.minimum = integer_word(word, 1, 10000)
    elseif name == "MAX"
        changed.maximum = integer_word(word, 1, 10000)
    elseif name == "BJ"
        word in ("3:2", "6:5") || fail("bad value $word")
        changed.bj = word == "3:2" ? ThreeToTwo : SixToFive
    elseif name == "DAS"
        changed.das = parse_switch(word)
    elseif name == "DOUBLE"
        word in ("ANY", "9-11", "10-11") || fail("bad value $word")
        changed.doubling = word == "ANY" ? AnyDouble : word == "9-11" ? Hard9 : Hard10
    elseif name == "HANDS"
        changed.hands = integer_word(word, 1, 4)
    elseif name == "RSA"
        changed.rsa = parse_switch(word)
    elseif name == "SURRENDER"
        changed.surrender = parse_switch(word)
    elseif name == "CHARLIE"
        value = integer_word(word, 0, 7)
        value in (0, 5, 6, 7) || fail("bad value $word")
        changed.charlie = value
    else
        changed.side_maximum = integer_word(word, 0, 1000)
    end
    changed
end
switch_text(value::Bool) = value ? "ON" : "OFF"
function rule_text(rules::Rules, name::AbstractString)
    name == "DEALER" && return string(rules.dealer)
    name == "PEN" && return string(rules.pen)
    name == "MIN" && return string(rules.minimum)
    name == "MAX" && return string(rules.maximum)
    name == "BJ" && return rules.bj == ThreeToTwo ? "3:2" : "6:5"
    name == "DAS" && return switch_text(rules.das)
    name == "DOUBLE" && return rules.doubling == AnyDouble ? "ANY" : rules.doubling == Hard9 ? "9-11" : "10-11"
    name == "HANDS" && return string(rules.hands)
    name == "RSA" && return switch_text(rules.rsa)
    name == "SURRENDER" && return switch_text(rules.surrender)
    name == "CHARLIE" && return string(rules.charlie)
    string(rules.side_maximum)
end

point(card::Int) = min(mod(card, 13) + 1, 10)
card_text(card::Int) = string(RANKS[mod(card, 13) + 1], SUITS[div(card, 13) + 1])
function hand_total(hand::Hand)
    value = sum(point, hand.cards; init = 0)
    soft = any(card -> mod(card, 13) == 0, hand.cards) && value + 10 <= 21
    (value = soft ? value + 10 : value, soft = soft)
end
blackjack(hand::Hand) = !hand.split && length(hand.cards) == 2 && hand_total(hand).value == 21
function hand_text(hand::Hand)
    score = hand_total(hand)
    status = blackjack(hand) ? "blackjack" : score.value > 21 ? "bust $(score.value)" : score.soft ? "soft $(score.value)" : string(score.value)
    join(card_text.(hand.cards), ' ') * " ($status)"
end
hand_name(player::Player, index::Int) = "$(player.name)[$index]"
function hand_line(table::Table, seat::Int, index::Int, verb::String = "")
    player = player_at(table, seat)
    emit("$(hand_name(player, index))$verb: $(hand_text(player.hands[index]))")
end
cut(shoe::Shoe, rules::Rules) = (length(shoe.cards) * rules.pen) ÷ 100
function shuffle!(shoe::Shoe)
    shoe.cards = mod.(0:(52 * shoe.decks - 1), 52)
    for index in length(shoe.cards):-1:2
        shoe.random_state = 48271 * shoe.random_state % 2147483647
        other = Int(shoe.random_state % index) + 1
        shoe.cards[index], shoe.cards[other] = shoe.cards[other], shoe.cards[index]
    end
    shoe.drawn = shoe.running = 0
end
function hilo(card::Int)
    value = point(card)
    2 <= value <= 6 ? 1 : 7 <= value <= 9 ? 0 : -1
end
function draw!(table::Table, visible::Bool)
    shoe = shoe_of(table)
    shoe.drawn += 1
    card = shoe.cards[shoe.drawn]
    visible && (shoe.running += hilo(card))
    card
end
function reveal_dealer!(table::Table)
    if !table.hole_visible
        shoe_of(table).running += hilo(table.dealer.cards[2])
        table.hole_visible = true
    end
    emit("dealer: $(hand_text(table.dealer))")
end
function finish_hand!(hand::Hand, rules::Rules, hand_count::Int)
    value = hand_total(hand).value
    if value > 21
        hand.finish = Bust
    elseif rules.charlie != 0 && length(hand.cards) == rules.charlie
        hand.finish = Charlie
    elseif value == 21
        hand.finish = Ordinary
    elseif hand.split_aces && length(hand.cards) == 2
        again = all(card -> mod(card, 13) == 0, hand.cards) && rules.rsa && hand_count < rules.hands
        hand.finish = again ? Pending : Ordinary
    end
end
function hand_result(table::Table, hand::Hand)::Outcome
    table.dealer_natural && return blackjack(hand) ? Push : Lose
    blackjack(hand) && return Blackjack
    hand.finish == Bust && return Busted
    hand.finish == Surrendered && return SurrenderLoss
    hand.finish == Charlie && return CharlieWin
    player_total = hand_total(hand).value
    dealer_total = hand_total(table.dealer).value
    dealer_total > 21 || player_total > dealer_total ? Win : player_total == dealer_total ? Push : Lose
end
function hand_profit(rules::Rules, bet::Int64, result::Outcome)::Int64
    result == Blackjack && return rules.bj == ThreeToTwo ? (bet * 3) ÷ 2 : (bet * 6) ÷ 5
    result in (Win, CharlieWin) && return bet
    result == Push && return 0
    result == SurrenderLoss && return bet ÷ 2 - bet
    -bet
end
function record!(stats::Statistics, result::Outcome)
    stats.hands += 1
    if result in (Blackjack, Win, CharlieWin)
        stats.wins += 1
    elseif result == Push
        stats.pushes += 1
    else
        stats.losses += 1
    end
    result == Blackjack && (stats.blackjacks += 1)
    result == Busted && (stats.busts += 1)
    result == SurrenderLoss && (stats.surrenders += 1)
end
function settle!(table::Table)
    for seat in table.participants
        player = player_at(table, seat)
        for (index, hand) in enumerate(player.hands)
            result = hand_result(table, hand)
            profit = hand_profit(table.rules, hand.bet, result)
            player.bankroll += hand.bet + profit
            player.net += profit
            record!(player.stats, result)
            emit(hand_name(player, index), RESULT_NAMES[result], signed_text(profit))
        end
        emit(player.name, "bankroll", player.bankroll)
    end
    for seat in seated(table)
        player = player_at(table, seat)
        player.bet = player.side = 0
    end
    table.phase = Idle
    table.current = nothing
end
function dealer_turn!(table::Table)
    reveal_dealer!(table)
    required = any(hand.finish == Ordinary && !blackjack(hand) for seat in table.participants for hand in player_at(table, seat).hands)
    drew = false
    if required
        while true
            score = hand_total(table.dealer)
            (score.value < 17 || (score.value == 17 && score.soft && table.rules.dealer == H17)) || break
            push!(table.dealer.cards, draw!(table, true))
            emit("dealer hits: $(hand_text(table.dealer))")
            drew = true
        end
    end
    drew && hand_total(table.dealer).value > 21 && (table.dealer_busts += 1)
    settle!(table)
end
function advance_hands!(table::Table)
    while true
        table.current = nothing
        for seat in table.participants
            index = findfirst(hand -> hand.finish == Pending, player_at(table, seat).hands)
            if !isnothing(index)
                table.current = Turn(seat, index)
                break
            end
        end
        if isnothing(table.current)
            dealer_turn!(table)
            return
        end
        turn = current_turn(table)
        player = player_at(table, turn.seat)
        hand = player.hands[turn.index]
        length(hand.cards) == 1 || return
        push!(hand.cards, draw!(table, true))
        hand_line(table, turn.seat, turn.index)
        finish_hand!(hand, table.rules, length(player.hands))
        hand.finish == Pending && return
    end
end
function peek!(table::Table)
    table.dealer_natural = blackjack(table.dealer)
    emit("dealer peeks:", table.dealer_natural ? "blackjack" : "no blackjack")
    for seat in table.participants
        player = player_at(table, seat)
        player.insurance == 0 && continue
        profit = table.dealer_natural ? player.insurance * 2 : -player.insurance
        player.bankroll += player.insurance + profit
        player.net += profit
        emit(player.name, "insurance", signed_text(profit))
    end
    if table.dealer_natural
        table.dealer_blackjacks += 1
        reveal_dealer!(table)
        settle!(table)
    else
        table.phase = Playing
        advance_hands!(table)
    end
end
function deal!(table::Table)
    shoe = shoe_of(table)
    if shoe.drawn >= cut(shoe, table.rules)
        shuffle!(shoe)
        emit("shuffle")
    end
    table.round += 1
    emit("round", table.round)
    table.participants = [seat for seat in seated(table) if player_at(table, seat).bet != 0]
    for seat in table.participants
        player = player_at(table, seat)
        player.bankroll -= player.bet + player.side
        player.insurance = 0
        player.stats.rounds += 1
        player.hands = [Hand(bet = player.bet)]
    end
    for seat in table.participants
        push!(player_at(table, seat).hands[1].cards, draw!(table, true))
    end
    table.dealer = Hand(cards = [draw!(table, true)])
    for seat in table.participants
        hand = player_at(table, seat).hands[1]
        push!(hand.cards, draw!(table, true))
        blackjack(hand) && (hand.finish = Ordinary)
    end
    push!(table.dealer.cards, draw!(table, false))
    table.hole_visible = table.dealer_natural = false
    table.current = nothing
    for seat in table.participants
        hand_line(table, seat, 1)
    end
    emit("dealer:", card_text(table.dealer.cards[1]), "??")
    for seat in table.participants
        player = player_at(table, seat)
        player.side == 0 && continue
        first, second = player.hands[1].cards
        same_color = (div(first, 13) in (0, 3)) == (div(second, 13) in (0, 3))
        multiplier = mod(first, 13) != mod(second, 13) ? -1 : first == second ? 25 : same_color ? 12 : 6
        result = multiplier == 25 ? "perfect" : multiplier == 12 ? "colored" : multiplier == 6 ? "mixed" : "lose"
        profit = player.side * multiplier
        player.bankroll += player.side + profit
        player.net += profit
        emit(player.name, "side", result, signed_text(profit))
    end
    up = point(table.dealer.cards[1])
    if up == 1
        table.phase = Insurance
        table.insurance_turn = 1
        emit("insurance offered")
    elseif up == 10
        peek!(table)
    else
        table.phase = Playing
        advance_hands!(table)
    end
end

function action_problem(table::Table, action::Action)::Union{Nothing,String}
    turn = current_turn(table)
    player = player_at(table, turn.seat)
    hand = player.hands[turn.index]
    if action == Hit
        return hand.split_aces ? "split aces" : nothing
    elseif action == DoubleDown
        hand.split_aces && return "split aces"
        length(hand.cards) == 2 || return "two cards only"
        score = hand_total(hand)
        low = table.rules.doubling == Hard9 ? 9 : 10
        limited = table.rules.doubling != AnyDouble && (score.soft || score.value < low || score.value > 11)
        (limited || (!table.rules.das && hand.split)) && return "double not allowed"
        player.bankroll < hand.bet && return "insufficient funds"
    elseif action == SplitHand
        length(hand.cards) == 2 || return "two cards only"
        point(hand.cards[1]) == point(hand.cards[2]) || return "not a pair"
        length(player.hands) >= table.rules.hands && return "hand limit"
        player.bankroll < hand.bet && return "insufficient funds"
    elseif action == Surrender
        (!table.rules.surrender || hand.split) && return "surrender not allowed"
        length(hand.cards) == 2 || return "two cards only"
    end
    nothing
end
function recommendation(table::Table)::Action
    turn = current_turn(table)
    hand = player_at(table, turn.seat).hands[turn.index]
    can_split = isnothing(action_problem(table, SplitHand))
    hand.split_aces && return can_split ? SplitHand : Stand
    up = point(table.dealer.cards[1])
    up == 1 && (up = 11)
    if can_split
        value = point(hand.cards[1])
        wanted = value in (1, 8) || (value == 9 && !(up in (7, 10, 11))) || (value in (2, 3, 7) && up <= 7) || (value == 6 && up <= 6) || (value == 4 && up in (5, 6))
        wanted && return SplitHand
    end
    score = hand_total(hand)
    value = score.value
    can_double = isnothing(action_problem(table, DoubleDown))
    if score.soft
        value >= 19 && return Stand
        if value == 18
            3 <= up <= 6 && return can_double ? DoubleDown : Stand
            return up in (2, 7, 8) ? Stand : Hit
        end
        wanted = (value == 17 && 3 <= up <= 6) || (value in (15, 16) && 4 <= up <= 6) || (value in (13, 14) && up in (5, 6))
        return wanted && can_double ? DoubleDown : Hit
    end
    value >= 17 && return Stand
    if value >= 13
        up <= 6 && return Stand
        if ((value == 16 && up >= 9) || (value == 15 && up == 10)) && isnothing(action_problem(table, Surrender))
            return Surrender
        end
        return Hit
    end
    value == 12 && return 4 <= up <= 6 ? Stand : Hit
    wanted = (value == 11 && up <= 10) || (value == 10 && up <= 9) || (value == 9 && 3 <= up <= 6)
    wanted && can_double ? DoubleDown : Hit
end
function perform_action!(table::Table, action::Action)
    turn = current_turn(table)
    player = player_at(table, turn.seat)
    hand = player.hands[turn.index]
    name = hand_name(player, turn.index)
    if action == SplitHand
        player.bankroll -= hand.bet
        player.stats.splits += 1
        emit(name, "splits", card_text.(hand.cards)...)
        aces = hand.split_aces || point(hand.cards[1]) == 1
        first = Hand(cards = [hand.cards[1]], bet = hand.bet, split = true, split_aces = aces)
        second = Hand(cards = [hand.cards[2]], bet = hand.bet, split = true, split_aces = aces)
        player.hands[turn.index] = first
        insert!(player.hands, turn.index + 1, second)
        push!(first.cards, draw!(table, true))
        hand_line(table, turn.seat, turn.index)
        finish_hand!(first, table.rules, length(player.hands))
    elseif action == Stand || action == Surrender
        hand.finish = action == Stand ? Ordinary : Surrendered
        hand_line(table, turn.seat, turn.index, action == Stand ? " stands" : " surrenders")
    else
        if action == DoubleDown
            player.bankroll -= hand.bet
            hand.bet *= 2
            player.stats.doubles += 1
        end
        push!(hand.cards, draw!(table, true))
        hand_line(table, turn.seat, turn.index, action == DoubleDown ? " doubles" : " hits")
        finish_hand!(hand, table.rules, length(player.hands))
        action == DoubleDown && hand.finish == Pending && (hand.finish = Ordinary)
    end
    advance_hands!(table)
end

function status_output(table::Table)
    if table.phase == Idle
        emit("table idle round", table.round)
    elseif table.phase == Insurance
        emit("table insurance round", table.round, "next", player_at(table, table.participants[table.insurance_turn]).name)
    else
        turn = current_turn(table)
        emit("table play round", table.round, "turn", hand_name(player_at(table, turn.seat), turn.index))
    end
    table.phase != Idle && emit("dealer:", card_text(table.dealer.cards[1]), "??")
    for seat in seated(table)
        player = player_at(table, seat)
        emit("seat", seat, player.name, "bankroll", player.bankroll, "bet", player.bet, "side", player.side)
        if table.phase != Idle && seat in table.participants
            for (index, hand) in enumerate(player.hands)
                emit("$(hand_name(player, index)): $(hand_text(hand)) bet $(hand.bet)")
            end
        end
    end
end
function statistics_output(table::Table)
    for seat in seated(table)
        player = player_at(table, seat)
        fields = join(("$name $(getfield(player.stats, name))" for name in STAT_NAMES), ' ')
        emit("stats", player.name, fields, "net", signed_text(player.net))
    end
    emit("stats dealer rounds", table.round, "blackjacks", table.dealer_blackjacks, "busts", table.dealer_busts)
end

function command!(table::Table, tokens::AbstractVector{<:AbstractString})
    op = tokens[1]
    op in COMMANDS || fail("unknown command $op")
    seat = 0
    amount = seed = Int64(0)
    proposed = table.rules
    if op == "SHOE"
        amount = integer_word(tokens[2], 1, 8)
        seed = integer_word(tokens[3], 1, 2147483646)
    elseif op == "RULE"
        proposed = change_rule(table.rules, tokens[2], tokens[3])
    elseif op == "PLAYER"
        occursin(r"^[A-Z]{1,8}$", tokens[2]) || fail("bad name $(tokens[2])")
        amount = integer_word(tokens[3], 1, 1000000)
    elseif op in PLAYER_COMMANDS
        seat = lookup_player(table, tokens[2])
        if op in ("REBUY", "BET", "SIDE", "INSURANCE")
            amount = integer_word(tokens[3], op == "REBUY" ? 1 : 0, 1000000)
        end
    end
    op in IDLE_COMMANDS && table.phase != Idle && fail("round in progress")
    op == "INSURANCE" && table.phase != Insurance && fail("no insurance")
    action_command = haskey(ACTIONS, op) || op == "AUTO"
    if action_command || op == "HINT"
        table.phase == Idle && fail("no round")
        table.phase == Insurance && fail("insurance pending")
        turn = current_turn(table)
        action_command && seat != turn.seat && fail("waiting for $(hand_name(player_at(table, turn.seat), turn.index))")
    end
    if action_command
        if op == "AUTO"
            while table.phase == Playing && current_turn(table).seat == seat
                perform_action!(table, recommendation(table))
            end
        else
            action = ACTIONS[op]
            problem = action_problem(table, action)
            isnothing(problem) || fail(problem)
            perform_action!(table, action)
        end
        return
    end
    if op == "SHOE"
        table.shoe = Shoe(decks = Int(amount), random_state = seed)
        shuffle!(shoe_of(table))
        emit("shoe", amount, "decks", length(shoe_of(table).cards), "cards cut", cut(shoe_of(table), table.rules))
    elseif op == "RULE"
        proposed.minimum > proposed.maximum && fail("min above max")
        table.rules = proposed
        emit("rule", tokens[2], rule_text(table.rules, tokens[2]))
    elseif op == "RULES"
        emit("rules", join(("$name $(rule_text(table.rules, name))" for name in RULE_NAMES), ' '))
    elseif op == "PLAYER"
        !isnothing(find_player(table, tokens[2])) && fail("player exists")
        empty_seat = findfirst(isnothing, table.players)
        isnothing(empty_seat) && fail("table full")
        table.players[empty_seat] = Player(name = String(tokens[2]), bankroll = amount)
        emit(tokens[2], "sits at seat", empty_seat, "with", amount)
    elseif op == "LEAVE"
        player = player_at(table, seat)
        emit(player.name, "leaves with", player.bankroll, "net", signed_text(player.net))
        table.players[seat] = nothing
    elseif op == "REBUY"
        player = player_at(table, seat)
        player.bankroll += amount
        emit(player.name, "rebuys", amount, "bankroll", player.bankroll)
    elseif op == "BET"
        player = player_at(table, seat)
        if amount != 0
            table.rules.minimum <= amount <= table.rules.maximum || fail("bet out of limits")
            amount + player.side > player.bankroll && fail("insufficient funds")
        end
        player.bet = amount
        if amount == 0
            player.side = 0
            emit(player.name, "bet cleared")
        else
            emit(player.name, "bets", amount)
        end
    elseif op == "SIDE"
        player = player_at(table, seat)
        if amount != 0
            player.bet == 0 && fail("no bet")
            amount > table.rules.side_maximum && fail("side out of limits")
            player.bet + amount > player.bankroll && fail("insufficient funds")
        end
        player.side = amount
        amount == 0 ? emit(player.name, "side cleared") : emit(player.name, "side", amount)
    elseif op == "DEAL"
        isnothing(table.shoe) && fail("no shoe")
        any(player_at(table, index).bet != 0 for index in seated(table)) || fail("no bets")
        deal!(table)
    elseif op == "INSURANCE"
        waiting = table.participants[table.insurance_turn]
        seat == waiting || fail("waiting for $(player_at(table, waiting).name)")
        player = player_at(table, seat)
        amount > player.bet ÷ 2 && fail("insurance out of limits")
        amount > player.bankroll && fail("insufficient funds")
        player.bankroll -= amount
        player.insurance = amount
        amount == 0 ? emit(player.name, "declines insurance") : emit(player.name, "insures", amount)
        table.insurance_turn += 1
        table.insurance_turn > length(table.participants) && peek!(table)
    elseif op == "HINT"
        turn = current_turn(table)
        emit("hint $(hand_name(player_at(table, turn.seat), turn.index)): $(ACTION_NAMES[recommendation(table)])")
    elseif op == "STATUS"
        status_output(table)
    elseif op == "COUNT"
        isnothing(table.shoe) && fail("no shoe")
        shoe = shoe_of(table)
        remaining = length(shoe.cards) - shoe.drawn
        scaled = (abs(shoe.running) * 5200) ÷ remaining
        sign = shoe.running < 0 ? "-" : ""
        decimals = lpad(string(mod(scaled, 100)), 2, '0')
        emit("count running", shoe.running, "true", "$sign$(scaled ÷ 100).$decimals", "remaining", remaining)
    elseif op == "STATS"
        isempty(seated(table)) && fail("no players")
        statistics_output(table)
    end
end

function main()
    count = parse(Int, readline())
    table = Table()
    for _ in 1:count
        tokens = split(readline(), ' ')
        try
            command!(table, tokens)
        catch problem
            problem isa CommandError || rethrow()
            emit("error:", problem.message)
        end
    end
end
main()
