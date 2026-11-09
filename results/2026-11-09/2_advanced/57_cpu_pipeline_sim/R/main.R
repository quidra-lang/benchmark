for (module in c("trace_io","hazards","pipeline","predictors","report")) source(paste0(module,".R"))
CLASSES <- c("ALU","MUL","LOAD","STORE","BRANCH","JUMP","NOP")
CONTROLS <- c("BRANCH","JUMP")
OPERANDS <- list(
    ALU=c(1L,1L,2L),
    MUL=c(1L,1L,1L),
    LOAD=c(1L,1L,0L),
    STORE=c(0L,1L,1L),
    BRANCH=c(0L,1L,2L),
    JUMP=c(2L,2L,0L),
    NOP=c(0L,0L,0L)
)
MISS_KINDS <- c("direction","btb_miss","wrong_target")
check_record <- function(line,static) {
  tokens <- strsplit(paste0(line,"@")," ",fixed=TRUE)[[1L]]
  tokens[length(tokens)] <- substring(tokens[length(tokens)],1L,nchar(tokens[length(tokens)])-1L)
  invalid <- function(reason) list(instruction=NULL,error=reason)
  if (length(tokens) != 8L || any(!nzchar(tokens))) return(invalid("fields"))
  pc <- parse_hex(tokens[1L])
  kind <- tokens[2L]
  if (is.na(pc) || pc %% 4L != 0L) return(invalid("pc"))
  if (!kind %in% CLASSES) return(invalid("class"))
  texts <- tokens[3:5]
  registers <- vapply(texts,parse_register,integer(1))
  if (any(texts != "-" & registers == -1L)) return(invalid("register"))
  usage <- OPERANDS[[kind]]
  if (any((usage == 1L & texts == "-") | (usage == 0L & texts != "-"))) return(invalid("operands"))
  outcome <- tokens[6L]
  allowed <- if (kind == "BRANCH") c("T","N") else if (kind == "JUMP") "T" else "-"
  if (!outcome %in% allowed) return(invalid("taken"))
  target <- parse_hex(tokens[7L])
  if (kind %in% CONTROLS) {
    if (is.na(target) || target %% 4L != 0L || target == pc+4L) return(invalid("target"))
  } else if (tokens[7L] != "-") return(invalid("target"))
  address <- parse_hex(tokens[8L])
  if (kind %in% c("LOAD","STORE")) {
    if (is.na(address) || address %% 4L != 0L) return(invalid("address"))
  } else if (tokens[8L] != "-") return(invalid("address"))
  instruction <- list(
      pc=pc,
      kind=kind,
      rd=registers[1L],
      rs1=registers[2L],
      rs2=registers[3L],
      outcome=outcome,
      target=target,
      address=address,
      next_pc=if (outcome == "T") target else pc+4L
  )
  previous <- static[[as.character(pc)]]
  if (!is.null(previous)) {
    if (kind != previous$kind || any(registers != c(
        previous$rd,
        previous$rs1,
        previous$rs2
    ))) return(invalid("conflict"))
    fixed_target <- kind == "BRANCH" || (kind == "JUMP" && instruction$rs1 == -1L)
    if (fixed_target && target != previous$target) return(invalid("conflict"))
  }
  list(instruction=instruction,error=NULL)
}
validate_trace <- function(lines) {
  instructions <- rejected <- gaps <- static <- list()
  for (line_number in seq_along(lines)) {
    checked <- check_record(lines[line_number],static)
    if (!is.null(checked$error)) {
      rejected[[length(rejected)+1L]] <- list(line=line_number,error=checked$error)
      next
    }
    instruction <- checked$instruction
    instruction$line <- line_number
    instruction$number <- length(instructions)+1L
    n <- length(instructions)
    if (n > 0L && instruction$pc != instructions[[n]]$next_pc) gaps[[length(gaps)+1L]] <- list(
        line=line_number,
        expected=instructions[[n]]$next_pc,
        found=instruction$pc
    )
    instructions[[n+1L]] <- instruction
    key <- as.character(instruction$pc)
    if (is.null(static[[key]])) static[[key]] <- instruction
  }
  list(lines=length(lines),instructions=instructions,rejected=rejected,gaps=gaps,static=static)
}
predict_trace <- function(instructions,definition,config) {
  btb_state <- btb(config$btb)
  ras_state <- ras(config$ras)
  direction <- direction_predictor(definition$scheme,definition$parameters)
  details <- vector("list",length(instructions))
  flags <- rep(FALSE,length(instructions))
  keys <- c(
      "lookups",
      "hits",
      "calls",
      "returns",
      "ras_predictions",
      "ras_correct",
      "control",
      "mispredictions",
      "BRANCH",
      "JUMP",
      "BRANCH_misses",
      "JUMP_misses",
      MISS_KINDS
  )
  statistics <- setNames(integer(length(keys)),keys)
  increase <- function(key,value=1L) statistics[key] <<- statistics[key]+as.integer(value)
  for (i in seq_along(instructions)) {
    instruction <- instructions[[i]]
    kind <- instruction$kind
    if (!kind %in% CONTROLS) next
    pc <- instruction$pc
    target <- instruction$target
    taken <- instruction$outcome == "T"
    candidate <- lookup(btb_state,pc)
    increase("lookups")
    increase("hits",!is.null(candidate))
    is_return <- kind == "JUMP" && instruction$rd == -1L && instruction$rs1 == 31L
    is_call <- kind == "JUMP" && instruction$rd == 31L
    increase("calls",is_call)
    increase("returns",is_return)
    if (is_return) {
      address <- ras_pop(ras_state)
      if (!is.null(address)) {
        candidate <- address
        increase("ras_predictions")
        increase("ras_correct",address == target)
      }
    }
    if (is_call) ras_push(ras_state,pc+4L)
    predicted_taken <- if (kind == "BRANCH") direction_prediction(direction,pc,target) else TRUE
    predicted <- if (definition$scheme == "PERFECT") instruction$next_pc else if (kind == "JUMP") {
      if (is.null(candidate)) pc+4L else candidate
    } else if (predicted_taken && !is.null(candidate)) candidate else pc+4L
    missed <- predicted != instruction$next_pc
    miss_kind <- NULL
    if (missed) {
      miss_kind <- if (kind == "BRANCH" && predicted_taken != taken) "direction" else if (is.null(candidate)) "btb_miss" else "wrong_target"
      increase(miss_kind)
    }
    flags[i] <- missed
    details[[i]] <- list(predicted=predicted,kind=miss_kind,missed=missed)
    increase("control")
    increase("mispredictions",missed)
    increase(kind)
    increase(paste0(kind,"_misses"),missed)
    if (kind == "BRANCH") direction_update(direction,pc,taken)
    if (taken) insert(btb_state,pc,target)
  }
  list(definition=definition,details=details,flags=flags,statistics=statistics,bits=storage_bits(direction))
}
stall_totals <- function(records) {
  cycles <- events <- integer(4L)
  for (record in records) {
    cycles[record$cause] <- cycles[record$cause]+record$cycles
    events[record$cause] <- events[record$cause]+1L
  }
  list(cycles=cycles,events=events)
}
all_combinations <- function(instructions,sources,predictions,config) {
  combinations <- list()
  primary <- NULL
  for (variant in config$variants) for (predictor in config$predictors) {
    result <- simulate(instructions,sources,variant,predictions[[predictor$name]]$flags)
    totals <- stall_totals(result$records)
    combinations[[length(combinations)+1L]] <- list(
        variant=variant$name,
        predictor=predictor$name,
        cycles=result$cycles,
        stalls=totals$cycles
    )
    if (variant$name == config$primary[1L] && predictor$name == config$primary[2L]) primary <- c(
        result,
        list(variant=variant,predictor=predictor$name,stalls=totals$cycles,stall_events=totals$events)
    )
  }
  ordered <- order(
      vapply(combinations,function(pair) pair$cycles,integer(1)),
      vapply(combinations,function(pair) pair$variant,character(1)),
      vapply(combinations,function(pair) pair$predictor,character(1)),
      method="radix"
  )
  list(combinations=combinations[ordered],primary=primary)
}
build_rows <- function(instructions,primary,prediction) {
  annotations <- rep("",length(instructions))
  for (record in primary$records) if (record$waiting != 0L) annotations[record$waiting] <- paste0(
      annotations[record$waiting],
      " ",
      CAUSES[record$cause],
      " ",
      record$cycles
  )
  rows <- list()
  for (i in seq_along(instructions)) {
    instruction <- instructions[[i]]
    t <- primary$timings[i,]
    f <- t[1L]
    d <- t[2L]
    x <- t[3L]
    m <- t[4L]
    w <- t[5L]
    annotation <- annotations[i]
    if (prediction$flags[i]) annotation <- paste0(annotation," mispredict ",prediction$details[[i]]$kind)
    characters <- list(
        list(f,f,"F"),
        list(f+1L,d-1L,"*"),
        list(d,d,"D"),
        list(d+1L,x-1L,"*"),
        list(x,m-1L,"X"),
        list(m,m,"M"),
        list(w,w,"W")
    )
    stages <- list(c(1L,f,d-1L),c(2L,d,x-1L),c(3L,x,m-1L),c(4L,m,m),c(5L,w,w))
    rows[[length(rows)+1L]] <- list(
        number=i,
        pc=instruction$pc,
        kind=instruction$kind,
        annotation=annotation,
        characters=characters,
        stages=stages
    )
    if (!prediction$flags[i]) next
    resolved <- id_resolved(instruction,primary$variant)
    cancel <- x+as.integer(!resolved)
    characters <- list(list(d,d,"F"),list(d+1L,x-1L,"*"),list(cancel,cancel,"x"))
    stages <- list(c(1L,d,x-1L))
    if (!resolved) {
      characters[[length(characters)+1L]] <- list(x,x,"D")
      stages[[length(stages)+1L]] <- c(2L,x,x)
    }
    pc <- prediction$details[[i]]$predicted
    rows[[length(rows)+1L]] <- list(
        number=0L,
        pc=pc,
        kind="FLUSH",
        annotation="",
        characters=characters,
        stages=stages
    )
    if (!resolved) rows[[length(rows)+1L]] <- list(
        number=0L,
        pc=pc+4L,
        kind="FLUSH",
        annotation="",
        characters=list(list(x,x,"F"),list(x+1L,x+1L,"x")),
        stages=list(c(1L,x,x))
    )
  }
  rows
}
occupancy <- function(rows) {
  counts <- matrix(0L,5L,2L)
  for (row in rows) for (stage in row$stages) {
    column <- if (row$number == 0L) 2L else 1L
    counts[stage[1L],column] <- counts[stage[1L],column]+stage[3L]-stage[2L]+1L
  }
  counts
}
clipped_cycles <- function(first,last,beginning,ending) {
  a <- max(first,beginning)
  b <- min(last,ending)
  if (a > b) integer() else seq.int(a,b)
}
pipeline_lines <- function(rows,primary,config) {
  first <- config$window[1L]
  last <- config$window[2L]
  width <- last-first+1L
  lines <- c(
      paste0(
          "pipeline variant=",
          primary$variant$name,
          " predictor=",
          primary$predictor,
          " cycles ",
          first,
          "-",
          last
      ),
      cycle_heading(first,last)
  )
  contents <- matrix(".",width,5L)
  visible <- stalled <- flushed <- 0L
  for (row in rows) {
    characters <- rep(".",width)
    for (entry in row$characters) {
      cycles <- clipped_cycles(first,last,entry[[1L]],entry[[2L]])
      characters[cycles-first+1L] <- entry[[3L]]
    }
    if (any(characters != ".")) {
      visible <- visible+1L
      stalled <- stalled+sum(characters == "*")
      flushed <- flushed+sum(characters == "x")
      lines <- c(lines,diagram_row(row$number,row$pc,row$kind,paste(characters,collapse=""),row$annotation))
    }
    for (stage in row$stages) {
      cycles <- clipped_cycles(first,last,stage[2L],stage[3L])
      contents[cycles-first+1L,stage[1L]] <- if (row$number == 0L) "w" else as.character(row$number)
    }
  }
  completed <- sum(first <= primary$timings[,5L] & primary$timings[,5L] <= last)
  lines <- c(
      lines,
      paste("rows",visible,"completed",completed,"stall_cells",stalled,"flushed",flushed),
      "",
      "stages",
      "cycle IF ID EX MEM WB"
  )
  for (cycle in seq.int(first,last)) lines <- c(
      lines,
      paste(cycle,paste(contents[cycle-first+1L,],collapse=" "))
  )
  lines
}
stall_aggregates <- function(instructions,records) {
  classes <- setNames(integer(length(CLASSES)),CLASSES)
  by_pc <- pairs <- list()
  for (record in records) {
    instruction <- instructions[[record$responsible]]
    classes[instruction$kind] <- classes[instruction$kind]+record$cycles
    key <- as.character(instruction$pc)
    if (is.null(by_pc[[key]])) by_pc[[key]] <- integer(4L)
    by_pc[[key]][record$cause] <- by_pc[[key]][record$cause]+record$cycles
    if (record$cause >= 3L) {
      producer <- instructions[[record$producer]]$pc
      waiting <- instructions[[record$waiting]]$pc
      key <- paste(producer,waiting,record$cause,sep=",")
      if (is.null(pairs[[key]])) pairs[[key]] <- list(
          producer=producer,
          waiting=waiting,
          cause=record$cause,
          cycles=0L,
          events=0L
      )
      pairs[[key]]$cycles <- pairs[[key]]$cycles+record$cycles
      pairs[[key]]$events <- pairs[[key]]$events+1L
    }
  }
  list(classes=classes,by_pc=by_pc,pairs=pairs)
}
dataflow_height <- function(instructions,sources,latency) {
  finish <- integer(length(instructions))
  for (i in seq_along(instructions)) {
    producers <- vapply(sources[[i]],function(source) source$producer,integer(1))
    producers <- producers[producers != 0L]
    start <- if (length(producers)) max(finish[producers]) else 0L
    kind <- instructions[[i]]$kind
    cost <- if (kind == "LOAD") 2L else if (kind == "MUL") latency else 1L
    finish[i] <- start+cost
  }
  max(finish)
}
whatif_runs <- function(instructions,sources,primary,flags) {
  variant <- primary$variant
  single <- off <- stage <- variant
  single$latency <- 1L
  off$forwarding <- !variant$forwarding
  stage$stage <- if (variant$stage == "EX") "ID" else "EX"
  changes <- list(list(name="perfect_prediction",variant=variant,flags=rep(FALSE,length(instructions))),list(name="single_cycle_mul",variant=single,flags=flags),
    list(
        name=if (variant$forwarding) "forwarding_off" else "forwarding_on",
        variant=off,
        flags=flags
    ),list(name=paste0("branch_stage_",stage$stage),variant=stage,flags=flags))
  lapply(
      changes,
      function(change) list(
          name=change$name,
          cycles=simulate(instructions,sources,change$variant,change$flags)$cycles
      )
  )
}
input_part <- function(trace) {
  lines <- paste(
      "input lines",
      trace$lines,
      "accepted",
      length(trace$instructions),
      "rejected",
      length(trace$rejected),
      "gaps",
      length(trace$gaps)
  )
  for (row in trace$rejected) lines <- c(lines,paste("reject line",row$line,row$error))
  for (row in trace$gaps) lines <- c(
      lines,
      paste("gap line",row$line,"expected",hexadecimal(row$expected),"found",hexadecimal(row$found))
  )
  lines
}
trace_part <- function(trace,sources) {
  instructions <- trace$instructions
  counts <- setNames(
      vapply(
          CLASSES,
          function(kind) sum(vapply(instructions,function(i) i$kind == kind,logical(1))),
          integer(1)
      ),
      CLASSES
  )
  branches <- Filter(function(i) i$kind == "BRANCH",instructions)
  jumps <- Filter(function(i) i$kind == "JUMP",instructions)
  memory <- Filter(function(i) i$kind %in% c("LOAD","STORE"),instructions)
  addresses <- unique(vapply(memory,function(i) i$address,integer(1)))
  distances <- integer(5L)
  source_count <- 0L
  for (i in seq_along(sources)) {
    source_count <- source_count+length(sources[[i]])
    for (source in sources[[i]]) if (source$producer != 0L) {
      bin <- min(5L,i-source$producer)
      distances[bin] <- distances[bin]+1L
    }
  }
  c("trace",paste("instructions",length(instructions)),paste("static_instructions",length(trace$static)),paste("mix",paste(paste(CLASSES,counts),collapse=" ")),
    paste(
        "branches",
        length(branches),
        "taken",
        sum(vapply(branches,function(i) i$outcome == "T",logical(1))),
        "backward",
        sum(vapply(branches,function(i) i$target < i$pc,logical(1)))
    ),
    paste(
        "jumps",
        length(jumps),
        "indirect",
        sum(vapply(jumps,function(i) i$rs1 != -1L,logical(1))),
        "link",
        sum(vapply(jumps,function(i) i$rd != -1L,logical(1)))
    ),
    paste(
        "static_control branches",
        sum(vapply(trace$static,function(i) i$kind == "BRANCH",logical(1))),
        "jumps",
        sum(vapply(trace$static,function(i) i$kind == "JUMP",logical(1)))
    ),
    paste("memory loads",counts["LOAD"],"stores",counts["STORE"],"distinct_addresses",length(addresses)),
    paste(
        "operands",
        source_count,
        "with_producer",
        sum(distances),
        "distance",
        paste(paste(c("1","2","3","4","5+"),distances),collapse=" ")
    ))
}
prediction_accuracy <- function(prediction,kind="control") {
  statistics <- prediction$statistics
  total <- statistics[kind]
  misses <- statistics[if (kind == "control") "mispredictions" else paste0(kind,"_misses")]
  percentage(total-misses,total)
}
prediction_part <- function(predictions,config) {
  lines <- "prediction"
  for (definition in config$predictors) {
    prediction <- predictions[[definition$name]]
    s <- prediction$statistics
    lines <- c(lines,paste(definition$name,definition$scheme,"bits",prediction$bits,"control",s["control"],"mispredicted",s["mispredictions"],
      "accuracy",prediction_accuracy(prediction),"branches",prediction_accuracy(
          prediction,
          "BRANCH"
      ),"jumps",prediction_accuracy(prediction,"JUMP"),
      paste(paste(MISS_KINDS,s[MISS_KINDS]),collapse=" ")))
  }
  s <- predictions[[config$predictors[[1L]]$name]]$statistics
  c(lines,paste("btb entries",config$btb,"lookups",s["lookups"],"hits",s["hits"],"misses",s["lookups"]-s["hits"]),
    paste(
        "ras depth",
        config$ras,
        "calls",
        s["calls"],
        "returns",
        s["returns"],
        "predicted",
        s["ras_predictions"],
        "correct",
        s["ras_correct"]
    ))
}
cause_values <- function(values) paste(paste(CAUSES,values),collapse=" ")
timing_part <- function(primary,n,height,refetch) {
  variant <- primary$variant
  cycles <- primary$cycles
  stalls <- primary$stalls
  total <- sum(stalls)
  lengths <- integer(5L)
  for (value in primary$delays) if (value > 0L) lengths[min(5L,value)] <- lengths[min(5L,value)]+1L
  cpi_causes <- paste(paste(CAUSES,vapply(stalls,function(value) decimal(value,n),character(1))),collapse=" ")
  c(paste0("timing variant=",variant$name," predictor=",primary$predictor),paste("forwarding",if (variant$forwarding) "on" else "off","branch_stage",variant$stage,"mul_latency",variant$latency),
    paste("cycles",cycles),paste(
        "cpi",
        reduced_fraction(cycles,n),
        decimal(cycles,n)
    ),paste("ipc",decimal(n,cycles)),paste("stall_cycles total",total,cause_values(stalls)),
    paste(
        "stall_events",
        cause_values(primary$stall_events)
    ),paste("flushed",refetch),paste("cycle_check",n,"+ 4 +",total,"=",n+4L+total),
    paste("cpi_stack base 1.0000 fill",decimal(4L,n),cpi_causes),paste(
        "stall_lengths",
        paste(paste(c("1","2","3","4","5+"),lengths),collapse=" ")
    ),
    paste("dataflow height",height,"ilp",decimal(n,height)))
}
statistics_lines <- function(trace,sources,predictions,combinations,primary,rows,config) {
  instructions <- trace$instructions
  n <- length(instructions)
  height <- dataflow_height(instructions,sources,primary$variant$latency)
  aggregates <- stall_aggregates(instructions,primary$records)
  forward <- integer(3L)
  for (i in seq_along(instructions)) for (source in sources[[i]]) {
    p <- source$producer
    path <- forwarding_path(
        instructions[[i]],
        if (p == 0L) NULL else primary$timings[p,],
        primary$timings[i,],
        primary$variant
    )
    forward[path] <- forward[path]+1L
  }
  whatif <- "whatif"
  for (run in whatif_runs(instructions,sources,primary,predictions[[primary$predictor]]$flags)) whatif <- c(
      whatif,
      paste(
          run$name,
          "cycles",
          run$cycles,
          "saved",
          primary$cycles-run$cycles,
          "speedup",
          decimal(primary$cycles,run$cycles)
      )
  )
  classes <- "classes"
  for (kind in CLASSES) {
    total <- sum(vapply(instructions,function(i) i$kind == kind,logical(1)))
    average <- if (total == 0L) "-" else decimal(aggregates$classes[kind],total)
    classes <- c(
        classes,
        paste(kind,"count",total,"stall_cycles",aggregates$classes[kind],"per_instruction",average)
    )
  }
  occupied <- occupancy(rows)
  occupancy_lines <- paste("occupancy cycles",primary$cycles)
  for (i in seq_along(STAGES)) {
    correct <- occupied[i,1L]
    wrong <- occupied[i,2L]
    occupancy_lines <- c(
        occupancy_lines,
        paste(
            STAGES[i],
            "correct",
            correct,
            "wrong",
            wrong,
            "idle",
            primary$cycles-correct-wrong,
            "busy",
            percentage(correct+wrong,primary$cycles)
        )
    )
  }
  hotspots <- "hotspots"
  by_pc <- aggregates$by_pc
  pcs <- as.integer(names(by_pc))
  if (length(pcs)) pcs <- pcs[order(-vapply(by_pc,sum,integer(1)),pcs)]
  for (rank in seq_along(head(pcs,config$top))) {
    pc <- pcs[rank]
    key <- as.character(pc)
    hotspots <- c(
        hotspots,
        paste(
            rank,
            hexadecimal(pc),
            trace$static[[key]]$kind,
            "stall_cycles",
            sum(by_pc[[key]]),
            cause_values(by_pc[[key]])
        )
    )
  }
  pairs <- aggregates$pairs
  dependency_lines <- paste("dependencies total",length(pairs))
  if (length(pairs)) {
    ordered <- order(-vapply(pairs,function(group) group$cycles,integer(1)),vapply(pairs,function(group) group$producer,integer(1)),
      vapply(
          pairs,
          function(group) group$waiting,
          integer(1)
      ),vapply(pairs,function(group) group$cause,integer(1)))
    for (rank in seq_along(head(ordered,config$top))) {
      group <- pairs[[ordered[rank]]]
      dependency_lines <- c(dependency_lines,paste(rank,hexadecimal(group$producer),trace$static[[as.character(group$producer)]]$kind,"->",hexadecimal(group$waiting),
        trace$static[[as.character(group$waiting)]]$kind,CAUSES[group$cause],"stall_cycles",group$cycles,"events",group$events))
    }
  }
  intervals <- paste("intervals size",config$interval)
  for (first in seq.int(1L,n,by=config$interval)) {
    last <- min(n,first+config$interval-1L)
    previous <- if (first == 1L) 0L else primary$timings[first-1L,5L]
    cycles <- primary$timings[last,5L]-previous
    intervals <- c(intervals,paste0(first,"-",last," cycles ",cycles," cpi ",decimal(cycles,last-first+1L)))
  }
  names <- vapply(config$predictors,function(definition) definition$name,character(1))
  table_lines <- paste("cycles_table",paste(names,collapse=" "))
  for (variant in config$variants) {
    counts <- vapply(names,function(name) {
      pair <- Filter(function(pair) pair$variant == variant$name && pair$predictor == name,combinations)[[1L]]
      pair$cycles
    },integer(1))
    table_lines <- c(table_lines,paste(variant$name,paste(counts,collapse=" ")))
  }
  forward_line <- paste("forwarding",paste(paste(c("regfile","ex_mem","mem_wb"),forward),collapse=" "))
  join_parts(list(input_part(trace),trace_part(trace,sources),prediction_part(predictions,config),timing_part(primary,n,height,sum(vapply(rows,function(row) row$number == 0L,logical(1)))),
    whatif,classes,forward_line,occupancy_lines,hotspots,dependency_lines,intervals,table_lines))
}
group_executions <- function(instructions) {
  groups <- list()
  for (i in seq_along(instructions)) {
    key <- as.character(instructions[[i]]$pc)
    groups[[key]] <- c(groups[[key]],i)
  }
  groups[order(as.integer(names(groups)))]
}
branch_lines <- function(instructions,groups,predictions,config) {
  lines <- "predictor,pc,class,executions,taken,mispredictions,accuracy"
  for (definition in config$predictors) for (key in names(groups)) {
    indices <- groups[[key]]
    instruction <- instructions[[indices[1L]]]
    if (!instruction$kind %in% CONTROLS) next
    taken <- sum(vapply(indices,function(i) instructions[[i]]$outcome == "T",logical(1)))
    missed <- sum(predictions[[definition$name]]$flags[indices])
    lines <- c(
        lines,
        paste(
            definition$name,
            hexadecimal(instruction$pc),
            instruction$kind,
            length(indices),
            taken,
            missed,
            percentage(length(indices)-missed,length(indices)),
            sep=","
        )
    )
  }
  lines
}
comparison_lines <- function(combinations,primary,predictions,n) {
  lines <- "rank,variant,predictor,cycles,cpi,speedup,accuracy,mispredictions,control,structural,load_use,raw"
  for (rank in seq_along(combinations)) {
    pair <- combinations[[rank]]
    prediction <- predictions[[pair$predictor]]
    values <- c(
        rank,
        pair$variant,
        pair$predictor,
        pair$cycles,
        decimal(pair$cycles,n),
        decimal(primary$cycles,pair$cycles),
        prediction_accuracy(prediction),
        prediction$statistics["mispredictions"],
        pair$stalls
    )
    lines <- c(lines,paste(values,collapse=","))
  }
  lines
}
profile_lines <- function(instructions,groups,predictions,primary,config) {
  branches <- "branches"
  loops <- "loops"
  indirect <- "indirect"
  static_lines <- "instructions"
  choices <- vapply(
      Filter(function(definition) definition$scheme != "PERFECT",config$predictors),
      function(definition) definition$name,
      character(1)
  )
  aggregates <- stall_aggregates(instructions,primary$records)
  for (key in names(groups)) {
    pc <- as.integer(key)
    indices <- groups[[key]]
    instruction <- instructions[[indices[1L]]]
    if (instruction$kind == "BRANCH") {
      outcomes <- vapply(indices,function(i) instructions[[i]]$outcome,character(1))
      transitions <- sum(head(outcomes,-1L) != tail(outcomes,-1L))
      longest <- c(T=0L,N=0L)
      previous <- ""
      run <- trip <- 0L
      trips <- integer()
      for (outcome in outcomes) {
        run <- if (outcome == previous) run+1L else 1L
        longest[outcome] <- max(longest[outcome],run)
        previous <- outcome
        trip <- trip+1L
        if (outcome == "N") {
          trips <- c(trips,trip)
          trip <- 0L
        }
      }
      if (trip > 0L) trips <- c(trips,trip)
      misses <- vapply(choices,function(name) sum(predictions[[name]]$flags[indices]),integer(1))
      best <- which.min(misses)
      direction <- if (instruction$target < pc) "backward" else "forward"
      branches <- c(branches,paste(hexadecimal(pc),direction,"executions",length(indices),"taken",sum(outcomes == "T"),"transitions",transitions,
        "longest_taken",longest["T"],"longest_not_taken",longest["N"],"best",choices[best],misses[best]))
      if (direction == "backward") loops <- c(loops,paste(paste0(hexadecimal(instruction$target),"-",hexadecimal(pc)),"body",(pc-instruction$target) %/% 4L+1L,
        "entries",length(trips),"iterations",length(indices),"avg_trip",decimal(
            length(indices),
            length(trips)
        ),"max_trip",max(trips)))
    }
    if (instruction$kind == "JUMP" && instruction$rs1 != -1L) {
      targets <- vapply(indices,function(i) instructions[[i]]$target,integer(1))
      unique_targets <- sort(unique(targets))
      counts <- vapply(unique_targets,function(target) sum(targets == target),integer(1))
      ordered <- order(-counts,unique_targets)
      values <- paste(
          vapply(ordered,function(j) paste0(hexadecimal(unique_targets[j]),":",counts[j]),character(1)),
          collapse=" "
      )
      indirect <- c(
          indirect,
          paste(
              hexadecimal(pc),
              "executions",
              length(indices),
              "distinct",
              length(unique_targets),
              "targets",
              values
          )
      )
    }
    operands <- paste(
        vapply(c(instruction$rd,instruction$rs1,instruction$rs2),register_text,character(1)),
        collapse=" "
    )
    stalls <- aggregates$by_pc[[key]]
    static_lines <- c(
        static_lines,
        paste(
            hexadecimal(pc),
            instruction$kind,
            operands,
            "executions",
            length(indices),
            "stall_cycles",
            sum(stalls)
        )
    )
  }
  segments <- list()
  first <- 1L
  for (last in seq_along(instructions)) {
    instruction <- instructions[[last]]
    if (instruction$kind %in% CONTROLS || last == length(instructions)) {
      key <- as.character(instructions[[first]]$pc)
      if (is.null(segments[[key]])) segments[[key]] <- c(0L,0L,0L)
      group <- segments[[key]]
      group[1L] <- group[1L]+1L
      group[2L] <- group[2L]+last-first+1L
      group[3L] <- group[3L]+primary$timings[last,5L]-(if (first == 1L) 0L else primary$timings[first-1L,5L])
      segments[[key]] <- group
      first <- last+1L
    }
  }
  segment_lines <- paste("segments total",length(segments))
  ordered <- order(-vapply(segments,`[`,integer(1),3L),as.integer(names(segments)))
  for (rank in seq_along(head(ordered,config$top))) {
    index <- ordered[rank]
    pc <- as.integer(names(segments)[index])
    group <- segments[[index]]
    segment_lines <- c(
        segment_lines,
        paste(
            rank,
            hexadecimal(pc),
            "instances",
            group[1L],
            "instructions",
            group[2L],
            "cycles",
            group[3L],
            "cpi",
            decimal(group[3L],group[2L])
        )
    )
  }
  join_parts(list(branches,loops,segment_lines,indirect,static_lines))
}
main <- function() {
  inputs <- read_inputs()
  config <- inputs$config
  trace <- validate_trace(inputs$trace)
  instructions <- trace$instructions
  sources <- dependencies(instructions)
  predictions <- setNames(
      lapply(config$predictors,function(definition) predict_trace(instructions,definition,config)),
      vapply(config$predictors,function(definition) definition$name,character(1))
  )
  all <- all_combinations(instructions,sources,predictions,config)
  combinations <- all$combinations
  primary <- all$primary
  rows <- build_rows(instructions,primary,predictions[[primary$predictor]])
  groups <- group_executions(instructions)
  write_lines("pipeline.txt",pipeline_lines(rows,primary,config))
  write_lines("stats.txt",statistics_lines(trace,sources,predictions,combinations,primary,rows,config))
  write_lines("branches.csv",branch_lines(instructions,groups,predictions,config))
  write_lines("comparison.csv",comparison_lines(combinations,primary,predictions,length(instructions)))
  write_lines("profile.txt",profile_lines(instructions,groups,predictions,primary,config))
}
main()
