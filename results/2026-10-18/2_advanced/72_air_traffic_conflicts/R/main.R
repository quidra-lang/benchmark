source("flight_plans.R")
source("trajectory.R")
source("conflict.R")
source("resolution.R")
source("report.R")

TRAFFIC_PI <- 3.141592653589793
words <- function(...) paste(...,collapse=" ")
attributes_text <- function(...) {
  values <- list(...)
  paste(paste0(names(values),"=",vapply(values,as.character,character(1))),collapse=" ")
}
sample_times <- function(params) seq.int(params$sample_start,params$sample_end-1L,60L)
pair_key <- function(pair) paste(pair,collapse=",")
pair_name <- function(plans,pair) paste(vapply(plans[pair],function(p) p$callsign,character(1)),collapse="-")
ordered_total <- function(items) {
  result <- 0
  for (value in items) result <- result+value
  result
}
find_blocker <- function(changed,new_trajectory,partner,trajectories,unresolved,start,params) {
  blockers <- list()
  for (other in seq_along(trajectories)) {
    if (other == changed) next
    pair <- sort(c(changed,other))
    if (pair_key(pair) %in% unresolved) next
    first <- if (pair[1L] == changed) new_trajectory else trajectories[[pair[1L]]]
    second <- if (pair[2L] == changed) new_trajectory else trajectories[[pair[2L]]]
    for (conflict in pair_conflicts(
        pair[1L],
        first,
        pair[2L],
        second,
        params$dh,
        params$dv
    )) if (other == partner || conflict$start < start+params$lookahead) blockers[[length(blockers)+1L]] <- conflict
  }
  if (!length(blockers)) return(NULL)
  blockers[[order(
      vapply(blockers,function(c) c$start,numeric(1)),
      vapply(blockers,function(c) c$pair[1L],integer(1)),
      vapply(blockers,function(c) c$pair[2L],integer(1))
  )[1L]]]
}
resolve_conflicts <- function(initial,types,params) {
  plans <- initial
  trajectories <- lapply(plans,build_trajectory,types=types)
  unresolved <- resolved <- character()
  rounds <- unresolved_conflicts <- list()
  repeat {
    conflicts <- all_conflicts(trajectories,params$dh,params$dv)
    eligible <- which(!vapply(conflicts,function(c) pair_key(c$pair) %in% unresolved,logical(1)))
    if (!length(eligible)) break
    target <- conflicts[[eligible[1L]]]
    a <- target$pair[1L]
    b <- target$pair[2L]
    priority <- priority_order(plans[[a]],plans[[b]],a,b)
    trials <- list()
    accepted <- NULL
    for (order in list(priority,rev(priority))) {
      if (!is.null(accepted)) break
      aircraft <- order[1L]
      partner <- order[2L]
      for (manoeuvre in manoeuvres(params$max_delay)) {
        name <- manoeuvre$name
        proposal <- propose(plans[[aircraft]],name,manoeuvre$amount,types,params)
        blocker <- NULL
        if (is.null(proposal)) status <- "infeasible" else {
          new_trajectory <- build_trajectory(proposal,types)
          blocker <- find_blocker(aircraft,new_trajectory,partner,trajectories,unresolved,target$start,params)
          status <- if (is.null(blocker)) "accepted" else "blocked"
          if (status == "accepted") {
            proposal$history <- c(proposal$history,name)
            plans[[aircraft]] <- proposal
            trajectories[[aircraft]] <- new_trajectory
          }
        }
        entry <- list(aircraft=aircraft,name=name,status=status,blocker=blocker)
        trials[[length(trials)+1L]] <- entry
        if (status == "accepted") {
          accepted <- entry
          break
        }
      }
    }
    if (is.null(accepted)) {
      unresolved <- union(unresolved,pair_key(target$pair))
      unresolved_conflicts[[length(unresolved_conflicts)+1L]] <- target
    } else resolved <- union(resolved,pair_key(target$pair))
    rounds[[length(rounds)+1L]] <- list(
        number=length(rounds)+1L,
        target=target,
        trials=trials,
        accepted=accepted
    )
  }
  list(
      plans=plans,
      trajectories=trajectories,
      rounds=rounds,
      unresolved=unresolved,
      resolved=resolved,
      unresolved_conflicts=unresolved_conflicts
  )
}
segment_track <- function(segment) {
  angle <- atan2(segment$velocity[1L],segment$velocity[2L])*180/TRAFFIC_PI
  if (angle < 0) angle+360 else angle
}
sector_contains <- function(sector,point) {
  x <- point[1L]
  y <- point[2L]
  z <- point[3L]
  sector$x1/10 <= x && x < sector$x2/10 && sector$y1/10 <= y && y < sector$y2/10 && sector$lower*100 <= z && z < sector$upper*100
}
classify_conflicts <- function(conflicts,sectors,final_pairs,resolved,dh,final=FALSE) {
  lapply(conflicts,function(c) {
    piece <- c$closest
    a <- piece$a_segment
    b <- piece$b_segment
    pa <- segment_position(a,piece$tc)
    pb <- segment_position(b,piece$tc)
    ta <- segment_track(a)
    tb <- segment_track(b)
    angle <- abs(ta-tb)
    if (angle > 180) angle <- 360-angle
    dot <- a$velocity[1L]*b$velocity[1L]+a$velocity[2L]*b$velocity[2L]
    cross <- a$velocity[1L]*b$velocity[2L]-a$velocity[2L]*b$velocity[1L]
    geometry <- if (dot*dot > cross*cross) if (dot < 0) "head_on" else "trailing" else "crossing"
    severity <- if (10*piece$distance < 4*dh) "HIGH" else if (10*piece$distance < 7*dh) "MEDIUM" else "LOW"
    midpoint <- (pa+pb)/2
    sector <- which(vapply(sectors,sector_contains,logical(1),point=midpoint))
    sector_name <- if (length(sector)) sectors[[sector[1L]]]$name else "-"
    outcome <- if (final || pair_key(c$pair) %in% final_pairs) "remaining" else if (pair_key(c$pair) %in% resolved) "resolved" else "indirect"
    c(
        c,
        list(
            level_a=pa[3L]/100,
            level_b=pb[3L]/100,
            track_a=ta,
            track_b=tb,
            angle=angle,
            geometry=geometry,
            severity=severity,
            sector=sector_name,
            outcome=outcome
        )
    )
  })
}
active_conflicts <- function(conflicts,time) Filter(function(c) c$start <= time && time < c$finish,conflicts)
trajectories_csv <- function(plans,trajectories) {
  lines <- "callsign,segment,leg,phase,t_start,t_end,x_start,y_start,fl_start,x_end,y_end,fl_end"
  for (i in seq_along(plans)) for (s in trajectories[[i]]$segments) {
    fields <- c(
        plans[[i]]$callsign,
        s$number,
        s$leg,
        s$phase,
        decimal(s$ts),
        decimal(s$te),
        decimal(s$start[1L]),
        decimal(s$start[2L]),
        as.integer(round(s$start[3L]/100)),
        decimal(s$finish[1L]),
        decimal(s$finish[2L]),
        as.integer(round(s$finish[3L]/100))
    )
    lines <- c(lines,paste(fields,collapse=","))
  }
  lines
}
conflict_lines <- function(label,plans,conflicts,trajectories,params) {
  lines <- paste("CONFLICTS",attributes_text(plan=label,count=length(conflicts)))
  for (i in seq_along(conflicts)) {
    c <- conflicts[[i]]
    p <- c$closest
    lines <- c(
        lines,
        words(
            "CONFLICT",
            i,
            pair_name(plans,c$pair),
            attributes_text(
                start=decimal(c$start),
                end=decimal(c$finish),
                duration=decimal(c$finish-c$start),
                outcome=c$outcome
            )
        )
    )
    lines <- c(
        lines,
        paste0(
            "  CPA ",
            attributes_text(
                t=decimal(p$tc),
                dist=decimal(p$distance),
                vert=decimal(p$vertical,1L),
                levels=paste(decimal(c$level_a,2L),decimal(c$level_b,2L),sep="/"),
                tracks=paste(decimal(c$track_a,1L),decimal(c$track_b,1L),sep="/"),
                angle=decimal(c$angle,1L)
            )
        )
    )
    lines <- c(
        lines,
        paste0(
            "  TYPE ",
            attributes_text(
                geometry=c$geometry,
                phases=paste(p$a_segment$phase,p$b_segment$phase,sep="/"),
                segments=paste(p$a_segment$number,p$b_segment$number,sep="/"),
                sector=c$sector,
                severity=c$severity
            )
        )
    )
    for (piece in c$pieces) lines <- c(
        lines,
        paste0(
            "  PIECE ",
            words(
                paste(piece$a_segment$number,piece$b_segment$number,sep="/"),
                decimal(piece$lo),
                decimal(piece$hi)
            )
        )
    )
  }
  closest <- if (length(conflicts)) decimal(min(vapply(
      conflicts,
      function(c) c$closest$distance,
      numeric(1)
  ))) else "-"
  geometry_count <- function(kind) sum(vapply(conflicts,function(c) c$geometry == kind,logical(1)))
  severity_count <- function(kind) sum(vapply(conflicts,function(c) c$severity == kind,logical(1)))
  duration <- ordered_total(vapply(conflicts,function(c) c$finish-c$start,numeric(1)))
  lines <- c(
      lines,
      paste(
          "SUMMARY",
          attributes_text(
              count=length(conflicts),
              total=decimal(duration),
              min_dist=closest,
              head_on=geometry_count("head_on"),
              crossing=geometry_count("crossing"),
              trailing=geometry_count("trailing"),
              high=severity_count("HIGH"),
              medium=severity_count("MEDIUM"),
              low=severity_count("LOW")
          )
      )
  )
  involved <- which(vapply(
      seq_along(plans),
      function(i) any(vapply(conflicts,function(c) i %in% c$pair,logical(1))),
      logical(1)
  ))
  for (i in involved) {
    matching <- Filter(function(c) i %in% c$pair,conflicts)
    partners <- sort(setdiff(unique(unlist(lapply(matching,function(c) c$pair),use.names=FALSE)),i))
    partner_names <- vapply(plans[partners],function(p) p$callsign,character(1))
    lines <- c(
        lines,
        words(
            "FLIGHT",
            plans[[i]]$callsign,
            attributes_text(
                conflicts=length(matching),
                first=decimal(min(vapply(matching,function(c) c$start,numeric(1)))),
                partners=paste(partner_names,collapse=",")
            )
        )
    )
  }
  lines <- c(lines,paste("TIMELINE",attributes_text(from=params$sample_start,to=params$sample_end,step=60L)))
  for (i in involved) {
    symbols <- vapply(sample_times(params),function(t) {
      if (is.null(active_segment(trajectories[[i]],t))) "." else if (any(vapply(
          conflicts,
          function(c) i %in% c$pair && c$start <= t && t < c$finish,
          logical(1)
      ))) "X" else "-"
    },character(1))
    lines <- c(lines,paste(plans[[i]]$callsign,paste(symbols,collapse="")))
  }
  lines
}
history_text <- function(plan) if (length(plan$history)) paste(plan$history,collapse=",") else "-"
resolution_lines <- function(initial,final,ti,tf,ci,cf,resolution) {
  lines <- character()
  for (record in resolution$rounds) {
    c <- record$target
    lines <- c(
        lines,
        words(
            "ROUND",
            record$number,
            pair_name(initial,c$pair),
            attributes_text(start=decimal(c$start),end=decimal(c$finish),dist=decimal(c$closest$distance))
        )
    )
    for (trial in record$trials) {
      line <- paste0("  TRY ",words(initial[[trial$aircraft]]$callsign,trial$name,trial$status))
      if (trial$status == "blocked") line <- paste(
          line,
          pair_name(initial,trial$blocker$pair),
          paste0("start=",decimal(trial$blocker$start))
      )
      lines <- c(lines,line)
    }
    line <- if (is.null(record$accepted)) "  RESULT unresolved" else paste0(
        "  RESULT resolved ",
        words(initial[[record$accepted$aircraft]]$callsign,record$accepted$name)
    )
    lines <- c(lines,line)
  }
  total_extra <- 0
  for (i in seq_along(initial)) {
    old <- initial[[i]]
    new <- final[[i]]
    extra <- tf[[i]]$arrival-ti[[i]]$arrival
    total_extra <- total_extra+extra
    before <- sum(vapply(ci,function(c) i %in% c$pair,logical(1)))
    after <- sum(vapply(cf,function(c) i %in% c$pair,logical(1)))
    lines <- c(
        lines,
        words(
            "FLIGHT",
            new$callsign,
            attributes_text(
                departure=new$departure+new$delay,
                delay=new$delay,
                level=signed_integer(new$offset),
                speed=paste(old$speed,new$speed,sep="->"),
                arrival=paste(decimal(ti[[i]]$arrival),decimal(tf[[i]]$arrival),sep="->"),
                extra=decimal(extra),
                length=decimal(tf[[i]]$length),
                conflicts=paste(before,after,sep="->"),
                manoeuvres=history_text(new)
            )
        )
    )
  }
  for (c in resolution$unresolved_conflicts) lines <- c(
      lines,
      words(
          "UNRESOLVED",
          pair_name(initial,c$pair),
          attributes_text(start=decimal(c$start),dist=decimal(c$closest$distance))
      )
  )
  attempts <- unlist(lapply(resolution$rounds,function(r) r$trials),recursive=FALSE)
  accepted <- lapply(Filter(function(r) !is.null(r$accepted),resolution$rounds),function(r) r$accepted)
  count_accepted <- function(test) sum(vapply(accepted,test,logical(1)))
  count_attempts <- function(status) sum(vapply(attempts,function(t) t$status == status,logical(1)))
  lines <- c(
      lines,
      paste(
          "TOTAL",
          attributes_text(
              rounds=length(resolution$rounds),
              resolved=length(accepted),
              unresolved=length(resolution$unresolved_conflicts),
              level=count_accepted(function(t) startsWith(t$name,"level_")),
              speed=count_accepted(function(t) t$name == "speed_down"),
              delay=count_accepted(function(t) startsWith(t$name,"delay_")),
              total_delay=sum(vapply(final,function(p) p$delay,integer(1))),
              total_extra=decimal(total_extra),
              trials=length(attempts),
              infeasible=count_attempts("infeasible"),
              blocked=count_attempts("blocked")
          )
      )
  )
  lines
}
inside_segment_sector <- function(segment,sector) {
  limits <- list(
      c(sector$x1/10,sector$x2/10),
      c(sector$y1/10,sector$y2/10),
      c(sector$lower*100,sector$upper*100)
  )
  lo <- segment$ts
  hi <- segment$te
  for (i in seq_len(3L)) {
    low <- limits[[i]][1L]
    high <- limits[[i]][2L]
    p <- segment$start[i]
    v <- segment$velocity[i]
    if (v == 0) {
      if (!(low <= p && p < high)) return(NULL)
    } else {
      r1 <- (low-p)/v
      r2 <- (high-p)/v
      lo <- max(lo,segment$ts+min(r1,r2))
      hi <- min(hi,segment$ts+max(r1,r2))
    }
  }
  if (hi-lo > 1e-6) c(lo,hi) else NULL
}
sector_transits <- function(trajectories,sectors) {
  all_transits <- list()
  for (aircraft in seq_along(trajectories)) {
    transits <- list()
    for (sector in seq_along(sectors)) {
      combined <- list()
      for (segment in trajectories[[aircraft]]$segments) {
        interval <- inside_segment_sector(segment,sectors[[sector]])
        if (is.null(interval)) next
        n <- length(combined)
        if (n && interval[1L]-combined[[n]][2L] <= 1e-6) combined[[n]][2L] <- interval[2L] else combined[[n+1L]] <- interval
      }
      for (interval in combined) transits[[length(transits)+1L]] <- list(
          aircraft=aircraft,
          sector=sector,
          entry=interval[1L],
          exit=interval[2L],
          previous=0L,
          next_sector=0L
      )
    }
    transits <- transits[order(
        vapply(transits,function(t) t$entry,numeric(1)),
        vapply(transits,function(t) t$sector,integer(1))
    )]
    if (length(transits) > 1L) for (i in seq_len(length(transits)-1L)) if (abs(transits[[i+1L]]$entry-transits[[i]]$exit) <= 1e-6) {
      transits[[i]]$next_sector <- transits[[i+1L]]$sector
      transits[[i+1L]]$previous <- transits[[i]]$sector
    }
    all_transits <- c(all_transits,transits)
  }
  all_transits
}
sector_name <- function(sectors,i) if (i == 0L) "-" else sectors[[i]]$name
transit_lines <- function(plans,sectors,transits) {
  lines <- "callsign,sector,entry,exit,duration,from,to"
  for (t in transits) lines <- c(
      lines,
      paste(
          plans[[t$aircraft]]$callsign,
          sectors[[t$sector]]$name,
          decimal(t$entry),
          decimal(t$exit),
          decimal(t$exit-t$entry),
          sector_name(sectors,t$previous),
          sector_name(sectors,t$next_sector),
          sep=","
      )
  )
  lines
}
occupancy_table <- function(trajectories,sectors,times) {
  result <- matrix(0L,length(sectors),length(times))
  for (i in seq_along(times)) for (trajectory in trajectories) {
    observed <- current_position(trajectory,times[i])
    if (is.null(observed)) next
    for (j in seq_along(sectors)) if (sector_contains(
        sectors[[j]],
        observed$point
    )) result[j,i] <- result[j,i]+1L
  }
  result
}
period_table <- function(sectors,times,oi,of,ti,tf) {
  rows <- list()
  for (sector in seq_along(sectors)) for (i in seq.int(1L,length(times),5L)) {
    s <- sectors[[sector]]
    first <- times[i]
    last <- times[i]+300L
    initial_peak <- max(oi[sector,i:(i+4L)])
    final_peak <- max(of[sector,i:(i+4L)])
    initial_entries <- sum(vapply(
        ti,
        function(t) t$sector == sector && first <= t$entry && t$entry < last,
        logical(1)
    ))
    final_entries <- sum(vapply(
        tf,
        function(t) t$sector == sector && first <= t$entry && t$entry < last,
        logical(1)
    ))
    status <- if (final_peak > s$capacity) "OVER" else if (initial_peak > s$capacity) "RELIEVED" else "OK"
    rows[[length(rows)+1L]] <- list(
        sector=sector,
        period=(i-1L) %/% 5L+1L,
        start=first,
        finish=last,
        initial_entries=initial_entries,
        final_entries=final_entries,
        initial_peak=initial_peak,
        final_peak=final_peak,
        mean=sum(of[sector,i:(i+4L)])/5,
        capacity=s$capacity,
        status=status
    )
  }
  rows
}
sector_load_lines <- function(sectors,periods) {
  lines <- "sector,period,start,end,entries_initial,entries_final,peak_initial,peak_final,mean_final,capacity,status"
  for (p in periods) lines <- c(
      lines,
      paste(
          sectors[[p$sector]]$name,
          p$period,
          p$start,
          p$finish,
          p$initial_entries,
          p$final_entries,
          p$initial_peak,
          p$final_peak,
          decimal(p$mean,1L),
          p$capacity,
          p$status,
          sep=","
      )
  )
  lines
}
level_usage <- function(trajectories) {
  usage <- list()
  for (aircraft in seq_along(trajectories)) for (s in trajectories[[aircraft]]$segments) {
    if (s$phase != "LVL") next
    level <- as.character(as.integer(round(s$start[3L]/100)))
    entry <- usage[[level]]
    if (is.null(entry)) entry <- list(flights=integer(),time=0)
    entry$flights <- union(entry$flights,aircraft)
    entry$time <- entry$time+(s$te-s$ts)
    usage[[level]] <- entry
  }
  usage
}
sector_report <- function(sectors,times,oi,of,ti,tf,ci,cf,trajectories_initial,trajectories_final) {
  lines <- character()
  for (i in seq_along(sectors)) {
    s <- sectors[[i]]
    lines <- c(
        lines,
        words(
            "SECTOR",
            s$name,
            attributes_text(
                x=paste(s$x1,s$x2,sep=".."),
                y=paste(s$y1,s$y2,sep=".."),
                fl=paste(s$lower,s$upper,sep=".."),
                capacity=s$capacity
            )
        )
    )
    for (data in list(
        list(label="INITIAL",transits=ti,occupancy=oi,conflicts=ci),
        list(label="FINAL",transits=tf,occupancy=of,conflicts=cf)
    )) {
      matching <- Filter(function(t) t$sector == i,data$transits)
      dwell <- ordered_total(vapply(matching,function(t) t$exit-t$entry,numeric(1)))
      peaks <- vapply(seq.int(1L,length(times),5L),function(j) max(data$occupancy[i,j:(j+4L)]),integer(1))
      lines <- c(
          lines,
          paste(
              data$label,
              attributes_text(
                  entries=length(matching),
                  time=decimal(dwell),
                  mean=if (length(matching)) decimal(dwell/length(matching)) else "-",
                  peak=max(data$occupancy[i,]),
                  over=sum(peaks > s$capacity),
                  conflicts=sum(vapply(data$conflicts,function(c) c$sector == s$name,logical(1)))
              )
          )
      )
    }
    height <- max(s$capacity+1L,max(of[i,]))
    rows <- vapply(
        seq.int(height,1L),
        function(k) paste(ifelse(of[i,] >= k,"#",if (k == s$capacity) "-" else "."),collapse=""),
        character(1)
    )
    lines <- c(lines,chart(rows))
  }
  before <- level_usage(trajectories_initial)
  after <- level_usage(trajectories_final)
  lines <- c(lines,"LEVELS")
  for (level in sort(unique(as.integer(c(names(before),names(after)))),decreasing=TRUE)) {
    old <- before[[as.character(level)]]
    new <- after[[as.character(level)]]
    if (is.null(old)) old <- list(flights=integer(),time=0)
    if (is.null(new)) new <- list(flights=integer(),time=0)
    lines <- c(
        lines,
        words(
            "LEVEL",
            level,
            attributes_text(
                flights=paste(length(old$flights),length(new$flights),sep="->"),
                time=paste(decimal(old$time),decimal(new$time),sep="->")
            )
        )
    )
  }
  handoffs <- matrix(0L,length(sectors),length(sectors))
  for (t in tf) if (t$next_sector != 0L) handoffs[t$sector,t$next_sector] <- handoffs[
      t$sector,
      t$next_sector
  ]+1L
  lines <- c(lines,paste0("HANDOFFS plan=final count=",sum(handoffs)))
  for (i in seq_along(sectors)) for (j in seq_along(sectors)) if (handoffs[i,j] > 0L) lines <- c(
      lines,
      words("HANDOFF",sectors[[i]]$name,sectors[[j]]$name,handoffs[i,j])
  )
  lines
}
compute_alerts <- function(trajectories,conflicts,params) {
  observations <- list()
  for (time in sample_times(params)) {
    observed <- lapply(trajectories,current_position,time=time)
    for (a in seq_along(trajectories)) if (a < length(trajectories)) for (b in seq.int(
        a+1L,
        length(trajectories)
    )) {
      if (is.null(observed[[a]]) || is.null(observed[[b]])) next
      pa <- observed[[a]]
      pb <- observed[[b]]
      loss <- loss_interval(
          pa$point-pb$point,
          pa$segment$velocity-pb$segment$velocity,
          0,
          params$alert,
          params$dh,
          params$dv
      )
      if (is.null(loss)) next
      key <- pair_key(c(a,b))
      observations[[key]][[length(observations[[key]])+1L]] <- list(
          pair=c(a,b),
          time=time,
          loss=time+loss$lo,
          distance=loss$distance
      )
    }
  }
  alerts <- list()
  for (events in observations) {
    groups <- list()
    for (event in events) {
      n <- length(groups)
      if (n && event$time-tail(
          groups[[n]],
          1L
      )[[1L]]$time == 60L) groups[[n]][[length(groups[[n]])+1L]] <- event else groups[[n+1L]] <- list(event)
    }
    for (group in groups) alerts[[length(alerts)+1L]] <- list(
        pair=group[[1L]]$pair,
        first=group[[1L]]$time,
        last=tail(group,1L)[[1L]]$time,
        samples=length(group),
        predicted=group[[1L]]$loss,
        min_dist=min(vapply(group,function(e) e$distance,numeric(1)))
    )
  }
  alerts <- alerts[order(
      vapply(alerts,function(a) a$first,integer(1)),
      vapply(alerts,function(a) a$pair[1L],integer(1)),
      vapply(alerts,function(a) a$pair[2L],integer(1))
  )]
  detected <- integer()
  for (i in seq_along(alerts)) {
    alert <- alerts[[i]]
    matches <- which(vapply(
        conflicts,
        function(c) identical(
            c$pair,
            alert$pair
        ) && c$start < alert$last+params$alert && c$finish > alert$first,
        logical(1)
    ))
    alerts[[i]]["lead"] <- list(if (length(matches)) conflicts[[matches[1L]]]$start-alert$first else NULL)
    detected <- union(detected,matches)
  }
  list(alerts=alerts,missed=conflicts[setdiff(seq_along(conflicts),detected)])
}
alert_lines <- function(label,plans,trajectories,conflicts,params) {
  computed <- compute_alerts(trajectories,conflicts,params)
  alerts <- computed$alerts
  missed <- computed$missed
  lines <- paste("ALERTS",attributes_text(plan=label,horizon=params$alert,count=length(alerts)))
  leads <- numeric()
  for (i in seq_along(alerts)) {
    a <- alerts[[i]]
    status <- if (is.null(a$lead)) "status=false lead=-" else paste0("status=true lead=",decimal(a$lead))
    if (!is.null(a$lead)) leads <- c(leads,a$lead)
    lines <- c(
        lines,
        words(
            "ALERT",
            i,
            pair_name(plans,a$pair),
            attributes_text(
                first=a$first,
                last=a$last,
                samples=a$samples,
                predicted=decimal(a$predicted),
                min_dist=decimal(a$min_dist)
            ),
            status
        )
    )
  }
  for (c in missed) lines <- c(
      lines,
      words("MISSED",pair_name(plans,c$pair),attributes_text(start=decimal(c$start),end=decimal(c$finish)))
  )
  c(
      lines,
      paste(
          "SUMMARY",
          attributes_text(
              alerts=length(alerts),
              `true`=length(leads),
              `false`=length(alerts)-length(leads),
              missed=length(missed),
              mean_lead=if (length(leads)) decimal(ordered_total(leads)/length(leads)) else "-"
          )
      )
  )
}
radar_cell <- function(point,params) {
  x <- point[1L]
  y <- point[2L]
  r <- params$radar
  col <- as.integer(floor((10*x-r[1L])*r[5L]/(r[3L]-r[1L])))
  row <- as.integer(floor((10*y-r[2L])*r[6L]/(r[4L]-r[2L])))
  if (col >= 0L && col < r[5L] && row >= 0L && row < r[6L]) c(col,r[6L]-1L-row) else NULL
}
radar_snapshot_lines <- function(label,plans,trajectories,conflicts,time,params) {
  width <- params$radar[5L]
  height <- params$radar[6L]
  grid <- matrix(".",height,width)
  observations <- vector("list",length(plans))
  cells <- list()
  for (i in seq_along(trajectories)) {
    observed <- current_position(trajectories[[i]],time)
    if (is.null(observed)) next
    cell <- radar_cell(observed$point,params)
    observations[[i]] <- c(observed,list(cell=cell))
    if (!is.null(cell)) {
      key <- paste(cell,collapse=",")
      cells[[key]] <- c(cells[[key]],i)
    }
  }
  active <- active_conflicts(conflicts,time)
  for (key in names(cells)) {
    cell <- as.integer(strsplit(key,",",fixed=TRUE)[[1L]])
    indices <- cells[[key]]
    character <- if (length(indices) > 1L) as.character(length(indices)) else substr(
        plans[[indices[1L]]]$callsign,
        1L,
        1L
    )
    if (length(indices) == 1L && any(vapply(
        active,
        function(c) indices[1L] %in% c$pair,
        logical(1)
    ))) character <- tolower(character)
    grid[cell[2L]+1L,cell[1L]+1L] <- character
  }
  in_flight <- which(!vapply(observations,is.null,logical(1)))
  for (i in in_flight) {
    predicted <- current_position(trajectories[[i]],time+params$leader)
    if (is.null(predicted)) next
    cell <- radar_cell(predicted$point,params)
    if (!is.null(cell) && grid[cell[2L]+1L,cell[1L]+1L] == ".") grid[cell[2L]+1L,cell[1L]+1L] <- "*"
  }
  lines <- c(
      paste("RADAR",attributes_text(plan=label,t=time,aircraft=length(in_flight),conflicts=length(active))),
      chart(vapply(seq_len(height),function(r) paste(grid[r,],collapse=""),character(1)))
  )
  for (i in in_flight) {
    entry <- observations[[i]]
    point <- entry$point
    cell <- if (is.null(entry$cell)) "outside" else paste(entry$cell,collapse=",")
    lines <- c(
        lines,
        words(
            plans[[i]]$callsign,
            attributes_text(
                x=decimal(point[1L]),
                y=decimal(point[2L]),
                fl=decimal(point[3L]/100,2L),
                track=decimal(segment_track(entry$segment),1L),
                phase=entry$segment$phase,
                cell=cell
            )
        )
    )
  }
  for (c in active) {
    pa <- observations[[c$pair[1L]]]$point
    pb <- observations[[c$pair[2L]]]$point
    dx <- pa[1L]-pb[1L]
    dy <- pa[2L]-pb[2L]
    lines <- c(
        lines,
        words(
            "CONFLICT",
            pair_name(plans,c$pair),
            attributes_text(dist=decimal(sqrt(dx*dx+dy*dy)),vert=decimal(abs(pa[3L]-pb[3L]),1L))
        )
    )
  }
  lines
}
radar_density_lines <- function(label,trajectories,params) {
  width <- params$radar[5L]
  height <- params$radar[6L]
  density <- matrix(0L,height,width)
  for (time in sample_times(params)) for (t in trajectories) {
    observed <- current_position(t,time)
    if (is.null(observed)) next
    cell <- radar_cell(observed$point,params)
    if (is.null(cell)) next
    density[cell[2L]+1L,cell[1L]+1L] <- density[cell[2L]+1L,cell[1L]+1L]+1L
  }
  lines <- paste(
      "DENSITY",
      attributes_text(plan=label,from=params$sample_start,to=params$sample_end,step=60L,max=max(density))
  )
  rows <- vapply(
      seq_len(height),
      function(r) paste(
          ifelse(density[r,] == 0L,".",ifelse(density[r,] < 10L,as.character(density[r,]),"#")),
          collapse=""
      ),
      character(1)
  )
  c(lines,chart(rows))
}
flight_strips <- function(plans,ti,tf,transits,sectors) {
  lines <- character()
  for (i in seq_along(plans)) {
    p <- plans[[i]]
    lines <- c(
        lines,
        words(
            "STRIP",
            p$callsign,
            attributes_text(
                type=p$type,
                waypoints=length(p$waypoints),
                length=decimal(tf[[i]]$length),
                manoeuvres=history_text(p)
            )
        )
    )
    for (k in seq_along(p$waypoints)) {
      w <- p$waypoints[[k]]
      old <- ti[[i]]$waypoint_times[[k]]
      new <- tf[[i]]$waypoint_times[[k]]
      lines <- c(
          lines,
          words(
              "WPT",
              k-1L,
              attributes_text(
                  at=paste(w$x,w$y,sep=":"),
                  eta=paste(decimal(old[1L]),decimal(new[1L]),sep="->"),
                  fl=paste(as.integer(old[2L]),as.integer(new[2L]),sep="->")
              )
          )
      )
    }
    matching <- Filter(function(t) t$aircraft == i,transits)
    entries <- vapply(matching,function(t) paste0(sectors[[t$sector]]$name,"@",decimal(t$entry)),character(1))
    lines <- c(lines,paste("SECTORS",if (length(entries)) paste(entries,collapse=",") else "-"))
  }
  lines
}
main <- function() {
  input <- load_all()
  initial <- input$plans
  types <- input$types
  sectors <- input$sectors
  params <- input$params
  ti <- lapply(initial,build_trajectory,types=types)
  ci <- all_conflicts(ti,params$dh,params$dv)
  resolution <- resolve_conflicts(initial,types,params)
  final <- resolution$plans
  tf <- resolution$trajectories
  cf <- all_conflicts(tf,params$dh,params$dv)
  final_pairs <- vapply(cf,function(c) pair_key(c$pair),character(1))
  ci <- classify_conflicts(ci,sectors,final_pairs,resolution$resolved,params$dh)
  cf <- classify_conflicts(cf,sectors,final_pairs,resolution$resolved,params$dh,TRUE)
  transits_initial <- sector_transits(ti,sectors)
  transits_final <- sector_transits(tf,sectors)
  times <- sample_times(params)
  oi <- occupancy_table(ti,sectors,times)
  of <- occupancy_table(tf,sectors,times)
  periods <- period_table(sectors,times,oi,of,transits_initial,transits_final)
  write_lines("trajectories.csv",trajectories_csv(final,tf))
  write_lines(
      "conflicts.txt",
      c(conflict_lines("initial",initial,ci,ti,params),conflict_lines("final",final,cf,tf,params))
  )
  write_lines("resolutions.txt",resolution_lines(initial,final,ti,tf,ci,cf,resolution))
  write_lines("sector_transits.csv",transit_lines(final,sectors,transits_final))
  write_lines("sector_load.csv",sector_load_lines(sectors,periods))
  write_lines(
      "sector_report.txt",
      sector_report(sectors,times,oi,of,transits_initial,transits_final,ci,cf,ti,tf)
  )
  write_lines(
      "alerts.txt",
      c(alert_lines("initial",initial,ti,ci,params),alert_lines("final",final,tf,cf,params))
  )
  radar <- character()
  for (time in params$snapshots) {
    radar <- c(
        radar,
        radar_snapshot_lines("initial",initial,ti,ci,time,params),
        radar_snapshot_lines("final",final,tf,cf,time,params)
    )
  }
  radar <- c(radar,radar_density_lines("initial",ti,params),radar_density_lines("final",tf,params))
  write_lines("radar.txt",radar)
  write_lines("strips.txt",flight_strips(final,ti,tf,transits_final,sectors))
}
main()
