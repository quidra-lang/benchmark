words <- function(text) strsplit(text," ",fixed=TRUE)[[1]]
systems <- words("HEPBURN TRADITIONAL KUNREI NIHON WAPURO")
rows <- words("a ka sa ta na ha ma ya ra wa ga za da ba pa")
row_text <- c("a i u e o","ka ki ku ke ko","sa si su se so","ta ti tu te to",
    "na ni nu ne no","ha hi hu he ho","ma mi mu me mo","ya yu yo","ra ri ru re ro",
    "wa wi we wo","ga gi gu ge go","za zi zu ze zo","da di du de do","ba bi bu be bo","pa pi pu pe po")
contract_rows <- words("ka sa ta na ha ma ra ga za da ba pa")
base_row <- c(ga="ka",za="sa",da="ta",ba="ha",pa="ha")
devoice_letter <- c(g="k",z="s",d="t",b="h",p="h")
gojuon <- words("a i u e o ka ki ku ke ko sa si su se so ta ti tu te to na ni nu ne no ha hi hu he ho ma mi mu me mo ya yu yo ra ri ru re ro wa wi we wo N")
iroha <- words("i ro ha ni ho he to ti ri nu ru wo wa ka yo ta re so tu ne na ra mu u wi no o ku ya ma ke hu ko e te a sa ki yu me mi si we hi mo se su N")
arg_counts <- c(SET=2,TABLE=2,CONVERT=2,NORMALIZE=0,REVERSE=1,VALID=1,DETECT=0,
    DIFF=2,SAME=2,MORAE=1,SYLLABLES=1,ROW=1,STATS=1,SORT=1,INDEX=1,FIND=2,HAIKU=1,KAIBUN=1,SHIRITORI=1)
set_values <- list(LONG=words("KEEP DROP PASSPORT HYPHEN DOUBLE"),
    CASE=words("KEEP LOWER UPPER TITLE"),ORDER=words("GOJUON IROHA"))
identifiers <- character(0)
row_of <- character(0)
dan_of <- character(0)
i_of <- character(0)
for (i in seq_along(rows)) {
    row <- rows[i]
    for (id in words(row_text[i])) {
        identifiers <- c(identifiers,id)
        row_of[id] <- row
        dan_of[id] <- substr(id,nchar(id),nchar(id))
        if (dan_of[[id]] == "i") i_of[row] <- id
    }
}
for (row in contract_rows) {
    for (dan in c("ya","yu","yo")) {
        id <- paste0(substr(i_of[[row]],1,nchar(i_of[[row]])-1),dan)
        identifiers <- c(identifiers,id)
        row_of[id] <- row
        dan_of[id] <- dan
    }
}

fail <- function(message) stop(message,call.=FALSE)

column_error <- function(column,message) fail(paste0("col ",column,": ",message))

is_syllabic <- function(id) id %in% names(row_of)

is_vowel <- function(id) id %in% c("a","i","u","e","o")

last_letter <- function(text) substr(text,nchar(text),nchar(text))

character_at <- function(text,position) substr(text,position,position)

spelling <- function(system,id) {
    if (system %in% c("HEPBURN","TRADITIONAL","WAPURO")) {
        changes <- c(si="shi",ti="chi",tu="tsu",hu="fu",zi="ji")
        if (system != "WAPURO") {
            changes <- c(changes,di="ji",du="zu",wi="i",we="e",wo="o")
        }
        if (id %in% names(changes)) return(changes[[id]])
        prefix <- substr(id,1,2)
        if (prefix == "sy") {
            return(paste0("sh",substring(id,3)))
        } else if (prefix == "ty") {
            return(paste0("ch",substring(id,3)))
        } else if (prefix == "zy" || (system != "WAPURO" && prefix == "dy")) {
            return(paste0("j",substring(id,3)))
        }
    } else if (system == "KUNREI") {
        changes <- c(di="zi",du="zu",wi="i",we="e",wo="o",dya="zya",dyu="zyu",dyo="zyo")
        if (id %in% names(changes)) return(changes[[id]])
    }
    id
}

readings <- list()
for (system in c(systems,"NORMAL")) {
    seen <- character(0)
    styles <- if (system == "NORMAL") c("HEPBURN","KUNREI","NIHON","WAPURO") else system
    for (id in identifiers) {
        for (style in styles) {
            text <- spelling(style,id)
            if (!text %in% names(seen)) seen[text] <- id
        }
    }
    readings[[system]] <- seen[order(-nchar(names(seen)))]
}

match_syllable <- function(word,position,system) {
    if (position > nchar(word)) return(NULL)
    entries <- readings[[system]]
    index <- match(TRUE,startsWith(substring(word,position),names(entries)))
    if (is.na(index)) NULL else list(text=names(entries)[index],id=entries[[index]])
}

parse_word <- function(text,start,system) {
    word <- tolower(text)
    ids <- character(0)
    columns <- numeric(0)
    p <- 1
    while (p <= nchar(word)) {
        c <- character_at(word,p)
        c2 <- character_at(word,p+1)
        c3 <- character_at(word,p+2)
        matched <- match_syllable(word,p,system)
        advance <- 1
        if (c == "-") {
            if (length(ids) == 0 || !is_syllabic(tail(ids,1))) {
                column_error(start+p-1,"misplaced long mark")
            }
            id <- "-"
        } else if (c == "'") {
            column_error(start+p-1,"misplaced apostrophe")
        } else if (!is.null(matched)) {
            id <- matched$id
            advance <- nchar(matched$text)
        } else if (system %in% c("WAPURO","NORMAL") && startsWith(substring(word,p),"xtu")) {
            id <- "Q"
            advance <- 3
        } else if (c == "n") {
            id <- "N"
            if (system == "WAPURO") {
                advance <- if (c2 == "n") 2 else 1
            } else if (system == "NORMAL") {
                if (c2 == "'" || (c2 == "n" && !c3 %in% c("a","i","u","e","o","y","'"))) {
                    advance <- 2
                }
            } else if (c2 == "'") {
                advance <- 2
            }
        } else if (system %in% c("TRADITIONAL","NORMAL") && c == "m" && c2 %in% c("b","m","p")) {
            id <- "N"
        } else if (grepl("^[a-z]$",c) && !c %in% c("a","i","u","e","o","n") && c == c2 && !is.null(match_syllable(word,p+1,system))) {
            id <- "Q"
        } else if (system %in% c("HEPBURN","TRADITIONAL","NORMAL") && c == "t" && c2 == "c" && c3 == "h" && !is.null(match_syllable(word,p+1,system))) {
            id <- "Q"
        } else {
            column_error(start+p-1,"unknown syllable")
        }
        ids <- c(ids,id)
        columns <- c(columns,start+p-1)
        p <- p+advance
    }
    list(ids=ids,columns=columns)
}

long_flags <- function(ids) {
    paired <- rep(FALSE,length(ids))
    long <- ids == "-"
    i <- 1
    while (i < length(ids)) {
        first <- ids[i]
        second <- ids[i+1]
        if (is_syllabic(first) && is_vowel(second)) {
            vowel <- last_letter(first)
            if (vowel == second || (vowel == "o" && second == "u") || (vowel == "e" && second == "i")) {
                paired[i+1] <- TRUE
                long[i+1] <- (vowel == "o" && second %in% c("o","u")) || (vowel == "u" && second == "u")
                i <- i+2
                next
            }
        }
        i <- i+1
    }
    list(paired=paired,long=long)
}

write_parts <- function(ids,columns,system,long_setting) {
    long <- long_flags(ids)$long
    parts <- character(0)
    for (i in seq_along(ids)) {
        id <- ids[i]
        next_id <- if (i < length(ids)) ids[i+1] else ""
        next_text <- if (is_syllabic(next_id)) spelling(system,next_id) else ""
        first <- substr(next_text,1,1)
        if (long[i]) {
            vowel <- last_letter(ids[i-1])
            if (long_setting == "KEEP") {
                part <- if (id == "-") "-" else spelling(system,id)
            } else if (long_setting == "DROP") {
                part <- ""
            } else if (long_setting == "PASSPORT") {
                part <- if (vowel == "o" && !is_vowel(first)) "h" else ""
            } else if (long_setting == "HYPHEN") {
                part <- "-"
            } else {
                part <- vowel
            }
        } else if (is_syllabic(id)) {
            part <- spelling(system,id)
        } else if (id == "N") {
            if (system == "WAPURO") {
                part <- if (next_id == "N" || first %in% c("a","i","u","e","o","y","n")) "nn" else "n"
            } else if (system == "TRADITIONAL" && first %in% c("b","m","p")) {
                part <- "m"
            } else {
                part <- if (first %in% c("a","i","u","e","o","y")) "n'" else "n"
            }
        } else {
            if (next_text != "" && !first %in% c("a","i","u","e","o","n")) {
                part <- if (system %in% c("HEPBURN","TRADITIONAL") && startsWith(next_text,"ch")) "t" else first
            } else if (system == "WAPURO") {
                part <- "xtu"
            } else {
                column_error(columns[i],"small tsu cannot be written")
            }
        }
        parts <- c(parts,part)
    }
    parts
}

word_pattern <- function(text) {
    if (text == tolower(text)) return("LOWER")
    if (grepl("^[A-Z]",text) && substring(text,2) == tolower(substring(text,2))) return("TITLE")
    letters <- strsplit(text,"",fixed=TRUE)[[1]]
    if (sum(grepl("^[A-Z]$",letters)) >= 2 && text == toupper(text)) return("UPPER")
    ""
}

written <- function(word,system,settings,canonical=FALSE,ids=word$ids,columns=word$columns) {
    mode <- if (canonical) "KEEP" else settings$LONG
    text <- paste(write_parts(ids,columns,system,mode),collapse="")
    pattern <- if (canonical || settings$CASE == "KEEP") word$pattern else settings$CASE
    if (pattern == "UPPER") return(toupper(text))
    if (pattern == "TITLE") return(paste0(toupper(substr(text,1,1)),substring(text,2)))
    text
}

count_character <- function(text,character) {
    sum(strsplit(text,"",fixed=TRUE)[[1]] == character)
}

words_in <- function(text) {
    matched <- gregexpr("[A-Za-z'-]+",text)[[1]]
    if (matched[1] == -1) return(list())
    lengths <- attr(matched,"match.length")
    lapply(seq_along(matched),function(i) {
        start <- matched[i]
        list(text=substr(text,start,start+lengths[i]-1),start=start,pattern="",ids=character(0),columns=numeric(0),
            part=count_character(substr(text,1,start-1),"/")+1,index=i)
    })
}

replace_words <- function(text,words,replacements) {
    output <- character(0)
    position <- 1
    for (i in seq_along(words)) {
        word <- words[[i]]
        output <- c(output,substr(text,position,word$start-1),replacements[i])
        position <- word$start+nchar(word$text)
    }
    paste(c(output,substring(text,position)),collapse="")
}

devoice <- function(id) {
    first <- substr(id,1,1)
    if (first %in% names(devoice_letter)) first <- devoice_letter[[first]]
    paste0(first,substring(id,2))
}

elements <- function(ids) {
    items <- list()
    for (id in ids) {
        if (id == "-") next
        if (id == "N") {
            items[[length(items)+1]] <- list(base="N",voice=0,size=0)
        } else if (id == "Q") {
            items[[length(items)+1]] <- list(base="tu",voice=0,size=1)
        } else {
            row <- row_of[[id]]
            voice <- 0
            if (row %in% c("ga","za","da","ba")) {
                voice <- 1
            } else if (row == "pa") {
                voice <- 2
            }
            if (nchar(dan_of[[id]]) == 2) {
                items[[length(items)+1]] <- list(base=devoice(i_of[[row]]),voice=voice,size=0)
                items[[length(items)+1]] <- list(base=dan_of[[id]],voice=0,size=1)
            } else {
                items[[length(items)+1]] <- list(base=devoice(id),voice=voice,size=0)
            }
        }
    }
    items
}

collation <- function(word,ordering) {
    ranks <- if (ordering == "GOJUON") gojuon else iroha
    items <- elements(word$ids)
    list(vapply(items,function(item) match(item$base,ranks),integer(1)),
        vapply(items,function(item) item$voice,numeric(1)),
        vapply(items,function(item) item$size,numeric(1)),as.numeric(word$ids == "-"))
}

vector_compare <- function(a,b) {
    for (i in seq_len(min(length(a),length(b)))) {
        if (a[i] != b[i]) return(if (a[i] < b[i]) -1 else 1)
    }
    sign(length(a)-length(b))
}

key_less <- function(a,b) {
    for (j in 1:4) {
        comparison <- vector_compare(a[[j]],b[[j]])
        if (comparison != 0) return(comparison < 0)
    }
    FALSE
}

pattern_tokens <- function(pattern,system) {
    if (!grepl("^[a-z'\\-?*]+$",pattern)) fail("invalid pattern")
    tokens <- character(0)
    chunk <- ""
    tryCatch({
        for (c in strsplit(pattern,"",fixed=TRUE)[[1]]) {
            if (c %in% c("?","*")) {
                tokens <- c(tokens,parse_word(chunk,1,system)$ids,c)
                chunk <- ""
            } else {
                chunk <- paste0(chunk,c)
            }
        }
        c(tokens,parse_word(chunk,1,system)$ids)
    },error=function(e) fail("invalid pattern"))
}

wildcard_matches <- function(tokens,ids) {
    previous <- c(TRUE,rep(FALSE,length(ids)))
    for (token in tokens) {
        current <- rep(FALSE,length(ids)+1)
        if (token == "*") current[1] <- previous[1]
        for (j in seq_along(ids)) {
            if (token == "*") {
                current[j+1] <- previous[j+1] || current[j]
            } else {
                current[j+1] <- previous[j] && (token == "?" || token == ids[j])
            }
        }
        previous <- current
    }
    tail(previous,1)
}

execute <- function(line,settings) {
    command <- strsplit(line," ",fixed=TRUE)[[1]][1]
    if (!command %in% names(arg_counts)) fail(paste("unknown command",command))
    k <- arg_counts[[command]]
    if (command %in% c("SET","TABLE")) {
        parts <- strsplit(line," ",fixed=TRUE)[[1]]
        if (length(parts) < 3) fail("missing argument")
        if (length(parts) > 3) fail("too many arguments")
        args <- parts[2:3]
        text <- ""
    } else {
        if (count_character(line," ") < k+1) fail("missing argument")
        args <- character(0)
        position <- nchar(command)+2
        for (i in seq_len(k)) {
            rest <- substring(line,position)
            ending <- regexpr(" ",rest,fixed=TRUE)[1]
            args <- c(args,substr(rest,1,ending-1))
            position <- position+ending
        }
        text <- substring(line,position)
    }
    system_count <- 1
    if (command %in% c("SET","NORMALIZE","DETECT")) {
        system_count <- 0
    } else if (command %in% c("CONVERT","DIFF","SAME")) {
        system_count <- 2
    }
    for (system in head(args,system_count)) {
        if (!system %in% systems) fail(paste("unknown system",system))
    }
    if (command == "SET") {
        option <- args[1]
        value <- args[2]
        if (!option %in% names(set_values)) fail(paste("unknown option",option))
        if (!value %in% set_values[[option]]) fail(paste("unknown value",value))
        settings[[option]] <- value
        return(paste0(option,"=",value))
    }
    if (command == "TABLE") {
        system <- args[1]
        row <- args[2]
        if (!row %in% rows) fail(paste("unknown row",row))
        return(paste(vapply(identifiers[row_of[identifiers] == row],function(id) spelling(system,id),character(1)),collapse=" "))
    }
    tokens <- if (command == "FIND") pattern_tokens(args[2],args[1]) else character(0)
    slash_allowed <- command %in% c("HAIKU","SAME")
    characters <- strsplit(text,"",fixed=TRUE)[[1]]
    for (i in seq_along(characters)) {
        c <- characters[i]
        allowed <- grepl("^[A-Za-z0-9]$",c) || c %in% strsplit("'- .,!?;:()\"","",fixed=TRUE)[[1]] || (slash_allowed && c == "/")
        if (!allowed) column_error(i,"invalid character")
    }
    word_list <- words_in(text)
    if (command %in% c("SAME","HAIKU")) {
        parts <- count_character(text,"/")+1
        message <- if (command == "SAME") "expected two texts" else "expected 3 or 5 lines"
        if ((command == "SAME" && parts != 2) || (command == "HAIKU" && !parts %in% c(3,5))) fail(message)
        for (i in seq_len(parts)) {
            if (!any(vapply(word_list,function(word) word$part == i,logical(1)))) fail(message)
        }
    }
    if (length(word_list) == 0) fail("no words")
    for (i in seq_along(word_list)) {
        word_list[[i]]$pattern <- word_pattern(word_list[[i]]$text)
        if (word_list[[i]]$pattern == "") column_error(word_list[[i]]$start,"mixed case")
    }
    if (command == "DETECT") {
        output <- character(0)
        for (system in systems) {
            verdict <- tryCatch({
                result <- "canonical"
                parsed_words <- lapply(word_list,function(word) {
                    parsed <- parse_word(word$text,word$start,system)
                    word$ids <- parsed$ids
                    word$columns <- parsed$columns
                    word
                })
                for (word in parsed_words) {
                    if (written(word,system,settings,TRUE) != word$text) result <- "readable"
                }
                result
            },error=function(e) "error")
            output <- c(output,paste0(system,"=",verdict))
        }
        return(paste(output,collapse=" "))
    }
    for (i in seq_along(word_list)) {
        word <- word_list[[i]]
        if (command == "NORMALIZE") {
            system <- "NORMAL"
        } else if (command == "SAME") {
            system <- args[word$part]
        } else {
            system <- args[1]
        }
        parsed <- parse_word(word$text,word$start,system)
        word_list[[i]]$ids <- parsed$ids
        word_list[[i]]$columns <- parsed$columns
    }
    system <- if (command == "NORMALIZE") "HEPBURN" else args[1]
    if (command %in% c("CONVERT","NORMALIZE","REVERSE")) {
        target <- if (command == "CONVERT") args[2] else system
        output <- vapply(word_list,function(word) {
            ids <- word$ids
            columns <- word$columns
            if (command == "REVERSE") {
                for (i in seq_along(ids)) {
                    if (ids[i] == "-") ids[i] <- last_letter(word$ids[i-1])
                }
                ids <- rev(ids)
                columns <- rev(columns)
            }
            written(word,target,settings,FALSE,ids,columns)
        },character(1))
        return(replace_words(text,word_list,output))
    }
    if (command == "VALID") {
        for (word in word_list) {
            expected <- written(word,system,settings,TRUE)
            if (expected != word$text) {
                i <- 1
                while (i <= min(nchar(expected),nchar(word$text)) && character_at(expected,i) == character_at(word$text,i)) {
                    i <- i+1
                }
                return(paste0("INVALID col ",word$start+i-1,": expected ",expected))
            }
        }
        return("VALID")
    }
    if (command == "DIFF") {
        output <- character(0)
        for (word in word_list) {
            a <- written(word,args[1],settings)
            b <- written(word,args[2],settings)
            if (a != b) output <- c(output,paste0(a,">",b))
        }
        prefix <- paste(length(output),"of",length(word_list))
        return(if (length(output) == 0) prefix else paste0(prefix,": ",paste(output,collapse=" ")))
    }
    if (command == "SAME") {
        left <- Filter(function(word) word$part == 1,word_list)
        right <- Filter(function(word) word$part == 2,word_list)
        exact <- TRUE
        for (i in seq_len(min(length(left),length(right)))) {
            a <- left[[i]]$ids
            b <- right[[i]]$ids
            if (!identical(a[!long_flags(a)$long],b[!long_flags(b)$long])) return(paste("DIFFERENT at word",i))
            exact <- exact && identical(a,b)
        }
        if (length(left) != length(right)) return(paste("DIFFERENT at word",min(length(left),length(right))+1))
        return(if (exact) "EXACT" else "LOOSE")
    }
    if (command %in% c("MORAE","SYLLABLES")) {
        output <- character(0)
        total <- 0
        for (word in word_list) {
            if (command == "MORAE") {
                parts <- vapply(word$ids,function(id) spelling(system,id),character(1))
            } else {
                paired <- long_flags(word$ids)$paired
                written_parts <- write_parts(word$ids,word$columns,system,"KEEP")
                parts <- character(0)
                for (i in seq_along(word$ids)) {
                    if (i > 1 && (!is_syllabic(word$ids[i]) || paired[i])) {
                        parts[length(parts)] <- paste0(parts[length(parts)],written_parts[i])
                    } else {
                        parts <- c(parts,written_parts[i])
                    }
                }
            }
            total <- total+length(parts)
            output <- c(output,paste(parts,collapse="."))
        }
        return(paste0(total,": ",paste(output,collapse=" ")))
    }
    if (command == "ROW") {
        output <- character(0)
        for (word in word_list) {
            for (id in word$ids) {
                item <- if (is_syllabic(id)) paste0(spelling(system,id),": ",row_of[[id]]," ",dan_of[[id]]) else paste0(id,": special")
                output <- c(output,item)
            }
        }
        return(paste(output,collapse=", "))
    }
    if (command == "STATS") {
        counts <- setNames(rep(0,16),c(rows[1:10],words("voiced semivoiced contracted N Q L")))
        total <- 0
        for (word in word_list) {
            for (id in word$ids) {
                total <- total+1
                if (is_syllabic(id)) {
                    row <- row_of[[id]]
                    base <- if (row %in% names(base_row)) base_row[[row]] else row
                    counts[base] <- counts[base]+1
                    if (row %in% c("ga","za","da","ba")) counts["voiced"] <- counts["voiced"]+1
                    if (row == "pa") counts["semivoiced"] <- counts["semivoiced"]+1
                    if (nchar(dan_of[[id]]) == 2) counts["contracted"] <- counts["contracted"]+1
                } else {
                    key <- if (id == "-") "L" else id
                    counts[key] <- counts[key]+1
                }
            }
        }
        output <- paste0("morae=",total)
        for (row in rows[1:10]) {
            if (counts[[row]] > 0) output <- c(output,paste0(row,"=",counts[[row]]))
        }
        for (name in words("voiced semivoiced contracted N Q L")) output <- c(output,paste0(name,"=",counts[[name]]))
        return(paste(output,collapse=" "))
    }
    if (command %in% c("SORT","INDEX")) {
        keys <- lapply(word_list,collation,settings$ORDER)
        indices <- seq_along(word_list)
        for (i in seq_along(indices)) {
            index <- indices[i]
            position <- i
            while (position > 1 && key_less(keys[[index]],keys[[indices[position-1]]])) {
                indices[position] <- indices[position-1]
                position <- position-1
            }
            indices[position] <- index
        }
        ordered <- word_list[indices]
        if (command == "SORT") return(paste(vapply(ordered,function(word) word$text,character(1)),collapse=" "))
        groups <- character(0)
        previous <- ""
        for (word in ordered) {
            base <- elements(word$ids)[[1]]$base
            heading <- if (settings$ORDER == "IROHA" || base == "N") base else row_of[[base]]
            if (heading == previous) {
                groups[length(groups)] <- paste(groups[length(groups)],word$text)
            } else {
                groups <- c(groups,paste0(heading,": ",word$text))
                previous <- heading
            }
        }
        return(paste(groups,collapse="; "))
    }
    if (command == "FIND") {
        matches <- Filter(function(word) wildcard_matches(tokens,word$ids),word_list)
        prefix <- paste(length(matches),"of",length(word_list))
        return(if (length(matches) == 0) prefix else paste0(prefix,": ",paste(vapply(matches,function(word) word$text,character(1)),collapse=" ")))
    }
    if (command == "HAIKU") {
        counts <- rep(0,count_character(text,"/")+1)
        for (word in word_list) counts[word$part] <- counts[word$part]+length(word$ids)
        expected <- if (length(counts) == 3) c(5,7,5) else c(5,7,5,7,7)
        verdict <- if (identical(counts,expected)) "OK" else "NG"
        form <- if (length(counts) == 3) "haiku" else "tanka"
        return(paste(verdict,form,paste(counts,collapse="-")))
    }
    if (command == "KAIBUN") {
        bases <- unlist(lapply(word_list,function(word) vapply(elements(word$ids),function(item) item$base,character(1))),use.names=FALSE)
        return(paste(if (identical(bases,rev(bases))) "YES" else "NO",paste(bases,collapse=".")))
    }
    seen <- list()
    previous <- ""
    for (i in seq_along(word_list)) {
        word <- word_list[[i]]
        items <- elements(word$ids)
        head <- items[[1]]$base
        tail <- items[[length(items)]]$base
        prefix <- paste0("NG ",i,": ",word$text)
        if (i > 1 && head != previous) return(paste(prefix,"must start with",spelling(system,previous)))
        if (any(vapply(seen,function(ids) identical(ids,word$ids),logical(1)))) return(paste(prefix,"is repeated"))
        if (tail == "N") return(paste(prefix,"ends with N"))
        seen[[length(seen)+1]] <- word$ids
        previous <- tail
    }
    paste("OK",length(word_list))
}

main <- function() {
    input <- readLines(file("stdin"),warn=FALSE)
    count <- as.integer(input[1])
    settings <- new.env(parent=emptyenv())
    settings$LONG <- "KEEP"
    settings$CASE <- "KEEP"
    settings$ORDER <- "GOJUON"
    for (i in seq_len(count)) {
        output <- tryCatch(execute(input[i+1],settings),error=function(e) paste("ERROR",conditionMessage(e)))
        cat(output,"\n",sep="")
    }
}
main()
