source("protocol.R")
source("masks.R")
source("clients.R")
source("channels.R")
source("modes.R")

words <- function(...) paste(...,collapse=" ")
new_counts <- function() new.env(hash=TRUE,parent=emptyenv())
counter <- function(counts,key) {
  value <- counts[[as.character(key)]]
  if (is.null(value)) 0L else value
}
bump <- function(counts,key,amount=1L) counts[[as.character(key)]] <- counter(counts,key)+amount
active_clients <- function(s) Filter(function(c) c$active,s$clients)
active_channels <- function(s) Filter(function(c) c$active,s$channels)
read_inputs <- function() {
  settings <- list(MOTD=character())
  integers <- c(
      "NICKLEN",
      "CHANNELLEN",
      "TOPICLEN",
      "MAXCHANNELS",
      "BUCKET",
      "REFILL",
      "QUEUE",
      "PINGFREQ",
      "TIMEOUT"
  )
  for (line in readLines("input/server.txt",warn=FALSE)) {
    space <- regexpr(" ",line,fixed=TRUE)[1L]
    key <- substr(line,1L,space-1L)
    value <- substring(line,space+1L)
    if (key == "MOTD") settings[[key]] <- c(
        settings[[key]],
        value
    ) else settings[[key]] <- if (key %in% integers) as.integer(value) else value
  }
  traffic <- list()
  counts <- new_counts()
  for (line in readLines("input/traffic.txt",warn=FALSE)) {
    first <- regexpr(" ",line,fixed=TRUE)[1L]
    time <- as.integer(substr(line,1L,first-1L))
    rest <- substring(line,first+1L)
    second <- regexpr(" ",rest,fixed=TRUE)[1L]
    id <- substr(rest,1L,second-1L)
    body <- substring(rest,second+1L)
    kind <- if (grepl(
        "^CONNECT [A-Za-z0-9.-]{1,63}$",
        body
    )) "connect" else if (body == "DISCONNECT") "disconnect" else "messages"
    traffic[[length(traffic)+1L]] <- list(time=time,identifier=id,kind=kind,body=body)
    bump(counts,kind)
  }
  s <- new.env(parent=emptyenv())
  s$settings <- settings
  s$traffic <- traffic
  s$finish <- tail(traffic,1L)[[1L]]$time
  s$time <- 0L
  s$clients <- s$channels <- s$gone <- list()
  s$client_index <- s$channel_index <- NULL
  s$client_index <- new_counts()
  s$channel_index <- new_counts()
  s$sent <- character()
  s$commands <- new_counts()
  s$numeric_counts <- new_counts()
  s$line_counts <- counts
  s$statistics <- new_counts()
  s$disconnections <- new_counts()
  s$peak_connections <- s$peak_registered <- c(0L,0L)
  s
}
send_line <- function(s,client,line) {
  s$sent <- c(s$sent,paste(s$time,client$identifier,line))
  client$sent <- client$sent+1L
}
numeric_reply <- function(
    s,
    client,
    number,
    channel=NULL,
    user=NULL,
    x="",
    command="",
    character="?",
    ban=NULL,
    motd="",
    display="",
    names="",
    channel_list=""
) {
  v <- s$settings
  simple <- c(
      "305"=":You are no longer marked as being away",
      "306"=":You have been marked as being away",
      "376"=":End of /MOTD command.",
      "409"=":No origin specified",
      "412"=":No text to send",
      "431"=":No nickname given",
      "451"=":You have not registered",
      "462"=":You may not reregister",
      "501"=":Unknown MODE flag",
      "502"=":Cannot change mode for other users"
  )
  key <- as.character(number)
  if (key %in% names(simple)) content <- unname(simple[key]) else content <- switch(key,
    "1"=paste(":Welcome to the Internet Relay Network",client_prefix(client)),
    "2"=paste0(":Your host is ",v$NAME,", running version ",v$VERSION),
    "3"=paste(":This server was created",v$CREATED),
    "4"=paste(v$NAME,v$VERSION,"i biklmnotv"),
    "5"=paste0(
        "CASEMAPPING=rfc1459 CHANTYPES=# NICKLEN=",
        v$NICKLEN,
        " CHANNELLEN=",
        v$CHANNELLEN,
        " TOPICLEN=",
        v$TOPICLEN,
        " CHANLIMIT=#:",
        v$MAXCHANNELS,
        " CHANMODES=b,k,l,imnt PREFIX=(ov)@+ :are supported by this server"
    ),
    "221"=client_mode(client),
    "301"=paste0(user$nickname," :",user$away),
    "311"=paste(user$nickname,user$username,user$hostname,"*",paste0(":",user$realname)),
    "312"=paste(user$nickname,v$NAME,paste0(":",v$DESCRIPTION)),
    "317"=paste(user$nickname,s$time-user$last_speaking,user$registration_time,":seconds idle, signon time"),
    "318"=paste(x,":End of /WHOIS list."),
    "319"=paste0(user$nickname," :",channel_list),
    "324"=paste(channel$name,display),
    "329"=paste(channel$name,channel$created),
    "331"=paste(channel$name,":No topic is set"),
    "332"=paste0(channel$name," :",channel$topic),
    "333"=paste(channel$name,channel$topic_setter,channel$topic_time),
    "341"=paste(user$nickname,channel$name),
    "353"=paste0("= ",channel$name," :",names),
    "366"=paste(x,":End of /NAMES list."),
    "367"=paste(channel$name,ban$mask,ban$setter,ban$time),
    "368"=paste(channel$name,":End of channel ban list"),
    "372"=paste(":-",motd),
    "375"=paste(":-",v$NAME,"Message of the day -"),
    "401"=paste(x,":No such nick/channel"),
    "403"=paste(x,":No such channel"),
    "404"=paste(channel$name,":Cannot send to channel"),
    "405"=paste(x,":You have joined too many channels"),
    "411"=paste0(":No recipient given (",command,")"),
    "421"=paste(command,":Unknown command"),
    "432"=paste(x,":Erroneous nickname"),
    "433"=paste(x,":Nickname is already in use"),
    "441"=paste(user$nickname,channel$name,":They aren't on that channel"),
    "442"=paste(channel$name,":You're not on that channel"),
    "443"=paste(user$nickname,channel$name,":is already on channel"),
    "461"=paste(command,":Not enough parameters"),
    "467"=paste(channel$name,":Channel key already set"),
    "471"=paste(channel$name,":Cannot join channel (+l)"),
    "472"=paste(character,":is unknown mode char to me for",channel$name),
    "473"=paste(channel$name,":Cannot join channel (+i)"),
    "474"=paste(channel$name,":Cannot join channel (+b)"),
    "475"=paste(channel$name,":Cannot join channel (+k)"),
    "482"=paste(channel$name,":You're not channel operator")
  )
  bump(s$numeric_counts,key)
  send_line(s,client,paste(paste0(":",v$NAME),sprintf("%03d",number),addressee(client),content))
}
broadcast <- function(s,channel,line,exclude=0L) {
  for (member in channel$members) if (member$client != exclude) send_line(s,s$clients[[member$client]],line)
}
send_peers <- function(s,client,line) {
  peers <- unique(unlist(
      lapply(client$channels,function(id) vapply(s$channels[[id]]$members,function(m) m$client,integer(1))),
      use.names=FALSE
  ))
  for (other in s$clients) if (other$active && other$index != client$index && other$index %in% peers) send_line(
      s,
      other,
      line
  )
}
find_user <- function(s,nickname) {
  name <- irc_fold(nickname)
  for (c in s$clients) if (c$active && c$registered && irc_fold(c$nickname) == name) return(c)
  NULL
}
find_channel <- function(s,name) {
  index <- s$channel_index[[irc_fold(name)]]
  if (is.null(index)) NULL else s$channels[[index]]
}
joined_channels <- function(s,client,separator) {
  paste(
      vapply(
          client$channels,
          function(i) paste0(member_status(channel_member(s$channels[[i]],client)),s$channels[[i]]$name),
          character(1)
      ),
      collapse=separator
  )
}
remove_member <- function(s,client,channel) {
  channel_remove(channel,client)
  if (!length(channel$members)) {
    channel$active <- FALSE
    rm(list=irc_fold(channel$name),envir=s$channel_index)
    for (other in s$clients) if (other$active) other$invites <- other$invites[other$invites != channel$index]
  }
}
disconnect_client <- function(s,client,reason,kind) {
  if (kind != "closed") {
    send_line(s,client,paste0("ERROR :Closing Link: ",addressee(client),"[",client$hostname,"] (",reason,")"))
    bump(s$statistics,"errors")
  }
  if (client$registered) send_peers(s,client,paste0(":",client_prefix(client)," QUIT :",reason))
  for (i in client$channels) remove_member(s,client,s$channels[[i]])
  bump(s$statistics,"discarded",length(client$queue))
  client$queue <- character()
  rm(list=client$identifier,envir=s$client_index)
  client$active <- FALSE
  s$gone[[length(s$gone)+1L]] <- list(
      time=s$time,
      identifier=client$identifier,
      addressee=addressee(client),
      reason=reason
  )
  bump(s$disconnections,kind)
}
complete_registration <- function(s,client) {
  if (client$registered || is.null(client$nickname) || is.null(client$username)) return(invisible(NULL))
  client$registered <- TRUE
  client$registration_time <- client$last_speaking <- s$time
  registered <- sum(vapply(s$clients,function(c) c$active && c$registered,logical(1)))
  if (registered > s$peak_registered[1L]) s$peak_registered <- c(registered,s$time)
  for (number in c(1L,2L,3L,4L,5L,375L)) numeric_reply(s,client,number)
  for (line in s$settings$MOTD) numeric_reply(s,client,372L,motd=line)
  numeric_reply(s,client,376L)
  if (client$invisible) send_line(s,client,paste0(":",client$nickname," MODE ",client$nickname," :+i"))
  invisible(NULL)
}
require_parameters <- function(s,c,p,n,command) {
  if (length(p) >= n) return(TRUE)
  numeric_reply(s,c,461L,command=command)
  FALSE
}
nick_command <- function(s,c,p) {
  if (!length(p) || !nzchar(p[1L])) {
    numeric_reply(s,c,431L)
    return(invisible(NULL))
  }
  nickname <- substr(p[1L],1L,s$settings$NICKLEN)
  if (!valid_nickname(nickname)) {
    numeric_reply(s,c,432L,x=nickname)
    return(invisible(NULL))
  }
  if (identical(nickname,c$nickname)) return(invisible(NULL))
  duplicate <- any(vapply(
      s$clients,
      function(o) o$active && o$index != c$index && !is.null(o$nickname) && irc_fold(o$nickname) == irc_fold(nickname),
      logical(1)
  ))
  if (duplicate) {
    numeric_reply(s,c,433L,x=nickname)
    return(invisible(NULL))
  }
  if (c$registered) {
    line <- paste0(":",client_prefix(c)," NICK :",nickname)
    send_line(s,c,line)
    send_peers(s,c,line)
  }
  c$nickname <- nickname
  complete_registration(s,c)
}
user_command <- function(s,c,p) {
  if (!is.null(c$username)) {
    numeric_reply(s,c,462L)
    return(invisible(NULL))
  }
  if (!require_parameters(s,c,p,4L,"USER")) return(invisible(NULL))
  c$username <- p[1L]
  c$realname <- p[4L]
  c$invisible <- is_digits(p[2L]) && nchar(p[2L]) <= 3L && (as.integer(p[2L]) %/% 8L) %% 2L == 1L
  complete_registration(s,c)
}
names_reply <- function(s,c,channel) {
  names <- name_list(channel,c,s$clients)
  if (nzchar(names)) numeric_reply(s,c,353L,channel=channel,names=names)
  numeric_reply(s,c,366L,x=channel$name)
}
join_channels <- function(s,c,p) {
  if (!require_parameters(s,c,p,1L,"JOIN")) return(invisible(NULL))
  if (p[1L] == "0") {
    for (i in c$channels) {
      channel <- s$channels[[i]]
      broadcast(s,channel,paste0(":",client_prefix(c)," PART ",channel$name))
      remove_member(s,c,channel)
    }
    return(invisible(NULL))
  }
  keys <- if (length(p) >= 2L) strsplit(p[2L],",",fixed=TRUE)[[1L]] else character()
  names <- strsplit(p[1L],",",fixed=TRUE)[[1L]]
  for (i in seq_along(names)) {
    name <- names[i]
    key <- if (i <= length(keys)) keys[i] else ""
    if (!valid_channel(name,s$settings$CHANNELLEN)) {
      numeric_reply(s,c,403L,x=name)
      next
    }
    channel <- find_channel(s,name)
    if (!is.null(channel) && !is.null(channel_member(channel,c))) next
    if (length(c$channels) >= s$settings$MAXCHANNELS) {
      numeric_reply(s,c,405L,x=name)
      next
    }
    if (is.null(channel)) {
      channel <- new_channel(length(s$channels)+1L,name,s$time)
      s$channels[[length(s$channels)+1L]] <- channel
      s$channel_index[[irc_fold(name)]] <- channel$index
    } else {
      invited <- channel$index %in% c$invites
      failure <- 0L
      if (banned(channel,c) && !invited) {
        failure <- 474L
      } else if ("i" %in% channel$flags && !invited) {
        failure <- 473L
      } else if (nzchar(channel$key) && key != channel$key) {
        failure <- 475L
      } else if (channel$limit > 0L && length(channel$members) >= channel$limit) {
        failure <- 471L
      }
      if (failure != 0L) {
        numeric_reply(s,c,failure,channel=channel)
        next
      }
    }
    c$invites <- c$invites[c$invites != channel$index]
    channel_add(channel,c,!length(channel$members))
    broadcast(s,channel,paste0(":",client_prefix(c)," JOIN ",channel$name))
    if (nzchar(channel$topic)) {
      numeric_reply(s,c,332L,channel=channel)
      numeric_reply(s,c,333L,channel=channel)
    }
    names_reply(s,c,channel)
  }
  invisible(NULL)
}
part_channels <- function(s,c,p) {
  if (!require_parameters(s,c,p,1L,"PART")) return(invisible(NULL))
  suffix <- if (length(p) >= 2L && nzchar(p[2L])) paste0(" :",p[2L]) else ""
  for (name in strsplit(p[1L],",",fixed=TRUE)[[1L]]) {
    channel <- find_channel(s,name)
    if (is.null(channel)) numeric_reply(
        s,
        c,
        403L,
        x=name
    ) else if (is.null(channel_member(channel,c))) numeric_reply(
        s,
        c,
        442L,
        channel=channel
    ) else {
      broadcast(s,channel,paste0(":",client_prefix(c)," PART ",channel$name,suffix))
      remove_member(s,c,channel)
    }
  }
  invisible(NULL)
}
message_command <- function(s,c,p,command) {
  replies <- command == "PRIVMSG"
  if (replies) c$last_speaking <- s$time
  if (!length(p) || !nzchar(p[1L])) {
    if (replies) numeric_reply(s,c,411L,command=command)
    return(invisible(NULL))
  }
  if (length(p) < 2L || !nzchar(p[2L])) {
    if (replies) numeric_reply(s,c,412L)
    return(invisible(NULL))
  }
  text <- p[2L]
  for (target in strsplit(p[1L],",",fixed=TRUE)[[1L]]) {
    if (startsWith(target,"#")) {
      channel <- find_channel(s,target)
      if (is.null(channel)) {
        if (replies) numeric_reply(s,c,401L,x=target)
      } else if (!can_speak(channel,c)) {
        if (replies) numeric_reply(s,c,404L,channel=channel)
      } else {
        channel$messages <- channel$messages+1L
        broadcast(s,channel,paste0(":",client_prefix(c)," ",command," ",channel$name," :",text),c$index)
      }
    } else {
      user <- find_user(s,target)
      if (is.null(user)) {
        if (replies) numeric_reply(s,c,401L,x=target)
        next
      }
      send_line(s,user,paste0(":",client_prefix(c)," ",command," ",user$nickname," :",text))
      if (replies && nzchar(user$away)) numeric_reply(s,c,301L,user=user)
    }
  }
  invisible(NULL)
}
topic_command <- function(s,c,p) {
  if (!require_parameters(s,c,p,1L,"TOPIC")) return(invisible(NULL))
  channel <- find_channel(s,p[1L])
  if (is.null(channel)) {
    numeric_reply(s,c,403L,x=p[1L])
    return(invisible(NULL))
  }
  member <- channel_member(channel,c)
  if (is.null(member)) {
    numeric_reply(s,c,442L,channel=channel)
    return(invisible(NULL))
  }
  if (length(p) == 1L) {
    numeric_reply(s,c,if (nzchar(channel$topic)) 332L else 331L,channel=channel)
    if (nzchar(channel$topic)) numeric_reply(s,c,333L,channel=channel)
    return(invisible(NULL))
  }
  if ("t" %in% channel$flags && !member$operator) {
    numeric_reply(s,c,482L,channel=channel)
    return(invisible(NULL))
  }
  channel$topic <- substr(p[2L],1L,s$settings$TOPICLEN)
  channel$topic_setter <- c$nickname
  channel$topic_time <- s$time
  broadcast(s,channel,paste0(":",client_prefix(c)," TOPIC ",channel$name," :",channel$topic))
}
names_command <- function(s,c,p) {
  if (!length(p)) {
    numeric_reply(s,c,366L,x="*")
    return(invisible(NULL))
  }
  for (name in strsplit(p[1L],",",fixed=TRUE)[[1L]]) {
    channel <- find_channel(s,name)
    if (is.null(channel)) numeric_reply(s,c,366L,x=name) else names_reply(s,c,channel)
  }
  invisible(NULL)
}
whois_command <- function(s,c,p) {
  if (!length(p)) {
    numeric_reply(s,c,431L)
    return(invisible(NULL))
  }
  user <- find_user(s,p[1L])
  if (is.null(user)) {
    numeric_reply(s,c,401L,x=p[1L])
    numeric_reply(s,c,318L,x=p[1L])
    return(invisible(NULL))
  }
  numeric_reply(s,c,311L,user=user)
  if (length(user$channels)) numeric_reply(s,c,319L,user=user,channel_list=joined_channels(s,user," "))
  numeric_reply(s,c,312L,user=user)
  if (nzchar(user$away)) numeric_reply(s,c,301L,user=user)
  numeric_reply(s,c,317L,user=user)
  numeric_reply(s,c,318L,x=user$nickname)
}
invite_command <- function(s,c,p) {
  if (!require_parameters(s,c,p,2L,"INVITE")) return(invisible(NULL))
  user <- find_user(s,p[1L])
  if (is.null(user)) {
    numeric_reply(s,c,401L,x=p[1L])
    return(invisible(NULL))
  }
  channel <- find_channel(s,p[2L])
  if (is.null(channel)) {
    numeric_reply(s,c,403L,x=p[2L])
    return(invisible(NULL))
  }
  member <- channel_member(channel,c)
  if (is.null(member)) {
    numeric_reply(s,c,442L,channel=channel)
    return(invisible(NULL))
  }
  if (!is.null(channel_member(channel,user))) {
    numeric_reply(s,c,443L,user=user,channel=channel)
    return(invisible(NULL))
  }
  if ("i" %in% channel$flags && !member$operator) {
    numeric_reply(s,c,482L,channel=channel)
    return(invisible(NULL))
  }
  if (!(channel$index %in% user$invites)) user$invites <- c(user$invites,channel$index)
  numeric_reply(s,c,341L,user=user,channel=channel)
  if (nzchar(user$away)) numeric_reply(s,c,301L,user=user)
  send_line(s,user,paste0(":",client_prefix(c)," INVITE ",user$nickname," :",channel$name))
}
kick_command <- function(s,c,p) {
  if (!require_parameters(s,c,p,2L,"KICK")) return(invisible(NULL))
  channel <- find_channel(s,p[1L])
  if (is.null(channel)) {
    numeric_reply(s,c,403L,x=p[1L])
    return(invisible(NULL))
  }
  member <- channel_member(channel,c)
  if (is.null(member)) {
    numeric_reply(s,c,442L,channel=channel)
    return(invisible(NULL))
  }
  if (!member$operator) {
    numeric_reply(s,c,482L,channel=channel)
    return(invisible(NULL))
  }
  user <- find_user(s,p[2L])
  if (is.null(user)) {
    numeric_reply(s,c,401L,x=p[2L])
    return(invisible(NULL))
  }
  if (is.null(channel_member(channel,user))) {
    numeric_reply(s,c,441L,user=user,channel=channel)
    return(invisible(NULL))
  }
  reason <- if (length(p) >= 3L && nzchar(p[3L])) p[3L] else c$nickname
  broadcast(s,channel,paste0(":",client_prefix(c)," KICK ",channel$name," ",user$nickname," :",reason))
  remove_member(s,user,channel)
}
user_mode <- function(s,c,p) {
  user <- find_user(s,p[1L])
  if (is.null(user)) {
    numeric_reply(s,c,401L,x=p[1L])
    return(invisible(NULL))
  }
  if (user$index != c$index) {
    numeric_reply(s,c,502L)
    return(invisible(NULL))
  }
  if (length(p) == 1L) {
    numeric_reply(s,c,221L)
    return(invisible(NULL))
  }
  sign <- "+"
  changes <- list()
  unknown <- FALSE
  for (character in strsplit(p[2L],"",fixed=TRUE)[[1L]]) {
    if (character %in% c("+","-")) sign <- character else if (character == "i") {
      desired <- sign == "+"
      if (c$invisible != desired) {
        c$invisible <- desired
        changes[[length(changes)+1L]] <- list(sign=sign,character=character,argument=NULL)
      }
    } else unknown <- TRUE
  }
  if (length(changes)) send_line(s,c,paste0(":",c$nickname," MODE ",c$nickname," :",change_string(changes)))
  if (unknown) numeric_reply(s,c,501L)
  invisible(NULL)
}
apply_channel_mode <- function(s,c,channel,sign,character,argument) {
  adding <- sign == "+"
  changed <- FALSE
  change_argument <- NULL
  if (character %in% c("o","v")) {
    user <- find_user(s,argument)
    if (is.null(user)) {
      numeric_reply(s,c,401L,x=argument)
      return(NULL)
    }
    member <- channel_member(channel,user)
    if (is.null(member)) {
      numeric_reply(s,c,441L,user=user,channel=channel)
      return(NULL)
    }
    before <- if (character == "o") member$operator else member$voice
    if (before != adding) {
      if (character == "o") member$operator <- adding else member$voice <- adding
      changed <- TRUE
      change_argument <- user$nickname
    }
  } else if (character == "b") {
    mask <- normalize_mask(argument)
    found <- which(vapply(channel$bans,function(b) irc_fold(b$mask) == irc_fold(mask),logical(1)))
    if (adding && !length(found)) {
      channel$bans[[length(channel$bans)+1L]] <- list(mask=mask,setter=c$nickname,time=s$time)
      changed <- TRUE
      change_argument <- mask
    } else if (!adding && length(found)) {
      change_argument <- channel$bans[[found[1L]]]$mask
      channel$bans <- channel$bans[-found[1L]]
      changed <- TRUE
    }
  } else if (character == "k") {
    if (adding) {
      if (nzchar(channel$key)) numeric_reply(s,c,467L,channel=channel) else {
        channel$key <- argument
        changed <- TRUE
        change_argument <- argument
      }
    } else if (nzchar(channel$key)) {
      channel$key <- ""
      changed <- TRUE
      change_argument <- "*"
    }
  } else if (character == "l") {
    if (adding) {
      limit <- as.integer(argument)
      if (channel$limit != limit) {
        channel$limit <- limit
        changed <- TRUE
        change_argument <- as.character(limit)
      }
    } else if (channel$limit > 0L) {
      channel$limit <- 0L
      changed <- TRUE
    }
  } else if (adding && !(character %in% channel$flags)) {
    channel$flags <- c(channel$flags,character)
    changed <- TRUE
  } else if (!adding && character %in% channel$flags) {
    channel$flags <- channel$flags[channel$flags != character]
    changed <- TRUE
  }
  if (changed) list(sign=sign,character=character,argument=change_argument) else NULL
}
channel_mode <- function(s,c,p) {
  channel <- find_channel(s,p[1L])
  if (is.null(channel)) {
    numeric_reply(s,c,403L,x=p[1L])
    return(invisible(NULL))
  }
  if (length(p) == 1L) {
    numeric_reply(s,c,324L,channel=channel,display=mode_display(channel,!is.null(channel_member(channel,c))))
    numeric_reply(s,c,329L,channel=channel)
    return(invisible(NULL))
  }
  items <- channel_items(p[2L],p[-c(1L,2L)])
  member <- channel_member(channel,c)
  authorized <- !is.null(member) && member$operator
  bans_sent <- denial_sent <- FALSE
  changes <- list()
  for (item in items) {
    sign <- item$sign
    character <- item$character
    argument <- item$argument
    if (!(character %in% c("b","i","k","l","m","n","o","t","v"))) {
      numeric_reply(s,c,472L,character=character,channel=channel)
      next
    }
    if (character == "b" && is.null(argument)) {
      if (sign == "+" && !bans_sent) {
        for (ban in channel$bans) numeric_reply(s,c,367L,channel=channel,ban=ban)
        numeric_reply(s,c,368L,channel=channel)
        bans_sent <- TRUE
      }
      next
    }
    if (is.null(argument) && (character %in% c("o","v") || (sign == "+" && character %in% c("k","l")))) next
    if (!authorized) {
      if (!denial_sent) numeric_reply(s,c,482L,channel=channel)
      denial_sent <- TRUE
      next
    }
    change <- apply_channel_mode(s,c,channel,sign,character,argument)
    if (!is.null(change)) changes[[length(changes)+1L]] <- change
  }
  if (length(changes)) broadcast(
      s,
      channel,
      paste0(":",client_prefix(c)," MODE ",channel$name," ",change_string(changes))
  )
  invisible(NULL)
}
process_line <- function(s,c,raw) {
  bump(s$statistics,"processed")
  parsed <- parse_message(raw)
  command <- parsed$command
  p <- parsed$parameters
  if (!nzchar(command)) {
    bump(s$statistics,"empty")
    return(invisible(NULL))
  }
  bump(s$commands,command)
  if (!c$registered && !(command %in% c("NICK","USER","PING","PONG","QUIT"))) {
    numeric_reply(s,c,451L)
    return(invisible(NULL))
  }
  if (command == "NICK") {
    nick_command(s,c,p)
  } else if (command == "USER") {
    user_command(s,c,p)
  } else if (command == "PING") {
    if (!length(p) || !nzchar(p[1L])) numeric_reply(s,c,409L) else {
      name <- s$settings$NAME
      send_line(s,c,paste0(":",name," PONG ",name," :",p[1L]))
    }
  } else if (command == "PONG") {
    return(invisible(NULL))
  } else if (command == "QUIT") {
    reason <- if (length(p) && nzchar(p[1L])) paste0("Quit: ",p[1L]) else "Client Quit"
    disconnect_client(s,c,reason,"quit")
  } else if (command == "JOIN") {
    join_channels(s,c,p)
  } else if (command == "PART") {
    part_channels(s,c,p)
  } else if (command %in% c("PRIVMSG","NOTICE")) {
    message_command(s,c,p,command)
  } else if (command == "TOPIC") {
    topic_command(s,c,p)
  } else if (command == "NAMES") {
    names_command(s,c,p)
  } else if (command == "WHOIS") {
    whois_command(s,c,p)
  } else if (command == "AWAY") {
    c$away <- if (length(p) && nzchar(p[1L])) p[1L] else ""
    numeric_reply(s,c,if (nzchar(c$away)) 306L else 305L)
  } else if (command == "INVITE") {
    invite_command(s,c,p)
  } else if (command == "KICK") {
    kick_command(s,c,p)
  } else if (command == "MODE") {
    if (!require_parameters(s,c,p,1L,"MODE")) return(invisible(NULL))
    if (startsWith(p[1L],"#")) channel_mode(s,c,p) else user_mode(s,c,p)
  } else {
    numeric_reply(s,c,421L,command=command)
  }
  invisible(NULL)
}
arrival <- function(s,record) {
  id <- record$identifier
  kind <- record$kind
  body <- record$body
  if (kind == "connect") {
    c <- new_client(length(s$clients)+1L,id,substring(body,9L),s$time,s$settings$BUCKET)
    s$clients[[length(s$clients)+1L]] <- c
    s$client_index[[id]] <- c$index
    n <- length(ls(s$client_index,all.names=TRUE))
    if (n > s$peak_connections[1L]) s$peak_connections <- c(n,s$time)
    return(invisible(NULL))
  }
  index <- s$client_index[[id]]
  if (kind == "disconnect") {
    if (!is.null(index)) disconnect_client(s,s$clients[[index]],"Remote host closed the connection","closed")
    return(invisible(NULL))
  }
  if (is.null(index)) {
    bump(s$statistics,"dropped")
    return(invisible(NULL))
  }
  c <- s$clients[[index]]
  c$received <- c$received+1L
  c$last_received <- s$time
  c$ping_sent <- -1L
  if (!length(c$queue) && c$tokens >= 1L) {
    use_token(c,s$time,s$settings$BUCKET,s$settings$REFILL)
    process_line(s,c,body)
  } else if (length(c$queue) >= s$settings$QUEUE) {
    bump(s$statistics,"discarded")
    disconnect_client(s,c,"Excess Flood","flood")
  } else {
    c$queue <- c(c$queue,body)
    bump(s$statistics,"queued")
  }
  invisible(NULL)
}
run_server <- function(s) {
  position <- 1L
  for (time in seq.int(0L,s$finish)) {
    s$time <- time
    for (c in active_clients(s)) {
      refill(c,time,s$settings$BUCKET,s$settings$REFILL)
      while (c$active && length(c$queue) && c$tokens >= 1L) {
        use_token(c,time,s$settings$BUCKET,s$settings$REFILL)
        raw <- c$queue[1L]
        c$queue <- c$queue[-1L]
        process_line(s,c,raw)
      }
    }
    while (position <= length(s$traffic) && s$traffic[[position]]$time == time) {
      arrival(s,s$traffic[[position]])
      position <- position+1L
    }
    for (c in active_clients(s)) {
      if (c$ping_sent != -1L) {
        if (time-c$ping_sent >= s$settings$TIMEOUT) disconnect_client(
            s,
            c,
            paste0("Ping timeout: ",time-c$last_received," seconds"),
            "timeout"
        )
      } else if (time-c$last_received >= s$settings$PINGFREQ) {
        send_line(s,c,paste0("PING :",s$settings$NAME))
        bump(s$statistics,"pings")
        c$ping_sent <- time
      }
    }
  }
}
channel_report <- function(s) {
  lines <- character()
  channels <- active_channels(s)
  for (ch in channels) {
    lines <- c(
        lines,
        words(
            "CHANNEL",
            ch$name,
            "created",
            ch$created,
            "members",
            length(ch$members),
            "peak",
            ch$peak,
            "messages",
            ch$messages,
            "modes",
            mode_display(ch)
        )
    )
    lines <- c(
        lines,
        if (nzchar(ch$topic)) words("TOPIC",ch$topic_setter,ch$topic_time,ch$topic) else "TOPIC none"
    )
    for (ban in ch$bans) lines <- c(lines,words("BAN",ban$mask,ban$setter,ban$time))
    lines <- c(
        lines,
        paste("MEMBERS",paste(vapply(ch$members,member_display,character(1),clients=s$clients),collapse=" "))
    )
  }
  c(
      lines,
      words(
          "TOTAL channels",
          length(channels),
          "members",
          sum(vapply(channels,function(ch) length(ch$members),integer(1))),
          "bans",
          sum(vapply(channels,function(ch) length(ch$bans),integer(1)))
      )
  )
}
client_report <- function(s) {
  lines <- character()
  clients <- active_clients(s)
  for (c in clients) {
    username <- if (is.null(c$username)) "*" else c$username
    signon <- if (c$registered) as.character(c$registration_time) else "-"
    channels <- if (length(c$channels)) joined_channels(s,c,",") else "none"
    invites <- if (length(c$invites)) paste(
        vapply(s$channels[c$invites],function(ch) ch$name,character(1)),
        collapse=","
    ) else "none"
    lines <- c(
        lines,
        words(
            "CLIENT",
            c$identifier,
            addressee(c),
            username,
            c$hostname,
            client_mode(c),
            "connected",
            c$connection_time,
            "signon",
            signon,
            "received",
            c$received,
            "sent",
            c$sent,
            "tokens",
            c$tokens,
            "queue",
            length(c$queue),
            "channels",
            channels,
            "invites",
            invites
        )
    )
    if (nzchar(c$away)) lines <- c(lines,words("AWAY",c$identifier,c$away))
  }
  c(
      lines,
      words(
          "TOTAL clients",
          length(clients),
          "registered",
          sum(vapply(clients,function(c) c$registered,logical(1))),
          "invisible",
          sum(vapply(clients,function(c) c$invisible,logical(1))),
          "away",
          sum(vapply(clients,function(c) nzchar(c$away),logical(1)))
      )
  )
}
statistics_report <- function(s) {
  pending <- sum(vapply(active_clients(s),function(c) length(c$queue),integer(1)))
  stat <- function(key) counter(s$statistics,key)
  numeric_names <- as.integer(ls(s$numeric_counts,all.names=TRUE))
  numeric_total <- sum(vapply(numeric_names,function(n) counter(s$numeric_counts,n),integer(1)))
  lines <- c(
      paste("END",s$finish),
      words(
          "LINES total",
          length(s$traffic),
          "connect",
          counter(s$line_counts,"connect"),
          "disconnect",
          counter(s$line_counts,"disconnect"),
          "messages",
          counter(s$line_counts,"messages")
      ),
      words(
          "MESSAGES dropped",
          stat("dropped"),
          "queued",
          stat("queued"),
          "processed",
          stat("processed"),
          "discarded",
          stat("discarded"),
          "pending",
          pending,
          "empty",
          stat("empty")
      ),
      words(
          "SENT lines",
          length(s$sent),
          "numerics",
          numeric_total,
          "pings",
          stat("pings"),
          "errors",
          stat("errors")
      )
  )
  for (command in sort(ls(s$commands,all.names=TRUE),method="radix")) lines <- c(
      lines,
      words("COMMAND",command,counter(s$commands,command))
  )
  for (number in sort(numeric_names)) lines <- c(
      lines,
      words("NUMERIC",sprintf("%03d",number),counter(s$numeric_counts,number))
  )
  lines <- c(
      lines,
      words("PEAK connections",s$peak_connections[1L],"at",s$peak_connections[2L]),
      words("PEAK registered",s$peak_registered[1L],"at",s$peak_registered[2L])
  )
  lines <- c(
      lines,
      paste(
          "DISCONNECTS",
          paste(
              vapply(
                  c("quit","closed","flood","timeout"),
                  function(kind) words(kind,counter(s$disconnections,kind)),
                  character(1)
              ),
              collapse=" "
          )
      )
  )
  for (record in s$gone) lines <- c(
      lines,
      words("GONE",record$time,record$identifier,record$addressee,record$reason)
  )
  lines
}
main <- function() {
  s <- read_inputs()
  run_server(s)
  outputs <- list(
      "sent.txt"=s$sent,
      "channels.txt"=channel_report(s),
      "clients.txt"=client_report(s),
      "stats.txt"=statistics_report(s)
  )
  dir.create("output",showWarnings=FALSE)
  for (name in names(outputs)) {
    connection <- file(paste0("output/",name),"wb")
    if (length(outputs[[name]])) writeChar(
        paste0(paste(outputs[[name]],collapse="\n"),"\n"),
        connection,
        eos=NULL,
        useBytes=TRUE
    )
    close(connection)
  }
}
main()
