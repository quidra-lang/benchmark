include("grid_map.jl")
include("pathing.jl")
include("combat.jl")
include("enemies.jl")
include("towers.jl")

const WAVE_COLUMNS = "wave,start,end,status,spawned,peak,kills,leaks,lives_lost,bounty,reward,interest,gold,lives"
read_lines(name::String) = readlines(joinpath("input", name))
write_lines(name::String, lines::Vector{String}) = write(joinpath("output", name), isempty(lines) ? "" : join(lines, '\n') * "\n")
function one_decimal(numerator::Int, denominator::Int)
    denominator == 0 && return "-"
    rounded = (20 * numerator + denominator) ÷ (2 * denominator)
    "$(rounded ÷ 10).$(rounded % 10)"
end
digit(value::Int) = value == 0 ? UInt8('.') : value <= 9 ? UInt8('0') + UInt8(value) : UInt8('*')
function ruled(rows::Vector{Vector{UInt8}})
    lines = ["  " * join([string(x % 10) for x in 0:(length(rows[1]) - 1)])]
    for (y, row) in enumerate(rows)
        push!(lines, "$(mod(y - 1, 10)) " * String(copy(row)))
    end
    lines
end
struct Params
    gold::Int
    lives::Int
    interest_rate::Int
    interest_cap::Int
    sell_rate::Int
    start::Int
    interval::Int
    early::Int
    snapshots::Set{Int}
end
function Params(lines::Vector{String})
    values = [parse.(Int, split(line, ' ')[2:end]) for line in lines]
    Params(values[1][1], values[2][1], values[3][1], values[3][2], values[4][1], values[5][1], values[5][2], values[6][1], Set(values[7]))
end
abstract type GameCommand end
struct BuildCommand <: GameCommand
    name::String
    cell::Cell
end
struct UpgradeCommand <: GameCommand
    number::Int
end
struct SellCommand <: GameCommand
    number::Int
end
struct TargetCommand <: GameCommand
    number::Int
    mode::String
end
struct CallCommand <: GameCommand end
struct Action
    tick::Int
    command::GameCommand
end
function parse_action(line::String)
    fields = String.(split(line, ' '))
    command = if fields[2] == "BUILD"
        BuildCommand(fields[3], (parse(Int, fields[4]), parse(Int, fields[5])))
    elseif fields[2] == "UPGRADE"
        UpgradeCommand(parse(Int, fields[3]))
    elseif fields[2] == "SELL"
        SellCommand(parse(Int, fields[3]))
    elseif fields[2] == "TARGET"
        TargetCommand(parse(Int, fields[3]), fields[4])
    else
        CallCommand()
    end
    Action(parse(Int, fields[1]), command)
end
@enum WaveStatus WaveActive WaveCleared WaveLost
wave_status_text(status::WaveStatus) = status == WaveCleared ? "cleared" : status == WaveLost ? "lost" : "active"
mutable struct WaveRecord
    number::Int
    start::Int
    end_tick::Int
    status::WaveStatus
    released::Vector{Int}
    spawned::Int
    peak::Int
    kills::Int
    leaks::Int
    lives_lost::Int
    bounty::Int
    reward::Int
    interest::Int
    gold::Int
    lives::Int
    tower_damage::Dict{Int,Int}
end
WaveRecord(number::Int, start::Int, group_count::Int) = WaveRecord(number, start, 0, WaveActive, zeros(Int, group_count), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, Dict{Int,Int}())
function close_wave!(wave::WaveRecord, status::WaveStatus, tick::Int, gold::Int, lives::Int)
    wave.status, wave.end_tick, wave.gold, wave.lives = status, tick, gold, lives
end
function wave_csv_row(wave::WaveRecord, tower_count::Int)
    fields = [string(wave.number), string(wave.start), string(wave.end_tick), wave_status_text(wave.status), string(wave.spawned), string(wave.peak),
        string(wave.kills), string(wave.leaks), string(wave.lives_lost), string(wave.bounty), string(wave.reward), string(wave.interest), string(wave.gold), string(wave.lives)]
    append!(fields, [string(get(wave.tower_damage, number, 0)) for number in 1:tower_count])
    join(fields, ',')
end
@enum Outcome Victory Defeat
outcome_text(outcome::Outcome) = outcome == Victory ? "victory" : "defeat"
mutable struct Income
    bounty::Int
    reward::Int
    interest::Int
    early::Int
    refund::Int
end
Income() = Income(0, 0, 0, 0, 0)
mutable struct Game
    grid::GridMap
    tower_types::Vector{TowerType}
    enemy_types::Vector{EnemyType}
    waves::Vector{Wave}
    params::Params
    tick::Int
    gold::Int
    lives::Int
    towers::Vector{Tower}
    enemies::Vector{Enemy}
    projectiles::Vector{Projectile{Targets,Level}}
    projectile_count::Int
    records::Vector{WaveRecord}
    active::Union{Nothing,Int}
    next_start::Union{Nothing,Int}
    outcome::Union{Nothing,Outcome}
    field::DistanceField
    kill_counts::Matrix{Int}
    income::Income
    spent::Int
    done::Int
    refused::Int
    events::Vector{String}
    snapshots::Vector{String}
end
function Game(grid::GridMap, tower_types::Vector{TowerType}, enemy_types::Vector{EnemyType}, waves::Vector{Wave}, params::Params)
    field = DistanceField(grid, Set{Cell}())
    Game(grid, tower_types, enemy_types, waves, params, 0, params.gold, params.lives, Tower[], Enemy[], Projectile{Targets,Level}[], 0,
        WaveRecord[], nothing, params.start, nothing, field, zeros(Int, grid.height, grid.width), Income(), 0, 0, 0, String[], String[])
end
record!(game::Game, body::String) = push!(game.events, "$(game.tick) " * body)
function run!(game::Game, actions::Vector{Action})
    index = 1
    while true
        game.tick += 1
        while index <= length(actions) && actions[index].tick == game.tick
            perform!(game, actions[index])
            index += 1
        end
        spawn_enemies!(game)
        move_enemies!(game)
        game.outcome === nothing || break
        fire_towers!(game)
        move_projectiles!(game)
        check_wave_end!(game)
        game.tick in game.params.snapshots && append!(game.snapshots, snapshot_block(game, "SNAPSHOT"))
        game.outcome === nothing || break
    end
    append!(game.snapshots, final_block(game))
end
tower_cells(game::Game) = Set{Cell}(tower.cell for tower in game.towers if standing(tower))
function tower_at(game::Game, cell::Cell)
    index = findfirst(tower -> standing(tower) && tower.cell == cell, game.towers)
    index === nothing ? nothing : game.towers[index]
end
standing_tower(game::Game, number::Int) = 1 <= number <= length(game.towers) && standing(game.towers[number]) ? game.towers[number] : nothing
function perform!(game::Game, action::Action)
    if execute!(game, action.command)
        game.done += 1
    else
        game.refused += 1
    end
end
execute!(game::Game, command::BuildCommand) = build!(game, command.name, command.cell)
execute!(game::Game, command::UpgradeCommand) = upgrade!(game, command.number)
execute!(game::Game, command::SellCommand) = sell!(game, command.number)
execute!(game::Game, command::TargetCommand) = set_target!(game, command.number, command.mode)
execute!(game::Game, command::CallCommand) = call_wave!(game)
function build_refusal(game::Game, name::String, cell::Cell)
    kind = findfirst(kind -> kind.name == name, game.tower_types)
    kind === nothing && return "type"
    inside(game.grid, cell) || return "bounds"
    buildable(game.grid, cell) || return "terrain"
    tower_at(game, cell) !== nothing && return "tower"
    game.gold < game.tower_types[kind].levels[1].cost && return "gold"
    for enemy in game.enemies
        if enemy.alive && enemy.position isa GroundPosition
            position = enemy.position
            (position.cell == cell || position.next_cell == cell) && return "enemy"
        end
    end
    cells = tower_cells(game)
    push!(cells, cell)
    trial = DistanceField(game.grid, cells)
    any(spawn -> distance_at(trial, spawn) === nothing, game.grid.spawns) && return "blocked"
    for enemy in game.enemies
        if enemy.alive && enemy.position isa GroundPosition && distance_at(trial, enemy.position.next_cell) === nothing
            return "blocked"
        end
    end
    nothing
end
function build!(game::Game, name::String, cell::Cell)
    reason = build_refusal(game, name, cell)
    if reason !== nothing
        record!(game, "BUILD_REFUSED $name $(cell[1]) $(cell[2]) $reason")
        return false
    end
    kind = findfirst(kind -> kind.name == name, game.tower_types)
    cost = game.tower_types[kind].levels[1].cost
    tower = Tower(length(game.towers) + 1, kind, game.tower_types, cell, game.tick)
    push!(game.towers, tower)
    game.gold -= cost
    game.spent += cost
    record!(game, "BUILD T$(tower.number) $name $(cell[1]) $(cell[2]) cost $cost gold $(game.gold)")
    update_field!(game)
    true
end
function upgrade!(game::Game, number::Int)
    tower = standing_tower(game, number)
    if tower === nothing
        record!(game, "UPGRADE_REFUSED T$number notower")
        return false
    elseif tower.level == length(game.tower_types[tower.kind].levels)
        record!(game, "UPGRADE_REFUSED T$number maxlevel")
        return false
    end
    cost = game.tower_types[tower.kind].levels[tower.level + 1].cost
    if game.gold < cost
        record!(game, "UPGRADE_REFUSED T$number gold")
        return false
    end
    game.gold -= cost
    game.spent += cost
    tower.level += 1
    tower.investment += cost
    record!(game, "UPGRADE T$number level $(tower.level) cost $cost gold $(game.gold)")
    true
end
function sell!(game::Game, number::Int)
    tower = standing_tower(game, number)
    if tower === nothing
        record!(game, "SELL_REFUSED T$number notower")
        return false
    end
    rate = game.tick == tower.built ? 100 : game.params.sell_rate
    refund = tower.investment * rate ÷ 100
    tower.sold = game.tick
    game.gold += refund
    game.income.refund += refund
    record!(game, "SELL T$number refund $refund gold $(game.gold)")
    update_field!(game)
    true
end
function set_target!(game::Game, number::Int, mode::String)
    tower = standing_tower(game, number)
    if tower === nothing
        record!(game, "TARGET_REFUSED T$number notower")
        return false
    end
    target_mode = parse_mode(mode)
    if target_mode === nothing
        record!(game, "TARGET_REFUSED T$number mode")
        return false
    end
    tower.mode = target_mode
    record!(game, "TARGET T$number $mode")
    true
end
function call_wave!(game::Game)
    if game.active !== nothing
        record!(game, "CALL_REFUSED active")
        return false
    end
    bonus = (game.next_start - game.tick) * game.params.early
    game.gold += bonus
    game.income.early += bonus
    game.next_start = game.tick
    record!(game, "CALL $(length(game.records) + 1) bonus $bonus gold $(game.gold)")
    true
end
function update_field!(game::Game)
    updated = DistanceField(game.grid, tower_cells(game))
    for (number, spawn) in enumerate(game.grid.spawns)
        old, new = distance_at(game.field, spawn), distance_at(updated, spawn)
        old != new && record!(game, "REPATH $number $old $new")
    end
    game.field = updated
end
function start_wave!(game::Game)
    number = length(game.records) + 1
    plan = game.waves[number]
    push!(game.records, WaveRecord(number, game.tick, length(plan.groups)))
    game.active = number
    game.next_start = nothing
    record!(game, "WAVE_START $number enemies $(enemy_count(plan))")
end
function add_enemy!(game::Game, enemy::Enemy)
    game.records[game.active].spawned += 1
    game.enemy_types[enemy.kind].spawned += 1
    push!(game.enemies, enemy)
end
function spawn_enemies!(game::Game)
    game.next_start == game.tick && start_wave!(game)
    game.active === nothing && return
    wave = game.records[game.active]
    for (index, group) in enumerate(game.waves[game.active].groups)
        released = wave.released[index]
        (released == group.count || spawn_tick(group, wave.start, released) != game.tick) && continue
        wave.released[index] += 1
        spawn = game.grid.spawns[group.spawn]
        position = game.enemy_types[group.kind].movement == AirMovement ? AirPosition(cell_center(spawn)) : GroundPosition(spawn, next_cell(game.field, spawn), 0)
        enemy = Enemy(length(game.enemies) + 1, group.kind, game.enemy_types, group.multiplier, position)
        add_enemy!(game, enemy)
        record!(game, "SPAWN E$(enemy.number) $(game.enemy_types[group.kind].name) $(group.spawn) hp $(enemy.hp)")
    end
    wave.peak = max(wave.peak, count(enemy -> enemy.alive, game.enemies))
end
function move_enemies!(game::Game)
    order = [index for index in eachindex(game.enemies) if game.enemies[index].alive]
    for index in order
        move_enemy!(game, game.enemies[index])
        game.outcome === nothing || return
    end
end
function move_enemy!(game::Game, enemy::Enemy)
    if effect_active(enemy.burn)
        source = game.towers[enemy.burn.source]
        damage = min(enemy.hp, enemy.burn.strength)
        enemy.hp -= damage
        credit!(game, source, enemy, damage)
        advance_time!(enemy.burn)
        if enemy.hp == 0
            kill!(game, enemy, source)
            return
        end
    end
    enemy.hp = min(enemy.hp + game.enemy_types[enemy.kind].regen, enemy.max_hp)
    speed = slowed_speed(enemy, game.enemy_types)
    effect_active(enemy.slow) && advance_time!(enemy.slow)
    if enemy.position isa AirPosition
        point, arrived = advance_point(enemy.position.point, cell_center(game.grid.exit), speed)
        enemy.position = AirPosition(point)
    else
        arrived = walk!(game, enemy, speed)
    end
    arrived && leak!(game, enemy)
end
function walk!(game::Game, enemy::Enemy, speed::Int)
    is_water(game.grid, occupied_cell(enemy)) && (speed ÷= 2)
    position = enemy.position::GroundPosition
    cell, following, progress = position.cell, position.next_cell, position.progress
    arrived = false
    while speed > 0
        rest = 100 - progress
        if speed < rest
            progress += speed
            speed = 0
        else
            speed -= rest
            cell = following
            progress = 0
            if cell == game.grid.exit
                arrived = true
                break
            end
            following = next_cell(game.field, cell)
        end
    end
    enemy.position = GroundPosition(cell, following, progress)
    arrived
end
function leak!(game::Game, enemy::Enemy)
    enemy.alive = false
    kind = game.enemy_types[enemy.kind]
    lost = min(game.lives, kind.lives)
    game.lives -= lost
    wave = game.records[game.active]
    wave.leaks += 1
    wave.lives_lost += lost
    kind.leaks += 1
    record!(game, "LEAK E$(enemy.number) $(kind.name) lives $(game.lives)")
    if game.lives == 0
        record!(game, "DEFEAT")
        game.outcome = Defeat
        close_wave!(wave, WaveLost, game.tick, game.gold, game.lives)
        game.active = nothing
    end
end
function fire_towers!(game::Game)
    for tower in game.towers
        (!standing(tower) || game.tick < tower.ready) && continue
        target = select_target(tower, game.enemies, game.enemy_types, game.tower_types, game.field)
        if target !== nothing
            stats = tower_stats(tower, game.tower_types)
            game.projectile_count += 1
            push!(game.projectiles, Projectile(game.projectile_count, tower.number, target, tower_center(tower), enemy_point(game.enemies[target]), game.tower_types[tower.kind].targets, stats))
            tower.shots += 1
            tower.ready = game.tick + stats.interval
            record!(game, "SHOT T$(tower.number) E$(game.enemies[target].number)")
        end
    end
end
function move_projectiles!(game::Game)
    flying = game.projectiles
    game.projectiles = Projectile{Targets,Level}[]
    for projectile in flying
        game.enemies[projectile.target].alive && (projectile.aim = enemy_point(game.enemies[projectile.target]))
        if fly!(projectile)
            impact!(game, projectile)
        else
            push!(game.projectiles, projectile)
        end
    end
end
function impact!(game::Game, projectile::Projectile{Targets,Level})
    tower = game.towers[projectile.tower]
    if projectile.stats.splash == 0
        victims = game.enemies[projectile.target].alive ? [projectile.target] : Int[]
    else
        radius = projectile.stats.splash * projectile.stats.splash
        victims = [index for (index, enemy) in enumerate(game.enemies) if enemy.alive && can_aim(projectile.targets, game.enemy_types[enemy.kind].movement) && squared_distance(enemy_point(enemy), projectile.aim) <= radius]
    end
    isempty(victims) && (tower.fizzles += 1)
    for index in victims
        enemy = game.enemies[index]
        tower.hits += 1
        damage = damage_dealt(enemy.hp, projectile.stats.power, game.enemy_types[enemy.kind].armor)
        enemy.hp -= damage
        credit!(game, tower, enemy, damage)
        if enemy.hp == 0
            kill!(game, enemy, tower)
            continue
        end
        projectile.stats.slow_rate > 0 && receive!(enemy.slow, projectile.stats.slow_rate, projectile.stats.slow_time)
        projectile.stats.burn_amount > 0 && receive!(enemy.burn, projectile.stats.burn_amount, projectile.stats.burn_time, projectile.tower)
    end
end
function credit!(game::Game, tower::Tower, enemy::Enemy, damage::Int)
    tower.damage += damage
    game.enemy_types[enemy.kind].damage += damage
    amounts = game.records[game.active].tower_damage
    amounts[tower.number] = get(amounts, tower.number, 0) + damage
end
function kill!(game::Game, enemy::Enemy, tower::Tower)
    enemy.alive = false
    x, y = occupied_cell(enemy)
    game.kill_counts[y + 1, x + 1] += 1
    kind = game.enemy_types[enemy.kind]
    wave = game.records[game.active]
    tower.kills += 1
    wave.kills += 1
    kind.kills += 1
    game.gold += kind.bounty
    wave.bounty += kind.bounty
    game.income.bounty += kind.bounty
    record!(game, "KILL E$(enemy.number) $(kind.name) T$(tower.number) bounty $(kind.bounty) gold $(game.gold)")
    for _ in 1:kind.split_count
        child = split_enemy(enemy, length(game.enemies) + 1, game.enemy_types)
        add_enemy!(game, child)
        record!(game, "SPAWN E$(child.number) $(game.enemy_types[child.kind].name) E$(enemy.number) hp $(child.hp)")
    end
end
function check_wave_end!(game::Game)
    game.active === nothing && return
    wave = game.records[game.active]
    plan = game.waves[game.active]
    (any(enemy -> enemy.alive, game.enemies) || any(pair -> pair[1] != pair[2].count, zip(wave.released, plan.groups))) && return
    game.gold += plan.reward
    interest = min(game.params.interest_cap, game.gold * game.params.interest_rate ÷ 100)
    game.gold += interest
    wave.reward, wave.interest = plan.reward, interest
    game.income.reward += plan.reward
    game.income.interest += interest
    game.active = nothing
    record!(game, "WAVE_END $(wave.number) reward $(plan.reward) interest $interest gold $(game.gold)")
    if wave.number == length(game.waves)
        record!(game, "VICTORY")
        game.outcome = Victory
    else
        game.next_start = game.tick + game.params.interval
    end
    close_wave!(wave, WaveCleared, game.tick, game.gold, game.lives)
end
function map_picture(game::Game)
    rows = copy.(game.grid.rows)
    for spawn in game.grid.spawns, cell in spawn_path(game.field, spawn)
        terrain(game.grid, cell) in (UInt8('.'), UInt8('~')) && (rows[cell[2] + 1][cell[1] + 1] = UInt8('+'))
    end
    for tower in game.towers
        standing(tower) && (rows[tower.cell[2] + 1][tower.cell[1] + 1] = game.tower_types[tower.kind].symbol)
    end
    occupants = Dict{Cell,Tuple{Int,UInt8}}()
    for enemy in game.enemies
        enemy.alive || continue
        cell = occupied_cell(enemy)
        old = get(occupants, cell, (0, game.enemy_types[enemy.kind].symbol))
        occupants[cell] = (old[1] + 1, old[2])
    end
    for (cell, group) in occupants
        rows[cell[2] + 1][cell[1] + 1] = group[1] == 1 ? group[2] : UInt8('*')
    end
    rows
end
function flow_picture(game::Game)
    rows = Vector{UInt8}[]
    arrows = collect(codeunits("^>v<"))
    for y in 0:game.grid.height-1
        row = UInt8[]
        for x in 0:game.grid.width-1
            cell = (x, y)
            value = terrain(game.grid, cell)
            tower = tower_at(game, cell)
            if value in (UInt8('#'), UInt8('E'))
                push!(row, value)
            elseif tower !== nothing
                push!(row, game.tower_types[tower.kind].symbol)
            elseif distance_at(game.field, cell) === nothing
                push!(row, UInt8('?'))
            else
                push!(row, arrows[direction_of(game.field, cell)])
            end
        end
        push!(rows, row)
    end
    rows
end
function coverage_picture(game::Game)
    rows = Vector{UInt8}[]
    for y in 0:game.grid.height-1
        row = UInt8[]
        for x in 0:game.grid.width-1
            cell = (x, y)
            tower = tower_at(game, cell)
            if is_rock(game.grid, cell)
                push!(row, UInt8('#'))
            elseif tower !== nothing
                push!(row, game.tower_types[tower.kind].symbol)
            else
                covered = count(tower -> standing(tower) && in_range(tower, cell_center(cell), game.tower_types), game.towers)
                push!(row, digit(covered))
            end
        end
        push!(rows, row)
    end
    rows
end
function kills_picture(game::Game)
    rows = Vector{UInt8}[]
    for y in 0:game.grid.height-1
        row = UInt8[]
        for x in 0:game.grid.width-1
            frequency = game.kill_counts[y + 1, x + 1]
            value = frequency > 0 ? digit(frequency) : is_rock(game.grid, (x, y)) ? UInt8('#') : UInt8('.')
            push!(row, value)
        end
        push!(rows, row)
    end
    rows
end
function snapshot_block(game::Game, label::String)
    next = game.active === nothing && game.outcome === nothing ? string(game.next_start) : "-"
    lines = ["$label $(game.tick) wave $(length(game.records)) next $next gold $(game.gold) lives $(game.lives)"]
    append!(lines, ruled(map_picture(game)))
    for (number, spawn) in enumerate(game.grid.spawns)
        push!(lines, "PATH $number length $(distance_at(game.field, spawn))")
    end
    for tower in game.towers
        if standing(tower)
            push!(lines, "T$(tower.number) $(game.tower_types[tower.kind].name) $(tower.cell[1]) $(tower.cell[2]) level $(tower.level) mode $(mode_text(tower.mode)) ready $(tower.ready)")
        end
    end
    for enemy in game.enemies
        enemy.alive || continue
        x, y = enemy_point(enemy)
        push!(lines, "E$(enemy.number) $(game.enemy_types[enemy.kind].name) $x $y hp $(enemy.hp)/$(enemy.max_hp) slow $(enemy.slow.strength) $(enemy.slow.remaining) burn $(enemy.burn.strength) $(enemy.burn.remaining)")
    end
    for projectile in game.projectiles
        x, y = projectile.position
        push!(lines, "P$(projectile.number) T$(game.towers[projectile.tower].number) E$(game.enemies[projectile.target].number) $x $y")
    end
    lines
end
function final_block(game::Game)
    lines = snapshot_block(game, "FINAL")
    push!(lines, "FLOW")
    append!(lines, ruled(flow_picture(game)))
    push!(lines, "COVERAGE")
    append!(lines, ruled(coverage_picture(game)))
    push!(lines, "KILLS")
    append!(lines, ruled(kills_picture(game)))
    lines
end
function wave_lines(game::Game)
    header = WAVE_COLUMNS * join([",T$(tower.number)" for tower in game.towers])
    vcat([header], [wave_csv_row(wave, length(game.towers)) for wave in game.records])
end
function summary_lines(game::Game, action_count::Int)
    cleared = count(wave -> wave.status == WaveCleared, game.records)
    perfect = count(wave -> wave.status == WaveCleared && wave.leaks == 0, game.records)
    spawned = sum(kind.spawned for kind in game.enemy_types)
    killed = sum(kind.kills for kind in game.enemy_types)
    leaked = sum(kind.leaks for kind in game.enemy_types)
    total_damage = sum((tower.damage for tower in game.towers); init = 0)
    score = 10 * killed + 100 * game.lives + 50 * perfect + game.gold
    income = game.income
    lines = ["outcome $(outcome_text(game.outcome))", "ticks $(game.tick)", "waves $cleared/$(length(game.waves)) perfect $perfect",
        "lives $(game.lives)/$(game.params.lives)", "gold $(game.gold)", "enemies spawned $spawned killed $killed leaked $leaked",
        "income bounty $(income.bounty) reward $(income.reward) interest $(income.interest) early $(income.early) refund $(income.refund)",
        "spent $(game.spent)", "damage $total_damage", "actions total $action_count done $(game.done) refused $(game.refused) unused $(action_count - game.done - game.refused)", "score $score"]
    best = nothing
    for tower in game.towers
        if best === nothing || tower.damage > best.damage
            best = tower
        end
    end
    push!(lines, best === nothing ? "mvp -" : "mvp T$(best.number) damage $(best.damage)")
    for kind in game.enemy_types
        push!(lines, "ENEMY $(kind.name) spawned $(kind.spawned) killed $(kind.kills) leaked $(kind.leaks) damage $(kind.damage)")
    end
    for tower in game.towers
        state = standing(tower) ? "active" : "sold $(tower.sold)"
        push!(lines, "TOWER T$(tower.number) $(game.tower_types[tower.kind].name) $(tower.cell[1]) $(tower.cell[2]) level $(tower.level) mode $(mode_text(tower.mode)) $state shots $(tower.shots) hits $(tower.hits) fizzles $(tower.fizzles) kills $(tower.kills) damage $(tower.damage) per_shot $(one_decimal(tower.damage, tower.shots)) share $(one_decimal(100 * tower.damage, total_damage)) invested $(tower.investment)")
    end
    lines
end
function main()
    grid = read_map(joinpath("input", "map.txt"))
    tower_types = parse_tower_types(read_lines("towers.txt"))
    enemy_types, waves = parse_waves(read_lines("waves.txt"))
    actions = parse_action.(read_lines("actions.txt"))
    params = Params(read_lines("params.txt"))
    game = Game(grid, tower_types, enemy_types, waves, params)
    run!(game, actions)
    mkpath("output")
    write_lines("events.txt", game.events)
    write_lines("waves.csv", wave_lines(game))
    write_lines("snapshots.txt", game.snapshots)
    write_lines("summary.txt", summary_lines(game, length(actions)))
end

main()
