PHI <- 0.6180339887498949
golden <- function(objective,a,b,iterations) {
  c <- b-PHI*(b-a)
  d <- a+PHI*(b-a)
  fc <- objective(c)
  fd <- objective(d)
  records <- list(c(a,b,c,d,fc,fd))
  for (unused in seq_len(iterations)) {
    if (fc < fd) {
      b <- d
      d <- c
      fd <- fc
      c <- b-PHI*(b-a)
      fc <- objective(c)
    } else {
      a <- c
      c <- d
      fc <- fd
      d <- a+PHI*(b-a)
      fd <- objective(d)
    }
    records[[length(records)+1L]] <- c(a,b,c,d,fc,fd)
  }
  list(point=if (fc < fd) c else d,value=if (fc < fd) fc else fd,records=records)
}
nelder_mead <- function(objective,beta,gamma,delta_beta,delta_gamma,alpha,chi,psi,omega,iterations) {
  points <- list(c(beta,gamma),c(beta+delta_beta,gamma),c(beta,gamma+delta_gamma))
  vertices <- lapply(
      seq_along(points),
      function(i) list(
          number=i-1L,
          beta=points[[i]][1L],
          gamma=points[[i]][2L],
          value=objective(points[[i]][1L],points[[i]][2L])
      )
  )
  initial <- vertices
  serial <- 3L
  records <- list()
  ordered <- function(vertices) vertices[order(
      vapply(vertices,function(vertex) vertex$value,numeric(1)),
      vapply(vertices,function(vertex) vertex$number,integer(1))
  )]
  toward <- function(origin,target,factor) origin+factor*(target-origin)
  for (unused in seq_len(iterations)) {
    vertices <- ordered(vertices)
    first <- vertices[[1L]]
    second <- vertices[[2L]]
    third <- vertices[[3L]]
    centroid <- c((first$beta+second$beta)/2,(first$gamma+second$gamma)/2)
    reflected <- centroid+alpha*(centroid-c(third$beta,third$gamma))
    fr <- objective(reflected[1L],reflected[2L])
    accepted <- NULL
    value <- 0
    operation <- "shrink"
    if (fr < first$value) {
      expanded <- toward(centroid,reflected,chi)
      fe <- objective(expanded[1L],expanded[2L])
      if (fe < fr) {
        accepted <- expanded
        value <- fe
        operation <- "expand"
      } else {
        accepted <- reflected
        value <- fr
        operation <- "reflect"
      }
    } else if (fr < second$value) {
      accepted <- reflected
      value <- fr
      operation <- "reflect"
    } else if (fr < third$value) {
      contracted <- toward(centroid,reflected,psi)
      fc <- objective(contracted[1L],contracted[2L])
      if (fc <= fr) {
        accepted <- contracted
        value <- fc
        operation <- "contract_out"
      }
    } else {
      contracted <- toward(centroid,c(third$beta,third$gamma),psi)
      fc <- objective(contracted[1L],contracted[2L])
      if (fc < third$value) {
        accepted <- contracted
        value <- fc
        operation <- "contract_in"
      }
    }
    if (is.null(accepted)) {
      vertices <- list(first)
      for (vertex in list(second,third)) {
        point <- toward(c(first$beta,first$gamma),c(vertex$beta,vertex$gamma),omega)
        vertices[[length(vertices)+1L]] <- list(
            number=serial,
            beta=point[1L],
            gamma=point[2L],
            value=objective(point[1L],point[2L])
        )
        serial <- serial+1L
      }
    } else {
      vertices <- list(first,second,list(number=serial,beta=accepted[1L],gamma=accepted[2L],value=value))
      serial <- serial+1L
    }
    vertices <- ordered(vertices)
    records[[length(records)+1L]] <- list(operation=operation,vertex=vertices[[1L]])
  }
  list(initial=initial,records=records,vertices=vertices)
}
