NOTE_TABLE <- c(26163, 27718, 29366, 31113, 32963, 34923, 36999, 39200, 41530, 44000, 46616, 49388)
SINE_TABLE <- c(0L, 24L, 49L, 74L, 97L, 120L, 141L, 161L, 180L, 197L, 212L, 224L, 235L, 244L, 250L, 253L,
                255L, 253L, 250L, 244L, 235L, 224L, 212L, 197L, 180L, 161L, 141L, 120L, 97L, 74L, 49L, 24L)
clamp <- function(value, low, high) min(max(value, low), high)
note_frequency <- function(note) {
  octave <- note %/% 12L
  pitch <- note %% 12L + 1L
  if (octave >= 4L) NOTE_TABLE[[pitch]] * (2 ^ (octave - 4L)) else NOTE_TABLE[[pitch]] %/% (2 ^ (4L - octave))
}
transpose_frequency <- function(
    frequency,
    semitones
) ((frequency * NOTE_TABLE[[semitones %% 12L + 1L]]) %/% NOTE_TABLE[[1L]]) * (2 ^ (semitones %/% 12L))
oscillation <- function(position, depth, divisor) {
  value <- (SINE_TABLE[[position %% 32L + 1L]] * depth) %/% divisor
  if (position < 32L) value else -value
}
envelope_value <- function(instrument, age, released, release_age, release_level) {
  if (released) {
    elapsed <- age - release_age
    return(if (elapsed < instrument$release) (release_level * (instrument$release - 1L - elapsed)) %/% instrument$release else 0L)
  }
  if (age < instrument$attack) return((15L * (age + 1L)) %/% instrument$attack)
  if (age < instrument$attack + instrument$decay) return(15L - ((15L - instrument$sustain) * (age - instrument$attack + 1L)) %/% instrument$decay)
  instrument$sustain
}
wave_value <- function(instrument, mode, phase, register) {
  if (instrument$wave == "PULSE") return(if (phase %/% 8192L < c(1L, 2L, 4L, 6L)[[mode + 1L]]) 15L else 0L)
  if (instrument$wave == "TRIANGLE") {
    step <- phase %/% 2048L
    return(if (step < 16L) 15L - step else step - 16L)
  }
  if (instrument$wave == "SAW") return(phase %/% 4096L)
  if (instrument$wave == "TABLE") return(instrument$table[[phase %/% 2048L + 1L]])
  if (register %% 2L == 0L) 15L else 0L
}
clock_register <- function(register, mode) {
  tap <- if (mode == 0L) 1L else 6L
  feedback <- bitwAnd(bitwXor(as.integer(register), bitwShiftR(as.integer(register), tap)), 1L)
  register %/% 2L + feedback * 16384L
}
