signatures <- list(
    ABS=c("I"), SGN=c("I"), INT=c("I"), SQR=c("I"), RND=c("I"),
    LEN=c("S"), ASC=c("S"), VAL=c("S"), "CHR$"=c("I"), "STR$"=c("I"),
    "LEFT$"=c("SI"), "RIGHT$"=c("SI"), "MID$"=c("SI","SII"), INSTR=c("SS")
)

error_codes <- c(
    "NEXT WITHOUT FOR"=1, "RETURN WITHOUT GOSUB"=3, "OUT OF DATA"=4,
    "ILLEGAL FUNCTION CALL"=5, OVERFLOW=6, "OUT OF MEMORY"=7,
    "UNDEFINED LINE NUMBER"=8, "SUBSCRIPT OUT OF RANGE"=9,
    "DUPLICATE DEFINITION"=10, "DIVISION BY ZERO"=11,
    "TYPE MISMATCH"=13, "STRING TOO LONG"=15, "RESUME WITHOUT ERROR"=20,
    "FOR WITHOUT NEXT"=26, "WHILE WITHOUT WEND"=29,
    "WEND WITHOUT WHILE"=30, "INPUT PAST END"=62
)

operators <- list(
    c("OR"), c("AND"), character(),
    c("=","<>","<",">","<=",">="),
    c("+","-"), c("*","/","MOD"), character(), c("^")
)

syntax <- function() {
    stop(structure(list(message="SYNTAX ERROR",call=NULL),
                   class=c("syntax_fault","error","condition")))
}

fault <- function(reason) {
    stop(structure(list(message=reason,call=NULL),
                   class=c("basic_fault","error","condition")))
}

variable_name <- function(word) {
    if (!grepl("^[A-Z]",word)) return(FALSE)
    letters <- strsplit(word,"",fixed=TRUE)[[1]]
    if (length(letters)>1L && tail(letters,1L)=="$") letters <- head(letters,-1L)
    if (length(letters)==1L) return(TRUE)
    length(letters)==2L && grepl("^[0-9]$",letters[[2]])
}

name_type <- function(name) {
    if (endsWith(name,"$")) "S" else "I"
}

value_type <- function(value) {
    if (is.character(value)) "S" else "I"
}

expr <- function(kind,type,value,args=list()) {
    list(kind=kind,type=type,value=value,args=args)
}

new_stmt <- function(kind) {
    s <- new.env(parent=emptyenv())
    s$kind <- kind
    s$line <- 0
    s$following <- NULL
    s$expr <- NULL
    s$target <- NULL
    s$targets <- list()
    s$expressions <- list()
    s$values <- list()
    s$numbers <- numeric()
    s$name <- ""
    s$mode <- ""
    s$clauses <- list()
    s$items <- list()
    s
}

tokenize <- function(text) {
    tokens <- list()
    p <- 1L
    n <- nchar(text,type="bytes")
    take_word <- function(start,stop) substr(text,start,stop)
    add <- function(kind,word,value) {
        tokens[[length(tokens)+1L]] <<- list(kind=kind,text=word,value=value)
    }
    while (p<=n) {
        ch <- substr(text,p,p)
        if (ch==" ") {
            p <- p+1L
        } else if (ch=="\"") {
            ending <- regexpr("\"",substring(text,p+1L),fixed=TRUE)[[1]]
            if (ending<0L) syntax()
            ending <- p+ending
            add("S",take_word(p,ending),take_word(p+1L,ending-1L))
            p <- ending+1L
        } else if (grepl("^[0-9]$",ch)) {
            start <- p
            while (p<=n && grepl("^[0-9]$",substr(text,p,p))) p <- p+1L
            word <- take_word(start,p-1L)
            value <- suppressWarnings(as.numeric(word))
            if (!is.finite(value) || value>32767) syntax()
            add("I",word,value)
        } else if (grepl("^[A-Z]$",ch)) {
            if (substr(text,p,p+2L)=="REM") {
                add("W","REM","REM")
                break
            }
            start <- p
            while (p<=n && grepl("^[A-Z0-9]$",substr(text,p,p))) p <- p+1L
            if (p<=n && substr(text,p,p)=="$") p <- p+1L
            word <- take_word(start,p-1L)
            add("W",word,word)
        } else {
            if (!grepl(ch,"+-*/^=<>() ,;:",fixed=TRUE)) syntax()
            word <- substr(text,p,p+1L)
            if (!word %in% c("<>","<=",">=")) word <- ch
            add("P",word,word)
            p <- p+nchar(word,type="bytes")
        }
    }
    add("E","","")
    tokens
}

Parser <- function(tokens) {
    p <- new.env(parent=emptyenv())
    p$tokens <- tokens
    p$position <- 1L
    p$current <- function() p$tokens[[p$position]]
    p$at <- function(word) {
        t <- p$current()
        t$kind %in% c("W","P") && t$text==word
    }
    p$take <- function(word) {
        if (!p$at(word)) return(FALSE)
        p$position <- p$position+1L
        TRUE
    }
    p$expect <- function(word) if (!p$take(word)) syntax()
    p$number <- function() {
        t <- p$current()
        if (t$kind!="I") syntax()
        p$position <- p$position+1L
        t$value
    }
    p$integer <- function(level=0L) {
        e <- p$expression(level)
        if (e$type!="I") syntax()
        e
    }
    p$target <- function() {
        t <- p$current()
        if (t$kind!="W" || !variable_name(t$text)) syntax()
        p$position <- p$position+1L
        args <- list()
        if (p$take("(")) {
            args[[1]] <- p$integer()
            if (p$take(",")) args[[2]] <- p$integer()
            p$expect(")")
        }
        expr(if (length(args)==0) "variable" else "array",
             name_type(t$text),t$text,args)
    }
    p$primary <- function() {
        t <- p$current()
        if (t$kind %in% c("I","S")) {
            p$position <- p$position+1L
            return(expr("constant",t$kind,t$value))
        }
        if (p$take("(")) {
            e <- p$expression()
            p$expect(")")
            return(e)
        }
        if (t$kind=="W" && variable_name(t$text)) return(p$target())
        if (p$take("ERR")) return(expr("builtin","I","ERR"))
        if (p$take("ERL")) return(expr("builtin","I","ERL"))
        if (t$kind=="W" && !is.null(signatures[[t$text]])) {
            p$position <- p$position+1L
            p$expect("(")
            args <- list(p$expression())
            while (p$take(",")) args[[length(args)+1L]] <- p$expression()
            p$expect(")")
            signature <- paste(vapply(args,function(e) e$type,""),collapse="")
            if (!signature %in% signatures[[t$text]]) syntax()
            return(expr("call",name_type(t$text),t$text,args))
        }
        syntax()
    }
    p$expression <- function(level=0L) {
        if (level==2L && p$take("NOT"))
            return(expr("unary","I","NOT",list(p$integer(2L))))
        if (level==6L && p$take("-"))
            return(expr("unary","I","-",list(p$integer(6L))))
        if (level==8L) return(p$primary())
        left <- p$expression(level+1L)
        while (p$current()$text %in% operators[[level+1L]]) {
            op <- p$current()$text
            p$position <- p$position+1L
            right <- p$expression(if (level==7L) 6L else level+1L)
            if (left$type!=right$type ||
                (left$type=="S" && level!=3L && op!="+")) syntax()
            left <- expr("binary",if (level==3L) "I" else left$type,
                         op,list(left,right))
            if (level==7L) break
        }
        left
    }
    p$clause <- function() {
        if (p$current()$kind=="I") return(list(line=p$number(),body=list()))
        list(line=NULL,body=p$listing(TRUE))
    }
    p$listing <- function(in_clause=FALSE) {
        statements <- list(p$statement(in_clause))
        while (p$take(":"))
            statements[[length(statements)+1L]] <- p$statement(in_clause)
        statements
    }
    p$statement <- function(in_clause) {
        word <- p$current()$text
        if (in_clause && word %in% c("IF","FOR","NEXT","WHILE","WEND","DATA"))
            syntax()
        s <- new_stmt(word)
        for (kind in c("REM","RETURN","WEND","END","STOP"))
            if (p$take(kind)) return(s)
        if (p$take("PRINT")) {
            expression_last <- FALSE
            while (p$current()$kind!="E" && !p$at(":") && !p$at("ELSE")) {
                if (p$take(";")) {
                    s$items[[length(s$items)+1L]] <- list(kind=";",node=NULL)
                    expression_last <- FALSE
                } else if (p$take(",")) {
                    s$items[[length(s$items)+1L]] <- list(kind=",",node=NULL)
                    expression_last <- FALSE
                } else {
                    kind <- if (p$at("TAB")) "TAB" else if (p$at("SPC")) "SPC" else "value"
                    if (kind=="value" && expression_last) syntax()
                    if (kind=="value") {
                        e <- p$expression()
                    } else {
                        p$position <- p$position+1L
                        p$expect("(")
                        e <- p$integer()
                        p$expect(")")
                    }
                    s$items[[length(s$items)+1L]] <- list(kind=kind,node=e)
                    expression_last <- kind=="value"
                }
            }
            return(s)
        }
        if (p$take("INPUT") || p$take("READ") || p$take("DIM")) {
            repeat {
                target <- p$target()
                if (word=="DIM" && target$kind!="array") syntax()
                s$targets[[length(s$targets)+1L]] <- target
                if (!p$take(",")) break
            }
            return(s)
        }
        if (p$take("DATA")) {
            repeat {
                negative <- p$take("-")
                t <- p$current()
                if (t$kind!="I" && (t$kind!="S" || negative)) syntax()
                p$position <- p$position+1L
                s$values[[length(s$values)+1L]] <- if (negative) -t$value else t$value
                if (!p$take(",")) break
            }
            return(s)
        }
        if (p$take("IF")) {
            s$expr <- p$integer()
            p$expect("THEN")
            s$clauses[[1]] <- p$clause()
            if (p$take("ELSE")) s$clauses[[2]] <- p$clause()
            if (p$current()$kind!="E") syntax()
            return(s)
        }
        if (p$take("GOTO") || p$take("GOSUB")) {
            s$numbers <- c(s$numbers,p$number())
            return(s)
        }
        if (p$take("ON")) {
            if (p$take("ERROR")) {
                s$kind <- "handler"
                p$expect("GOTO")
                s$numbers <- c(s$numbers,p$number())
            } else {
                s$expr <- p$integer()
                if (p$take("GOTO")) {
                    s$mode <- "GOTO"
                } else {
                    p$expect("GOSUB")
                    s$mode <- "GOSUB"
                }
                s$numbers <- c(s$numbers,p$number())
                while (p$take(",")) s$numbers <- c(s$numbers,p$number())
            }
            return(s)
        }
        if (p$take("RESUME")) {
            if (p$take("NEXT")) {
                s$mode <- "NEXT"
            } else if (p$current()$kind=="I") {
                s$mode <- "line"
                s$numbers <- c(s$numbers,p$number())
            }
            return(s)
        }
        if (p$take("FOR")) {
            t <- p$current()
            if (t$kind!="W" || !variable_name(t$text) || name_type(t$text)!="I")
                syntax()
            s$name <- t$text
            p$position <- p$position+1L
            p$expect("=")
            s$expressions[[1]] <- p$integer()
            p$expect("TO")
            s$expressions[[2]] <- p$integer()
            s$expressions[[3]] <- if (p$take("STEP")) p$integer() else
                                    expr("constant","I",1)
            return(s)
        }
        if (p$take("NEXT")) {
            t <- p$current()
            if (t$kind=="W" && variable_name(t$text) && name_type(t$text)=="I") {
                s$name <- t$text
                p$position <- p$position+1L
            }
            return(s)
        }
        if (p$take("WHILE") || p$take("RANDOMIZE")) {
            s$expr <- p$integer()
            return(s)
        }
        if (p$take("RESTORE")) {
            if (p$current()$kind=="I") s$numbers <- c(s$numbers,p$number())
            return(s)
        }
        p$take("LET")
        s$kind <- "assign"
        s$target <- p$target()
        p$expect("=")
        s$expr <- p$expression()
        if (s$expr$type!=s$target$type) syntax()
        s
    }
    p$parse <- function() {
        result <- p$listing()
        if (p$current()$kind!="E") syntax()
        result
    }
    p
}

Machine <- function(inputs) {
    m <- new.env(parent=emptyenv())
    m$inputs <- inputs
    m$variables <- new.env(hash=TRUE,parent=emptyenv())
    m$arrays <- new.env(hash=TRUE,parent=emptyenv())
    m$stack <- list()
    m$entries <- new.env(hash=TRUE,parent=emptyenv())
    m$sequence <- list()
    m$data <- list()
    m$data_position <- 1L
    m$input_position <- 1L
    m$random <- 1
    m$handler <- 0
    m$handling <- FALSE
    m$remembered <- NULL
    m$err <- 0
    m$erl <- 0
    m$buffer <- ""
    m$output <- character()
    m$end_line <- function() {
        m$output <- c(m$output,sub(" +$","",m$buffer))
        m$buffer <- ""
    }
    m$message <- function(text) {
        if (nchar(m$buffer,type="bytes")>0) m$end_line()
        m$output <- c(m$output,text)
    }
    m$checked <- function(n) {
        if (n < -32768 || n > 32767) fault("OVERFLOW")
        n
    }
    m$get <- function(name) {
        if (exists(name,envir=m$variables,inherits=FALSE)) {
            get(name,envir=m$variables,inherits=FALSE)
        } else if (name_type(name)=="S") {
            ""
        } else {
            0
        }
    }
    m$declare <- function(name,bounds) {
        count <- prod(bounds+1)
        initial <- if (name_type(name)=="S") "" else 0
        assign(name,list(bounds=bounds,values=rep(list(initial),count)),
               envir=m$arrays)
    }
    m$address <- function(target) {
        name <- target$value
        if (target$kind=="variable") return(list(name=name,index=NULL))
        indices <- vapply(target$args,m$evaluate,0.0)
        if (!exists(name,envir=m$arrays,inherits=FALSE))
            m$declare(name,rep(10,length(indices)))
        arr <- get(name,envir=m$arrays,inherits=FALSE)
        if (length(indices)!=length(arr$bounds)) fault("SUBSCRIPT OUT OF RANGE")
        if (any(indices<0) || any(indices>arr$bounds)) fault("SUBSCRIPT OUT OF RANGE")
        index <- 0
        for (i in seq_along(indices))
            index <- index*(arr$bounds[i]+1)+indices[i]
        list(name=name,index=index+1)
    }
    m$load <- function(place) {
        if (is.null(place$index)) return(m$get(place$name))
        arr <- get(place$name,envir=m$arrays,inherits=FALSE)
        arr$values[[place$index]]
    }
    m$store <- function(place,value) {
        if (is.null(place$index)) {
            assign(place$name,value,envir=m$variables)
        } else {
            arr <- get(place$name,envir=m$arrays,inherits=FALSE)
            arr$values[[place$index]] <- value
            assign(place$name,arr,envir=m$arrays)
        }
    }
    m$evaluate <- function(e) {
        op <- e$value
        if (e$kind=="constant") return(op)
        if (e$kind %in% c("variable","array")) return(m$load(m$address(e)))
        if (e$kind=="builtin") return(if (op=="ERR") m$err else m$erl)
        if (e$kind=="unary") {
            a <- m$evaluate(e$args[[1]])
            if (op=="NOT") return(bitwNot(as.integer(a)))
            return(m$checked(-a))
        }
        values <- lapply(e$args,m$evaluate)
        if (e$kind=="call") return(m$call(op,values))
        a <- values[[1]]
        b <- values[[2]]
        if (op %in% operators[[4]]) {
            result <- switch(op,"="=a==b,"<>"=a!=b,
                             "<"=a<b,">"=a>b,"<="=a<=b,">="=a>=b)
            return(if (result) -1 else 0)
        }
        if (e$type=="S") {
            value <- paste0(a,b)
            if (nchar(value,type="bytes")>255) fault("STRING TOO LONG")
            return(value)
        }
        if (op=="+") return(m$checked(a+b))
        if (op=="-") return(m$checked(a-b))
        if (op=="*") return(m$checked(a*b))
        if (op=="/" || op=="MOD") {
            if (b==0) fault("DIVISION BY ZERO")
            q <- if ((a<0)!=(b<0)) -floor(abs(a)/abs(b)) else floor(abs(a)/abs(b))
            return(if (op=="/") m$checked(q) else a-b*q)
        }
        if (op=="^") {
            if (b<0) fault("ILLEGAL FUNCTION CALL")
            if (abs(a)>1 && b>15) fault("OVERFLOW")
            return(m$checked(a^b))
        }
        if (op=="AND") return(bitwAnd(as.integer(a),as.integer(b)))
        if (op=="OR") return(bitwOr(as.integer(a),as.integer(b)))
        fault("ILLEGAL FUNCTION CALL")
    }
    m$call <- function(name,args) {
        a <- args[[1]]
        b <- if (length(args)>1) args[[2]] else NULL
        c <- if (length(args)>2) args[[3]] else NULL
        if (name=="ABS") return(m$checked(abs(a)))
        if (name=="SGN") return(sign(a))
        if (name=="INT") return(a)
        if (name=="SQR") {
            if (a<0) fault("ILLEGAL FUNCTION CALL")
            return(floor(sqrt(a)))
        }
        if (name=="RND") {
            if (a<1) fault("ILLEGAL FUNCTION CALL")
            m$random <- (48271*m$random)%%2147483647
            return(m$random%%a+1)
        }
        if (name=="LEN") return(nchar(a,type="bytes"))
        if (name=="ASC") {
            if (a=="") fault("ILLEGAL FUNCTION CALL")
            return(as.integer(charToRaw(substr(a,1,1))))
        }
        if (name=="VAL") {
            word <- regmatches(a,regexpr("^ *[+-]?[0-9]+",a))
            return(m$checked(if (length(word) && nzchar(word)) as.numeric(word) else 0))
        }
        if (name=="CHR$") {
            if (a<32 || a>126) fault("ILLEGAL FUNCTION CALL")
            return(intToUtf8(a))
        }
        if (name=="STR$") return(as.character(a))
        if (name=="LEFT$" || name=="RIGHT$") {
            if (b<0) fault("ILLEGAL FUNCTION CALL")
            if (name=="LEFT$") return(substr(a,1,b))
            if (b==0) return("")
            return(substr(a,max(1,nchar(a)-b+1),nchar(a)))
        }
        if (name=="MID$") {
            if (b<1 || (!is.null(c) && c<0)) fault("ILLEGAL FUNCTION CALL")
            if (!is.null(c)) return(substr(a,b,b+c-1))
            return(substr(a,b,nchar(a)))
        }
        if (name=="INSTR") {
            if (b=="") return(1)
            at <- regexpr(b,a,fixed=TRUE)[[1]]
            return(if (at<0) 0 else at)
        }
        fault("ILLEGAL FUNCTION CALL")
    }
    m$line <- function(number) {
        key <- as.character(number)
        if (!exists(key,envir=m$entries,inherits=FALSE))
            fault("UNDEFINED LINE NUMBER")
        get(key,envir=m$entries,inherits=FALSE)
    }
    m$push <- function(frame) {
        if (length(m$stack)>=100) fault("OUT OF MEMORY")
        m$stack[[length(m$stack)+1L]] <- frame
    }
    m$search <- function(kind,name="") {
        if (!length(m$stack)) return(NULL)
        for (i in seq(length(m$stack),1L,by=-1L)) {
            frame <- m$stack[[i]]
            if (frame$kind=="GOSUB") break
            if (frame$kind==kind && (name=="" || frame$name==name)) return(i)
        }
        NULL
    }
    m$matching <- function(s,opening,closing) {
        start <- which(vapply(m$sequence,identical,FALSE,s))
        depth <- 0L
        for (i in seq(start+1L,length(m$sequence))) {
            if (i>length(m$sequence)) break
            t <- m$sequence[[i]]
            if (t$kind==opening) {
                depth <- depth+1L
            } else if (t$kind==closing) {
                if (depth==0L) return(t$following)
                depth <- depth-1L
            }
        }
        fault(paste0(opening," WITHOUT ",closing))
    }
    m$subroutine <- function(number,after) {
        target <- m$line(number)
        m$push(list(kind="GOSUB",position=after,name=""))
        target
    }
    m$execute <- function(s) {
        following <- s$following
        if (s$kind=="assign") {
            place <- m$address(s$target)
            m$store(place,m$evaluate(s$expr))
        } else if (s$kind=="PRINT") {
            for (item in s$items) {
                if (item$kind==",") {
                    m$buffer <- paste0(m$buffer,
                                       strrep(" ",10-nchar(m$buffer)%%10))
                } else if (item$kind!=";") {
                    value <- m$evaluate(item$node)
                    if (item$kind=="value") {
                        m$buffer <- paste0(m$buffer,as.character(value))
                    } else {
                        if (value<0) fault("ILLEGAL FUNCTION CALL")
                        amount <- if (item$kind=="SPC") value else
                                  max(0,value-nchar(m$buffer,type="bytes"))
                        m$buffer <- paste0(m$buffer,strrep(" ",amount))
                    }
                }
            }
            if (!length(s$items) ||
                !(tail(s$items,1L)[[1]]$kind %in% c(";",","))) m$end_line()
        } else if (s$kind %in% c("INPUT","READ")) {
            for (target in s$targets) {
                place <- m$address(target)
                if (s$kind=="READ") {
                    if (m$data_position>length(m$data)) fault("OUT OF DATA")
                    value <- m$data[[m$data_position]]$value
                    m$data_position <- m$data_position+1L
                    if (value_type(value)!=target$type) fault("TYPE MISMATCH")
                } else {
                    repeat {
                        if (m$input_position>length(m$inputs)) fault("INPUT PAST END")
                        text <- m$inputs[[m$input_position]]
                        m$input_position <- m$input_position+1L
                        if (target$type=="S") {value <- text;break}
                        valid <- grepl("^-?[0-9]+$",text)
                        n <- suppressWarnings(as.numeric(text))
                        if (valid && is.finite(n) && n>=-32768 && n<=32767) {
                            value <- n
                            break
                        }
                        m$message("?REDO FROM START")
                    }
                }
                m$store(place,value)
            }
        } else if (s$kind=="RESTORE") {
            if (!length(s$numbers)) {
                m$data_position <- 1L
            } else {
                number <- s$numbers[[1]]
                m$line(number)
                m$data_position <- length(m$data)+1L
                for (i in seq_along(m$data)) {
                    if (m$data[[i]]$line>=number) {
                        m$data_position <- i
                        break
                    }
                }
            }
        } else if (s$kind=="IF") {
            index <- if (m$evaluate(s$expr)==0) 2L else 1L
            if (index<=length(s$clauses)) {
                chosen <- s$clauses[[index]]
                following <- if (is.null(chosen$line)) chosen$body[[1]] else
                             m$line(chosen$line)
            }
        } else if (s$kind=="GOTO") {
            following <- m$line(s$numbers[[1]])
        } else if (s$kind=="GOSUB") {
            following <- m$subroutine(s$numbers[[1]],following)
        } else if (s$kind=="ON") {
            n <- m$evaluate(s$expr)
            if (n<0) fault("ILLEGAL FUNCTION CALL")
            if (n>=1 && n<=length(s$numbers)) {
                following <- if (s$mode=="GOTO") m$line(s$numbers[[n]]) else
                             m$subroutine(s$numbers[[n]],following)
            }
        } else if (s$kind=="RETURN") {
            indices <- which(vapply(m$stack,function(f) f$kind=="GOSUB",FALSE))
            if (!length(indices)) fault("RETURN WITHOUT GOSUB")
            index <- max(indices)
            following <- m$stack[[index]]$position
            m$stack <- if (index>1) m$stack[seq_len(index-1L)] else list()
        } else if (s$kind=="FOR") {
            values <- vapply(s$expressions,m$evaluate,0.0)
            start <- values[[1]]
            final <- values[[2]]
            step <- values[[3]]
            if (step==0) fault("ILLEGAL FUNCTION CALL")
            index <- m$search("FOR",s$name)
            if (!is.null(index))
                m$stack <- if (index>1) m$stack[seq_len(index-1L)] else list()
            assign(s$name,start,envir=m$variables)
            if ((step>0 && start>final) || (step<0 && start<final)) {
                following <- m$matching(s,"FOR","NEXT")
            } else {
                m$push(list(kind="FOR",position=following,name=s$name,
                            final=final,step=step))
            }
        } else if (s$kind=="NEXT") {
            index <- m$search("FOR",s$name)
            if (is.null(index)) fault("NEXT WITHOUT FOR")
            m$stack <- m$stack[seq_len(index)]
            frame <- m$stack[[index]]
            value <- m$checked(m$get(frame$name)+frame$step)
            assign(frame$name,value,envir=m$variables)
            if ((frame$step>0 && value>frame$final) ||
                (frame$step<0 && value<frame$final)) {
                m$stack <- if (index>1) m$stack[seq_len(index-1L)] else list()
            } else {
                following <- frame$position
            }
        } else if (s$kind=="WHILE") {
            if (m$evaluate(s$expr)==0) {
                following <- m$matching(s,"WHILE","WEND")
            } else {
                m$push(list(kind="WHILE",position=s,name=""))
            }
        } else if (s$kind=="WEND") {
            index <- m$search("WHILE")
            if (is.null(index)) fault("WEND WITHOUT WHILE")
            following <- m$stack[[index]]$position
            m$stack <- if (index>1) m$stack[seq_len(index-1L)] else list()
        } else if (s$kind=="DIM") {
            for (target in s$targets) {
                name <- target$value
                bounds <- vapply(target$args,m$evaluate,0.0)
                if (exists(name,envir=m$arrays,inherits=FALSE))
                    fault("DUPLICATE DEFINITION")
                if (any(bounds<0)) fault("ILLEGAL FUNCTION CALL")
                if (prod(bounds+1)>10000) fault("OUT OF MEMORY")
                m$declare(name,bounds)
            }
        } else if (s$kind=="RANDOMIZE") {
            n <- m$evaluate(s$expr)
            if (n<1) fault("ILLEGAL FUNCTION CALL")
            m$random <- n
        } else if (s$kind=="handler") {
            if (s$numbers[[1]]!=0) m$line(s$numbers[[1]])
            m$handler <- s$numbers[[1]]
        } else if (s$kind=="RESUME") {
            if (!m$handling) fault("RESUME WITHOUT ERROR")
            following <- if (s$mode=="line") {
                m$line(s$numbers[[1]])
            } else if (s$mode=="NEXT") {
                m$remembered$following
            } else {
                m$remembered
            }
            m$handling <- FALSE
        } else if (s$kind=="STOP") {
            m$message(paste0("BREAK IN LINE ",s$line))
            return(NULL)
        } else if (s$kind=="END") {
            return(NULL)
        }
        following
    }
    m$connect <- function(body,after,number) {
        following <- after
        for (i in rev(seq_along(body))) {
            s <- body[[i]]
            s$line <- number
            s$following <- following
            for (clause in s$clauses) m$connect(clause$body,following,number)
            following <- s
        }
    }
    m$finish <- function() {
        if (nchar(m$buffer,type="bytes")>0) m$end_line()
        c(m$output,"READY")
    }
    m$run <- function(source) {
        parsed <- list()
        for (key in sort(as.numeric(names(source)))) {
            number <- as.numeric(key)
            code <- source[[as.character(key)]]
            body <- tryCatch(Parser(tokenize(code))$parse(),error=function(e) e)
            if (inherits(body,"error")) {
                m$message(paste0("ERROR IN LINE ",number,": SYNTAX ERROR"))
                return(m$finish())
            }
            parsed[[length(parsed)+1L]] <- list(number=number,body=body)
        }
        after <- NULL
        for (entry in rev(parsed)) {
            m$connect(entry$body,after,entry$number)
            assign(as.character(entry$number),entry$body[[1]],envir=m$entries)
            after <- entry$body[[1]]
        }
        for (entry in parsed) {
            for (s in entry$body) {
                m$sequence[[length(m$sequence)+1L]] <- s
                if (s$kind=="DATA") {
                    for (value in s$values)
                        m$data[[length(m$data)+1L]] <- list(line=s$line,value=value)
                }
            }
        }
        position <- after
        while (!is.null(position)) {
            current <- position
            result <- tryCatch(m$execute(current),error=function(e) e)
            if (inherits(result,"error")) {
                failure <- conditionMessage(result)
                if (m$handler!=0 && !m$handling) {
                    m$err <- if (failure %in% names(error_codes))
                             unname(error_codes[[failure]]) else 0
                    m$erl <- current$line
                    m$remembered <- current
                    m$handling <- TRUE
                    position <- tryCatch(m$line(m$handler),error=function(e) {
                        m$message(paste0("ERROR IN LINE ",current$line,": ",
                                         conditionMessage(e)))
                        NULL
                    })
                } else {
                    m$message(paste0("ERROR IN LINE ",current$line,": ",failure))
                    position <- NULL
                }
            } else {
                position <- result
            }
        }
        m$finish()
    }
    m
}

lines <- readLines("stdin",warn=FALSE)
cursor <- 2L
output <- character()
for (i in seq_len(as.integer(lines[[1]]))) {
    source <- list()
    while (lines[[cursor]]!="RUN") {
        line <- lines[[cursor]]
        cursor <- cursor+1L
        parts <- regmatches(line,regexec("^([0-9]+)(?: +(.*))?$",line))[[1]]
        number <- as.numeric(parts[[2]])
        key <- as.character(number)
        if (length(parts)>2L) {
            source[[key]] <- parts[[3]]
        } else {
            source[[key]] <- NULL
        }
    }
    cursor <- cursor+1L
    inputs <- character()
    while (lines[[cursor]]!="END") {
        inputs <- c(inputs,lines[[cursor]])
        cursor <- cursor+1L
    }
    cursor <- cursor+1L
    output <- c(output,Machine(inputs)$run(source))
}
cat(paste(output,collapse="\n"),"\n",sep="")
