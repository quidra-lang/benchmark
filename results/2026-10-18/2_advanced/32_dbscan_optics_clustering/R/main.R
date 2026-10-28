for (file in c("dataset", "grid_index", "dbscan", "optics", "report")) source(paste0(file, ".R"))

LABEL_LETTERS <- c(LETTERS, letters)
label_char <- function(label) if (label == NOISE) "." else if (label < 52L) LABEL_LETTERS[label + 1L] else "#"
value_text <- function(value) if (value == INF) "-" else sprintf("%.0f", value)
optional_root <- function(value) if (value == INF) "-" else root_text(value)
check_text <- function(passed) if (passed) "ok" else "mismatch"
condition_text <- function(passed) if (passed) "ok" else "fail"
optional_label <- function(value) if (value < 0L) "-" else as.character(value)
line_text <- function(...) paste(c(...), collapse = " ")
pair_count <- function(n) (as.numeric(n) * (n - 1L)) %/% 2
integer_sqrt <- function(value) {
    low <- 0L
    high <- 1L
    while (high * high <= value) high <- high * 2L
    while (low + 1L < high) {
        middle <- (low + high) %/% 2L
        if (middle * middle <= value) low <- middle else high <- middle
    }
    low
}
suggested_radius <- function(value) {
    radius <- integer_sqrt(value)
    max(radius + as.integer(radius * radius < value), 1L)
}
make_curve <- function(points, values) {
    n <- length(points)
    order <- order(-values, vapply(points, function(point) point$id, 0L))
    ordered <- values[order]
    first <- ordered[1L]
    last <- tail(ordered, 1L)
    crosses <- abs((n - 1L) * (ordered - first) - (last - first) * (seq_len(n) - 1L))
    knee <- which.max(crosses)
    list(
        order = order,
        values = ordered,
        cross = crosses[knee],
        knee = knee,
        eps = suggested_radius(ordered[knee])
    )
}
grid_summary <- function(points, eps) {
    grid <- grid_index(points, eps)
    queries <- lapply(seq_along(points), function(i) neighborhood(grid, i))
    neighborhoods <- lapply(queries, function(query) query$neighbors)
    candidates <- sum(vapply(queries, function(query) query$candidates, 0L))
    brute <- brute_force_counts(points, eps)
    sizes <- lengths(grid$cells)
    occupancy <- lapply(sort(unique(sizes)), function(size) c(size, sum(sizes == size)))
    list(
        eps = eps,
        neighborhoods = neighborhoods,
        candidates = candidates,
        cells = length(grid$cells),
        busiest = busiest_cell(grid),
        pairs = (sum(lengths(neighborhoods)) - length(points)) %/% 2L,
        brute_pairs = (sum(brute) - length(points)) %/% 2L,
        consistent = all(lengths(neighborhoods) == brute),
        occupancy = occupancy
    )
}
setting <- function(name, kind, radius, labels, core) {
    groups <- max(labels) + 1L
    members <- lapply(seq_len(groups) - 1L, function(label) which(labels == label))
    noise <- sum(labels == NOISE)
    core_count <- sum(labels != NOISE & core)
    list(
        name = name,
        kind = kind,
        radius = radius,
        labels = labels,
        core = core,
        count = groups,
        members = members,
        noise = noise,
        core_count = core_count,
        border_count = length(labels) - noise - core_count
    )
}
extract_clusters <- function(ordering, reach, core, radius) {
    limit <- radius * radius
    labels <- rep(NOISE, length(ordering))
    cluster <- -1L
    for (index in ordering) {
        if (reach[index] > limit) {
            if (core[index] <= limit) {
                cluster <- cluster + 1L
                labels[index] <- cluster
            }
        } else labels[index] <- cluster
    }
    list(labels = labels, core = core <= limit)
}
xi_method <- function(reach, params) {
    n <- length(reach) - 1L
    alpha <- (params$xi_v - params$xi_u) * (params$xi_v - params$xi_u)
    beta <- params$xi_v * params$xi_v
    xle <- function(a, b) if (b == INF) TRUE else if (a == INF) FALSE else beta * a <= alpha * b
    steep_up <- vapply(
        seq_len(n),
        function(i) !(reach[i] == INF && reach[i + 1L] == INF) && xle(reach[i], reach[i + 1L]),
        FALSE
    )
    steep_down <- vapply(
        seq_len(n),
        function(i) !(reach[i] == INF && reach[i + 1L] == INF) && xle(reach[i + 1L], reach[i]),
        FALSE
    )
    up <- reach[seq_len(n)] < reach[seq_len(n) + 1L]
    down <- reach[seq_len(n)] > reach[seq_len(n) + 1L]
    region_end <- function(start, steep, reverse_direction) {
        end <- start
        flat <- 0L
        for (i in seq.int(start, n)) {
            if (steep[i]) {
                end <- i
                flat <- 0L
            } else if (reverse_direction[i]) break else {
                flat <- flat + 1L
                if (flat > params$min_pts) break
            }
        }
        end
    }
    areas <- clusters <- down_areas <- list()
    index <- 1L
    mib <- 0
    for (start in seq_len(n)) {
        if (start < index || !(steep_up[start] || steep_down[start])) next
        mib <- max(mib, max(reach[seq.int(index, start)]))
        if (mib == INF) down_areas <- list() else {
            down_areas <- Filter(function(area) xle(mib, reach[area$start]), down_areas)
            down_areas <- lapply(down_areas, function(area) {
                area$high <- max(area$high, mib)
                area
            })
        }
        if (steep_down[start]) {
            end <- region_end(start, steep_down, up)
            areas <- c(areas, list(list(kind = "down", start = start, end = end)))
            down_areas <- c(down_areas, list(list(start = start, end = end, high = 0)))
            index <- end + 1L
            mib <- reach[index]
        } else {
            end <- region_end(start, steep_up, down)
            areas <- c(areas, list(list(kind = "up", start = start, end = end)))
            index <- end + 1L
            mib <- reach[index]
            candidates <- list()
            for (area in down_areas) {
                cs <- area$start
                ce <- end
                if (!xle(area$high, reach[ce + 1L])) next
                top <- reach[area$start]
                if (xle(reach[ce + 1L], top)) {
                    while (cs < area$end && reach[cs + 1L] > reach[ce + 1L]) cs <- cs + 1L
                } else if (xle(top, reach[ce + 1L])) {
                    while (ce > start && reach[ce - 1L] > top) ce <- ce - 1L
                }
                if (ce - cs + 1L >= params$xi_min_size && cs <= area$end && ce >= start) candidates <- c(
                    candidates,
                    list(c(cs, ce))
                )
            }
            clusters <- c(clusters, rev(candidates))
        }
    }
    position_labels <- rep(NOISE, n)
    cluster_labels <- rep(-1L, length(clusters))
    next_label <- 0L
    for (j in seq_along(clusters)) {
        indices <- seq.int(clusters[[j]][1L], clusters[[j]][2L])
        if (all(position_labels[indices] == NOISE)) {
            position_labels[indices] <- next_label
            cluster_labels[j] <- next_label
            next_label <- next_label + 1L
        }
    }
    parents <- integer(length(clusters))
    for (number in seq_along(clusters)) {
        start <- clusters[[number]][1L]
        end <- clusters[[number]][2L]
        size <- end - start + 1L
        best_size <- .Machine$integer.max
        for (other in seq_along(clusters)) {
            first <- clusters[[other]][1L]
            last <- clusters[[other]][2L]
            other_size <- last - first + 1L
            if (other == number || first > start || end > last || other_size < size || (other_size == size && other < number)) next
            if (other_size < best_size) {
                parents[number] <- other
                best_size <- other_size
            }
        }
    }
    list(
        areas = areas,
        clusters = clusters,
        position_labels = position_labels,
        cluster_labels = cluster_labels,
        parents = parents
    )
}
make_analysis <- function(points, params) {
    n <- length(points)
    k <- params$min_pts - 1L
    neighbors <- lapply(
        seq_along(points),
        function(i) sort(vapply(
            points[-i],
            function(other) squared_distance(points[[i]], other),
            0
        ))[seq_len(2L * params$min_pts)]
    )
    curves <- lapply(
        seq_len(2L * params$min_pts),
        function(j) make_curve(points, vapply(neighbors, function(row) row[j], 0))
    )
    curve <- curves[[k]]
    kdist <- vapply(neighbors, function(row) row[k], 0)
    radii <- sort(unique(c(params$eps_list, curve$eps, params$max_eps)))
    grids <- lapply(radii, function(eps) grid_summary(points, eps))
    neighborhoods <- setNames(lapply(grids, function(grid) grid$neighborhoods), as.character(radii))
    settings <- list()
    for (eps in params$eps_list) {
        result <- dbscan(neighborhoods[[as.character(eps)]], params$min_pts)
        settings <- c(settings, list(setting(paste0("db", eps), "dbscan", eps, result$labels, result$core)))
    }
    result <- dbscan(neighborhoods[[as.character(curve$eps)]], params$min_pts)
    knee <- setting(paste0("knee", curve$eps), "dbscan", curve$eps, result$labels, result$core)
    settings <- c(settings, list(knee))
    core_distance <- core_distances(points, neighborhoods[[as.character(params$max_eps)]], params$min_pts)
    optics <- optics_ordering(points, neighborhoods[[as.character(params$max_eps)]], core_distance)
    ordering <- optics$ordering
    reach <- optics$reach
    for (eps in params$extract_eps) {
        result <- extract_clusters(ordering, reach, core_distance, eps)
        settings <- c(settings, list(setting(paste0("op", eps), "extract", eps, result$labels, result$core)))
    }
    positions <- c(reach[ordering], INF)
    xi <- xi_method(positions, params)
    labels <- rep(NOISE, n)
    labels[ordering] <- xi$position_labels
    xi_setting <- setting("xi", "xi", params$max_eps, labels, core_distance != INF)
    settings <- c(settings, list(xi_setting))
    xs <- vapply(points, function(point) point$x, 0)
    ys <- vapply(points, function(point) point$y, 0)
    map_cells <- lapply(
        points,
        function(point) c(
            ((point$x - min(xs)) * params$map_width) %/% (max(xs) - min(xs) + 1) + 1,
            ((max(ys) - point$y) * params$map_height) %/% (max(ys) - min(ys) + 1) + 1
        )
    )
    list(
        points = points,
        params = params,
        min_pts = params$min_pts,
        k = k,
        curves = curves,
        curve = curve,
        kdist = kdist,
        grids = grids,
        neighborhoods = neighborhoods,
        settings = settings,
        knee = knee,
        core_distance = core_distance,
        ordering = ordering,
        reach = reach,
        predecessor = optics$predecessor,
        positions = positions,
        xi = xi,
        xi_setting = xi_setting,
        map_cells = map_cells
    )
}
turn <- function(o, a, b) (a$x - o$x) * (b$y - o$y) - (a$y - o$y) * (b$x - o$x)
half_hull <- function(ordered) {
    chain <- list()
    for (point in ordered) {
        while (length(chain) >= 2L && turn(
            chain[[length(chain) - 1L]],
            chain[[length(chain)]],
            point
        ) <= 0) chain <- head(chain, -1L)
        chain <- c(chain, list(point))
    }
    chain
}
convex_hull <- function(members) {
    ordered <- members[order(
        vapply(members, function(point) point$x, 0),
        vapply(members, function(point) point$y, 0)
    )]
    if (length(ordered) <= 2L) return(ordered)
    lower <- half_hull(ordered)
    upper <- half_hull(rev(ordered))
    c(head(lower, -1L), head(upper, -1L))
}
cluster_lines <- function(points, setting, label) {
    indices <- setting$members[[label + 1L]]
    members <- points[indices]
    size <- length(members)
    core <- sum(setting$core[indices])
    sx <- sum(vapply(members, function(point) point$x, 0))
    sy <- sum(vapply(members, function(point) point$y, 0))
    values <- vapply(
        members,
        function(point) (size * point$x - sx) * (size * point$x - sx) + (size * point$y - sy) * (size * point$y - sy),
        0
    )
    medoid <- members[[which.min(values)]]
    xmin <- min(vapply(members, function(point) point$x, 0))
    xmax <- max(vapply(members, function(point) point$x, 0))
    ymin <- min(vapply(members, function(point) point$y, 0))
    ymax <- max(vapply(members, function(point) point$y, 0))
    area <- (xmax - xmin + 1) * (ymax - ymin + 1)
    hull <- convex_hull(members)
    doubled <- abs(sum(vapply(seq_along(hull), function(i) {
        point <- hull[[i]]
        following <- hull[[i %% length(hull) + 1L]]
        point$x * following$y - following$x * point$y
    }, 0)))
    hull_area <- paste0(sprintf("%.0f", doubled %/% 2), ".", if (doubled %% 2) "5" else "0")
    diameter <- max(vapply(
        hull,
        function(point) max(vapply(hull, function(other) squared_distance(point, other), 0)),
        0
    ))
    c(line_text("cluster", label, label_char(label), "size", size, "core", core, "border", size - core, "centroid", fraction_text(sx, size), fraction_text(sy, size), "medoid", medoid$id),
      paste0(
          "  ",
          line_text("bbox", xmin, ymin, xmax, ymax, "area", area, "density", fraction_text(size, area))
      ),
      paste0(
          "  ",
          line_text(
              "hull",
              length(hull),
              "hull_area",
              hull_area,
              "diameter_sq",
              diameter,
              "diameter",
              root_text(diameter)
          )
      ))
}
adjusted_rand <- function(first, second) {
    pairs <- sum(vapply(as.numeric(table(paste(first, second, sep = ":"))), pair_count, 0))
    a <- sum(vapply(as.numeric(table(first)), pair_count, 0))
    b <- sum(vapply(as.numeric(table(second)), pair_count, 0))
    z <- pair_count(length(first))
    numerator <- 2 * (z * pairs - a * b)
    denominator <- z * (a + b) - 2 * a * b
    if (denominator == 0) c(1, 1) else c(numerator, denominator)
}
labels_lines <- function(a) {
    lines <- paste(c("id", vapply(a$settings, function(setting) setting$name, "")), collapse = ",")
    for (i in seq_along(a$points)) lines <- c(
        lines,
        paste(
            c(a$points[[i]]$id, vapply(a$settings, function(setting) setting$labels[i], 0L)),
            collapse = ","
        )
    )
    lines
}
optics_lines <- function(a) {
    lines <- "order,id,core_sq,reach_sq,reach,predecessor"
    for (position in seq_along(a$ordering)) {
        index <- a$ordering[position]
        reach <- a$reach[index]
        predecessor <- a$predecessor[index]
        previous <- if (predecessor == 0L) "-" else as.character(a$points[[predecessor]]$id)
        lines <- c(
            lines,
            paste(
                position,
                a$points[[index]]$id,
                value_text(a$core_distance[index]),
                value_text(reach),
                optional_root(reach),
                previous,
                sep = ","
            )
        )
    }
    lines
}
kdist_lines <- function(a) {
    curve <- a$curve
    lines <- c(line_text("k_distance", "k", a$k, "points", length(a$points)), "rank id kdist_sq kdist")
    add <- function(...) lines <<- c(lines, line_text(...))
    for (rank in seq_along(curve$order)) add(
        rank,
        a$points[[curve$order[rank]]]$id,
        curve$values[rank],
        root_text(curve$values[rank])
    )
    value <- curve$values[curve$knee]
    add("")
    add(
        "knee",
        "rank",
        curve$knee,
        "id",
        a$points[[curve$order[curve$knee]]]$id,
        "kdist_sq",
        value,
        "kdist",
        root_text(value),
        "cross",
        curve$cross
    )
    add("suggested_eps", curve$eps)
    add("")
    add("knee_table")
    for (j in seq_along(a$curves)) {
        row <- a$curves[[j]]
        add(
            "k",
            j,
            "rank",
            row$knee,
            "id",
            a$points[[row$order[row$knee]]]$id,
            "kdist_sq",
            row$values[row$knee],
            "eps",
            row$eps
        )
    }
    add("")
    add("core_check")
    for (setting in a$settings) {
        if (setting$kind != "dbscan") next
        core <- sum(a$kdist <= setting$radius * setting$radius)
        grid_core <- sum(setting$core)
        add(
            "eps",
            setting$radius,
            "core",
            core,
            "non_core",
            length(a$points) - core,
            "grid_core",
            grid_core,
            check_text(core == grid_core)
        )
    }
    defined <- which(a$core_distance != INF)
    add(
        "optics",
        "max_eps",
        a$params$max_eps,
        "core",
        length(defined),
        check_text(all(a$core_distance[defined] == a$kdist[defined]))
    )
    lines
}
check_lines <- function(a, setting) {
    linked <- supported <- separated <- TRUE
    isolated <- 0L
    ambiguous <- character()
    neighborhoods <- a$neighborhoods[[as.character(setting$radius)]]
    for (i in seq_along(neighborhoods)) {
        neighbors <- neighborhoods[[i]]
        label <- setting$labels[i]
        core_labels <- setting$labels[neighbors[setting$core[neighbors]]]
        if (setting$core[i]) {
            if (any(core_labels != label)) linked <- FALSE
        } else if (label != NOISE) {
            if (!(label %in% core_labels)) supported <- FALSE
            others <- sort(unique(core_labels[core_labels != label]))
            if (length(others)) ambiguous <- c(
                ambiguous,
                paste0("  ", line_text(a$points[[i]]$id, "cluster", label, "also", others))
            )
        } else {
            if (length(core_labels)) separated <- FALSE
            if (length(neighbors) == 1L) isolated <- isolated + 1L
        }
    }
    c(
        line_text("check", condition_text(linked), condition_text(supported), condition_text(separated)),
        line_text("isolated", isolated),
        line_text("ambiguous", length(ambiguous)),
        ambiguous
    )
}
setting_lines <- function(a, setting) {
    lines <- line_text(
        "setting",
        setting$name,
        "eps",
        setting$radius,
        "clusters",
        setting$count,
        "noise",
        setting$noise,
        "core",
        setting$core_count,
        "border",
        setting$border_count
    )
    for (label in seq_len(setting$count) - 1L) lines <- c(lines, cluster_lines(a$points, setting, label))
    if (setting$kind == "dbscan") lines <- c(lines, check_lines(a, setting))
    lines
}
hierarchy_lines <- function(a) {
    settings <- Filter(function(setting) setting$kind == "dbscan", a$settings)
    settings <- settings[order(vapply(settings, function(setting) setting$radius, 0L), seq_along(settings))]
    lines <- "hierarchy"
    if (length(settings) > 1L) for (i in seq.int(2L, length(settings))) {
        small <- settings[[i - 1L]]
        large <- settings[[i]]
        lines <- c(lines, line_text(small$name, "->", large$name))
        sources <- lapply(seq_len(large$count), function(i) integer())
        for (label in seq_along(small$members)) {
            members <- small$members[[label]]
            first_core <- members[which(small$core[members])[1L]]
            destination <- large$labels[first_core] + 1L
            sources[[destination]] <- c(sources[[destination]], label - 1L)
        }
        for (label in seq_along(sources)) lines <- c(
            lines,
            paste0("  ", line_text(label - 1L, "<-", if (length(sources[[label]])) sources[[label]] else "-"))
        )
    }
    lines
}
comparison_lines <- function(a) {
    lines <- "optics_vs_dbscan"
    for (x in a$settings) {
        if (x$kind != "extract") next
        matches <- Filter(
            function(setting) setting$kind == "dbscan" && setting$radius == x$radius,
            a$settings
        )
        if (!length(matches)) next
        y <- matches[[1L]]
        pairs <- unique(cbind(x$labels[x$core], y$labels[x$core]))
        same <- nrow(pairs) == length(unique(pairs[, 1L])) && nrow(pairs) == length(unique(pairs[, 2L]))
        border_as_noise <- sum(x$labels == NOISE & y$labels != NOISE)
        moved <- "-"
        if (same) {
            mapping <- setNames(as.list(pairs[, 2L]), as.character(pairs[, 1L]))
            moved <- as.character(sum(vapply(
                seq_along(x$labels),
                function(i) x$labels[i] != NOISE && mapping[[as.character(x$labels[i])]] != y$labels[i],
                FALSE
            )))
        }
        lines <- c(
            lines,
            line_text(
                x$name,
                y$name,
                "core_partition",
                if (same) "same" else "different",
                "border_as_noise",
                border_as_noise,
                "moved",
                moved
            )
        )
    }
    lines
}
optics_summary_lines <- function(a) {
    components <- integer()
    for (index in a$ordering) {
        if (a$reach[index] == INF) components <- c(components, 0L)
        components[length(components)] <- tail(components, 1L) + 1L
    }
    line_text(
        "optics",
        "max_eps",
        a$params$max_eps,
        "core",
        sum(a$core_distance != INF),
        "components",
        length(components),
        "singletons",
        sum(components == 1L),
        "largest",
        max(components)
    )
}
sweep_lines <- function(a) {
    lines <- c(line_text("sweep", "max_eps", a$params$max_eps), "eps clusters noise largest")
    counts <- integer(a$params$max_eps)
    for (eps in seq_len(a$params$max_eps)) {
        result <- extract_clusters(a$ordering, a$reach, a$core_distance, eps)
        labels <- result$labels
        sizes <- as.integer(table(labels[labels != NOISE]))
        counts[eps] <- max(labels) + 1L
        lines <- c(lines, line_text(eps, counts[eps], sum(labels == NOISE), max(c(0L, sizes))))
    }
    stable <- NULL
    start <- 1L
    for (eps in seq_len(a$params$max_eps)) {
        if (eps < a$params$max_eps && counts[eps + 1L] == counts[start]) next
        run_length <- eps - start + 1L
        if (counts[start] >= 2L && (is.null(stable) || run_length > stable$length)) stable <- list(
            clusters = counts[start],
            first = start,
            last = eps,
            length = run_length
        )
        start <- eps + 1L
    }
    ending <- if (is.null(stable)) "stable -" else line_text(
        "stable",
        "clusters",
        stable$clusters,
        "eps",
        stable$first,
        stable$last,
        "length",
        stable$length
    )
    c(lines, ending)
}
xi_lines <- function(a) {
    xi <- a$xi
    lines <- line_text(
        "xi",
        a$params$xi_text,
        "min_size",
        a$params$xi_min_size,
        "steep_areas",
        length(xi$areas)
    )
    for (area in xi$areas) lines <- c(lines, line_text(area$kind, area$start, area$end))
    lines <- c(lines, line_text("xi_clusters", length(xi$clusters)))
    for (j in seq_along(xi$clusters)) {
        start <- xi$clusters[[j]][1L]
        end <- xi$clusters[[j]][2L]
        inner <- a$positions[seq.int(start + 1L, end)]
        inner <- inner[inner != INF]
        valley <- if (length(inner)) min(inner) else INF
        parent <- if (xi$parents[j] == 0L) "-" else as.character(xi$parents[j] - 1L)
        lines <- c(
            lines,
            line_text(
                j - 1L,
                "start",
                start,
                "end",
                end,
                "size",
                end - start + 1L,
                "label",
                optional_label(xi$cluster_labels[j]),
                "parent",
                parent,
                "walls",
                optional_root(a$positions[start]),
                optional_root(a$positions[end + 1L]),
                "valley",
                optional_root(valley)
            )
        )
    }
    lines
}
outlier_lines <- function(a) {
    knee <- a$knee
    core <- which(knee$core)
    rows <- list()
    for (i in which(knee$labels == NOISE)) {
        distances <- vapply(core, function(j) squared_distance(a$points[[i]], a$points[[j]]), 0)
        q <- core[which.min(distances)]
        rows <- c(
            rows,
            list(list(distance = squared_distance(a$points[[i]], a$points[[q]]), index = i, nearest = q))
        )
    }
    rows <- rows[order(
        -vapply(rows, function(row) row$distance, 0),
        vapply(rows, function(row) a$points[[row$index]]$id, 0L)
    )]
    lines <- line_text("outliers", knee$name, "count", length(rows))
    for (row in rows) lines <- c(
        lines,
        line_text(
            a$points[[row$index]]$id,
            "nearest_core",
            a$points[[row$nearest]]$id,
            "cluster",
            knee$labels[row$nearest],
            "dist_sq",
            row$distance,
            "dist",
            root_text(row$distance)
        )
    )
    lines
}
gap_lines <- function(a) {
    knee <- a$knee
    lines <- line_text("gaps", knee$name)
    if (knee$count > 1L) for (first in seq_len(knee$count - 1L)) for (second in seq.int(
        first + 1L,
        knee$count
    )) {
        best <- NULL
        for (i in knee$members[[first]]) for (j in knee$members[[second]]) {
            distance <- squared_distance(a$points[[i]], a$points[[j]])
            if (is.null(best) || distance < best$distance) best <- list(
                distance = distance,
                p = a$points[[i]]$id,
                q = a$points[[j]]$id
            )
        }
        lines <- c(
            lines,
            line_text(
                first - 1L,
                second - 1L,
                "dist_sq",
                best$distance,
                "dist",
                root_text(best$distance),
                "between",
                best$p,
                best$q
            )
        )
    }
    lines
}
contingency_lines <- function(a) {
    knee <- a$knee
    xi <- a$xi_setting
    table <- matrix(0L, knee$count + 1L, xi$count + 1L)
    for (i in seq_along(knee$labels)) table[knee$labels[i] + 2L, xi$labels[i] + 2L] <- table[
        knee$labels[i] + 2L,
        xi$labels[i] + 2L
    ] + 1L
    lines <- c(line_text("contingency", knee$name, "xi"), line_text("columns", seq_len(xi$count + 1L) - 2L))
    for (r in seq_len(knee$count + 1L) - 2L) lines <- c(lines, line_text(r, table[r + 2L, ]))
    for (column in seq_len(xi$count) - 1L) {
        shared_counts <- table[seq.int(2L, nrow(table)), column + 2L]
        row <- which.max(shared_counts)
        shared <- shared_counts[row]
        union <- length(knee$members[[row]]) + length(xi$members[[column + 1L]]) - shared
        lines <- c(
            lines,
            line_text("match", column, row - 1L, "shared", shared, "jaccard", fraction_text(shared, union))
        )
    }
    lines
}
ari_lines <- function(a) {
    lines <- "ari"
    for (i in seq_len(length(a$settings) - 1L)) for (j in seq.int(i + 1L, length(a$settings))) {
        first <- a$settings[[i]]
        second <- a$settings[[j]]
        value <- adjusted_rand(first$labels, second$labels)
        lines <- c(lines, line_text(first$name, second$name, ari_text(value[1L], value[2L])))
    }
    lines
}
join_parts <- function(parts) {
    lines <- character()
    for (part in parts) {
        if (length(lines)) lines <- c(lines, "")
        lines <- c(lines, part)
    }
    lines
}
clusters_lines <- function(a) {
    parts <- list(c(
        line_text("points", length(a$points), "min_pts", a$min_pts),
        line_text("settings", vapply(a$settings, function(setting) setting$name, ""))
    ))
    grid_lines <- "grid"
    for (grid in a$grids) {
        occupancy <- vapply(grid$occupancy, function(pair) paste(pair, collapse = ":"), "")
        grid_lines <- c(
            grid_lines,
            line_text(
                "eps",
                grid$eps,
                "cells",
                grid$cells,
                "busiest",
                grid$busiest,
                "candidates",
                grid$candidates,
                "pairs",
                grid$pairs,
                "brute_pairs",
                grid$brute_pairs,
                check_text(grid$consistent)
            ),
            paste0("  occupancy ", paste(occupancy, collapse = " "))
        )
    }
    parts <- c(
        parts,
        list(grid_lines),
        lapply(a$settings, function(setting) setting_lines(a, setting)),
        list(
            hierarchy_lines(a),
            comparison_lines(a),
            optics_summary_lines(a),
            sweep_lines(a),
            xi_lines(a),
            outlier_lines(a),
            gap_lines(a),
            contingency_lines(a),
            ari_lines(a)
        )
    )
    join_parts(parts)
}
map_rows <- function(a, setting, kind = FALSE) {
    width <- a$params$map_width
    height <- a$params$map_height
    cells <- lapply(seq_len(width * height), function(i) integer())
    for (i in seq_along(a$map_cells)) {
        cell <- a$map_cells[[i]]
        index <- (cell[2L] - 1L) * width + cell[1L]
        cells[[index]] <- c(cells[[index]], i)
    }
    vapply(seq_len(height), function(row) {
        characters <- vapply(seq_len(width), function(column) {
            indices <- cells[[(row - 1L) * width + column]]
            if (!length(indices)) return(" ")
            if (kind) return(if (any(setting$core[indices])) "#" else if (any(setting$labels[indices] != NOISE)) "+" else ".")
            clusters <- unique(setting$labels[indices][setting$labels[indices] != NOISE])
            if (!length(clusters)) "." else if (length(clusters) == 1L) label_char(clusters[1L]) else "*"
        }, "")
        paste(characters, collapse = "")
    }, "")
}
kdist_plot <- function(a) {
    curve <- a$curve
    width <- a$params$kdist_width
    height <- a$params$kdist_height
    n <- length(a$points)
    top <- curve$values[1L]
    heights <- integer(width)
    knee_column <- 1L
    for (column in seq.int(0L, width - 1L)) {
        first <- (column * n) %/% width + 1L
        last <- ((column + 1L) * n) %/% width
        heights[column + 1L] <- integer_sqrt((height * height * curve$values[first]) %/% top)
        if (first <= curve$knee && curve$knee <= last) knee_column <- column + 1L
    }
    rows <- vapply(
        seq_len(height),
        function(row) paste(
            vapply(
                seq_len(width),
                function(column) if (height - row + 1L <= heights[column]) "#" else if (column == knee_column) ":" else " ",
                ""
            ),
            collapse = ""
        ),
        ""
    )
    list(rows = rows, knee_column = knee_column)
}
maps_lines <- function(a) {
    lines <- character()
    for (setting in a$settings) {
        lines <- c(
            lines,
            line_text("map", setting$name, "clusters", setting$count, "noise", setting$noise),
            framed(map_rows(a, setting), a$params$map_width)
        )
        legend <- if (!length(setting$members)) "-" else vapply(
            seq_along(setting$members),
            function(label) paste0(label_char(label - 1L), "=", length(setting$members[[label]])),
            ""
        )
        lines <- c(lines, line_text("legend", legend), "")
    }
    lines <- c(
        lines,
        line_text("kinds", a$knee$name),
        framed(map_rows(a, a$knee, kind = TRUE), a$params$map_width),
        ""
    )
    plot <- kdist_plot(a)
    lines <- c(
        lines,
        line_text(
            "kdist_plot",
            "k",
            a$k,
            "max",
            root_text(a$curve$values[1L]),
            "knee_column",
            plot$knee_column
        ),
        framed(plot$rows, a$params$kdist_width),
        ""
    )
    top <- max(a$positions[a$positions != INF])
    columns <- c(Filter(function(setting) setting$kind == "extract", a$settings), list(a$xi_setting))
    lines <- c(
        lines,
        line_text(
            "reachability",
            "width",
            a$params$plot_width,
            "max_reach",
            root_text(top),
            "columns",
            vapply(columns, function(setting) setting$name, "")
        )
    )
    for (position in seq_along(a$ordering)) {
        index <- a$ordering[position]
        reach <- a$reach[index]
        width <- a$params$plot_width
        bar <- if (reach == INF) strrep("-", width) else strrep(
            "#",
            integer_sqrt((width * width * reach) %/% top)
        )
        characters <- paste(
            vapply(columns, function(setting) label_char(setting$labels[index]), ""),
            collapse = ""
        )
        lines <- c(
            lines,
            paste0(
                sprintf("%4d", position),
                " ",
                sprintf("%5d", a$points[[index]]$id),
                " ",
                sprintf("%7s", optional_root(reach)),
                " ",
                characters,
                " |",
                bar
            )
        )
    }
    lines
}
main <- function() {
    options(scipen = 999)
    analysis <- make_analysis(read_points(), read_params())
    outputs <- list(
        "labels.csv" = labels_lines(analysis),
        "optics_order.csv" = optics_lines(analysis),
        "kdist.txt" = kdist_lines(analysis),
        "clusters.txt" = clusters_lines(analysis),
        "maps.txt" = maps_lines(analysis)
    )
    for (name in names(outputs)) write_lines(name, outputs[[name]])
}
main()
