source("minstd.R")
source("cluster.R")
source("raft_node.R")
source("network.R")
source("checker.R")

words <- function(...) paste(...,collapse=" ")
node_set <- function(nodes) if (length(nodes)) paste0("n",sort(unique(nodes)),collapse=",") else "-"
command_text <- function(command) paste(unlist(command,use.names=FALSE),collapse=" ")
new_simulation <- function(settings,script,network) {
  s <- new.env(parent=emptyenv())
  s$settings <- settings
  s$nodes <- lapply(seq_len(settings$nodes),new_node)
  s$network <- network
  s$random <- new_minstd(settings$seed)
  s$controls <- script$controls
  s$requests <- script$requests
  s$checker <- new_checker()
  s$time <- s$leader_ticks <- s$multi_ticks <- s$maximum_term <- s$committed_count <- 0L
  s$trace <- s$timelines <- character()
  s$elections <- s$gaps <- list()
  s$leaders <- new.env(hash=TRUE,parent=emptyenv())
  s$gap_start <- -1L
  s$reference_states <- list()
  s$reference_state <- new_store()
  s$status_counts <- new.env(hash=TRUE,parent=emptyenv())
  s$latencies <- integer()
  s$key_requests <- s$key_committed <- integer()
  s
}
majority <- function(s,count) 2L*count > s$settings$nodes
write_trace <- function(s,content) s$trace <- c(s$trace,paste(s$time,content))
set_election_timer <- function(s,node) node$election_deadline <- s$time+between(
    s$random,
    s$settings$election_min,
    s$settings$election_max
)
send_message <- function(s,node,destination,kind,data) network_send(
    s$network,
    s$time,
    node$number,
    destination,
    node$term,
    kind,
    data
)
send_append <- function(s,node,destination) {
  previous <- node$next_index[destination]-1L
  last <- min(previous+s$settings$batch,last_index(node))
  entries <- if (previous < last) node$log[seq.int(previous+1L,last)] else list()
  send_message(
      s,
      node,
      destination,
      "AE",
      list(previous=previous,previous_term=term_at(node,previous),entries=entries,commit=node$commit)
  )
}
broadcast_append <- function(s,node) {
  for (other in s$nodes) if (other$number != node$number) send_append(s,node,other$number)
}
end_leadership <- function(s,node,reason) {
  record <- s$leaders[[as.character(node$term)]]
  record$ended <- s$time
  record$reason <- reason
  record$commit <- node$commit
  cancel_transfer(node)
}
control_event <- function(s,event) {
  kind <- event$kind
  arguments <- event$arguments
  if (kind == "CRASH") {
    node <- s$nodes[[arguments[1L]]]
    write_trace(s,words("CRASH",paste0("n",node$number),node$role,"term",node$term))
    if (node$role == "LEADER") end_leadership(s,node,"CRASH")
    crash_node(node)
  } else if (kind == "RESTART") {
    node <- s$nodes[[arguments[1L]]]
    node$up <- TRUE
    set_election_timer(s,node)
    write_trace(
        s,
        words(
            "RESTART",
            paste0("n",node$number),
            "term",
            node$term,
            "length",
            last_index(node),
            "deadline",
            node$election_deadline
        )
    )
  } else if (kind == "PARTITION") {
    for (i in seq_along(arguments)) s$network$groups[arguments[[i]]] <- i
    write_trace(s,paste("PARTITION",paste(vapply(arguments,node_set,character(1)),collapse=" ")))
  } else if (kind == "HEAL") {
    s$network$groups[] <- 0L
    write_trace(s,"HEAL")
  } else start_transfer(s,s$nodes[[arguments[1L]]],arguments[2L])
}
attempt_request <- function(s,request) {
  request$attempts <- request$attempts+1L
  destination <- request$destination
  redirected <- 0L
  reason <- ""
  repeat {
    node <- s$nodes[[destination]]
    if (!node$up) {
      reason <- "down"
      break
    }
    if (node$role == "LEADER") {
      if (node$transfer_target != 0L) {
        reason <- "transfer"
        break
      }
      node$log[[length(node$log)+1L]] <- new_entry(node$term,request$command,request$number)
      leader <- s$leaders[[as.character(node$term)]]
      leader$appended <- leader$appended+1L
      request$accepted_index <- last_index(node)
      request$accepted_term <- node$term
      request$scheduled <- -1L
      write_trace(
          s,
          words(
              "ACCEPT",
              paste0("r",request$number),
              paste0("n",node$number),
              "index",
              last_index(node),
              "term",
              node$term
          )
      )
      return(invisible(NULL))
    }
    if (node$known_leader == 0L || redirected >= s$settings$nodes-1L) {
      reason <- "noleader"
      break
    }
    destination <- node$known_leader
    write_trace(
        s,
        words("REDIRECT",paste0("r",request$number),paste0("n",node$number),paste0("n",destination))
    )
    redirected <- redirected+1L
    request$redirects <- request$redirects+1L
  }
  node <- s$nodes[[destination]]
  prefix <- words("REJECT",paste0("r",request$number),paste0("n",node$number),reason)
  if (request$attempts < s$settings$attempts) {
    request$destination <- node$number %% s$settings$nodes+1L
    request$scheduled <- s$time+s$settings$retry
    write_trace(s,words(prefix,"retry",paste0("n",request$destination),"at",request$scheduled))
  } else {
    request$abandoned <- TRUE
    request$scheduled <- -1L
    write_trace(s,paste(prefix,"giveup"))
  }
  invisible(NULL)
}
start_election <- function(s,node,trigger) {
  node$term <- node$term+1L
  node$role <- "CANDIDATE"
  node$voted_for <- node$number
  node$votes <- node$number
  node$known_leader <- 0L
  set_election_timer(s,node)
  node$stats["elections"] <- node$stats["elections"]+1L
  record <- new.env(parent=emptyenv())
  record$time <- s$time
  record$node <- node$number
  record$term <- node$term
  record$trigger <- trigger
  record$votes <- node$votes
  record$won <- -1L
  s$elections[[length(s$elections)+1L]] <- record
  node$election_record <- length(s$elections)
  write_trace(
      s,
      words(
          "ELECTION",
          paste0("n",node$number),
          "term",
          node$term,
          "last",
          paste(last_index(node),last_term(node),sep="/"),
          "deadline",
          node$election_deadline
      )
  )
  for (other in s$nodes) if (other$number != node$number) send_message(
      s,
      node,
      other$number,
      "RV",
      list(last_index=last_index(node),last_term=last_term(node))
  )
}
vote_request <- function(s,node,message) {
  reason <- if (message$term < node$term) "term" else if (node$voted_for != 0L && node$voted_for != message$source) "voted" else if (!accepts_log(
      node,
      message$data$last_index,
      message$data$last_term
  )) "log" else ""
  if (!nzchar(reason)) {
    node$voted_for <- message$source
    node$stats["votes_granted"] <- node$stats["votes_granted"]+1L
    set_election_timer(s,node)
    write_trace(
        s,
        words(
            "VOTE",
            paste0("n",node$number),
            paste0("n",message$source),
            "term",
            node$term,
            "deadline",
            node$election_deadline
        )
    )
  } else write_trace(
      s,
      words("DENY",paste0("n",node$number),paste0("n",message$source),"term",node$term,reason)
  )
  send_message(s,node,message$source,"RVR",list(granted=!nzchar(reason)))
}
vote_response <- function(s,node,message) {
  if (node$role != "CANDIDATE" || message$term != node$term || !message$data$granted) return(invisible(NULL))
  node$votes <- union(node$votes,message$source)
  s$elections[[node$election_record]]$votes <- node$votes
  if (majority(s,length(node$votes))) become_leader(s,node)
  invisible(NULL)
}
become_leader <- function(s,node) {
  node$role <- "LEADER"
  node$known_leader <- node$number
  node$next_index <- rep(last_index(node)+1L,s$settings$nodes)
  node$match_index <- integer(s$settings$nodes)
  node$log[[length(node$log)+1L]] <- new_entry(node$term,list(kind="NOOP"),0L)
  node$stats["leader_terms"] <- node$stats["leader_terms"]+1L
  s$elections[[node$election_record]]$won <- s$time
  check_leader(s$checker,node)
  record <- new.env(parent=emptyenv())
  record$node <- node$number
  record$elected <- s$time
  record$votes <- node$votes
  record$appended <- 1L
  record$ended <- -1L
  record$reason <- ""
  record$commit <- 0L
  s$leaders[[as.character(node$term)]] <- record
  write_trace(
      s,
      words(
          "LEADER",
          paste0("n",node$number),
          "term",
          node$term,
          "votes",
          node_set(node$votes),
          "noop",
          last_index(node)
      )
  )
  broadcast_append(s,node)
  node$heartbeat_deadline <- s$time+s$settings$heartbeat
  node$quorum_deadline <- s$time+s$settings$quorum
  node$heard <- integer()
}
truncate_log <- function(s,node,first) {
  removed <- node$log[seq.int(first,length(node$log))]
  node$log <- node$log[seq_len(first-1L)]
  node$stats["truncated"] <- node$stats["truncated"]+length(removed)
  check_truncate(s$checker,first,removed)
  write_trace(s,words("TRUNCATE",paste0("n",node$number),"from",first,"removed",length(removed)))
}
append_request <- function(s,node,message) {
  if (message$term < node$term) {
    send_message(s,node,message$source,"AER",list(success=FALSE,matched=0L))
    return(invisible(NULL))
  }
  if (node$role == "CANDIDATE") {
    node$role <- "FOLLOWER"
    write_trace(s,words("YIELD",paste0("n",node$number),"term",node$term,paste0("n",message$source)))
  }
  node$known_leader <- message$source
  set_election_timer(s,node)
  previous <- message$data$previous
  if (previous > last_index(node) || term_at(node,previous) != message$data$previous_term) {
    node$stats["ae_fail"] <- node$stats["ae_fail"]+1L
    hint <- if (previous > last_index(node)) last_index(node) else previous-1L
    send_message(s,node,message$source,"AER",list(success=FALSE,matched=hint))
    return(invisible(NULL))
  }
  node$stats["ae_ok"] <- node$stats["ae_ok"]+1L
  for (offset in seq_along(message$data$entries)) {
    entry <- message$data$entries[[offset]]
    index <- previous+offset
    if (index <= last_index(node) && term_at(node,index) != entry$term) truncate_log(s,node,index)
    if (index > last_index(node)) {
      node$log[[length(node$log)+1L]] <- entry
      node$stats["appended"] <- node$stats["appended"]+1L
    }
  }
  confirmed <- previous+length(message$data$entries)
  commit <- min(message$data$commit,confirmed)
  if (commit > node$commit) advance_commit(s,node,commit)
  send_message(s,node,message$source,"AER",list(success=TRUE,matched=confirmed))
}
append_response <- function(s,node,message) {
  if (node$role != "LEADER" || message$term != node$term) return(invisible(NULL))
  source <- message$source
  confirmed <- message$data$matched
  node$heard <- union(node$heard,source)
  if (message$data$success) {
    node$match_index[source] <- max(node$match_index[source],confirmed)
    node$next_index[source] <- max(node$next_index[source],confirmed+1L)
    check_commit(s,node)
    if (source == node$transfer_target && !node$transfer_sent && node$match_index[source] == last_index(node)) {
      send_timeout_now(s,node)
    } else if (node$next_index[source] <= last_index(node)) {
      send_append(s,node,source)
    }
  } else {
    node$next_index[source] <- max(node$match_index[source]+1L,min(node$next_index[source]-1L,confirmed+1L))
    write_trace(
        s,
        words("BACKTRACK",paste0("n",node$number),paste0("n",source),"next",node$next_index[source])
    )
    send_append(s,node,source)
  }
  invisible(NULL)
}
check_commit <- function(s,node) {
  if (last_index(node) <= node$commit) return(invisible(NULL))
  for (index in seq.int(last_index(node),node$commit+1L)) {
    if (term_at(node,index) != node$term) return(invisible(NULL))
    replicated <- 1L+sum(node$match_index >= index)
    if (majority(s,replicated)) {
      write_trace(
          s,
          words("COMMIT",paste0("n",node$number),paste(node$commit+1L,index,sep="-"),"term",node$term)
      )
      advance_commit(s,node,index)
      return(invisible(NULL))
    }
  }
  invisible(NULL)
}
advance_commit <- function(s,node,index) {
  for (position in seq.int(node$commit+1L,index)) record_commit(
      s$checker,
      position,
      term_at(node,position),
      s$time
  )
  node$commit <- index
  first <- node$applied+1L
  for (position in seq.int(first,index)) {
    entry <- node$log[[position]]
    result <- apply_command(node$store,entry$command)
    node$stats["applies"] <- node$stats["applies"]+1L
    record_apply(s$checker,position,entry,result)
  }
  node$applied <- index
  write_trace(s,words("APPLY",paste0("n",node$number),paste(first,index,sep="-")))
}
receive_message <- function(s,message) {
  node <- s$nodes[[message$destination]]
  if (message$term > node$term) {
    role <- node$role
    write_trace(
        s,
        words(
            "TERM",
            paste0("n",node$number),
            paste(node$term,message$term,sep="->"),
            message$kind,
            paste0("n",message$source),
            role
        )
    )
    if (role == "LEADER") end_leadership(s,node,"STEPDOWN")
    node$term <- message$term
    node$voted_for <- node$known_leader <- 0L
    node$role <- "FOLLOWER"
    if (role == "LEADER") set_election_timer(s,node)
  }
  if (message$kind == "RV") {
    vote_request(s,node,message)
  } else if (message$kind == "RVR") {
    vote_response(s,node,message)
  } else if (message$kind == "AE") {
    append_request(s,node,message)
  } else if (message$kind == "AER") {
    append_response(s,node,message)
  } else if (message$term != node$term || node$role != "FOLLOWER") {
    write_trace(s,words("IGNORE",paste0("n",node$number),"TN",paste0("n",message$source),"term",message$term))
  } else {
    start_election(s,node,"transfer")
  }
}
start_transfer <- function(s,node,destination) {
  prefix <- words("TRANSFER",paste0("n",node$number),paste0("n",destination))
  if (!node$up || node$role != "LEADER" || node$transfer_target != 0L || node$number == destination) {
    write_trace(s,paste(prefix,"ignored"))
    return(invisible(NULL))
  }
  write_trace(s,words(prefix,"start match",paste(node$match_index[destination],last_index(node),sep="/")))
  node$transfer_target <- destination
  node$transfer_sent <- FALSE
  node$transfer_deadline <- s$time+s$settings$election_min
  if (node$match_index[destination] == last_index(node)) send_timeout_now(s,node) else send_append(
      s,
      node,
      destination
  )
  invisible(NULL)
}
send_timeout_now <- function(s,node) {
  write_trace(
      s,
      words(
          "TIMEOUTNOW",
          paste0("n",node$number),
          paste0("n",node$transfer_target),
          "term",
          node$term,
          "index",
          last_index(node)
      )
  )
  node$transfer_sent <- TRUE
  send_message(s,node,node$transfer_target,"TN",list())
}
process_timers <- function(s,node) {
  if (node$role == "LEADER") {
    if (node$quorum_deadline == s$time) {
      if (!majority(s,1L+length(node$heard))) {
        write_trace(s,words("STEPDOWN",paste0("n",node$number),"term",node$term,"heard",node_set(node$heard)))
        end_leadership(s,node,"QUORUM")
        node$role <- "FOLLOWER"
        node$known_leader <- 0L
        set_election_timer(s,node)
        return(invisible(NULL))
      }
      node$heard <- integer()
      node$quorum_deadline <- s$time+s$settings$quorum
    }
    if (node$transfer_target != 0L && node$transfer_deadline == s$time) {
      write_trace(s,words("TRANSFER",paste0("n",node$number),paste0("n",node$transfer_target),"abort"))
      cancel_transfer(node)
    }
    if (node$heartbeat_deadline == s$time) {
      broadcast_append(s,node)
      node$heartbeat_deadline <- s$time+s$settings$heartbeat
    }
  } else if (node$election_deadline == s$time) start_election(s,node,"timeout")
  invisible(NULL)
}
end_of_tick <- function(s) {
  check_logs(s$checker,s$nodes)
  leaders <- Filter(function(node) node$up && node$role == "LEADER",s$nodes)
  for (node in leaders) node$stats["leader_ticks"] <- node$stats["leader_ticks"]+1L
  if (length(leaders)) {
    s$leader_ticks <- s$leader_ticks+1L
    s$multi_ticks <- s$multi_ticks+as.integer(length(leaders) >= 2L)
    if (s$gap_start != -1L) {
      s$gaps[[length(s$gaps)+1L]] <- c(s$gap_start,s$time-1L)
      s$gap_start <- -1L
    }
  } else if (s$gap_start == -1L) s$gap_start <- s$time
  if (s$time %% s$settings$sample == 0L) {
    fields <- vapply(
        s$nodes,
        function(node) paste0(if (node$up) substr(node$role,1L,1L) else "D",node$term),
        character(1)
    )
    s$timelines <- c(s$timelines,words("TIMELINE",s$time,paste(fields,collapse=" ")))
  }
}
copy_store <- function(store) list2env(as.list(store,all.names=TRUE),hash=TRUE,parent=emptyenv())
store_equal <- function(left,right) {
  keys <- sort(ls(left,all.names=TRUE),method="radix")
  other_keys <- sort(ls(right,all.names=TRUE),method="radix")
  identical(keys,other_keys) && all(vapply(keys,function(k) identical(left[[k]],right[[k]]),logical(1)))
}
lookup_count <- function(values,key) if (key %in% names(values)) unname(values[key]) else 0L
increment_count <- function(values,key) {
  values[key] <- lookup_count(values,key)+1L
  values
}
finish_statistics <- function(s) {
  s$maximum_term <- max(vapply(s$nodes,function(node) node$term,integer(1)))
  s$committed_count <- length(s$checker$committed)
  needed <- vapply(s$nodes,function(node) node$applied,integer(1))
  s$reference_states[["0"]] <- new_store()
  for (index in seq_len(s$committed_count)) {
    entry <- s$checker$applied[[index]]$entry
    apply_command(s$reference_state,entry$command)
    if (index %in% needed) s$reference_states[[as.character(index)]] <- copy_store(s$reference_state)
  }
  for (request in s$requests) {
    key <- request$command$key
    s$key_requests <- increment_count(s$key_requests,key)
    if (request$accepted_index != 0L) {
      index <- request$accepted_index
      term <- request$accepted_term
      committed <- if (index <= s$committed_count) s$checker$committed[[index]] else NULL
      if (!is.null(committed) && committed$term == term) {
        request$status <- "COMMITTED"
        request$latency <- committed$time-request$time
        request$result <- s$checker$applied[[index]]$result
        s$latencies <- c(s$latencies,request$latency)
        s$key_committed <- increment_count(s$key_committed,key)
      } else if (any(vapply(
          s$nodes,
          function(node) last_index(node) >= index && term_at(node,index) == term,
          logical(1)
      ))) request$status <- "UNCOMMITTED" else request$status <- "LOST"
    } else request$status <- if (request$abandoned) "FAILED" else "WAITING"
    count <- s$status_counts[[request$status]]
    s$status_counts[[request$status]] <- if (is.null(count)) 1L else count+1L
  }
}
run_simulation <- function(s) {
  for (node in s$nodes) {
    set_election_timer(s,node)
    write_trace(s,words("START",paste0("n",node$number),"deadline",node$election_deadline))
  }
  controls <- split(s$controls,vapply(s$controls,function(event) as.character(event$time),character(1)))
  for (time in seq.int(0L,s$settings$finish)) {
    s$time <- time
    for (event in controls[[as.character(time)]]) control_event(s,event)
    for (request in s$requests) if (request$scheduled == time) attempt_request(s,request)
    for (message in network_arrivals(s$network,time)) if (network_deliver(
        s$network,
        message,
        s$nodes[[message$destination]]$up
    )) receive_message(s,message)
    for (node in s$nodes) if (node$up) process_timers(s,node)
    end_of_tick(s)
  }
  if (s$gap_start != -1L) s$gaps[[length(s$gaps)+1L]] <- c(s$gap_start,s$settings$finish)
  finish_statistics(s)
}
leader_lines <- function(s) {
  lines <- character()
  for (r in s$elections) {
    outcome <- if (r$won == -1L) "LOST" else paste("WON",r$won)
    lines <- c(
        lines,
        words(
            "ELECTION",
            r$time,
            paste0("n",r$node),
            "term",
            r$term,
            "trigger",
            r$trigger,
            "votes",
            length(r$votes),
            outcome
        )
    )
  }
  for (term in seq_len(s$maximum_term)) {
    elections <- Filter(function(r) r$term == term,s$elections)
    candidates <- node_set(vapply(elections,function(r) r$node,integer(1)))
    r <- s$leaders[[as.character(term)]]
    if (is.null(r)) {
      lines <- c(lines,words("TERM",term,"NONE candidates",candidates))
      next
    }
    finish <- if (r$ended == -1L) "-" else as.character(r$ended)
    reason <- if (r$ended == -1L) "ACTIVE" else r$reason
    commit <- if (r$ended == -1L) s$nodes[[r$node]]$commit else r$commit
    start <- elections[[1L]]$time
    lines <- c(
        lines,
        words(
            "TERM",
            term,
            "LEADER",
            paste0("n",r$node),
            "elected",
            r$elected,
            "votes",
            node_set(r$votes),
            "ended",
            finish,
            reason,
            "appended",
            r$appended,
            "commit",
            commit,
            "candidates",
            candidates,
            "started",
            start,
            "wait",
            r$elected-start
        )
    )
  }
  for (n in s$nodes) lines <- c(
      lines,
      words(
          "NODE",
          paste0("n",n$number),
          "elections",
          n$stats["elections"],
          "leader_terms",
          n$stats["leader_terms"],
          "leader_ticks",
          n$stats["leader_ticks"],
          "votes_granted",
          n$stats["votes_granted"]
      )
  )
  lines <- c(lines,s$timelines)
  for (gap in s$gaps) lines <- c(
      lines,
      words("GAP",paste(gap[1L],gap[2L],sep="-"),"length",gap[2L]-gap[1L]+1L)
  )
  longest <- if (length(s$gaps)) max(vapply(s$gaps,function(g) g[2L]-g[1L]+1L,integer(1))) else 0L
  c(
      lines,
      words(
          "SUMMARY terms",
          s$maximum_term,
          "leaders",
          length(ls(s$leaders,all.names=TRUE)),
          "elections",
          length(s$elections),
          "leader_ticks",
          s$leader_ticks,
          "multi_ticks",
          s$multi_ticks,
          "ticks",
          s$settings$finish+1L,
          "gaps",
          length(s$gaps),
          "longest",
          longest
      )
  )
}
log_lines <- function(s) {
  lines <- character()
  for (node in s$nodes) {
    status <- if (node$up) node$role else "DOWN"
    voted <- if (node$voted_for == 0L) "-" else paste0("n",node$voted_for)
    lines <- c(
        lines,
        words(
            "NODE",
            paste0("n",node$number),
            status,
            "term",
            node$term,
            "voted",
            voted,
            "commit",
            node$commit,
            "applied",
            node$applied,
            "length",
            last_index(node)
        )
    )
    for (i in seq_along(node$log)) {
      e <- node$log[[i]]
      line <- words(i,e$term,command_text(e$command))
      if (e$request != 0L) line <- paste(line,paste0("r",e$request))
      lines <- c(lines,line)
    }
  }
  prefix <- 0L
  limit <- min(vapply(s$nodes,last_index,integer(1)))
  for (i in seq_len(limit)) {
    if (!all(vapply(
        s$nodes[-1L],
        function(node) identical(node$log[[i]],s$nodes[[1L]]$log[[i]]),
        logical(1)
    ))) break
    prefix <- prefix+1L
  }
  lines <- c(lines,words("AGREE prefix",prefix,"committed",s$committed_count))
  for (n in s$nodes) {
    common <- 0L
    for (i in seq_len(min(last_index(n),s$committed_count))) {
      if (term_at(n,i) != s$checker$committed[[i]]$term) break
      common <- i
    }
    lines <- c(
        lines,
        words(
            "DIFF",
            paste0("n",n$number),
            "common",
            common,
            "behind",
            s$committed_count-common,
            "extra",
            last_index(n)-common,
            "ae_ok",
            n$stats["ae_ok"],
            "ae_fail",
            n$stats["ae_fail"],
            "appended",
            n$stats["appended"],
            "truncated",
            n$stats["truncated"],
            "applies",
            n$stats["applies"]
        )
    )
  }
  lines
}
request_line <- function(request) {
  line <- words(
      "REQUEST",
      paste0("r",request$number),
      "at",
      request$time,
      paste0("n",request$initial_destination),
      command_text(request$command),
      "attempts",
      request$attempts,
      "redirects",
      request$redirects
  )
  if (request$accepted_index != 0L) {
    line <- words(line,request$status,"index",request$accepted_index,"term",request$accepted_term)
    if (request$status == "COMMITTED") line <- words(line,"latency",request$latency,"result",request$result)
  } else if (request$status == "FAILED") line <- paste(line,"FAILED") else line <- words(
      line,
      "WAITING next",
      request$scheduled
  )
  line
}
state_lines <- function(s) {
  lines <- character()
  for (n in s$nodes) {
    status <- if (n$up) "UP" else "DOWN"
    replay <- if (store_equal(n$store,s$reference_states[[as.character(n$applied)]])) "match" else "mismatch"
    keys <- sort(ls(n$store,all.names=TRUE),method="radix")
    lines <- c(
        lines,
        words("NODE",paste0("n",n$number),status,"applied",n$applied,"keys",length(keys),"replay",replay)
    )
    for (key in keys) lines <- c(lines,words(key,n$store[[key]]))
  }
  lines <- c(lines,vapply(s$requests,request_line,character(1)))
  for (key in sort(names(s$key_requests),method="radix")) {
    value <- s$reference_state[[key]]
    if (is.null(value)) value <- "missing"
    lines <- c(
        lines,
        words(
            "KEY",
            key,
            "requests",
            s$key_requests[key],
            "committed",
            lookup_count(s$key_committed,key),
            "final",
            value
        )
    )
  }
  status_count <- function(status) if (is.null(s$status_counts[[status]])) 0L else s$status_counts[[status]]
  statuses <- paste(
      vapply(
          c("COMMITTED","UNCOMMITTED","LOST","FAILED","WAITING"),
          function(name) words(tolower(name),status_count(name)),
          character(1)
      ),
      collapse=" "
  )
  lines <- c(lines,words("REQUESTS total",length(s$requests),statuses))
  c(
      lines,
      words(
          "LATENCY count",
          length(s$latencies),
          "total",
          sum(s$latencies),
          "min",
          if (length(s$latencies)) min(s$latencies) else 0L,
          "max",
          if (length(s$latencies)) max(s$latencies) else 0L
      )
  )
}
safety_lines <- function(s) {
  lines <- checker_lines(s$checker,s$maximum_term)
  statistics <- function(entries) paste(
      vapply(MESSAGE_FIELDS,function(field) words(field,entries[field]),character(1)),
      collapse=" "
  )
  lines <- c(lines,paste("MESSAGES",statistics(s$network$total)))
  for (kind in MESSAGE_TYPES) lines <- c(lines,words("TYPE",kind,statistics(s$network$by_type[[kind]])))
  for (a in seq_len(s$settings$nodes)) for (b in seq_len(s$settings$nodes)) {
    if (a == b) next
    link <- network_link(s$network,a,b)
    lines <- c(
        lines,
        words(
            "LINK",
            paste0("n",a,"->n",b),
            "delay",
            link$delay,
            "loss",
            link$loss,
            "sent",
            link$stats["sent"],
            "delivered",
            link$stats["delivered"],
            "dropped",
            sum(link$stats[MESSAGE_REASONS])
        )
    )
  }
  c(
      lines,
      paste("DRAWS",s$random$draws),
      if (any(s$checker$violations != 0L)) "RESULT UNSAFE" else "RESULT SAFE"
  )
}
main <- function() {
  settings <- read_settings()
  script <- read_script()
  s <- new_simulation(settings,script,read_network(settings$nodes))
  run_simulation(s)
  outputs <- list(
      "trace.txt"=s$trace,
      "leaders.txt"=leader_lines(s),
      "logs.txt"=log_lines(s),
      "state.txt"=state_lines(s),
      "safety.txt"=safety_lines(s)
  )
  dir.create("output",showWarnings=FALSE)
  for (name in names(outputs)) writeLines(outputs[[name]],paste0("output/",name),useBytes=TRUE)
}
main()
