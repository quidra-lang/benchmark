for (module in c("predicates","triangulation","voronoi","proximity","plot")) source(paste0(module,".R"))
number <- function(x) sprintf("%.3f",if (x == 0) 0 else x)
words <- function(sequence) paste(sequence,collapse=" ")
edge_id <- function(a,b) paste(min(a,b),max(a,b),sep=",")
read_inputs <- function() {
  lines <- readLines("input/points.txt")
  points <- list()
  rejected <- character()
  accepted <- new.env(hash=TRUE,parent=emptyenv())
  for (i in seq_along(lines)) {
    line <- lines[i]
    if (!nzchar(line) || startsWith(line,"#")) next
    fields <- strsplit(line," ",fixed=TRUE)[[1L]]
    if (length(fields) != 2L || any(!grepl("^-?[0-9]+$",fields))) {
      rejected <- c(rejected,paste("reject",i,"format"))
      next
    }
    point <- as.numeric(fields)
    key <- paste(point,collapse=",")
    if (any(point < 0 | point > 1000)) {
      rejected <- c(rejected,paste("reject",i,"range"))
    } else if (exists(key,envir=accepted,inherits=FALSE)) {
      rejected <- c(rejected,paste("reject",i,"duplicate",accepted[[key]]))
    } else {
      points[[length(points)+1L]] <- point
      accepted[[key]] <- length(points)
    }
  }
  params <- list(
      plot=c(61L,31L),
      plot_layers=c("edges","hull","sites"),
      sections="summary",
      alpha=numeric(),
      queries=character()
  )
  for (line in readLines("input/params.txt")) {
    if (!nzchar(line) || startsWith(line,"#")) next
    fields <- strsplit(line," ",fixed=TRUE)[[1L]]
    name <- fields[1L]
    if (name == "query") params$queries <- c(params$queries,substring(line,7L)) else
      params[[name]] <- if (name %in% c("plot","alpha")) as.numeric(fields[-1L]) else fields[-1L]
  }
  list(points=points,line_count=length(lines),rejected=rejected,params=params)
}
convex_layers <- function(points) {
  remaining <- seq_along(points)
  layers <- list()
  depth <- integer(length(points))
  while (length(remaining)) {
    if (length(remaining) <= 2L) {
      layer <- sort(remaining)
    } else {
      ordered <- remaining[order(vapply(points[remaining],`[`,numeric(1),1L),vapply(points[remaining],`[`,numeric(1),2L))]
      chains <- list()
      for (ordering in list(ordered,rev(ordered))) {
        chain <- integer()
        for (s in ordering) {
          while (length(chain) >= 2L && orient(
              points[[chain[length(chain)-1L]]],
              points[[tail(chain,1L)]],
              points[[s]]
          ) <= 0) chain <- head(chain,-1L)
          chain <- c(chain,s)
        }
        chains[[length(chains)+1L]] <- head(chain,-1L)
      }
      layer <- unlist(chains,use.names=FALSE)
      start <- which.min(layer)
      layer <- layer[((seq_along(layer)+start-2L) %% length(layer))+1L]
    }
    layers[[length(layers)+1L]] <- layer
    depth[layer] <- length(layers)
    remaining <- setdiff(remaining,layer)
  }
  list(layers=layers,depth=depth)
}
circle_order <- function(points,a,b,c) if (orient(
    points[[a]],
    points[[b]],
    points[[c]]
) > 0) c(a,b,c) else c(a,c,b)
circle_relation <- function(points,support,s) {
  if (length(support) == 1L) return(if (support[1L] == s) 0 else -1)
  if (length(support) == 2L) return(-dot_at(points[[s]],points[[support[1L]]],points[[support[2L]]]))
  incircle(points[[support[1L]]],points[[support[2L]]],points[[support[3L]]],points[[s]])
}
enclosing_circle <- function(points,hull) {
  support <- NULL
  for (i in seq_along(hull)) {
    a <- hull[i]
    if (!is.null(support) && circle_relation(points,support,a) >= 0) next
    support <- a
    for (j in seq_len(i-1L)) {
      b <- hull[j]
      if (circle_relation(points,support,b) >= 0) next
      support <- c(a,b)
      for (k in seq_len(j-1L)) {
        c <- hull[k]
        if (circle_relation(points,support,c) < 0) support <- circle_order(points,a,b,c)
      }
    }
  }
  boundary <- Filter(function(s) circle_relation(points,support,s) == 0,seq_along(points))
  diameter <- NULL
  for (i in seq_len(length(boundary)-1L)) {
    for (j in seq.int(i+1L,length(boundary))) {
      a <- boundary[i]
      b <- boundary[j]
      if (all(vapply(boundary,function(s) dot_at(points[[s]],points[[a]],points[[b]]) == 0,logical(1)))) {
        diameter <- c(a,b)
        break
      }
    }
    if (!is.null(diameter)) break
  }
  if (is.null(diameter)) {
    vertices <- circle_order(points,boundary[1L],boundary[2L],boundary[3L])
    a <- points[[vertices[1L]]]
    b <- points[[vertices[2L]]]
    c <- points[[vertices[3L]]]
    center <- circumcenter(a,b,c)
    radius <- squared_radius(a,b,c)
  } else {
    a <- points[[diameter[1L]]]
    b <- points[[diameter[2L]]]
    center <- c(a+b,2)
    radius <- d2(a,b)/4
  }
  list(center=center,radius=radius,sites=boundary)
}
shortest_from <- function(shortest,points,neighbors,site) {
  key <- as.character(site)
  if (!exists(key,envir=shortest,inherits=FALSE)) shortest[[key]] <- dijkstra(points,neighbors,site)
  shortest[[key]]
}
query_answer <- function(
    query,
    points,
    triangles,
    edges,
    edge_triangles,
    neighbors,
    degree,
    duals,
    gabriel,
    rng,
    mst,
    shortest
) {
  fields <- strsplit(query," ",fixed=TRUE)[[1L]]
  name <- fields[1L]
  arguments <- as.integer(fields[-1L])
  n <- length(points)
  if (name %in% c("route","path","neighbors","edge")) {
    if (any(arguments < 1L | arguments > n)) return(paste(query,"error unknown_site"))
    if (name == "edge" && arguments[1L] == arguments[2L]) return(paste(query,"error same_site"))
  }
  if (name == "locate") {
    q <- arguments
    nearest <- which.min(vapply(points,function(point) d2(point,q),numeric(1)))
    vertex <- which(vapply(points,function(point) all(point == q),logical(1)))
    position <- "outside"
    if (length(vertex)) {
      position <- paste("vertex",vertex[1L])
    } else {
      crossing <- Filter(
          function(edge) orient(points[[edge[1L]]],points[[edge[2L]]],q) == 0 && dot_at(
              q,
              points[[edge[1L]]],
              points[[edge[2L]]]
          ) < 0,
          edges
      )
      if (length(crossing)) {
        position <- paste("edge",words(crossing[[1L]]))
      } else {
        for (triangle in triangles) {
          a <- points[[triangle[1L]]]
          b <- points[[triangle[2L]]]
          c <- points[[triangle[3L]]]
          if (orient(a,b,q) > 0 && orient(b,c,q) > 0 && orient(c,a,q) > 0) {
            position <- paste("triangle",words(triangle))
            break
          }
        }
      }
    }
    answer <- paste(position,"nearest",nearest,"d2",integer_text(d2(points[[nearest]],q)))
  } else if (name == "walk") {
    walk <- visibility_walk(points,arguments,triangles,edge_triangles)
    stopping <- if (is.null(walk$outside)) paste("triangle",tail(walk$path,1L)) else paste(
        "outside",
        words(walk$outside)
    )
    answer <- paste("steps",length(walk$path)-1L,stopping,"path",words(walk$path))
  } else if (name == "natural") {
    selected <- Filter(
        function(triangle) incircle(
            points[[triangle[1L]]],
            points[[triangle[2L]]],
            points[[triangle[3L]]],
            arguments
        ) > 0,
        triangles
    )
    sites <- sort(unique(unlist(selected,use.names=FALSE)))
    answer <- paste("triangles",length(selected),"sites",if (length(sites)) words(sites) else "-")
  } else if (name == "route") {
    route <- greedy_route(points,neighbors,arguments[1L],arguments[2L])
    answer <- paste("hops",length(route$path)-1L,"length",number(route$length),"path",words(route$path))
  } else if (name == "path") {
    a <- arguments[1L]
    b <- arguments[2L]
    paths <- shortest_from(shortest,points,neighbors,a)
    path <- b
    while (tail(path,1L) != a) path <- c(path,paths$previous[tail(path,1L)])
    path <- rev(path)
    total <- paths$distances[b]
    stretch <- if (a == b) "-" else number(total/sqrt(d2(points[[a]],points[[b]])))
    answer <- paste("length",number(total),"stretch",stretch,"hops",length(path)-1L,"sites",words(path))
  } else if (name == "neighbors") {
    s <- arguments[1L]
    answer <- paste("degree",degree[s],"sites",words(neighbors[[s]]))
  } else {
    a <- arguments[1L]
    b <- arguments[2L]
    edge <- edge_id(a,b)
    if (edge %in% names(duals)) {
      yesno <- function(graph) if (edge %in% graph) "yes" else "no"
      answer <- paste(
          "delaunay len2",
          integer_text(d2(points[[a]],points[[b]])),
          "gabriel",
          yesno(gabriel),
          "rng",
          yesno(rng),
          "mst",
          yesno(mst),
          "dual",
          duals[[edge]]
      )
    } else {
      crossings <- character()
      for (pair in edges) {
        p <- points[[pair[1L]]]
        q <- points[[pair[2L]]]
        if (orient(points[[a]],points[[b]],p)*orient(
            points[[a]],
            points[[b]],
            q
        ) < 0 && orient(p,q,points[[a]])*orient(p,q,points[[b]]) < 0)
          crossings <- c(crossings,paste(pair,collapse="-"))
      }
      answer <- paste0(
          "missing crossings ",
          length(crossings),
          if (length(crossings)) paste0(" ",words(crossings)) else ""
      )
    }
  }
  paste(query,answer)
}
main <- function() {
  inputs <- read_inputs()
  points <- inputs$points
  params <- inputs$params
  n <- length(points)
  mesh <- make_triangulation(points)
  insertions <- if (n > 3L) lapply(seq.int(4L,n),function(s) insert_site(mesh,s)) else list()
  triangles <- triangles(mesh)
  triangle_count <- length(triangles)
  edge_triangles <- matrix(0L,n,n)
  for (k in seq_along(triangles)) {
    triangle <- triangles[[k]]
    edge_triangles[triangle[1L],triangle[2L]] <- k
    edge_triangles[triangle[2L],triangle[3L]] <- k
    edge_triangles[triangle[3L],triangle[1L]] <- k
  }
  coordinates <- which(upper.tri(mesh$directed) & (mesh$directed != 0L | t(mesh$directed) != 0L),arr.ind=TRUE)
  coordinates <- coordinates[order(coordinates[,1L],coordinates[,2L]),,drop=FALSE]
  edges <- lapply(seq_len(nrow(coordinates)),function(i) coordinates[i,])
  edge_keys <- vapply(edges,function(edge) edge_id(edge[1L],edge[2L]),character(1))
  e <- length(edges)
  lengths <- setNames(
      vapply(edges,function(edge) d2(points[[edge[1L]]],points[[edge[2L]]]),numeric(1)),
      edge_keys
  )
  hull_next <- hull_prev <- integer(n)
  for (edge in hull_edges(mesh)) {
    hull_next[edge[1L]] <- edge[2L]
    hull_prev[edge[2L]] <- edge[1L]
  }
  start <- which(hull_next != 0L)[1L]
  hull <- start
  while (hull_next[tail(hull,1L)] != start) hull <- c(hull,hull_next[tail(hull,1L)])
  h <- length(hull)
  hull_pairs <- lapply(seq_len(h),function(i) c(hull[i],hull[i %% h+1L]))
  perimeter <- area_hull <- 0
  for (edge in hull_pairs) {
    a <- points[[edge[1L]]]
    b <- points[[edge[2L]]]
    perimeter <- perimeter+sqrt(d2(a,b))
    area_hull <- area_hull+(a[1L]*b[2L]-b[1L]*a[2L])
  }
  adjacent <- replicate(n,integer(),simplify=FALSE)
  for (edge in edges) {
    a <- edge[1L]
    b <- edge[2L]
    adjacent[[a]] <- c(adjacent[[a]],b)
    adjacent[[b]] <- c(adjacent[[b]],a)
  }
  neighbors <- lapply(seq_len(n),function(s) neighbor_order(s,adjacent[[s]],mesh$directed,hull_next))
  degree <- lengths(neighbors)
  areas <- min_angles <- max_angles <- numeric(triangle_count)
  kinds <- character(triangle_count)
  bins <- integer(6L)
  angle_total <- 0
  for (k in seq_along(triangles)) {
    triangle <- triangles[[k]]
    a <- points[[triangle[1L]]]
    b <- points[[triangle[2L]]]
    c <- points[[triangle[3L]]]
    area <- orient(a,b,c)
    products <- c(dot_at(a,b,c),dot_at(b,c,a),dot_at(c,a,b))
    sides <- c(d2(b,c),d2(c,a),d2(a,b))
    kinds[k] <- if (any(products == 0)) "right" else if (min(products) < 0) "obtuse" else "acute"
    lo <- atan2(area,products[which.min(sides)])*180/pi
    hi <- atan2(area,products[which.max(sides)])*180/pi
    areas[k] <- area
    min_angles[k] <- lo
    max_angles[k] <- hi
    angle_total <- angle_total+lo
    bin <- floor(lo/10)+1L
    bins[bin] <- bins[bin]+1L
  }
  centers <- lapply(
      triangles,
      function(triangle) circumcenter(points[[triangle[1L]]],points[[triangle[2L]]],points[[triangle[3L]]])
  )
  radii <- vapply(
      triangles,
      function(triangle) squared_radius(points[[triangle[1L]]],points[[triangle[2L]]],points[[triangle[3L]]]),
      numeric(1)
  )
  positions <- vapply(centers,function(center) center_position(center,points,hull),character(1))
  duals <- setNames(character(e),edge_keys)
  for (i in seq_along(edges)) {
    edge <- edges[[i]]
    a <- edge[1L]
    b <- edge[2L]
    left <- edge_triangles[a,b]
    right <- edge_triangles[b,a]
    if (left != 0L && right != 0L) {
      duals[i] <- paste("segment",left,right)
    } else {
      u <- if (left != 0L) a else b
      v <- if (left != 0L) b else a
      duals[i] <- paste("ray",max(left,right),words(outward(points,u,v)))
    }
  }
  cells <- list()
  cell_total <- clip_total <- 0
  largest <- 0L
  for (s in seq_len(n)) {
    vertices <- edge_triangles[s,neighbors[[s]]]
    vertices <- vertices[vertices != 0L]
    clipped <- clipped_area(points,s,neighbors[[s]])
    bounded <- hull_next[s] == 0L
    area <- if (bounded) bounded_area(points[[s]],centers[vertices]) else 0
    incoming <- if (bounded) c(0,0) else outward(points,s,hull_next[s])
    outgoing <- if (bounded) c(0,0) else outward(points,hull_prev[s],s)
    cells[[s]] <- list(
        vertices=vertices,
        clip=clipped,
        bounded=bounded,
        area=area,
        incoming=incoming,
        outgoing=outgoing
    )
    if (bounded) {
      cell_total <- cell_total+area
      if (largest == 0L || area > cells[[largest]]$area) largest <- s
    }
    clip_total <- clip_total+clipped
  }
  nearest <- nearest_neighbors(points,neighbors)
  mutual <- Filter(function(s) s < nearest[s] && nearest[nearest[s]] == s,seq_len(n))
  closest_index <- order(lengths,seq_along(edges))[1L]
  closest <- edges[[closest_index]]
  components <- nearest_components(nearest)
  component_number <- integer(n)
  component_pairs <- list()
  for (k in seq_along(components)) {
    sites <- components[[k]]
    component_number[sites] <- k
    s <- Filter(function(s) s < nearest[s] && nearest[nearest[s]] == s,sites)[1L]
    component_pairs[[k]] <- c(s,nearest[s])
  }
  nn_edges <- unique(vapply(seq_len(n),function(s) edge_id(s,nearest[s]),character(1)))
  mst <- kruskal(points,edges)
  mst_keys <- vapply(mst,function(edge) edge_id(edge[1L],edge[2L]),character(1))
  mst_length <- 0
  for (key in mst_keys) mst_length <- mst_length+sqrt(lengths[[key]])
  gabriel <- edge_keys[vapply(edges,function(edge) is_gabriel(points,edge,mesh$directed),logical(1))]
  rng <- edge_keys[vapply(edges,function(edge) is_relative_neighbor(points,edge),logical(1))]
  graph_degrees <- list()
  for (name in c("gg","rng","mst")) {
    graph <- switch(name,gg=gabriel,rng=rng,mst=mst_keys)
    counts <- integer(n)
    for (i in which(edge_keys %in% graph)) counts[edges[[i]]] <- counts[edges[[i]]]+1L
    graph_degrees[[name]] <- counts
  }
  candidates <- which(positions == "inside")
  empty_vertex <- if (length(candidates)) candidates[which.max(radii[candidates])] else 0L
  diameter <- c(1L,2L)
  diameter2 <- -1
  for (a in seq_len(n-1L)) for (b in seq.int(a+1L,n)) {
    distance <- d2(points[[a]],points[[b]])
    if (distance > diameter2) {
      diameter <- c(a,b)
      diameter2 <- distance
    }
  }
  width <- Inf
  width_edge <- hull_pairs[[1L]]
  for (edge in hull_pairs) {
    a <- points[[edge[1L]]]
    b <- points[[edge[2L]]]
    value <- max(vapply(points[hull],function(p) orient(a,b,p),numeric(1)))/sqrt(d2(a,b))
    if (value < width) {
      width <- value
      width_edge <- edge
    }
  }
  enclosing <- enclosing_circle(points,hull)
  layers <- convex_layers(points)
  shortest <- new.env(hash=TRUE,parent=emptyenv())
  pair_count <- (n*(n-1L)) %/% 2L
  stretch_total <- stretch_length <- stretch_distance <- 0
  maximum_stretch <- -Inf
  stretch_pair <- c(1L,2L)
  for (a in seq_len(n-1L)) {
    paths <- shortest_from(shortest,points,neighbors,a)
    for (b in seq.int(a+1L,n)) {
      total <- paths$distances[b]
      distance <- sqrt(d2(points[[a]],points[[b]]))
      stretch <- total/distance
      stretch_total <- stretch_total+stretch
      if (stretch > maximum_stretch) {
        maximum_stretch <- stretch
        stretch_pair <- c(a,b)
        stretch_length <- total
        stretch_distance <- distance
      }
    }
  }
  sections <- list()
  sections$input <- c(
      paste("lines",inputs$line_count),
      paste("accepted",n),
      paste("rejected",length(inputs$rejected)),
      inputs$rejected
  )
  maximum <- "max_flips none"
  if (length(insertions)) {
    record <- insertions[[which.max(vapply(insertions,function(r) r$flips,integer(1)))]]
    maximum <- paste("max_flips",record$site,record$flips)
  }
  sections$summary <- c(paste("sites",n),paste("triangles",triangle_count),paste("edges",e),paste("hull_vertices",h),
    paste("interior_sites",n-h),paste("euler",n-e+triangle_count),paste(
        "flips",
        sum(vapply(insertions,function(r) r$flips,integer(1)))
    ),
    paste("outside_insertions",sum(vapply(insertions,function(r) r$kind == "outside",logical(1)))),maximum,
    paste("acute",sum(kinds == "acute")),paste("right",sum(kinds == "right")),paste(
        "obtuse",
        sum(kinds == "obtuse")
    ))
  sections$insertions <- paste("init",words(mesh$initial))
  for (record in insertions) {
    description <- if (record$kind == "inside") paste(
        "inside",
        words(record$containing)
    ) else paste("outside",record$visible)
    sections$insertions <- c(
        sections$insertions,
        paste(
            "insert",
            record$site,
            description,
            "flips",
            record$flips,
            "triangles",
            record$triangles,
            "hull",
            record$hull
        )
    )
  }
  sections$triangles <- character()
  for (k in seq_along(triangles)) {
    triangle <- triangles[[k]]
    a <- triangle[1L]
    b <- triangle[2L]
    c <- triangle[3L]
    adjacent_numbers <- c(edge_triangles[c,b],edge_triangles[a,c],edge_triangles[b,a])
    adjacent_text <- ifelse(adjacent_numbers == 0L,"-",as.character(adjacent_numbers))
    sections$triangles <- c(
        sections$triangles,
        paste("tri",k,words(triangle),"area2",integer_text(areas[k]),kinds[k],"adj",words(adjacent_text))
    )
  }
  sections$edges <- character()
  for (i in seq_along(edges)) {
    edge <- edges[[i]]
    a <- edge[1L]
    b <- edge[2L]
    left <- edge_triangles[a,b]
    right <- edge_triangles[b,a]
    kind <- if (left != 0L && right != 0L) "inner" else "hull"
    sections$edges <- c(
        sections$edges,
        paste(
            "edge",
            a,
            b,
            kind,
            "len2",
            integer_text(lengths[i]),
            "left",
            if (left == 0L) "-" else left,
            "right",
            if (right == 0L) "-" else right
        )
    )
  }
  sections$hull <- c(
      paste("hull_vertices",h),
      paste("order",words(hull)),
      paste("perimeter",number(perimeter)),
      paste("area2",integer_text(area_hull))
  )
  sections$convex_layers <- paste("layers",length(layers$layers))
  for (k in seq_along(layers$layers)) sections$convex_layers <- c(
      sections$convex_layers,
      paste("layer",k,"size",length(layers$layers[[k]]),"sites",words(layers$layers[[k]]))
  )
  lo <- which.min(min_angles)
  hi <- which.max(max_angles)
  sections$quality <- c(
      paste("min_angle",number(min_angles[lo]),"tri",lo),
      paste("max_angle",number(max_angles[hi]),"tri",hi),
      paste("mean_min_angle",number(angle_total/triangle_count))
  )
  for (i in seq_len(6L)-1L) sections$quality <- c(sections$quality,paste("bin",10L*i,10L*(i+1L),bins[i+1L]))
  sections$vertices <- vapply(
      c("inside","on","outside"),
      function(name) paste(name,sum(positions == name)),
      character(1)
  )
  for (k in seq_along(centers)) {
    center <- centers[[k]]
    sections$vertices <- c(
        sections$vertices,
        paste(
            "v",
            k,
            fraction(center[1L],center[3L]),
            fraction(center[2L],center[3L]),
            "r",
            number(sqrt(radii[k])),
            positions[k]
        )
    )
  }
  sections$voronoi_edges <- c(
      paste("segments",e-h),
      paste("rays",h),
      vapply(seq_along(edges),function(i) paste("ve",words(edges[[i]]),duals[i]),character(1))
  )
  sections$cells <- c(paste("bounded",n-h),paste("unbounded",h),paste("total_area",number(cell_total)),paste("clip_total",number(clip_total)),
    if (largest == 0L) "largest none" else paste("largest",largest,"area",number(cells[[largest]]$area)))
  for (s in seq_len(n)) {
    cell <- cells[[s]]
    if (cell$bounded) {
      line <- paste(
          "cell",
          s,
          "bounded",
          length(cell$vertices),
          "area",
          number(cell$area),
          "clip",
          number(cell$clip),
          "vertices",
          words(cell$vertices)
      )
    } else {
      line <- paste(
          "cell",
          s,
          "unbounded",
          length(cell$vertices),
          "clip",
          number(cell$clip),
          "from",
          words(cell$incoming),
          "vertices",
          words(cell$vertices),
          "to",
          words(cell$outgoing)
      )
    }
    sections$cells <- c(sections$cells,line)
  }
  sections$nearest <- c(
      paste("mutual_pairs",length(mutual)),
      paste("closest_pair",words(closest),"d2",integer_text(lengths[closest_index]))
  )
  for (s in seq_len(n)) sections$nearest <- c(
      sections$nearest,
      paste(
          "nn",
          s,
          nearest[s],
          "d2",
          integer_text(d2(points[[s]],points[[nearest[s]]])),
          if (nearest[nearest[s]] == s) "mutual" else "-"
      )
  )
  sections$components <- paste("components",length(components))
  for (k in seq_along(components)) sections$components <- c(
      sections$components,
      paste(
          "component",
          k,
          "size",
          length(components[[k]]),
          "pair",
          words(component_pairs[[k]]),
          "sites",
          words(components[[k]])
      )
  )
  sections$mst <- c(
      paste("edges",n-1L),
      paste("total_length",number(mst_length)),
      paste("longest",words(tail(mst,1L)[[1L]]),"len2",integer_text(lengths[[tail(mst_keys,1L)]]))
  )
  for (i in seq_along(mst)) sections$mst <- c(
      sections$mst,
      paste("mst",words(mst[[i]]),"len2",integer_text(lengths[[mst_keys[i]]]))
  )
  sections$proximity <- c(
      paste("delaunay",e),
      paste("gabriel",length(gabriel)),
      paste("rng",length(rng)),
      paste("mst",n-1L),
      paste("nn",length(nn_edges))
  )
  for (i in which(edge_keys %in% rng & !edge_keys %in% mst_keys)) sections$proximity <- c(
      sections$proximity,
      paste("rng_extra",words(edges[[i]]),"len2",integer_text(lengths[i]))
  )
  sections$degrees <- c(paste("min",min(degree)),paste("max",max(degree)))
  for (d in sort(unique(degree))) sections$degrees <- c(
      sections$degrees,
      paste("degree",d,"count",sum(degree == d))
  )
  sections$empty_circle <- paste("candidates",length(candidates))
  if (empty_vertex == 0L) {
    sections$empty_circle <- c(sections$empty_circle,"none")
  } else {
    center <- centers[[empty_vertex]]
    sections$empty_circle <- c(sections$empty_circle,paste("vertex",empty_vertex),paste("center",fraction(center[1L],center[3L]),fraction(center[2L],center[3L])),
      paste("radius",number(sqrt(radii[empty_vertex]))),paste("sites",words(triangles[[empty_vertex]])))
  }
  center <- enclosing$center
  sections$extent <- c(paste("diameter",words(diameter),"d2",integer_text(diameter2)),paste("width",number(width),"edge",words(width_edge)),
    paste(
        "enclosing_center",
        fraction(center[1L],center[3L]),
        fraction(center[2L],center[3L])
    ),paste("enclosing_radius",number(sqrt(enclosing$radius))),paste("enclosing_sites",words(enclosing$sites)))
  sections$spanner <- c(
      paste("pairs",pair_count),
      paste(
          "max_stretch",
          number(maximum_stretch),
          "pair",
          words(stretch_pair),
          "length",
          number(stretch_length),
          "distance",
          number(stretch_distance)
      ),
      paste("mean_stretch",number(stretch_total/pair_count))
  )
  sections$alpha <- character()
  for (alpha in params$alpha) {
    selected <- which(radii <= alpha)
    incidence <- setNames(integer(e),edge_keys)
    area <- 0
    for (k in selected) {
      triangle <- triangles[[k]]
      area <- area+areas[k]
      keys <- c(
          edge_id(triangle[1L],triangle[2L]),
          edge_id(triangle[2L],triangle[3L]),
          edge_id(triangle[3L],triangle[1L])
      )
      incidence[keys] <- incidence[keys]+1L
    }
    selected_edges <- which(incidence > 0L | (edge_keys %in% gabriel & lengths <= 4*alpha))
    sets <- disjoint_sets(n)
    incident <- logical(n)
    for (i in selected_edges) {
      edge <- edges[[i]]
      unite(sets,edge[1L],edge[2L])
      incident[edge] <- TRUE
    }
    boundary <- sum(incidence[selected_edges] == 1L)
    dangling <- sum(incidence[selected_edges] == 0L)
    holes <- sets$count-(n-length(selected_edges)+length(selected))
    sections$alpha <- c(sections$alpha,paste("alpha",integer_text(alpha),"triangles",length(selected),"edges",length(selected_edges),"boundary",boundary,
      "dangling",dangling,"isolated",sum(!incident),"components",sets$count,"holes",holes,"area2",integer_text(area)))
  }
  sections$sites <- character()
  for (s in seq_len(n)) sections$sites <- c(sections$sites,paste("site",s,words(points[[s]]),if (hull_next[s] != 0L) "hull" else "inner",
    "dt",degree[s],"gg",graph_degrees$gg[s],"rng",graph_degrees$rng[s],"mst",graph_degrees$mst[s],"nn",nearest[s],"comp",component_number[s],"depth",layers$depth[s]))
  sections$queries <- vapply(
      params$queries,
      function(query) query_answer(
          query,
          points,
          triangles,
          edges,
          edge_triangles,
          neighbors,
          degree,
          duals,
          gabriel,
          rng,
          mst_keys,
          shortest
      ),
      character(1)
  )
  canvas <- make_canvas(params$plot[1L],params$plot[2L])
  for (layer in params$plot_layers) {
    if (layer == "sites") {
      for (point in points) mark(canvas,point,"o")
    } else if (layer == "circle") {
      if (empty_vertex != 0L) mark(canvas,centers[[empty_vertex]],"@")
    } else {
      graph <- switch(layer,edges=edges,mst=mst,hull=hull_pairs)
      character <- switch(layer,edges=".",mst="*",hull="#")
      for (edge in graph) draw_line(canvas,points[[edge[1L]]],points[[edge[2L]]],character)
    }
  }
  sections$delaunay_plot <- framed(canvas)
  canvas <- make_canvas(params$plot[1L],params$plot[2L])
  draw_voronoi(canvas,points)
  sections$voronoi_plot <- framed(canvas)
  files <- list("triangulation.txt"=c("input","summary","insertions","triangles","edges","hull","convex_layers","quality"),
    "voronoi.txt"=c("vertices","voronoi_edges","cells"),"derived.txt"=c(
        "nearest",
        "components",
        "mst",
        "proximity",
        "degrees",
        "empty_circle",
        "extent",
        "spanner",
        "alpha",
        "sites",
        "queries"
    ),
    "plot.txt"=c("delaunay_plot","voronoi_plot"))
  dir.create("output",showWarnings=FALSE)
  for (name in names(files)) {
    lines <- character()
    for (section in params$sections) if (section %in% files[[name]]) lines <- c(
        lines,
        paste0("[",section,"]"),
        sections[[section]]
    )
    writeLines(lines,file.path("output",name),useBytes=TRUE)
  }
}
main()
