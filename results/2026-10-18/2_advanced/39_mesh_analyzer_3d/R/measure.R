WINDING_PI <- 3.141592653589793
subtract <- function(a, b) a - b
cross <- function(a, b) c(
    a[[2L]] * b[[3L]] - a[[3L]] * b[[2L]],
    a[[3L]] * b[[1L]] - a[[1L]] * b[[3L]],
    a[[1L]] * b[[2L]] - a[[2L]] * b[[1L]]
)
dot <- function(a, b) a[[1L]] * b[[1L]] + a[[2L]] * b[[2L]] + a[[3L]] * b[[3L]]
normal <- function(face, points) {
  a <- points[face$vertices[[1L]], ]
  b <- points[face$vertices[[2L]], ]
  c <- points[face$vertices[[3L]], ]
  cross(b - a, c - a)
}
determinant <- function(face, points) dot(
    points[face$vertices[[1L]], ],
    cross(points[face$vertices[[2L]], ], points[face$vertices[[3L]], ])
)
area <- function(faces, points) {
  total <- 0
  for (face in faces) {
    n <- normal(face, points)
    total <- total + sqrt(dot(n, n))
  }
  total / 2
}
triangle_angle <- function(face, points) {
  a <- points[face$vertices[[1L]], ]
  b <- points[face$vertices[[2L]], ]
  c <- points[face$vertices[[3L]], ]
  smallest <- min(dot(b - a, c - a), dot(c - b, a - b), dot(a - c, b - c))
  if (smallest < 0) "obtuse" else if (smallest == 0) "right" else "acute"
}
edge_length_squared <- function(edge, points) {
  difference <- points[edge[[1L]], ] - points[edge[[2L]], ]
  dot(difference, difference)
}
winding_number <- function(face_indices, faces, points, sample) {
  total <- 0
  for (index in face_indices) {
    face <- faces[[index]]
    a <- points[face$vertices[[1L]], ] - sample
    b <- points[face$vertices[[2L]], ] - sample
    c <- points[face$vertices[[3L]], ] - sample
    la <- sqrt(dot(a, a))
    lb <- sqrt(dot(b, b))
    lc <- sqrt(dot(c, c))
    numerator <- dot(a, cross(b, c))
    denominator <- la * lb * lc + dot(a, b) * lc + dot(b, c) * la + dot(c, a) * lb
    total <- total + 2 * atan2(numerator, denominator)
  }
  as.integer(round(total / (4 * WINDING_PI)))
}
volume6 <- function(face_indices, faces, points) {
  total <- 0
  for (index in face_indices) total <- total + determinant(faces[[index]], points)
  total
}
format_fraction <- function(numerator, denominator = 1) {
  if (denominator < 0) {
    numerator <- -numerator
    denominator <- -denominator
  }
  a <- abs(numerator)
  b <- denominator
  while (b != 0) {
    remainder <- a %% b
    a <- b
    b <- remainder
  }
  numerator <- numerator %/% a
  denominator <- denominator %/% a
  if (denominator == 1) sprintf("%.0f", numerator) else sprintf("%.0f/%.0f", numerator, denominator)
}
centroid <- function(face_indices, faces, points, six_volume) {
  vapply(seq_len(3L), function(axis) {
    numerator <- 0
    for (index in face_indices) {
      face <- faces[[index]]
      numerator <- numerator + determinant(face, points) * sum(points[face$vertices, axis])
    }
    format_fraction(numerator, 4 * six_volume)
  }, "")
}
format_real <- function(value) sprintf("%.3f", if (value == 0) 0 else value)
bbox <- function(vertices, points) c(
    apply(points[vertices, , drop = FALSE], 2L, min),
    apply(points[vertices, , drop = FALSE], 2L, max)
)
