source("pgm_reader.R")
source("threshold.R")
source("morphology.R")
source("labeling.R")
source("report.R")

symbols <- strsplit("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz", "", fixed = TRUE)[[1L]]
orientations <- c("none", "horizontal", "vertical", "falling", "rising")
four <- matrix(c(1, 0, 0, -1, -1, 0, 0, 1), ncol = 2L, byrow = TRUE)
eight <- matrix(c(1, 0, 1, -1, 0, -1, -1, -1, -1, 0, -1, 1, 0, 1, 1, 1), ncol = 2L, byrow = TRUE)
csv_header <- "image,label,class,flags,area,x0,y0,x1,y1,cx,cy,mean,variance,min,max,contrast,border,perimeter,chain,straight,diagonal,turns,compactness,runs,holes,hole_area,euler,parent,depth,var_x,var_y,cov_xy,hu1,orientation,anisotropy,extent,mirror_lr,mirror_tb,hull_area,solidity,feret2,width2,elongation,bays,bay_area,skeleton,endpoints,branches,neighbor,distance2,codes"

method_name <- function(setting) {
  if (setting$threshold %in% c("otsu", "isodata")) setting$threshold else "fixed"
}

parse_rational <- function(text) {
  parts <- strsplit(text, "/", fixed = TRUE)[[1L]]
  rational(as.numeric(parts[1L]), if (length(parts) == 1L) 1 else as.numeric(parts[2L]))
}

read_parameters <- function(path) {
  parameters <- list(otsu_top = 0L, sweep_step = 0L, isotropy = rational(0), bay_min = 0L, elements = list(), settings = list())
  for (line in readLines(path, warn = FALSE)) {
    words <- strsplit(line, " ", fixed = TRUE)[[1L]]
    keyword <- words[1L]
    if (keyword == "otsu_top") {
      parameters$otsu_top <- as.integer(words[2L])
    } else if (keyword == "sweep") {
      parameters$sweep_step <- as.integer(words[2L])
    } else if (keyword == "isotropy") {
      parameters$isotropy <- parse_rational(words[2L])
    } else if (keyword == "bay_min") {
      parameters$bay_min <- as.integer(words[2L])
    } else if (keyword == "element") {
      ox <- as.integer(words[5L])
      oy <- as.integer(words[6L])
      offsets <- matrix(numeric(), 0L, 2L)
      rows <- words[-seq_len(6L)]
      for (y in seq_along(rows) - 1L) {
        characters <- strsplit(rows[y + 1L], "", fixed = TRUE)[[1L]]
        for (x in which(characters == "#") - 1L) offsets <- rbind(offsets, c(x - ox, y - oy))
      }
      parameters$elements[[words[2L]]] <- offsets
    } else if (keyword == "image") {
      parameters$settings[[words[2L]]] <- list(connectivity = as.integer(words[3L]), threshold = words[4L], polarity = words[5L], operations = words[-seq_len(5L)])
    }
  }
  parameters
}

new_condition <- function(words) {
  list(feature = words[1L], comparison = words[2L], text = words[3L], value = if (words[1L] == "orientation") rational(0) else parse_rational(words[3L]))
}

condition_holds <- function(condition, region) {
  if (condition$feature == "orientation") {
    equal <- region$orientation == condition$text
    return(if (condition$comparison == "=") equal else !equal)
  }
  order <- compare_ratio(region$features[[condition$feature]], condition$value)
  switch(condition$comparison, "<" = order < 0, "<=" = order <= 0, ">" = order > 0, ">=" = order >= 0, "=" = order == 0, "!=" = order != 0)
}

rule_matches <- function(rule, region) {
  all(vapply(rule$conditions, function(condition) condition_holds(condition, region), logical(1)))
}

parse_conditions <- function(words, start) {
  if (start > length(words)) return(list())
  lapply(seq.int(start, length(words), by = 3L), function(i) new_condition(words[i + 0:2]))
}

read_rules <- function(path) {
  rules <- list(filters = list(), classes = list(), flags = list())
  for (line in readLines(path, warn = FALSE)) {
    words <- strsplit(line, " ", fixed = TRUE)[[1L]]
    if (words[1L] == "filter") {
      rules$filters[[length(rules$filters) + 1L]] <- new_condition(words[-1L])
    } else {
      rule <- list(name = words[2L], conditions = parse_conditions(words, 3L))
      key <- if (words[1L] == "class") "classes" else "flags"
      rules[[key]][[length(rules[[key]]) + 1L]] <- rule
    }
  }
  rules$class_names <- c(unique(vapply(rules$classes, function(rule) rule$name, character(1))), "other")
  rules
}

new_region <- function(number, pixels) {
  region <- new.env(parent = emptyenv())
  region$number <- number
  region$pixels <- pixels
  region$features <- list()
  region$orientation <- "none"
  region$codes <- integer()
  region$skeleton <- NULL
  region$hull_doubled <- 0
  region$parent <- 0L
  region$depth <- 0L
  region$children <- integer()
  region$kept <- FALSE
  region$dropped_by <- 0L
  region$class_name <- "other"
  region$flags <- character()
  region$neighbor <- 0L
  region$distance <- 0
  region
}

put <- function(region, key, numerator, denominator = 1) {
  region$features[[key]] <- rational(numerator, denominator)
}

region_int <- function(region, key) region$features[[key]][1L]
directions <- function(connectivity) if (connectivity == 4L) four else eight
count_foreground <- function(mask) sum(mask)

empty_points <- function() matrix(numeric(), 0L, 2L)

group_pixels <- function(labels, count) {
  groups <- lapply(seq_len(count + 1L), function(i) empty_points())
  for (y in seq_len(nrow(labels)) - 1L) {
    for (x in seq_len(ncol(labels)) - 1L) {
      number <- labels[y + 1L, x + 1L] + 1L
      groups[[number]] <- rbind(groups[[number]], c(x, y))
    }
  }
  groups
}

enclosed_components <- function(mask, connectivity) {
  result <- label_components(!mask, connectivity)
  groups <- group_pixels(result$labels, result$count)[-1L]
  Filter(function(pixels) !any(pixels[, 1L] == 0 | pixels[, 2L] == 0 | pixels[, 1L] == ncol(mask) - 1L | pixels[, 2L] == nrow(mask) - 1L), groups)
}

fill_holes <- function(mask, connectivity) {
  for (pixels in enclosed_components(mask, connectivity)) {
    for (i in seq_len(nrow(pixels))) mask[pixels[i, 2L] + 1L, pixels[i, 1L] + 1L] <- TRUE
  }
  mask
}

cross <- function(a, b, point) (b[1L] - a[1L]) * (point[2L] - a[2L]) - (b[2L] - a[2L]) * (point[1L] - a[1L])
squared_distance <- function(a, b) sum((a - b)^2)

half_hull <- function(points) {
  chain <- empty_points()
  for (i in seq_len(nrow(points))) {
    point <- points[i, ]
    while (nrow(chain) >= 2L && cross(chain[nrow(chain) - 1L, ], chain[nrow(chain), ], point) <= 0) {
      chain <- chain[-nrow(chain), , drop = FALSE]
    }
    chain <- rbind(chain, point)
  }
  chain
}

convex_hull <- function(pixels) {
  corners <- empty_points()
  for (i in seq_len(nrow(pixels))) {
    point <- pixels[i, ]
    corners <- rbind(corners, point, point + c(1, 0), point + c(0, 1), point + c(1, 1))
  }
  ordered <- unique(corners)
  ordered <- ordered[order(ordered[, 1L], ordered[, 2L], method = "radix"), , drop = FALSE]
  lower <- half_hull(ordered)
  upper <- half_hull(ordered[rev(seq_len(nrow(ordered))), , drop = FALSE])
  rbind(lower[-nrow(lower), , drop = FALSE], upper[-nrow(upper), , drop = FALSE])
}

contains_center <- function(hull, x, y) {
  center <- c(2 * x + 1, 2 * y + 1)
  for (i in seq_len(nrow(hull))) {
    if (cross(2 * hull[i, ], 2 * hull[i %% nrow(hull) + 1L, ], center) < 0) return(FALSE)
  }
  TRUE
}

box_bounds <- function(pixels) c(min(pixels[, 1L]), min(pixels[, 2L]), max(pixels[, 1L]), max(pixels[, 2L]))

box_distance <- function(first, second) {
  dx <- region_int(first, "x0") + region_int(first, "x1") - region_int(second, "x0") - region_int(second, "x1")
  dy <- region_int(first, "y0") + region_int(first, "y1") - region_int(second, "y0") - region_int(second, "y1")
  dx * dx + dy * dy
}

mean_text <- function(total, count) if (count == 0) "-" else decimal_text(rational(total, count), 2L)

orientation_line <- function(regions) {
  parts <- "orientations"
  for (name in orientations) parts <- c(parts, name, sum(vapply(regions, function(region) region$orientation == name, logical(1))))
  paste(parts, collapse = " ")
}

binarize <- function(analysis, cutoff) {
  if (analysis$setting$polarity == "bright") analysis$image$pixels > cutoff else analysis$image$pixels <= cutoff
}

label_at <- function(analysis, x, y) {
  if (x >= 0 && x < analysis$image$width && y >= 0 && y < analysis$image$height) analysis$labels[y + 1L, x + 1L] else -1L
}

chain_code <- function(analysis, region) {
  steps <- directions(analysis$setting$connectivity)
  first <- region$pixels[1L, ]
  visited <- matrix(first, nrow = 1L)
  codes <- integer()
  heading <- nrow(steps) - 1L
  repeat {
    point <- visited[nrow(visited), ]
    start <- if (nrow(steps) == 4L) (heading + 3L) %% 4L else (heading + if (heading %% 2L == 0L) 7L else 6L) %% 8L
    chosen <- -1L
    for (offset in seq_len(nrow(steps)) - 1L) {
      direction <- (start + offset) %% nrow(steps)
      step <- steps[direction + 1L, ]
      if (label_at(analysis, point[1L] + step[1L], point[2L] + step[2L]) == region$number) {
        chosen <- direction
        break
      }
    }
    if (chosen < 0L) return(integer())
    visited <- rbind(visited, point + steps[chosen + 1L, ])
    codes <- c(codes, chosen)
    heading <- chosen
    moves <- length(codes)
    if (moves >= 2L && all(visited[moves + 1L, ] == visited[2L, ]) && all(visited[moves, ] == first)) return(codes[-moves])
  }
}

measure <- function(analysis, region, parameters) {
  pixels <- region$pixels
  area <- as.numeric(nrow(pixels))
  box <- box_bounds(pixels)
  x0 <- box[1L]
  y0 <- box[2L]
  x1 <- box[3L]
  y1 <- box[4L]
  basics <- c(area = area, x0 = x0, y0 = y0, x1 = x1, y1 = y1, width = x1 - x0 + 1, height = y1 - y0 + 1)
  for (name in names(basics)) put(region, name, basics[[name]])
  put(region, "border", as.numeric(x0 == 0 || y0 == 0 || x1 == analysis$image$width - 1L || y1 == analysis$image$height - 1L))
  xs <- pixels[, 1L]
  ys <- pixels[, 2L]
  values <- analysis$image$pixels[cbind(ys + 1L, xs + 1L)]
  sum_values <- sum(values)
  sum_squares <- sum(values * values)
  put(region, "mean", sum_values, area)
  put(region, "variance", area * sum_squares - sum_values * sum_values, area * area)
  put(region, "min", min(values))
  put(region, "max", max(values))
  surrounding <- matrix(FALSE, analysis$image$height, analysis$image$width)
  perimeter <- runs <- mirrored_lr <- mirrored_tb <- 0L
  boundary_steps <- directions(12L - analysis$setting$connectivity)
  for (i in seq_len(nrow(pixels))) {
    x <- pixels[i, 1L]
    y <- pixels[i, 2L]
    for (j in seq_len(nrow(eight))) {
      nx <- x + eight[j, 1L]
      ny <- y + eight[j, 2L]
      if (label_at(analysis, nx, ny) == 0L) surrounding[ny + 1L, nx + 1L] <- TRUE
    }
    for (j in seq_len(nrow(boundary_steps))) {
      if (label_at(analysis, x + boundary_steps[j, 1L], y + boundary_steps[j, 2L]) != region$number) {
        perimeter <- perimeter + 1L
        break
      }
    }
    if (label_at(analysis, x - 1L, y) != region$number) runs <- runs + 1L
    if (label_at(analysis, x0 + x1 - x, y) == region$number) mirrored_lr <- mirrored_lr + 1L
    if (label_at(analysis, x, y0 + y1 - y) == region$number) mirrored_tb <- mirrored_tb + 1L
  }
  count <- as.numeric(sum(surrounding))
  sum_surrounding <- sum(analysis$image$pixels[surrounding])
  if (count) put(region, "contrast", sum_values * count - sum_surrounding * area, area * count) else put(region, "contrast", 0)
  put(region, "perimeter", perimeter)
  put(region, "runs", runs)
  region$codes <- chain_code(analysis, region)
  straight <- if (analysis$setting$connectivity == 4L) length(region$codes) else sum(region$codes %% 2L == 0L)
  diagonal <- length(region$codes) - straight
  previous <- if (length(region$codes)) c(tail(region$codes, 1L), head(region$codes, -1L)) else integer()
  turns <- sum(region$codes != previous)
  put(region, "chain", length(region$codes))
  put(region, "straight", straight)
  put(region, "diagonal", diagonal)
  put(region, "turns", turns)
  contour_length <- as.numeric(5 * straight + 7 * diagonal)
  put(region, "compactness", contour_length * contour_length, 25 * area)
  owned <- Filter(function(hole) hole$owner == region$number, analysis$holes)
  put(region, "holes", length(owned))
  put(region, "hole_area", sum(vapply(owned, function(hole) nrow(hole$pixels), integer(1))))
  put(region, "euler", 1L - length(owned))
  put(region, "depth", region$depth)
  sx <- sum(xs)
  sy <- sum(ys)
  m20 <- area * sum(xs * xs) - sx * sx
  m02 <- area * sum(ys * ys) - sy * sy
  m11 <- area * sum(xs * ys) - sx * sy
  put(region, "cx", sx, area)
  put(region, "cy", sy, area)
  put(region, "var_x", m20, area * area)
  put(region, "var_y", m02, area * area)
  put(region, "cov_xy", m11, area * area)
  put(region, "hu1", m20 + m02, area * area * area)
  anisotropy <- if (m20 + m02 > 0) rational(abs(m20 - m02) + 2 * abs(m11), m20 + m02) else rational(0)
  region$features$anisotropy <- anisotropy
  u <- m20 - m02
  v <- 2 * m11
  region$orientation <- if (compare_ratio(anisotropy, parameters$isotropy) <= 0) "none" else if (abs(v) >= abs(u)) { if (v > 0) "falling" else "rising" } else { if (u > 0) "horizontal" else "vertical" }
  put(region, "extent", area, (x1 - x0 + 1) * (y1 - y0 + 1))
  put(region, "mirror_lr", mirrored_lr, area)
  put(region, "mirror_tb", mirrored_tb, area)
  hull <- convex_hull(pixels)
  doubled <- feret <- 0
  width <- rational(0)
  for (i in seq_len(nrow(hull))) {
    a <- hull[i, ]
    b <- hull[i %% nrow(hull) + 1L, ]
    doubled <- doubled + a[1L] * b[2L] - b[1L] * a[2L]
    reach <- 0
    for (j in seq_len(nrow(hull))) {
      point <- hull[j, ]
      reach <- max(reach, abs(cross(a, b, point)))
      feret <- max(feret, squared_distance(a, point))
    }
    candidate <- rational(reach * reach, squared_distance(a, b))
    if (i == 1L || compare_ratio(candidate, width) < 0) width <- candidate
  }
  region$hull_doubled <- abs(doubled)
  put(region, "solidity", 2 * area, region$hull_doubled)
  put(region, "feret2", feret)
  region$features$width2 <- width
  put(region, "elongation", feret * width[2L], width[1L])
  bay_mask <- matrix(FALSE, y1 - y0 + 1L, x1 - x0 + 1L)
  for (y in seq.int(y0, y1)) {
    for (x in seq.int(x0, x1)) {
      bay_mask[y - y0 + 1L, x - x0 + 1L] <- analysis$labels[y + 1L, x + 1L] == 0L && analysis$hole_of[y + 1L, x + 1L] == 0L && contains_center(hull, x, y)
    }
  }
  bays <- label_components(bay_mask, 12L - analysis$setting$connectivity)
  sizes <- vapply(group_pixels(bays$labels, bays$count)[-1L], nrow, integer(1))
  put(region, "bays", sum(sizes >= parameters$bay_min))
  put(region, "bay_area", sum(sizes))
  region$skeleton <- thin(analysis$labels == region$number)
  crossings <- numeric()
  for (y in seq_len(analysis$image$height) - 1L) {
    for (x in seq_len(analysis$image$width) - 1L) {
      if (region$skeleton[y + 1L, x + 1L]) crossings <- c(crossings, crossing_number(region$skeleton, x, y))
    }
  }
  put(region, "skeleton", sum(region$skeleton))
  put(region, "endpoints", sum(crossings == 1))
  put(region, "branches", sum(crossings >= 3))
}

analyze_image <- function(image, setting, parameters) {
  analysis <- new.env(parent = emptyenv())
  analysis$image <- image
  analysis$setting <- setting
  analysis$histogram <- new_histogram(image)
  analysis$otsu <- otsu(analysis$histogram)
  iso <- isodata(analysis$histogram)
  analysis$isodata_cutoff <- iso[1L]
  analysis$isodata_iterations <- iso[2L]
  analysis$cutoff <- if (setting$threshold == "otsu") analysis$otsu$cutoff else if (setting$threshold == "isodata") iso[1L] else as.integer(setting$threshold)
  analysis$initial <- binarize(analysis, analysis$cutoff)
  analysis$final <- analysis$initial
  analysis$morph_counts <- numeric()
  for (operation in setting$operations) {
    if (operation == "fill") {
      analysis$final <- fill_holes(analysis$final, 12L - setting$connectivity)
    } else {
      parts <- strsplit(operation, ":", fixed = TRUE)[[1L]]
      offsets <- parameters$elements[[parts[2L]]]
      analysis$final <- switch(parts[1L], erode = erode(analysis$final, offsets), dilate = dilate(analysis$final, offsets), open = opening(analysis$final, offsets), close = closing(analysis$final, offsets))
    }
    analysis$morph_counts <- c(analysis$morph_counts, count_foreground(analysis$final))
  }
  analysis$sweep <- list()
  cutoff <- parameters$sweep_step
  while (cutoff < image$maxval) {
    mask <- binarize(analysis, cutoff)
    analysis$sweep[[length(analysis$sweep) + 1L]] <- c(cutoff, count_foreground(mask), label_components(mask, setting$connectivity)$count)
    cutoff <- cutoff + parameters$sweep_step
  }
  result <- label_components(analysis$final, setting$connectivity)
  analysis$labels <- result$labels
  analysis$provisional <- result$provisional
  groups <- group_pixels(result$labels, result$count)
  analysis$regions <- lapply(seq_len(result$count), function(number) new_region(number, groups[[number + 1L]]))
  analysis$four_components <- label_components(analysis$final, 4L)$count
  analysis$eight_components <- label_components(analysis$final, 8L)$count
  analysis$bit_quad <- bit_quad_euler(analysis$final, setting$connectivity)
  analysis$holes <- list()
  analysis$hole_of <- matrix(0L, image$height, image$width)
  for (pixels in enclosed_components(analysis$final, 12L - setting$connectivity)) {
    first <- pixels[1L, ]
    number <- length(analysis$holes) + 1L
    owner <- analysis$labels[first[2L], first[1L] + 1L]
    analysis$hole_of[cbind(pixels[, 2L] + 1L, pixels[, 1L] + 1L)] <- number
    analysis$holes[[number]] <- list(number = number, pixels = pixels, owner = owner)
  }
  for (region in analysis$regions) {
    first <- region$pixels[1L, ]
    if (first[2L] >= 1L && analysis$hole_of[first[2L], first[1L] + 1L] > 0L) {
      owner <- analysis$holes[[analysis$hole_of[first[2L], first[1L] + 1L]]]$owner
      region$parent <- owner
      region$depth <- analysis$regions[[owner]]$depth + 1L
      analysis$regions[[owner]]$children <- c(analysis$regions[[owner]]$children, region$number)
    }
    measure(analysis, region, parameters)
  }
  analysis
}

kept_regions <- function(analysis) Filter(function(region) region$kept, analysis$regions)

apply_rules <- function(analysis, rules) {
  for (region in analysis$regions) {
    for (i in seq_along(rules$filters)) {
      if (!condition_holds(rules$filters[[i]], region)) {
        region$dropped_by <- i
        break
      }
    }
    if (region$dropped_by) next
    region$kept <- TRUE
    for (rule in rules$classes) {
      if (rule_matches(rule, region)) {
        region$class_name <- rule$name
        break
      }
    }
    region$flags <- vapply(Filter(function(rule) rule_matches(rule, region), rules$flags), function(rule) rule$name, character(1))
  }
  kept <- kept_regions(analysis)
  for (region in kept) {
    for (other in kept) {
      if (other$number == region$number) next
      distance <- box_distance(region, other)
      if (!region$neighbor || distance < region$distance) {
        region$neighbor <- other$number
        region$distance <- distance
      }
    }
  }
}

tree_text <- function(analysis, number) {
  region <- analysis$regions[[number]]
  if (!length(region$children)) return(as.character(number))
  paste0(number, "(", paste(vapply(region$children, function(child) tree_text(analysis, child), character(1)), collapse = " "), ")")
}

threshold_lines <- function(analysis, top) {
  image <- analysis$image
  h <- analysis$histogram
  lines <- c(paste("image", image$name, "size", image$width, image$height, "maxval", image$maxval),
    paste("histogram pixels", h$pixels, "min", h$minimum, "max", h$maximum, "mean", mean_text(h$total, h$pixels), "median", h$median, "mode", h$mode, "levels", h$levels),
    paste(c("bins", h$bin_width, h$bins), collapse = " "),
    paste("otsu threshold", analysis$otsu$cutoff, "upper", analysis$otsu$upper, "candidates", length(analysis$otsu$candidates)))
  for (i in seq_len(min(top, length(analysis$otsu$candidates)))) {
    candidate <- analysis$otsu$candidates[[i]]
    gap <- rational(candidate$sum_above * candidate$below - candidate$sum_below * candidate$above, candidate$below * candidate$above)
    lines <- c(lines, paste("rank", i, "t", candidate$cutoff, "below", candidate$below, "above", candidate$above, "mean_below", mean_text(candidate$sum_below, candidate$below), "mean_above", mean_text(candidate$sum_above, candidate$above), "gap", decimal_text(gap, 2L)))
  }
  lines <- c(lines, paste("isodata threshold", analysis$isodata_cutoff, "iterations", analysis$isodata_iterations), paste("threshold", analysis$cutoff, method_name(analysis$setting), analysis$setting$polarity, "foreground", count_foreground(analysis$initial)))
  for (i in seq_along(analysis$setting$operations)) lines <- c(lines, paste("morph", analysis$setting$operations[i], "foreground", analysis$morph_counts[i]))
  for (result in analysis$sweep) lines <- c(lines, paste("sweep", result[1L], "foreground", result[2L], "regions", result[3L]))
  lines
}

region_symbol <- function(analysis, x, y, skeleton_only) {
  label <- analysis$labels[y + 1L, x + 1L]
  if (!label) return(if (analysis$hole_of[y + 1L, x + 1L]) ":" else ".")
  region <- analysis$regions[[label]]
  if (skeleton_only && !region$skeleton[y + 1L, x + 1L]) return("+")
  if (region$kept) symbols[label %% length(symbols) + 1L] else "#"
}

map_lines <- function(analysis) {
  size <- paste(analysis$image$name, analysis$image$width, analysis$image$height)
  lines <- paste("morphology", size)
  for (y in seq_len(analysis$image$height)) {
    row <- ifelse(analysis$initial[y, ], ifelse(analysis$final[y, ], "#", "-"), ifelse(analysis$final[y, ], "+", "."))
    lines <- c(lines, paste(row, collapse = ""))
  }
  for (heading in c("labels", "skeleton")) {
    lines <- c(lines, paste(heading, size))
    for (y in seq_len(analysis$image$height) - 1L) {
      row <- vapply(seq_len(analysis$image$width) - 1L, function(x) region_symbol(analysis, x, y, heading == "skeleton"), character(1))
      lines <- c(lines, paste(row, collapse = ""))
    }
  }
  lines
}

csv_row <- function(analysis, region) {
  f <- region$features
  integers <- function(names) vapply(names, function(name) integer_text(region_int(region, name)), character(1))
  decimals <- function(names, digits) vapply(names, function(name) decimal_text(f[[name]], digits), character(1))
  fields <- c(analysis$image$name, region$number, region$class_name, if (length(region$flags)) paste(region$flags, collapse = "+") else "-",
    integers(c("area", "x0", "y0", "x1", "y1")), decimals(c("cx", "cy"), 3L), decimals(c("mean", "variance"), 2L),
    integers(c("min", "max")), decimals("contrast", 2L), integers(c("border", "perimeter", "chain", "straight", "diagonal", "turns")),
    decimals("compactness", 3L), integers(c("runs", "holes", "hole_area", "euler")), if (region$parent) region$parent else "-", region$depth,
    decimals(c("var_x", "var_y", "cov_xy"), 3L), decimals("hu1", 4L), region$orientation,
    decimals(c("anisotropy", "extent", "mirror_lr", "mirror_tb"), 3L), hull_area_text(region$hull_doubled), decimals("solidity", 3L),
    integers("feret2"), decimals(c("width2", "elongation"), 3L), integers(c("bays", "bay_area", "skeleton", "endpoints", "branches")),
    if (region$neighbor) region$neighbor else "-", if (region$neighbor) decimal_text(rational(region$distance, 4), 2L) else "-",
    if (length(region$codes)) paste(region$codes, collapse = "") else "-")
  paste(fields, collapse = ",")
}

intensity_text <- function(analysis, foreground) {
  values <- analysis$image$pixels[analysis$final == foreground]
  mean_text(sum(values), length(values))
}

area_line <- function(analysis) {
  kept <- kept_regions(analysis)
  if (!length(kept)) return("area total 0 mean - largest - smallest -")
  areas <- vapply(kept, function(region) region_int(region, "area"), numeric(1))
  largest <- kept[[which.max(areas)]]
  smallest <- kept[[which.min(areas)]]
  paste("area total", sum(areas), "mean", mean_text(sum(areas), length(kept)), "largest", largest$number, region_int(largest, "area"), "smallest", smallest$number, region_int(smallest, "area"))
}

summary_lines <- function(analysis, rules) {
  kept <- kept_regions(analysis)
  region_count <- length(analysis$regions)
  hole_pixels <- sum(vapply(analysis$holes, function(hole) nrow(hole$pixels), integer(1)))
  lines <- c(paste("image", analysis$image$name), paste("threshold", analysis$cutoff, method_name(analysis$setting), analysis$setting$polarity, "conn", analysis$setting$connectivity),
    paste("foreground", count_foreground(analysis$initial), count_foreground(analysis$final)),
    paste("regions", region_count, "provisional", analysis$provisional, "kept", length(kept), "dropped", region_count - length(kept)),
    paste("connectivity four", analysis$four_components, "eight", analysis$eight_components),
    paste("holes", length(analysis$holes), "hole_pixels", hole_pixels, "euler", region_count - length(analysis$holes), "bitquad", analysis$bit_quad))
  for (hole in analysis$holes) lines <- c(lines, paste(c("hole", hole$number, "owner", hole$owner, "area", nrow(hole$pixels), "box", box_bounds(hole$pixels)), collapse = " "))
  depths <- vapply(analysis$regions, function(region) region$depth, integer(1))
  roots <- Filter(function(region) !region$parent, analysis$regions)
  trees <- vapply(roots, function(region) tree_text(analysis, region$number), character(1))
  lines <- c(lines, paste("depth_max", max(c(0L, depths))), paste(c("tree", trees), collapse = " "), paste("intensity foreground", intensity_text(analysis, TRUE), "background", intensity_text(analysis, FALSE)), area_line(analysis))
  classes <- "classes"
  for (name in rules$class_names) classes <- c(classes, name, sum(vapply(kept, function(region) region$class_name == name, logical(1))))
  flags <- "flags"
  for (rule in rules$flags) flags <- c(flags, rule$name, sum(vapply(kept, function(region) rule$name %in% region$flags, logical(1))))
  c(lines, paste(classes, collapse = " "), orientation_line(kept), paste(flags, collapse = " "))
}

overall_lines <- function(analyses, rules) {
  regions <- unlist(lapply(analyses, function(analysis) analysis$regions), recursive = FALSE, use.names = FALSE)
  kept <- Filter(function(region) region$kept, regions)
  holes <- sum(vapply(analyses, function(analysis) length(analysis$holes), integer(1)))
  lines <- c("overall", paste("images", length(analyses)), paste("regions", length(regions), "kept", length(kept), "dropped", length(regions) - length(kept)), paste("holes", holes, "euler", length(regions) - holes))
  for (i in seq_along(rules$filters)) {
    condition <- rules$filters[[i]]
    dropped <- sum(vapply(regions, function(region) region$dropped_by == i, logical(1)))
    lines <- c(lines, paste("filter", i, condition$feature, condition$comparison, condition$text, "dropped", dropped))
  }
  for (name in rules$class_names) {
    members <- Filter(function(region) region$class_name == name, kept)
    area <- sum(vapply(members, function(region) region_int(region, "area"), numeric(1)))
    lines <- c(lines, paste("class", name, "count", length(members), "area", area, "mean", mean_text(area, length(members))))
  }
  for (rule in rules$flags) lines <- c(lines, paste("flag", rule$name, "count", sum(vapply(kept, function(region) rule$name %in% region$flags, logical(1)))))
  lines <- c(lines, orientation_line(kept))
  largest <- NULL
  largest_name <- ""
  for (analysis in analyses) {
    for (region in kept_regions(analysis)) {
      if (is.null(largest) || region_int(region, "area") > region_int(largest, "area")) {
        largest <- region
        largest_name <- analysis$image$name
      }
    }
  }
  c(lines, if (is.null(largest)) "largest -" else paste("largest", largest_name, largest$number, region_int(largest, "area")))
}

main <- function() {
  parameters <- read_parameters("input/params.txt")
  rules <- read_rules("input/rules.txt")
  analyses <- list()
  for (image in read_images("input/images.txt")) {
    analysis <- analyze_image(image, parameters$settings[[image$name]], parameters)
    apply_rules(analysis, rules)
    analyses[[length(analyses) + 1L]] <- analysis
  }
  thresholds <- maps <- summary <- character()
  rows <- csv_header
  for (analysis in analyses) {
    thresholds <- c(thresholds, threshold_lines(analysis, parameters$otsu_top))
    maps <- c(maps, map_lines(analysis))
    rows <- c(rows, vapply(kept_regions(analysis), function(region) csv_row(analysis, region), character(1)))
    summary <- c(summary, summary_lines(analysis, rules))
  }
  summary <- c(summary, overall_lines(analyses, rules))
  write_files("output", list(thresholds.txt = thresholds, labels.txt = maps, regions.csv = rows, summary.txt = summary))
}

main()
