board <- c(
  "MMONKENBIR",
  "PMTIGERJPL",
  "TGREJEDUZI",
  "SPYUTEJDEC",
  "WKAPSIDLBN",
  "KUVNGSBPRO",
  "RIBSDACBAM",
  "YWVAUAPKAH",
  "KYCGTHHESR",
  "OCCALAOKKR"
)

find_word <- function(word) {
  directions <- list(c(0, 1), c(1, 1), c(1, 0), c(1, -1), c(0, -1), c(-1, -1), c(-1, 0), c(-1, 1))
  names <- c("E", "SE", "S", "SW", "W", "NW", "N", "NE")
  for (row in 0:9) {
    for (column in 0:9) {
      for (d in seq_along(directions)) {
        matched <- TRUE
        for (offset in 0:(nchar(word) - 1)) {
          r <- row + offset * directions[[d]][1]
          c_value <- column + offset * directions[[d]][2]
          if (r < 0 || r >= 10 || c_value < 0 || c_value >= 10 ||
            substr(board[r + 1], c_value + 1, c_value + 1) != substr(word, offset + 1, offset + 1)) {
            matched <- FALSE
            break
          }
        }
        if (matched) {
          return(sprintf("(%d, %d) %s", row, column, names[d]))
        }
      }
    }
  }
  "not found"
}

for (word in c("TIGER", "ZEBRA", "MONKEY", "PANDA", "KOALA", "RABBIT")) cat(sprintf("%s: %s\n", word, find_word(word)))
