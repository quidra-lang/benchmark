TRUSS_PI <- 3.141592653589793
buckling <- function(p,g,inertia=p$inertia) TRUSS_PI*TRUSS_PI*p$young*inertia/(g$length*g$length)
utilization <- function(force,p,g,section=NULL) {
  area <- if (is.null(section)) p$area else section$area
  inertia <- if (is.null(section)) p$inertia else section$inertia
  max(abs(force/area)/p$yield_stress,max(0,-force)/buckling(p,g,inertia))
}
slenderness <- function(p,g,section=NULL) {
  area <- if (is.null(section)) p$area else section$area
  inertia <- if (is.null(section)) p$inertia else section$inertia
  g$length/sqrt(inertia/area)
}
slenderness_limit <- function(number,combinations,limits) if (any(vapply(
    combinations,
    function(r) r$forces[number] < 0,
    logical(1)
))) limits[1L] else limits[2L]
select_section <- function(members,sections,properties,geometry,combinations,limits) {
  for (number in seq_along(sections)) {
    section <- sections[[number]]
    acceptable <- TRUE
    for (member in members) {
      if (slenderness(properties[[member]],geometry[[member]],section) > limits[member] || any(vapply(
          combinations,
          function(r) utilization(r$forces[member],properties[[member]],geometry[[member]],section) > 1,
          logical(1)
      ))) {
        acceptable <- FALSE
        break
      }
    }
    if (acceptable) return(number)
  }
  length(sections)
}
