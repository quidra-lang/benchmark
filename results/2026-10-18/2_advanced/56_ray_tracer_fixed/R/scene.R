read_scene <- function() {
  scene <- list(fog=NULL,objects=list(),lights=list())
  materials <- new.env(hash=TRUE,parent=emptyenv())
  for (line in readLines(file.path("input","scene.txt"))) {
    if (!nzchar(line) || startsWith(line,"#")) next
    words <- strsplit(line," ",fixed=TRUE)[[1L]]
    kind <- words[1L]
    if (kind == "material") {
      values <- as.numeric(words[-c(1L,2L)])
      material <- new.env(parent=emptyenv())
      material$name <- words[2L]
      material$color <- values[1:3]
      for (i in seq_along(c("kd","ks","n","kr","kt","ior"))) material[[c(
          "kd",
          "ks",
          "n",
          "kr",
          "kt",
          "ior"
      )[i]]] <- values[i+3L]
      material$checker <- NULL
      materials[[words[2L]]] <- material
    } else if (kind == "checker") {
      values <- as.numeric(words[-c(1L,2L)])
      materials[[words[2L]]]$checker <- list(color=values[1:3],size=values[4L])
    } else if (kind %in% c("sphere","plane","box")) {
      values <- as.numeric(words[-c(1L,2L,3L)])
      object <- list(
          number=length(scene$objects)+1L,
          kind=kind,
          label=words[2L],
          material=materials[[words[3L]]]
      )
      if (kind == "sphere") object <- c(
          object,
          list(center=values[1:3],radius=values[4L])
      ) else if (kind == "plane")
        object <- c(
            object,
            list(point=values[1:3],normal=norm(values[4:6]))
        ) else object <- c(object,list(lo=values[1:3],hi=values[4:6]))
      scene$objects[[length(scene$objects)+1L]] <- object
    } else if (kind %in% c("point","spot","sun","area")) {
      values <- as.numeric(words[-1L])
      light <- list(number=length(scene$lights)+1L,kind=kind,intensity=tail(values,1L),samples=1L)
      if (kind == "sun") light$direction <- norm(-values[1:3]) else {
        light$position <- values[1:3]
        if (kind == "spot") light <- c(
            light,
            list(direction=norm(values[4:6]),outer=values[7L],inner=values[8L])
        )
        if (kind == "area") {
          light$u <- values[4:6]
          light$v <- values[7:9]
          light$divisions <- values[10L]
          light$samples <- values[10L]^2
        }
      }
      scene$lights[[length(scene$lights)+1L]] <- light
    } else {
      values <- as.numeric(words[-1L])
      scene[[kind]] <- if (kind == "ambient") values[1L] else values
    }
  }
  scene
}
