source("graph_io.R")
source("acyclic_layering.R")
source("crossing.R")
source("coordinates.R")
source("canvas.R")
words <- function(...) {
    parts <- lapply(list(...), function(part) if (is.numeric(part)) sprintf("%.0f", part) else as.character(part))
    paste(unlist(parts), collapse=" ")
}
new_edge <- function(number, source, target) {
    edge <- new.env(parent=emptyenv())
    edge$number <- number
    edge$source <- edge$upper <- source
    edge$target <- edge$lower <- target
    edge$reversed <- edge$transitive <- FALSE
    edge$chain <- integer()
    edge$span <- edge$crossings <- edge$bends <- edge$length <- 0L
    edge$route <- list()
    edge$upper_endpoint <- edge$lower_endpoint <- c(0L, 0L)
    edge
}
reachable <- function(start, neighbors) {
    found <- pending <- start
    while (length(pending)) {
        v <- tail(pending, 1)
        pending <- head(pending, -1)
        for (w in neighbors[[v]]) if (!w %in% found) {
            found <- c(found, w)
            pending <- c(pending, w)
        }
    }
    found
}
reorder_layer <- function(orders, layer, reference, method) {
    position <- positions(orders)
    current <- orders[[layer]]
    movable <- current[lengths(reference[current]) > 0L]
    keys <- lapply(movable, function(v) {
        neighbors <- sort(position[reference[[v]]])
        size <- length(neighbors)
        if (method == "barycenter") c(sum(neighbors), size) else {
            c(neighbors[(size-1L) %/% 2L+1L]+neighbors[size %/% 2L+1L], 1L)
        }
    })
    ordered <- integer()
    for (i in seq_along(movable)) {
        destination <- 1L
        while (destination <= length(ordered)) {
            other <- ordered[destination]
            if (keys[[i]][1]*keys[[other]][2] < keys[[other]][1]*keys[[i]][2]) break
            destination <- destination+1L
        }
        ordered <- append(ordered, i, after=destination-1L)
    }
    current[lengths(reference[current]) > 0L] <- movable[ordered]
    orders[[layer]] <- current
    orders
}
adjacent_exchanges <- function(orders, upper, lower) {
    swaps <- 0L
    position <- positions(orders)
    repeat {
        changed <- FALSE
        for (layer in seq_along(orders)) for (i in seq_len(length(orders[[layer]])-1L)) {
            a <- orders[[layer]][i]
            b <- orders[[layer]][i+1L]
            if (adjacent_cost(a, b, upper, lower, position) > adjacent_cost(b, a, upper, lower, position)) {
                orders[[layer]][c(i,i+1L)] <- c(b,a)
                position[a] <- i
                position[b] <- i-1L
                swaps <- swaps+1L
                changed <- TRUE
            }
        }
        if (!changed) return(list(orders=orders, swaps=swaps))
    }
}
reduce_crossings <- function(initial, gaps, upper, lower, vertex_layer, settings) {
    records <- sift_records <- list()
    random_state <- as.numeric(settings$seed)
    best_run <- best_sweep <- 0L
    best_crossings <- .Machine$integer.max
    adopted <- initial
    for (run in 0:settings$restarts) {
        orders <- initial
        if (run > 0L) for (layer in seq_along(orders)) if (length(orders[[layer]]) >= 2L) {
            for (j in seq.int(length(orders[[layer]]), 2L)) {
                random_state <- (48271*random_state) %% 2147483647
                k <- random_state %% j+1L
                orders[[layer]][c(j,k)] <- orders[[layer]][c(k,j)]
            }
        }
        crossings <- total_crossings(gaps, orders)
        records[[length(records)+1L]] <- list(run=run, sweep=0L, direction="initial", moved=0L, swaps=0L, crossings=crossings)
        history <- list(orders)
        local_best <- crossings
        local_sweep <- 0L
        local_order <- orders
        sweep <- 1L
        while (crossings != 0L && sweep-1L != settings$sweeps) {
            if (sweep-1L >= 2L && identical(history[[length(history)]], history[[length(history)-2L]])) break
            before <- positions(orders)
            if (sweep %% 2L == 1L) {
                layers <- if (length(orders) >= 2L) seq.int(2L, length(orders)) else integer()
                reference <- upper
            } else {
                layers <- rev(seq_len(length(orders)-1L))
                reference <- lower
            }
            for (layer in layers) orders <- reorder_layer(orders, layer, reference, settings$heuristic)
            moved <- sum(before != positions(orders))
            exchange <- adjacent_exchanges(orders, upper, lower)
            orders <- exchange$orders
            crossings <- total_crossings(gaps, orders)
            records[[length(records)+1L]] <- list(run=run, sweep=sweep, direction=if (sweep %% 2L == 1L) "down" else "up",
                moved=moved, swaps=exchange$swaps, crossings=crossings)
            history[[length(history)+1L]] <- orders
            if (crossings < local_best) {
                local_best <- crossings
                local_sweep <- sweep
                local_order <- orders
            }
            sweep <- sweep+1L
        }
        if (local_best < best_crossings) {
            best_crossings <- local_best
            best_run <- run
            best_sweep <- local_sweep
            adopted <- local_order
        }
    }
    if (settings$sifting == "on") {
        round <- 0L
        repeat {
            round <- round+1L
            moves <- 0L
            for (v in seq_along(vertex_layer)) {
                layer <- vertex_layer[v]
                original <- which(adopted[[layer]] == v)[1]
                remaining <- adopted[[layer]][adopted[[layer]] != v]
                costs <- integer()
                for (position in 0:length(remaining)) {
                    adopted[[layer]] <- append(remaining, v, after=position)
                    costs <- c(costs, local_crossings(gaps, adopted, layer))
                }
                lowest <- min(costs)
                chosen <- if (costs[original] == lowest) original else which.min(costs)
                adopted[[layer]] <- append(remaining, v, after=chosen-1L)
                moves <- moves+as.integer(chosen != original)
            }
            sift_records[[length(sift_records)+1L]] <- c(round, moves, total_crossings(gaps, adopted))
            if (moves == 0L) break
        }
    }
    list(orders=adopted, records=records, sift=sift_records, best_run=best_run, best_sweep=best_sweep, best_crossings=best_crossings)
}
assign_tracks <- function(segments, x, settings) {
    bent <- Filter(function(s) x[s[1]] != x[s[2]], segments)
    upper_counts <- table(vapply(bent, function(s) s[1], 0L))
    buses <- list()
    for (segment in bent) {
        p <- segment[1]
        q <- segment[2]
        kind <- if (upper_counts[[as.character(p)]] >= 2L) 0L else 1L
        vertex <- if (kind == 0L) p else q
        key <- paste(kind, vertex)
        bus <- buses[[key]]
        if (is.null(bus)) bus <- list(kind=kind, vertex=vertex, members=list())
        bus$members[[length(bus$members)+1L]] <- segment
        buses[[key]] <- bus
    }
    details <- lapply(buses, function(bus) {
        values <- unlist(lapply(bus$members, function(s) x[s[1:2]]), use.names=FALSE)
        list(low=min(values), high=max(values), kind=bus$kind, coordinate=x[bus$vertex], members=bus$members)
    })
    indices <- order(vapply(details, function(b) b$low, 0L), vapply(details, function(b) b$high, 0L),
        vapply(details, function(b) b$kind, 0L), vapply(details, function(b) b$coordinate, 0L))
    ends <- integer()
    tracks <- integer()
    for (bus in details[indices]) {
        available <- which(ends+1L < bus$low)
        if (length(available)) {
            chosen <- available[1]
            ends[chosen] <- bus$high
        } else {
            ends <- c(ends, bus$high)
            chosen <- length(ends)
        }
        for (s in bus$members) tracks[segment_key(s[1],s[2])] <- chosen
    }
    total <- length(ends)
    gap <- max(settings$layer_gap, total+2L)
    offsets <- tracks+(gap-2L-total) %/% 2L
    list(total=total, gap=gap, offsets=offsets)
}
layout_graph <- function(graph) {
    settings <- graph$settings
    ids <- sort(as.integer(names(graph$nodes)))
    node_count <- length(ids)
    node_numbers <- setNames(seq_along(ids), as.character(ids))
    labels <- unname(graph$nodes[as.character(ids)])
    edges <- lapply(seq_along(graph$edges), function(i) {
        edge <- graph$edges[[i]]
        new_edge(i, unname(node_numbers[[as.character(edge[1])]]), unname(node_numbers[[as.character(edge[2])]]))
    })
    vertex_names <- as.character(ids)
    widths <- nchar(labels)+2L
    original <- lapply(edges, function(e) c(e$source,e$target))
    original_neighbors <- graph_neighbors(node_count, original)
    sources <- sum(lengths(original_neighbors$upper) == 0L & lengths(original_neighbors$lower) > 0L)
    sinks <- sum(lengths(original_neighbors$lower) == 0L & lengths(original_neighbors$upper) > 0L)
    isolated <- sum(lengths(original_neighbors$upper) == 0L & lengths(original_neighbors$lower) == 0L)
    undirected <- lapply(seq_len(node_count), function(v) union(original_neighbors$upper[[v]], original_neighbors$lower[[v]]))
    remaining <- seq_len(node_count)
    components <- 0L
    while (length(remaining)) {
        remaining <- setdiff(remaining, reachable(min(remaining), undirected))
        components <- components+1L
    }
    closure <- lapply(seq_len(node_count), function(v) reachable(v, original_neighbors$lower))
    remaining <- seq_len(node_count)
    strong <- list()
    while (length(remaining)) {
        first <- min(remaining)
        component <- sort(remaining[vapply(remaining, function(v) v %in% closure[[first]] && first %in% closure[[v]], FALSE)])
        remaining <- setdiff(remaining, component)
        if (length(component) >= 2L) strong[[length(strong)+1L]] <- component
    }
    acyclic <- acyclic_order(node_count, original)
    acyclic_position <- match(seq_len(node_count), acyclic)
    for (edge in edges) if (acyclic_position[edge$source] > acyclic_position[edge$target]) {
        edge$reversed <- TRUE
        edge$upper <- edge$target
        edge$lower <- edge$source
    }
    dag <- lapply(edges, function(e) c(e$upper,e$lower))
    dag_lower <- graph_neighbors(node_count, dag)$lower
    if (settings$reduce == "on") {
        closure <- lapply(seq_len(node_count), function(v) reachable(v, dag_lower))
        for (edge in edges) if (!edge$reversed) {
            edge$transitive <- any(vapply(dag_lower[[edge$upper]], function(w) w != edge$lower && edge$lower %in% closure[[w]], FALSE))
        }
    }
    drawn <- Filter(function(e) !e$transitive, edges)
    heights <- assign_heights(node_count, lapply(drawn, function(e) c(e$upper,e$lower)), settings)
    levels <- max(heights$heights)-heights$heights
    used <- unique(levels)
    for (edge in drawn) if (levels[edge$lower]-levels[edge$upper] >= 2L) {
        used <- union(used, seq.int(levels[edge$upper]+1L, levels[edge$lower]-1L))
    }
    used <- sort(used)
    vertex_layer <- match(levels, used)
    layer_count <- length(used)
    for (edge in drawn) {
        first <- vertex_layer[edge$upper]
        last <- vertex_layer[edge$lower]
        edge$span <- last-first
        edge$chain <- edge$upper
        if (last-first >= 2L) for (layer in seq.int(first+1L, last-1L)) {
            vertex_layer <- c(vertex_layer, layer)
            vertex_names <- c(vertex_names, paste0("d", length(vertex_layer)-node_count))
            widths <- c(widths, 1L)
            edge$chain <- c(edge$chain, length(vertex_layer))
        }
        edge$chain <- c(edge$chain, edge$lower)
    }
    vertex_count <- length(vertex_layer)
    upper <- lower <- rep(list(integer()), vertex_count)
    gaps <- rep(list(list()), layer_count-1L)
    for (edge in drawn) for (j in seq_len(length(edge$chain)-1L)) {
        p <- edge$chain[j]
        q <- edge$chain[j+1L]
        layer <- vertex_layer[p]
        gaps[[layer]][[length(gaps[[layer]])+1L]] <- c(p,q,edge$number)
        lower[[p]] <- c(lower[[p]], q)
        upper[[q]] <- c(upper[[q]], p)
    }
    initial_order <- rep(list(integer()), layer_count)
    visited <- rep(FALSE, vertex_count)
    visit <- function(v) {
        if (visited[v]) return(invisible(NULL))
        visited[v] <<- TRUE
        layer <- vertex_layer[v]
        initial_order[[layer]] <<- c(initial_order[[layer]], v)
        for (w in lower[[v]]) visit(w)
    }
    for (v in seq_len(node_count)) visit(v)
    initial_crossings <- total_crossings(gaps, initial_order)
    reduction <- reduce_crossings(initial_order, gaps, upper, lower, vertex_layer, settings)
    orders <- reduction$orders
    position <- positions(orders)
    crossings_by_gap <- gap_counts(gaps, orders)
    final_crossings <- sum(crossings_by_gap)
    brute <- sum(vapply(gaps, function(s) brute_crossings(s, position), 0L))
    for (segments in gaps) for (i in seq_along(segments)) if (i < length(segments)) for (j in seq.int(i+1L, length(segments))) {
        a <- segments[[i]]
        b <- segments[[j]]
        if ((position[a[1]]-position[b[1]])*(position[a[2]]-position[b[2]]) < 0L) {
            edges[[a[3]]]$crossings <- edges[[a[3]]]$crossings+1L
            edges[[b[3]]]$crossings <- edges[[b[3]]]$crossings+1L
        }
    }
    coordinates <- assign_coordinates(orders, upper, lower, widths, node_count, settings)
    x <- coordinates$x
    track_counts <- gap_widths <- integer()
    offsets <- integer()
    for (segments in gaps) {
        geometry <- assign_tracks(segments, x, settings)
        track_counts <- c(track_counts, geometry$total)
        gap_widths <- c(gap_widths, geometry$gap)
        offsets <- c(offsets, geometry$offsets)
    }
    vertical <- settings$direction %in% c("TB", "BT")
    thickness <- vapply(orders, function(layer) if (vertical) 1L else max(widths[layer]), 0L)
    bands <- 0L
    for (layer in seq_len(layer_count-1L)) bands <- c(bands, tail(bands,1)+thickness[layer]+gap_widths[layer])
    main_length <- tail(bands,1)+tail(thickness,1)
    secondary_length <- max(x+coordinates$right)+1L
    canvas <- new_canvas(settings$direction, main_length, secondary_length)
    for (edge in drawn) {
        size <- if (vertical) 1L else widths[edge$upper]
        edge$upper_endpoint <- c(bands[vertex_layer[edge$upper]]+size, x[edge$upper])
        edge$lower_endpoint <- c(bands[vertex_layer[edge$lower]]-1L, x[edge$lower])
    }
    for (v in seq_len(vertex_count)) {
        layer <- vertex_layer[v]
        beginning <- bands[layer]
        ending <- beginning+thickness[layer]-1L
        if (v > node_count) main_line(canvas, beginning, ending, x[v]) else {
            if (!vertical && length(lower[[v]])) main_line(canvas, beginning+widths[v], ending, x[v])
        }
    }
    for (layer in seq_along(gaps)) for (segment in gaps[[layer]]) {
        p <- segment[1]
        q <- segment[2]
        key <- segment_key(p,q)
        offset <- if (key %in% names(offsets)) offsets[[key]] else 0L
        draw_segment(canvas, bands[layer]+thickness[layer], gap_widths[layer], x[p], x[q], offset)
    }
    for (edge in drawn) {
        draw_arrow(canvas, if (edge$reversed) edge$upper_endpoint else edge$lower_endpoint, edge$reversed)
        points <- list(edge$upper_endpoint)
        bent <- 0L
        for (j in seq_len(length(edge$chain)-1L)) {
            p <- edge$chain[j]
            q <- edge$chain[j+1L]
            if (x[p] == x[q]) next
            layer <- vertex_layer[p]
            main <- bands[layer]+thickness[layer]+offsets[[segment_key(p,q)]]
            points <- c(points, list(c(main,x[p]), c(main,x[q])))
            bent <- bent+1L
        }
        points <- c(points, list(edge$lower_endpoint))
        edge$route <- lapply(points, function(point) canvas_cell(canvas, point[1], point[2]))
        if (edge$reversed) edge$route <- rev(edge$route)
        edge$bends <- 2L*bent
        edge$length <- 1L+sum(vapply(seq_len(length(edge$route)-1L), function(i) {
            sum(abs(edge$route[[i+1L]]-edge$route[[i]]))
        }, 0L))
    }
    path <- NULL
    if (!is.null(graph$path)) {
        start <- node_numbers[[as.character(graph$path[1])]]
        stop <- node_numbers[[as.character(graph$path[2])]]
        following <- lapply(seq_len(node_count), function(v) sort(vapply(Filter(function(e) e$source == v, drawn), function(e) e$target, 0L)))
        parent <- rep(-1L, node_count)
        parent[start] <- 0L
        queue <- start
        head <- 1L
        while (head <= length(queue)) {
            v <- queue[head]
            head <- head+1L
            for (w in following[[v]]) if (parent[w] == -1L) {
                parent[w] <- v
                queue <- c(queue, w)
            }
        }
        if (parent[stop] != -1L) {
            path <- integer()
            v <- stop
            while (v != 0L) {
                path <- c(path, v)
                v <- parent[v]
            }
            path <- rev(path)
        }
    }
    if (!is.null(path)) {
        by_endpoints <- setNames(drawn, vapply(drawn, function(e) segment_key(e$source,e$target), ""))
        for (i in seq_len(length(path)-1L)) highlight_route(canvas, by_endpoints[[segment_key(path[i],path[i+1L])]]$route)
    }
    for (v in seq_len(node_count)) draw_box(canvas, labels[v], bands[vertex_layer[v]], x[v], coordinates$left[v], !is.null(path) && v %in% path)
    settings_text <- vapply(SETTING_NAMES, function(key) paste0(key, "=", settings[[key]]), "")
    layout <- c(paste("graph", graph$name), words("settings", settings_text), words("acyclic", vertex_names[acyclic]))
    if (!is.null(heights$labels)) layout <- c(layout, words("labels", paste0(vertex_names[seq_len(node_count)], ":", heights$labels)))
    for (record in heights$records) layout <- c(layout, words("promote", record[1], vertex_names[record[2]], record[3]))
    for (r in reduction$records) {
        text <- words("sweep", r$run, r$sweep, r$direction)
        if (r$sweep > 0L) text <- words(text, "moved", r$moved, "swaps", r$swaps)
        layout <- c(layout, words(text, "crossings", r$crossings))
    }
    layout <- c(layout, words("best run", reduction$best_run, "sweep", reduction$best_sweep, "crossings", reduction$best_crossings))
    for (record in reduction$sift) layout <- c(layout, words("sift", record[1], "moves", record[2], "crossings", record[3]))
    for (layer in seq_along(orders)) {
        vertices <- orders[[layer]]
        first <- bands[layer]
        last <- first+thickness[layer]-1L
        if (settings$direction %in% c("BT", "RL")) {
            previous_first <- first
            first <- main_length-1L-last
            last <- main_length-1L-previous_first
        }
        low <- min(x[vertices]-coordinates$left[vertices])
        high <- max(x[vertices]+coordinates$right[vertices])
        layout <- c(layout, words("layer", layer-1L, "band", first, last, "extent", low, high, ":", paste0(vertex_names[vertices], "@", x[vertices])))
    }
    for (gap in seq_along(gaps)) layout <- c(layout, words("between", gap-1L, gap, "segments", length(gaps[[gap]]),
        "crossings", crossings_by_gap[gap], "tracks", track_counts[gap], "gap", gap_widths[gap]))
    variants <- vapply(VARIANTS, function(k) paste0(k,"=",coordinates$blocks[[k]],"/",coordinates$widths[[k]]), "")
    layout <- c(layout, words("bk conflicts", length(ls(coordinates$conflicts, all.names=TRUE)), variants, "smallest", coordinates$smallest))
    for (vertices in orders) for (v in vertices) {
        aligned <- vapply(VARIANTS, function(k) words(k, coordinates$aligned[[k]][v]), "")
        layout <- c(layout, words("vertex", vertex_names[v], "layer", vertex_layer[v]-1L, "pos", position[v], aligned, "x", x[v]))
    }
    for (edge in edges) {
        text <- words("edge", ids[edge$source], ids[edge$target])
        if (edge$transitive) {
            layout <- c(layout, paste(text, "transitive"))
        } else {
            if (edge$reversed) text <- paste(text, "reversed")
            chain <- if (edge$reversed) rev(edge$chain) else edge$chain
            route <- vapply(edge$route, function(point) paste(point, collapse=","), "")
            layout <- c(layout, words(text, "span", edge$span, "crossings", edge$crossings, "bends", edge$bends, "path", x[chain], "route", route))
        }
    }
    layout <- c(layout, "end")
    statistics <- c(paste("graph", graph$name), words("nodes", node_count, "edges", length(edges), "self_loops", graph$self_loops, "duplicates", graph$duplicates),
        words("sources", sources, "sinks", sinks, "isolated", isolated, "components", components))
    for (component in strong) statistics <- c(statistics, words("scc", vertex_names[component]))
    edge_name <- function(edge) paste0(ids[edge$source], "->", ids[edge$target])
    for (kind in c("reversed", "transitive")) {
        selected <- Filter(function(e) e[[kind]], edges)
        statistics <- c(statistics, words(kind, length(selected), vapply(selected, edge_name, "")))
    }
    max_nodes <- max(vapply(orders, function(layer) sum(layer <= node_count), 0L))
    statistics <- c(statistics, words("layers", layer_count, "max_nodes", max_nodes, "max_vertices", max(lengths(orders))))
    statistics <- c(statistics, if (settings$promotion == "on") {
        words("promotion rounds", heights$rounds, "accepted", length(heights$records), "dummies_before", heights$dummies_before)
    } else "promotion off")
    spans <- sort(unique(vapply(drawn, function(e) e$span, 0L)))
    statistics <- c(statistics, words("dummies", vertex_count-node_count, "span_total", sum(vapply(drawn, function(e) e$span, 0L)), "span_max", max(c(0L,spans))))
    if (length(spans)) {
        counts <- vapply(spans, function(span) paste0(span, ":", sum(vapply(drawn, function(e) e$span == span, FALSE))), "")
        statistics <- c(statistics, words("spans", counts))
    } else statistics <- c(statistics, "spans none")
    long_edges <- Filter(function(e) e$span >= 2L, drawn)
    vertical_edges <- sum(vapply(long_edges, function(e) length(unique(x[e$chain[-c(1L,length(e$chain))]])) == 1L, FALSE))
    statistics <- c(statistics, words("long_edges", length(long_edges), "vertical", vertical_edges),
        words("crossings initial", initial_crossings, "swept", reduction$best_crossings, "best_run", reduction$best_run,
            "best_sweep", reduction$best_sweep, "final", final_crossings, "brute", brute))
    segments <- unlist(gaps, recursive=FALSE)
    straight <- sum(vapply(segments, function(s) x[s[1]] == x[s[2]], FALSE))
    offset <- sum(vapply(segments, function(s) abs(x[s[1]]-x[s[2]]), 0L))
    statistics <- c(statistics, words("segments", length(segments), "straight", straight, "bent", length(segments)-straight, "offset", offset))
    text <- words("routes length", sum(vapply(drawn, function(e) e$length, 0L)), "bends", sum(vapply(drawn, function(e) e$bends, 0L)))
    if (length(drawn)) {
        longest <- drawn[[which.max(vapply(drawn, function(e) e$length, 0L))]]
        text <- words(text, "longest", edge_name(longest), longest$length)
    }
    statistics <- c(statistics, text, words("canvas width", canvas$columns, "height", canvas$rows, "crossing_cells", crossing_cells(canvas)))
    if (!is.null(graph$path)) {
        text <- words("path", graph$path)
        statistics <- c(statistics, if (is.null(path)) paste(text, "none") else words(text, "hops", length(path)-1L, ":", vertex_names[path]))
    }
    statistics <- c(statistics, "end")
    csv <- vapply(reduction$records, function(r) paste(c(graph$name,r$run,r$sweep,r$crossings), collapse=","), "")
    drawing <- c(paste0("graph ", graph$name, " ", canvas$columns, "x", canvas$rows), drawing_lines(canvas))
    list(layout=layout, statistics=statistics, csv=csv, drawing=drawing, nodes=node_count, edges=length(edges),
        dummies=vertex_count-node_count, initial_crossings=initial_crossings, final_crossings=final_crossings)
}
main <- function() {
    graphs <- read_graphs(read_defaults())
    layouts <- statistics <- character()
    crossings <- "graph,run,sweep,crossings"
    drawings <- list()
    total_names <- c("graphs", "laid_out", "errors", "nodes", "edges", "dummies", "crossings_initial", "crossings_final")
    totals <- setNames(integer(length(total_names)), total_names)
    for (graph in graphs) {
        totals["graphs"] <- totals["graphs"]+1L
        if (!is.null(graph$error)) {
            kind <- graph$error$kind
            number <- graph$error$line
            error <- c(paste("graph", graph$name), words("error", kind, "line", number), "end")
            layouts <- c(layouts, error)
            statistics <- c(statistics, error)
            drawings[[length(drawings)+1L]] <- words("graph", graph$name, "error", kind)
            totals["errors"] <- totals["errors"]+1L
            next
        }
        result <- layout_graph(graph)
        layouts <- c(layouts, result$layout)
        statistics <- c(statistics, result$statistics)
        crossings <- c(crossings, result$csv)
        drawings[[length(drawings)+1L]] <- result$drawing
        totals["laid_out"] <- totals["laid_out"]+1L
        for (key in c("nodes", "edges", "dummies")) totals[key] <- totals[key]+result[[key]]
        totals["crossings_initial"] <- totals["crossings_initial"]+result$initial_crossings
        totals["crossings_final"] <- totals["crossings_final"]+result$final_crossings
    }
    summary <- vapply(total_names, function(key) words(key, totals[[key]]), "")
    statistics <- c(statistics, words("summary", summary))
    dir.create("output", showWarnings=FALSE)
    reports <- list(layout.txt=layouts, stats.txt=statistics, crossings.csv=crossings)
    for (name in names(reports)) writeLines(reports[[name]], file.path("output",name), useBytes=TRUE)
    text <- paste(vapply(drawings, function(block) paste(block, collapse="\n"), ""), collapse="\n\n")
    connection <- file("output/drawings.txt", open="wb")
    writeChar(paste0(text, if (length(drawings)) "\n" else ""), connection, eos=NULL, useBytes=TRUE)
    close(connection)
}
main()
