base_color <- function(material,point) {
  if (!is.null(material$checker) && sum(point %/% material$checker$size) %% 2 != 0) return(material$checker$color)
  material$color
}
phong <- function(material,normal,light,view,ndl,intensity,factor) {
  effective <- mul(intensity,factor)
  diffuse <- mul(mul(material$kd,ndl),effective)
  rv <- dot(sub(sc(normal,2*ndl),light),view)
  specular <- 0
  if (rv > 0) {
    power <- S
    for (unused in seq_len(material$n)) power <- mul(power,rv)
    specular <- mul(mul(material$ks,power),effective)
  }
  c(diffuse,specular)
}
reflected <- function(direction,normal) norm(sub(direction,sc(normal,2*dot(direction,normal))))
refraction <- function(material,direction,normal,front) {
  wr <- material$kr
  wt <- material$kt
  if (wt == 0) return(list(wr=wr,wt=wt,direction=NULL,internal=FALSE))
  eta <- if (front) (S*S) %/% material$ior else material$ior
  cosine <- -dot(direction,normal)
  discriminant <- S*S-(mul(eta,eta)*(S*S-cosine*cosine)) %/% S
  if (discriminant < 0) return(list(wr=wr+wt,wt=0,direction=NULL,internal=TRUE))
  transmitted <- norm(add(sc(direction,eta),sc(normal,mul(eta,cosine)-integer_sqrt(discriminant))))
  r0 <- ((material$ior-S)*S) %/% (material$ior+S)
  reflectance <- mul(r0,r0)
  x <- S-min(cosine,S)
  power <- S
  for (unused in seq_len(5L)) power <- mul(power,x)
  fresnel <- reflectance+mul(S-reflectance,power)
  transfer <- mul(material$kt,fresnel)
  list(wr=wr+transfer,wt=wt-transfer,direction=transmitted,internal=FALSE)
}
mix <- function(...) {
  weighted <- list(...)
  vapply(
      seq_len(3L),
      function(a) sum(vapply(weighted,function(item) (item$color[a]*item$weight) %/% S,numeric(1))),
      numeric(1)
  )
}
