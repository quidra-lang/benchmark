DETERMINISTIC <- c(predicate_keys(c("true", "fail", "false", "nl"), 0L),
    predicate_keys(c("var", "nonvar", "atom", "number", "integer", "atomic", "compound", "callable", "is_list", "write", "writeq"), 1L),
    predicate_keys(c("=", "\\=", "==", "\\==", "is", "=:=", "=\\=", "<", ">", "=<", ">=", "=..", "copy_term", "atom_length", "atom_chars"), 2L),
    predicate_keys(c("functor", "arg"), 3L))
EVALUABLE <- c(predicate_keys(c("+", "-", "*", "//", "mod", "rem", "min", "max"), 2L), predicate_keys(c("-", "abs"), 1L))
checked_integer <- function(value) {
    if (value < gmp::as.bigz("-2147483648") || value > gmp::as.bigz("2147483647")) prolog_fault(compound("evaluation_error", atom_term("int_overflow")))
    value
}
quotient <- function(left, right) {
    value <- abs(left) %/% abs(right)
    if ((left < 0L) != (right < 0L)) -value else value
}
evaluate_arithmetic <- function(term) {
    term <- dereference(term)
    if (is_variable(term)) prolog_fault(atom_term("instantiation_error"))
    if (is_integer(term)) return(term$value)
    key <- indicator(term)
    if (is_atom(term) || !key %in% EVALUABLE) prolog_fault(type_error("evaluable", indicator_term(key)))
    values <- lapply(term$arguments, evaluate_arithmetic)
    name <- term$name
    if (length(values) == 1L) {
        result <- if (name == "-") -values[[1L]] else abs(values[[1L]])
    } else {
        left <- values[[1L]]
        right <- values[[2L]]
        if (name %in% c("//", "mod", "rem") && right == 0L) prolog_fault(compound("evaluation_error", atom_term("zero_divisor")))
        if (name == "+") {
            result <- left + right
        } else if (name == "-") {
            result <- left - right
        } else if (name == "*") {
            result <- left * right
        } else if (name == "//") {
            result <- quotient(left, right)
        } else if (name %in% c("mod", "rem")) {
            q <- quotient(left, right)
            if (name == "mod" && (left < 0L) != (right < 0L) && left != right * q) q <- q - 1L
            result <- left - right * q
        } else if (name == "min") {
            result <- if (left < right) left else right
        } else result <- if (left > right) left else right
    }
    checked_integer(result)
}
require_integer <- function(term) {
    term <- dereference(term)
    if (is_variable(term)) prolog_fault(atom_term("instantiation_error"))
    if (!is_integer(term)) prolog_fault(type_error("integer", term))
    term$value
}
require_atom <- function(term) {
    term <- dereference(term)
    if (is_variable(term)) prolog_fault(atom_term("instantiation_error"))
    if (!is_atom(term)) prolog_fault(type_error("atom", term))
    term$name
}
require_list <- function(term) {
    parts <- list_parts(term)
    if (is_variable(parts$tail)) prolog_fault(atom_term("instantiation_error"))
    if (!is_atom(parts$tail, "[]")) prolog_fault(type_error("list", term))
    parts$elements
}
execute_deterministic <- function(goal, trail, output) {
    name <- indicator_parts(indicator(goal))$name
    args <- if (is_compound(goal)) lapply(goal$arguments, dereference) else list()
    if (name == "true") return(TRUE)
    if (name %in% c("fail", "false")) return(FALSE)
    if (name == "=") return(unify(trail, args[[1L]], args[[2L]]))
    if (name == "\\=") {
        mark <- trail_mark(trail)
        result <- unify(trail, args[[1L]], args[[2L]])
        undo(trail, mark)
        return(!result)
    }
    if (name %in% c("==", "\\==")) {
        result <- identical_terms(args[[1L]], args[[2L]])
        return(if (name == "==") result else !result)
    }
    if (name %in% c("var", "nonvar", "atom", "number", "integer", "atomic", "compound", "callable", "is_list")) {
        term <- args[[1L]]
        if (name == "var") return(is_variable(term))
        if (name == "nonvar") return(!is_variable(term))
        if (name == "atom") return(is_atom(term))
        if (name %in% c("number", "integer")) return(is_integer(term))
        if (name == "atomic") return(is_atom(term) || is_integer(term))
        if (name == "compound") return(is_compound(term))
        if (name == "callable") return(is_atom(term) || is_compound(term))
        return(is_atom(list_parts(term)$tail, "[]"))
    }
    if (name == "is") return(unify(trail, args[[1L]], integer_term(evaluate_arithmetic(args[[2L]]))))
    if (name %in% c("=:=", "=\\=", "<", ">", "=<", ">=")) {
        left <- evaluate_arithmetic(args[[1L]])
        right <- evaluate_arithmetic(args[[2L]])
        return(switch(name, "=:=" = left == right, "=\\=" = left != right, "<" = left < right, ">" = left > right, "=<" = left <= right, ">=" = left >= right))
    }
    if (name == "functor") {
        term <- args[[1L]]
        functor <- args[[2L]]
        count <- args[[3L]]
        if (!is_variable(term)) {
            if (is_compound(term)) return(unify(trail, functor, atom_term(term$name)) && unify(trail, count, integer_term(length(term$arguments))))
            return(unify(trail, functor, term) && unify(trail, count, integer_term(0L)))
        }
        if (is_variable(functor) || is_variable(count)) prolog_fault(atom_term("instantiation_error"))
        if (is_compound(functor)) prolog_fault(type_error("atomic", functor))
        if (!is_integer(count)) prolog_fault(type_error("integer", count))
        if (count$value < 0L) prolog_fault(domain_error("not_less_than_zero", count))
        if (count$value > 255L) prolog_fault(compound("representation_error", atom_term("max_arity")))
        if (count$value == 0L) return(unify(trail, term, functor))
        if (is_integer(functor)) prolog_fault(type_error("atom", functor))
        return(unify(trail, term, compound_term(functor$name, lapply(seq_len(as.integer(count$value)), function(unused) variable_term()))))
    }
    if (name == "arg") {
        number <- args[[1L]]
        term <- args[[2L]]
        value <- args[[3L]]
        if (is_variable(number) || is_variable(term)) prolog_fault(atom_term("instantiation_error"))
        if (!is_integer(number)) prolog_fault(type_error("integer", number))
        if (!is_compound(term)) prolog_fault(type_error("compound", term))
        return(number$value >= 1L && number$value <= length(term$arguments) && unify(trail, term$arguments[[as.integer(number$value)]], value))
    }
    if (name == "=..") {
        term <- args[[1L]]
        sequence <- args[[2L]]
        if (is_compound(term)) return(unify(trail, make_list(c(list(atom_term(term$name)), term$arguments)), sequence))
        if (!is_variable(term)) return(unify(trail, make_list(list(term)), sequence))
        elements <- require_list(sequence)
        if (!length(elements)) prolog_fault(domain_error("non_empty_list", NIL))
        head <- dereference(elements[[1L]])
        if (is_variable(head)) prolog_fault(atom_term("instantiation_error"))
        if (length(elements) == 1L) {
            if (is_compound(head)) prolog_fault(type_error("atomic", head))
            return(unify(trail, term, head))
        }
        if (!is_atom(head)) prolog_fault(type_error("atom", head))
        if (length(elements) > 256L) prolog_fault(compound("representation_error", atom_term("max_arity")))
        return(unify(trail, term, compound_term(head$name, elements[-1L])))
    }
    if (name == "copy_term") return(unify(trail, copy_term(args[[1L]]), args[[2L]]))
    if (name == "atom_length") {
        atom <- require_atom(args[[1L]])
        if (!is_variable(args[[2L]]) && !is_integer(args[[2L]])) prolog_fault(type_error("integer", args[[2L]]))
        return(unify(trail, integer_term(nchar(atom)), args[[2L]]))
    }
    if (name == "atom_chars") {
        atom <- args[[1L]]
        sequence <- args[[2L]]
        if (!is_variable(atom)) {
            text <- require_atom(atom)
            return(unify(trail, sequence, make_list(lapply(strsplit(text, "", fixed = TRUE)[[1L]], atom_term))))
        }
        characters <- character()
        for (element in require_list(sequence)) {
            character <- dereference(element)
            if (is_variable(character)) prolog_fault(atom_term("instantiation_error"))
            if (!is_atom(character) || nchar(character$name) != 1L) prolog_fault(type_error("character", character))
            characters <- c(characters, character$name)
        }
        return(unify(trail, atom, atom_term(paste0(characters, collapse = ""))))
    }
    if (name %in% c("write", "writeq")) output(args[[1L]], name == "writeq") else output(NULL, FALSE)
    TRUE
}
