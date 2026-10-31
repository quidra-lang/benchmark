new_canvas <- function(direction, main_length, secondary_length) {
    canvas <- new.env(parent=emptyenv())
    canvas$direction <- direction
    canvas$main_length <- main_length
    canvas$vertical <- direction %in% c("TB", "BT")
    canvas$rows <- if (canvas$vertical) main_length else secondary_length
    canvas$columns <- if (canvas$vertical) secondary_length else main_length
    canvas$lines <- matrix(0L, canvas$rows, canvas$columns)
    canvas$arrows <- canvas$boxes <- matrix(" ", canvas$rows, canvas$columns)
    canvas$highlighted <- matrix(FALSE, canvas$rows, canvas$columns)
    canvas
}
canvas_cell <- function(canvas, main, secondary) {
    if (canvas$direction %in% c("BT", "RL")) main <- canvas$main_length-1L-main
    if (canvas$vertical) c(main, secondary) else c(secondary, main)
}
add_line <- function(canvas, main, secondary, character) {
    cell <- canvas_cell(canvas, main, secondary)+1L
    bit <- switch(character, "|"=1L, "-"=2L, "+"=4L)
    canvas$lines[cell[1],cell[2]] <- bitwOr(canvas$lines[cell[1],cell[2]], bit)
}
main_line <- function(canvas, start, stop, secondary) {
    if (start > stop) return(invisible(NULL))
    character <- if (canvas$vertical) "|" else "-"
    for (main in seq.int(start, stop)) add_line(canvas, main, secondary, character)
}
draw_segment <- function(canvas, start, gap, a, b, offset) {
    if (a == b) {
        main_line(canvas, start, start+gap-1L, a)
        return(invisible(NULL))
    }
    main_line(canvas, start, start+offset-1L, a)
    add_line(canvas, start+offset, a, "+")
    add_line(canvas, start+offset, b, "+")
    character <- if (canvas$vertical) "-" else "|"
    if (abs(a-b) > 1L) for (secondary in seq.int(min(a,b)+1L, max(a,b)-1L)) {
        add_line(canvas, start+offset, secondary, character)
    }
    main_line(canvas, start+offset+1L, start+gap-1L, b)
}
draw_arrow <- function(canvas, point, reversed_edge) {
    forward <- c(TB="v", BT="^", LR=">", RL="<")
    backward <- c(TB="^", BT="v", LR="<", RL=">")
    cell <- canvas_cell(canvas, point[1], point[2])+1L
    canvas$arrows[cell[1],cell[2]] <- if (reversed_edge) backward[[canvas$direction]] else forward[[canvas$direction]]
}
highlight_route <- function(canvas, points) {
    for (i in seq_len(length(points)-1L)) {
        a <- points[[i]]
        b <- points[[i+1L]]
        row_step <- sign(b[1]-a[1])
        column_step <- sign(b[2]-a[2])
        for (step in 0:(abs(b[1]-a[1])+abs(b[2]-a[2]))) {
            canvas$highlighted[a[1]+step*row_step+1L,a[2]+step*column_step+1L] <- TRUE
        }
    }
}
draw_box <- function(canvas, label, band, coordinate, left, on_path) {
    text <- paste0(if (on_path) "{" else "[", label, if (on_path) "}" else "]")
    if (canvas$vertical) {
        cell <- canvas_cell(canvas, band, coordinate-left)
    } else if (canvas$direction == "LR") {
        cell <- c(coordinate, band)
    } else cell <- c(coordinate, canvas$main_length-band-nchar(text))
    characters <- strsplit(text, "", fixed=TRUE)[[1]]
    canvas$boxes[cell[1]+1L,cell[2]+seq_along(characters)] <- characters
}
crossing_cells <- function(canvas) sum(bitwAnd(canvas$lines, 3L) == 3L)
drawing_lines <- function(canvas) {
    lines <- paste0("    ", paste((seq_len(canvas$columns)-1L) %% 10L, collapse=""))
    for (row in seq_len(canvas$rows)) {
        bits <- canvas$lines[row,]
        characters <- ifelse(bits == 0L, " ", ifelse(bits == 1L, "|", ifelse(bits == 2L, "-", "+")))
        characters[canvas$highlighted[row,]] <- "#"
        arrows <- canvas$arrows[row,]
        characters[arrows != " "] <- arrows[arrows != " "]
        boxes <- canvas$boxes[row,]
        characters[boxes != " "] <- boxes[boxes != " "]
        text <- paste0(sprintf("%3d ", row-1L), paste(characters, collapse=""))
        lines <- c(lines, sub(" +$", "", text))
    }
    lines
}
