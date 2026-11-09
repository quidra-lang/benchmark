for (module in c("dataset","kdtree","quadtree","rtree","grid","report")) source(paste0(module,".R"))
POINT_STRUCTURES <- c("kdtree","quadtree","rtree","str","grid")
RECTANGLE_STRUCTURES <- c("rtree_rect","str_rect")
RTREE_STRUCTURES <- c("rtree","str","rtree_rect","str_rect")
SEARCH_COMMANDS <- c("RANGE","RADIUS","KNN","WINDOWCOUNT","CONTAINS","NEAREST","JOIN")
node_view <- function(region,held,children,source,mark="root",depth=0L) {
  view <- new.env(parent=emptyenv())
  view$region <- region
  view$held <- held
  view$children <- children
  view$source <- source
  view$mark <- mark
  view$depth <- depth
  view$count <- length(held)+sum(vapply(children,function(child) child$count,integer(1)))
  view
}
kd_view <- function(root,world) {
  result <- node_view(c(0L,0L,world-1L,world-1L),list(root$point),list(),root)
  pending <- list(result)
  order <- list()
  while (length(pending)) {
    view <- pending[[length(pending)]]
    pending <- head(pending,-1L)
    order[[length(order)+1L]] <- view
    node <- view$source
    left <- right <- view$region
    split <- node$point[node$axis+2L]
    left[node$axis+3L] <- split
    right[node$axis+1L] <- split
    if (!is.null(node$left)) view$children[[length(view$children)+1L]] <- node_view(
        left,
        list(node$left$point),
        list(),
        node$left,
        "L",
        view$depth+1L
    )
    if (!is.null(node$right)) view$children[[length(view$children)+1L]] <- node_view(
        right,
        list(node$right$point),
        list(),
        node$right,
        "R",
        view$depth+1L
    )
    pending <- c(pending,rev(view$children))
  }
  for (view in rev(order)) view$count <- length(view$held)+sum(vapply(
      view$children,
      function(child) child$count,
      integer(1)
  ))
  result
}
quad_view <- function(node,mark="root",depth=0L) {
  children <- lapply(
      seq_along(node$children),
      function(i) quad_view(node$children[[i]],CHILD_NAMES[i],depth+1L)
  )
  node_view(c(node$x,node$y,node$x+node$size-1L,node$y+node$size-1L),node$points,children,node,mark,depth)
}
rtree_view <- function(node,objects,depth=0L) {
  if (node$level == 0L) {
    held <- lapply(node$entries,function(entry) objects[[as.character(entry$id)]])
    children <- list()
  } else {
    held <- list()
    children <- lapply(node$entries,function(entry) rtree_view(entry$child,objects,depth+1L))
  }
  node_view(node_box(node),held,children,node,depth=depth)
}
grid_view <- function(grid) {
  cells <- lapply(grid$cells,function(cell) node_view(cell$box,cell$points,list(),cell,depth=1L))
  node_view(c(0L,0L,grid$world-1L,grid$world-1L),list(),cells,grid)
}
preorder <- function(root) {
  result <- list()
  pending <- list(root)
  while (length(pending)) {
    node <- pending[[length(pending)]]
    pending <- head(pending,-1L)
    result[[length(result)+1L]] <- node
    pending <- c(pending,rev(node$children))
  }
  result
}
object_box <- function(object) if (length(object) == 3L) point_box(object) else object[-1L]
point_distance <- function(q,p) (p[2L]-q[1L])*(p[2L]-q[1L])+(p[3L]-q[2L])*(p[3L]-q[2L])
minimum_distance <- function(q,b) {
  dx <- if (q[1L] < b[1L]) b[1L]-q[1L] else if (q[1L] > b[3L]) q[1L]-b[3L] else 0L
  dy <- if (q[2L] < b[2L]) b[2L]-q[2L] else if (q[2L] > b[4L]) q[2L]-b[4L] else 0L
  dx*dx+dy*dy
}
object_distance <- function(q,object) if (length(object) == 3L) point_distance(
    q,
    object
) else minimum_distance(
    q,
    object_box(object)
)
search_conditions <- function(command,values) {
  if (command == "RANGE") return(list(
      region=function(region) intersects(region,values),
      object=function(point) contains(values,point_box(point))
  ))
  if (command == "RADIUS") {
    q <- values[1:2]
    limit <- values[3L]*values[3L]
    return(list(
        region=function(region) minimum_distance(q,region) <= limit,
        object=function(point) point_distance(q,point) <= limit
    ))
  }
  box <- values[c(1L,2L,1L,2L)]
  list(
      region=function(region) contains(region,box),
      object=function(rectangle) contains(object_box(rectangle),box)
  )
}
condition_search <- function(root,conditions) {
  answer <- integer()
  nodes <- tests <- 0L
  pending <- list(root)
  while (length(pending)) {
    node <- pending[[length(pending)]]
    pending <- head(pending,-1L)
    nodes <- nodes+1L
    tests <- tests+length(node$held)
    for (object in node$held) if (conditions$object(object)) answer <- c(answer,object[1L])
    children <- Filter(function(child) conditions$region(child$region),node$children)
    pending <- c(pending,rev(children))
  }
  list(answer=sort(answer),nodes=nodes,tests=tests)
}
window_count <- function(root,window) {
  answer <- nodes <- tests <- 0L
  pending <- list(root)
  while (length(pending)) {
    node <- pending[[length(pending)]]
    pending <- head(pending,-1L)
    nodes <- nodes+1L
    if (contains(window,node$region)) {
      answer <- answer+node$count
    } else {
      tests <- tests+length(node$held)
      answer <- answer+sum(vapply(node$held,function(point) contains(window,point_box(point)),logical(1)))
      children <- Filter(function(child) intersects(child$region,window),node$children)
      pending <- c(pending,rev(children))
    }
  }
  list(answer=answer,nodes=nodes,tests=tests)
}
make_heap <- function() {
  heap <- new.env(parent=emptyenv())
  heap$items <- list()
  heap
}
heap_push <- function(heap,key,element) {
  items <- heap$items
  items[[length(items)+1L]] <- list(key=key,element=element)
  i <- length(items)
  while (i > 1L) {
    parent <- i %/% 2L
    if (!key_less(items[[i]]$key,items[[parent]]$key)) break
    temporary <- items[[i]]
    items[[i]] <- items[[parent]]
    items[[parent]] <- temporary
    i <- parent
  }
  heap$items <- items
}
heap_pop <- function(heap) {
  items <- heap$items
  result <- items[[1L]]
  last <- items[[length(items)]]
  items <- head(items,-1L)
  if (length(items)) {
    items[[1L]] <- last
    i <- 1L
    while (2L*i <= length(items)) {
      child <- 2L*i
      if (child < length(items) && key_less(items[[child+1L]]$key,items[[child]]$key)) child <- child+1L
      if (!key_less(items[[child]]$key,items[[i]]$key)) break
      temporary <- items[[i]]
      items[[i]] <- items[[child]]
      items[[child]] <- temporary
      i <- child
    }
  }
  heap$items <- items
  result
}
best_first <- function(root,q,k) {
  heap <- make_heap()
  heap_push(heap,c(minimum_distance(q,root$region),0L,0L),root)
  serial <- 1L
  answer <- list()
  nodes <- tests <- 0L
  while (length(heap$items)) {
    item <- heap_pop(heap)
    distance <- item$key[1L]
    element <- item$element
    if (item$key[2L] == 1L) {
      answer[[length(answer)+1L]] <- c(element[1L],distance)
      if (length(answer) == k) break
    } else {
      nodes <- nodes+1L
      tests <- tests+length(element$held)
      for (object in element$held) heap_push(heap,c(object_distance(q,object),1L,object[1L]),object)
      for (child in element$children) {
        heap_push(heap,c(minimum_distance(q,child$region),0L,serial),child)
        serial <- serial+1L
      }
    }
  }
  list(answer=answer,nodes=nodes,tests=tests)
}
sort_pairs <- function(pairs) {
  if (!length(pairs)) return(pairs)
  first <- vapply(pairs,`[`,integer(1),1L)
  second <- vapply(pairs,`[`,integer(1),2L)
  pairs[order(first,second)]
}
spatial_join <- function(point_root,rectangle_root) {
  answer <- list()
  nodes <- tests <- 0L
  pending <- list(list(point_root,rectangle_root))
  while (length(pending)) {
    pair <- pending[[length(pending)]]
    pending <- head(pending,-1L)
    a <- pair[[1L]]
    b <- pair[[2L]]
    nodes <- nodes+1L
    if (!length(a$children) && !length(b$children)) {
      tests <- tests+length(a$held)*length(b$held)
      for (point in a$held) for (rectangle in b$held) if (contains(object_box(rectangle),point_box(point)))
        answer[[length(answer)+1L]] <- c(rectangle[1L],point[1L])
    } else {
      left <- if (length(a$children)) a$children else list(a)
      right <- if (length(b$children)) b$children else list(b)
      children <- list()
      for (u in left) for (v in right) if (intersects(
          u$region,
          v$region
      )) children[[length(children)+1L]] <- list(u,v)
      pending <- c(pending,rev(children))
    }
  }
  list(answer=sort_pairs(answer),nodes=nodes,tests=tests)
}
brute_force <- function(command,values,points,rectangles) {
  if (command %in% c("RANGE","RADIUS","CONTAINS")) {
    condition <- search_conditions(command,values)$object
    objects <- if (command == "CONTAINS") rectangles else points
    return(sort(vapply(Filter(condition,objects),`[`,integer(1),1L)))
  }
  if (command == "WINDOWCOUNT") return(sum(vapply(
      points,
      function(p) contains(values,point_box(p)),
      logical(1)
  )))
  if (command %in% c("KNN","NEAREST")) {
    q <- values[1:2]
    k <- values[3L]
    objects <- if (command == "NEAREST") rectangles else points
    lengths <- vapply(objects,function(object) object_distance(q,object),integer(1))
    identifiers <- vapply(objects,`[`,integer(1),1L)
    indices <- head(order(lengths,identifiers),k)
    return(lapply(indices,function(i) c(identifiers[i],lengths[i])))
  }
  answer <- list()
  for (rectangle in rectangles) for (point in points) if (contains(object_box(rectangle),point_box(point)))
    answer[[length(answer)+1L]] <- c(rectangle[1L],point[1L])
  sort_pairs(answer)
}
structures_for <- function(command) if (command == "JOIN") c("rtree","str") else if (command %in% c(
    "CONTAINS",
    "NEAREST"
)) RECTANGLE_STRUCTURES else POINT_STRUCTURES
locate_kd <- function(node,point) {
  path <- ""
  while (node$point[1L] != point[1L]) {
    left <- key_less(kd_key(point,node$axis),kd_key(node$point,node$axis))
    path <- paste0(path,if (left) "L" else "R")
    node <- if (left) node$left else node$right
  }
  if (nzchar(path)) path else "-"
}
locate_quad <- function(node,point) {
  path <- character()
  while (length(node$children)) {
    destination <- quad_destination(node,point)
    path <- c(path,CHILD_NAMES[destination])
    node <- node$children[[destination]]
  }
  if (length(path)) paste(path,collapse="/") else "-"
}
locate_rtree <- function(root,point) {
  pending <- list(list(node=root,path=integer()))
  while (length(pending)) {
    item <- pending[[length(pending)]]
    pending <- head(pending,-1L)
    node <- item$node
    if (node$level == 0L) {
      position <- which(vapply(node$entries,function(entry) entry$id == point[1L],logical(1)))
      if (length(position)) return(paste(c(item$path,position[1L]),collapse="/"))
    } else {
      for (i in rev(seq_along(node$entries))) {
        entry <- node$entries[[i]]
        if (contains(entry$box,point_box(point))) pending[[length(pending)+1L]] <- list(
            node=entry$child,
            path=c(item$path,i)
        )
      }
    }
  }
  "-"
}
dump_tree <- function(name,root) {
  lines <- character()
  for (view in preorder(root)) {
    prefix <- strrep("  ",view$depth+1L)
    if (name == "kdtree") {
      axis <- if (view$source$axis == 0L) "x" else "y"
      line <- paste(view$mark,axis,ids(view$held[[1L]]),"box",ids(view$region))
    } else if (name == "quadtree") {
      node <- view$source
      contents <- if (length(view$children)) paste(
          "node count",
          view$count
      ) else paste("leaf",ids(vapply(view$held,`[`,integer(1),1L)))
      line <- paste(view$mark,node$x,node$y,node$size,contents)
    } else if (view$source$level == 0L) {
      line <- paste("leaf",ids(view$region),"ids",ids(vapply(view$held,`[`,integer(1),1L)))
    } else line <- paste("node",view$source$level,ids(view$region),"entries",length(view$source$entries))
    lines <- c(lines,paste0(prefix,line))
  }
  lines
}
kd_statistics <- function(root) {
  nodes <- preorder(root)
  depths <- vapply(nodes,function(view) view$depth,integer(1))
  child_counts <- vapply(nodes,function(view) length(view$children),integer(1))
  height <- max(depths)+1L
  n <- length(nodes)
  ideal <- 0L
  capacity <- 0L
  while (capacity < n) {
    capacity <- 2L*capacity+1L
    ideal <- ideal+1L
  }
  lines <- paste("kdtree height",height,"ideal",ideal,"nodes",n,"leaves",sum(child_counts == 0L),"one_child",sum(child_counts == 1L),
    "depth_sum",sum(depths),"avg_depth",fraction(sum(depths),n))
  for (depth in seq_len(height)-1L) {
    group <- child_counts[depths == depth]
    lines <- c(
        lines,
        paste("  depth",depth,"nodes",length(group),"leaves",sum(group == 0L),"one_child",sum(group == 1L))
    )
  }
  lines
}
quad_statistics <- function(root,capacity) {
  nodes <- preorder(root)
  depths <- vapply(nodes,function(view) view$depth,integer(1))
  leaf <- !vapply(nodes,function(view) length(view$children) > 0L,logical(1))
  counts <- vapply(nodes,function(view) length(view$held),integer(1))
  height <- max(depths)+1L
  lines <- paste("quadtree height",height,"internal",sum(!leaf),"leaves",sum(leaf),"empty",sum(leaf & counts == 0L),
    "max_leaf",max(counts[leaf]),"fill",fraction(root$count,sum(leaf)*capacity))
  for (depth in seq_len(height)-1L) lines <- c(lines,paste("  depth",depth,"internal",sum(depths == depth & !leaf),
    "leaves",sum(depths == depth & leaf),"points",sum(counts[depths == depth & leaf])))
  lines
}
rtree_statistics <- function(name,root,maximum,minimum) {
  nodes <- preorder(root)
  levels <- vapply(nodes,function(view) view$source$level,integer(1))
  sizes <- vapply(nodes,function(view) length(view$source$entries),integer(1))
  height <- root$source$level+1L
  lines <- paste(
      name,
      "height",
      height,
      "nodes",
      length(nodes),
      "leaves",
      sum(levels == 0L),
      "entries",
      sum(sizes),
      "fill",
      fraction(sum(sizes),length(nodes)*maximum)
  )
  for (level in seq.int(height-1L,0L)) {
    indices <- which(levels == level)
    group <- nodes[indices]
    local_sizes <- sizes[indices]
    area_sum <- sum(vapply(group,function(view) area(view$region),integer(1)))
    overlap_sum <- 0L
    if (length(group) > 1L) for (i in seq_len(length(group)-1L)) for (j in seq.int(
        i+1L,
        length(group)
    )) overlap_sum <- overlap_sum+overlap(
        group[[i]]$region,
        group[[j]]$region
    )
    lines <- c(lines,paste("  level",level,"nodes",length(group),"entries",sum(local_sizes),"min",min(local_sizes),"max",max(local_sizes),
      "under",sum(local_sizes < minimum),"area",area_sum,"overlap",overlap_sum))
  }
  lines
}
grid_statistics <- function(root) {
  counts <- vapply(root$children,function(view) length(view$held),integer(1))
  occupancy <- vapply(sort(unique(counts)),function(k) paste0(k,":",sum(counts == k)),character(1))
  c(
      paste("grid cells",length(counts),"used",sum(counts > 0L),"max",max(counts)),
      paste("  occupancy",paste(occupancy,collapse=" "))
  )
}
snapshot <- function(views,number,query,point_count,rectangle_count,params) {
  header <- paste("snapshot",number,"query",query,"points",point_count,"rects",rectangle_count)
  structures <- header
  stats <- c(header,kd_statistics(views$kdtree),quad_statistics(views$quadtree,params$bucket))
  for (name in c("kdtree","quadtree",RTREE_STRUCTURES)) {
    structures <- c(structures,name,dump_tree(name,views[[name]]))
    if (name %in% RTREE_STRUCTURES) stats <- c(
        stats,
        rtree_statistics(name,views[[name]],params$maximum,params$minimum)
    )
  }
  list(structures=structures,stats=c(stats,grid_statistics(views$grid)))
}
visits_summary <- function(totals) {
  lines <- "visits"
  for (command in SEARCH_COMMANDS) {
    if (is.null(totals[[command]])) next
    names <- structures_for(command)
    rows <- totals[[command]]
    for (name in names) {
      row <- rows[[name]]
      lines <- c(
          lines,
          paste(
              command,
              name,
              "queries",
              row[1L],
              "nodes",
              row[2L],
              "tests",
              row[3L],
              "max_nodes",
              row[4L],
              "mean_nodes",
              fraction(row[2L],row[1L])
          )
      )
    }
    ranks <- order(vapply(rows[names],`[`,integer(1),2L),vapply(rows[names],`[`,integer(1),3L),seq_along(names))
    lines <- c(lines,paste("rank",command,paste(names[ranks],collapse=" ")))
  }
  lines
}
main <- function() {
  inputs <- read_dataset()
  initial <- inputs$points
  rectangle_rows <- inputs$rectangles
  params <- inputs$parameters
  points <- setNames(initial,vapply(initial,function(point) as.character(point[1L]),character(1)))
  rectangles <- setNames(
      rectangle_rows,
      vapply(rectangle_rows,function(rectangle) as.character(rectangle[1L]),character(1))
  )
  kd <- kd_build(initial)
  quad <- quad_build(initial,params$world,params$bucket)
  grid <- make_grid(params$world,params$cell_size,initial)
  trees <- list()
  for (name in RTREE_STRUCTURES) trees[[name]] <- rtree_build(if (name %in% RECTANGLE_STRUCTURES) rectangle_rows else initial,
    params$maximum,params$minimum,bulk=name %in% c("str","str_rect"))
  refresh_views <- function() {
    views <- list(kdtree=kd_view(kd,params$world),quadtree=quad_view(quad),grid=grid_view(grid))
    for (name in RTREE_STRUCTURES) views[[name]] <- rtree_view(
        trees[[name]]$root,
        if (name %in% RECTANGLE_STRUCTURES) rectangles else points
    )
    views
  }
  views <- refresh_views()
  saved <- snapshot(views,0L,0L,length(points),length(rectangles),params)
  structures <- saved$structures
  stats <- saved$stats
  answers <- character()
  visits <- "query,command,structure,nodes,tests"
  join_rows <- "query,rect,point"
  totals <- list()
  snapshot_number <- 0L
  for (q in seq_along(inputs$commands)) {
    command <- inputs$commands[[q]]
    name <- command$name
    values <- command$values
    if (name %in% SEARCH_COMMANDS) {
      expected <- brute_force(name,values,unname(points),unname(rectangles))
      mismatches <- character()
      for (structure in structures_for(name)) {
        root <- views[[structure]]
        result <- if (name %in% c("RANGE","RADIUS","CONTAINS")) condition_search(
            root,
            search_conditions(name,values)
        ) else
          if (name == "WINDOWCOUNT") window_count(root,values) else if (name == "JOIN") spatial_join(
              root,
              views[[paste0(structure,"_rect")]]
          ) else
            best_first(root,values[1:2],values[3L])
        if (!isTRUE(all.equal(
            result$answer,
            expected,
            tolerance=0,
            check.attributes=FALSE
        ))) mismatches <- c(mismatches,structure)
        visits <- c(visits,paste(q,name,structure,result$nodes,result$tests,sep=","))
        if (is.null(totals[[name]])) totals[[name]] <- list()
        row <- totals[[name]][[structure]]
        if (is.null(row)) row <- integer(4L)
        row[1L] <- row[1L]+1L
        row[2L] <- row[2L]+result$nodes
        row[3L] <- row[3L]+result$tests
        row[4L] <- max(row[4L],result$nodes)
        totals[[name]][[structure]] <- row
      }
      check <- if (length(mismatches)) paste("mismatch",paste(mismatches,collapse=" ")) else "ok"
      if (name == "WINDOWCOUNT") {
        line <- paste(q,name,"count",expected,"check",check)
      } else if (name == "JOIN") {
        line <- paste(q,name,"count",length(expected),"check",check)
        for (pair in expected) join_rows <- c(join_rows,paste(q,pair[1L],pair[2L],sep=","))
      } else {
        sequence <- if (name %in% c("KNN","NEAREST")) distances(expected) else ids(expected)
        line <- paste(q,name,"count",length(expected),"ids",sequence,"check",check)
      }
      answers <- c(answers,line)
    } else if (name == "LOCATE") {
      identifier <- values[1L]
      point <- points[[as.character(identifier)]]
      if (is.null(point)) {
        answers <- c(answers,paste(q,"LOCATE",identifier,"missing"))
      } else {
        position <- grid_position(grid,point)
        answers <- c(answers,paste(q,"LOCATE",identifier,"kdtree",locate_kd(kd,point),"quadtree",locate_quad(quad,point),
          "rtree",locate_rtree(
              trees$rtree$root,
              point
          ),"str",locate_rtree(trees$str$root,point),"grid",position[1L],position[2L]))
      }
    } else if (name == "INSERT") {
      point <- values
      points[[as.character(point[1L])]] <- point
      kd <- kd_insert(kd,point)
      quad_insert(quad,point,params$bucket)
      for (structure in c("rtree","str")) rtree_insert(
          trees[[structure]],
          rentry(point_box(point),id=point[1L])
      )
      grid_insert(grid,point)
      views <- refresh_views()
      answers <- c(answers,paste(q,"INSERT",point[1L],"inserted points",length(points)))
    } else if (name == "DELETE") {
      identifier <- values[1L]
      key <- as.character(identifier)
      point <- points[[key]]
      status <- "missing"
      if (!is.null(point)) {
        kd <- kd_delete(kd,point)
        quad_delete(quad,point,params$bucket)
        for (structure in c("rtree","str")) rtree_delete(trees[[structure]],point)
        grid_delete(grid,point)
        points[[key]] <- NULL
        views <- refresh_views()
        status <- "deleted"
      }
      answers <- c(answers,paste(q,"DELETE",identifier,status,"points",length(points)))
    } else {
      snapshot_number <- snapshot_number+1L
      saved <- snapshot(views,snapshot_number,q,length(points),length(rectangles),params)
      structures <- c(structures,"",saved$structures)
      stats <- c(stats,"",saved$stats)
      answers <- c(answers,paste(q,"DUMP snapshot",snapshot_number))
    }
  }
  stats <- c(stats,"",visits_summary(totals))
  files <- list(
      "answers.txt"=answers,
      "visits.csv"=visits,
      "join.csv"=join_rows,
      "structures.txt"=structures,
      "stats.txt"=stats
  )
  for (name in names(files)) write_lines(name,files[[name]])
}
main()
