for (module in c("waveform_io","magnitude","picker","associator","locator")) source(paste0(module,".R"))
integer_text <- function(value) sprintf("%.0f",value)
scaled <- function(value,digits) if (value < 0) -floor(-value*10^digits+0.5) else floor(value*10^digits+0.5)
decimal <- function(value,digits) {
  integer <- scaled(value,digits)
  magnitude <- abs(integer)
  scale <- 10^digits
  remainder <- integer_text(magnitude %% scale)
  paste0(
      if (integer < 0) "-" else "",
      integer_text(magnitude %/% scale),
      ".",
      strrep("0",digits-nchar(remainder)),
      remainder
  )
}
time_notation <- function(sample) paste0(integer_text(sample %/% 100),".",sprintf("%02.0f",sample %% 100))
station_ordered <- function(picks) picks[order(vapply(picks,function(pick) pick$station,integer(1)))]
observations <- function(
    picks,
    stations,
    corrections=rep(0,length(stations))
) lapply(station_ordered(picks),function(pick)
  list(station=stations[[pick$station]],time=pick$sample/100-corrections[pick$station]))
locate_candidates <- function(candidates,stations,params) {
  events <- list()
  for (index in seq_along(candidates)) {
    candidate <- candidates[[index]]
    initial <- station_ordered(candidate$picks)
    first <- run_location(observations(initial,stations),params)
    passes <- list(list(picks=initial,run=first))
    dropped_indices <- which(abs(first$residuals) > params$residual_limit[1L])
    retained_indices <- which(abs(first$residuals) <= params$residual_limit[1L])
    dropped <- lapply(dropped_indices,function(i) list(pick=initial[[i]],error=first$residuals[i]))
    retained <- initial[retained_indices]
    rejected <- length(dropped) > 0L && length(retained) < params$min_stations[1L]
    if (rejected) {
      for (pick in initial) pick$state <- "rejected"
      event_number <- 0L
    } else {
      adopted <- first
      if (length(dropped)) {
        adopted <- run_location(observations(retained,stations),params)
        passes[[2L]] <- list(picks=retained,run=adopted)
      }
      event_number <- length(events)+1L
      for (i in seq_along(retained)) {
        pick <- retained[[i]]
        pick$state <- "used"
        pick$event <- event_number
        pick$first_residual <- adopted$residuals[i]
      }
      for (item in dropped) {
        item$pick$state <- "dropped"
        item$pick$event <- event_number
      }
      events[[event_number]] <- list(
          number=event_number,
          candidate=candidate$number,
          used=retained,
          first=adopted
      )
    }
    candidate$passes <- passes
    candidate$dropped <- dropped
    candidate$rejected <- rejected
    candidate$event <- event_number
    candidates[[index]] <- candidate
  }
  list(candidates=candidates,events=events)
}
station_time_corrections <- function(events,stations) {
  values <- replicate(length(stations),numeric(),simplify=FALSE)
  for (event in events) for (pick in event$used) values[[pick$station]] <- c(
      values[[pick$station]],
      pick$first_residual
  )
  vapply(values,function(v) if (length(v)) ordered_sum(v)/length(v) else 0,numeric(1))
}
quality_for_event <- function(event,stations,params) {
  solution <- event$final$solution
  used <- event$used
  obs <- event$observations
  velocity <- params$velocity[1L]
  ellipse <- error_ellipse(solution,obs,velocity)
  x <- solution[1L]
  y <- solution[2L]
  z <- solution[3L]
  angles <- vapply(used,function(pick) {
    station <- stations[[pick$station]]
    angle <- atan2(station$x-x,station$y-y)*180/PI_VALUE
    if (angle < 0) angle+360 else angle
  },numeric(1))
  angles <- sort(angles)
  gap <- max(c(diff(angles),angles[1L]+360-tail(angles,1L)))
  dmin <- min(vapply(
      used,
      function(pick) sqrt((stations[[pick$station]]$x-x)^2+(stations[[pick$station]]$y-y)^2),
      numeric(1)
  ))
  fits <- function(bounds) gap <= bounds[1L] && event$final$rms <= bounds[2L] && ellipse$smaj <= bounds[3L]
  grade <- if (fits(params$quality_a)) "A" else if (fits(params$quality_b)) "B" else "C"
  first <- event$first$solution
  dh <- sqrt((x-first[1L])^2+(y-first[2L])^2)
  dz <- z-first[3L]
  jackknife <- lapply(seq_along(used),function(i) {
    alternative <- geiger(solution,obs[-i],velocity)$solution
    dx <- alternative[1L]-x
    dy <- alternative[2L]-y
    dz <- alternative[3L]-z
    list(station=used[[i]]$station,dx=dx,dy=dy,dz=dz,shift=sqrt(dx*dx+dy*dy))
  })
  ellipse$gap <- gap
  ellipse$dmin <- dmin
  ellipse$grade <- grade
  ellipse$dh <- dh
  ellipse$dz <- dz
  ellipse$jackknife <- jackknife
  ellipse$max_jack <- jackknife[[which.max(vapply(jackknife,function(j) j$shift,numeric(1)))]]
  ellipse
}
relocate_events <- function(events,stations,params,corrections) {
  for (i in seq_along(events)) {
    event <- events[[i]]
    obs <- observations(event$used,stations,corrections)
    event$observations <- obs
    event$start_rms <- location_rms(event$first$solution,obs,params$velocity[1L])
    final <- geiger(event$first$solution,obs,params$velocity[1L])
    for (j in seq_along(event$used)) event$used[[j]]$residual <- final$residuals[j]
    event$final <- final
    event$solution <- final$solution
    event$quality <- quality_for_event(event,stations,params)
    events[[i]] <- event
  }
  events
}
compute_magnitudes <- function(events,stations,params) {
  station_residuals <- replicate(length(stations),numeric(),simplify=FALSE)
  for (i in seq_along(events)) {
    event <- events[[i]]
    magnitudes <- lapply(event$used,function(pick) {
      data <- per_pick_magnitude(pick,distance(event$solution,stations[[pick$station]])/1000,params)
      data$pick <- pick
      data
    })
    local_values <- vapply(
        Filter(function(item) !is.null(item$ml),magnitudes),
        function(item) item$ml,
        numeric(1)
    )
    ml <- if (length(local_values)) median_value(local_values) else NULL
    md <- median_value(vapply(magnitudes,function(item) item$md,numeric(1)))
    for (item in magnitudes) if (!is.null(item$ml)) {
      station <- item$pick$station
      station_residuals[[station]] <- c(station_residuals[[station]],item$ml-ml)
    }
    event$magnitudes <- magnitudes
    event$ml <- ml
    event$md <- md
    events[[i]] <- event
  }
  corrections <- vapply(
      station_residuals,
      function(values) if (length(values)) ordered_sum(values)/length(values) else 0,
      numeric(1)
  )
  for (i in seq_along(events)) {
    corrected <- vapply(
        Filter(function(item) !is.null(item$ml),events[[i]]$magnitudes),
        function(item) item$ml-corrections[item$pick$station],
        numeric(1)
    )
    events[[i]]$ml_corrected <- if (length(corrected)) median_value(corrected) else NULL
  }
  list(events=events,corrections=corrections,residuals=station_residuals)
}
travel_time_regression <- function(events,stations,params) {
  points <- list()
  for (event in events) for (pick in event$used) points[[length(points)+1L]] <- c(
      distance(event$solution,stations[[pick$station]])/1000,
      pick$sample/100-event$solution[4L]
  )
  n <- length(points)
  d <- vapply(points,`[`,numeric(1),1L)
  t <- vapply(points,`[`,numeric(1),2L)
  sd <- ordered_sum(d)
  st <- ordered_sum(t)
  sdd <- ordered_sum(d*d)
  sdt <- ordered_sum(d*t)
  slope <- (n*sdt-sd*st)/(n*sdd-sd*sd)
  intercept <- (st-slope*sd)/n
  error <- ordered_sum((t-intercept-slope*d)^2)
  list(n=n,velocity=1000/slope,intercept=intercept,rms=sqrt(error/n))
}
cluster_events <- function(events,params) {
  n <- length(events)
  neighbors <- replicate(n,integer(),simplify=FALSE)
  dlimit <- params$cluster[1L]
  tlimit <- params$cluster[2L]
  if (n > 1L) for (i in seq_len(n-1L)) for (j in seq.int(i+1L,n)) {
    a <- events[[i]]$solution
    b <- events[[j]]$solution
    if (abs(a[4L]-b[4L]) <= tlimit && sqrt(ordered_sum((a[1:3]-b[1:3])^2)) <= dlimit) {
      neighbors[[i]] <- c(neighbors[[i]],j)
      neighbors[[j]] <- c(neighbors[[j]],i)
    }
  }
  seen <- logical(n)
  clusters <- list()
  for (start in seq_len(n)) {
    if (seen[start]) next
    queue <- start
    seen[start] <- TRUE
    cursor <- 1L
    while (cursor <= length(queue)) {
      current <- queue[cursor]
      cursor <- cursor+1L
      for (other in neighbors[[current]]) if (!seen[other]) {
        seen[other] <- TRUE
        queue <- c(queue,other)
      }
    }
    members <- sort(queue)
    number <- length(clusters)+1L
    for (i in members) events[[i]]$cluster <- number
    center <- vapply(
        seq_len(3L),
        function(k) ordered_sum(vapply(
            events[members],
            function(event) event$solution[k],
            numeric(1)
        ))/length(members),
        numeric(1)
    )
    origins <- vapply(events[members],function(event) event$solution[4L],numeric(1))
    clusters[[number]] <- list(number=number,members=members,center=center,span=max(origins)-min(origins))
  }
  list(events=events,clusters=clusters)
}
reassociate <- function(picks,events,stations,corrections,params) {
  station_sets <- lapply(events,function(event) vapply(event$used,function(pick) pick$station,integer(1)))
  added <- list()
  for (pick in picks) {
    if (pick$state != "unassociated") next
    choices <- list()
    for (event in events) {
      if (pick$station %in% station_sets[[event$number]]) next
      rho <- pick$sample/100-event$solution[4L]-distance(
          event$solution,
          stations[[pick$station]]
      )/params$velocity[1L]-corrections[pick$station]
      if (abs(rho) <= params$residual_limit[1L]) choices[[length(choices)+1L]] <- list(
          error=abs(rho),
          number=event$number,
          rho=rho
      )
    }
    if (!length(choices)) next
    ordering <- order(
        vapply(choices,function(choice) choice$error,numeric(1)),
        vapply(choices,function(choice) choice$number,integer(1))
    )
    choice <- choices[[ordering[1L]]]
    pick$state <- "added"
    pick$event <- choice$number
    pick$residual <- choice$rho
    station_sets[[choice$number]] <- c(station_sets[[choice$number]],pick$station)
    added[[length(added)+1L]] <- pick
  }
  added
}
magnitude_relation <- function(events) {
  available <- Filter(function(event) !is.null(event$ml),events)
  n <- length(available)
  x <- vapply(available,function(event) event$md,numeric(1))
  y <- vapply(available,function(event) event$ml,numeric(1))
  xm <- ordered_sum(x)/n
  ym <- ordered_sum(y)/n
  xx <- ordered_sum((x-xm)^2)
  xy <- ordered_sum((x-xm)*(y-ym))
  yy <- ordered_sum((y-ym)^2)
  slope <- xy/xx
  list(n=n,slope=slope,intercept=ym-slope*xm,r=xy/sqrt(xx*yy),mean_diff=ym-xm)
}
picks_report <- function(picks,stations) {
  lines <- "station,sample,time_s,duration,snr,amplitude,clipped,event,status,residual"
  for (pick in picks) {
    error <- if (pick$state %in% c("used","added")) decimal(pick$residual,4L) else "-"
    event <- if (pick$state %in% c("used","dropped","added")) pick$event else 0L
    lines <- c(lines,paste(stations[[pick$station]]$code,integer_text(pick$sample),time_notation(pick$sample),integer_text(pick$duration),
      decimal(
          pick$ratio,
          2L
      ),integer_text(pick$amplitude),if (pick$clipped) "yes" else "no",event,pick$state,error,sep=","))
  }
  lines
}
format_solution <- function(label,solution,rms,index=0L) {
  prefix <- paste0(label,if (index == 0L) "" else paste0(" ",index))
  paste0(
      prefix,
      " x=",
      decimal(solution[1L],1L),
      " y=",
      decimal(solution[2L],1L),
      " z=",
      decimal(solution[3L],1L),
      " t0=",
      decimal(solution[4L],3L),
      " rms=",
      decimal(rms,4L)
  )
}
pass_lines <- function(number,picks,run,stations,velocity) {
  codes <- vapply(picks,function(pick) stations[[pick$station]]$code,character(1))
  lines <- c(paste0("PASS ",number," stations=",paste(codes,collapse=",")),format_solution("GRID",run$grid$solution,run$grid$rms),
    paste0("PROFILE ",paste(vapply(run$grid$profile,decimal,character(1),digits=4L),collapse=" ")))
  for (record in run$trace) lines <- c(lines,format_solution("ITER",record$solution,record$rms,record$number))
  for (i in seq_along(picks)) {
    pick <- picks[[i]]
    d <- distance(run$solution,stations[[pick$station]])
    lines <- c(lines,paste0("RES ",stations[[pick$station]]$code," dist=",decimal(d,1L)," tt=",decimal(d/velocity,4L),
      " obs=",time_notation(pick$sample)," res=",decimal(run$residuals[i],4L)))
  }
  lines
}
locations_report <- function(picks,candidates,events,stations,corrections,fit,clusters,added,params) {
  lines <- character()
  velocity <- params$velocity[1L]
  for (candidate in candidates) {
    lines <- c(lines,paste0("CANDIDATE ",candidate$number," picks=",length(candidate$picks)," first=",time_notation(candidate$first$sample)),
      pass_lines(1L,candidate$passes[[1L]]$picks,candidate$passes[[1L]]$run,stations,velocity))
    for (item in candidate$dropped) lines <- c(
        lines,
        paste0("DROP ",stations[[item$pick$station]]$code," res=",decimal(item$error,4L))
    )
    if (candidate$rejected) {
      lines <- c(lines,paste0("RESULT REJECTED stations=",length(candidate$picks)-length(candidate$dropped)))
    } else {
      if (length(candidate$passes) == 2L) lines <- c(
          lines,
          pass_lines(2L,candidate$passes[[2L]]$picks,candidate$passes[[2L]]$run,stations,velocity)
      )
      lines <- c(lines,paste("RESULT EVENT",candidate$event))
    }
  }
  lines <- c(lines,"CORRECTIONS")
  for (s in seq_along(stations)) {
    n <- sum(vapply(picks,function(pick) pick$state == "used" && pick$station == s,logical(1)))
    lines <- c(lines,paste0(stations[[s]]$code," n=",n," correction=",decimal(corrections[s],4L)))
  }
  for (event in events) {
    q <- event$quality
    final <- event$final
    lines <- c(
        lines,
        paste("EVENT",event$number),
        format_solution("START",event$first$solution,event$start_rms)
    )
    for (record in final$trace) lines <- c(
        lines,
        format_solution("ITER",record$solution,record$rms,record$number)
    )
    for (pick in event$used) {
      d <- distance(event$solution,stations[[pick$station]])
      lines <- c(lines,paste0("RES ",stations[[pick$station]]$code," dist=",decimal(d,1L)," tt=",decimal(d/velocity,4L)," obs=",time_notation(pick$sample),
        " corr=",decimal(corrections[pick$station],4L)," res=",decimal(pick$residual,4L)))
    }
    lines <- c(lines,paste0("ELLIPSE smaj=",decimal(q$smaj,1L)," smin=",decimal(q$smin,1L)," az=",decimal(q$az,1L)," erz=",decimal(q$erz,1L)," ert=",decimal(q$ert,4L)),
      paste0("SHIFT dh=",decimal(q$dh,1L)," dz=",decimal(q$dz,1L)),paste0(
          "GAP ",
          decimal(q$gap,1L),
          " DMIN ",
          decimal(q$dmin,1L),
          " QUALITY ",
          q$grade
      ))
    for (jack in q$jackknife) lines <- c(
        lines,
        paste0(
            "JACK ",
            stations[[jack$station]]$code,
            " dx=",
            decimal(jack$dx,1L),
            " dy=",
            decimal(jack$dy,1L),
            " dz=",
            decimal(jack$dz,1L),
            " shift=",
            decimal(jack$shift,1L)
        )
    )
    lines <- c(
        lines,
        paste0("JACKKNIFE max=",decimal(q$max_jack$shift,1L)," station=",stations[[q$max_jack$station]]$code)
    )
  }
  lines <- c(
      lines,
      paste0(
          "FIT n=",
          fit$n,
          " velocity=",
          decimal(fit$velocity,1L),
          " intercept=",
          decimal(fit$intercept,4L),
          " rms=",
          decimal(fit$rms,4L)
      )
  )
  for (cluster in clusters) {
    if (length(cluster$members) < 2L) next
    lines <- c(lines,paste0("CLUSTER ",cluster$number," events=",paste(cluster$members,collapse=",")," x=",decimal(cluster$center[1L],1L),
      " y=",decimal(cluster$center[2L],1L)," z=",decimal(
          cluster$center[3L],
          1L
      )," span=",decimal(cluster$span,3L)))
  }
  lines <- c(lines,"ADDED")
  for (pick in added) lines <- c(
      lines,
      paste0(
          stations[[pick$station]]$code,
          " sample=",
          integer_text(pick$sample),
          " event=",
          pick$event,
          " res=",
          decimal(pick$residual,4L)
      )
  )
  depths <- vapply(events,function(event) event$solution[3L],numeric(1))
  lines <- c(lines,paste0("SUMMARY picks=",length(picks)," candidates=",length(candidates)," events=",length(events)," rejected=",
    sum(vapply(candidates,function(candidate) candidate$rejected,logical(1)))," unassociated=",sum(vapply(
        picks,
        function(pick) pick$state == "unassociated",
        logical(1)
    ))),
    paste0(
        "DEPTH min=",
        decimal(min(depths),1L),
        " median=",
        decimal(median_value(depths),1L),
        " max=",
        decimal(max(depths),1L)
    ),
    paste0("QUALITY A=",sum(vapply(events,function(event) event$quality$grade == "A",logical(1)))," B=",sum(vapply(events,function(event) event$quality$grade == "B",logical(1))),
      " C=",sum(vapply(events,function(event) event$quality$grade == "C",logical(1)))," mean_rms=",decimal(
          ordered_sum(vapply(events,function(event) event$final$rms,numeric(1)))/length(events),
          4L
      )))
  lines
}
optional_magnitude <- function(value) if (is.null(value)) "-" else decimal(value,2L)
catalog_report <- function(events) {
  lines <- "event,origin_time,x,y,depth,rms,stations,gap,dmin,smaj,smin,azimuth,erz,ml,md,quality,cluster"
  for (event in events) {
    solution <- event$solution
    q <- event$quality
    fields <- c(as.character(event$number),decimal(solution[4L],3L),decimal(solution[1L],1L),decimal(solution[2L],1L),decimal(solution[3L],1L),decimal(event$final$rms,4L),
      as.character(length(event$used)),decimal(q$gap,1L),decimal(q$dmin,1L),decimal(q$smaj,1L),decimal(
          q$smin,
          1L
      ),decimal(q$az,1L),decimal(q$erz,1L),
      optional_magnitude(event$ml),decimal(event$md,2L),q$grade,as.character(event$cluster))
    lines <- c(lines,paste(fields,collapse=","))
  }
  lines
}
frame_lines <- function(rows) {
  border <- paste0("+",strrep("-",ncol(rows)),"+")
  c(
      border,
      vapply(seq_len(nrow(rows)),function(r) paste0("|",paste(rows[r,],collapse=""),"|"),character(1)),
      border
  )
}
timeline_lines <- function(events,params) {
  duration <- params$timeline[1L]
  width <- params$timeline[2L]
  low <- params$timeline[3L]
  high <- params$timeline[4L]
  height <- params$timeline[5L]
  rows <- matrix(" ",height,width)
  for (event in events) {
    if (is.null(event$ml)) next
    t <- scaled(event$solution[4L],3L)
    h <- magnitude_hundredths(event$ml)
    if (!(t >= 0 && t < 1000*duration && h >= 100*low)) next
    column <- (t*width) %/% (1000*duration)
    level <- min(((h-100*low)*height) %/% (100*(high-low)),height-1L)
    for (k in seq_len(level+1L)-1L) {
      r <- height-k
      if (k == level) rows[r,column+1L] <- "o" else if (rows[r,column+1L] == " ") rows[r,column+1L] <- "|"
    }
  }
  c(
      paste0("TIMELINE t=0..",integer_text(duration)," ML=",integer_text(low),"..",integer_text(high)),
      frame_lines(rows)
  )
}
magnitudes_report <- function(events,statistics,relation,stations,params) {
  lines <- character()
  for (event in events) {
    available <- sum(vapply(event$magnitudes,function(item) !is.null(item$ml),logical(1)))
    lines <- c(
        lines,
        paste0(
            "EVENT ",
            event$number,
            " ML=",
            optional_magnitude(event$ml),
            " n=",
            available,
            " MD=",
            decimal(event$md,2L)
        )
    )
    for (item in event$magnitudes) {
      pick <- item$pick
      prefix <- paste0(
          stations[[pick$station]]$code,
          " r=",
          decimal(item$r,3L),
          " amp=",
          integer_text(pick$amplitude),
          " "
      )
      detail <- if (is.null(item$ml)) "clipped" else paste0(
          "ml=",
          decimal(item$ml,2L),
          " res=",
          decimal(item$ml-event$ml,2L)
      )
      lines <- c(lines,paste0(prefix,detail," dur=",integer_text(pick$duration)," md=",decimal(item$md,2L)))
    }
  }
  lines <- c(
      lines,
      "CORRECTED",
      vapply(
          events,
          function(event) paste0("EVENT ",event$number," MLC=",optional_magnitude(event$ml_corrected)),
          character(1)
      ),
      "FMD"
  )
  for (t in seq.int(min(statistics$values),max(statistics$values))) {
    matched <- match(t,statistics$values)
    count <- if (is.na(matched)) 0L else statistics$counts[matched]
    cumulative <- sum(statistics$counts[statistics$values >= t])
    lines <- c(lines,paste0("M=",magnitude_class(t)," N=",count," CUM=",cumulative))
  }
  lines <- c(lines,paste("MC",magnitude_class(statistics$completeness)),paste0("BVALUE ",decimal(statistics$b,3L)," SIGMA ",decimal(statistics$sigma,3L)," N ",statistics$nb),
    paste0("AVALUE ",decimal(statistics$a,3L)),paste0(
        "MLMD n=",
        relation$n,
        " slope=",
        decimal(relation$slope,3L),
        " intercept=",
        decimal(relation$intercept,3L),
        " r=",
        decimal(relation$r,3L),
        " mean_diff=",
        decimal(relation$mean_diff,3L)
    ),
    timeline_lines(events,params))
  lines
}
stations_report <- function(
    stations,
    statistics,
    picks,
    events,
    time_corrections,
    magnitude_corrections,
    magnitude_residuals
) {
  lines <- character()
  for (s in seq_along(stations)) {
    station <- stations[[s]]
    stats <- statistics[[s]]
    local_picks <- Filter(function(pick) pick$station == s,picks)
    used <- list()
    for (event in events) for (pick in event$used) if (pick$station == s) used[[length(used)+1L]] <- pick
    before <- if (!length(used)) "-" else decimal(
        sqrt(ordered_sum(vapply(used,function(pick) pick$first_residual^2,numeric(1)))/length(used)),
        4L
    )
    after <- if (!length(used)) "-" else decimal(
        sqrt(ordered_sum(vapply(used,function(pick) pick$residual^2,numeric(1)))/length(used)),
        4L
    )
    states <- vapply(
        c("used","dropped","added","rejected","unassociated"),
        function(name) paste0(name,"=",sum(vapply(local_picks,function(pick) pick$state == name,logical(1)))),
        character(1)
    )
    lines <- c(lines,paste0("STATION ",station$code," x=",integer_text(station$x)," y=",integer_text(station$y)," elevation=",integer_text(station$elevation)),
      paste0(
          "SAMPLES start=",
          integer_text(station$start),
          " count=",
          length(station$samples),
          " mean=",
          integer_text(stats$mean),
          " noise=",
          decimal(stats$noise,1L),
          " peak=",
          integer_text(stats$peak),
          " clipped=",
          stats$clipped
      ),
      paste0(
          "TRIGGERS total=",
          stats$triggers,
          " short=",
          stats$short,
          " picks=",
          length(local_picks)
      ),paste0("PICKS ",paste(states,collapse=" ")),
      paste0(
          "RESIDUALS n=",
          length(used),
          " rms=",
          before,
          " correction=",
          decimal(time_corrections[s],4L),
          " after=",
          after
      ),
      paste0(
          "MAGNITUDES n=",
          length(magnitude_residuals[[s]]),
          " correction=",
          decimal(magnitude_corrections[s],2L)
      ))
  }
  lines
}
event_symbol <- function(event) {
  if (is.null(event$ml)) return("?")
  h <- magnitude_hundredths(event$ml)
  if (h < 100) "." else if (h < 200) "o" else if (h < 300) "O" else "@"
}
map_position <- function(x,y,params) {
  left <- params$map_area[1L]
  right <- params$map_area[2L]
  bottom <- params$map_area[3L]
  top <- params$map_area[4L]
  width <- params$map_size[1L]
  height <- params$map_size[2L]
  if (!(10*left <= x && x < 10*right && 10*bottom <= y && y < 10*top)) return(NULL)
  c(((x-10*left)*width) %/% (10*(right-left)),height-1L-((y-10*bottom)*height) %/% (10*(top-bottom)))
}
plotted_positions <- function(event,params) {
  x <- scaled(event$solution[1L],1L)
  y <- scaled(event$solution[2L],1L)
  z <- scaled(event$solution[3L],1L)
  left <- params$map_area[1L]
  right <- params$map_area[2L]
  bottom <- params$map_area[3L]
  top <- params$map_area[4L]
  width <- params$map_size[1L]
  limit <- params$section[1L]
  height <- params$section[2L]
  row <- (z*height) %/% (10*limit)
  ew <- if (10*left <= x && x < 10*right && z < 10*limit) c(
      ((x-10*left)*width) %/% (10*(right-left)),
      row
  ) else NULL
  ns <- if (10*bottom <= y && y < 10*top && z < 10*limit) c(
      ((y-10*bottom)*width) %/% (10*(top-bottom)),
      row
  ) else NULL
  list(map=map_position(x,y,params),ew=ew,ns=ns)
}
place_point <- function(rows,position,symbol) {
  if (is.null(position)) return(rows)
  column <- position[1L]+1L
  row <- position[2L]+1L
  priority <- c(" "=-1L,"?"=0L,"."=1L,"o"=2L,"O"=3L,"@"=4L,"^"=5L)
  if (priority[[symbol]] > priority[[rows[row,column]]]) rows[row,column] <- symbol
  rows
}
position_text <- function(position) if (is.null(position)) "outside" else paste(
    integer_text(position),
    collapse=","
)
map_report <- function(events,stations,params) {
  left <- params$map_area[1L]
  right <- params$map_area[2L]
  bottom <- params$map_area[3L]
  top <- params$map_area[4L]
  width <- params$map_size[1L]
  height <- params$map_size[2L]
  limit <- params$section[1L]
  section_height <- params$section[2L]
  map <- matrix(" ",height,width)
  ew <- ns <- matrix(" ",section_height,width)
  locations <- lapply(events,function(event) plotted_positions(event,params))
  for (i in seq_along(events)) {
    symbol <- event_symbol(events[[i]])
    position <- locations[[i]]
    map <- place_point(map,position$map,symbol)
    ew <- place_point(ew,position$ew,symbol)
    ns <- place_point(ns,position$ns,symbol)
  }
  station_locations <- lapply(stations,function(station) map_position(10*station$x,10*station$y,params))
  for (position in station_locations) map <- place_point(map,position,"^")
  lines <- c(paste0("MAP x=",integer_text(left),"..",integer_text(right)," y=",integer_text(bottom),"..",integer_text(top)),frame_lines(map),
    paste0(
        "SECTION EW x=",
        integer_text(left),
        "..",
        integer_text(right),
        " z=0..",
        integer_text(limit)
    ),frame_lines(ew),
    paste0(
        "SECTION NS y=",
        integer_text(bottom),
        "..",
        integer_text(top),
        " z=0..",
        integer_text(limit)
    ),frame_lines(ns),"LEGEND ^ station . ML<1 o ML<2 O ML<3 @ ML>=3 ? no ML")
  for (i in seq_along(stations)) lines <- c(
      lines,
      paste0("STATION ",stations[[i]]$code," map=",position_text(station_locations[[i]]))
  )
  for (i in seq_along(events)) {
    event <- events[[i]]
    position <- locations[[i]]
    lines <- c(
        lines,
        paste0(
            "EVENT ",
            event$number,
            " ",
            event_symbol(event),
            " map=",
            position_text(position$map),
            " ew=",
            position_text(position$ew),
            " ns=",
            position_text(position$ns)
        )
    )
  }
  lines
}
main <- function() {
  inputs <- load_inputs()
  stations <- inputs$stations
  params <- inputs$params
  picks <- station_statistics <- list()
  for (station in stations) {
    detected <- detect_station(station,params)
    picks <- c(picks,detected$picks)
    station_statistics[[length(station_statistics)+1L]] <- detected$stats
  }
  ordering <- order(
      vapply(picks,function(pick) pick$sample,numeric(1)),
      vapply(picks,function(pick) pick$station,integer(1))
  )
  picks <- picks[ordering]
  candidates <- associate(picks,params$association_window[1L],params$min_stations[1L])
  located <- locate_candidates(candidates,stations,params)
  candidates <- located$candidates
  events <- located$events
  time_corrections <- station_time_corrections(events,stations)
  events <- relocate_events(events,stations,params,time_corrections)
  magnitudes <- compute_magnitudes(events,stations,params)
  events <- magnitudes$events
  fit <- travel_time_regression(events,stations,params)
  clustered <- cluster_events(events,params)
  events <- clustered$events
  added <- reassociate(picks,events,stations,time_corrections,params)
  available <- vapply(Filter(function(event) !is.null(event$ml),events),function(event) event$ml,numeric(1))
  statistics <- frequency_statistics(available)
  relation <- magnitude_relation(events)
  reports <- list("picks.csv"=picks_report(picks,stations),"locations.txt"=locations_report(picks,candidates,events,stations,time_corrections,fit,clustered$clusters,added,params),
    "catalog.csv"=catalog_report(events),"magnitudes.txt"=magnitudes_report(
        events,
        statistics,
        relation,
        stations,
        params
    ),
    "stations.txt"=stations_report(
        stations,
        station_statistics,
        picks,
        events,
        time_corrections,
        magnitudes$corrections,
        magnitudes$residuals
    ),"map.txt"=map_report(events,stations,params))
  for (name in names(reports)) writeLines(reports[[name]],file.path("output",name),useBytes=TRUE)
}
main()
