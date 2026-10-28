source("matrix.R")
source("kalman.R")
source("association.R")
source("imm.R")
source("evaluation.R")

FILTERS <- c("cv","ca","abg","imm","rts")
words <- function(...) paste(...,collapse=" ")
optional <- function(value) if (is.null(value)) "-" else as.character(value)
listed <- function(keyword,items) paste(keyword,if (length(items)) paste(items,collapse=" ") else "none")
segments <- function(scans,labels) {
  result <- list()
  for (i in seq_along(scans)) {
    n <- length(result)
    if (n && result[[n]][2L]+1L == scans[i] && result[[n]][3L] == labels[i]) result[[n]][2L] <- scans[i] else result[[n+1L]] <- c(
        scans[i],
        scans[i],
        labels[i]
    )
  }
  result
}
path_length <- function(positions) {
  if (length(positions) < 2L) return(0)
  ordered_total(vapply(
      seq.int(2L,length(positions)),
      function(i) distance(positions[[i-1L]],positions[[i]]),
      numeric(1)
  ))
}
rmse <- function(errors) sqrt(ordered_total(errors)/length(errors))
filter_scores <- function(values) {
  rounded <- vapply(FILTERS,function(name) as.numeric(real_text(values[[name]])),numeric(1))
  paste(
      paste(FILTERS,vapply(FILTERS,function(name) real_text(values[[name]]),character(1)),collapse=" "),
      "best",
      FILTERS[which.min(rounded)]
  )
}
framed <- function(grid) {
  border <- paste0("+",strrep("-",ncol(grid)),"+")
  c(
      border,
      vapply(seq_len(nrow(grid)),function(row) paste0("|",paste(grid[row,],collapse=""),"|"),character(1)),
      border
  )
}
read_inputs <- function() {
  measurements <- list()
  times <- numeric()
  truth <- list()
  params <- list()
  for (line in readLines("input/measurements.csv")[-1L]) {
    fields <- strsplit(line,",",fixed=TRUE)[[1L]]
    scan <- as.integer(fields[1L])
    if (length(measurements) < scan) measurements[[scan]] <- list()
    times[scan] <- as.numeric(fields[2L])
    measurements[[scan]][[length(measurements[[scan]])+1L]] <- as.numeric(fields[3:4])
  }
  for (line in readLines("input/truth.csv")[-1L]) {
    fields <- strsplit(line,",",fixed=TRUE)[[1L]]
    target <- fields[1L]
    scan <- fields[2L]
    if (is.null(truth[[target]])) truth[[target]] <- list()
    truth[[target]][[scan]] <- as.numeric(fields[3:4])
  }
  for (line in readLines("input/params.txt")) {
    fields <- strsplit(line," ",fixed=TRUE)[[1L]]
    name <- fields[1L]
    params[[name]] <- if (name == "MODEL") fields[2L] else if (name %in% c(
        "CONFIRM",
        "DELETE",
        "PLOT_SIZE"
    )) as.integer(fields[-1L]) else as.numeric(fields[-1L])
  }
  list(measurements=measurements,times=times,truth=truth,params=params)
}
parameter <- function(s,name) s$params[[name]][1L]
make_kalman <- function(s,model,measurement) {
  new_kalman(
      model,
      parameter(s,paste0("Q_",model)),
      parameter(s,"SIGMA"),
      parameter(s,"INIT_VELOCITY_VARIANCE"),
      parameter(s,"INIT_ACCELERATION_VARIANCE"),
      measurement
  )
}
new_track <- function(number,scan,measurement,kalman) {
  observations <- list()
  observations[[as.character(scan)]] <- measurement
  list2env(
      list(
          number=number,
          birth=scan,
          last_hit=scan,
          kalman=kalman,
          confirmed=NULL,
          deleted=NULL,
          status="tentative",
          hits=1L,
          consecutive_misses=0L,
          observations=observations,
          nis=list(),
          target=NULL,
          primary_matches=list()
      ),
      parent=emptyenv()
  )
}
track_all_scans <- function(s) {
  required_hits <- s$params$CONFIRM[1L]
  window <- s$params$CONFIRM[2L]
  for (scan in seq_len(s$scans)) {
    key <- as.character(scan)
    live <- Filter(function(track) track$status != "deleted",s$tracks)
    measurements <- s$measurements[[scan]]
    if (scan > 1L) for (track in live) predict_filter(track$kalman,s$times[scan]-s$times[scan-1L])
    usable <- matrix(Inf,length(live),length(measurements))
    innovations <- vector("list",length(live)*length(measurements))
    row_gates <- integer(length(live))
    column_gates <- integer(length(measurements))
    for (row in seq_along(live)) for (column in seq_along(measurements)) {
      info <- innovation(live[[row]]$kalman,measurements[[column]])
      if (info$distance2 <= parameter(s,"GATE")) {
        usable[row,column] <- info$distance2
        innovations[[(row-1L)*length(measurements)+column]] <- info
        row_gates[row] <- row_gates[row]+1L
        column_gates[column] <- column_gates[column]+1L
      }
    }
    assigned <- optimal_assignment(length(live),length(measurements),usable)
    candidates <- which(is.finite(usable),arr.ind=TRUE)
    if (nrow(candidates)) candidates <- candidates[
        order(usable[candidates],candidates[,1L],candidates[,2L]),
        ,
        drop=FALSE
    ]
    greedy <- matrix(integer(),0L,2L)
    used_rows <- integer()
    used_columns <- integer()
    for (i in seq_len(nrow(candidates))) {
      row <- candidates[i,1L]
      column <- candidates[i,2L]
      if (!(row %in% used_rows) && !(column %in% used_columns)) {
        greedy <- rbind(greedy,c(row,column))
        used_rows <- c(used_rows,row)
        used_columns <- c(used_columns,column)
      }
    }
    if (nrow(greedy)) greedy <- greedy[order(greedy[,1L],greedy[,2L]),,drop=FALSE]
    s$counters[3L] <- s$counters[3L]+as.integer(!identical(unname(assigned),unname(greedy)))
    matches <- integer(length(live))
    if (nrow(assigned)) matches[assigned[,1L]] <- assigned[,2L]
    missed <- confirmed <- deleted <- integer()
    for (row in seq_along(live)) {
      track <- live[[row]]
      column <- matches[row]
      if (column != 0L) {
        measurement <- measurements[[column]]
        update_filter(track$kalman,measurement,innovations[[(row-1L)*length(measurements)+column]])
        track$observations[[key]] <- measurement
        track$nis[[key]] <- usable[row,column]
        track$last_hit <- scan
        track$hits <- track$hits+1L
        track$consecutive_misses <- 0L
      } else {
        track$observations[key] <- list(NULL)
        track$consecutive_misses <- track$consecutive_misses+1L
        missed <- c(missed,track$number)
      }
      if (track$status == "confirmed") {
        if (track$consecutive_misses >= parameter(s,"DELETE")) {
          track$status <- "deleted"
          track$deleted <- scan
          deleted <- c(deleted,track$number)
        }
      } else if (track$hits >= required_hits) {
        track$status <- "confirmed"
        track$confirmed <- scan
        confirmed <- c(confirmed,track$number)
      } else if (scan-track$birth+1L >= window) {
        track$status <- "deleted"
        track$deleted <- scan
        deleted <- c(deleted,track$number)
      }
    }
    used_columns <- assigned[,2L]
    created <- list()
    for (column in seq_along(measurements)) {
      if (column %in% used_columns) next
      measurement <- measurements[[column]]
      track <- new_track(length(s$tracks)+1L,scan,measurement,make_kalman(s,s$params$MODEL,measurement))
      s$tracks[[length(s$tracks)+1L]] <- track
      created[[length(created)+1L]] <- list(track=track,column=column)
    }
    conflicts_m <- sum(column_gates >= 2L)
    conflicts_t <- sum(row_gates >= 2L)
    s$counters[1L] <- s$counters[1L]+conflicts_m
    s$counters[2L] <- s$counters[2L]+conflicts_t
    gated <- which(is.finite(usable),arr.ind=TRUE)
    if (nrow(gated)) gated <- gated[order(gated[,1L],gated[,2L]),,drop=FALSE]
    pair_text <- function(pairs) vapply(
        seq_len(nrow(pairs)),
        function(i) paste0(live[[pairs[i,1L]]]$number,":",pairs[i,2L]),
        character(1)
    )
    s$log <- c(s$log,words("scan",scan,"tracks",length(live),"measurements",length(measurements)),
      listed(
          "gate",
          vapply(
              seq_len(nrow(gated)),
              function(i) paste0(
                  live[[gated[i,1L]]]$number,
                  ":",
                  gated[i,2L],
                  "=",
                  real_text(usable[gated[i,1L],gated[i,2L]])
              ),
              character(1)
          )
      ),
      listed("assign",pair_text(assigned)),listed("greedy",pair_text(greedy)),listed("missed",missed),
      listed(
          "new",
          vapply(created,function(item) paste0(item$track$number,":",item$column),character(1))
      ),listed("confirmed",confirmed),listed("deleted",deleted),
      words(
          "status tentative",
          sum(vapply(s$tracks,function(t) t$status == "tentative",logical(1))),
          "confirmed",
          sum(vapply(s$tracks,function(t) t$status == "confirmed",logical(1)))
      ),
      words("conflicts measurements",conflicts_m,"tracks",conflicts_t))
    processed <- c(live,lapply(created,function(item) item$track))
    for (track in processed) s$track_rows <- c(
        s$track_rows,
        paste(
            c(track$number,scan,vapply(track$kalman$x[1:4],real_text,character(1)),track$status),
            collapse=","
        )
    )
  }
  s$evaluated <- Filter(function(track) !is.null(track$confirmed),s$tracks)
}
abg_estimates <- function(s,track) {
  alpha <- s$params$ABG[1L]
  beta <- s$params$ABG[2L]
  gamma <- s$params$ABG[3L]
  state <- c(track$observations[[as.character(track$birth)]],rep(0,4L))
  estimates <- list()
  for (scan in track$span) {
    if (scan > track$birth) {
      interval <- s$times[scan]-s$times[scan-1L]
      measurement <- track$observations[[as.character(scan)]]
      for (axis in 1:2) {
        position <- state[axis]
        velocity <- state[axis+2L]
        acceleration <- state[axis+4L]
        position <- position+interval*velocity+interval*interval*acceleration/2
        velocity <- velocity+interval*acceleration
        if (!is.null(measurement)) {
          residual <- measurement[axis]-position
          position <- position+alpha*residual
          velocity <- velocity+beta*residual/interval
          acceleration <- acceleration+2*gamma*residual/(interval*interval)
        }
        state[axis] <- position
        state[axis+2L] <- velocity
        state[axis+4L] <- acceleration
      }
    }
    estimates[[as.character(scan)]] <- state[1:4]
  }
  estimates
}
compare_filters <- function(s) {
  for (track in s$evaluated) {
    track$span <- seq.int(track$birth,track$last_hit)
    track$estimates <- setNames(lapply(FILTERS,function(unused) list()),FILTERS)
    track$model_logs <- list()
    histories <- list()
    for (name in c("cv","ca")) {
      filter <- make_kalman(s,toupper(name),track$observations[[as.character(track$birth)]])
      history <- list()
      likelihood <- 0
      for (scan in track$span) {
        key <- as.character(scan)
        if (scan > track$birth) {
          predict_filter(filter,s$times[scan]-s$times[scan-1L])
          measurement <- track$observations[[key]]
          if (!is.null(measurement)) likelihood <- likelihood+update_filter(filter,measurement)$likelihood
        }
        track$estimates[[name]][[key]] <- filter$x[1:4]
        history[[length(history)+1L]] <- filter_snapshot(filter)
      }
      histories[[name]] <- history
      track$model_logs[[name]] <- likelihood
    }
    track$estimates$abg <- abg_estimates(s,track)
    history <- histories[[s$primary]]
    track$primary_covariances <- setNames(lapply(history,function(state) state$p),as.character(track$span))
    track$estimates$rts <- setNames(
        lapply(smooth(history),function(state) state[1:4]),
        as.character(track$span)
    )
    imm <- new_imm(
        s$params$IMM_Q,
        s$params$IMM_TRANSITION,
        s$params$IMM_INITIAL,
        parameter(s,"SIGMA"),
        parameter(s,"INIT_VELOCITY_VARIANCE"),
        track$observations[[as.character(track$birth)]]
    )
    track$high <- list()
    for (scan in track$span) {
      key <- as.character(scan)
      if (scan > track$birth) imm_step(imm,s$times[scan]-s$times[scan-1L],track$observations[[key]])
      track$estimates$imm[[key]] <- imm_estimate(imm)
      track$high[[key]] <- imm$probabilities[2L]
    }
    track$nis_values <- vapply(
        track$nis[intersect(as.character(track$span),names(track$nis))],
        identity,
        numeric(1)
    )
    gap <- longest <- 0L
    for (scan in track$span) {
      gap <- if (is.null(track$observations[[as.character(scan)]])) gap+1L else 0L
      longest <- max(longest,gap)
    }
    track$longest_gap <- longest
    track$path <- path_length(track$estimates$rts)
  }
}
evaluate_scans <- function(s) {
  s$labels <- setNames(
      lapply(
          FILTERS,
          function(unused) setNames(
              lapply(s$targets,function(unused) integer(s$scans)),
              as.character(s$targets)
          )
      ),
      FILTERS
  )
  s$ospa_values <- setNames(lapply(FILTERS,function(unused) numeric()),FILTERS)
  s$scan_sizes <- list()
  for (scan in seq_len(s$scans)) {
    key <- as.character(scan)
    tracks <- Filter(function(track) track$birth <= scan && scan <= track$last_hit,s$evaluated)
    targets <- s$targets[vapply(
        s$targets,
        function(target) !is.null(s$truth[[as.character(target)]][[key]]),
        logical(1)
    )]
    s$scan_sizes[[scan]] <- c(length(targets),length(tracks))
    positions <- lapply(targets,function(target) s$truth[[as.character(target)]][[key]])
    for (name in FILTERS) {
      estimates <- lapply(tracks,function(track) track$estimates[[name]][[key]])
      usable <- matrix(Inf,length(tracks),length(targets))
      for (row in seq_along(estimates)) for (column in seq_along(positions)) {
        value <- distance(estimates[[row]],positions[[column]])
        if (value <= parameter(s,"MATCH_DISTANCE")) usable[row,column] <- value
      }
      pairs <- optimal_assignment(length(tracks),length(targets),usable)
      for (i in seq_len(nrow(pairs))) {
        track <- tracks[[pairs[i,1L]]]
        target <- targets[pairs[i,2L]]
        s$labels[[name]][[as.character(target)]][scan] <- track$number
        if (name == s$primary) track$primary_matches[[key]] <- target
      }
      s$ospa_values[[name]] <- c(s$ospa_values[[name]],ospa(estimates,positions,parameter(s,"OSPA_CUTOFF")))
    }
  }
  s$continuities <- setNames(
      lapply(
          FILTERS,
          function(name) setNames(
              lapply(
                  s$targets,
                  function(target) continuity(s$labels[[name]][[as.character(target)]][as.integer(names(s$truth[[as.character(target)]]))])
              ),
              as.character(s$targets)
          )
      ),
      FILTERS
  )
}
match_tracks <- function(s) {
  usable <- matrix(Inf,length(s$evaluated),length(s$targets))
  details <- list()
  cutoff <- parameter(s,"OSPA_CUTOFF")
  for (row in seq_along(s$evaluated)) for (column in seq_along(s$targets)) {
    track <- s$evaluated[[row]]
    target <- as.character(s$targets[column])
    positions <- s$truth[[target]]
    common <- intersect(track$span,as.integer(names(positions)))
    if (!length(common)) next
    distances <- setNames(
        vapply(
            common,
            function(scan) distance(
                track$estimates[[s$primary]][[as.character(scan)]],
                positions[[as.character(scan)]]
            ),
            numeric(1)
        ),
        as.character(common)
    )
    if (!any(distances < cutoff)) next
    union_scans <- sort(union(track$span,as.integer(names(positions))))
    cost <- ordered_total(vapply(
        union_scans,
        function(scan) if (as.character(scan) %in% names(distances)) min(
            cutoff,
            distances[[as.character(scan)]]
        ) else cutoff,
        numeric(1)
    ))/length(union_scans)
    usable[row,column] <- cost
    details[[paste(row,column)]] <- common
  }
  s$matched_tracks <- list()
  pairs <- optimal_assignment(length(s$evaluated),length(s$targets),usable)
  for (i in seq_len(nrow(pairs))) {
    row <- pairs[i,1L]
    column <- pairs[i,2L]
    track <- s$evaluated[[row]]
    target <- s$targets[column]
    track$target <- target
    track$common <- details[[paste(row,column)]]
    track$mean_distance <- usable[row,column]
    s$matched_tracks[[as.character(target)]] <- track
  }
}
evaluate_errors <- function(s) {
  s$target_results <- list()
  overall_position <- overall_velocity <- setNames(lapply(FILTERS,function(unused) numeric()),FILTERS)
  for (target in s$targets) {
    key <- as.character(target)
    if (is.null(s$matched_tracks[[key]])) next
    track <- s$matched_tracks[[key]]
    positions <- s$truth[[key]]
    velocities <- list()
    for (scan in track$common) if (!is.null(positions[[as.character(scan-1L)]]) && !is.null(positions[[as.character(scan+1L)]])) velocities[[as.character(scan)]] <- (positions[[as.character(scan+1L)]]-positions[[as.character(scan-1L)]])/(s$times[scan+1L]-s$times[scan-1L])
    position_scores <- velocity_scores <- list()
    for (name in FILTERS) {
      pe <- vapply(
          track$common,
          function(scan) squared_distance(
              track$estimates[[name]][[as.character(scan)]],
              positions[[as.character(scan)]]
          ),
          numeric(1)
      )
      ve <- vapply(
          names(velocities),
          function(scan) squared_distance(track$estimates[[name]][[scan]][3:4],velocities[[scan]]),
          numeric(1)
      )
      position_scores[[name]] <- rmse(pe)
      velocity_scores[[name]] <- rmse(ve)
      overall_position[[name]] <- c(overall_position[[name]],pe)
      overall_velocity[[name]] <- c(overall_velocity[[name]],ve)
    }
    nees <- vapply(track$common,function(scan) {
      key <- as.character(scan)
      quadratic2(
          track$estimates[[s$primary]][[key]][1:2]-positions[[key]],
          matrix_inverse(track$primary_covariances[[key]][1:2,1:2,drop=FALSE])
      )
    },numeric(1))
    s$target_results[[key]] <- list(
        track=track,
        position=position_scores,
        velocity=velocity_scores,
        velocity_count=length(velocities),
        nees=nees
    )
  }
  s$overall_position <- lapply(overall_position,rmse)
  s$overall_velocity <- lapply(overall_velocity,rmse)
}
evaluation_lines <- function(s) {
  lines <- c(
      "summary",
      words("scans",s$scans),
      words("measurements",sum(lengths(s$measurements))),
      words("targets",length(s$targets)),
      words("tracks_created",length(s$tracks)),
      words("tracks_confirmed",length(s$evaluated)),
      words("false_tracks",sum(vapply(s$evaluated,function(t) !length(t$primary_matches),logical(1)))),
      words("missed_targets",length(s$targets)-length(s$matched_tracks)),
      words("measurements_used",sum(vapply(s$evaluated,function(t) t$hits,integer(1)))),
      words("conflict_measurements",s$counters[1L]),
      words("conflict_tracks",s$counters[2L]),
      words("greedy_differences",s$counters[3L]),
      "",
      "targets"
  )
  for (target in s$targets) {
    positions <- s$truth[[as.character(target)]]
    scans <- as.integer(names(positions))
    path <- path_length(positions)
    lines <- c(
        lines,
        words(
            "target",
            target,
            "first",
            scans[1L],
            "last",
            tail(scans,1L),
            "scans",
            length(scans),
            "path",
            real_text(path),
            "mean_speed",
            real_text(path/(s$times[tail(scans,1L)]-s$times[scans[1L]]))
        )
    )
  }
  lines <- c(lines,"","tracks")
  bound <- parameter(s,"CONSISTENCY_BOUND")
  for (track in s$evaluated) {
    n <- length(track$nis_values)
    lines <- c(
        lines,
        words(
            "track",
            track$number,
            "birth",
            track$birth,
            "confirmed",
            track$confirmed,
            "end",
            track$last_hit,
            "deleted",
            optional(track$deleted),
            "hits",
            track$hits,
            "misses",
            length(track$span)-track$hits,
            "longest_gap",
            track$longest_gap,
            "path",
            real_text(track$path),
            "nis",
            real_text(ordered_total(track$nis_values)/n),
            "nis_inside",
            paste0(sum(track$nis_values <= bound),"/",n)
        )
    )
  }
  lines <- c(lines,"","matching")
  for (track in s$evaluated) {
    text <- words("track",track$number,"target",optional(track$target))
    if (!is.null(track$target)) text <- paste(
        text,
        words("common",length(track$common),"mean_distance",real_text(track$mean_distance))
    )
    scans <- sort(as.integer(names(track$primary_matches)))
    ranges <- segments(
        scans,
        vapply(as.character(scans),function(scan) track$primary_matches[[scan]],integer(1))
    )
    lines <- c(
        lines,
        paste(
            text,
            words(
                "matched_scans",
                length(track$primary_matches),
                listed("segments",vapply(ranges,function(r) paste0(r[1L],"-",r[2L],":",r[3L]),character(1)))
            )
        )
    )
  }
  lines <- c(lines,"","rmse")
  for (target in s$targets) {
    result <- s$target_results[[as.character(target)]]
    if (is.null(result)) lines <- c(lines,words("target",target,"track -")) else {
      lines <- c(
          lines,
          words(
              "target",
              target,
              "track",
              result$track$number,
              "common",
              length(result$track$common),
              filter_scores(result$position)
          ),
          words("target",target,"velocity",result$velocity_count,filter_scores(result$velocity))
      )
    }
  }
  lines <- c(
      lines,
      paste("overall position",filter_scores(s$overall_position)),
      paste("overall velocity",filter_scores(s$overall_velocity)),
      "",
      "consistency"
  )
  for (target in s$targets) {
    result <- s$target_results[[as.character(target)]]
    if (is.null(result)) lines <- c(lines,words("target",target,"track -")) else lines <- c(
        lines,
        words(
            "target",
            target,
            "track",
            result$track$number,
            "nees",
            real_text(ordered_total(result$nees)/length(result$nees)),
            "inside",
            paste0(sum(result$nees <= bound),"/",length(result$nees))
        )
    )
  }
  nis <- unlist(lapply(s$evaluated,function(track) track$nis_values),use.names=FALSE)
  edges <- s$params$NIS_EDGES
  observed <- integer(length(edges)+1L)
  for (value in nis) {
    bin <- 1L+sum(edges <= value)
    observed[bin] <- observed[bin]+1L
  }
  expected <- numeric()
  lower <- 0
  for (upper in c(edges,Inf)) {
    expected <- c(expected,length(nis)*(exp(-lower/2)-if (is.infinite(upper)) 0 else exp(-upper/2)))
    lower <- upper
  }
  lines <- c(
      lines,
      words(
          "nis_histogram total",
          length(nis),
          "observed",
          paste(observed,collapse=" "),
          "expected",
          paste(vapply(expected,real_text,character(1)),collapse=" ")
      ),
      "",
      "models"
  )
  for (track in s$evaluated) {
    cv <- track$model_logs$cv
    ca <- track$model_logs$ca
    lines <- c(
        lines,
        words(
            "track",
            track$number,
            "updates",
            length(track$nis_values),
            "cv",
            real_text(cv),
            "ca",
            real_text(ca),
            "better",
            if (cv >= ca) "cv" else "ca"
        )
    )
  }
  lines <- c(
      lines,
      "",
      words("ospa cutoff",real_text(parameter(s,"OSPA_CUTOFF")),"order 2"),
      "scan targets tracks cv ca abg imm rts"
  )
  for (scan in seq_len(s$scans)) lines <- c(
      lines,
      words(
          scan,
          s$scan_sizes[[scan]][1L],
          s$scan_sizes[[scan]][2L],
          paste(
              vapply(FILTERS,function(name) real_text(s$ospa_values[[name]][scan]),character(1)),
              collapse=" "
          )
      )
  )
  lines <- c(
      lines,
      paste(
          "mean",
          paste(
              vapply(
                  FILTERS,
                  function(name) real_text(ordered_total(s$ospa_values[[name]])/s$scans),
                  character(1)
              ),
              collapse=" "
          )
      ),
      "",
      "continuity"
  )
  for (name in FILTERS) {
    values <- s$continuities[[name]]
    lines <- c(
        lines,
        words(
            name,
            "covered",
            sum(vapply(values,function(v) v$covered,integer(1))),
            "breaks",
            sum(vapply(values,function(v) v$breaks,integer(1))),
            "swaps",
            sum(vapply(values,function(v) v$swaps,integer(1)))
        )
    )
    for (target in s$targets) {
      result <- values[[as.character(target)]]
      lines <- c(
          lines,
          words(
              "  target",
              target,
              "scans",
              length(s$truth[[as.character(target)]]),
              "covered",
              result$covered,
              "breaks",
              result$breaks,
              "swaps",
              result$swaps,
              "delay",
              optional(result$delay)
          )
      )
    }
  }
  lines <- c(lines,"","imm")
  for (track in s$evaluated) {
    high <- unlist(track$high,use.names=FALSE)
    index <- which.max(high)
    high_scans <- track$span[high > 0.5]
    ranges <- segments(high_scans,rep(1L,length(high_scans)))
    lines <- c(
        lines,
        words(
            "track",
            track$number,
            "mean_high",
            real_text(ordered_total(high)/length(high)),
            "max_high",
            real_text(high[index]),
            "at",
            track$span[index],
            "high_scans",
            length(high_scans),
            listed("segments",vapply(ranges,function(r) paste0(r[1L],"-",r[2L]),character(1)))
        )
    )
  }
  lines
}
plot_cell <- function(s,point) {
  xmin <- s$params$PLOT_X[1L]
  xmax <- s$params$PLOT_X[2L]
  ymin <- s$params$PLOT_Y[1L]
  ymax <- s$params$PLOT_Y[2L]
  width <- s$params$PLOT_SIZE[1L]
  height <- s$params$PLOT_SIZE[2L]
  column <- floor((point[1L]-xmin)/((xmax-xmin)/width))
  row <- floor((ymax-point[2L])/((ymax-ymin)/height))
  if (column >= 0 && column < width && row >= 0 && row < height) c(row+1L,column+1L) else NULL
}
plot_lines <- function(s) {
  width <- s$params$PLOT_SIZE[1L]
  height <- s$params$PLOT_SIZE[2L]
  xmin <- s$params$PLOT_X[1L]
  xmax <- s$params$PLOT_X[2L]
  ymin <- s$params$PLOT_Y[1L]
  ymax <- s$params$PLOT_Y[2L]
  characters <- setNames(
      vapply(
          seq_along(s$evaluated),
          function(i) intToUtf8(if (i <= 26L) utf8ToInt("A")+i-1L else utf8ToInt("a")+i-27L),
          character(1)
      ),
      vapply(s$evaluated,function(track) as.character(track$number),character(1))
  )
  trajectory <- matrix(" ",height,width)
  for (target in s$targets) for (point in s$truth[[as.character(target)]]) {
    cell <- plot_cell(s,point)
    if (!is.null(cell)) trajectory[cell[1L],cell[2L]] <- "."
  }
  for (track in s$evaluated) for (point in track$estimates$rts) {
    cell <- plot_cell(s,point)
    if (!is.null(cell)) trajectory[cell[1L],cell[2L]] <- characters[[as.character(track$number)]]
  }
  lines <- c(
      words(
          "tracks x",
          real_text(xmin),
          real_text(xmax),
          "y",
          real_text(ymin),
          real_text(ymax),
          "size",
          width,
          height
      ),
      framed(trajectory)
  )
  for (track in s$evaluated) lines <- c(
      lines,
      words(characters[[as.character(track$number)]],"track",track$number,"target",optional(track$target))
  )
  counts <- matrix(0L,height,width)
  for (measurements in s$measurements) for (measurement in measurements) {
    cell <- plot_cell(s,measurement)
    if (!is.null(cell)) counts[cell[1L],cell[2L]] <- counts[cell[1L],cell[2L]]+1L
  }
  density <- matrix(
      vapply(
          as.vector(counts),
          function(value) if (value == 0L) " " else if (value < 10L) as.character(value) else "#",
          character(1)
      ),
      height,
      width
  )
  lines <- c(lines,"","measurements",framed(density),"","timeline")
  for (target in s$targets) {
    labels <- s$labels[[s$primary]][[as.character(target)]]
    timeline <- vapply(
        seq_len(s$scans),
        function(scan) if (is.null(s$truth[[as.character(target)]][[as.character(scan)]])) " " else if (labels[scan] == 0L) "." else characters[[as.character(labels[scan])]],
        character(1)
    )
    lines <- c(lines,paste0(target," |",paste(timeline,collapse=""),"|"))
  }
  heights <- floor(10*s$ospa_values[[s$primary]]/parameter(s,"OSPA_CUTOFF"))
  bars <- matrix(" ",10L,s$scans)
  for (row in seq_len(10L)) for (column in seq_len(s$scans)) if (heights[column] >= 11L-row) bars[
      row,
      column
  ] <- "#"
  c(lines,"",paste("ospa",s$primary),framed(bars))
}
main <- function() {
  s <- list2env(read_inputs(),parent=emptyenv())
  s$scans <- length(s$measurements)
  s$targets <- sort(as.integer(names(s$truth)))
  s$primary <- tolower(s$params$MODEL)
  s$tracks <- list()
  s$track_rows <- "track,scan,x,y,vx,vy,status"
  s$log <- character()
  s$counters <- integer(3L)
  track_all_scans(s)
  compare_filters(s)
  evaluate_scans(s)
  match_tracks(s)
  evaluate_errors(s)
  smoothed <- "track,scan,x,y,vx,vy"
  for (track in s$evaluated) for (scan in track$span) smoothed <- c(
      smoothed,
      paste(
          c(track$number,scan,vapply(track$estimates$rts[[as.character(scan)]],real_text,character(1))),
          collapse=","
      )
  )
  outputs <- list(
      "tracks.csv"=s$track_rows,
      "smoothed.csv"=smoothed,
      "association_log.txt"=s$log,
      "evaluation.txt"=evaluation_lines(s),
      "track_plot.txt"=plot_lines(s)
  )
  dir.create("output",showWarnings=FALSE)
  for (name in names(outputs)) writeLines(outputs[[name]],file.path("output",name),useBytes=TRUE)
}
main()
