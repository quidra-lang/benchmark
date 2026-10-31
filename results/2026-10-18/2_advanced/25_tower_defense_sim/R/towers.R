target_modes <- c("FIRST", "LAST", "STRONGEST", "WEAKEST", "CLOSEST")
parse_tower_types <- function(lines) {
  types <- list()
  index <- 1
  names <- c("cost", "range", "power", "interval", "shot_speed", "splash", "slow_rate", "slow_time", "burn_amount", "burn_time")
  while (index <= length(lines)) {
    fields <- strsplit(lines[index], " ", fixed = TRUE)[[1]]
    count <- as.numeric(fields[5])
    levels <- lapply(seq_len(count), function(i) {
      values <- as.numeric(strsplit(lines[index + i], " ", fixed = TRUE)[[1]][-1])
      setNames(as.list(values), names)
    })
    types[[length(types) + 1]] <- list(name = fields[2], symbol = fields[3], targets = fields[4], levels = levels)
    index <- index + count + 1
  }
  types
}
can_aim <- function(targets, enemy) targets == "both" || targets == enemy$kind$movement
new_tower <- function(number, kind, cell, tick) {
  tower <- new.env(parent = emptyenv())
  tower$number <- number
  tower$kind <- kind
  tower$cell <- cell
  tower$level <- 1
  tower$mode <- "FIRST"
  tower$ready <- tick
  tower$investment <- kind$levels[[1]]$cost
  tower$built <- tick
  tower$sold <- NULL
  tower$shots <- tower$hits <- tower$fizzles <- tower$kills <- tower$damage <- 0
  tower
}
tower_stats <- function(tower) tower$kind$levels[[tower$level]]
tower_center <- function(tower) cell_center(tower$cell)
standing <- function(tower) is.null(tower$sold)
in_range <- function(tower, point) {
  reach <- tower_stats(tower)$range
  squared_distance(tower_center(tower), point) <= reach * reach
}
target_key <- function(tower, enemy, field) {
  switch(tower$mode, FIRST = remaining_distance(enemy, field), LAST = -remaining_distance(enemy, field),
         STRONGEST = -enemy$hp, WEAKEST = enemy$hp, CLOSEST = squared_distance(tower_center(tower), enemy_position(enemy)))
}
select_target <- function(tower, enemies, field) {
  best <- NULL
  best_key <- 0
  for (enemy in enemies) {
    if (!can_aim(tower$kind$targets, enemy) || !in_range(tower, enemy_position(enemy))) next
    key <- target_key(tower, enemy, field)
    if (is.null(best) || key < best_key) {
      best <- enemy
      best_key <- key
    }
  }
  best
}
