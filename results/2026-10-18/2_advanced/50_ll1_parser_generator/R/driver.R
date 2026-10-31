parse_node <- function(symbol) {
  node <- new.env(parent=emptyenv())
  node$symbol <- symbol
  node$mark <- ""
  node$children <- list()
  node
}
parse_tokens <- function(tokens,grammar,sets,table) {
  input <- c(tokens,list(list(name=END_MARKER,position=length(tokens)+1L)))
  root <- parse_node(grammar$start)
  stack <- list(list(symbol=END_MARKER,node=NULL),list(symbol=grammar$start,node=root))
  cursor <- 1L
  step <- 0L
  left_parse <- integer()
  traces <- events <- list()
  counts <- setNames(as.list(integer(6L)),c("predict","match","skip","pop","missing","max_stack"))
  repeat {
    step <- step+1L
    item <- tail(stack,1L)[[1L]]
    top <- item$symbol
    node <- item$node
    current <- input[[cursor]]$name
    position <- input[[cursor]]$position
    counts$max_stack <- max(counts$max_stack,length(stack))
    before_stack <- vapply(stack,function(item) item$symbol,character(1))
    before_input <- vapply(input[seq.int(cursor,length(input))],function(item) item$name,character(1))
    terminate <- FALSE
    event <- ""
    choice <- if (is_nonterminal(top)) table$choices[[cell_key(top,current)]] else 0L
    if (top == END_MARKER && current == END_MARKER) {
      action <- "accept"
      terminate <- TRUE
    } else if (top == END_MARKER) {
      action <- paste("error: skip",current)
      event <- "skip"
      cursor <- cursor+1L
    } else if (!is_nonterminal(top)) {
      if (top == current) {
        action <- paste("match",current)
        stack <- head(stack,-1L)
        cursor <- cursor+1L
        counts$match <- counts$match+1L
      } else {
        action <- paste("error: missing",top)
        event <- "missing"
        node$mark <- "missing"
        stack <- head(stack,-1L)
      }
    } else if (choice != 0L) {
      p <- table$productions[[choice]]
      action <- paste0("predict ",choice,": ",p$notation)
      left_parse <- c(left_parse,choice)
      stack <- head(stack,-1L)
      if (length(p$rhs)) {
        children <- lapply(p$rhs,parse_node)
        node$children <- c(node$children,children)
        for (child in rev(children)) stack[[length(stack)+1L]] <- list(symbol=child$symbol,node=child)
      } else node$children[[length(node$children)+1L]] <- parse_node("%empty")
      counts$predict <- counts$predict+1L
    } else if (current == END_MARKER || current %in% sets$follow[[top]]) {
      action <- paste("error: pop",top)
      event <- "pop"
      node$mark <- "error"
      stack <- head(stack,-1L)
    } else {
      action <- paste("error: skip",current)
      event <- "skip"
      cursor <- cursor+1L
    }
    traces[[length(traces)+1L]] <- list(step=step,stack=before_stack,input=before_input,action=action)
    if (nzchar(event)) {
      counts[[event]] <- counts[[event]]+1L
      events[[length(events)+1L]] <- list(step=step,kind=event,symbol=top,token=current,position=position)
    }
    if (terminate) break
  }
  list(root=root,trace=traces,left_parse=left_parse,events=events,counts=counts)
}
