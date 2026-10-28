ratio <- function(a,b) if (b == 0L) "-" else sprintf("%.4f",a/b)
sam_header <- function(references) {
  c(
      "@HD\tVN:1.6\tSO:unsorted",
      vapply(references,function(r) paste0("@SQ\tSN:",r$name,"\tLN:",length(r$bases)),character(1)),
      "@PG\tID:fm_index_aligner\tPN:fm_index_aligner\tVN:1.0"
  )
}
sam_record <- function(result,references,maximum_alternatives) {
  read <- result$read
  if (!result$mapped) return(paste(
      c(
          read$name,
          4L,
          "*",
          0L,
          0L,
          "*",
          "*",
          0L,
          0L,
          paste(read$bases,collapse=""),
          paste(read$quality,collapse=""),
          paste0("YM:Z:",result$reason)
      ),
      collapse="\t"
  ))
  alignment <- result$primary
  reverse <- alignment$strand == "-"
  fields <- c(
      read$name,
      if (reverse) "16" else "0",
      references[[alignment$reference]]$name,
      alignment$position+1L,
      result$mapq,
      alignment$cigar,
      "*",
      "0",
      "0",
      paste(if (reverse) reverse_complement(read$bases) else read$bases,collapse=""),
      paste(if (reverse) rev(read$quality) else read$quality,collapse=""),
      paste0("NM:i:",alignment$nm),
      paste0("MD:Z:",alignment$md),
      paste0("AS:i:",result$score),
      paste0("X0:i:",result$x0),
      paste0("X1:i:",result$x1),
      paste0("YM:Z:",result$method)
  )
  if (length(result$others) >= 1L && length(result$others) <= maximum_alternatives) {
    alternative <- paste(
        vapply(
            result$others,
            function(item) paste0(
                references[[item$reference]]$name,
                ",",
                item$strand,
                item$position+1L,
                ",",
                item$cigar,
                ",",
                item$nm,
                ";"
            ),
            character(1)
        ),
        collapse=""
    )
    fields <- c(fields,paste0("XA:Z:",alternative))
  }
  paste(fields,collapse="\t")
}
write_lines <- function(name,lines) {
  dir.create("output",showWarnings=FALSE)
  writeLines(lines,file.path("output",name),useBytes=TRUE)
}
