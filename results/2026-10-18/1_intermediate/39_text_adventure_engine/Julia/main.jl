@enum PlaceKind FLOOR HELD INSIDE NOWHERE
@enum ContainerState OPEN CLOSED LOCKED
@enum EndStatus PLAYING WON DEAD
@enum TriggerKind ENTER_ROOM USE_ITEMS
@enum Verb GO LOOK EXAMINE TAKE DROP PUT INVENTORY OPEN_ITEM CLOSE_ITEM UNLOCK LOCK USE LIGHT EXTINGUISH WAIT SCORE SAVE RESTORE VERBOSE BRIEF

const DIRECTIONS = ("north", "south", "east", "west", "up", "down")
const VERB_NAMES = ("go", "look", "examine", "take", "drop", "put", "inventory", "open", "close", "unlock",
                    "lock", "use", "light", "extinguish", "wait", "score", "save", "restore", "verbose", "brief")
const VERBS = Dict{String,Verb}(word => verb for (verb, aliases) in (
    (GO, "go walk run"), (LOOK, "look l"), (EXAMINE, "examine x inspect read"), (TAKE, "take get grab"),
    (DROP, "drop discard"), (PUT, "put insert place"), (INVENTORY, "inventory inv i"), (OPEN_ITEM, "open"),
    (CLOSE_ITEM, "close shut"), (UNLOCK, "unlock"), (LOCK, "lock"), (USE, "use apply"),
    (LIGHT, "light ignite"), (EXTINGUISH, "extinguish douse snuff"), (WAIT, "wait z"), (SCORE, "score"),
    (SAVE, "save"), (RESTORE, "restore load"), (VERBOSE, "verbose"), (BRIEF, "brief")) for word in split(aliases))
const ACTIONS = (GO, TAKE, DROP, PUT, OPEN_ITEM, CLOSE_ITEM, UNLOCK, LOCK, USE, LIGHT, EXTINGUISH, WAIT)
const NO_ARGUMENTS = (LOOK, INVENTORY, WAIT, SCORE, SAVE, RESTORE, VERBOSE, BRIEF)

struct CommandError <: Exception
    message::String
end
fail(message::String) = throw(CommandError(message))
canonical(verb::Verb) = VERB_NAMES[Int(verb) + 1]
direction(word::AbstractString) = something(findfirst(d -> word == DIRECTIONS[d] || word == DIRECTIONS[d][1:1], 1:6), 0)
command_words(line::String) = filter(word -> word ∉ ("the", "a", "an"), String.(split(lowercase(line))))
all_items(phrase::Vector{String}) = phrase == ["all"]

struct Place
    kind::PlaceKind
    index::Int
end
const PLAYER = Place(HELD, 0)
const REMOVED = Place(NOWHERE, 0)
floor_place(room::Int) = Place(FLOOR, room)
inside(item::Int) = Place(INSIDE, item)

struct ExitLink
    destination::Int
    key::Union{Nothing,Int}
    locked::Bool
end
struct Room
    name::String
    dark::Bool
    description::Vector{String}
end
mutable struct Item
    id::String
    name::String
    nouns::Set{String}
    words::Set{String}
    details::Vector{String}
    weight::Int
    treasure::Int
    light::Bool
    capacity::Int
    key::Union{Nothing,Int}
    fixed::Bool
end
Item(id::String) = Item(id, "", Set([id]), Set{String}(), String[], 0, 0, false, 0, nothing, false)
struct Trigger
    kind::TriggerKind
    first::Int
    second::Int
end
struct Condition
    flag::String
    on::Bool
end
struct MessageEffect
    text::String
end
struct OpenEffect
    room::Int
    direction::Int
    destination::Int
end
struct MoveEffect
    item::Int
    place::Place
end
struct FlagEffect
    flag::String
    on::Bool
end
struct PointsEffect
    amount::Int
end
const Effect = Union{MessageEffect,OpenEffect,MoveEffect,FlagEffect,PointsEffect}
struct Rule
    trigger::Trigger
    condition::Union{Nothing,Condition}
    effect::Effect
end
struct World
    rooms::Vector{Room}
    items::Vector{Item}
    rules::Vector{Rule}
    vocabulary::Set{String}
    trophy::Int
    max_weight::Int
end
mutable struct GameState
    room::Int
    places::Vector{Place}
    containers::Vector{ContainerState}
    exits::Matrix{Union{Nothing,ExitLink}}
    lit::BitVector
    fuel::Vector{Int}
    flags::Set{String}
    bonus::Int
    moves::Int
    visited::BitVector
    darkness::Int
    ended::EndStatus
end
Base.copy(state::GameState) = GameState(state.room, copy(state.places), copy(state.containers), copy(state.exits),
    copy(state.lit), copy(state.fuel), copy(state.flags), state.bonus, state.moves, copy(state.visited), state.darkness, state.ended)
mutable struct Adventure
    world::World
    state::GameState
    saved::Union{Nothing,GameState}
    pronoun::Union{Nothing,Int}
    previous::Union{Nothing,String}
    verbose::Bool
end

function read_rule(tokens::Vector{String}, position::Int, trigger::Trigger, rooms::Dict{String,Int}, items::Dict{String,Int})
    condition = nothing
    if tokens[position] in ("IF", "UNLESS")
        condition = Condition(tokens[position + 1], tokens[position] == "IF")
        position += 2
    end
    kind = tokens[position]
    args = tokens[position+1:end]
    effect = if kind == "MESSAGE"
        MessageEffect(join(args, " "))
    elseif kind == "OPEN"
        OpenEffect(rooms[args[1]], direction(args[2]), rooms[args[3]])
    elseif kind == "REMOVE"
        MoveEffect(items[args[1]], REMOVED)
    elseif kind == "ADD"
        MoveEffect(items[args[1]], floor_place(rooms[args[2]]))
    elseif kind in ("SET", "CLEAR")
        FlagEffect(args[1], kind == "SET")
    else
        PointsEffect(parse(Int, args[1]))
    end
    Rule(trigger, condition, effect)
end
function Adventure(definitions::Vector{Vector{String}})
    room_ids = [tokens[2] for tokens in definitions if tokens[1] == "ROOM"]
    item_ids = sort([tokens[2] for tokens in definitions if tokens[1] == "ITEM"])
    room_index = Dict{String,Int}(id => index for (index, id) in enumerate(room_ids))
    item_index = Dict{String,Int}(id => index for (index, id) in enumerate(item_ids))
    rooms = [Room("", false, String[]) for _ in room_ids]
    items = Item.(item_ids)
    exits = fill!(Matrix{Union{Nothing,ExitLink}}(undef, length(rooms), 6), nothing)
    state = GameState(1, fill(PLAYER, length(items)), fill(OPEN, length(items)), exits, falses(length(items)),
                      zeros(Int, length(items)), Set{String}(), 0, 0, falses(length(rooms)), 0, PLAYING)
    rules = Rule[]
    trophy = max_weight = 0
    for tokens in definitions
        kind = tokens[1]
        if kind == "ROOM"
            dark = tokens[3] == "DARK"
            rooms[room_index[tokens[2]]] = Room(join(tokens[(dark ? 4 : 3):end], " "), dark, String[])
        elseif kind == "DESC"
            push!(rooms[room_index[tokens[2]]].description, join(tokens[3:end], " "))
        elseif kind == "EXIT"
            key = length(tokens) > 4 ? item_index[tokens[6]] : nothing
            state.exits[room_index[tokens[2]], direction(tokens[3])] = ExitLink(room_index[tokens[4]], key, key !== nothing)
        elseif kind == "ITEM"
            index = item_index[tokens[2]]
            item = items[index]
            state.places[index] = tokens[3] == "PLAYER" ? PLAYER : tokens[3] == "NOWHERE" ? REMOVED : floor_place(room_index[tokens[3]])
            item.weight = parse(Int, tokens[4])
            position = 5
            if tokens[position] == "TREASURE"
                item.treasure = parse(Int, tokens[position + 1]); position += 2
            end
            if tokens[position] == "LIGHT"
                item.light = true; state.fuel[index] = parse(Int, tokens[position + 1]); position += 2
            end
            if tokens[position] == "CONTAINER"
                item.capacity = parse(Int, tokens[position + 1]); position += 2
                if tokens[position] == "CLOSED"
                    state.containers[index] = CLOSED; position += 1
                end
                if tokens[position] == "LOCKED"
                    item.key = item_index[tokens[position + 1]]; state.containers[index] = LOCKED; position += 2
                end
            end
            if tokens[position] == "FIXED"
                item.fixed = true; position += 1
            end
            item.name = join(tokens[position:end], " ")
            union!(item.words, tokens[position:end])
        elseif kind == "INSIDE"
            state.places[item_index[tokens[2]]] = inside(item_index[tokens[3]])
        elseif kind == "ALIAS"
            push!(items[item_index[tokens[2]]].nouns, tokens[3])
        elseif kind == "DETAIL"
            push!(items[item_index[tokens[2]]].details, join(tokens[3:end], " "))
        elseif kind == "RULE"
            push!(rules, read_rule(tokens, 4, Trigger(USE_ITEMS, item_index[tokens[2]], item_index[tokens[3]]), room_index, item_index))
        elseif kind == "ENTER"
            push!(rules, read_rule(tokens, 3, Trigger(ENTER_ROOM, room_index[tokens[2]], 0), room_index, item_index))
        elseif kind == "TROPHY"
            trophy = room_index[tokens[2]]
        elseif kind == "START"
            state.room = room_index[tokens[2]]
        elseif kind == "MAXWEIGHT"
            max_weight = parse(Int, tokens[2])
        end
    end
    state.visited[state.room] = true
    vocabulary = Set{String}()
    for item in items
        union!(vocabulary, item.nouns, item.words)
    end
    Adventure(World(rooms, items, rules, vocabulary, trophy, max_weight), state, nothing, nothing, nothing, false)
end

current_floor(game::Adventure) = floor_place(game.state.room)
direct(game::Adventure, place::Place) = findall(==(place), game.state.places)
function reachable(game::Adventure, item::Int, root::Place)
    place = game.state.places[item]
    while place.kind == INSIDE
        game.state.containers[place.index] == OPEN || return false
        place = game.state.places[place.index]
    end
    place == root
end
carried(game::Adventure, item::Int) = reachable(game, item, PLAYER)
room_item(game::Adventure, item::Int) = reachable(game, item, current_floor(game))
is_lit(game::Adventure) = !game.world.rooms[game.state.room].dark ||
    any(i -> game.state.lit[i] && (carried(game, i) || room_item(game, i)), eachindex(game.world.items))
function visible(game::Adventure)
    lit = is_lit(game)
    [carried(game, i) || (lit && room_item(game, i)) for i in eachindex(game.world.items)]
end
function within(game::Adventure, item::Int, ancestor::Int)
    place = game.state.places[item]
    while place.kind == INSIDE
        place.index == ancestor && return true
        place = game.state.places[place.index]
    end
    false
end
total_weight(game::Adventure, item::Int) = game.world.items[item].weight + place_weight(game, inside(item))
place_weight(game::Adventure, place::Place) = sum(i -> total_weight(game, i), direct(game, place); init = 0)
function stored(game::Adventure, item::Int)
    place = game.state.places[item]
    while place.kind == INSIDE
        place = game.state.places[place.index]
    end
    place == floor_place(game.world.trophy)
end
function treasures(game::Adventure)
    indices = findall(item -> item.treasure > 0, game.world.items)
    collected = filter(i -> stored(game, i), indices)
    (points = sum(i -> game.world.items[i].treasure, collected; init = 0), stored = length(collected), total = length(indices))
end
score(game::Adventure) = treasures(game).points + game.state.bonus
item_names(game::Adventure, items::Vector{Int}) = join((game.world.items[i].name for i in items), ", ")
function display_name(game::Adventure, item::Int)
    annotations = String[]
    game.world.items[item].capacity > 0 && push!(annotations, lowercase(string(game.state.containers[item])))
    game.state.lit[item] && push!(annotations, "lit")
    game.world.items[item].name * (isempty(annotations) ? "" : " ($(join(annotations, ", ")))")
end
function item_tree(game::Adventure, place::Place, depth::Int)
    for item in direct(game, place)
        println("  " ^ depth, display_name(game, item))
        if game.world.items[item].capacity > 0 && game.state.containers[item] == OPEN
            item_tree(game, inside(item), depth + 1)
        end
    end
end
function describe(game::Adventure, full::Bool)
    if !is_lit(game)
        println("It is pitch dark.")
        return
    end
    room = game.state.room
    println(game.world.rooms[room].name)
    full && foreach(println, game.world.rooms[room].description)
    exits = String[]
    for d in 1:6
        exit = game.state.exits[room, d]
        exit === nothing || push!(exits, DIRECTIONS[d] * (exit.locked ? " (locked)" : ""))
    end
    println("Exits: ", isempty(exits) ? "none" : join(exits, ", "))
    if !isempty(direct(game, current_floor(game)))
        println("You see:"); item_tree(game, current_floor(game), 1)
    end
end
function resolve!(game::Adventure, phrase::Vector{String})
    seen = visible(game)
    if phrase == ["it"]
        game.pronoun === nothing && fail("I don't know what \"it\" refers to.")
        seen[game.pronoun] || fail("You can't see any such thing.")
        return game.pronoun::Int
    end
    for word in phrase
        word in game.world.vocabulary || fail("I don't know the word \"$word\".")
    end
    matches = [i for i in eachindex(game.world.items) if seen[i] && last(phrase) in game.world.items[i].nouns &&
               all(word -> word in game.world.items[i].words, phrase[1:end-1])]
    isempty(matches) && fail("You can't see any such thing.")
    length(matches) > 1 && fail("Which do you mean: $(item_names(game, matches))?")
    game.pronoun = only(matches)
    game.pronoun::Int
end
function run_rules!(game::Adventure, trigger::Trigger)
    executed = 0
    message = false
    for rule in game.world.rules
        rule.trigger == trigger || continue
        condition = rule.condition
        condition !== nothing && (condition.flag in game.state.flags) != condition.on && continue
        executed += 1
        effect = rule.effect
        if effect isa MessageEffect
            println(effect.text); message = true
        elseif effect isa OpenEffect
            game.state.exits[effect.room, effect.direction] = ExitLink(effect.destination, nothing, false)
        elseif effect isa MoveEffect
            game.state.places[effect.item] = effect.place
        elseif effect isa FlagEffect
            effect.on ? push!(game.state.flags, effect.flag) : delete!(game.state.flags, effect.flag)
        elseif effect isa PointsEffect
            game.state.bonus += effect.amount
        end
    end
    (; executed, message)
end
function pass_turn!(game::Adventure, baseline::Bool)
    game.state.moves += 1
    nearby = [carried(game, i) || room_item(game, i) for i in eachindex(game.world.items)]
    for item in eachindex(game.world.items)
        game.state.lit[item] || continue
        game.state.fuel[item] -= 1
        if game.state.fuel[item] == 0
            game.state.lit[item] = false
            nearby[item] && println("The $(game.world.items[item].name) goes out.")
        end
    end
    lit = is_lit(game)
    if baseline && !lit
        println("It is now pitch dark.")
    elseif !baseline && lit
        describe(game, true)
    end
    game.state.darkness = lit ? 0 : game.state.darkness + 1
    game.state.darkness == 2 && println("You hear something moving in the dark.")
    game.state.darkness == 3 && (game.state.ended = DEAD)
    treasure = treasures(game)
    if game.state.ended == PLAYING && treasure.total > 0 && treasure.stored == treasure.total
        game.state.ended = WON
    end
    if game.state.ended != PLAYING
        println(game.state.ended == DEAD ? "*** You have died ***" : "*** You have won ***")
        println("You scored $(treasure.points + game.state.bonus) points in $(game.state.moves) moves.")
    end
end

function require_container(game::Adventure, item::Int)
    game.world.items[item].capacity > 0 || fail("The $(game.world.items[item].name) is not a container.")
    game.state.containers[item] == OPEN || fail("The $(game.world.items[item].name) is closed.")
end
function put_item!(game::Adventure, item::Int, container::Int)
    name, target = game.world.items[item].name, game.world.items[container].name
    within(game, container, item) && return "The $target is inside the $name."
    game.state.places[item] == inside(container) && return "The $name is already in the $target."
    weight = place_weight(game, inside(container)) + (within(game, item, container) ? 0 : total_weight(game, item))
    weight > game.world.items[container].capacity && return "The $name doesn't fit in the $target."
    game.state.places[item] = inside(container)
    ""
end
function take_items!(game::Adventure, first::Vector{String}, second::Vector{String})
    is_lit(game) || fail("It is pitch dark.")
    container = nothing
    source = current_floor(game)
    if !isempty(second)
        container = resolve!(game, second); require_container(game, container); source = inside(container)
    end
    if all_items(first)
        candidates = filter(i -> !game.world.items[i].fixed, direct(game, source))
        isempty(candidates) && fail(container === nothing ? "There is nothing here to take." : "There is nothing in the $(game.world.items[container].name) to take.")
        taken = false
        for item in candidates
            if !carried(game, item) && place_weight(game, PLAYER) + total_weight(game, item) > game.world.max_weight
                println("$(game.world.items[item].name): You can't carry any more.")
            else
                game.state.places[item] = PLAYER; println("$(game.world.items[item].name): Taken."); taken = true
            end
        end
        return taken
    end
    item = resolve!(game, first)
    name = game.world.items[item].name
    container !== nothing && game.state.places[item] != source && fail("The $name is not in the $(game.world.items[container].name).")
    game.state.places[item] == PLAYER && fail("You already have the $name.")
    game.world.items[item].fixed && fail("The $name is fixed in place.")
    !carried(game, item) && place_weight(game, PLAYER) + total_weight(game, item) > game.world.max_weight && fail("You can't carry any more.")
    game.state.places[item] = PLAYER
    println("Taken.")
    true
end
function drop_items!(game::Adventure, target::Vector{String})
    if all_items(target)
        candidates = direct(game, PLAYER)
        isempty(candidates) && fail("You are empty-handed.")
        for item in candidates
            game.state.places[item] = current_floor(game)
            println("$(game.world.items[item].name): Dropped.")
        end
    else
        item = resolve!(game, target)
        carried(game, item) || fail("You aren't carrying the $(game.world.items[item].name).")
        game.state.places[item] = current_floor(game)
        println("Dropped.")
    end
end
function put_items!(game::Adventure, first::Vector{String}, second::Vector{String})
    item = all_items(first) ? nothing : resolve!(game, first)
    container = resolve!(game, second)
    if item !== nothing
        carried(game, item) || fail("You aren't carrying the $(game.world.items[item].name).")
        item == container && fail("You can't put the $(game.world.items[item].name) inside itself.")
    end
    require_container(game, container)
    if item !== nothing
        reason = put_item!(game, item, container)
        isempty(reason) || fail(reason)
        println("You put the $(game.world.items[item].name) in the $(game.world.items[container].name).")
        return true
    end
    candidates = filter(!=(container), direct(game, PLAYER))
    isempty(candidates) && fail("You have nothing to put in the $(game.world.items[container].name).")
    moved = false
    for candidate in candidates
        reason = put_item!(game, candidate, container)
        isempty(reason) && (moved = true)
        println("$(game.world.items[candidate].name): ", isempty(reason) ? "Done." : reason)
    end
    moved
end
function key_check!(game::Adventure, key::Int, phrase::Vector{String})
    if isempty(phrase)
        carried(game, key) || fail("You don't have the right key.")
        println("(with the $(game.world.items[key].name))")
    else
        item = resolve!(game, phrase)
        carried(game, item) || fail("You aren't carrying the $(game.world.items[item].name).")
        item == key || fail("The $(game.world.items[item].name) doesn't fit.")
    end
end
function change_lock!(game::Adventure, target::Vector{String}, key_phrase::Vector{String}, locking::Bool)
    d = length(target) == 1 ? direction(only(target)) : 0
    status = locking ? "already locked" : "not locked"
    if d != 0
        room = game.state.room
        exit = game.state.exits[room, d]
        exit === nothing && fail("There is no exit $(DIRECTIONS[d]).")
        key = exit.key
        key === nothing && fail("The way $(DIRECTIONS[d]) has no lock.")
        exit.locked == locking && fail("The way $(DIRECTIONS[d]) is $status.")
        key_check!(game, key, key_phrase)
        game.state.exits[room, d] = ExitLink(exit.destination, key, locking)
        reverse = xor(d - 1, 1) + 1
        opposite = game.state.exits[exit.destination, reverse]
        if opposite !== nothing && opposite.destination == room && opposite.key == key
            game.state.exits[exit.destination, reverse] = ExitLink(opposite.destination, key, locking)
        end
    else
        item = resolve!(game, target)
        value = game.world.items[item]
        key = value.key
        (value.capacity == 0 || key === nothing) && fail("The $(value.name) has no lock.")
        (game.state.containers[item] == LOCKED) == locking && fail("The $(value.name) is $status.")
        locking && game.state.containers[item] == OPEN && fail("You must close the $(value.name) first.")
        key_check!(game, key, key_phrase)
        game.state.containers[item] = locking ? LOCKED : CLOSED
    end
    println(locking ? "Locked." : "Unlocked.")
end
function examine(game::Adventure, item::Int)
    value = game.world.items[item]
    isempty(value.details) ? println("You see nothing special about the $(value.name).") : foreach(println, value.details)
    value.light && println("It is $(game.state.lit[item] ? "lit" : "unlit") (fuel $(game.state.fuel[item])).")
    if value.capacity > 0
        state = game.state.containers[item]
        if state != OPEN
            println("It is $(lowercase(string(state))).")
        elseif isempty(direct(game, inside(item)))
            println("It is empty.")
        else
            println("It contains:"); item_tree(game, inside(item), 1)
        end
    end
    value.treasure > 0 && println("It is a treasure worth $(value.treasure) points.")
    println("It weighs $(total_weight(game, item)).")
end

function execute!(game::Adventure, verb::Verb, first::Vector{String}, second::Vector{String}, d::Int)
    baseline = is_lit(game)
    success = true
    if verb == GO
        exit = game.state.exits[game.state.room, d]
        exit === nothing && fail("You can't go that way.")
        exit.locked && fail("The way $(DIRECTIONS[d]) is locked.")
        game.state.room = exit.destination
        baseline = is_lit(game)
        describe(game, game.verbose || !game.state.visited[game.state.room])
        game.state.visited[game.state.room] = true
        run_rules!(game, Trigger(ENTER_ROOM, game.state.room, 0))
    elseif verb == LOOK
        describe(game, true)
    elseif verb == EXAMINE
        examine(game, resolve!(game, first))
    elseif verb == TAKE
        success = take_items!(game, first, second)
    elseif verb == DROP
        drop_items!(game, first)
    elseif verb == PUT
        success = put_items!(game, first, second)
    elseif verb == INVENTORY
        if isempty(direct(game, PLAYER))
            println("You are empty-handed.")
        else
            println("You are carrying:"); item_tree(game, PLAYER, 1)
            println("Total weight: $(place_weight(game, PLAYER))/$(game.world.max_weight)")
        end
    elseif verb == OPEN_ITEM
        item = resolve!(game, first)
        name = game.world.items[item].name
        game.world.items[item].capacity > 0 || fail("You can't open the $name.")
        game.state.containers[item] == OPEN && fail("The $name is already open.")
        game.state.containers[item] == LOCKED && fail("The $name is locked.")
        game.state.containers[item] = OPEN
        children = direct(game, inside(item))
        println(isempty(children) ? "Opened." : "Opening the $name reveals $(item_names(game, children)).")
    elseif verb == CLOSE_ITEM
        item = resolve!(game, first)
        name = game.world.items[item].name
        game.world.items[item].capacity > 0 || fail("You can't close the $name.")
        game.state.containers[item] == OPEN || fail("The $name is already closed.")
        game.state.containers[item] = CLOSED
        println("Closed.")
    elseif verb in (UNLOCK, LOCK)
        change_lock!(game, first, second, verb == LOCK)
    elseif verb == USE
        a = resolve!(game, first)
        b = resolve!(game, second)
        carried(game, a) || fail("You aren't carrying the $(game.world.items[a].name).")
        result = run_rules!(game, Trigger(USE_ITEMS, a, b))
        result.executed > 0 || fail("Nothing happens.")
        result.message || println("Done.")
    elseif verb in (LIGHT, EXTINGUISH)
        item = resolve!(game, first)
        value = game.world.items[item]
        lighting = verb == LIGHT
        value.light || fail("You can't $(canonical(verb)) the $(value.name).")
        game.state.lit[item] == lighting && fail("The $(value.name) is $(lighting ? "already lit" : "not lit").")
        lighting && game.state.fuel[item] == 0 && fail("The $(value.name) has no fuel.")
        game.state.lit[item] = lighting
        println("The $(value.name) is now $(lighting ? "lit" : "out").")
    elseif verb == WAIT
        println("Time passes.")
    elseif verb == SCORE
        treasure = treasures(game)
        println("You have scored $(treasure.points + game.state.bonus) points (treasure $(treasure.points), bonus $(game.state.bonus)) in $(game.state.moves) moves.")
        println("Treasures stored: $(treasure.stored) of $(treasure.total).")
    elseif verb == SAVE
        game.saved = copy(game.state)
        println("Game saved.")
    elseif verb == RESTORE
        game.saved === nothing && fail("There is no saved game.")
        game.state = copy(game.saved)
        println("Game restored."); describe(game, true)
    elseif verb == VERBOSE
        game.verbose = true; println("Verbose mode.")
    elseif verb == BRIEF
        game.verbose = false; println("Brief mode.")
    end
    success && verb in ACTIONS && pass_turn!(game, baseline)
    nothing
end
function interpret!(game::Adventure, tokens::Vector{String})
    isempty(tokens) && fail("I beg your pardon?")
    direction(tokens[1]) != 0 && pushfirst!(tokens, "go")
    verb = get(VERBS, tokens[1], nothing)
    verb === nothing && fail("I don't know the verb \"$(tokens[1])\".")
    game.state.ended != PLAYING && verb != RESTORE && fail("The game is over.")
    first, second = tokens[2:end], String[]
    d = 0
    if verb == LOOK && !isempty(first)
        first[1] == "at" || fail("I don't understand that.")
        verb = EXAMINE; first = first[2:end]
    end
    if verb in NO_ARGUMENTS
        isempty(first) || fail("I don't understand that.")
    else
        isempty(first) && fail(verb == GO ? "Which way do you want to go?" : "What do you want to $(canonical(verb))?")
        if verb == GO
            length(first) == 1 && (d = direction(first[1]))
            d == 0 && fail("I don't understand that.")
        else
            prepositions = verb == PUT ? ("in", "into") : verb == USE ? ("on", "with") :
                           verb in (UNLOCK, LOCK) ? ("with",) : verb == TAKE ? ("from",) : ()
            split = findfirst(word -> word in prepositions, first)
            if split !== nothing
                (split == 1 || split == length(first)) && fail("I don't understand that.")
                second, first = first[split+1:end], first[1:split-1]
            elseif verb in (PUT, USE)
                fail("I don't understand that.")
            end
        end
    end
    execute!(game, verb, first, second, d)
end
function process_line!(game::Adventure, line::String)
    println("> ", line)
    try
        tokens = command_words(line)
        if !isempty(tokens) && tokens[1] in ("again", "g")
            length(tokens) == 1 || fail("I don't understand that.")
            game.previous === nothing && fail("There is nothing to repeat.")
            tokens = command_words(game.previous)
        else
            game.previous = line
        end
        interpret!(game, tokens)
    catch error
        error isa CommandError || rethrow()
        println(error.message)
    end
end

function main()
    definitions = Vector{String}[]
    for line in eachline(stdin)
        line == "BEGIN" && break
        push!(definitions, String.(split(line, ' ')))
    end
    game = Adventure(definitions)
    describe(game, true)
    for line in eachline(stdin)
        line == "QUIT" && break
        process_line!(game, line)
    end
    println("Final score: $(score(game)) points in $(game.state.moves) moves.")
end
main()
