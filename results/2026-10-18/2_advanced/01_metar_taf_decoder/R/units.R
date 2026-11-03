suppressPackageStartupMessages(library(gmp))
Z <- as.bigz
# Strip decimal padding before GMP's automatic string-base detection.
decimal_integer <- function(text) {
    negative <- startsWith(text, '-')
    digits <- sub('^-', '', text)
    digits <- sub('^0+', '', digits)
    if (!nzchar(digits)) return(Z(0L))
    Z(paste0(if (negative) '-' else '', digits))
}

floor_div <- function(a, b) {
    a <- Z(a)
    b <- Z(b)
    q <- abs(a) %/% b
    if (a >= 0L) return(q)
    if (abs(a) %% b == 0L) -q else -q - 1L
}

sine <- function(x) {
    s <- c(0L, 174L, 342L, 500L, 643L, 766L, 866L, 940L, 985L, 1000L)
    y <- x %% 360L
    if (y <= 90L) return(s[y %/% 10L + 1L])
    if (y <= 180L) return(s[(180L - y) %/% 10L + 1L])
    if (y <= 270L) return( -s[(y - 180L) %/% 10L + 1L])
    -s[(360L - y) %/% 10L + 1L]
}

cosine <- function(x) sine(x + 90L)
knots <- function(v) (v * 1944L + 500L) %/% 1000L
inhg <- function(v) (v * 2953L + 500L) %/% 1000L
hpa <- function(v) (v * 33864L + 50000L) %/% 100000L
miles <- function(v) {
    if (v$kind == 'miles') {
        list(n = Z(v$whole) * v$den + v$num, d = Z(v$den))
    } else list(n = Z(1000L) * v$value, d = Z(1609344L))
}

meters <- function(v) {
    if (v$kind != 'miles') return(v$value)
    f <- miles(v)
    (Z(1609344L) * f$n) %/% (Z(1000L) * f$d)
}

fraction <- function(n, d) {
    n <- Z(n)
    d <- Z(d)
    if (d == 0L) return('undefined')
    divisor <- gcd.bigz(abs(n), d)
    paste0(as.character(n %/% divisor), '/', as.character(d %/% divisor))
}

month_days <- function(y, m) {
    if (m == 2L) {
        if (y %% 400L == 0L || (y %% 4L == 0L && y %% 100L != 0L)) 29L else 28L
    } else if (m %in% c(4L, 6L, 9L, 11L)) 30L else 31L
}

calendar <- function(year, month) {
    days <- month_days(year, month)
    next_year <- year + if (month == 12L) 1L else 0L
    next_month <- if (month == 12L) 1L else month + 1L
    report_time <- function(text) {
        m <- captures('^(\\d{2})(\\d{2})(\\d{2})Z$', text)
        if (is.null(m)) return(NULL)
        d <- as.integer(m[1L])
        h <- as.integer(m[2L])
        n <- as.integer(m[3L])
        if (d < 1L || d > days || h > 23L || n > 59L) return(NULL)
        ((d - 1L) * 24L + h) * 60L + n
    }
    day_time <- function(d, h, n, issue) {
        following <- d < issue
        last <- if (following) month_days(next_year, next_month) else days
        if (d < 1L || d > last) return(NULL)
        (if (following) days * 1440L else 0L) + ((d - 1L) * 24L + h) * 60L + n
    }
    period <- function(text, issue, limit = NULL) {
        m <- captures('^(\\d{2})(\\d{2})/(\\d{2})(\\d{2})$', text)
        if (is.null(m)) return(NULL)
        v <- as.integer(m)
        if (v[2L] > 23L || v[4L] < 1L || v[4L] > 24L) return(NULL)
        a <- day_time(v[1L], v[2L], 0L, issue)
        b <- day_time(v[3L], v[4L], 0L, issue)
        if (is.null(a) || is.null(b) || a >= b || (!is.null(limit) && b > a + limit)) return(NULL)
        c(a, b)
    }
    stamp <- function(t) {
        y <- year
        m <- month
        if (t >= days * 1440L) {
            t <- t - days * 1440L
            y <- next_year
            m <- next_month
        }
        sprintf('%04d-%02d-%02dT%02d:%02dZ', y, m, t %/% 1440L + 1L, t %% 1440L %/% 60L, t %% 60L)
    }
    list(report_time = report_time, day_time = day_time, period = period, stamp = stamp)
}
