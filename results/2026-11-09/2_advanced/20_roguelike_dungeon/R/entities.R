new_monster_type <- function(tokens, index) {
  traits <- tokens[12L]
  list(index = index, name = tokens[1L], symbol = tokens[2L], min_depth = as.integer(tokens[3L]), max_depth = as.integer(tokens[4L]), weight = as.integer(tokens[5L]), hp = parse_dice(tokens[6L]), to_hit = as.integer(tokens[7L]), defense = as.integer(tokens[8L]), damage = parse_dice(tokens[9L]), speed = as.integer(tokens[10L]), xp = as.integer(tokens[11L]), erratic = grepl("E", traits, fixed = TRUE), stationary = grepl("S", traits, fixed = TRUE), regenerates = grepl("R", traits, fixed = TRUE), poisonous = grepl("P", traits, fixed = TRUE))
}

new_item_type <- function(category, name, min_depth = 0L, max_depth = 0L, weight = 0L) {
  list(category = category, name = name, min_depth = min_depth, max_depth = max_depth, weight = weight, dice = NULL, to_hit = 0L, armor = 0L, effect = "", poison_turns = 0L, nutrition = 0L)
}

parse_item_type <- function(tokens) {
  kind <- new_item_type(tokens[1L], tokens[2L], as.integer(tokens[3L]), as.integer(tokens[4L]), as.integer(tokens[5L]))
  args <- tokens[-seq_len(5L)]
  if (kind$category == "weapon") {
    kind$dice <- parse_dice(args[1L])
    kind$to_hit <- as.integer(args[2L])
  } else if (kind$category == "armor") {
    kind$armor <- as.integer(args[1L])
  } else if (kind$category == "potion") {
    kind$effect <- args[1L]
    if (kind$effect == "heal") kind$dice <- parse_dice(args[2L]) else if (kind$effect == "poison") kind$poison_turns <- as.integer(args[2L])
  } else if (kind$category == "scroll") {
    kind$effect <- args[1L]
  } else if (kind$category == "food") {
    kind$nutrition <- as.integer(args[1L])
  } else if (kind$category == "gold") {
    kind$dice <- parse_dice(args[1L])
  }
  kind
}

new_monster <- function(id, kind, x, y, hp, asleep) {
  monster <- new.env(parent = emptyenv())
  monster$id <- id
  monster$kind <- kind
  monster$x <- x
  monster$y <- y
  monster$hp <- monster$max_hp <- hp
  monster$asleep <- asleep
  monster$energy <- 0L
  monster$was_visible <- FALSE
  monster
}

new_item <- function(kind, x, y, amount = 0) {
  item <- new.env(parent = emptyenv())
  item$kind <- kind
  item$x <- x
  item$y <- y
  item$amount <- amount
  item$bonus <- 0L
  item
}

item_symbol <- function(item) {
  switch(item$kind$category, weapon = ")", armor = "[", potion = "!", scroll = "?", food = "%", gold = "$", amulet = "\"")
}

display_name <- function(item) {
  name <- gsub("_", " ", item$kind$name, fixed = TRUE)
  if (item$kind$category %in% c("weapon", "armor")) return(paste0("+", item$bonus, " ", name))
  if (item$kind$category == "gold") return(paste(item$amount, "gold"))
  name
}
reference_name <- function(item) if (item$kind$category == "gold") display_name(item) else paste("the", display_name(item))
