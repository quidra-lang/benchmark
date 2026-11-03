for (module in c("network","clocks","processes","snapshot","analysis")) source(paste0(module,".R"))
load_params <- function() {
  params <- list(compare=list(),cuts=list(),predicates=integer())
  for (line in readLines(file.path("input","params.txt"))) {
    words <- strsplit(line," ",fixed=TRUE)[[1L]]
    key <- words[1L]
    if (key %in% c(
        "SEED",
        "END",
        "CUTCOUNT"
    )) params[[tolower(key)]] <- as.integer(words[2L]) else if (key == "COMPARE")
      params$compare[[length(params$compare)+1L]] <- words[-1L] else if (key == "CUT") params$cuts[[length(params$cuts)+1L]] <- as.integer(words[-1L]) else
      params$predicates <- c(params$predicates,as.integer(words[2L]))
  }
  params
}
queue_less <- function(
    a,
    b
) a$time < b$time || (a$time == b$time && (a$process < b$process || (a$process == b$process && a$creation < b$creation)))
enqueue <- function(sim,time,process,kind,payload) {
  sim$creation <- sim$creation+1L
  item <- list(time=time,process=process,creation=sim$creation,kind=kind,payload=payload)
  index <- length(sim$queue)+1L
  sim$queue[[index]] <- item
  while (index > 1L) {
    parent <- index %/% 2L
    if (!queue_less(item,sim$queue[[parent]])) break
    sim$queue[[index]] <- sim$queue[[parent]]
    index <- parent
  }
  sim$queue[[index]] <- item
}
dequeue <- function(sim) {
  first <- sim$queue[[1L]]
  n <- length(sim$queue)
  last <- sim$queue[[n]]
  sim$queue <- head(sim$queue,-1L)
  if (length(sim$queue)) {
    index <- 1L
    while (2L*index <= length(sim$queue)) {
      child <- 2L*index
      if (child < length(sim$queue) && queue_less(sim$queue[[child+1L]],sim$queue[[child]])) child <- child+1L
      if (!queue_less(sim$queue[[child]],last)) break
      sim$queue[[index]] <- sim$queue[[child]]
      index <- child
    }
    sim$queue[[index]] <- last
  }
  first
}
make_simulation <- function(topology,scripts,params,raw=FALSE) {
  sim <- new.env(parent=emptyenv())
  sim$names <- topology$names
  sim$params <- params
  sim$raw <- raw
  sim$processes <- initialize_processes(sim$names,scripts)
  sim$channels <- copy_channels(topology$channels)
  sim$channel_order <- topology$order
  sim$random <- minstd(params$seed)
  sim$queue <- sim$messages <- sim$packets <- sim$events <- sim$snapshots <- sim$timeline <- list()
  sim$copies <- integer()
  sim$creation <- sim$current_time <- 0L
  sim$snapshot_by_name <- list()
  schedule_actions(sim$processes,params$end,function(time,p,action) enqueue(sim,time,p,"action",action))
  sim
}
record_event <- function(sim,p,kind,details,sender=0L) {
  process <- sim$processes[[p]]
  if (kind == "RECV") receive_event(process,p,sim$events[[sender]]) else nonreceive_event(process,p)
  event <- list(number=length(sim$events)+1L,local_number=length(process$events)+1L,process=p,kind=kind,details=details,time=sim$current_time,
    lamport=process$lamport,vector=process$vector,balance=process$balance)
  process$events <- c(process$events,event$number)
  process$types[kind] <- process$types[kind]+1L
  process$min_balance <- min(process$min_balance,process$balance)
  sim$events[[event$number]] <- event
  sim$timeline[[length(sim$timeline)+1L]] <- list(kind="event",index=event$number)
  event$number
}
dispatch_packet <- function(sim,source,destination,packet) {
  index <- length(sim$packets)+1L
  sim$packets[[index]] <- packet
  vector <- if (packet$packet_type == "copy") sim$events[[sim$messages[[packet$message]]$send_event]]$vector else integer()
  dispatch(
      sim$channels[[channel_key(source,destination)]],
      packet,
      sim$current_time,
      sim$random,
      vector,
      function(time,p) enqueue(sim,time,p,"arrival",index)
  )
  index
}
send_message <- function(sim,p,action,sender) {
  process <- sim$processes[[p]]
  kind <- action$kind
  destination <- if (action$destination == 0L) sender else action$destination
  amount <- 0L
  tag <- action$text
  event_type <- "SEND"
  message_kind <- "P2P"
  if (kind == "TRANSFER") {
    amount <- action$amount
    if (amount > process$balance) {
      process$refused <- process$refused+1L
      record_event(sim,p,"NOFUNDS",list(destination=destination,amount=amount,balance=process$balance))
      return(invisible(NULL))
    }
    process$balance <- process$balance-amount
    process$outgoing <- process$outgoing+amount
    tag <- "transfer"
  } else if (kind == "BROADCAST") {
    event_type <- message_kind <- "BCAST"
    process$broadcast[p] <- process$broadcast[p]+1L
  }
  id <- length(sim$messages)+1L
  message <- new_message(
      id,
      message_kind,
      p,
      tag,
      amount,
      if (message_kind == "BCAST") process$broadcast else integer()
  )
  sim$messages[[id]] <- message
  message$send_event <- record_event(sim,p,event_type,list(message=id,destination=destination))
  message$send_time <- sim$current_time
  destinations <- if (message_kind == "BCAST") setdiff(seq_along(sim$names),p) else destination
  for (q in destinations) {
    index <- dispatch_packet(sim,p,q,new_packet("copy",message=id))
    message$copies <- c(message$copies,index)
    sim$copies <- c(sim$copies,index)
  }
}
process_action <- function(sim,p,action,sender=0L) {
  if (action$kind == "LOCAL") record_event(
      sim,
      p,
      "LOCAL",
      list(label=action$text)
  ) else if (action$kind == "SNAPSHOT")
    initiate_snapshot(sim,p,action$text) else send_message(sim,p,action,sender)
}
start_snapshot <- function(sim,name) {
  index <- sim$snapshot_by_name[[name]]
  if (is.null(index)) {
    index <- length(sim$snapshots)+1L
    sim$snapshots[[index]] <- new_snapshot(name,sim$current_time,length(sim$names))
    sim$snapshot_by_name[[name]] <- index
  }
  index
}
record_snapshot <- function(sim,index,p,reason) {
  snapshot <- sim$snapshots[[index]]
  record_state(snapshot,sim$processes[[p]],p,sim$current_time,reason)
  sim$timeline[[length(sim$timeline)+1L]] <- list(kind="snapshot",index=index,process=p,time=sim$current_time)
  for (q in seq_along(sim$names)) {
    if (p == q) next
    dispatch_packet(sim,p,q,new_packet("marker",snapshot=index))
    snapshot$markers[[channel_key(p,q)]] <- list(sent=sim$current_time,accepted=0L)
  }
}
initiate_snapshot <- function(sim,p,name) {
  index <- start_snapshot(sim,name)
  snapshot <- sim$snapshots[[index]]
  if (!is.null(snapshot$records[[p]])) snapshot$ignored[[length(snapshot$ignored)+1L]] <- c(p,sim$current_time) else record_snapshot(
      sim,
      index,
      p,
      "initiate"
  )
}
accept_marker <- function(sim,p,packet) {
  snapshot <- sim$snapshots[[packet$snapshot]]
  if (is.null(snapshot$records[[p]])) record_snapshot(
      sim,
      packet$snapshot,
      p,
      paste("marker",sim$names[packet$source])
  )
  accepted_marker(snapshot,packet$source,p,sim$current_time,length(sim$names))
}
deliver <- function(sim,p,index) {
  packet <- sim$packets[[index]]
  process <- sim$processes[[p]]
  message <- sim$messages[[packet$message]]
  if (message$kind == "BCAST") process$broadcast[packet$source] <- process$broadcast[packet$source]+1L
  process$balance <- process$balance+message$amount
  process$incoming <- process$incoming+message$amount
  packet$recv_event <- record_event(sim,p,"RECV",list(copy=index),message$send_event)
  packet$delivery_time <- sim$current_time
  process$delivered <- c(process$delivered,index)
  for (action in reaction_actions(process,message$tag)) process_action(sim,p,action,packet$source)
}
can_deliver <- function(sim,p,index) {
  packet <- sim$packets[[index]]
  broadcast_deliverable(sim$messages[[packet$message]]$stamp,sim$processes[[p]]$broadcast,packet$source)
}
release_causal_waits <- function(sim,p) {
  process <- sim$processes[[p]]
  repeat {
    positions <- which(vapply(process$holdback,function(index) can_deliver(sim,p,index),logical(1)))
    if (!length(positions)) break
    position <- positions[1L]
    index <- process$holdback[position]
    process$holdback <- process$holdback[-position]
    deliver(sim,p,index)
  }
}
accept_packet <- function(sim,p,index) {
  packet <- sim$packets[[index]]
  process <- sim$processes[[p]]
  source <- packet$source
  process$next_sequence[source] <- process$next_sequence[source]+1L
  if (packet$packet_type == "marker") {
    accept_marker(sim,p,packet)
    return(invisible(NULL))
  }
  key <- channel_key(source,p)
  for (snapshot in sim$snapshots) if (!is.null(snapshot$records[[p]]) && !key %in% snapshot$accepted) snapshot$channel_states[[key]] <- c(
      snapshot$channel_states[[key]],
      index
  )
  message <- sim$messages[[packet$message]]
  if (message$kind == "P2P" || sim$raw) deliver(sim,p,index) else if (can_deliver(sim,p,index)) {
    deliver(sim,p,index)
    release_causal_waits(sim,p)
  } else {
    packet$causal_wait <- TRUE
    packet$missing <- missing_indices(message$stamp,process$broadcast,source)
    process$holdback <- c(process$holdback,index)
  }
}
receive_packet <- function(sim,p,index) {
  packet <- sim$packets[[index]]
  process <- sim$processes[[p]]
  source <- packet$source
  if (sim$raw) accept_packet(sim,p,index) else if (packet$sequence != process$next_sequence[source]) {
    packet$fifo_wait <- TRUE
    process$reorder[[source]][[as.character(packet$sequence)]] <- index
    channel <- sim$channels[[channel_key(source,p)]]
    channel$buffered <- channel$buffered+1L
  } else {
    accept_packet(sim,p,index)
    repeat {
      key <- as.character(process$next_sequence[source])
      following <- process$reorder[[source]][[key]]
      if (is.null(following)) break
      process$reorder[[source]][[key]] <- NULL
      accept_packet(sim,p,following)
    }
  }
  process$max_held <- max(process$max_held,held_count(process))
}
run_simulation <- function(sim) {
  while (length(sim$queue) && sim$queue[[1L]]$time <= sim$params$end) {
    item <- dequeue(sim)
    sim$current_time <- item$time
    if (item$kind == "action") process_action(sim,item$process,item$payload) else receive_packet(
        sim,
        item$process,
        item$payload
    )
  }
  sim
}
yes <- function(value) if (value) "yes" else "no"
msg_name <- function(id) paste0("m",id)
event_name <- function(sim,event) paste0(sim$names[event$process],".",event$local_number)
initial_total <- function(sim) sum(vapply(sim$processes,function(process) process$initial,integer(1)))
simulation_cut <- function(sim,cut) cut_details(
    cut,
    sim$processes,
    sim$packets,
    sim$copies,
    sim$messages,
    sim$events
)
simulation_copy_label <- function(sim,index) copy_label(sim$packets[[index]],sim$messages,sim$names)
trace_lines <- function(sim) {
  lines <- character()
  for (event in sim$events) {
    kind <- event$kind
    detail <- event$details
    if (kind == "LOCAL") info <- detail$label else if (kind == "NOFUNDS") info <- paste(
        "to",
        sim$names[detail$destination],
        "amount",
        detail$amount,
        "balance",
        detail$balance
    ) else if (kind %in% c("SEND","BCAST")) {
      message <- sim$messages[[detail$message]]
      info <- if (kind == "BCAST") paste(msg_name(message$id),"tag",message$tag) else paste(
          msg_name(message$id),
          "to",
          sim$names[detail$destination],
          "tag",
          message$tag
      )
      if (message$amount > 0L) info <- paste(info,"amount",message$amount,"balance",event$balance)
    } else {
      packet <- sim$packets[[detail$copy]]
      message <- sim$messages[[packet$message]]
      info <- paste(msg_name(message$id),"from",sim$names[packet$source],"tag",message$tag)
      if (message$amount > 0L) info <- paste(info,"amount",message$amount,"balance",event$balance)
    }
    lines <- c(
        lines,
        paste(
            event$number,
            paste0("t=",event$time),
            event_name(sim,event),
            kind,
            info,
            paste0("L=",event$lamport),
            paste0("V=",vector_text(event$vector))
        )
    )
  }
  delivered <- sum(vapply(sim$copies,function(i) sim$packets[[i]]$recv_event != 0L,logical(1)))
  lines <- c(
      lines,
      paste(
          "SUMMARY events",
          length(sim$events),
          "messages",
          length(sim$messages),
          "copies",
          length(sim$copies),
          "delivered",
          delivered,
          "undelivered",
          length(sim$copies)-delivered,
          "draws",
          sim$random$draws
      )
  )
  for (p in seq_along(sim$processes)) {
    process <- sim$processes[[p]]
    lines <- c(lines,paste("FINAL",sim$names[p],"events",length(process$events),paste0("L=",process$lamport),paste0("V=",vector_text(process$vector)),
      paste0(
          "B=",
          vector_text(process$broadcast)
      ),"balance",process$balance,"in",process$incoming,"out",process$outgoing,"refused",process$refused,"min",process$min_balance))
  }
  for (p in seq_along(sim$processes)) {
    counts <- sim$processes[[p]]$types
    kinds <- c("LOCAL","NOFUNDS","SEND","BCAST","RECV")
    lines <- c(lines,paste("COUNTS",sim$names[p],paste(paste(tolower(kinds),counts[kinds]),collapse=" ")))
  }
  lines
}
wait_mode <- function(sim,packet) {
  if (!packet$causal_wait) return(if (packet$fifo_wait) "fifo" else "direct")
  missing <- paste(sim$names[packet$missing],collapse=",")
  paste(if (packet$fifo_wait) "fifo+causal" else "causal",missing)
}
broadcast_history <- function(sim,p) {
  history <- integer()
  for (index in sim$processes[[p]]$events) {
    event <- sim$events[[index]]
    if (event$kind == "BCAST") history <- c(history,event$details$message) else if (event$kind == "RECV") {
      message <- sim$messages[[sim$packets[[event$details$copy]]$message]]
      if (message$kind == "BCAST") history <- c(history,message$id)
    }
  }
  history
}
deliveries_lines <- function(sim) {
  lines <- character()
  for (p in seq_along(sim$processes)) {
    process <- sim$processes[[p]]
    lines <- c(lines,paste("PROCESS",sim$names[p]))
    modes <- integer(4L)
    total_wait <- max_wait <- 0L
    for (number in seq_along(process$delivered)) {
      packet <- sim$packets[[process$delivered[number]]]
      message <- sim$messages[[packet$message]]
      wait <- packet$delivery_time-packet$arrival_time
      total_wait <- total_wait+wait
      max_wait <- max(max_wait,wait)
      mode <- if (packet$fifo_wait) { if (packet$causal_wait) 4L else 2L } else if (packet$causal_wait) 3L else 1L
      modes[mode] <- modes[mode]+1L
      lines <- c(lines,paste(number,msg_name(message$id),"from",sim$names[packet$source],message$kind,"tag",message$tag,"sent",message$send_time,
        "arrived",packet$arrival_time,"delivered",packet$delivery_time,"wait",wait,wait_mode(sim,packet)))
    }
    for (index in sim$copies) {
      packet <- sim$packets[[index]]
      if (packet$destination != p || packet$arrival_time > sim$params$end || packet$recv_event != 0L) next
      message <- sim$messages[[packet$message]]
      place <- if (!is.null(process$reorder[[packet$source]][[as.character(packet$sequence)]])) "fifo" else paste(
          "causal",
          paste(sim$names[packet$missing],collapse=",")
      )
      lines <- c(
          lines,
          paste(
              "HELD",
              msg_name(message$id),
              "from",
              sim$names[packet$source],
              message$kind,
              "tag",
              message$tag,
              "sent",
              message$send_time,
              "arrived",
              packet$arrival_time,
              place
          )
      )
    }
    for (index in sim$copies) {
      packet <- sim$packets[[index]]
      if (packet$destination != p || packet$arrival_time <= sim$params$end) next
      message <- sim$messages[[packet$message]]
      lines <- c(
          lines,
          paste(
              "TRANSIT",
              msg_name(message$id),
              "from",
              sim$names[packet$source],
              message$kind,
              "tag",
              message$tag,
              "sent",
              message$send_time,
              "arrival",
              packet$arrival_time
          )
      )
    }
    lines <- c(
        lines,
        paste(
            "TOTAL delivered",
            length(process$delivered),
            "direct",
            modes[1L],
            "fifo",
            modes[2L],
            "causal",
            modes[3L],
            "both",
            modes[4L],
            "wait",
            total_wait,
            "max_wait",
            max_wait,
            "max_held",
            process$max_held
        )
    )
    history <- broadcast_history(sim,p)
    lines <- c(lines,paste("BCASTS",if (length(history)) paste(msg_name(history),collapse=" ") else "none"))
  }
  for (pair in sim$channel_order) {
    channel <- sim$channels[[channel_key(pair[1L],pair[2L])]]
    lines <- c(lines,paste("CHANNEL",paste0(sim$names[pair[1L]],"->",sim$names[pair[2L]]),channel$kind,delay_notation(channel),"messages",channel$messages,
      "markers",channel$markers,"buffered",channel$buffered,"max_delay",channel$max_delay,"entries",channel$entries))
  }
  tags <- sort(
      unique(vapply(sim$copies,function(i) sim$messages[[sim$packets[[i]]$message]]$tag,character(1))),
      method="radix"
  )
  for (tag in tags) {
    tagged <- Filter(function(i) sim$messages[[sim$packets[[i]]$message]]$tag == tag,sim$copies)
    completed <- Filter(function(i) sim$packets[[i]]$recv_event != 0L,tagged)
    latencies <- vapply(
        completed,
        function(i) sim$packets[[i]]$delivery_time-sim$messages[[sim$packets[[i]]$message]]$send_time,
        integer(1)
    )
    lines <- c(
        lines,
        paste(
            "TAG",
            tag,
            "copies",
            length(tagged),
            "delivered",
            length(completed),
            "latency",
            sum(latencies),
            "max",
            if (length(latencies)) max(latencies) else 0L
        )
    )
  }
  broadcasts <- Filter(function(message) message$kind == "BCAST",sim$messages)
  for (message in broadcasts) {
    completed <- Filter(function(i) sim$packets[[i]]$recv_event != 0L,message$copies)
    times <- vapply(completed,function(i) sim$packets[[i]]$delivery_time,integer(1))
    stable <- if (length(completed) == length(message$copies)) as.character(max(times)) else "none"
    lines <- c(
        lines,
        paste(
            "STABLE",
            msg_name(message$id),
            sim$names[message$source],
            "tag",
            message$tag,
            "sent",
            message$send_time,
            "stable",
            stable
        )
    )
  }
  disagreements <- 0L
  if (length(broadcasts) > 1L) for (a in seq_len(length(broadcasts)-1L)) for (b in seq.int(
      a+1L,
      length(broadcasts)
  )) {
    first <- broadcasts[[a]]$id
    second <- broadcasts[[b]]$id
    earlier <- later <- integer()
    for (p in seq_along(sim$names)) {
      history <- broadcast_history(sim,p)
      i <- match(first,history)
      j <- match(second,history)
      if (!is.na(i) && !is.na(j)) {
        if (i < j) earlier <- c(earlier,p) else later <- c(later,p)
      }
    }
    if (length(earlier) && length(later)) {
      disagreements <- disagreements+1L
      lines <- c(
          lines,
          paste(
              "DISAGREE",
              msg_name(first),
              msg_name(second),
              paste(sim$names[earlier],collapse=","),
              paste(sim$names[later],collapse=",")
          )
      )
    }
  }
  c(lines,paste("DISAGREEMENTS",disagreements))
}
consistent_verdict <- function(sim,details) if (details$consistent) "yes" else paste(
    "no",
    paste(vapply(details$orphans,function(i) simulation_copy_label(sim,i),character(1)),collapse=" ")
)
snapshots_lines <- function(normal,raw) {
  lines <- character()
  for (sim in list(normal,raw)) for (snapshot in sim$snapshots) {
    cut <- snapshot_cut(snapshot)
    details <- simulation_cut(sim,cut)
    recorded <- recorded_copies(snapshot,sim$channel_order)
    entries <- recorded$entries
    pending <- recorded$pending
    channel_money <- sum(vapply(
        entries,
        function(i) sim$messages[[sim$packets[[i]]$message]]$amount,
        integer(1)
    ))
    balances <- sum(vapply(snapshot$records,function(record) record$balance,integer(1)))
    money <- balances+channel_money
    initial <- initial_total(sim)
    if (sim$raw) {
      lines <- c(
          lines,
          paste(
              "RAW",
              snapshot$name,
              "completed",
              snapshot$complete,
              "cut",
              vector_text(cut),
              "consistent",
              consistent_verdict(sim,details),
              "money",
              money,
              "conserved",
              yes(money == initial)
          )
      )
      next
    }
    lines <- c(lines,paste("SNAPSHOT",snapshot$name,"started",snapshot$start,"completed",snapshot$complete))
    for (p in seq_along(snapshot$records)) {
      record <- snapshot$records[[p]]
      pending_text <- if (!length(record$pending)) "none" else paste(
          vapply(record$pending,function(i) msg_name(sim$packets[[i]]$message),character(1)),
          collapse=" "
      )
      lines <- c(
          lines,
          paste(
              "RECORD",
              sim$names[p],
              paste0("t=",record$time),
              record$reason,
              "balance",
              record$balance,
              paste0("L=",record$lamport),
              paste0("V=",vector_text(record$vector)),
              "pending",
              pending_text
          )
      )
    }
    for (pair in sim$channel_order) {
      key <- channel_key(pair[1L],pair[2L])
      state <- snapshot$channel_states[[key]]
      marker <- snapshot$markers[[key]]
      values <- vapply(state,function(i) {
        message <- sim$messages[[sim$packets[[i]]$message]]
        paste0(msg_name(message$id),if (message$amount == 0L) "" else paste0(":",message$amount))
      },character(1))
      text <- if (length(values)) paste(values,collapse=" ") else "empty"
      lines <- c(
          lines,
          paste(
              "CHANNEL",
              paste0(sim$names[pair[1L]],"->",sim$names[pair[2L]]),
              "marker",
              marker$sent,
              marker$accepted,
              "state",
              text
          )
      )
    }
    for (ignored in snapshot$ignored) lines <- c(
        lines,
        paste("IGNORED",sim$names[ignored[1L]],paste0("t=",ignored[2L]))
    )
    lines <- c(lines,paste("CUT",vector_text(cut),"consistent",consistent_verdict(sim,details),"vector",yes(vector_consistent(snapshot,cut))),
      paste(
          "TRANSIT channels",
          length(entries),
          "pending",
          length(pending),
          "cut",
          length(details$transit),
          "match",
          yes(transit_match(entries,pending,details$transit))
      ),
      paste(
          "MONEY balances",
          balances,
          "channels",
          channel_money,
          "total",
          money,
          "initial",
          initial,
          "conserved",
          yes(money == initial)
      ))
  }
  lines
}
range_notation <- function(sim,path) {
  if (!length(path)) return("-")
  parts <- character()
  first <- last <- sim$events[[path[1L]]]
  append_part <- function(a,b) {
    text <- if (a$number == b$number) event_name(sim,a) else paste0(
        sim$names[a$process],
        ".",
        a$local_number,
        "-",
        b$local_number
    )
    parts <<- c(parts,text)
  }
  if (length(path) > 1L) for (index in path[-1L]) {
    event <- sim$events[[index]]
    if (event$process == last$process && event$local_number == last$local_number+1L) last <- event else {
      append_part(first,last)
      first <- last <- event
    }
  }
  append_part(first,last)
  paste(parts,collapse=" ")
}
causal_longest_chain <- function(sim) {
  current <- sim$events[[which.max(vapply(sim$events,function(event) event$lamport,integer(1)))]]
  chain <- current$number
  while (current$lamport > 1L) {
    previous <- 0L
    if (current$kind == "RECV") {
      candidate <- sim$messages[[sim$packets[[current$details$copy]]$message]]$send_event
      if (sim$events[[candidate]]$lamport == current$lamport-1L) previous <- candidate
    }
    if (previous == 0L) previous <- sim$processes[[current$process]]$events[current$local_number-1L]
    chain <- c(chain,previous)
    current <- sim$events[[previous]]
  }
  rev(chain)
}
fifo_count <- function(items,model) sum(vapply(
    items,
    function(item) model$packets[[item$a]]$source == model$packets[[item$b]]$source,
    logical(1)
))
analysis_lines <- function(sim,raw) {
  lines <- character()
  edges <- graph_edges(sim$events,sim$processes,sim$packets,sim$copies,sim$messages)
  names <- vapply(sim$events,function(event) event_name(sim,event),character(1))
  for (pair in sim$params$compare) {
    first <- sim$events[[match(pair[1L],names)]]
    second <- sim$events[[match(pair[2L],names)]]
    vector_relation <- relation(first$vector,second$vector)
    forward <- graph_path(first$number,second$number,edges)
    reverse <- if (is.null(forward)) graph_path(second$number,first$number,edges) else NULL
    graph_relation <- if (!is.null(forward)) "->" else if (!is.null(reverse)) "<-" else "||"
    lines <- c(
        lines,
        paste(
            "COMPARE",
            pair[1L],
            vector_relation,
            pair[2L],
            paste0("L=",first$lamport,",",second$lamport),
            "graph",
            graph_relation,
            "agree",
            yes(vector_relation == graph_relation)
        )
    )
    path <- if (is.null(forward)) reverse else forward
    if (!is.null(path)) {
      processes <- vapply(path,function(index) sim$events[[index]]$process,integer(1))
      messages <- sum(head(processes,-1L) != tail(processes,-1L))
      lines <- c(lines,paste("PATH length",length(path),"messages",messages,range_notation(sim,path)))
    }
    for (event in list(first,second)) {
      future <- vapply(
          sim$processes,
          function(process) sum(vapply(
              process$events,
              function(i) sim$events[[i]]$vector[event$process] < event$local_number,
              logical(1)
          )),
          integer(1)
      )
      lines <- c(
          lines,
          paste("WINDOW",event_name(sim,event),"past",vector_text(event$vector),"future",vector_text(future))
      )
    }
  }
  summary <- concurrency_statistics(sim$events,length(sim$names))
  lines <- c(
      lines,
      paste(
          "CONCURRENCY events",
          length(sim$events),
          "pairs",
          summary$pairs,
          "ordered",
          summary$ordered,
          "concurrent",
          summary$concurrent,
          "same_lamport",
          summary$same_lamport,
          "inversions",
          summary$inversions
      )
  )
  for (p in seq_len(length(sim$names)-1L)) for (q in seq.int(p+1L,length(sim$names))) lines <- c(
      lines,
      paste("PAIR",sim$names[p],sim$names[q],summary$by_pair[p,q])
  )
  chain <- causal_longest_chain(sim)
  lines <- c(lines,paste("CHAIN length",length(chain),range_notation(sim,chain)))
  found <- races_and_violations(sim$processes,sim$packets,sim$messages,sim$events)
  for (item in found$races) {
    a <- sim$packets[[item$a]]
    b <- sim$packets[[item$b]]
    lines <- c(
        lines,
        paste(
            "RACE",
            sim$names[item$process],
            msg_name(a$message),
            sim$names[a$source],
            msg_name(b$message),
            sim$names[b$source]
        )
    )
  }
  lines <- c(lines,paste("RACES",length(found$races)))
  for (item in found$violations) {
    a <- sim$packets[[item$a]]
    b <- sim$packets[[item$b]]
    lines <- c(
        lines,
        paste(
            "VIOLATION",
            sim$names[item$process],
            msg_name(a$message),
            sim$names[a$source],
            "overtook",
            msg_name(b$message),
            sim$names[b$source]
        )
    )
  }
  lines <- c(
      lines,
      paste("VIOLATIONS causal",length(found$violations),"fifo",fifo_count(found$violations,sim))
  )
  raw_found <- races_and_violations(raw$processes,raw$packets,raw$messages,raw$events)
  raw_delivered <- sum(vapply(raw$copies,function(i) raw$packets[[i]]$recv_event != 0L,logical(1)))
  lines <- c(
      lines,
      paste(
          "RAW events",
          length(raw$events),
          "delivered",
          raw_delivered,
          "causal",
          length(raw_found$violations),
          "fifo",
          fifo_count(raw_found$violations,raw)
      )
  )
  for (cut in sim$params$cuts) {
    details <- simulation_cut(sim,cut)
    verdict <- if (details$consistent) "consistent" else paste(
        "inconsistent orphans",
        paste(vapply(details$orphans,function(i) simulation_copy_label(sim,i),character(1)),collapse=" ")
    )
    lines <- c(
        lines,
        paste(
            "CUT",
            vector_text(cut),
            verdict,
            "transit",
            length(details$transit),
            "money",
            details$money,
            "initial",
            initial_total(sim)
        )
    )
  }
  enumeration <- enumerate_cuts(sim$processes,sim$events,sim$params$cutcount,sim$params$predicates)
  lines <- c(lines,paste(paste0("CUTCOUNT t=",sim$params$cutcount),"events",vector_text(enumeration$limits),"product",enumeration$product,"consistent",enumeration$consistent),
    paste("LEVELS",paste(enumeration$levels,collapse=" ")))
  for (i in seq_along(sim$params$predicates)) {
    threshold <- sim$params$predicates[i]
    record <- enumeration$predicates[[i]]
    lines <- c(
        lines,
        paste(
            paste0("PREDICATE transit>=",threshold),
            "cuts",
            record$cuts,
            "possibly",
            yes(record$possibly),
            "definitely",
            yes(record$definitely)
        )
    )
  }
  lines
}
write_at <- function(line,position,text) {
  characters <- strsplit(text,"",fixed=TRUE)[[1L]]
  required <- position+length(characters)
  if (required > length(line)) line <- c(line,rep(" ",required-length(line)))
  if (length(characters)) line[position+seq_along(characters)] <- characters
  line
}
diagram_header <- function(letter,names) {
  line <- rep(" ",8L*length(names)-1L)
  line <- write_at(line,0L,paste0("    ",letter," "))
  for (p in seq_along(names)) line <- write_at(line,8L*p-2L,names[p])
  sub(" +$","",paste(line,collapse=""))
}
diagram_entry <- function(sim,value,p,kind,detail) {
  columns <- 8L*seq_along(sim$names)-2L
  line <- rep(" ",tail(columns,1L)+1L)
  line <- write_at(line,0L,paste0(sprintf("%5d",value)," "))
  line[columns+1L] <- "|"
  own <- columns[p]
  symbols <- c(LOCAL="*",NOFUNDS="x",SEND="S",BCAST="B",RECV="R",snapshot="#")
  line[own+1L] <- symbols[kind]
  if (kind == "snapshot") line <- write_at(
      line,
      own+1L,
      sim$snapshots[[detail$snapshot]]$name
  ) else if (kind %in% c("SEND","BCAST"))
    line <- write_at(line,own+1L,msg_name(detail$message)) else if (kind == "RECV") {
    packet <- sim$packets[[detail$copy]]
    other <- columns[packet$source]
    low <- min(own,other)
    high <- max(own,other)
    positions <- seq.int(low+1L,high-1L)
    line[positions+1L] <- ifelse(positions %in% columns,"+","-")
    line[(if (other < own) high-1L else low+1L)+1L] <- if (other < own) ">" else "<"
    line <- write_at(line,low+2L,msg_name(packet$message))
    line[own+1L] <- "R"
  }
  sub(" +$","",paste(line,collapse=""))
}
diagram_lines <- function(sim) {
  lines <- diagram_header("t",sim$names)
  for (item in sim$timeline) {
    if (item$kind == "snapshot") lines <- c(
        lines,
        diagram_entry(sim,item$time,item$process,"snapshot",list(snapshot=item$index))
    ) else {
      event <- sim$events[[item$index]]
      lines <- c(lines,diagram_entry(sim,event$time,event$process,event$kind,event$details))
    }
  }
  lines <- c(lines,diagram_header("L",sim$names))
  ordered <- order(
      vapply(sim$events,function(event) event$lamport,integer(1)),
      vapply(sim$events,function(event) event$process,integer(1))
  )
  for (index in ordered) {
    event <- sim$events[[index]]
    lines <- c(lines,diagram_entry(sim,event$lamport,event$process,event$kind,event$details))
  }
  lines
}
save_output <- function(name,lines) {
  dir.create("output",showWarnings=FALSE)
  writeLines(lines,file.path("output",name),useBytes=TRUE)
}
main <- function() {
  topology <- read_topology()
  scripts <- read_scripts(topology$names)
  params <- load_params()
  normal <- run_simulation(make_simulation(topology,scripts,params))
  raw <- run_simulation(make_simulation(topology,scripts,params,TRUE))
  save_output("trace.txt",trace_lines(normal))
  save_output("deliveries.txt",deliveries_lines(normal))
  save_output("snapshots.txt",snapshots_lines(normal,raw))
  save_output("analysis.txt",analysis_lines(normal,raw))
  save_output("diagram.txt",diagram_lines(normal))
}
main()
