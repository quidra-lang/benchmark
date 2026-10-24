pi_value <- 3.141592653589793
for (radius in c(3, 7, 12, 25, 41)) {
    area <- pi_value * radius * radius
    circumference <- 2 * pi_value * radius
    cat(sprintf("r=%d area=%.3f circumference=%.3f\n", radius, area, circumference))
}
