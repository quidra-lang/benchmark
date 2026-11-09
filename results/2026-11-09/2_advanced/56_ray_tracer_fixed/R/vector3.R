add <- function(u,v) u+v
sub <- function(u,v) u-v
neg <- function(u) -u
dot <- function(u,v) sum(u*v) %/% S
sc <- function(u,k) (u*k) %/% S
vector_length <- function(u) integer_sqrt(sum(u*u))
norm <- function(u) (u*S) %/% vector_length(u)
