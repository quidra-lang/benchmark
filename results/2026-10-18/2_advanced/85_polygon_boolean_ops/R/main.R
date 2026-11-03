source("rational.R")
source("intersections.R")
source("rings.R")
source("greiner_hormann.R")
source("render.R")
KINDS <- c(
    "UNION",
    "INTERSECTION",
    "DIFFERENCE",
    "XOR",
    "CLIP",
    "AREA",
    "MOVE",
    "ROTATE",
    "MIRROR",
    "SNAP",
    "LOCATE",
    "RENDER"
)
BINARY <- KINDS[1:5]
DEFINITIONS <- c("MOVE","ROTATE","MIRROR","SNAP")
WORD_COUNTS <- setNames(c(3,3,3,3,3,2,5,6,5,3,4,8),KINDS)
reject <- function(reason) stop(structure(
    list(message=reason,call=NULL),
    class=c("polygon_rejection","error","condition")
))
line <- function(...) paste(
    unlist(lapply(list(...),function(x) if (is.numeric(x)) sprintf("%.0f",x) else as.character(x))),
    collapse=" "
)
fixed3 <- function(value) sprintf("%.3f",value)
fixed6 <- function(value) sprintf("%.6f",value)
digits_word <- function(word) grepl("^[0-9]{1,9}$",word)
integer_word <- function(word) grepl("^-?[0-9]{1,9}$",word)
valid_name <- function(word) grepl("^[a-z0-9_]{1,16}$",word)
records <- function(name) {
    lines <- readLines(file.path("input",name),warn=FALSE)
    indices <- which(nzchar(lines) & !startsWith(lines,"#"))
    lapply(indices,function(i) list(number=i,text=lines[i]))
}
canonical_polygon <- function(name,input_rings) {
    holes <- sort_rings(lapply(input_rings[-1],normalize_ring,outer=FALSE))
    list(name=name,input_rings=input_rings,rings=c(list(normalize_ring(input_rings[[1]],TRUE)),holes))
}
parse_rings <- function(content,end_line) {
    result <- list()
    position <- 1L
    while (position <= length(content)) {
        record <- content[[position]]
        words <- strsplit(record$text," ",fixed=TRUE)[[1]]
        if (length(words) != 2L || !words[1] %in% c(
            "OUTER",
            "HOLE"
        ) || !digits_word(words[2]) || as.numeric(words[2]) < 1) return(list(error=record$number))
        if ((words[1] == "OUTER" && length(result)) || (words[1] == "HOLE" && !length(result))) return(list(error=record$number))
        n <- as.numeric(words[2])
        position <- position+1L
        vertices <- list()
        for (i in seq_len(n)) {
            if (position > length(content)) return(list(error=end_line))
            record <- content[[position]]
            words <- strsplit(record$text," ",fixed=TRUE)[[1]]
            if (length(words) != 2L || !all(vapply(
                words,
                integer_word,
                FALSE
            ))) return(list(error=record$number))
            vertices[[length(vertices)+1L]] <- point(as.numeric(words[1]),as.numeric(words[2]))
            position <- position+1L
        }
        result[[length(result)+1L]] <- vertices
    }
    if (length(result)) list(rings=result,error=0L) else list(error=end_line)
}
check_polygon <- function(sequence) {
    for (k in seq_along(sequence)) {
        ring <- sequence[[k]]
        n <- length(ring)
        if (n < 3L) return(line("too_few_vertices ring",k))
        for (p in ring) if (!(p[[1]] >= 0 && p[[1]] <= 1000 && p[[2]] >= 0 && p[[2]] <= 1000)) return(line(
            "out_of_range ring",
            k,
            point_text(p)
        ))
        seen <- character()
        for (p in ring) {
            key <- point_text(p)
            if (key %in% seen) return(line("duplicate_vertex ring",k,key))
            seen <- c(seen,key)
        }
        for (i in seq_len(n)) if (cross(
            ring[[(i-2L) %% n+1L]],
            ring[[i]],
            ring[[i %% n+1L]]
        ) == 0) return(line("collinear ring",k,point_text(ring[[i]])))
        edges <- ring_edges(ring)
        for (i in seq_len(n)) if (i+2L <= n) for (j in seq.int(i+2L,n)) {
            if (i == 1L && j == n) next
            a <- edges[[i]][[1]]
            b <- edges[[i]][[2]]
            c <- edges[[j]][[1]]
            d <- edges[[j]][[2]]
            if (segments_touch(a,b,c,d)) return(line(
                "self_intersection ring",
                k,
                segment_text(a,b),
                segment_text(c,d)
            ))
        }
    }
    for (i in seq_along(sequence)) if (i < length(sequence)) for (j in seq.int(i+1L,length(sequence))) {
        for (e in ring_edges(sequence[[i]])) for (f in ring_edges(sequence[[j]])) if (segments_touch(e[[1]],e[[2]],f[[1]],f[[2]])) return(line(
            "rings_touch rings",
            i,
            j,
            segment_text(e[[1]],e[[2]]),
            segment_text(f[[1]],f[[2]])
        ))
    }
    if (length(sequence) >= 2L) for (k in seq.int(2L,length(sequence))) if (!inside_ring(sequence[[1]],sequence[[k]][[1]])) return(line(
        "hole_outside ring",
        k,
        point_text(sequence[[k]][[1]])
    ))
    if (length(sequence) >= 3L) for (i in seq.int(
        2L,
        length(sequence)-1L
    )) for (j in seq.int(i+1L,length(sequence))) {
        p <- if (inside_ring(sequence[[i]],sequence[[j]][[1]])) sequence[[j]][[1]] else if (inside_ring(
            sequence[[j]],
            sequence[[i]][[1]]
        )) sequence[[i]][[1]] else NULL
        if (!is.null(p)) return(line("hole_in_hole rings",i,j,point_text(p)))
    }
    ""
}
read_registry <- function() {
    registry <- new.env(parent=emptyenv())
    registry$used <- character()
    registry$polygons <- list()
    registry$invalid <- character()
    registry$blocks <- registry$valid <- 0L
    lines <- records("polygons.txt")
    position <- 1L
    while (position <= length(lines)) {
        start <- lines[[position]]
        name <- strsplit(start$text," ",fixed=TRUE)[[1]][2]
        position <- position+1L
        content <- list()
        while (lines[[position]]$text != "END") {
            content[[length(content)+1L]] <- lines[[position]]
            position <- position+1L
        }
        end_line <- lines[[position]]$number
        position <- position+1L
        registry$blocks <- registry$blocks+1L
        reason <- ""
        if (name %in% registry$used) {
            reason <- line("duplicate_name line",start$number)
        } else {
            registry$used <- c(registry$used,name)
            parsed <- parse_rings(content,end_line)
            reason <- if (parsed$error != 0L) line(
                "format line",
                parsed$error
            ) else check_polygon(parsed$rings)
            if (!nzchar(reason)) {
                registry$polygons[[name]] <- canonical_polygon(name,parsed$rings)
                registry$valid <- registry$valid+1L
            }
        }
        if (nzchar(reason)) registry$invalid <- c(registry$invalid,line("polygon",name,reason))
    }
    registry
}
resolve_polygon <- function(registry,name) {
    if (!name %in% registry$used) reject(paste("unknown_polygon",name))
    if (is.null(registry$polygons[[name]])) reject(paste("invalid_polygon",name))
    registry$polygons[[name]]
}
arguments_valid <- function(words) {
    kind <- words[1]
    if (length(words) != WORD_COUNTS[[kind]]) return(FALSE)
    if (kind %in% c(BINARY,"AREA")) return(TRUE)
    if (kind == "SNAP") return(valid_name(words[3]))
    if (kind == "MIRROR") return(valid_name(words[5]) && words[3] %in% c(
        "x",
        "y"
    ) && integer_word(words[4]) && as.numeric(words[4]) >= 0 && as.numeric(words[4]) <= 1000)
    selected <- if (kind == "MOVE") words[3:4] else if (kind == "ROTATE") words[3:5] else words[-c(1,2)]
    if (!all(vapply(selected,integer_word,FALSE))) return(FALSE)
    v <- as.numeric(selected)
    if (kind == "LOCATE") return(all(v >= 0 & v <= 1000))
    if (kind == "MOVE") return(valid_name(words[5]) && all(v >= -1000 & v <= 1000))
    if (kind == "ROTATE") return(valid_name(words[6]) && all(v[1:2] >= 0 & v[1:2] <= 1000) && v[3] >= 1 && v[3] <= 3)
    v[1] >= 0 && v[2] >= 0 && v[3] >= 1 && v[3] <= 100 && v[4] >= 1 && v[4] <= 100 && v[5] >= 1 && v[5] <= 100 && v[6] >= 1 && v[6] <= 60 && v[1]+v[3]*v[5] <= 1000 && v[2]+v[4]*v[6] <= 1000
}
general_position <- function(first,second) {
    av <- unlist(first$rings,recursive=FALSE)
    bv <- unlist(second$rings,recursive=FALSE)
    bkeys <- vapply(bv,point_text,"")
    for (p in av) if (point_text(p) %in% bkeys) return(paste("shared_vertex",point_text(p)))
    ae <- unlist(lapply(first$rings,ring_edges),recursive=FALSE)
    be <- unlist(lapply(second$rings,ring_edges),recursive=FALSE)
    for (e in ae) for (f in be) if (segments_overlap(e[[1]],e[[2]],f[[1]],f[[2]])) return(line(
        "overlapping_edges",
        segment_text(e[[1]],e[[2]]),
        segment_text(f[[1]],f[[2]])
    ))
    for (side in 1:2) {
        source <- if (side == 1L) first else second
        other <- if (side == 1L) second else first
        edges <- if (side == 1L) be else ae
        for (ring in source$rings) for (p in ring) for (e in edges) if (on_segment(p,e[[1]],e[[2]])) return(line(
            "vertex_on_edge",
            source$name,
            point_text(p),
            other$name,
            segment_text(e[[1]],e[[2]])
        ))
    }
    ""
}
transformed_rings <- function(polygon,words) {
    lapply(polygon$input_rings,function(ring) lapply(ring,function(p) {
        x <- p[[1]]
        y <- p[[2]]
        if (words[1] == "MOVE") {
            x <- x+as.numeric(words[3])
            y <- y+as.numeric(words[4])
        } else if (words[1] == "ROTATE") {
            cx <- as.numeric(words[3])
            cy <- as.numeric(words[4])
            for (turn in seq_len(as.numeric(words[5]))) {
                previous_x <- x
                x <- cx-(y-cy)
                y <- cy+(previous_x-cx)
            }
        } else if (words[3] == "x") {
            x <- 2*as.numeric(words[4])-x
        } else {
            y <- 2*as.numeric(words[4])-y
        }
        list(x,y)
    }))
}
resolve_target <- function(registry,regions,word) {
    if (startsWith(word,"@")) {
        suffix <- substring(word,2L)
        if (!digits_word(suffix)) reject(paste("bad_target",word))
        key <- as.character(as.numeric(suffix))
        if (is.null(regions[[key]])) reject(paste("bad_target",word))
        return(regions[[key]])
    }
    polygon <- resolve_polygon(registry,word)
    list(polygons=list(polygon$rings),operands=NULL)
}
check_operation <- function(registry,regions,words) {
    kind <- words[1]
    if (!kind %in% KINDS) reject(paste("unknown_operation",kind))
    if (!arguments_valid(words)) reject("bad_arguments")
    first <- second <- target <- defined <- NULL
    if (kind %in% BINARY) {
        first <- resolve_polygon(registry,words[2])
        second <- resolve_polygon(registry,words[3])
    } else if (kind %in% c("AREA","MOVE","ROTATE","MIRROR")) {
        first <- resolve_polygon(registry,words[2])
    } else {
        target <- resolve_target(registry,regions,words[2])
    }
    new_name <- tail(words,1)
    if (kind %in% DEFINITIONS && new_name %in% registry$used) reject(paste("duplicate_name",new_name))
    if (kind == "SNAP" && length(target$polygons) != 1L) reject(paste("not_single",words[2]))
    if (kind == "CLIP") {
        window <- second$rings
        if (length(window) != 1L) reject(paste("not_convex",words[3]))
        ring <- window[[1]]
        n <- length(ring)
        if (any(vapply(
            seq_len(n),
            function(i) cross(ring[[(i-2L) %% n+1L]],ring[[i]],ring[[i %% n+1L]]) <= 0,
            FALSE
        ))) reject(paste("not_convex",words[3]))
    }
    if (kind %in% BINARY) {
        error <- general_position(first,second)
        if (nzchar(error)) reject(error)
    }
    if (kind %in% c("MOVE","ROTATE","MIRROR")) {
        sequence <- transformed_rings(first,words)
        vertices <- unlist(sequence,recursive=FALSE)
        if (any(vapply(
            vertices,
            function(p) !(p[[1]] >= 0 && p[[1]] <= 1000 && p[[2]] >= 0 && p[[2]] <= 1000),
            FALSE
        ))) reject(paste("out_of_range",new_name))
        defined <- canonical_polygon(new_name,sequence)
    } else if (kind == "SNAP") {
        sequence <- lapply(
            target$polygons[[1]],
            function(ring) lapply(
                ring,
                function(p) list(q(gmp::as.bigz(p[[1]]+q(1,2))),q(gmp::as.bigz(p[[2]]+q(1,2))))
            )
        )
        error <- check_polygon(sequence)
        if (nzchar(error)) reject(paste("invalid_result",error))
        defined <- canonical_polygon(new_name,sequence)
    }
    list(first=first,second=second,target=target,defined=defined)
}
total_area <- function(polygons) {
    total <- 0
    for (polygon in polygons) for (ring in polygon) total <- total+ring_area(ring)
    total
}
sort_polygons <- function(polygons) {
    result <- list()
    for (polygon in polygons) {
        position <- 1L
        while (position <= length(result) && !point_less(
            polygon[[1]][[1]],
            result[[position]][[1]][[1]]
        )) position <- position+1L
        result <- append(result,list(polygon),after=position-1L)
    }
    result
}
binary_result <- function(kind,first,second) {
    graph <- build_graph(first$rings,second$rings)
    intersection <- assemble_rings(traverse_graph(graph,FALSE,FALSE))
    union <- assemble_rings(traverse_graph(graph,TRUE,TRUE))
    polygons <- if (kind == "UNION") union else if (kind %in% c(
        "INTERSECTION",
        "CLIP"
    )) intersection else assemble_rings(traverse_graph(graph,TRUE,FALSE))
    if (kind == "XOR") {
        other <- build_graph(second$rings,first$rings)
        polygons <- sort_polygons(c(polygons,assemble_rings(traverse_graph(other,TRUE,FALSE))))
    }
    relation <- if (length(graph$crossings)) "overlap" else if (graph$n_a == length(first$rings) && graph$n_b == 0) "within" else if (graph$n_b == length(second$rings) && graph$n_a == 0) "contains" else if (graph$n_a == 0 && graph$n_b == 0) "disjoint" else "overlap"
    list(
        region=list(polygons=polygons,operands=list(first,second)),
        graph=graph,
        relation=relation,
        iou=total_area(intersection)/total_area(union)
    )
}
cyclic_equal <- function(a,b) {
    if (length(a) != length(b)) return(FALSE)
    any(vapply(
        seq_along(b),
        function(start) all(vapply(
            seq_along(a),
            function(i) point_equal(a[[i]],b[[(start+i-2L) %% length(b)+1L]]),
            FALSE
        )),
        FALSE
    ))
}
crosscheck_clip <- function(first,window,polygons) {
    clipped <- list()
    for (ring in first$rings) {
        points <- ring
        for (edge in ring_edges(window$rings[[1]])) {
            replacement <- list()
            for (i in seq_along(points)) {
                previous <- points[[(i-2L) %% length(points)+1L]]
                current <- points[[i]]
                a <- cross(edge[[1]],edge[[2]],previous)
                b <- cross(edge[[1]],edge[[2]],current)
                if ((a > 0) != (b > 0)) replacement[[length(replacement)+1L]] <- clipping_point(
                    previous,
                    current,
                    a,
                    b
                )
                if (b > 0) replacement[[length(replacement)+1L]] <- current
            }
            points <- replacement
        }
        keep <- vapply(
            seq_along(points),
            function(i) !point_equal(points[[i]],points[[(i-2L) %% length(points)+1L]]),
            FALSE
        )
        deduplicated <- points[keep]
        if (length(deduplicated) >= 3L) clipped[[length(clipped)+1L]] <- deduplicated
    }
    result_rings <- unlist(polygons,recursive=FALSE)
    matches <- length(result_rings) == length(clipped) && all(vapply(
        result_rings,
        function(r) any(vapply(clipped,function(s) cyclic_equal(r,s),FALSE)),
        FALSE
    ))
    line(
        "crosscheck",
        if (matches) "match" else "mismatch",
        "rings",
        length(clipped),
        "vertices",
        sum(lengths(clipped))
    )
}
result_values <- function(polygons,first,second) {
    lines <- character()
    av <- vapply(unlist(first$rings,recursive=FALSE),point_text,"")
    bv <- if (is.null(second)) character() else vapply(unlist(second$rings,recursive=FALSE),point_text,"")
    origins <- integer(3L)
    vertices <- list()
    ring_count <- hole_count <- 0L
    total <- perimeter <- sx <- sy <- 0
    for (k in seq_along(polygons)) for (j in seq_along(polygons[[k]])) {
        ring <- polygons[[k]][[j]]
        ring_count <- ring_count+1L
        hole_count <- hole_count+as.integer(j > 1L)
        area <- ring_area(ring)
        total <- total+area
        perimeter <- perimeter+ring_perimeter(ring)
        prefix <- if (j == 1L) line("outer",k) else line("hole",k,j-1L)
        lines <- c(lines,line(prefix,length(ring),fixed3(area),vapply(ring,point_text,"")))
        vertices <- c(vertices,ring)
        for (edge in ring_edges(ring)) {
            a <- edge[[1]]
            b <- edge[[2]]
            key <- point_text(a)
            index <- if (key %in% av) 1L else if (key %in% bv) 2L else 3L
            origins[index] <- origins[index]+1L
            ar <- vapply(a,coordinate_real,0)
            br <- vapply(b,coordinate_real,0)
            c <- ar[1]*br[2]-br[1]*ar[2]
            sx <- sx+(ar[1]+br[1])*c
            sy <- sy+(ar[2]+br[2])*c
        }
    }
    lines <- c(
        line(
            "polygons",
            length(polygons),
            "rings",
            ring_count,
            "holes",
            hole_count,
            "vertices",
            length(vertices),
            "area",
            fixed3(total)
        ),
        lines
    )
    if (!length(vertices)) {
        lines <- c(lines,"bbox none","centroid none")
    } else {
        low <- high <- vertices[[1]]
        for (p in vertices) for (axis in 1:2) {
            if (p[[axis]] < low[[axis]]) low[[axis]] <- p[[axis]]
            if (p[[axis]] > high[[axis]]) high[[axis]] <- p[[axis]]
        }
        lines <- c(
            lines,
            line("bbox",point_text(low),point_text(high)),
            paste0("centroid (",fixed3(sx/(6*total)),",",fixed3(sy/(6*total)),")")
        )
    }
    lines <- c(
        lines,
        line("perimeter",fixed3(perimeter)),
        line("origins a",origins[1],"b",origins[2],"crossing",origins[3])
    )
    list(lines=lines,rings=ring_count,holes=hole_count,vertices=length(vertices),area=total)
}
property_lines <- function(polygon,area) {
    orientations <- vapply(polygon$input_rings,function(ring) {
        total <- q(0)
        for (edge in ring_edges(ring)) total <- total+edge[[1]][[1]]*edge[[2]][[2]]-edge[[2]][[1]]*edge[[1]][[2]]
        if (total > 0) "ccw" else "cw"
    },"")
    reflex <- 0L
    for (ring in polygon$rings) {
        n <- length(ring)
        for (i in seq_len(n)) if (cross(
            ring[[(i-2L) %% n+1L]],
            ring[[i]],
            ring[[i %% n+1L]]
        ) < 0) reflex <- reflex+1L
    }
    ordered <- sort_points(
        polygon$rings[[1]],
        function(a,b) if (a[[1]] == b[[1]]) a[[2]] < b[[2]] else a[[1]] < b[[1]]
    )
    chains <- list()
    for (sequence in list(ordered,rev(ordered))) {
        chain <- list()
        for (p in sequence) {
            while (length(chain) >= 2L && cross(
                chain[[length(chain)-1L]],
                chain[[length(chain)]],
                p
            ) <= 0) chain <- chain[-length(chain)]
            chain[[length(chain)+1L]] <- p
        }
        chains[[length(chains)+1L]] <- chain
    }
    hull <- c(head(chains[[1]],-1),head(chains[[2]],-1))
    total <- q(0)
    for (edge in ring_edges(hull)) total <- total+edge[[1]][[1]]*edge[[2]][[2]]-edge[[2]][[1]]*edge[[1]][[2]]
    hull_area <- coordinate_real(total/2)
    c(
        line("input",orientations),
        line("reflex",reflex),
        line("hull",length(hull),fixed3(hull_area),"solidity",fixed6(area/hull_area))
    )
}
locate <- function(polygons,p) {
    for (k in seq_along(polygons)) {
        polygon <- polygons[[k]]
        if (boundary(polygon[[1]],p)) return(line("boundary outer",k))
        if (length(polygon) >= 2L) for (j in seq.int(2L,length(polygon))) if (boundary(polygon[[j]],p)) return(line(
            "boundary hole",
            k,
            j-1L
        ))
    }
    for (k in seq_along(polygons)) {
        polygon <- polygons[[k]]
        if (inside_ring(polygon[[1]],p) && !any(vapply(
            polygon[-1],
            function(r) inside_ring(r,p),
            FALSE
        ))) return(line("inside polygon",k))
    }
    "outside"
}
operand_location <- function(polygon,p) if (any(vapply(
    polygon$rings,
    function(r) boundary(r,p),
    FALSE
))) "boundary" else if (interior(polygon$rings,p)) "inside" else "outside"
main <- function() {
    registry <- read_registry()
    operations <- records("operations.txt")
    regions <- list()
    results <- drawings <- rejected <- character()
    areas <- "operation,rings,holes,vertices,area"
    kind_totals <- kind_succeeded <- setNames(integer(length(KINDS)),KINDS)
    succeeded <- defined <- crossings <- 0L
    for (number in seq_along(operations)) {
        record <- operations[[number]]
        words <- strsplit(record$text," ",fixed=TRUE)[[1]]
        kind <- words[1]
        if (kind %in% KINDS) kind_totals[kind] <- kind_totals[kind]+1L
        checked <- tryCatch(check_operation(registry,regions,words),polygon_rejection=function(error) error)
        if (inherits(checked,"polygon_rejection")) {
            rejected <- c(rejected,line("op",number,checked$message))
            next
        }
        succeeded <- succeeded+1L
        kind_succeeded[kind] <- kind_succeeded[kind]+1L
        if (kind %in% DEFINITIONS) {
            registry$polygons[[checked$defined$name]] <- checked$defined
            registry$used <- c(registry$used,checked$defined$name)
            defined <- defined+1L
        }
        if (kind == "RENDER") {
            parameters <- as.numeric(words[-c(1,2)])
            grid <- do.call(
                render_grid,
                c(list(polygons=checked$target$polygons,operands=checked$target$operands),as.list(parameters))
            )
            counts <- grid$counts
            drawings <- c(
                drawings,
                line(
                    "render",
                    number,
                    words[2],
                    "cols",
                    parameters[5],
                    "rows",
                    parameters[6],
                    "result",
                    counts["#"],
                    "a",
                    counts["a"],
                    "b",
                    counts["b"],
                    "both",
                    counts["+"]
                ),
                grid$lines
            )
        } else if (kind == "LOCATE") {
            p <- point(as.numeric(words[3]),as.numeric(words[4]))
            results <- c(
                results,
                line("op",number,record$text),
                line("location",locate(checked$target$polygons,p))
            )
            if (!is.null(checked$target$operands)) {
                operands <- checked$target$operands
                results <- c(
                    results,
                    line("operands a",operand_location(operands[[1]],p),"b",operand_location(operands[[2]],p))
                )
            }
        } else {
            results <- c(results,line("op",number,record$text))
            first <- checked$first
            second <- checked$second
            if (kind %in% BINARY) {
                binary <- binary_result(kind,first,second)
                region <- binary$region
                graph <- binary$graph
                results <- c(
                    results,
                    line("relation",binary$relation,"iou",fixed6(binary$iou)),
                    line("crossings",length(graph$crossings))
                )
                crossings <- crossings+length(graph$crossings)
                for (id in graph$crossings) {
                    node <- graph$nodes[[id]]
                    results <- c(
                        results,
                        line("crossing",point_text(node$point),if (node$entering) "in" else "out")
                    )
                }
            } else {
                first <- if (kind %in% DEFINITIONS) checked$defined else first
                second <- NULL
                region <- list(polygons=list(first$rings),operands=NULL)
            }
            regions[[as.character(number)]] <- region
            values <- result_values(region$polygons,first,second)
            results <- c(results,values$lines)
            if (!kind %in% BINARY) results <- c(results,property_lines(first,values$area))
            if (kind == "CLIP") results <- c(results,crosscheck_clip(first,second,region$polygons))
            areas <- c(
                areas,
                paste0(
                    number,
                    ":",
                    paste(words,collapse=":"),
                    ",",
                    values$rings,
                    ",",
                    values$holes,
                    ",",
                    values$vertices,
                    ",",
                    fixed3(values$area)
                )
            )
        }
    }
    results <- c(results,line("summary polygons",registry$blocks,"valid",registry$valid,"invalid",length(registry$invalid),"defined",defined),
                 line(
                     "summary operations",
                     length(operations),
                     "succeeded",
                     succeeded,
                     "rejected",
                     length(rejected)
                 ),line("summary crossings",crossings))
    for (kind in KINDS) results <- c(results,line("kind",kind,kind_totals[kind],kind_succeeded[kind]))
    rejections <- c(line("rejections",length(registry$invalid)+length(rejected)),registry$invalid,rejected)
    dir.create("output",showWarnings=FALSE)
    reports <- list(results.txt=results,areas.csv=areas,render.txt=drawings,rejections.txt=rejections)
    for (name in names(reports)) writeLines(reports[[name]],file.path("output",name),useBytes=TRUE)
}
main()
