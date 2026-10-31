source("report.R")
source("eventlog.R")
source("dfg.R")
source("alpha_miner.R")
source("heuristic_miner.R")
source("conformance.R")

words <- function(...) paste(
    vapply(list(...),function(value) if (is.numeric(value)) sprintf("%.0f",value) else value,character(1)),
    collapse=" "
)
mean_fraction <- function(values) q(sum(as.numeric(values)),length(values))
trace_key <- function(trace) if (length(trace)) paste(trace,collapse=",") else "!"
ordered_pairs <- function(counts,by_count=FALSE) {
  keys <- names(counts)
  if (!length(keys)) return(list())
  pairs <- strsplit(keys,"|",fixed=TRUE)
  a <- vapply(pairs,function(p) p[1L],character(1))
  b <- vapply(pairs,function(p) p[2L],character(1))
  indices <- if (by_count) order(-counts,a,b) else order(a,b)
  pairs[indices]
}
prepare_study <- function() {
  input <- read_inputs()
  params <- lapply(input$params,function(value) {
    if (grepl("/",value,fixed=TRUE)) {
      parts <- as.numeric(strsplit(value,"/",fixed=TRUE)[[1L]])
      q(parts[1L],parts[2L])
    } else as.numeric(value)
  })
  events <- list()
  errors <- character()
  adopted <- character()
  for (row in input$rows) {
    t <- timestamp_minutes(row$timestamp)
    identity <- paste(row$case_id,row$activity,row$timestamp,sep="|")
    if (is.null(t)) errors <- c(errors,paste0("line ",row$line,": bad timestamp ",row$timestamp)) else if (identity %in% adopted) errors <- c(
        errors,
        paste0("line ",row$line,": duplicate event ",row$case_id," ",row$activity," ",row$timestamp)
    ) else {
      adopted <- c(adopted,identity)
      row$time <- t
      events[[length(events)+1L]] <- row
    }
  }
  cases <- group_cases(events)
  log <- lapply(cases,function(case) list(trace=case$trace,weight=1))
  list(
      rows=input$rows,
      params=params,
      events=events,
      errors=errors,
      cases=cases,
      activities=sort(unique(vapply(events,function(e) e$activity,character(1)))),
      resources=sort(unique(vapply(events,function(e) e$resource,character(1)))),
      log=log,
      counts=directly_follows(log),
      reference=read_model()
  )
}
build_variants <- function(s) {
  grouped <- list()
  for (case in s$cases) {
    key <- trace_key(case$trace)
    grouped[[key]] <- c(grouped[[key]],list(case))
  }
  keys <- names(grouped)
  keys <- keys[order(-lengths(grouped),keys)]
  variants <- filtered_log <- list()
  variant_by_case <- integer()
  for (number in seq_along(keys)) {
    cases <- grouped[[keys[number]]]
    trace <- cases[[1L]]$trace
    keep <- TRUE
    if (length(trace) > 1L) keep <- all(vapply(
        seq_len(length(trace)-1L),
        function(i) count_at(s$counts,trace[i],trace[i+1L]) >= s$params$filter_min_follows,
        logical(1)
    ))
    variants[[number]] <- list(number=number,trace=trace,cases=cases,keep=keep)
    for (case in cases) variant_by_case[case$identifier] <- number
    if (keep) filtered_log[[length(filtered_log)+1L]] <- list(trace=trace,weight=as.numeric(length(cases)))
  }
  c(
      s,
      list(
          variants=variants,
          variant_by_case=variant_by_case,
          filtered_log=filtered_log,
          kept_cases=sum(vapply(filtered_log,function(e) e$weight,numeric(1))),
          kept_events=sum(vapply(filtered_log,function(e) length(e$trace)*e$weight,numeric(1)))
      )
  )
}
discover <- function(log,activities,relation) {
  candidates <- new.env(hash=TRUE,parent=emptyenv())
  pending <- list()
  causal <- 0L
  key_for <- function(pair) paste(pair_order(pair),collapse="|")
  for (a in activities) for (b in activities) {
    if (relation(a,b) != "->") next
    causal <- causal+1L
    if (relation(a,a) == "#" && relation(b,b) == "#") {
      pair <- list(a,b)
      assign(key_for(pair),TRUE,candidates)
      pending[[length(pending)+1L]] <- pair
    }
  }
  cursor <- 1L
  while (cursor <= length(pending)) {
    pair <- pending[[cursor]]
    cursor <- cursor+1L
    for (a in activities) for (side in 1:2) {
      extended <- extend_pair(pair,a,side,relation)
      if (!is.null(extended) && !exists(key_for(extended),candidates,inherits=FALSE)) {
        assign(key_for(extended),TRUE,candidates)
        pending[[length(pending)+1L]] <- extended
      }
    }
  }
  maximal <- Filter(function(pair) {
    for (a in activities) for (side in 1:2) if (!is.null(extend_pair(pair,a,side,relation))) return(FALSE)
    TRUE
  },pending)
  if (length(maximal)) maximal <- maximal[order(
      vapply(maximal,function(pair) pair_order(pair)[1L],character(1)),
      vapply(maximal,function(pair) pair_order(pair)[2L],character(1))
  )]
  starts <- sort(unique(vapply(log,function(entry) entry$trace[1L],character(1))))
  ends <- sort(unique(vapply(log,function(entry) tail(entry$trace,1L),character(1))))
  places <- c("start",if (length(maximal)) paste0("p",seq_along(maximal)) else character(),"end")
  arcs <- c(
      vapply(starts,function(a) pair_key("start",a),character(1)),
      vapply(ends,function(a) pair_key(a,"end"),character(1))
  )
  for (i in seq_along(maximal)) {
    arcs <- c(
        arcs,
        vapply(maximal[[i]][[1L]],function(a) pair_key(a,paste0("p",i)),character(1)),
        vapply(maximal[[i]][[2L]],function(a) pair_key(paste0("p",i),a),character(1))
    )
  }
  list(
      net=new_net(places,activities,arcs,"start","end"),
      pairs=maximal,
      candidates=length(pending),
      causal=causal,
      starts=starts,
      ends=ends,
      activities=activities
  )
}
pair_line <- function(d) words("PAIRS causal",d$causal,"candidates",d$candidates,"maximal",length(d$pairs))
net_lines <- function(d) {
  net <- d$net
  lines <- words("PLACE start -",name_list(d$starts))
  for (i in seq_along(d$pairs)) lines <- c(
      lines,
      words(paste0("PLACE p",i),name_list(d$pairs[[i]][[1L]]),name_list(d$pairs[[i]][[2L]]))
  )
  lines <- c(lines,words("PLACE end",name_list(d$ends),"-"))
  for (t in net$transitions) lines <- c(
      lines,
      words(
          "TRANSITION",
          t,
          "in",
          name_list(net$places[net$inputs[[t]]]),
          "out",
          name_list(net$places[net$outputs[[t]]])
      )
  )
  c(
      lines,
      words("NET places",length(net$places),"transitions",length(net$transitions),"arcs",length(net$arcs))
  )
}
mine_workflows <- function(s) {
  counts <- directly_follows(s$filtered_log)
  activities <- sort(unique(unlist(lapply(s$filtered_log,function(entry) entry$trace),use.names=FALSE)))
  loops <- activities[vapply(activities,function(a) count_at(counts,a,a) >= 1,logical(1))]
  basic <- function(a,b) basic_relation(counts,a,b)
  alpha <- discover(s$filtered_log,activities,basic)
  lines <- c(
      words("LOG variants",length(s$filtered_log),"cases",s$kept_cases,"activities",name_list(activities)),
      paste("LOOPS",name_list(loops)),
      "MINER alpha",
      footprint(activities,basic),
      pair_line(alpha),
      net_lines(alpha)
  )
  reduced <- lapply(
      s$filtered_log,
      function(entry) list(trace=entry$trace[!(entry$trace %in% loops)],weight=entry$weight)
  )
  retained <- setdiff(activities,loops)
  reduced_counts <- directly_follows(reduced)
  triangles <- triangle_counts(reduced)
  relation <- function(a,b) plus_relation(reduced_counts,triangles,a,b)
  plus <- discover(reduced,retained,relation)
  lines <- c(lines,"MINER alpha_plus")
  for (pair in ordered_pairs(triangles)) lines <- c(
      lines,
      words("TRIANGLE",pair[1L],pair[2L],"count",count_at(triangles,pair[1L],pair[2L]))
  )
  lines <- c(lines,footprint(retained,relation),pair_line(plus))
  arcs <- plus$net$arcs
  for (a in loops) {
    before <- retained[vapply(retained,function(b) count_at(counts,b,a) >= 1,logical(1))]
    after <- retained[vapply(retained,function(b) count_at(counts,a,b) >= 1,logical(1))]
    matches <- which(vapply(plus$pairs,function(pair) identical(pair,list(before,after)),logical(1)))
    place <- if (length(matches)) paste0("p",matches[1L]) else "-"
    if (length(matches)) arcs <- c(arcs,pair_key(place,a),pair_key(a,place))
    lines <- c(lines,words("LOOP",a,"before",name_list(before),"after",name_list(after),"place",place))
  }
  plus$net <- new_net(plus$net$places,activities,arcs,"start","end")
  list(lines=c(lines,net_lines(plus)),nets=list(reference=s$reference,alpha=alpha$net,alpha_plus=plus$net))
}
heuristic_report <- function(s) {
  counts <- s$counts
  triangles <- triangle_counts(s$log)
  minimum_count <- s$params$positive_observations
  loops1 <- loops2 <- character()
  lines <- character()
  for (a in s$activities) {
    n <- count_at(counts,a,a)
    if (n == 0) next
    measure <- loop_measure(n)
    accepted <- n >= minimum_count && qge(measure,s$params$loop1_threshold)
    if (accepted) loops1 <- c(loops1,a)
    lines <- c(lines,words("L1",a,"count",n,"measure",fraction(measure),if (accepted) "ACCEPT" else "REJECT"))
  }
  if (length(s$activities) > 1L) for (i in seq_len(length(s$activities)-1L)) for (j in seq.int(
      i+1L,
      length(s$activities)
  )) {
    a <- s$activities[i]
    b <- s$activities[j]
    n <- count_at(triangles,a,b)+count_at(triangles,b,a)
    if (a %in% loops1 || b %in% loops1 || n == 0) next
    measure <- loop_measure(n)
    accepted <- n >= minimum_count && qge(measure,s$params$loop2_threshold)
    if (accepted) loops2 <- c(loops2,pair_key(a,b))
    lines <- c(
        lines,
        words("L2",a,b,"count",n,"measure",fraction(measure),if (accepted) "ACCEPT" else "REJECT")
    )
  }
  measures <- best_out <- best_in <- list()
  for (pair in ordered_pairs(counts)) {
    a <- pair[1L]
    b <- pair[2L]
    if (a == b) next
    measure <- dependency(counts,a,b)
    measures[[pair_key(a,b)]] <- measure
    best_out[[a]] <- if (is.null(best_out[[a]])) measure else qmax(best_out[[a]],measure)
    best_in[[b]] <- if (is.null(best_in[[b]])) measure else qmax(best_in[[b]],measure)
  }
  edges <- vapply(loops1,function(a) pair_key(a,a),character(1))
  relative <- s$params$relative_to_best
  for (key in names(measures)) {
    pair <- strsplit(key,"|",fixed=TRUE)[[1L]]
    a <- pair[1L]
    b <- pair[2L]
    measure <- measures[[key]]
    if (pair_key(min(a,b),max(a,b)) %in% loops2) verdict <- "LOOP2" else if (count_at(counts,a,b) < minimum_count) verdict <- "REJECT_COUNT" else if (qlt(
        measure,
        s$params$dependency_threshold
    )) verdict <- "REJECT_MEASURE" else if (qlt(relative,qsub(best_out[[a]],measure)) && qlt(relative,qsub(best_in[[b]],measure))) verdict <- "REJECT_BEST" else verdict <- "ACCEPT"
    if (verdict %in% c("LOOP2","ACCEPT")) edges <- union(edges,key)
    lines <- c(
        lines,
        words(
            "DEP",
            a,
            b,
            "count",
            count_at(counts,a,b),
            "reverse",
            count_at(counts,b,a),
            "measure",
            fraction(measure),
            verdict
        )
    )
  }
  inputs <- setNames(
      lapply(
          s$activities,
          function(a) s$activities[vapply(s$activities,function(x) pair_key(x,a) %in% edges,logical(1))]
      ),
      s$activities
  )
  outputs <- setNames(
      lapply(
          s$activities,
          function(a) s$activities[vapply(s$activities,function(x) pair_key(a,x) %in% edges,logical(1))]
      ),
      s$activities
  )
  for (a in s$activities) lines <- c(
      lines,
      words("NODE",a,"in",name_list(inputs[[a]]),"out",name_list(outputs[[a]]))
  )
  for (a in s$activities) for (kind in c("SPLIT","JOIN")) {
    neighbors <- if (kind == "SPLIT") setdiff(outputs[[a]],a) else setdiff(inputs[[a]],a)
    if (length(neighbors) > 1L) for (i in seq_len(length(neighbors)-1L)) for (j in seq.int(
        i+1L,
        length(neighbors)
    )) {
      b <- neighbors[i]
      c <- neighbors[j]
      measure <- if (kind == "SPLIT") split_measure(counts,a,b,c) else join_measure(counts,a,b,c)
      lines <- c(
          lines,
          words(
              kind,
              a,
              b,
              c,
              "measure",
              fraction(measure),
              if (qge(measure,s$params$and_threshold)) "AND" else "XOR"
          )
      )
    }
  }
  c(
      lines,
      words(
          "GRAPH activities",
          length(s$activities),
          "edges",
          length(edges),
          "loops1",
          length(loops1),
          "loops2",
          length(loops2)
      )
  )
}
explore <- function(net) {
  key_for <- function(marking) paste(marking,collapse=",")
  markings <- list(net$initial_marking)
  seen <- new.env(hash=TRUE,parent=emptyenv())
  assign(key_for(net$initial_marking),1L,seen)
  edges <- list()
  reverse <- list(integer())
  enabled_at <- list()
  ever <- character()
  unsafe <- deadlocks <- 0L
  cursor <- 1L
  while (cursor <= length(markings)) {
    marking <- markings[[cursor]]
    transitions <- enabled_transitions(net,marking)
    enabled_at[[cursor]] <- transitions
    ever <- union(ever,transitions)
    if (!length(transitions) && !identical(marking,net$final_marking)) deadlocks <- deadlocks+1L
    for (t in transitions) {
      after <- fire(net,marking,t)
      if (any(after > 1L)) {
        unsafe <- unsafe+1L
        next
      }
      key <- key_for(after)
      if (!exists(key,seen,inherits=FALSE)) {
        markings[[length(markings)+1L]] <- after
        assign(key,length(markings),seen)
        reverse[[length(markings)]] <- integer()
      }
      next_id <- get(key,seen,inherits=FALSE)
      edges[[length(edges)+1L]] <- list(before=cursor,transition=t,after=next_id)
      reverse[[next_id]] <- union(reverse[[next_id]],cursor)
    }
    cursor <- cursor+1L
  }
  final_key <- key_for(net$final_marking)
  final <- exists(final_key,seen,inherits=FALSE)
  reachable <- rep(FALSE,length(markings))
  pending <- integer()
  if (final) {
    final_id <- get(final_key,seen,inherits=FALSE)
    reachable[final_id] <- TRUE
    pending <- final_id
  }
  cursor <- 1L
  while (cursor <= length(pending)) {
    for (before in reverse[[pending[cursor]]]) if (!reachable[before]) {
      reachable[before] <- TRUE
      pending <- c(pending,before)
    }
    cursor <- cursor+1L
  }
  dead <- setdiff(net$transitions,ever)
  stuck <- sum(!reachable)
  follows <- numeric()
  for (edge in edges) for (u in enabled_at[[edge$after]]) follows[pair_key(edge$transition,u)] <- 1
  list(
      markings=length(markings),
      edges=length(edges),
      unsafe=unsafe,
      deadlocks=deadlocks,
      stuck=stuck,
      final=final,
      dead=dead,
      sound=unsafe == 0L && stuck == 0L && !length(dead),
      follows=follows
  )
}
build_prefixes <- function(cases) {
  prefixes <- list()
  for (case in cases) for (n in 0:length(case$trace)) {
    prefix <- case$trace[seq_len(n)]
    key <- trace_key(prefix)
    entry <- prefixes[[key]]
    if (is.null(entry)) entry <- list(trace=prefix,weight=0,followers=character())
    if (n < length(case$trace)) entry$followers <- union(entry$followers,case$trace[n+1L])
    entry$weight <- entry$weight+1
    prefixes[[key]] <- entry
  }
  prefixes
}
precision_report <- function(name,net,prefixes) {
  fitting <- allowed <- escaping <- 0
  weights <- numeric()
  for (entry in prefixes) {
    marking <- net$initial_marking
    fits <- TRUE
    for (t in entry$trace) {
      if (!(t %in% net$transitions) || !enabled(net,marking,t)) {
        fits <- FALSE
        break
      }
      marking <- fire(net,marking,t)
    }
    if (!fits) next
    fitting <- fitting+1
    transitions <- enabled_transitions(net,marking)
    escapes <- setdiff(transitions,entry$followers)
    allowed <- allowed+entry$weight*length(transitions)
    escaping <- escaping+entry$weight*length(escapes)
    for (t in escapes) weights <- add_count(weights,t,entry$weight)
  }
  lines <- words(
      "PRECISION",
      name,
      "prefixes",
      fitting,
      "allowed",
      allowed,
      "escaping",
      escaping,
      "precision",
      fraction(if (allowed == 0) q(1) else q(allowed-escaping,allowed))
  )
  for (t in names(weights)[order(-weights,names(weights))]) lines <- c(
      lines,
      words("ESCAPE",name,t,"weight",weights[[t]])
  )
  lines
}
replay_case <- function(net,case) {
  r <- new_replay_totals(length(net$places))
  tokens <- lapply(net$places,function(unused) numeric())
  tokens[[net$initial]] <- case$events[[1L]]$time
  r$produced <- 1
  for (event in case$events) {
    t <- event$activity
    if (!(t %in% net$transitions)) {
      r$skipped <- r$skipped+1
      next
    }
    for (p in net$inputs[[t]]) {
      r$consumed <- r$consumed+1
      if (length(tokens[[p]])) {
        r$waiting[[p]] <- c(r$waiting[[p]],event$time-tokens[[p]][1L])
        tokens[[p]] <- tokens[[p]][-1L]
        r$routes[[p]] <- add_count(r$routes[[p]],t)
      } else {
        r$missing <- r$missing+1
        r$place_missing[p] <- r$place_missing[p]+1
      }
    }
    for (p in net$outputs[[t]]) {
      tokens[[p]] <- c(tokens[[p]],event$time)
      r$produced <- r$produced+1
    }
  }
  r$consumed <- r$consumed+1
  if (length(tokens[[net$final]])) tokens[[net$final]] <- tokens[[net$final]][-1L] else {
    r$missing <- r$missing+1
    r$place_missing[net$final] <- r$place_missing[net$final]+1
  }
  for (p in seq_along(tokens)) {
    r$place_remaining[p] <- length(tokens[[p]])
    r$remaining <- r$remaining+length(tokens[[p]])
    r$deviating[p] <- as.integer(r$place_missing[p] > 0 || length(tokens[[p]]) > 0L)
  }
  r
}
aggregate_replays <- function(net,cases) {
  total <- new_replay_totals(length(net$places))
  results <- list()
  fitting <- 0L
  for (case in cases) {
    r <- replay_case(net,case)
    results[[case$identifier]] <- r
    fitting <- fitting+as.integer(r$missing == 0 && r$remaining == 0)
    for (field in c(
        "missing",
        "remaining",
        "consumed",
        "produced",
        "skipped"
    )) total[[field]] <- total[[field]]+r[[field]]
    for (p in seq_along(net$places)) {
      total$place_missing[p] <- total$place_missing[p]+r$place_missing[p]
      total$place_remaining[p] <- total$place_remaining[p]+r$place_remaining[p]
      total$deviating[p] <- total$deviating[p]+r$deviating[p]
      total$waiting[[p]] <- c(total$waiting[[p]],r$waiting[[p]])
      for (t in names(r$routes[[p]])) total$routes[[p]] <- add_count(total$routes[[p]],t,r$routes[[p]][[t]])
    }
  }
  list(total=total,results=results,fitting=fitting)
}
conformance_report <- function(s,nets) {
  lines <- words(
      "MODEL places",
      length(s$reference$places),
      "transitions",
      length(s$reference$transitions),
      "arcs",
      length(s$reference$arcs)
  )
  explorations <- list()
  for (name in names(nets)) {
    r <- explore(nets[[name]])
    explorations[[name]] <- r
    lines <- c(
        lines,
        words(
            "REACHABILITY",
            name,
            "markings",
            r$markings,
            "edges",
            r$edges,
            "unsafe",
            r$unsafe,
            "deadlocks",
            r$deadlocks,
            "stuck",
            r$stuck,
            "final",
            if (r$final) "yes" else "no",
            "dead",
            name_list(r$dead),
            "sound",
            if (r$sound) "yes" else "no"
        )
    )
  }
  for (name in names(nets)) {
    net <- nets[[name]]
    activities <- sort(union(s$activities,net$transitions))
    follows <- explorations[[name]]$follows
    differences <- list()
    for (a in activities) for (b in activities) {
      log <- basic_relation(s$counts,a,b)
      model <- basic_relation(follows,a,b)
      if (log != model) differences[[length(differences)+1L]] <- c(a,b,log,model)
    }
    cells <- length(activities)*length(activities)
    lines <- c(
        lines,
        words(
            "FOOTPRINT",
            name,
            "activities",
            length(activities),
            "cells",
            cells,
            "differing",
            length(differences),
            "fitness",
            fraction(q(cells-length(differences),cells))
        )
    )
    if (name == "reference") for (diff in differences) if (diff[1L] <= diff[2L]) lines <- c(
        lines,
        words("DIFF",diff[1L],diff[2L],"log",diff[3L],"model",diff[4L])
    )
  }
  prefixes <- build_prefixes(s$cases)
  for (name in names(nets)) lines <- c(lines,precision_report(name,nets[[name]],prefixes))
  reference_replays <- list()
  for (name in names(nets)) {
    net <- nets[[name]]
    aggregate <- aggregate_replays(net,s$cases)
    total <- aggregate$total
    if (name == "reference") reference_replays <- aggregate$results
    lines <- c(
        lines,
        words(
            "REPLAY",
            name,
            "cases",
            length(s$cases),
            "fitting",
            aggregate$fitting,
            "skipped",
            total$skipped,
            "missing",
            total$missing,
            "remaining",
            total$remaining,
            "consumed",
            total$consumed,
            "produced",
            total$produced,
            "fitness",
            fraction(fitness(total))
        )
    )
    for (p in seq_along(net$places)) {
      waiting <- total$waiting[[p]]
      mean <- if (length(waiting)) fraction(mean_fraction(waiting)) else "-"
      largest <- if (length(waiting)) as.character(max(waiting)) else "-"
      lines <- c(
          lines,
          words(
              "PLACE",
              name,
              net$places[p],
              "missing",
              total$place_missing[p],
              "remaining",
              total$place_remaining[p],
              "deviating",
              total$deviating[p],
              "tokens",
              length(waiting),
              "mean",
              mean,
              "max",
              largest
          )
      )
    }
    for (p in seq_along(net$places)) if (length(net$routes[[p]]) >= 2L) {
      consumptions <- vapply(
          net$routes[[p]],
          function(t) paste0(t,"=",if (t %in% names(total$routes[[p]])) total$routes[[p]][[t]] else 0),
          character(1)
      )
      lines <- c(lines,words("ROUTE",name,net$places[p],paste(consumptions,collapse=",")))
    }
  }
  list(lines=lines,replays=reference_replays)
}
log_summary <- function(s) {
  lines <- paste("ERROR",s$errors)
  if (!length(s$errors)) lines <- character()
  times <- vapply(s$events,function(e) e$time,integer(1))
  earliest <- s$events[[which.min(times)]]
  latest <- s$events[[which.max(times)]]
  lines <- c(
      lines,
      words(
          "LOG rows",
          length(s$rows),
          "adopted",
          length(s$events),
          "rejected",
          length(s$errors),
          "cases",
          length(s$cases),
          "activities",
          length(s$activities),
          "resources",
          length(s$resources),
          "first",
          earliest$timestamp,
          "last",
          latest$timestamp
      )
  )
  for (a in s$activities) {
    events <- Filter(function(e) e$activity == a,s$events)
    waits <- numeric()
    for (case in s$cases) if (length(case$events) > 1L) for (i in seq.int(2L,length(case$events))) if (case$events[[i]]$activity == a) waits <- c(
        waits,
        case$events[[i]]$time-case$events[[i-1L]]$time
    )
    cases <- sum(vapply(s$cases,function(c) a %in% c$trace,logical(1)))
    starts <- sum(vapply(s$cases,function(c) c$trace[1L] == a,logical(1)))
    ends <- sum(vapply(s$cases,function(c) tail(c$trace,1L) == a,logical(1)))
    rework <- sum(vapply(s$cases,function(c) sum(c$trace == a) >= 2L,logical(1)))
    lines <- c(
        lines,
        words(
            "ACTIVITY",
            a,
            "events",
            length(events),
            "cases",
            cases,
            "start",
            starts,
            "end",
            ends,
            "rework",
            rework,
            "wait",
            if (length(waits)) fraction(mean_fraction(waits)) else "-",
            "resources",
            length(unique(vapply(events,function(e) e$resource,character(1)))),
            "model",
            if (a %in% s$reference$transitions) "yes" else "no"
        )
    )
  }
  lengths <- vapply(s$cases,function(c) length(c$events),integer(1))
  durations <- vapply(s$cases,function(c) c$duration,integer(1))
  for (label in c("LENGTH","DURATION")) {
    values <- if (label == "LENGTH") lengths else durations
    lines <- c(
        lines,
        words(
            label,
            "min",
            min(values),
            "max",
            max(values),
            "mean",
            fraction(mean_fraction(values)),
            "median",
            fraction(integer_median(values))
        )
    )
  }
  days <- durations %/% 1440L
  for (day in 0:max(days)) {
    n <- sum(days == day)
    lines <- c(lines,words("DAYS",day,"cases",n,"share",percentage(n,length(s$cases))))
  }
  late <- sum(durations > s$params$sla_minutes)
  lines <- c(
      lines,
      words("SLA limit",s$params$sla_minutes,"late",late,"share",percentage(late,length(s$cases)))
  )
  weekdays <- c("Mon","Tue","Wed","Thu","Fri","Sat","Sun")
  weekday <- function(t) (t %/% 1440L+3L) %% 7L
  for (i in seq_along(weekdays)) {
    events <- sum(vapply(s$events,function(e) weekday(e$time) == i-1L,logical(1)))
    starts <- sum(vapply(s$cases,function(c) weekday(c$events[[1L]]$time) == i-1L,logical(1)))
    ends <- sum(vapply(s$cases,function(c) weekday(c$events[[length(c$events)]]$time) == i-1L,logical(1)))
    lines <- c(lines,words("WEEKDAY",weekdays[i],"events",events,"starts",starts,"ends",ends))
  }
  lines
}
variant_report <- function(s,replays) {
  lines <- character()
  for (v in s$variants) {
    durations <- vapply(v$cases,function(c) c$duration,integer(1))
    lines <- c(
        lines,
        words(
            "VARIANT",
            v$number,
            "count",
            length(v$cases),
            "share",
            percentage(length(v$cases),length(s$cases)),
            "length",
            length(v$trace),
            "first",
            v$cases[[1L]]$identifier,
            "duration",
            fraction(mean_fraction(durations)),
            "late",
            sum(durations > s$params$sla_minutes),
            "fitness",
            fraction(fitness(replays[[v$cases[[1L]]$identifier]])),
            if (v$keep) "KEEP" else "DROP",
            name_list(v$trace)
        )
    )
  }
  c(
      lines,
      words(
          "FILTER min_follows",
          s$params$filter_min_follows,
          "variants",
          length(s$filtered_log),
          "of",
          length(s$variants),
          "cases",
          s$kept_cases,
          "of",
          length(s$cases),
          "events",
          s$kept_events,
          "of",
          length(s$events)
      )
  )
}
dfg_report <- function(s) {
  starts <- setNames(
      vapply(
          s$activities,
          function(a) sum(vapply(s$cases,function(c) c$trace[1L] == a,logical(1))),
          numeric(1)
      ),
      s$activities
  )
  ends <- setNames(
      lapply(
          s$activities,
          function(a) vapply(
              Filter(function(c) tail(c$trace,1L) == a,s$cases),
              function(c) c$duration,
              integer(1)
          )
      ),
      s$activities
  )
  names_start <- names(starts)[starts > 0]
  names_start <- names_start[order(-starts[names_start],names_start)]
  lines <- vapply(names_start,function(a) words("START",a,"count",starts[[a]]),character(1))
  names_end <- names(ends)[lengths(ends) > 0L]
  names_end <- names_end[order(-lengths(ends[names_end]),names_end)]
  for (a in names_end) lines <- c(
      lines,
      words("END",a,"count",length(ends[[a]]),"duration",fraction(mean_fraction(ends[[a]])))
  )
  for (pair in ordered_pairs(s$counts,TRUE)) {
    a <- pair[1L]
    b <- pair[2L]
    waiting <- numeric()
    cases <- 0L
    for (case in s$cases) {
      found <- FALSE
      if (length(case$events) > 1L) for (i in seq_len(length(case$events)-1L)) if (case$trace[i] == a && case$trace[i+1L] == b) {
        waiting <- c(waiting,case$events[[i+1L]]$time-case$events[[i]]$time)
        found <- TRUE
      }
      cases <- cases+as.integer(found)
    }
    lines <- c(
        lines,
        words(
            "EDGE",
            a,
            b,
            "count",
            count_at(s$counts,a,b),
            "cases",
            cases,
            "mean",
            fraction(mean_fraction(waiting)),
            "min",
            min(waiting),
            "max",
            max(waiting)
        )
    )
  }
  c(lines,footprint(s$activities,function(a,b) basic_relation(s$counts,a,b)))
}
resource_report <- function(s) {
  handovers <- handover_cases <- subcontract <- together <- numeric()
  for (case in s$cases) {
    workers <- vapply(case$events,function(e) e$resource,character(1))
    present <- sort(unique(workers))
    pairs <- character()
    if (length(workers) > 1L) for (i in seq_len(length(workers)-1L)) {
      key <- pair_key(workers[i],workers[i+1L])
      pairs <- c(pairs,key)
      handovers <- add_count(handovers,key)
    }
    for (key in unique(pairs)) handover_cases <- add_count(handover_cases,key)
    if (length(workers) > 2L) for (i in seq_len(length(workers)-2L)) if (workers[i] == workers[i+2L] && workers[i] != workers[i+1L]) subcontract <- add_count(
        subcontract,
        pair_key(workers[i],workers[i+1L])
    )
    if (length(present) > 1L) for (i in seq_len(length(present)-1L)) for (j in seq.int(i+1L,length(present))) together <- add_count(
        together,
        pair_key(present[i],present[j])
    )
  }
  lines <- character()
  for (number in seq_along(s$resources)) {
    resource <- s$resources[number]
    events <- Filter(function(e) e$resource == resource,s$events)
    activities <- sort(unique(vapply(events,function(e) e$activity,character(1))))
    work <- vapply(
        activities,
        function(a) paste0(a,"=",sum(vapply(events,function(e) e$activity == a,logical(1)))),
        character(1)
    )
    cases <- sum(vapply(
        s$cases,
        function(c) any(vapply(c$events,function(e) e$resource == resource,logical(1))),
        logical(1)
    ))
    lines <- c(
        lines,
        words(
            "RESOURCE",
            number,
            resource,
            "events",
            length(events),
            "cases",
            cases,
            "work",
            paste(work,collapse=",")
        )
    )
  }
  for (pair in ordered_pairs(handovers,TRUE)) if (pair[1L] != pair[2L]) lines <- c(
      lines,
      words(
          "HANDOVER",
          pair[1L],
          pair[2L],
          "count",
          count_at(handovers,pair[1L],pair[2L]),
          "cases",
          count_at(handover_cases,pair[1L],pair[2L])
      )
  )
  rows <- lapply(s$resources,function(a) vapply(s$resources,function(b) count_at(handovers,a,b),numeric(1)))
  lines <- c(lines,table_lines(rows,5L))
  for (pair in ordered_pairs(subcontract,TRUE)) lines <- c(
      lines,
      words("SUBCONTRACT",pair[1L],pair[2L],"count",count_at(subcontract,pair[1L],pair[2L]))
  )
  for (pair in ordered_pairs(together,TRUE)) lines <- c(
      lines,
      words("TOGETHER",pair[1L],pair[2L],"cases",count_at(together,pair[1L],pair[2L]))
  )
  total <- sum(handovers)
  own <- sum(vapply(s$resources,function(a) count_at(handovers,a,a),numeric(1)))
  c(lines,words("TOTAL handovers",total,"self",own,"other",total-own))
}
main <- function() {
  invisible(Sys.setlocale("LC_COLLATE","C"))
  s <- build_variants(prepare_study())
  workflows <- mine_workflows(s)
  conformance <- conformance_report(s,workflows$nets)
  replays <- conformance$replays
  csv <- "case_id,variant,events,skipped,missing,remaining,consumed,produced,fitness"
  for (case in s$cases) {
    r <- replays[[case$identifier]]
    csv <- c(
        csv,
        paste(
            c(
                case$identifier,
                s$variant_by_case[[case$identifier]],
                length(case$events),
                r$skipped,
                r$missing,
                r$remaining,
                r$consumed,
                r$produced,
                fraction(fitness(r))
            ),
            collapse=","
        )
    )
  }
  write_outputs(list(
      "log_summary.txt"=log_summary(s),
      "variants.txt"=variant_report(s,replays),
      "dfg.txt"=dfg_report(s),
      "alpha_net.txt"=workflows$lines,
      "heuristic_net.txt"=heuristic_report(s),
      "conformance.csv"=csv,
      "conformance.txt"=conformance$lines,
      "resources.txt"=resource_report(s)
  ))
}
main()
