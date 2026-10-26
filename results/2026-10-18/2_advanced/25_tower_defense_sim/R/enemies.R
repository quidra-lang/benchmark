new_enemy_type <- function(fields, known) {
  kind <- new.env(parent = emptyenv())
  kind$name <- fields[2]
  kind$symbol <- fields[3]
  kind$movement <- fields[4]
  names <- c("hp", "armor", "speed", "bounty", "lives", "regen")
  for (i in seq_along(names)) kind[[names[i]]] <- as.numeric(fields[i + 4])
  kind$split_into <- if (fields[11] == "-") NULL else get(fields[11], envir = known, inherits = FALSE)
  kind$split_count <- as.numeric(fields[12])
  kind$spawned <- kind$kills <- kind$leaks <- kind$damage <- 0
  kind
}
new_group <- function(fields, known) {
  values <- as.numeric(fields[3:7])
  list(kind = get(fields[2], envir = known, inherits = FALSE), spawn = values[1], count = values[2], delay = values[3], interval = values[4], multiplier = values[5])
}
spawn_tick <- function(group, start, index) start + group$delay + index * group$interval
wave_enemy_count <- function(wave) sum(vapply(wave$groups, function(group) group$count, numeric(1)))
parse_waves <- function(lines) {
  known <- new.env(hash = TRUE, parent = emptyenv())
  types <- list()
  waves <- list()
  for (line in lines) {
    fields <- strsplit(line, " ", fixed = TRUE)[[1]]
    if (fields[1] == "enemy") {
      kind <- new_enemy_type(fields, known)
      assign(kind$name, kind, envir = known)
      types[[length(types) + 1]] <- kind
    } else if (fields[1] == "wave") {
      waves[[length(waves) + 1]] <- list(reward = as.numeric(fields[2]), groups = list())
    } else {
      last <- length(waves)
      waves[[last]]$groups[[length(waves[[last]]$groups) + 1]] <- new_group(fields, known)
    }
  }
  list(types = types, waves = waves)
}
new_enemy <- function(number, kind, multiplier) {
  enemy <- new.env(parent = emptyenv())
  enemy$number <- number
  enemy$kind <- kind
  enemy$multiplier <- multiplier
  enemy$max_hp <- (kind$hp * multiplier) %/% 100
  enemy$hp <- enemy$max_hp
  enemy$slow <- new_effect()
  enemy$burn <- new_effect()
  enemy$alive <- TRUE
  enemy$cell <- enemy$next_cell <- enemy$point <- c(0, 0)
  enemy$progress <- 0
  enemy
}
flying <- function(enemy) enemy$kind$movement == "air"
enemy_position <- function(enemy) {
  if (flying(enemy)) enemy$point else 100 * enemy$cell + (enemy$next_cell - enemy$cell) * enemy$progress
}
occupied_cell <- function(enemy) {
  if (flying(enemy)) (enemy$point + 50) %/% 100 else if (enemy$progress < 50) enemy$cell else enemy$next_cell
}
remaining_distance <- function(enemy, field) {
  if (flying(enemy)) integer_sqrt(squared_distance(enemy$point, cell_center(field$exit))) else 100 * field_at(field, enemy$next_cell) + 100 - enemy$progress
}
slowed_speed <- function(enemy) {
  if (effect_active(enemy$slow)) (enemy$kind$speed * (100 - enemy$slow$strength)) %/% 100 else enemy$kind$speed
}
split_enemy <- function(enemy, number) {
  child <- new_enemy(number, enemy$kind$split_into, enemy$multiplier)
  child$cell <- enemy$cell
  child$next_cell <- enemy$next_cell
  child$progress <- enemy$progress
  child$point <- enemy$point
  child
}
