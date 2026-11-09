render_grid <- function(polygons,operands,x0,y0,cw,ch,cols,rows) {
    result_rings <- unlist(polygons,recursive=FALSE)
    counts <- setNames(integer(4L),c("#","a","b","+"))
    lines <- character()
    for (j in seq_len(rows)-1L) {
        y <- q(2*y0+(2*(rows-1L-j)+1L)*ch,2)
        cells <- character(cols)
        for (i in seq_len(cols)-1L) {
            x <- q(2*x0+(2*i+1L)*cw,2)
            p <- list(x,y)
            character <- "."
            if (interior(result_rings,p)) {
                character <- "#"
            } else if (!is.null(operands)) {
                a <- interior(operands[[1]]$rings,p)
                b <- interior(operands[[2]]$rings,p)
                character <- if (a && b) "+" else if (a) "a" else if (b) "b" else "."
            }
            cells[i+1L] <- character
            if (character %in% names(counts)) counts[character] <- counts[character]+1L
        }
        lines <- c(lines,paste(cells,collapse=""))
    }
    list(lines=lines,counts=counts)
}
