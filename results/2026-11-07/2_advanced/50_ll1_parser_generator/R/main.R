for (module in c("grammar_parser","transform","first_follow","table","driver")) source(paste0(module,".R"))
listed <- function(heading,items) if (length(items)) paste(heading,paste(items,collapse=" ")) else heading
reachable <- function(grammar) {
  seen <- queue <- grammar$start
  cursor <- 1L
  while (cursor <= length(queue)) {
    lhs <- queue[cursor]
    cursor <- cursor+1L
    for (rhs in grammar$rules[[lhs]]) for (symbol in rhs) if (is_nonterminal(symbol) && !symbol %in% seen) {
      seen <- c(seen,symbol)
      queue <- c(queue,symbol)
    }
  }
  seen
}
retain_grammar <- function(grammar,names) list(order=names,rules=grammar$rules[names],start=grammar$start)
clean_grammar <- function(grammar) {
  g <- clone_grammar(grammar)
  diagnostics <- character()
  symbols <- unique(unlist(g$rules,use.names=FALSE))
  undefined <- symbols[vapply(symbols,function(s) is_nonterminal(s) && !s %in% g$order,logical(1))]
  undefined <- undefined[order(substr(undefined,2L,nchar(undefined)-1L),method="radix")]
  diagnostics <- c(
      diagnostics,
      vapply(undefined,function(name) paste("undefined nonterminal",name),character(1))
  )
  for (lhs in g$order) {
    kept <- list()
    for (rhs in g$rules[[lhs]]) {
      bad <- which(rhs %in% undefined)
      if (length(bad)) diagnostics <- c(
          diagnostics,
          paste0("removed ",format_production(lhs,rhs)," (undefined ",rhs[bad[1L]],")")
      ) else
        kept[[length(kept)+1L]] <- rhs
    }
    g$rules[[lhs]] <- kept
  }
  productive <- character()
  repeat {
    changed <- FALSE
    for (lhs in g$order) {
      possible <- any(vapply(
          g$rules[[lhs]],
          function(rhs) all(vapply(rhs,function(s) !is_nonterminal(s) || s %in% productive,logical(1))),
          logical(1)
      ))
      if (!lhs %in% productive && possible) {
        productive <- c(productive,lhs)
        changed <- TRUE
      }
    }
    if (!changed) break
  }
  removed <- setdiff(g$order,productive)
  diagnostics <- c(
      diagnostics,
      vapply(removed,function(lhs) paste("unproductive nonterminal",lhs),character(1))
  )
  g <- retain_grammar(g,g$order[!g$order %in% removed])
  for (lhs in g$order) {
    kept <- list()
    for (rhs in g$rules[[lhs]]) {
      bad <- which(rhs %in% removed)
      if (length(bad)) diagnostics <- c(
          diagnostics,
          paste0("removed ",format_production(lhs,rhs)," (unproductive ",rhs[bad[1L]],")")
      ) else
        kept[[length(kept)+1L]] <- rhs
    }
    g$rules[[lhs]] <- kept
  }
  reached <- reachable(g)
  diagnostics <- c(
      diagnostics,
      vapply(g$order[!g$order %in% reached],function(lhs) paste("unreachable nonterminal",lhs),character(1))
  )
  list(grammar=retain_grammar(g,g$order[g$order %in% reached]),diagnostics=diagnostics)
}
left_recursion_diagnostics <- function(grammar) {
  diagnostics <- character()
  for (start in grammar$order) {
    queue <- start
    parent <- setNames(list(""),start)
    cursor <- 1L
    found <- FALSE
    while (cursor <= length(queue) && !found) {
      lhs <- queue[cursor]
      cursor <- cursor+1L
      for (rhs in grammar$rules[[lhs]]) {
        if (!length(rhs) || !is_nonterminal(rhs[1L])) next
        next_symbol <- rhs[1L]
        if (next_symbol == start) {
          path <- lhs
          while (nzchar(parent[[tail(path,1L)]])) path <- c(path,parent[[tail(path,1L)]])
          diagnostics <- c(diagnostics,paste0("left recursion: ",paste(c(rev(path),start),collapse=" -> ")))
          found <- TRUE
          break
        }
        if (!next_symbol %in% names(parent)) {
          parent[[next_symbol]] <- lhs
          queue <- c(queue,next_symbol)
        }
      }
    }
  }
  diagnostics
}
grammar_summary <- function(grammar) {
  alternatives <- unlist(grammar$rules[grammar$order],recursive=FALSE)
  paste0("start=",grammar$start," nonterminals=",length(grammar$order)," terminals=",length(terminals_of(grammar)),
    " productions=",length(alternatives)," empty=",sum(lengths(alternatives) == 0L)," unit=",
    sum(vapply(alternatives,function(rhs) length(rhs) == 1L && is_nonterminal(rhs[1L]),logical(1))))
}
grammar_listing <- function(grammar,numbered=FALSE) {
  lines <- character()
  total <- sum(lengths(grammar$rules[grammar$order]))
  width <- nchar(as.character(total))
  number <- 0L
  for (lhs in grammar$order) for (i in seq_along(grammar$rules[[lhs]])) {
    rhs <- grammar$rules[[lhs]][[i]]
    number <- number+1L
    line <- if (i == 1L) format_production(lhs,rhs) else paste0(
        strrep(" ",nchar(lhs)),
        " | ",
        format_alternative(rhs)
    )
    lines <- c(lines,if (numbered) paste0(sprintf(paste0("%",width,"d"),number),"  ",line) else line)
  }
  lines
}
grammar_report <- function(cleaned,recursion,factored,final,recursion_log,factor_log,final_log) {
  lines <- c("== cleaned grammar ==",grammar_summary(cleaned),grammar_listing(cleaned))
  stages <- list(list(title="left recursion elimination",grammar=recursion,log=recursion_log,numbered=FALSE),
    list(
        title="left factoring",
        grammar=factored,
        log=factor_log,
        numbered=FALSE
    ),list(title="final grammar",grammar=final,log=final_log,numbered=TRUE))
  for (stage in stages) lines <- c(lines,"",paste0("== ",stage$title," =="),if (length(stage$log)) stage$log else "none",
    grammar_summary(stage$grammar),grammar_listing(stage$grammar,stage$numbered))
  lines <- c(lines,"","== cross reference ==")
  productions <- number_productions(final)
  for (symbol in c(final$order,terminal_order(terminals_of(final)))) {
    numbers <- vapply(Filter(function(p) symbol %in% p$rhs,productions),function(p) p$number,integer(1))
    name <- if (is_nonterminal(symbol)) symbol else paste0('"',symbol,'"')
    lines <- c(lines,if (length(numbers)) listed(paste(name,"used in"),numbers) else paste(name,"not used"))
  }
  lines
}
sequence_measure <- function(rhs,scores) {
  length <- height <- 0L
  for (symbol in rhs) {
    if (is_nonterminal(symbol)) {
      if (is.null(scores[[symbol]])) return(NULL)
      length <- length+scores[[symbol]][1L]
      height <- max(height,scores[[symbol]][2L])
    } else length <- length+1L
  }
  c(length,height+1L)
}
expand_sequence <- function(rhs,sentences) {
  result <- character()
  for (symbol in rhs) result <- c(result,if (is_nonterminal(symbol)) sentences[[symbol]] else symbol)
  result
}
shortest_sentences <- function(grammar) {
  scores <- list()
  repeat {
    changed <- FALSE
    for (lhs in grammar$order) for (rhs in grammar$rules[[lhs]]) {
      measure <- sequence_measure(rhs,scores)
      if (is.null(measure)) next
      if (is.null(scores[[lhs]]) || key_less(measure,scores[[lhs]])) {
        scores[[lhs]] <- measure
        changed <- TRUE
      }
    }
    if (!changed) break
  }
  sentences <- list()
  ordering <- order(vapply(scores[grammar$order],`[`,integer(1),2L),seq_along(grammar$order))
  for (lhs in grammar$order[ordering]) {
    selected <- Filter(
        function(rhs) identical(sequence_measure(rhs,scores),scores[[lhs]]),
        grammar$rules[[lhs]]
    )[[1L]]
    sentences[[lhs]] <- expand_sequence(selected,sentences)
  }
  list(scores=scores,sentences=sentences)
}
key_less <- function(a,b) {
  different <- which(a != b)
  length(different) > 0L && a[different[1L]] < b[different[1L]]
}
shortest_contexts <- function(grammar,scores,sentences) {
  costs <- setNames(list(c(0L,0L)),grammar$start)
  parents <- list()
  productions <- number_productions(grammar)
  repeat {
    changed <- FALSE
    for (p in productions) {
      if (is.null(costs[[p$lhs]])) next
      for (k in seq_along(p$rhs)) {
        symbol <- p$rhs[k]
        if (!is_nonterminal(symbol) || symbol == grammar$start) next
        before <- head(p$rhs,k-1L)
        after <- tail(p$rhs,length(p$rhs)-k)
        extra <- sum(vapply(
            c(before,after),
            function(s) if (is_nonterminal(s)) scores[[s]][1L] else 1L,
            integer(1)
        ))
        candidate <- c(costs[[p$lhs]][1L]+extra,costs[[p$lhs]][2L]+1L)
        key <- c(p$number,k)
        if (is.null(costs[[symbol]]) || key_less(candidate,costs[[symbol]]) ||
            (identical(candidate,costs[[symbol]]) && key_less(key,parents[[symbol]]$key))) {
          costs[[symbol]] <- candidate
          parents[[symbol]] <- list(key=key,lhs=p$lhs,before=before,after=after)
          changed <- TRUE
        }
      }
    }
    if (!changed) break
  }
  contexts <- setNames(list(list(prefix=character(),suffix=character())),grammar$start)
  others <- grammar$order[grammar$order != grammar$start]
  ordering <- order(vapply(costs[others],`[`,integer(1),2L),seq_along(others))
  for (symbol in others[ordering]) {
    parent <- parents[[symbol]]
    outer <- contexts[[parent$lhs]]
    contexts[[symbol]] <- list(
        prefix=c(outer$prefix,expand_sequence(parent$before,sentences)),
        suffix=c(expand_sequence(parent$after,sentences),outer$suffix)
    )
  }
  contexts
}
sets_report <- function(grammar,sets,sentences) {
  passes <- sets$passes
  lines <- c(paste0("passes: nullable=",passes$nullable," first=",passes$first," follow=",passes$follow),"")
  for (lhs in grammar$order) lines <- c(lines,lhs,paste0("  nullable: ",if (sets$nullable[[lhs]]) "yes" else "no"),
    listed("  first:",terminal_order(sets$first[[lhs]])),listed(
        "  follow:",
        terminal_order(sets$follow[[lhs]])
    ),listed("  shortest:",sentences[[lhs]]))
  lines
}
first_path <- function(number,token,table,sets) {
  queue <- number
  parent <- setNames(list(0L),as.character(number))
  cursor <- 1L
  while (cursor <= length(queue)) {
    current <- queue[cursor]
    cursor <- cursor+1L
    for (symbol in table$productions[[current]]$rhs) {
      if (symbol == token) {
        path <- integer()
        while (current != number) {
          path <- c(path,current)
          current <- parent[[as.character(current)]]
        }
        return(rev(path))
      }
      if (is_nonterminal(symbol)) {
        for (p in table$productions) {
          key <- as.character(p$number)
          if (p$lhs == symbol && !key %in% names(parent)) {
            parent[[key]] <- current
            queue <- c(queue,p$number)
          }
        }
        if (!sets$nullable[[symbol]]) break
      } else break
    }
  }
  integer()
}
follow_path <- function(lhs,token,grammar,table,sets) {
  queue <- lhs
  paths <- setNames(list(integer()),lhs)
  cursor <- 1L
  while (cursor <= length(queue)) {
    symbol <- queue[cursor]
    cursor <- cursor+1L
    path <- paths[[symbol]]
    if (symbol == grammar$start && token == END_MARKER) return(path)
    for (p in table$productions) for (i in seq_along(p$rhs)) {
      if (p$rhs[i] != symbol) next
      more <- first_sequence(tail(p$rhs,length(p$rhs)-i),sets$nullable,sets$first)
      if (token %in% more$first) return(c(path,p$number))
      if (more$empty && !p$lhs %in% names(paths)) {
        paths[[p$lhs]] <- c(path,p$number)
        queue <- c(queue,p$lhs)
      }
    }
  }
  integer()
}
table_report <- function(grammar,sets,table,before) {
  lines <- "== predict sets =="
  for (p in table$productions) lines <- c(
      lines,
      paste0(p$number,": ",p$notation),
      listed("  predict:",terminal_order(names(p$predict)))
  )
  lines <- c(lines,"","== parse table ==")
  tokens <- c(sets$terminals,END_MARKER)
  matrix <- list(c("",tokens))
  for (lhs in grammar$order) {
    values <- vapply(tokens,function(token) {
      entries <- table$cells[[cell_key(lhs,token)]]
      if (length(entries)) paste(entries,collapse="/") else "."
    },character(1))
    matrix[[length(matrix)+1L]] <- c(lhs,values)
  }
  widths <- vapply(
      seq_along(matrix[[1L]]),
      function(j) max(vapply(matrix,function(row) nchar(row[j]),integer(1))),
      integer(1)
  )
  for (row in matrix) {
    first <- paste0(row[1L],strrep(" ",widths[1L]-nchar(row[1L])))
    rest <- vapply(
        seq.int(2L,length(row)),
        function(j) paste0("  ",strrep(" ",widths[j]-nchar(row[j])),row[j]),
        character(1)
    )
    lines <- c(lines,paste0(first,paste(rest,collapse="")))
  }
  lines <- c(lines,"","== conflicts ==")
  if (!length(table$conflicts)) lines <- c(lines,"none")
  for (conflict in table$conflicts) {
    lhs <- conflict$lhs
    token <- conflict$token
    lines <- c(lines,paste0("conflict ",lhs," on ",token,": ",conflict$kind,", chosen ",conflict$chosen))
    for (number in conflict$entries) {
      p <- table$productions[[number]]
      reason <- p$predict[[token]]
      path <- if (reason == "FIRST") first_path(number,token,table,sets) else follow_path(
          lhs,
          token,
          grammar,
          table,
          sets
      )
      if (length(path)) reason <- paste0(reason,listed(" via",path))
      lines <- c(lines,paste0("  ",number,": ",p$notation," (",reason,")"))
    }
  }
  c(
      lines,
      paste0("LL(1): ",if (length(table$conflicts)) "no" else "yes"),
      paste0("conflicts before transformation: ",before)
  )
}
compact_tree <- function(root) {
  pending <- list(list(node=root,ready=FALSE))
  while (length(pending)) {
    item <- tail(pending,1L)[[1L]]
    pending <- head(pending,-1L)
    node <- item$node
    if (!item$ready) {
      pending[[length(pending)+1L]] <- list(node=node,ready=TRUE)
      for (child in rev(node$children)) pending[[length(pending)+1L]] <- list(node=child,ready=FALSE)
      next
    }
    children <- list()
    for (original in node$children) {
      if (original$symbol == "%empty") next
      child <- original$compacted
      if (is_nonterminal(child$symbol) && !nzchar(child$mark) && !length(child$children)) next
      if (is_nonterminal(child$symbol) && grepl(
          "'",
          child$symbol,
          fixed=TRUE
      ) && !nzchar(child$mark)) children <- c(children,child$children) else
        children[[length(children)+1L]] <- child
    }
    if (length(children) == 1L && !nzchar(node$mark)) {
      node$compacted <- children[[1L]]
    } else {
      result <- parse_node(node$symbol)
      result$mark <- node$mark
      result$children <- children
      node$compacted <- result
    }
  }
  root$compacted
}
tree_label <- function(node) paste0(node$symbol,if (nzchar(node$mark)) paste0(" (",node$mark,")") else "")
tree_lines <- function(root) {
  lines <- tree_label(root)
  pending <- list()
  for (i in rev(seq_along(root$children))) pending[[length(pending)+1L]] <- list(
      node=root$children[[i]],
      prefix="",
      last=i == length(root$children)
  )
  while (length(pending)) {
    item <- tail(pending,1L)[[1L]]
    pending <- head(pending,-1L)
    node <- item$node
    lines <- c(lines,paste0(item$prefix,if (item$last) "`-- " else "|-- ",tree_label(node)))
    prefix <- paste0(item$prefix,if (item$last) "    " else "|   ")
    for (i in rev(seq_along(node$children))) pending[[length(pending)+1L]] <- list(
        node=node$children[[i]],
        prefix=prefix,
        last=i == length(node$children)
    )
  }
  lines
}
trace_lines <- function(trace) {
  rows <- c(
      list(c("step","stack","input","action")),
      lapply(
          trace,
          function(row) c(
              as.character(row$step),
              paste(row$stack,collapse=" "),
              paste(row$input,collapse=" "),
              row$action
          )
      )
  )
  widths <- vapply(
      seq_len(3L),
      function(j) max(vapply(rows,function(row) nchar(row[j]),integer(1))),
      integer(1)
  )
  vapply(
      rows,
      function(row) paste0(
          paste(
              vapply(
                  seq_len(3L),
                  function(j) paste0(row[j],strrep(" ",widths[j]-nchar(row[j])),"  "),
                  character(1)
              ),
              collapse=""
          ),
          row[4L]
      ),
      character(1)
  )
}
error_strings <- function(events,sets,table) {
  errors <- character()
  for (event in events) {
    unexpected <- if (event$token == END_MARKER) "end of input" else paste0(
        '"',
        event$token,
        '" at token ',
        event$position
    )
    if (is_nonterminal(event$symbol)) {
      names <- c(sets$terminals,END_MARKER)
      names <- names[vapply(
          names,
          function(token) table$choices[[cell_key(event$symbol,token)]] != 0L,
          logical(1)
      )]
      expected <- paste(
          vapply(
              names,
              function(token) if (token == END_MARKER) token else paste0('"',token,'"'),
              character(1)
          ),
          collapse=" "
      )
    } else expected <- if (event$symbol == END_MARKER) END_MARKER else paste0('"',event$symbol,'"')
    recovery <- if (event$kind == "skip") paste0('skipped "',event$token,'"') else if (event$kind == "pop") paste("popped",event$symbol) else paste0(
        'inserted "',
        event$symbol,
        '"'
    )
    errors <- c(
        errors,
        paste0("step ",event$step,": unexpected ",unexpected,"; expected ",expected,"; ",recovery)
    )
  }
  errors
}
leftmost_derivation <- function(start,numbers,productions) {
  symbols <- start
  lines <- paste0("  ",start)
  for (number in numbers) {
    position <- which(vapply(symbols,is_nonterminal,logical(1)))[1L]
    symbols <- c(head(symbols,position-1L),productions[[number]]$rhs,tail(symbols,length(symbols)-position))
    lines <- c(lines,paste0("  => ",format_alternative(symbols)))
  }
  lines
}
recognize_language <- function(grammar,tokens) {
  productions <- number_productions(grammar)
  rhs <- function(number) if (number == 0L) grammar$start else productions[[number]]$rhs
  lhs <- function(number) if (number == 0L) "" else productions[[number]]$lhs
  n <- length(tokens)
  charts <- replicate(n+1L,new.env(hash=TRUE,parent=emptyenv()),simplify=FALSE)
  pending <- replicate(n+1L,list(),simplify=FALSE)
  add <- function(position,item) {
    key <- paste(item,collapse=",")
    if (!exists(key,envir=charts[[position+1L]],inherits=FALSE)) {
      charts[[position+1L]][[key]] <- TRUE
      pending[[position+1L]] <<- c(pending[[position+1L]],list(item))
    }
  }
  add(0L,c(0L,0L,0L))
  for (position in seq_len(n+1L)-1L) {
    cursor <- 1L
    while (cursor <= length(pending[[position+1L]])) {
      item <- pending[[position+1L]][[cursor]]
      cursor <- cursor+1L
      p <- item[1L]
      dot <- item[2L]
      origin <- item[3L]
      body <- rhs(p)
      if (dot == length(body)) {
        snapshot <- pending[[origin+1L]]
        for (outer in snapshot) {
          alternative <- rhs(outer[1L])
          consumed <- outer[2L]
          if (consumed < length(alternative) && alternative[consumed+1L] == lhs(p)) add(
              position,
              c(outer[1L],consumed+1L,outer[3L])
          )
        }
      } else if (is_nonterminal(body[dot+1L])) {
        next_symbol <- body[dot+1L]
        for (child in productions) if (child$lhs == next_symbol) add(position,c(child$number,0L,position))
        snapshot <- pending[[position+1L]]
        for (completed in snapshot) if (lhs(completed[1L]) == next_symbol && completed[2L] == length(rhs(completed[1L])) && completed[3L] == position)
          add(position,c(p,dot+1L,origin))
      } else if (position < n && body[dot+1L] == tokens[position+1L]) add(position+1L,c(p,dot+1L,origin))
    }
  }
  exists("0,1,0",envir=charts[[n+1L]],inherits=FALSE)
}
parse_input <- function(tokens,grammar,sets,table,cleaned) {
  kept <- list()
  unknown <- character()
  for (i in seq_along(tokens)) {
    token <- tokens[i]
    if (token %in% sets$terminals) kept[[length(kept)+1L]] <- list(name=token,position=i) else
      unknown <- c(unknown,paste0('unknown "',token,'" at token ',i,"; removed"))
  }
  parsed <- parse_tokens(kept,grammar,sets,table)
  parsed$original <- tokens
  parsed$unknown <- unknown
  parsed$errors <- c(unknown,error_strings(parsed$events,sets,table))
  parsed$accepted <- !length(parsed$errors)
  parsed$language <- recognize_language(cleaned,tokens)
  parsed
}
parses_report <- function(parses,grammar,sets,table,sentences,contexts) {
  lines <- character()
  for (i in seq_along(parses)) {
    p <- parses[[i]]
    lines <- c(lines,paste0("== input ",i," =="),listed("tokens:",p$original),trace_lines(p$trace),listed("left parse:",p$left_parse),
      paste0(
          "stats: steps=",
          length(p$trace),
          " predicts=",
          p$counts$predict,
          " matches=",
          p$counts$match,
          " max_stack=",
          p$counts$max_stack
      ))
    if (length(p$errors)) lines <- c(lines,"errors:",paste0("  ",p$errors))
    lines <- c(
        lines,
        if (p$accepted) "result: accepted" else paste0("result: rejected (errors: ",length(p$errors),")"),
        paste0("language: ",if (p$language) "yes" else "no")
    )
    if (p$accepted) lines <- c(
        lines,
        "derivation:",
        leftmost_derivation(grammar$start,p$left_parse,table$productions)
    )
    lines <- c(lines,"tree:",tree_lines(p$root),"compact tree:",tree_lines(compact_tree(p$root)),"")
  }
  used <- unique(unlist(lapply(parses,function(p) p$left_parse),use.names=FALSE))
  unused <- Filter(function(p) !p$number %in% used,table$productions)
  accepted <- sum(vapply(parses,function(p) p$accepted,logical(1)))
  in_language <- sum(vapply(parses,function(p) p$language,logical(1)))
  mismatches <- which(vapply(parses,function(p) p$accepted != p$language,logical(1)))
  unknown <- sum(vapply(parses,function(p) length(p$unknown),integer(1)))
  skips <- sum(vapply(parses,function(p) p$counts$skip,integer(1)))
  pops <- sum(vapply(parses,function(p) p$counts$pop,integer(1)))
  missings <- sum(vapply(parses,function(p) p$counts$missing,integer(1)))
  lines <- c(lines,"== summary ==",paste0("inputs=",length(parses)," accepted=",accepted," rejected=",length(parses)-accepted," in_language=",in_language),
    listed("mismatches:",mismatches),paste0(
        "recovery: unknown=",
        unknown,
        " skip=",
        skips,
        " pop=",
        pops,
        " missing=",
        missings
    ),
    paste0(
        "coverage: ",
        length(used),
        " of ",
        length(table$productions),
        " productions used"
    ),listed("unused:",vapply(unused,function(p) p$number,integer(1))))
  for (p in unused) {
    context <- contexts[[p$lhs]]
    sentence <- c(context$prefix,expand_sequence(p$rhs,sentences),context$suffix)
    tokens <- lapply(seq_along(sentence),function(i) list(name=sentence[i],position=i))
    parsed <- parse_tokens(tokens,grammar,sets,table)
    errors <- length(parsed$events)
    lines <- c(lines,paste0("  ",p$number,": ",p$notation),listed("    example:",sentence),
      if (errors == 0L) "    result: accepted" else paste0("    result: rejected (errors: ",errors,")"),paste0(
          "    used: ",
          if (p$number %in% parsed$left_parse) "yes" else "no"
      ))
  }
  lines
}
main <- function() {
  source <- parse_grammar()
  cleaned_result <- clean_grammar(source$grammar)
  cleaned <- cleaned_result$grammar
  recursion_diags <- left_recursion_diagnostics(cleaned)
  recursion <- eliminate_left_recursion(cleaned)
  factored <- left_factor(recursion$grammar)
  reached <- reachable(factored$grammar)
  removed <- factored$grammar$order[!factored$grammar$order %in% reached]
  final <- retain_grammar(factored$grammar,factored$grammar$order[factored$grammar$order %in% reached])
  final_log <- vapply(removed,function(lhs) paste("remove unreachable",lhs),character(1))
  diagnostics <- source$diagnostics
  if (source$has_declaration) {
    for (token in sort(names(source$words),method="radix")) if (!token %in% source$declared)
      diagnostics <- c(diagnostics,paste("undeclared terminal",token,"at line",source$words[[token]]))
  }
  diagnostics <- c(
      diagnostics,
      cleaned_result$diagnostics,
      recursion_diags,
      vapply(removed,function(lhs) paste("unreachable after transformation",lhs),character(1))
  )
  if (source$has_declaration) diagnostics <- c(
      diagnostics,
      vapply(
          sort(setdiff(source$declared,terminals_of(final)),method="radix"),
          function(token) paste("unused token",token),
          character(1)
      )
  )
  before <- build_table(cleaned,analyze_sets(cleaned))
  sets <- analyze_sets(final)
  table <- build_table(final,sets)
  shortest <- shortest_sentences(final)
  contexts <- shortest_contexts(final,shortest$scores,shortest$sentences)
  inputs <- lapply(
      readLines("input/inputs.txt"),
      function(line) if (nzchar(line)) strsplit(line," ",fixed=TRUE)[[1L]] else character()
  )
  parses <- lapply(inputs,function(tokens) parse_input(tokens,final,sets,table,cleaned))
  diagnostics <- c(
      diagnostics,
      if (length(table$conflicts)) paste0(
          "result: not LL(1) (conflicts: ",
          length(table$conflicts),
          ")"
      ) else "result: LL(1)"
  )
  reports <- list("grammar.txt"=grammar_report(cleaned,recursion$grammar,factored$grammar,final,recursion$log,factored$log,final_log),
    "sets.txt"=sets_report(final,sets,shortest$sentences),"table.txt"=table_report(
        final,
        sets,
        table,
        length(before$conflicts)
    ),
    "parses.txt"=parses_report(
        parses,
        final,
        sets,
        table,
        shortest$sentences,
        contexts
    ),"diagnostics.txt"=diagnostics)
  for (name in names(reports)) writeLines(reports[[name]],file.path("output",name),useBytes=TRUE)
}
main()
