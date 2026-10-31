for (name in c("song_parser", "instruments", "sequencer", "mixer", "report")) source(paste0(name, ".R"))

FMIN <- 1000
LANE_LIMIT <- 3375L
EFFECT_ORDER <- c(
    "0",
    "1",
    "2",
    "3",
    "4",
    "5",
    "6",
    "7",
    "A",
    "B",
    "C",
    "D",
    "E1",
    "E2",
    "E9",
    "EA",
    "EB",
    "EC",
    "ED",
    "EE",
    "F",
    "P",
    "Q",
    "R",
    "V"
)
TONIC_NAMES <- c("C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B")
MAJOR_WEIGHTS <- c(64, 22, 35, 23, 44, 41, 25, 52, 24, 37, 23, 29)
MINOR_WEIGHTS <- c(64, 27, 35, 54, 27, 35, 25, 48, 40, 27, 34, 32)
integer_text <- function(value) sprintf("%.0f", value)
hex2 <- function(value) sprintf("%02X", as.integer(value))
hex1 <- function(value) sprintf("%X", as.integer(value))
hex_list <- function(values) if (length(values)) paste(hex2(values), collapse = " ") else "none"
note_range <- function(notes) if (length(notes)) paste0(
    note_name(min(notes)),
    "..",
    note_name(max(notes))
) else "none"
new_channel <- function(number) {
  new_object(number = number, instrument = NULL, note = NULL, frequency = 0, target = 0, portamento = 0L,
             slide = 0L, detune = 0L, vibrato_speed = 0L, vibrato_depth = 0L, vibrato_position = 0L,
             tremolo_speed = 0L, tremolo_depth = 0L, tremolo_position = 0L, volume = 15L, mode = 0L,
             phase = 0, register = 1L, age = 0L, released = FALSE, release_age = 0L, release_level = 0L,
             envelope = 0L, output_frequency = 0, output_volume = 0L, amplitude = 0L, increment = 0,
             effect = NULL, sounding = FALSE, record = NULL, note_ons = 0L, retriggers = 0L, cuts = 0L,
             active = 0L, audible = 0L)
}
effect_name <- function(channel) if (is.null(channel$effect)) "" else channel$effect$name
effect_value <- function(channel) if (is.null(channel$effect)) 0L else channel$effect$value
key_off <- function(channel) {
  channel$release_age <- channel$age
  channel$release_level <- channel$envelope
  channel$released <- TRUE
}
approach <- function(channel, step) {
  channel$frequency <- if (channel$frequency < channel$target) min(channel$frequency + step, channel$target) else max(
      channel$frequency - step,
      channel$target
  )
}
volume_slide <- function(channel) channel$volume <- clamp(
    channel$volume + high(channel$effect) - low(channel$effect),
    0L,
    15L
)
update_output <- function(channel, tick, rate) {
  instrument <- channel$instrument
  name <- effect_name(channel)
  semitones <- if (name == "0") c(0L, high(channel$effect), low(channel$effect))[[tick %% 3L + 1L]] else 0L
  if (length(instrument$arpeggio)) semitones <- semitones + instrument$arpeggio[[channel$age %% length(instrument$arpeggio) + 1L]]
  frequency <- transpose_frequency(channel$frequency, semitones) + channel$detune
  if (name %in% c("4", "6")) frequency <- frequency + oscillation(
      channel$vibrato_position,
      channel$vibrato_depth,
      4L
  )
  if (!is.null(instrument$vibrato)) {
    delay <- instrument$vibrato[[1L]]
    speed <- instrument$vibrato[[2L]]
    depth <- instrument$vibrato[[3L]]
    if (channel$age >= delay) frequency <- frequency + oscillation(
        ((channel$age - delay) * speed) %% 64L,
        depth,
        4L
    )
  }
  channel$output_frequency <- clamp(frequency, FMIN, 50 * rate)
  channel$envelope <- envelope_value(
      instrument,
      channel$age,
      channel$released,
      channel$release_age,
      channel$release_level
  )
  channel$output_volume <- if (name == "7") clamp(
      channel$volume + oscillation(channel$tremolo_position, channel$tremolo_depth, 255L),
      0L,
      15L
  ) else channel$volume
  channel$amplitude <- channel$envelope * channel$output_volume
  channel$increment <- (channel$output_frequency * 65536) %/% (100 * rate)
}
new_player <- function(song, params) {
  new_object(song = song, params = params, channels = lapply(seq_len(CHANNEL_COUNT), new_channel), buffer = new_buffer(params$max_samples, CHANNEL_COUNT),
             samples = integer(), lanes = matrix(
                 integer(),
                 0L,
                 CHANNEL_COUNT
             ), speed = song$speed, tempo = song$tempo, delay = 0L,
             position = 0L, row = 0L, cells = list(), records = list(), warnings = character(), log = character(), played = list(),
             play_counts = new.env(hash = TRUE, parent = emptyenv()), first_starts = new.env(
                 hash = TRUE,
                 parent = emptyenv()
             ),
             ticks = 0L, clipped = 0L, instrument_ticks = setNames(
                 integer(length(song$instruments)),
                 names(song$instruments)
             ),
             effect_counts = setNames(
                 integer(length(EFFECT_ORDER)),
                 EFFECT_ORDER
             ), end_reason = "finished", end_row = NULL, loop_start = NULL)
}
warn <- function(player, channel, message) {
  player$warnings <- c(
      player$warnings,
      paste0("warning ", hex2(player$position), ":", hex2(player$row), " ch", channel$number, " ", message)
  )
}
clamp_frequency <- function(player, frequency) clamp(frequency, FMIN, 50 * player$song$rate)
end_record <- function(player, channel, reason) {
  channel$record$length <- player$buffer$count - channel$record$start
  channel$record$reason <- reason
  channel$record <- NULL
}
note_on <- function(player, channel, note) {
  if (!is.null(channel$record)) end_record(player, channel, "next")
  channel$frequency <- note_frequency(note)
  channel$target <- channel$frequency
  channel$phase <- 0
  channel$age <- channel$vibrato_position <- channel$tremolo_position <- 0L
  channel$released <- FALSE
  channel$note <- note
  channel$note_ons <- channel$note_ons + 1L
  channel$record <- new_object(serial = length(player$records) + 1L, channel = channel$number, position = player$position, row = player$row,
                               instrument = channel$instrument, note = note, start = player$buffer$count, length = 0L, release = NULL, reason = "")
  player$records[[length(player$records) + 1L]] <- channel$record
}
apply_cell <- function(player, channel, cell, portamento) {
  if (!is.null(cell$instrument)) {
    instrument <- player$song$instruments[[as.character(cell$instrument)]]
    if (is.null(instrument)) warn(
        player,
        channel,
        paste("undefined instrument", hex2(cell$instrument))
    ) else {
      channel$instrument <- instrument
      channel$volume <- 15L
      channel$mode <- instrument$mode
    }
  }
  if (!is.null(cell$volume)) channel$volume <- cell$volume
  if (cell$key_off) {
    if (!is.null(channel$note) && !channel$released) {
      key_off(channel)
      channel$record$release <- player$buffer$count - channel$record$start
    } else warn(player, channel, "key off without note")
  } else if (!is.null(cell$note)) {
    if (is.null(channel$instrument)) warn(
        player,
        channel,
        "note without instrument"
    ) else if (portamento && !is.null(channel$note)) {
      channel$target <- note_frequency(cell$note)
      channel$note <- cell$note
    } else {
      if (portamento) warn(player, channel, "portamento without note")
      note_on(player, channel, cell$note)
    }
  }
}
start_effect <- function(player, channel) {
  effect <- channel$effect
  name <- effect$name
  value <- effect$value
  if (name == "3") {
    if (value > 0L) channel$portamento <- value
  } else if (name == "4") {
    if (high(effect) > 0L) channel$vibrato_speed <- high(effect)
    if (low(effect) > 0L) channel$vibrato_depth <- low(effect)
  } else if (name == "7") {
    if (high(effect) > 0L) channel$tremolo_speed <- high(effect)
    if (low(effect) > 0L) channel$tremolo_depth <- low(effect)
  } else if (name == "C") {
    channel$volume <- min(value, 15L)
  } else if (name == "E1") {
    channel$frequency <- clamp_frequency(player, channel$frequency + 10L * value)
  } else if (name == "E2") {
    channel$frequency <- clamp_frequency(player, channel$frequency - 10L * value)
  } else if (name == "EA") {
    channel$volume <- min(channel$volume + value, 15L)
  } else if (name == "EB") {
    channel$volume <- max(channel$volume - value, 0L)
  } else if (name == "EE") {
    player$delay <- value
  } else if (name == "F") {
    if (value >= 1L && value <= 31L) player$speed <- value else if (value >= 32L) player$tempo <- value
  } else if (name == "P") channel$detune <- value - 128L else if (name %in% c("Q", "R")) {
    if (is.null(channel$note)) warn(player, channel, "slide without note") else {
      channel$note <- if (name == "Q") min(channel$note + low(effect), 95L) else max(
          channel$note - low(effect),
          12L
      )
      channel$target <- note_frequency(channel$note)
      channel$slide <- 2L * high(effect) + 1L
    }
  } else if (name == "V") {
    instrument <- channel$instrument
    if (!is.null(instrument) && ((instrument$wave == "PULSE" && value <= 3L) || (instrument$wave == "NOISE" && value <= 1L))) channel$mode <- value else warn(
        player,
        channel,
        paste("invalid mode", hex2(value))
    )
  }
}
tick_effect <- function(player, channel) {
  name <- channel$effect$name
  value <- channel$effect$value
  if (name == "1") channel$frequency <- clamp_frequency(player, channel$frequency + 10L * value) else if (name == "2") channel$frequency <- clamp_frequency(
      player,
      channel$frequency - 10L * value
  ) else if (name %in% c("3", "5")) {
    approach(channel, 10L * channel$portamento)
    if (name == "5") volume_slide(channel)
  } else if (name %in% c("6", "A")) volume_slide(channel) else if (name %in% c("Q", "R") && channel$slide != 0L) approach(
      channel,
      10L * channel$slide
  )
}
start_row <- function(player) {
  player$delay <- 0L
  for (k in seq_along(player$channels)) {
    channel <- player$channels[[k]]
    cell <- player$cells[[k]]
    channel$effect <- cell$effect
    channel$slide <- 0L
    if (!is.null(cell$effect)) player$effect_counts[[cell$effect$name]] <- player$effect_counts[[cell$effect$name]] + 1L
    name <- effect_name(channel)
    if (!(name == "ED" && effect_value(channel) >= 1L)) apply_cell(
        player,
        channel,
        cell,
        name %in% c("3", "5")
    )
    if (!is.null(channel$effect)) start_effect(player, channel)
  }
}
process_tick <- function(player, tick) {
  for (k in seq_along(player$channels)) {
    channel <- player$channels[[k]]
    cell <- player$cells[[k]]
    name <- effect_name(channel)
    value <- effect_value(channel)
    if (!is.null(channel$note) && channel$age >= 1L && channel$instrument$sweep != 0L) channel$frequency <- clamp_frequency(
        player,
        channel$frequency + 10L * channel$instrument$sweep
    )
    if (tick >= 1L && !is.null(channel$effect)) tick_effect(player, channel)
    if (name == "ED" && value >= 1L && tick == value) apply_cell(player, channel, cell, FALSE)
    if (name == "E9" && value >= 1L && tick >= 1L && tick %% value == 0L && !is.null(channel$note)) {
      channel$phase <- 0
      channel$age <- 0L
      channel$released <- FALSE
      channel$retriggers <- channel$retriggers + 1L
    }
    if (name == "EC" && tick == value && !is.null(channel$note)) {
      end_record(player, channel, "cut")
      channel$note <- NULL
      channel$cuts <- channel$cuts + 1L
    }
    channel$sounding <- !is.null(channel$note)
    if (channel$sounding) {
      update_output(channel, tick, player$song$rate)
      channel$active <- channel$active + 1L
      if (channel$amplitude > 0L) channel$audible <- channel$audible + 1L
      number <- as.character(channel$instrument$number)
      player$instrument_ticks[[number]] <- player$instrument_ticks[[number]] + 1L
    }
  }
}
advance <- function(player) {
  for (channel in player$channels) {
    if (!is.null(channel$note)) channel$age <- channel$age + 1L
    name <- effect_name(channel)
    if (name %in% c(
        "4",
        "6"
    )) channel$vibrato_position <- (channel$vibrato_position + channel$vibrato_speed) %% 64L else if (name == "7") channel$tremolo_position <- (channel$tremolo_position + channel$tremolo_speed) %% 64L
  }
  player$ticks <- player$ticks + 1L
}
channel_text <- function(channel) {
  effect <- if (is.null(channel$effect)) "..." else channel$effect$text
  if (is.null(channel$note)) return(sprintf("--- -- %7s - %s %s", "-", hex1(channel$volume), effect))
  sprintf(
      "%s %s %7.0f %s %s %s",
      note_name(channel$note),
      hex2(channel$instrument$number),
      channel$output_frequency,
      hex1(channel$envelope),
      hex1(channel$output_volume),
      effect
  )
}
log_row <- function(player, start) {
  pattern <- player$song$order[[player$position + 1L]]
  prefix <- sprintf(
      "%s %s %s %7.0f %2d %3d",
      hex2(player$position),
      hex2(pattern),
      hex2(player$row),
      start,
      player$speed,
      player$tempo
  )
  player$log <- c(player$log, paste(c(prefix, vapply(player$channels, channel_text, "")), collapse = " | "))
  notes <- vapply(
      player$channels,
      function(channel) if (is.null(channel$note)) NA_integer_ else as.integer(channel$note),
      0L
  )
  player$played[[length(player$played) + 1L]] <- list(
      position = player$position,
      row = player$row,
      start = start,
      speed = player$speed,
      tempo = player$tempo,
      notes = notes
  )
}
log_tick <- function(player, tick) {
  parts <- sprintf("  tick %3d %7.0f", tick, player$buffer$count)
  for (channel in player$channels) {
    text <- if (channel$sounding) sprintf(
        "%7.0f %5.0f %s%s",
        channel$output_frequency,
        channel$increment,
        hex1(channel$envelope),
        hex1(channel$output_volume)
    ) else sprintf("%7s %5s --", "-", "-")
    parts <- c(parts, text)
  }
  player$log <- c(player$log, paste(parts, collapse = " | "))
}
play_row <- function(player, position, row) {
  player$position <- position
  player$row <- row
  player$cells <- song_cells(player$song, position, row)
  start <- player$buffer$count
  key <- row_key(position, row)
  if (!exists(key, envir = player$first_starts, inherits = FALSE)) player$first_starts[[key]] <- start
  start_row(player)
  ticks <- player$speed * (1L + player$delay)
  for (channel in player$channels) {
    if (effect_name(channel) == "EC" && effect_value(channel) >= ticks) warn(player, channel, "cut beyond row") else if (effect_name(channel) == "ED" && effect_value(channel) >= ticks) warn(
        player,
        channel,
        "delay beyond row"
    )
  }
  tick_samples <- samples_per_tick(player$song$rate, player$tempo)
  for (tick in seq_len(ticks) - 1L) {
    process_tick(player, tick)
    if (tick == 0L) log_row(player, start)
    if (key %in% player$params$traces) log_tick(player, tick)
    count <- min(tick_samples, player$params$max_samples - player$buffer$count)
    player$clipped <- player$clipped + mix_tick(
        player$channels,
        count,
        player$song$gain,
        player$params$muted,
        player$buffer
    )
    advance(player)
    if (player$buffer$count == player$params$max_samples) return(FALSE)
  }
  TRUE
}
play <- function(player) {
  position <- row <- 0L
  repeat {
    key <- row_key(position, row)
    count <- if (exists(key, envir = player$play_counts, inherits = FALSE)) player$play_counts[[key]] else 0L
    player$play_counts[[key]] <- count + 1L
    if (!play_row(player, position, row)) {
      player$end_reason <- "limit"
      break
    }
    following <- next_row(player$song, position, row)
    if (is.null(following)) {
      player$end_reason <- "stop"
      player$end_row <- c(position, row)
      break
    }
    position <- following[[1L]]
    row <- following[[2L]]
    if (position >= length(player$song$order)) {
      player$end_reason <- "finished"
      break
    }
    key <- row_key(position, row)
    count <- if (exists(key, envir = player$play_counts, inherits = FALSE)) player$play_counts[[key]] else 0L
    if (count >= player$params$loops) {
      player$end_reason <- "loop"
      player$end_row <- following
      player$loop_start <- player$first_starts[[key]]
      break
    }
  }
  for (channel in player$channels) if (!is.null(channel$record)) end_record(player, channel, "end")
  player$samples <- player$buffer$samples[seq_len(player$buffer$count)]
  player$lanes <- player$buffer$lanes[seq_len(player$buffer$count), , drop = FALSE]
  if (player$end_reason %in% c("limit", "loop") && player$params$fade > 0L) player$samples <- fade_out(
      player$samples,
      player$params$fade
  )
}
end_text <- function(player) {
  if (player$end_reason %in% c("stop", "loop")) paste0(
      player$end_reason,
      " order=",
      hex2(player$end_row[[1L]]),
      " row=",
      hex2(player$end_row[[2L]])
  ) else player$end_reason
}
note_lines <- function(player) {
  vapply(player$records, function(record) {
    indices <- if (record$length) seq.int(record$start + 1L, record$start + record$length) else integer()
    segment <- player$lanes[indices, record$channel]
    cycles <- sum(head(segment, -1L) < 0L & tail(segment, -1L) >= 0L)
    release <- if (is.null(record$release)) "-" else integer_text(record$release)
    paste0(sprintf("%4d", record$serial), " ch=", record$channel, " at=", hex2(record$position), ":", hex2(record$row),
           " ins=", hex2(record$instrument$number), " note=", note_name(record$note), " start=", integer_text(record$start), " length=", integer_text(record$length),
           " release=", release, " end=", record$reason, " peak=", integer_text(peak(
               segment,
               0L
           )), " cycles=", cycles)
  }, "")
}
roll_lines <- function(played, start, rows) {
  indices <- if (start < length(played)) seq.int(start + 1L, min(start + rows, length(played))) else integer()
  targets <- played[indices]
  pitches <- unlist(lapply(targets, `[[`, "notes"))
  pitches <- sort(unique(pitches[!is.na(pitches)]), decreasing = TRUE)
  lines <- paste0("ROLL start=", start, " rows=", length(targets), " pitches=", length(pitches))
  for (pitch in pitches) {
    marks <- vapply(targets, function(row) {
      owners <- which(row$notes == pitch)
      if (!length(owners)) " " else if (length(owners) == 1L) as.character(owners[[1L]]) else "*"
    }, "")
    lines <- c(lines, paste0(note_name(pitch), " |", paste(marks, collapse = ""), "|"))
  }
  ruler <- paste(ifelse((seq_along(targets) - 1L) %% 16L == 0L, "+", "-"), collapse = "")
  c(lines, paste0("    +", ruler, "+"))
}
estimate_key <- function(totals) {
  keys <- list()
  for (mode in c("major", "minor")) {
    weights <- if (mode == "major") MAJOR_WEIGHTS else MINOR_WEIGHTS
    for (tonic in 0L:11L) {
      score <- sum(weights[((0L:11L) - tonic) %% 12L + 1L] * totals)
      keys[[length(keys) + 1L]] <- list(name = paste(TONIC_NAMES[[tonic + 1L]], mode), score = score)
    }
  }
  keys[order(-vapply(keys, `[[`, 0, "score"), seq_along(keys), method = "radix")[1L:2L]]
}
stats_lines <- function(player) {
  song <- player$song
  samples <- player$samples
  total <- length(samples)
  lines <- c(paste0("title=", song$title), paste0("rate=", integer_text(song$rate)), paste0("samples=", total),
             paste0(
                 "duration_ms=",
                 integer_text((total * 1000) %/% song$rate)
             ), paste0("end=", end_text(player)))
  if (player$end_reason == "loop") lines <- c(
      lines,
      paste0("loop_start=", integer_text(player$loop_start)),
      paste0("loop_length=", integer_text(total - player$loop_start))
  ) else lines <- c(lines, "loop_start=-", "loop_length=-")
  lines <- c(lines, paste0("rows=", length(player$played)), paste0("ticks=", player$ticks), paste0("clipped=", player$clipped),
             paste0(
                 "peak=",
                 integer_text(peak(samples, 128L))
             ), paste0("min=", min(samples)), paste0("max=", max(samples)),
             paste0(
                 "rms=",
                 integer_text(root_mean_square(samples, 128L))
             ), paste0("zero_crossings=", zero_crossings(samples)), paste0("adler32=", adler32_text(samples)))
  positions <- integer()
  for (row in player$played) if (!length(positions) || tail(positions, 1L) != row$position) positions <- c(
      positions,
      row$position
  )
  lines <- c(lines, paste("path", paste(hex2(positions), collapse = " ")))
  previous <- NULL
  for (row in player$played) {
    timing <- c(row$speed, row$tempo)
    if (!identical(timing, previous)) lines <- c(
        lines,
        paste0(
            "timing sample=",
            integer_text(row$start),
            " order=",
            hex2(row$position),
            " row=",
            hex2(row$row),
            " speed=",
            row$speed,
            " tempo=",
            row$tempo
        )
    )
    previous <- timing
  }
  for (channel in player$channels) {
    lane <- player$lanes[, channel$number]
    lines <- c(lines, paste0("channel ", channel$number, " notes=", channel$note_ons, " retriggers=", channel$retriggers, " cuts=", channel$cuts,
                             " active=", channel$active, " audible=", channel$audible, " peak=", integer_text(peak(lane, 0L)), " rms=", integer_text(root_mean_square(
                                 lane,
                                 0L
                             ))))
  }
  numbers <- sort(as.integer(names(song$instruments)))
  for (number in numbers) {
    instrument <- song$instruments[[as.character(number)]]
    records <- Filter(function(record) record$instrument$number == number, player$records)
    summary <- if (length(records)) paste0("range=", note_range(vapply(records, `[[`, 0L, "note")), " average=", integer_text(sum(vapply(records, function(record) record$length, 0)) %/% length(records))) else "range=none average=-"
    lines <- c(
        lines,
        paste0(
            "instrument ",
            hex2(number),
            " ",
            instrument$name,
            " ",
            instrument$wave,
            " notes=",
            length(records),
            " ticks=",
            player$instrument_ticks[[as.character(number)]],
            " ",
            summary
        )
    )
  }
  for (number in sort(as.integer(names(song$patterns)))) {
    pattern <- song$patterns[[as.character(number)]]
    rows <- sum(vapply(
        pattern,
        function(cells) any(vapply(cells, function(cell) !is_empty(cell), FALSE)),
        FALSE
    ))
    notes <- sum(vapply(pattern, function(cells) sum(vapply(cells, has_note, FALSE)), 0L))
    lines <- c(
        lines,
        paste0(
            "pattern ",
            hex2(number),
            " rows=",
            rows,
            " notes=",
            notes,
            " orders=",
            sum(song$order == number)
        )
    )
  }
  reached <- reachable_rows(song)
  for (index in seq_along(song$order)) {
    position <- index - 1L
    starts <- vapply(Filter(function(row) row$position == position, player$played), `[[`, 0, "start")
    first <- if (length(starts)) integer_text(starts[[1L]]) else "-"
    dead <- sum(vapply(
        0L:63L,
        function(row) !(row_key(position, row) %in% reached) && any(vapply(
            song_cells(song, position, row),
            has_note,
            FALSE
        )),
        FALSE
    ))
    lines <- c(
        lines,
        paste0(
            "order ",
            hex2(position),
            " pattern=",
            hex2(song$order[[index]]),
            " rows=",
            length(starts),
            " first=",
            first,
            " dead=",
            dead
        )
    )
  }
  notes <- vapply(player$records, function(record) record$note, 0L)
  for (note in sort(unique(notes))) lines <- c(
      lines,
      paste0("note ", note_name(note), " count=", sum(notes == note))
  )
  used_effects <- EFFECT_ORDER[player$effect_counts[EFFECT_ORDER] > 0L]
  lines <- c(
      lines,
      paste(
          "effects",
          if (length(used_effects)) paste(
              paste0(used_effects, "=", player$effect_counts[used_effects]),
              collapse = " "
          ) else "none"
      )
  )
  used_instruments <- vapply(player$records, function(record) record$instrument$number, 0L)
  played_positions <- vapply(player$played, `[[`, 0L, "position")
  patterns <- sort(as.integer(names(song$patterns)))
  all_positions <- seq_along(song$order) - 1L
  lines <- c(lines, paste0("unused_instruments=", hex_list(numbers[!(numbers %in% used_instruments)])),
             paste0("unused_patterns=", hex_list(patterns[!(patterns %in% song$order)])), paste0(
                 "unreached_orders=",
                 hex_list(all_positions[!(all_positions %in% played_positions)])
             ))
  totals <- numeric(12L)
  for (record in player$records) if (record$instrument$wave != "NOISE") totals[[record$note %% 12L + 1L]] <- totals[[record$note %% 12L + 1L]] + record$length
  lines <- c(
      lines,
      paste("pitch_classes", paste(paste0(TONIC_NAMES, "=", integer_text(totals)), collapse = " "))
  )
  keys <- estimate_key(totals)
  lines <- c(
      lines,
      paste0(
          "key=",
          keys[[1L]]$name,
          " score=",
          integer_text(keys[[1L]]$score),
          " runner_up=",
          keys[[2L]]$name,
          " score=",
          integer_text(keys[[2L]]$score)
      )
  )
  for (channel in player$channels) {
    records <- Filter(function(record) record$channel == channel$number, player$records)
    parts <- paste0(
        "usage ch",
        channel$number,
        " range=",
        note_range(vapply(records, function(record) record$note, 0L))
    )
    for (number in numbers) parts <- c(
        parts,
        paste0(
            hex2(number),
            "=",
            sum(vapply(records, function(record) record$instrument$number == number, FALSE))
        )
    )
    lines <- c(lines, paste(parts, collapse = " "))
  }
  c(lines, player$warnings)
}
plot_row <- function(
    value,
    low,
    high,
    height
) (2 * (high - value) * (height - 1L) + (high - low)) %/% (2 * (high - low))
plot_lines <- function(values, low, high, middle, height, width) {
  count <- length(values)
  middle_row <- plot_row(middle, low, high, height)
  columns <- lapply(0L:(width - 1L), function(column) {
    covered <- values[seq.int((column * count) %/% width + 1L, ((column + 1L) * count) %/% width)]
    c(plot_row(max(covered), low, high, height), plot_row(min(covered), low, high, height))
  })
  vapply(0L:(height - 1L), function(row) {
    label <- if (row == 0L) integer_text(high) else if (row == middle_row) integer_text(middle) else if (row == height - 1L) integer_text(low) else ""
    marks <- vapply(
        columns,
        function(column) if (column[[1L]] <= row && row <= column[[2L]]) "#" else if (row == middle_row) "-" else " ",
        ""
    )
    sprintf("%5s |%s|", label, paste(marks, collapse = ""))
  }, "")
}
axis_lines <- function(start, count, width, rate) {
  ruler <- paste(ifelse((0L:(width - 1L)) %% 10L == 0L, "+", "-"), collapse = "")
  labels <- "    ms"
  for (column in seq.int(0L, width - 1L, by = 10L)) {
    milliseconds <- ((start + (column * count) %/% width) * 1000) %/% rate
    labels <- paste0(labels, strrep(" ", max(0L, 7L + column - nchar(labels))), integer_text(milliseconds))
  }
  c(paste0("      +", ruler, "+"), labels)
}
waveform_lines <- function(player) {
  params <- player$params
  start <- params$window_start
  count <- params$window_length
  width <- params$window_width
  indices <- seq.int(start + 1L, start + count)
  axes <- axis_lines(start, count, width, player$song$rate)
  lines <- c(paste0("MIX start=", start, " length=", count, " width=", width, " height=", params$window_height),
             plot_lines(player$samples[indices], 0L, 255L, 128L, params$window_height, width), axes)
  for (channel in player$channels) lines <- c(
      lines,
      paste("CHANNEL", channel$number),
      plot_lines(
          player$lanes[indices, channel$number],
          -LANE_LIMIT,
          LANE_LIMIT,
          0L,
          params$window_scope,
          width
      )
  )
  c(lines, axes)
}
preview_lines <- function(song, params, instrument) {
  channel <- new_channel(1L)
  channel$instrument <- instrument
  channel$mode <- instrument$mode
  channel$note <- params$preview_note
  channel$frequency <- note_frequency(params$preview_note)
  channel$target <- channel$frequency
  channel$sounding <- TRUE
  tick_samples <- samples_per_tick(song$rate, song$tempo)
  buffer <- new_buffer(params$preview_ticks * tick_samples, 1L)
  envelopes <- character()
  frequencies <- numeric()
  for (tick in seq_len(params$preview_ticks) - 1L) {
    channel$age <- tick
    if (tick == params$preview_release) key_off(channel)
    if (tick >= 1L && instrument$sweep != 0L) channel$frequency <- clamp(
        channel$frequency + 10L * instrument$sweep,
        FMIN,
        50 * song$rate
    )
    update_output(channel, tick, song$rate)
    envelopes <- c(envelopes, hex1(channel$envelope))
    frequencies <- c(frequencies, channel$output_frequency)
    mix_tick(list(channel), tick_samples, song$gain, FALSE, buffer)
  }
  samples <- buffer$samples[seq_len(buffer$count)]
  c(paste0("instrument ", hex2(instrument$number), " ", instrument$name, " wave=", instrument$wave, " samples=", length(samples),
           " peak=", integer_text(peak(samples, 128L)), " rms=", integer_text(root_mean_square(
               samples,
               128L
           )), " adler32=", adler32_text(samples)),
    paste0("  env ", paste(envelopes, collapse = "")), paste0(
        "  freq ",
        paste(integer_text(frequencies), collapse = " ")
    ))
}
main <- function() {
  song <- read_song(file.path("input", "song.txt"))
  params <- read_params(file.path("input", "params.txt"))
  player <- new_player(song, params)
  play(player)
  previews <- character()
  for (number in sort(as.integer(names(song$instruments)))) previews <- c(
      previews,
      preview_lines(song, params, song$instruments[[as.character(number)]])
  )
  outputs <- list("samples.txt" = hex_lines(player$samples), "channel_log.txt" = player$log, "notes.txt" = note_lines(player),
                  "roll.txt" = roll_lines(
                      player$played,
                      params$roll_start,
                      params$roll_rows
                  ), "stats.txt" = stats_lines(player),
                  "waveform.txt" = waveform_lines(player), "instruments.txt" = previews)
  dir.create("output", showWarnings = FALSE)
  for (name in names(outputs)) writeLines(outputs[[name]], file.path("output", name), useBytes = TRUE)
}
main()
