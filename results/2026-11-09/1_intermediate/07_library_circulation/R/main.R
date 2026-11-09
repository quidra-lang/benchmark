rules <- list(STUDENT=c(3L,14L,25L,1000L,2L,50L), STAFF=c(10L,28L,10L,2000L,5L,100L))
object <- function(...) list2env(list(...),parent=emptyenv())
registry <- function() new.env(hash=TRUE,parent=emptyenv())
books <- registry()
members <- registry()
book_order <- member_order <- character()
closed <- integer()
day <- 1L
counts <- setNames(as.list(rep(0L,9L)),c("borrowed","returned","renewed","lost","FINE","FEE","PRICE","paid","waived"))
fail <- function(message) stop(message,call.=FALSE)
cents <- function(text) {
  parts <- strsplit(text,".",fixed=TRUE)[[1L]]
  as.integer(parts[1L])*100L+as.integer(parts[2L])
}
money <- function(v) sprintf("%d.%02d",as.integer(v%/%100L),as.integer(v%%100L))
isbn <- function(text) {
  s <- gsub("-","",text,fixed=TRUE)
  digits <- strsplit(s,"",fixed=TRUE)[[1L]]
  if (grepl("^[0-9]{9}[0-9X]$",s,perl=TRUE)) {
    values <- vapply(digits,function(char) if (char=="X") 10L else as.integer(char),integer(1L))
    if (sum((10:1)*values)%%11L!=0L) fail("invalid isbn")
    s <- paste0("978",substr(s,1L,9L))
    values <- as.integer(strsplit(s,"",fixed=TRUE)[[1L]])
    total <- sum(values*rep(c(1L,3L),6L))
    return(paste0(s,(10L-total%%10L)%%10L))
  }
  if (grepl("^97[89][0-9]{10}$",s,perl=TRUE)) {
    total <- sum(as.integer(digits)*rep(c(1L,3L),length.out=13L))
    if (total%%10L==0L) return(s)
  }
  fail("invalid isbn")
}
get_member <- function(id) {
  m <- members[[id]]
  if (is.null(m)) fail("unknown member")
  m
}
get_book <- function(text) {
  id <- isbn(text)
  b <- books[[id]]
  if (is.null(b)) fail("unknown book")
  b
}
map_values <- function(map) lapply(ls(map,all.names=TRUE),function(key) map[[key]])
balance <- function(m) sum(vapply(m$items,function(item) item$unpaid,integer(1L)))
holdings <- function(b) sum(vapply(b$copies,function(c) c$state %in% c("AVAILABLE","LOANED","HOLD"),logical(1L)))
reservations <- function(m) {
  length(ls(m$holds,all.names=TRUE)) + sum(vapply(book_order,
    function(id) m$id %in% books[[id]]$queue, logical(1L)))
}
open_day <- function(date) {
  while (date %in% closed) date <- date+1L
  date
}
late_fine <- function(c) {
  m <- members[[c$member]]
  late <- max(0L,day-c$due)
  c(late,min(late*rules[[m$type]][3L],rules[[m$type]][4L]))
}
charge <- function(m,kind,id,amount) {
  if (amount==0L) return(invisible(NULL))
  m$items[[length(m$items)+1L]] <- object(day=day,kind=kind,isbn=id,amount=amount,unpaid=amount)
  counts[[kind]] <<- counts[[kind]]+amount
}
release_copy <- function(b,c) {
  if (!length(b$queue)) {
    c$state <- "AVAILABLE"
    return(character())
  }
  id <- b$queue[1L]
  b$queue <- b$queue[-1L]
  c$state <- "HOLD"
  c$member <- id
  c$expiry <- open_day(day+3L)
  m <- members[[id]]
  m$holds[[b$id]] <- c
  paste("HOLD",b$id,"copy",c$number,id,"until",c$expiry)
}
end_loan <- function(b,c,result) {
  m <- members[[c$member]]
  fine <- late_fine(c)
  rm(list=b$id,envir=m$loans)
  charge(m,"FINE",b$id,fine[2L])
  m$history <- c(m$history,paste(result,b$id,"copy",c$number,"from",c$start,"to",day,"late",fine[1L],"fine",money(fine[2L])))
  list(member=m,late=fine[1L],fine=fine[2L])
}
lose_copy <- function(b,c,heading) {
  ended <- end_loan(b,c,"LOST")
  m <- ended$member
  last <- length(m$history)
  m$history[last] <- paste(m$history[last],"price",money(b$price))
  charge(m,"PRICE",b$id,b$price)
  c$state <- "LOST"
  counts$lost <<- counts$lost+1L
  out <- paste(heading,m$id,b$id,"copy",c$number,"late",ended$late,"fine",money(ended$fine),"price",money(b$price),"balance",money(balance(m)))
  if (holdings(b)==0L) {
    for (id in b$queue) out <- c(out,paste("DROPPED",b$id,id))
    b$queue <- character()
  }
  out
}
renewal_reason <- function(b,c) {
  if (c$due<day) return("loan overdue")
  if (c$renewals==2L) return("renewal limit")
  if (length(b$queue)) "title reserved" else ""
}
renew_loan <- function(m,b,c) {
  c$due <- open_day(day+rules[[m$type]][2L])
  c$renewals <- c$renewals+1L
  counts$renewed <<- counts$renewed+1L
  paste("RENEW",m$id,b$id,"copy",c$number,"due",c$due,"renewals",c$renewals)
}
sorted_copies <- function(map,date) {
  copies <- map_values(map)
  dates <- vapply(copies,function(c) c[[date]],integer(1L))
  ids <- vapply(copies,function(c) c$isbn,character(1L))
  copies[order(dates,ids,method="radix")]
}
execute <- function(line) {
  t <- strsplit(line," ",fixed=TRUE)[[1L]]
  cmd <- t[1L]
  out <- character()
  emit <- function(lines) out <<- c(out,lines)
  if (cmd=="DAY") {
    target <- as.integer(t[2L])
    if (target<=day) fail("invalid day")
    emit(paste("DAY",target))
    while (day<target) {
      next_day <- target+1L
      for (id in member_order) {
        m <- members[[id]]
        for (c in map_values(m$loans)) next_day <- min(next_day,c$due+365L)
        for (c in map_values(m$holds)) next_day <- min(next_day,c$expiry+1L)
      }
      if (next_day>target) {
        day <<- target
        break
      }
      day <<- next_day
      losses <- list()
      for (id in member_order) {
        m <- members[[id]]
        for (key in sort(ls(m$loans,all.names=TRUE),method="radix")) {
          c <- m$loans[[key]]
          if (c$due+365L<=day) losses[[length(losses)+1L]] <- c
        }
      }
      for (c in losses) emit(lose_copy(books[[c$isbn]],c,"AUTOLOST"))
      expired <- list()
      for (id in book_order) {
        for (c in books[[id]]$copies) {
          if (c$state=="HOLD" && c$expiry<day) expired[[length(expired)+1L]] <- c
        }
      }
      for (c in expired) {
        b <- books[[c$isbn]]
        m <- members[[c$member]]
        fee <- rules[[m$type]][6L]
        charge(m,"FEE",b$id,fee)
        rm(list=b$id,envir=m$holds)
        emit(paste("EXPIRED",b$id,"copy",c$number,m$id,"fee",money(fee)))
        emit(release_copy(b,c))
      }
    }
  } else if (cmd=="CLOSED") {
    date <- as.integer(t[2L])
    if (date<=day) fail("invalid day")
    if (date %in% closed) fail("already closed")
    closed <<- c(closed,date)
    emit(paste("CLOSED",date))
    for (id in book_order) {
      for (c in books[[id]]$copies) {
        if (c$state=="LOANED" && c$due==date) {
          c$due <- open_day(date)
          emit(paste("MOVED",id,"copy",c$number,c$member,"due",c$due))
        } else if (c$state=="HOLD" && c$expiry==date) {
          c$expiry <- open_day(date)
          emit(paste("MOVED",id,"copy",c$number,c$member,"until",c$expiry))
        }
      }
    }
  } else if (cmd=="ADDBOOK") {
    id <- isbn(t[2L])
    name <- paste(t[5:length(t)],collapse=" ")
    b <- books[[id]]
    if (!is.null(b) && b$name!=name) fail("title mismatch")
    if (is.null(b)) {
      b <- object(id=id,name=name,price=0L,copies=list(),queue=character(),borrowed=0L)
      books[[id]] <- b
      book_order <<- sort(c(book_order,id),method="radix")
    }
    b$price <- cents(t[4L])
    added <- list()
    for (i in seq_len(as.integer(t[3L]))) {
      c <- object(isbn=id,number=length(b$copies)+1L,state="AVAILABLE",member="",start=0L,due=0L,renewals=0L,expiry=0L)
      b$copies[[length(b$copies)+1L]] <- c
      added[[length(added)+1L]] <- c
    }
    emit(paste("ADDBOOK",id,"added",t[3L],"total",holdings(b)))
    for (c in added) emit(release_copy(b,c))
  } else if (cmd=="ADDMEMBER") {
    if (!is.null(members[[t[2L]]])) fail("duplicate member")
    if (is.null(rules[[t[3L]]])) fail("unknown type")
    m <- object(id=t[2L],type=t[3L],name=paste(t[4:length(t)],collapse=" "),loans=registry(),holds=registry(),items=list(),history=character())
    members[[m$id]] <- m
    member_order <<- sort(c(member_order,m$id),method="radix")
    rule <- rules[[m$type]]
    emit(paste("ADDMEMBER",m$id,m$type,"loans",rule[1L],"days",rule[2L]))
  } else if (cmd %in% c("BORROW","RETURN","RENEW","RESERVE","CANCEL","LOST")) {
    m <- get_member(t[2L])
    b <- get_book(t[3L])
    id <- b$id
    loan <- m$loans[[id]]
    hold <- m$holds[[id]]
    rule <- rules[[m$type]]
    if (cmd=="BORROW") {
      if (day %in% closed) fail("library closed")
      if (!is.null(loan)) fail("already borrowed")
      if (balance(m)>500L) fail("member blocked")
      for (c in map_values(m$loans)) if (c$due<day) fail("overdue loans")
      if (length(ls(m$loans,all.names=TRUE))>=rule[1L]) fail("loan limit")
      chosen <- hold
      if (is.null(chosen)) {
        for (c in b$copies) {
          if (c$state=="AVAILABLE") {
            chosen <- c
            break
          }
        }
      }
      if (is.null(chosen)) {
        for (c in b$copies) if (c$state=="HOLD") fail("all copies on hold")
        fail("no copy available")
      }
      if (!is.null(hold)) rm(list=id,envir=m$holds)
      chosen$state <- "LOANED"
      chosen$member <- m$id
      chosen$start <- day
      chosen$due <- open_day(day+rule[2L])
      chosen$renewals <- 0L
      m$loans[[id]] <- chosen
      b$borrowed <- b$borrowed+1L
      counts$borrowed <<- counts$borrowed+1L
      emit(paste("BORROW",m$id,id,"copy",chosen$number,"due",chosen$due))
    } else if (cmd %in% c("RETURN","RENEW","LOST")) {
      if (is.null(loan)) fail("not borrowed")
      if (cmd=="RETURN") {
        ended <- end_loan(b,loan,"RETURNED")
        counts$returned <<- counts$returned+1L
        emit(paste("RETURN",m$id,id,"copy",loan$number,"late",ended$late,"fine",money(ended$fine),"balance",money(balance(m))))
        emit(release_copy(b,loan))
      } else if (cmd=="LOST") {
        emit(lose_copy(b,loan,"LOST"))
      } else {
        if (balance(m)>500L) fail("member blocked")
        reason <- renewal_reason(b,loan)
        if (reason!="") fail(reason)
        emit(renew_loan(m,b,loan))
      }
    } else if (cmd=="RESERVE") {
      if (!is.null(loan)) fail("already borrowed")
      if (!is.null(hold) || m$id %in% b$queue) fail("already reserved")
      if (balance(m)>500L) fail("member blocked")
      if (reservations(m)>=rule[5L]) fail("reservation limit")
      if (holdings(b)==0L) fail("no copies")
      for (c in b$copies) if (c$state=="AVAILABLE") fail("copy available")
      b$queue <- c(b$queue,m$id)
      position <- length(b$queue)
      dues <- sort(vapply(Filter(function(c) c$state=="LOANED",b$copies),function(c) c$due,integer(1L)))
      estimate <- if (position<=length(dues)) as.character(dues[position]) else "none"
      emit(paste("RESERVE",m$id,id,"position",position,"estimate",estimate))
    } else {
      position <- match(m$id,b$queue)
      if (is.na(position) && is.null(hold)) fail("not reserved")
      if (!is.na(position)) {
        b$queue <- b$queue[-position]
        emit(paste("CANCEL",m$id,id,"queue"))
      } else {
        rm(list=id,envir=m$holds)
        emit(paste("CANCEL",m$id,id,"hold copy",hold$number))
        emit(release_copy(b,hold))
      }
    }
  } else if (cmd %in% c("RENEWALL","PAYFINE","WAIVE","FINES","MEMBER","HISTORY")) {
    m <- get_member(t[2L])
    if (cmd=="RENEWALL") {
      ids <- sort(ls(m$loans,all.names=TRUE),method="radix")
      if (!length(ids)) fail("no loans")
      if (balance(m)>500L) fail("member blocked")
      renewed <- skipped <- 0L
      for (id in ids) {
        reason <- renewal_reason(books[[id]],m$loans[[id]])
        if (reason=="") {
          emit(renew_loan(m,books[[id]],m$loans[[id]]))
          renewed <- renewed+1L
        } else {
          emit(paste("SKIP",id,reason))
          skipped <- skipped+1L
        }
      }
      emit(paste("RENEWALL",m$id,"renewed",renewed,"skipped",skipped))
    } else if (cmd=="PAYFINE") {
      if (balance(m)==0L) fail("no fines")
      remaining <- cents(t[3L])
      paid <- 0L
      lines <- character()
      for (index in seq_along(m$items)) {
        item <- m$items[[index]]
        applied <- min(remaining,item$unpaid)
        if (applied>0L) {
          item$unpaid <- item$unpaid-applied
          remaining <- remaining-applied
          paid <- paid+applied
          lines <- c(lines,paste("ITEM",index,item$kind,"paid",money(applied),"remaining",money(item$unpaid)))
        }
      }
      counts$paid <<- counts$paid+paid
      emit(paste("PAYFINE",m$id,"paid",money(paid),"change",money(remaining),"balance",money(balance(m))))
      emit(lines)
    } else if (cmd=="WAIVE") {
      index <- as.integer(t[3L])
      if (index<1L || index>length(m$items)) fail("unknown item")
      item <- m$items[[index]]
      if (item$unpaid==0L) fail("item settled")
      amount <- item$unpaid
      item$unpaid <- 0L
      counts$waived <<- counts$waived+amount
      emit(paste("WAIVE",m$id,"item",index,item$kind,"amount",money(amount),"balance",money(balance(m))))
    } else if (cmd=="FINES") {
      n <- sum(vapply(m$items,function(item) item$unpaid>0L,logical(1L)))
      emit(paste("FINES",m$id,"items",n,"balance",money(balance(m))))
      for (index in seq_along(m$items)) {
        item <- m$items[[index]]
        if (item$unpaid>0L) emit(paste(index,"day",item$day,item$kind,item$isbn,"amount",money(item$amount),"remaining",money(item$unpaid)))
      }
    } else if (cmd=="HISTORY") {
      emit(paste("HISTORY",m$id,length(m$history)))
      emit(m$history)
    } else {
      rule <- rules[[m$type]]
      state <- if (balance(m)>500L) "BLOCKED" else "OK"
      emit(paste("MEMBER",m$id,m$type,m$name))
      emit(paste("STATUS loans",paste0(length(ls(m$loans,all.names=TRUE)),"/",rule[1L]),"reservations",paste0(reservations(m),"/",rule[5L]),"balance",money(balance(m)),state))
      for (c in sorted_copies(m$loans,"due")) {
        text <- paste("LOAN",c$isbn,"copy",c$number,"due",c$due,"renewals",c$renewals)
        if (c$due<day) {
          fine <- late_fine(c)
          text <- paste(text,"late",fine[1L],"fine",money(fine[2L]))
        }
        emit(text)
      }
      for (c in sorted_copies(m$holds,"expiry")) emit(paste("HOLD",c$isbn,"copy",c$number,"until",c$expiry))
      for (id in book_order) {
        position <- match(m$id,books[[id]]$queue)
        if (!is.na(position)) emit(paste("QUEUE",id,"position",position))
      }
    }
  } else if (cmd %in% c("WITHDRAW","BOOK")) {
    b <- get_book(t[2L])
    if (cmd=="WITHDRAW") {
      index <- as.integer(t[3L])
      if (index<1L || index>length(b$copies)) fail("unknown copy")
      c <- b$copies[[index]]
      if (c$state!="AVAILABLE") fail("copy not available")
      c$state <- "WITHDRAWN"
      emit(paste("WITHDRAW",b$id,"copy",c$number,"total",holdings(b)))
    } else {
      emit(paste("BOOK",b$id,b$name))
      emit(paste("PRICE",money(b$price),"copies",holdings(b),"borrowed",b$borrowed))
      for (c in b$copies) {
        text <- paste("COPY",c$number,c$state)
        if (c$state=="LOANED") text <- paste(text,c$member,"due",c$due) else if (c$state=="HOLD") text <- paste(text,c$member,"until",c$expiry)
        emit(text)
      }
      emit(paste(c("QUEUE",length(b$queue),b$queue),collapse=" "))
    }
  } else if (cmd=="SEARCH") {
    keyword <- chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ","abcdefghijklmnopqrstuvwxyz",paste(t[-1L],collapse=" "))
    lower <- function(text) chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ","abcdefghijklmnopqrstuvwxyz",text)
    found <- Filter(function(b) grepl(keyword,lower(b$name),fixed=TRUE),map_values(books))
    names <- vapply(found,function(b) lower(b$name),character(1L))
    ids <- vapply(found,function(b) b$id,character(1L))
    found <- found[order(names,ids,method="radix")]
    emit(paste("SEARCH",length(found)))
    for (b in found) {
      available <- sum(vapply(b$copies,function(c) c$state=="AVAILABLE",logical(1L)))
      emit(paste(b$id,paste0(available,"/",holdings(b)),b$name))
    }
  } else if (cmd %in% c("OVERDUE","NOTICES")) {
    lines <- character()
    if (cmd=="OVERDUE") {
      loans <- list()
      for (id in member_order) {
        for (c in map_values(members[[id]]$loans)) if (c$due<day) loans[[length(loans)+1L]] <- c
      }
      dues <- vapply(loans,function(c) c$due,integer(1L))
      mids <- vapply(loans,function(c) c$member,character(1L))
      ids <- vapply(loans,function(c) c$isbn,character(1L))
      loans <- loans[order(dues,mids,ids,method="radix")]
      for (c in loans) {
        fine <- late_fine(c)
        lines <- c(lines,paste(c$member,c$isbn,"copy",c$number,"due",c$due,"late",fine[1L],"fine",money(fine[2L])))
      }
    } else {
      for (id in member_order) {
        m <- members[[id]]
        loans <- sorted_copies(m$loans,"due")
        for (c in loans) if (c$due<day) lines <- c(lines,paste("OVERDUE",id,c$isbn,"due",c$due))
        for (c in loans) if (c$due>=day && c$due<=day+2L) lines <- c(lines,paste("DUESOON",id,c$isbn,"due",c$due))
        for (c in sorted_copies(m$holds,"expiry")) lines <- c(lines,paste("PICKUP",id,c$isbn,"until",c$expiry))
      }
    }
    emit(paste(cmd,length(lines)))
    emit(lines)
  } else if (cmd=="MEMBERS") {
    emit(paste("MEMBERS",length(member_order)))
    for (id in member_order) {
      m <- members[[id]]
      state <- if (balance(m)>500L) "BLOCKED" else "OK"
      emit(paste(id,m$type,"loans",length(ls(m$loans,all.names=TRUE)),"reservations",reservations(m),"balance",money(balance(m)),state))
    }
  } else if (cmd=="INVENTORY") {
    totals <- setNames(rep(0L,5L),c("AVAILABLE","LOANED","HOLD","LOST","WITHDRAWN"))
    lines <- character()
    for (id in book_order) {
      b <- books[[id]]
      states <- vapply(b$copies, function(c) c$state, character(1L))
      n <- setNames(as.integer(table(factor(states, levels = names(totals)))), names(totals))
      totals <- totals+n
      lines <- c(lines,paste(id,"copies",holdings(b),"available",n[["AVAILABLE"]],"loaned",n[["LOANED"]],"hold",n[["HOLD"]],"queue",length(b$queue)))
    }
    holding <- totals[["AVAILABLE"]]+totals[["LOANED"]]+totals[["HOLD"]]
    emit(paste("INVENTORY titles",length(book_order),"copies",holding,"available",totals[["AVAILABLE"]],"loaned",totals[["LOANED"]],"hold",totals[["HOLD"]],"lost",totals[["LOST"]],"withdrawn",totals[["WITHDRAWN"]]))
    emit(lines)
  } else if (cmd=="STATS") {
    active <- outstanding <- 0L
    for (id in member_order) {
      active <- active+length(ls(members[[id]]$loans,all.names=TRUE))
      outstanding <- outstanding+balance(members[[id]])
    }
    emit(paste("STATS day",day,"titles",length(book_order),"members",length(member_order),"closed",length(closed)))
    emit(paste("LOANS borrowed",counts$borrowed,"returned",counts$returned,"renewed",counts$renewed,"lost",counts$lost,"active",active))
    emit(paste("MONEY fines",money(counts$FINE),"fees",money(counts$FEE),"charges",money(counts$PRICE),"paid",money(counts$paid),"waived",money(counts$waived),"outstanding",money(outstanding)))
    top <- Filter(function(b) b$borrowed>0L,map_values(books))
    totals <- vapply(top,function(b) b$borrowed,integer(1L))
    ids <- vapply(top,function(b) b$id,character(1L))
    top <- top[order(-totals,ids,method="radix")]
    for (rank in seq_len(min(3L,length(top)))) {
      b <- top[[rank]]
      emit(paste("TOP",rank,b$id,b$borrowed,b$name))
    }
  }
  out
}
input <- file("stdin",open="r")
n <- as.integer(readLines(input,n=1L))
for (i in seq_len(n)) {
  line <- readLines(input,n=1L)
  output <- tryCatch(execute(line),error=function(error) paste("ERROR",conditionMessage(error)))
  if (length(output)) cat(paste(output,collapse="\n"),"\n",sep="")
}
close(input)
