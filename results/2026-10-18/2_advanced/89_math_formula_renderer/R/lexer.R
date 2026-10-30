formula_error <- function(column, message) {
    stop(structure(list(message=message, column=column, call=NULL), class=c("formula_error", "error", "condition")))
}
new_token <- function(kind, value, column) list(kind=kind, value=value, column=column)
GREEK <- strsplit("alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi pi rho sigma tau upsilon phi chi psi omega Gamma Delta Theta Lambda Xi Pi Sigma Upsilon Phi Psi Omega", " ", fixed=TRUE)[[1]]
FUNCTIONS <- c("sin", "cos", "tan", "log", "ln", "exp", "det", "lim", "max", "min")
LARGE_OPERATORS <- c("sum", "prod", "int")
ACCENTS <- c("overline", "hat", "vec", "dot", "tilde", "overbrace", "underbrace")
CONSTRUCTS <- c("frac", "binom", "overset", "underset", "sqrt", "left", "right")
RAW_COMMANDS <- c("text", "begin", "end", "tag", "label", "eqref")
ENVIRONMENTS <- c("matrix", "pmatrix", "bmatrix", "vmatrix", "cases")
SYMBOLS <- strsplit("+-*/=<>:()[],;.!|'", "", fixed=TRUE)[[1]]
SYMBOL_COMMANDS <- local({
    table <- list()
    for (name in GREEK) table[[paste0("\\", name)]] <- c(name, "ordinary")
    for (name in c(FUNCTIONS, LARGE_OPERATORS)) table[[paste0("\\", name)]] <- c(name, "operator")
    entries <- list(c("cdot","*","binary"), c("times","x","binary"), c("pm","+-","binary"),
        c("mp","-+","binary"), c("leq","<=","relation"), c("geq",">=","relation"), c("neq","!=","relation"),
        c("approx","~=","relation"), c("to","->","relation"), c("infty","oo","ordinary"),
        c("ldots","...","ordinary"), c("cdots","...","ordinary"), c("quad","  ","ordinary"),
        c(","," ","ordinary"), c("{","{","open"), c("}","}","close"))
    for (entry in entries) table[[paste0("\\", entry[1])]] <- entry[2:3]
    table
})
COMMAND_NAMES <- substring(names(SYMBOL_COMMANDS), 2L)
COMMAND_NAMES <- COMMAND_NAMES[grepl("^[A-Za-z]+$", COMMAND_NAMES)]
letter <- function(c) grepl("^[A-Za-z]$", c)
digit <- function(c) grepl("^[0-9]$", c)
character_at <- function(text, i) if (i >= 1L && i <= nchar(text)) substr(text, i, i) else ""
text_slice <- function(text, a, b) if (a <= b) substr(text, a, b) else ""
tokenize <- function(text) {
    tokens <- list()
    position <- 1L
    append_token <- function(kind, value, column) tokens[[length(tokens)+1L]] <<- new_token(kind, value, column)
    while (position <= nchar(text)) {
        c <- character_at(text, position)
        column <- position
        if (c == " ") {
            position <- position+1L
        } else if (letter(c)) {
            first <- position
            while (letter(character_at(text, position))) position <- position+1L
            append_token("identifier", text_slice(text, first, position-1L), column)
        } else if (digit(c)) {
            first <- position
            while (digit(character_at(text, position))) position <- position+1L
            if (character_at(text, position) == "." && digit(character_at(text, position+1L))) {
                position <- position+2L
                while (digit(character_at(text, position))) position <- position+1L
            }
            append_token("number", text_slice(text, first, position-1L), column)
        } else if (c %in% c(SYMBOLS, "{", "}", "^", "_", "&")) {
            append_token(if (c %in% SYMBOLS) "symbol" else c, c, column)
            position <- position+1L
        } else if (c == "\\") {
            position <- position+1L
            c <- character_at(text, position)
            if (c %in% c("\\", "{", "}", ",")) {
                append_token(if (c == "\\") "newline" else "command", paste0("\\", c), column)
                position <- position+1L
                next
            }
            first <- position
            while (letter(character_at(text, position))) position <- position+1L
            name <- text_slice(text, first, position-1L)
            if (!nzchar(name)) formula_error(column, "invalid command")
            if (name %in% RAW_COMMANDS) {
                while (character_at(text, position) == " ") position <- position+1L
                if (character_at(text, position) != "{") formula_error(position, "expected {")
                closing <- regexpr("}", substring(text, position+1L), fixed=TRUE)[1]
                if (closing < 0L) formula_error(column, "unterminated argument")
                last <- position+closing
                argument <- text_slice(text, position+1L, last-1L)
                if (name %in% c("begin", "end") && !argument %in% ENVIRONMENTS) {
                    formula_error(column, paste0("unknown environment \"", argument, "\""))
                }
                append_token(name, argument, column)
                position <- last+1L
            } else if (paste0("\\", name) %in% names(SYMBOL_COMMANDS)) {
                append_token("command", paste0("\\", name), column)
            } else if (name %in% ACCENTS) {
                append_token("accent", name, column)
            } else if (name %in% CONSTRUCTS) {
                append_token(name, name, column)
            } else formula_error(column, paste0("unknown command \\", name))
        } else formula_error(column, paste("invalid character", c))
    }
    append_token("eof", "", nchar(text)+1L)
    tokens
}
