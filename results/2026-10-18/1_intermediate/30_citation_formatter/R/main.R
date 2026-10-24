upper_letters <- "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
lower_letters <- "abcdefghijklmnopqrstuvwxyz"
known_fields <- strsplit("author editor title journal booktitle edition volume number pages publisher institution school address howpublished month year doi note", " ", fixed = TRUE)[[1L]]
required_fields <- list(
  article = c("author", "title", "journal", "year"),
  book = c("author", "title", "publisher", "year"),
  inproceedings = c("author", "title", "booktitle", "year"),
  incollection = c("author", "title", "booktitle", "publisher", "year"),
  techreport = c("author", "title", "institution", "year"),
  phdthesis = c("author", "title", "school", "year"),
  misc = c("author", "title", "year")
)
small_words <- strsplit("a an and as at but by for from in into nor of on or over per so the to up via with yet", " ", fixed = TRUE)[[1L]]
month_names <- c("January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December")
month_short <- c("Jan.", "Feb.", "Mar.", "Apr.", "May", "June", "July", "Aug.", "Sep.", "Oct.", "Nov.", "Dec.")
styles <- c("APA", "IEEE", "CHICAGO", "MLA")

chars <- function(text) strsplit(text, "", fixed = TRUE)[[1L]]
lowercase <- function(text) chartr(upper_letters, lower_letters, text)
uppercase <- function(text) chartr(lower_letters, upper_letters, text)
plain <- function(text) gsub("[{}]", "", text)
letters_only <- function(text) lowercase(gsub("[^A-Za-z]", "", text))
all_digits <- function(text) grepl("^[0-9]+$", text)
emit <- function(text) cat(text, "\n", sep = "")
fail <- function(message) {
  stop(structure(list(message = message, call = NULL), class = c("bib_error", "error", "condition")))
}
split_fixed <- function(text, separator) strsplit(text, separator, fixed = TRUE)[[1L]]
trim_spaces <- function(text) trimws(text, whitespace = " ")

# Each delimiter contains no braces, so its matches can be filtered by depth.
depth_before <- function(text) {
  characters <- chars(text)
  c(0L, head(cumsum((characters == "{") - (characters == "}")), -1L))
}
split_depth <- function(text, separator) {
  positions <- gregexpr(separator, text, fixed = TRUE)[[1L]]
  positions <- positions[positions > 0L]
  positions <- positions[depth_before(text)[positions] == 0L]
  substring(text, c(1L, positions + nchar(separator)), c(positions - 1L, nchar(text)))
}
evaluate <- function(expression, macros) {
  characters <- chars(expression)
  depths <- cumsum((characters == "{") - (characters == "}"))
  if (any(depths < 0L) || tail(depths, 1L) != 0L) fail("unbalanced braces")
  terms <- split_fixed(expression, " # ")
  values <- vapply(terms, function(term) {
    if (substr(term, 1L, 1L) %in% c("{", '"')) return(substr(term, 2L, nchar(term) - 1L))
    if (all_digits(term)) return(term)
    value <- get0(term, envir = macros, inherits = FALSE)
    if (is.null(value)) fail(paste0("unknown macro '", term, "'"))
    value
  }, character(1L), USE.NAMES = FALSE)
  paste0(values, collapse = "")
}
accent_at <- function(characters, position) {
  size <- length(characters)
  if (position + 1L > size || characters[position] != "\\") return(NULL)
  command <- characters[position + 1L]
  if (command == "&") return(list(value = "&", width = 2L))
  symbol <- command %in% c("'", '"', "`", "^", "~", "=", ".")
  if (symbol && position + 2L <= size && grepl("^[A-Za-z]$", characters[position + 2L])) {
    return(list(value = characters[position + 2L], width = 3L))
  }
  if ((symbol || command %in% c("c", "u", "v", "H")) && position + 4L <= size &&
      characters[position + 2L] == "{" && grepl("^[A-Za-z]$", characters[position + 3L]) && characters[position + 4L] == "}") {
    return(list(value = characters[position + 3L], width = 5L))
  }
  NULL
}
normalize <- function(text) {
  characters <- chars(text)
  output <- character(length(characters))
  position <- 1L
  used <- 0L
  while (position <= length(characters)) {
    wrapped <- if (characters[position] == "{") accent_at(characters, position + 1L) else NULL
    if (!is.null(wrapped) && position + wrapped$width + 1L <= length(characters) &&
        characters[position + wrapped$width + 1L] == "}") {
      used <- used + 1L
      output[used] <- wrapped$value
      position <- position + wrapped$width + 2L
      next
    }
    found <- accent_at(characters, position)
    used <- used + 1L
    if (is.null(found)) {
      output[used] <- characters[position]
      position <- position + 1L
    } else {
      output[used] <- found$value
      position <- position + found$width
    }
  }
  value <- gsub("~", " ", paste0(output[seq_len(used)], collapse = ""), fixed = TRUE)
  trim_spaces(gsub(" +", " ", value))
}

parse_person <- function(text) {
  parts <- trim_spaces(split_depth(text, ","))
  words <- split_depth(parts[1L], " ")
  lowercase_words <- which(grepl("^[a-z]", head(words, -1L)))
  person <- list(first = "", von = "", last = "", junior = "")
  if (length(parts) == 1L) {
    if (!length(lowercase_words)) {
      person$first <- paste(head(words, -1L), collapse = " ")
      person$last <- tail(words, 1L)
    } else {
      start <- lowercase_words[1L]
      finish <- tail(lowercase_words, 1L)
      person$first <- paste(head(words, start - 1L), collapse = " ")
      person$von <- paste(words[seq.int(start, finish)], collapse = " ")
      person$last <- paste(words[seq.int(finish + 1L, length(words))], collapse = " ")
    }
  } else {
    finish <- if (length(lowercase_words)) tail(lowercase_words, 1L) else 0L
    person$von <- paste(head(words, finish), collapse = " ")
    person$last <- paste(words[seq.int(finish + 1L, length(words))], collapse = " ")
    person$first <- tail(parts, 1L)
    if (length(parts) == 3L) person$junior <- parts[2L]
  }
  person
}
parse_names <- function(text) {
  parts <- split_depth(text, " and ")
  etal <- tail(parts, 1L) == "others"
  if (etal) parts <- head(parts, -1L)
  list(names = lapply(parts, parse_person), etal = etal)
}
singular <- function(names) length(names$names) == 1L && !names$etal
surname <- function(person) plain(paste0(if (nzchar(person$von)) paste0(person$von, " ") else "", person$last))
initials <- function(first) {
  words <- split_fixed(plain(first), " ")
  words <- words[nzchar(words)]
  formatted <- vapply(words, function(word) {
    pieces <- split_fixed(word, "-")
    paste0(uppercase(substr(letters_only(pieces), 1L, 1L)), ".", collapse = "-")
  }, character(1L), USE.NAMES = FALSE)
  paste(formatted, collapse = " ")
}
name_text <- function(person, inverted, abbreviated) {
  given <- if (abbreviated) initials(person$first) else plain(person$first)
  result <- surname(person)
  if (nzchar(person$first)) result <- if (inverted) paste0(result, ", ", given) else paste(given, result)
  if (nzchar(person$junior)) result <- paste0(result, ", ", plain(person$junior))
  result
}
field <- function(entry, name) {
  value <- entry$fields[[name]]
  if (is.null(value)) "" else value
}
has_field <- function(entry, name) name %in% names(entry$fields)
make_entry <- function(key, kind, fields) {
  primary <- parse_names(fields[[if ("author" %in% names(fields)) "author" else "editor"]])
  title <- sub("^(a |an |the )", "", lowercase(plain(fields[["title"]])))
  list(key = key, kind = kind, fields = fields, primary = primary,
       editor = if ("editor" %in% names(fields)) parse_names(fields[["editor"]]) else NULL,
       sort_last = lowercase(plain(primary$names[[1L]]$last)), year = plain(fields[["year"]]),
       sort_title = title, suffix = "")
}
ordered_entries <- function(entries, indices = seq_along(entries), title_only = FALSE) {
  values <- function(name) vapply(entries[indices], `[[`, character(1L), name)
  ordering <- if (title_only) order(values("sort_title"), values("key"), method = "radix") else
    order(values("sort_last"), values("year"), values("sort_title"), values("key"), method = "radix")
  indices[ordering]
}
read_database <- function(lines) {
  database <- new.env(parent = emptyenv())
  database$entries <- list()
  database$keys <- character()
  database$record <- integer()
  macros <- new.env(hash = TRUE, parent = emptyenv())
  for (i in seq_along(month_names)) assign(substr(lowercase(month_names[i]), 1L, 3L), month_names[i], envir = macros)
  errors <- 0L
  position <- 1L
  while (position <= length(lines)) {
    line <- lines[position]
    if (!nzchar(line) || startsWith(line, "%")) {
      position <- position + 1L
      next
    }
    reason <- ""
    error_line <- position
    if (startsWith(line, "@string{")) {
      separator <- regexpr(" = ", line, fixed = TRUE)[1L]
      name <- substr(line, 9L, separator - 1L)
      expression <- substr(line, separator + 3L, nchar(line) - 1L)
      tryCatch({
        value <- evaluate(expression, macros)
        if (exists(name, envir = macros, inherits = FALSE)) fail("duplicate macro")
        assign(name, value, envir = macros)
      }, bib_error = function(problem) reason <<- conditionMessage(problem))
    } else {
      opening <- regexpr("{", line, fixed = TRUE)[1L]
      kind <- substr(line, 2L, opening - 1L)
      name <- substr(line, opening + 1L, nchar(line) - 1L)
      fields <- list()
      if (!(kind %in% names(required_fields))) reason <- paste0("unknown type '", kind, "'") else
        if (name %in% database$keys) reason <- "duplicate key"
      position <- position + 1L
      while (lines[position] != "}") {
        if (!nzchar(reason)) {
          field_line <- lines[position]
          separator <- regexpr(" = ", field_line, fixed = TRUE)[1L]
          field_name <- substr(field_line, 3L, separator - 1L)
          expression <- substr(field_line, separator + 3L, nchar(field_line) - as.integer(endsWith(field_line, ",")))
          tryCatch({
            value <- evaluate(expression, macros)
            if (field_name %in% names(fields)) fail(paste0("duplicate field '", field_name, "'"))
            fields[[field_name]] <- normalize(value)
          }, bib_error = function(problem) {
            reason <<- conditionMessage(problem)
            error_line <<- position
          })
        }
        position <- position + 1L
      }
      if (!nzchar(reason)) {
        for (required in required_fields[[kind]]) {
          if (required %in% names(fields) || (kind == "book" && required == "author" && "editor" %in% names(fields))) next
          reason <- paste0("missing field '", required, "'")
          error_line <- position
          break
        }
      }
      if (!nzchar(reason)) {
        database$keys <- c(database$keys, name)
        database$entries[[length(database$entries) + 1L]] <- make_entry(name, kind, fields)
      }
    }
    if (nzchar(reason)) {
      errors <- errors + 1L
      emit(paste0("ERROR line ", error_line, ": ", name, ": ", reason))
    }
    position <- position + 1L
  }
  emit(paste0("LOADED entries=", length(database$entries), " macros=", length(ls(macros)) - 12L, " errors=", errors))
  database$bibliography <- ordered_entries(database$entries)
  assigned <- rep(FALSE, length(database$entries))
  for (i in seq_along(database$entries)) {
    if (assigned[i]) next
    entry <- database$entries[[i]]
    group <- which(vapply(database$entries, function(other) identical(entry$primary, other$primary) &&
      identical(field(entry, "year"), field(other, "year")), logical(1L)))
    assigned[group] <- TRUE
    if (length(group) >= 2L) {
      group <- ordered_entries(database$entries, group, TRUE)
      for (j in seq_along(group)) database$entries[[group[j]]]$suffix <- substr(lower_letters, j, j)
    }
  }
  database
}

list_names <- function(names, conjunction, list_b = FALSE) {
  if (length(names) == 1L) return(names[1L])
  if (list_b && length(names) == 2L) return(paste(names, collapse = paste0(" ", conjunction, " ")))
  paste0(paste(head(names, -1L), collapse = ", "), ", ", conjunction, " ", tail(names, 1L))
}
author_names <- function(list, style) {
  forms <- vapply(seq_along(list$names), function(i) {
    name_text(list$names[[i]], style == "APA" || (style %in% c("CHICAGO", "MLA") && i == 1L), style %in% c("APA", "IEEE"))
  }, character(1L))
  if (style == "APA") {
    if (list$etal) return(paste0(paste(forms, collapse = ", "), ", et al."))
    if (length(forms) >= 21L) return(paste0(paste(head(forms, 19L), collapse = ", "), ", . . . ", tail(forms, 1L)))
    return(list_names(forms, "&"))
  }
  if (style == "IEEE") return(if (list$etal || length(forms) >= 7L) paste0(forms[1L], " et al.") else list_names(forms, "and", TRUE))
  if (style == "CHICAGO") return(if (list$etal || length(forms) >= 11L) paste0(paste(head(forms, 7L), collapse = ", "), ", et al.") else list_names(forms, "and"))
  if (list$etal || length(forms) >= 3L) paste0(forms[1L], ", et al.") else list_names(forms, "and")
}
editor_names <- function(list, style) {
  if (is.null(list)) return("")
  forms <- vapply(list$names, name_text, character(1L), inverted = FALSE, abbreviated = style %in% c("APA", "IEEE"))
  if (list$etal) paste0(forms[1L], " et al.") else list_names(forms, if (style == "APA") "&" else "and", TRUE)
}
year_label <- function(entry, style) paste0(entry$year, if (style %in% c("APA", "CHICAGO")) entry$suffix else "")
convert_outside <- function(text, mode) {
  characters <- chars(text)
  depths <- depth_before(text)
  letters <- which(grepl("^[A-Za-z]$", characters))
  outside <- letters[depths[letters] == 0L]
  if (mode %in% c(0L, 1L)) characters[outside] <- lowercase(characters[outside])
  if (mode == 1L) {
    colons <- gregexpr(": ", text, fixed = TRUE)[[1L]]
    capitals <- intersect(outside, c(1L, colons[colons > 0L] + 2L))
    characters[capitals] <- uppercase(characters[capitals])
  } else if (mode == 2L && length(letters) && depths[letters[1L]] == 0L) {
    characters[letters[1L]] <- uppercase(characters[letters[1L]])
  }
  paste0(characters, collapse = "")
}
title_text <- function(title, style) {
  if (style == "IEEE") return(plain(title))
  if (style == "APA") return(plain(convert_outside(title, 1L)))
  words <- split_depth(title, " ")
  converted <- vapply(seq_along(words), function(i) {
    word <- words[i]
    if (startsWith(word, "{")) return(word)
    small <- i > 1L && i < length(words) && !endsWith(words[i - 1L], ":") && letters_only(word) %in% small_words
    convert_outside(word, if (small) 0L else 2L)
  }, character(1L))
  plain(paste(converted, collapse = " "))
}

template_sources <- list(
  APA = c(
    article = "{author}. ({year}). {title}. {journal}<, {volume}<({number})>><, {pages}>.< https://doi.org/{doi}>",
    book = "{author}. ({year}). {title}< ({edition})>. {publisher}.",
    inproceedings = "{author}. ({year}). {title}. In <{editor} ({eds}), >{booktitle}< ({pp})>.< {publisher}.>",
    techreport = "{author}. ({year}). {title}< (Report No. {number})>. {institution}.",
    phdthesis = "{author}. ({year}). {title} [Doctoral dissertation, {school}].",
    misc = "{author}. ({year}<, {month}>). {title}.< {howpublished}.>< {note}.>"
  ),
  IEEE = c(
    article = '{author}, "{title}," {journal}<, vol. {volume}><, no. {number}><, {pp}>, <{mon} >{year}<, doi: {doi}>.',
    book = "{author}, {title}<, {edition}>. <{address}: >{publisher}, {year}.",
    inproceedings = '{author}, "{title}," in {booktitle}<, {editor}, {eds}><, {address}><, {publisher}>, {year}<, {pp}>.',
    techreport = '{author}, "{title}," {institution}<, {address}>, Tech. Rep.< {number}>, {year}.',
    phdthesis = '{author}, "{title}," Ph.D. dissertation, {school}<, {address}>, {year}.',
    misc = '{author}, "{title},"< {howpublished},> <{mon} >{year}.< {note}.>'
  ),
  CHICAGO = c(
    article = '{author}. {year}. "{title}." {journal}< {volume}>< ({number})><: {pages}>.< https://doi.org/{doi}.>',
    book = "{author}. {year}. {title}.< {edition}.> <{address}: >{publisher}.",
    inproceedings = '{author}. {year}. "{title}." In {booktitle}<, edited by {editor}><, {pages}>.< <{address}: >{publisher}.>',
    techreport = "{author}. {year}. {title}. Technical Report< {number}>. <{address}: >{institution}.",
    phdthesis = '{author}. {year}. "{title}." PhD diss., {school}.',
    misc = "{author}. {year}. {title}.< {howpublished}.>< {note}.>"
  ),
  MLA = c(
    article = '{author}. "{title}." {journal}<, vol. {volume}><, no. {number}>, <{mon} >{year}<, {pp}>.< https://doi.org/{doi}.>',
    book = "{author}. {title}.< {edition},> {publisher}, {year}.",
    inproceedings = '{author}. "{title}." {booktitle},< edited by {editor},>< {publisher},> {year}<, {pp}>.',
    techreport = "{author}. {title}. {institution}, {year}.< Technical Report {number}.>",
    phdthesis = "{author}. {title}. {year}. {school}, PhD dissertation.",
    misc = "{author}. {title}.< {howpublished},> <{mon} >{year}.< {note}.>"
  )
)
parse_template <- function(source) {
  characters <- chars(source)
  position <- 1L
  parse <- function() {
    nodes <- list()
    while (position <= length(characters) && characters[position] != ">") {
      character <- characters[position]
      position <<- position + 1L
      if (character == "{") {
        start <- position
        while (characters[position] != "}") position <<- position + 1L
        node <- list(kind = "value", text = substr(source, start, position - 1L))
        position <<- position + 1L
      } else if (character == "<") {
        node <- list(kind = "optional", children = parse())
        position <<- position + 1L
      } else {
        node <- list(kind = "literal", text = character)
      }
      nodes[[length(nodes) + 1L]] <- node
    }
    nodes
  }
  parse()
}
templates <- lapply(template_sources, function(style) lapply(style, parse_template))
render_template <- function(nodes, values) {
  pieces <- character()
  last <- ""
  append <- function(text) {
    if (!nzchar(text)) return(invisible(NULL))
    pieces <<- c(pieces, text)
    last <<- substr(text, nchar(text), nchar(text))
  }
  render <- function(nodes) {
    for (node in nodes) {
      if (node$kind == "value") {
        append(values[[node$text]])
      } else if (node$kind == "optional") {
        direct <- Filter(function(child) child$kind == "value", node$children)
        if (all(vapply(direct, function(child) nzchar(values[[child$text]]), logical(1L)))) render(node$children)
      } else if (node$text != "." || !(last %in% c(".", "?", "!"))) {
        append(node$text)
      }
    }
  }
  render(nodes)
  paste0(pieces, collapse = "")
}
placeholder_values <- function(entry, style, repeated) {
  values <- lapply(setNames(known_fields, known_fields), function(name) plain(field(entry, name)))
  values$eds <- values$pp <- values$mon <- ""
  values$author <- if (repeated) "---" else author_names(entry$primary, style)
  if (!has_field(entry, "author")) {
    labels <- switch(style, APA = c(" (Ed.)", " (Eds.)"), IEEE = c(", Ed.", ", Eds."),
                     CHICAGO = c(", ed.", ", eds."), MLA = c(", editor", ", editors"))
    values$author <- paste0(values$author, labels[if (singular(entry$primary)) 1L else 2L])
  }
  values$editor <- editor_names(entry$editor, style)
  if (!is.null(entry$editor)) values$eds <- if (singular(entry$editor)) "Ed." else "Eds."
  values$title <- title_text(field(entry, "title"), style)
  values$year <- year_label(entry, style)
  values$pages <- gsub("--", "-", values$pages, fixed = TRUE)
  if (has_field(entry, "pages")) values$pp <- paste0(if (grepl("-", values$pages, fixed = TRUE)) "pp. " else "p. ", values$pages)
  if (has_field(entry, "edition")) {
    edition <- values$edition
    if (all_digits(edition)) {
      number <- as.integer(edition)
      suffix <- if (number %% 100L %in% 11L:13L) "th" else
        switch(as.character(number %% 10L), "1" = "st", "2" = "nd", "3" = "rd", "th")
      edition <- paste0(edition, suffix)
    }
    values$edition <- paste0(edition, " ed.")
  }
  if (has_field(entry, "month")) {
    found <- match(values$month, month_names)
    values$mon <- if (is.na(found)) values$month else month_short[found]
  }
  values
}
reference <- function(entry, style, number = 0L, repeated = FALSE) {
  kind <- if (entry$kind == "incollection") "inproceedings" else entry$kind
  result <- render_template(templates[[style]][[kind]], placeholder_values(entry, style, repeated))
  if (style == "IEEE") paste0("[", number, "] ", result) else result
}
ieee_order <- function(database) {
  remaining <- setdiff(seq_along(database$entries), database$record)
  c(database$record, remaining[order(database$keys[remaining], method = "radix")])
}
ieee_numbers <- function(database) {
  result <- integer(length(database$entries))
  result[ieee_order(database)] <- seq_along(result)
  result
}
short_name <- function(entry, style, parenthetical = FALSE) {
  names <- vapply(entry$primary$names, surname, character(1L))
  threshold <- if (style == "CHICAGO") 4L else 3L
  if (entry$primary$etal || length(names) >= threshold) return(paste0(names[1L], " et al."))
  list_names(names, if (style == "APA" && parenthetical) "&" else "and", TRUE)
}
citation_text <- function(database, citation, style, numbers) {
  indices <- citation$indices
  kind <- citation$kind
  parenthetical <- kind %in% c("cite", "citep")
  if (parenthetical && style %in% c("APA", "CHICAGO")) indices <- ordered_entries(database$entries, indices)
  entries <- database$entries[indices]
  names <- vapply(entries, short_name, character(1L), style = style, parenthetical = parenthetical)
  years <- vapply(entries, year_label, character(1L), style = style)
  if (kind == "citeauthor") return(paste(names, collapse = "; "))
  if (kind == "citeyear") return(paste(years, collapse = ", "))
  if (style == "MLA") {
    result <- paste(names, collapse = "; ")
    return(if (parenthetical) paste0("(", result, ")") else result)
  }
  if (style == "IEEE") {
    if (!parenthetical) return(paste0(names, " [", numbers[indices], "]", collapse = "; "))
    ordered <- sort(numbers[indices])
    ranges <- split(ordered, cumsum(c(TRUE, diff(ordered) != 1L)))
    parts <- lapply(ranges, function(range) if (length(range) >= 3L) paste0("[", range[1L], "]-[", tail(range, 1L), "]") else paste0("[", range, "]"))
    return(paste(unlist(parts, use.names = FALSE), collapse = ", "))
  }
  lengths <- rle(names)$lengths
  finishes <- cumsum(lengths)
  starts <- c(1L, head(finishes, -1L) + 1L)
  groups <- vapply(seq_along(starts), function(i) {
    years_text <- paste(years[seq.int(starts[i], finishes[i])], collapse = ", ")
    if (!parenthetical) paste0(names[starts[i]], " (", years_text, ")") else
      paste0(names[starts[i]], if (style == "APA") ", " else " ", years_text)
  }, character(1L))
  result <- paste(groups, collapse = "; ")
  if (parenthetical) paste0("(", result, ")") else result
}
cite <- function(database, style, text) {
  starts <- gregexpr("\\", text, fixed = TRUE)[[1L]]
  starts <- starts[starts > 0L]
  citations <- lapply(starts, function(start) {
    opening <- start - 1L + regexpr("{", substring(text, start), fixed = TRUE)[1L]
    finish <- opening - 1L + regexpr("}", substring(text, opening), fixed = TRUE)[1L]
    keys <- unique(split_fixed(substr(text, opening + 1L, finish - 1L), ","))
    indices <- match(keys, database$keys)
    missing <- which(is.na(indices))
    if (length(missing)) fail(paste0("unknown key '", keys[missing[1L]], "'"))
    list(start = start, finish = finish, kind = substr(text, start + 1L, opening - 1L), indices = indices)
  })
  # All keys have been checked; every citation uses this complete new record.
  database$record <- unique(c(database$record, unlist(lapply(citations, `[[`, "indices"), use.names = FALSE)))
  numbers <- ieee_numbers(database)
  pieces <- character()
  position <- 1L
  for (citation in citations) {
    pieces <- c(pieces, substr(text, position, citation$start - 1L), citation_text(database, citation, style, numbers))
    position <- citation$finish + 1L
  }
  paste0(c(pieces, substring(text, position)), collapse = "")
}

keygen <- function(database) {
  bases <- vapply(database$entries, function(entry) {
    words <- letters_only(split_fixed(plain(field(entry, "title")), " "))
    words <- words[nzchar(words) & !(words %in% small_words)]
    paste0(letters_only(plain(entry$primary$names[[1L]]$last)), gsub("[^0-9]", "", field(entry, "year")),
           if (length(words)) words[1L] else "")
  }, character(1L))
  groups <- match(bases, unique(bases))
  totals <- tabulate(groups)
  seen <- integer(length(totals))
  for (i in seq_along(bases)) {
    group <- groups[i]
    suffix <- if (totals[group] >= 2L) intToUtf8(97L + seen[group]) else ""
    seen[group] <- seen[group] + 1L
    emit(paste0(database$keys[i], " -> ", bases[i], suffix))
  }
}
check_entries <- function(database) {
  warnings <- 0L
  titles <- character()
  for (i in seq_along(database$entries)) {
    entry <- database$entries[[i]]
    messages <- character()
    pages <- plain(field(entry, "pages"))
    if (has_field(entry, "pages")) {
      if (grepl("-", pages, fixed = TRUE) && !grepl("--", pages, fixed = TRUE)) messages <- c(messages, "pages use a single hyphen")
      parts <- split_fixed(pages, "-")
      parts <- parts[nzchar(parts)]
      if (length(parts) == 2L && all(all_digits(parts)) && as.integer(parts[1L]) > as.integer(parts[2L])) messages <- c(messages, "pages are reversed")
    }
    if (!grepl("^[0-9]{4}$", entry$year)) messages <- c(messages, "year is not 4 digits")
    title <- plain(field(entry, "title"))
    if (!grepl("[a-z]", title) && sum(grepl("^[A-Z]$", chars(title))) >= 2L) messages <- c(messages, "title is all caps")
    if (entry$kind == "article" && !has_field(entry, "doi")) messages <- c(messages, "article has no doi")
    previous <- match(lowercase(title), titles)
    if (!is.na(previous)) messages <- c(messages, paste0("same title as ", database$keys[previous]))
    titles <- c(titles, lowercase(title))
    unknown <- sort(setdiff(names(entry$fields), known_fields), method = "radix")
    if (length(unknown)) messages <- c(messages, paste0("unknown field '", unknown, "'"))
    for (message in messages) emit(paste0("WARN ", entry$key, ": ", message))
    warnings <- warnings + length(messages)
  }
  emit(paste0("CHECK warnings=", warnings))
}
export_entry <- function(entry) {
  fields <- c(known_fields[known_fields %in% names(entry$fields)], sort(setdiff(names(entry$fields), known_fields), method = "radix"))
  emit(paste0("@", entry$kind, "{", entry$key, ","))
  for (i in seq_along(fields)) emit(paste0("  ", fields[i], " = {", field(entry, fields[i]), "}", if (i < length(fields)) "," else ""))
  emit("}")
}
statistics <- function(database) {
  entries <- database$entries
  emit(paste0("ENTRIES ", length(entries)))
  for (property in c("kind", "year")) {
    values <- vapply(entries, `[[`, character(1L), property)
    for (value in sort(unique(values), method = "radix")) emit(paste(if (property == "kind") "TYPE" else "YEAR", value, sum(values == value)))
  }
  authors <- character()
  pairs <- list()
  for (entry in entries) {
    if (!has_field(entry, "author")) next
    names <- sort(unique(vapply(entry$primary$names, name_text, character(1L), inverted = FALSE, abbreviated = FALSE)), method = "radix")
    authors <- union(authors, names)
    if (length(names) >= 2L) {
      for (i in seq_len(length(names) - 1L)) {
        for (j in seq.int(i + 1L, length(names))) pairs[[length(pairs) + 1L]] <- c(names[i], names[j])
      }
    }
  }
  emit(paste0("AUTHORS ", length(authors)))
  if (!length(pairs)) {
    emit("PAIR none")
    return(invisible(NULL))
  }
  a <- vapply(pairs, `[`, character(1L), 1L)
  b <- vapply(pairs, `[`, character(1L), 2L)
  keys <- paste(a, b, sep = "\t")
  counts <- tabulate(match(keys, unique(keys)))
  first <- !duplicated(keys)
  choice <- order(-counts, a[first], b[first], method = "radix")[1L]
  emit(paste0("PAIR ", a[first][choice], " & ", b[first][choice], " ", counts[choice]))
}

execute <- function(database, line) {
  words <- split_fixed(line, " ")
  command <- words[1L]
  if (!(command %in% c("FORMAT", "BIBLIOGRAPHY", "CITE", "KEYGEN", "CHECK", "SEARCH", "EXPORT", "STATS"))) fail(paste0("unknown command '", command, "'"))
  if (command %in% c("CITE", "SEARCH")) {
    spaces <- gregexpr(" ", line, fixed = TRUE)[[1L]]
    spaces <- head(spaces[spaces > 0L], 2L)
    words <- substring(line, c(1L, spaces + 1L), c(spaces - 1L, nchar(line)))
  }
  count <- length(words) - 1L
  expected <- switch(command, BIBLIOGRAPHY = 1L, CITE = 2L, SEARCH = 2L, EXPORT = 1L, 0L)
  if (if (command == "FORMAT") count < 2L else count != expected) fail("wrong number of arguments")
  if (command %in% c("FORMAT", "BIBLIOGRAPHY", "CITE") && !(words[2L] %in% styles)) fail(paste0("unknown style '", words[2L], "'"))
  if (command == "FORMAT") {
    numbers <- ieee_numbers(database)
    for (key in words[-c(1L, 2L)]) {
      index <- match(key, database$keys)
      if (is.na(index)) emit(paste0("ERROR unknown key '", key, "'")) else emit(reference(database$entries[[index]], words[2L], numbers[index]))
    }
  } else if (command == "BIBLIOGRAPHY") {
    style <- words[2L]
    emit(if (style == "MLA") "Works Cited" else "References")
    order <- if (style == "IEEE") ieee_order(database) else database$bibliography
    numbers <- ieee_numbers(database)
    previous <- NULL
    for (index in order) {
      entry <- database$entries[[index]]
      repeated <- style %in% c("CHICAGO", "MLA") && identical(previous, entry$primary)
      emit(reference(entry, style, numbers[index], repeated))
      previous <- entry$primary
    }
  } else if (command == "CITE") {
    emit(cite(database, words[2L], words[3L]))
  } else if (command == "KEYGEN") {
    keygen(database)
  } else if (command == "CHECK") {
    check_entries(database)
  } else if (command == "SEARCH") {
    query <- lowercase(words[3L])
    matches <- which(vapply(database$entries, function(entry) has_field(entry, words[2L]) && grepl(query, lowercase(plain(field(entry, words[2L]))), fixed = TRUE), logical(1L)))
    emit(if (length(matches)) paste0("MATCHES ", length(matches), ": ", paste(database$keys[matches], collapse = " ")) else "MATCHES 0")
  } else if (command == "EXPORT") {
    index <- match(words[2L], database$keys)
    if (is.na(index)) fail(paste0("unknown key '", words[2L], "'"))
    export_entry(database$entries[[index]])
  } else {
    statistics(database)
  }
  invisible(NULL)
}

input <- readLines(file("stdin"), warn = FALSE)
separator <- match("%%", input)
database <- read_database(head(input, separator - 1L))
command_count <- as.integer(input[separator + 1L])
for (i in seq_len(command_count)) {
  tryCatch(execute(database, input[separator + 1L + i]), bib_error = function(problem) emit(paste0("ERROR ", conditionMessage(problem))))
}
