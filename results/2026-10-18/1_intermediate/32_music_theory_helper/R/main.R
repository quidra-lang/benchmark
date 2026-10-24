letters <- strsplit("CDEFGAB", "", fixed = TRUE)[[1L]]
naturals <- c(0L, 2L, 4L, 5L, 7L, 9L, 11L)
fifths_values <- c(0L, 2L, 4L, -1L, 1L, 3L, 5L)
accidentals <- c("bb", "b", "", "#", "x")
sharp_names <- strsplit("C C# D D# E F F# G G# A A# B", " ", fixed = TRUE)[[1L]]
flat_names <- strsplit("C Db D Eb E F Gb G Ab A Bb B", " ", fixed = TRUE)[[1L]]
romans <- c("I", "II", "III", "IV", "V", "VI", "VII")
interval_qualities <- c("P", "M", "m", "A", "d", "AA", "dd")

fail <- function(message) {
  stop(structure(list(message = paste0("ERROR ", message)),
                 class = c("music_error", "error", "condition")))
}
bad <- function(kind, word) fail(paste("BAD", kind, word))
words <- function(text) strsplit(text, " ", fixed = TRUE)[[1L]]
joined <- function(values, separator = " ") paste(values, collapse = separator)

bounded_integer <- function(text, kind, low, high) {
  if (nchar(text) > 3L || !grepl("^(0|[1-9][0-9]*)$", text)) bad(kind, text)
  value <- as.integer(text)
  if (value < low || value > high) bad(kind, text)
  value
}
parse_frequency <- function(text, tuning) {
  if (!grepl("^[0-9]{1,5}(\\.[0-9]{1,2})?$", text)) bad("FREQUENCY", text)
  parts <- strsplit(text, ".", fixed = TRUE)[[1L]]
  value <- as.integer(parts[[1L]]) * 100L
  if (length(parts) == 2L) {
    value <- value + as.integer(parts[[2L]]) * if (nchar(parts[[2L]]) == 1L) 10L else 1L
  }
  if (value == 0L || (tuning && (value < 40000L || value > 48000L))) bad("FREQUENCY", text)
  value
}
frequency_text <- function(cents) sprintf("%d.%02d", cents %/% 100L, cents %% 100L)

# A pitch retains its letter independently of its pitch class.
new_pitch <- function(letter, alteration) c(letter = letter, alteration = alteration)
pitch_class <- function(pitch) (naturals[pitch[["letter"]] + 1L] + pitch[["alteration"]]) %% 12L
pitch_text <- function(pitch) paste0(letters[pitch[["letter"]] + 1L], accidentals[pitch[["alteration"]] + 3L])
pitch_prefix <- function(text, kind) {
  first <- substr(text, 1L, 1L)
  letter <- match(first, letters)
  if (is.na(letter)) bad(kind, text)
  end <- 2L
  alteration <- 0L
  next_char <- substr(text, end, end)
  if (next_char == "b") {
    alteration <- -1L
    end <- end + 1L
    if (substr(text, end, end) == "b") {
      alteration <- -2L
      end <- end + 1L
    }
  } else if (next_char == "#") {
    alteration <- 1L
    end <- end + 1L
  } else if (next_char == "x") {
    alteration <- 2L
    end <- end + 1L
  }
  list(pitch = new_pitch(letter - 1L, alteration), rest = substring(text, end))
}
parse_pitch <- function(text) {
  parsed <- pitch_prefix(text, "PITCH")
  if (parsed$rest != "") bad("PITCH", text)
  parsed$pitch
}
new_note <- function(pitch, octave) {
  list(pitch = pitch, octave = octave,
       midi = 12L * (octave + 1L) + naturals[pitch[["letter"]] + 1L] + pitch[["alteration"]],
       position = 7L * octave + pitch[["letter"]])
}
valid_note <- function(note) note$octave >= -1L && note$octave <= 9L && note$midi >= 0L && note$midi <= 127L
note_text <- function(note) paste0(pitch_text(note$pitch), note$octave)
parse_note <- function(text) {
  parsed <- pitch_prefix(text, "NOTE")
  if (!grepl("^(-1|[0-9])$", parsed$rest)) bad("NOTE", text)
  note <- new_note(parsed$pitch, as.integer(parsed$rest))
  if (!valid_note(note)) bad("NOTE", text)
  note
}
make_note <- function(pitch, midi) {
  new_note(pitch, (midi - naturals[pitch[["letter"]] + 1L] - pitch[["alteration"]]) %/% 12L - 1L)
}
spelling <- function(midi, flat = FALSE) {
  names <- if (flat) flat_names else sharp_names
  new_note(parse_pitch(names[midi %% 12L + 1L]), midi %/% 12L - 1L)
}
fifth_pitch <- function(value) {
  new_pitch(c(3L, 0L, 4L, 1L, 5L, 2L, 6L)[(value + 1L) %% 7L + 1L], (value + 1L) %/% 7L)
}

quality_delta <- function(quality, number) {
  if ((number - 1L) %% 7L %in% c(0L, 3L, 4L)) {
    c(0L, NA_integer_, NA_integer_, 1L, -1L, 2L, -2L)[quality]
  } else c(NA_integer_, 0L, -1L, 1L, -2L, 2L, -3L)[quality]
}
new_interval <- function(quality, number) list(quality = quality, number = number)
forbidden_interval <- function(interval) interval$number == 1L && interval$quality %in% c(5L, 7L)
parse_interval <- function(text) {
  for (quality in seq_along(interval_qualities)) {
    prefix <- interval_qualities[quality]
    if (!startsWith(text, prefix)) next
    rest <- substring(text, nchar(prefix) + 1L)
    if (!grepl("^[1-9][0-9]?$", rest)) next
    number <- as.integer(rest)
    interval <- new_interval(quality, number)
    if (!is.na(quality_delta(quality, number)) && !forbidden_interval(interval)) return(interval)
  }
  bad("INTERVAL", text)
}
interval_text <- function(interval) paste0(interval_qualities[interval$quality], interval$number)
simple_interval <- function(interval) {
  while (interval$number > 8L) interval$number <- interval$number - 7L
  interval
}
interval_tone <- function(interval) {
  distance <- interval$number - 1L
  c(letters = distance,
    semitones = 12L * (distance %/% 7L) + naturals[distance %% 7L + 1L] + quality_delta(interval$quality, interval$number))
}
consonance <- function(interval) {
  simple <- simple_interval(interval)
  if (simple$quality == 1L && simple$number %in% c(1L, 5L, 8L)) return("perfect")
  if (simple$quality %in% c(2L, 3L) && simple$number %in% c(3L, 6L)) return("imperfect")
  "dissonant"
}
between <- function(first, second) {
  distance <- second$position - first$position
  semitones <- second$midi - first$midi
  down <- distance < 0L || (distance == 0L && semitones < 0L)
  if (down) {
    distance <- -distance
    semitones <- -semitones
  }
  difference <- semitones - 12L * (distance %/% 7L) - naturals[distance %% 7L + 1L]
  for (quality in seq_along(interval_qualities)) {
    delta <- quality_delta(quality, distance + 1L)
    if (!is.na(delta) && delta == difference) {
      return(list(interval = new_interval(quality, distance + 1L), down = down, semitones = semitones))
    }
  }
  fail("UNNAMEABLE INTERVAL")
}
raise_pitch <- function(root, tone) {
  target <- root[["letter"]] + tone[["letters"]]
  alteration <- naturals[root[["letter"]] + 1L] + root[["alteration"]] + tone[["semitones"]] -
    naturals[target %% 7L + 1L] - 12L * (target %/% 7L)
  if (alteration < -2L || alteration > 2L) fail("CANNOT SPELL")
  new_pitch(target %% 7L, alteration)
}
make_tones <- function(text) lapply(words(text), function(word) interval_tone(parse_interval(word)))
build <- function(root, tones) lapply(tones, function(tone) raise_pitch(root, tone))
pitches_text <- function(pitches) joined(vapply(pitches, pitch_text, character(1L)))
notes_text <- function(notes) joined(vapply(notes, note_text, character(1L)))

scale_rows <- c(
  major = "P1 M2 M3 P4 P5 M6 M7", natural_minor = "P1 M2 m3 P4 P5 m6 m7",
  harmonic_minor = "P1 M2 m3 P4 P5 m6 M7", melodic_minor = "P1 M2 m3 P4 P5 M6 M7",
  ionian = "P1 M2 M3 P4 P5 M6 M7", dorian = "P1 M2 m3 P4 P5 M6 m7",
  phrygian = "P1 m2 m3 P4 P5 m6 m7", lydian = "P1 M2 M3 A4 P5 M6 M7",
  mixolydian = "P1 M2 M3 P4 P5 M6 m7", aeolian = "P1 M2 m3 P4 P5 m6 m7",
  locrian = "P1 m2 m3 P4 d5 m6 m7", major_pentatonic = "P1 M2 M3 P5 M6",
  minor_pentatonic = "P1 m3 P4 P5 m7", blues = "P1 m3 P4 A4 P5 m7", whole_tone = "P1 M2 M3 A4 A5 A6"
)
scales <- lapply(scale_rows, make_tones)
chord_rows <- c(
  "maj||I|P1 M3 P5", "min|m|i|P1 m3 P5", "dim|dim|io|P1 m3 d5",
  "aug|aug|I+|P1 M3 A5", "sus2|sus2|Isus2|P1 M2 P5", "sus4|sus4|Isus4|P1 P4 P5",
  "6|6|I6|P1 M3 P5 M6", "m6|m6|i6|P1 m3 P5 M6", "7|7|I7|P1 M3 P5 m7",
  "maj7|maj7|Imaj7|P1 M3 P5 M7", "m7|m7|i7|P1 m3 P5 m7", "mMaj7|mMaj7|imaj7|P1 m3 P5 M7",
  "m7b5|m7b5|ih7|P1 m3 d5 m7", "dim7|dim7|io7|P1 m3 d5 d7",
  "9|9|I9|P1 M3 P5 m7 M9", "add9|add9|Iadd9|P1 M3 P5 M9"
)
chords <- lapply(chord_rows, function(row) {
  fields <- strsplit(row, "|", fixed = TRUE)[[1L]]
  list(name = fields[[1L]], suffix = fields[[2L]], lower = startsWith(fields[[3L]], "i"),
       numeral_suffix = substring(fields[[3L]], 2L), tones = make_tones(fields[[4L]]))
})
names(chords) <- vapply(chords, function(chord) chord$name, character(1L))
mode_names <- c("major", "minor", "ionian", "dorian", "phrygian", "lydian", "mixolydian", "aeolian", "locrian")
mode_scales <- c("major", "natural_minor", "ionian", "dorian", "phrygian", "lydian", "mixolydian", "aeolian", "locrian")
mode_offsets <- c(0L, -3L, 0L, -2L, -4L, 1L, -1L, -3L, -5L)

named_index <- function(text, kind, choices) {
  index <- match(text, choices)
  if (is.na(index)) bad(kind, text)
  index
}
chord_symbol <- function(root, chord, bass = NULL) {
  paste0(pitch_text(root), chord$suffix, if (is.null(bass)) "" else paste0("/", pitch_text(bass)))
}
roman <- function(degree, chord) {
  part <- romans[degree]
  paste0(if (chord$lower) tolower(part) else part, chord$numeral_suffix)
}
make_key <- function(tonic, mode) {
  fifths <- fifths_values[tonic[["letter"]] + 1L] + 7L * tonic[["alteration"]] + mode_offsets[mode]
  if (fifths < -7L || fifths > 7L) fail("THEORETICAL KEY")
  list(tonic = tonic, mode = mode, fifths = fifths, scale = build(tonic, scales[[mode_scales[mode]]]))
}
parse_key <- function(arguments, start = 1L) {
  tonic <- parse_pitch(arguments[[start]])
  mode <- named_index(arguments[[start + 1L]], "MODE", mode_names)
  make_key(tonic, mode)
}
key_text <- function(key) paste(pitch_text(key$tonic), mode_names[key$mode])
key_set <- function(key) sort(vapply(key$scale, pitch_class, integer(1L)))
key_degree <- function(key, pitch) (pitch[["letter"]] - key$tonic[["letter"]]) %% 7L + 1L
key_prefix <- function(key, pitch) {
  difference <- pitch[["alteration"]] - key$scale[[key_degree(key, pitch)]][["alteration"]]
  strrep(if (difference < 0L) "b" else "#", abs(difference))
}
key_label <- function(key, pitch) paste0(key_prefix(key, pitch), key_degree(key, pitch))
parse_numeral <- function(text) {
  prefix <- substr(text, 1L, 1L)
  alteration <- if (prefix == "b") -1L else if (prefix == "#") 1L else 0L
  rest <- if (alteration == 0L) text else substring(text, 2L)
  end <- 1L
  while (end <= nchar(rest) && substr(rest, end, end) %in% c("I", "V", "i", "v")) end <- end + 1L
  part <- substr(rest, 1L, end - 1L)
  suffix <- substring(rest, end)
  for (degree in seq_along(romans)) {
    for (quality in seq_along(chords)) {
      chord <- chords[[quality]]
      expected <- if (chord$lower) tolower(romans[degree]) else romans[degree]
      if (part == expected && suffix == chord$numeral_suffix) {
        return(list(alteration = alteration, degree = degree, quality = quality))
      }
    }
  }
  bad("NUMERAL", text)
}
parse_symbol <- function(text) {
  parsed <- pitch_prefix(text, "SYMBOL")
  quality <- match(parsed$rest, vapply(chords, function(chord) chord$suffix, character(1L)))
  if (is.na(quality)) bad("SYMBOL", text)
  list(root = parsed$pitch, quality = quality)
}

identify <- function(notes) {
  values <- vapply(notes, function(note) note$midi, integer(1L))
  ordered <- notes[order(values, method = "radix")]
  classes <- vapply(ordered, function(note) pitch_class(note$pitch), integer(1L))
  candidates <- ordered[!duplicated(classes)]
  present <- sort(unique(classes))
  bass <- candidates[[1L]]$pitch
  for (root in candidates) {
    for (chord in chords) {
      semitones <- vapply(chord$tones, function(tone) tone[["semitones"]], integer(1L))
      possible <- (root$midi + semitones) %% 12L
      if (!identical(sort(unique(possible)), present)) next
      inversion <- match(pitch_class(bass), possible) - 1L
      symbol <- chord_symbol(root$pitch, chord, if (inversion == 0L) NULL else bass)
      return(paste0("IDENTIFY ", symbol, " root=", pitch_text(root$pitch), " quality=", chord$name, " inversion=", inversion))
    }
  }
  "IDENTIFY UNKNOWN"
}
melody <- function(notes, arguments) {
  values <- vapply(notes, function(note) note$midi, integer(1L))
  low <- which.min(values)
  high <- which.max(values)
  range <- between(notes[[low]], notes[[high]])$interval
  steps <- vapply(seq.int(2L, length(notes)), function(index) {
    motion <- between(notes[[index - 1L]], notes[[index]])
    paste0(if (motion$down) "-" else "+", interval_text(motion$interval))
  }, character(1L))
  paste0("MELODY n=", length(notes), " low=", arguments[low], " high=", arguments[high],
         " range=", interval_text(range), " leaps=", sum(abs(diff(values)) >= 3L), " steps=", joined(steps, ","))
}
cadence <- function(numerals) {
  if (length(numerals) < 2L) return("none")
  first <- numerals[[length(numerals) - 1L]]
  second <- numerals[[length(numerals)]]
  if (first$alteration == 0L && second$alteration == 0L) {
    if (first$degree == 5L && second$degree == 1L) return("authentic")
    if (first$degree == 4L && second$degree == 1L) return("plagal")
    if (first$degree == 5L && second$degree == 6L) return("deceptive")
  }
  if (second$alteration == 0L && second$degree == 5L) "half" else "none"
}
diatonic <- function(key) {
  rows <- paste("DIATONIC", key_text(key))
  classes <- vapply(key$scale, pitch_class, integer(1L))
  for (size in 3L:4L) {
    items <- vapply(seq_len(7L), function(index) {
      third <- (classes[(index + 1L) %% 7L + 1L] - classes[index]) %% 12L
      fifth <- (classes[(index + 3L) %% 7L + 1L] - classes[index]) %% 12L
      if (size == 3L) {
        quality <- if (third == 4L) 1L else if (fifth == 7L) 2L else 3L
      } else {
        seventh <- (classes[(index + 5L) %% 7L + 1L] - classes[index]) %% 12L
        quality <- if (third == 4L) { if (seventh == 11L) 10L else 9L } else if (fifth == 7L) 11L else 13L
      }
      chord <- chords[[quality]]
      paste0(roman(index, chord), "=", chord_symbol(key$scale[[index]], chord))
    }, character(1L))
    rows <- c(rows, paste(if (size == 3L) "TRIADS" else "SEVENTHS", joined(items)))
  }
  rows
}

arities <- list(
  MIDI = c(1L,1L), NOTE = c(1L,1L), FREQ = c(1L,1L), TUNING = c(1L,1L), PITCH = c(1L,1L),
  INTERVAL = c(2L,2L), INVERT = c(1L,1L), TRANSPOSE = c(3L,3L), SCALE = c(2L,2L),
  CHORD = c(2L,3L), VOICE = c(2L,3L), IDENTIFY = c(2L,15L), MELODY = c(2L,15L),
  ENHARMONIC = c(1L,1L), KEYSIG = c(2L,2L), RELATIVE = c(2L,2L), CIRCLE = c(1L,1L),
  DIATONIC = c(2L,2L), PROGRESSION = c(3L,15L), ANALYZE = c(3L,15L), FINDKEY = c(1L,15L),
  DEGREE = c(3L,3L), SPELL = c(3L,3L), KEYDIST = c(4L,4L)
)
execute <- function(line, calculator) {
  tokens <- words(line)
  command <- tokens[[1L]]
  arity <- arities[[command]]
  if (is.null(arity)) fail(paste("UNKNOWN COMMAND", command))
  arguments <- tokens[-1L]
  count <- length(arguments)
  if (count < arity[1L] || count > arity[2L]) fail("ARGUMENT COUNT")
  if (command %in% c("MIDI", "FREQ", "ENHARMONIC")) {
    note <- parse_note(arguments[[1L]])
    value <- note$midi
    if (command == "MIDI") return(paste("MIDI", arguments[[1L]], value))
    if (command == "FREQ") {
      cents <- as.integer(floor(calculator$tuning * 2^((value - 69L) / 12) + 0.5))
      return(paste("FREQ", arguments[[1L]], frequency_text(cents)))
    }
    equivalents <- list()
    for (octave in -1L:9L) for (letter in 0L:6L) {
      alteration <- value - 12L * (octave + 1L) - naturals[letter + 1L]
      if (alteration >= -2L && alteration <= 2L) equivalents[[length(equivalents) + 1L]] <- new_note(new_pitch(letter, alteration), octave)
    }
    return(paste("ENHARMONIC", arguments[[1L]], notes_text(equivalents)))
  }
  if (command == "NOTE") {
    value <- bounded_integer(arguments[[1L]], "NUMBER", 0L, 127L)
    return(paste("NOTE", value, note_text(spelling(value)), note_text(spelling(value, TRUE))))
  }
  if (command %in% c("TUNING", "PITCH")) {
    value <- parse_frequency(arguments[[1L]], command == "TUNING")
    if (command == "TUNING") {
      calculator$tuning <- value
      return(paste("TUNING", frequency_text(value)))
    }
    height <- 69 + 12 * log2(value / calculator$tuning)
    nearest <- as.integer(floor(height + 0.5))
    if (nearest < 0L || nearest > 127L) fail("OUT OF RANGE")
    cents <- as.integer(floor(100 * (height - nearest) + 0.5))
    return(paste("PITCH", frequency_text(value), note_text(spelling(nearest)), sprintf("%+d", cents)))
  }
  if (command == "INTERVAL") {
    first <- parse_note(arguments[[1L]])
    second <- parse_note(arguments[[2L]])
    motion <- between(first, second)
    return(paste0("INTERVAL ", arguments[[1L]], " ", arguments[[2L]], " ", interval_text(motion$interval),
                  if (motion$down) " down" else " up", " semitones=", motion$semitones,
                  " simple=", interval_text(simple_interval(motion$interval)), " class=", consonance(motion$interval)))
  }
  if (command == "INVERT") {
    interval <- parse_interval(arguments[[1L]])
    simple <- simple_interval(interval)
    inverse <- new_interval(c(1L, 3L, 2L, 5L, 4L, 7L, 6L)[simple$quality], 9L - simple$number)
    if (forbidden_interval(inverse)) fail("CANNOT INVERT")
    return(paste("INVERT", arguments[[1L]], interval_text(simple), interval_text(inverse)))
  }
  if (command == "TRANSPOSE") {
    note <- parse_note(arguments[[1L]])
    interval <- parse_interval(arguments[[2L]])
    direction <- arguments[[3L]]
    if (!direction %in% c("UP", "DOWN")) bad("DIRECTION", direction)
    sign <- if (direction == "UP") 1L else -1L
    tone <- interval_tone(interval)
    position <- note$position + sign * tone[["letters"]]
    value <- note$midi + sign * tone[["semitones"]]
    letter <- position %% 7L
    octave <- position %/% 7L
    alteration <- value - 12L * (octave + 1L) - naturals[letter + 1L]
    if (alteration < -2L || alteration > 2L) fail("CANNOT SPELL")
    result <- new_note(new_pitch(letter, alteration), octave)
    if (!valid_note(result)) fail("OUT OF RANGE")
    return(paste("TRANSPOSE", arguments[[1L]], arguments[[2L]], direction, note_text(result)))
  }
  if (command == "SCALE") {
    root <- parse_pitch(arguments[[1L]])
    index <- named_index(arguments[[2L]], "SCALE", names(scales))
    tones <- scales[[index]]
    pitches <- build(root, tones)
    semitones <- vapply(tones, function(tone) tone[["semitones"]], integer(1L))
    return(paste0("SCALE ", arguments[[1L]], " ", arguments[[2L]], " ", pitches_text(pitches),
                  " steps=", joined(diff(c(semitones, 12L)), ",")))
  }
  if (command %in% c("CHORD", "VOICE")) {
    if (command == "VOICE") {
      note <- parse_note(arguments[[1L]])
      root <- note$pitch
    } else root <- parse_pitch(arguments[[1L]])
    quality <- named_index(arguments[[2L]], "QUALITY", names(chords))
    chord <- chords[[quality]]
    inversion <- if (count == 3L) bounded_integer(arguments[[3L]], "INVERSION", 0L, length(chord$tones) - 1L) else 0L
    tones <- build(root, chord$tones)
    ordered <- tones[(seq_along(tones) - 1L + inversion) %% length(tones) + 1L]
    symbol <- chord_symbol(root, chord, if (inversion == 0L) NULL else ordered[[1L]])
    if (command == "CHORD") return(paste("CHORD", symbol, pitches_text(ordered)))
    notes <- list()
    values <- integer()
    value <- note$midi
    for (index in seq_along(ordered)) {
      pitch <- ordered[[index]]
      if (index > 1L || inversion > 0L) {
        difference <- (pitch_class(pitch) - value) %% 12L
        value <- value + if (difference == 0L) 12L else difference
      }
      next_note <- make_note(pitch, value)
      if (!valid_note(next_note)) fail("OUT OF RANGE")
      notes[[index]] <- next_note
      values <- c(values, value)
    }
    return(paste0("VOICE ", symbol, " ", notes_text(notes), " midi=", joined(values, ",")))
  }
  if (command %in% c("IDENTIFY", "MELODY")) {
    notes <- lapply(arguments, parse_note)
    return(if (command == "IDENTIFY") identify(notes) else melody(notes, arguments))
  }
  if (command == "CIRCLE") {
    mode <- named_index(arguments[[1L]], "MODE", mode_names)
    pitches <- lapply(-7L:7L, function(value) fifth_pitch(value - mode_offsets[mode]))
    return(paste("CIRCLE", arguments[[1L]], pitches_text(pitches)))
  }
  if (command == "FINDKEY") {
    pitches <- lapply(arguments, parse_pitch)
    keys <- character()
    for (fifths in -7L:7L) for (mode in 1L:2L) {
      key <- make_key(fifth_pitch(fifths - mode_offsets[mode]), mode)
      included <- vapply(pitches, function(pitch) identical(pitch, key$scale[[key_degree(key, pitch)]]), logical(1L))
      if (all(included)) keys <- c(keys, key_text(key))
    }
    return(paste0("FINDKEY ", length(keys), if (length(keys)) paste0(" ", joined(keys, ", ")) else ""))
  }
  if (command == "SPELL") {
    value <- bounded_integer(arguments[[1L]], "NUMBER", 0L, 127L)
    key <- parse_key(arguments, 2L)
    classes <- vapply(key$scale, pitch_class, integer(1L))
    index <- match(value %% 12L, classes)
    pitch <- if (is.na(index)) spelling(value, key$fifths < 0L)$pitch else key$scale[[index]]
    note <- make_note(pitch, value)
    if (!valid_note(note)) fail("OUT OF RANGE")
    return(paste("SPELL", value, key_text(key), note_text(note), key_label(key, pitch)))
  }
  key <- parse_key(arguments)
  if (command == "KEYSIG") {
    value <- key$fifths
    if (value == 0L) return(paste("KEYSIG", key_text(key), "none"))
    names <- if (value > 0L) words("F# C# G# D# A# E# B#") else words("Bb Eb Ab Db Gb Cb Fb")
    return(paste0("KEYSIG ", key_text(key), if (value > 0L) " sharps=" else " flats=", abs(value),
                  " ", joined(names[seq_len(abs(value))])))
  }
  if (command == "RELATIVE") {
    return(paste0("RELATIVE ", key_text(key), " major=", pitch_text(fifth_pitch(key$fifths)),
                  " minor=", pitch_text(fifth_pitch(key$fifths + 3L))))
  }
  if (command == "DIATONIC") return(diatonic(key))
  if (command == "DEGREE") {
    pitch <- parse_pitch(arguments[[3L]])
    return(paste("DEGREE", key_text(key), arguments[[3L]], key_label(key, pitch)))
  }
  if (command == "KEYDIST") {
    other <- parse_key(arguments, 3L)
    distance <- (other$fifths - key$fifths) %% 12L
    if (distance > 6L) distance <- distance - 12L
    first_set <- key_set(key)
    second_set <- key_set(other)
    same_tonic <- pitch_class(key$tonic) == pitch_class(other$tonic)
    relation <- if (identical(first_set, second_set)) {
      if (same_tonic) "same" else "relative"
    } else if (same_tonic) "parallel" else if (abs(distance) == 1L) "close" else "distant"
    return(paste0("KEYDIST ", key_text(key), " ", key_text(other), " fifths=", if (distance > 0L) "+" else "", distance,
                  " common=", length(intersect(first_set, second_set)), " relation=", relation))
  }
  if (command == "ANALYZE") {
    symbols <- lapply(arguments[-c(1L, 2L)], parse_symbol)
    numerals <- vapply(symbols, function(symbol) {
      paste0(key_prefix(key, symbol$root), roman(key_degree(key, symbol$root), chords[[symbol$quality]]))
    }, character(1L))
    return(paste("ANALYZE", key_text(key), joined(numerals)))
  }
  numerals <- lapply(arguments[-c(1L, 2L)], parse_numeral)
  rows <- paste("PROGRESSION", key_text(key), length(numerals))
  for (index in seq_along(numerals)) {
    numeral <- numerals[[index]]
    root <- key$scale[[numeral$degree]]
    root[["alteration"]] <- root[["alteration"]] + numeral$alteration
    chord <- chords[[numeral$quality]]
    tones <- build(root, chord$tones)
    rows <- c(rows, paste(arguments[index + 2L], chord_symbol(root, chord), pitches_text(tones)))
  }
  c(rows, paste("CADENCE", cadence(numerals)))
}

input <- readLines(file("stdin"), warn = FALSE)
calculator <- new.env(parent = emptyenv())
calculator$tuning <- 44000L
for (index in seq_len(as.integer(input[[1L]]))) {
  response <- tryCatch(execute(input[[index + 1L]], calculator), music_error = function(problem) conditionMessage(problem))
  cat(paste0(response, "\n"), sep = "")
}
