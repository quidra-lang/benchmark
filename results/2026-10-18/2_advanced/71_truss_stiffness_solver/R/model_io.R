csv_rows <- function(name) strsplit(readLines(paste0("input/",name,".csv"),warn=FALSE)[-1L],",",fixed=TRUE)
read_model <- function() {
  nodes <- lapply(
      csv_rows("nodes"),
      function(r) list(id=as.integer(r[1L]),x=as.integer(r[2L]),y=as.integer(r[3L]))
  )
  sections <- lapply(
      csv_rows("sections"),
      function(r) list(name=r[1L],area=as.numeric(r[2L]),inertia=as.numeric(r[3L]))
  )
  materials <- lapply(
      csv_rows("materials"),
      function(r) list(
          name=r[1L],
          young=as.numeric(r[2L]),
          yield_stress=as.numeric(r[3L]),
          density=as.numeric(r[4L]),
          expansion=as.numeric(r[5L])
      )
  )
  ni <- vapply(nodes,function(n) n$id,integer(1))
  si <- vapply(sections,function(s) s$name,character(1))
  mi <- vapply(materials,function(m) m$name,character(1))
  members <- lapply(
      csv_rows("members"),
      function(r) list(
          id=as.integer(r[1L]),
          start=match(as.integer(r[2L]),ni),
          finish=match(as.integer(r[3L]),ni),
          section=match(r[4L],si),
          material=match(r[5L],mi),
          group=r[6L]
      )
  )
  ei <- vapply(members,function(e) e$id,integer(1))
  supports <- lapply(
      csv_rows("supports"),
      function(r) list(
          node=match(as.integer(r[1L]),ni),
          fixed=as.integer(r[2L:3L]),
          prescribed=as.numeric(r[4L:5L])
      )
  )
  cases <- combinations <- loads <- list()
  name <- ""
  for (line in readLines("input/loads.txt",warn=FALSE)) {
    f <- strsplit(line," ",fixed=TRUE)[[1L]]
    kind <- f[1L]
    if (kind == "LOADCASE") {
      name <- f[2L]
      loads <- list()
    } else if (kind == "END") {
      cases[[length(cases)+1L]] <- list(name=name,lines=loads)
    } else if (kind == "COMBINATION") {
      terms <- lapply(seq.int(3L,length(f),2L),function(i) list(name=f[i],factor=as.numeric(f[i+1L])))
      combinations[[length(combinations)+1L]] <- list(name=f[2L],terms=terms)
    } else if (kind == "FORCE") {
      loads[[length(loads)+1L]] <- list(
          kind=kind,
          node=match(as.integer(f[2L]),ni),
          horizontal=as.numeric(f[3L]),
          vertical=as.numeric(f[4L])
      )
    } else if (kind == "TEMPERATURE") {
      loads[[length(loads)+1L]] <- list(kind=kind,member=match(as.integer(f[2L]),ei),change=as.numeric(f[3L]))
    } else {
      loads[[length(loads)+1L]] <- list(kind=kind)
    }
  }
  settings <- list(influence=integer(),drawing=list())
  for (line in readLines("input/params.txt",warn=FALSE)) {
    f <- strsplit(line," ",fixed=TRUE)[[1L]]
    kind <- f[1L]
    v <- f[-1L]
    if (kind == "deck") {
      settings[[kind]] <- match(as.integer(v),ni)
    } else if (kind == "influence") {
      settings[[kind]] <- c(settings[[kind]],match(as.integer(v[1L]),ei))
    } else if (kind == "vehicle") {
      settings[[kind]] <- list(
          step=as.integer(v[1L]),
          axles=lapply(
              seq.int(2L,length(v),2L),
              function(i) list(offset=as.integer(v[i]),load=as.numeric(v[i+1L]))
          )
      )
    } else if (kind == "rating") {
      settings[[kind]] <- list(name=v[1L],dead=as.numeric(v[2L]),vehicle=as.numeric(v[3L]))
    } else if (kind == "slenderness") {
      settings[[kind]] <- as.numeric(v)
    } else if (kind == "deflection") {
      settings[[kind]] <- list(name=v[1L],ratio=as.integer(v[2L]))
    } else if (kind == "vibration") {
      settings[[kind]] <- list(name=v[1L],modes=as.integer(v[2L]),iterations=as.integer(v[3L]))
    } else if (kind == "removal") {
      settings[[kind]] <- v[1L]
    } else if (kind == "drawing") {
      settings[[kind]][[length(settings[[kind]])+1L]] <- list(
          name=v[1L],
          magnification=as.integer(v[2L]),
          horizontal=as.integer(v[3L]),
          vertical=as.integer(v[4L])
      )
    } else {
      settings[[kind]] <- as.integer(v)
    }
  }
  list(
      nodes=nodes,
      members=members,
      sections=sections,
      materials=materials,
      supports=supports,
      cases=cases,
      combinations=combinations,
      settings=settings
  )
}
