for (module in c("fixed_point","vector3","scene","intersect","shading")) source(paste0(module,".R"))
RAY_KINDS <- c("primary","reflection","refraction","shadow")
LIGHT_COUNTS <- c("pixels","shadow_rays","blocked","attenuated","backfacing","outside")
BLACK <- c(0,0,0)
integer_text <- function(values) sprintf("%.0f",values)
vector_text <- function(values) paste(integer_text(values),collapse=" ")
write_lines <- function(name,lines) {
  dir.create("output",showWarnings=FALSE)
  writeLines(lines,file.path("output",name),useBytes=TRUE)
}
read_settings <- function() {
  rows <- strsplit(readLines(file.path("input","render.txt"))," ",fixed=TRUE)
  setNames(lapply(rows,function(row) as.numeric(row[-1L])),vapply(rows,`[`,character(1),1L))
}
union_box <- function(renderer,ids) {
  list(lo=vapply(seq_len(3L),function(a) min(vapply(ids,function(i) renderer$objects[[i]]$bounds$lo[a],numeric(1))),numeric(1)),
    hi=vapply(
        seq_len(3L),
        function(a) max(vapply(ids,function(i) renderer$objects[[i]]$bounds$hi[a],numeric(1))),
        numeric(1)
    ))
}
surface_cost <- function(renderer,ids) {
  box <- union_box(renderer,ids)
  d <- box$hi-box$lo
  (d[1L]*d[2L]+d[2L]*d[3L]+d[3L]*d[1L])*length(ids)
}
build_bvh <- function(renderer,ids,depth) {
  node <- new.env(parent=emptyenv())
  node$bounds <- union_box(renderer,ids)
  node$depth <- depth
  node$visits <- 0
  node$objects <- integer()
  node$left <- node$right <- 0L
  index <- length(renderer$nodes)+1L
  renderer$nodes[[index]] <- node
  if (length(ids) <= 2L) {
    node$objects <- sort(ids)
    renderer$leaf_depth[ids] <- depth
    return(index)
  }
  best_cost <- NULL
  best_left <- best_right <- integer()
  for (axis in seq_len(3L)) {
    centers <- vapply(
        ids,
        function(i) (renderer$objects[[i]]$bounds$lo[axis]+renderer$objects[[i]]$bounds$hi[axis]) %/% 2,
        numeric(1)
    )
    ordered <- ids[order(centers,ids)]
    for (split in seq_len(length(ordered)-1L)) {
      left <- head(ordered,split)
      right <- tail(ordered,length(ordered)-split)
      cost <- surface_cost(renderer,left)+surface_cost(renderer,right)
      if (is.null(best_cost) || cost < best_cost) {
        best_cost <- cost
        best_left <- left
        best_right <- right
      }
    }
  }
  node$left <- build_bvh(renderer,best_left,depth+1L)
  node$right <- build_bvh(renderer,best_right,depth+1L)
  index
}
make_renderer <- function(scene,settings) {
  renderer <- new.env(parent=emptyenv())
  renderer$scene <- scene
  renderer$width <- settings$size[1L]
  renderer$height <- settings$size[2L]
  renderer$contrast <- settings$contrast[1L]
  renderer$max_depth <- settings$depth[1L]
  renderer$far <- settings$far[1L]
  renderer$epsilon <- settings$epsilon[1L]
  renderer$objects <- lapply(scene$objects,function(object) {
    object$bounds <- object_bounds(object,settings$pad[1L])
    object
  })
  renderer$planes <- which(vapply(renderer$objects,function(object) object$kind == "plane",logical(1)))
  bounded <- which(vapply(renderer$objects,function(object) !is.null(object$bounds),logical(1)))
  renderer$nodes <- list()
  renderer$leaf_depth <- rep(-1L,length(renderer$objects))
  renderer$root <- if (length(bounded)) build_bvh(renderer,bounded,0L) else 0L
  renderer$rays <- numeric(4L)
  renderer$misses <- numeric(3L)
  renderer$depth_counts <- numeric(renderer$max_depth+1L)
  renderer$tests <- matrix(0,4L,2L)
  renderer$object_counts <- matrix(0,length(renderer$objects),3L)
  renderer$light_counts <- matrix(0,length(scene$lights),6L)
  renderer$total_internal_reflections <- renderer$clamped <- renderer$supersampled <- 0
  renderer$pixels <- list()
  renderer
}
test_node <- function(renderer,index,origin,direction,kind,counted) {
  node <- renderer$nodes[[index]]
  if (counted) {
    renderer$tests[kind,1L] <- renderer$tests[kind,1L]+1
    node$visits <- node$visits+1
  }
  interval <- slab(node$bounds$lo,node$bounds$hi,origin,direction)
  if (is.null(interval) || interval$far <= renderer$epsilon) NULL else interval$near
}
test_object <- function(renderer,index,origin,direction,kind,counted) {
  if (counted) renderer$tests[kind,2L] <- renderer$tests[kind,2L]+1
  candidate(renderer$objects[[index]],origin,direction,renderer$epsilon)
}
nearest <- function(renderer,origin,direction,kind=1L,counted=FALSE) {
  best <- NULL
  consider <- function(index) {
    intersection <- test_object(renderer,index,origin,direction,kind,counted)
    if (is.null(intersection) || intersection$distance > renderer$far) return(invisible(NULL))
    if (is.null(best) || intersection$distance < best$intersection$distance ||
      (intersection$distance == best$intersection$distance && index < best$index)) best <<- list(
          index=index,
          intersection=intersection
      )
  }
  visit <- function(index) {
    entry <- test_node(renderer,index,origin,direction,kind,counted)
    if (is.null(entry) || entry > renderer$far || (!is.null(best) && entry > best$intersection$distance)) return(invisible(NULL))
    node <- renderer$nodes[[index]]
    if (length(node$objects)) for (i in node$objects) consider(i) else {
      visit(node$left)
      visit(node$right)
    }
  }
  for (i in renderer$planes) consider(i)
  if (renderer$root != 0L) visit(renderer$root)
  best
}
occluders <- function(renderer,origin,direction,distance,counted=FALSE) {
  found <- integer()
  consider <- function(index) {
    intersection <- test_object(renderer,index,origin,direction,4L,counted)
    if (!is.null(intersection) && intersection$distance < distance) {
      found <<- c(found,index)
      if (counted) renderer$object_counts[index,3L] <- renderer$object_counts[index,3L]+1
    }
  }
  visit <- function(index) {
    entry <- test_node(renderer,index,origin,direction,4L,counted)
    if (is.null(entry) || entry >= distance) return(invisible(NULL))
    node <- renderer$nodes[[index]]
    if (length(node$objects)) for (i in node$objects) consider(i) else {
      visit(node$left)
      visit(node$right)
    }
  }
  for (i in renderer$planes) consider(i)
  if (renderer$root != 0L) visit(renderer$root)
  sort(found)
}
camera_ray <- function(renderer,qx,qy) {
  scene <- renderer$scene
  hw <- scene$view[1L]
  hh <- scene$view[2L]
  u <- ((qx-2*renderer$width)*hw) %/% (2*renderer$width)
  v <- ((2*renderer$height-qy)*hh) %/% (2*renderer$height)
  list(origin=scene$eye,direction=norm(add(add(scene$forward,sc(scene$right,u)),sc(scene$up,v))))
}
intersection_info <- function(renderer,nearest_hit,origin,direction) {
  object <- renderer$objects[[nearest_hit$index]]
  distance <- nearest_hit$intersection$distance
  point <- add(origin,sc(direction,distance))
  outward <- outward_normal(object,point,direction,nearest_hit$intersection)
  front <- dot(outward,direction) <= 0
  list(
      index=nearest_hit$index,
      object=object,
      distance=distance,
      point=point,
      normal=if (front) outward else -outward,
      front=front,
      base=base_color(object$material,point)
  )
}
light_samples <- function(renderer,light,point) {
  if (light$kind == "sun") return(list(list(
      direction=light$direction,
      distance=renderer$far,
      intensity=light$intensity
  )))
  positions <- list()
  if (light$kind == "area") {
    k <- light$divisions
    for (j in seq_len(k)-1L) for (i in seq_len(k)-1L) positions[[length(positions)+1L]] <- light$position+((2*i+1)*light$u) %/% (2*k)+((2*j+1)*light$v) %/% (2*k)
  } else positions <- list(light$position)
  intensity <- light$intensity %/% light$samples
  lapply(positions,function(position) {
    relative <- position-point
    list(direction=norm(relative),distance=vector_length(relative),intensity=intensity)
  })
}
cone_factor <- function(light,direction) {
  if (light$kind != "spot") return(S)
  cosine <- -dot(direction,light$direction)
  if (cosine <= light$outer) return(0)
  if (cosine >= light$inner) return(S)
  ((cosine-light$outer)*S) %/% (light$inner-light$outer)
}
sample_contribution <- function(renderer,light,sample,info,view,pixel) {
  direction <- sample$direction
  j <- light$number
  counted <- !is.null(pixel)
  ndl <- dot(info$normal,direction)
  if (ndl <= 0) {
    if (counted) renderer$light_counts[j,5L] <- renderer$light_counts[j,5L]+1
    return(c(0,0,0))
  }
  factor <- cone_factor(light,direction)
  if (factor == 0) {
    if (counted) renderer$light_counts[j,6L] <- renderer$light_counts[j,6L]+1
    return(c(0,0,0))
  }
  if (counted) {
    renderer$rays[4L] <- renderer$rays[4L]+1
    pixel$rays <- pixel$rays+1
    renderer$light_counts[j,2L] <- renderer$light_counts[j,2L]+1
  }
  blockers <- occluders(renderer,info$point,direction,sample$distance,counted)
  for (i in blockers) factor <- mul(factor,renderer$objects[[i]]$material$kt)
  if (factor == 0) {
    if (counted) renderer$light_counts[j,3L] <- renderer$light_counts[j,3L]+1
    return(c(0,0,0))
  }
  if (counted && length(blockers)) renderer$light_counts[j,4L] <- renderer$light_counts[j,4L]+1
  terms <- phong(info$object$material,info$normal,direction,view,ndl,sample$intensity,factor)
  c(1,terms)
}
local_color <- function(renderer,info,direction,pixel) {
  lighting <- list()
  for (light in renderer$scene$lights) {
    terms <- c(0,0,0)
    for (sample in light_samples(renderer,light,info$point)) terms <- terms+sample_contribution(
        renderer,
        light,
        sample,
        info,
        -direction,
        pixel
    )
    lighting[[length(lighting)+1L]] <- terms
  }
  diffuse <- sum(vapply(lighting,`[`,numeric(1),2L))
  specular <- sum(vapply(lighting,`[`,numeric(1),3L))
  raw <- (info$base*(renderer$scene$ambient+diffuse)) %/% S+(255*specular) %/% S
  if (!is.null(pixel)) renderer$clamped <- renderer$clamped+sum(raw > 255)
  info$lighting <- lighting
  info$illumination <- sum(vapply(lighting,function(item) item[1L] > 0,logical(1)))
  list(color=pmin(raw,255),info=info)
}
apply_fog <- function(renderer,color,distance) {
  fog <- renderer$scene$fog
  if (is.null(fog)) return(color)
  start <- fog[4L]
  ending <- fog[5L]
  factor <- if (distance <= start) 0 else if (distance >= ending) S else ((distance-start)*S) %/% (ending-start)
  mix(list(color=color,weight=S-factor),list(color=fog[1:3],weight=factor))
}
record_line <- function(record,line) {
  if (!is.null(record)) record$lines <- c(record$lines,line)
}
trace_ray <- function(renderer,origin,direction,kind=1L,depth=0L,pixel=NULL,record=NULL) {
  counted <- !is.null(pixel)
  if (counted) {
    renderer$rays[kind] <- renderer$rays[kind]+1
    renderer$depth_counts[depth+1L] <- renderer$depth_counts[depth+1L]+1
    pixel$rays <- pixel$rays+1
    pixel$depth <- max(pixel$depth,depth)
  }
  record_line(
      record,
      paste("ray",RAY_KINDS[kind],depth,"origin",vector_text(origin),"direction",vector_text(direction))
  )
  nearest_hit <- nearest(renderer,origin,direction,kind,counted)
  if (is.null(nearest_hit)) {
    if (counted) renderer$misses[kind] <- renderer$misses[kind]+1
    color <- renderer$scene$background
    record_line(record,c("miss",paste("color",vector_text(color))))
    return(list(color=color,hit=NULL))
  }
  info <- intersection_info(renderer,nearest_hit,origin,direction)
  if (counted) {
    column <- if (kind == 1L) 1L else 2L
    renderer$object_counts[info$index,column] <- renderer$object_counts[info$index,column]+1
  }
  local <- local_color(renderer,info,direction,pixel)
  info <- local$info
  record_line(
      record,
      paste(
          "hit",
          info$object$label,
          "t",
          integer_text(info$distance),
          "point",
          vector_text(info$point),
          "normal",
          vector_text(info$normal),
          "base",
          vector_text(info$base)
      )
  )
  for (j in seq_along(renderer$scene$lights)) {
    light <- renderer$scene$lights[[j]]
    terms <- info$lighting[[j]]
    record_line(
        record,
        paste(
            "light",
            j,
            "lit",
            integer_text(terms[1L]),
            "of",
            integer_text(light$samples),
            "diffuse",
            integer_text(terms[2L]),
            "specular",
            integer_text(terms[3L])
        )
    )
  }
  record_line(record,paste("local",vector_text(local$color)))
  material <- info$object$material
  color <- local$color
  if (depth < renderer$max_depth && (material$kr > 0 || material$kt > 0)) {
    optics <- refraction(material,direction,info$normal,info$front)
    if (optics$internal) {
      if (counted) renderer$total_internal_reflections <- renderer$total_internal_reflections+1
      record_line(record,"total_internal_reflection")
    }
    weight <- S-material$kr-material$kt
    record_line(record,paste("weights",vector_text(c(weight,optics$wr,optics$wt))))
    reflected_color <- if (optics$wr > 0) trace_ray(
        renderer,
        info$point,
        reflected(direction,info$normal),
        2L,
        depth+1L,
        pixel,
        record
    )$color else BLACK
    refracted_color <- if (optics$wt > 0) trace_ray(
        renderer,
        info$point,
        optics$direction,
        3L,
        depth+1L,
        pixel,
        record
    )$color else BLACK
    color <- mix(
        list(color=local$color,weight=weight),
        list(color=reflected_color,weight=optics$wr),
        list(color=refracted_color,weight=optics$wt)
    )
  }
  color <- apply_fog(renderer,color,info$distance)
  record_line(record,paste("color",vector_text(color)))
  list(color=color,hit=info)
}
render <- function(renderer) {
  for (y in seq_len(renderer$height)-1L) for (x in seq_len(renderer$width)-1L) {
    pixel <- new.env(parent=emptyenv())
    pixel$x <- x
    pixel$y <- y
    pixel$rays <- pixel$depth <- 0
    pixel$samples <- 1L
    pixel$label <- "."
    ray <- camera_ray(renderer,4L*x+2L,4L*y+2L)
    result <- trace_ray(renderer,ray$origin,ray$direction,pixel=pixel)
    pixel$center <- pixel$color <- result$color
    pixel$hit <- result$hit
    if (!is.null(result$hit)) {
      pixel$label <- result$hit$object$label
      for (j in seq_along(result$hit$lighting)) if (result$hit$lighting[[j]][1L] > 0) renderer$light_counts[j,1L] <- renderer$light_counts[
          j,
          1L
      ]+1
    }
    renderer$pixels[[length(renderer$pixels)+1L]] <- pixel
  }
  for (pixel in renderer$pixels) {
    x <- pixel$x
    y <- pixel$y
    boundary <- FALSE
    for (position in list(c(x,y-1L),c(x,y+1L),c(x-1L,y),c(x+1L,y))) {
      nx <- position[1L]
      ny <- position[2L]
      if (nx < 0L || nx >= renderer$width || ny < 0L || ny >= renderer$height) next
      other <- renderer$pixels[[ny*renderer$width+nx+1L]]
      if (other$label != pixel$label || max(abs(other$center-pixel$center)) > renderer$contrast) {
        boundary <- TRUE
        break
      }
    }
    if (!boundary) next
    renderer$supersampled <- renderer$supersampled+1
    pixel$samples <- 4L
    colors <- list()
    for (offset in list(c(1L,1L),c(3L,1L),c(1L,3L),c(3L,3L))) {
      ray <- camera_ray(renderer,4L*x+offset[1L],4L*y+offset[2L])
      colors[[length(colors)+1L]] <- trace_ray(renderer,ray$origin,ray$direction,pixel=pixel)$color
    }
    pixel$color <- Reduce(`+`,colors) %/% 4
  }
}
write_netpbm <- function(renderer,name,magic,values) {
  lines <- c(magic,vector_text(c(renderer$width,renderer$height)),"255")
  for (y in seq_len(renderer$height)-1L) {
    row <- values[seq.int(y*renderer$width+1L,(y+1L)*renderer$width)]
    lines <- c(
        lines,
        if (magic == "P3") paste(
            vapply(row,vector_text,character(1)),
            collapse=" "
        ) else vector_text(unlist(row,use.names=FALSE))
    )
  }
  write_lines(name,lines)
}
write_map <- function(renderer,name,values) {
  lines <- vapply(
      seq_len(renderer$height)-1L,
      function(y) paste(values[seq.int(y*renderer$width+1L,(y+1L)*renderer$width)],collapse=""),
      character(1)
  )
  write_lines(name,lines)
}
distance_range <- function(renderer) {
  hits <- Filter(function(pixel) !is.null(pixel$hit),renderer$pixels)
  if (!length(hits)) NULL else range(vapply(hits,function(pixel) pixel$hit$distance,numeric(1)))
}
mean_color <- function(pixels) vapply(
    seq_len(3L),
    function(a) sum(vapply(pixels,function(pixel) pixel$color[a],numeric(1))) %/% length(pixels),
    numeric(1)
)
write_images <- function(renderer) {
  distances <- distance_range(renderer)
  max_cost <- max(vapply(renderer$pixels,function(pixel) pixel$rays,numeric(1)))
  depth_values <- normal_values <- albedo_values <- list()
  light_values <- character()
  for (pixel in renderer$pixels) {
    hit <- pixel$hit
    if (is.null(hit)) {
      depth_values[[length(depth_values)+1L]] <- 0
      normal_values[[length(normal_values)+1L]] <- BLACK
      albedo_values[[length(albedo_values)+1L]] <- BLACK
      light_values <- c(light_values,".")
      next
    }
    low <- distances[1L]
    high <- distances[2L]
    depth_values[[length(depth_values)+1L]] <- if (low == high) 255 else 255-(235*(hit$distance-low)) %/% (high-low)
    normal_values[[length(normal_values)+1L]] <- pmax(0,pmin(255,((hit$normal+S)*255) %/% (2*S)))
    albedo_values[[length(albedo_values)+1L]] <- hit$base
    light_values <- c(light_values,integer_text(hit$illumination))
  }
  write_netpbm(renderer,"image.ppm","P3",lapply(renderer$pixels,function(pixel) pixel$color))
  write_netpbm(renderer,"depth.pgm","P2",depth_values)
  write_netpbm(renderer,"normal.ppm","P3",normal_values)
  write_netpbm(renderer,"albedo.ppm","P3",albedo_values)
  write_netpbm(renderer,"cost.pgm","P2",lapply(renderer$pixels,function(pixel) (255*pixel$rays) %/% max_cost))
  write_map(renderer,"object_map.txt",vapply(renderer$pixels,function(pixel) pixel$label,character(1)))
  write_map(renderer,"light_map.txt",light_values)
  write_map(
      renderer,
      "ray_depth.txt",
      vapply(renderer$pixels,function(pixel) integer_text(pixel$depth),character(1))
  )
}
statistics <- function(renderer) {
  lines <- c(paste("image",vector_text(c(renderer$width,renderer$height))),paste("supersampled",integer_text(renderer$supersampled)),
    paste(
        "rays",
        paste(paste(RAY_KINDS,integer_text(renderer$rays)),collapse=" "),
        "total",
        integer_text(sum(renderer$rays))
    ),
    paste(
        "misses",
        paste(paste(RAY_KINDS[1:3],integer_text(renderer$misses)),collapse=" ")
    ),paste("depth",vector_text(renderer$depth_counts)))
  for (i in seq_along(RAY_KINDS)) lines <- c(
      lines,
      paste(
          "tests",
          RAY_KINDS[i],
          "nodes",
          integer_text(renderer$tests[i,1L]),
          "objects",
          integer_text(renderer$tests[i,2L])
      )
  )
  distances <- distance_range(renderer)
  lines <- c(lines,paste("total_internal_reflection",integer_text(renderer$total_internal_reflections)),paste("clamped",integer_text(renderer$clamped)),
    paste("distance",if (is.null(distances)) "none" else vector_text(distances)),paste(
        "max_pixel_rays",
        integer_text(max(vapply(renderer$pixels,function(pixel) pixel$rays,numeric(1))))
    ),
    paste("mean",vector_text(mean_color(renderer$pixels))))
  histogram <- numeric(8L)
  for (pixel in renderer$pixels) {
    brightness <- sum(c(299,587,114)*pixel$color) %/% 1000
    bin <- brightness %/% 32+1L
    histogram[bin] <- histogram[bin]+1
  }
  lines <- c(lines,paste("histogram",vector_text(histogram)))
  for (node in renderer$nodes) {
    role <- if (!length(node$objects)) "inner" else paste(
        "leaf",
        paste(vapply(node$objects,function(i) renderer$objects[[i]]$label,character(1)),collapse="")
    )
    lines <- c(
        lines,
        paste(
            "node",
            node$depth,
            role,
            "box",
            vector_text(node$bounds$lo),
            vector_text(node$bounds$hi),
            "visits",
            integer_text(node$visits)
        )
    )
  }
  for (i in seq_along(renderer$objects)) {
    object <- renderer$objects[[i]]
    pixels <- Filter(function(pixel) pixel$label == object$label,renderer$pixels)
    box <- color <- "none"
    if (length(pixels)) {
      xs <- vapply(pixels,function(pixel) pixel$x,integer(1))
      ys <- vapply(pixels,function(pixel) pixel$y,integer(1))
      box <- vector_text(c(min(xs),min(ys),max(xs),max(ys)))
      color <- vector_text(mean_color(pixels))
    }
    counts <- renderer$object_counts[i,]
    lines <- c(lines,paste("object",object$label,object$kind,"primary",integer_text(counts[1L]),"secondary",integer_text(counts[2L]),"shadow",integer_text(counts[3L]),
      "pixels",length(pixels),"box",box,"color",color))
  }
  for (i in seq_along(renderer$scene$lights)) {
    light <- renderer$scene$lights[[i]]
    values <- paste(paste(LIGHT_COUNTS,integer_text(renderer$light_counts[i,])),collapse=" ")
    lines <- c(lines,paste("light",i,light$kind,"samples",integer_text(light$samples),values))
  }
  lines
}
process_queries <- function(renderer) {
  record <- new.env(parent=emptyenv())
  record$lines <- character()
  queries <- readLines(file.path("input","queries.txt"))
  for (number in seq_along(queries)) {
    line <- queries[number]
    record_line(record,paste("query",number,line))
    words <- strsplit(line," ",fixed=TRUE)[[1L]]
    kind <- words[1L]
    if (kind == "object") {
      i <- which(vapply(renderer$objects,function(object) object$label == words[2L],logical(1)))[1L]
      object <- renderer$objects[[i]]
      suffix <- if (is.null(object$bounds)) "bounds none leaf none" else paste(
          "bounds",
          vector_text(object$bounds$lo),
          vector_text(object$bounds$hi),
          "leaf",
          renderer$leaf_depth[i]
      )
      record_line(record,paste(object$kind,"material",object$material$name,suffix))
      next
    }
    values <- as.numeric(words[-1L])
    if (kind == "pixel") {
      x <- values[1L]
      y <- values[2L]
      pixel <- renderer$pixels[[y*renderer$width+x+1L]]
      distance <- if (is.null(pixel$hit)) "none" else integer_text(pixel$hit$distance)
      record_line(
          record,
          paste(
              "label",
              pixel$label,
              "distance",
              distance,
              "color",
              vector_text(pixel$color),
              "samples",
              pixel$samples,
              "rays",
              integer_text(pixel$rays)
          )
      )
    } else if (kind == "trace") {
      ray <- camera_ray(renderer,4*values[1L]+2,4*values[2L]+2)
      trace_ray(renderer,ray$origin,ray$direction,record=record)
    } else if (kind == "ray") trace_ray(
        renderer,
        values[1:3],
        norm(values[4:6]),
        record=record
    ) else if (kind == "visible") {
      relative <- values-renderer$scene$eye
      direction <- norm(relative)
      blockers <- occluders(renderer,renderer$scene$eye,direction,vector_length(relative)-renderer$epsilon)
      visible <- if (length(blockers)) "no" else "yes"
      first <- nearest(renderer,renderer$scene$eye,direction)
      suffix <- if (is.null(first)) "first none" else paste(
          "first",
          renderer$objects[[first$index]]$label,
          "t",
          integer_text(first$intersection$distance)
      )
      record_line(record,paste(visible,suffix))
    } else if (kind == "shadow") {
      for (light in renderer$scene$lights) {
        total <- 0
        numbers <- integer()
        for (sample in light_samples(renderer,light,values)) {
          factor <- cone_factor(light,sample$direction)
          for (i in occluders(renderer,values,sample$direction,sample$distance)) {
            numbers <- union(numbers,i)
            factor <- mul(factor,renderer$objects[[i]]$material$kt)
          }
          total <- total+factor
        }
        labels <- paste(
            vapply(
                renderer$objects,
                function(object) if (object$number %in% numbers) object$label else "",
                character(1)
            ),
            collapse=""
        )
        record_line(
            record,
            paste(
                "light",
                light$number,
                "factor",
                integer_text(total),
                "occluders",
                if (nzchar(labels)) labels else "none"
            )
        )
      }
    } else if (kind == "region") {
      x0 <- values[1L]
      y0 <- values[2L]
      x1 <- values[3L]
      y1 <- values[4L]
      pixels <- list()
      for (y in seq.int(y0,y1)) for (x in seq.int(
          x0,
          x1
      )) pixels[[length(pixels)+1L]] <- renderer$pixels[[y*renderer$width+x+1L]]
      record_line(record,paste("pixels",length(pixels),"mean",vector_text(mean_color(pixels))))
      for (label in c(vapply(renderer$objects,function(object) object$label,character(1)),".")) {
        total <- sum(vapply(pixels,function(pixel) pixel$label == label,logical(1)))
        if (total > 0L) record_line(record,paste("label",label,total))
      }
    }
  }
  record$lines
}
main <- function() {
  renderer <- make_renderer(read_scene(),read_settings())
  render(renderer)
  write_images(renderer)
  write_lines("stats.txt",statistics(renderer))
  write_lines("queries.txt",process_queries(renderer))
}
main()
