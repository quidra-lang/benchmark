read_materials <- function() lapply(strsplit(readLines(file.path("input","materials.txt"))," ",fixed=TRUE),function(words)
  list(
      code=words[1L],
      name=words[2L],
      k=as.numeric(words[3L]),
      rho=as.numeric(words[4L]),
      cp=as.numeric(words[5L])
  ))
heat_capacity <- function(material,dx,thickness) material$rho*material$cp*dx*dx*thickness
interior_conductance <- function(first,second,thickness) 2*first*second/(first+second)*thickness
fixed_conductance <- function(conductivity,thickness) 2*conductivity*thickness
convective_conductance <- function(
    conductivity,
    coefficient,
    dx,
    thickness
) 1/(1/(coefficient*dx*thickness)+1/(2*conductivity*thickness))
