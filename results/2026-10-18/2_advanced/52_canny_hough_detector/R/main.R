for (module in c("pgm_io","filters","canny","hough","corners")) source(paste0(module,".R"))
POLYGON_KINDS <- c(
    "equilateral_triangle",
    "right_triangle",
    "triangle",
    "square",
    "rectangle",
    "parallelogram",
    "trapezoid",
    "quadrilateral"
)
cross2 <- function(a,b) a[1L]*b[2L]-a[2L]*b[1L]
dot2 <- function(a,b) a[1L]*b[1L]+a[2L]*b[2L]
difference <- function(a,b) a-b
chebyshev <- function(a,b) max(abs(a-b))
angle_difference <- function(a,b) min(abs(a-b),180L-abs(a-b))
nearest_integer <- function(n,d) {
  if (d < 0) {
    n <- -n
    d <- -d
  }
  (2*n+d) %/% (2*d)
}
bresenham <- function(start,ending) {
  x <- start[1L]
  y <- start[2L]
  x1 <- ending[1L]
  y1 <- ending[2L]
  dx <- abs(x1-x)
  dy <- -abs(y1-y)
  sx <- if (x < x1) 1L else -1L
  sy <- if (y < y1) 1L else -1L
  error <- dx+dy
  points <- list()
  repeat {
    points[[length(points)+1L]] <- c(x,y)
    if (x == x1 && y == y1) break
    twice <- 2L*error
    if (twice >= dy) {
      error <- error+dy
      x <- x+sx
    }
    if (twice <= dx) {
      error <- error+dx
      y <- y+sy
    }
  }
  points
}
circle_gaps <- function(center,outline,edges) {
  half <- function(p) if (p[2L] > 0L || (p[2L] == 0L && p[1L] > 0L)) 0L else 1L
  earlier <- function(a,b) if (half(a) != half(b)) half(a) < half(b) else cross2(a,b) > 0L
  ordered <- list()
  for (point in outline) {
    position <- 1L
    while (position <= length(ordered) && !earlier(point,ordered[[position]])) position <- position+1L
    ordered <- append(ordered,list(point),after=position-1L)
  }
  hits <- vapply(
      ordered,
      function(offset) has_edge(edges,center[1L]+offset[1L],center[2L]+offset[2L]),
      logical(1)
  )
  n <- length(hits)
  if (all(hits)) return(list(gap=0L,arcs=1L))
  if (!any(hits)) return(list(gap=n,arcs=0L))
  arcs <- sum(hits & !hits[c(n,seq_len(n-1L))])
  maximum_gap <- run <- 0L
  for (hit in c(hits,hits)) {
    run <- if (hit) 0L else run+1L
    maximum_gap <- max(maximum_gap,run)
  }
  list(gap=min(maximum_gap,n),arcs=arcs)
}
on_circumference <- function(point,circle) {
  offset <- point-circle$center
  squared <- dot2(offset,offset)
  (circle$radius-1L)^2 <= squared && squared <= (circle$radius+1L)^2
}
selected_circles <- function(outlines,peaks,edges,maximum_count) {
  circles <- list()
  for (cell in head(peaks,maximum_count)) {
    center <- c(cell$x,cell$y)
    outline <- outlines[[as.character(cell$radius)]]
    gaps <- circle_gaps(center,outline,edges)
    circles[[length(circles)+1L]] <- list(type="circle",number=length(circles)+1L,center=center,radius=cell$radius,votes=cell$votes,
      outline=outline,outline_count=length(outline),gap=gaps$gap,arcs=gaps$arcs)
  }
  circle_edges <- matrix(FALSE,nrow(edges),ncol(edges))
  for (point in raster_points(edges)) if (any(vapply(
      circles,
      function(circle) on_circumference(point,circle),
      logical(1)
  ))) circle_edges[point[2L]+1L,point[1L]+1L] <- TRUE
  list(circles=circles,circle_edges=circle_edges,line_edges=edges & !circle_edges)
}
extract_segments <- function(peaks,line_edges,trig,params) {
  used <- matrix(FALSE,nrow(line_edges),ncol(line_edges))
  lines <- segments <- list()
  points <- raster_points(line_edges)
  for (peak in peaks) {
    if (length(lines) >= params$hough_max_lines[1L]) break
    cosine <- trig[peak$theta+1L,1L]
    sine <- trig[peak$theta+1L,2L]
    available <- Filter(
        function(p) !has_edge(used,p[1L],p[2L]) && abs(rho(
            p,
            peak$theta,
            trig,
            params$hough_rho_step[1L]
        )-peak$rho) <= params$segment_tolerance[1L],
        points
    )
    positions <- vapply(available,function(p) p[2L]*cosine-p[1L]*sine,numeric(1))
    ordering <- order(positions,vapply(available,`[`,integer(1),1L),vapply(available,`[`,integer(1),2L))
    available <- available[ordering]
    groups <- list()
    previous <- NULL
    for (point in available) {
      u <- point[2L]*cosine-point[1L]*sine
      if (!length(groups) || u-previous > params$segment_max_gap[1L]*16384) groups[[length(groups)+1L]] <- list()
      last <- length(groups)
      groups[[last]][[length(groups[[last]])+1L]] <- point
      previous <- u
    }
    pending <- Filter(
        function(group) chebyshev(group[[1L]],tail(group,1L)[[1L]])+1L >= params$segment_min_length[1L],
        groups
    )
    if (!length(pending)) next
    numbers <- integer()
    for (group in pending) {
      number <- length(segments)+1L
      start <- group[[1L]]
      ending <- tail(group,1L)[[1L]]
      segments[[number]] <- list(
          number=number,
          line=length(lines)+1L,
          start=start,
          ending=ending,
          length=chebyshev(start,ending)+1L,
          pixels=length(group),
          points=group,
          theta=peak$theta
      )
      numbers <- c(numbers,number)
      for (point in group) used[point[2L]+1L,point[1L]+1L] <- TRUE
    }
    peak$number <- length(lines)+1L
    peak$segments <- numbers
    lines[[length(lines)+1L]] <- peak
  }
  list(lines=lines,segments=segments,used=used)
}
join_key <- function(a,b) paste(min(a,b),max(a,b),sep=",")
build_junctions <- function(segments,minimum_angle,maximum_distance) {
  joins <- list()
  if (length(segments) < 2L) return(joins)
  for (a in seq_len(length(segments)-1L)) for (b in seq.int(a+1L,length(segments))) {
    sa <- segments[[a]]
    sb <- segments[[b]]
    if (angle_difference(sa$theta,sb$theta) < minimum_angle) next
    da <- sa$ending-sa$start
    db <- sb$ending-sb$start
    den <- cross2(da,db)
    if (den == 0L) next
    lambda <- cross2(sb$start-sa$start,db)
    point <- c(
        nearest_integer(sa$start[1L]*den+lambda*da[1L],den),
        nearest_integer(sa$start[2L]*den+lambda*da[2L],den)
    )
    start_a <- chebyshev(sa$start,point)
    finish_a <- chebyshev(sa$ending,point)
    start_b <- chebyshev(sb$start,point)
    finish_b <- chebyshev(sb$ending,point)
    if (max(min(start_a,finish_a),min(start_b,finish_b)) <= maximum_distance) joins[[join_key(a,b)]] <-
      list(
          point=point,
          a=a,
          b=b,
          end_a=if (start_a <= finish_a) 1L else 2L,
          end_b=if (start_b <= finish_b) 1L else 2L
      )
  }
  joins
}
joined <- function(a,b,joins) joins[[join_key(a,b)]]
junction_end <- function(join,s) if (join$a == s) join$end_a else join$end_b
polygon_cycles <- function(segments,joins) {
  graph <- replicate(length(segments),integer(),simplify=FALSE)
  for (join in joins) {
    graph[[join$a]] <- c(graph[[join$a]],join$b)
    graph[[join$b]] <- c(graph[[join$b]],join$a)
  }
  graph <- lapply(graph,sort)
  polygons <- list()
  for (k in c(3L,4L)) {
    found <- list()
    for (first_segment in seq_along(segments)) {
      extend <- function(sequence) {
        if (length(sequence) == k) {
          if (sequence[2L] >= tail(sequence,1L) || is.null(joined(
              tail(sequence,1L),
              first_segment,
              joins
          ))) return(invisible(NULL))
          vertices <- list()
          for (i in seq_len(k)) {
            previous <- sequence[((i-2L) %% k)+1L]
            current <- sequence[i]
            following <- sequence[(i %% k)+1L]
            entry <- joined(previous,current,joins)
            exit <- joined(current,following,joins)
            if (junction_end(entry,current) == junction_end(exit,current)) return(invisible(NULL))
            vertices[[i]] <- entry$point
          }
          turns <- vapply(
              seq_len(k),
              function(i) cross2(
                  vertices[[(i %% k)+1L]]-vertices[[i]],
                  vertices[[((i+1L) %% k)+1L]]-vertices[[(i %% k)+1L]]
              ),
              numeric(1)
          )
          if (!(all(turns > 0L) || all(turns < 0L))) return(invisible(NULL))
          found[[length(found)+1L]] <<- list(segments=sequence,vertices=vertices)
          return(invisible(NULL))
        }
        for (candidate in graph[[tail(sequence,1L)]]) if (candidate > first_segment && !candidate %in% sequence) extend(c(
            sequence,
            candidate
        ))
      }
      extend(first_segment)
    }
    if (length(found)) {
      keys <- do.call(rbind,lapply(found,function(p) p$segments))
      ordering <- do.call(order,c(lapply(seq_len(k),function(i) keys[,i]),list(method="radix")))
      for (p in found[ordering]) {
        p$type <- "polygon"
        p$number <- length(polygons)+1L
        polygons[[length(polygons)+1L]] <- p
      }
    }
  }
  polygons
}
polygon_properties <- function(p,segments,edges,params) {
  k <- length(p$segments)
  vertices <- p$vertices
  theta <- vapply(segments[p$segments],function(segment) segment$theta,integer(1))
  angles <- lengths <- supports <- integer(k)
  sigma <- 0L
  for (i in seq_len(k)) {
    previous <- vertices[[((i-2L) %% k)+1L]]
    current <- vertices[[i]]
    following <- vertices[[(i %% k)+1L]]
    phi <- angle_difference(theta[((i-2L) %% k)+1L],theta[i])
    if (dot2(previous-current,following-current) < 0L) phi <- 180L-phi
    angles[i] <- phi
    side <- following-current
    lengths[i] <- dot2(side,side)
    points <- bresenham(current,following)
    hits <- sum(vapply(points,function(point) any(vapply(seq.int(-1L,1L),function(dx) any(vapply(seq.int(-1L,1L),
      function(dy) has_edge(edges,point[1L]+dx,point[2L]+dy),logical(1))),logical(1))),logical(1)))
    supports[i] <- (100L*hits) %/% length(points)
    sigma <- sigma+cross2(current,following)
  }
  tolerance <- params$angle_tolerance[1L]
  if (k == 3L) {
    kind <- if (all(abs(angles-60L) <= tolerance)) "equilateral_triangle" else if (any(abs(angles-90L) <= tolerance)) "right_triangle" else "triangle"
  } else {
    first_parallel <- angle_difference(theta[1L],theta[3L]) <= tolerance
    second_parallel <- angle_difference(theta[2L],theta[4L]) <= tolerance
    kind <- if (!first_parallel && !second_parallel) "quadrilateral" else if (first_parallel != second_parallel) "trapezoid" else
      if (any(abs(angles-90L) > tolerance)) "parallelogram" else if (100*(max(lengths)-min(lengths)) <= params$square_tolerance[1L]*max(lengths)) "square" else "rectangle"
  }
  p$angles <- angles
  p$lengths <- lengths
  p$supports <- supports
  p$sigma <- sigma
  p$kind <- kind
  p$vertex_corners <- integer(k)
  p
}
representatives <- function(shape) {
  if (shape$type == "polygon") return(shape$vertices)
  x <- shape$center[1L]
  y <- shape$center[2L]
  r <- shape$radius
  list(c(x+r,y),c(x,y+r),c(x-r,y),c(x,y-r))
}
contains_pixel <- function(shape,point) {
  if (shape$type == "circle") {
    offset <- point-shape$center
    return(dot2(offset,offset) <= shape$radius^2)
  }
  vertices <- shape$vertices
  for (i in seq_along(vertices)) {
    value <- cross2(vertices[[i %% length(vertices)+1L]]-vertices[[i]],point-vertices[[i]])
    if (value != 0L && ((value > 0L) != (shape$sigma > 0L))) return(FALSE)
  }
  TRUE
}
measure_shapes <- function(shapes,image,margin) {
  height <- nrow(image)
  width <- ncol(image)
  for (i in seq_along(shapes)) {
    shape <- shapes[[i]]
    points <- representatives(shape)
    xs <- vapply(points,`[`,numeric(1),1L)
    ys <- vapply(points,`[`,numeric(1),2L)
    x0 <- max(0L,min(xs)-margin)
    x1 <- min(width-1L,max(xs)+margin)
    y0 <- max(0L,min(ys)-margin)
    y1 <- min(height-1L,max(ys)+margin)
    inner_count <- outer_count <- inner_total <- outer_total <- 0L
    if (x0 <= x1 && y0 <= y1) for (y in seq.int(y0,y1)) for (x in seq.int(x0,x1)) {
      if (contains_pixel(shape,c(x,y))) {
        inner_count <- inner_count+1L
        inner_total <- inner_total+image[y+1L,x+1L]
      } else {
        outer_count <- outer_count+1L
        outer_total <- outer_total+image[y+1L,x+1L]
      }
    }
    mean <- if (inner_count == 0L) 0L else inner_total %/% inner_count
    shape$pixel_count <- inner_count
    shape$mean <- mean
    shape$contrast <- mean-if (outer_count == 0L) 0L else outer_total %/% outer_count
    shape$enclosing <- 0L
    shapes[[i]] <- shape
  }
  for (i in seq_along(shapes)) {
    shape <- shapes[[i]]
    parents <- Filter(function(j) j != i && shapes[[j]]$pixel_count > shape$pixel_count &&
      all(vapply(
          representatives(shape),
          function(point) contains_pixel(shapes[[j]],point),
          logical(1)
      )),seq_along(shapes))
    if (length(parents)) {
      ordering <- order(vapply(shapes[parents],function(parent) parent$pixel_count,integer(1)),parents)
      shapes[[i]]$enclosing <- parents[ordering[1L]]
    }
  }
  shapes
}
match_corners <- function(corners,polygons,segments,maximum_distance) {
  for (i in seq_along(corners)) {
    corner <- corners[[i]]
    point <- c(corner$x,corner$y)
    vertices <- list()
    for (p in polygons) for (j in seq_along(p$vertices)) {
      distance <- chebyshev(point,p$vertices[[j]])
      if (distance <= maximum_distance) vertices[[length(vertices)+1L]] <- c(distance,p$number,j)
    }
    if (length(vertices)) {
      keys <- do.call(rbind,vertices)
      selected <- vertices[[order(keys[,1L],keys[,2L],keys[,3L])[1L]]]
      corner$match <- paste("polygon",selected[2L],"vertex",selected[3L])
      corner$match_kind <- "vertex"
    } else {
      ends <- list()
      for (s in segments) for (j in seq_len(2L)) {
        endpoint <- if (j == 1L) s$start else s$ending
        distance <- chebyshev(point,endpoint)
        if (distance <= maximum_distance) ends[[length(ends)+1L]] <- c(distance,s$number,j)
      }
      if (!length(ends)) {
        corner$match <- corner$match_kind <- "none"
      } else {
        keys <- do.call(rbind,ends)
        selected <- ends[[order(keys[,1L],keys[,2L],keys[,3L])[1L]]]
        corner$match <- paste("segment",selected[2L],if (selected[3L] == 1L) "start" else "end")
        corner$match_kind <- "segment"
      }
    }
    corners[[i]] <- corner
  }
  matched <- 0L
  for (p in seq_along(polygons)) for (i in seq_along(polygons[[p]]$vertices)) {
    vertex <- polygons[[p]]$vertices[[i]]
    distances <- vapply(corners,function(corner) chebyshev(c(corner$x,corner$y),vertex),numeric(1))
    candidates <- which(distances <= maximum_distance)
    if (length(candidates)) {
      chosen <- candidates[order(distances[candidates],candidates)[1L]]
      polygons[[p]]$vertex_corners[i] <- chosen
      matched <- matched+1L
    }
  }
  list(corners=corners,polygons=polygons,matched=matched)
}
shape_explanations <- function(shape,edges) {
  explained <- matrix(FALSE,nrow(edges),ncol(edges))
  if (shape$type == "circle") {
    for (point in raster_points(edges)) if (on_circumference(point,shape)) explained[
        point[2L]+1L,
        point[1L]+1L
    ] <- TRUE
  } else {
    vertices <- shape$vertices
    for (i in seq_along(vertices)) for (point in bresenham(
        vertices[[i]],
        vertices[[i %% length(vertices)+1L]]
    )) for (dx in seq.int(-1L,1L)) for (dy in seq.int(-1L,1L)) {
      x <- point[1L]+dx
      y <- point[2L]+dy
      if (has_edge(edges,x,y)) explained[y+1L,x+1L] <- TRUE
    }
  }
  explained
}
component_attributes <- function(groups,edges,magnitude,direction,shapes) {
  explanations <- lapply(shapes,function(shape) shape_explanations(shape,edges))
  result <- list()
  for (pixels in groups) {
    xs <- vapply(pixels,`[`,integer(1),1L)
    ys <- vapply(pixels,`[`,integer(1),2L)
    ends <- sum(vapply(
        pixels,
        function(point) sum(vapply(
            NEIGHBORS,
            function(offset) has_edge(edges,point[1L]+offset[1L],point[2L]+offset[2L]),
            logical(1)
        )) == 1L,
        logical(1)
    ))
    strength <- sum(vapply(
        pixels,
        function(point) magnitude[point[2L]+1L,point[1L]+1L],
        numeric(1)
    )) %/% length(pixels)
    directions <- c(0L,45L,90L,135L)
    counts <- vapply(
        directions,
        function(d) sum(vapply(pixels,function(point) direction[point[2L]+1L,point[1L]+1L] == d,logical(1))),
        integer(1)
    )
    main_direction <- directions[order(-counts,directions)[1L]]
    counts <- vapply(
        explanations,
        function(explained) sum(vapply(
            pixels,
            function(point) has_edge(explained,point[1L],point[2L]),
            logical(1)
        )),
        integer(1)
    )
    maximum_count <- if (length(counts)) max(counts) else 0L
    shape <- if (maximum_count == 0L) 0L else which.max(counts)
    result[[length(result)+1L]] <- list(
        number=length(result)+1L,
        pixels=length(pixels),
        box=c(min(xs),min(ys),max(xs),max(ys)),
        ends=ends,
        strength=strength,
        direction=main_direction,
        shape=shape,
        explained=maximum_count
    )
  }
  result
}
overlay_image <- function(image,segments,circles,corners,divisor) {
  output <- image %/% divisor
  mark <- function(point) {
    x <- point[1L]
    y <- point[2L]
    if (x >= 0L && x < ncol(output) && y >= 0L && y < nrow(output)) output[y+1L,x+1L] <<- 255L
  }
  for (s in segments) for (point in bresenham(s$start,s$ending)) mark(point)
  for (circle in circles) for (offset in circle$outline) mark(circle$center+offset)
  for (corner in corners) for (offset in seq.int(-2L,2L)) {
    mark(c(corner$x+offset,corner$y))
    mark(c(corner$x,corner$y+offset))
  }
  output
}
shape_name <- function(index,shapes) if (index == 0L) "none" else paste(
    shapes[[index]]$type,
    shapes[[index]]$number
)
main <- function() {
  inputs <- read_inputs()
  image <- inputs$image
  trig <- inputs$trig
  params <- inputs$params
  height <- nrow(image)
  width <- ncol(image)
  smoothed <- smoothing(image,params)
  gradients <- gradient(smoothed)
  gx <- gradients$gx
  gy <- gradients$gy
  magnitude <- gradients$magnitude
  direction <- directions(gx,gy)
  nonmax <- suppress(magnitude,direction)
  thresholded <- hysteresis(nonmax,params$canny_low[1L],params$canny_high[1L])
  edges <- thresholded$edges
  strong <- thresholded$strong
  weak <- thresholded$weak
  groups <- components(edges)
  voted <- circle_votes(edges,params)
  circle_peaks_result <- circle_peaks(
      voted$cells,
      voted$outlines,
      voted$radii,
      width,
      height,
      params$circle_min_percent[1L]
  )
  selected <- selected_circles(voted$outlines,circle_peaks_result$peaks,edges,params$circle_max_count[1L])
  circles <- selected$circles
  circle_edges <- selected$circle_edges
  line_edges <- selected$line_edges
  votes <- line_votes(line_edges,trig,params$hough_rho_step[1L])
  peaks <- line_peaks(votes,params$hough_threshold[1L])
  extracted <- extract_segments(peaks,line_edges,trig,params)
  lines <- extracted$lines
  segments <- extracted$segments
  used <- extracted$used
  joins <- build_junctions(segments,params$junction_min_angle[1L],params$junction_distance[1L])
  polygons <- lapply(polygon_cycles(segments,joins),function(p) polygon_properties(p,segments,edges,params))
  polygon_count <- length(polygons)
  shapes <- measure_shapes(c(polygons,circles),image,params$contrast_margin[1L])
  polygons <- head(shapes,polygon_count)
  circles <- tail(shapes,length(shapes)-polygon_count)
  harris <- harris_corners(
      gx,
      gy,
      params$harris_window[1L],
      params$harris_threshold[1L],
      params$harris_max_count[1L]
  )
  matched <- match_corners(harris$chosen,polygons,segments,params$corner_match_distance[1L])
  corners <- matched$corners
  polygons <- matched$polygons
  component_list <- component_attributes(groups,edges,magnitude,direction,shapes)
  overlay <- overlay_image(image,segments,circles,corners,params$overlay_divisor[1L])
  hough_image <- if (votes$maximum > 0L) (255L*votes$votes) %/% votes$maximum else votes$votes
  write_pgm("edges.pgm",255L*edges)
  write_pgm("hough.pgm",hough_image)
  write_pgm("overlay.pgm",overlay)
  line_text <- paste("lines",length(lines))
  for (line in lines) {
    line_text <- c(
        line_text,
        paste(
            "line",
            line$number,
            "theta",
            line$theta,
            "rho",
            integer_text(line$rho),
            "votes",
            line$votes,
            "segments",
            length(line$segments)
        )
    )
    for (number in line$segments) {
      s <- segments[[number]]
      line_text <- c(
          line_text,
          paste(
              "segment",
              number,
              "start",
              paste(integer_text(s$start),collapse=" "),
              "end",
              paste(integer_text(s$ending),collapse=" "),
              "length",
              integer_text(s$length),
              "pixels",
              s$pixels
          )
      )
    }
  }
  circle_text <- paste("circles",length(circles))
  for (circle in circles) circle_text <- c(circle_text,paste("circle",circle$number,"center",paste(integer_text(circle$center),collapse=" "),"radius",integer_text(circle$radius),"votes",circle$votes,
    "points",circle$outline_count,"gap",circle$gap,"arcs",circle$arcs,"pixels",circle$pixel_count,"mean",integer_text(circle$mean),"contrast",integer_text(circle$contrast),"inside",shape_name(
        circle$enclosing,
        shapes
    )))
  polygon_text <- paste("polygons",length(polygons))
  for (p in polygons) {
    amount <- abs(p$sigma)
    area <- paste0(integer_text(amount %/% 2L),".",if (amount %% 2L) "5" else "0")
    polygon_text <- c(
        polygon_text,
        paste(
            "polygon",
            p$number,
            p$kind,
            "segments",
            paste(p$segments,collapse=" "),
            "area",
            area,
            "pixels",
            p$pixel_count,
            "mean",
            integer_text(p$mean),
            "contrast",
            integer_text(p$contrast),
            "inside",
            shape_name(p$enclosing,shapes)
        )
    )
    for (i in seq_along(p$vertices)) {
      corner <- if (p$vertex_corners[i] == 0L) "none" else as.character(p$vertex_corners[i])
      polygon_text <- c(
          polygon_text,
          paste(
              "vertex",
              i,
              paste(integer_text(p$vertices[[i]]),collapse=" "),
              "angle",
              integer_text(p$angles[i]),
              "corner",
              corner
          )
      )
    }
    for (i in seq_along(p$segments)) polygon_text <- c(
        polygon_text,
        paste(
            "side",
            i,
            "segment",
            p$segments[i],
            "length2",
            integer_text(p$lengths[i]),
            "support",
            integer_text(p$supports[i])
        )
    )
  }
  corner_text <- c(
      paste("corners",length(corners)),
      vapply(
          corners,
          function(corner) paste(
              "corner",
              corner$number,
              corner$x,
              corner$y,
              "response",
              integer_text(corner$response),
              "match",
              corner$match
          ),
          character(1)
      )
  )
  component_text <- c(paste("components",length(component_list)),vapply(component_list,function(component) paste("component",component$number,"pixels",component$pixels,"box",paste(component$box,collapse=" "),"ends",component$ends,
    "strength",integer_text(component$strength),"direction",component$direction,"shape",shape_name(
        component$shape,
        shapes
    ),"explained",component$explained),character(1)))
  report <- c(paste("image",width,height),paste("gradient_nonzero",sum(magnitude > 0L)),paste("gradient_max",max(magnitude)),paste("nms_kept",sum(nonmax > 0L)),
    paste("strong",sum(strong)),paste("weak",sum(weak)),paste("edges",sum(edges)),paste("weak_kept",sum(weak & edges)),paste(
        "weak_dropped",
        sum(weak & !edges)
    ),paste("edge_components",length(groups)))
  for (d in c(0L,45L,90L,135L)) report <- c(report,paste0("direction_",d," ",sum(edges & direction == d)))
  report <- c(report,paste("circle_candidates",length(circle_peaks_result$candidates)),paste("circle_peaks",length(circle_peaks_result$peaks)),paste("circles",length(circles)),paste("circle_edge_pixels",sum(circle_edges)),
    paste(
        "line_edge_pixels",
        sum(line_edges)
    ),paste("hough_max_votes",votes$maximum),paste("hough_peaks",length(peaks)),paste("lines",length(lines)),paste("segments",length(segments)),paste("claimed_pixels",sum(used)),paste("junctions",length(joins)),paste("polygons",length(polygons)))
  for (kind in POLYGON_KINDS) report <- c(
      report,
      paste(kind,sum(vapply(polygons,function(p) p$kind == kind,logical(1))))
  )
  report <- c(report,paste("corner_candidates",length(harris$candidates)),paste("corners",length(corners)),paste("corners_on_vertices",sum(vapply(corners,function(c) c$match_kind == "vertex",logical(1)))),
    paste(
        "corners_on_segments",
        sum(vapply(corners,function(c) c$match_kind == "segment",logical(1)))
    ),paste("corners_unmatched",sum(vapply(corners,function(c) c$match_kind == "none",logical(1)))),paste("vertices_with_corner",matched$matched))
  files <- list(
      "lines.txt"=line_text,
      "circles.txt"=circle_text,
      "polygons.txt"=polygon_text,
      "corners.txt"=corner_text,
      "components.txt"=component_text,
      "report.txt"=report
  )
  for (name in names(files)) write_lines(name,files[[name]])
}
main()
