script_arg <- grep('^--file=', commandArgs(), value = TRUE)
script_dir <- if (length(script_arg)) dirname(sub('^--file=', '', script_arg[1L])) else '.'
for (module in c('units', 'groups', 'metar', 'taf', 'verification')) source(file.path(script_dir, paste0(module, '.R')))
`%or%` <- function(a, b) if (is.null(a)) b else a
errors <- list()
error_at <- function(number, position, text) {
    errors[[length(errors) + 1L]] <<- list(number = number, position = position, text = text)
}

group_error <- function(r, g, reason) error_at(r$number, g$position, paste0(reason, ' "', g$text, '"'))
join_groups <- function(words, start) {
    groups <- list()
    i <- start
    while (i <= length(words)) {
        position <- i
        text <- words[i]
        if (grepl('^\\d$', text, perl = TRUE) && i < length(words) && grepl('^\\d/\\d{1,2}SM$', words[i + 1L], perl = TRUE)) {
            text <- paste(text, words[i + 1L])
            i <- i + 1L
        }
        groups[[length(groups) + 1L]] <- list(position = position, text = text)
        i <- i + 1L
    }
    groups
}

parse_header <- function(words, number, stations, cal) {
    kind <- words[1L]
    r <- list(number = number, kind = kind)
    i <- 2L
    if (!(kind %in% c('METAR', 'SPECI', 'TAF'))) {
        error_at(number, 1L, paste0('rejected report, invalid type "', kind, '"'))
        return(NULL)
    }
    if (kind == 'TAF'  && i <= length(words) && words[i] %in% c('AMD', 'COR')) {
        r$modifier <- words[i]
        i <- i + 1L
    }
    fields <- if (kind == 'TAF') c('station', 'time', 'validity') else c('station', 'time')
    for (field in fields) {
        if (i > length(words)) {
            error_at(number, length(words) + 1L, paste('rejected report, missing', field))
            return(NULL)
        }
        text <- words[i]
        value <- switch(field,
            station = stations[[text]],
            time = cal$report_time(text),
            validity = cal$period(text, r$issue_day, 1800L))
        if (is.null(value)) {
            error_at(number, i, paste0('rejected report, invalid ', field, ' "', text, '"'))
            return(NULL)
        }
        if (field == 'validity') {
            r$start <- value[1L]
            r$finish <- value[2L]
        } else r[[field]] <- value
        if (field == 'time') r$issue_day <- value %/% 1440L + 1L
        i <- i + 1L
    }
    r$groups <- join_groups(words, i)
    r
}

match_section <- function(groups, slots, r, change = FALSE) {
    s <- list()
    current <- 1L
    recognize_slot <- if (identical(slots, metar_slots)) metar_slot_value else recognize
    for (g in groups) {
        found <- NULL
        value <- NULL
        if (current <= length(slots)) for (i in seq.int(current, length(slots))) {
            value <- recognize_slot(slots[[i]][1L], g$text)
            if (!is.null(value)) {
                found <- i
                break
            }
        }
        if (is.null(found)) {
            earlier <- FALSE
            for (i in seq_len(current - 1L)) if (!is.null(recognize_slot(slots[[i]][1L], g$text))) {
                earlier <- TRUE
                break
            }
            group_error(r, g, if (earlier) 'out of order group' else 'unknown group')
            next
        }
        kind <- slots[[found]][1L]
        repeatable <- slots[[found]][2L] == 'repeat'
        if (!valid_group(kind, value, s, r$station, change)) {
            group_error(r, g, 'invalid group')
            next
        }
        s <- record_group(s, kind, value, repeatable)
        current <- if (repeatable) found else found + 1L
        if (kind == 'visibility'  && value$kind == 'cavok') {
            s$weather <- list()
            s$cloud <- list()
            current <- which(vapply(slots, function(slot) slot[1L] == 'cloud', FALSE)) + 1L
        }
    }
    s
}

describe_state <- function(s) {
    ceiling <- NULL
    for (c in s$cloud) if (c$amount %in% c('BKN', 'OVC', 'VV')) {
        ceiling <- c$height
        break
    }
    visibility <- if (is.null(s$visibility)) NULL else miles(s$visibility)
    less <- function(n) !is.null(visibility) && visibility$n < Z(n) * visibility$d
    at_most <- function(n) !is.null(visibility) && visibility$n <= Z(n) * visibility$d
    category <- 'VFR'
    if ((!is.null(ceiling) && ceiling < 500L) || less(1L)) category <- 'LIFR' else if ((!is.null(ceiling) && ceiling < 1000L) || less(3L)) category <- 'IFR' else if ((!is.null(ceiling) && ceiling <= 3000L) || at_most(5L)) category <- 'MVFR'
    s$ceiling <- ceiling
    s$category <- category
    s
}

components <- function(speed, direction, heading) {
    c(floor_div(speed * cosine(direction - heading), 1000L), floor_div(speed * sine(direction - heading), 1000L))
}

derive_observation <- function(r, settings) {
    s <- r$state
    p <- s$pressure
    t <- s$temperature
    if (!is.null(p)) {
        a <- r$station$elevation + (2992L - p$inhg) * 10L
        r$pressure_altitude <- a
        if (!is.null(t)) r$density_altitude <- a + floor_div(Z(120L) * (1000L * t$temperature - 15000L + Z(2L) * a), 1000L)
    }
    w <- s$wind
    if (is.null(w) || identical(w$direction, 'VRB') || w$direction == 0L) return(r)
    r$components <- list()
    r$usable <- character()
    preferred <- NULL
    for (runway in r$station$runways) {
        mean <- components(w$speed, w$direction, runway$heading)
        gust <- if (is.null(w$gust)) NULL else components(w$gust, w$direction, runway$heading)
        deciding <- gust %or% mean
        r$components[[length(r$components) + 1L]] <- list(name = runway$name, mean = mean, gust = gust)
        if (abs(deciding[2L]) <= settings$CROSSWIND_LIMIT && - deciding[1L] <= settings$TAILWIND_LIMIT) {
            r$usable <- c(r$usable, runway$name)
            if (is.null(preferred) || mean[1L] > preferred$head) preferred <- list(name = runway$name, head = mean[1L])
        }
    }
    r$preferred <- if (is.null(preferred)) 'none' else preferred$name
    r
}

wind_changes <- function(a, b, angle) {
    if (is.null(a) || is.null(b)) return(character())
    reasons <- character()
    if (!identical(a$direction, 'VRB') && a$direction != 0L && !identical(b$direction, 'VRB') && b$direction != 0L) {
        d <- abs(a$direction - b$direction) %% 360L
        if (max(a$speed, b$speed) >= 10L && min(d, 360L - d) >= angle) reasons <- c(reasons, 'wind shift')
    }
    if (abs(a$speed - b$speed) >= 10L) reasons <- c(reasons, 'wind speed')
    reasons
}

weather_present <- function(s, kind) {
    any(vapply(s$weather, function(w) {
        if (kind == 'TS') identical(w$descriptor, 'TS') else identical(w$descriptor, 'FZ') && any(w$phenomena %in% c('DZ', 'RA'))
    }, FALSE))
}

speci_check <- function(previous, r) {
    if (is.null(previous)) return('no previous report')
    a <- previous$state
    b <- r$state
    reasons <- character()
    if (a$category != b$category) reasons <- c(reasons, paste('category', a$category, 'to', b$category))
    reasons <- c(reasons, wind_changes(a$wind, b$wind, 45L))
    for (kind in c('TS', 'FZ')) {
        before <- weather_present(a, kind)
        after <- weather_present(b, kind)
        label <- if (kind == 'TS') 'thunderstorm' else 'freezing precipitation'
        if (before != after) reasons <- c(reasons, paste(label, if (after) 'began' else 'ended'))
    }
    if (length(reasons)) paste(reasons, collapse = ', ') else 'no criteria met'
}

wind_phrase <- function(w) {
    if (identical(w$direction, 0L)) return('calm')
    text <- if (identical(w$direction, 'VRB')) paste('variable at', w$speed, 'KT') else sprintf('%03d degrees at %d KT', w$direction, w$speed)
    if (!is.null(w$gust)) text <- paste(text, 'gusting', w$gust, 'KT')
    text
}

visibility_number <- function(v) {
    if (!v$fraction) return(as.character(v$whole))
    paste0(if (v$whole != 0L) paste0(v$whole, ' ') else '', v$num, '/', v$den)
}

visibility_phrase <- function(v) {
    if (v$kind == 'cavok') return('10 km or more (CAVOK)')
    if (v$kind == 'meters') return(if (v$value == 10000L) '10 km or more' else paste(v$value, 'm'))
    prefix <- if (v$qualifier == 'M') 'less than ' else if (v$qualifier == 'P') 'more than ' else ''
    paste0(prefix, visibility_number(v), ' SM')
}

weather_phrase <- function(w) {
    if (w$nsw) return('no significant weather')
    intensity <- switch(w$intensity, '-' = 'light', '+' = 'heavy', VC = 'nearby', '')
    descriptor <- if (is.null(w$descriptor)) '' else unname(descriptors[w$descriptor])
    phenomenon <- paste(phenomena[w$phenomena], collapse = ' and ')
    parts <- c(intensity, descriptor, phenomenon)
    paste(parts[nzchar(parts)], collapse = ' ')
}

cloud_phrase <- function(c) {
    if (c$amount %in% names(clear)) return(unname(clear[c$amount]))
    if (c$amount == 'VV') return(paste('vertical visibility', c$height, 'ft'))
    extra <- switch(c$extra, CB = ' cumulonimbus', TCU = ' towering cumulus', '')
    paste0(amounts[c$amount], ' at ', c$height, ' ft', extra)
}

summary_state <- function(s) {
    parts <- character()
    if (!is.null(s$wind)) parts <- c(parts, paste('wind', wind_phrase(s$wind)))
    if (!is.null(s$visibility)) parts <- c(parts, paste('visibility', visibility_phrase(s$visibility)))
    if (length(s$weather)) parts <- c(parts, paste('weather', paste(vapply(s$weather, weather_phrase, ''), collapse = ', ')))
    if (length(s$cloud)) parts <- c(parts, paste('cloud', paste(vapply(s$cloud, cloud_phrase, ''), collapse = ', ')))
    if (length(parts)) paste(parts, collapse = '; ') else 'no conditions'
}

wind_code <- function(w) {
    if (identical(w$direction, 0L)) return('00000KT')
    direction <- if (identical(w$direction, 'VRB')) 'VRB' else sprintf('%03d', w$direction)
    paste0(direction, sprintf('%02d', w$speed), if (is.null(w$gust)) '' else sprintf('G%02d', w$gust), 'KT')
}

visibility_code <- function(v) {
    if (v$kind == 'cavok') return('CAVOK')
    if (v$kind == 'meters') return(sprintf('%04d', if (v$value == 10000L) 9999L else v$value))
    paste0(v$qualifier, visibility_number(v), 'SM')
}

state_tokens <- function(s) {
    words <- character()
    if (!is.null(s$wind)) words <- c(words, wind_code(s$wind))
    if (!is.null(s$visibility)) words <- c(words, visibility_code(s$visibility))
    for (w in s$weather) if (!w$nsw) words <- c(words, w$raw)
    for (c in s$cloud) {
        code <- if (c$amount %in% names(clear)) c$amount else paste0(c$amount, sprintf('%03d', c$height %/% 100L), c$extra)
        words <- c(words, code)
    }
    paste(c(words, s$category), collapse = ' ')
}

tenths <- function(v) paste0(if (v < 0L) '-' else '', abs(v) %/% 10L, '.', abs(v) %% 10L)
inhg_text <- function(v) sprintf('%d.%02d', v %/% 100L, v %% 100L)
component_phrase <- function(v) {
    h <- v[1L]
    c <- v[2L]
    paste0(if (h < 0L) paste('tailwind', as.character( -h)) else paste('headwind', as.character(h)),
    ' KT, crosswind ', as.character(abs(c)), ' KT', if (c > 0L) ' from right' else if (c < 0L) ' from left' else '')
}

rvr_phrase <- function(v) {
    readings <- vapply(v$readings, function(r) paste0(if (r$q == 'M') 'less than ' else if (r$q == 'P') 'more than ' else '', r$value), '')
    text <- if (length(readings) == 1L) readings[1L] else paste('between', readings[1L], 'and', readings[2L])
    trend <- if (v$trend == '') '' else paste0(', ', switch(v$trend, U = 'rising', D = 'falling', N = 'no change'))
    paste0('runway ', v$runway, ' ', text, ' ', v$unit, trend)
}

decoded <- function(r, cal) {
    lines <- paste0('REPORT ', r$number, ': ', r$kind, ' ', r$station$code, ' (', r$station$name, ')')
    details <- character()
    add <- function(text) details <<- c(details, text)
    if (r$kind == 'TAF') {
        add(paste('issued:', cal$stamp(r$time)))
        if (!is.null(r$modifier)) add(paste('modifier:', if (r$modifier == 'AMD') 'amended' else 'corrected'))
        add(paste('valid:', cal$stamp(r$start), 'to', cal$stamp(r$finish)))
        add(paste('base:', summary_state(r$base)))
        for (c in r$changes) {
            period <- if (c$kind == 'FM') cal$stamp(c$time) else paste(cal$stamp(c$start), 'to', cal$stamp(c$finish))
            add(paste0(c$kind, ' ', period, ': ', summary_state(c$state)))
        }
    } else {
        s <- r$state
        add(paste('time:', cal$stamp(r$time)))
        if (!is.null(s$modifier)) add(paste('modifier:', if (s$modifier$code == 'AUTO') 'automated' else 'corrected'))
        wind <- if (is.null(s$wind)) 'not reported' else wind_phrase(s$wind)
        if (!is.null(s$variation)) wind <- paste0(wind, sprintf(', varying between %03d and %03d degrees', s$variation$first, s$variation$last))
        add(paste('wind:', wind))
        add(paste('visibility:', if (is.null(s$visibility)) 'not reported' else visibility_phrase(s$visibility)))
        for (v in s$rvr) add(paste('runway visual range:', rvr_phrase(v)))
        for (w in s$weather) add(paste('weather:', weather_phrase(w)))
        if (!is.null(s$visibility) && s$visibility$kind == 'cavok') {
            add('cloud: no significant cloud')
        } else if (is.null(s$cloud)) {
            add('cloud: not reported')
        } else {
            for (c in s$cloud) add(paste('cloud:', cloud_phrase(c)))
        }
        t <- s$temperature
        if (is.null(t)) add('temperature: not reported') else add(paste0('temperature: ', t$temperature, ' C, dew point ', t$dew, ' C, spread ', t$temperature - t$dew, ' C'))
        p <- s$pressure
        if (is.null(p)) {
            add('altimeter: not reported')
        } else if (p$unit == 'A') {
            add(paste0('altimeter: ', inhg_text(p$inhg), ' inHg (', p$hpa, ' hPa)'))
        } else {
            add(paste0('altimeter: ', p$hpa, ' hPa (', inhg_text(p$inhg), ' inHg)'))
        }
        if (!is.null(s$nosig)) add('trend: no significant change')
        for (trend in r$trends) {
            text <- if (trend$kind == 'BECMG') 'becoming' else 'temporarily'
            for (t in trend$times) text <- paste0(text, ' ', switch(t$kind, FM = 'from', TL = 'until', AT = 'at'), sprintf(' %02d:%02dZ', t$hour, t$minute))
            add(paste0('trend: ', text, ': ', summary_state(trend$state)))
        }
        for (v in r$sea) add(paste('sea level pressure:', tenths(v), 'hPa'))
        for (v in r$precise) add(paste0('precise temperature: ', tenths(v[1L]), ' C, dew point ', tenths(v[2L]), ' C'))
        add(paste('ceiling:', if (is.null(s$ceiling)) 'none' else paste(s$ceiling, 'ft')))
        add(paste('flight category:', s$category))
        for (key in c('pressure_altitude', 'density_altitude')) add(paste0(gsub('_', ' ', key), ': ', if (is.null(r[[key]])) 'not available' else paste(as.character(r[[key]]), 'ft')))
        if (!is.null(r$components)) {
            for (v in r$components) add(paste0('runway ', v$name, ': ', component_phrase(v$mean), if (is.null(v$gust)) '' else paste0('; gusts ', component_phrase(v$gust))))
            add(paste('usable runways:', if (length(r$usable)) paste(r$usable, collapse = ' ') else 'none'))
            add(paste('preferred runway:', r$preferred))
        } else add('runway wind: not computed')
        if (r$kind == 'SPECI') add(paste('speci check:', r$speci))
    }
    c(lines, paste0('  ', details))
}

category_counts <- function(states) {
    paste(vapply(categories, function(category) paste(category, sum(vapply(states, function(s) s$category == category, FALSE))), ''), collapse = ', ')
}

timeline <- function(r, cal) {
    lines <- paste('TAF', r$station$code, 'issued', cal$stamp(r$time), 'valid', cal$stamp(r$start), 'to', cal$stamp(r$finish))
    states <- list()
    for (h in names(r$hours)) {
        v <- r$hours[[h]]
        states[[length(states) + 1L]] <- v$state
        line <- paste(cal$stamp(as.integer(h)), state_tokens(v$state))
        for (c in v$temporary) line <- paste(line, '|', c$kind, state_tokens(c$state))
        lines <- c(lines, line)
    }
    c(lines, paste('summary:', category_counts(states)))
}

extreme <- function(observations, value, maximum = FALSE, ratio = FALSE) {
    chosen <- NULL
    best <- NULL
    for (o in observations) {
        v <- value(o)
        if (is.null(v)) next
        comparison <- 0L
        if (!is.null(best)) {
            left <- if (ratio) v$n * best$d else v
            right <- if (ratio) best$n * v$d else best
            comparison <- if (left < right) -1L else if (left > right) 1L else 0L
        }
        if (is.null(chosen) || (maximum && comparison > 0L) || (!maximum && comparison < 0L)) {
            chosen <- o
            best <- v
        }
    }
    chosen
}

verification_lines <- function(station, reports, cal) {
    observations <- list()
    forecasts <- list()
    for (r in reports) if (r$station$code == station$code) {
        if (r$kind == 'TAF') {
            forecasts[[length(forecasts) + 1L]] <- r
        } else {
            observations[[length(observations) + 1L]] <- r
        }
    }
    v <- compare_forecasts(observations, forecasts)
    lines <- c(paste0('station ', station$code, ' (', station$name, ')'),
    paste0('reports: METAR ', sum(vapply(observations, function(o) o$kind == 'METAR', FALSE)), ', SPECI ', sum(vapply(observations, function(o) o$kind == 'SPECI', FALSE))),
    paste('observed categories:', category_counts(lapply(observations, `[[`, 'state'))))
    add_extreme <- function(label, value, phrase, maximum = FALSE, ratio = FALSE) {
        o <- extreme(observations, value, maximum, ratio)
        text <- if (is.null(o)) 'not available' else paste(phrase(o), 'at', cal$stamp(o$time))
        lines <<- c(lines, paste0(label, ': ', text))
    }
    temperature <- function(o) o$state$temperature$temperature
    add_extreme('lowest temperature', temperature, function(o) paste(temperature(o), 'C'))
    add_extreme('highest temperature', temperature, function(o) paste(temperature(o), 'C'), TRUE)
    add_extreme('strongest wind', function(o) if (is.null(o$state$wind)) NULL else o$state$wind$gust %or% o$state$wind$speed, function(o) wind_phrase(o$state$wind), TRUE)
    add_extreme('lowest ceiling', function(o) o$state$ceiling, function(o) paste(o$state$ceiling, 'ft'))
    add_extreme('lowest visibility', function(o) if (is.null(o$state$visibility)) NULL else miles(o$state$visibility), function(o) visibility_phrase(o$state$visibility), ratio = TRUE)
    lines <- c(lines, paste('verified:', v$total), paste('no forecast:', v$no_forecast))
    row <- function(label, values) paste0(sprintf('%-8s', label), paste(sprintf('%6s', as.character(values)), collapse = ''))
    lines <- c(lines, row('forecast', c(categories, 'total')))
    for (i in seq_len(4L)) lines <- c(lines, row(categories[i], c(v$table[i, ], v$rows[i])))
    lines <- c(lines, row('total', c(v$columns, v$total)), paste('hit rate:', fraction(v$hits, v$total)),
    paste('hit rate with temporary groups:', fraction(v$temporary_hits, v$total)),
    paste('heidke skill score:', fraction(v$skill[1L], v$skill[2L])))
    for (i in seq_len(4L)) lines <- c(lines, paste0(categories[i], ': pod ', fraction(v$pod[[i]][1L], v$pod[[i]][2L]), ', far ', fraction(v$far[[i]][1L], v$far[[i]][2L])))
    buckets <- matrix(0L, 5L, 2L)
    for (f in forecasts) for (o in observations) if (covers(f, o)) {
        h <- o$time - o$time %% 60L
        i <- (h - f$start) %/% 360L + 1L
        buckets[i, 2L] <- buckets[i, 2L] + 1L
        if (f$hours[[as.character(h)]]$state$category == o$state$category) buckets[i, 1L] <- buckets[i, 1L] + 1L
    }
    for (i in seq_len(5L)) lines <- c(lines, paste0('hours ', (i - 1L) * 6L, '-', (i - 1L) * 6L + 5L, ': ', fraction(buckets[i, 1L], buckets[i, 2L])))
    for (choice in v$selected) {
        o <- choice$observation
        actual <- o$state
        forecast <- choice$states$state
        reasons <- character()
        if (!(actual$category %in% choice$possible)) reasons <- c(reasons, paste0('category ', actual$category, ', forecast ', forecast$category))
        if (length(wind_changes(forecast$wind, actual$wind, 60L))) reasons <- c(reasons, paste0('wind ', wind_code(actual$wind), ', forecast ', wind_code(forecast$wind)))
        if (length(reasons)) lines <- c(lines, paste0('amendment ', cal$stamp(o$time), ': ', paste(reasons, collapse = '; ')))
    }
    lines
}

write_lines <- function(path, lines) {
    con <- file(path, open = 'wb')
    on.exit(close(con))
    if (length(lines)) writeLines(lines, con, useBytes = TRUE)
}

write_blocks <- function(path, blocks) {
    lines <- character()
    for (i in seq_along(blocks)) {
        if (i > 1L) lines <- c(lines, '')
        lines <- c(lines, blocks[[i]])
    }
    write_lines(path, lines)
}
stations <- list()
for (line in readLines('input/stations.txt', warn = FALSE)) {
    m <- captures('^([A-Z]{4}) (-?\\d+) ([^ ]+) (.+)$', line)
    runways <- lapply(strsplit(m[3L], ',', fixed = TRUE)[[1L]], function(entry) {
        p <- strsplit(entry, '/', fixed = TRUE)[[1L]]
        list(name = p[1L], heading = as.integer(p[2L]))
    })
    stations[[m[1L]]] <- list(code = m[1L], elevation = decimal_integer(m[2L]), runways = runways, name = m[4L])
}
settings <- list()
for (line in readLines('input/params.txt', warn = FALSE)) {
    p <- strsplit(line, ' ', fixed = TRUE)[[1L]]
    key <- p[1L]
    settings[[key]] <- if (key == 'VERIFY') p[ - 1L] else if (key %in% c('YEAR', 'MONTH')) as.integer(p[2L]) else decimal_integer(p[2L])
}
cal <- calendar(settings$YEAR, settings$MONTH)
report_words <- list()
for (line in readLines('input/reports.txt', warn = FALSE)) {
    p <- strsplit(sub('^ +', '', line), ' ', fixed = TRUE)[[1L]]
    if (startsWith(line, ' ')) report_words[[length(report_words)]] <- c(report_words[[length(report_words)]], p) else report_words[[length(report_words) + 1L]] <- p
}
reports <- list()
previous <- list()
for (i in seq_along(report_words)) {
    r <- parse_header(report_words[[i]], i, stations, cal)
    if (is.null(r)) next
    error <- function(g, reason) group_error(r, g, reason)
    if (r$kind == 'TAF') {
        parts <- split_taf(r$groups, r, cal, error)
        r$base <- match_section(parts$base, taf_slots, r)
        r$changes <- lapply(parts$changes, function(c) {
            c$state <- match_section(c$groups, taf_slots, r, TRUE)
            c
        })
        r$hours <- expand_taf(r, describe_state)
    } else {
        parts <- split_metar(r$groups, error)
        r$state <- describe_state(match_section(parts$main, metar_slots, r))
        r$trends <- lapply(parts$trends, function(t) {
            t$state <- match_section(t$groups, taf_slots, r, TRUE)
            t
        })
        r$sea <- parts$sea
        r$precise <- parts$precise
        r <- derive_observation(r, settings)
        if (r$kind == 'SPECI') r$speci <- speci_check(previous[[r$station$code]], r)
        previous[[r$station$code]] <- r
    }
    reports[[length(reports) + 1L]] <- r
}
invisible(dir.create('output', showWarnings = FALSE))
write_blocks('output/decoded.txt', lapply(reports, decoded, cal = cal))
category_lines <- 'station,time,ceiling,visibility,category'
timelines <- list()
for (r in reports) {
    if (r$kind == 'TAF') {
        timelines[[length(timelines) + 1L]] <- timeline(r, cal)
        next
    }
    s <- r$state
    visibility <- if (is.null(s$visibility)) 'NONE' else paste0(s$visibility$qualifier, as.character(meters(s$visibility)))
    category_lines <- c(category_lines, paste(r$station$code, cal$stamp(r$time), s$ceiling %or% 'NONE', visibility, s$category, sep = ','))
}
write_lines('output/categories.csv', category_lines)
write_blocks('output/taf_timeline.txt', timelines)
write_blocks('output/verification.txt', lapply(settings$VERIFY, function(code) verification_lines(stations[[code]], reports, cal)))
if (length(errors)) errors <- errors[order(vapply(errors, `[[`, 0L, 'number'), vapply(errors, `[[`, 0L, 'position'))]
write_lines('output/errors.txt', vapply(errors, function(e) paste0('report ', e$number, ' word ', e$position, ': ', e$text), ''))
