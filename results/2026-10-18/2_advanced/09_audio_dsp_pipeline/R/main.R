script_args <- grep("^--file=", commandArgs(), value = TRUE)
source_dir <- if (length(script_args)) dirname(sub("^--file=", "", script_args[1L])) else "R"
for (unit in c("signals", "effects", "filters", "dynamics", "analysis")) source(file.path(source_dir, paste0(unit, ".R")))

argument <- function(name, low = NULL, high = NULL) {
  kinds <- c(dst = "name", var = "name", src = "signal", metric = "metric", op = "operator")
  list(name = name, kind = if (name %in% names(kinds)) unname(kinds[name]) else "integer", low = low, high = high)
}
command <- function(arguments, repeated = list(), minimum = 0L, maximum = 0L) list(arguments = arguments, repeated = repeated, minimum = minimum, maximum = maximum)
DST <- argument("dst")
SRC <- argument("src")
RATE <- argument("rate", 1000, 48000)
COUNT <- argument("count", 1, 20000)
NUM <- argument("num", -65536, 65536)
DEN <- argument("den", 1, 65536)
ATTACK <- argument("attack", 1, 32768)
RELEASE <- argument("release", 1, 32768)
START <- argument("start", 0, "L - 1")
MIN_HZ <- argument("min_hz", 1, "rate div 2 - 1")
MAX_HZ <- argument("max_hz", "min_hz + 1", "rate div 2")
TEST_SIGNAL <- list(DST, RATE, COUNT, argument("pos", 0, "count - 1"), argument("amp", -32768, 32767))
COMMANDS <- list(
  SET = command(list(argument("var"), argument("value", -10000000, 10000000)), list(argument("op"), argument("operand", -10000000, 10000000)), 0L, 1L),
  IMPULSE = command(TEST_SIGNAL), STEP = command(TEST_SIGNAL), NOISE = command(list(DST, RATE, COUNT, argument("seed", 1, 2147483646))),
  GAIN = command(list(DST, SRC, NUM, DEN)), MIX = command(list(DST, DEN), list(SRC, argument("weight", -65536, 65536)), 1L, 8L),
  DELAY = command(list(DST, SRC, argument("samples", 0, 20000))), ECHO = command(list(DST, SRC, argument("delay", 1, 20000), NUM, DEN, argument("tail", 0, 20000))),
  RESAMPLE = command(list(DST, SRC, argument("new_rate", 1000, 48000))), FADE = command(list(DST, SRC, argument("in", 0, "L"), argument("out", 0, "L"))),
  TRIM = command(list(DST, SRC, START, argument("count", 1, "L - start"))), CONCAT = command(list(DST), list(SRC), 2L, 8L),
  FIR = command(list(DST, SRC, argument("divisor", 1, 1000000)), list(argument("tap", -32768, 32767)), 1L, 64L),
  BIQUAD = command(list(DST, SRC), lapply(c("b0", "b1", "b2", "a1", "a2"), argument, low = -65536, high = 65536), 1L, 4L),
  MOVAVG = command(list(DST, SRC, argument("width", 1, 1000))), DCBLOCK = command(list(DST, SRC, argument("num", 0, 65535), argument("den", "num + 1", 65536))),
  NORMALIZE = command(list(DST, SRC, argument("target", 1, 32767))), GATE = command(list(DST, SRC, argument("threshold", 1, 32768), argument("hold", 0, 20000))),
  ENVELOPE = command(list(DST, SRC, ATTACK, RELEASE)), COMPRESS = command(list(DST, SRC, argument("threshold", 1, 32767), argument("ratio_num", 1, 100), argument("ratio_den", 1, "ratio_num"), ATTACK, RELEASE)),
  ANALYZE = command(list(SRC, MIN_HZ, MAX_HZ)), COMPARE = command(list(SRC, SRC)), EXPECT = command(list(SRC, argument("metric"), argument("op"), argument("value", -1000000000, 1000000000))),
  SEGMENTS = command(list(SRC, argument("threshold", 1, 32768), argument("gap", 1, 20000), argument("min_length", 1, 20000))),
  ONSETS = command(list(SRC, ATTACK, RELEASE, argument("threshold", 1, 32767), argument("min_gap", 1, 20000))),
  PITCHTRACK = command(list(SRC, argument("frame", 16, "L"), argument("hop", 1, "frame"), MIN_HZ, MAX_HZ, argument("threshold", 0, 32767))),
  EXCERPT = command(list(SRC, START, argument("count", 1, 1000))), PLOT = command(list(SRC, START, argument("count", 1, "L - start"), argument("columns", 8, "min(120, count)"), argument("half", 2, 20), ATTACK, RELEASE)),
  METER = command(list(SRC, argument("block", 1, 20000))), HISTOGRAM = command(list(SRC, argument("bins", 2, 64))), TRACE = command(list(SRC)), SAVE = command(list(SRC)))
GENERATORS <- c("IMPULSE", "STEP", "NOISE", "GAIN", "MIX", "DELAY", "ECHO", "RESAMPLE", "FADE", "TRIM", "CONCAT", "FIR", "BIQUAD", "MOVAVG", "DCBLOCK", "NORMALIZE", "GATE", "ENVELOPE", "COMPRESS")
METRICS <- list(samples = length, peak = peak, rms = rms, sum = sum, zero_crossings = zero_crossings, clipped = count_clipped)

fail <- function(message) stop(structure(list(message = message, call = NULL), class = c("pipeline_error", "error", "condition")))
kv <- function(name, value) paste0(name, "=", integer_text(value))
ceil_divide <- function(a, b) -integer_divide(-a, b)
milliseconds <- function(index, rate) integer_divide(index * 1000, rate)
two_decimals <- function(value) paste0(integer_text(integer_divide(value, 100)), ".", sprintf("%02.0f", integer_mod(value, 100)))
frequency_text <- function(rate, lag) two_decimals(rdiv(100 * rate, lag))
lag_range <- function(rate, minimum, maximum) c(ceil_divide(rate, maximum), integer_divide(rate, minimum))

resolve_bound <- function(bound, known, source) {
  if (is.numeric(bound)) return(bound)
  switch(bound, "count - 1" = known$count - 1, "min(120, count)" = min(120, known$count), "min_hz + 1" = known$min_hz + 1,
         "num + 1" = known$num + 1, "L" = length(source$samples), "L - 1" = length(source$samples) - 1,
         "L - start" = length(source$samples) - known$start, "rate div 2" = integer_divide(source$rate, 2),
         "rate div 2 - 1" = integer_divide(source$rate, 2) - 1, known[[bound]])
}

parse_arguments <- function(pipeline, name, tokens) {
  spec <- COMMANDS[[name]]
  if (is.null(spec)) fail(paste("unknown command", name))
  extra <- length(tokens) - length(spec$arguments)
  if (!length(spec$repeated)) {
    if (extra != 0L) fail("wrong number of arguments")
  } else if (extra < spec$minimum * length(spec$repeated) || extra > spec$maximum * length(spec$repeated) || extra %% length(spec$repeated) != 0L) fail("wrong number of arguments")
  values <- sources <- list()
  known <- list()
  for (index in seq_along(tokens)) {
    descriptor <- if (index <= length(spec$arguments)) spec$arguments[[index]] else spec$repeated[[(index - length(spec$arguments) - 1L) %% length(spec$repeated) + 1L]]
    token <- tokens[index]
    kind <- descriptor$kind
    if (kind == "name") {
      if (!grepl("^[a-z][a-z0-9_]{0,15}$", token)) fail(paste("bad name", token))
      value <- token
    } else if (kind == "signal") {
      if (!token %in% names(pipeline$signals)) fail(paste("unknown signal", token))
      value <- pipeline$signals[[token]]
      sources[[length(sources) + 1L]] <- value
    } else if (kind == "metric") {
      if (!token %in% names(METRICS)) fail(paste("unknown metric", token))
      value <- token
    } else if (kind == "operator") {
      operators <- if (name == "SET") c("+", "-", "*", "/") else c("eq", "ne", "lt", "le", "gt", "ge")
      if (!token %in% operators) fail(paste("unknown operator", token))
      value <- token
    } else {
      if (startsWith(token, "$")) {
        variable <- substring(token, 2L)
        if (!variable %in% names(pipeline$variables)) fail(paste("undefined variable", token))
        value <- pipeline$variables[[variable]]
      } else {
        if (token == "-0" || !grepl("^-?(0|[1-9][0-9]{0,9})$", token)) fail(paste("bad integer", token))
        value <- as.numeric(token)
      }
      source <- if (length(sources)) sources[[1L]] else NULL
      if (value < resolve_bound(descriptor$low, known, source) || value > resolve_bound(descriptor$high, known, source)) fail(paste(descriptor$name, "out of range"))
      known[[descriptor$name]] <- value
    }
    values[[index]] <- value
  }
  list(values = values, sources = sources)
}

require_same_rate <- function(sources) if (any(vapply(sources, function(source) source$rate, numeric(1L)) != sources[[1L]]$rate)) fail("rate mismatch")

generate_signal <- function(pipeline, number, name, values, sources) {
  dst <- values[[1L]]
  args <- values[-1L]
  extras <- list()
  if (name %in% c("IMPULSE", "STEP", "NOISE")) {
    rate <- args[[1L]]
    samples <- if (name == "IMPULSE") do.call(impulse, args[-1L]) else if (name == "STEP") do.call(step_signal, args[-1L]) else do.call(noise, args[-1L])
  } else {
    source <- sources[[1L]]
    samples <- source$samples
    rate <- source$rate
    result <- NULL
    if (name == "GAIN") result <- gain(samples, args[[2L]], args[[3L]])
    else if (name == "MIX") {
      require_same_rate(sources)
      result <- mix(lapply(sources, function(source) source$samples), unlist(args[seq.int(3L, length(args), by = 2L)]), args[[1L]])
    } else if (name == "DELAY") {
      if (length(samples) + args[[2L]] > 20000) fail("result too long")
      samples <- delay_signal(samples, args[[2L]])
    } else if (name == "ECHO") {
      if (abs(args[[3L]]) >= args[[4L]]) fail("unstable feedback")
      if (length(samples) + args[[5L]] > 20000) fail("result too long")
      result <- echo(samples, args[[2L]], args[[3L]], args[[4L]], args[[5L]])
    } else if (name == "RESAMPLE") {
      if (resampled_length(length(samples), rate, args[[2L]]) > 20000) fail("result too long")
      samples <- resample(samples, rate, args[[2L]])
      rate <- args[[2L]]
    } else if (name == "FADE") samples <- fade(samples, args[[2L]], args[[3L]])
    else if (name == "TRIM") samples <- samples[seq.int(args[[2L]] + 1L, args[[2L]] + args[[3L]])]
    else if (name == "CONCAT") {
      require_same_rate(sources)
      if (sum(vapply(sources, function(source) length(source$samples), integer(1L))) > 20000) fail("result too long")
      samples <- unlist(lapply(sources, function(source) source$samples), use.names = FALSE)
    } else if (name == "FIR") result <- fir(samples, args[[2L]], unlist(args[-c(1L, 2L)]))
    else if (name == "BIQUAD") {
      coefficients <- unlist(args[-1L])
      sections <- lapply(seq.int(1L, length(coefficients), by = 5L), function(first) coefficients[seq.int(first, first + 4L)])
      result <- biquad(samples, sections)
      result <- c(list(samples = result$samples, sections = length(sections)), list(clipped = result$clipped))
    } else if (name == "MOVAVG") samples <- moving_average(samples, args[[2L]])
    else if (name == "DCBLOCK") result <- dc_block(samples, args[[2L]], args[[3L]])
    else if (name == "NORMALIZE") result <- normalize(samples, args[[2L]])
    else if (name == "GATE") result <- gate(samples, args[[2L]], args[[3L]])
    else if (name == "ENVELOPE") samples <- envelope(samples, args[[2L]], args[[3L]])
    else if (name == "COMPRESS") result <- do.call(compress, c(list(samples), args[-1L]))
    if (!is.null(result)) {
      samples <- result$samples
      extras <- result[-1L]
    }
  }
  signal <- signal_record(dst, rate, samples, paste("line", number, name), sources)
  pipeline$signals[[dst]] <- signal
  details <- paste(dst, kv("rate", rate), kv("samples", length(samples)), kv("peak", peak(samples)), kv("sum", sum(samples)))
  for (key in names(extras)) details <- paste(details, kv(key, extras[[key]]))
  details
}

waveform_plot <- function(source, start, count, columns, half, attack, release) {
  window <- source$samples[seq.int(start + 1L, start + count)]
  levels <- envelope(source$samples, attack, release)[seq.int(start + 1L, start + count)]
  rows <- 2L * half + 1L
  scale <- max(1, peak(window))
  row_of <- function(value) rdiv((scale - value) * (rows - 1L), 2L * scale)
  grid <- matrix(" ", rows, columns)
  for (column in seq_len(columns)) {
    first <- integer_divide((column - 1L) * count, columns) + 1L
    last <- integer_divide(column * count, columns)
    top <- row_of(max(window[seq.int(first, last)]))
    bottom <- row_of(min(window[seq.int(first, last)]))
    level <- min(scale, max(levels[seq.int(first, last)]))
    marks <- c(row_of(level), row_of(-level))
    for (row in seq_len(rows) - 1L) grid[row + 1L, column] <- if (row %in% marks) "*" else if (row >= top && row <= bottom) "#" else if (row == half) "-" else " "
  }
  lines <- paste("PLOT", source$name, kv("rate", source$rate), kv("start", start), kv("count", count), kv("columns", columns), kv("rows", rows), kv("scale", scale), kv("attack", attack), kv("release", release))
  for (row in seq_len(rows) - 1L) {
    label <- if (row == 0L) integer_text(scale) else if (row == half) "0" else if (row == rows - 1L) integer_text(-scale) else ""
    lines <- c(lines, paste0(sprintf("%6s", label), " |", paste(grid[row + 1L, ], collapse = ""), "|"))
  }
  axis <- ifelse((seq_len(columns) - 1L) %% 10L == 0L, "+", "-")
  lines <- c(lines, paste0("       +", paste(axis, collapse = ""), "+"))
  time <- "    ms"
  for (column in seq.int(0L, columns - 1L, by = 10L)) {
    index <- start + integer_divide(column * count, columns)
    time <- paste0(time, strrep(" ", max(0, 8L + column - nchar(time, type = "bytes"))), integer_text(milliseconds(index, source$rate)))
  }
  c(lines, time)
}

meter_plot <- function(source, block) {
  blocks <- ceil_divide(length(source$samples), block)
  lines <- paste("METER", source$name, kv("rate", source$rate), kv("samples", length(source$samples)), kv("block", block), kv("blocks", blocks))
  for (index in seq_len(blocks) - 1L) {
    part <- source$samples[seq.int(index * block + 1L, min((index + 1L) * block, length(source$samples)))]
    p <- peak(part)
    q <- rms(part)
    peak_width <- rdiv(p * 40, 32768)
    rms_width <- rdiv(q * 40, 32768)
    bar <- vapply(0L:39L, function(position) if (position < rms_width) "#" else if (position < peak_width) "-" else " ", character(1L))
    lines <- c(lines, paste0(sprintf("%6.0f", milliseconds(index * block, source$rate)), " |", paste(bar, collapse = ""), "| ", kv("peak", p), " ", kv("rms", q), " ", kv("clipped", count_clipped(part))))
  }
  lines
}

histogram_plot <- function(source, bins) {
  counts <- numeric(bins)
  for (value in source$samples) {
    bin <- integer_divide((value + 32768) * bins, 65536) + 1L
    counts[bin] <- counts[bin] + 1L
  }
  edges <- vapply(seq.int(0L, bins), function(bin) ceil_divide(bin * 65536, bins) - 32768, numeric(1L))
  top <- max(counts)
  lines <- paste("HISTOGRAM", source$name, kv("rate", source$rate), kv("samples", length(source$samples)), kv("bins", bins), kv("max", top))
  for (bin in seq_len(bins)) lines <- c(lines, paste0(sprintf("%6.0f %6.0f %5.0f |", edges[bin], edges[bin + 1L] - 1L, counts[bin]), strrep("#", rdiv(counts[bin] * 50, top))))
  lines
}

pitch_row <- function(rate, start, level, lag, low, high) {
  band <- rep(" ", 41L)
  prefix <- paste0(sprintf("%6.0f", milliseconds(start, rate)), " |")
  if (is.na(lag)) return(paste0(prefix, paste(band, collapse = ""), "| unvoiced ", kv("rms", level)))
  position <- if (high > low) rdiv((high - lag) * 40, high - low) else 0
  band[position + 1L] <- "o"
  paste0(prefix, paste(band, collapse = ""), "| ", kv("lag", lag), " hz=", frequency_text(rate, lag), " ", kv("rms", level))
}

trace_lines <- function(signal, depth) {
  lines <- paste0(strrep("  ", depth), signal$name, " <- ", signal$origin)
  for (ingredient in signal$ingredients) lines <- c(lines, trace_lines(ingredient, depth + 1L))
  lines
}

execute_command <- function(pipeline, number, name, parsed) {
  values <- parsed$values
  if (name %in% GENERATORS) return(generate_signal(pipeline, number, name, values, parsed$sources))
  if (name == "SET") {
    result <- values[[2L]]
    if (length(values) == 4L) {
      operator <- values[[3L]]
      operand <- values[[4L]]
      if (operator == "/" && operand == 0) fail("division by zero")
      result <- switch(operator, "+" = result + operand, "-" = result - operand, "*" = result * operand, "/" = integer_divide(result, operand))
      if (abs(result) > 10000000) fail("value out of range")
    }
    pipeline$variables[[values[[1L]]]] <- result
    return(kv(values[[1L]], result))
  }
  source <- values[[1L]]
  samples <- source$samples
  sample_count <- length(samples)
  if (name == "ANALYZE") {
    lags <- lag_range(source$rate, values[[2L]], values[[3L]])
    if (lags[1L] > lags[2L]) fail("empty lag range")
    if (lags[2L] >= sample_count) fail("signal too short")
    lag <- pitch_lag(samples, lags[1L], lags[2L])
    fields <- c(source$name, integer_text(peak(samples)), integer_text(rms(samples)), integer_text(zero_crossings(samples)), integer_text(count_clipped(samples)), crest_fraction(samples),
                if (is.na(lag)) "none" else integer_text(lag), if (is.na(lag)) "none" else frequency_text(source$rate, lag))
    pipeline$analysis <- c(pipeline$analysis, paste(fields, collapse = ","))
    return(paste0(source$name, " lags=", integer_text(lags[1L]), "-", integer_text(lags[2L])))
  }
  if (name == "COMPARE") {
    second <- values[[2L]]
    require_same_rate(list(source, second))
    count <- max(sample_count, length(second$samples))
    a <- c(samples, rep(0, count - sample_count))
    b <- c(second$samples, rep(0, count - length(second$samples)))
    differences <- a - b
    first <- which(differences != 0)
    first_text <- if (length(first)) integer_text(first[1L] - 1L) else "none"
    return(paste(source$name, second$name, kv("differing", sum(differences != 0)), kv("max_diff", max(abs(differences))), paste0("first=", first_text), kv("error_energy", energy(differences))))
  }
  if (name == "EXPECT") {
    metric <- values[[2L]]
    operator <- values[[3L]]
    target <- values[[4L]]
    value <- METRICS[[metric]](samples)
    passed <- switch(operator, eq = value == target, ne = value != target, lt = value < target, le = value <= target, gt = value > target, ge = value >= target)
    if (passed) pipeline$passed <- pipeline$passed + 1L else pipeline$failed <- pipeline$failed + 1L
    return(paste(source$name, kv(metric, value), operator, integer_text(target), if (passed) "pass" else "fail"))
  }
  if (name == "SEGMENTS") {
    threshold <- values[[2L]]
    gap <- values[[3L]]
    minimum <- values[[4L]]
    found <- list()
    for (index in which(abs(samples) >= threshold) - 1L) {
      last <- length(found)
      if (last && index - found[[last]][2L] <= gap) found[[last]][2L] <- index else found[[last + 1L]] <- c(index, index)
    }
    found <- Filter(function(segment) segment[2L] - segment[1L] + 1L >= minimum, found)
    lines <- paste(source$name, kv("segments", length(found)))
    for (index in seq_along(found)) {
      bounds <- found[[index]]
      part <- samples[seq.int(bounds[1L] + 1L, bounds[2L] + 1L)]
      lines <- c(lines, paste0("  segment ", index, " ", paste(kv("start", bounds[1L]), kv("end", bounds[2L]), kv("start_ms", milliseconds(bounds[1L], source$rate)), kv("end_ms", milliseconds(bounds[2L], source$rate)), kv("peak", peak(part)), kv("rms", rms(part)), kv("crossings", zero_crossings(part)))))
    }
    return(lines)
  }
  if (name == "ONSETS") {
    levels <- envelope(samples, values[[2L]], values[[3L]])
    threshold <- values[[4L]]
    gap <- values[[5L]]
    onsets <- numeric()
    for (index in seq_along(samples)) if (levels[index] >= threshold && (index == 1L || levels[index - 1L] < threshold) && (!length(onsets) || index - 1L - tail(onsets, 1L) >= gap)) onsets <- c(onsets, index - 1L)
    intervals <- diff(onsets)
    tempo <- if (length(onsets) < 2L) "none" else two_decimals(rdiv(6000 * source$rate, sort(intervals)[integer_divide(length(onsets) - 2L, 2) + 1L]))
    lines <- paste(source$name, kv("onsets", length(onsets)), paste0("tempo=", tempo))
    for (index in seq_along(onsets)) lines <- c(lines, paste0("  onset ", index, " ", paste(kv("sample", onsets[index]), kv("ms", milliseconds(onsets[index], source$rate)), paste0("interval=", if (index == 1L) "none" else integer_text(intervals[index - 1L])))))
    return(lines)
  }
  if (name == "PITCHTRACK") {
    frame <- values[[2L]]
    hop <- values[[3L]]
    lags <- lag_range(source$rate, values[[4L]], values[[5L]])
    threshold <- values[[6L]]
    if (lags[1L] > lags[2L]) fail("empty lag range")
    if (lags[2L] >= frame) fail("frame too short")
    count <- integer_divide(sample_count - frame, hop) + 1L
    rows <- character()
    voiced <- 0L
    for (index in seq_len(count) - 1L) {
      part <- samples[seq.int(index * hop + 1L, index * hop + frame)]
      level <- rms(part)
      lag <- if (level < threshold) NA_real_ else pitch_lag(part, lags[1L], lags[2L])
      if (!is.na(lag)) voiced <- voiced + 1L
      rows <- c(rows, pitch_row(source$rate, index * hop, level, lag, lags[1L], lags[2L]))
    }
    heading <- paste("PITCHTRACK", source$name, kv("rate", source$rate), kv("frame", frame), kv("hop", hop), paste0("lags=", integer_text(lags[1L]), "-", integer_text(lags[2L])), kv("threshold", threshold), kv("frames", count), kv("voiced", voiced))
    pipeline$waveforms <- c(pipeline$waveforms, heading, rows)
    return(paste(source$name, kv("frames", count), kv("voiced", voiced)))
  }
  if (name == "EXCERPT") {
    start <- values[[2L]]
    count <- min(values[[3L]], sample_count - start)
    lines <- paste("EXCERPT", source$name, kv("rate", source$rate), kv("samples", sample_count), kv("start", start), kv("count", count))
    for (offset in seq.int(0L, count - 1L, by = 8L)) {
      part <- samples[seq.int(start + offset + 1L, start + min(offset + 8L, count))]
      lines <- c(lines, paste0(sprintf("%5.0f:", start + offset), paste(sprintf(" %6.0f", part), collapse = "")))
    }
    pipeline$excerpts <- c(pipeline$excerpts, lines)
    return(paste(source$name, kv("start", start), kv("count", count)))
  }
  if (name == "PLOT") {
    pipeline$waveforms <- c(pipeline$waveforms, do.call(waveform_plot, values))
    return(paste(source$name, kv("start", values[[2L]]), kv("count", values[[3L]]), kv("columns", values[[4L]]), kv("rows", 2L * values[[5L]] + 1L)))
  }
  if (name == "METER") {
    pipeline$waveforms <- c(pipeline$waveforms, meter_plot(source, values[[2L]]))
    return(paste(source$name, kv("block", values[[2L]])))
  }
  if (name == "HISTOGRAM") {
    pipeline$waveforms <- c(pipeline$waveforms, histogram_plot(source, values[[2L]]))
    return(paste(source$name, kv("bins", values[[2L]])))
  }
  if (name == "TRACE") return(c(source$name, trace_lines(source, 1L)))
  pipeline$saved <- c(pipeline$saved, format_signal(source))
  paste(source$name, kv("samples", sample_count))
}

main <- function() {
  pipeline <- new.env(parent = emptyenv())
  pipeline$signals <- pipeline$variables <- list()
  pipeline$log <- pipeline$excerpts <- pipeline$waveforms <- pipeline$saved <- character()
  pipeline$analysis <- "signal,peak,rms,zero_crossings,clipped,crest,pitch_lag,pitch_hz"
  pipeline$steps <- pipeline$errors <- pipeline$passed <- pipeline$failed <- 0L
  for (signal in read_signals()) {
    pipeline$signals[[signal$name]] <- signal
    pipeline$log <- c(pipeline$log, paste("load", signal$name, kv("rate", signal$rate), kv("samples", length(signal$samples)), kv("peak", peak(signal$samples))))
  }
  lines <- readLines("input/pipeline.txt", warn = FALSE)
  for (number in seq_along(lines)) {
    line <- lines[number]
    if (!nzchar(line) || startsWith(line, "#")) next
    tokens <- strsplit(line, " ", fixed = TRUE)[[1L]]
    name <- tokens[1L]
    result <- tryCatch(execute_command(pipeline, number, name, parse_arguments(pipeline, name, tokens[-1L])), pipeline_error = function(error) error)
    if (inherits(result, "pipeline_error")) {
      pipeline$errors <- pipeline$errors + 1L
      pipeline$log <- c(pipeline$log, paste0("line ", number, ": error: ", result$message))
    } else {
      pipeline$steps <- pipeline$steps + 1L
      pipeline$log <- c(pipeline$log, paste0("line ", number, ": ", name, " ", result[1L]), result[-1L])
    }
  }
  for (name in sort(names(pipeline$signals), method = "radix")) {
    signal <- pipeline$signals[[name]]
    pipeline$log <- c(pipeline$log, paste("signal", name, kv("rate", signal$rate), kv("samples", length(signal$samples)), kv("peak", peak(signal$samples)), kv("rms", rms(signal$samples))))
  }
  pipeline$log <- c(pipeline$log, paste("summary", kv("steps", pipeline$steps), kv("errors", pipeline$errors), kv("signals", length(pipeline$signals)), kv("passed", pipeline$passed), kv("failed", pipeline$failed)))
  dir.create("output", showWarnings = FALSE)
  outputs <- list("log.txt" = pipeline$log, "analysis.csv" = pipeline$analysis, "excerpts.txt" = pipeline$excerpts, "waveforms.txt" = pipeline$waveforms, "signals_out.txt" = pipeline$saved)
  for (name in names(outputs)) writeLines(outputs[[name]], file.path("output", name), useBytes = TRUE)
}

main()
