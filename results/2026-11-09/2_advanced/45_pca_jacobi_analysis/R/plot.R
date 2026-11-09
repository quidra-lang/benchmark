new_grid <- function(rows,columns) matrix(" ",rows,columns)
framed <- function(grid) {
  border <- paste0("+",strrep("-",ncol(grid)),"+")
  c(
      border,
      vapply(seq_len(nrow(grid)),function(i) paste0("|",paste(grid[i,],collapse=""),"|"),character(1)),
      border
  )
}
grid_index <- function(fraction,n) min(floor(fraction*n),n-1L)
rounded_position <- function(fraction,n) floor(fraction*n+0.5)
biplot_cell <- function(x,y,x_limit,y_limit,width,height) c(
    grid_index((y_limit-y)/(2*y_limit),height),
    grid_index((x+x_limit)/(2*x_limit),width)
)
circle_cell <- function(a,b,radius) c(
    radius %/% 2L+1L-rounded_position(b,radius/2),
    radius+1L+rounded_position(a,radius)
)
diagnostic_cell <- function(t2,spe,x,y,width,height) c(
    height-1L-grid_index(spe/y,height),
    grid_index(t2/x,width)
)
shaft_cells <- function(origin,tip) {
  dr <- tip[1L]-origin[1L]
  dc <- tip[2L]-origin[2L]
  steps <- max(abs(dc),abs(dr))
  if (steps <= 1L) return(list())
  lapply(seq_len(steps-1L),function(s) c(origin[1L]+sign(dr)*((2*s*abs(dr)+steps) %/% (2*steps)),
    origin[2L]+sign(dc)*((2*s*abs(dc)+steps) %/% (2*steps))))
}
shaft_character <- function(origin,tip) {
  dr <- tip[1L]-origin[1L]
  dc <- tip[2L]-origin[2L]
  if (2*abs(dr) <= abs(dc)) "-" else if (2*abs(dc) <= abs(dr)) "|" else if (dc*dr < 0) "/" else "\\"
}
scree_line <- function(n,kaiser,broken,width) paste0("|",paste(vapply(seq_len(width),function(p)
  if (p == broken) "o" else if (p == kaiser) ":" else if (p <= n) "#" else " ",character(1)),collapse=""),"|")
