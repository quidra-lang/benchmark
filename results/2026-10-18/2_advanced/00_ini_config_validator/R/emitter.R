MASK <- "********"
number_text <- function(value) if (value == 0) "0" else sprintf("%.0f", value)

string_notation <- function(text) {
    chars <- strsplit(text, "", fixed = TRUE)[[1L]]
    escapes <- setNames(c("\\\\", '\\"', "\\n", "\\t"), c("\\", '"', "\n", "\t"))
    converted <- vapply(chars, function(char) if (char %in% names(escapes)) escapes[[char]] else char, character(1L))
    paste0('"', paste(converted, collapse = ""), '"')
}

value_notation <- function(kind, item, value) {
    if (kind == "list") return(paste0("[", paste(vapply(value, function(value) value_notation(item, "", value), character(1L)), collapse = ", "), "]"))
    if (kind == "string") return(string_notation(value))
    if (kind == "bool") return(if (value) "true" else "false")
    if (kind %in% c("int", "size", "duration")) number_text(value) else value
}

shown <- function(output) if (output$secret) MASK else output$notation
origin_text <- function(origin) paste0(origin$document, ":", origin$line)

normalized_block <- function(profile) {
    lines <- paste0("profile ", profile$name); previous <- NULL
    for (key in key_order(names(profile$outputs))) {
        section <- section_of(key)
        if (!identical(section, previous)) lines <- c(lines, paste0("[", section, "]"))
        lines <- c(lines, paste0(key_name(key), " = ", shown(profile$outputs[[key]])))
        previous <- section
    }
    lines
}

diagnostics_block <- function(profile) {
    lines <- paste0("profile ", profile$name, " errors ", profile$errors, " warnings ", profile$warnings)
    for (diagnostic in profile$diagnostics) lines <- c(lines, paste0(diagnostic$document, ":", diagnostic$line, " ", diagnostic$code, " ", diagnostic$message))
    lines
}

diff_block <- function(diff) {
    lines <- paste0("diff ", diff$first, " -> ", diff$second, ": ", diff$added, " added, ", diff$removed, " removed, ", diff$changed, " changed")
    for (entry in diff$entries) {
        line <- if (entry$sign == "+") {
            paste0("+ ", entry$key, " = ", shown(entry$after))
        } else if (entry$sign == "-") {
            paste0("- ", entry$key, " = ", shown(entry$before))
        } else {
            paste0("~ ", entry$key, ": ", shown(entry$before), " -> ", shown(entry$after))
        }
        lines <- c(lines, line)
    }
    lines
}

report_block <- function(profile) {
    lines <- c(paste0("profile ", profile$name), "includes")
    for (entry in profile$tree) lines <- c(lines, paste0(strrep(" ", 2L + 2L * entry$depth), entry$text))
    lines <- c(lines, "overridden"); found <- FALSE
    for (key in key_order(names(profile$outputs))) {
        history <- profile$outputs[[key]]$definition$history
        if (length(history) >= 2L) {
            found <- TRUE
            lines <- c(lines, paste0("  ", key, ": ", paste(vapply(history, origin_text, character(1L)), collapse = " -> ")))
        }
    }
    if (!found) lines <- c(lines, "  (none)")
    c(lines, paste0("keys ", length(profile$outputs), " documents ", profile$document_keys, " manifest ", profile$manifest_keys, " defaults ", profile$default_keys),
      paste0("dropped ", profile$dropped), paste0("errors ", profile$errors, " warnings ", profile$warnings))
}

write_outputs <- function(directory, profiles, diffs) {
    dir.create(directory, showWarnings = FALSE, recursive = TRUE)
    write_blocks <- function(name, blocks) {
        text <- paste0(paste(vapply(blocks, paste, character(1L), collapse = "\n"), collapse = "\n\n"), "\n")
        connection <- file(file.path(directory, name), "wb")
        writeBin(charToRaw(text), connection)
        close(connection)
    }
    write_blocks("normalized.txt", lapply(profiles, normalized_block))
    write_blocks("diagnostics.txt", lapply(profiles, diagnostics_block))
    write_blocks("diff.txt", lapply(diffs, diff_block))
    write_blocks("report.txt", lapply(profiles, report_block))
}
