PITCH_NAMES <- c("C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-")
ROWS_PER_PATTERN <- 64L
CHANNEL_COUNT <- 4L
new_object <- function(...) list2env(list(...), parent = emptyenv())
note_number <- function(name) 12L * as.integer(substr(name, 3L, 3L)) + match(
    substr(name, 1L, 2L),
    PITCH_NAMES
) - 1L
note_name <- function(number) paste0(PITCH_NAMES[number %% 12L + 1L], number %/% 12L)
new_effect <- function(text) {
  extended <- startsWith(text, "E")
  list(
      text = text,
      name = substr(text, 1L, if (extended) 2L else 1L),
      value = strtoi(substring(text, if (extended) 3L else 2L), base = 16L)
  )
}
high <- function(effect) effect$value %/% 16L
low <- function(effect) effect$value %% 16L
new_cell <- function(text) {
  note <- substr(text, 1L, 3L)
  instrument <- substr(text, 5L, 6L)
  volume <- substr(text, 8L, 8L)
  effect <- substr(text, 10L, 12L)
  list(key_off = note == "OFF", note = if (note %in% c("...", "OFF")) NULL else note_number(note),
       instrument = if (instrument == "..") NULL else strtoi(instrument, base = 16L),
       volume = if (volume == ".") NULL else strtoi(
           volume,
           base = 16L
       ), effect = if (effect == "...") NULL else new_effect(effect))
}
has_note <- function(cell) cell$key_off || !is.null(cell$note)
is_empty <- function(cell) !has_note(cell) && is.null(cell$instrument) && is.null(cell$volume) && is.null(cell$effect)
parse_instrument <- function(words, lines) {
  instrument <- new_object(number = strtoi(words[[2L]], base = 16L), name = words[[3L]], wave = "", mode = 0L,
                           table = integer(), attack = 0L, decay = 0L, sustain = 0L, release = 0L,
                           vibrato = NULL, arpeggio = integer(), sweep = 0L)
  for (line in lines) {
    parts <- strsplit(line, " ", fixed = TRUE)[[1L]]
    key <- parts[[1L]]
    values <- parts[-1L]
    if (key == "WAVE") {
      instrument$wave <- values[[1L]]
      if (instrument$wave == "PULSE") instrument$mode <- match(values[[2L]], c("12", "25", "50", "75")) - 1L
      if (instrument$wave == "NOISE") instrument$mode <- as.integer(values[[2L]] == "SHORT")
      if (instrument$wave == "TABLE") instrument$table <- strtoi(
          strsplit(values[[2L]], "", fixed = TRUE)[[1L]],
          base = 16L
      )
    } else if (key == "ENVELOPE") {
      instrument$attack <- as.integer(values[[1L]])
      instrument$decay <- as.integer(values[[2L]])
      instrument$sustain <- as.integer(values[[3L]])
      instrument$release <- as.integer(values[[4L]])
    } else if (key == "VIBRATO") instrument$vibrato <- as.integer(values) else if (key == "ARPEGGIO") instrument$arpeggio <- as.integer(values) else if (key == "SWEEP") instrument$sweep <- as.integer(values[[1L]])
  }
  instrument
}
song_cells <- function(
    song,
    position,
    row
) song$patterns[[as.character(song$order[[position + 1L]])]][[row + 1L]]
read_song <- function(path) {
  lines <- readLines(path, warn = FALSE)
  lines <- lines[nzchar(lines) & !startsWith(lines, "#")]
  header <- vapply(lines[seq_len(5L)], function(line) substring(line, regexpr(" ", line)[[1L]] + 1L), "")
  song <- new_object(title = header[[1L]], rate = as.numeric(header[[2L]]), speed = as.integer(header[[3L]]),
                     tempo = as.integer(header[[4L]]), gain = as.numeric(header[[5L]]), instruments = list(), patterns = list(), order = integer())
  index <- 6L
  while (index <= length(lines)) {
    words <- strsplit(lines[[index]], " ", fixed = TRUE)[[1L]]
    if (words[[1L]] == "ORDER") {
      song$order <- strtoi(words[-1L], base = 16L)
      index <- index + 1L
      next
    }
    stop <- index + which(lines[seq.int(index + 1L, length(lines))] == "END")[[1L]]
    block <- if (stop > index + 1L) lines[seq.int(index + 1L, stop - 1L)] else character()
    if (words[[1L]] == "INSTRUMENT") {
      instrument <- parse_instrument(words, block)
      song$instruments[[as.character(instrument$number)]] <- instrument
    } else {
      rows <- lapply(
          seq_len(ROWS_PER_PATTERN),
          function(i) lapply(seq_len(CHANNEL_COUNT), function(k) new_cell("... .. . ..."))
      )
      for (line in block) rows[[strtoi(substr(line, 1L, 2L), base = 16L) + 1L]] <- lapply(
          strsplit(substring(line, 4L), " | ", fixed = TRUE)[[1L]],
          new_cell
      )
      song$patterns[[as.character(strtoi(words[[2L]], base = 16L))]] <- rows
    }
    index <- stop + 1L
  }
  song
}
read_params <- function(path) {
  fields <- list()
  traces <- character()
  for (line in readLines(path, warn = FALSE)) {
    if (!nzchar(line)) next
    words <- strsplit(line, " ", fixed = TRUE)[[1L]]
    if (words[[1L]] == "trace") traces <- c(
        traces,
        paste(strtoi(words[-1L], base = 16L), collapse = ":")
    ) else fields[[words[[1L]]]] <- words[-1L]
  }
  window <- as.integer(fields$window)
  roll <- as.integer(fields$roll)
  list(max_samples = as.integer(fields$max_samples), loops = as.integer(fields$loops), fade = as.integer(fields$fade),
       muted = fields$mute == "1", window_start = window[[1L]], window_length = window[[2L]], window_width = window[[3L]],
       window_height = window[[4L]], window_scope = window[[5L]], roll_start = roll[[1L]], roll_rows = roll[[2L]],
       preview_note = note_number(fields$preview[[1L]]), preview_ticks = as.integer(fields$preview[[2L]]), preview_release = as.integer(fields$preview[[3L]]), traces = traces)
}
