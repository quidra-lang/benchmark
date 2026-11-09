gcd <- function(a, b) {
    while (b != 0) {
        remainder <- a %% b
        a <- b
        b <- remainder
    }
    a
}
fraction_text <- function(a, b) {
    divisor <- gcd(abs(a), b)
    paste0(sprintf("%.0f", a %/% divisor), "/", sprintf("%.0f", b %/% divisor))
}
root_text <- function(value) sprintf("%.3f", sqrt(value))
ari_text <- function(a, b) {
    value <- sprintf("%.4f", a / b)
    if (value == "-0.0000") value <- "0.0000"
    paste(fraction_text(a, b), value)
}
framed <- function(rows, width) {
    border <- paste0("+", strrep("-", width), "+")
    c(border, paste0("|", rows, "|"), border)
}
write_lines <- function(name, lines) {
    dir.create("output", showWarnings = FALSE)
    writeLines(lines, file.path("output", name), useBytes = TRUE)
}
