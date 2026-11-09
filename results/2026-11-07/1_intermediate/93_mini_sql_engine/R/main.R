reserved <- strsplit("SELECT DISTINCT FROM AS JOIN INNER LEFT OUTER ON WHERE GROUP BY HAVING ORDER ASC DESC LIMIT OFFSET INSERT INTO VALUES UPDATE SET DELETE CREATE TABLE DROP PRIMARY KEY NOT NULL INT TEXT AND OR IS IN BETWEEN LIKE COUNT SUM MIN MAX AVG EXIT", " ", fixed = TRUE)[[1]]
aggregates <- c("COUNT", "SUM", "MIN", "MAX", "AVG")
comparisons <- c("=", "<>", "!=", "<", "<=", ">", ">=")
sql_null <- NA
fail <- function(reason) stop(reason, call. = FALSE)
is_null <- function(x) length(x) == 1L && is.na(x)
value_text <- function(x) if (is_null(x)) "NULL" else as.character(x)
truth <- function(x) !is_null(x) && is.numeric(x) && x != 0
value_type <- function(x) if (is_null(x)) "NULL" else if (is.numeric(x)) "INT" else "TEXT"
compatible <- function(a,b) a == b || a == "NULL" || b == "NULL"
require_type <- function(a,b,op) if (!compatible(a,b)) fail(paste0("type mismatch for ",op))
compare <- function(a,b) {
  if (is.numeric(a)) return(sign(a-b))
  if (a == b) return(0L)
  left <- utf8ToInt(a)
  right <- utf8ToInt(b)
  count <- min(length(left),length(right))
  if (count > 0L) {
    for (i in seq_len(count)) {
      if (left[i] != right[i]) return(sign(left[i]-right[i]))
    }
  }
  sign(length(left)-length(right))
}
quotient <- function(a,b) trunc(a/b)
otherwise <- function(a,b) if (is.null(a)) b else a

split_statements <- function(source) {
  chars <- strsplit(source,"",fixed=TRUE)[[1]]
  out <- character()
  pending <- character()
  quoted <- FALSE
  comment <- FALSE
  i <- 1L
  while (i <= length(chars)) {
    character <- chars[i]
    if (comment) {
      if (character == "\n") {
        comment <- FALSE
        pending <- c(pending,"\n")
      }
    } else if (!quoted && character == "-" && i < length(chars) && chars[i+1L] == "-") {
      comment <- TRUE
      i <- i+1L
    } else {
      pending <- c(pending,character)
      if (character == "'") quoted <- !quoted
      if (character == ";" && !quoted) {
        out <- c(out,paste0(pending,collapse=""))
        pending <- character()
      }
    }
    i <- i+1L
  }
  out
}

token <- function(kind,value,text) list(kind=kind,value=value,text=text)
tokenize <- function(source) {
  out <- list()
  i <- 1L
  n <- nchar(source,type="bytes")
  while (i <= n) {
    rest <- substr(source,i,n)
    if (grepl("^[ \n]",rest)) {
      i <- i+1L
      next
    }
    if (startsWith(rest,"--")) {
      end <- regexpr("\n",rest,fixed=TRUE)[1]
      i <- if (end < 0L) n+1L else i+end
      next
    }
    if (startsWith(rest,"'")) {
      closing <- regexpr("'",substring(rest,2L),fixed=TRUE)[1]
      if (closing < 0L) fail("unexpected character '''")
      word <- substr(rest,1L,closing+1L)
      out[[length(out)+1L]] <- token("string",substr(word,2L,nchar(word)-1L),word)
      i <- i+nchar(word)
      next
    }
    found <- regexpr("^[0-9]+|^[A-Za-z_][A-Za-z0-9_]*|^(<>|!=|<=|>=|\\|\\|)|^[(),.;*/%+\\-=<>]",rest,perl=TRUE)
    if (found[1] < 0L) fail(paste0("unexpected character '",substr(rest,1L,1L),"'"))
    word <- substr(rest,1L,attr(found,"match.length"))
    item <- if (grepl("^[0-9]",word)) {
      token("integer",as.numeric(word),word)
    } else if (grepl("^[A-Za-z_]",word)) {
      upper <- toupper(word)
      if (upper %in% reserved) token("keyword",upper,word) else token("name",word,word)
    } else {
      token("symbol",word,word)
    }
    out[[length(out)+1L]] <- item
    i <- i+nchar(word)
  }
  out[[length(out)+1L]] <- token("eof","","<EOF>")
  out
}

expr <- function(kind,op="",args=list(),value=NA,table=NULL,column=NULL,text="",
                 distinct=FALSE,negated=FALSE) {
  e <- new.env(parent=emptyenv())
  e$kind <- kind
  e$op <- op
  e$args <- args
  e$value <- value
  e$table <- table
  e$column <- column
  e$text <- text
  e$index <- NULL
  e$distinct <- distinct
  e$negated <- negated
  e
}

parser <- function(tokens) {
  p <- new.env(parent=emptyenv())
  p$tokens <- tokens
  p$i <- 1L
  p
}
peek <- function(p) p$tokens[[p$i]]
take <- function(p) {
  item <- peek(p)
  p$i <- p$i+1L
  item
}
at <- function(p,words) peek(p)$kind %in% c("keyword","symbol") && peek(p)$value %in% words
accept <- function(p,word) {
  if (!at(p,word)) return(FALSE)
  p$i <- p$i+1L
  TRUE
}
syntax_error <- function(p) fail(paste0("syntax error at '",peek(p)$text,"'"))
expect <- function(p,word) if (!accept(p,word)) syntax_error(p)
kind <- function(p,k) {
  if (peek(p)$kind != k) syntax_error(p)
  take(p)$value
}
comma <- function(p,reader) {
  a <- list(reader(p))
  while (accept(p,",")) a[[length(a)+1L]] <- reader(p)
  a
}
parens <- function(p,reader) {
  expect(p,"(")
  result <- comma(p,reader)
  expect(p,")")
  result
}
alias_name <- function(p) {
  if (accept(p,"AS")) return(kind(p,"name"))
  if (peek(p)$kind == "name") return(take(p)$value)
  NULL
}
clause <- function(p,word) if (accept(p,word)) parse_expression(p) else NULL
table_ref <- function(p) {
  name <- kind(p,"name")
  c(name,otherwise(alias_name(p),name))
}
reference <- function(p) {
  name <- kind(p,"name")
  if (accept(p,".")) {
    column <- kind(p,"name")
    expr("ref",table=name,column=column,text=paste0(name,".",column))
  } else expr("ref",column=name,text=name)
}

parse_binary <- function(p,operators,next_reader) {
  e <- next_reader(p)
  while (at(p,operators)) {
    op <- take(p)$value
    e <- expr("binary",op,list(e,next_reader(p)))
  }
  e
}
parse_expression <- function(p) parse_binary(p,"OR",parse_and)
parse_and <- function(p) parse_binary(p,"AND",parse_not)
parse_not <- function(p) if (accept(p,"NOT")) expr("unary","NOT",list(parse_not(p))) else parse_comparison(p)
parse_comparison <- function(p) {
  e <- parse_additive(p)
  if (at(p,comparisons)) return(expr("binary",take(p)$value,list(e,parse_additive(p))))
  if (accept(p,"IS")) {
    neg <- accept(p,"NOT")
    expect(p,"NULL")
    return(expr("isnull",args=list(e),negated=neg))
  }
  neg <- accept(p,"NOT")
  if (accept(p,"IN")) return(expr("in",args=c(list(e),parens(p,parse_expression)),negated=neg))
  if (accept(p,"BETWEEN")) {
    a <- parse_additive(p)
    expect(p,"AND")
    return(expr("between",args=list(e,a,parse_additive(p)),negated=neg))
  }
  if (accept(p,"LIKE")) return(expr("like",args=list(e,parse_additive(p)),negated=neg))
  if (neg) syntax_error(p)
  e
}
parse_additive <- function(p) parse_binary(p,c("+","-","||"),parse_multiplicative)
parse_multiplicative <- function(p) parse_binary(p,c("*","/","%"),parse_unary)
parse_unary <- function(p) if (accept(p,"-")) expr("unary","-",list(parse_unary(p))) else parse_primary(p)
parse_primary <- function(p) {
  if (peek(p)$kind %in% c("integer","string")) return(expr("literal",value=take(p)$value))
  if (accept(p,"NULL")) return(expr("literal",value=sql_null))
  if (peek(p)$kind == "name") return(reference(p))
  if (at(p,aggregates)) {
    name <- take(p)$value
    expect(p,"(")
    if (name == "COUNT" && accept(p,"*")) {
      args <- list()
      distinct <- FALSE
    } else {
      distinct <- accept(p,"DISTINCT")
      args <- list(parse_expression(p))
    }
    expect(p,")")
    return(expr("aggregate",name,args,distinct=distinct))
  }
  if (accept(p,"(")) {
    e <- parse_expression(p)
    expect(p,")")
    return(e)
  }
  syntax_error(p)
}
expr_tokens <- function(p) {
  start <- p$i
  e <- parse_expression(p)
  list(expr=e,tokens=p$tokens[start:(p$i-1L)])
}
select_item <- function(p) {
  value <- expr_tokens(p)
  name <- alias_name(p)
  e <- value$expr
  tokens <- value$tokens
  if (!is.null(name)) {
    heading <- name
  } else if (e$kind == "ref" && tokens[[1]]$kind == "name") {
    heading <- e$column
  } else {
    parts <- character()
    for (i in seq_along(tokens)) {
      item <- tokens[[i]]
      space <- i > 1L && item$kind != "symbol" && tokens[[i-1L]]$kind != "symbol"
      parts <- c(parts,paste0(if(space) " " else "",item$text))
    }
    heading <- paste0(parts,collapse="")
  }
  list(expr=e,alias=name,heading=heading)
}
order_item <- function(p) {
  item <- expr_tokens(p)
  desc <- accept(p,"DESC")
  if (!desc) accept(p,"ASC")
  list(expr=item$expr,tokens=item$tokens,desc=desc)
}
select_query <- function(p) {
  q <- list(kind="select",distinct=accept(p,"DISTINCT"))
  q$items <- if (accept(p,"*")) NULL else comma(p,select_item)
  expect(p,"FROM")
  q$source <- table_ref(p)
  q$joins <- list()
  while (at(p,c("JOIN","INNER","LEFT"))) {
    left <- accept(p,"LEFT")
    if (left) accept(p,"OUTER") else accept(p,"INNER")
    expect(p,"JOIN")
    ref <- table_ref(p)
    expect(p,"ON")
    q$joins[[length(q$joins)+1L]] <- list(table=ref,left=left,condition=parse_expression(p))
  }
  q$where <- clause(p,"WHERE")
  q$group <- list()
  if (accept(p,"GROUP")) {
    expect(p,"BY")
    q$group <- comma(p,reference)
  }
  q$having <- clause(p,"HAVING")
  q$order <- list()
  if (accept(p,"ORDER")) {
    expect(p,"BY")
    q$order <- comma(p,order_item)
  }
  q$limit <- NULL
  q$offset <- NULL
  if (accept(p,"LIMIT")) {
    q$limit <- kind(p,"integer")
    if (accept(p,"OFFSET")) q$offset <- kind(p,"integer")
  }
  q
}
parse_statement <- function(p) {
  result <- NULL
  if (accept(p,"CREATE")) {
    expect(p,"TABLE")
    name <- kind(p,"name")
    column <- function(p) {
      n <- kind(p,"name")
      if (!at(p,c("INT","TEXT"))) syntax_error(p)
      type <- take(p)$value
      primary <- 0L
      not_null <- FALSE
      repeat {
        if (accept(p,"PRIMARY")) {
          expect(p,"KEY")
          primary <- primary+1L
        } else if (accept(p,"NOT")) {
          expect(p,"NULL")
          not_null <- TRUE
        } else break
      }
      list(name=n,type=type,not_null=not_null,primary=primary)
    }
    result <- list(kind="create",name=name,columns=parens(p,column))
  } else if (accept(p,"DROP")) {
    expect(p,"TABLE")
    result <- list(kind="drop",name=kind(p,"name"))
  } else if (accept(p,"INSERT")) {
    expect(p,"INTO")
    name <- kind(p,"name")
    cols <- if (at(p,"(")) unlist(parens(p,function(p) kind(p,"name"))) else NULL
    expect(p,"VALUES")
    tuples <- comma(p,function(p) parens(p,parse_expression))
    result <- list(kind="insert",name=name,columns=cols,tuples=tuples)
  } else if (accept(p,"UPDATE")) {
    name <- kind(p,"name")
    expect(p,"SET")
    assignments <- comma(p,function(p) {
      name <- kind(p,"name")
      expect(p,"=")
      list(name=name,expr=parse_expression(p))
    })
    result <- list(kind="update",name=name,assignments=assignments,where=clause(p,"WHERE"))
  } else if (accept(p,"DELETE")) {
    expect(p,"FROM")
    result <- list(kind="delete",name=kind(p,"name"),where=clause(p,"WHERE"))
  } else if (accept(p,"SELECT")) {
    result <- select_query(p)
  } else if (accept(p,"EXIT")) {
    result <- list(kind="exit")
  } else if (!at(p,";")) syntax_error(p)
  expect(p,";")
  if (peek(p)$kind != "eof") syntax_error(p)
  result
}

scope <- function() {
  s <- new.env(parent=emptyenv())
  s$entries <- list()
  s$width <- 0L
  s
}
scope_add <- function(s,name,t) {
  if (any(vapply(s$entries,function(e) e$name == name,FALSE)))
    fail(paste0("duplicate table name ",name))
  s$entries[[length(s$entries)+1L]] <- list(name=name,table=t,offset=s$width)
  s$width <- s$width+length(t$columns)
}
resolve <- function(s,ref) {
  entries <- if (is.null(ref$table)) s$entries else Filter(function(e) e$name == ref$table,s$entries)
  if (!is.null(ref$table) && length(entries) == 0L) fail(paste0("unknown table ",ref$table))
  matches <- list()
  for (entry in entries) {
    indices <- which(vapply(entry$table$columns,function(c) c$name == ref$column,FALSE))
    for (i in indices)
      matches[[length(matches)+1L]] <- list(index=entry$offset+i,type=entry$table$columns[[i]]$type)
  }
  if (length(matches) == 0L) fail(paste0("unknown column ",ref$text))
  if (length(matches) > 1L) fail(paste0("ambiguous column ",ref$column))
  ref$index <- matches[[1]]$index
  matches[[1]]$type
}

check_expr <- function(e,s,aggregates_allowed=FALSE,grouped=NULL,inside=FALSE) {
  if (e$kind == "literal") return(value_type(e$value))
  if (e$kind == "ref") {
    type <- resolve(s,e)
    if (!is.null(grouped) && !inside && !(e$index %in% grouped))
      fail(paste0("column ",e$text," is not grouped"))
    return(type)
  }
  if (e$kind == "aggregate") {
    if (!aggregates_allowed || inside) fail(paste0("misuse of aggregate ",e$op))
    if (length(e$args) == 0L) return("INT")
    type <- check_expr(e$args[[1]],s,aggregates_allowed,grouped,TRUE)
    if (e$op %in% c("SUM","AVG")) require_type(type,"INT",e$op)
    return(if (e$op %in% c("MIN","MAX")) type else "INT")
  }
  types <- vapply(e$args,function(a) check_expr(a,s,aggregates_allowed,grouped,inside),"")
  if (e$kind == "unary") {
    require_type(types[1],"INT",e$op)
    return("INT")
  }
  if (e$kind == "binary") {
    if (e$op %in% comparisons) {
      require_type(types[1],types[2],e$op)
    } else {
      type <- if (e$op == "||") "TEXT" else "INT"
      for (value in types) require_type(value,type,e$op)
    }
    return(if (e$op == "||") "TEXT" else "INT")
  }
  if (e$kind == "isnull") return("INT")
  if (e$kind %in% c("in","between")) {
    for (value in types[-1]) require_type(value,types[1],if(e$kind == "in") "IN" else "BETWEEN")
    return("INT")
  }
  if (e$kind == "like") {
    for (value in types) require_type(value,"TEXT","LIKE")
    return("INT")
  }
  "INT"
}
condition_check <- function(e,s,name,aggregates=FALSE,grouped=NULL) {
  if (!is.null(e)) require_type(check_expr(e,s,aggregates,grouped),"INT",name)
}
has_aggregate <- function(e) e$kind == "aggregate" || any(vapply(e$args,has_aggregate,FALSE))
logical_not <- function(x) if (is_null(x)) sql_null else if (x == 0) 1 else 0
logical_and <- function(a,b) {
  if ((!is_null(a) && a == 0) || (!is_null(b) && b == 0)) return(0)
  if (is_null(a) || is_null(b)) return(sql_null)
  1
}
logical_or <- function(a,b) {
  if (truth(a) || truth(b)) return(1)
  if (is_null(a) || is_null(b)) return(sql_null)
  0
}
operate <- function(op,a,b) {
  if (op == "AND") return(logical_and(a,b))
  if (op == "OR") return(logical_or(a,b))
  if (is_null(a) || is_null(b)) return(sql_null)
  switch(op,
    "+"=a+b,"-"=a-b,"*"=a*b,
    "/"=if(b == 0) sql_null else quotient(a,b),
    "%"=if(b == 0) sql_null else a-b*quotient(a,b),
    "||"=paste0(a,b),
    "="=as.numeric(a == b),"<>"=as.numeric(a != b),"!="=as.numeric(a != b),
    "<"=as.numeric(a < b),"<="=as.numeric(a <= b),
    ">"=as.numeric(a > b),">="=as.numeric(a >= b))
}
like <- function(value,pattern) {
  chars <- strsplit(value,"",fixed=TRUE)[[1]]
  symbols <- strsplit(pattern,"",fixed=TRUE)[[1]]
  dp <- c(TRUE,rep(FALSE,length(chars)))
  for (character in symbols) {
    if (character == "%") {
      if (length(chars) > 0L)
        for (i in seq_along(chars)) dp[i+1L] <- dp[i+1L] || dp[i]
    } else {
      if (length(chars) > 0L)
        for (i in rev(seq_along(chars))) dp[i+1L] <- dp[i] && (character == "_" || character == chars[i])
      dp[1L] <- FALSE
    }
  }
  as.numeric(dp[length(dp)])
}
value_key <- function(values) {
  parts <- vapply(values,function(value) {
    if (is_null(value)) return("N")
    if (is.numeric(value)) return(paste0("I",format(value,scientific=FALSE,trim=TRUE)))
    paste0("S",nchar(value),":",value)
  },"")
  paste(parts,collapse="\037")
}
evaluate <- function(e,row=list(),group=NULL) {
  if (e$kind == "literal") return(e$value)
  if (e$kind == "ref") return(row[[e$index]])
  if (e$kind == "aggregate") {
    if (length(e$args) == 0L) return(length(group))
    values <- lapply(group,function(r) evaluate(e$args[[1]],r))
    values <- Filter(function(v) !is_null(v),values)
    if (e$distinct) values <- values[!duplicated(vapply(values,function(v) value_key(list(v)),""))]
    if (e$op == "COUNT") return(length(values))
    if (length(values) == 0L) return(sql_null)
    numbers <- unlist(values)
    return(switch(e$op,
      "SUM"=sum(numbers),"MIN"=min(numbers),"MAX"=max(numbers),
      "AVG"=quotient(sum(numbers),length(numbers))))
  }
  a <- lapply(e$args,function(x) evaluate(x,row,group))
  if (e$kind == "unary") return(if(e$op == "NOT") logical_not(a[[1]]) else if(is_null(a[[1]])) sql_null else -a[[1]])
  if (e$kind == "binary") return(operate(e$op,a[[1]],a[[2]]))
  if (e$kind == "isnull") return(as.numeric(is_null(a[[1]]) != e$negated))
  result <- if (e$kind == "in") {
    if (is_null(a[[1]])) sql_null else
      if (any(vapply(a[-1],function(v) !is_null(v) && v == a[[1]],FALSE))) 1 else
        if (any(vapply(a[-1],is_null,FALSE))) sql_null else 0
  } else if (e$kind == "between") {
    logical_and(operate(">=",a[[1]],a[[2]]),operate("<=",a[[1]],a[[3]]))
  } else if (e$kind == "like") {
    if (any(vapply(a,is_null,FALSE))) sql_null else like(a[[1]],a[[2]])
  } else sql_null
  if (e$negated) logical_not(result) else result
}
satisfies <- function(e,row,group=NULL) is.null(e) || truth(evaluate(e,row,group))
row_count <- function(n) paste0(n,if(n == 1) " row" else " rows")
pad <- function(text,width,right=FALSE) {
  spaces <- strrep(" ",width-nchar(text,type="bytes"))
  if (right) paste0(spaces,text) else paste0(text,spaces)
}
print_table <- function(items,types,rows) {
  headings <- vapply(items,function(i) i$heading,"")
  cells <- lapply(rows,function(row) vapply(row,value_text,""))
  widths <- vapply(seq_along(headings),function(i)
    max(c(nchar(headings[i],type="bytes"),
          vapply(cells,function(row) nchar(row[i],type="bytes"),0L))),0L)
  border <- paste0("+",paste(vapply(widths,function(w) paste0(strrep("-",w+2L),"+"),""),collapse=""))
  cat(border,"\n",sep="")
  cat("|",paste(vapply(seq_along(headings),function(i)
    paste0(" ",pad(headings[i],widths[i])," |"),""),collapse=""),"\n",sep="")
  cat(border,"\n",sep="")
  for (row in cells) {
    fields <- vapply(seq_along(row),function(i)
      paste0(" ",pad(row[i],widths[i],types[i] == "INT")," |"),"")
    cat("|",paste(fields,collapse=""),"\n",sep="")
  }
  cat(border,"\n(",row_count(length(rows)),")\n",sep="")
}

database <- new.env(parent=emptyenv())
database$tables <- new.env(hash=TRUE,parent=emptyenv())
table_lookup <- function(name) {
  if (!exists(name,envir=database$tables,inherits=FALSE)) fail(paste0("unknown table ",name))
  get(name,envir=database$tables,inherits=FALSE)
}
column_index <- function(t,name) which(vapply(t$columns,function(c) c$name == name,FALSE))
column_indices <- function(t,names) {
  result <- integer()
  for (name in names) {
    i <- column_index(t,name)
    if (length(i) == 0L) fail(paste0("unknown column ",name))
    if (i %in% result) fail(paste0("duplicate column ",name))
    result <- c(result,i)
  }
  result
}
constraints <- function(t,rows,indices) {
  for (i in indices) {
    row <- rows[[i]]
    for (j in seq_along(t$columns))
      if (t$columns[[j]]$not_null && is_null(row[[j]]))
        fail(paste0("NULL value in column ",t$columns[[j]]$name))
    if (!is.null(t$key) && sum(vapply(rows,function(r) {
      a <- r[[t$key]]
      b <- row[[t$key]]
      (is_null(a) && is_null(b)) || (!is_null(a) && !is_null(b) && a == b)
    },FALSE)) > 1L)
      fail(paste0("duplicate primary key ",value_text(row[[t$key]])))
  }
}
execute_statement <- function(s) {
  if (s$kind == "create") {
    if (exists(s$name,envir=database$tables,inherits=FALSE))
      fail(paste0("table ",s$name," already exists"))
    columns <- list()
    key <- NULL
    primary <- 0L
    for (column in s$columns) {
      if (any(vapply(columns,function(c) c$name == column$name,FALSE)))
        fail(paste0("duplicate column ",column$name))
      primary <- primary+column$primary
      if (primary >= 2L) fail("multiple primary keys")
      if (column$primary > 0L) key <- length(columns)+1L
      column$not_null <- column$not_null || column$primary > 0L
      columns[[length(columns)+1L]] <- column
    }
    t <- new.env(parent=emptyenv())
    t$name <- s$name
    t$columns <- columns
    t$key <- key
    t$rows <- list()
    assign(s$name,t,envir=database$tables)
    cat("Table ",s$name," created.\n",sep="")
  } else if (s$kind == "drop") {
    table_lookup(s$name)
    rm(list=s$name,envir=database$tables)
    cat("Table ",s$name," dropped.\n",sep="")
  } else if (s$kind == "insert") {
    t <- table_lookup(s$name)
    indices <- if (is.null(s$columns)) seq_along(t$columns) else column_indices(t,s$columns)
    for (tuple in s$tuples) {
      if (length(tuple) != length(indices))
        fail(paste0("expected ",length(indices)," values, got ",length(tuple)))
      for (j in seq_along(tuple))
        require_type(check_expr(tuple[[j]],scope()),t$columns[[indices[j]]]$type,
                     paste0("column ",t$columns[[indices[j]]]$name))
    }
    additions <- list()
    for (tuple in s$tuples) {
      row <- rep(list(sql_null),length(t$columns))
      for (j in seq_along(tuple)) row[[indices[j]]] <- evaluate(tuple[[j]],list())
      additions[[length(additions)+1L]] <- row
    }
    rows <- c(t$rows,additions)
    constraints(t,rows,seq.int(length(t$rows)+1L,length(rows)))
    t$rows <- rows
    cat(row_count(length(additions))," inserted.\n",sep="")
  } else if (s$kind == "update" || s$kind == "delete") {
    t <- table_lookup(s$name)
    context <- scope()
    scope_add(context,t$name,t)
    if (s$kind == "delete") {
      condition_check(s$where,context,"WHERE")
      rows <- Filter(function(row) !satisfies(s$where,row),t$rows)
      changed <- length(t$rows)-length(rows)
      t$rows <- rows
      cat(row_count(changed)," deleted.\n",sep="")
    } else {
      indices <- column_indices(t,vapply(s$assignments,function(a) a$name,""))
      for (j in seq_along(indices))
        require_type(check_expr(s$assignments[[j]]$expr,context),
                     t$columns[[indices[j]]]$type,
                     paste0("column ",t$columns[[indices[j]]]$name))
      condition_check(s$where,context,"WHERE")
      rows <- t$rows
      changed <- integer()
      for (i in seq_along(t$rows)) {
        row <- t$rows[[i]]
        if (!satisfies(s$where,row)) next
        replacement <- row
        for (j in seq_along(indices))
          replacement[[indices[j]]] <- evaluate(s$assignments[[j]]$expr,row)
        rows[[i]] <- replacement
        changed <- c(changed,i)
      }
      constraints(t,rows,changed)
      t$rows <- rows
      cat(row_count(length(changed))," updated.\n",sep="")
    }
  } else if (s$kind == "select") {
    execute_select(s)
  }
  invisible(NULL)
}
sort_comparison <- function(a,b,desc) {
  for (i in seq_along(a$keys)) {
    left <- a$keys[[i]]
    right <- b$keys[[i]]
    order <- if (is_null(left)) {
      if (is_null(right)) 0 else -1
    } else if (is_null(right)) 1 else compare(left,right)
    if (desc[i]) order <- -order
    if (order != 0) return(order)
  }
  sign(a$position-b$position)
}
execute_select <- function(q) {
  context <- scope()
  first <- table_lookup(q$source[1])
  scope_add(context,q$source[2],first)
  for (joined in q$joins) {
    t <- table_lookup(joined$table[1])
    scope_add(context,joined$table[2],t)
    condition_check(joined$condition,context,"ON")
  }
  condition_check(q$where,context,"WHERE")
  for (ref in q$group) resolve(context,ref)
  items <- q$items
  if (is.null(items)) {
    items <- list()
    for (entry in context$entries)
      for (column in entry$table$columns)
        items[[length(items)+1L]] <- list(
          expr=expr("ref",table=entry$name,column=column$name,text=column$name),
          alias=NULL,heading=column$name)
  }
  aggregate <- length(q$group)>0L || !is.null(q$having) ||
    any(vapply(c(items,q$order),function(item) has_aggregate(item$expr),FALSE))
  grouped <- if (aggregate) vapply(q$group,function(ref) ref$index,0L) else NULL
  types <- vapply(items,function(item) check_expr(item$expr,context,TRUE,grouped),"")
  condition_check(q$having,context,"HAVING",TRUE,grouped)
  keys <- list()
  for (order in q$order) {
    tokens <- order$tokens
    if (length(tokens)==1L && tokens[[1]]$kind=="integer") {
      position <- tokens[[1]]$value
      if (position < 1 || position > length(items))
        fail(paste0("ORDER BY position ",position," is out of range"))
      key <- items[[position]]$expr
    } else if (length(tokens)==1L && tokens[[1]]$kind=="name" &&
               any(vapply(items,function(item)
                 !is.null(item$alias) && item$alias==tokens[[1]]$value,FALSE))) {
      i <- which(vapply(items,function(item)
        !is.null(item$alias) && item$alias==tokens[[1]]$value,FALSE))[1]
      key <- items[[i]]$expr
    } else {
      check_expr(order$expr,context,TRUE,grouped)
      key <- order$expr
    }
    keys[[length(keys)+1L]] <- key
  }
  rows <- first$rows
  for (joined in q$joins) {
    t <- table_lookup(joined$table[1])
    next_rows <- list()
    for (left in rows) {
      matched <- FALSE
      for (right in t$rows) {
        combined <- c(left,right)
        if (!satisfies(joined$condition,combined)) next
        next_rows[[length(next_rows)+1L]] <- combined
        matched <- TRUE
      }
      if (!matched && joined$left)
        next_rows[[length(next_rows)+1L]] <- c(left,rep(list(sql_null),length(t$columns)))
    }
    rows <- next_rows
  }
  rows <- Filter(function(row) satisfies(q$where,row),rows)
  sources <- list()
  if (aggregate) {
    groups <- list()
    if (length(q$group)==0L) {
      groups <- list(rows)
    } else {
      known <- character()
      for (row in rows) {
        key <- value_key(lapply(grouped,function(i) row[[i]]))
        found <- match(key,known)
        if (is.na(found)) {
          known <- c(known,key)
          groups[[length(groups)+1L]] <- list(row)
        } else {
          groups[[found]][[length(groups[[found]])+1L]] <- row
        }
      }
    }
    for (group in groups) {
      row <- if(length(group)>0L) group[[1]] else list()
      if (satisfies(q$having,row,group))
        sources[[length(sources)+1L]] <- list(row=row,group=group)
    }
  } else sources <- lapply(rows,function(row) list(row=row,group=NULL))
  results <- list()
  for (i in seq_along(sources)) {
    s <- sources[[i]]
    values <- lapply(items,function(item) evaluate(item$expr,s$row,s$group))
    order <- lapply(keys,function(key) evaluate(key,s$row,s$group))
    results[[length(results)+1L]] <- list(values=values,keys=order,position=i)
  }
  if (length(results)>1L && length(keys)>0L) {
    desc <- vapply(q$order,function(o) o$desc,FALSE)
    for (i in seq.int(2L,length(results))) {
      j <- i
      while (j>1L && sort_comparison(results[[j]],results[[j-1L]],desc)<0L) {
        previous <- results[[j]]
        results[[j]] <- results[[j-1L]]
        results[[j-1L]] <- previous
        j <- j-1L
      }
    }
  }
  if (q$distinct) {
    used <- character()
    unique_rows <- list()
    for (row in results) {
      key <- value_key(row$values)
      if (key %in% used) next
      used <- c(used,key)
      unique_rows[[length(unique_rows)+1L]] <- row
    }
    results <- unique_rows
  }
  if (!is.null(q$offset)) {
    offset <- as.integer(q$offset)
    results <- if (offset>=length(results)) list() else results[seq.int(offset+1L,length(results))]
  }
  if (!is.null(q$limit)) results <- head(results,as.integer(q$limit))
  print_table(items,types,lapply(results,function(row) row$values))
}

source <- paste(readLines(file("stdin"),warn=FALSE),collapse="\n")
for (text in split_statements(source)) {
  done <- tryCatch({
    p <- parser(tokenize(text))
    statement <- parse_statement(p)
    if (is.null(statement)) FALSE else if (statement$kind=="exit") TRUE else {
      execute_statement(statement)
      FALSE
    }
  },error=function(problem) {
    cat("ERROR: ",conditionMessage(problem),"\n",sep="")
    FALSE
  })
  if (done) break
}
