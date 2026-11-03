registry <- function() new.env(hash=TRUE,parent=emptyenv())
object <- function(...) list2env(list(...),parent=emptyenv())
courses <- registry()
players <- registry()
events <- registry()
event_order <- character()
fail <- function(message) stop(message,call.=FALSE)
fd <- function(a,b) {
  q <- floor(a/b)
  while (q*b>a) q <- q-1
  while ((q+1)*b<=a) q <- q+1
  q
}
half_up <- function(a,b) fd(2*a+b,2*b)
half_away <- function(a,b) (if (a<0) -1 else 1)*fd(2*abs(a)+b,2*b)
num <- function(v) sprintf("%d",as.integer(v))
text <- function(...) paste(vapply(list(...),function(v) if (is.numeric(v)) num(v) else as.character(v),character(1L)),collapse=" ")
tenths_text <- function(v) paste0(num(fd(abs(v),10)),".",num(abs(v)-fd(abs(v),10)*10))
index_text <- function(v) if (is.na(v)) "none" else paste0(if (v<0) "+" else "",tenths_text(v))
signed_text <- function(v) paste0(if (v<0) "-" else "",tenths_text(v))
handicap_text <- function(v) if (is.na(v)) "none" else if (v<0) paste0("+",num(-v)) else num(v)
hundredths <- function(v) paste0(num(fd(v,100)),".",sprintf("%02d",as.integer(v-fd(v,100)*100)))
mean_text <- function(total,n) if (n==0L) "-" else hundredths(fd(total*100,n))
status_text <- function(lead) if (lead==0) "AS" else text(abs(lead),if (lead>0) "UP" else "DN")
map_values <- function(map) lapply(ls(map,all.names=TRUE,sorted=FALSE),function(id) map[[id]])
get_player <- function(id) {
  p <- players[[id]]
  if (is.null(p)) fail("unknown player")
  p
}
get_course <- function(id) {
  c <- courses[[id]]
  if (is.null(c)) fail("unknown course")
  c
}
tee_check <- function(course,tee) {
  c <- get_course(course)
  rule <- c$tees[[tee]]
  if (is.null(rule)) fail("unknown tee")
  list(course=c,tee=rule)
}
course_handicap <- function(index,c,tee) half_up(index*tee[2L]+113*(tee[1L]-10*sum(c$pars)),1130)
allocate <- function(handicap,si) {
  q <- fd(abs(handicap),18)
  r <- abs(handicap)-18*q
  if (handicap>=0) q+as.numeric(si<=r) else -q-as.numeric(si>=19-r)
}
low_index <- function(p,day) {
  best <- NULL
  for (record in p$records) {
    if (record[1L]>=day-365 && record[1L]<day) {
      if (is.null(best) || record[2L]<best[2L] || (record[2L]==best[2L] && record[1L]<best[1L])) best <- record
    }
  }
  best
}
counting_rule <- function(n) {
  if (n<3L) return(c(0L,0L))
  if (n==3L) return(c(1L,-20L))
  if (n==4L) return(c(1L,-10L))
  if (n==5L) return(c(1L,0L))
  if (n==6L) return(c(2L,-10L))
  if (n<=8L) return(c(2L,0L))
  if (n<=11L) return(c(3L,0L))
  if (n<=14L) return(c(4L,0L))
  if (n<=16L) return(c(5L,0L))
  if (n<=18L) return(c(6L,0L))
  c(if (n==19L) 7L else 8L,0L)
}
eligible <- function(p) {
  if (!length(p$rounds)) return(list())
  result <- list()
  reduction <- 0
  indices <- seq.int(max(1L,length(p$rounds)-19L),length(p$rounds))
  for (i in rev(indices)) {
    r <- p$rounds[[i]]
    reduction <- reduction+r$exceptional
    result[[length(result)+1L]] <- list(number=i,round=r,adjusted=r$diff-reduction)
  }
  rev(result)
}
counting <- function(items) {
  k <- counting_rule(length(items))[1L]
  values <- vapply(items,function(item) item$adjusted,numeric(1L))
  numbers <- vapply(items,function(item) item$number,integer(1L))
  items[order(values,-numbers,method="radix")][seq_len(k)]
}
update_index <- function(p,day) {
  items <- eligible(p)
  rule <- counting_rule(length(items))
  k <- rule[1L]
  adjustment <- rule[2L]
  if (k==0L) {
    p$calculation <- NULL
    return(invisible(NULL))
  }
  total <- sum(vapply(counting(items),function(item) item$adjusted,numeric(1L)))
  average <- half_away(total,k)
  value <- average+adjustment
  low <- low_index(p,day)
  soft <- hard <- maximum <- FALSE
  if (!is.null(low)) {
    l <- low[2L]
    if (value-l>30) {
      new <- l+30+fd(value-l-30,2)
      soft <- new!=value
      value <- new
    }
    if (value-l>50) {
      value <- l+50
      hard <- TRUE
    }
  }
  if (value>540) {
    value <- 540
    maximum <- TRUE
  }
  p$index <- value
  p$calculation <- list(k=k,average=average,adjustment=adjustment,low=if (is.null(low)) NA_real_ else low[2L],hard=hard,soft=soft,maximum=maximum)
}
score_number <- function(score) if (score %in% c("X","-")) NA_real_ else as.numeric(score)
hole_values <- function(r,strokes,c) {
  nets <- vapply(r$scores,score_number,numeric(1L))-strokes
  points <- ifelse(is.na(nets),0,pmax(0,c$pars+2-nets))
  list(nets=nets,points=points)
}
countback <- function(values,larger=FALSE) vapply(c(1L,10L,13L,16L,18L),function(start) sum(values[start:18L])*(if (larger) -1 else 1),numeric(1L))
key_order <- function(ids,keys) {
  if (!length(ids)) return(ids)
  matrix <- do.call(rbind,keys)
  ids[order(matrix[,1L],matrix[,2L],matrix[,3L],matrix[,4L],matrix[,5L],ids,method="radix")]
}
event_context <- function(e) {
  checked <- tee_check(e$course,e$tee)
  c <- checked$course
  rounds <- ph <- list()
  for (id in e$players) {
    found <- NULL
    for (r in players[[id]]$rounds) {
      if (r$course==e$course && r$tee==e$tee && r$day==e$day) {
        found <- r
        break
      }
    }
    if (is.null(found)) fail("missing round")
    if (is.na(found$handicap)) fail("no index")
    rounds[[id]] <- found
    ph[[id]] <- half_up(found$handicap*e$allowance,100)
  }
  minimum <- if (e$format %in% c("MATCH","NASSAU","FOURBALL")) min(unlist(ph,use.names=FALSE)) else 0
  nets <- points <- list()
  for (id in e$players) {
    values <- hole_values(rounds[[id]],allocate(ph[[id]]-minimum,c$si),c)
    nets[[id]] <- values$nets
    points[[id]] <- values$points
  }
  list(course=c,rounds=rounds,ph=ph,minimum=minimum,nets=nets,points=points)
}
par_values <- function(nets,pars) ifelse(is.na(nets),-1,sign(pars-nets))
ranking <- function(e,ctx) {
  ranked <- character()
  keys <- list()
  for (id in e$players) {
    if (e$format=="STROKE") {
      values <- ctx$nets[[id]]
      if (anyNA(values)) next
    } else if (e$format=="STABLEFORD") {
      values <- ctx$points[[id]]
    } else {
      values <- par_values(ctx$nets[[id]],ctx$course$pars)
    }
    ranked <- c(ranked,id)
    keys[[length(keys)+1L]] <- countback(values,e$format!="STROKE")
  }
  key_order(ranked,keys)
}
play_match <- function(wins,names,first,last) {
  lead <- remaining <- 0
  statuses <- character()
  for (h in first:last) {
    lead <- lead+wins[h]
    statuses <- c(statuses,status_text(lead))
    remaining <- last-h
    if (abs(lead)>remaining) break
  }
  result <- "AS"
  if (lead!=0) {
    name <- names[if (lead>0) 1L else 2L]
    margin <- if (remaining>0) paste0(num(abs(lead)),"&",num(remaining)) else text(abs(lead),"UP")
    result <- text(name,margin)
  }
  list(statuses=statuses,result=result)
}
raw_scores <- function(r) vapply(r$scores,score_number,numeric(1L))
result_lines <- function(e) {
  ctx <- event_context(e)
  c <- ctx$course
  out <- text("results",paste0(e$id,":"),e$format,e$course,e$tee,"day",e$day,"allowance",e$allowance)
  if (e$format %in% c("STROKE","STABLEFORD","PAR")) {
    ranked <- ranking(e,ctx)
    for (rank in seq_along(ranked)) {
      id <- ranked[rank]
      if (e$format=="STROKE") {
        value <- text("net",sum(ctx$nets[[id]]),"gross",sum(raw_scores(ctx$rounds[[id]])))
      } else if (e$format=="STABLEFORD") {
        value <- text("points",sum(ctx$points[[id]]))
      } else {
        value <- status_text(sum(par_values(ctx$nets[[id]],c$pars)))
      }
      out <- c(out,text(rank,id,value,"hcp",handicap_text(ctx$ph[[id]])))
    }
    if (e$format=="STROKE") {
      nr <- sort(setdiff(e$players,ranked),method="radix")
      for (id in nr) out <- c(out,text("NR",id,"hcp",handicap_text(ctx$ph[[id]])))
      if (length(ranked)) {
        keys <- lapply(ranked,function(id) countback(raw_scores(ctx$rounds[[id]])))
        gross_order <- key_order(ranked,keys)
        id <- gross_order[1L]
        out <- c(out,text("gross",id,sum(raw_scores(ctx$rounds[[id]]))))
      }
    }
  } else if (e$format %in% c("MATCH","NASSAU","FOURBALL")) {
    side_size <- if (e$format=="FOURBALL") 2L else 1L
    sides <- list(e$players[seq_len(side_size)],e$players[side_size+seq_len(side_size)])
    names <- vapply(sides,function(ids) paste(ids,collapse="+"),character(1L))
    wins <- numeric(18L)
    for (h in 1:18) {
      scores <- vapply(sides,function(ids) {
        values <- vapply(ids,function(id) ctx$nets[[id]][h],numeric(1L))
        values <- values[!is.na(values)]
        if (length(values)) min(values) else NA_real_
      },numeric(1L))
      if (is.na(scores[1L])) {
        wins[h] <- if (is.na(scores[2L])) 0 else -1
      } else if (is.na(scores[2L])) {
        wins[h] <- 1
      } else {
        wins[h] <- sign(scores[2L]-scores[1L])
      }
    }
    parts <- "strokes"
    for (id in e$players) parts <- c(parts,id,num(ctx$ph[[id]]-ctx$minimum))
    out <- c(out,paste(parts,collapse=" "))
    if (e$format=="NASSAU") {
      for (range in list(list("front",1L,9L),list("back",10L,18L),list("total",1L,18L))) {
        result <- play_match(wins,names,range[[2L]],range[[3L]])
        out <- c(out,text(range[[1L]],result$result))
      }
    } else {
      result <- play_match(wins,names,1L,18L)
      out <- c(out,paste0("status ",paste(result$statuses,collapse=", ")),text("result",result$result))
    }
  } else if (e$format=="BETTERBALL") {
    teams <- list()
    ids <- character()
    keys <- list()
    for (i in seq.int(1L,length(e$players),by=2L)) {
      a <- e$players[i]
      b <- e$players[i+1L]
      values <- pmax(ctx$points[[a]],ctx$points[[b]])
      teams[[a]] <- list(a=a,b=b,values=values)
      ids <- c(ids,a)
      keys[[length(keys)+1L]] <- countback(values,TRUE)
    }
    ordered <- key_order(ids,keys)
    for (rank in seq_along(ordered)) {
      team <- teams[[ordered[rank]]]
      out <- c(out,text(rank,paste0(team$a,"+",team$b),"points",sum(team$values),"hcp",handicap_text(ctx$ph[[team$a]]),handicap_text(ctx$ph[[team$b]])))
    }
  } else {
    totals <- setNames(rep(0,length(e$players)),e$players)
    carry <- 0
    winners <- character()
    for (h in 1:18) {
      carry <- carry+1
      minimum <- NA_real_
      winners <- character()
      for (id in e$players) {
        net <- ctx$nets[[id]][h]
        if (is.na(net)) next
        if (is.na(minimum) || net<minimum) {
          minimum <- net
          winners <- id
        } else if (net==minimum) {
          winners <- c(winners,id)
        }
      }
      if (length(winners)==1L) {
        id <- winners[1L]
        totals[id] <- totals[id]+100*carry
        out <- c(out,text("hole",h,id,carry))
        carry <- 0
      }
    }
    if (carry>0) {
      if (!length(winners)) winners <- e$players
      winners <- sort(winners,method="radix")
      share <- fd(100*carry,length(winners))
      totals[winners] <- totals[winners]+share
      out <- c(out,paste(c("carry",num(carry),winners),collapse=" "))
    }
    ids <- e$players[order(-totals[e$players],e$players,method="radix")]
    for (id in ids) out <- c(out,text(id,hundredths(totals[[id]])))
  }
  out
}
execute <- function(line) {
  t <- strsplit(line," ",fixed=TRUE)[[1L]]
  cmd <- t[1L]
  out <- character()
  emit <- function(lines) out <<- c(out,lines)
  if (cmd=="COURSE") {
    if (!is.null(courses[[t[2L]]])) fail("duplicate course")
    pars <- as.numeric(t[3:20])
    si <- as.integer(t[21:38])
    if (!all(pars %in% c(3,4,5)) || !identical(sort(si),1:18)) fail("invalid course")
    courses[[t[2L]]] <- object(id=t[2L],pars=pars,si=si,tees=registry())
  } else if (cmd=="TEE") {
    c <- get_course(t[2L])
    if (!is.null(c$tees[[t[3L]]])) fail("duplicate tee")
    rating <- as.numeric(t[4L])
    slope <- as.numeric(t[5L])
    if (rating<500 || rating>900 || slope<55 || slope>155) fail("invalid tee")
    c$tees[[t[3L]]] <- c(rating,slope)
  } else if (cmd=="PLAYER") {
    if (!is.null(players[[t[2L]]])) fail("duplicate player")
    index <- if (length(t)==4L) as.numeric(t[4L]) else NA_real_
    if (!is.na(index) && (index < -100 || index>540)) fail("invalid index")
    players[[t[2L]]] <- object(id=t[2L],name=t[3L],index=index,rounds=list(),records=list(),calculation=NULL)
  } else if (cmd=="ROUND") {
    p <- get_player(t[2L])
    checked <- tee_check(t[3L],t[4L])
    c <- checked$course
    tee <- checked$tee
    day <- as.numeric(t[5L])
    if (length(p$rounds) && day<p$rounds[[length(p$rounds)]]$day) fail("invalid day")
    scores <- t[6:length(t)]
    if (sum(scores=="-")>=5L) fail("too few holes")
    hcp <- if (is.na(p$index)) NA_real_ else course_handicap(p$index,c,tee)
    strokes <- allocate(if (is.na(hcp)) 0 else hcp,c$si)
    limits <- c$pars + (if (is.na(p$index)) 5 else 2+strokes)
    raw <- vapply(scores,score_number,numeric(1L))
    adjusted <- pmin(raw,limits)
    adjusted[scores=="X"] <- limits[scores=="X"]
    adjusted[scores=="-"] <- (c$pars+strokes)[scores=="-"]
    ags <- sum(adjusted)
    diff <- half_away(113*(10*ags-tee[1L]),tee[2L])
    exceptional <- 0
    if (!is.na(p$index) && p$index-diff>=70) exceptional <- if (p$index-diff>=100) 20 else 10
    r <- list(day=day,course=c$id,tee=t[4L],scores=scores,handicap=hcp,adjusted=adjusted,ags=ags,diff=diff,exceptional=exceptional,
              before_index=p$index,before_records=length(p$records),before_calculation=p$calculation)
    p$rounds[[length(p$rounds)+1L]] <- r
    update_index(p,day)
    if (!is.na(p$index)) p$records[[length(p$records)+1L]] <- c(day,p$index)
    value <- text("round",p$id,paste0(length(p$rounds),":"),"ags",ags,"diff",signed_text(diff))
    if (exceptional!=0) value <- text(value,"exceptional",signed_text(-exceptional))
    emit(text(value,"index",index_text(p$index)))
  } else if (cmd=="REMOVE") {
    p <- get_player(t[2L])
    if (!length(p$rounds)) fail("no rounds")
    number <- length(p$rounds)
    r <- p$rounds[[number]]
    p$rounds <- p$rounds[-number]
    p$index <- r$before_index
    p$records <- p$records[seq_len(r$before_records)]
    p$calculation <- r$before_calculation
    emit(text("removed",p$id,paste0(number,":"),"index",index_text(p$index)))
  } else if (cmd %in% c("INDEX","HISTORY","LOWINDEX","COURSEHCP","CARD","STATS")) {
    p <- get_player(t[2L])
    if (cmd=="INDEX") {
      value <- text("index",paste0(p$id,":"),index_text(p$index),"rounds",length(p$rounds))
      calc <- p$calculation
      if (!is.null(calc)) {
        value <- text(value,"lowest",calc$k,"average",signed_text(calc$average),"adjustment",signed_text(calc$adjustment))
        if (!is.na(calc$low)) value <- text(value,"low",index_text(calc$low))
        if (calc$hard) value <- text(value,"hard cap") else if (calc$soft) value <- text(value,"soft cap")
        if (calc$maximum) value <- text(value,"maximum")
      }
      emit(value)
    } else if (cmd=="HISTORY") {
      emit(text("history",paste0(p$id,":"),"rounds",length(p$rounds)))
      items <- eligible(p)
      counted <- vapply(counting(items),function(item) item$number,integer(1L))
      for (item in items) {
        r <- item$round
        value <- text(item$number,"day",r$day,r$course,r$tee,"ags",r$ags,"diff",signed_text(r$diff))
        if (item$adjusted!=r$diff) value <- text(value,"adjusted",signed_text(item$adjusted))
        if (item$number %in% counted) value <- text(value,"*")
        emit(value)
      }
    } else if (cmd=="LOWINDEX") {
      low <- low_index(p,as.numeric(t[3L]))
      value <- if (is.null(low)) "none" else text(index_text(low[2L]),"day",low[1L])
      emit(text("lowindex",p$id,paste0(t[3L],":"),value))
    } else if (cmd=="COURSEHCP") {
      checked <- tee_check(t[3L],t[4L])
      c <- checked$course
      if (is.na(p$index)) fail("no index")
      hcp <- course_handicap(p$index,c,checked$tee)
      emit(paste(c("coursehcp",p$id,c$id,paste0(t[4L],":"),handicap_text(hcp),"strokes",vapply(allocate(hcp,c$si),num,character(1L))),collapse=" "))
    } else if (cmd=="CARD") {
      number <- as.integer(t[3L])
      if (number>length(p$rounds)) fail("unknown round")
      r <- p$rounds[[number]]
      c <- courses[[r$course]]
      strokes <- allocate(if (is.na(r$handicap)) 0 else r$handicap,c$si)
      values <- hole_values(r,strokes,c)
      nets <- values$nets
      points <- values$points
      emit(text("card",p$id,paste0(number,":"),r$course,r$tee,"day",r$day,"handicap",handicap_text(r$handicap)))
      for (h in 1:18) {
        emit(text(h,c$pars[h],c$si[h],r$scores[h],r$adjusted[h],strokes[h],if (is.na(nets[h])) "-" else num(nets[h]),points[h]))
        if (h==9L) {
          ranges <- list(list("OUT",1:9))
        } else if (h==18L) {
          ranges <- list(list("IN",10:18),list("TOTAL",1:18))
        } else {
          ranges <- list()
        }
        for (range in ranges) {
          indices <- range[[2L]]
          complete <- !anyNA(nets[indices])
          raw <- if (complete) num(sum(raw_scores(r)[indices])) else "-"
          net <- if (complete) num(sum(nets[indices])) else "-"
          emit(text(range[[1L]],sum(c$pars[indices]),raw,sum(r$adjusted[indices]),sum(strokes[indices]),net,sum(points[indices])))
        }
      }
      emit(text("ags",r$ags,"diff",signed_text(r$diff)))
    } else {
      counts <- c(eagles=0L,birdies=0L,pars=0L,bogeys=0L,doubles=0L,others=0L,pickups=0L)
      sums <- numbers <- setNames(rep(0,3L),c("3","4","5"))
      totals <- numeric()
      for (r in p$rounds) {
        c <- courses[[r$course]]
        total <- 0
        complete <- TRUE
        for (h in 1:18) {
          value <- score_number(r$scores[h])
          if (is.na(value)) {
            complete <- FALSE
            if (r$scores[h]=="X") counts["pickups"] <- counts["pickups"]+1L
            next
          }
          par <- c$pars[h]
          relative <- value-par
          if (relative<=-2) {
            category <- "eagles"
          } else if (relative== -1) {
            category <- "birdies"
          } else if (relative==0) {
            category <- "pars"
          } else if (relative==1) {
            category <- "bogeys"
          } else if (relative==2) {
            category <- "doubles"
          } else {
            category <- "others"
          }
          counts[category] <- counts[category]+1L
          key <- as.character(par)
          sums[key] <- sums[key]+value
          numbers[key] <- numbers[key]+1
          total <- total+value
        }
        if (complete) totals <- c(totals,total)
      }
      best <- if (!length(totals)) "-" else num(min(totals))
      emit(text("stats",paste0(p$id,":"),"rounds",length(p$rounds),"best",best,"average",mean_text(sum(totals),length(totals)),
                "eagles",counts[["eagles"]],"birdies",counts[["birdies"]],"pars",counts[["pars"]],"bogeys",counts[["bogeys"]],"doubles",counts[["doubles"]],"others",counts[["others"]],"pickups",counts[["pickups"]],
                "par3",mean_text(sums[["3"]],numbers[["3"]]),"par4",mean_text(sums[["4"]],numbers[["4"]]),"par5",mean_text(sums[["5"]],numbers[["5"]])))
    }
  } else if (cmd=="HCPTABLE") {
    checked <- tee_check(t[2L],t[3L])
    c <- checked$course
    tee <- checked$tee
    first <- as.numeric(t[4L])
    last <- as.numeric(t[5L])
    if (first < -100 || first>last || last>540) fail("invalid index")
    emit(text("hcptable",c$id,paste0(t[3L],":"),index_text(first),"to",index_text(last)))
    start <- first
    hcp <- course_handicap(first,c,tee)
    for (i in seq.int(first+1,last+1)) {
      next_hcp <- if (i<=last) course_handicap(i,c,tee) else NA_real_
      if (is.na(next_hcp) || next_hcp!=hcp) {
        emit(text(index_text(start),"to",paste0(index_text(i-1),":"),handicap_text(hcp)))
        start <- i
        hcp <- next_hcp
      }
    }
  } else if (cmd=="HOLESTATS") {
    c <- get_course(t[2L])
    sums <- numbers <- numeric(18L)
    rounds <- 0L
    for (p in map_values(players)) {
      for (r in p$rounds) {
        if (r$course!=c$id) next
        rounds <- rounds+1L
        scores <- raw_scores(r)
        valid <- !is.na(scores)
        sums[valid] <- sums[valid]+scores[valid]
        numbers[valid] <- numbers[valid]+1
      }
    }
    harder <- function(a,b) {
      if (numbers[a]==0 || numbers[b]==0) {
        if ((numbers[a]==0)!=(numbers[b]==0)) return(numbers[a]!=0)
        return(a<b)
      }
      left <- (sums[a]-c$pars[a]*numbers[a])*numbers[b]
      right <- (sums[b]-c$pars[b]*numbers[b])*numbers[a]
      if (left==right) a<b else left>right
    }
    holes <- integer()
    for (h in 1:18) {
      position <- length(holes)+1L
      for (i in seq_along(holes)) {
        if (harder(h,holes[i])) {
          position <- i
          break
        }
      }
      holes <- append(holes,h,after=position-1L)
    }
    ranks <- integer(18L)
    ranks[holes] <- 1:18
    emit(text("holestats",paste0(c$id,":"),"rounds",rounds))
    for (h in 1:18) emit(text(h,"par",c$pars[h],"si",c$si[h],"scores",numbers[h],"avg",mean_text(sums[h],numbers[h]),"rank",ranks[h]))
  } else if (cmd=="PLAYERS") {
    all <- map_values(players)
    ids <- vapply(all,function(p) p$id,character(1L))
    indices <- vapply(all,function(p) p$index,numeric(1L))
    all <- all[order(is.na(indices),ifelse(is.na(indices),0,indices),ids,method="radix")]
    emit(text("players",length(all)))
    for (p in all) emit(text(p$id,p$name,index_text(p$index),"rounds",length(p$rounds)))
  } else if (cmd=="EVENT") {
    if (!is.null(events[[t[2L]]])) fail("duplicate event")
    tee_check(t[4L],t[5L])
    allowance <- as.numeric(t[7L])
    if (allowance<1 || allowance>100) fail("invalid allowance")
    ids <- t[8:length(t)]
    for (id in ids) get_player(id)
    n <- length(ids)
    if (t[3L] %in% c("MATCH","NASSAU")) {
      valid <- n==2L
    } else if (t[3L]=="FOURBALL") {
      valid <- n==4L
    } else if (t[3L]=="BETTERBALL") {
      valid <- n %in% c(4L,6L,8L)
    } else {
      valid <- n>=2L && n<=8L
    }
    if (!valid || anyDuplicated(ids)) fail("invalid players")
    events[[t[2L]]] <- list(id=t[2L],format=t[3L],course=t[4L],tee=t[5L],day=as.numeric(t[6L]),allowance=allowance,players=ids)
    event_order <<- c(event_order,t[2L])
  } else if (cmd=="RESULTS") {
    e <- events[[t[2L]]]
    if (is.null(e)) fail("unknown event")
    out <- result_lines(e)
  } else if (cmd=="MERIT") {
    totals <- registry()
    counted <- 0L
    for (id in event_order) {
      e <- events[[id]]
      if (!(e$format %in% c("STROKE","STABLEFORD","PAR"))) next
      ctx <- tryCatch(event_context(e),error=function(error) NULL)
      if (is.null(ctx)) next
      counted <- counted+1L
      for (player in e$players) {
        record <- totals[[player]]
        if (is.null(record)) record <- c(0L,0L,0L)
        record[3L] <- record[3L]+1L
        totals[[player]] <- record
      }
      ranked <- ranking(e,ctx)
      for (rank in seq_along(ranked)) {
        player <- ranked[rank]
        record <- totals[[player]]
        record[1L] <- record[1L]+c(10L,8L,6L,5L,4L,3L,2L,1L)[rank]
        if (rank==1L) record[2L] <- record[2L]+1L
        totals[[player]] <- record
      }
    }
    ids <- ls(totals,all.names=TRUE,sorted=FALSE)
    points <- vapply(ids,function(id) totals[[id]][1L],integer(1L))
    wins <- vapply(ids,function(id) totals[[id]][2L],integer(1L))
    ids <- ids[order(-points,-wins,ids,method="radix")]
    emit(text("merit: events",counted))
    for (rank in seq_along(ids)) {
      id <- ids[rank]
      record <- totals[[id]]
      emit(text(rank,id,record[1L],"wins",record[2L],"played",record[3L]))
    }
  }
  out
}
input <- file("stdin",open="r")
n <- as.integer(readLines(input,n=1L))
for (i in seq_len(n)) {
  line <- readLines(input,n=1L)
  out <- tryCatch(execute(line),error=function(error) paste("ERROR",conditionMessage(error)))
  if (length(out)) cat(paste(out,collapse="\n"),"\n",sep="")
}
close(input)
