script_args <- grep("^--file=", commandArgs(), value = TRUE)
source_dir <- if (length(script_args)) dirname(sub("^--file=", "", script_args[1L])) else "R"
for (unit in c("dataset", "variable_charts", "attribute_charts", "run_rules", "capability", "plot")) source(file.path(source_dir, paste0(unit, ".R")))

CHART_ORDER <- c("XBAR_R", "R", "XBAR_S", "S", "I", "MR", "CUSUM", "EWMA", "MA")
SHEWHART_CHARTS <- CHART_ORDER[1L:6L]
RULE_ORDER <- c(as.character(1L:8L), "UPPER", "LOWER")
LOCATION_CHARTS <- c("XBAR_R", "XBAR_S", "I", "CUSUM", "EWMA", "MA")
EVENT_TYPES <- c("SHIFT_UP", "SHIFT_DOWN", "SPREAD_UP", "SPREAD_DOWN", "PATTERN")
FAMILIES <- c("XBAR_R", "XBAR_S", "I_MR")
FAMILY_LABELS <- list(XBAR_R = c("XBAR", "R"), XBAR_S = c("XBAR", "S"), I_MR = c("I", "MR"))
FAMILY_CHARTS <- list(XBAR_R = c("XBAR_R", "R"), XBAR_S = c("XBAR_S", "S"), I_MR = c("I", "MR"))
CHART_FAMILIES <- list(XBAR_R = c("XBAR_R", "1"), R = c("XBAR_R", "2"), XBAR_S = c("XBAR_S", "1"), S = c("XBAR_S", "2"), I = c("I_MR", "1"), MR = c("I_MR", "2"))

real_text <- function(value) {
  text <- sprintf("%.4f", value)
  text[text == "-0.0000"] <- "0.0000"
  text
}

integer_text <- function(value) sprintf("%.0f", value)
text_line <- function(...) paste(vapply(list(...), function(value) if (is.numeric(value)) integer_text(value) else value, character(1L)), collapse = " ")
number_list <- function(numbers) if (length(numbers)) paste(integer_text(sort(numbers)), collapse = " ") else "none"
status_text <- function(converged) if (converged) "converged" else "stopped"
limits_text <- function(label, limits) paste(label, "lcl", real_text(limits$lcl), "cl", real_text(limits$cl), "ucl", real_text(limits$ucl))

pair_text <- function(family, limits) paste(limits_text(FAMILY_LABELS[[family]][1L], limits[[1L]]), limits_text(FAMILY_LABELS[[family]][2L], limits[[2L]]))

family_limits <- function(analysis, family, numbers) {
  if (family == "I_MR") return(i_mr_limits(analysis$values[numbers], analysis$pair_constants))
  chosen <- analysis$subgroups[numbers]
  if (family == "XBAR_R") xbar_r_limits(chosen, analysis$size, analysis$constants)
  else xbar_s_limits(chosen, analysis$size, analysis$constants)
}

family_series <- function(analysis, family, numbers) {
  if (family == "I_MR") {
    values <- analysis$values[numbers]
    return(list(list(numbers = numbers, values = values), list(numbers = numbers[-1L], values = moving_ranges(values))))
  }
  chosen <- analysis$subgroups[numbers]
  field <- if (family == "XBAR_R") "range" else "sd"
  list(list(numbers = numbers, values = vapply(chosen, function(group) group$mean, numeric(1L))),
       list(numbers = numbers, values = vapply(chosen, function(group) group[[field]], numeric(1L))))
}

estimate_family <- function(analysis, family) {
  initial <- seq_len(if (family == "I_MR") analysis$phase1 * analysis$size else analysis$phase1)
  points <- initial
  passes <- list()
  converged <- FALSE
  for (pass in seq_len(analysis$settings$max_passes)) {
    limits <- family_limits(analysis, family, points)
    series <- family_series(analysis, family, points)
    outliers <- integer()
    for (index in seq_len(2L)) outliers <- c(outliers, series[[index]]$numbers[outside(limits[[index]], series[[index]]$values)])
    outliers <- sort(unique(outliers))
    passes[[pass]] <- list(points = length(points), limits = limits, outliers = outliers)
    if (!length(outliers)) {
      converged <- TRUE
      break
    }
    if (pass < analysis$settings$max_passes) points <- setdiff(points, outliers)
  }
  list(passes = passes, converged = converged, limits = limits, retained = points, removed = setdiff(initial, points))
}

chart_limits <- function(analysis, chart) {
  location <- CHART_FAMILIES[[chart]]
  analysis$estimates[[location[1L]]]$limits[[as.integer(location[2L])]]
}

signal_subgroup <- function(analysis, signal) {
  if (signal$chart %in% c("I", "MR")) (signal$end - 1L) %/% analysis$size + 1L else signal$end
}

event_of <- function(analysis, number) {
  for (event in analysis$events) if (number >= event$start && number <= event$end) return(event)
  NULL
}

has_signal <- function(analysis, chart, end, rule = NULL) {
  any(vapply(analysis$signals, function(signal) signal$chart == chart && signal$end == end && (is.null(rule) || signal$rule == rule), logical(1L)))
}

build_events <- function(analysis) {
  groups <- vapply(analysis$signals, function(signal) signal_subgroup(analysis, signal), integer(1L))
  events <- list()
  for (group in sort(unique(groups))) {
    last <- length(events)
    if (last && group - events[[last]]$end - 1L <= analysis$settings$event_gap) events[[last]]$end <- group
    else events[[last + 1L]] <- list(number = last + 1L, start = group, end = group)
  }
  for (index in seq_along(events)) {
    event <- events[[index]]
    event$signals <- analysis$signals[groups >= event$start & groups <= event$end]
    counts <- integer(5L)
    for (signal in event$signals) {
      type <- if (signal$direction == "NONE") 5L else if (signal$chart %in% LOCATION_CHARTS) {
        if (signal$direction == "UP") 1L else 2L
      } else if (signal$direction == "UP") 3L else 4L
      counts[type] <- counts[type] + 1L
    }
    event$counts <- counts
    event$kind <- EVENT_TYPES[which.max(counts)]
    starts <- vapply(Filter(function(signal) signal$chart == "CUSUM", event$signals), function(signal) signal$start, integer(1L))
    event$onset <- if (length(starts)) min(starts) else event$start
    covered <- analysis$subgroups[seq.int(event$start, event$end)]
    span <- event$end - event$start + 1L
    mean <- sum(vapply(covered, function(group) group$total, numeric(1L))) / (analysis$size * span)
    event$shift <- (mean - analysis$mu0) / analysis$sigma
    event$spread <- (real_sum(vapply(covered, function(group) group$sd, numeric(1L))) / span) / analysis$sbar
    values <- unlist(lapply(covered, function(group) group$values), use.names = FALSE)
    event$out_of_spec <- sum(values < analysis$settings$lsl | values > analysis$settings$usl)
    event$detection <- vapply(CHART_ORDER, function(chart) {
      signals <- Filter(function(signal) signal$chart == chart, event$signals)
      if (length(signals)) min(vapply(signals, function(signal) signal_subgroup(analysis, signal), integer(1L))) else 0L
    }, integer(1L))
    events[[index]] <- event
  }
  events
}

estimate_attribute <- function(analysis, chart) {
  lots <- analysis$lots
  passes <- list()
  converged <- FALSE
  for (pass in seq_len(analysis$settings$max_passes)) {
    center <- center_line(chart, lots)
    outliers <- vapply(Filter(function(lot) lot_point(lot, center)$status != "ok", lots), function(lot) lot$number, integer(1L))
    passes[[pass]] <- list(lots = length(lots), center = center$value, outliers = outliers)
    if (!length(outliers)) {
      converged <- TRUE
      break
    }
    if (pass < analysis$settings$max_passes) lots <- Filter(function(lot) !lot$number %in% outliers, lots)
  }
  retained <- vapply(lots, function(lot) lot$number, integer(1L))
  points <- lapply(analysis$lots, lot_point, center = center)
  numbers <- seq_along(analysis$lots)
  signals <- check_rules(chart, numbers, vapply(points, function(point) point$z, numeric(1L)), new_limits(-3, 0, 3), analysis$settings$rules$STD)
  list(chart = chart, passes = passes, converged = converged, retained = length(retained), removed = setdiff(numbers, retained), points = points, signals = signals)
}

run_analysis <- function(settings, values, lots) {
  analysis <- list(settings = settings, values = values, lots = lots, size = settings$subgroup_size, phase1 = settings$phase1_subgroups,
                   constants = control_constants(settings$subgroup_size), pair_constants = control_constants(2L),
                   subgroups = subgroup_statistics(values, settings$subgroup_size), estimates = list(), pattern_checks = list(), signals = list())
  for (family in FAMILIES) analysis$estimates[[family]] <- estimate_family(analysis, family)
  for (family in FAMILIES) {
    estimate <- analysis$estimates[[family]]
    series <- family_series(analysis, family, estimate$retained)
    for (index in seq_len(2L)) {
      chart <- FAMILY_CHARTS[[family]][index]
      signals <- check_rules(chart, series[[index]]$numbers, series[[index]]$values, estimate$limits[[index]], settings$rules[[chart]])
      analysis$pattern_checks[[length(analysis$pattern_checks) + 1L]] <- list(chart = chart, points = length(series[[index]]$values), signals = signals)
    }
  }
  analysis$mu0 <- chart_limits(analysis, "XBAR_R")$cl
  analysis$sigma <- chart_limits(analysis, "R")$cl / analysis$constants$d2 / sqrt(analysis$size)
  analysis$reference <- settings$cusum_k * analysis$sigma
  analysis$interval <- settings$cusum_h * analysis$sigma
  analysis$sbar <- chart_limits(analysis, "S")$cl
  phase2 <- seq.int(analysis$phase1 + 1L, length(analysis$subgroups))
  samples <- seq.int(analysis$phase1 * analysis$size + 1L, length(values))
  for (chart in SHEWHART_CHARTS) {
    if (chart %in% c("I", "MR")) {
      numbers <- samples
      observed <- if (chart == "I") values[samples] else abs(values[samples] - values[samples - 1L])
    } else {
      numbers <- phase2
      field <- if (chart %in% c("XBAR_R", "XBAR_S")) "mean" else if (chart == "R") "range" else "sd"
      observed <- vapply(analysis$subgroups[phase2], function(group) group[[field]], numeric(1L))
    }
    analysis$signals <- c(analysis$signals, check_rules(chart, numbers, observed, chart_limits(analysis, chart), settings$rules[[chart]]))
  }
  upper <- lower <- 0
  upper_run <- lower_run <- 0L
  analysis$cusum <- analysis$ewma <- analysis$moving_average <- list()
  smoothed <- analysis$mu0
  factor <- 1
  lambda <- settings$ewma_lambda
  decay <- (1 - lambda) * (1 - lambda)
  ratio <- lambda / (2 - lambda)
  analysis$ewma_width <- settings$ewma_l * analysis$sigma * sqrt(ratio)
  analysis$ma_width <- 3 * analysis$sigma / sqrt(settings$ma_span)
  for (number in phase2) {
    group <- analysis$subgroups[[number]]
    upper <- max(0, upper + (group$mean - analysis$mu0 - analysis$reference))
    lower <- max(0, lower + (analysis$mu0 - group$mean - analysis$reference))
    upper_run <- if (upper > 0) upper_run + 1L else 0L
    lower_run <- if (lower > 0) lower_run + 1L else 0L
    analysis$cusum[[length(analysis$cusum) + 1L]] <- list(subgroup = number, upper = upper, lower = lower)
    if (upper > analysis$interval) {
      analysis$signals <- c(analysis$signals, list(new_signal("CUSUM", "UPPER", number - upper_run + 1L, number, upper, "UP")))
      upper <- 0
      upper_run <- 0L
    }
    if (lower > analysis$interval) {
      analysis$signals <- c(analysis$signals, list(new_signal("CUSUM", "LOWER", number - lower_run + 1L, number, lower, "DOWN")))
      lower <- 0
      lower_run <- 0L
    }
    smoothed <- lambda * group$mean + (1 - lambda) * smoothed
    factor <- factor * decay
    width <- settings$ewma_l * analysis$sigma * sqrt(ratio * (1 - factor))
    ewma <- list(subgroup = number, value = smoothed, width = width, lcl = analysis$mu0 - width, ucl = analysis$mu0 + width)
    analysis$ewma[[length(analysis$ewma) + 1L]] <- ewma
    first <- max(analysis$phase1 + 1L, number - settings$ma_span + 1L)
    count <- number - first + 1L
    total <- sum(vapply(analysis$subgroups[seq.int(first, number)], function(group) group$total, numeric(1L)))
    width <- 3 * analysis$sigma / sqrt(count)
    ma <- list(subgroup = number, value = total / (analysis$size * count), width = width, lcl = analysis$mu0 - width, ucl = analysis$mu0 + width)
    analysis$moving_average[[length(analysis$moving_average) + 1L]] <- ma
    for (chart in c("EWMA", "MA")) {
      point <- if (chart == "EWMA") ewma else ma
      start <- if (chart == "EWMA") number else first
      if (point$value > point$ucl) analysis$signals <- c(analysis$signals, list(new_signal(chart, "UPPER", start, number, point$value, "UP")))
      else if (point$value < point$lcl) analysis$signals <- c(analysis$signals, list(new_signal(chart, "LOWER", start, number, point$value, "DOWN")))
    }
  }
  signals <- analysis$signals
  analysis$signals <- signals[order(vapply(signals, function(signal) match(signal$chart, CHART_ORDER), integer(1L)),
                                     vapply(signals, function(signal) signal$end, integer(1L)),
                                     vapply(signals, function(signal) match(signal$rule, RULE_ORDER), integer(1L)))]
  analysis$events <- build_events(analysis)
  free <- phase2[vapply(phase2, function(number) is.null(event_of(analysis, number)), logical(1L))]
  analysis$proposals <- lapply(FAMILIES, function(family) {
    added <- if (family == "I_MR") unlist(lapply(free, function(group) (group - 1L) * analysis$size + seq_len(analysis$size)), use.names = FALSE) else free
    numbers <- c(analysis$estimates[[family]]$retained, added)
    list(family = family, points = length(numbers), limits = family_limits(analysis, family, numbers))
  })
  analysis$attribute_charts <- lapply(ATTRIBUTE_CHARTS, function(chart) estimate_attribute(analysis, chart))
  analysis$capability_groups <- list()
  for (name in c("phase1", "phase2")) {
    numbers <- if (name == "phase1") analysis$estimates$XBAR_R$retained else phase2
    groups <- analysis$subgroups[numbers]
    analysis$capability_groups[[length(analysis$capability_groups) + 1L]] <- list(name = name, subgroups = groups, result = capability(groups, settings, analysis$constants))
  }
  analysis$rolling <- list()
  first <- analysis$phase1 + 1L
  while (first + settings$rolling_window - 1L <= length(analysis$subgroups)) {
    last <- first + settings$rolling_window - 1L
    result <- capability(analysis$subgroups[seq.int(first, last)], settings, analysis$constants)
    analysis$rolling[[length(analysis$rolling) + 1L]] <- list(first = first, last = last, result = result)
    first <- first + settings$rolling_step
  }
  analysis
}

limits_lines <- function(analysis) {
  lines <- c(text_line("characteristic", analysis$settings$characteristic), text_line("subgroup_size", analysis$size),
              text_line("subgroups", length(analysis$subgroups)), text_line("samples", length(analysis$values)), text_line("phase1_subgroups", analysis$phase1))
  for (family in FAMILIES) {
    estimate <- analysis$estimates[[family]]
    lines <- c(lines, text_line("family", family))
    for (number in seq_along(estimate$passes)) {
      pass <- estimate$passes[[number]]
      lines <- c(lines, text_line("pass", number, "points", pass$points, pair_text(family, pass$limits), "out", number_list(pass$outliers)))
    }
    lines <- c(lines, text_line("result", status_text(estimate$converged), "passes", length(estimate$passes), "retained", length(estimate$retained), "removed", number_list(estimate$removed)))
  }
  for (check in analysis$pattern_checks) {
    for (signal in check$signals) lines <- c(lines, text_line("phase1_signal", check$chart, signal$rule, signal$start, signal$end, real_text(signal$value)))
    lines <- c(lines, text_line("phase1_check", check$chart, "points", check$points, "signals", length(check$signals)))
  }
  for (proposal in analysis$proposals) lines <- c(lines, text_line("proposed", proposal$family, "points", proposal$points, pair_text(proposal$family, proposal$limits)))
  target <- paste("target", real_text(analysis$mu0), "sigma", real_text(analysis$sigma))
  lines <- c(lines, paste("cusum", target, "k", real_text(analysis$reference), "h", real_text(analysis$interval)),
              paste("ewma", target, "lcl", real_text(analysis$mu0 - analysis$ewma_width), "ucl", real_text(analysis$mu0 + analysis$ewma_width)),
              text_line("ma", target, "span", analysis$settings$ma_span, "lcl", real_text(analysis$mu0 - analysis$ma_width), "ucl", real_text(analysis$mu0 + analysis$ma_width)))
  for (chart in CHART_ORDER) {
    signals <- Filter(function(signal) signal$chart == chart, analysis$signals)
    ends <- unique(vapply(signals, function(signal) signal$end, integer(1L)))
    points <- if (chart %in% c("I", "MR")) length(analysis$values) - analysis$phase1 * analysis$size else length(analysis$subgroups) - analysis$phase1
    rules <- if (chart %in% SHEWHART_CHARTS) as.character(analysis$settings$rules[[chart]]) else c("UPPER", "LOWER")
    counts <- vapply(rules, function(rule) paste0(rule, ":", sum(vapply(signals, function(signal) signal$rule == rule, logical(1L)))), character(1L))
    first <- if (length(ends)) integer_text(min(ends)) else "none"
    lines <- c(lines, text_line("phase2", chart, "points", points, "signals", length(signals), "signalled", length(ends), "first", first, "by_rule", paste(counts, collapse = " ")))
  }
  lines
}

signal_lines <- function(analysis) {
  c("chart,rule,start,end,value,direction", vapply(analysis$signals, function(signal) {
    paste(signal$chart, signal$rule, signal$start, signal$end, real_text(signal$value), signal$direction, sep = ",")
  }, character(1L)))
}

event_lines <- function(analysis) {
  lines <- text_line("events", length(analysis$events))
  for (event in analysis$events) {
    counts <- event$counts
    charts <- paste(CHART_ORDER[event$detection > 0L], collapse = ",")
    lines <- c(lines, text_line("event", event$number, "start", event$start, "end", event$end, "length", event$end - event$start + 1L,
                                "signals", length(event$signals), "charts", charts, "location_up", counts[1L], "location_down", counts[2L],
                                "spread_up", counts[3L], "spread_down", counts[4L], "pattern", counts[5L], "onset", event$onset,
                                "shift", real_text(event$shift), "spread", real_text(event$spread), "out_of_spec", event$out_of_spec, "type", event$kind))
    detection <- vapply(seq_along(CHART_ORDER), function(i) paste0(CHART_ORDER[i], ":", if (event$detection[i]) integer_text(event$detection[i]) else "-"), character(1L))
    lines <- c(lines, text_line("detection", event$number, paste(detection, collapse = " ")))
  }
  lines
}

zone_name <- function(zone, value) {
  if (value > zone$ucl) return("OUT+")
  if (value < zone$lcl) return("OUT-")
  if (value > zone$u2) return("A+")
  if (value > zone$u1) return("B+")
  if (value > zone$cl) return("C+")
  if (value < zone$l2) return("A-")
  if (value < zone$l1) return("B-")
  if (value < zone$cl) return("C-")
  "C0"
}

subgroup_lines <- function(analysis) {
  lines <- "subgroup,phase,mean,zone,range,sd,cusum_upper,cusum_lower,ewma,ma,signals,event"
  zone <- zones(chart_limits(analysis, "XBAR_R"))
  groups <- vapply(analysis$signals, function(signal) signal_subgroup(analysis, signal), integer(1L))
  for (group in analysis$subgroups) {
    number <- group$number
    if (number > analysis$phase1) {
      index <- number - analysis$phase1
      phase <- "phase2"
      monitored <- real_text(c(analysis$cusum[[index]]$upper, analysis$cusum[[index]]$lower, analysis$ewma[[index]]$value, analysis$moving_average[[index]]$value))
    } else {
      phase <- if (number %in% analysis$estimates$XBAR_R$removed) "excluded" else "phase1"
      monitored <- rep("-", 4L)
    }
    event <- event_of(analysis, number)
    fields <- c(integer_text(number), phase, real_text(group$mean), zone_name(zone, group$mean), integer_text(group$range), real_text(group$sd), monitored,
                integer_text(sum(groups == number)), if (is.null(event)) "-" else integer_text(event$number))
    lines <- c(lines, paste(fields, collapse = ","))
  }
  lines
}

attribute_lines <- function(analysis) {
  lines <- character()
  for (result in analysis$attribute_charts) {
    lines <- c(lines, text_line("chart", result$chart))
    for (number in seq_along(result$passes)) {
      pass <- result$passes[[number]]
      lines <- c(lines, text_line("pass", number, "lots", pass$lots, "center", real_text(pass$center), "out", number_list(pass$outliers)))
    }
    lines <- c(lines, text_line("result", status_text(result$converged), "passes", length(result$passes), "retained", result$retained, "removed", number_list(result$removed)))
    for (index in seq_along(analysis$lots)) {
      lot <- analysis$lots[[index]]
      point <- result$points[[index]]
      value <- if (result$chart %in% c("np", "c")) integer_text(point$value) else real_text(point$value)
      lines <- c(lines, text_line("lot", lot$number, "size", lot$inspected, "value", value, "lcl", real_text(point$lcl), "ucl", real_text(point$ucl), "z", real_text(point$z), "status", point$status))
    }
    for (signal in result$signals) lines <- c(lines, text_line("signal", signal$rule, signal$start, signal$end, real_text(signal$value)))
    lines <- c(lines, text_line("signals", length(result$signals)))
  }
  lines
}

capability_lines <- function(analysis) {
  lines <- character()
  fields <- c("mean", "sigma_within", "sigma_sbar", "sigma_overall", "cp", "cpu", "cpl", "cpk", "pp", "ppu", "ppl", "ppk", "cpm")
  for (group in analysis$capability_groups) {
    result <- group$result
    lines <- c(lines, text_line("group", group$name, "subgroups", length(group$subgroups), "values", result$count))
    for (field in fields) lines <- c(lines, paste(field, real_text(result[[field]])))
    for (field in c("cpk_ci", "ppk_ci")) lines <- c(lines, paste(field, paste(real_text(result[[field]]), collapse = " ")))
    lines <- c(lines, text_line("below_lsl", result$below), text_line("above_usl", result$above), paste("ppm", real_text(result$ppm)))
    for (subgroup in group$subgroups) for (position in seq_along(subgroup$values)) {
      value <- subgroup$values[position]
      side <- if (value < analysis$settings$lsl) "low" else if (value > analysis$settings$usl) "high" else NULL
      if (!is.null(side)) lines <- c(lines, text_line("out_of_spec sample", (subgroup$number - 1L) * analysis$size + position, "subgroup", subgroup$number, "value", value, "side", side))
    }
    lines <- c(lines, paste("verdict", result$verdict))
    for (bin in result$bins) {
      parts <- c("bin", integer_text(bin$lower), integer_text(bin$upper), integer_text(bin$frequency))
      if (bin$length > 0L) parts <- c(parts, strrep("#", bin$length))
      lines <- c(lines, paste(c(parts, bin$marks), collapse = " "))
    }
  }
  for (window in analysis$rolling) {
    result <- window$result
    lines <- c(lines, text_line("rolling", window$first, window$last, "mean", real_text(result$mean), "sigma_within", real_text(result$sigma_within),
                                "sigma_overall", real_text(result$sigma_overall), "cpk", real_text(result$cpk), "ppk", real_text(result$ppk), "verdict", result$verdict))
  }
  lines
}

chart_lines <- function(analysis) {
  lines <- character()
  for (chart in c("XBAR", "R", "S")) {
    signal_chart <- if (chart == "XBAR") "XBAR_R" else chart
    family <- if (chart == "S") "XBAR_S" else "XBAR_R"
    limits <- chart_limits(analysis, signal_chart)
    field <- if (chart == "XBAR") "mean" else if (chart == "R") "range" else "sd"
    lines <- c(lines, limits_text(paste("chart", chart), limits))
    for (group in analysis$subgroups) {
      number <- group$number
      mark <- if (number > analysis$phase1) "2" else if (number %in% analysis$estimates[[family]]$removed) "x" else "1"
      signalled <- number > analysis$phase1 && has_signal(analysis, signal_chart, number)
      lines <- c(lines, paste(sprintf("%3d", number), mark, limits_band(limits, group[[field]], signalled), real_text(group[[field]])))
    }
  }
  lines <- c(lines, paste("chart CUSUM h", real_text(analysis$interval)))
  for (point in analysis$cusum) {
    band <- cusum_band(point$upper, point$lower, analysis$interval, has_signal(analysis, "CUSUM", point$subgroup, "UPPER"), has_signal(analysis, "CUSUM", point$subgroup, "LOWER"))
    lines <- c(lines, paste(sprintf("%3d", point$subgroup), band, real_text(point$upper), real_text(point$lower)))
  }
  for (chart in c("EWMA", "MA")) {
    scale <- if (chart == "EWMA") analysis$ewma_width else analysis$ma_width
    points <- if (chart == "EWMA") analysis$ewma else analysis$moving_average
    lines <- c(lines, limits_text(paste("chart", chart), new_limits(analysis$mu0 - scale, analysis$mu0, analysis$mu0 + scale)))
    for (point in points) {
      band <- width_band(scale, point$width, point$value, analysis$mu0, has_signal(analysis, chart, point$subgroup))
      lines <- c(lines, paste(sprintf("%3d", point$subgroup), band, real_text(point$value), real_text(point$lcl), real_text(point$ucl)))
    }
  }
  pictures <- c("P_STD", "NP_STD", "C_STD", "U_STD")
  for (index in seq_along(pictures)) {
    lines <- c(lines, limits_text(paste("chart", pictures[index]), new_limits(-3, 0, 3)))
    result <- analysis$attribute_charts[[index]]
    for (lot in seq_along(analysis$lots)) {
      point <- result$points[[lot]]
      lines <- c(lines, paste(sprintf("%3d", analysis$lots[[lot]]$number), standard_band(point$z, point$status == "ok"), real_text(point$z)))
    }
  }
  lines
}

main <- function() {
  settings <- read_settings("input/spec.txt")
  analysis <- run_analysis(settings, read_measurements("input/measurements.csv"), read_attributes("input/attributes.csv"))
  dir.create("output", showWarnings = FALSE)
  outputs <- list("limits.txt" = limits_lines(analysis), "signals.csv" = signal_lines(analysis), "events.txt" = event_lines(analysis),
                   "subgroups.csv" = subgroup_lines(analysis), "attribute_charts.txt" = attribute_lines(analysis),
                   "capability.txt" = capability_lines(analysis), "charts.txt" = chart_lines(analysis))
  for (name in names(outputs)) writeLines(outputs[[name]], file.path("output", name), useBytes = TRUE)
}

main()
