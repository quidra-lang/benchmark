sex_index <- c(M = 1L, F = 2L, X = 3L)
terms <- list(
  parent = c("father", "mother", "parent"), child = c("son", "daughter", "child"),
  sibling = c("brother", "sister", "sibling"), pibling = c("uncle", "aunt", "pibling"),
  nibling = c("nephew", "niece", "nibling"), spouse = c("husband", "wife", "spouse"),
  late = c("late husband", "late wife", "late spouse"),
  survivor = c("widower", "widow", "surviving spouse"),
  ex = c("ex-husband", "ex-wife", "ex-spouse"),
  stepparent = c("stepfather", "stepmother", "stepparent"),
  stepchild = c("stepson", "stepdaughter", "stepchild"),
  stepsibling = c("stepbrother", "stepsister", "stepsibling"),
  stepgrandparent = c("stepgrandfather", "stepgrandmother", "stepgrandparent"),
  stepgrandchild = c("stepgrandson", "stepgranddaughter", "stepgrandchild"),
  `parent-in-law` = c("father-in-law", "mother-in-law", "parent-in-law"),
  `child-in-law` = c("son-in-law", "daughter-in-law", "child-in-law"),
  `sibling-in-law` = c("brother-in-law", "sister-in-law", "sibling-in-law")
)
ordinals <- c("first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth")
gendered <- function(kind, sex) terms[[kind]][sex_index[[sex]]]
generation_prefix <- function(g) if (g == 1L) "" else paste0(strrep("great-", g - 2L), "grand")
ordinal <- function(k) {
  if (k <= 10L) return(ordinals[k])
  suffix <- if (k %% 100L %in% 11:13) "th" else switch(as.character(k %% 10L), "1" = "st", "2" = "nd", "3" = "rd", "th")
  paste0(k, suffix)
}
kinship_term <- function(da, db, sex) {
  if (da == 0 && db == 0) return("self")
  if (da == 0) return(paste0(generation_prefix(db), gendered("parent", sex)))
  if (db == 0) return(paste0(generation_prefix(da), gendered("child", sex)))
  if (da == 1 && db == 1) return(gendered("sibling", sex))
  if (da == 1) return(paste0(generation_prefix(db - 1L), gendered("pibling", sex)))
  if (db == 1) return(paste0(generation_prefix(da - 1L), gendered("nibling", sex)))
  r <- abs(da - db)
  removal <- if (r == 0) "" else if (r == 1) " once removed" else if (r == 2) " twice removed" else paste0(" ", r, " times removed")
  paste0(ordinal(min(da, db) - 1L), " cousin", removal)
}
fail <- function(...) {
  stop(structure(list(message = paste(...), call = NULL),
                 class = c("command_error", "error", "condition")))
}
id_order <- function(ids) sort(ids, method = "radix")
persons <- list()
marriages <- list()
history <- list()
children_cache <- NULL
distance_cache <- new.env(parent = emptyenv())
coefficient_cache <- new.env(parent = emptyenv())
height_cache <- new.env(parent = emptyenv())
check_person <- function(x) {
  if (!(x %in% names(persons))) fail("UNKNOWN PERSON", x)
  invisible(NULL)
}
sex_of <- function(x) persons[[x]]$sex
parents_of <- function(x) persons[[x]]$parents
children_of <- function(x) {
  if (is.null(children_cache)) {
    children_cache <<- setNames(rep(list(character()), length(persons)), names(persons))
    for (child in names(persons)) for (parent in parents_of(child)) {
      children_cache[[parent]] <<- c(children_cache[[parent]], child)
    }
  }
  children_cache[[x]]
}
age_order <- function(ids) {
  if (!length(ids)) return(character())
  births <- vapply(ids, function(x) persons[[x]]$birth, numeric(1))
  ids[order(births, ids, method = "radix")]
}
person_list <- function(ids) if (length(ids)) paste(age_order(ids), collapse = " ") else "-"
life_years <- function(p) paste0(p$birth, "-", if (is.na(p$death)) "" else p$death)
common_parents <- function(a, b) length(intersect(parents_of(a), parents_of(b)))
are_siblings <- function(a, b) a != b && common_parents(a, b) > 0L
siblings_of <- function(x) {
  ids <- setdiff(names(persons), x)
  ids[vapply(ids, function(y) are_siblings(x, y), logical(1))]
}
contains <- function(m, x) m$first == x || m$second == x
other_person <- function(m, x) if (m$first == x) m$second else m$first
records_of <- function(x) marriages[vapply(marriages, function(m) contains(m, x), logical(1))]
current_index <- function(x) {
  indices <- which(vapply(marriages, function(m) m$status == "current" && contains(m, x), logical(1)))
  if (length(indices)) indices[1] else NA_integer_
}
spouse_of <- function(x) {
  index <- current_index(x)
  if (is.na(index)) character() else other_person(marriages[[index]], x)
}
last_record <- function(a, b) {
  last <- NULL
  for (m in marriages) if (contains(m, a) && contains(m, b)) last <- m
  last
}
partners_of <- function(x) {
  latest <- list()
  for (m in records_of(x)) latest[[other_person(m, x)]] <- m
  names(latest)[vapply(latest, function(m) m$status != "divorced", logical(1))]
}
step_related <- function(pa, pb) {
  for (p in pa) if (any(pb %in% partners_of(p))) return(TRUE)
  FALSE
}
distances <- function(start, upward = TRUE) {
  key <- paste0(if (upward) "up:" else "down:", start)
  if (exists(key, distance_cache, inherits = FALSE)) return(distance_cache[[key]])
  result <- setNames(0L, start)
  queue <- start
  position <- 1L
  while (position <= length(queue)) {
    x <- queue[position]
    position <- position + 1L
    neighbors <- if (upward) parents_of(x) else children_of(x)
    for (y in neighbors) if (!(y %in% names(result))) {
      result[y] <- result[[x]] + 1L
      queue <- c(queue, y)
    }
  }
  distance_cache[[key]] <- result
  result
}
is_ancestor <- function(a, b) a != b && a %in% names(distances(b))
grandparents_of <- function(x) {
  d <- distances(x)
  names(d)[d == 2L]
}
apex <- function(a, b) {
  da <- distances(a)
  db <- distances(b)
  if (a %in% names(db)) return(list(id = a, da = 0L, db = db[[a]], shares = 0L))
  if (b %in% names(da)) return(list(id = b, da = da[[b]], db = 0L, shares = 0L))
  shared <- intersect(names(da), names(db))
  if (!length(shared)) return(NULL)
  best <- shared[order(da[shared] + db[shared], da[shared], shared, method = "radix")][1]
  shares <- sum(da[shared] == da[[best]] & db[shared] == db[[best]])
  list(id = best, da = da[[best]], db = db[[best]], shares = shares)
}
blood_term <- function(top, sex) {
  prefix <- if (top$shares == 1L) "half-" else if (top$shares >= 4L) "double " else ""
  paste0(prefix, kinship_term(top$da, top$db, sex))
}
relationship <- function(a, b, sex = sex_of(a)) {
  if (a == b) return("self")
  result <- character()
  top <- apex(a, b)
  if (!is.null(top)) result <- c(result, blood_term(top, sex))
  record <- last_record(a, b)
  if (is.null(record)) {
    common_child <- any(vapply(persons, function(p) a %in% p$parents && b %in% p$parents, logical(1)))
    if (common_child) result <- c(result, "co-parent")
  } else if (record$status == "current") result <- c(result, gendered("spouse", sex))
  else if (record$status == "widowed") result <- c(result, gendered(if (record$died == a) "late" else "survivor", sex))
  else result <- c(result, gendered("ex", sex))
  pa <- parents_of(a)
  pb <- parents_of(b)
  partners_a <- partners_of(a)
  partners_b <- partners_of(b)
  if (!(a %in% pb) && any(pb %in% partners_a)) result <- c(result, gendered("stepparent", sex))
  if (!(b %in% pa) && any(pa %in% partners_b)) result <- c(result, gendered("stepchild", sex))
  if (common_parents(a, b) == 0L && step_related(pa, pb)) result <- c(result, gendered("stepsibling", sex))
  if (!is_ancestor(a, b) && any(grandparents_of(b) %in% partners_a)) result <- c(result, gendered("stepgrandparent", sex))
  if (!is_ancestor(b, a) && any(grandparents_of(a) %in% partners_b)) result <- c(result, gendered("stepgrandchild", sex))
  if (any(vapply(partners_b, function(q) a %in% parents_of(q), logical(1)))) result <- c(result, gendered("parent-in-law", sex))
  if (any(vapply(partners_a, function(q) b %in% parents_of(q), logical(1)))) result <- c(result, gendered("child-in-law", sex))
  sibling_of_partner <- any(vapply(partners_b, function(q) are_siblings(a, q), logical(1)))
  partner_of_sibling <- any(vapply(partners_a, function(q) are_siblings(q, b), logical(1)))
  if (sibling_of_partner || partner_of_sibling) result <- c(result, gendered("sibling-in-law", sex))
  result
}
relationship_text <- function(a, b) {
  result <- relationship(a, b)
  if (length(result)) paste(result, collapse = ", ") else "no relation"
}

# All coefficients are multiples of 2^-37. These scaled integers and their sums
# are exactly representable as R numerics, without any integer32 bit operations.
coefficient_scale <- 2^37
phi <- function(a, b) {
  key <- paste(id_order(c(a, b)), collapse = ":")
  if (exists(key, coefficient_cache, inherits = FALSE)) return(coefficient_cache[[key]])
  if (a == b) value <- (coefficient_scale + inbreeding(a)) / 2
  else {
    if (persons[[a]]$birth >= persons[[b]]$birth) {
      x <- a
      y <- b
    } else {
      x <- b
      y <- a
    }
    value <- sum(vapply(parents_of(x), function(p) phi(p, y), numeric(1))) / 2
  }
  coefficient_cache[[key]] <- value
  value
}
inbreeding <- function(x) {
  parents <- parents_of(x)
  if (length(parents) < 2L) 0 else phi(parents[1], parents[2])
}
fraction_text <- function(value) {
  if (value == 0) return("0/1")
  denominator <- coefficient_scale
  while (denominator > 1 && value %% 2 == 0) {
    value <- value / 2
    denominator <- denominator / 2
  }
  paste0(sprintf("%.0f", value), "/", sprintf("%.0f", denominator))
}
lineage_length <- function(x) {
  if (exists(x, height_cache, inherits = FALSE)) return(height_cache[[x]])
  heights <- vapply(parents_of(x), lineage_length, numeric(1))
  value <- 1L + max(c(0, heights))
  height_cache[[x]] <- value
  value
}
upward_path <- function(x, top) {
  path <- x
  while (x != top) {
    target_distance <- distances(x)[[top]] - 1L
    candidates <- parents_of(x)
    candidates <- candidates[vapply(candidates, function(p) {
      d <- distances(p)
      top %in% names(d) && d[[top]] == target_distance
    }, logical(1))]
    x <- id_order(candidates)[1]
    path <- c(path, x)
  }
  path
}
census_status <- function(x, year) {
  last <- NULL
  for (m in records_of(x)) if (m$start <= year) last <- m
  if (is.null(last)) return("single")
  if (is.na(last$end) || last$end > year) return(paste("married", other_person(last, x)))
  last$status
}

modifying <- c("PERSON", "DEATH", "REMOVE", "PARENT", "UNPARENT", "SPOUSE", "DIVORCE")
two_ids <- c("PARENT", "UNPARENT", "SPOUSE", "DIVORCE", "RELATION", "PATH", "COMMON", "KINSHIP")
single_id <- c("DEATH", "REMOVE", "INFO", "RELATIVES", "WHO", "ANCESTORS", "DESCENDANTS", "COUSINS", "SIBLINGS", "GENERATIONS", "TREE", "PEDIGREE", "TIMELINE", "FIND")
handle_command <- function(words) {
  command <- words[1]
  x <- if (length(words) > 1L) words[2] else ""
  y <- if (length(words) > 2L) words[3] else ""
  if (command %in% c(single_id, two_ids)) check_person(x)
  if (command %in% two_ids) check_person(y)
  if (command == "PERSON") {
    if (x %in% names(persons)) fail("DUPLICATE PERSON", x)
    persons[[x]] <<- list(sex = words[3], birth = as.integer(words[4]), name = words[5], death = NA_integer_, parents = character())
    return(paste("ADDED", x, words[5], words[3], words[4]))
  }
  if (command == "DEATH") {
    year <- as.integer(words[3])
    person <- persons[[x]]
    if (!is.na(person$death)) fail("ALREADY DECEASED", x)
    years <- person$birth
    for (m in records_of(x)) years <- c(years, m$start, if (!is.na(m$end)) m$end)
    if (year < max(years)) fail("BAD YEAR", x)
    children <- id_order(children_of(x))
    for (child in children) if (persons[[child]]$birth > year + 1L) fail("AFTER DEATH", child, x)
    persons[[x]]$death <<- year
    index <- current_index(x)
    if (is.na(index)) return(paste("DIED", x, year))
    marriages[[index]]$end <<- year
    marriages[[index]]$status <<- "widowed"
    marriages[[index]]$died <<- x
    return(paste0("DIED ", x, " ", year, " spouse=", other_person(marriages[[index]], x)))
  }
  if (command == "REMOVE") {
    for (id in names(persons)) persons[[id]]$parents <<- setdiff(parents_of(id), x)
    marriages <<- marriages[!vapply(marriages, function(m) contains(m, x), logical(1))]
    persons[[x]] <<- NULL
    return(paste("REMOVED", x))
  }
  if (command == "PARENT") {
    if (x == y) fail("SAME PERSON", x)
    if (y %in% parents_of(x)) fail("ALREADY PARENT", x, y)
    if (length(parents_of(x)) == 2L) fail("TOO MANY PARENTS", x)
    if (is_ancestor(x, y)) fail("CYCLE", x, y)
    if (persons[[y]]$birth + 12L > persons[[x]]$birth) fail("AGE GAP", x, y)
    if (!is.na(persons[[y]]$death) && persons[[y]]$death + 1L < persons[[x]]$birth) fail("AFTER DEATH", x, y)
    persons[[x]]$parents <<- c(parents_of(x), y)
    return(paste("LINKED", x, y, gendered("parent", sex_of(y))))
  }
  if (command == "UNPARENT") {
    if (!(y %in% parents_of(x))) fail("NOT PARENT", x, y)
    persons[[x]]$parents <<- setdiff(parents_of(x), y)
    return(paste("UNLINKED", x, y))
  }
  if (command == "SPOUSE") {
    year <- as.integer(words[4])
    if (x == y) fail("SAME PERSON", x)
    for (id in c(x, y)) if (!is.na(persons[[id]]$death)) fail("DECEASED", id)
    for (id in c(x, y)) if (length(spouse_of(id))) fail("ALREADY MARRIED", id)
    if (is_ancestor(x, y) || is_ancestor(y, x) || are_siblings(x, y)) fail("CLOSE KIN", x, y)
    for (id in c(x, y)) if (year < persons[[id]]$birth + 16L) fail("TOO YOUNG", id)
    for (id in c(x, y)) for (m in records_of(id)) if (!is.na(m$end) && m$end >= year) fail("BAD YEAR", id)
    marriages[[length(marriages) + 1L]] <<- list(first = x, second = y, start = year, end = NA_integer_, status = "current", died = "")
    return(paste("MARRIED", x, y, year))
  }
  if (command == "DIVORCE") {
    year <- as.integer(words[4])
    if (!identical(spouse_of(x), y)) fail("NOT MARRIED", x, y)
    index <- current_index(x)
    if (year <= marriages[[index]]$start) fail("BAD YEAR", x)
    marriages[[index]]$end <<- year
    marriages[[index]]$status <<- "divorced"
    return(paste("DIVORCED", x, y, year))
  }
  if (command == "UNDO") {
    if (!length(history)) fail("NOTHING TO UNDO")
    saved <- history[[length(history)]]
    persons <<- saved$persons
    marriages <<- saved$marriages
    history[[length(history)]] <<- NULL
    return(paste("UNDONE", saved$line))
  }
  if (command == "INFO") {
    person <- persons[[x]]
    result <- c(paste("INFO", x, person$name, person$sex, life_years(person)), paste0("  parents: ", person_list(parents_of(x))))
    for (m in records_of(x)) result <- c(result, paste0("  marriage: ", other_person(m, x), " ", m$start, "-", if (is.na(m$end)) "" else m$end, " ", m$status))
    return(c(result, paste0("  children: ", person_list(children_of(x))),
             paste0("  siblings: ", person_list(siblings_of(x))), paste0("  inbreeding: ", fraction_text(inbreeding(x)))))
  }
  if (command == "RELATION") return(paste0("RELATION ", x, " ", y, ": ", relationship_text(x, y)))
  if (command == "RELATIVES") {
    lines <- character()
    for (id in id_order(setdiff(names(persons), x))) {
      relation <- relationship(id, x)
      if (length(relation)) lines <- c(lines, paste0("  ", id, ": ", paste(relation, collapse = ", ")))
    }
    return(c(paste("RELATIVES", x, length(lines)), lines))
  }
  if (command == "WHO") {
    query <- paste(words[-c(1L, 2L)], collapse = " ")
    lines <- character()
    for (id in id_order(setdiff(names(persons), x))) {
      relation <- relationship(id, x)
      neutral <- relationship(id, x, "X")
      matches <- which(relation == query | neutral == query)
      if (length(matches)) lines <- c(lines, paste0("  ", id, ": ", relation[matches[1]]))
    }
    return(c(paste("WHO", x, query, length(lines)), lines))
  }
  if (command == "PATH") {
    top <- apex(x, y)
    if (is.null(top)) return(paste("PATH", x, y, "none"))
    first <- upward_path(x, top$id)
    second <- upward_path(y, top$id)
    route <- c(first, rev(head(second, -1L)))
    return(paste0("PATH ", x, " ", y, " ", top$da + top$db, ": ", paste(route, collapse = " ")))
  }
  if (command == "COMMON") {
    da <- distances(x)
    db <- distances(y)
    shared <- intersect(names(da), names(db))
    nearest <- shared[vapply(shared, function(id) !any(children_of(id) %in% shared), logical(1))]
    nearest <- nearest[order(da[nearest] + db[nearest], nearest, method = "radix")]
    lines <- vapply(nearest, function(id) paste(" ", id, da[[id]], db[[id]]), character(1))
    return(c(paste("COMMON", x, y, length(nearest)), lines))
  }
  if (command %in% c("ANCESTORS", "DESCENDANTS")) {
    upward <- command == "ANCESTORS"
    d <- distances(x, upward)
    ids <- setdiff(names(d), x)
    ids <- ids[order(d[ids], ids, method = "radix")]
    lines <- vapply(ids, function(id) {
      g <- d[[id]]
      term <- if (upward) kinship_term(0L, g, sex_of(id)) else kinship_term(g, 0L, sex_of(id))
      paste(" ", g, id, term)
    }, character(1))
    return(c(paste(command, x, length(ids)), lines))
  }
  if (command == "COUSINS") {
    degree <- as.integer(words[3])
    matches <- list()
    for (id in setdiff(names(persons), x)) {
      top <- apex(id, x)
      if (!is.null(top) && top$da >= 2L && top$db >= 2L && min(top$da, top$db) - 1L == degree) {
        matches[[id]] <- list(removal = abs(top$da - top$db), term = blood_term(top, sex_of(id)))
      }
    }
    ids <- names(matches)
    ids <- ids[order(vapply(matches, `[[`, numeric(1), "removal"), ids, method = "radix")]
    lines <- vapply(ids, function(id) paste(" ", id, matches[[id]]$term), character(1))
    return(c(paste("COUSINS", x, degree, length(matches)), lines))
  }
  if (command == "SIBLINGS") {
    lines <- character()
    earlier <- 0L
    ordered <- age_order(names(persons))
    for (id in setdiff(ordered, x)) {
      common <- common_parents(x, id)
      kind <- if (common == 2L) "full" else if (common == 1L) "half" else if (step_related(parents_of(x), parents_of(id))) "step" else ""
      if (!nzchar(kind)) next
      if (kind != "step" && match(id, ordered) < match(x, ordered)) earlier <- earlier + 1L
      lines <- c(lines, paste(" ", id, kind, persons[[id]]$birth))
    }
    return(c(paste0("SIBLINGS ", x, " ", length(lines), " order=", earlier + 1L), lines))
  }
  if (command == "GENERATIONS") {
    d <- distances(x, FALSE)
    d <- d[names(d) != x]
    groups <- sort(unique(unname(d)))
    lines <- character()
    for (g in groups) {
      ids <- names(d)[d == g]
      births <- vapply(ids, function(id) persons[[id]]$birth, numeric(1))
      living <- sum(vapply(ids, function(id) is.na(persons[[id]]$death), logical(1)))
      lines <- c(lines, paste0("  ", g, " ", length(ids), " ", living, " ", min(births), "-", max(births)))
    }
    return(c(paste("GENERATIONS", x, length(groups)), lines))
  }
  if (command == "TREE") {
    lines <- character()
    visited <- character()
    visit <- function(id, depth) {
      indent <- strrep("  ", depth + 1L)
      if (id %in% visited) {
        lines <<- c(lines, paste0(indent, id, " (see above)"))
        return(invisible(NULL))
      }
      visited <<- c(visited, id)
      p <- persons[[id]]
      line <- paste0(indent, id, " ", p$name, " ", life_years(p))
      spouse <- spouse_of(id)
      if (length(spouse)) line <- paste(line, "=", spouse)
      lines <<- c(lines, line)
      for (child in age_order(children_of(id))) visit(child, depth + 1L)
      invisible(NULL)
    }
    visit(x, 0L)
    return(c(paste("TREE", x, length(distances(x, FALSE)) - 1L), lines))
  }
  if (command == "PEDIGREE") {
    depth <- as.integer(words[3])
    lines <- character()
    entered <- character()
    enter <- function(id, number, generation) {
      p <- persons[[id]]
      lines <<- c(lines, paste0(strrep("  ", generation + 1L), number, " ", id, " ", p$name, " ", life_years(p)))
      entered <<- union(entered, id)
      if (generation < depth) {
        parents <- parents_of(id)
        sexes <- vapply(parents, function(parent) sex_index[[sex_of(parent)]], integer(1))
        parents <- parents[order(sexes, parents, method = "radix")]
        for (i in seq_along(parents)) enter(parents[i], 2L * number + i - 1L, generation + 1L)
      }
      invisible(NULL)
    }
    enter(x, 1L, 0L)
    return(c(paste0("PEDIGREE ", x, " ", depth, " entries=", length(lines), " distinct=", length(entered)), lines))
  }
  if (command == "TIMELINE") {
    p <- persons[[x]]
    events <- list()
    event <- function(year, rank, counterpart, text) {
      events[[length(events) + 1L]] <<- list(year = year, rank = rank, counterpart = counterpart, text = text)
    }
    event(p$birth, 0L, "", "born")
    for (m in records_of(x)) {
      other <- other_person(m, x)
      event(m$start, 1L, other, paste("married", other))
      if (m$status == "divorced") event(m$end, 3L, other, paste("divorced", other))
      if (m$status == "widowed" && m$died == other) event(m$end, 4L, other, paste("widowed", other))
    }
    for (child in children_of(x)) event(persons[[child]]$birth, 2L, child, paste("child", child))
    relatives <- list(parent = parents_of(x), child = children_of(x))
    for (label in names(relatives)) for (other in relatives[[label]]) {
      death <- persons[[other]]$death
      if (!is.na(death) && death >= p$birth && (is.na(p$death) || death <= p$death)) event(death, 5L, other, paste("lost", label, other))
    }
    if (!is.na(p$death)) event(p$death, 6L, "", "died")
    ordering <- order(vapply(events, `[[`, numeric(1), "year"),
                      vapply(events, `[[`, integer(1), "rank"),
                      vapply(events, `[[`, character(1), "counterpart"), method = "radix")
    lines <- vapply(events[ordering], function(e) paste(" ", e$year, e$text), character(1))
    return(c(paste("TIMELINE", x, length(events)), lines))
  }
  if (command == "CENSUS") {
    year <- as.integer(words[2])
    residents <- names(persons)[vapply(persons, function(p) p$birth <= year && (is.na(p$death) || p$death > year), logical(1))]
    lines <- vapply(age_order(residents), function(id) paste(" ", id, year - persons[[id]]$birth, census_status(id, year)), character(1))
    return(c(paste("CENSUS", year, length(residents)), lines))
  }
  if (command == "KINSHIP") return(paste("KINSHIP", x, y, fraction_text(phi(x, y))))
  if (command == "FIND") {
    route <- words[3]
    steps <- strsplit(route, ".", fixed = TRUE)[[1]]
    current <- x
    for (step in steps) {
      kind <- if (step %in% c("parent", "father", "mother")) "parent" else if (step %in% c("child", "son", "daughter")) "child" else if (step %in% c("sibling", "brother", "sister")) "sibling" else "spouse"
      sex <- if (step %in% c("father", "son", "brother", "husband")) "M" else if (step %in% c("mother", "daughter", "sister", "wife")) "F" else ""
      collected <- character()
      for (id in current) {
        targets <- switch(kind, parent = parents_of(id), child = children_of(id), sibling = siblings_of(id), spouse = spouse_of(id))
        if (nzchar(sex)) targets <- targets[vapply(targets, function(target) sex_of(target) == sex, logical(1))]
        collected <- union(collected, targets)
      }
      current <- collected
    }
    current <- id_order(setdiff(current, x))
    lines <- vapply(current, function(id) paste0("  ", id, ": ", relationship_text(id, x)), character(1))
    return(c(paste("FIND", x, route, length(current)), lines))
  }
  if (command == "TERM") return(paste("TERM", words[2], words[3], words[4], kinship_term(as.integer(words[2]), as.integer(words[3]), words[4])))
  if (command == "STATS") {
    living <- sum(vapply(persons, function(p) is.na(p$death), logical(1)))
    links <- sum(vapply(persons, function(p) length(p$parents), integer(1)))
    couples <- sum(vapply(marriages, function(m) m$status == "current", logical(1)))
    founders <- sum(vapply(persons, function(p) !length(p$parents), logical(1)))
    generations <- max(c(0, vapply(names(persons), lineage_length, numeric(1))))
    return(paste0("STATS persons=", length(persons), " living=", living, " links=", links, " couples=", couples, " founders=", founders, " generations=", generations))
  }
  if (command == "AUDIT") {
    lines <- character()
    for (m in marriages) {
      top <- apex(m$first, m$second)
      if (!is.null(top)) lines <- c(lines, paste(" ", "marriage", m$first, m$second, blood_term(top, sex_of(m$first))))
    }
    for (id in id_order(names(persons))) {
      value <- inbreeding(id)
      if (value != 0) lines <- c(lines, paste(" ", "inbred", id, fraction_text(value)))
    }
    return(c(paste("AUDIT", length(lines)), lines))
  }
}
execute <- function(line) {
  children_cache <<- NULL
  distance_cache <<- new.env(parent = emptyenv())
  coefficient_cache <<- new.env(parent = emptyenv())
  height_cache <<- new.env(parent = emptyenv())
  words <- strsplit(line, " ", fixed = TRUE)[[1]]
  if (words[1] %in% modifying) {
    saved <- list(line = line, persons = persons, marriages = marriages)
    result <- handle_command(words)
    history[[length(history) + 1L]] <<- saved
    return(result)
  }
  handle_command(words)
}
input <- readLines(file("stdin"), warn = FALSE)
count <- as.integer(input[1])
output <- character()
for (i in seq_len(count)) {
  result <- tryCatch(execute(input[i + 1L]), command_error = function(e) paste("ERROR", e$message))
  output <- c(output, result)
}
writeLines(output)
