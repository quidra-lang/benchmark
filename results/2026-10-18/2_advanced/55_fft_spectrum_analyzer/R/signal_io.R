read_signal <- function() {
  rows <- strsplit(readLines(file.path("input","signal.csv")),",",fixed=TRUE)
  list(
      fs=as.integer(rows[[1L]][1L]),
      x=vapply(rows[-1L],function(row) as.numeric(row[1L]),numeric(1)),
      y=vapply(rows[-1L],function(row) as.numeric(row[2L]),numeric(1))
  )
}
read_params <- function() {
  rows <- strsplit(readLines(file.path("input","params.txt"))," ",fixed=TRUE)
  raw <- setNames(lapply(rows,function(row) row[-1L]),vapply(rows,`[`,character(1),1L))
  result <- raw
  for (key in c(
      "main_length",
      "peak_count",
      "max_lag",
      "block_length",
      "pitch_range",
      "bandpass",
      "notch",
      "envelope_band",
      "zoom",
      "bands",
      "third_octave"
  )) result[[key]] <- as.integer(raw[[key]])
  for (key in c("peak_threshold_db","onset_factor","fir")) result[[key]] <- as.numeric(raw[[key]])
  result$fundamental <- list(as.numeric(raw$fundamental[1L]),as.integer(raw$fundamental[2L]))
  result$welch <- list(as.integer(raw$welch[1L]),raw$welch[2L])
  result$spectrogram <- list(
      as.integer(raw$spectrogram[1L]),
      as.integer(raw$spectrogram[2L]),
      as.integer(raw$spectrogram[3L]),
      raw$spectrogram[4L]
  )
  result
}
