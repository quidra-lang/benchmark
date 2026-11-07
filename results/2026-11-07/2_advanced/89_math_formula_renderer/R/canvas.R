walk_boxes <- function(box, x, y, level=0L, role="") {
    result <- list(list(box=box, x=x, y=y, level=level, role=role))
    for (child in box$children) result <- c(result, walk_boxes(child$box, x+child$x, y+child$y, level+1L, child$role))
    result
}
draw_boxes <- function(roots, width, height) {
    grid <- matrix(" ", height, width)
    for (root in roots) for (entry in walk_boxes(root$box, root$x, root$y)) {
        for (drawn in entry$box$strings) {
            characters <- strsplit(drawn$text,"",fixed=TRUE)[[1]]
            for (i in seq_along(characters)) if (characters[i] != " ") grid[entry$y+drawn$y+1L,entry$x+drawn$x+i] <- characters[i]
        }
    }
    vapply(seq_len(height), function(row) sub(" +$","",paste(grid[row,],collapse="")), "")
}
box_lines <- function(roots) {
    result <- list()
    for (root in roots) for (entry in walk_boxes(root$box,root$x,root$y)) {
        box <- entry$box
        text <- paste0(strrep("  ",entry$level), entry$role, box$description, " x=",entry$x," y=",entry$y,
            " w=",box$width," h=",box$height," b=",box$baseline)
        result[[length(result)+1L]] <- list(text=text, level=entry$level, kind=strsplit(box$description," ",fixed=TRUE)[[1]][1])
    }
    result
}
