types <- c("MOTORCYCLE","CAR","ECAR","VAN","BUS")
kinds <- c("MOTO","COMPACT","LARGE","EV")
prefs <- list(MOTORCYCLE=c("MOTO","COMPACT","LARGE"),CAR=c("COMPACT","LARGE"),ECAR=c("EV","COMPACT","LARGE"),VAN="LARGE")
rates <- list(MOTORCYCLE=c(100L,800L),CAR=c(200L,1600L),ECAR=c(200L,1600L),VAN=c(300L,2400L),BUS=c(600L,4800L))
fees <- c(NIGHT=300L,LOST=2000L,KWH=30L)
object <- function(...) list2env(list(...),parent=emptyenv())
registry <- function() new.env(hash=TRUE,parent=emptyenv())
spots <- registry()
vehicles <- registry()
passes <- registry()
history <- registry()
levels <- queue <- list()
stat_fields <- c("entries","exits","refused","stay","parking","night","lost","charge","total")
stats <- setNames(lapply(types,function(type) setNames(rep(0L,length(stat_fields)),stat_fields)),types)
daily <- list()
now <- peak <- peak_time <- 0L
fail <- function(message) stop(message,call.=FALSE)
map_values <- function(map) lapply(ls(map,all.names=TRUE,sorted=FALSE),function(key) map[[key]])
map_size <- function(map) length(ls(map,all.names=TRUE,sorted=FALSE))
date_of <- function(time) time%/%1440L+1L
time_text <- function(time) paste0(date_of(time),"-",sprintf("%02d:%02d",as.integer((time%%1440L)%/%60L),as.integer(time%%60L)))
duration <- function(minutes) sprintf("%d:%02d",as.integer(minutes%/%60L),as.integer(minutes%%60L))
one_decimal <- function(q) paste0(q%/%10L,".",q%%10L)
valid_pass <- function(plate,time) !is.null(passes[[plate]]) && date_of(time)<=passes[[plate]]
get_spot <- function(id) {
  s <- spots[[id]]
  if (is.null(s)) fail(paste("unknown spot",id))
  s
}
get_vehicle <- function(plate) {
  v <- vehicles[[plate]]
  if (is.null(v)) fail(paste(plate,"is not parked"))
  v
}
location <- function(v) {
  s <- v$spots[[1L]]
  if (v$type=="BUS") paste0("L",s$level,"-",s$number,"..",s$number+2L) else s$id
}
free_spot <- function(s) !s$closed && s$plate==""
assignment <- function(type) {
  if (type=="BUS") {
    for (level in levels) {
      if (length(level)>=3L) {
        for (i in seq_len(length(level)-2L)) {
          triple <- level[i:(i+2L)]
          if (all(vapply(triple,function(s) s$kind=="LARGE" && free_spot(s),logical(1L)))) return(triple)
        }
      }
    }
  } else {
    for (kind in prefs[[type]]) {
      for (level in levels) {
        for (s in level) if (s$kind==kind && free_spot(s)) return(list(s))
      }
    }
  }
  list()
}
add_stat <- function(type,field,amount,date) {
  stats[[type]][field] <<- stats[[type]][field]+amount
  if (field %in% c("entries","exits","refused","total")) {
    key <- as.character(date)
    rows <- daily[[key]]
    if (is.null(rows)) rows <- setNames(lapply(types,function(k) c(entries=0L,exits=0L,refused=0L,revenue=0L)),types)
    daily_field <- if (field=="total") "revenue" else field
    rows[[type]][daily_field] <- rows[[type]][daily_field]+amount
    daily[[key]] <<- rows
  }
}
park_vehicle <- function(plate,type,chosen) {
  v <- object(plate=plate,type=type,spots=chosen,entry=now,kwh=0L,cost=0L,validation=0L,payment=NULL)
  for (s in chosen) s$plate <- plate
  vehicles[[plate]] <- v
  add_stat(type,"entries",1L,date_of(now))
  if (map_size(vehicles)>peak) {
    peak <<- map_size(vehicles)
    peak_time <<- now
  }
  v
}
process_queue <- function() {
  remaining <- list()
  out <- character()
  for (waiting in queue) {
    chosen <- assignment(waiting$type)
    if (!length(chosen)) {
      remaining[[length(remaining)+1L]] <- waiting
    } else {
      v <- park_vehicle(waiting$plate,waiting$type,chosen)
      out <- c(out,paste("ADMIT",v$plate,v$type,location(v),"waited",duration(now-waiting$time)))
    }
  }
  queue <<- remaining
  out
}
giveups <- function() {
  remaining <- list()
  out <- character()
  for (waiting in queue) {
    if (now-waiting$time>=30L) {
      time <- waiting$time+30L
      out <- c(out,paste("GIVEUP",waiting$plate,waiting$type,time_text(time)))
      add_stat(waiting$type,"refused",1L,date_of(time))
    } else {
      remaining[[length(remaining)+1L]] <- waiting
    }
  }
  queue <<- remaining
  out
}
interval_fee <- function(v,a,b,free) {
  total <- b-a
  if (valid_pass(v$plate,b) || total<=free) return(c(0L,0L))
  rule <- rates[[v$type]]
  parking <- i <- 0L
  while (total>0L) {
    minutes <- min(total,1440L)
    billable <- minutes-(if (i==0L) free else 0L)
    parking <- parking+min(((billable+29L)%/%30L)*rule[1L],rule[2L])
    total <- total-minutes
    i <- i+1L
  }
  c(parking,(date_of(b)-date_of(a))*fees[["NIGHT"]])
}
charges <- function(v,lost=FALSE) {
  if (is.null(v$payment)) {
    amounts <- interval_fee(v,v$entry,now,15L+v$validation)
    loss <- if (lost) fees[["LOST"]] else 0L
    total <- sum(amounts)+loss+v$cost
    return(c(amounts,loss,v$cost,total,total))
  }
  extra <- interval_fee(v,v$payment$time,now,15L)
  parking <- v$payment$parking+extra[1L]
  night <- v$payment$night+extra[2L]
  c(parking,night,0L,v$cost,parking+night+v$cost,sum(extra))
}
fee_line <- function(label,v,f) paste(label,v$plate,location(v),"stay",duration(now-v$entry),"parking",f[1L],"night",f[2L],"lost",f[3L],"charge",f[4L],"total",f[5L],"due",f[6L])
annotation <- function(v) {
  text <- if (valid_pass(v$plate,now)) " PASS" else ""
  if (v$validation!=0L) text <- paste0(text," VAL ",v$validation)
  if (v$kwh!=0L) text <- paste0(text," KWH ",v$kwh)
  if (!is.null(v$payment)) text <- paste0(text," PAID")
  text
}
move_vehicle <- function(v,spot) {
  old <- location(v)
  original <- v$spots[[1L]]
  original$plate <- ""
  spot$plate <- v$plate
  v$spots <- list(spot)
  paste("MOVE",v$plate,old,"->",spot$id)
}
location_order <- function(values,entry=FALSE) {
  rows <- vapply(values,function(v) v$spots[[1L]]$level,integer(1L))
  numbers <- vapply(values,function(v) v$spots[[1L]]$number,integer(1L))
  if (entry) {
    times <- vapply(values,function(v) v$entry,integer(1L))
    return(values[order(times,rows,numbers,method="radix")])
  }
  values[order(rows,numbers,method="radix")]
}
occupancy_line <- function(label,used,available,closed_count) {
  counts <- paste(kinds, paste0(used[kinds], "/", available[kinds]), collapse = " ")
  paste(label, counts, "closed", closed_count)
}
execute <- function(t) {
  cmd <- t[1L]
  out <- character()
  emit <- function(lines) out <<- c(out,lines)
  if (cmd=="LEVEL") {
    level_no <- length(levels)+1L
    level <- list()
    for (index in seq_along(kinds)) {
      kind <- kinds[index]
      for (i in seq_len(as.integer(t[index+1L]))) {
        number <- length(level)+1L
        id <- paste0("L",level_no,"-",number)
        s <- object(id=id,level=level_no,number=number,kind=kind,closed=FALSE,plate="")
        spots[[id]] <- s
        level[[number]] <- s
      }
    }
    levels[[level_no]] <<- level
    emit(paste("LEVEL",level_no,"spots",length(level),"MOTO",t[2L],"COMPACT",t[3L],"LARGE",t[4L],"EV",t[5L]))
  } else if (cmd %in% c("CLOSE","OPEN")) {
    s <- get_spot(t[2L])
    if (cmd=="CLOSE") {
      if (s$closed) fail(paste("spot",t[2L],"is already closed"))
      if (s$plate!="") fail(paste("spot",t[2L],"is occupied by",s$plate))
      s$closed <- TRUE
    } else {
      if (!s$closed) fail(paste("spot",t[2L],"is not closed"))
      s$closed <- FALSE
    }
    emit(paste(cmd,s$id,s$kind))
  } else if (cmd=="RATE") {
    if (is.null(rates[[t[2L]]])) fail(paste("unknown type",t[2L]))
    if (as.integer(t[4L])<as.integer(t[3L])) fail(paste("cap below rate for",t[2L]))
    rates[[t[2L]]] <<- as.integer(t[3:4])
    emit(paste("RATE",t[2L],t[3L],t[4L]))
  } else if (cmd=="FEE") {
    if (!(t[2L] %in% names(fees))) fail(paste("unknown fee",t[2L]))
    fees[t[2L]] <<- as.integer(t[3L])
    emit(paste("FEE",t[2L],t[3L]))
  } else if (cmd=="ENTER") {
    plate <- t[2L]
    type <- t[3L]
    if (is.null(rates[[type]])) fail(paste("unknown type",type))
    if (!is.null(vehicles[[plate]])) fail(paste(plate,"is already parked at",location(vehicles[[plate]])))
    for (w in queue) if (w$plate==plate) fail(paste(plate,"is already waiting"))
    chosen <- assignment(type)
    if (length(chosen)) {
      v <- park_vehicle(plate,type,chosen)
      emit(paste("ENTER",plate,type,location(v)))
    } else if (length(queue)<3L) {
      queue[[length(queue)+1L]] <<- list(plate=plate,type=type,time=now)
      emit(paste("WAIT",plate,type,length(queue)))
    } else {
      add_stat(type,"refused",1L,date_of(now))
      emit(paste("FULL",plate,type))
    }
  } else if (cmd=="LEAVE") {
    found <- which(vapply(queue,function(w) w$plate==t[2L],logical(1L)))
    if (!length(found)) fail(paste(t[2L],"is not waiting"))
    w <- queue[[found]]
    queue <<- queue[-found]
    emit(paste("LEAVE",w$plate,w$type))
  } else if (cmd %in% c("EXIT","PAY","QUOTE","CHARGE","VALIDATE","MOVE")) {
    v <- get_vehicle(t[2L])
    if (cmd=="EXIT") {
      lost <- length(t)==3L
      if (lost && !is.null(v$payment)) fail(paste(v$plate,"has already paid"))
      f <- charges(v,lost)
      emit(fee_line("EXIT",v,f))
      record <- list(entry=v$entry,exit=now,location=location(v),type=v$type,total=f[5L],lost=lost)
      records <- history[[v$plate]]
      records[[length(records)+1L]] <- record
      history[[v$plate]] <- records
      for (s in v$spots) s$plate <- ""
      rm(list=v$plate,envir=vehicles)
      add_stat(v$type,"exits",1L,date_of(now))
      add_stat(v$type,"stay",now-v$entry,date_of(now))
      fields <- c("parking","night","lost","charge","total")
      for (index in seq_along(fields)) add_stat(v$type,fields[index],f[index],date_of(now))
    } else if (cmd=="PAY") {
      if (!is.null(v$payment)) fail(paste(v$plate,"has already paid"))
      f <- charges(v)
      v$payment <- list(time=now,parking=f[1L],night=f[2L])
      emit(paste("PAY",v$plate,"parking",f[1L],"night",f[2L],"charge",f[4L],"total",f[5L]))
    } else if (cmd=="QUOTE") {
      emit(fee_line("QUOTE",v,charges(v)))
    } else if (cmd=="CHARGE") {
      if (v$type!="ECAR") fail(paste(v$plate,"is not an electric car"))
      if (v$spots[[1L]]$kind!="EV") fail(paste(v$plate,"is not at a charger"))
      if (!is.null(v$payment)) fail(paste(v$plate,"has already paid"))
      kwh <- as.integer(t[3L])
      if (v$kwh+kwh>100L) fail(paste("charge limit exceeded for",v$plate))
      cost <- kwh*fees[["KWH"]]
      v$kwh <- v$kwh+kwh
      v$cost <- v$cost+cost
      emit(paste("CHARGE",v$plate,"kwh",kwh,"cost",cost,"stay_kwh",v$kwh,"stay_cost",v$cost))
    } else if (cmd=="VALIDATE") {
      if (!is.null(v$payment)) fail(paste(v$plate,"has already paid"))
      minutes <- as.integer(t[3L])
      if (v$validation+minutes>180L) fail(paste("validation limit exceeded for",v$plate))
      v$validation <- v$validation+minutes
      emit(paste("VALIDATE",v$plate,minutes,"total",v$validation))
    } else {
      if (v$type=="BUS") fail(paste("bus",v$plate,"cannot be moved"))
      s <- get_spot(t[3L])
      if (v$spots[[1L]]$id==s$id) fail(paste(v$plate,"is already at",s$id))
      if (s$closed) fail(paste("spot",s$id,"is closed"))
      if (s$plate!="") fail(paste("spot",s$id,"is occupied by",s$plate))
      if (!(s$kind %in% prefs[[v$type]])) fail(paste(v$type,"cannot use",s$kind,"spot",s$id))
      emit(move_vehicle(v,s))
    }
  } else if (cmd=="PASS") {
    plate <- t[2L]
    passes[[plate]] <- if (valid_pass(plate,now)) passes[[plate]]+as.integer(t[3L]) else date_of(now)+as.integer(t[3L])-1L
    emit(paste("PASS",plate,"until",passes[[plate]]))
  } else if (cmd=="UNPASS") {
    if (!valid_pass(t[2L],now)) fail(paste(t[2L],"has no pass"))
    rm(list=t[2L],envir=passes)
    emit(paste("UNPASS",t[2L]))
  } else if (cmd=="REBALANCE") {
    targets <- location_order(Filter(function(v) v$type!="BUS",map_values(vehicles)))
    moved <- 0L
    for (v in targets) {
      current <- match(v$spots[[1L]]$kind,prefs[[v$type]])
      if (current==1L) next
      chosen <- assignment(v$type)
      if (length(chosen) && match(chosen[[1L]]$kind,prefs[[v$type]])<current) {
        emit(move_vehicle(v,chosen[[1L]]))
        moved <- moved+1L
      }
    }
    emit(paste("REBALANCE",moved))
  } else if (cmd=="WHERE") {
    plate <- t[2L]
    v <- vehicles[[plate]]
    if (!is.null(v)) {
      emit(paste0(paste("WHERE",plate,location(v),v$type,time_text(v$entry),"stay",duration(now-v$entry)),annotation(v)))
    } else {
      position <- which(vapply(queue,function(w) w$plate==plate,logical(1L)))
      records <- history[[plate]]
      if (length(position)) {
        emit(paste("WHERE",plate,"waiting",position))
      } else if (!is.null(records)) {
        emit(paste("WHERE",plate,"gone",time_text(records[[length(records)]]$exit)))
      } else {
        fail(paste("unknown plate",plate))
      }
    }
  } else if (cmd %in% c("LIST","OVERSTAY")) {
    if (cmd=="LIST" && length(t)==2L && as.integer(t[2L])>length(levels)) fail(paste("unknown level",t[2L]))
    targets <- map_values(vehicles)
    if (cmd=="LIST" && length(t)==2L) targets <- Filter(function(v) v$spots[[1L]]$level==as.integer(t[2L]),targets)
    if (cmd=="OVERSTAY") targets <- Filter(function(v) now-v$entry>=as.integer(t[2L])*60L,targets)
    targets <- location_order(targets,cmd=="OVERSTAY")
    header <- if (cmd=="OVERSTAY") paste(cmd,t[2L]) else cmd
    emit(paste(header,length(targets)))
    for (v in targets) {
      text <- paste(location(v),v$plate,v$type,time_text(v$entry))
      text <- if (cmd=="LIST") paste0(text,annotation(v)) else paste(text,"stay",duration(now-v$entry))
      emit(text)
    }
  } else if (cmd=="MAP") {
    emit(paste("MAP",length(levels)))
    for (index in seq_along(levels)) {
      symbols <- vapply(levels[[index]],function(s) {
        if (s$closed) return("#")
        initial <- substr(s$kind,1L,1L)
        if (s$plate=="") tolower(initial) else initial
      },character(1L))
      starts <- seq.int(1L,length(symbols),by=10L)
      chunks <- vapply(starts,function(i) paste(symbols[i:min(i+9L,length(symbols))],collapse=""),character(1L))
      emit(paste0("L",index," ",paste(chunks,collapse=" ")))
    }
  } else if (cmd=="OCCUPANCY") {
    emit(paste("OCCUPANCY vehicles",map_size(vehicles),"waiting",length(queue)))
    total_used <- total_available <- setNames(rep(0L,4L),kinds)
    total_closed <- 0L
    for (index in seq_along(levels)) {
      used <- available <- setNames(rep(0L,4L),kinds)
      closed_count <- 0L
      for (s in levels[[index]]) {
        if (s$closed) closed_count <- closed_count+1L else available[s$kind] <- available[s$kind]+1L
        if (s$plate!="") used[s$kind] <- used[s$kind]+1L
      }
      emit(occupancy_line(paste0("L",index),used,available,closed_count))
      total_used <- total_used+used
      total_available <- total_available+available
      total_closed <- total_closed+closed_count
    }
    capacity <- sum(total_available)
    usage <- if (capacity==0L) 0L else (sum(total_used)*1000L)%/%capacity
    emit(paste0(occupancy_line("TOTAL",total_used,total_available,total_closed)," rate ",one_decimal(usage),"%"))
  } else if (cmd=="SIGN") {
    parts <- "SIGN"
    for (type in types) {
      count <- 0L
      for (level in levels) {
        run <- 0L
        for (s in level) {
          if (type=="BUS") {
            if (s$kind=="LARGE" && free_spot(s)) {
              run <- run+1L
            } else {
              count <- count+run%/%3L
              run <- 0L
            }
          } else if (s$kind %in% prefs[[type]] && free_spot(s)) {
            count <- count+1L
          }
        }
        if (type=="BUS") count <- count+run%/%3L
      }
      parts <- c(parts,type,if (count==0L) "FULL" else as.character(count))
    }
    emit(paste(parts,collapse=" "))
  } else if (cmd=="RATES") {
    emit("RATES")
    for (type in types) emit(paste(type,rates[[type]][1L],rates[[type]][2L]))
    emit(paste("NIGHT",fees[["NIGHT"]],"LOST",fees[["LOST"]],"KWH",fees[["KWH"]]))
  } else if (cmd=="PASSES") {
    plates <- sort(Filter(function(plate) valid_pass(plate,now),ls(passes,all.names=TRUE)),method="radix")
    emit(paste("PASSES",length(plates)))
    for (plate in plates) emit(paste0(paste(plate,"until",passes[[plate]]),if (!is.null(vehicles[[plate]])) " IN" else ""))
  } else if (cmd=="HISTORY") {
    records <- history[[t[2L]]]
    if (is.null(records)) fail(paste("no history for",t[2L]))
    paid <- sum(vapply(records,function(r) r$total,integer(1L)))
    emit(paste("HISTORY",t[2L],"visits",length(records),"paid",paid))
    for (r in records) emit(paste0(paste(time_text(r$entry),time_text(r$exit),r$location,r$type,r$total),if (r$lost) " LOST" else ""))
  } else if (cmd=="REVENUE") {
    emit("REVENUE")
    total <- stats[[types[1L]]]*0L
    for (type in c(types,"TOTAL")) {
      s <- if (type=="TOTAL") total else stats[[type]]
      if (type!="TOTAL") total <- total+s
      emit(paste(type,"exits",s[["exits"]],"parking",s[["parking"]],"night",s[["night"]],"lost",s[["lost"]],"charge",s[["charge"]],"total",s[["total"]]))
    }
  } else if (cmd=="DAILY") {
    date <- as.integer(t[2L])
    rows <- daily[[as.character(date)]]
    if (is.null(rows)) rows <- setNames(lapply(types,function(k) c(entries=0L,exits=0L,refused=0L,revenue=0L)),types)
    total <- c(entries=0L,exits=0L,refused=0L,revenue=0L)
    lines <- character()
    for (type in types) {
      s <- rows[[type]]
      total <- total+s
      lines <- c(lines,paste(type,"entries",s[["entries"]],"exits",s[["exits"]],"refused",s[["refused"]],"revenue",s[["revenue"]]))
    }
    emit(paste("DAILY",date,"entries",total[["entries"]],"exits",total[["exits"]],"refused",total[["refused"]],"revenue",total[["revenue"]]))
    emit(lines)
  } else if (cmd=="STATS") {
    emit(paste("STATS parked",map_size(vehicles),"peak",peak,"at",if (peak==0L) "-" else time_text(peak_time)))
    total <- c(entries=0L,exits=0L,refused=0L,stay=0L)
    for (type in c(types,"ALL")) {
      s <- if (type=="ALL") total else stats[[type]][names(total)]
      if (type!="ALL") total <- total+s
      average <- if (s[["exits"]]==0L) 0L else (s[["stay"]]*10L)%/%s[["exits"]]
      emit(paste(type,"entries",s[["entries"]],"exits",s[["exits"]],"refused",s[["refused"]],"avg_stay",one_decimal(average)))
    }
  }
  if (cmd %in% c("LEVEL","OPEN","EXIT","MOVE","REBALANCE")) emit(process_queue())
  out
}
input <- file("stdin",open="r")
n <- as.integer(readLines(input,n=1L))
for (i in seq_len(n)) {
  tokens <- strsplit(readLines(input,n=1L)," ",fixed=TRUE)[[1L]]
  clock <- as.integer(strsplit(tokens[2L],":",fixed=TRUE)[[1L]])
  now <- (as.integer(tokens[1L])-1L)*1440L+clock[1L]*60L+clock[2L]
  prefix <- giveups()
  if (length(prefix)) cat(paste(prefix,collapse="\n"),"\n",sep="")
  out <- tryCatch(execute(tokens[-c(1L,2L)]),error=function(error) paste("ERROR",conditionMessage(error)))
  if (length(out)) cat(paste(out,collapse="\n"),"\n",sep="")
}
close(input)
