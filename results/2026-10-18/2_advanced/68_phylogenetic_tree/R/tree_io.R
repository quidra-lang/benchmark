real_text <- function(value,places) {
  text <- sprintf(paste0("%.",places,"f"),value)
  if (startsWith(text,"-") && as.numeric(text) == 0) substring(text,2L) else text
}
symbols <- function(mask,n) paste(
    vapply(
        seq_len(n),
        function(taxon) if (bitwAnd(mask,bitwShiftL(1L,taxon-1L)) != 0L) "*" else ".",
        character(1)
    ),
    collapse=""
)
child_order <- function(rooted,taxon_names) {
  minima <- character(length(rooted$tree$adjacent))
  children <- vector("list",length(rooted$tree$adjacent))
  for (node in rev(rooted$order)) {
    if (node <= rooted$tree$size) {
      minima[node] <- taxon_names[node]
      children[[node]] <- integer()
    } else {
      children[[node]] <- rooted$children[[node]][order(minima[rooted$children[[node]]])]
      minima[node] <- minima[children[[node]][1L]]
    }
  }
  children
}
newick <- function(tree,taxon_names,outgroup,lengths=FALSE,support=NULL) {
  rooted <- root_tree(tree,outgroup)
  children <- child_order(rooted,taxon_names)
  node_text <- function(node) {
    if (node <= tree$size) text <- taxon_names[node] else {
      text <- paste0("(",paste(vapply(children[[node]],node_text,character(1)),collapse=","),")")
      if (!is.null(support) && node != rooted$root) {
        key <- as.character(rooted$masks[node])
        text <- paste0(text,if (key %in% names(support)) support[[key]] else 0L)
      }
    }
    if (lengths && node != rooted$root) text <- paste0(
        text,
        ":",
        real_text(tree$adjacent[[node]][[as.character(rooted$parents[node])]],5L)
    )
    text
  }
  paste0(node_text(rooted$root),";")
}
cladogram <- function(tree,taxon_names,outgroup,support) {
  rooted <- root_tree(tree,outgroup)
  children <- child_order(rooted,taxon_names)
  lines <- "*"
  descend <- function(node,prefix) {
    for (i in seq_along(children[[node]])) {
      child <- children[[node]][i]
      last_child <- i == length(children[[node]])
      connector <- if (last_child) "`-- " else "|-- "
      key <- as.character(rooted$masks[child])
      label <- if (child <= tree$size) taxon_names[child] else paste0(
          "[",
          if (key %in% names(support)) support[[key]] else 0L,
          "]"
      )
      lines <<- c(lines,paste0(prefix,connector,label))
      descend(child,paste0(prefix,if (last_child) "    " else "|   "))
    }
  }
  descend(rooted$root,"")
  lines
}
write_lines <- function(filename,lines) {
  dir.create("output",showWarnings=FALSE)
  writeLines(lines,file.path("output",filename),useBytes=TRUE)
}
