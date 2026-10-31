read_points <- function() {
    rows <- lapply(
        strsplit(readLines("input/points.csv")[-1L], ",", fixed = TRUE),
        function(fields) list(
            id = as.integer(fields[1L]),
            x = as.numeric(fields[2L]),
            y = as.numeric(fields[3L])
        )
    )
    rows[order(vapply(rows, function(point) point$id, 0L))]
}
read_params <- function() {
    values <- list()
    for (fields in strsplit(
        readLines("input/params.txt"),
        " ",
        fixed = TRUE
    )) values[[fields[1L]]] <- fields[-1L]
    integer <- function(key, i = 1L) as.integer(values[[key]][i])
    xi_text <- values$XI[1L]
    xi <- as.numeric(strsplit(xi_text, "/", fixed = TRUE)[[1L]])
    list(
        eps_list = as.integer(values$EPS),
        min_pts = integer("MIN_PTS"),
        max_eps = integer("OPTICS_MAX_EPS"),
        extract_eps = as.integer(values$EXTRACT_EPS),
        xi_text = xi_text,
        xi_u = xi[1L],
        xi_v = xi[2L],
        xi_min_size = integer("XI_MIN_SIZE"),
        map_width = integer("MAP_SIZE"),
        map_height = integer("MAP_SIZE", 2L),
        kdist_width = integer("KDIST_PLOT"),
        kdist_height = integer("KDIST_PLOT", 2L),
        plot_width = integer("PLOT_WIDTH")
    )
}
