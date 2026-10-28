path_text <- function(path) paste(path, collapse = ",")
attribute_text <- function(attribute) sprintf(
    "path %s origin %s med %d comm %s",
    path_text(attribute$path),
    attribute$origin,
    attribute$med,
    communities_text(attribute$communities)
)
route_text <- function(route, network) {
    if (is.null(route)) return("NONE")
    communities <- communities_text(route$communities)
    if (route_local(route)) return(sprintf("LOCAL origin %s comm %s", route$origin, communities))
    sprintf(
        "next %d path %s link %s lp %d med %d origin %s comm %s",
        route_neighbor(route),
        path_text(route$path),
        network$links[[route$link]]$name,
        route$local_pref,
        route$med,
        route$origin,
        communities
    )
}
write_reports <- function(reports) {
    dir.create("output", showWarnings = FALSE)
    for (name in names(reports)) writeLines(reports[[name]], file.path("output", name), useBytes = TRUE)
}
