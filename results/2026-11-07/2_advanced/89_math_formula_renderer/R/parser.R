ATOM_KINDS <- c("identifier", "number", "symbol", "command", "text")
TERMINATORS <- c("}", "&", "newline", "right", "end", "eof")
ARGUMENT_KINDS <- c(ATOM_KINDS, "eqref", "{", "frac", "binom", "overset", "underset", "sqrt", "accent")
UNEXPECTED <- c(right="unexpected \\right", end="unexpected \\end", "&"="misplaced &", newline="misplaced \\\\")
new_node <- function(kind, children=list(), value=NULL, column=0L) list(kind=kind, children=children, value=value, column=column)
collapse <- function(elements) if (length(elements) == 1L) elements[[1]] else new_node("row", elements)
check_braces <- function(tokens) {
    stack <- integer()
    for (token in tokens) {
        if (token$kind == "{") {
            stack <- c(stack, token$column)
        } else if (token$kind == "}") {
            if (!length(stack)) formula_error(token$column, "unmatched }")
            stack <- head(stack, -1)
        }
    }
    if (length(stack)) formula_error(tail(stack,1), "unclosed {")
}
new_parser <- function(tokens) {
    parser <- new.env(parent=emptyenv())
    parser$tokens <- tokens
    parser$position <- 1L
    parser$tag <- parser$label <- NULL
    parser
}
peek_token <- function(parser) parser$tokens[[parser$position]]
take_token <- function(parser) {
    token <- peek_token(parser)
    if (token$kind != "eof") parser$position <- parser$position+1L
    token
}
unexpected <- function(parser) {
    token <- peek_token(parser)
    formula_error(token$column, UNEXPECTED[[token$kind]])
}
parse_formula <- function(parser) {
    elements <- element_list(parser, top=TRUE)
    if (peek_token(parser)$kind != "eof") unexpected(parser)
    elements
}
element_list <- function(parser, top=FALSE, index=FALSE) {
    elements <- list()
    repeat {
        token <- peek_token(parser)
        if (token$kind %in% TERMINATORS || (index && token$kind == "symbol" && token$value == "]")) return(elements)
        if (token$kind %in% c("tag", "label")) {
            if (!top) formula_error(token$column, paste0("misplaced \\", token$kind))
            previous <- parser[[token$kind]]
            if (!is.null(previous)) formula_error(token$column, paste0("duplicate \\", token$kind))
            parser[[token$kind]] <- take_token(parser)
        } else elements[[length(elements)+1L]] <- read_element(parser)
    }
}
read_element <- function(parser) {
    base <- if (peek_token(parser)$kind %in% c("^", "_")) new_node("row") else nucleus(parser)
    sub <- sup <- NULL
    while (peek_token(parser)$kind %in% c("^", "_")) {
        token <- take_token(parser)
        if (token$kind == "^") {
            if (!is.null(sup)) formula_error(token$column, "double superscript")
            sup <- argument(parser, "^")
        } else {
            if (!is.null(sub)) formula_error(token$column, "double subscript")
            sub <- argument(parser, "_")
        }
    }
    if (is.null(sub) && is.null(sup)) base else new_node("script", list(base, sub, sup))
}
argument <- function(parser, name) {
    if (!peek_token(parser)$kind %in% ARGUMENT_KINDS) formula_error(peek_token(parser)$column, paste("missing argument for", name))
    nucleus(parser)
}
delimiter <- function(parser) {
    token <- take_token(parser)
    if (token$kind == "symbol" && token$value %in% c("(", ")", "[", "]", "|", ".")) return(token$value)
    if (token$kind == "command" && token$value %in% c("\\{", "\\}")) return(token$value)
    formula_error(token$column, "invalid delimiter")
}
nucleus <- function(parser) {
    token <- take_token(parser)
    kind <- token$kind
    if (kind %in% ATOM_KINDS) return(new_node(kind, value=token$value, column=token$column))
    if (kind == "eqref") return(new_node("reference", value=token$value, column=token$column))
    if (kind == "{") {
        elements <- element_list(parser)
        if (peek_token(parser)$kind != "}") unexpected(parser)
        take_token(parser)
        return(collapse(elements))
    }
    if (kind %in% c("frac", "binom", "overset", "underset")) {
        first <- argument(parser, paste0("\\", kind))
        second <- argument(parser, paste0("\\", kind))
        return(new_node(kind, list(first, second)))
    }
    if (kind == "sqrt") {
        index <- NULL
        if (peek_token(parser)$kind == "symbol" && peek_token(parser)$value == "[") {
            opening <- take_token(parser)
            elements <- element_list(parser, index=TRUE)
            if (peek_token(parser)$kind != "symbol" || peek_token(parser)$value != "]") formula_error(opening$column, "missing ]")
            take_token(parser)
            index <- collapse(elements)
        }
        body <- argument(parser, "\\sqrt")
        return(if (is.null(index)) new_node("sqrt", list(body)) else new_node("root", list(index, body)))
    }
    if (kind == "accent") return(new_node("accent", list(argument(parser, paste0("\\", token$value))), value=token$value))
    if (kind == "left") {
        left <- delimiter(parser)
        elements <- element_list(parser)
        if (peek_token(parser)$kind != "right") formula_error(token$column, "missing \\right")
        closing <- take_token(parser)
        right <- delimiter(parser)
        return(new_node("delim", list(collapse(elements)), value=c(left,right), column=closing$column))
    }
    read_matrix(parser, token$value, token$column)
}
read_matrix <- function(parser, environment, column) {
    rows <- list(list())
    repeat {
        row <- rows[[length(rows)]]
        row[[length(row)+1L]] <- collapse(element_list(parser))
        rows[[length(rows)]] <- row
        token <- take_token(parser)
        if (token$kind == "&") next
        if (token$kind == "newline") {
            rows[[length(rows)+1L]] <- list()
            next
        }
        if (token$kind != "end") formula_error(column, "missing \\end")
        if (token$value != environment) formula_error(token$column, "mismatched \\end")
        break
    }
    last <- rows[[length(rows)]]
    if (length(rows) >= 2L && length(last) == 1L && last[[1]]$kind == "row" && !length(last[[1]]$children)) rows <- head(rows,-1)
    columns <- max(lengths(rows))
    for (i in seq_along(rows)) while (length(rows[[i]]) < columns) rows[[i]][[length(rows[[i]])+1L]] <- new_node("row")
    new_node("matrix", rows, value=environment)
}
