metar_slots <- list(c('modifier', 'single'), c('wind', 'single'), c('variation', 'single'), c('visibility', 'single'), c('rvr', 'repeat'), c('weather', 'repeat'), c('cloud', 'repeat'), c('temperature', 'single'), c('pressure', 'single'), c('nosig', 'single'))
metar_slot_value <- function(kind, text) recognize(kind, text)
trend_time <- function(g) {
    m <- captures('^(FM|TL|AT)(\\d{2})(\\d{2})$', g$text)
    if (is.null(m)) NULL else list(kind = m[1L], hour = as.integer(m[2L]), minute = as.integer(m[3L]), group = g)
}

slice <- function(a, first, last) if (first > last) list() else a[seq.int(first, last)]
split_metar <- function(groups, error) {
    rmk <- length(groups) + 1L
    for (i in seq_along(groups)) if (groups[[i]]$text == 'RMK') {
        rmk <- i
        break
    }
    first <- rmk
    for (i in seq_len(rmk - 1L)) if (groups[[i]]$text %in% c('BECMG', 'TEMPO')) {
        first <- i
        break
    }
    trends <- list()
    i <- first
    while (i < rmk) {
        finish <- i + 1L
        while (finish < rmk && !(groups[[finish]]$text %in% c('BECMG', 'TEMPO'))) finish <- finish + 1L
        j <- i + 1L
        times <- list()
        t <- if (j < finish) trend_time(groups[[j]]) else NULL
        if (!is.null(t)) {
            times <- list(t)
            j <- j + 1L
            u <- if (j < finish) trend_time(groups[[j]]) else NULL
            if (t$kind == 'FM'  && !is.null(u) && u$kind == 'TL') {
                times[[2L]] <- u
                j <- j + 1L
            }
        }
        bad <- NULL
        for (t in times) if (t$hour > 23L || t$minute > 59L) {
            bad <- t
            break
        }
        if (!is.null(bad)) error(bad$group, 'invalid period') else trends[[length(trends) + 1L]] <- list(kind = groups[[i]]$text, times = times, groups = slice(groups, j, finish - 1L))
        i <- finish
    }
    sea <- list()
    precise <- list()
    for (g in slice(groups, rmk + 1L, length(groups))) {
        m <- captures('^SLP(\\d{3})$', g$text)
        if (!is.null(m)) {
            p <- as.integer(m[1L])
            sea[[length(sea) + 1L]] <- (if (p >= 500L) 9000L else 10000L) + p
        } else {
            m <- captures('^T([01])(\\d{3})([01])(\\d{3})$', g$text)
            if (!is.null(m)) precise[[length(precise) + 1L]] <- c(as.integer(m[2L]) * (if (m[1L] == '1') - 1L else 1L), as.integer(m[4L]) * (if (m[3L] == '1') - 1L else 1L))
        }
    }
    list(main = slice(groups, 1L, first - 1L), trends = trends, sea = sea, precise = precise)
}
