include("schema_io.jl")
include("bitstream.jl")
include("encoding.jl")
include("query.jl")

const SCAN_COUNTS = (
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
struct UnknownCell end
const UNKNOWN_CELL = UnknownCell()

function column_statistics(values)
    present = [value for value in values if value !== nothing]
    return isempty(present) ? nothing : Any[minimum(present), maximum(present)]
end

function statistics_text(column, bounds)
    bounds === nothing && return "stats none"
    return "min $(value_text(column.kind, bounds[1])) max $(value_text(column.kind, bounds[2]))"
end

method_list(methods) = join((ENCODING_METHODS[method + 1] for method in methods), ",")
column_line(
    index,
    column
) = "column $index $(column.name) $(column.kind) $(column.nullable ? "NULLABLE" : "REQUIRED")"

function build_page(column, kind, method, values, dictionary=Any[])
    if kind == 1
        body = encode_values(column.kind, 0, values)
        nulls, bounds = 0, nothing
    else
        present = [value for value in values if value !== nothing]
        nulls, bounds = length(values) - length(present), column_statistics(values)
        body = Int[]
        if column.nullable
            levels = hybrid_encode([Int(value !== nothing) for value in values], 1)
            append!(body, integer_bytes(length(levels)))
            append!(body, levels)
        end
        append!(body, encode_values(column.kind, method, present, dictionary))
    end
    header = vcat(
        [kind, method],
        uleb_bytes(length(values)),
        uleb_bytes(nulls),
        uleb_bytes(length(body)),
        integer_bytes(adler32(body)),
        encode_statistics(column.kind, bounds)
    )
    return vcat(header, body)
end

function build_chunk(column, values, method, page_size, dictionary_limit)
    pages = [values[start:min(start + page_size - 1, end)] for start in 1:page_size:length(values)]
    dictionary = Any[]
    dictionary_pages = 0
    if method == 1
        known = Set{Any}()
        dictionary_bytes = 0
        for page in pages
            additions = Any[]
            proposed = copy(known)
            for value in page
                if value !== nothing && !(value in proposed)
                    push!(additions, value)
                    push!(proposed, value)
                end
            end
            bytes = dictionary_bytes + length(encode_values(column.kind, 0, additions))
            bytes > dictionary_limit && break
            append!(dictionary, additions)
            known, dictionary_bytes = proposed, bytes
            dictionary_pages += 1
        end
        isempty(dictionary) && (dictionary_pages = 0)
    end
    data, methods = Int[], Set{Int}()
    dictionary_pages > 0 && append!(data, build_page(column, 1, 0, dictionary))
    for (number, page) in enumerate(pages)
        selected = method == 1 ? (number <= dictionary_pages ? 1 : 0) : method
        push!(methods, selected)
        append!(data, build_page(column, 0, selected, page, dictionary))
    end
    return (
        data=data,
        size=length(data),
        methods=sort!(collect(methods)),
        has_dictionary=dictionary_pages > 0,
        page_count=length(pages),
        nulls=count(isnothing, values),
        statistics=column_statistics(values),
        fallback=method == 1 ? length(pages) - dictionary_pages : 0
    )
end

function build_file(columns, rows, options)
    data = ascii_bytes("MPTC")
    groups = NamedTuple[]
    report = ["row_group,column,encoding,bytes,fallback_pages,chosen"]
    for first_row in 1:options["row_group_size"]:length(rows)
        group_rows = rows[first_row:min(first_row + options["row_group_size"] - 1, end)]
        chunks = NamedTuple[]
        number = length(groups)
        for (index, column) in enumerate(columns)
            values = Any[row[index] for row in group_rows]
            candidates = Dict(method => build_chunk(
                column,
                values,
                method,
                options["page_size"],
                options["dictionary_limit"]
            ) for method in ENCODING_CANDIDATES[column.kind])
            requested = options["encoding"][column.name]
            if requested == "AUTO"
                chosen = argmin(
                    method -> (candidates[method].size, method),
                    collect(ENCODING_CANDIDATES[column.kind])
                )
            else
                chosen = findfirst(==(requested), ENCODING_METHODS) - 1
                chosen == 1 && !candidates[chosen].has_dictionary && (chosen = 0)
            end
            for method in ENCODING_CANDIDATES[column.kind]
                candidate = candidates[method]
                selected = method == chosen ? "yes" : "no"
                push!(
                    report,
                    "$number,$(column.name),$(ENCODING_METHODS[method + 1]),$(candidate.size),$(candidate.fallback),$selected"
                )
            end
            chunk = (; candidates[chosen]..., offset=length(data))
            append!(data, chunk.data)
            push!(chunks, chunk)
        end
        push!(groups, (rows=length(group_rows), chunks=chunks))
    end
    footer = vcat(uleb_bytes(1), uleb_bytes(length(columns)))
    for column in columns
        append!(footer, uleb_bytes(length(column.name)))
        append!(footer, ascii_bytes(column.name))
        append!(footer, [findfirst(==(column.kind), COLUMN_TYPES) - 1, Int(column.nullable)])
    end
    append!(footer, uleb_bytes(length(rows)))
    append!(footer, uleb_bytes(length(groups)))
    for group in groups
        append!(footer, uleb_bytes(group.rows))
        for (column, chunk) in zip(columns, group.chunks)
            append!(footer, uleb_bytes(chunk.offset))
            append!(footer, uleb_bytes(chunk.size))
            append!(footer, uleb_bytes(length(chunk.methods)))
            append!(footer, chunk.methods)
            push!(footer, Int(chunk.has_dictionary))
            append!(footer, uleb_bytes(chunk.page_count))
            append!(footer, uleb_bytes(chunk.nulls))
            append!(footer, encode_statistics(column.kind, chunk.statistics))
        end
    end
    append!(data, footer)
    append!(data, integer_bytes(length(footer)))
    append!(data, ascii_bytes("MPTC"))
    return data, report
end

function parse_file(data)
    footer_size = read_integer!(ByteReader(data, length(data) - 8))
    footer_offset = length(data) - 8 - footer_size
    reader = ByteReader(data, footer_offset)
    version = read_uleb!(reader)
    columns = ColumnSchema[]
    for _ in 1:read_uleb!(reader)
        name = ascii_text(read_bytes!(reader, read_uleb!(reader)))
        kind = COLUMN_TYPES[read_byte!(reader) + 1]
        push!(columns, ColumnSchema(name, kind, read_byte!(reader) == 1))
    end
    row_count = read_uleb!(reader)
    groups = NamedTuple[]
    first_row = 0
    for _ in 1:read_uleb!(reader)
        count = read_uleb!(reader)
        chunks = NamedTuple[]
        for column in columns
            offset, bytes = read_uleb!(reader), read_uleb!(reader)
            methods = [read_byte!(reader) for _ in 1:read_uleb!(reader)]
            has_dictionary = read_byte!(reader) == 1
            page_count, nulls = read_uleb!(reader), read_uleb!(reader)
            bounds = decode_statistics!(reader, column.kind)
            page_reader = ByteReader(data, offset)
            pages = NamedTuple[]
            while page_reader.position < offset + bytes
                start = page_reader.position
                kind, method = read_byte!(page_reader), read_byte!(page_reader)
                values, page_nulls, body_size = read_uleb!(page_reader), read_uleb!(page_reader), read_uleb!(page_reader)
                checksum = read_integer!(page_reader)
                statistics = decode_statistics!(page_reader, column.kind)
                header_size = page_reader.position - start
                push!(
                    pages,
                    (
                        offset=start,
                        kind=kind,
                        method=method,
                        values=values,
                        nulls=page_nulls,
                        body_size=body_size,
                        checksum=checksum,
                        statistics=statistics,
                        header_size=header_size,
                        body_offset=page_reader.position,
                        size=header_size + body_size
                    )
                )
                page_reader.position += body_size
            end
            dictionary = has_dictionary ? pages[1] : nothing
            data_pages = has_dictionary ? pages[2:end] : pages
            push!(
                chunks,
                (
                    offset=offset,
                    size=bytes,
                    methods=methods,
                    has_dictionary=has_dictionary,
                    page_count=page_count,
                    nulls=nulls,
                    statistics=bounds,
                    dictionary=dictionary,
                    pages=data_pages
                )
            )
        end
        push!(groups, (rows=count, first_row=first_row, chunks=chunks))
        first_row += count
    end
    return (; data, version, columns, rows=row_count, groups, footer_size, footer_offset)
end

page_body(file, page) = file.data[page.body_offset + 1:page.body_offset + page.body_size]
decode_dictionary(file, column, page) = decode_values!(
    ByteReader(page_body(file, page)),
    column.kind,
    0,
    page.values
)

function decode_page(file, column, page, dictionary=Any[])
    reader = ByteReader(page_body(file, page))
    levels = column.nullable ? hybrid_decode!(
        ByteReader(read_bytes!(reader, read_integer!(reader))),
        1,
        page.values
    ) : ones(Int, page.values)
    values = decode_values!(reader, column.kind, page.method, count(==(1), levels), dictionary)
    result = Any[]
    index = 1
    for level in levels
        push!(result, level == 1 ? values[index] : nothing)
        level == 1 && (index += 1)
    end
    return result
end

function verify_and_describe(file, original)
    columns = file.columns
    lines = [
        "file bytes $(length(file.data)) footer_offset $(file.footer_offset) footer_bytes $(file.footer_size)",
        "table version $(file.version) rows $(file.rows) columns $(length(columns)) row_groups $(length(file.groups))"
    ]
    append!(lines, [column_line(index - 1, column) for (index, column) in enumerate(columns)])
    summaries = [(
        counts=Dict("bytes" => 0, "data_pages" => 0, "dictionary_pages" => 0),
        methods=Set{Int}()
    ) for _ in columns]
    cells, nulls, mismatches, checksum_errors = 0, 0, 0, 0
    for (group_index, group) in enumerate(file.groups)
        number = group_index - 1
        bytes = sum(chunk.size for chunk in group.chunks)
        push!(lines, "row_group $number rows $(group.rows) first_row $(group.first_row) bytes $bytes")
        for (index, (column, chunk)) in enumerate(zip(columns, group.chunks))
            has_dictionary = chunk.has_dictionary ? "yes" : "no"
            push!(
                lines,
                "chunk $number $(column.name) offset $(chunk.offset) size $(chunk.size) encodings $(method_list(chunk.methods)) dictionary $has_dictionary pages $(chunk.page_count) nulls $(chunk.nulls) $(statistics_text(column, chunk.statistics))"
            )
            summary = summaries[index]
            summary.counts["bytes"] += chunk.size
            summary.counts["data_pages"] += chunk.page_count
            summary.counts["dictionary_pages"] += Int(chunk.has_dictionary)
            union!(summary.methods, chunk.methods)
            dictionary = Any[]
            if chunk.dictionary !== nothing
                page = chunk.dictionary
                checksum_errors += Int(adler32(page_body(file, page)) != page.checksum)
                dictionary = decode_dictionary(file, column, page)
                push!(
                    lines,
                    "page $number $(column.name) dict offset $(page.offset) header $(page.header_size) body $(page.body_size) checksum $(hex_checksum(page.checksum)) entries $(page.values)"
                )
            end
            row_number = group.first_row + 1
            for (page_index, page) in enumerate(chunk.pages)
                checksum_errors += Int(adler32(page_body(file, page)) != page.checksum)
                push!(
                    lines,
                    "page $number $(column.name) $(page_index - 1) offset $(page.offset) header $(page.header_size) body $(page.body_size) checksum $(hex_checksum(page.checksum)) encoding $(ENCODING_METHODS[page.method + 1]) values $(page.values) nulls $(page.nulls) $(statistics_text(column, page.statistics))"
                )
                for value in decode_page(file, column, page, dictionary)
                    cells += 1
                    nulls += Int(value === nothing)
                    mismatches += Int(!isequal(value, original[row_number][index]))
                    row_number += 1
                end
            end
        end
    end
    for (column, summary) in zip(columns, summaries)
        push!(
            lines,
            "summary $(column.name) bytes $(summary.counts["bytes"]) data_pages $(summary.counts["data_pages"]) dictionary_pages $(summary.counts["dictionary_pages"]) encodings $(method_list(sort!(collect(summary.methods))))"
        )
    end
    status = mismatches == 0 && checksum_errors == 0 ? "ok" : "failed"
    push!(
        lines,
        "roundtrip $status cells $cells nulls $nulls mismatches $mismatches checksum_errors $checksum_errors"
    )
    return lines
end

function condition_leaves(tree)
    tree === nothing && return Any[]
    tree.operation == "NOT" && return condition_leaves(tree.left)
    tree.operation in ("AND", "OR") && return vcat(condition_leaves(tree.left), condition_leaves(tree.right))
    return Any[tree]
end

function convert_condition(tree, columns, indices)
    tree === nothing && return nothing
    operation = tree.operation
    operation == "NOT" && return (operation=operation, left=convert_condition(tree.left, columns, indices))
    operation in ("AND", "OR") && return (
        operation=operation,
        left=convert_condition(tree.left, columns, indices),
        right=convert_condition(tree.right, columns, indices)
    )
    index = indices[tree.column]
    values = Any[columns[index].kind == "DATE" ? day_number(literal.value) : literal.value for literal in tree.literals]
    return (operation=operation, column=index, literals=values)
end

function item_header(item)
    item.operation == "COLUMN" && return item.name
    item.operation == "COUNT_DISTINCT" && return "COUNT(DISTINCT $(item.name))"
    return "$(item.operation)($(item.name === nothing ? "*" : item.name))"
end

function check_query(raw, columns)
    indices = Dict(column.name => index for (index, column) in enumerate(columns))
    items = raw.items === nothing ? Any[(
        operation="COLUMN",
        name=column.name
    ) for column in columns] : raw.items
    leaves = condition_leaves(raw.condition)
    names = String[item.name for item in items if item.name !== nothing]
    append!(names, [leaf.column for leaf in leaves])
    raw.group !== nothing && push!(names, raw.group)
    raw.order !== nothing && push!(names, raw.order)
    any(name -> !haskey(indices, name), names) && return "unknown_column", nothing
    for leaf in leaves
        kind = columns[indices[leaf.column]].kind
        expected = kind == "DATE" ? "STRING" : kind
        any(literal -> literal.kind != expected, leaf.literals) && return "type_mismatch", nothing
    end
    any(
        item -> item.operation in ("SUM", "AVG") && columns[indices[item.name]].kind != "INT",
        items
    ) && return "bad_aggregate", nothing
    aggregate = raw.group !== nothing || any(item -> item.operation != "COLUMN", items)
    aggregate && any(
        item -> item.operation == "COLUMN" && item.name != raw.group,
        items
    ) && return "not_grouped", nothing
    aggregate && raw.order !== nothing && return "bad_order", nothing
    plan = (
        items=[(
            operation=item.operation,
            index=item.name === nothing ? nothing : indices[item.name]
        ) for item in items],
        headers=item_header.(items),
        condition=convert_condition(raw.condition, columns, indices),
        group=raw.group === nothing ? nothing : indices[raw.group],
        order=raw.order === nothing ? nothing : indices[raw.order],
        descending=raw.descending,
        limit=raw.limit,
        aggregate=aggregate,
        needed=sort!(unique([indices[name] for name in names])),
        condition_columns=sort!(unique([indices[leaf.column] for leaf in leaves]))
    )
    return nothing, plan
end

logical_not(value) = value == 2 ? 2 : 1 - value
function logical_pair(operation, first_value, second_value)
    if operation == "AND"
        (first_value == 0 || second_value == 0) && return 0
        return first_value == 2 || second_value == 2 ? 2 : 1
    end
    (first_value == 1 || second_value == 1) && return 1
    return first_value == 2 || second_value == 2 ? 2 : 0
end

function compare_value(operation, value, literals)
    operation == "IS_NULL" && return Int(value === nothing)
    operation == "IS_NOT_NULL" && return Int(value !== nothing)
    value === nothing && return 2
    operation == "BETWEEN" && return Int(literals[1] <= value <= literals[2])
    operation == "IN" && return Int(value in literals)
    other = literals[1]
    operation == "=" && return Int(value == other)
    operation == "<>" && return Int(value != other)
    operation == "<" && return Int(value < other)
    operation == "<=" && return Int(value <= other)
    operation == ">" && return Int(value > other)
    return Int(value >= other)
end

function evaluate_condition(tree, row)
    tree === nothing && return 1
    operation = tree.operation
    operation == "NOT" && return logical_not(evaluate_condition(tree.left, row))
    operation in ("AND", "OR") && return logical_pair(
        operation,
        evaluate_condition(tree.left, row),
        evaluate_condition(tree.right, row)
    )
    return compare_value(operation, row[tree.column], tree.literals)
end

function range_possibilities(operation, low, high, literals)
    if operation == "BETWEEN"
        first_value, last_value = literals
        return low <= last_value && high >= first_value && first_value <= last_value, low < first_value || high > last_value
    elseif operation == "IN"
        return any(value -> low <= value <= high, literals), !(low == high && low in literals)
    end
    value = literals[1]
    operation == "=" && return low <= value <= high, !(low == value && high == value)
    operation == "<>" && return !(low == value && high == value), low <= value <= high
    operation == "<" && return low < value, high >= value
    operation == "<=" && return low <= value, high > value
    operation == ">" && return high > value, low <= value
    return high >= value, low < value
end

function zone_values(tree, zones)
    operation = tree.operation
    operation == "NOT" && return Set(logical_not(value) for value in zone_values(tree.left, zones))
    if operation in ("AND", "OR")
        first_values, second_values = zone_values(tree.left, zones), zone_values(tree.right, zones)
        return Set(logical_pair(operation, left, right) for left in first_values for right in second_values)
    end
    bounds, nulls, count = zones[tree.column]
    values = Set{Int}()
    if operation in ("IS_NULL", "IS_NOT_NULL")
        nulls > 0 && push!(values, Int(operation == "IS_NULL"))
        nulls < count && push!(values, Int(operation == "IS_NOT_NULL"))
        return values
    end
    nulls > 0 && push!(values, 2)
    if bounds !== nothing
        can_true, can_false = range_possibilities(operation, bounds[1], bounds[2], tree.literals)
        can_true && push!(values, 1)
        can_false && push!(values, 0)
    end
    return values
end

function read_scan_page(file, group_index, index, page_index, dictionaries, counts)
    column = file.columns[index]
    chunk = file.groups[group_index].chunks[index]
    page = chunk.pages[page_index]
    dictionary = Any[]
    if page.method == 1
        key = (group_index, index)
        if !haskey(dictionaries, key)
            dictionaries[key] = decode_dictionary(file, column, chunk.dictionary)
            counts["dictionary_pages_read"] += 1
            counts["bytes_read"] += chunk.dictionary.size
        end
        dictionary = dictionaries[key]
    end
    counts["pages_read"] += 1
    counts["bytes_read"] += page.size
    return decode_page(file, column, page, dictionary)
end

function scan_file(file, plan)
    counts = Dict(name => 0 for name in SCAN_COUNTS)
    records = Any[]
    matched = Vector{Any}[]
    dictionaries = Dict{Tuple{Int,Int},Any}()
    condition, condition_columns = plan.condition, plan.condition_columns
    remaining = setdiff(plan.needed, condition_columns)
    for (group_index, group) in enumerate(file.groups)
        zones = Dict(index => (
            group.chunks[index].statistics,
            group.chunks[index].nulls,
            group.rows
        ) for index in condition_columns)
        if condition !== nothing && !(1 in zone_values(condition, zones))
            counts["row_groups_skipped"] += 1
            push!(records, nothing)
            continue
        end
        counts["row_groups_read"] += 1
        if isempty(plan.needed)
            counts["rows_scanned"] += group.rows
            append!(matched, [Any[nothing for _ in file.columns] for _ in 1:group.rows])
            push!(records, "-")
            continue
        end
        record = String[]
        for page_index in 1:group.chunks[1].page_count
            zones = Dict(index => (
                group.chunks[index].pages[page_index].statistics,
                group.chunks[index].pages[page_index].nulls,
                group.chunks[index].pages[page_index].values
            ) for index in condition_columns)
            if condition !== nothing && !(1 in zone_values(condition, zones))
                counts["pages_skipped"] += length(plan.needed)
                push!(record, "s")
                continue
            end
            row_count = group.chunks[1].pages[page_index].values
            counts["rows_scanned"] += row_count
            rows = [Any[nothing for _ in file.columns] for _ in 1:row_count]
            for index in condition_columns
                values = read_scan_page(file, group_index, index, page_index, dictionaries, counts)
                for (row, value) in zip(rows, values)
                    row[index] = value
                end
            end
            selected = [number for (number, row) in enumerate(rows) if evaluate_condition(
                condition,
                row
            ) == 1]
            if isempty(selected) && !isempty(remaining)
                counts["pages_unneeded"] += length(remaining)
                push!(record, "u")
                continue
            end
            for index in remaining
                values = read_scan_page(file, group_index, index, page_index, dictionaries, counts)
                for (row, value) in zip(rows, values)
                    row[index] = value
                end
            end
            append!(matched, rows[selected])
            push!(record, "r")
        end
        push!(records, join(record))
    end
    counts["rows_matched"] = length(matched)
    return matched, counts, records
end

function aggregate_item(columns, item, rows, key)
    operation, index = item.operation, item.index
    operation == "COLUMN" && return value_text(columns[index].kind, key)
    operation == "COUNT" && index === nothing && return string(length(rows))
    values = [row[index] for row in rows if row[index] !== nothing]
    operation == "COUNT" && return string(length(values))
    operation == "COUNT_DISTINCT" && return string(length(Set(values)))
    isempty(values) && return "NULL"
    operation == "SUM" && return string(sum(values))
    if operation == "AVG"
        total = sum(values)
        divisor = gcd(total, length(values))
        numerator, denominator = total ÷ divisor, length(values) ÷ divisor
        return denominator == 1 ? string(numerator) : "$numerator/$denominator"
    end
    value = operation == "MIN" ? minimum(values) : maximum(values)
    return value_text(columns[index].kind, value)
end

function build_result(columns, plan, matched)
    if !plan.aggregate
        kind = "rows"
        arranged = matched
        if plan.order !== nothing
            arranged = sort(
                matched; by=row -> (row[plan.order] !== nothing, row[plan.order]),
                rev=plan.descending,
                alg=MergeSort
            )
        end
        output = [join(
            (value_text(columns[item.index].kind, row[item.index]) for item in plan.items),
            ","
        ) for row in arranged]
    else
        if plan.group === nothing
            kind = "aggregate"
            groups = [(nothing, matched)]
        else
            kind = "grouped"
            grouped = Dict{Any,Vector{Vector{Any}}}()
            for row in matched
                push!(get!(grouped, row[plan.group], Vector{Any}[]), row)
            end
            ordered_keys = sort!(
                collect(keys(grouped)); by=value -> (value !== nothing, value),
                alg=MergeSort
            )
            groups = [(key, grouped[key]) for key in ordered_keys]
        end
        output = [join(
            (aggregate_item(columns, item, rows, key) for item in plan.items),
            ","
        ) for (key, rows) in groups]
    end
    plan.limit !== nothing && (output = output[1:min(end, plan.limit)])
    return (kind=kind, matched=length(matched), rows=output)
end

counts_text(counts) = join(("$name $(counts[name])" for name in SCAN_COUNTS), " ")

function execute_queries(file, originals, queries)
    results, stats_lines = String[], String[]
    totals = Dict(name => 0 for name in SCAN_COUNTS)
    errors, checks_ok = 0, 0
    columns = file.columns
    for (number, text) in enumerate(queries)
        error, plan = check_query(parse_query(text), columns)
        if error !== nothing
            line = "query $number error $error"
            push!(results, line)
            push!(stats_lines, line)
            errors += 1
            continue
        end
        matched, counts, records = scan_file(file, plan)
        result = build_result(columns, plan, matched)
        reference = [row for row in originals if evaluate_condition(plan.condition, row) == 1]
        check = result == build_result(columns, plan, reference) ? "ok" : "mismatch"
        checks_ok += Int(check == "ok")
        push!(results, "query $number $(result.kind) matched $(result.matched) output $(length(result.rows))")
        push!(results, "columns " * join(plan.headers, ","))
        append!(results, result.rows)
        needed = isempty(plan.needed) ? "-" : join((columns[index].name for index in plan.needed), ",")
        push!(stats_lines, "query $number columns $needed $(counts_text(counts)) check $check")
        for (index, record) in enumerate(records)
            detail = record === nothing ? "skipped" : "pages $record"
            push!(stats_lines, "query $number row_group $(index - 1) $detail")
        end
        for name in SCAN_COUNTS
            totals[name] += counts[name]
        end
    end
    push!(
        stats_lines,
        "total queries $(length(queries)) errors $errors $(counts_text(totals)) checks_ok $checks_ok"
    )
    return results, stats_lines
end

function recover_file(data)
    file = parse_file(data)
    columns = file.columns
    rows = [Any[UNKNOWN_CELL for _ in columns] for _ in 1:file.rows]
    lines = ["file bytes $(length(data)) rows $(file.rows) columns $(length(columns)) row_groups $(length(file.groups))"]
    append!(lines, [column_line(index - 1, column) for (index, column) in enumerate(columns)])
    pages_examined, damaged_count, lost_pages, lost_cells = 0, 0, 0, 0
    for (group_index, group) in enumerate(file.groups)
        number = group_index - 1
        for (index, (column, chunk)) in enumerate(zip(columns, group.chunks))
            dictionary = Any[]
            dictionary_damaged = false
            pages = Any[(string(page_index - 1), page) for (page_index, page) in enumerate(chunk.pages)]
            chunk.dictionary !== nothing && pushfirst!(pages, ("dict", chunk.dictionary))
            row_number = group.first_row + 1
            for (page_number, page) in pages
                pages_examined += 1
                checksum = adler32(page_body(file, page))
                damaged = checksum != page.checksum
                if damaged
                    damaged_count += 1
                    push!(
                        lines,
                        "damaged $number $(column.name) $page_number offset $(page.offset) stored $(hex_checksum(page.checksum)) computed $(hex_checksum(checksum))"
                    )
                end
                if page_number == "dict"
                    dictionary_damaged = damaged
                    !damaged && (dictionary = decode_dictionary(file, column, page))
                    continue
                end
                reason = damaged ? "checksum" : page.method == 1 && dictionary_damaged ? "dictionary" : nothing
                if reason !== nothing
                    lost_pages += 1
                    lost_cells += page.values
                    push!(
                        lines,
                        "lost $number $(column.name) $page_number rows $(page.values) reason $reason"
                    )
                else
                    for (offset, value) in enumerate(decode_page(file, column, page, dictionary))
                        rows[row_number + offset - 1][index] = value
                    end
                end
                row_number += page.values
            end
        end
    end
    recovered_cells = file.rows * length(columns) - lost_cells
    push!(
        lines,
        "summary pages $pages_examined damaged $damaged_count lost_pages $lost_pages lost_cells $lost_cells recovered_cells $recovered_cells"
    )
    recovered = [join((column.name for column in columns), ",")]
    for row in rows
        push!(
            recovered,
            join(
                (value === UNKNOWN_CELL ? "?" : value_text(
                    column.kind,
                    value; null=""
                ) for (column, value) in zip(columns, row)),
                ","
            )
        )
    end
    return lines, recovered
end

function main()
    columns, rows, options, queries, damaged = read_inputs()
    data, encoding_report = build_file(columns, rows, options)
    file = parse_file(data)
    metadata = verify_and_describe(file, rows)
    query_results, query_statistics = execute_queries(file, rows, queries)
    recovery, recovered = recover_file(damaged)
    hex_lines = [hex_bytes(data[start:min(start + 31, end)]) for start in 1:32:length(data)]
    write_outputs(Dict(
        "file.hex" => hex_lines,
        "metadata.txt" => metadata,
        "encoding_report.csv" => encoding_report,
        "query_results.txt" => query_results,
        "query_stats.txt" => query_statistics,
        "recovery.txt" => recovery,
        "recovered.csv" => recovered
    ))
end

main()
