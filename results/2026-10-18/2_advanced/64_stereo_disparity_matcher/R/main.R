source("pgm_io.R")
source("costs.R")
source("aggregation.R")
source("refinement.R")
source("evaluation.R")

METHODS <- c("sad","ssd","census","sgm","fusion","wta_final","sgm_final")
SELECTION_METHODS <- METHODS[1:4]
REASONS <- c(textureless=50,nonunique=100,outside=150,mismatch=200,occluded=255)
SOURCES <- c("kept","median","background","interpolated","none")
words <- function(...) paste(...,collapse=" ")
lower_median <- function(values) sort(values)[(length(values)+1L) %/% 2L]
neighbors4 <- function(p,width,height) {
  y <- (p-1L) %/% width
  x <- (p-1L) %% width
  result <- integer()
  for (point in list(
      c(x+1L,y),
      c(x-1L,y),
      c(x,y+1L),
      c(x,y-1L)
  )) if (point[1L] >= 0L && point[1L] < width && point[2L] >= 0L && point[2L] < height) result <- c(result,point[2L]*width+point[1L]+1L)
  result
}
select_disparities <- function(volume,strengths,width,height,params) {
  dmin <- params$disparity_min
  dmax <- params$disparity_max
  candidates <- dmin:dmax
  right <- numeric(nrow(volume))
  for (y in 0:(height-1L)) for (x in 0:(width-1L)) {
    p <- y*width+x+1L
    available <- candidates[x+candidates < width]
    if (length(available)) right[p] <- available[which.min(vapply(
        available,
        function(d) volume[p+d,d-dmin+1L],
        numeric(1)
    ))]
  }
  image <- reasons <- margins <- numeric(nrow(volume))
  lr <- numeric(4L)
  bounds <- 0L
  for (y in 0:(height-1L)) for (x in 0:(width-1L)) {
    p <- y*width+x+1L
    costs <- volume[p,]
    best <- which.min(costs)+dmin-1L
    first <- costs[best-dmin+1L]
    second <- min(costs[abs(candidates-best) >= 2L])
    bounds <- bounds+as.integer(best == dmin || best == dmax)
    consistent <- function(d) x >= d && abs(d-right[p-d]) <= params$lr_max_diff
    if (strengths[p] < params$texture_threshold) {
      reason <- 50
    } else if (100*second <= (100+params$uniqueness)*first) {
      reason <- 100
    } else if (x < best) {
      reason <- 150
    } else if (!consistent(best)) {
      reason <- if (any(vapply(candidates,consistent,logical(1)))) 200 else 255
    } else {
      reason <- 0
      image[p] <- best
      margins[p] <- second-first
    }
    reasons[p] <- reason
    if (reason %in% c(0,200,255)) {
      index <- min(abs(best-right[p-best]),3L)+1L
      lr[index] <- lr[index]+1L
    }
  }
  list(image=image,reasons=reasons,margins=margins,lr=lr,bounds=bounds)
}
connected_regions <- function(image,width,height,maximum_difference) {
  visited <- rep(FALSE,length(image))
  components <- list()
  for (start in seq_along(image)) {
    if (image[start] == 0 || visited[start]) next
    visited[start] <- TRUE
    stack <- start
    component <- integer()
    while (length(stack)) {
      p <- tail(stack,1L)
      stack <- head(stack,-1L)
      component <- c(component,p)
      for (q in neighbors4(
          p,
          width,
          height
      )) if (image[q] != 0 && !visited[q] && abs(image[q]-image[p]) <= maximum_difference) {
        visited[q] <- TRUE
        stack <- c(stack,q)
      }
    }
    components[[length(components)+1L]] <- component
  }
  components
}
ray_values <- function(image,width,height,x,y,directions) {
  values <- numeric()
  for (direction in directions) {
    xx <- x+direction[1L]
    yy <- y+direction[2L]
    while (xx >= 0L && xx < width && yy >= 0L && yy < height) {
      value <- image[yy*width+xx+1L]
      if (value != 0) {
        values <- c(values,value)
        break
      }
      xx <- xx+direction[1L]
      yy <- yy+direction[2L]
    }
  }
  values
}
postprocess <- function(selection,width,height,params) {
  original <- filtered <- selection$image
  removed <- Filter(
      function(part) length(part) < params$speckle_size,
      connected_regions(original,width,height,params$speckle_range)
  )
  for (part in removed) filtered[part] <- 0
  medians <- numeric(length(original))
  for (y in 0:(height-1L)) for (x in 0:(width-1L)) {
    p <- y*width+x+1L
    if (filtered[p] == 0) next
    values <- numeric()
    for (yy in max(0L,y-1L):min(height-1L,y+1L)) for (xx in max(0L,x-1L):min(width-1L,x+1L)) {
      value <- filtered[yy*width+xx+1L]
      if (value != 0) values <- c(values,value)
    }
    medians[p] <- lower_median(values)
  }
  result <- medians
  sources <- rep("none",length(original))
  for (y in 0:(height-1L)) for (x in 0:(width-1L)) {
    p <- y*width+x+1L
    if (medians[p] != 0) {
      sources[p] <- if (medians[p] == original[p]) "kept" else "median"
    } else if (selection$reasons[p] %in% c(150,255)) {
      values <- ray_values(medians,width,height,x,y,list(c(-1L,0L),c(1L,0L)))
      if (length(values)) {
        result[p] <- min(values)
        sources[p] <- "background"
      }
    } else {
      values <- ray_values(medians,width,height,x,y,DIRECTIONS)
      if (length(values)) {
        result[p] <- lower_median(values)
        sources[p] <- "interpolated"
      }
    }
  }
  list(
      image=result,
      sources=sources,
      speckles=length(removed),
      speckle_pixels=sum(lengths(removed)),
      median_changed=sum(filtered != medians),
      background=sum(sources == "background"),
      interpolated=sum(sources == "interpolated"),
      unfilled=sum(sources == "none")
  )
}
fuse <- function(methods,minimum_votes) {
  result <- numeric(length(methods$sad$image))
  votes <- numeric(5L)
  for (p in seq_along(result)) {
    candidates <- vapply(SELECTION_METHODS,function(name) methods[[name]]$image[p],numeric(1))
    candidates <- candidates[candidates != 0]
    votes[length(candidates)+1L] <- votes[length(candidates)+1L]+1L
    if (length(candidates)) {
      median <- lower_median(candidates)
      if (sum(abs(candidates-median) <= 1L) >= minimum_votes) result[p] <- median
    }
  }
  list(image=result,votes=votes)
}
extract_objects <- function(image,truth,width,height,params) {
  layers <- sort(unique(truth[truth != 0]))
  counts <- setNames(vapply(layers,function(layer) sum(truth == layer),numeric(1)),as.character(layers))
  objects <- list()
  small <- 0L
  for (component in connected_regions(image,width,height,params$object_range)) {
    if (length(component) < params$object_min_size) {
      small <- small+1L
      next
    }
    xs <- (component-1L) %% width
    ys <- (component-1L) %/% width
    disparities <- image[component]
    n <- length(component)
    median <- lower_median(disparities)
    total <- sum(disparities)
    box <- c(min(xs),min(ys),max(xs),max(ys))
    known <- truth[component]
    known <- known[known != 0]
    layer <- NULL
    if (length(known)) {
      candidates <- sort(unique(known))
      layer <- candidates[which.max(vapply(candidates,function(g) sum(known == g),numeric(1)))]
    }
    hits <- if (is.null(layer)) 0L else sum(known == layer)
    union_count <- if (is.null(layer)) 0L else n+counts[[as.character(layer)]]-hits
    objects[[length(objects)+1L]] <- list(
        pixels=n,
        box=box,
        minimum=min(disparities),
        maximum=max(disparities),
        median=median,
        mean=two_decimals(total,n),
        depth=two_decimals(params$focal_length*params$baseline*n,total),
        width=two_decimals((box[3L]-box[1L]+1L)*params$baseline,median),
        height=two_decimals((box[4L]-box[2L]+1L)*params$baseline,median),
        truth=layer,
        hits=hits,
        union_count=union_count,
        first=min(component)
    )
  }
  if (length(objects)) objects <- objects[order(
      -vapply(objects,function(o) o$median,numeric(1)),
      -vapply(objects,function(o) o$pixels,integer(1)),
      vapply(objects,function(o) o$first,numeric(1))
  )]
  detected <- unique(unlist(lapply(
      objects,
      function(o) if (!is.null(o$truth) && 2*o$hits > o$union_count) o$truth else NULL
  )))
  lines <- words(
      "objects",
      length(objects),
      "small",
      small,
      "pixels",
      sum(vapply(objects,function(o) o$pixels,integer(1)))
  )
  for (number in seq_along(objects)) {
    o <- objects[[number]]
    truth_text <- if (is.null(o$truth)) "truth - iou -" else words(
        "truth",
        o$truth,
        "iou",
        ratio(o$hits,o$union_count)
    )
    lines <- c(
        lines,
        words(
            "object",
            number,
            "pixels",
            o$pixels,
            "box",
            paste(o$box,collapse=" "),
            "disparity",
            o$minimum,
            o$maximum,
            "median",
            o$median,
            "mean",
            o$mean,
            "depth",
            o$depth,
            "size",
            o$width,
            o$height,
            truth_text
        )
    )
  }
  missed <- setdiff(layers,detected)
  c(
      lines,
      words(
          "layers",
          length(layers),
          "detected",
          length(detected),
          "missed",
          if (length(missed)) paste(missed,collapse=" ") else "-"
      )
  )
}
sample_lines <- function(methods,costs,truth,width,params) {
  lines <- "x,y,sad,ssd,census,sgm,disparity,source,subpixel,depth,truth,truth_depth"
  focal <- params$focal_length
  baseline <- params$baseline
  for (point in params$sample_pixels) {
    x <- point[1L]
    y <- point[2L]
    p <- y*width+x+1L
    values <- c(
        as.character(x),
        as.character(y),
        vapply(
            SELECTION_METHODS,
            function(name) if (methods[[name]]$image[p] == 0) "-" else integer_text(methods[[name]]$image[p]),
            character(1)
        )
    )
    d <- methods$sgm_final$image[p]
    if (d != 0) values <- c(
        values,
        integer_text(d),
        methods$sgm_final$sources[p],
        subpixel(d,costs[p,],params$disparity_min,params$disparity_max,focal,baseline)
    ) else values <- c(values,"-","none","-","-")
    values <- c(
        values,
        if (truth[p] == 0) c("-","-") else c(integer_text(truth[p]),two_decimals(focal*baseline,truth[p]))
    )
    lines <- c(lines,paste(values,collapse=","))
  }
  lines
}
method_lines <- function(name,method,truth,width,height,regions,scores,params) {
  image <- method$image
  values <- image[image != 0]
  lines <- words("method",name,"valid",length(values),"invalid",length(image)-length(values))
  lines <- c(
      lines,
      if (!length(values)) "disparity min - max - median - distinct 0" else words(
          "disparity min",
          min(values),
          "max",
          max(values),
          "median",
          lower_median(values),
          "distinct",
          length(unique(values))
      )
  )
  horizontal <- vertical <- 0L
  for (y in 0:(height-1L)) for (x in 0:(width-1L)) {
    p <- y*width+x+1L
    if (image[p] == 0) next
    horizontal <- horizontal+as.integer(x+1L < width && image[p+1L] != 0 && abs(image[p]-image[p+1L]) >= 2L)
    vertical <- vertical+as.integer(y+1L < height && image[p+width] != 0 && abs(image[p]-image[p+width]) >= 2L)
  }
  lines <- c(lines,words("jumps horizontal",horizontal,"vertical",vertical))
  if (name %in% SELECTION_METHODS) {
    lines <- c(
        lines,
        words("window",method$window,"bounds",method$bounds),
        paste(
            "reasons",
            paste(
                vapply(
                    names(REASONS),
                    function(reason) words(reason,sum(method$reasons == REASONS[[reason]])),
                    character(1)
                ),
                collapse=" "
            )
        ),
        words("lr 0",method$lr[1L],"1",method$lr[2L],"2",method$lr[3L],"3+",method$lr[4L])
    )
  } else if (name == "fusion") lines <- c(
      lines,
      paste("votes",paste(vapply(0:4,function(n) words(n,method$votes[n+1L]),character(1)),collapse=" "))
  ) else {
    lines <- c(
        lines,
        words(
            "postprocess speckles",
            method$speckles,
            method$speckle_pixels,
            "median",
            method$median_changed,
            "background",
            method$background,
            "interpolated",
            method$interpolated,
            "unfilled",
            method$unfilled
        )
    )
    for (source in SOURCES) {
      region <- regions$all[method$sources[regions$all] == source]
      score <- evaluate(image,truth,region)
      lines <- c(lines,words("source",source,"pixels",score$pixels,"bad1",ratio(score$bad1,score$pixels)))
    }
  }
  for (region in REGION_ORDER) {
    score <- scores[[region]]
    lines <- c(
        lines,
        words(
            "region",
            region,
            "pixels",
            score$pixels,
            "valid",
            score$valid,
            "bad1",
            ratio(score$bad1,score$pixels),
            "bad2",
            ratio(score$bad2,score$pixels),
            "mae",
            score$mae,
            "exact",
            score$exact
        )
    )
  }
  focal <- params$focal_length
  baseline <- params$baseline
  pixels <- regions$nonocc[image[regions$nonocc] != 0]
  errors <- vapply(
      pixels,
      function(p) abs(depth_hundredths(image[p],focal,baseline)-depth_hundredths(truth[p],focal,baseline)),
      numeric(1)
  )
  lines <- c(
      lines,
      if (!length(errors)) "depth_error pixels 0 mean - max -" else words(
          "depth_error pixels",
          length(errors),
          "mean",
          two_decimals(sum(errors),100*length(errors)),
          "max",
          two_decimals(max(errors),100)
      )
  )
  bins <- numeric(5L)
  invalid <- 0L
  for (p in regions$all) {
    if (image[p] == 0) invalid <- invalid+1L else {
      index <- min(abs(image[p]-truth[p]),4L)+1L
      bins[index] <- bins[index]+1L
    }
  }
  c(lines,words("errors 0",bins[1L],"1",bins[2L],"2",bins[3L],"3",bins[4L],"4+",bins[5L],"invalid",invalid))
}
rank_before <- function(a,b) {
  if (a$bad1 != b$bad1) return(a$bad1 < b$bad1)
  if (a$bad2 != b$bad2) return(a$bad2 < b$bad2)
  if ((a$valid == 0L) != (b$valid == 0L)) return(a$valid != 0L)
  if (a$valid && b$valid && a$error_sum*b$valid != b$error_sum*a$valid) return(a$error_sum*b$valid < b$error_sum*a$valid)
  FALSE
}
evaluation_lines <- function(s,methods,sweeps,progress) {
  width <- s$width
  height <- s$height
  left <- s$left
  right <- s$right
  truth <- s$truth
  strengths <- s$strengths
  regions <- s$regions
  params <- s$params
  scores <- setNames(
      lapply(
          METHODS,
          function(name) setNames(
              lapply(REGION_ORDER,function(region) evaluate(methods[[name]]$image,truth,regions[[region]])),
              REGION_ORDER
          )
      ),
      METHODS
  )
  delta <- right[regions$nonocc-truth[regions$nonocc]]-left[regions$nonocc]
  bias_sum <- sum(delta)
  bias <- two_decimals(abs(bias_sum),length(delta))
  if (bias_sum < 0 && bias != "0.00") bias <- paste0("-",bias)
  lines <- c(words("image",width,height),words("disparities",params$disparity_min,params$disparity_max))
  for (name in c("left","right")) {
    image <- s[[name]]
    lines <- c(
        lines,
        words(name,"mean",two_decimals(sum(image),length(image)),"min",min(image),"max",max(image))
    )
  }
  lines <- c(
      lines,
      words(
          "texture mean",
          two_decimals(sum(strengths),width*height),
          "textureless",
          sum(strengths < params$texture_threshold)
      ),
      words(
          "ground_truth known",
          length(regions$all),
          "nonocc",
          length(regions$nonocc),
          "occluded",
          length(regions$occluded),
          "disc",
          length(regions$disc),
          "unknown",
          width*height-length(regions$all)
      ),
      words(
          "photometric pixels",
          length(delta),
          "mean_abs",
          two_decimals(sum(abs(delta)),length(delta)),
          "bias",
          bias
      )
  )
  for (sweep in sweeps) {
    score <- sweep$metrics
    lines <- c(
        lines,
        words(
            "sweep",
            sweep$kind,
            "window",
            sweep$window,
            "valid",
            sweep$valid,
            "bad1",
            ratio(score$bad1,score$pixels),
            "bad2",
            ratio(score$bad2,score$pixels)
        )
    )
  }
  for (item in progress) {
    score <- item$metrics
    lines <- c(
        lines,
        words(
            "paths",
            item$number,
            "valid",
            item$valid,
            "bad1",
            ratio(score$bad1,score$pixels),
            "bad2",
            ratio(score$bad2,score$pixels)
        )
    )
  }
  for (name in METHODS) lines <- c(
      lines,
      method_lines(name,methods[[name]],truth,width,height,regions,scores[[name]],params)
  )
  for (region in REGION_ORDER) {
    ranking <- character()
    for (name in METHODS) {
      at <- length(ranking)+1L
      while (at > 1L && rank_before(scores[[name]][[region]],scores[[ranking[at-1L]]][[region]])) at <- at-1L
      ranking <- append(ranking,name,after=at-1L)
    }
    lines <- c(lines,words("ranking",region,paste(ranking,collapse=" ")))
  }
  for (name in SELECTION_METHODS) {
    method <- methods[[name]]
    tp <- sum(method$reasons[regions$occluded] %in% c(150,255))
    fp <- sum(method$reasons[regions$nonocc] %in% c(150,255))
    fn <- length(regions$occluded)-tp
    lines <- c(
        lines,
        words("occlusion",name,"tp",tp,"fp",fp,"fn",fn,"precision",ratio(tp,tp+fp),"recall",ratio(tp,tp+fn))
    )
  }
  for (name in SELECTION_METHODS) {
    method <- methods[[name]]
    pixels <- regions$nonocc[method$image[regions$nonocc] != 0]
    pixels <- pixels[order(-method$margins[pixels],pixels)]
    for (percentage in c(25L,50L,75L,100L)) {
      n <- (length(pixels)*percentage+99L) %/% 100L
      bad <- sum(abs(method$image[pixels[seq_len(n)]]-truth[pixels[seq_len(n)]]) > 1L)
      lines <- c(
          lines,
          words(
              "confidence",
              name,
              percentage,
              "pixels",
              n,
              "margin",
              if (n) method$margins[pixels[n]] else "-",
              "bad1",
              ratio(bad,n)
          )
      )
    }
  }
  for (layer in sort(unique(truth[truth != 0]))) {
    region <- regions$nonocc[truth[regions$nonocc] == layer]
    errors <- vapply(METHODS,function(name) evaluate(methods[[name]]$image,truth,region)$bad1,numeric(1))
    lines <- c(
        lines,
        words(
            "layer",
            layer,
            "pixels",
            sum(truth == layer),
            "nonocc",
            length(region),
            "bad1",
            paste(errors,collapse=" ")
        )
    )
  }
  for (d in params$disparity_min:params$disparity_max) lines <- c(
      lines,
      words("histogram",d,sum(methods$sgm_final$image == d))
  )
  lines
}
main <- function() {
  image <- read_pgm("input/left.pgm")
  width <- image$width
  height <- image$height
  left <- image$pixels
  right <- read_pgm("input/right.pgm")$pixels
  truth <- read_pgm("input/ground_truth.pgm")$pixels
  params <- read_parameters()
  regions <- truth_regions(truth,width,height)
  strengths <- texture(left,width,height,params$texture_window)
  cl <- census(left,width,height)
  cr <- census(right,width,height)
  volume <- function(kind,window) cost_volume(
      left,
      right,
      cl,
      cr,
      width,
      height,
      kind,
      window,
      params$disparity_min,
      params$disparity_max
  )
  methods <- list()
  sweeps <- list()
  for (kind in METHODS[1:3]) {
    best <- c(Inf,Inf)
    for (window in params[[paste0(kind,"_windows")]]) {
      selection <- select_disparities(volume(kind,window),strengths,width,height,params)
      selection$window <- window
      metrics <- evaluate(selection$image,truth,regions$nonocc)
      sweeps[[length(sweeps)+1L]] <- list(
          kind=kind,
          window=window,
          metrics=metrics,
          valid=sum(selection$image != 0)
      )
      if (metrics$bad1 < best[1L] || (metrics$bad1 == best[1L] && metrics$bad2 < best[2L])) {
        best <- c(metrics$bad1,metrics$bad2)
        methods[[kind]] <- selection
      }
    }
  }
  stages <- cumulative_costs(
      volume(params$sgm_cost,params$sgm_window),
      left,
      width,
      height,
      params$sgm_paths,
      params$p1,
      params$p2,
      params$p2_gamma
  )
  progress <- list()
  for (number in seq_along(stages)) {
    selection <- select_disparities(stages[[number]],strengths,width,height,params)
    progress[[number]] <- list(
        number=number,
        metrics=evaluate(selection$image,truth,regions$nonocc),
        valid=sum(selection$image != 0)
    )
    selection$window <- params$sgm_window
    methods$sgm <- selection
  }
  methods$fusion <- fuse(methods,params$fusion_min_votes)
  methods$wta_final <- postprocess(methods[[params$wta_cost]],width,height,params)
  methods$sgm_final <- postprocess(methods$sgm,width,height,params)
  dir.create("output",showWarnings=FALSE)
  write_pgm("output/disparity_wta.pgm",width,height,8*methods$wta_final$image)
  write_pgm("output/disparity_sgm.pgm",width,height,8*methods$sgm_final$image)
  write_pgm("output/occlusion.pgm",width,height,methods$sgm$reasons)
  error_image <- vapply(
      seq_along(truth),
      function(p) if (truth[p] == 0) 0 else if (methods$sgm_final$image[p] == 0) 255 else 50*(min(
          abs(methods$sgm_final$image[p]-truth[p]),
          3L
      )+1L),
      numeric(1)
  )
  write_pgm("output/error_sgm.pgm",width,height,error_image)
  s <- list(
      width=width,
      height=height,
      left=left,
      right=right,
      truth=truth,
      strengths=strengths,
      regions=regions,
      params=params
  )
  outputs <- list(
      "depth.csv"=sample_lines(methods,stages[[length(stages)]],truth,width,params),
      "evaluation.txt"=evaluation_lines(s,methods,sweeps,progress),
      "objects.txt"=extract_objects(methods$sgm_final$image,truth,width,height,params)
  )
  for (name in names(outputs)) writeLines(outputs[[name]],file.path("output",name),useBytes=TRUE)
}
main()
