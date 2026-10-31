parse_target <- function(text) {
  lapply(strsplit(text," | ",fixed=TRUE)[[1L]],function(alternative) lapply(strsplit(alternative," & ",fixed=TRUE)[[1L]],function(clause) {
    fields <- strsplit(clause," ",fixed=TRUE)[[1L]]
    reference <- fields[1L]
    mandatory <- endsWith(reference,"!")
    if (mandatory) reference <- substr(reference,1L,nchar(reference)-1L)
    list(reference=reference,mandatory=mandatory,operation=fields[2L],literal=parse_expression(fields[3L]))
  }))
}
read_policies <- function() {
  elements <- list()
  stack <- integer()
  for (raw in readLines("input/policies.txt",warn=FALSE)) {
    line <- sub("^ +","",raw)
    if (!nzchar(line) || startsWith(line,"#")) next
    space <- regexpr(" ",line,fixed=TRUE)[1L]
    keyword <- if (space == -1L) line else substr(line,1L,space-1L)
    rest <- if (space == -1L) "" else substring(line,space+1L)
    if (keyword %in% c("POLICYSET","POLICY","RULE")) {
      fields <- strsplit(rest," ",fixed=TRUE)[[1L]]
      element <- new.env(parent=emptyenv())
      element$index <- length(elements)+1L
      element$kind <- tolower(keyword)
      element$identifier <- fields[1L]
      element$behavior <- fields[2L]
      element$parent <- if (length(stack)) tail(stack,1L) else 0L
      element$targets <- element$obligations <- element$advice <- list()
      element$children <- integer()
      element$condition <- NULL
      if (element$parent != 0L) elements[[element$parent]]$children <- c(
          elements[[element$parent]]$children,
          element$index
      )
      elements[[element$index]] <- element
      stack <- c(stack,element$index)
    } else if (keyword == "END") {
      stack <- stack[-length(stack)]
    } else if (keyword == "TARGET") {
      element <- elements[[tail(stack,1L)]]
      element$targets[[length(element$targets)+1L]] <- parse_target(rest)
    } else if (keyword == "CONDITION") {
      elements[[tail(stack,1L)]]$condition <- parse_expression(rest)
    } else {
      first <- regexpr(" ",rest,fixed=TRUE)[1L]
      effect <- substr(rest,1L,first-1L)
      tail_text <- substring(rest,first+1L)
      second <- regexpr(" ",tail_text,fixed=TRUE)[1L]
      identifier <- if (second == -1L) tail_text else substr(tail_text,1L,second-1L)
      arguments <- list()
      if (second != -1L) for (part in strsplit(substring(tail_text,second+1L),";",fixed=TRUE)[[1L]]) {
        part <- trimws(part,whitespace=" ")
        equals <- regexpr("=",part,fixed=TRUE)[1L]
        arguments[[length(arguments)+1L]] <- list(
            name=substr(part,1L,equals-1L),
            expression=parse_expression(substring(part,equals+1L))
        )
      }
      definition <- list(effect=effect,identifier=identifier,arguments=arguments)
      element <- elements[[tail(stack,1L)]]
      if (keyword == "OBLIGATION") element$obligations[[length(element$obligations)+1L]] <- definition else element$advice[[length(element$advice)+1L]] <- definition
    }
  }
  elements
}
