source("minstd.R")
source("combat.R")
source("entities.R")
source("dungeon_gen.R")
source("fov.R")

read_rows <- function(name) strsplit(readLines(file.path("input", name), warn = FALSE), " ", fixed = TRUE)
write_lines <- function(name, lines) writeLines(lines, file.path("output", name), useBytes = TRUE)
dec_1 <- function(a, b) {
  if (b == 0) return("-")
  z <- (20 * a + b) %/% (2 * b)
  paste0(sprintf("%.0f", z %/% 10), ".", z %% 10)
}
exploration <- function(level) {
  non_rock <- level$terrain != " "
  c(sum(non_rock & level$memory != " "), sum(non_rock))
}

read_config <- function(rows) {
  values <- setNames(lapply(rows, function(row) row[-1L]), vapply(rows, function(row) row[1L], character(1)))
  value <- function(key, position = 1L) as.integer(values[[key]][position])
  list(generation_seed = value("seed"), game_seed = value("seed", 2L), width = value("map"), height = value("map", 2L),
    min_size = value("bsp"), max_split = value("bsp", 2L), room_min = value("room"), room_max = value("room", 2L), levels = value("levels"),
    monster_base = value("monsters"), monster_step = value("monsters", 2L), item_base = value("items"), item_step = value("items", 2L),
    sleep_chance = value("sleep"), wake_chance = value("sleep", 2L), fov_radius = value("fov"), max_hp = value("player"), regen_interval = value("player", 2L),
    hit_die = parse_dice(values$hitdie[1L]), food_start = value("food"), food_max = value("food", 2L), food_hungry = value("food", 3L), food_weak = value("food", 4L),
    pack_limit = value("pack"), start_items = values$start, xp_levels = as.integer(values$xp), checkpoints = as.integer(values$checkpoints))
}

expand_commands <- function(rows) {
  commands <- list()
  for (tokens in rows) {
    name <- tokens[1L]
    argument <- ""
    count <- 1L
    if (name == "wait") {
      if (length(tokens) == 2L) count <- as.integer(tokens[2L])
    } else {
      if (length(tokens) > 1L) argument <- tokens[2L]
      if (length(tokens) == 3L) count <- as.integer(tokens[3L])
    }
    for (i in seq_len(count)) commands[[length(commands) + 1L]] <- list(name = name, argument = argument)
  }
  commands
}

new_player <- function(config, point) {
  player <- new.env(parent = emptyenv())
  player$x <- point[1L]
  player$y <- point[2L]
  player$depth <- player$level <- 1L
  player$hp <- player$max_hp <- config$max_hp
  player$xp <- player$gold <- player$poison <- 0L
  player$satiation <- config$food_start
  player$pack <- list()
  player$weapon <- player$armor <- NULL
  player
}
player_defense <- function(player) if (is.null(player$armor)) 10L else 10L + player$armor$kind$armor + player$armor$bonus

new_attack_stats <- function() {
  stats <- new.env(parent = emptyenv())
  stats$count <- stats$hits <- stats$criticals <- stats$damage <- 0L
  stats
}
record_attack <- function(stats, outcome, damage) {
  stats$count <- stats$count + 1L
  if (outcome != "miss") {
    stats$hits <- stats$hits + 1L
    stats$damage <- stats$damage + damage
  }
  if (outcome == "critical") stats$criticals <- stats$criticals + 1L
}
attack_line <- function(stats, label) sprintf("%s %d hits %d criticals %d damage %d accuracy %s", label, stats$count, stats$hits, stats$criticals, stats$damage, dec_1(100 * stats$hits, stats$count))

new_game <- function(config, monster_types, item_types, commands) {
  game <- new.env(parent = emptyenv())
  game$config <- config
  game$monster_types <- monster_types
  game$item_types <- item_types
  game$commands <- commands
  game$generation_rng <- new_rng(config$generation_seed)
  game$rng <- new_rng(config$game_seed)
  game$levels <- list()
  build_levels(game)
  game$player <- new_player(config, game$levels[[1L]]$arrival)
  types_by_name <- setNames(item_types, vapply(item_types, function(kind) kind$name, character(1)))
  for (name in config$start_items) {
    item <- new_item(types_by_name[[name]], game$player$x, game$player$y)
    game$player$pack[[length(game$player$pack) + 1L]] <- item
    if (item$kind$category == "weapon" && is.null(game$player$weapon)) game$player$weapon <- item
    if (item$kind$category == "armor" && is.null(game$player$armor)) game$player$armor <- item
  }
  game$turn <- 1L
  game$messages <- game$map_lines <- character()
  game$visible <- game$distance <- NULL
  game$result <- game$cause <- ""
  game$succeeded <- game$failed <- game$unused <- game$moves <- 0L
  game$player_attacks <- new_attack_stats()
  game$monster_attacks <- new_attack_stats()
  game$poison_damage <- game$starvation_damage <- 0L
  game$usage <- setNames(integer(6L), c("picked", "quaffed", "read", "eaten", "wielded", "worn"))
  game$kills <- integer(length(monster_types))
  game
}

build_levels <- function(game) {
  config <- game$config
  generator <- new_level_generator(game$generation_rng, config$min_size, config$max_split, config$room_min, config$room_max)
  for (depth in seq_len(config$levels)) {
    level <- generate_level(generator, depth, config$width, config$height)
    target <- level$target
    if (depth < config$levels) level$terrain[target[2L] + 1L, target[1L] + 1L] <- ">" else level$items[[1L]] <- new_item(new_item_type("amulet", "amulet"), target[1L], target[2L])
    place_monsters(game, level)
    place_items(game, level)
    game$levels[[depth]] <- level
  }
}

place_monsters <- function(game, level) {
  candidates <- Filter(function(kind) kind$min_depth <= level$depth && level$depth <= kind$max_depth, game$monster_types)
  weights <- vapply(candidates, function(kind) kind$weight, integer(1))
  count <- game$config$monster_base + game$config$monster_step * (level$depth - 1L)
  for (id in seq_len(count)) {
    kind <- candidates[[rng_select(game$generation_rng, weights)]]
    repeat {
      drawn <- draw_room_cell(level, game$generation_rng)
      if (drawn$room != level$arrival_room && level$terrain[drawn$y + 1L, drawn$x + 1L] == "." && is.null(monster_at(level, drawn$x, drawn$y))) break
    }
    hp <- roll_dice(kind$hp, game$generation_rng)
    asleep <- rng_rnd(game$generation_rng, 100L) < game$config$sleep_chance
    level$monsters[[id]] <- new_monster(id, kind, drawn$x, drawn$y, hp, asleep)
  }
  level$monsters_created <- count
}

place_items <- function(game, level) {
  candidates <- Filter(function(kind) kind$min_depth <= level$depth && level$depth <= kind$max_depth, game$item_types)
  weights <- vapply(candidates, function(kind) kind$weight, integer(1))
  count <- game$config$item_base + game$config$item_step * (level$depth - 1L)
  for (i in seq_len(count)) {
    kind <- candidates[[rng_select(game$generation_rng, weights)]]
    repeat {
      drawn <- draw_room_cell(level, game$generation_rng)
      if (level$terrain[drawn$y + 1L, drawn$x + 1L] == "." && is.null(item_at(level, drawn$x, drawn$y))) break
    }
    amount <- if (kind$category == "gold") roll_dice(kind$dice, game$generation_rng) else 0L
    level$items[[length(level$items) + 1L]] <- new_item(kind, drawn$x, drawn$y, amount)
  }
  level$items_placed <- length(level$items)
}

current_level <- function(game) game$levels[[game$player$depth]]
say <- function(game, text) game$messages <- c(game$messages, sprintf("%04d %s", game$turn, text))
hunger_state <- function(game) {
  food <- game$player$satiation
  if (food > game$config$food_hungry) "normal" else if (food > game$config$food_weak) "hungry" else if (food > 0L) "weak" else "starving"
}
finish <- function(game, result, cause) {
  game$result <- result
  game$cause <- cause
}
die <- function(game, cause) {
  say(game, "You die.")
  finish(game, "died", cause)
}

update_view <- function(game) {
  level <- current_level(game)
  player <- game$player
  game$visible <- field_of_view(level, player$x, player$y, game$config$fov_radius)
  for (y in seq_len(level$height) - 1L) {
    for (x in seq_len(level$width) - 1L) {
      if (game$visible[y + 1L, x + 1L]) {
        item <- item_at(level, x, y)
        level$memory[y + 1L, x + 1L] <- if (is.null(item)) level$terrain[y + 1L, x + 1L] else item_symbol(item)
      }
    }
  }
  for (monster in level$monsters) {
    seen <- game$visible[monster$y + 1L, monster$x + 1L]
    if (seen && !monster$was_visible) say(game, paste0("You see the ", monster$kind$name, "."))
    monster$was_visible <- seen
  }
}

run_game <- function(game) {
  update_view(game)
  for (command in game$commands) {
    if (nzchar(game$result)) {
      game$unused <- game$unused + 1L
    } else if (!execute_command(game, command)) {
      game$failed <- game$failed + 1L
    } else {
      game$succeeded <- game$succeeded + 1L
      if (!nzchar(game$result)) advance_turn(game)
    }
  }
  if (!nzchar(game$result)) finish(game, "alive", "commands_exhausted")
}
advance_turn <- function(game) {
  update_view(game)
  monsters_act(game)
  if (nzchar(game$result)) return(invisible(NULL))
  end_turn(game)
  if (nzchar(game$result)) return(invisible(NULL))
  if (game$turn %in% game$config$checkpoints) write_checkpoint(game)
  game$turn <- game$turn + 1L
}

execute_command <- function(game, command) {
  if (command$name == "move") {
    step <- directions[match(command$argument, direction_names), ]
    return(move_player(game, step[1L], step[2L]))
  }
  if (command$name == "wait") return(TRUE)
  if (command$name == "pickup") return(pickup(game))
  if (command$name == "descend") return(descend(game))
  use_item(game, command$name, as.integer(command$argument))
}

move_player <- function(game, dx, dy) {
  player <- game$player
  level <- current_level(game)
  x <- player$x + dx
  y <- player$y + dy
  if (!passable(level, x, y)) {
    say(game, "You bump into a wall.")
    return(FALSE)
  }
  if (!can_move(level, player$x, player$y, dx, dy)) {
    say(game, "You cannot move diagonally through a door.")
    return(FALSE)
  }
  monster <- monster_at(level, x, y)
  if (!is.null(monster)) {
    player_attack(game, level, monster)
    return(TRUE)
  }
  player$x <- x
  player$y <- y
  game$moves <- game$moves + 1L
  item <- item_at(level, x, y)
  if (!is.null(item)) say(game, paste0("You see ", reference_name(item), " here.")) else if (level$terrain[y + 1L, x + 1L] == ">") say(game, "There is a staircase down here.")
  TRUE
}

remove_identity <- function(items, target) Filter(function(item) !identical(item, target), items)
pickup <- function(game) {
  player <- game$player
  level <- current_level(game)
  item <- item_at(level, player$x, player$y)
  if (is.null(item)) {
    say(game, "There is nothing here.")
    return(FALSE)
  }
  category <- item$kind$category
  if (category == "gold") {
    player$gold <- player$gold + item$amount
    say(game, paste0("You pick up ", display_name(item), "."))
  } else if (category == "amulet") {
    say(game, "You pick up the amulet.")
    say(game, "You win!")
    finish(game, "won", "amulet")
  } else if (length(player$pack) >= game$config$pack_limit) {
    say(game, "Your pack is full.")
    return(FALSE)
  } else {
    player$pack[[length(player$pack) + 1L]] <- item
    say(game, sprintf("You pick up the %s (%d).", display_name(item), length(player$pack)))
  }
  level$items <- remove_identity(level$items, item)
  level$picked <- level$picked + 1L
  game$usage["picked"] <- game$usage["picked"] + 1L
  TRUE
}

descend <- function(game) {
  player <- game$player
  if (current_level(game)$terrain[player$y + 1L, player$x + 1L] != ">") {
    say(game, "There are no stairs here.")
    return(FALSE)
  }
  player$depth <- player$depth + 1L
  arrival <- current_level(game)$arrival
  player$x <- arrival[1L]
  player$y <- arrival[2L]
  say(game, sprintf("You descend to depth %d.", player$depth))
  TRUE
}

use_item <- function(game, command, number) {
  if (number > length(game$player$pack)) {
    say(game, "You do not have that item.")
    return(FALSE)
  }
  item <- game$player$pack[[number]]
  classes <- c(quaff = "potion", read = "scroll", wield = "weapon", wear = "armor", eat = "food")
  if (item$kind$category != classes[[command]]) {
    say(game, paste0("You cannot ", command, " that."))
    return(FALSE)
  }
  switch(command, quaff = quaff(game, item), read = read_scroll(game, item), wield = wield(game, item), wear = wear(game, item), eat = eat(game, item))
}

quaff <- function(game, item) {
  player <- game$player
  player$pack <- remove_identity(player$pack, item)
  game$usage["quaffed"] <- game$usage["quaffed"] + 1L
  say(game, paste0("You quaff the ", display_name(item), "."))
  effect <- item$kind$effect
  if (effect == "heal") {
    player$hp <- player$hp + roll_dice(item$kind$dice, game$rng)
    if (player$hp > player$max_hp) {
      player$max_hp <- player$max_hp + 1L
      player$hp <- player$max_hp
    }
    player$poison <- 0L
    say(game, "You feel better.")
  } else if (effect == "poison") {
    player$poison <- player$poison + item$kind$poison_turns
    say(game, "You feel very sick.")
  } else if (effect == "level") {
    say(game, "You feel more experienced.")
    if (player$level <= length(game$config$xp_levels)) gain_xp(game, game$config$xp_levels[player$level] - player$xp)
  }
  TRUE
}

read_scroll <- function(game, item) {
  player <- game$player
  level <- current_level(game)
  player$pack <- remove_identity(player$pack, item)
  game$usage["read"] <- game$usage["read"] + 1L
  say(game, paste0("You read the ", display_name(item), "."))
  effect <- item$kind$effect
  if (effect == "mapping") {
    unseen <- level$terrain != " " & level$memory == " "
    level$memory[unseen] <- level$terrain[unseen]
    say(game, "A map forms in your mind.")
  } else if (effect == "teleport") {
    repeat {
      drawn <- draw_room_cell(level, game$rng)
      if ((drawn$x != player$x || drawn$y != player$y) && is.null(monster_at(level, drawn$x, drawn$y))) break
    }
    player$x <- drawn$x
    player$y <- drawn$y
    say(game, "You are teleported.")
  } else if (effect == "enchant_weapon") {
    if (is.null(player$weapon)) {
      say(game, "Your hands twitch.")
    } else {
      say(game, paste0("Your ", display_name(player$weapon), " glows blue."))
      player$weapon$bonus <- player$weapon$bonus + 1L
    }
  } else if (effect == "enchant_armor") {
    if (is.null(player$armor)) {
      say(game, "Your skin tingles.")
    } else {
      say(game, paste0("Your ", display_name(player$armor), " glows silver."))
      player$armor$bonus <- player$armor$bonus + 1L
    }
  }
  TRUE
}

wield <- function(game, item) {
  if (identical(item, game$player$weapon)) {
    say(game, "You are already wielding that.")
    return(FALSE)
  }
  game$player$weapon <- item
  game$usage["wielded"] <- game$usage["wielded"] + 1L
  say(game, paste0("You are now wielding the ", display_name(item), "."))
  TRUE
}
wear <- function(game, item) {
  if (identical(item, game$player$armor)) {
    say(game, "You are already wearing that.")
    return(FALSE)
  }
  game$player$armor <- item
  game$usage["worn"] <- game$usage["worn"] + 1L
  say(game, paste0("You are now wearing the ", display_name(item), "."))
  TRUE
}
eat <- function(game, item) {
  game$player$pack <- remove_identity(game$player$pack, item)
  game$usage["eaten"] <- game$usage["eaten"] + 1L
  game$player$satiation <- min(game$player$satiation + item$kind$nutrition, game$config$food_max)
  say(game, paste0("You eat the ", display_name(item), "."))
  TRUE
}

player_attack <- function(game, level, monster) {
  player <- game$player
  monster$asleep <- FALSE
  weapon <- player$weapon
  to_hit <- player$level
  dice <- c(1L, 2L)
  bonus <- 0L
  if (!is.null(weapon)) {
    to_hit <- to_hit + weapon$kind$to_hit + weapon$bonus
    dice <- weapon$kind$dice
    bonus <- weapon$bonus
  }
  if (hunger_state(game) %in% c("weak", "starving")) to_hit <- to_hit - 2L
  attack <- resolve_attack(game$rng, to_hit, monster$kind$defense, dice, bonus)
  record_attack(game$player_attacks, attack$outcome, attack$damage)
  name <- monster$kind$name
  if (attack$outcome == "miss") {
    say(game, paste0("You miss the ", name, "."))
    return(invisible(NULL))
  }
  say(game, paste0("You hit the ", name, if (attack$outcome == "critical") " hard" else "", " for ", attack$damage, "."))
  monster$hp <- monster$hp - attack$damage
  if (monster$hp <= 0L) {
    say(game, paste0("You kill the ", name, "."))
    level$monsters <- remove_identity(level$monsters, monster)
    level$kills <- level$kills + 1L
    game$kills[monster$kind$index] <- game$kills[monster$kind$index] + 1L
    gain_xp(game, monster$kind$xp)
  }
}

gain_xp <- function(game, amount) {
  player <- game$player
  player$xp <- player$xp + amount
  while (player$level <= length(game$config$xp_levels) && player$xp >= game$config$xp_levels[player$level]) {
    player$level <- player$level + 1L
    gained <- roll_dice(game$config$hit_die, game$rng)
    player$max_hp <- player$max_hp + gained
    player$hp <- player$hp + gained
    say(game, sprintf("Welcome to level %d.", player$level))
  }
}

monster_attack <- function(game, monster) {
  kind <- monster$kind
  attack <- resolve_attack(game$rng, kind$to_hit, player_defense(game$player), kind$damage, 0L)
  record_attack(game$monster_attacks, attack$outcome, attack$damage)
  if (attack$outcome == "miss") {
    say(game, paste0("The ", kind$name, " misses you."))
    return(invisible(NULL))
  }
  say(game, paste0("The ", kind$name, " hits you", if (attack$outcome == "critical") " hard" else "", " for ", attack$damage, "."))
  game$player$hp <- game$player$hp - attack$damage
  if (game$player$hp <= 0L) {
    die(game, paste("killed_by", kind$name))
  } else if (kind$poisonous) {
    game$player$poison <- game$player$poison + 5L
    say(game, "You are poisoned.")
  }
}

monsters_act <- function(game) {
  level <- current_level(game)
  game$distance <- distances(level, game$player$x, game$player$y)
  for (monster in level$monsters) {
    monster$energy <- monster$energy + monster$kind$speed
    while (monster$energy >= 2L) {
      monster$energy <- monster$energy - 2L
      monster_action(game, level, monster)
      if (nzchar(game$result)) return(invisible(NULL))
    }
  }
}

monster_action <- function(game, level, monster) {
  sees <- game$visible[monster$y + 1L, monster$x + 1L]
  if (monster$asleep) {
    if (sees && rng_rnd(game$rng, 100L) < game$config$wake_chance) {
      monster$asleep <- FALSE
      say(game, paste0("The ", monster$kind$name, " wakes up."))
    }
  } else if (monster$kind$stationary) {
    if (can_attack(game, level, monster)) monster_attack(game, monster)
  } else if (monster$kind$erratic && rng_rnd(game$rng, 2L) == 0L) {
    wander(game, level, monster)
  } else if (sees) {
    chase(game, level, monster)
  } else {
    wander(game, level, monster)
  }
}
can_attack <- function(game, level, monster) {
  dx <- game$player$x - monster$x
  dy <- game$player$y - monster$y
  max(abs(dx), abs(dy)) == 1L && can_move(level, monster$x, monster$y, dx, dy)
}
wander <- function(game, level, monster) {
  step <- directions[rng_rnd(game$rng, 8L) + 1L, ]
  if (!can_move(level, monster$x, monster$y, step[1L], step[2L])) return(invisible(NULL))
  x <- monster$x + step[1L]
  y <- monster$y + step[2L]
  if (x == game$player$x && y == game$player$y) {
    monster_attack(game, monster)
  } else if (is.null(monster_at(level, x, y))) {
    monster$x <- x
    monster$y <- y
  }
}
chase <- function(game, level, monster) {
  if (can_attack(game, level, monster)) {
    monster_attack(game, monster)
    return(invisible(NULL))
  }
  here <- game$distance[monster$y + 1L, monster$x + 1L]
  best <- NULL
  best_distance <- 0L
  for (i in seq_len(nrow(directions))) {
    dx <- directions[i, 1L]
    dy <- directions[i, 2L]
    if (!can_move(level, monster$x, monster$y, dx, dy)) next
    x <- monster$x + dx
    y <- monster$y + dy
    distance <- game$distance[y + 1L, x + 1L]
    if (distance < 0L || (here >= 0L && distance >= here) || (x == game$player$x && y == game$player$y) || !is.null(monster_at(level, x, y))) next
    if (is.null(best) || distance < best_distance) {
      best <- c(x, y)
      best_distance <- distance
    }
  }
  if (!is.null(best)) {
    monster$x <- best[1L]
    monster$y <- best[2L]
  }
}

end_turn <- function(game) {
  player <- game$player
  for (monster in current_level(game)$monsters) {
    if (monster$kind$regenerates && monster$hp < monster$max_hp) monster$hp <- monster$hp + 1L
  }
  if (player$poison > 0L) {
    player$hp <- player$hp - 1L
    game$poison_damage <- game$poison_damage + 1L
    if (player$hp <= 0L) {
      die(game, "poison")
      return(invisible(NULL))
    }
    player$poison <- player$poison - 1L
    if (player$poison == 0L) say(game, "You feel less sick.")
  }
  if (player$satiation == 0L) {
    player$hp <- player$hp - 1L
    game$starvation_damage <- game$starvation_damage + 1L
    if (player$hp <= 0L) {
      die(game, "starvation")
      return(invisible(NULL))
    }
  } else {
    before <- hunger_state(game)
    player$satiation <- player$satiation - 1L
    after <- hunger_state(game)
    if (after != before) {
      text <- switch(after, hungry = "You are getting hungry.", weak = "You feel weak from hunger.", starving = "You are starving.")
      say(game, text)
    }
  }
  if (game$turn %% game$config$regen_interval == 0L && player$poison == 0L && player$satiation > 0L && player$hp < player$max_hp) player$hp <- player$hp + 1L
}

view_symbol <- function(game, level, x, y) {
  if (x == game$player$x && y == game$player$y) return("@")
  monster <- monster_at(level, x, y)
  if (!is.null(monster)) return(monster$kind$symbol)
  item <- item_at(level, x, y)
  if (!is.null(item)) return(item_symbol(item))
  level$terrain[y + 1L, x + 1L]
}
map_rows <- function(game, level, current) {
  border <- paste0("+", strrep("-", level$width), "+")
  rows <- border
  for (y in seq_len(level$height) - 1L) {
    row <- vapply(seq_len(level$width) - 1L, function(x) {
      if (current && game$visible[y + 1L, x + 1L]) view_symbol(game, level, x, y) else level$memory[y + 1L, x + 1L]
    }, character(1))
    rows <- c(rows, paste0("|", paste(row, collapse = ""), "|"))
  }
  c(rows, border)
}
status_line <- function(game) {
  p <- game$player
  sprintf("STATUS hp %d/%d level %d xp %d defense %d gold %d food %d %s poison %d", p$hp, p$max_hp, p$level, p$xp, player_defense(p), p$gold, p$satiation, hunger_state(game), p$poison)
}
write_checkpoint <- function(game) {
  game$map_lines <- c(game$map_lines, sprintf("CHECKPOINT turn %d depth %d", game$turn, game$player$depth), map_rows(game, current_level(game), TRUE), status_line(game))
}
final_block <- function(game) {
  depth <- game$player$depth
  lines <- sprintf("FINAL turn %d depth %d", game$succeeded, depth)
  for (level in game$levels[seq_len(depth)]) {
    counts <- exploration(level)
    lines <- c(lines, sprintf("LEVEL %d explored %d/%d", level$depth, counts[1L], counts[2L]), map_rows(game, level, level$depth == depth))
  }
  c(lines, status_line(game))
}
item_label <- function(item) if (is.null(item)) "-" else display_name(item)
stats_lines <- function(game) {
  p <- game$player
  lines <- c(paste("result", game$result), paste("cause", game$cause), paste("turns", game$succeeded), paste("depth", p$depth), paste("level", p$level), paste("xp", p$xp),
    sprintf("hp %d/%d", p$hp, p$max_hp), paste("defense", player_defense(p)), sprintf("gold %d", p$gold), paste("food", p$satiation, hunger_state(game)), paste("poison", p$poison),
    paste("weapon", item_label(p$weapon)), paste("armor", item_label(p$armor)), sprintf("commands %d executed %d failed %d unused %d", length(game$commands), game$succeeded, game$failed, game$unused),
    paste("moves", game$moves), attack_line(game$player_attacks, "player_attacks"), attack_line(game$monster_attacks, "monster_attacks"),
    sprintf("poison_damage %d starvation_damage %d", game$poison_damage, game$starvation_damage), paste(paste(names(game$usage), game$usage), collapse = " "), paste("kills", sum(game$kills)))
  for (kind in game$monster_types) if (game$kills[kind$index] > 0L) lines <- c(lines, paste("KILL", kind$name, game$kills[kind$index]))
  for (level in game$levels) {
    counts <- exploration(level)
    lines <- c(lines, sprintf("LEVEL %d rooms %d explored %d/%d %s monsters %d/%d items %d/%d", level$depth, length(level$rooms), counts[1L], counts[2L], dec_1(100 * counts[1L], counts[2L]), level$kills, level$monsters_created, level$picked, level$items_placed))
  }
  for (i in seq_along(p$pack)) {
    item <- p$pack[[i]]
    suffix <- if (identical(item, p$weapon)) " (wielded)" else if (identical(item, p$armor)) " (worn)" else ""
    lines <- c(lines, paste0("INVENTORY ", i, " ", display_name(item), suffix))
  }
  lines
}

main <- function() {
  config <- read_config(read_rows("config.txt"))
  monster_rows <- read_rows("monsters.txt")
  monster_types <- lapply(seq_along(monster_rows), function(i) new_monster_type(monster_rows[[i]], i))
  item_types <- lapply(read_rows("items.txt"), parse_item_type)
  game <- new_game(config, monster_types, item_types, expand_commands(read_rows("commands.txt")))
  run_game(game)
  dir.create("output", showWarnings = FALSE, recursive = TRUE)
  write_lines("messages.txt", game$messages)
  write_lines("maps.txt", c(game$map_lines, final_block(game)))
  write_lines("stats.txt", stats_lines(game))
}

main()
