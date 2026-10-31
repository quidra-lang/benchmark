source("grid_map.R")
source("pathing.R")
source("combat.R")
source("towers.R")
source("enemies.R")

income_fields <- c("bounty", "reward", "interest", "early", "refund")
wave_columns <- "wave,start,end,status,spawned,peak,kills,leaks,lives_lost,bounty,reward,interest,gold,lives"
read_lines <- function(name) readLines(file.path("input", name), warn = FALSE)
integer_text <- function(value) sprintf("%.0f", value)
text_value <- function(value) if (is.numeric(value)) integer_text(value) else as.character(value)
write_lines <- function(name, lines) {
  cat(if (length(lines)) paste0(paste(lines, collapse = "\n"), "\n") else "", file = file.path("output", name))
}
one_decimal <- function(numerator, denominator) {
  if (denominator == 0) return("-")
  rounded <- (20 * numerator + denominator) %/% (2 * denominator)
  paste0(integer_text(rounded %/% 10), ".", integer_text(rounded %% 10))
}
digit <- function(count) if (count == 0) "." else if (count <= 9) integer_text(count) else "*"
ruled <- function(rows) {
  lines <- paste0("  ", paste((seq_len(ncol(rows)) - 1) %% 10, collapse = ""))
  for (y in seq_len(nrow(rows))) lines <- c(lines, paste0((y - 1) %% 10, " ", paste(rows[y, ], collapse = "")))
  lines
}
tower_id <- function(number) paste0("T", integer_text(number))
enemy_id <- function(number) paste0("E", integer_text(number))
lookup <- function(table, key) {
  if (exists(key, envir = table, inherits = FALSE)) get(key, envir = table, inherits = FALSE) else NULL
}
new_params <- function(lines) {
  fields <- strsplit(lines, " ", fixed = TRUE)
  list(gold = as.numeric(fields[[1]][2]), lives = as.numeric(fields[[2]][2]),
       interest_rate = as.numeric(fields[[3]][2]), interest_cap = as.numeric(fields[[3]][3]), sell_rate = as.numeric(fields[[4]][2]),
       start = as.numeric(fields[[5]][2]), interval = as.numeric(fields[[5]][3]), early = as.numeric(fields[[6]][2]),
       snapshots = as.numeric(fields[[7]][-1]))
}
new_action <- function(line) {
  fields <- strsplit(line, " ", fixed = TRUE)[[1]]
  list(tick = as.numeric(fields[1]), command = fields[2], arguments = fields[-c(1, 2)])
}
new_wave_record <- function(number, plan, start) {
  wave <- new.env(parent = emptyenv())
  wave$number <- number
  wave$plan <- plan
  wave$start <- start
  wave$end <- 0
  wave$status <- ""
  wave$released <- rep(0, length(plan$groups))
  wave$spawned <- wave$peak <- wave$kills <- wave$leaks <- wave$lives_lost <- wave$bounty <- 0
  wave$reward <- wave$interest <- wave$gold <- wave$lives <- 0
  wave$tower_damage <- numeric()
  wave
}
all_released <- function(wave) all(wave$released == vapply(wave$plan$groups, function(group) group$count, numeric(1)))
close_wave <- function(wave, status, tick, gold, lives) {
  wave$status <- status
  wave$end <- tick
  wave$gold <- gold
  wave$lives <- lives
}
wave_csv_row <- function(wave, tower_count) {
  values <- list(wave$number, wave$start, wave$end, wave$status, wave$spawned, wave$peak, wave$kills, wave$leaks,
                 wave$lives_lost, wave$bounty, wave$reward, wave$interest, wave$gold, wave$lives)
  for (number in seq_len(tower_count)) values[[length(values) + 1]] <- if (number <= length(wave$tower_damage)) wave$tower_damage[number] else 0
  paste(vapply(values, text_value, character(1)), collapse = ",")
}
new_game <- function(grid, tower_types, enemy_types, waves, params) {
  game <- new.env(parent = emptyenv())
  game$grid <- grid
  game$tower_types <- new.env(hash = TRUE, parent = emptyenv())
  for (kind in tower_types) assign(kind$name, kind, envir = game$tower_types)
  game$enemy_types <- enemy_types
  game$waves <- waves
  game$params <- params
  game$exit_center <- cell_center(grid$exit)
  game$tick <- 0
  game$gold <- params$gold
  game$lives <- params$lives
  game$towers <- list()
  game$enemies <- list()
  game$enemy_count <- 0
  game$projectiles <- list()
  game$projectile_count <- 0
  game$records <- list()
  game$active <- NULL
  game$next_start <- params$start
  game$outcome <- NULL
  game$field <- new_distance_field(grid, rep(FALSE, grid$width * grid$height))
  game$kill_counts <- rep(0, grid$width * grid$height)
  game$income <- setNames(rep(0, length(income_fields)), income_fields)
  game$spent <- game$done <- game$refused <- 0
  game$events <- game$snapshots <- character()
  game
}
record_event <- function(game, ...) {
  fields <- c(integer_text(game$tick), vapply(list(...), text_value, character(1)))
  game$events <- c(game$events, paste(fields, collapse = " "))
}
run_game <- function(game, actions) {
  index <- 1
  repeat {
    game$tick <- game$tick + 1
    while (index <= length(actions) && actions[[index]]$tick == game$tick) {
      perform(game, actions[[index]])
      index <- index + 1
    }
    spawn_enemies(game)
    move_enemies(game)
    if (!is.null(game$outcome)) break
    fire_towers(game)
    move_projectiles(game)
    check_wave_end(game)
    if (game$tick %in% game$params$snapshots) game$snapshots <- c(game$snapshots, snapshot_block(game, "SNAPSHOT"))
    if (!is.null(game$outcome)) break
  }
  game$snapshots <- c(game$snapshots, final_block(game))
}
standing_towers <- function(game) Filter(standing, game$towers)
tower_cells <- function(game) {
  cells <- rep(FALSE, game$grid$width * game$grid$height)
  for (tower in standing_towers(game)) cells[cell_index(game$grid, tower$cell)] <- TRUE
  cells
}
tower_at <- function(game, cell) {
  for (tower in game$towers) if (standing(tower) && all(tower$cell == cell)) return(tower)
  NULL
}
standing_tower <- function(game, text) {
  number <- as.numeric(text)
  if (number >= 1 && number <= length(game$towers) && standing(game$towers[[number]])) game$towers[[number]] else NULL
}
ground_enemies <- function(game) Filter(function(enemy) !flying(enemy), game$enemies)
perform <- function(game, action) {
  result <- switch(action$command, BUILD = build(game, action$arguments), UPGRADE = upgrade(game, action$arguments),
                   SELL = sell(game, action$arguments), TARGET = set_target(game, action$arguments), CALL = call_wave(game))
  if (result) game$done <- game$done + 1 else game$refused <- game$refused + 1
}
build_refusal <- function(game, name, cell) {
  kind <- lookup(game$tower_types, name)
  if (is.null(kind)) return("type")
  if (!inside(game$grid, cell)) return("bounds")
  if (!buildable(game$grid, cell)) return("terrain")
  if (!is.null(tower_at(game, cell))) return("tower")
  if (game$gold < kind$levels[[1]]$cost) return("gold")
  walkers <- ground_enemies(game)
  for (enemy in walkers) if (all(enemy$cell == cell) || all(enemy$next_cell == cell)) return("enemy")
  cells <- tower_cells(game)
  cells[cell_index(game$grid, cell)] <- TRUE
  trial <- new_distance_field(game$grid, cells)
  for (spawn in game$grid$spawns) if (field_at(trial, spawn) < 0) return("blocked")
  for (enemy in walkers) if (field_at(trial, enemy$next_cell) < 0) return("blocked")
  NULL
}
build <- function(game, arguments) {
  name <- arguments[1]
  cell <- as.numeric(arguments[2:3])
  reason <- build_refusal(game, name, cell)
  if (!is.null(reason)) {
    record_event(game, "BUILD_REFUSED", name, arguments[2], arguments[3], reason)
    return(FALSE)
  }
  kind <- get(name, envir = game$tower_types, inherits = FALSE)
  cost <- kind$levels[[1]]$cost
  tower <- new_tower(length(game$towers) + 1, kind, cell, game$tick)
  game$towers[[length(game$towers) + 1]] <- tower
  game$gold <- game$gold - cost
  game$spent <- game$spent + cost
  record_event(game, "BUILD", tower_id(tower$number), name, cell[1], cell[2], "cost", cost, "gold", game$gold)
  update_field(game)
  TRUE
}
upgrade <- function(game, arguments) {
  tower <- standing_tower(game, arguments[1])
  if (is.null(tower)) {
    reason <- "notower"
  } else if (tower$level == length(tower$kind$levels)) {
    reason <- "maxlevel"
  } else if (game$gold < tower$kind$levels[[tower$level + 1]]$cost) {
    reason <- "gold"
  } else {
    cost <- tower$kind$levels[[tower$level + 1]]$cost
    game$gold <- game$gold - cost
    game$spent <- game$spent + cost
    tower$level <- tower$level + 1
    tower$investment <- tower$investment + cost
    record_event(game, "UPGRADE", tower_id(tower$number), "level", tower$level, "cost", cost, "gold", game$gold)
    return(TRUE)
  }
  record_event(game, "UPGRADE_REFUSED", paste0("T", arguments[1]), reason)
  FALSE
}
sell <- function(game, arguments) {
  tower <- standing_tower(game, arguments[1])
  if (is.null(tower)) {
    record_event(game, "SELL_REFUSED", paste0("T", arguments[1]), "notower")
    return(FALSE)
  }
  rate <- if (game$tick == tower$built) 100 else game$params$sell_rate
  refund <- (tower$investment * rate) %/% 100
  tower$sold <- game$tick
  game$gold <- game$gold + refund
  game$income["refund"] <- game$income["refund"] + refund
  record_event(game, "SELL", tower_id(tower$number), "refund", refund, "gold", game$gold)
  update_field(game)
  TRUE
}
set_target <- function(game, arguments) {
  tower <- standing_tower(game, arguments[1])
  if (is.null(tower)) {
    reason <- "notower"
  } else if (!arguments[2] %in% target_modes) {
    reason <- "mode"
  } else {
    tower$mode <- arguments[2]
    record_event(game, "TARGET", tower_id(tower$number), tower$mode)
    return(TRUE)
  }
  record_event(game, "TARGET_REFUSED", paste0("T", arguments[1]), reason)
  FALSE
}
call_wave <- function(game) {
  if (!is.null(game$active)) {
    record_event(game, "CALL_REFUSED", "active")
    return(FALSE)
  }
  bonus <- (game$next_start - game$tick) * game$params$early
  game$gold <- game$gold + bonus
  game$income["early"] <- game$income["early"] + bonus
  game$next_start <- game$tick
  record_event(game, "CALL", length(game$records) + 1, "bonus", bonus, "gold", game$gold)
  TRUE
}
update_field <- function(game) {
  before <- game$field
  game$field <- new_distance_field(game$grid, tower_cells(game))
  for (number in seq_along(game$grid$spawns)) {
    old <- field_at(before, game$grid$spawns[[number]])
    current <- field_at(game$field, game$grid$spawns[[number]])
    if (old != current) record_event(game, "REPATH", number, old, current)
  }
}
start_wave <- function(game) {
  plan <- game$waves[[length(game$records) + 1]]
  wave <- new_wave_record(length(game$records) + 1, plan, game$tick)
  game$records[[length(game$records) + 1]] <- wave
  game$active <- wave
  game$next_start <- NULL
  record_event(game, "WAVE_START", wave$number, "enemies", wave_enemy_count(plan))
}
add_enemy <- function(game, enemy) {
  game$enemies[[length(game$enemies) + 1]] <- enemy
  game$enemy_count <- game$enemy_count + 1
  game$active$spawned <- game$active$spawned + 1
  enemy$kind$spawned <- enemy$kind$spawned + 1
}
remove_enemy <- function(game, enemy) {
  enemy$alive <- FALSE
  game$enemies <- Filter(function(candidate) candidate$number != enemy$number, game$enemies)
}
spawn_enemies <- function(game) {
  if (!is.null(game$next_start) && game$tick == game$next_start) start_wave(game)
  wave <- game$active
  if (is.null(wave)) return(invisible(NULL))
  for (i in seq_along(wave$plan$groups)) {
    group <- wave$plan$groups[[i]]
    released <- wave$released[i]
    if (released == group$count || spawn_tick(group, wave$start, released) != game$tick) next
    wave$released[i] <- wave$released[i] + 1
    spawn <- game$grid$spawns[[group$spawn]]
    enemy <- new_enemy(game$enemy_count + 1, group$kind, group$multiplier)
    if (flying(enemy)) {
      enemy$point <- cell_center(spawn)
    } else {
      enemy$cell <- spawn
      enemy$next_cell <- next_cell(game$field, spawn)
    }
    add_enemy(game, enemy)
    record_event(game, "SPAWN", enemy_id(enemy$number), enemy$kind$name, group$spawn, "hp", enemy$hp)
  }
  wave$peak <- max(wave$peak, length(game$enemies))
}
move_enemies <- function(game) {
  moving <- game$enemies
  for (enemy in moving) {
    move_enemy(game, enemy)
    if (!is.null(game$outcome)) return(invisible(NULL))
  }
}
move_enemy <- function(game, enemy) {
  if (effect_active(enemy$burn)) {
    source <- enemy$burn$source
    damage <- min(enemy$hp, enemy$burn$strength)
    enemy$hp <- enemy$hp - damage
    credit(game, source, enemy, damage)
    advance_effect(enemy$burn)
    if (enemy$hp == 0) {
      kill(game, enemy, source)
      return(invisible(NULL))
    }
  }
  enemy$hp <- min(enemy$hp + enemy$kind$regen, enemy$max_hp)
  speed <- slowed_speed(enemy)
  if (effect_active(enemy$slow)) advance_effect(enemy$slow)
  if (flying(enemy)) {
    result <- advance_point(enemy$point, game$exit_center, speed)
    enemy$point <- result$point
    arrived <- result$arrived
  } else {
    arrived <- walk(game, enemy, speed)
  }
  if (arrived) leak(game, enemy)
}
walk <- function(game, enemy, speed) {
  if (is_water(game$grid, occupied_cell(enemy))) speed <- speed %/% 2
  while (speed > 0) {
    rest <- 100 - enemy$progress
    if (speed < rest) {
      enemy$progress <- enemy$progress + speed
      speed <- 0
    } else {
      speed <- speed - rest
      enemy$cell <- enemy$next_cell
      enemy$progress <- 0
      if (all(enemy$cell == game$grid$exit)) return(TRUE)
      enemy$next_cell <- next_cell(game$field, enemy$cell)
    }
  }
  FALSE
}
leak <- function(game, enemy) {
  remove_enemy(game, enemy)
  lost <- min(game$lives, enemy$kind$lives)
  game$lives <- game$lives - lost
  wave <- game$active
  wave$leaks <- wave$leaks + 1
  wave$lives_lost <- wave$lives_lost + lost
  enemy$kind$leaks <- enemy$kind$leaks + 1
  record_event(game, "LEAK", enemy_id(enemy$number), enemy$kind$name, "lives", game$lives)
  if (game$lives == 0) {
    record_event(game, "DEFEAT")
    game$outcome <- "defeat"
    close_wave(wave, "lost", game$tick, game$gold, game$lives)
    game$active <- NULL
  }
}
fire_towers <- function(game) {
  for (tower in standing_towers(game)) {
    if (game$tick < tower$ready) next
    target <- select_target(tower, game$enemies, game$field)
    if (!is.null(target)) fire(game, tower, target)
  }
}
fire <- function(game, tower, target) {
  stats <- tower_stats(tower)
  game$projectile_count <- game$projectile_count + 1
  game$projectiles[[length(game$projectiles) + 1]] <- new_projectile(game$projectile_count, tower, target, tower_center(tower), enemy_position(target), tower$kind$targets, stats)
  tower$shots <- tower$shots + 1
  tower$ready <- game$tick + stats$interval
  record_event(game, "SHOT", tower_id(tower$number), enemy_id(target$number))
}
move_projectiles <- function(game) {
  flying_shots <- list()
  for (projectile in game$projectiles) {
    if (projectile$target$alive) projectile$aim <- enemy_position(projectile$target)
    if (fly_projectile(projectile)) impact(game, projectile) else flying_shots[[length(flying_shots) + 1]] <- projectile
  }
  game$projectiles <- flying_shots
}
impact <- function(game, projectile) {
  tower <- projectile$tower
  target <- projectile$target
  if (projectile$splash == 0) {
    victims <- if (target$alive) list(target) else list()
  } else {
    reach <- projectile$splash * projectile$splash
    victims <- Filter(function(enemy) can_aim(projectile$targets, enemy) && squared_distance(enemy_position(enemy), projectile$aim) <= reach, game$enemies)
  }
  if (!length(victims)) tower$fizzles <- tower$fizzles + 1
  for (enemy in victims) {
    tower$hits <- tower$hits + 1
    damage <- damage_dealt(enemy$hp, projectile$power, enemy$kind$armor)
    enemy$hp <- enemy$hp - damage
    credit(game, tower, enemy, damage)
    if (enemy$hp == 0) {
      kill(game, enemy, tower)
      next
    }
    if (projectile$slow_rate > 0) receive_effect(enemy$slow, projectile$slow_rate, projectile$slow_time)
    if (projectile$burn_amount > 0) receive_effect(enemy$burn, projectile$burn_amount, projectile$burn_time, tower)
  }
}
credit <- function(game, tower, enemy, damage) {
  tower$damage <- tower$damage + damage
  enemy$kind$damage <- enemy$kind$damage + damage
  old <- game$active$tower_damage
  if (length(old) < length(game$towers)) old <- c(old, rep(0, length(game$towers) - length(old)))
  old[tower$number] <- old[tower$number] + damage
  game$active$tower_damage <- old
}
kill <- function(game, enemy, tower) {
  remove_enemy(game, enemy)
  cell <- occupied_cell(enemy)
  index <- cell_index(game$grid, cell)
  game$kill_counts[index] <- game$kill_counts[index] + 1
  wave <- game$active
  bounty <- enemy$kind$bounty
  tower$kills <- tower$kills + 1
  wave$kills <- wave$kills + 1
  enemy$kind$kills <- enemy$kind$kills + 1
  game$gold <- game$gold + bounty
  wave$bounty <- wave$bounty + bounty
  game$income["bounty"] <- game$income["bounty"] + bounty
  record_event(game, "KILL", enemy_id(enemy$number), enemy$kind$name, tower_id(tower$number), "bounty", bounty, "gold", game$gold)
  for (i in seq_len(enemy$kind$split_count)) {
    child <- split_enemy(enemy, game$enemy_count + 1)
    add_enemy(game, child)
    record_event(game, "SPAWN", enemy_id(child$number), child$kind$name, enemy_id(enemy$number), "hp", child$hp)
  }
}
check_wave_end <- function(game) {
  wave <- game$active
  if (is.null(wave) || length(game$enemies) || !all_released(wave)) return(invisible(NULL))
  reward <- wave$plan$reward
  game$gold <- game$gold + reward
  interest <- min(game$params$interest_cap, (game$gold * game$params$interest_rate) %/% 100)
  game$gold <- game$gold + interest
  wave$reward <- reward
  wave$interest <- interest
  game$income["reward"] <- game$income["reward"] + reward
  game$income["interest"] <- game$income["interest"] + interest
  game$active <- NULL
  record_event(game, "WAVE_END", wave$number, "reward", reward, "interest", interest, "gold", game$gold)
  if (wave$number == length(game$waves)) {
    record_event(game, "VICTORY")
    game$outcome <- "victory"
  } else {
    game$next_start <- game$tick + game$params$interval
  }
  close_wave(wave, "cleared", game$tick, game$gold, game$lives)
}
map_picture <- function(game) {
  rows <- game$grid$rows
  for (spawn in game$grid$spawns) for (cell in spawn_path(game$field, spawn)) {
    if (terrain(game$grid, cell) %in% c(".", "~")) rows[cell[2] + 1, cell[1] + 1] <- "+"
  }
  for (tower in standing_towers(game)) rows[tower$cell[2] + 1, tower$cell[1] + 1] <- tower$kind$symbol
  occupants <- vector("list", game$grid$width * game$grid$height)
  for (enemy in game$enemies) {
    index <- cell_index(game$grid, occupied_cell(enemy))
    occupants[[index]] <- c(occupants[[index]], list(enemy))
  }
  for (index in seq_along(occupants)) if (length(occupants[[index]])) {
    x <- (index - 1) %% game$grid$width
    y <- (index - 1) %/% game$grid$width
    rows[y + 1, x + 1] <- if (length(occupants[[index]]) == 1) occupants[[index]][[1]]$kind$symbol else "*"
  }
  rows
}
flow_picture <- function(game) {
  rows <- matrix("", nrow = game$grid$height, ncol = game$grid$width)
  arrows <- c("^", ">", "v", "<")
  for (y in seq_len(game$grid$height) - 1) for (x in seq_len(game$grid$width) - 1) {
    cell <- c(x, y)
    symbol <- terrain(game$grid, cell)
    tower <- tower_at(game, cell)
    rows[y + 1, x + 1] <- if (symbol %in% c("#", "E")) symbol else if (!is.null(tower)) tower$kind$symbol else if (field_at(game$field, cell) < 0) "?" else arrows[field_direction(game$field, cell)]
  }
  rows
}
coverage_picture <- function(game) {
  rows <- matrix("", nrow = game$grid$height, ncol = game$grid$width)
  towers <- standing_towers(game)
  for (y in seq_len(game$grid$height) - 1) for (x in seq_len(game$grid$width) - 1) {
    cell <- c(x, y)
    tower <- tower_at(game, cell)
    rows[y + 1, x + 1] <- if (is_rock(game$grid, cell)) "#" else if (!is.null(tower)) tower$kind$symbol else digit(sum(vapply(towers, function(other) in_range(other, cell_center(cell)), logical(1))))
  }
  rows
}
kills_picture <- function(game) {
  rows <- matrix("", nrow = game$grid$height, ncol = game$grid$width)
  for (y in seq_len(game$grid$height) - 1) for (x in seq_len(game$grid$width) - 1) {
    cell <- c(x, y)
    count <- game$kill_counts[cell_index(game$grid, cell)]
    rows[y + 1, x + 1] <- if (count > 0) digit(count) else if (is_rock(game$grid, cell)) "#" else "."
  }
  rows
}
snapshot_block <- function(game, label) {
  next_text <- if (is.null(game$active) && is.null(game$outcome)) integer_text(game$next_start) else "-"
  lines <- c(paste(label, integer_text(game$tick), "wave", length(game$records), "next", next_text, "gold", integer_text(game$gold), "lives", integer_text(game$lives)), ruled(map_picture(game)))
  for (number in seq_along(game$grid$spawns)) lines <- c(lines, paste("PATH", number, "length", field_at(game$field, game$grid$spawns[[number]])))
  for (tower in standing_towers(game)) lines <- c(lines, paste(tower_id(tower$number), tower$kind$name, tower$cell[1], tower$cell[2], "level", tower$level, "mode", tower$mode, "ready", integer_text(tower$ready)))
  for (enemy in game$enemies) {
    point <- enemy_position(enemy)
    lines <- c(lines, paste(enemy_id(enemy$number), enemy$kind$name, point[1], point[2], "hp", paste0(integer_text(enemy$hp), "/", integer_text(enemy$max_hp)), "slow", enemy$slow$strength, enemy$slow$remaining, "burn", enemy$burn$strength, enemy$burn$remaining))
  }
  for (projectile in game$projectiles) lines <- c(lines, paste0("P", integer_text(projectile$number), " ", tower_id(projectile$tower$number), " ", enemy_id(projectile$target$number), " ", integer_text(projectile$position[1]), " ", integer_text(projectile$position[2])))
  lines
}
final_block <- function(game) c(snapshot_block(game, "FINAL"), "FLOW", ruled(flow_picture(game)), "COVERAGE", ruled(coverage_picture(game)), "KILLS", ruled(kills_picture(game)))
wave_lines <- function(game) {
  header <- paste0(wave_columns, paste0(vapply(game$towers, function(tower) paste0(",", tower_id(tower$number)), character(1)), collapse = ""))
  c(header, vapply(game$records, function(wave) wave_csv_row(wave, length(game$towers)), character(1)))
}
mvp_line <- function(game) {
  best <- NULL
  for (tower in game$towers) if (is.null(best) || tower$damage > best$damage) best <- tower
  if (is.null(best)) "mvp -" else paste("mvp", tower_id(best$number), "damage", integer_text(best$damage))
}
tower_line <- function(tower, total_damage) {
  state <- if (standing(tower)) "active" else paste("sold", integer_text(tower$sold))
  paste("TOWER", tower_id(tower$number), tower$kind$name, tower$cell[1], tower$cell[2], "level", tower$level, "mode", tower$mode,
        state, "shots", integer_text(tower$shots), "hits", integer_text(tower$hits), "fizzles", integer_text(tower$fizzles), "kills", integer_text(tower$kills),
        "damage", integer_text(tower$damage), "per_shot", one_decimal(tower$damage, tower$shots), "share", one_decimal(100 * tower$damage, total_damage), "invested", integer_text(tower$investment))
}
summary_lines <- function(game, action_count) {
  cleared <- Filter(function(wave) wave$status == "cleared", game$records)
  perfect <- sum(vapply(cleared, function(wave) wave$leaks == 0, logical(1)))
  spawned <- sum(vapply(game$enemy_types, function(kind) kind$spawned, numeric(1)))
  killed <- sum(vapply(game$enemy_types, function(kind) kind$kills, numeric(1)))
  leaked <- sum(vapply(game$enemy_types, function(kind) kind$leaks, numeric(1)))
  total_damage <- sum(vapply(game$towers, function(tower) tower$damage, numeric(1)))
  score <- 10 * killed + 100 * game$lives + 50 * perfect + game$gold
  income <- paste(vapply(income_fields, function(name) paste(name, integer_text(game$income[name])), character(1)), collapse = " ")
  lines <- c(paste("outcome", game$outcome), paste("ticks", integer_text(game$tick)), paste0("waves ", length(cleared), "/", length(game$waves), " perfect ", perfect),
             paste0("lives ", integer_text(game$lives), "/", integer_text(game$params$lives)), paste("gold", integer_text(game$gold)),
             paste("enemies spawned", integer_text(spawned), "killed", integer_text(killed), "leaked", integer_text(leaked)), paste("income", income),
             paste("spent", integer_text(game$spent)), paste("damage", integer_text(total_damage)),
             paste("actions total", action_count, "done", game$done, "refused", game$refused, "unused", action_count - game$done - game$refused), paste("score", integer_text(score)), mvp_line(game))
  for (kind in game$enemy_types) lines <- c(lines, paste("ENEMY", kind$name, "spawned", integer_text(kind$spawned), "killed", integer_text(kind$kills), "leaked", integer_text(kind$leaks), "damage", integer_text(kind$damage)))
  for (tower in game$towers) lines <- c(lines, tower_line(tower, total_damage))
  lines
}
main <- function() {
  grid <- read_map()
  tower_types <- parse_tower_types(read_lines("towers.txt"))
  definitions <- parse_waves(read_lines("waves.txt"))
  actions <- lapply(read_lines("actions.txt"), new_action)
  game <- new_game(grid, tower_types, definitions$types, definitions$waves, new_params(read_lines("params.txt")))
  run_game(game, actions)
  dir.create("output", showWarnings = FALSE, recursive = TRUE)
  write_lines("events.txt", game$events)
  write_lines("waves.csv", wave_lines(game))
  write_lines("snapshots.txt", game$snapshots)
  write_lines("summary.txt", summary_lines(game, length(actions)))
}
main()
