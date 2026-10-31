source("network_io.R")
source("learning.R")
source("factors.R")
source("elimination.R")
source("sampling.R")

words <- function(...) paste(...,collapse=" ")
real <- function(value) {
  text <- sprintf("%.4f",value)
  text[text == "-0.0000"] <- "0.0000"
  text
}
yes <- function(value) if (value) "yes" else "no"
write_blocks <- function(path,blocks) {
  text <- paste(vapply(blocks,function(block) paste(block,collapse="\n"),character(1)),collapse="\n\n")
  connection <- file(path,"wb")
  on.exit(close(connection))
  if (nzchar(text)) writeChar(paste0(text,"\n"),connection,eos=NULL,useBytes=TRUE)
}
closure <- function(initial,links) {
  reached <- pending <- unique(initial)
  while (length(pending)) {
    v <- pending[length(pending)]
    pending <- pending[-length(pending)]
    for (neighbor in links[[v]]) if (!(neighbor %in% reached)) {
      reached <- c(reached,neighbor)
      pending <- c(pending,neighbor)
    }
  }
  sort(reached)
}
network_analysis <- function(input) {
  a <- list2env(input,parent=emptyenv())
  a$sizes <- lengths(a$states)
  a$variables <- seq_along(a$names)
  a$children <- lapply(a$variables,function(v) a$variables[vapply(a$parents,function(p) v %in% p,logical(1))])
  selected <- integer()
  a$topological <- integer()
  while (length(selected) < length(a$variables)) {
    eligible <- a$variables[vapply(
        a$variables,
        function(v) !(v %in% selected) && all(a$parents[[v]] %in% selected),
        logical(1)
    )]
    v <- min(eligible)
    selected <- c(selected,v)
    a$topological <- c(a$topological,v)
  }
  a$depths <- integer(length(a$variables))
  for (v in a$topological) if (length(a$parents[[v]])) a$depths[v] <- max(a$depths[a$parents[[v]]])+1L
  a$ancestors <- lapply(a$variables,function(v) closure(a$parents[[v]],a$parents))
  a$descendants <- lapply(a$variables,function(v) closure(a$children[[v]],a$children))
  a$spouses <- a$blankets <- list()
  for (v in a$variables) {
    immediate <- union(a$parents[[v]],a$children[[v]])
    other_parents <- unique(unlist(a$parents[a$children[[v]]],use.names=FALSE))
    spouse <- sort(setdiff(other_parents,c(v,immediate)))
    a$spouses[[v]] <- if (length(spouse)) spouse else integer()
    a$blankets[[v]] <- sort(union(immediate,spouse))
  }
  a$counts <- lapply(a$variables,function(v) count_samples(v,a$parents[[v]],a$samples,a$sizes))
  a$learned <- lapply(a$counts,learn_cpt,alpha=a$params$alpha)
  a$cpts <- lapply(
      a$variables,
      function(v) if (a$params$sources[v] == "GIVEN") a$expert[[v]] else a$learned[[v]]
  )
  a$likelihoods <- vapply(a$variables,function(v) log_likelihood(a$counts[[v]],a$cpts[[v]]),numeric(1))
  a$parameters <- vapply(a$counts,parameter_count,numeric(1))
  a$factors <- lapply(a$variables,function(v) cpt_factor(v,a$parents[[v]],a$cpts[[v]],a$sizes))
  a$random <- new_minstd(a$params$seed)
  a$family_scores <- new.env(hash=TRUE,parent=emptyenv())
  a
}
sequence <- function(a,variables) if (length(variables)) paste(a$names[variables],collapse=" ") else "-"
assignment_text <- function(a,assignment,variables) {
  if (!length(variables)) return("-")
  paste(
      vapply(variables,function(v) paste0(a$names[v],"=",a$states[[v]][assignment[v]]),character(1)),
      collapse=" "
  )
}
empty_evidence <- function() list(variables=integer(),states=integer())
parse_evidence <- function(a,fields) {
  evidence <- empty_evidence()
  for (field in fields) {
    pair <- strsplit(field,"=",fixed=TRUE)[[1L]]
    v <- match(pair[1L],a$names)
    evidence$variables <- c(evidence$variables,v)
    evidence$states <- c(evidence$states,match(pair[2L],a$states[[v]]))
  }
  evidence
}
query_parts <- function(a,fields) {
  separator <- match("|",fields)
  if (is.na(separator)) return(list(query=match(fields,a$names),evidence=empty_evidence()))
  list(
      query=match(fields[seq_len(separator-1L)],a$names),
      evidence=parse_evidence(a,fields[seq.int(separator+1L,length(fields))])
  )
}
plans <- function(a,initial,eliminate) {
  result <- lapply(
      c("MINFILL","GIVEN"),
      function(method) make_plan(initial,eliminate,method,a$params$order,a$sizes)
  )
  names(result) <- c("MINFILL","GIVEN")
  result
}
sum_result <- function(a,initial,plan,query) {
  factor <- execute_plan(initial,plan,a$sizes)$factor
  probability <- ordered_total(factor$entries)
  distribution <- new_factor(factor$variables,factor$entries/probability)
  marginals <- lapply(a$sizes,function(k) numeric(k))
  tuples <- assignments(distribution$variables,a$sizes)
  for (i in seq_along(tuples)) for (v in query) {
    s <- tuples[[i]][v]
    marginals[[v]][s] <- marginals[[v]][s]+distribution$entries[i]
  }
  list(distribution=distribution,probability=probability,marginals=marginals)
}
posterior <- function(a,query,evidence) {
  relevant <- closure(union(query,evidence$variables),a$parents)
  eliminate <- setdiff(relevant,union(query,evidence$variables))
  initial <- lapply(a$factors[relevant],reduce_factor,evidence=evidence,sizes=a$sizes)
  options <- plans(a,initial,eliminate)
  c(
      sum_result(a,initial,options[[a$params$method]],query),
      list(relevant=relevant,eliminate=eliminate,initial=initial,plans=options)
  )
}
joint_probability <- function(a,assignment,variables) {
  probability <- 1
  for (v in variables) probability <- probability*a$cpts[[v]][
      parent_row(a$parents[[v]],assignment,a$sizes),
      assignment[v]
  ]
  probability
}
query_enumeration <- function(a,result,query,evidence) {
  free <- setdiff(result$relevant,evidence$variables)
  n <- entry_count(free,a$sizes)
  if (n > a$params$limit) return(list(n=n,result="skipped"))
  query <- sort(query)
  entries <- numeric(entry_count(query,a$sizes))
  for (assignment in assignments(free,a$sizes)) {
    assignment[evidence$variables] <- evidence$states
    index <- parent_row(query,assignment,a$sizes)
    entries[index] <- entries[index]+joint_probability(a,assignment,result$relevant)
  }
  probability <- ordered_total(entries)
  agreement <- abs(log(probability)-log(result$probability)) <= 1e-9 && all(abs(entries/probability-result$distribution$entries) <= 1e-9)
  list(n=n,result=if (agreement) "agree" else "disagree")
}
elimination_lines <- function(a,result,agreement,enumeration) {
  lines <- c(
      paste("relevant",sequence(a,result$relevant)),
      paste("pruned",sequence(a,setdiff(a$variables,result$relevant))),
      paste("eliminate",sequence(a,result$eliminate))
  )
  for (method in c("MINFILL","GIVEN")) {
    plan <- result$plans[[method]]
    lines <- c(lines,paste("order",tolower(method)))
    for (step in plan$steps) lines <- c(
        lines,
        words(
            "step",
            a$names[step$variable],
            "fill",
            step$fill,
            "scope",
            sequence(a,step$scope),
            "entries",
            step$size
        )
    )
    lines <- c(lines,words("cost max",plan$maximum,"total",plan$total))
  }
  c(
      lines,
      paste("used",tolower(a$params$method)),
      paste("orders_agree",yes(agreement)),
      words("enumeration",enumeration$n,enumeration$result)
  )
}
marginal_lines <- function(a,prefix,query,marginals) {
  vapply(
      query,
      function(v) words(prefix,a$names[v],paste(paste(a$states[[v]],real(marginals[[v]])),collapse=" ")),
      character(1)
  )
}
answer_query <- function(a,query,evidence) {
  result <- posterior(a,query,evidence)
  lines <- paste("log_evidence",real(log(result$probability)))
  if (length(evidence$variables)) {
    conflict <- 0
    for (i in seq_along(evidence$variables)) conflict <- conflict+log(posterior(
        a,
        integer(),
        list(variables=evidence$variables[i],states=evidence$states[i])
    )$probability)
    lines <- c(lines,paste("conflict",real(conflict-log(result$probability))))
  }
  if (length(query) >= 2L) {
    tuples <- assignments(result$distribution$variables,a$sizes)
    for (i in seq_along(tuples)) lines <- c(
        lines,
        words(
            "joint",
            assignment_text(a,tuples[[i]],result$distribution$variables),
            real(result$distribution$entries[i])
        )
    )
  }
  lines <- c(lines,marginal_lines(a,"marginal",query,result$marginals))
  for (i in seq_along(evidence$variables)) {
    v <- evidence$variables[i]
    s <- evidence$states[i]
    without <- posterior(a,query,list(variables=evidence$variables[-i],states=evidence$states[-i]))$marginals
    shift <- max(vapply(query,function(q) max(abs(result$marginals[[q]]-without[[q]])),numeric(1)))
    lines <- c(lines,words("drop",paste0(a$names[v],"=",a$states[[v]][s]),"shift",real(shift)))
  }
  left <- sum_result(a,result$initial,result$plans$MINFILL,query)
  right <- sum_result(a,result$initial,result$plans$GIVEN,query)
  agreement <- abs(log(left$probability)-log(right$probability)) <= 1e-9 && all(abs(left$distribution$entries-right$distribution$entries) <= 1e-9)
  list(
      answer=lines,
      elimination=elimination_lines(a,result,agreement,query_enumeration(a,result,query,evidence))
  )
}
mpe_enumeration <- function(a,eliminate,evidence,assignment,maximum_probability) {
  n <- entry_count(eliminate,a$sizes)
  if (n > a$params$limit) return(list(n=n,result="skipped"))
  best <- -1
  best_assignment <- NULL
  for (candidate in assignments(eliminate,a$sizes)) {
    candidate[evidence$variables] <- evidence$states
    probability <- joint_probability(a,candidate,a$variables)
    if (probability > best) {
      best <- probability
      best_assignment <- candidate
    }
  }
  agreement <- identical(best_assignment,assignment) && abs(log(best)-log(maximum_probability)) <= 1e-9
  list(n=n,result=if (agreement) "agree" else "disagree")
}
answer_mpe <- function(a,evidence) {
  initial <- lapply(a$factors,reduce_factor,evidence=evidence,sizes=a$sizes)
  eliminate <- setdiff(a$variables,evidence$variables)
  options <- plans(a,initial,eliminate)
  outcomes <- list()
  for (method in c("MINFILL","GIVEN")) {
    execution <- execute_plan(initial,options[[method]],a$sizes,TRUE)
    assignment <- traceback(execution$products,a$sizes)
    assignment[evidence$variables] <- evidence$states
    outcomes[[method]] <- list(probability=execution$factor$entries[1L],assignment=assignment)
  }
  outcome <- outcomes[[a$params$method]]
  best <- outcome$probability
  assignment <- outcome$assignment
  probability <- if (length(evidence$variables)) posterior(a,integer(),evidence)$probability else 1
  lines <- c(
      paste("assignment",assignment_text(a,assignment,a$variables)),
      paste("log_joint",real(log(best))),
      paste("log_evidence",real(log(probability))),
      paste("posterior",real(best/probability))
  )
  for (v in eliminate) {
    plan <- make_plan(initial,setdiff(eliminate,v),a$params$method,a$params$order,a$sizes)
    factor <- execute_plan(initial,plan,a$sizes,TRUE)$factor
    alternatives <- setdiff(seq_len(a$sizes[v]),assignment[v])
    alternative <- alternatives[which.max(factor$entries[alternatives])]
    lines <- c(
        lines,
        words("margin",a$names[v],a$states[[v]][alternative],real(log(best)-log(factor$entries[alternative])))
    )
  }
  left <- outcomes$MINFILL
  right <- outcomes$GIVEN
  agreement <- identical(
      left$assignment,
      right$assignment
  ) && abs(log(left$probability)-log(right$probability)) <= 1e-9
  result <- list(relevant=a$variables,eliminate=eliminate,plans=options)
  list(
      answer=lines,
      elimination=elimination_lines(a,result,agreement,mpe_enumeration(a,eliminate,evidence,assignment,best))
  )
}
answer_sample <- function(a,number,query,evidence,counts) {
  exact <- posterior(a,query,evidence)$marginals
  lines <- marginal_lines(a,"exact",query,exact)
  rows <- character()
  weight <- squared_weight <- 0
  weights <- lapply(a$sizes,numeric)
  for (index in seq_len(tail(counts,1L))) {
    generated <- weighted_sample(a$topological,a$parents,a$cpts,a$sizes,evidence,a$random)
    current <- generated$weight
    weight <- weight+current
    squared_weight <- squared_weight+current*current
    for (v in query) {
      s <- generated$sample[v]
      weights[[v]][s] <- weights[[v]][s]+current
    }
    if (!(index %in% counts)) next
    maximum_error <- 0
    for (v in query) for (s in seq_len(a$sizes[v])) {
      estimate <- weights[[v]][s]/weight
      p <- exact[[v]][s]
      error <- abs(estimate-p)
      maximum_error <- max(maximum_error,error)
      rows <- c(
          rows,
          paste(number,index,a$names[v],a$states[[v]][s],real(estimate),real(p),real(error),sep=",")
      )
    }
    lines <- c(
        lines,
        words(
            "after",
            index,
            "weight",
            real(weight),
            "ess",
            real(weight*weight/squared_weight),
            "max_error",
            real(maximum_error)
        )
    )
  }
  list(answer=lines,rows=rows)
}
answer_predict <- function(a,v) {
  k <- a$sizes[v]
  likelihood <- 0
  confusion <- matrix(0L,k,k)
  for (sample in a$samples) {
    assignment <- sample
    probabilities <- numeric(k)
    for (s in seq_len(k)) {
      assignment[v] <- s
      p <- a$cpts[[v]][parent_row(a$parents[[v]],assignment,a$sizes),s]
      for (child in a$children[[v]]) p <- p*a$cpts[[child]][
          parent_row(a$parents[[child]],assignment,a$sizes),
          assignment[child]
      ]
      probabilities[s] <- p
    }
    probabilities <- probabilities/ordered_total(probabilities)
    predicted <- which.max(probabilities)
    actual <- sample[v]
    confusion[actual,predicted] <- confusion[actual,predicted]+1L
    likelihood <- likelihood+log(probabilities[actual])
  }
  correct <- sum(diag(confusion))
  n <- length(a$samples)
  lines <- c(
      paste("blanket",sequence(a,a$blankets[[v]])),
      words("accuracy",paste0(correct,"/",n),real(correct/n)),
      paste("log_loss",real(-likelihood/n)),
      paste("predicted",paste(a$states[[v]],collapse=" "))
  )
  for (s in seq_len(k)) lines <- c(lines,words("actual",a$states[[v]][s],paste(confusion[s,],collapse=" ")))
  lines
}
reachable <- function(a,x,z) {
  ancestors <- closure(z,a$parents)
  pending <- lapply(sort(x),function(v) c(v,1L))
  visited <- matrix(FALSE,length(a$variables),2L)
  if (length(x)) visited[cbind(x,rep(1L,length(x)))] <- TRUE
  head <- 1L
  while (head <= length(pending)) {
    position <- pending[[head]]
    head <- head+1L
    v <- position[1L]
    up <- position[2L] == 1L
    following <- list()
    if (up && !(v %in% z)) {
      following <- c(lapply(a$parents[[v]],function(p) c(p,1L)),lapply(a$children[[v]],function(c) c(c,2L)))
    } else if (!up) {
      if (!(v %in% z)) following <- c(following,lapply(a$children[[v]],function(c) c(c,2L)))
      if (v %in% ancestors) following <- c(following,lapply(a$parents[[v]],function(p) c(p,1L)))
    }
    for (next_position in following) if (!visited[next_position[1L],next_position[2L]]) {
      visited[next_position[1L],next_position[2L]] <- TRUE
      pending[[length(pending)+1L]] <- next_position
    }
  }
  setdiff(which(rowSums(visited) > 0L),union(x,z))
}
frequency_counts <- function(a,scope) {
  counts <- new.env(hash=TRUE,parent=emptyenv())
  for (sample in a$samples) {
    key <- as.character(parent_row(scope,sample,a$sizes))
    current <- counts[[key]]
    counts[[key]] <- if (is.null(current)) 1L else current+1L
  }
  counts
}
mutual_information <- function(a,x,y,z) {
  scope <- sort(unique(c(x,y,z)))
  xz <- sort(union(x,z))
  yz <- sort(union(y,z))
  z <- sort(z)
  counts <- frequency_counts(a,scope)
  cxz <- frequency_counts(a,xz)
  cyz <- frequency_counts(a,yz)
  cz <- frequency_counts(a,z)
  information <- 0
  n <- length(a$samples)
  for (key in sort(as.numeric(ls(counts,all.names=TRUE)))) {
    assignment <- canonical_assignment(key-1,scope,a$sizes)
    observed <- counts[[as.character(key)]]
    nxz <- cxz[[as.character(parent_row(xz,assignment,a$sizes))]]
    nyz <- cyz[[as.character(parent_row(yz,assignment,a$sizes))]]
    nz <- cz[[as.character(parent_row(z,assignment,a$sizes))]]
    information <- information+(observed/n)*log(as.numeric(observed*nz)/as.numeric(nxz*nyz))
  }
  degrees <- (entry_count(x,a$sizes)-1)*(entry_count(y,a$sizes)-1)*entry_count(z,a$sizes)
  list(information=information,statistic=2*n*information,degrees=degrees)
}
answer_dsep <- function(a,groups) {
  x <- groups[[1L]]
  y <- groups[[2L]]
  z <- if (length(groups) == 3L) groups[[3L]] else integer()
  reached <- reachable(a,x,z)
  information <- mutual_information(a,x,y,z)
  c(
      paste("result",if (!length(intersect(reached,y))) "separated" else "connected"),
      paste("reachable",sequence(a,reached)),
      words(
          "data cmi",
          real(information$information),
          "g2",
          real(information$statistic),
          "df",
          sprintf("%.0f",information$degrees)
      )
  )
}
answer_blanket <- function(a,v) {
  blanket <- a$blankets[[v]]
  rest <- setdiff(a$variables,c(v,blanket))
  c(
      paste("parents",sequence(a,a$parents[[v]])),
      paste("children",sequence(a,a$children[[v]])),
      paste("spouses",sequence(a,a$spouses[[v]])),
      paste("blanket",sequence(a,blanket)),
      paste("rest",sequence(a,rest)),
      paste("rest_separated",yes(!length(intersect(reachable(a,v,blanket),rest))))
  )
}
directed_path <- function(a,start,finish,ignored=integer()) {
  previous <- rep(-1L,length(a$variables))
  previous[start] <- 0L
  pending <- start
  head <- 1L
  while (head <= length(pending)) {
    v <- pending[head]
    head <- head+1L
    for (child in a$children[[v]]) {
      if (identical(c(v,child),ignored) || previous[child] != -1L) next
      previous[child] <- v
      if (child == finish) {
        result <- integer()
        current <- child
        while (current != 0L) {
          result <- c(result,current)
          current <- previous[current]
        }
        return(rev(result))
      }
      pending <- c(pending,child)
    }
  }
  NULL
}
cached_score <- function(a,v,parents) {
  key <- paste(c(v,sort(parents)),collapse=",")
  if (is.null(a$family_scores[[key]])) a$family_scores[[key]] <- family_score(
      v,
      parents,
      a$samples,
      a$sizes,
      a$params$alpha
  )
  a$family_scores[[key]]
}
answer_edge <- function(a,operation,x,y) {
  exists <- x %in% a$parents[[y]]
  if (operation == "ADD" && exists) return("result exists")
  if (operation != "ADD" && !exists) return("result missing")
  path <- if (operation == "ADD") directed_path(a,y,x) else if (operation == "REVERSE") directed_path(
      a,
      x,
      y,
      c(x,y)
  ) else NULL
  if (!is.null(path)) return(paste(
      "result cycle",
      paste(a$names[c(if (operation == "ADD") x else y,path)],collapse=" -> ")
  ))
  before_y <- cached_score(a,y,a$parents[[y]])
  parents_y <- if (operation == "ADD") union(a$parents[[y]],x) else setdiff(a$parents[[y]],x)
  after_y <- cached_score(a,y,parents_y)
  change <- after_y-before_y
  lines <- c("result ok",words("family",a$names[y],"before",real(before_y),"after",real(after_y)))
  if (operation == "REVERSE") {
    before_x <- cached_score(a,x,a$parents[[x]])
    after_x <- cached_score(a,x,union(a$parents[[x]],y))
    change <- (after_y-before_y)+(after_x-before_x)
    lines <- c(lines,words("family",a$names[x],"before",real(before_x),"after",real(after_x)))
  }
  c(lines,words("delta",real(change),if (change > 0) "improves" else "worsens"))
}
cpt_blocks <- function(a) {
  blocks <- list()
  n <- length(a$samples)
  for (v in a$variables) {
    source <- a$params$sources[v]
    parents <- a$parents[[v]]
    cpt <- a$cpts[[v]]
    counts <- a$counts[[v]]
    lines <- c(
        words("variable",a$names[v],"source",source),
        paste("states",paste(a$states[[v]],collapse=" ")),
        paste("parents",sequence(a,parents))
    )
    tuples <- assignments(parents,a$sizes)
    for (row in seq_along(tuples)) lines <- c(
        lines,
        words(
            "row",
            assignment_text(a,tuples[[row]],parents),
            "counts",
            paste(counts[row,],collapse=" "),
            "probs",
            paste(real(cpt[row,]),collapse=" ")
        )
    )
    ll <- a$likelihoods[v]
    d <- a$parameters[v]
    lines <- c(lines,words("loglik",real(ll),"parameters",d,"bic",real(ll-d*log(n)/2)))
    marginal <- posterior(a,v,empty_evidence())$marginals[[v]]
    frequencies <- colSums(counts)/n
    lines <- c(
        lines,
        words(
            "marginal model",
            paste(real(marginal),collapse=" "),
            "data",
            paste(real(frequencies),collapse=" ")
        )
    )
    if (source == "LEARNED") {
      difference <- if (is.null(a$expert[[v]])) "-" else real(max(abs(a$learned[[v]]-a$expert[[v]])))
      lines <- c(lines,paste("given_difference",difference))
    }
    blocks[[length(blocks)+1L]] <- lines
  }
  ll <- ordered_total(a$likelihoods)
  d <- sum(a$parameters)
  c(
      blocks,
      list(words(
          "network samples",
          n,
          "pseudocount",
          real(a$params$alpha),
          "loglik",
          real(ll),
          "parameters",
          d,
          "bic",
          real(ll-d*log(n)/2)
      ))
  )
}
structure_summary <- function(a) {
  options <- plans(a,a$factors,a$variables)
  widths <- vapply(
      options,
      function(plan) max(vapply(plan$steps,function(step) length(step$scope),integer(1)))-1L,
      integer(1)
  )
  graph <- interaction_graph(a$factors)
  moral_edges <- sum(lengths(graph)) %/% 2L
  lines <- c(
      words("variables",length(a$variables),"edges",sum(lengths(a$parents))),
      paste("topological_order",sequence(a,a$topological)),
      paste("roots",sequence(a,which(lengths(a$parents) == 0L))),
      paste("leaves",sequence(a,which(lengths(a$children) == 0L))),
      words("moral_edges",moral_edges,"width minfill",widths["MINFILL"],"given",widths["GIVEN"])
  )
  for (v in a$variables) lines <- c(
      lines,
      words(
          "variable",
          a$names[v],
          "states",
          a$sizes[v],
          "parents",
          length(a$parents[[v]]),
          "children",
          length(a$children[[v]]),
          "depth",
          a$depths[v],
          "ancestors",
          length(a$ancestors[[v]]),
          "descendants",
          length(a$descendants[[v]]),
          "blanket",
          length(a$blankets[[v]])
      )
  )
  lines
}
main <- function() {
  input <- read_inputs()
  a <- network_analysis(input)
  cpts <- cpt_blocks(a)
  answers <- elimination <- list()
  structure <- list(structure_summary(a))
  sampling <- "query,samples,variable,state,estimate,exact,abs_error"
  for (number in seq_along(input$queries)) {
    line <- input$queries[number]
    fields <- strsplit(line," ",fixed=TRUE)[[1L]]
    kind <- fields[1L]
    fields <- fields[-1L]
    heading <- words("query",number,line)
    if (kind == "QUERY") {
      parts <- query_parts(a,fields)
      result <- answer_query(a,parts$query,parts$evidence)
      answers[[length(answers)+1L]] <- c(heading,result$answer)
      elimination[[length(elimination)+1L]] <- c(heading,result$elimination)
    } else if (kind == "MPE") {
      result <- answer_mpe(a,parse_evidence(a,fields))
      answers[[length(answers)+1L]] <- c(heading,result$answer)
      elimination[[length(elimination)+1L]] <- c(heading,result$elimination)
    } else if (kind == "SAMPLE") {
      separator <- match("COUNTS",fields)
      parts <- query_parts(a,fields[seq_len(separator-1L)])
      result <- answer_sample(
          a,
          number,
          parts$query,
          parts$evidence,
          as.integer(fields[seq.int(separator+1L,length(fields))])
      )
      answers[[length(answers)+1L]] <- c(heading,result$answer)
      sampling <- c(sampling,result$rows)
    } else if (kind == "PREDICT") answers[[length(answers)+1L]] <- c(
        heading,
        answer_predict(a,match(fields[1L],a$names))
    ) else if (kind == "DSEP") {
      groups <- list(integer())
      for (field in fields) if (field == "|") groups[[length(groups)+1L]] <- integer() else groups[[length(groups)]] <- c(
          groups[[length(groups)]],
          match(field,a$names)
      )
      structure[[length(structure)+1L]] <- c(heading,answer_dsep(a,groups))
    } else if (kind == "BLANKET") structure[[length(structure)+1L]] <- c(
        heading,
        answer_blanket(a,match(fields[1L],a$names))
    ) else structure[[length(structure)+1L]] <- c(
        heading,
        answer_edge(a,fields[1L],match(fields[2L],a$names),match(fields[3L],a$names))
    )
  }
  dir.create("output",showWarnings=FALSE)
  write_blocks("output/cpts.txt",cpts)
  write_blocks("output/structure.txt",structure)
  write_blocks("output/answers.txt",answers)
  write_blocks("output/elimination.txt",elimination)
  write_blocks("output/sampling.csv",list(sampling))
}
main()
