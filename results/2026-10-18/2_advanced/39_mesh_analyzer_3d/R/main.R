for (name in c("obj_io", "measure", "topology", "orientation", "repair")) source(paste0(name, ".R"))

read_parameters <- function() {
  settings <- list(snap = 1L, merge = TRUE, degenerate = TRUE, duplicates = TRUE, orient = TRUE, outward = TRUE,
                   fill_holes = 0L, keep_unused = TRUE, sections = c(
                       "summary",
                       "components"
                   ), queries = list())
  for (line in readLines(file.path("input", "params.txt"), warn = FALSE)) {
    if (!nzchar(line) || startsWith(line, "#")) next
    words <- strsplit(line, " ", fixed = TRUE)[[1L]]
    key <- words[[1L]]
    args <- words[-1L]
    if (key == "query") settings$queries[[length(settings$queries) + 1L]] <- list(
        kind = args[[1L]],
        args = as.integer(args[-1L])
    ) else if (key == "sections") settings$sections <- args else if (key %in% c("snap", "fill_holes")) settings[[key]] <- as.integer(args[[1L]]) else settings[[key]] <- args[[1L]] == "on"
  }
  settings
}
polygon_is_nonplanar <- function(polygon, snapped) {
  corners <- polygon$vertices
  origin <- snapped[corners[[1L]], ]
  total <- numeric(3L)
  for (i in seq.int(2L, length(corners) - 1L)) total <- total + cross(
      snapped[corners[[i]], ] - origin,
      snapped[corners[[i + 1L]], ] - origin
  )
  any(vapply(corners, function(v) dot(snapped[v, ] - origin, total) != 0, FALSE))
}
edge_shape <- function(key, faces, points, adjacent) {
  if (length(adjacent) != 2L) return("-")
  edge <- edge_vertices(key)
  a <- edge[[1L]]
  b <- edge[[2L]]
  first <- faces[[adjacent[[1L]]]]
  second <- faces[[adjacent[[2L]]]]
  if (has_directed(first$vertices, a, b) == has_directed(second$vertices, a, b)) return("inconsistent")
  third <- second$vertices[!(second$vertices %in% edge)][[1L]]
  signed <- dot(points[third, ] - points[first$vertices[[1L]], ], normal(first, points))
  if (signed < 0) "convex" else if (signed > 0) "concave" else "flat"
}
shape_counts <- function(component, mesh, faces, points) {
  shapes <- vapply(component$edges, function(key) edge_shape(key, faces, points, mesh$edges[[key]]), "")
  setNames(
      vapply(c("convex", "concave", "flat"), function(shape) sum(shapes == shape), 0L),
      c("convex", "concave", "flat")
  )
}
descriptors <- function(faces, points, mesh, loops, orientability, inside) {
  violations <- inconsistent_edges(faces, mesh$edges)
  lapply(mesh$components, function(comp) {
    ids <- comp$faces
    vertices <- comp$vertices
    edges <- comp$edges
    closed <- !length(comp$boundary)
    manifold <- !length(comp$nonmanifold) && !length(comp$nonmanifold_vertices)
    consistent <- !any(edges %in% violations)
    solid <- closed && manifold && consistent
    orientable <- orientability[[comp$number]]
    loop_count <- sum(vapply(loops, function(loop) loop$component == comp$number, FALSE))
    chi <- length(vertices) - length(edges) + length(ids)
    signed <- volume6(ids, faces, points)
    total_normal <- numeric(3L)
    for (id in ids) total_normal <- total_normal + normal(faces[[id]], points)
    degrees <- vapply(
        vertices,
        function(v) sum(vapply(edges, function(key) v %in% edge_vertices(key), FALSE)),
        0L
    )
    lengths <- vapply(edges, function(key) edge_length_squared(edge_vertices(key), points), 0)
    angles <- vapply(faces[ids], triangle_angle, "", points = points)
    component <- record(number = comp$number, faces = ids, vertices = vertices, edges = edges, boundary = comp$boundary,
                         nonmanifold = comp$nonmanifold, nonmanifold_vertices = comp$nonmanifold_vertices,
                         closed = closed, manifold = manifold, consistent = consistent, solid = solid, orientable = orientable, loops = loop_count, euler = chi,
                         genus = if (manifold && orientable) (2L - chi - loop_count) %/% 2L else NULL,
                         crosscaps = if (manifold && !orientable) 2L - chi - loop_count else NULL,
                         volume6 = signed, centroid = if (solid && signed != 0) centroid(
                             ids,
                             faces,
                             points,
                             signed
                         ) else NULL,
                         area = area(
                             faces[ids],
                             points
                         ), normal_sum = total_normal, bbox = bbox(vertices, points),
                         inside = if (solid) inside[[as.character(comp$number)]] else integer(), angles = angles,
                         edge_min = min(lengths), edge_max = max(lengths), valence_min = min(degrees), valence_max = max(degrees))
    component
  })
}
analyze_source <- function(source, settings) {
  snapping <- snapped_vertices(source$vertices, settings$snap)
  snapped <- snapping$points
  representative <- representatives(snapped, settings$merge)
  triangles <- split_polygons(source$polygons)
  cleanup <- cleaned_faces(triangles, snapped, representative, settings$degenerate, settings$duplicates)
  remapping <- remap_vertices(source$vertices, snapped, representative, cleanup$faces, settings$keep_unused)
  points <- remapping$points
  cleaned <- remapping$faces
  initial <- lapply(cleaned, function(face) face$vertices)
  before <- analyze_mesh(cleaned)
  initial_inconsistent <- inconsistent_edges(cleaned, before$edges)
  if (settings$orient) repair_orientation(cleaned, before$edges)
  after <- inconsistent_edges(cleaned, before$edges)
  loops <- boundary_loops(cleaned, before, has_directed)
  permitted <- vapply(
      Filter(
          function(component) !length(component$nonmanifold) && !any(component$edges %in% after),
          before$components
      ),
      function(component) component$number,
      0L
  )
  filling <- fill_loops(cleaned, loops, settings$fill_holes, permitted)
  faces <- filling$faces
  mesh <- analyze_mesh(faces)
  violations <- inconsistent_edges(faces, mesh$edges)
  solids <- Filter(
      function(comp) !length(comp$boundary) && !length(comp$nonmanifold) && !length(comp$nonmanifold_vertices) && !any(comp$edges %in% violations),
      mesh$components
  )
  inside <- list()
  for (comp in solids) {
    containers <- integer()
    for (other in solids) {
      if (identical(comp, other)) next
      samples <- comp$vertices[!(comp$vertices %in% other$vertices)]
      if (length(samples) && winding_number(
          other$faces,
          faces,
          points,
          points[samples[[1L]], ]
      ) != 0L) containers <- c(containers, other$number)
    }
    inside[[as.character(comp$number)]] <- sort(containers)
  }
  outward_components <- 0L
  if (settings$outward) {
    for (comp in solids) {
      signed <- volume6(comp$faces, faces, points)
      depth <- length(inside[[as.character(comp$number)]])
      if (signed != 0 && ((depth %% 2L == 0L && signed < 0) || (depth %% 2L == 1L && signed > 0))) {
        for (id in comp$faces) flip(faces[[id]])
        outward_components <- outward_components + 1L
      }
    }
  }
  flipped <- sum(vapply(seq_along(initial), function(i) !identical(faces[[i]]$vertices, initial[[i]]), FALSE))
  final_loops <- boundary_loops(faces, mesh, has_directed)
  components <- descriptors(faces, points, mesh, final_loops, orientable_components(faces, mesh), inside)
  nonplanar <- vapply(
      Filter(function(polygon) polygon_is_nonplanar(polygon, snapped), source$polygons),
      function(polygon) polygon$number,
      0L
  )
  groups <- unique(vapply(source$polygons, function(polygon) polygon$group, ""))
  if (length(filling$added)) groups <- c(groups, "fill")
  original_to_reps <- split(seq_along(representative), representative)
  list(source = source, settings = settings, snapped_list = snapping$changed, representative = representative, original_to_reps = original_to_reps,
       triangles = triangles, removed = cleanup$removed, points = points, faces = faces, renumber = remapping$numbers,
       initial_faces = length(cleaned), mesh_before = before, initial_inconsistent = initial_inconsistent, inconsistent_after = after,
       loops_before = loops, added = filling$added, mesh = mesh, components = components, outward_components = outward_components,
       flipped_faces = flipped, nonplanar = nonplanar, group_order = groups)
}
yes <- function(value) if (value) "yes" else "no"
listing <- function(items) {
  if (!length(items)) return("-")
  if (is.numeric(items)) paste(sprintf("%.0f", items), collapse = " ") else paste(items, collapse = " ")
}
optional <- function(value) if (is.null(value)) "-" else as.character(value)
section_summary <- function(data) {
  source <- data$source
  sizes <- vapply(source$polygons, function(p) length(p$vertices), 0L)
  removals <- vapply(data$removed, `[[`, "", "reason")
  lines <- c("[summary]", paste("lines", source$lines), paste("vertices", nrow(source$vertices)), paste("polygons", length(source$polygons)),
             paste("errors", length(source$errors)), paste("ignored", source$ignored), paste(
                 "nonplanar_polygons",
                 length(data$nonplanar)
             ))
  for (size in sort(unique(sizes))) lines <- c(lines, paste("polygon_size", size, sum(sizes == size)))
  c(lines, paste("triangles", length(data$triangles)), paste("snapped", length(data$snapped_list)), paste("merged", sum(data$representative != seq_along(data$representative))),
    paste("removed_repeated", sum(removals == "repeated")), paste("removed_zero_area", sum(removals == "zero_area")), paste(
        "removed_duplicate",
        sum(removals == "duplicate")
    ),
    paste("faces", data$initial_faces), paste(
        "inconsistent_before",
        length(data$initial_inconsistent)
    ), paste("flipped_faces", data$flipped_faces),
    paste("outward_components", data$outward_components), paste("boundary_loops", length(data$loops_before)), paste(
        "holes_filled",
        sum(vapply(data$loops_before, function(loop) loop$filled, FALSE))
    ),
    paste("fill_faces", length(data$added)), paste("final_vertices", nrow(data$points)), paste("final_faces", length(data$faces)), paste(
        "components",
        length(data$components)
    ),
    paste(
        "solids",
        sum(vapply(data$components, function(comp) comp$solid, FALSE))
    ), paste("total_area", format_real(area(data$faces, data$points))),
    paste(
        "total_volume",
        format_fraction(
            sum(vapply(Filter(function(comp) comp$solid, data$components), function(comp) comp$volume6, 0)),
            6
        )
    ))
}
section_warnings <- function(data) c(
    "[warnings]",
    vapply(data$source$errors, function(error) paste("line", error[[1L]], error[[2L]]), "")
)
section_cleanup <- function(data) {
  lines <- c("[cleanup]", paste("snapped", length(data$snapped_list)))
  for (change in data$snapped_list) lines <- c(
      lines,
      paste("snap", change$number, listing(change$before), "to", listing(change$after))
  )
  lines <- c(lines, paste("merged", sum(data$representative != seq_along(data$representative))))
  for (original in sort(as.integer(names(data$original_to_reps)))) {
    members <- data$original_to_reps[[as.character(original)]]
    if (length(members) > 1L) {
      new <- if (as.character(original) %in% names(data$renumber)) as.character(data$renumber[[as.character(original)]]) else "-"
      lines <- c(lines, paste("merge", new, listing(members)))
    }
  }
  lines <- c(lines, paste("removed", length(data$removed)))
  for (removed in data$removed) {
    face <- removed$face
    lines <- c(
        lines,
        paste("remove", face$triangle, "polygon", face$polygon, "line", face$line, removed$reason)
    )
  }
  lines
}
section_components <- function(data) {
  lines <- character()
  for (comp in data$components) {
    face_groups <- unique(vapply(data$faces[comp$faces], function(face) face$group, ""))
    groups <- data$group_order[data$group_order %in% face_groups]
    shapes <- shape_counts(comp, data$mesh, data$faces, data$points)
    lines <- c(lines, paste0("[component ", comp$number, "]"), paste("groups", listing(groups)), paste("faces", length(comp$faces)), paste("vertices", length(comp$vertices)),
               paste("edges", length(comp$edges)), paste("boundary_edges", length(comp$boundary)), paste(
                   "nonmanifold_edges",
                   length(comp$nonmanifold)
               ),
               paste(
                   "nonmanifold_vertices",
                   length(comp$nonmanifold_vertices)
               ), paste("boundary_loops", comp$loops))
    for (key in c(
        "closed",
        "manifold",
        "orientable",
        "consistent",
        "solid"
    )) lines <- c(lines, paste(key, yes(comp[[key]])))
    lines <- c(lines, paste("euler", comp$euler), if (!is.null(comp$genus)) paste("genus", comp$genus) else if (!is.null(comp$crosscaps)) paste("crosscaps", comp$crosscaps) else "genus -",
               paste(
                   "volume",
                   if (comp$solid) format_fraction(comp$volume6, 6) else "-"
               ), paste("area", format_real(comp$area)), paste("normal_sum", listing(comp$normal_sum)),
               paste("bbox", listing(comp$bbox)), paste("inside", listing(comp$inside)), paste(
                   "centroid",
                   if (is.null(comp$centroid)) "-" else listing(comp$centroid)
               ))
    for (shape in c("convex", "concave", "flat")) lines <- c(lines, paste(shape, shapes[[shape]]))
    for (angle in c("acute", "right", "obtuse")) lines <- c(lines, paste(angle, sum(comp$angles == angle)))
    lines <- c(
        lines,
        paste("edge_len2", listing(c(comp$edge_min, comp$edge_max))),
        paste("valence", comp$valence_min, comp$valence_max)
    )
  }
  lines
}
section_groups <- function(data) {
  lines <- character()
  for (group in data$group_order) {
    polygons <- Filter(function(p) p$group == group, data$source$polygons)
    assigned <- which(vapply(data$faces, function(face) face$group == group, FALSE))
    components <- sort(unique(data$mesh$face_components[assigned]))
    lines <- c(lines, paste0("[group ", group, "]"), paste("polygons", length(polygons)), paste("triangles", sum(vapply(data$triangles, function(t) t$group == group, FALSE))),
               paste(
                   "nonplanar",
                   sum(vapply(polygons, function(p) p$number %in% data$nonplanar, FALSE))
               ), paste("faces", length(assigned)),
               paste(
                   "area",
                   format_real(area(data$faces[assigned], data$points))
               ), paste("components", listing(components)))
  }
  lines
}
section_contacts <- function(data) {
  lines <- "[contacts]"
  comps <- data$components
  points <- data$points
  if (length(comps) < 2L) return(lines)
  for (i in seq_len(length(comps) - 1L)) for (j in seq.int(i + 1L, length(comps))) {
    first <- comps[[i]]
    second <- comps[[j]]
    if (!all(first$bbox[1L:3L] <= second$bbox[4L:6L] & second$bbox[1L:3L] <= first$bbox[4L:6L])) next
    shared <- length(intersect(first$vertices, second$vertices))
    gap <- Inf
    for (a in first$vertices) for (b in second$vertices) if (a != b) gap <- min(
        gap,
        dot(points[a, ] - points[b, ], points[a, ] - points[b, ])
    )
    lines <- c(lines, paste("contact", i, j, "shared", shared, "gap2", listing(gap)))
  }
  lines
}
section_edges <- function(data) {
  mesh <- data$mesh
  faces <- data$faces
  points <- data$points
  lengths <- vapply(mesh$edge_order, function(key) edge_length_squared(edge_vertices(key), points), 0)
  shapes <- vapply(mesh$edge_order, function(key) edge_shape(key, faces, points, mesh$edges[[key]]), "")
  adjacent <- lengths(mesh$edges)
  shortest <- which.min(lengths)
  longest <- which.max(lengths)
  lines <- c("[edges]", paste("edges", length(mesh$edges)), paste("boundary", sum(adjacent == 1L)), paste("manifold", sum(adjacent == 2L)),
             paste("nonmanifold", sum(adjacent >= 3L)), paste("max_faces", max(adjacent)))
  for (shape in c(
      "convex",
      "concave",
      "flat",
      "inconsistent"
  )) lines <- c(lines, paste(shape, sum(shapes == shape)))
  c(lines, paste("shortest", listing(edge_vertices(mesh$edge_order[[shortest]])), "len2", listing(lengths[[shortest]])),
    paste("longest", listing(edge_vertices(mesh$edge_order[[longest]])), "len2", listing(lengths[[longest]])))
}
degrees <- function(mesh, n) {
  values <- integer(n)
  for (key in mesh$edge_order) {
    edge <- edge_vertices(key)
    values[edge] <- values[edge] + 1L
  }
  values
}
section_valence <- function(data) {
  degree <- degrees(data$mesh, nrow(data$points))
  degree <- degree[degree > 0L]
  lines <- c("[valence]", paste("used", length(degree)), paste("isolated", nrow(data$points) - length(degree)), paste("min", min(degree)), paste("max", max(degree)),
             paste("mean", format_fraction(sum(degree), length(degree))))
  for (value in sort(unique(degree))) lines <- c(lines, paste("degree", value, sum(degree == value)))
  lines
}
find_vertex_path <- function(start, stop, mesh, n) {
  graph <- vector("list", n)
  for (key in mesh$edge_order) {
    edge <- edge_vertices(key)
    graph[[edge[[1L]]]] <- c(graph[[edge[[1L]]]], edge[[2L]])
    graph[[edge[[2L]]]] <- c(graph[[edge[[2L]]]], edge[[1L]])
  }
  parent <- rep.int(-1L, n)
  parent[[start]] <- 0L
  queue <- start
  index <- 1L
  while (index <= length(queue)) {
    current <- queue[[index]]
    index <- index + 1L
    for (neighbor in sort(graph[[current]])) if (parent[[neighbor]] == -1L) {
      parent[[neighbor]] <- current
      queue <- c(queue, neighbor)
    }
  }
  if (parent[[stop]] == -1L) return(NULL)
  path <- integer()
  current <- stop
  while (current != 0L) {
    path <- c(current, path)
    current <- parent[[current]]
  }
  path
}
answer_query <- function(kind, args, data) {
  points <- data$points
  faces <- data$faces
  mesh <- data$mesh
  if (kind == "vertex") {
    number <- args[[1L]]
    if (number < 1L || number > nrow(points)) return(paste("vertex", number, "invalid"))
    containing <- which(vapply(faces, function(face) number %in% face$vertices, FALSE))
    degree <- sum(vapply(mesh$edge_order, function(key) number %in% edge_vertices(key), FALSE))
    fans <- mesh$fans[[as.character(number)]]
    boundary <- any(vapply(
        mesh$edge_order,
        function(key) number %in% edge_vertices(key) && length(mesh$edges[[key]]) == 1L,
        FALSE
    ))
    components <- sort(unique(mesh$face_components[containing]))
    return(paste(
        "vertex",
        number,
        "at",
        listing(points[number, ]),
        "faces",
        length(containing),
        "valence",
        degree,
        "fans",
        length(fans),
        "boundary",
        yes(boundary),
        "components",
        listing(components)
    ))
  }
  if (kind == "face") {
    number <- args[[1L]]
    if (number < 1L || number > length(faces)) return(paste("face", number, "invalid"))
    face <- faces[[number]]
    neighbors <- vapply(triangle_edges(face$vertices), function(edge) {
      participating <- mesh$edges[[key_edge(edge[[1L]], edge[[2L]])]]
      if (length(participating) == 1L) "-" else if (length(participating) >= 3L) "*" else as.character(participating[participating != number][[1L]])
    }, "")
    polygon <- if (face$polygon == 0L) "-" else as.character(face$polygon)
    line <- if (face$line == 0L) "-" else as.character(face$line)
    return(paste("face", number, "vertices", listing(face$vertices), "group", face$group, "polygon", polygon, "line", line, "component", mesh$face_components[[number]],
                 "normal", listing(normal(face, points)), "area", format_real(area(
                     list(face),
                     points
                 )), "neighbors", listing(neighbors)))
  }
  if (kind == "edge") {
    key <- key_edge(args[[1L]], args[[2L]])
    edge <- edge_vertices(key)
    adjacent <- mesh$edges[[key]]
    if (is.null(adjacent)) return(paste("edge", listing(edge), "none"))
    category <- if (length(adjacent) == 1L) "boundary" else if (length(adjacent) == 2L) "manifold" else "nonmanifold"
    return(paste(
        "edge",
        listing(edge),
        "faces",
        listing(adjacent),
        "kind",
        category,
        "shape",
        edge_shape(key, faces, points, adjacent),
        "len2",
        listing(edge_length_squared(edge, points))
    ))
  }
  if (kind == "point") {
    inside <- integer()
    total <- 0L
    for (component in data$components) {
      if (!component$solid) next
      winding <- winding_number(component$faces, faces, points, as.numeric(args))
      if (winding != 0L) {
        inside <- c(inside, component$number)
        total <- total + winding
      }
    }
    return(paste("point", listing(args), "inside", listing(inside), "winding", total))
  }
  if (kind == "path") {
    start <- args[[1L]]
    stop <- args[[2L]]
    if (start < 1L || start > nrow(points) || stop < 1L || stop > nrow(points)) return(paste(
        "path",
        start,
        stop,
        "invalid"
    ))
    path <- find_vertex_path(start, stop, mesh, nrow(points))
    return(if (is.null(path)) paste("path", start, stop, "none") else paste(
        "path",
        start,
        stop,
        "hops",
        length(path) - 1L,
        "vertices",
        listing(path)
    ))
  }
  scores <- vapply(faces, function(face) dot(normal(face, points), args), 0)
  silhouette <- sum(vapply(mesh$edges, function(adjacent) {
    length(adjacent) == 2L && ((scores[[adjacent[[1L]]]] > 0 && scores[[adjacent[[2L]]]] < 0) || (scores[[adjacent[[1L]]]] < 0 && scores[[adjacent[[2L]]]] > 0))
  }, FALSE))
  paste(
      "view",
      listing(args),
      "front",
      sum(scores > 0),
      "back",
      sum(scores < 0),
      "side",
      sum(scores == 0),
      "silhouette",
      silhouette
  )
}
section_queries <- function(data) c(
    "[queries]",
    vapply(data$settings$queries, function(query) answer_query(query$kind, query$args, data), "")
)
boundaries_report <- function(data) {
  mesh <- data$mesh_before
  lines <- paste("loops", length(data$loops_before))
  for (loop in data$loops_before) lines <- c(lines, paste("loop", loop$number, "component", loop$component, "length", loop$length, loop$kind,
                                                        if (loop$filled) "filled" else "kept", "vertices", listing(loop$vertices)))
  nonmanifold <- mesh$edge_order[lengths(mesh$edges) >= 3L]
  lines <- c(lines, paste("nonmanifold_edges", length(nonmanifold)))
  for (key in nonmanifold) lines <- c(
      lines,
      paste("edge", listing(edge_vertices(key)), "faces", listing(mesh$edges[[key]]))
  )
  lines <- c(lines, paste("nonmanifold_vertices", length(mesh$nonmanifold_vertices)))
  for (vertex in mesh$nonmanifold_vertices) {
    fans <- mesh$fans[[as.character(vertex)]]
    components <- sort(unique(mesh$face_components[unlist(fans, use.names = FALSE)]))
    lines <- c(lines, paste("vertex", vertex, "fans", length(fans), "components", listing(components)))
  }
  lines <- c(lines, paste("inconsistent_edges", length(data$inconsistent_after)))
  for (key in data$inconsistent_after) lines <- c(
      lines,
      paste("edge", listing(edge_vertices(key)), "faces", listing(mesh$edges[[key]]))
  )
  lines
}
csv_components <- function(data) {
  lines <- "component,faces,vertices,closed,euler,genus,volume6,area"
  for (comp in data$components) {
    row <- c(comp$number, length(comp$faces), length(comp$vertices), yes(comp$closed), comp$euler, optional(comp$genus),
             if (comp$solid) sprintf("%.0f", comp$volume6) else "-", format_real(comp$area))
    lines <- c(lines, paste(row, collapse = ","))
  }
  lines
}
main <- function() {
  source <- read_obj()
  settings <- read_parameters()
  data <- analyze_source(source, settings)
  actions <- list(summary = section_summary, warnings = section_warnings, cleanup = section_cleanup, components = section_components,
                  groups = section_groups, contacts = section_contacts, edges = section_edges, valence = section_valence, queries = section_queries)
  report <- character()
  for (section in settings$sections) report <- c(report, actions[[section]](data))
  outputs <- list(
      "report.txt" = report,
      "components.csv" = csv_components(data),
      "boundaries.txt" = boundaries_report(data),
      "repaired.obj" = write_repaired_obj(data$points, data$faces)
  )
  dir.create("output", showWarnings = FALSE)
  for (name in names(outputs)) writeLines(outputs[[name]], file.path("output", name), useBytes = TRUE)
}
main()
