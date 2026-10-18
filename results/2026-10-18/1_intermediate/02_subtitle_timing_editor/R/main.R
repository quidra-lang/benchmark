schemas <- c(
    LIST="",
    VALIDATE="",
    SEARCH="string",
    AT="time",
    GAPS="0:60000",
    STATS="",
    PRINT="",
    TOVTT="",
    TOASS="",
    FRAMES="fps",
    SHIFT="signed",
    SHIFTFROM="pos signed",
    SCALE="1:100000 1:100000",
    SYNC="pos time pos time",
    SNAP="fps",
    FIXOVERLAP="0:60000",
    EXTEND="1:60000",
    TIME="pos time time",
    SORT="",
    RENUMBER="",
    MERGE="0:60000",
    SPLIT="10:80",
    INSERT="pos time time text",
    DELETE="delete",
    TEXT="pos text",
    BALANCE="",
    STRIP="",
    CLEANHI="",
    REPLACE="replace",
    UNDO="")
modifying <- strsplit("SHIFT SHIFTFROM SCALE SYNC SNAP FIXOVERLAP EXTEND TIME SORT RENUMBER MERGE SPLIT INSERT DELETE TEXT BALANCE STRIP CLEANHI REPLACE"," ")[[1]]
format_tags <- c("<i>"="{\\i1}","</i>"="{\\i0}","<b>"="{\\b1}",
    "</b>"="{\\b0}","<u>"="{\\u1}","</u>"="{\\u0}")

fail <- function(message) stop(message,call.=FALSE)

floor_div <- function(n,d) {
    quotient <- trunc(n/d)
    remainder <- n-quotient*d
    if (remainder < 0) {
        quotient <- quotient-1
    } else if (remainder >= d) {
        quotient <- quotient+1
    }
    quotient
}

round_ratio <- function(n,d) floor_div(2*n+d,2*d)

number <- function(value) sprintf("%.0f",value)

char_count <- function(cue) sum(nchar(cue$lines))

dialogue <- function(cue) any(startsWith(cue$lines,"- "))

cue_words <- function(lines) {
    values <- strsplit(paste(lines,collapse=" ")," ",fixed=TRUE)[[1]]
    values[values != ""]
}

trim_spaces <- function(text) gsub("^ +| +$","",text)

two_decimal <- function(value) sprintf("%.0f.%02d",floor_div(value,100),value %% 100)

split_literal <- function(text,separator) {
    positions <- gregexpr(separator,text,fixed=TRUE)[[1]]
    if (positions[1] == -1) return(text)
    starts <- c(1,positions+nchar(separator))
    ends <- c(positions-1,nchar(text))
    vapply(seq_along(starts),function(i) substr(text,starts[i],ends[i]),character(1))
}

time_value <- function(text) {
    if (!grepl("^[0-9]{2}:[0-9]{2}:[0-9]{2},[0-9]{3}$",text)) fail("bad arguments")
    values <- as.numeric(strsplit(text,"[:,]")[[1]])
    if (values[2] > 59 || values[3] > 59) fail("bad arguments")
    sum(values*c(3600000,60000,1000,1))
}

time_text <- function(t,kind="SRT") {
    if (kind == "ASS") {
        c <- floor_div(t+5,10)
        return(sprintf("%.0f:%02d:%02d.%02d",floor_div(c,360000),floor_div(c,6000) %% 60,floor_div(c,100) %% 60,c %% 100))
    }
    sprintf("%02d:%02d:%02d%s%03d",floor_div(t,3600000),floor_div(t,60000) %% 60,floor_div(t,1000) %% 60,
        if (kind == "VTT") "." else ",",t %% 1000)
}

unsigned_arg <- function(text,low=0,high=999999999) {
    if (!grepl("^[0-9]{1,9}$",text)) fail("bad arguments")
    value <- as.numeric(text)
    if (value < low || value > high) fail("bad arguments")
    value
}

typed_arg <- function(text,kind) {
    if (kind == "string") return(text)
    if (kind == "time") return(time_value(text))
    if (kind == "pos") return(unsigned_arg(text,1))
    if (kind == "signed") {
        if (!grepl("^-?[0-9]{1,9}$",text)) fail("bad arguments")
        return(as.numeric(text))
    }
    if (kind == "fps") {
        parts <- split_literal(text,"/")
        if (length(parts) > 2) fail("bad arguments")
        return(c(unsigned_arg(parts[1],1,100000),if (length(parts) == 1) 1 else unsigned_arg(parts[2],1,100000)))
    }
    if (kind %in% c("text","replace")) {
        parts <- split_literal(text,"|")
        if (any(parts == "") || (kind == "replace" && length(parts) != 2)) fail("bad arguments")
        return(parts)
    }
    bounds <- as.numeric(strsplit(kind,":",fixed=TRUE)[[1]])
    unsigned_arg(text,bounds[1],bounds[2])
}

arguments <- function(line,cues) {
    parts <- strsplit(line," ",fixed=TRUE)[[1]]
    command <- parts[1]
    if (!command %in% names(schemas)) fail("unknown command")
    if (command == "DELETE") {
        raw <- parts[-1]
        if (!length(raw) %in% c(1,2)) fail("bad arguments")
        args <- lapply(raw,unsigned_arg,1)
        if (length(args) == 2 && args[[2]] < args[[1]]) fail("bad arguments")
        kinds <- rep("pos",length(args))
    } else {
        kinds <- if (schemas[[command]] == "") character(0) else strsplit(schemas[[command]]," ",fixed=TRUE)[[1]]
        if (length(kinds) > 0 && tail(kinds,1) %in% c("string","text","replace")) {
            if (length(parts) <= length(kinds)) fail("bad arguments")
            raw <- character(0)
            position <- nchar(command)+2
            for (i in seq_along(kinds)) {
                rest <- substring(line,position)
                if (i == length(kinds)) {
                    raw <- c(raw,rest)
                } else {
                    ending <- regexpr(" ",rest,fixed=TRUE)[1]
                    if (ending == -1) fail("bad arguments")
                    raw <- c(raw,substr(rest,1,ending-1))
                    position <- position+ending
                }
            }
        } else {
            raw <- parts[-1]
            if (length(raw) != length(kinds)) fail("bad arguments")
        }
        args <- lapply(seq_along(kinds),function(i) typed_arg(raw[i],kinds[i]))
    }
    for (i in seq_along(kinds)) {
        if (kinds[i] == "pos" && args[[i]] > length(cues)+(if (command == "INSERT") 1 else 0)) {
            fail(paste("no cue",number(args[[i]])))
        }
    }
    if (command == "SYNC" && cues[[args[[1]]]]$start == cues[[args[[3]]]]$start) fail("sync points coincide")
    list(command=command,args=args)
}

wrap_lines <- function(lines,width) {
    output <- character(0)
    for (word in cue_words(lines)) {
        last <- length(output)
        if (last > 0 && nchar(output[last])+1+nchar(word) <= width) {
            output[last] <- paste(output[last],word)
        } else {
            output <- c(output,word)
        }
    }
    output
}

markup <- function(line) {
    items <- list()
    p <- 1
    while (p <= nchar(line)) {
        rest <- substring(line,p)
        tags <- names(format_tags)[vapply(names(format_tags),function(tag) startsWith(rest,tag),logical(1))]
        ending <- regexpr(">",substring(line,p+5),fixed=TRUE)[1]
        if (length(tags) > 0) {
            text <- tags[1]
            item <- list(kind="format",text=text,digit=0)
            p <- p+nchar(text)
        } else if (startsWith(rest,"</font>")) {
            item <- list(kind="font",text="</font>",digit=0)
            p <- p+7
        } else if (startsWith(rest,"<font") && substr(line,p+5,p+5) %in% c(" ",">") && ending != -1) {
            ending <- p+5+ending-1
            item <- list(kind="font",text=substr(line,p,ending),digit=0)
            p <- ending+1
        } else if (substr(line,p,p+3) == "{\\an" && grepl("^[1-9]$",substr(line,p+4,p+4)) && substr(line,p+5,p+5) == "}") {
            item <- list(kind="position",text=substr(line,p,p+5),digit=as.numeric(substr(line,p+4,p+4)))
            p <- p+6
        } else {
            item <- list(kind="ordinary",text=substr(line,p,p),digit=0)
            p <- p+1
        }
        items[[length(items)+1]] <- item
    }
    items
}

converted_line <- function(line,mode) {
    output <- character(0)
    tags <- 0
    position <- 0
    escapes <- c("&"="&amp;","<"="&lt;",">"="&gt;")
    for (item in markup(line)) {
        kind <- item$kind
        text <- item$text
        if (kind != "ordinary") tags <- tags+1
        if (kind == "position" && position == 0) position <- item$digit
        if (kind == "ordinary") {
            output <- c(output,if (mode == "VTT" && text %in% names(escapes)) escapes[[text]] else text)
        } else if (mode == "VTT" && kind == "format") {
            output <- c(output,text)
        } else if (mode == "ASS" && kind == "format") {
            output <- c(output,format_tags[[text]])
        } else if (mode == "ASS" && kind == "position") {
            output <- c(output,text)
        }
    }
    result <- paste(output,collapse="")
    list(text=if (mode == "ASS") result else trim_spaces(result),tags=tags,position=position)
}

clean_hi <- function(line) {
    output <- character(0)
    segments <- 0
    p <- 1
    while (p <= nchar(line)) {
        character <- substr(line,p,p)
        closing <- ""
        if (character == "[") closing <- "]"
        if (character == "(") closing <- ")"
        ending <- if (closing == "") -1 else regexpr(closing,substring(line,p+1),fixed=TRUE)[1]
        if (ending != -1) {
            segments <- segments+1
            p <- p+ending+1
        } else {
            output <- c(output,character)
            p <- p+1
        }
    }
    normalize <- function(text) trim_spaces(gsub(" +"," ",text))
    result <- normalize(paste(output,collapse=""))
    prefix <- if (startsWith(result,"- ")) "- " else ""
    body <- if (prefix == "") result else substring(result,3)
    label <- regexpr("^[A-Z][A-Z0-9 ]*:",body)
    labels <- as.numeric(label[1] != -1)
    if (labels == 1) result <- normalize(paste0(prefix,substring(body,attr(label,"match.length")+1)))
    list(text=result,segments=segments,labels=labels)
}

list_line <- function(cue,p) {
    paste(number(p),number(cue$index),time_text(cue$start),time_text(cue$stop),paste(cue$lines,collapse="|"))
}

inspect <- function(command,args,cues) {
    output <- character(0)
    n <- length(cues)
    if (command %in% c("LIST","AT")) {
        for (p in seq_along(cues)) {
            cue <- cues[[p]]
            if (command == "LIST" || (cue$start <= args[[1]] && args[[1]] < cue$stop)) output <- c(output,list_line(cue,p))
        }
        if (command == "AT") output <- c(output,paste0("AT active=",length(output)))
    } else if (command == "VALIDATE") {
        for (p in seq_along(cues)) {
            cue <- cues[[p]]
            d <- cue$stop-cue$start
            if (cue$index != p) output <- c(output,sprintf("cue %d: index %.0f (expected %d)",p,cue$index,p))
            if (d <= 0) output <- c(output,sprintf("cue %d: end not after start",p))
            if (p > 1 && cue$start < cues[[p-1]]$stop) output <- c(output,sprintf("cue %d: overlaps previous by %.0f ms",p,cues[[p-1]]$stop-cue$start))
            if (d >= 1 && d < 700) {
                output <- c(output,sprintf("cue %d: too short (%.0f ms)",p,d))
            } else if (d > 7000) {
                output <- c(output,sprintf("cue %d: too long (%.0f ms)",p,d))
            }
            for (j in seq_along(cue$lines)) {
                if (nchar(cue$lines[j]) > 42) output <- c(output,sprintf("cue %d: line %d too long (%d chars)",p,j,nchar(cue$lines[j])))
            }
            if (length(cue$lines) >= 3) output <- c(output,sprintf("cue %d: too many lines (%d)",p,length(cue$lines)))
            if (d >= 1 && char_count(cue)*1000 > 21*d) output <- c(output,sprintf("cue %d: too fast (%s cps)",p,two_decimal(floor_div(char_count(cue)*100000,d))))
        }
        output <- c(output,paste0("VALIDATE problems=",length(output)))
    } else if (command == "SEARCH") {
        for (p in seq_along(cues)) {
            cue <- cues[[p]]
            matches <- which(grepl(args[[1]],cue$lines,fixed=TRUE))
            if (length(matches) > 0) output <- c(output,paste(p,time_text(cue$start),cue$lines[matches[1]]))
        }
        output <- c(output,paste0("SEARCH found=",length(output)))
    } else if (command == "GAPS") {
        for (p in seq_len(max(0,n-1))) {
            gap <- cues[[p+1]]$start-cues[[p]]$stop
            if (gap < args[[1]]) output <- c(output,paste(p,p+1,number(gap)))
        }
        output <- c(output,paste0("GAPS count=",length(output)))
    } else if (command == "STATS") {
        output <- paste0("STATS cues=",n)
        if (n == 0) return(output)
        durations <- vapply(cues,function(cue) max(0,cue$stop-cue$start),numeric(1))
        total <- sum(durations)
        characters <- sum(vapply(cues[durations > 0],char_count,numeric(1)))
        output <- c(output,paste0("duration total=",time_text(total)," mean=",time_text(floor_div(total,n))))
        output <- c(output,if (total == 0) "speed -" else paste("speed",two_decimal(floor_div(characters*100000,total))))
        p <- which.max(durations)
        output <- c(output,paste0("longest cue=",p," duration=",time_text(durations[p])))
        if (n == 1) {
            output <- c(output,"gap none")
        } else {
            gaps <- vapply(seq_len(n-1),function(i) cues[[i+1]]$start-cues[[i]]$stop,numeric(1))
            p <- which.max(gaps)
            output <- c(output,paste0("gap cue=",p," ms=",number(gaps[p])))
        }
    } else if (command == "PRINT") {
        for (cue in cues) output <- c(output,number(cue$index),paste(time_text(cue$start),"-->",time_text(cue$stop)),cue$lines,"")
    } else if (command == "TOVTT") {
        output <- c("WEBVTT","")
        for (cue in cues) {
            lines <- character(0)
            position <- 0
            for (line in cue$lines) {
                converted <- converted_line(line,"VTT")
                if (position == 0 && converted$position > 0) position <- converted$position
                if (converted$text != "") lines <- c(lines,converted$text)
            }
            if (length(lines) == 0) next
            settings <- ""
            if (position >= 7) {
                settings <- " line:0"
            } else if (position >= 4) {
                settings <- " line:50%"
            }
            if (position %in% c(1,4,7)) settings <- paste0(settings," align:start")
            if (position %in% c(3,6,9)) settings <- paste0(settings," align:end")
            output <- c(output,number(cue$index),paste0(time_text(cue$start,"VTT")," --> ",time_text(cue$stop,"VTT"),settings),lines,"")
        }
    } else if (command == "TOASS") {
        output <- c("[Events]","Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text")
        for (cue in cues) {
            text <- paste(vapply(cue$lines,function(line) converted_line(line,"ASS")$text,character(1)),collapse="\\N")
            output <- c(output,paste0("Dialogue: 0,",time_text(cue$start,"ASS"),",",time_text(cue$stop,"ASS"),",Default,,0,0,0,,",text))
        }
    } else if (command == "FRAMES") {
        a <- args[[1]][1]
        b <- args[[1]][2]
        for (p in seq_along(cues)) {
            cue <- cues[[p]]
            output <- c(output,paste(p,number(floor_div(cue$start*a,1000*b)),number(floor_div(cue$stop*a,1000*b))))
        }
    }
    output
}

modify <- function(command,args,cues) {
    output <- character(0)
    n <- length(cues)
    if (command %in% c("SHIFT","SHIFTFROM","SCALE","SYNC","SNAP")) {
        first <- if (command == "SHIFTFROM") args[[1]] else 1
        clamped <- 0
        changed <- 0
        if (command == "SYNC") {
            s1 <- cues[[args[[1]]]]$start
            den <- cues[[args[[3]]]]$start-s1
            t1 <- args[[2]]
            t2 <- args[[4]]
            transform <- function(t) {
                num <- t1*den+(t-s1)*(t2-t1)
                if (den < 0) round_ratio(-num,-den) else round_ratio(num,den)
            }
        } else if (command == "SCALE") {
            transform <- function(t) round_ratio(t*args[[1]],args[[2]])
        } else if (command == "SNAP") {
            a <- args[[1]][1]
            b <- args[[1]][2]
            transform <- function(t) round_ratio(round_ratio(t*a,1000*b)*1000*b,a)
        } else {
            delta <- if (command == "SHIFT") args[[1]] else args[[2]]
            transform <- function(t) t+delta
        }
        for (p in seq_len(max(0,n-first+1))+first-1) {
            start <- transform(cues[[p]]$start)
            stop <- transform(cues[[p]]$stop)
            clamped <- clamped+as.numeric(start < 0 || stop < 0)
            start <- max(0,start)
            stop <- max(0,stop)
            changed <- changed+(start != cues[[p]]$start)+(stop != cues[[p]]$stop)
            cues[[p]]$start <- start
            cues[[p]]$stop <- stop
        }
        if (command == "SNAP") {
            output <- paste0("SNAP changed=",changed)
        } else if (command == "SCALE") {
            output <- paste0("SCALE cues=",n)
        } else {
            output <- paste0(command," cues=",max(0,n-first+1)," clamped=",clamped)
        }
    } else if (command == "FIXOVERLAP") {
        fixed <- 0
        failed <- 0
        for (p in seq_len(max(0,n-1))) {
            candidate <- cues[[p+1]]$start-args[[1]]
            if (cues[[p]]$stop > candidate) {
                if (candidate > cues[[p]]$start) {
                    cues[[p]]$stop <- candidate
                    fixed <- fixed+1
                } else {
                    output <- c(output,paste0("cue ",p,": cannot fix"))
                    failed <- failed+1
                }
            }
        }
        output <- c(output,paste0("FIXOVERLAP fixed=",fixed," failed=",failed))
    } else if (command == "EXTEND") {
        extended <- 0
        for (p in seq_along(cues)) {
            cue <- cues[[p]]
            if (cue$stop-cue$start < args[[1]]) {
                candidate <- cue$start+args[[1]]
                if (p < n) candidate <- min(candidate,cues[[p+1]]$start)
                if (candidate > cue$stop) {
                    cues[[p]]$stop <- candidate
                    extended <- extended+1
                }
            }
        }
        short <- sum(vapply(cues,function(cue) cue$stop-cue$start < args[[1]],logical(1)))
        output <- paste0("EXTEND extended=",extended," short=",short)
    } else if (command == "TIME") {
        p <- args[[1]]
        cues[[p]]$start <- args[[2]]
        cues[[p]]$stop <- args[[3]]
        output <- paste0("TIME cue=",p)
    } else if (command == "SORT") {
        indices <- order(vapply(cues,function(cue) cue$start,numeric(1)),vapply(cues,function(cue) cue$stop,numeric(1)),seq_along(cues))
        moved <- sum(indices != seq_along(cues))
        cues <- cues[indices]
        output <- paste0("SORT moved=",moved)
    } else if (command == "RENUMBER") {
        changed <- 0
        for (p in seq_along(cues)) {
            changed <- changed+(cues[[p]]$index != p)
            cues[[p]]$index <- p
        }
        output <- paste0("RENUMBER changed=",changed)
    } else if (command == "MERGE") {
        result <- list()
        merged <- 0
        for (cue in cues) {
            last <- length(result)
            joined <- FALSE
            if (last > 0 && cue$start-result[[last]]$stop < args[[1]] && !dialogue(result[[last]]) && !dialogue(cue)) {
                lines <- wrap_lines(c(result[[last]]$lines,cue$lines),42)
                if (length(lines) <= 2) {
                    result[[last]]$stop <- max(result[[last]]$stop,cue$stop)
                    result[[last]]$lines <- lines
                    merged <- merged+1
                    joined <- TRUE
                }
            }
            if (!joined) result[[length(result)+1]] <- cue
        }
        cues <- result
        output <- paste0("MERGE merged=",merged," cues=",length(cues))
    } else if (command == "SPLIT") {
        result <- list()
        split_count <- 0
        for (cue in cues) {
            duration <- cue$stop-cue$start
            if (duration <= 0 || dialogue(cue)) {
                result[[length(result)+1]] <- cue
                next
            }
            lines <- wrap_lines(cue$lines,args[[1]])
            if (length(lines) <= 2) {
                cue$lines <- lines
                result[[length(result)+1]] <- cue
                next
            }
            starts <- seq(1,length(lines),by=2)
            parts <- lapply(starts,function(i) lines[i:min(i+1,length(lines))])
            weights <- vapply(parts,function(part) sum(nchar(part)),numeric(1))
            total <- sum(weights)
            allotted <- vapply(weights,function(weight) floor_div(duration*weight,total),numeric(1))
            remainders <- duration*weights-allotted*total
            ordering <- order(-remainders,seq_along(parts))
            for (i in seq_len(duration-sum(allotted))) allotted[ordering[i]] <- allotted[ordering[i]]+1
            start <- cue$start
            for (i in seq_along(parts)) {
                result[[length(result)+1]] <- list(index=cue$index,start=start,stop=start+allotted[i],lines=parts[[i]])
                start <- start+allotted[i]
            }
            split_count <- split_count+1
        }
        cues <- result
        output <- paste0("SPLIT split=",split_count," cues=",length(cues))
    } else if (command == "INSERT") {
        p <- args[[1]]
        cue <- list(index=p,start=args[[2]],stop=args[[3]],lines=args[[4]])
        cues <- append(cues,list(cue),after=p-1)
        output <- paste0("INSERT cue=",p," cues=",length(cues))
    } else if (command == "DELETE") {
        p <- args[[1]]
        q <- if (length(args) == 1) p else args[[2]]
        cues <- cues[-(p:q)]
        output <- paste0("DELETE removed=",q-p+1," cues=",length(cues))
    } else if (command == "TEXT") {
        p <- args[[1]]
        cues[[p]]$lines <- args[[2]]
        output <- paste0("TEXT cue=",p," lines=",length(args[[2]]))
    } else if (command == "BALANCE") {
        changed <- 0
        skipped <- 0
        dialogues <- 0
        for (p in seq_along(cues)) {
            cue <- cues[[p]]
            if (dialogue(cue)) {
                dialogues <- dialogues+1
                next
            }
            words <- cue_words(cue$lines)
            text <- paste(words,collapse=" ")
            candidate <- NULL
            best_difference <- 1000000
            best_first <- 1000000
            if (nchar(text) <= 42) {
                candidate <- text
            } else {
                for (j in seq_len(max(0,length(words)-1))) {
                    left <- paste(words[seq_len(j)],collapse=" ")
                    right <- paste(words[(j+1):length(words)],collapse=" ")
                    difference <- abs(nchar(left)-nchar(right))
                    if (nchar(left) <= 42 && nchar(right) <= 42 && (difference < best_difference || (difference == best_difference && nchar(left) < best_first))) {
                        candidate <- c(left,right)
                        best_difference <- difference
                        best_first <- nchar(left)
                    }
                }
            }
            if (is.null(candidate)) {
                skipped <- skipped+1
            } else {
                changed <- changed+!identical(cue$lines,candidate)
                cues[[p]]$lines <- candidate
            }
        }
        output <- paste0("BALANCE changed=",changed," skipped=",skipped," dialogue=",dialogues)
    } else if (command %in% c("STRIP","CLEANHI")) {
        result <- list()
        tags <- 0
        labels <- 0
        removed_lines <- 0
        removed_cues <- 0
        for (cue in cues) {
            lines <- character(0)
            for (line in cue$lines) {
                if (command == "STRIP") {
                    converted <- converted_line(line,"STRIP")
                    tags <- tags+converted$tags
                } else {
                    converted <- clean_hi(line)
                    tags <- tags+converted$segments
                    labels <- labels+converted$labels
                }
                text <- converted$text
                if (text == "" || (command == "CLEANHI" && text == "-")) {
                    removed_lines <- removed_lines+1
                } else {
                    lines <- c(lines,text)
                }
            }
            if (length(lines) == 0) {
                removed_cues <- removed_cues+1
            } else {
                cue$lines <- lines
                result[[length(result)+1]] <- cue
            }
        }
        cues <- result
        prefix <- if (command == "STRIP") paste0("STRIP tags=",tags) else paste0("CLEANHI segments=",tags," labels=",labels)
        output <- paste0(prefix," removed_lines=",removed_lines," removed_cues=",removed_cues)
    } else if (command == "REPLACE") {
        old <- args[[1]][1]
        new <- args[[1]][2]
        replacements <- 0
        changed <- 0
        for (p in seq_along(cues)) {
            local_count <- 0
            lines <- character(0)
            for (line in cues[[p]]$lines) {
                pieces <- character(0)
                position <- 1
                repeat {
                    rest <- substring(line,position)
                    first <- regexpr(old,rest,fixed=TRUE)[1]
                    if (first == -1) {
                        pieces <- c(pieces,rest)
                        break
                    }
                    pieces <- c(pieces,substr(rest,1,first-1),new)
                    position <- position+first-1+nchar(old)
                    local_count <- local_count+1
                }
                lines <- c(lines,paste(pieces,collapse=""))
            }
            cues[[p]]$lines <- lines
            replacements <- replacements+local_count
            changed <- changed+(local_count > 0)
        }
        output <- paste0("REPLACE count=",number(replacements)," cues=",changed)
    }
    list(cues=cues,output=output)
}

load_block <- function(block,k) {
    if (!grepl("^[0-9]{1,6}$",block[1])) return(list(problem=paste0("BAD CUE ",k,": index")))
    times <- tryCatch({
        if (length(block) < 2 || nchar(block[2]) != 29 || substr(block[2],13,17) != " --> ") fail("bad arguments")
        c(time_value(substr(block[2],1,12)),time_value(substr(block[2],18,29)))
    },error=function(e) NULL)
    if (is.null(times)) return(list(problem=paste0("BAD CUE ",k,": time")))
    if (length(block) < 3) return(list(problem=paste0("BAD CUE ",k,": no text")))
    list(cue=list(index=as.numeric(block[1]),start=times[1],stop=times[2],lines=block[-c(1,2)]))
}

main <- function() {
    input <- readLines(file("stdin"),warn=FALSE)
    cues <- list()
    block <- character(0)
    blocks <- 0
    bad <- 0
    position <- 1
    repeat {
        line <- input[position]
        position <- position+1
        if (line == "" || line == "###") {
            if (length(block) > 0) {
                blocks <- blocks+1
                loaded <- load_block(block,blocks)
                if (!is.null(loaded$problem)) {
                    cat(loaded$problem,"\n",sep="")
                    bad <- bad+1
                } else {
                    cues[[length(cues)+1]] <- loaded$cue
                }
                block <- character(0)
            }
            if (line == "###") break
        } else {
            block <- c(block,line)
        }
    }
    cat("LOAD cues=",length(cues)," bad=",bad,"\n",sep="")
    history <- list()
    count <- as.integer(input[position])
    for (i in seq_len(count)) {
        line <- input[position+i]
        output <- tryCatch({
            parsed <- arguments(line,cues)
            command <- parsed$command
            args <- parsed$args
            if (command == "UNDO") {
                if (length(history) == 0) fail("nothing to undo")
                previous <- history[[length(history)]]
                history <- history[-length(history)]
                cues <- previous$cues
                paste0("UNDO command=",previous$command)
            } else if (command %in% modifying) {
                result <- modify(command,args,cues)
                history[[length(history)+1]] <- list(command=command,cues=cues)
                cues <- result$cues
                result$output
            } else {
                inspect(command,args,cues)
            }
        },error=function(e) paste("ERROR",conditionMessage(e)))
        if (length(output) > 0) cat(paste0(output,"\n"),sep="")
    }
}
main()
