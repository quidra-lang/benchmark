runtime_issue <- function(position, message) {
    stop(structure(list(message = message, position = position), class = c("runtime_issue", "error", "condition")))
}
base_digits <- function(value, base) {
    if (value == 0L) return("0")
    alphabet <- strsplit("0123456789abcdef", "", fixed = TRUE)[[1L]]
    digits <- character()
    while (value > 0L) {
        digits <- c(alphabet[value %% base + 1L], digits)
        value <- value %/% base
    }
    paste0(digits, collapse = "")
}
format_output <- function(arguments, position) {
    format <- strsplit(to_string(arguments[[1L]]), "", fixed = TRUE)[[1L]]
    pieces <- character()
    index <- 1L
    argument_index <- 2L
    while (index <= length(format)) {
        if (format[index] != "%") {
            pieces <- c(pieces, format[index])
            index <- index + 1L
            next
        }
        index <- index + 1L
        if (index <= length(format) && format[index] == "%") {
            pieces <- c(pieces, "%")
            index <- index + 1L
            next
        }
        flags <- character()
        while (index <= length(format) && format[index] %in% c("-", "0")) {
            flags <- union(flags, format[index])
            index <- index + 1L
        }
        width <- 0L
        while (index <= length(format) && digit(format[index])) {
            width <- width * 10L + utf8ToInt(format[index]) - 48L
            index <- index + 1L
        }
        precision <- NULL
        if (index <= length(format) && format[index] == ".") {
            index <- index + 1L
            precision <- 0L
            while (index <= length(format) && digit(format[index])) {
                precision <- precision * 10L + utf8ToInt(format[index]) - 48L
                index <- index + 1L
            }
        }
        if (index > length(format) || !format[index] %in% c("d", "i", "s", "c", "x", "o")) runtime_issue(position, "invalid format")
        conversion <- format[index]
        index <- index + 1L
        if (argument_index > length(arguments)) runtime_issue(position, "not enough arguments")
        value <- arguments[[argument_index]]
        argument_index <- argument_index + 1L
        numeric <- conversion %in% c("d", "i", "x", "o")
        if (numeric) {
            integer <- to_number(value)
            base <- if (conversion %in% c("d", "i")) 10L else if (conversion == "x") 16L else 8L
            digits <- base_digits(abs(integer), base)
            if (!is.null(precision)) {
                digits <- if (precision == 0L && integer == 0L) "" else paste0(strrep("0", max(0L, precision - nchar(digits))), digits)
            }
            body <- paste0(if (integer < 0L) "-" else "", digits)
        } else if (conversion == "s") {
            body <- to_string(value)
            if (!is.null(precision)) body <- substr(body, 1L, precision)
        } else if (value$kind %in% c("number", "strnum")) {
            code <- to_number(value)
            if (code != 10L && !(code >= 32L && code <= 126L)) runtime_issue(position, "invalid character code")
            body <- intToUtf8(code)
        } else body <- substr(to_string(value), 1L, 1L)
        missing <- width - nchar(body)
        if (missing > 0L) {
            if ("-" %in% flags) body <- paste0(body, strrep(" ", missing)) else if (numeric && "0" %in% flags && is.null(precision)) {
                body <- if (startsWith(body, "-")) paste0("-", strrep("0", missing), substring(body, 2L)) else paste0(strrep("0", missing), body)
            } else body <- paste0(strrep(" ", missing), body)
        }
        pieces <- c(pieces, body)
    }
    paste0(pieces, collapse = "")
}
invoke_builtin <- function(name, arguments, position) {
    if (name == "sprintf") return(string_value(format_output(arguments, position)))
    if (name == "int") return(number(to_number(arguments[[1L]])))
    text <- to_string(arguments[[1L]])
    if (name == "substr") {
        beginning <- to_number(arguments[[2L]])
        finish <- if (length(arguments) == 3L) beginning + to_number(arguments[[3L]]) else nchar(text) + 1L
        beginning <- max(beginning, 1L)
        finish <- min(finish, nchar(text) + 1L)
        return(string_value(if (finish > beginning) substr(text, beginning, finish - 1L) else ""))
    }
    if (name == "index") return(number(literal_index(text, to_string(arguments[[2L]]))))
    codes <- utf8ToInt(text)
    if (name == "toupper") codes[codes %in% 97L:122L] <- codes[codes %in% 97L:122L] - 32L else codes[codes %in% 65L:90L] <- codes[codes %in% 65L:90L] + 32L
    string_value(intToUtf8(codes))
}
