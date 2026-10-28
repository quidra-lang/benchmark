source("schema_io.R")
source("bitstream.R")
source("encoding.R")
source("query.R")

SCAN_COUNTS <- c(
    "row_groups_read",
    "row_groups_skipped",
    "pages_read",
    "pages_skipped",
    "pages_unneeded",
    "dictionary_pages_read",
    "bytes_read",
    "rows_scanned",
    "rows_matched"
)
UNKNOWN_CELL <- new.env(parent = emptyenv())

scalar_compare <- function(first, second) {
    if (!is.character(first)) return(if (first < second) -1L else if (first > second) 1L else 0L)
    left <- utf8ToInt(first)
    right <- utf8ToInt(second)
    for (index in seq_len(min(length(left), length(right)))) {
        if (left[index] != right[index]) return(if (left[index] < right[index]) -1L else 1L)
    }
    if (length(left) < length(right)) -1L else if (length(left) > length(right)) 1L else 0L
}

scalar_extreme <- function(values, maximum = FALSE) {
    result <- values[[1L]]
    for (value in values) {
        comparison <- scalar_compare(value, result)
        if ((!maximum && comparison < 0L) || (maximum && comparison > 0L)) result <- value
    }
    result
}

column_statistics <- function(values) {
    present <- Filter(Negate(is.null), values)
    if (!length(present)) NULL else list(scalar_extreme(present), scalar_extreme(present, TRUE))
}

statistics_text <- function(column, bounds) {
    if (is.null(bounds)) "stats none" else paste(
        "min",
        value_text(column$kind, bounds[[1L]]),
        "max",
        value_text(column$kind, bounds[[2L]])
    )
}

method_list <- function(methods) paste(ENCODING_METHODS[methods + 1L], collapse = ",")
column_line <- function(index, column) sprintf(
    "column %d %s %s %s",
    index,
    column$name,
    column$kind,
    if (column$nullable) "NULLABLE" else "REQUIRED"
)

build_page <- function(column, kind, method, values, dictionary = list()) {
    if (kind == 1L) {
        body <- encode_values(column$kind, 0L, values)
        nulls <- 0L
        bounds <- NULL
    } else {
        present <- Filter(Negate(is.null), values)
        nulls <- length(values) - length(present)
        bounds <- column_statistics(values)
        body <- integer()
        if (column$nullable) {
            levels <- hybrid_encode(as.integer(!vapply(values, is.null, FALSE)), 1L)
            body <- c(integer_bytes(length(levels)), levels)
        }
        body <- c(body, encode_values(column$kind, method, present, dictionary))
    }
    c(
        kind,
        method,
        uleb_bytes(length(values)),
        uleb_bytes(nulls),
        uleb_bytes(length(body)),
        integer_bytes(adler32(body)),
        encode_statistics(column$kind, bounds),
        body
    )
}

build_chunk <- function(column, values, method, page_size, dictionary_limit) {
    pages <- lapply(
        seq.int(1L, length(values), by = page_size),
        function(start) values[start:min(start + page_size - 1L, length(values))]
    )
    dictionary <- list()
    dictionary_pages <- 0L
    if (method == 1L) {
        dictionary_bytes <- 0L
        for (page in pages) {
            additions <- list()
            proposed <- dictionary
            for (value in page) {
                if (!is.null(value) && !any(vapply(proposed, function(item) identical(item, value), FALSE))) {
                    additions[[length(additions) + 1L]] <- value
                    proposed[[length(proposed) + 1L]] <- value
                }
            }
            bytes <- dictionary_bytes + length(encode_values(column$kind, 0L, additions))
            if (bytes > dictionary_limit) break
            dictionary <- proposed
            dictionary_bytes <- bytes
            dictionary_pages <- dictionary_pages + 1L
        }
        if (!length(dictionary)) dictionary_pages <- 0L
    }
    data <- integer()
    methods <- integer()
    if (dictionary_pages > 0L) data <- c(data, build_page(column, 1L, 0L, dictionary))
    for (number in seq_along(pages)) {
        selected <- method
        if (method == 1L) selected <- if (number <= dictionary_pages) 1L else 0L
        methods <- union(methods, selected)
        data <- c(data, build_page(column, 0L, selected, pages[[number]], dictionary))
    }
    list(
        data = data,
        size = length(data),
        methods = sort(methods),
        has_dictionary = dictionary_pages > 0L,
        page_count = length(pages),
        nulls = sum(vapply(values, is.null, FALSE)),
        statistics = column_statistics(values),
        fallback = if (method == 1L) length(pages) - dictionary_pages else 0L
    )
}

build_file <- function(columns, rows, options) {
    data <- ascii_bytes("MPTC")
    groups <- list()
    report <- "row_group,column,encoding,bytes,fallback_pages,chosen"
    for (first_row in seq.int(1L, length(rows), by = options$row_group_size)) {
        group_rows <- rows[first_row:min(first_row + options$row_group_size - 1L, length(rows))]
        chunks <- list()
        number <- length(groups)
        for (index in seq_along(columns)) {
            column <- columns[[index]]
            values <- lapply(group_rows, function(row) row[[index]])
            candidate_methods <- ENCODING_CANDIDATES[[column$kind]]
            candidates <- lapply(
                candidate_methods,
                function(method) build_chunk(
                    column,
                    values,
                    method,
                    options$page_size,
                    options$dictionary_limit
                )
            )
            names(candidates) <- as.character(candidate_methods)
            requested <- options$encoding[[column$name]]
            if (requested == "AUTO") {
                chosen <- candidate_methods[which.min(vapply(
                    candidates,
                    function(candidate) candidate$size,
                    0L
                ))]
            } else {
                chosen <- match(requested, ENCODING_METHODS) - 1L
                if (chosen == 1L && !candidates[[as.character(chosen)]]$has_dictionary) chosen <- 0L
            }
            for (method in candidate_methods) {
                candidate <- candidates[[as.character(method)]]
                report <- c(
                    report,
                    sprintf(
                        "%d,%s,%s,%d,%d,%s",
                        number,
                        column$name,
                        ENCODING_METHODS[method + 1L],
                        candidate$size,
                        candidate$fallback,
                        if (method == chosen) "yes" else "no"
                    )
                )
            }
            chunk <- candidates[[as.character(chosen)]]
            chunk$offset <- length(data)
            data <- c(data, chunk$data)
            chunks[[index]] <- chunk
        }
        groups[[length(groups) + 1L]] <- list(rows = length(group_rows), chunks = chunks)
    }
    footer <- c(uleb_bytes(1L), uleb_bytes(length(columns)))
    for (column in columns) footer <- c(
        footer,
        uleb_bytes(nchar(column$name)),
        ascii_bytes(column$name),
        match(column$kind, COLUMN_TYPES) - 1L,
        as.integer(column$nullable)
    )
    footer <- c(footer, uleb_bytes(length(rows)), uleb_bytes(length(groups)))
    for (group in groups) {
        footer <- c(footer, uleb_bytes(group$rows))
        for (index in seq_along(columns)) {
            chunk <- group$chunks[[index]]
            footer <- c(
                footer,
                uleb_bytes(chunk$offset),
                uleb_bytes(chunk$size),
                uleb_bytes(length(chunk$methods)),
                chunk$methods,
                as.integer(chunk$has_dictionary),
                uleb_bytes(chunk$page_count),
                uleb_bytes(chunk$nulls),
                encode_statistics(columns[[index]]$kind, chunk$statistics)
            )
        }
    }
    list(
        data = as.integer(c(data, footer, integer_bytes(length(footer)), ascii_bytes("MPTC"))),
        report = report
    )
}

parse_file <- function(data) {
    footer_size <- read_integer(new_byte_reader(data, length(data) - 8L))
    footer_offset <- length(data) - 8L - footer_size
    reader <- new_byte_reader(data, footer_offset)
    version <- read_uleb(reader)
    columns <- lapply(seq_len(read_uleb(reader)), function(index) {
        name <- ascii_text(read_bytes(reader, read_uleb(reader)))
        kind <- COLUMN_TYPES[read_byte(reader) + 1L]
        list(name = name, kind = kind, nullable = read_byte(reader) == 1L)
    })
    row_count <- read_uleb(reader)
    group_count <- read_uleb(reader)
    groups <- list()
    first_row <- 0L
    for (number in seq_len(group_count)) {
        count <- read_uleb(reader)
        chunks <- list()
        for (index in seq_along(columns)) {
            column <- columns[[index]]
            offset <- read_uleb(reader)
            bytes <- read_uleb(reader)
            methods <- vapply(seq_len(read_uleb(reader)), function(item) read_byte(reader), 0L)
            has_dictionary <- read_byte(reader) == 1L
            page_count <- read_uleb(reader)
            nulls <- read_uleb(reader)
            bounds <- decode_statistics(reader, column$kind)
            page_reader <- new_byte_reader(data, offset)
            pages <- list()
            while (page_reader$position < offset + bytes) {
                start <- page_reader$position
                kind <- read_byte(page_reader)
                method <- read_byte(page_reader)
                values <- read_uleb(page_reader)
                page_nulls <- read_uleb(page_reader)
                body_size <- read_uleb(page_reader)
                checksum <- read_integer(page_reader)
                statistics <- decode_statistics(page_reader, column$kind)
                header_size <- page_reader$position - start
                pages[[length(pages) + 1L]] <- list(
                    offset = start,
                    kind = kind,
                    method = method,
                    values = values,
                    nulls = page_nulls,
                    body_size = body_size,
                    checksum = checksum,
                    statistics = statistics,
                    header_size = header_size,
                    body_offset = page_reader$position,
                    size = header_size + body_size
                )
                page_reader$position <- page_reader$position + body_size
            }
            dictionary <- if (has_dictionary) pages[[1L]] else NULL
            data_pages <- if (has_dictionary) pages[-1L] else pages
            chunks[[index]] <- list(
                offset = offset,
                size = bytes,
                methods = methods,
                has_dictionary = has_dictionary,
                page_count = page_count,
                nulls = nulls,
                statistics = bounds,
                dictionary = dictionary,
                pages = data_pages
            )
        }
        groups[[number]] <- list(rows = count, first_row = first_row, chunks = chunks)
        first_row <- first_row + count
    }
    list(
        data = data,
        version = version,
        columns = columns,
        rows = row_count,
        groups = groups,
        footer_size = footer_size,
        footer_offset = footer_offset
    )
}

page_body <- function(file, page) file$data[page$body_offset + seq_len(page$body_size)]
decode_dictionary <- function(file, column, page) decode_values(
    new_byte_reader(page_body(file, page)),
    column$kind,
    0L,
    page$values
)

decode_page <- function(file, column, page, dictionary = list()) {
    reader <- new_byte_reader(page_body(file, page))
    levels <- if (column$nullable) hybrid_decode(
        new_byte_reader(read_bytes(reader, read_integer(reader))),
        1L,
        page$values
    ) else rep(1L, page$values)
    values <- decode_values(reader, column$kind, page$method, sum(levels == 1L), dictionary)
    result <- rep(list(NULL), length(levels))
    index <- 1L
    for (row in seq_along(levels)) {
        if (levels[row] == 1L) {
            result[row] <- values[index]
            index <- index + 1L
        }
    }
    result
}

value_equal <- function(first, second) {
    if (is.null(first) || is.null(second)) return(is.null(first) && is.null(second))
    first == second
}

verify_and_describe <- function(file, original) {
    columns <- file$columns
    lines <- c(
        sprintf(
            "file bytes %d footer_offset %d footer_bytes %d",
            length(file$data),
            file$footer_offset,
            file$footer_size
        ),
        sprintf(
            "table version %d rows %d columns %d row_groups %d",
            file$version,
            file$rows,
            length(columns),
            length(file$groups)
        )
    )
    for (index in seq_along(columns)) lines <- c(lines, column_line(index - 1L, columns[[index]]))
    summaries <- lapply(
        columns,
        function(column) list(bytes = 0L, data_pages = 0L, dictionary_pages = 0L, methods = integer())
    )
    cells <- nulls <- mismatches <- checksum_errors <- 0L
    for (group_index in seq_along(file$groups)) {
        group <- file$groups[[group_index]]
        number <- group_index - 1L
        bytes <- sum(vapply(group$chunks, function(chunk) chunk$size, 0))
        lines <- c(
            lines,
            sprintf("row_group %d rows %d first_row %d bytes %d", number, group$rows, group$first_row, bytes)
        )
        for (index in seq_along(columns)) {
            column <- columns[[index]]
            chunk <- group$chunks[[index]]
            lines <- c(
                lines,
                sprintf(
                    "chunk %d %s offset %d size %d encodings %s dictionary %s pages %d nulls %d %s",
                    number,
                    column$name,
                    chunk$offset,
                    chunk$size,
                    method_list(chunk$methods),
                    if (chunk$has_dictionary) "yes" else "no",
                    chunk$page_count,
                    chunk$nulls,
                    statistics_text(column, chunk$statistics)
                )
            )
            summary <- summaries[[index]]
            summary$bytes <- summary$bytes + chunk$size
            summary$data_pages <- summary$data_pages + chunk$page_count
            summary$dictionary_pages <- summary$dictionary_pages + as.integer(chunk$has_dictionary)
            summary$methods <- union(summary$methods, chunk$methods)
            summaries[[index]] <- summary
            dictionary <- list()
            if (!is.null(chunk$dictionary)) {
                page <- chunk$dictionary
                checksum_errors <- checksum_errors + as.integer(adler32(page_body(
                    file,
                    page
                )) != page$checksum)
                dictionary <- decode_dictionary(file, column, page)
                lines <- c(
                    lines,
                    sprintf(
                        "page %d %s dict offset %d header %d body %d checksum %s entries %d",
                        number,
                        column$name,
                        page$offset,
                        page$header_size,
                        page$body_size,
                        hex_checksum(page$checksum),
                        page$values
                    )
                )
            }
            row_number <- group$first_row + 1L
            for (page_index in seq_along(chunk$pages)) {
                page <- chunk$pages[[page_index]]
                checksum_errors <- checksum_errors + as.integer(adler32(page_body(
                    file,
                    page
                )) != page$checksum)
                lines <- c(
                    lines,
                    sprintf(
                        "page %d %s %d offset %d header %d body %d checksum %s encoding %s values %d nulls %d %s",
                        number,
                        column$name,
                        page_index - 1L,
                        page$offset,
                        page$header_size,
                        page$body_size,
                        hex_checksum(page$checksum),
                        ENCODING_METHODS[page$method + 1L],
                        page$values,
                        page$nulls,
                        statistics_text(column, page$statistics)
                    )
                )
                for (value in decode_page(file, column, page, dictionary)) {
                    cells <- cells + 1L
                    nulls <- nulls + as.integer(is.null(value))
                    mismatches <- mismatches + as.integer(!value_equal(
                        value,
                        original[[row_number]][[index]]
                    ))
                    row_number <- row_number + 1L
                }
            }
        }
    }
    for (index in seq_along(columns)) {
        summary <- summaries[[index]]
        lines <- c(
            lines,
            sprintf(
                "summary %s bytes %d data_pages %d dictionary_pages %d encodings %s",
                columns[[index]]$name,
                summary$bytes,
                summary$data_pages,
                summary$dictionary_pages,
                method_list(sort(summary$methods))
            )
        )
    }
    c(
        lines,
        sprintf(
            "roundtrip %s cells %d nulls %d mismatches %d checksum_errors %d",
            if (mismatches == 0L && checksum_errors == 0L) "ok" else "failed",
            cells,
            nulls,
            mismatches,
            checksum_errors
        )
    )
}

condition_leaves <- function(tree) {
    if (is.null(tree)) return(list())
    if (tree$operation == "NOT") return(condition_leaves(tree$left))
    if (tree$operation %in% c("AND", "OR")) return(c(
        condition_leaves(tree$left),
        condition_leaves(tree$right)
    ))
    list(tree)
}

convert_condition <- function(tree, columns, indices) {
    if (is.null(tree)) return(NULL)
    operation <- tree$operation
    if (operation == "NOT") return(list(
        operation = operation,
        left = convert_condition(tree$left, columns, indices)
    ))
    if (operation %in% c("AND", "OR")) return(list(
        operation = operation,
        left = convert_condition(tree$left, columns, indices),
        right = convert_condition(tree$right, columns, indices)
    ))
    index <- indices[[tree$column]]
    values <- lapply(
        tree$literals,
        function(literal) if (columns[[index]]$kind == "DATE") day_number(literal$value) else literal$value
    )
    list(operation = operation, column = index, literals = values)
}

item_header <- function(item) {
    if (item$operation == "COLUMN") return(item$name)
    if (item$operation == "COUNT_DISTINCT") return(paste0("COUNT(DISTINCT ", item$name, ")"))
    paste0(item$operation, "(", if (is.null(item$name)) "*" else item$name, ")")
}

check_query <- function(raw, columns) {
    indices <- setNames(seq_along(columns), vapply(columns, function(column) column$name, ""))
    items <- raw$items
    if (is.null(items)) items <- lapply(
        columns,
        function(column) list(operation = "COLUMN", name = column$name)
    )
    leaves <- condition_leaves(raw$condition)
    names <- unlist(lapply(items, function(item) item$name), use.names = FALSE)
    names <- c(names, vapply(leaves, function(leaf) leaf$column, ""), raw$group, raw$order)
    failure <- function(code) list(error = code, plan = NULL)
    if (any(!names %in% names(indices))) return(failure("unknown_column"))
    for (leaf in leaves) {
        kind <- columns[[indices[[leaf$column]]]]$kind
        expected <- if (kind == "DATE") "STRING" else kind
        if (any(vapply(
            leaf$literals,
            function(literal) literal$kind != expected,
            FALSE
        ))) return(failure("type_mismatch"))
    }
    if (any(vapply(
        items,
        function(item) item$operation %in% c("SUM", "AVG") && columns[[indices[[item$name]]]]$kind != "INT",
        FALSE
    ))) return(failure("bad_aggregate"))
    aggregate <- !is.null(raw$group) || any(vapply(items, function(item) item$operation != "COLUMN", FALSE))
    if (aggregate && any(vapply(
        items,
        function(item) item$operation == "COLUMN" && (is.null(raw$group) || item$name != raw$group),
        FALSE
    ))) return(failure("not_grouped"))
    if (aggregate && !is.null(raw$order)) return(failure("bad_order"))
    plan <- list(
        items = lapply(
            items,
            function(item) list(
                operation = item$operation,
                index = if (is.null(item$name)) NULL else indices[[item$name]]
            )
        ),
        headers = vapply(items, item_header, ""),
        condition = convert_condition(raw$condition, columns, indices),
        group = if (is.null(raw$group)) NULL else indices[[raw$group]],
        order = if (is.null(raw$order)) NULL else indices[[raw$order]],
        descending = raw$descending,
        limit = raw$limit,
        aggregate = aggregate,
        needed = sort(unique(unname(indices[names]))),
        condition_columns = sort(unique(vapply(leaves, function(leaf) indices[[leaf$column]], 0L)))
    )
    list(error = NULL, plan = plan)
}

logical_not <- function(value) if (value == 2L) 2L else 1L - value
logical_pair <- function(operation, first, second) {
    if (operation == "AND") {
        if (first == 0L || second == 0L) return(0L)
        return(if (first == 2L || second == 2L) 2L else 1L)
    }
    if (first == 1L || second == 1L) return(1L)
    if (first == 2L || second == 2L) 2L else 0L
}

compare_value <- function(operation, value, literals) {
    if (operation == "IS_NULL") return(as.integer(is.null(value)))
    if (operation == "IS_NOT_NULL") return(as.integer(!is.null(value)))
    if (is.null(value)) return(2L)
    if (operation == "BETWEEN") return(as.integer(scalar_compare(literals[[1L]], value) <= 0L && scalar_compare(
        value,
        literals[[2L]]
    ) <= 0L))
    if (operation == "IN") return(as.integer(any(vapply(
        literals,
        function(literal) scalar_compare(value, literal) == 0L,
        FALSE
    ))))
    comparison <- scalar_compare(value, literals[[1L]])
    as.integer(switch(
        operation,
        "=" = comparison == 0L,
        "<>" = comparison != 0L,
        "<" = comparison < 0L,
        "<=" = comparison <= 0L,
        ">" = comparison > 0L,
        ">=" = comparison >= 0L
    ))
}

evaluate_condition <- function(tree, row) {
    if (is.null(tree)) return(1L)
    operation <- tree$operation
    if (operation == "NOT") return(logical_not(evaluate_condition(tree$left, row)))
    if (operation %in% c("AND", "OR")) return(logical_pair(
        operation,
        evaluate_condition(tree$left, row),
        evaluate_condition(tree$right, row)
    ))
    compare_value(operation, row[[tree$column]], tree$literals)
}

range_possibilities <- function(operation, low, high, literals) {
    le <- function(a, b) scalar_compare(a, b) <= 0L
    lt <- function(a, b) scalar_compare(a, b) < 0L
    equal <- function(a, b) scalar_compare(a, b) == 0L
    if (operation == "BETWEEN") {
        first <- literals[[1L]]
        last <- literals[[2L]]
        return(c(le(low, last) && le(first, high) && le(first, last), lt(low, first) || lt(last, high)))
    }
    if (operation == "IN") return(c(
        any(vapply(literals, function(value) le(low, value) && le(value, high), FALSE)),
        !(equal(low, high) && any(vapply(literals, function(value) equal(low, value), FALSE)))
    ))
    value <- literals[[1L]]
    switch(operation,
        "=" = c(le(low, value) && le(value, high), !(equal(low, value) && equal(high, value))),
        "<>" = c(!(equal(low, value) && equal(high, value)), le(low, value) && le(value, high)),
        "<" = c(lt(low, value), le(value, high)),
        "<=" = c(le(low, value), lt(value, high)),
        ">" = c(lt(value, high), le(low, value)),
        ">=" = c(le(value, high), lt(low, value)))
}

zone_values <- function(tree, zones) {
    operation <- tree$operation
    if (operation == "NOT") return(unique(vapply(zone_values(tree$left, zones), logical_not, 0L)))
    if (operation %in% c("AND", "OR")) {
        first <- zone_values(tree$left, zones)
        second <- zone_values(tree$right, zones)
        return(unique(unlist(
            lapply(
                first,
                function(left) vapply(second, function(right) logical_pair(operation, left, right), 0L)
            ),
            use.names = FALSE
        )))
    }
    zone <- zones[[as.character(tree$column)]]
    values <- integer()
    if (operation %in% c("IS_NULL", "IS_NOT_NULL")) {
        if (zone$nulls > 0L) values <- c(values, as.integer(operation == "IS_NULL"))
        if (zone$nulls < zone$count) values <- c(values, as.integer(operation == "IS_NOT_NULL"))
        return(unique(values))
    }
    if (zone$nulls > 0L) values <- c(values, 2L)
    if (!is.null(zone$bounds)) {
        possibilities <- range_possibilities(operation, zone$bounds[[1L]], zone$bounds[[2L]], tree$literals)
        if (possibilities[1L]) values <- c(values, 1L)
        if (possibilities[2L]) values <- c(values, 0L)
    }
    unique(values)
}

read_scan_page <- function(file, group_index, index, page_index, dictionaries, counts) {
    column <- file$columns[[index]]
    chunk <- file$groups[[group_index]]$chunks[[index]]
    page <- chunk$pages[[page_index]]
    dictionary <- list()
    if (page$method == 1L) {
        key <- paste(group_index, index)
        if (!exists(key, dictionaries, inherits = FALSE)) {
            dictionaries[[key]] <- decode_dictionary(file, column, chunk$dictionary)
            counts$dictionary_pages_read <- counts$dictionary_pages_read + 1L
            counts$bytes_read <- counts$bytes_read + chunk$dictionary$size
        }
        dictionary <- dictionaries[[key]]
    }
    counts$pages_read <- counts$pages_read + 1L
    counts$bytes_read <- counts$bytes_read + page$size
    decode_page(file, column, page, dictionary)
}

scan_file <- function(file, plan) {
    counts <- new.env(parent = emptyenv())
    for (name in SCAN_COUNTS) counts[[name]] <- 0L
    records <- matched <- list()
    dictionaries <- new.env(parent = emptyenv())
    condition <- plan$condition
    condition_columns <- plan$condition_columns
    remaining <- setdiff(plan$needed, condition_columns)
    for (group_index in seq_along(file$groups)) {
        group <- file$groups[[group_index]]
        zones <- list()
        for (index in condition_columns) {
            chunk <- group$chunks[[index]]
            zones[[as.character(index)]] <- list(
                bounds = chunk$statistics,
                nulls = chunk$nulls,
                count = group$rows
            )
        }
        if (!is.null(condition) && !1L %in% zone_values(condition, zones)) {
            counts$row_groups_skipped <- counts$row_groups_skipped + 1L
            records[group_index] <- list(NULL)
            next
        }
        counts$row_groups_read <- counts$row_groups_read + 1L
        if (!length(plan$needed)) {
            counts$rows_scanned <- counts$rows_scanned + group$rows
            matched <- c(
                matched,
                lapply(seq_len(group$rows), function(row) rep(list(NULL), length(file$columns)))
            )
            records[[group_index]] <- "-"
            next
        }
        record <- character()
        for (page_index in seq_len(group$chunks[[1L]]$page_count)) {
            zones <- list()
            for (index in condition_columns) {
                page <- group$chunks[[index]]$pages[[page_index]]
                zones[[as.character(index)]] <- list(
                    bounds = page$statistics,
                    nulls = page$nulls,
                    count = page$values
                )
            }
            if (!is.null(condition) && !1L %in% zone_values(condition, zones)) {
                counts$pages_skipped <- counts$pages_skipped + length(plan$needed)
                record <- c(record, "s")
                next
            }
            row_count <- group$chunks[[1L]]$pages[[page_index]]$values
            counts$rows_scanned <- counts$rows_scanned + row_count
            rows <- lapply(seq_len(row_count), function(row) rep(list(NULL), length(file$columns)))
            for (index in condition_columns) {
                values <- read_scan_page(file, group_index, index, page_index, dictionaries, counts)
                for (row in seq_along(rows)) rows[[row]][index] <- values[row]
            }
            selected <- which(vapply(rows, function(row) evaluate_condition(condition, row) == 1L, FALSE))
            if (!length(selected) && length(remaining)) {
                counts$pages_unneeded <- counts$pages_unneeded + length(remaining)
                record <- c(record, "u")
                next
            }
            for (index in remaining) {
                values <- read_scan_page(file, group_index, index, page_index, dictionaries, counts)
                for (row in seq_along(rows)) rows[[row]][index] <- values[row]
            }
            matched <- c(matched, rows[selected])
            record <- c(record, "r")
        }
        records[[group_index]] <- paste0(record, collapse = "")
    }
    counts$rows_matched <- length(matched)
    list(matched = matched, counts = counts, records = records)
}

integer_gcd <- function(first, second) {
    first <- abs(first)
    while (second != 0) {
        remainder <- first %% second
        first <- second
        second <- remainder
    }
    first
}

aggregate_item <- function(columns, item, rows, key) {
    operation <- item$operation
    index <- item$index
    if (operation == "COLUMN") return(value_text(columns[[index]]$kind, key))
    if (operation == "COUNT" && is.null(index)) return(as.character(length(rows)))
    values <- Filter(Negate(is.null), lapply(rows, function(row) row[[index]]))
    if (operation == "COUNT") return(as.character(length(values)))
    if (operation == "COUNT_DISTINCT") return(as.character(length(unique(values))))
    if (!length(values)) return("NULL")
    if (operation == "SUM") return(sprintf("%.0f", sum(unlist(values))))
    if (operation == "AVG") {
        total <- sum(unlist(values))
        divisor <- integer_gcd(total, length(values))
        numerator <- total %/% divisor
        denominator <- length(values) %/% divisor
        return(if (denominator == 1L) sprintf("%.0f", numerator) else sprintf(
            "%.0f/%.0f",
            numerator,
            denominator
        ))
    }
    value <- scalar_extreme(values, operation == "MAX")
    value_text(columns[[index]]$kind, value)
}

ordered_rows <- function(rows, index, kind, descending = FALSE) {
    if (!length(rows)) return(rows)
    template <- if (kind == "STRING") NA_character_ else if (kind == "BOOL") NA else NA_real_
    values <- vapply(rows, function(row) if (is.null(row[[index]])) template else row[[index]], template)
    rows[order(values, decreasing = descending, na.last = descending, method = "radix")]
}

build_result <- function(columns, plan, matched) {
    if (!plan$aggregate) {
        kind <- "rows"
        arranged <- matched
        if (!is.null(plan$order)) arranged <- ordered_rows(
            matched,
            plan$order,
            columns[[plan$order]]$kind,
            plan$descending
        )
        output <- vapply(
            arranged,
            function(row) paste(
                vapply(
                    plan$items,
                    function(item) value_text(columns[[item$index]]$kind, row[[item$index]]),
                    ""
                ),
                collapse = ","
            ),
            ""
        )
    } else {
        groups <- list()
        if (is.null(plan$group)) {
            kind <- "aggregate"
            groups <- list(list(key = NULL, rows = matched))
        } else {
            kind <- "grouped"
            arranged <- ordered_rows(matched, plan$group, columns[[plan$group]]$kind)
            for (row in arranged) {
                key <- row[[plan$group]]
                last <- length(groups)
                if (last == 0L || !value_equal(groups[[last]]$key, key)) {
                    groups[[last + 1L]] <- list(key = key, rows = list(row))
                } else {
                    groups[[last]]$rows[[length(groups[[last]]$rows) + 1L]] <- row
                }
            }
        }
        output <- vapply(
            groups,
            function(group) paste(
                vapply(plan$items, function(item) aggregate_item(columns, item, group$rows, group$key), ""),
                collapse = ","
            ),
            ""
        )
    }
    if (!is.null(plan$limit)) output <- head(output, plan$limit)
    list(kind = kind, matched = length(matched), rows = unname(output))
}

counts_text <- function(counts) paste(
    vapply(SCAN_COUNTS, function(name) paste(name, counts[[name]]), ""),
    collapse = " "
)

execute_queries <- function(file, originals, queries) {
    results <- stats_lines <- character()
    totals <- setNames(integer(length(SCAN_COUNTS)), SCAN_COUNTS)
    errors <- checks_ok <- 0L
    columns <- file$columns
    for (number in seq_along(queries)) {
        checked <- check_query(parse_query(queries[number]), columns)
        if (!is.null(checked$error)) {
            line <- sprintf("query %d error %s", number, checked$error)
            results <- c(results, line)
            stats_lines <- c(stats_lines, line)
            errors <- errors + 1L
            next
        }
        plan <- checked$plan
        scanned <- scan_file(file, plan)
        result <- build_result(columns, plan, scanned$matched)
        reference <- Filter(function(row) evaluate_condition(plan$condition, row) == 1L, originals)
        check <- if (identical(result, build_result(columns, plan, reference))) "ok" else "mismatch"
        checks_ok <- checks_ok + as.integer(check == "ok")
        results <- c(
            results,
            sprintf(
                "query %d %s matched %d output %d",
                number,
                result$kind,
                result$matched,
                length(result$rows)
            ),
            paste("columns", paste(plan$headers, collapse = ",")),
            result$rows
        )
        needed <- if (length(plan$needed)) paste(
            vapply(plan$needed, function(index) columns[[index]]$name, ""),
            collapse = ","
        ) else "-"
        stats_lines <- c(
            stats_lines,
            sprintf("query %d columns %s %s check %s", number, needed, counts_text(scanned$counts), check)
        )
        for (index in seq_along(scanned$records)) {
            record <- scanned$records[[index]]
            detail <- if (is.null(record)) "skipped" else paste("pages", record)
            stats_lines <- c(stats_lines, sprintf("query %d row_group %d %s", number, index - 1L, detail))
        }
        for (name in SCAN_COUNTS) totals[name] <- totals[name] + scanned$counts[[name]]
    }
    stats_lines <- c(
        stats_lines,
        sprintf(
            "total queries %d errors %d %s checks_ok %d",
            length(queries),
            errors,
            counts_text(totals),
            checks_ok
        )
    )
    list(results = results, statistics = stats_lines)
}

recover_file <- function(data) {
    file <- parse_file(data)
    columns <- file$columns
    rows <- lapply(seq_len(file$rows), function(row) rep(list(UNKNOWN_CELL), length(columns)))
    lines <- sprintf(
        "file bytes %d rows %d columns %d row_groups %d",
        length(data),
        file$rows,
        length(columns),
        length(file$groups)
    )
    for (index in seq_along(columns)) lines <- c(lines, column_line(index - 1L, columns[[index]]))
    pages_examined <- damaged_count <- lost_pages <- lost_cells <- 0L
    for (group_index in seq_along(file$groups)) {
        group <- file$groups[[group_index]]
        number <- group_index - 1L
        for (index in seq_along(columns)) {
            column <- columns[[index]]
            chunk <- group$chunks[[index]]
            dictionary <- list()
            dictionary_damaged <- FALSE
            pages <- lapply(
                seq_along(chunk$pages),
                function(page_index) list(
                    number = as.character(page_index - 1L),
                    page = chunk$pages[[page_index]]
                )
            )
            if (!is.null(chunk$dictionary)) pages <- c(
                list(list(number = "dict", page = chunk$dictionary)),
                pages
            )
            row_number <- group$first_row + 1L
            for (entry in pages) {
                page_number <- entry$number
                page <- entry$page
                pages_examined <- pages_examined + 1L
                checksum <- adler32(page_body(file, page))
                damaged <- checksum != page$checksum
                if (damaged) {
                    damaged_count <- damaged_count + 1L
                    lines <- c(
                        lines,
                        sprintf(
                            "damaged %d %s %s offset %d stored %s computed %s",
                            number,
                            column$name,
                            page_number,
                            page$offset,
                            hex_checksum(page$checksum),
                            hex_checksum(checksum)
                        )
                    )
                }
                if (page_number == "dict") {
                    dictionary_damaged <- damaged
                    if (!damaged) dictionary <- decode_dictionary(file, column, page)
                    next
                }
                reason <- if (damaged) "checksum" else if (page$method == 1L && dictionary_damaged) "dictionary" else NULL
                if (!is.null(reason)) {
                    lost_pages <- lost_pages + 1L
                    lost_cells <- lost_cells + page$values
                    lines <- c(
                        lines,
                        sprintf(
                            "lost %d %s %s rows %d reason %s",
                            number,
                            column$name,
                            page_number,
                            page$values,
                            reason
                        )
                    )
                } else {
                    values <- decode_page(file, column, page, dictionary)
                    for (offset in seq_along(values)) rows[[row_number + offset - 1L]][index] <- values[offset]
                }
                row_number <- row_number + page$values
            }
        }
    }
    recovered_cells <- file$rows * length(columns) - lost_cells
    lines <- c(
        lines,
        sprintf(
            "summary pages %d damaged %d lost_pages %d lost_cells %d recovered_cells %d",
            pages_examined,
            damaged_count,
            lost_pages,
            lost_cells,
            recovered_cells
        )
    )
    recovered <- paste(vapply(columns, function(column) column$name, ""), collapse = ",")
    for (row in rows) {
        recovered <- c(recovered, paste(vapply(seq_along(columns), function(index) {
            if (identical(row[[index]], UNKNOWN_CELL)) "?" else value_text(
                columns[[index]]$kind,
                row[[index]],
                null = ""
            )
        }, ""), collapse = ","))
    }
    list(lines = lines, recovered = recovered)
}

main <- function() {
    input <- read_inputs()
    built <- build_file(input$columns, input$rows, input$options)
    file <- parse_file(built$data)
    metadata <- verify_and_describe(file, input$rows)
    queries <- execute_queries(file, input$rows, input$queries)
    recovery <- recover_file(input$damaged)
    hex_lines <- vapply(
        seq.int(1L, length(built$data), by = 32L),
        function(start) hex_bytes(built$data[start:min(start + 31L, length(built$data))]),
        ""
    )
    write_outputs(list(
        file.hex = hex_lines,
        metadata.txt = metadata,
        encoding_report.csv = built$report,
        query_results.txt = queries$results,
        query_stats.txt = queries$statistics,
        recovery.txt = recovery$lines,
        recovered.csv = recovery$recovered
    ))
}

main()
