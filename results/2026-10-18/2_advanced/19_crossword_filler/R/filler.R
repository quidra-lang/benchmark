new_grid_state <- function(letters, count, word_count) list(letters = c(letters), words = integer(count), used = rep(FALSE, word_count))
copy_state <- function(state) list(letters = c(state$letters), words = c(state$words), used = c(state$used))
slot_pattern <- function(state, slot) state$letters[slot$cells]

assign_word <- function(state, slot, id, index) {
  changed <- slot$cells[state$letters[slot$cells] == "."]
  state$letters[slot$cells] <- index$letters[[id]]
  state$words[slot$index] <- id
  state$used[id] <- TRUE
  list(state = state, changed = changed)
}

unassign_word <- function(state, slot, changed) {
  state$letters[changed] <- "."
  state$used[state$words[slot$index]] <- FALSE
  state$words[slot$index] <- 0L
  state
}

new_attempt <- function(layout, index, initial, minimum, budget) {
  attempt <- new.env(parent = emptyenv())
  attempt$layout <- layout
  attempt$index <- index
  attempt$state <- copy_state(initial)
  attempt$best <- copy_state(initial)
  attempt$minimum <- minimum
  attempt$budget <- budget
  attempt$nodes <- attempt$backtracks <- attempt$prunes <- attempt$dead_ends <- attempt$max_depth <- 0L
  attempt$sequence <- integer()
  attempt$failures <- integer(length(layout$slots))
  attempt$trace <- character()
  attempt$outcome <- ""
  attempt
}

attempt_candidates <- function(attempt, slot) candidates(attempt$index, slot_pattern(attempt$state, slot), attempt$minimum, attempt$state$used)

search_attempt <- function(attempt) {
  chosen <- 0L
  choices <- integer()
  for (slot in attempt$layout$slots) {
    if (attempt$state$words[slot$index]) next
    available <- attempt_candidates(attempt, slot)
    if (!chosen || length(available) < length(choices)) {
      chosen <- slot$index
      choices <- available
    }
  }
  if (!chosen) return("complete")
  if (!length(choices)) {
    attempt$dead_ends <- attempt$dead_ends + 1L
    attempt$failures[chosen] <- attempt$failures[chosen] + 1L
    return("fail")
  }
  slot <- attempt$layout$slots[[chosen]]
  for (word in choices) {
    if (attempt$nodes == attempt$budget) return("abort")
    attempt$nodes <- attempt$nodes + 1L
    assigned <- assign_word(attempt$state, slot, word, attempt$index)
    attempt$state <- assigned$state
    attempt$sequence <- c(attempt$sequence, chosen)
    wiped <- 0L
    for (other in slot$crossings) {
      if (!attempt$state$words[other] && !length(attempt_candidates(attempt, attempt$layout$slots[[other]]))) {
        wiped <- other
        break
      }
    }
    if (attempt$nodes <= 10L) attempt$trace <- c(attempt$trace, paste0(slot$label, "=", attempt$index$words[word], if (wiped) "!" else ""))
    result <- "fail"
    if (wiped) {
      attempt$prunes <- attempt$prunes + 1L
      attempt$failures[wiped] <- attempt$failures[wiped] + 1L
    } else {
      if (length(attempt$sequence) > attempt$max_depth) {
        attempt$max_depth <- length(attempt$sequence)
        attempt$best <- copy_state(attempt$state)
      }
      result <- search_attempt(attempt)
    }
    if (result != "fail") return(result)
    attempt$state <- unassign_word(attempt$state, slot, assigned$changed)
    attempt$sequence <- head(attempt$sequence, -1L)
    attempt$backtracks <- attempt$backtracks + 1L
  }
  "fail"
}

run_attempt <- function(attempt) {
  result <- search_attempt(attempt)
  attempt$outcome <- switch(result, complete = "filled", fail = "unfillable", abort = "budget")
}

final_state <- function(attempt) if (attempt$outcome == "filled") attempt$state else attempt$best
