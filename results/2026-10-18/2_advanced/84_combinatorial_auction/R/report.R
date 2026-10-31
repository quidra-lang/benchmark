gcd_integer <- function(a, b) {
    a <- abs(a)
    b <- abs(b)
    while (b != 0) {
        remainder <- a %% b
        a <- b
        b <- remainder
    }
    a
}
rat <- function(n, d=1) {
    if (d < 0) {
        n <- -n
        d <- -d
    }
    divisor <- gcd_integer(n, d)
    c(n/divisor, d/divisor)
}
radd <- function(a, b) {
    divisor <- gcd_integer(a[2], b[2])
    rat(a[1]*(b[2]/divisor)+b[1]*(a[2]/divisor), a[2]*(b[2]/divisor))
}
rsub <- function(a, b) radd(a, c(-b[1], b[2]))
rmul <- function(a, b) {
    left <- gcd_integer(a[1], b[2])
    right <- gcd_integer(b[1], a[2])
    rat((a[1]/left)*(b[1]/right), (a[2]/right)*(b[2]/left))
}
rdiv <- function(a, b) rmul(a, rat(b[2], b[1]))
rcmp <- function(a, b) sign(a[1]*b[2]-b[1]*a[2])
integer_text <- function(value) sprintf("%.0f", value)
fraction <- function(value) {
    if (length(value) == 1L) return(integer_text(value))
    if (value[2] == 1) integer_text(value[1]) else paste0(integer_text(value[1]), "/", integer_text(value[2]))
}
bundle_text <- function(mask, items) {
    names <- items[vapply(seq_along(items), function(i) has_item(mask, i), FALSE)]
    if (length(names)) paste(names, collapse="+") else "-"
}
number_text <- function(values) if (length(values)) paste(integer_text(sort(values)), collapse="+") else "-"
write_reports <- function(reports) {
    dir.create("output", showWarnings=FALSE)
    for (name in names(reports)) writeLines(reports[[name]], file.path("output", name), useBytes=TRUE)
}
