mode_names <- c("IRM", "LNM", "DECCKM", "DECSCNM", "DECOM", "DECAWM", "DECTCEM", "DECKPAM", "BRACKETED")
flag_names <- c("bold", "dim", "italic", "underline", "blink", "reverse", "hidden", "strike")
ansi_modes <- c(`4` = "IRM", `20` = "LNM")
dec_modes <- c(`1` = "DECCKM", `5` = "DECSCNM", `6` = "DECOM", `7` = "DECAWM", `25` = "DECTCEM", `2004` = "BRACKETED")
default_attr <- list(flags = 0L, fg = "", bg = "")
blank <- list(char = " ", attr = default_attr)
initial <- function(name) name %in% c("DECAWM", "DECTCEM")
span <- function(first, last) if (first <= last) seq.int(first, last) else integer()
blank_row <- function(t) rep(list(blank), t$width)
blank_screen <- function(t) replicate(t$height, blank_row(t), simplify = FALSE)
clear_screen <- function(t, display) t$screens[[display]] <- blank_screen(t)
clear_sequence <- function(t) {
    t$marker <- ""
    t$parameters <- ""
    t$intermediates <- ""
    t$osc <- ""
}
reset <- function(t) {
    t$screens <- list(blank_screen(t), blank_screen(t))
    t$display <- 1L
    t$row <- 1L
    t$column <- 1L
    t$top <- 1L
    t$bottom <- t$height
    t$shape <- 1L
    t$pending <- FALSE
    t$attr <- default_attr
    t$g0 <- FALSE
    t$g1 <- FALSE
    t$gl <- FALSE
    t$modes <- setNames(vapply(mode_names, initial, logical(1)), mode_names)
    t$saved <- vector("list", 2)
    t$tabs <- if (t$width >= 9L) seq.int(9L, t$width, by = 8L) else integer()
    t$scrollback <- character()
    t$title <- NULL
    t$last <- NULL
    t$state <- "ground"
    clear_sequence(t)
}
row_text <- function(row) sub(" +$", "", paste(vapply(row, function(cell) cell$char, character(1)), collapse = ""))
scroll_up <- function(t, top, bottom, history = FALSE) {
    removed <- t$screens[[t$display]][[top]]
    for (r in span(top, bottom - 1L)) t$screens[[t$display]][[r]] <- t$screens[[t$display]][[r + 1L]]
    t$screens[[t$display]][[bottom]] <- blank_row(t)
    if (history && t$display == 1L && top == 1L) {
        t$scrollback <- c(t$scrollback, row_text(removed))
        if (length(t$scrollback) > 100L) t$scrollback <- t$scrollback[-1L]
    }
}
scroll_down <- function(t, top, bottom) {
    for (r in rev(span(top + 1L, bottom))) t$screens[[t$display]][[r]] <- t$screens[[t$display]][[r - 1L]]
    t$screens[[t$display]][[top]] <- blank_row(t)
}
line_feed <- function(t) {
    if (t$row == t$bottom) scroll_up(t, t$top, t$bottom, TRUE) else if (t$row < t$height) t$row <- t$row + 1L
}
reverse_feed <- function(t) {
    if (t$row == t$top) scroll_down(t, t$top, t$bottom) else if (t$row > 1L) t$row <- t$row - 1L
}
tab_move <- function(t, reverse = FALSE) {
    if (reverse) {
        earlier <- t$tabs[t$tabs < t$column]
        t$column <- if (length(earlier)) max(earlier) else 1L
    } else {
        later <- t$tabs[t$tabs > t$column]
        t$column <- if (length(later)) min(later) else t$width
    }
}
address <- function(t, value) if (t$modes[["DECOM"]]) min(t$top + value - 1L, t$bottom) else min(value, t$height)
home <- function(t) {
    t$row <- address(t, 1L)
    t$column <- 1L
}
save_cursor <- function(t) {
    t$saved[[t$display]] <- list(row = t$row, column = t$column, attr = t$attr,
                                origin = t$modes[["DECOM"]], g0 = t$g0, g1 = t$g1, gl = t$gl)
}
restore_cursor <- function(t) {
    t$pending <- FALSE
    saved <- t$saved[[t$display]]
    if (is.null(saved)) saved <- list(row = 1L, column = 1L, attr = default_attr, origin = FALSE, g0 = FALSE, g1 = FALSE, gl = FALSE)
    t$row <- saved$row
    t$column <- saved$column
    t$attr <- saved$attr
    t$modes[["DECOM"]] <- saved$origin
    t$g0 <- saved$g0
    t$g1 <- saved$g1
    t$gl <- saved$gl
}
insert_cells <- function(t, count) {
    row <- t$screens[[t$display]][[t$row]]
    for (column in rev(span(t$column + count, t$width))) row[[column]] <- row[[column - count]]
    for (column in span(t$column, t$column + count - 1L)) row[[column]] <- blank
    t$screens[[t$display]][[t$row]] <- row
}
delete_cells <- function(t, count) {
    row <- t$screens[[t$display]][[t$row]]
    for (column in span(t$column, t$width - count)) row[[column]] <- row[[column + count]]
    for (column in span(t$width - count + 1L, t$width)) row[[column]] <- blank
    t$screens[[t$display]][[t$row]] <- row
}
write_char <- function(t, char) {
    t$printed <- t$printed + 1L
    t$last <- char
    if (t$pending) {
        t$pending <- FALSE
        t$column <- 1L
        line_feed(t)
    }
    if (t$modes[["IRM"]]) insert_cells(t, 1L)
    t$screens[[t$display]][[t$row]][[t$column]] <- list(char = char, attr = t$attr)
    if (t$column < t$width) t$column <- t$column + 1L else if (t$modes[["DECAWM"]]) t$pending <- TRUE
}
print_char <- function(t, char) {
    graphics <- if (t$gl) t$g1 else t$g0
    if (graphics) {
        replacements <- c("`" = "*", a = "#", j = "+", k = "+", l = "+", m = "+", n = "+",
                          t = "+", u = "+", v = "+", w = "+", q = "-", x = "|", "~" = "o")
        if (char %in% names(replacements)) char <- replacements[[char]]
    }
    write_char(t, char)
}
control <- function(t, byte) {
    if (byte == 7L) {
        t$bells <- t$bells + 1L
    } else if (byte == 8L) {
        t$pending <- FALSE
        t$column <- max(t$column - 1L, 1L)
    } else if (byte == 9L) {
        t$pending <- FALSE
        tab_move(t)
    } else if (byte %in% c(10L, 11L, 12L)) {
        t$pending <- FALSE
        line_feed(t)
        if (t$modes[["LNM"]]) t$column <- 1L
    } else if (byte == 13L) {
        t$pending <- FALSE
        t$column <- 1L
    } else if (byte == 14L) {
        t$gl <- TRUE
    } else if (byte == 15L) {
        t$gl <- FALSE
    }
}
execute_esc <- function(t, key) {
    if (key == "7") {
        save_cursor(t)
    } else if (key == "8") {
        restore_cursor(t)
    } else if (key == "D") {
        t$pending <- FALSE
        line_feed(t)
    } else if (key == "E") {
        t$pending <- FALSE
        t$column <- 1L
        line_feed(t)
    } else if (key == "M") {
        t$pending <- FALSE
        reverse_feed(t)
    } else if (key == "H") {
        t$tabs <- union(t$tabs, t$column)
    } else if (key == "c") {
        reset(t)
    } else if (key %in% c("=", ">")) {
        t$modes[["DECKPAM"]] <- key == "="
    } else if (key == "\\") {
        invisible(NULL)
    } else if (key %in% c("(0", "(B")) {
        t$g0 <- key == "(0"
    } else if (key %in% c(")0", ")B")) {
        t$g1 <- key == ")0"
    } else if (key == "#8") {
        t$pending <- FALSE
        cell <- list(char = "E", attr = default_attr)
        t$screens[[t$display]] <- replicate(t$height, rep(list(cell), t$width), simplify = FALSE)
        t$top <- 1L
        t$bottom <- t$height
        t$row <- 1L
        t$column <- 1L
        t$modes[["DECOM"]] <- FALSE
    } else {
        t$ignored[1] <- t$ignored[1] + 1L
        return(invisible(NULL))
    }
    t$sequences <- t$sequences + 1L
}
execute_osc <- function(t) {
    if (startsWith(t$osc, "0;") || startsWith(t$osc, "2;")) {
        t$title <- substring(t$osc, 3L)
        t$sequences <- t$sequences + 1L
    } else {
        t$ignored[1] <- t$ignored[1] + 1L
    }
}
palette <- function(number) {
    names <- c("black", "red", "green", "yellow", "blue", "magenta", "cyan", "white")
    if (number < 8L) return(names[number + 1L])
    if (number < 16L) return(paste0("bright-", names[number - 7L]))
    as.character(number)
}
sgr <- function(t, params) {
    values <- if (length(params)) params else 0L
    attr <- t$attr
    on <- c(`1` = 0L, `2` = 1L, `3` = 2L, `4` = 3L, `5` = 4L, `7` = 5L, `8` = 6L, `9` = 7L)
    off <- c(`23` = 2L, `24` = 3L, `25` = 4L, `27` = 5L, `28` = 6L, `29` = 7L)
    index <- 1L
    while (index <= length(values)) {
        value <- values[index]
        name <- as.character(value)
        if (value == 0L) {
            attr <- default_attr
        } else if (name %in% names(on)) {
            attr$flags <- bitwOr(attr$flags, bitwShiftL(1L, on[[name]]))
        } else if (value == 22L) {
            attr$flags <- bitwAnd(attr$flags, bitwNot(3L))
        } else if (name %in% names(off)) {
            attr$flags <- bitwAnd(attr$flags, bitwNot(bitwShiftL(1L, off[[name]])))
        } else if (value >= 30L && value <= 37L) {
            attr$fg <- palette(value - 30L)
        } else if (value >= 90L && value <= 97L) {
            attr$fg <- palette(value - 82L)
        } else if (value >= 40L && value <= 47L) {
            attr$bg <- palette(value - 40L)
        } else if (value >= 100L && value <= 107L) {
            attr$bg <- palette(value - 92L)
        } else if (value == 39L) {
            attr$fg <- ""
        } else if (value == 49L) {
            attr$bg <- ""
        } else if (value %in% c(38L, 48L)) {
            if (index + 2L <= length(values) && values[index + 1L] == 5L && values[index + 2L] <= 255L) {
                color <- palette(values[index + 2L])
                index <- index + 2L
            } else if (index + 4L <= length(values) && values[index + 1L] == 2L && all(values[index + 2:4] <= 255L)) {
                color <- paste0("#", paste(sprintf("%02x", values[index + 2:4]), collapse = ""))
                index <- index + 4L
            } else {
                return(FALSE)
            }
            if (value == 38L) attr$fg <- color else attr$bg <- color
        } else {
            return(FALSE)
        }
        index <- index + 1L
    }
    t$attr <- attr
    TRUE
}
set_modes <- function(t, params, dec, enabled) {
    values <- if (length(params)) params else 0L
    allowed <- if (dec) c(1L, 5L, 6L, 7L, 25L, 47L, 1047L, 1048L, 1049L, 2004L) else c(4L, 20L)
    if (!all(values %in% allowed)) return(FALSE)
    for (value in values) {
        name <- as.character(value)
        if (!dec) {
            t$modes[[ansi_modes[[name]]]] <- enabled
        } else if (name %in% names(dec_modes)) {
            if (value == 6L || value == 7L && !enabled) t$pending <- FALSE
            t$modes[[dec_modes[[name]]]] <- enabled
            if (value == 6L) home(t)
        } else if (value == 1048L) {
            if (enabled) save_cursor(t) else restore_cursor(t)
        } else {
            t$pending <- FALSE
            if (enabled && t$display == 1L) {
                if (value == 1049L) save_cursor(t)
                t$display <- 2L
                if (value == 1049L) clear_screen(t, 2L)
            } else if (!enabled && t$display == 2L) {
                if (value == 1047L) clear_screen(t, 2L)
                t$display <- 1L
                if (value == 1049L) restore_cursor(t)
            }
        }
    }
    TRUE
}
erase <- function(t, row, first, last) {
    for (column in span(first, last)) t$screens[[t$display]][[row]][[column]] <- blank
}
move_up <- function(t, count) t$row <- max(t$row - count, if (t$row >= t$top) t$top else 1L)
move_down <- function(t, count) t$row <- min(t$row + count, if (t$row <= t$bottom) t$bottom else t$height)
reply <- function(t, text) {
    t$replies <- t$replies + 1L
    cat("REPLY ", text, "\n", sep = "")
}
mode_state <- function(enabled) if (enabled) 1L else 2L
csi <- function(t, key, params) {
    p1 <- if (length(params)) params[1] else 0L
    p2 <- if (length(params) >= 2L) params[2] else 0L
    n <- max(p1, 1L)
    conditions <- list(J = 0:3, K = 0:2, g = c(0L, 3L), ` q` = 0:6, n = c(5L, 6L), `?n` = 6L, c = 0L, `>c` = 0L, t = 18L)
    if (key %in% names(conditions) && !(p1 %in% conditions[[key]])) return(1L)
    wrap_keys <- strsplit("ABCDEFGHIJKLMPSTXZ`adef@", "", fixed = TRUE)[[1]]
    if (key %in% wrap_keys) t$pending <- FALSE
    if (key == "A") {
        move_up(t, n)
    } else if (key %in% c("B", "e")) {
        move_down(t, n)
    } else if (key %in% c("C", "a")) {
        t$column <- min(t$column + n, t$width)
    } else if (key == "D") {
        t$column <- max(t$column - n, 1L)
    } else if (key == "E") {
        move_down(t, n)
        t$column <- 1L
    } else if (key == "F") {
        move_up(t, n)
        t$column <- 1L
    } else if (key %in% c("G", "`")) {
        t$column <- min(n, t$width)
    } else if (key %in% c("H", "f")) {
        t$row <- address(t, n)
        t$column <- min(max(p2, 1L), t$width)
    } else if (key == "d") {
        t$row <- address(t, n)
    } else if (key %in% c("I", "Z")) {
        for (i in seq_len(n)) tab_move(t, key == "Z")
    } else if (key == "J") {
        if (p1 == 0L) {
            erase(t, t$row, t$column, t$width)
            for (row in span(t$row + 1L, t$height)) erase(t, row, 1L, t$width)
        } else if (p1 == 1L) {
            for (row in span(1L, t$row - 1L)) erase(t, row, 1L, t$width)
            erase(t, t$row, 1L, t$column)
        } else if (p1 == 2L) {
            clear_screen(t, t$display)
        } else {
            t$scrollback <- character()
        }
    } else if (key == "K") {
        erase(t, t$row, if (p1 %in% c(1L, 2L)) 1L else t$column, if (p1 == 1L) t$column else t$width)
    } else if (key == "X") {
        erase(t, t$row, t$column, min(t$column + n - 1L, t$width))
    } else if (key == "@") {
        insert_cells(t, min(n, t$width - t$column + 1L))
    } else if (key == "P") {
        delete_cells(t, min(n, t$width - t$column + 1L))
    } else if (key %in% c("L", "M")) {
        if (t$row >= t$top && t$row <= t$bottom) {
            for (i in seq_len(min(n, t$bottom - t$row + 1L))) {
                if (key == "L") scroll_down(t, t$row, t$bottom) else scroll_up(t, t$row, t$bottom)
            }
            t$column <- 1L
        }
    } else if (key %in% c("S", "T")) {
        for (i in seq_len(min(n, t$bottom - t$top + 1L))) {
            if (key == "S") scroll_up(t, t$top, t$bottom, TRUE) else scroll_down(t, t$top, t$bottom)
        }
    } else if (key == "b") {
        if (!is.null(t$last)) {
            char <- t$last
            for (i in seq_len(n)) write_char(t, char)
        }
    } else if (key == "g") {
        t$tabs <- if (p1 == 0L) setdiff(t$tabs, t$column) else integer()
    } else if (key == "m") {
        if (!sgr(t, params)) return(1L)
    } else if (key %in% c("h", "l", "?h", "?l")) {
        if (!set_modes(t, params, startsWith(key, "?"), endsWith(key, "h"))) return(1L)
    } else if (key == " q") {
        t$shape <- n
    } else if (key == "r") {
        bottom <- min(if (p2 == 0L) t$height else p2, t$height)
        if (n >= bottom) return(4L)
        t$pending <- FALSE
        t$top <- n
        t$bottom <- bottom
        home(t)
    } else if (key == "s") {
        save_cursor(t)
    } else if (key == "u") {
        restore_cursor(t)
    } else if (key == "!p") {
        t$pending <- FALSE
        for (name in c("IRM", "DECCKM", "DECOM", "DECAWM", "DECTCEM", "DECKPAM")) t$modes[[name]] <- initial(name)
        t$top <- 1L
        t$bottom <- t$height
        t$attr <- default_attr
        t$g0 <- FALSE
        t$g1 <- FALSE
        t$gl <- FALSE
        t$saved[t$display] <- list(NULL)
    } else if (key %in% c("n", "?n")) {
        row <- if (t$modes[["DECOM"]]) max(t$row - t$top + 1L, 1L) else t$row
        text <- if (key == "?n") paste0("^[[?", row, ";", t$column, ";1R") else if (p1 == 5L) "^[[0n" else paste0("^[[", row, ";", t$column, "R")
        reply(t, text)
    } else if (key == "c") {
        reply(t, "^[[?1;2c")
    } else if (key == ">c") {
        reply(t, "^[[>0;95;0c")
    } else if (key == "t") {
        reply(t, paste0("^[[8;", t$height, ";", t$width, "t"))
    } else if (key %in% c("$p", "?$p")) {
        state <- 0L
        prefix <- ""
        name <- as.character(p1)
        if (key == "$p") {
            if (name %in% names(ansi_modes)) state <- mode_state(t$modes[[ansi_modes[[name]]]])
        } else {
            prefix <- "?"
            if (name %in% names(dec_modes)) state <- mode_state(t$modes[[dec_modes[[name]]]]) else if (p1 %in% c(47L, 1047L, 1049L)) state <- mode_state(t$display == 2L)
        }
        reply(t, paste0("^[[", prefix, p1, ";", state, "$y"))
    } else {
        return(1L)
    }
    0L
}
execute_csi <- function(t, final) {
    fields <- if (nzchar(t$parameters)) strsplit(paste0(t$parameters, ";x"), ";", fixed = TRUE)[[1]] else character()
    if (length(fields)) fields <- fields[-length(fields)]
    if (length(fields) > 16L) {
        t$ignored[4] <- t$ignored[4] + 1L
        return(invisible(NULL))
    }
    params <- vapply(fields, function(field) {
        value <- 0L
        for (digit in utf8ToInt(field) - 48L) value <- min(9999L, value * 10L + digit)
        value
    }, integer(1))
    reason <- csi(t, paste0(t$marker, t$intermediates, final), params)
    if (reason == 0L) t$sequences <- t$sequences + 1L else t$ignored[reason] <- t$ignored[reason] + 1L
}
is_intermediate <- function(byte) byte >= 32L && byte <= 47L
is_final <- function(byte) byte >= 64L && byte <= 126L
receive <- function(t, byte) {
    t$bytes <- t$bytes + 1L
    if (byte < 32L) {
        if (byte == 27L) {
            if (t$state == "osc") execute_osc(t) else if (t$state != "ground") t$ignored[3] <- t$ignored[3] + 1L
            clear_sequence(t)
            t$state <- "escape"
        } else if (byte %in% c(24L, 26L)) {
            if (t$state != "ground") {
                t$ignored[3] <- t$ignored[3] + 1L
                t$state <- "ground"
            }
        } else if (t$state == "osc") {
            if (byte == 7L) {
                execute_osc(t)
                t$state <- "ground"
            }
        } else {
            control(t, byte)
        }
        return(invisible(NULL))
    }
    char <- intToUtf8(byte)
    if (t$state == "ground") {
        print_char(t, char)
    } else if (t$state %in% c("escape", "escape_intermediate")) {
        if (is_intermediate(byte)) {
            t$intermediates <- paste0(t$intermediates, char)
            t$state <- "escape_intermediate"
        } else if (t$state == "escape" && char == "[") {
            t$state <- "csi_entry"
        } else if (t$state == "escape" && char == "]") {
            t$state <- "osc"
        } else {
            execute_esc(t, paste0(t$intermediates, char))
            t$state <- "ground"
        }
    } else if (t$state == "osc") {
        t$osc <- paste0(t$osc, char)
    } else if (t$state == "csi_ignore") {
        if (is_final(byte)) {
            t$ignored[2] <- t$ignored[2] + 1L
            t$state <- "ground"
        }
    } else if (t$state == "csi_intermediate") {
        if (is_intermediate(byte)) {
            t$intermediates <- paste0(t$intermediates, char)
        } else if (is_final(byte)) {
            execute_csi(t, char)
            t$state <- "ground"
        } else {
            t$state <- "csi_ignore"
        }
    } else if (t$state == "csi_entry" && byte >= 60L && byte <= 63L) {
        t$marker <- char
        t$state <- "csi_param"
    } else if (byte >= 48L && byte <= 57L || byte == 59L) {
        t$parameters <- paste0(t$parameters, char)
        t$state <- "csi_param"
    } else if (is_intermediate(byte)) {
        t$intermediates <- paste0(t$intermediates, char)
        t$state <- "csi_intermediate"
    } else if (is_final(byte)) {
        execute_csi(t, char)
        t$state <- "ground"
    } else {
        t$state <- "csi_ignore"
    }
}
key_string <- function(t, name) {
    cursor <- c(UP = "A", DOWN = "B", RIGHT = "C", LEFT = "D", HOME = "H", END = "F")
    if (name %in% names(cursor)) return(paste0(if (t$modes[["DECCKM"]]) "^[O" else "^[[", cursor[[name]]))
    fixed <- c(INSERT = "^[[2~", DELETE = "^[[3~", PAGEUP = "^[[5~", PAGEDOWN = "^[[6~",
               F1 = "^[OP", F2 = "^[OQ", F3 = "^[OR", F4 = "^[OS", F5 = "^[[15~", F6 = "^[[17~",
               F7 = "^[[18~", F8 = "^[[19~", F9 = "^[[20~", F10 = "^[[21~", F11 = "^[[23~", F12 = "^[[24~",
               TAB = "^I", BACKSPACE = "^?", ESCAPE = "^[")
    if (name %in% names(fixed)) return(fixed[[name]])
    enter <- if (t$modes[["LNM"]]) "^M^J" else "^M"
    if (name == "ENTER") return(enter)
    if (name == "KPENTER") return(if (t$modes[["DECKPAM"]]) "^[OM" else enter)
    digit <- as.integer(substring(name, 3L))
    if (t$modes[["DECKPAM"]]) paste0("^[O", intToUtf8(112L + digit)) else as.character(digit)
}
screen_output <- function(t, label) {
    cat(label, if (t$display == 1L) "main" else "alt", "cursor", paste0(t$row, ",", t$column), "scrollback", length(t$scrollback), sep = " ")
    cat(if (t$pending) " pending\n" else "\n")
    for (row in t$screens[[t$display]]) cat("|", row_text(row), "\n", sep = "")
}
describe <- function(attr) {
    parts <- flag_names[vapply(0:7, function(bit) bitwAnd(attr$flags, bitwShiftL(1L, bit)) != 0L, logical(1))]
    if (nzchar(attr$fg)) parts <- c(parts, paste0("fg=", attr$fg))
    if (nzchar(attr$bg)) parts <- c(parts, paste0("bg=", attr$bg))
    paste(parts, collapse = " ")
}
finish <- function(t) {
    if (t$state != "ground") {
        t$ignored[3] <- t$ignored[3] + 1L
        t$state <- "ground"
    }
    screen_output(t, "FINAL")
    cat("TITLE ", if (is.null(t$title)) "none" else paste0('"', t$title, '"'), "\n", sep = "")
    modes <- character()
    for (name in mode_names) if (t$modes[[name]] != initial(name)) modes <- c(modes, paste0(name, "=", if (t$modes[[name]]) "on" else "off"))
    if (t$g0) modes <- c(modes, "G0=graphics")
    if (t$g1) modes <- c(modes, "G1=graphics")
    if (t$gl) modes <- c(modes, "GL=G1")
    if (t$shape != 1L) modes <- c(modes, paste0("CURSOR=", t$shape))
    cat("MODES ", if (length(modes)) paste(modes, collapse = " ") else "default", "\n", sep = "")
    cat("REGION ", t$top, "-", t$bottom, "\n", sep = "")
    cat("TABS ", if (length(t$tabs)) paste(sort(t$tabs), collapse = ",") else "none", "\n", sep = "")
    cat("SCROLLBACK ", length(t$scrollback), "\n", sep = "")
    for (text in tail(t$scrollback, 5L)) cat("|", text, "\n", sep = "")
    runs <- character()
    for (r in seq_len(t$height)) {
        row <- t$screens[[t$display]][[r]]
        start <- 1L
        while (start <= t$width) {
            last <- start
            while (last < t$width && identical(row[[last + 1L]]$attr, row[[start]]$attr)) last <- last + 1L
            if (!identical(row[[start]]$attr, default_attr)) runs <- c(runs, paste0("row ", r, " col ", start, "-", last, " ", describe(row[[start]]$attr)))
            start <- last + 1L
        }
    }
    cat("ATTRS ", length(runs), "\n", sep = "")
    for (line in runs) cat(line, "\n", sep = "")
    cat("BELL ", t$bells, "\n", sep = "")
    cat("REPLIES ", t$replies, "\n", sep = "")
    cat("STATS bytes=", t$bytes, " printed=", t$printed, " sequences=", t$sequences, "\n", sep = "")
    v <- t$ignored
    cat("IGNORED ", sum(v), " unsupported=", v[1], " malformed=", v[2], " canceled=", v[3], " invalid=", v[4], "\n", sep = "")
}
main <- function() {
    lines <- readLines(file("stdin"), warn = FALSE)
    dimensions <- as.integer(strsplit(lines[1], " ", fixed = TRUE)[[1]])
    terminal <- new.env(parent = emptyenv())
    terminal$width <- dimensions[1]
    terminal$height <- dimensions[2]
    terminal$bytes <- 0L
    terminal$printed <- 0L
    terminal$sequences <- 0L
    terminal$bells <- 0L
    terminal$replies <- 0L
    terminal$dumps <- 0L
    terminal$ignored <- integer(4)
    reset(terminal)
    caret <- setNames(c(0L, 7L, 8L, 9L, 10L, 11L, 12L, 13L, 14L, 15L, 24L, 26L, 27L, 94L), c("@", "G", "H", "I", "J", "K", "L", "M", "N", "O", "X", "Z", "[", "^"))
    for (line in lines[-1L]) {
        if (line == "%%END") break
        if (line == "%%DUMP") {
            terminal$dumps <- terminal$dumps + 1L
            screen_output(terminal, paste("DUMP", terminal$dumps))
        } else if (startsWith(line, "%%KEY ")) {
            name <- substring(line, 7L)
            cat("KEY ", name, " ", key_string(terminal, name), "\n", sep = "")
        } else if (startsWith(line, "%%PASTE ")) {
            sent <- gsub("^", "^^", substring(line, 9L), fixed = TRUE)
            if (terminal$modes[["BRACKETED"]]) sent <- paste0("^[[200~", sent, "^[[201~")
            cat("PASTE ", sent, "\n", sep = "")
        } else {
            bytes <- utf8ToInt(line)
            index <- 1L
            while (index <= length(bytes)) {
                if (bytes[index] == 94L) {
                    receive(terminal, caret[[intToUtf8(bytes[index + 1L])]])
                    index <- index + 2L
                } else {
                    receive(terminal, bytes[index])
                    index <- index + 1L
                }
            }
        }
    }
    finish(terminal)
}
main()
