taf_slots <- list(c('wind', 'single'), c('visibility', 'single'), c('weather', 'repeat'), c('cloud', 'repeat'))
elements <- c('wind', 'visibility', 'weather', 'cloud')
indicator <- function(text) text %in% c('BECMG', 'TEMPO', 'PROB30', 'PROB40') || grepl('^FM\\d{6}$', text, perl = TRUE)
split_taf <- function(groups, r, cal, error) {
    first <- length(groups) + 1L
    for (i in seq_along(groups)) if (indicator(groups[[i]]$text)) {
        first <- i
        break
    }
    changes <- list()
    i <- first
    while (i <= length(groups)) {
        g <- groups[[i]]
        kind <- g$text
        j <- i + 1L
        if (kind %in% c('PROB30', 'PROB40') && j <= length(groups) && groups[[j]]$text == 'TEMPO') {
            kind <- paste(kind, 'TEMPO')
            j <- j + 1L
        }
        finish <- j
        while (finish <= length(groups) && !indicator(groups[[finish]]$text)) finish <- finish + 1L
        change <- list(kind = kind)
        valid <- TRUE
        if (startsWith(kind, 'FM')) {
            d <- as.integer(substr(kind, 3L, 4L))
            h <- as.integer(substr(kind, 5L, 6L))
            n <- as.integer(substr(kind, 7L, 8L))
            t <- cal$day_time(d, h, n, r$issue_day)
            if (h > 23L || n > 59L || is.null(t) || t < r$start || t >= r$finish) {
                error(g, 'invalid period')
                valid <- FALSE
            } else {
                change$kind <- 'FM'
                change$time <- t
            }
        } else if (j >= finish || !grepl('^\\d{4}/\\d{4}$', groups[[j]]$text, perl = TRUE)) {
            g$text <- kind
            error(g, 'missing period')
            valid <- FALSE
        } else {
            p <- cal$period(groups[[j]]$text, r$issue_day)
            if (is.null(p) || p[1L] < r$start || p[2L] > r$finish) {
                error(groups[[j]], 'invalid period')
                valid <- FALSE
            } else {
                change$start <- p[1L]
                change$finish <- p[2L]
            }
            j <- j + 1L
        }
        if (valid) {
            change$groups <- slice(groups, j, finish - 1L)
            changes[[length(changes) + 1L]] <- change
        }
        i <- finish
    }
    list(base = slice(groups, 1L, first - 1L), changes = changes)
}

overlay <- function(base, change, replace = FALSE) {
    s <- list()
    for (k in elements) {
        if (k %in% names(change)) s[k] <- change[k] else if (!replace && k %in% names(base)) s[k] <- base[k]
    }
    s
}

expand_taf <- function(r, describe) {
    hours <- list()
    for (h in seq.int(r$start, r$finish - 60L, 60L)) {
        s <- r$base
        for (c in r$changes) {
            if (c$kind == 'FM' && c$time <= h) {
                s <- overlay(s, c$state, TRUE)
            } else if (c$kind == 'BECMG' && c$finish <= h) {
                s <- overlay(s, c$state)
            }
        }
        s <- describe(s)
        temporary <- list()
        for (c in r$changes) {
            if (!(c$kind %in% c('FM', 'BECMG')) && c$start <= h && h < c$finish) {
                temporary[[length(temporary) + 1L]] <- list(kind = c$kind, state = describe(overlay(s, c$state)))
            }
        }
        hours[[as.character(h)]] <- list(state = s, temporary = temporary)
    }
    hours
}
