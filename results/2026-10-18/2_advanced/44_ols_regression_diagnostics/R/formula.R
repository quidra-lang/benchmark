make_factor <- function(name) {
  if (startsWith(name,"C(")) return(list(
      name=name,
      column=substr(name,3L,nchar(name)-1L),
      power=1L,
      categorical=TRUE
  ))
  if (startsWith(name,"I(")) {
    words <- strsplit(substr(name,3L,nchar(name)-1L),"^",fixed=TRUE)[[1L]]
    return(list(name=name,column=words[1L],power=as.integer(words[2L]),categorical=FALSE))
  }
  list(name=name,column=name,power=1L,categorical=FALSE)
}
parse_model <- function(line) {
  parts <- strsplit(line," weights=",fixed=TRUE)[[1L]]
  original <- parts[1L]
  weight <- if (length(parts) == 2L) parts[2L] else NULL
  words <- strsplit(original," ~ ",fixed=TRUE)[[1L]]
  response <- words[1L]
  terms <- list()
  seen <- character()
  for (expression in strsplit(words[2L]," + ",fixed=TRUE)[[1L]]) {
    star <- grepl("*",expression,fixed=TRUE)
    factors <- lapply(strsplit(expression,if (star) "*" else ":",fixed=TRUE)[[1L]],make_factor)
    if (star) {
      subsets <- unlist(
          lapply(seq_along(factors),function(size) combn(seq_along(factors),size,simplify=FALSE)),
          recursive=FALSE
      )
      expanded <- lapply(subsets,function(indices) factors[indices])
    } else expanded <- list(factors)
    for (sequence in expanded) {
      names <- vapply(sequence,`[[`,character(1),"name")
      key <- paste(sort(names,method="radix"),collapse=":")
      if (key %in% seen) next
      seen <- c(seen,key)
      terms[[length(terms)+1L]] <- list(factors=sequence,name=paste(names,collapse=":"),names=names)
    }
  }
  all_factors <- unlist(lapply(terms,`[[`,"factors"),recursive=FALSE)
  factor_columns <- unique(vapply(all_factors,`[[`,character(1),"column"))
  categorical <- unique(vapply(Filter(function(f) f$categorical,all_factors),`[[`,character(1),"column"))
  list(original=original,response=response,weight=weight,terms=terms,factor_columns=factor_columns,
    categorical=categorical,variables=unique(c(factor_columns,response,weight)))
}
contained <- function(a,b) length(a$names) < length(b$names) && all(a$names %in% b$names)
format_formula <- function(model,indices) paste(model$response,"~",if (length(indices))
  paste(vapply(model$terms[sort(indices)],`[[`,character(1),"name"),collapse=" + ") else "1")
removable <- function(model,indices) indices[!vapply(indices,function(i)
  any(vapply(indices,function(j) contained(model$terms[[i]],model$terms[[j]]),logical(1))),logical(1))]
candidates <- function(model,indices) {
  remaining <- setdiff(seq_along(model$terms),indices)
  remaining[vapply(remaining,function(i) all(vapply(seq_along(model$terms),function(j)
    !contained(model$terms[[j]],model$terms[[i]]) || j %in% indices,logical(1))),logical(1))]
}
hierarchical <- function(
    model,
    indices
) all(vapply(indices,function(i) all(vapply(seq_along(model$terms),function(j)
  !contained(model$terms[[j]],model$terms[[i]]) || j %in% indices,logical(1))),logical(1)))
factor_value <- function(factor,row,level) {
  value <- row[[factor$column]]
  if (factor$categorical) return(as.numeric(value == level))
  if (factor$power == 2L) return(value*value)
  if (factor$power == 3L) return(value*value*value)
  value
}
column_value <- function(column,row) {
  if (!length(column$components)) return(1)
  first <- column$components[[1L]]
  value <- factor_value(first$factor,row,first$level)
  for (component in column$components[-1L]) value <- value*factor_value(component$factor,row,component$level)
  value
}
design_values <- function(design,row) vapply(design$columns,column_value,numeric(1),row=row)
build_design <- function(model,data) {
  numbers <- which(vapply(
      data$rows,
      function(row) all(vapply(model$variables,function(name) !is.null(row[[name]]),logical(1))),
      logical(1)
  ))
  rows <- data$rows[numbers]
  levels <- setNames(lapply(model$categorical,function(name) sort(unique(vapply(rows,`[[`,character(1),name)),method="radix")),model$categorical)
  columns <- list(list(term=0L,name="(Intercept)",components=list()))
  for (i in seq_along(model$terms)) {
    term <- model$terms[[i]]
    components <- lapply(term$factors,function(f) {
      if (f$categorical) lapply(
          levels[[f$column]][-1L],
          function(level) list(factor=f,name=paste0(f$name,level),level=level)
      )
      else list(list(factor=f,name=f$name,level=NULL))
    })
    indices <- do.call(
        expand.grid,
        c(lapply(components,seq_along),list(KEEP.OUT.ATTRS=FALSE,stringsAsFactors=FALSE))
    )
    for (r in seq_len(nrow(indices))) {
      choices <- lapply(seq_along(components),function(j) components[[j]][[indices[r,j]]])
      columns[[length(columns)+1L]] <- list(term=i,name=paste(vapply(choices,`[[`,character(1),"name"),collapse=":"),components=choices)
    }
  }
  matrix <- matrix(0,length(rows),length(columns))
  for (i in seq_along(rows)) matrix[i,] <- vapply(columns,column_value,numeric(1),row=rows[[i]])
  response <- vapply(rows,`[[`,numeric(1),model$response)
  weights <- if (is.null(model$weight)) rep(1,length(rows)) else vapply(rows,`[[`,numeric(1),model$weight)
  list(
      model=model,
      numbers=numbers,
      rows=rows,
      levels=levels,
      columns=columns,
      matrix=matrix,
      response=response,
      weights=weights
  )
}
subset_matrix <- function(design,indices) {
  columns <- which(vapply(
      design$columns,
      function(column) column$term == 0L || column$term %in% indices,
      logical(1)
  ))
  design$matrix[,columns,drop=FALSE]
}
predictable <- function(design,row) all(vapply(design$model$factor_columns,function(name)
  !is.null(row[[name]]) && (!(name %in% names(design$levels)) || row[[name]] %in% design$levels[[name]]),logical(1)))
