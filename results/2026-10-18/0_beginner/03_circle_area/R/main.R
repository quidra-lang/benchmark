pi_value <- 3.141592653589793
for (radius in c(3, 7, 12, 25, 41)) {
    area <- pi_value * radius * radius
    circumference <- 2 * pi_value * radius
    area <- floor(area * 1000 + 0.5) / 1000
    circumference <- floor(circumference * 1000 + 0.5) / 1000
    cat(sprintf("r=%d area=%.3f circumference=%.3f\n", radius, area, circumference))
}
