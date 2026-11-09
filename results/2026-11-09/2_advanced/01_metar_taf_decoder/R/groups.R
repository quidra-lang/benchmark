descriptors <- c(MI = 'shallow', BC = 'patches', PR = 'partial', DR = 'low drifting', BL = 'blowing', SH = 'showers', TS = 'thunderstorm', FZ = 'freezing')
phenomena <- c(DZ = 'drizzle', RA = 'rain', SN = 'snow', SG = 'snow grains', IC = 'ice crystals', PL = 'ice pellets', GR = 'hail', GS = 'small hail', UP = 'unknown precipitation', BR = 'mist', FG = 'fog', FU = 'smoke', VA = 'volcanic ash', DU = 'dust', SA = 'sand', HZ = 'haze', PY = 'spray', PO = 'dust whirls', SQ = 'squalls', FC = 'funnel cloud', SS = 'sandstorm', DS = 'duststorm')
precipitation <- c('DZ', 'RA', 'SN', 'SG', 'IC', 'PL', 'GR', 'GS', 'UP')
amounts <- c(FEW = 'few', SCT = 'scattered', BKN = 'broken', OVC = 'overcast')
clear <- c(SKC = 'sky clear', CLR = 'clear below 12000 ft', NSC = 'no significant cloud')
captures <- function(pattern, text) {
    m <- regmatches(text, regexec(pattern, text, perl = TRUE))[[1L]]
    if (length(m) == 0L) NULL else unname(m[ - 1L])
}

recognize <- function(kind, text) {
    if (kind == 'modifier') {
        if (text %in% c('AUTO', 'COR')) return(list(code = text))
    } else if (kind == 'wind') {
        m <- captures('^(\\d{3}|VRB)(\\d{2,3})(?:G(\\d{2,3}))?(KT|MPS)$', text)
        if (!is.null(m)) return(list(direction = if (m[1L] == 'VRB') 'VRB' else as.integer(m[1L]), speed = as.integer(m[2L]), gust = if (m[3L] == '') NULL else as.integer(m[3L]), unit = m[4L]))
    } else if (kind == 'variation') {
        m <- captures('^(\\d{3})V(\\d{3})$', text)
        if (!is.null(m)) return(list(first = as.integer(m[1L]), last = as.integer(m[2L])))
    } else if (kind == 'visibility') {
        if (text == 'CAVOK') return(list(kind = 'cavok', value = 10000L, qualifier = 'P'))
        if (grepl('^\\d{4}$', text, perl = TRUE)) return(list(kind = 'meters', value = if (text == '9999') 10000L else as.integer(text), qualifier = if (text == '9999') 'P' else ''))
        m <- captures('^([MP]?)(\\d{1,2})SM$', text)
        if (!is.null(m)) return(list(kind = 'miles', whole = as.integer(m[2L]), num = 0L, den = 1L, qualifier = m[1L], fraction = FALSE, mixed = FALSE))
        m <- captures('^([MP]?)(\\d)/(\\d{1,2})SM$', text)
        if (!is.null(m)) return(list(kind = 'miles', whole = 0L, num = as.integer(m[2L]), den = as.integer(m[3L]), qualifier = m[1L], fraction = TRUE, mixed = FALSE))
        m <- captures('^(\\d) (\\d)/(\\d{1,2})SM$', text)
        if (!is.null(m)) return(list(kind = 'miles', whole = as.integer(m[1L]), num = as.integer(m[2L]), den = as.integer(m[3L]), qualifier = '', fraction = TRUE, mixed = TRUE))
    } else if (kind == 'rvr') {
        m <- captures('^R(\\d{2}[LCR]?)/([MP]?)(\\d{4})(?:V([MP]?)(\\d{4}))?(FT)?([UDN])?$', text)
        if (!is.null(m)) {
            readings <- list(list(q = m[2L], value = as.integer(m[3L])))
            if (m[5L] != '') readings[[2L]] <- list(q = m[4L], value = as.integer(m[5L]))
            return(list(runway = m[1L], readings = readings, unit = if (m[6L] == 'FT') 'ft' else 'm', trend = m[7L]))
        }
    } else if (kind == 'weather') {
        if (text == 'NSW') return(list(raw = text, nsw = TRUE, descriptor = NULL, phenomena = character()))
        pattern <- paste0('^(-|\\+|VC)?((?:', paste(c(names(descriptors), names(phenomena)), collapse = '|'), ')+)$')
        m <- captures(pattern, text)
        if (!is.null(m)) {
            codes <- substring(m[2L], seq.int(1L, nchar(m[2L]), 2L), seq.int(2L, nchar(m[2L]), 2L))
            desc <- NULL
            if (codes[1L] %in% names(descriptors)) {
                desc <- codes[1L]
                codes <- codes[ - 1L]
            }
            return(list(raw = text, nsw = FALSE, intensity = m[1L], descriptor = desc, phenomena = codes))
        }
    } else if (kind == 'cloud') {
        m <- captures('^(FEW|SCT|BKN|OVC)(\\d{3})(CB|TCU)?$', text)
        if (!is.null(m)) return(list(amount = m[1L], height = as.integer(m[2L]) * 100L, extra = m[3L], layer = TRUE))
        m <- captures('^VV(\\d{3})$', text)
        if (!is.null(m)) return(list(amount = 'VV', height = as.integer(m[1L]) * 100L, extra = '', layer = FALSE))
        if (text %in% names(clear)) return(list(amount = text, height = NULL, extra = '', layer = FALSE))
    } else if (kind == 'temperature') {
        m <- captures('^(M?)(\\d{2})/(M?)(\\d{2})$', text)
        if (!is.null(m)) return(list(temperature = as.integer(m[2L]) * (if (m[1L] == 'M') - 1L else 1L), dew = as.integer(m[4L]) * (if (m[3L] == 'M') - 1L else 1L)))
    } else if (kind == 'pressure') {
        m <- captures('^([AQ])(\\d{4})$', text)
        if (!is.null(m)) return(list(unit = m[1L], value = as.integer(m[2L])))
    } else if (kind == 'nosig'  && text == 'NOSIG') return(list(code = text))
    NULL
}

valid_group <- function(kind, v, s, station, change) {
    if (kind == 'wind') {
        d <- v$direction
        w <- v$speed
        g <- v$gust
        if (identical(d, 'VRB')) {
            if (w < 1L) return(FALSE)
        } else if (d > 360L || d %% 10L != 0L || ((d == 0L) != (w == 0L)) || (d == 0L && !is.null(g))) return(FALSE)
        return(is.null(g) || g > w)
    }
    if (kind == 'variation') {
        a <- v$first
        b <- v$last
        w <- s$wind
        return(a >= 10L && a <= 360L && b >= 10L && b <= 360L && a %% 10L == 0L && b %% 10L == 0L && a != b && !is.null(w) && !identical(w$direction, 'VRB') && w$direction != 0L)
    }
    if (kind == 'visibility') {
        if (v$kind != 'miles') return(TRUE)
        if (!v$fraction) return(v$whole >= 1L)
        return(v$den %in% c(2L, 4L, 8L, 16L) && v$num >= 1L && v$num < v$den && (!v$mixed || v$whole >= 1L))
    }
    if (kind == 'rvr') return(v$runway %in% vapply(station$runways, `[[`, '', 'name') && (length(v$readings) == 1L || v$readings[[1L]]$value < v$readings[[2L]]$value))
    if (kind == 'weather') {
        p <- s$weather
        if (length(p) >= 3L || any(vapply(p, function(w) w$nsw, FALSE))) return(FALSE)
        if (v$nsw) return(change && length(p) == 0L)
        p <- v$phenomena
        if (!all(p %in% names(phenomena)) || anyDuplicated(p) != 0L) return(FALSE)
        if (length(p) == 0L && !any(v$descriptor %in% c('TS', 'SH'))) return(FALSE)
        if (v$intensity %in% c('-', '+') && !any(p %in% precipitation)) return(FALSE)
        return(length(p) < 2L || all(p %in% precipitation))
    }
    if (kind == 'cloud') {
        p <- s$cloud
        return(length(p) == 0L || (v$layer && p[[length(p)]]$layer && v$height > p[[length(p)]]$height))
    }
    if (kind == 'temperature') return(v$dew <= v$temperature)
    if (kind == 'pressure') return(v$value >= (if (v$unit == 'A') 2500L else 850L) && v$value <= (if (v$unit == 'A') 3150L else 1070L))
    TRUE
}

record_group <- function(s, kind, v, repeatable) {
    if (kind == 'wind'  && v$unit == 'MPS') {
        v$speed <- knots(v$speed)
        if (!is.null(v$gust)) v$gust <- knots(v$gust)
        v$unit <- 'KT'
    }
    if (kind == 'pressure') {
        v$inhg <- if (v$unit == 'A') v$value else inhg(v$value)
        v$hpa <- if (v$unit == 'Q') v$value else hpa(v$value)
    }
    if (repeatable) s[[kind]] <- c(s[[kind]], list(v)) else s[[kind]] <- v
    s
}
