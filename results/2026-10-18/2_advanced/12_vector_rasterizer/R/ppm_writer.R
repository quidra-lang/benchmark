write_ppm <- function(image, width, height) {
  lines <- c("P3", paste(width, height), "255")
  for (y in seq_len(height) - 1L) lines <- c(lines, paste(as.vector(t(image[y * width + seq_len(width), , drop = FALSE])), collapse = " "))
  writeLines(lines, "output/image.ppm", useBytes = TRUE)
}
write_preview <- function(image, width, height) {
  ramp <- strsplit("@%#*+=-:,.", "", fixed = TRUE)[[1L]]
  lines <- character()
  for (top in seq.int(0L, height - 1L, 4L)) {
    text <- ""
    for (left in seq.int(0L, width - 1L, 2L)) {
      total <- 0L
      for (y in top:(top + 3L)) for (x in left:(left + 1L)) total <- total + sum(image[y * width + x + 1L, ] * c(299L, 587L, 114L))
      brightness <- total %/% 8000L
      text <- paste0(text, ramp[(brightness * 10L) %/% 256L + 1L])
    }
    lines <- c(lines, text)
  }
  writeLines(lines, "output/preview.txt", useBytes = TRUE)
}
