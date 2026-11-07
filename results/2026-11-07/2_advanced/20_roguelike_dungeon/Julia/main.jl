include("minstd.jl")
include("combat.jl")
include("entities.jl")
include("dungeon_gen.jl")
include("fov.jl")

struct Config
    generation_seed::Int
    game_seed::Int
    width::Int
    height::Int
    min_size::Int
    max_split::Int
    room_min::Int
    room_max::Int
    levels::Int
    monster_base::Int
    monster_step::Int
    item_base::Int
    item_step::Int
    sleep_chance::Int
    wake_chance::Int
    radius::Int
    max_hp::Int
    regen_interval::Int
    hit_die::Dice
    food_start::Int
    food_max::Int
    food_hungry::Int
    food_weak::Int
    pack_limit::Int
    start_items::Vector{String}
    xp_levels::Vector{Int}
    checkpoints::Set{Int}
end
read_rows(name::String) = [String.(split(line, ' ')) for line in readlines(joinpath("input", name))]
function Config(rows::Vector{Vector{String}})
    entries = Dict(row[1] => row[2:end] for row in rows)
    integer(key, position) = parse(Int, entries[key][position])
    Config(integer("seed", 1), integer("seed", 2), integer("map", 1), integer("map", 2), integer("bsp", 1), integer("bsp", 2),
        integer("room", 1), integer("room", 2), integer("levels", 1), integer("monsters", 1), integer("monsters", 2),
        integer("items", 1), integer("items", 2), integer("sleep", 1), integer("sleep", 2), integer("fov", 1),
        integer("player", 1), integer("player", 2), Dice(entries["hitdie"][1]), integer("food", 1), integer("food", 2),
        integer("food", 3), integer("food", 4), integer("pack", 1), entries["start"], parse.(Int, entries["xp"]), Set(parse.(Int, entries["checkpoints"])))
end
struct Command
    kind::Symbol
    dx::Int
    dy::Int
    number::Int
end
function expand_commands(rows::Vector{Vector{String}})
    commands = Command[]
    for words in rows
        if words[1] == "move"
            direction = findfirst(==(words[2]), DIRECTION_NAMES)
            dx, dy = DIRECTIONS[direction]
            command = Command(:move, dx, dy, 0)
            count = length(words) > 2 ? parse(Int, words[3]) : 1
        elseif words[1] == "wait"
            command = Command(:wait, 0, 0, 0)
            count = length(words) > 1 ? parse(Int, words[2]) : 1
        elseif words[1] in ("pickup", "descend")
            command = Command(Symbol(words[1]), 0, 0, 0)
            count = 1
        else
            command = Command(Symbol(words[1]), 0, 0, parse(Int, words[2]))
            count = 1
        end
        append!(commands, fill(command, count))
    end
    commands
end
function decimal_one(numerator::Int, denominator::Int)
    denominator == 0 && return "-"
    rounded = (20 * numerator + denominator) ÷ (2 * denominator)
    "$(rounded ÷ 10).$(rounded % 10)"
end
function exploration(level::Level)
    explored = 0
    total = 0
    for y in 1:level.height, x in 1:level.width
        level.terrain[y, x] == ' ' && continue
        total += 1
        level.memory[y, x] != ' ' && (explored += 1)
    end
    (explored, total)
end
mutable struct Player
    x::Int
    y::Int
    depth::Int
    hp::Int
    max_hp::Int
    level::Int
    xp::Int
    gold::Int
    food::Int
    poison::Int
    pack::Vector{Item}
    weapon::Union{Nothing,Item}
    armor::Union{Nothing,Item}
end
function defense(player::Player, types::Vector{ItemType})
    isnothing(player.armor) && return 10
    armor = player.armor
    category = types[armor.kind].category::ArmorType
    10 + category.defense + armor.bonus
end
mutable struct AttackStats
    count::Int
    hits::Int
    criticals::Int
    damage::Int
end
AttackStats() = AttackStats(0, 0, 0, 0)
function record_attack!(stats::AttackStats, outcome::AttackOutcome, damage::Int)
    stats.count += 1
    if outcome != attack_miss
        stats.hits += 1
        stats.damage += damage
    end
    outcome == attack_critical && (stats.criticals += 1)
end
function attack_line(stats::AttackStats, label::String)
    "$label $(stats.count) hits $(stats.hits) criticals $(stats.criticals) damage $(stats.damage) accuracy $(decimal_one(100 * stats.hits, stats.count))"
end
mutable struct Game
    config::Config
    monster_types::Vector{MonsterType}
    item_types::Vector{ItemType}
    commands::Vector{Command}
    generator::Minstd
    levels::Vector{Level}
    player::Player
    turn::Int
    messages::Vector{String}
    map_lines::Vector{String}
    visible::BitMatrix
    distance::Matrix{Int}
    result::Union{Nothing,String}
    cause::String
    succeeded::Int
    failed::Int
    unused::Int
    moves::Int
    player_attacks::AttackStats
    monster_attacks::AttackStats
    poison_damage::Int
    starvation_damage::Int
    usage::Vector{Int}
    kills::Vector{Int}
end
current_level(game::Game) = game.levels[game.player.depth]
function place_monsters!(level::Level, types::Vector{MonsterType}, config::Config, generator::Minstd)
    candidates = [index for index in eachindex(types) if types[index].min_depth <= level.depth <= types[index].max_depth]
    weights = [types[index].weight for index in candidates]
    count = config.monster_base + config.monster_step * (level.depth - 1)
    for number in 1:count
        kind = candidates[weighted_index!(generator, weights)]
        local cell::Cell
        while true
            room, cell = draw_room_cell!(generator, level)
            if room != level.arrival_room && level.terrain[cell.y + 1, cell.x + 1] == '.' && isnothing(monster_at(level, cell.x, cell.y))
                break
            end
        end
        hp = roll!(generator, types[kind].hp)
        asleep = draw!(generator) % 100 < config.sleep_chance
        push!(level.monsters, Monster(number, kind, cell.x, cell.y, hp, hp, asleep, 0, false))
    end
    level.monsters_created = count
end
function place_items!(level::Level, types::Vector{ItemType}, config::Config, generator::Minstd)
    candidates = [index for index in eachindex(types) if types[index].min_depth <= level.depth <= types[index].max_depth]
    weights = [types[index].weight for index in candidates]
    count = config.item_base + config.item_step * (level.depth - 1)
    for _ in 1:count
        kind = candidates[weighted_index!(generator, weights)]
        local cell::Cell
        while true
            _, cell = draw_room_cell!(generator, level)
            if level.terrain[cell.y + 1, cell.x + 1] == '.' && isnothing(item_at(level, cell.x, cell.y))
                break
            end
        end
        category = types[kind].category
        amount = category isa GoldType ? roll!(generator, category.dice) : 0
        push!(level.items, Item(kind, cell.x, cell.y, amount))
    end
    level.items_placed = length(level.items)
end
function Game(config::Config, monster_types::Vector{MonsterType}, original_items::Vector{ItemType}, commands::Vector{Command})
    original_names = Dict(kind.name => number for (number, kind) in enumerate(original_items))
    amulet = length(original_items) + 1
    item_types = vcat(original_items, [ItemType("amulet", 0, 0, 0, AmuletType())])
    generation = Minstd(config.generation_seed)
    builder = LevelGenerator(config.min_size, config.max_split, config.room_min, config.room_max)
    levels = Level[]
    for depth in 1:config.levels
        level = generate_level!(builder, generation, depth, config.width, config.height)
        point = level.target
        if depth < config.levels
            level.terrain[point.y + 1, point.x + 1] = '>'
        else
            push!(level.items, Item(amulet, point.x, point.y))
        end
        place_monsters!(level, monster_types, config, generation)
        place_items!(level, item_types, config, generation)
        push!(levels, level)
    end
    point = levels[1].arrival
    player = Player(point.x, point.y, 1, config.max_hp, config.max_hp, 1, 0, 0, config.food_start, 0, Item[], nothing, nothing)
    for name in config.start_items
        kind = original_names[name]
        item = Item(kind, point.x, point.y)
        push!(player.pack, item)
        if item_types[kind].category isa WeaponType && isnothing(player.weapon)
            player.weapon = item
        end
        if item_types[kind].category isa ArmorType && isnothing(player.armor)
            player.armor = item
        end
    end
    Game(config, monster_types, item_types, commands, Minstd(config.game_seed), levels, player, 1, String[], String[],
        falses(config.height, config.width), Matrix{Int}(undef, 0, 0), nothing, "", 0, 0, 0, 0, AttackStats(), AttackStats(), 0, 0, zeros(Int, 6), zeros(Int, length(monster_types)))
end
function say!(game::Game, text::String)
    push!(game.messages, lpad(string(game.turn), 4, '0') * " " * text)
end
function hunger_state(game::Game)
    food = game.player.food
    food > game.config.food_hungry && return "normal"
    food > game.config.food_weak && return "hungry"
    food > 0 ? "weak" : "starving"
end
function die!(game::Game, cause::String)
    say!(game, "You die.")
    game.result = "died"
    game.cause = cause
end
function update_view!(game::Game)
    level = current_level(game)
    player = game.player
    game.visible = field_of_view(level, player.x, player.y, game.config.radius)
    for y in 0:(level.height - 1), x in 0:(level.width - 1)
        game.visible[y + 1, x + 1] || continue
        number = item_at(level, x, y)
        level.memory[y + 1, x + 1] = isnothing(number) ? level.terrain[y + 1, x + 1] : item_symbol(game.item_types[level.items[number].kind].category)
    end
    for monster in level.monsters
        seen = game.visible[monster.y + 1, monster.x + 1]
        seen && !monster.was_visible && say!(game, "You see the $(game.monster_types[monster.kind].name).")
        monster.was_visible = seen
    end
end
function run_game!(game::Game)
    update_view!(game)
    for command in game.commands
        if !isnothing(game.result)
            game.unused += 1
            continue
        end
        if !execute!(game, command)
            game.failed += 1
            continue
        end
        game.succeeded += 1
        isnothing(game.result) && advance_turn!(game)
    end
    if isnothing(game.result)
        game.result = "alive"
        game.cause = "commands_exhausted"
    end
end
function advance_turn!(game::Game)
    update_view!(game)
    level = current_level(game)
    game.distance = distances(level, game.player.x, game.player.y)
    for monster in level.monsters
        monster.energy += game.monster_types[monster.kind].speed
        while monster.energy >= 2
            monster.energy -= 2
            monster_action!(game, monster)
            !isnothing(game.result) && return
        end
    end
    end_turn!(game)
    !isnothing(game.result) && return
    if game.turn in game.config.checkpoints
        push!(game.map_lines, "CHECKPOINT turn $(game.turn) depth $(game.player.depth)")
        append!(game.map_lines, map_rows(game, level, true))
        push!(game.map_lines, status_line(game))
    end
    game.turn += 1
end
function execute!(game::Game, command::Command)
    command.kind == :move && return move_player!(game, command.dx, command.dy)
    command.kind == :wait && return true
    command.kind == :pickup && return pickup!(game)
    command.kind == :descend && return descend!(game)
    use_item!(game, command.kind, command.number)
end
function move_player!(game::Game, dx::Int, dy::Int)
    level = current_level(game)
    player = game.player
    x, y = player.x + dx, player.y + dy
    if !passable(level, x, y)
        say!(game, "You bump into a wall.")
        return false
    end
    if !can_move(level, player.x, player.y, dx, dy)
        say!(game, "You cannot move diagonally through a door.")
        return false
    end
    number = monster_at(level, x, y)
    if !isnothing(number)
        player_attack!(game, level.monsters[number])
        return true
    end
    player.x, player.y = x, y
    game.moves += 1
    number = item_at(level, x, y)
    if !isnothing(number)
        say!(game, "You see $(reference_name(level.items[number], game.item_types)) here.")
    elseif level.terrain[y + 1, x + 1] == '>'
        say!(game, "There is a staircase down here.")
    end
    true
end
function pickup!(game::Game)
    level = current_level(game)
    player = game.player
    number = item_at(level, player.x, player.y)
    if isnothing(number)
        say!(game, "There is nothing here.")
        return false
    end
    item = level.items[number]
    name = display_name(item, game.item_types)
    category = game.item_types[item.kind].category
    if category isa GoldType
        player.gold += item.amount
        say!(game, "You pick up $name.")
    elseif category isa AmuletType
        say!(game, "You pick up the amulet.")
        say!(game, "You win!")
        game.result = "won"
        game.cause = "amulet"
    else
        if length(player.pack) >= game.config.pack_limit
            say!(game, "Your pack is full.")
            return false
        end
        push!(player.pack, item)
        say!(game, "You pick up the $name ($(length(player.pack))).")
    end
    deleteat!(level.items, number)
    level.picked += 1
    game.usage[1] += 1
    true
end
function descend!(game::Game)
    player = game.player
    if current_level(game).terrain[player.y + 1, player.x + 1] != '>'
        say!(game, "There are no stairs here.")
        return false
    end
    player.depth += 1
    point = current_level(game).arrival
    player.x, player.y = point.x, point.y
    say!(game, "You descend to depth $(player.depth).")
    true
end
function accepts(action::Symbol, category::ItemCategory)
    action == :quaff && return category isa PotionType
    action == :read && return category isa ScrollType
    action == :wield && return category isa WeaponType
    action == :wear && return category isa ArmorType
    action == :eat && return category isa FoodType
    false
end
function use_item!(game::Game, action::Symbol, number::Int)
    player = game.player
    if number > length(player.pack)
        say!(game, "You do not have that item.")
        return false
    end
    item = player.pack[number]
    category = game.item_types[item.kind].category
    if !accepts(action, category)
        say!(game, "You cannot $action that.")
        return false
    end
    if action == :wield
        if player.weapon === item
            say!(game, "You are already wielding that.")
            return false
        end
        player.weapon = item
        game.usage[5] += 1
        say!(game, "You are now wielding the $(display_name(item, game.item_types)).")
    elseif action == :wear
        if player.armor === item
            say!(game, "You are already wearing that.")
            return false
        end
        player.armor = item
        game.usage[6] += 1
        say!(game, "You are now wearing the $(display_name(item, game.item_types)).")
    elseif action == :quaff
        deleteat!(player.pack, number)
        game.usage[2] += 1
        say!(game, "You quaff the $(display_name(item, game.item_types)).")
        effect = (category::PotionType).effect
        if effect isa HealEffect
            player.hp += roll!(game.generator, effect.dice)
            if player.hp > player.max_hp
                player.max_hp += 1
                player.hp = player.max_hp
            end
            player.poison = 0
            say!(game, "You feel better.")
        elseif effect isa PoisonEffect
            player.poison += effect.turns
            say!(game, "You feel very sick.")
        else
            say!(game, "You feel more experienced.")
            player.level <= length(game.config.xp_levels) && gain_xp!(game, game.config.xp_levels[player.level] - player.xp)
        end
    elseif action == :read
        deleteat!(player.pack, number)
        game.usage[3] += 1
        say!(game, "You read the $(display_name(item, game.item_types)).")
        read_scroll!(game, (category::ScrollType).effect)
    else
        deleteat!(player.pack, number)
        game.usage[4] += 1
        player.food = min(game.config.food_max, player.food + (category::FoodType).nutrition)
        say!(game, "You eat the $(display_name(item, game.item_types)).")
    end
    true
end
function read_scroll!(game::Game, effect::ScrollEffect)
    level = current_level(game)
    player = game.player
    if effect == mapping_scroll
        for y in 1:level.height, x in 1:level.width
            if level.terrain[y, x] != ' ' && level.memory[y, x] == ' '
                level.memory[y, x] = level.terrain[y, x]
            end
        end
        say!(game, "A map forms in your mind.")
    elseif effect == teleport_scroll
        while true
            _, point = draw_room_cell!(game.generator, level)
            if (point.x != player.x || point.y != player.y) && isnothing(monster_at(level, point.x, point.y))
                player.x, player.y = point.x, point.y
                break
            end
        end
        say!(game, "You are teleported.")
    elseif effect == weapon_scroll
        if isnothing(player.weapon)
            say!(game, "Your hands twitch.")
        else
            say!(game, "Your $(display_name(player.weapon, game.item_types)) glows blue.")
            player.weapon.bonus += 1
        end
    else
        if isnothing(player.armor)
            say!(game, "Your skin tingles.")
        else
            say!(game, "Your $(display_name(player.armor, game.item_types)) glows silver.")
            player.armor.bonus += 1
        end
    end
end
function player_attack!(game::Game, monster::Monster)
    player = game.player
    monster.asleep = false
    kind = game.monster_types[monster.kind]
    to_hit = player.level
    dice = Dice(1, 2)
    bonus = 0
    if !isnothing(player.weapon)
        weapon = player.weapon
        category = game.item_types[weapon.kind].category::WeaponType
        to_hit += category.to_hit + weapon.bonus
        dice = category.damage
        bonus = weapon.bonus
    end
    hunger_state(game) in ("weak", "starving") && (to_hit -= 2)
    outcome, damage = resolve_attack!(game.generator, to_hit, kind.defense, dice, bonus)
    record_attack!(game.player_attacks, outcome, damage)
    if outcome == attack_miss
        say!(game, "You miss the $(kind.name).")
        return
    end
    hard = outcome == attack_critical ? " hard" : ""
    say!(game, "You hit the $(kind.name)$hard for $damage.")
    monster.hp -= damage
    if monster.hp <= 0
        say!(game, "You kill the $(kind.name).")
        level = current_level(game)
        filter!(other -> other !== monster, level.monsters)
        level.kills += 1
        game.kills[monster.kind] += 1
        gain_xp!(game, kind.xp)
    end
end
function gain_xp!(game::Game, amount::Int)
    player = game.player
    player.xp += amount
    while player.level <= length(game.config.xp_levels) && player.xp >= game.config.xp_levels[player.level]
        player.level += 1
        gained = roll!(game.generator, game.config.hit_die)
        player.max_hp += gained
        player.hp += gained
        say!(game, "Welcome to level $(player.level).")
    end
end
function monster_attack!(game::Game, monster::Monster)
    kind = game.monster_types[monster.kind]
    player = game.player
    outcome, damage = resolve_attack!(game.generator, kind.to_hit, defense(player, game.item_types), kind.damage, 0)
    record_attack!(game.monster_attacks, outcome, damage)
    if outcome == attack_miss
        say!(game, "The $(kind.name) misses you.")
        return
    end
    hard = outcome == attack_critical ? " hard" : ""
    say!(game, "The $(kind.name) hits you$hard for $damage.")
    player.hp -= damage
    if player.hp <= 0
        die!(game, "killed_by $(kind.name)")
    elseif kind.poisonous
        player.poison += 5
        say!(game, "You are poisoned.")
    end
end
function can_attack(game::Game, monster::Monster)
    dx = game.player.x - monster.x
    dy = game.player.y - monster.y
    max(abs(dx), abs(dy)) == 1 && can_move(current_level(game), monster.x, monster.y, dx, dy)
end
function monster_action!(game::Game, monster::Monster)
    kind = game.monster_types[monster.kind]
    sees = game.visible[monster.y + 1, monster.x + 1]
    if monster.asleep
        if sees && draw!(game.generator) % 100 < game.config.wake_chance
            monster.asleep = false
            say!(game, "The $(kind.name) wakes up.")
        end
    elseif kind.stationary
        can_attack(game, monster) && monster_attack!(game, monster)
    elseif kind.erratic && iseven(draw!(game.generator))
        wander!(game, monster)
    elseif sees
        chase!(game, monster)
    else
        wander!(game, monster)
    end
end
function wander!(game::Game, monster::Monster)
    level = current_level(game)
    dx, dy = DIRECTIONS[1 + random_index!(game.generator, 8)]
    can_move(level, monster.x, monster.y, dx, dy) || return
    x, y = monster.x + dx, monster.y + dy
    if x == game.player.x && y == game.player.y
        monster_attack!(game, monster)
    elseif isnothing(monster_at(level, x, y))
        monster.x, monster.y = x, y
    end
end
function chase!(game::Game, monster::Monster)
    if can_attack(game, monster)
        monster_attack!(game, monster)
        return
    end
    level = current_level(game)
    here = game.distance[monster.y + 1, monster.x + 1]
    best = nothing
    for (dx, dy) in DIRECTIONS
        can_move(level, monster.x, monster.y, dx, dy) || continue
        x, y = monster.x + dx, monster.y + dy
        distance = game.distance[y + 1, x + 1]
        distance < 0 && continue
        here >= 0 && distance >= here && continue
        !isnothing(monster_at(level, x, y)) && continue
        x == game.player.x && y == game.player.y && continue
        if isnothing(best) || distance < best[1]
            best = (distance, x, y)
        end
    end
    if !isnothing(best)
        monster.x, monster.y = best[2], best[3]
    end
end
function end_turn!(game::Game)
    player = game.player
    for monster in current_level(game).monsters
        game.monster_types[monster.kind].regenerates && monster.hp < monster.max_hp && (monster.hp += 1)
    end
    if player.poison > 0
        player.hp -= 1
        game.poison_damage += 1
        if player.hp <= 0
            die!(game, "poison")
            return
        end
        player.poison -= 1
        player.poison == 0 && say!(game, "You feel less sick.")
    end
    if player.food == 0
        player.hp -= 1
        game.starvation_damage += 1
        if player.hp <= 0
            die!(game, "starvation")
            return
        end
    else
        before = hunger_state(game)
        player.food -= 1
        after = hunger_state(game)
        if before != after
            messages = Dict("hungry" => "You are getting hungry.", "weak" => "You feel weak from hunger.", "starving" => "You are starving.")
            say!(game, messages[after])
        end
    end
    if game.turn % game.config.regen_interval == 0 && player.poison == 0 && player.food > 0 && player.hp < player.max_hp
        player.hp += 1
    end
end
function map_rows(game::Game, level::Level, current::Bool)
    border = "+" * repeat("-", level.width) * "+"
    rows = [border]
    for y in 0:(level.height - 1)
        row = Char['|']
        for x in 0:(level.width - 1)
            symbol = if !current || !game.visible[y + 1, x + 1]
                level.memory[y + 1, x + 1]
            elseif x == game.player.x && y == game.player.y
                '@'
            else
                monster = monster_at(level, x, y)
                item = item_at(level, x, y)
                if !isnothing(monster)
                    game.monster_types[level.monsters[monster].kind].symbol
                elseif !isnothing(item)
                    item_symbol(game.item_types[level.items[item].kind].category)
                else
                    level.terrain[y + 1, x + 1]
                end
            end
            push!(row, symbol)
        end
        push!(row, '|')
        push!(rows, join(row))
    end
    push!(rows, border)
    rows
end
function status_line(game::Game)
    p = game.player
    "STATUS hp $(p.hp)/$(p.max_hp) level $(p.level) xp $(p.xp) defense $(defense(p, game.item_types)) gold $(p.gold) food $(p.food) $(hunger_state(game)) poison $(p.poison)"
end
function final_block(game::Game)
    lines = ["FINAL turn $(game.succeeded) depth $(game.player.depth)"]
    for level in game.levels[1:game.player.depth]
        explored, total = exploration(level)
        push!(lines, "LEVEL $(level.depth) explored $explored/$total")
        append!(lines, map_rows(game, level, level.depth == game.player.depth))
    end
    push!(lines, status_line(game))
    lines
end
item_label(item::Nothing, types::Vector{ItemType}) = "-"
item_label(item::Item, types::Vector{ItemType}) = display_name(item, types)
function stats_lines(game::Game)
    p = game.player
    lines = ["result $(game.result)", "cause $(game.cause)", "turns $(game.succeeded)", "depth $(p.depth)", "level $(p.level)", "xp $(p.xp)",
        "hp $(p.hp)/$(p.max_hp)", "defense $(defense(p, game.item_types))", "gold $(p.gold)", "food $(p.food) $(hunger_state(game))", "poison $(p.poison)",
        "weapon $(item_label(p.weapon, game.item_types))", "armor $(item_label(p.armor, game.item_types))",
        "commands $(length(game.commands)) executed $(game.succeeded) failed $(game.failed) unused $(game.unused)", "moves $(game.moves)",
        attack_line(game.player_attacks, "player_attacks"), attack_line(game.monster_attacks, "monster_attacks"),
        "poison_damage $(game.poison_damage) starvation_damage $(game.starvation_damage)",
        "picked $(game.usage[1]) quaffed $(game.usage[2]) read $(game.usage[3]) eaten $(game.usage[4]) wielded $(game.usage[5]) worn $(game.usage[6])", "kills $(sum(game.kills))"]
    for index in eachindex(game.monster_types)
        game.kills[index] > 0 && push!(lines, "KILL $(game.monster_types[index].name) $(game.kills[index])")
    end
    for level in game.levels
        explored, total = exploration(level)
        push!(lines, "LEVEL $(level.depth) rooms $(length(level.rooms)) explored $explored/$total $(decimal_one(100 * explored, total)) monsters $(level.kills)/$(level.monsters_created) items $(level.picked)/$(level.items_placed)")
    end
    for (number, item) in enumerate(p.pack)
        marker = item === p.weapon ? " (wielded)" : (item === p.armor ? " (worn)" : "")
        push!(lines, "INVENTORY $number $(display_name(item, game.item_types))$marker")
    end
    lines
end
function main()
    config = Config(read_rows("config.txt"))
    monster_types = MonsterType.(read_rows("monsters.txt"))
    item_types = ItemType.(read_rows("items.txt"))
    commands = expand_commands(read_rows("commands.txt"))
    game = Game(config, monster_types, item_types, commands)
    run_game!(game)
    mkpath("output")
    files = [("messages.txt", game.messages), ("maps.txt", vcat(game.map_lines, final_block(game))), ("stats.txt", stats_lines(game))]
    for (name, lines) in files
        write(joinpath("output", name), isempty(lines) ? "" : join(lines, '\n') * "\n")
    end
end

main()
