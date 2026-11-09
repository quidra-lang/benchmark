from collections import defaultdict
from math import gcd

from bitstream import Reader, adler32, hybrid_decode, hybrid_encode, integer, uleb
from encoding import CANDIDATES, METHODS, decode_statistics, decode_values, encode_statistics, encode_values
from query import Parser
from schema_io import Column, TYPES, day_number, read_inputs, value_text, write_outputs


SCAN_COUNTS = ("row_groups_read", "row_groups_skipped", "pages_read", "pages_skipped",
               "pages_unneeded", "dictionary_pages_read", "bytes_read", "rows_scanned", "rows_matched")
UNKNOWN_CELL = object()


def statistics(values):
    present = [value for value in values if value is not None]
    return (min(present), max(present)) if present else None


def statistics_text(column, bounds):
    if bounds is None:
        return "stats none"
    return f"min {value_text(column.kind, bounds[0])} max {value_text(column.kind, bounds[1])}"


def method_list(methods):
    return ",".join(METHODS[method] for method in methods)


def column_line(index, column):
    nullability = "NULLABLE" if column.nullable else "REQUIRED"
    return f"column {index} {column.name} {column.kind} {nullability}"


def build_page(column, kind, method, values, dictionary=None):
    if kind == 1:
        body = encode_values(column.kind, 0, values)
        nulls, bounds = 0, None
    else:
        present = [value for value in values if value is not None]
        nulls = len(values) - len(present)
        bounds = statistics(values)
        body = b""
        if column.nullable:
            levels = hybrid_encode([int(value is not None) for value in values], 1)
            body = integer(len(levels)) + levels
        body += encode_values(column.kind, method, present, dictionary)
    header = bytes([kind, method]) + uleb(len(values)) + uleb(nulls) + uleb(len(body))
    header += integer(adler32(body)) + encode_statistics(column.kind, bounds)
    return header + body


def build_chunk(column, values, method, page_size, dictionary_limit):
    pages = [values[start:start + page_size] for start in range(0, len(values), page_size)]
    dictionary = []
    dictionary_pages = 0
    if method == 1:
        known = set()
        dictionary_bytes = 0
        for page in pages:
            additions = []
            proposed = known.copy()
            for value in page:
                if value is not None and value not in proposed:
                    additions.append(value)
                    proposed.add(value)
            size = dictionary_bytes + len(encode_values(column.kind, 0, additions))
            if size > dictionary_limit:
                break
            dictionary.extend(additions)
            known = proposed
            dictionary_bytes = size
            dictionary_pages += 1
        if not dictionary:
            dictionary_pages = 0
    parts = []
    if dictionary_pages:
        parts.append(build_page(column, 1, 0, dictionary))
    methods = set()
    for number, page in enumerate(pages):
        selected = (1 if number < dictionary_pages else 0) if method == 1 else method
        methods.add(selected)
        parts.append(build_page(column, 0, selected, page, dictionary))
    data = b"".join(parts)
    return {"data": data, "size": len(data), "methods": sorted(methods),
            "has_dictionary": bool(dictionary_pages), "page_count": len(pages),
            "nulls": sum(value is None for value in values), "statistics": statistics(values),
            "fallback": len(pages) - dictionary_pages if method == 1 else 0}


def build_file(columns, rows, options):
    data = bytearray(b"MPTC")
    groups = []
    report = ["row_group,column,encoding,bytes,fallback_pages,chosen"]
    for first in range(0, len(rows), options["row_group_size"]):
        group_rows = rows[first:first + options["row_group_size"]]
        group = {"rows": len(group_rows), "chunks": []}
        number = len(groups)
        for index, column in enumerate(columns):
            values = [row[index] for row in group_rows]
            candidates = {method: build_chunk(column, values, method, options["page_size"],
                                              options["dictionary_limit"])
                          for method in CANDIDATES[column.kind]}
            requested = options["encoding"][column.name]
            if requested == "AUTO":
                chosen = min(candidates, key=lambda method: (candidates[method]["size"], method))
            else:
                chosen = METHODS.index(requested)
                if chosen == 1 and not candidates[chosen]["has_dictionary"]:
                    chosen = 0
            for method, candidate in candidates.items():
                selected = "yes" if method == chosen else "no"
                report.append(f"{number},{column.name},{METHODS[method]},{candidate['size']},"
                              f"{candidate['fallback']},{selected}")
            chunk = candidates[chosen]
            chunk["offset"] = len(data)
            data.extend(chunk["data"])
            group["chunks"].append(chunk)
        groups.append(group)
    footer = bytearray(uleb(1) + uleb(len(columns)))
    for column in columns:
        footer.extend(uleb(len(column.name)))
        footer.extend(column.name.encode("ascii"))
        footer.extend((TYPES.index(column.kind), int(column.nullable)))
    footer.extend(uleb(len(rows)))
    footer.extend(uleb(len(groups)))
    for group in groups:
        footer.extend(uleb(group["rows"]))
        for column, chunk in zip(columns, group["chunks"]):
            footer.extend(uleb(chunk["offset"]) + uleb(chunk["size"]))
            footer.extend(uleb(len(chunk["methods"])))
            footer.extend(chunk["methods"])
            footer.append(int(chunk["has_dictionary"]))
            footer.extend(uleb(chunk["page_count"]) + uleb(chunk["nulls"]))
            footer.extend(encode_statistics(column.kind, chunk["statistics"]))
    data.extend(footer)
    data.extend(integer(len(footer)))
    data.extend(b"MPTC")
    return bytes(data), report


def parse_file(data):
    footer_size = Reader(data, len(data) - 8).integer()
    footer_offset = len(data) - 8 - footer_size
    reader = Reader(data, footer_offset)
    version = reader.uleb()
    columns = []
    for index in range(reader.uleb()):
        name = reader.read(reader.uleb()).decode("ascii")
        columns.append(Column(name, TYPES[reader.byte()], bool(reader.byte())))
    row_count = reader.uleb()
    groups = []
    first_row = 0
    for number in range(reader.uleb()):
        count = reader.uleb()
        group = {"rows": count, "first_row": first_row, "chunks": []}
        for column in columns:
            offset, size = reader.uleb(), reader.uleb()
            methods = [reader.byte() for index in range(reader.uleb())]
            has_dictionary = bool(reader.byte())
            pages, nulls = reader.uleb(), reader.uleb()
            bounds = decode_statistics(reader, column.kind)
            group["chunks"].append({"offset": offset, "size": size, "methods": methods,
                                    "has_dictionary": has_dictionary, "page_count": pages,
                                    "nulls": nulls, "statistics": bounds})
        groups.append(group)
        first_row += count
    for group in groups:
        for column, chunk in zip(columns, group["chunks"]):
            reader = Reader(data, chunk["offset"])
            pages = []
            while reader.position < chunk["offset"] + chunk["size"]:
                start = reader.position
                kind, method = reader.byte(), reader.byte()
                count, nulls, body_size = reader.uleb(), reader.uleb(), reader.uleb()
                checksum = reader.integer()
                bounds = decode_statistics(reader, column.kind)
                header_size = reader.position - start
                pages.append({"offset": start, "kind": kind, "method": method, "values": count,
                              "nulls": nulls, "body_size": body_size, "checksum": checksum,
                              "statistics": bounds, "header_size": header_size,
                              "body_offset": reader.position, "size": header_size + body_size})
                reader.position += body_size
            chunk["dictionary"] = pages[0] if chunk["has_dictionary"] else None
            chunk["pages"] = pages[1:] if chunk["has_dictionary"] else pages
    return {"data": data, "version": version, "columns": columns, "rows": row_count,
            "groups": groups, "footer_size": footer_size, "footer_offset": footer_offset}


def page_body(file, page):
    start = page["body_offset"]
    return file["data"][start:start + page["body_size"]]


def decode_dictionary(file, column, page):
    return decode_values(Reader(page_body(file, page)), column.kind, 0, page["values"])


def decode_page(file, column, page, dictionary=None):
    reader = Reader(page_body(file, page))
    count = page["values"]
    if column.nullable:
        levels = hybrid_decode(Reader(reader.read(reader.integer())), 1, count)
    else:
        levels = [1] * count
    present = sum(level == 1 for level in levels)
    values = iter(decode_values(reader, column.kind, page["method"], present, dictionary))
    return [next(values) if level == 1 else None for level in levels]


def verify_and_describe(file, original):
    columns = file["columns"]
    lines = [f"file bytes {len(file['data'])} footer_offset {file['footer_offset']} footer_bytes {file['footer_size']}",
             f"table version {file['version']} rows {file['rows']} columns {len(columns)} row_groups {len(file['groups'])}"]
    lines.extend(column_line(index, column) for index, column in enumerate(columns))
    summaries = [{"bytes": 0, "data_pages": 0, "dictionary_pages": 0, "methods": set()} for column in columns]
    cells = nulls = mismatches = checksum_errors = 0
    for number, group in enumerate(file["groups"]):
        size = sum(chunk["size"] for chunk in group["chunks"])
        lines.append(f"row_group {number} rows {group['rows']} first_row {group['first_row']} bytes {size}")
        for index, (column, chunk) in enumerate(zip(columns, group["chunks"])):
            has_dictionary = "yes" if chunk["has_dictionary"] else "no"
            lines.append(f"chunk {number} {column.name} offset {chunk['offset']} size {chunk['size']} "
                         f"encodings {method_list(chunk['methods'])} dictionary {has_dictionary} "
                         f"pages {chunk['page_count']} nulls {chunk['nulls']} {statistics_text(column, chunk['statistics'])}")
            summary = summaries[index]
            summary["bytes"] += chunk["size"]
            summary["data_pages"] += chunk["page_count"]
            summary["dictionary_pages"] += chunk["has_dictionary"]
            summary["methods"].update(chunk["methods"])
            dictionary = None
            if chunk["dictionary"] is not None:
                page = chunk["dictionary"]
                checksum_errors += adler32(page_body(file, page)) != page["checksum"]
                dictionary = decode_dictionary(file, column, page)
                lines.append(f"page {number} {column.name} dict offset {page['offset']} header {page['header_size']} "
                             f"body {page['body_size']} checksum {page['checksum']:08x} entries {page['values']}")
            row_number = group["first_row"]
            for page_number, page in enumerate(chunk["pages"]):
                checksum_errors += adler32(page_body(file, page)) != page["checksum"]
                lines.append(f"page {number} {column.name} {page_number} offset {page['offset']} "
                             f"header {page['header_size']} body {page['body_size']} checksum {page['checksum']:08x} "
                             f"encoding {METHODS[page['method']]} values {page['values']} nulls {page['nulls']} "
                             f"{statistics_text(column, page['statistics'])}")
                for value in decode_page(file, column, page, dictionary):
                    cells += 1
                    nulls += value is None
                    mismatches += value != original[row_number][index]
                    row_number += 1
    for column, summary in zip(columns, summaries):
        lines.append(f"summary {column.name} bytes {summary['bytes']} data_pages {summary['data_pages']} "
                     f"dictionary_pages {summary['dictionary_pages']} encodings {method_list(sorted(summary['methods']))}")
    status = "ok" if mismatches == 0 and checksum_errors == 0 else "failed"
    lines.append(f"roundtrip {status} cells {cells} nulls {nulls} mismatches {mismatches} checksum_errors {checksum_errors}")
    return lines


def condition_leaves(tree):
    if tree is None:
        return
    if tree[0] == "NOT":
        yield from condition_leaves(tree[1])
    elif tree[0] in ("AND", "OR"):
        yield from condition_leaves(tree[1])
        yield from condition_leaves(tree[2])
    else:
        yield tree


def convert_condition(tree, columns, indices):
    if tree is None:
        return None
    operation = tree[0]
    if operation == "NOT":
        return operation, convert_condition(tree[1], columns, indices)
    if operation in ("AND", "OR"):
        return (operation, convert_condition(tree[1], columns, indices),
                convert_condition(tree[2], columns, indices))
    index = indices[tree[1]]
    values = tuple(day_number(value) if columns[index].kind == "DATE" else value for kind, value in tree[2])
    return operation, index, values


def item_header(operation, name):
    if operation == "COLUMN":
        return name
    if operation == "COUNT_DISTINCT":
        return f"COUNT(DISTINCT {name})"
    return f"{operation}({name if name is not None else '*'})"


def check_query(raw, columns):
    indices = {column.name: index for index, column in enumerate(columns)}
    items = raw["items"]
    if items is None:
        items = [("COLUMN", column.name) for column in columns]
    leaves = list(condition_leaves(raw["condition"]))
    names = [name for operation, name in items if name is not None]
    names.extend(leaf[1] for leaf in leaves)
    names.extend(name for name in (raw["group"], raw["order"]) if name is not None)
    if any(name not in indices for name in names):
        return "unknown_column", None
    for operation, name, literals in leaves:
        kind = columns[indices[name]].kind
        expected = "STRING" if kind == "DATE" else kind
        if any(literal_kind != expected for literal_kind, value in literals):
            return "type_mismatch", None
    if any(operation in ("SUM", "AVG") and columns[indices[name]].kind != "INT" for operation, name in items):
        return "bad_aggregate", None
    aggregate = raw["group"] is not None or any(operation != "COLUMN" for operation, name in items)
    if aggregate and any(operation == "COLUMN" and name != raw["group"] for operation, name in items):
        return "not_grouped", None
    if aggregate and raw["order"] is not None:
        return "bad_order", None
    plan = {"items": [(operation, indices[name] if name is not None else None) for operation, name in items],
            "headers": [item_header(operation, name) for operation, name in items],
            "condition": convert_condition(raw["condition"], columns, indices),
            "group": indices[raw["group"]] if raw["group"] is not None else None,
            "order": indices[raw["order"]] if raw["order"] is not None else None,
            "descending": raw["descending"], "limit": raw["limit"], "aggregate": aggregate,
            "needed": sorted({indices[name] for name in names}),
            "condition_columns": sorted({indices[leaf[1]] for leaf in leaves})}
    return None, plan


def logical_not(value):
    return None if value is None else not value


def logical_pair(operation, first, second):
    if operation == "AND":
        if first is False or second is False:
            return False
        return None if first is None or second is None else True
    if first is True or second is True:
        return True
    return None if first is None or second is None else False


def compare_value(operation, value, literals):
    if operation == "IS_NULL":
        return value is None
    if operation == "IS_NOT_NULL":
        return value is not None
    if value is None:
        return None
    if operation == "BETWEEN":
        return literals[0] <= value <= literals[1]
    if operation == "IN":
        return value in literals
    other = literals[0]
    if operation == "=":
        return value == other
    if operation == "<>":
        return value != other
    if operation == "<":
        return value < other
    if operation == "<=":
        return value <= other
    if operation == ">":
        return value > other
    return value >= other


def evaluate(tree, row):
    if tree is None:
        return True
    operation = tree[0]
    if operation == "NOT":
        return logical_not(evaluate(tree[1], row))
    if operation in ("AND", "OR"):
        return logical_pair(operation, evaluate(tree[1], row), evaluate(tree[2], row))
    return compare_value(operation, row[tree[1]], tree[2])


def range_possibilities(operation, low, high, literals):
    if operation == "BETWEEN":
        first, last = literals
        return low <= last and high >= first and first <= last, low < first or high > last
    if operation == "IN":
        return any(low <= value <= high for value in literals), not (low == high and low in literals)
    value = literals[0]
    if operation == "=":
        return low <= value <= high, not (low == value and high == value)
    if operation == "<>":
        return not (low == value and high == value), low <= value <= high
    if operation == "<":
        return low < value, high >= value
    if operation == "<=":
        return low <= value, high > value
    if operation == ">":
        return high > value, low <= value
    return high >= value, low < value


def zone_values(tree, zones):
    operation = tree[0]
    if operation == "NOT":
        return {logical_not(value) for value in zone_values(tree[1], zones)}
    if operation in ("AND", "OR"):
        first = zone_values(tree[1], zones)
        second = zone_values(tree[2], zones)
        return {logical_pair(operation, left, right) for left in first for right in second}
    bounds, nulls, count = zones[tree[1]]
    values = set()
    if operation in ("IS_NULL", "IS_NOT_NULL"):
        if nulls > 0:
            values.add(operation == "IS_NULL")
        if nulls < count:
            values.add(operation == "IS_NOT_NULL")
        return values
    if nulls > 0:
        values.add(None)
    if bounds is not None:
        can_be_true, can_be_false = range_possibilities(operation, *bounds, tree[2])
        if can_be_true:
            values.add(True)
        if can_be_false:
            values.add(False)
    return values


def read_scan_page(file, group_number, index, page_number, dictionaries, counts):
    column = file["columns"][index]
    chunk = file["groups"][group_number]["chunks"][index]
    page = chunk["pages"][page_number]
    dictionary = None
    if page["method"] == 1:
        key = group_number, index
        if key not in dictionaries:
            dictionary_page = chunk["dictionary"]
            dictionaries[key] = decode_dictionary(file, column, dictionary_page)
            counts["dictionary_pages_read"] += 1
            counts["bytes_read"] += dictionary_page["size"]
        dictionary = dictionaries[key]
    counts["pages_read"] += 1
    counts["bytes_read"] += page["size"]
    return decode_page(file, column, page, dictionary)


def scan(file, plan):
    counts = dict.fromkeys(SCAN_COUNTS, 0)
    records = []
    matched = []
    dictionaries = {}
    condition = plan["condition"]
    condition_columns = plan["condition_columns"]
    remaining = [index for index in plan["needed"] if index not in condition_columns]
    for group_number, group in enumerate(file["groups"]):
        zones = {index: (group["chunks"][index]["statistics"], group["chunks"][index]["nulls"], group["rows"])
                 for index in condition_columns}
        if condition is not None and True not in zone_values(condition, zones):
            counts["row_groups_skipped"] += 1
            records.append(None)
            continue
        counts["row_groups_read"] += 1
        if not plan["needed"]:
            counts["rows_scanned"] += group["rows"]
            matched.extend([[None] * len(file["columns"]) for row in range(group["rows"])])
            records.append("-")
            continue
        record = []
        for page_number in range(group["chunks"][0]["page_count"]):
            zones = {}
            for index in condition_columns:
                page = group["chunks"][index]["pages"][page_number]
                zones[index] = page["statistics"], page["nulls"], page["values"]
            if condition is not None and True not in zone_values(condition, zones):
                counts["pages_skipped"] += len(plan["needed"])
                record.append("s")
                continue
            row_count = group["chunks"][0]["pages"][page_number]["values"]
            counts["rows_scanned"] += row_count
            rows = [[None] * len(file["columns"]) for row in range(row_count)]
            for index in condition_columns:
                values = read_scan_page(file, group_number, index, page_number, dictionaries, counts)
                for row, value in zip(rows, values):
                    row[index] = value
            selected = [number for number, row in enumerate(rows) if evaluate(condition, row) is True]
            if not selected and remaining:
                counts["pages_unneeded"] += len(remaining)
                record.append("u")
                continue
            for index in remaining:
                values = read_scan_page(file, group_number, index, page_number, dictionaries, counts)
                for row, value in zip(rows, values):
                    row[index] = value
            matched.extend(rows[number] for number in selected)
            record.append("r")
        records.append("".join(record))
    counts["rows_matched"] = len(matched)
    return matched, counts, records


def aggregate_item(columns, operation, index, rows, key):
    if operation == "COLUMN":
        return value_text(columns[index].kind, key)
    if operation == "COUNT" and index is None:
        return str(len(rows))
    values = [row[index] for row in rows if row[index] is not None]
    if operation == "COUNT":
        return str(len(values))
    if operation == "COUNT_DISTINCT":
        return str(len(set(values)))
    if not values:
        return "NULL"
    if operation == "SUM":
        return str(sum(values))
    if operation == "AVG":
        total = sum(values)
        divisor = gcd(total, len(values))
        numerator, denominator = total // divisor, len(values) // divisor
        return str(numerator) if denominator == 1 else f"{numerator}/{denominator}"
    value = min(values) if operation == "MIN" else max(values)
    return value_text(columns[index].kind, value)


def build_result(columns, plan, matched):
    if not plan["aggregate"]:
        kind = "rows"
        arranged = matched
        if plan["order"] is not None:
            index = plan["order"]
            arranged = sorted(matched, key=lambda row: (row[index] is not None, row[index]),
                              reverse=plan["descending"])
        output = [",".join(value_text(columns[index].kind, row[index]) for operation, index in plan["items"])
                  for row in arranged]
    else:
        if plan["group"] is None:
            kind = "aggregate"
            groups = [(None, matched)]
        else:
            kind = "grouped"
            grouped = defaultdict(list)
            for row in matched:
                grouped[row[plan["group"]]].append(row)
            keys = sorted(grouped, key=lambda value: (value is not None, value))
            groups = [(key, grouped[key]) for key in keys]
        output = [",".join(aggregate_item(columns, operation, index, rows, key)
                           for operation, index in plan["items"]) for key, rows in groups]
    if plan["limit"] is not None:
        output = output[:plan["limit"]]
    return kind, len(matched), output


def counts_text(counts):
    return " ".join(f"{name} {counts[name]}" for name in SCAN_COUNTS)


def execute_queries(file, originals, queries):
    results, statistics_lines = [], []
    totals = dict.fromkeys(SCAN_COUNTS, 0)
    errors = checks_ok = 0
    columns = file["columns"]
    for number, text in enumerate(queries, 1):
        error, plan = check_query(Parser(text).parse(), columns)
        if error is not None:
            line = f"query {number} error {error}"
            results.append(line)
            statistics_lines.append(line)
            errors += 1
            continue
        matched, counts, records = scan(file, plan)
        result = build_result(columns, plan, matched)
        reference = [row for row in originals if evaluate(plan["condition"], row) is True]
        check = "ok" if result == build_result(columns, plan, reference) else "mismatch"
        checks_ok += check == "ok"
        kind, matched_count, output = result
        results.append(f"query {number} {kind} matched {matched_count} output {len(output)}")
        results.append("columns " + ",".join(plan["headers"]))
        results.extend(output)
        needed = ",".join(columns[index].name for index in plan["needed"]) or "-"
        statistics_lines.append(f"query {number} columns {needed} {counts_text(counts)} check {check}")
        for group, record in enumerate(records):
            detail = "skipped" if record is None else "pages " + record
            statistics_lines.append(f"query {number} row_group {group} {detail}")
        for name in SCAN_COUNTS:
            totals[name] += counts[name]
    statistics_lines.append(f"total queries {len(queries)} errors {errors} {counts_text(totals)} checks_ok {checks_ok}")
    return results, statistics_lines


def recover(data):
    file = parse_file(data)
    columns = file["columns"]
    rows = [[UNKNOWN_CELL] * len(columns) for row in range(file["rows"])]
    lines = [f"file bytes {len(data)} rows {file['rows']} columns {len(columns)} row_groups {len(file['groups'])}"]
    lines.extend(column_line(index, column) for index, column in enumerate(columns))
    pages_examined = damaged_count = lost_pages = lost_cells = 0
    for group_number, group in enumerate(file["groups"]):
        for index, (column, chunk) in enumerate(zip(columns, group["chunks"])):
            dictionary = None
            dictionary_damaged = False
            pages = [(number, page) for number, page in enumerate(chunk["pages"])]
            if chunk["dictionary"] is not None:
                pages.insert(0, ("dict", chunk["dictionary"]))
            row_number = group["first_row"]
            for page_number, page in pages:
                pages_examined += 1
                checksum = adler32(page_body(file, page))
                damaged = checksum != page["checksum"]
                if damaged:
                    damaged_count += 1
                    lines.append(f"damaged {group_number} {column.name} {page_number} offset {page['offset']} "
                                 f"stored {page['checksum']:08x} computed {checksum:08x}")
                if page_number == "dict":
                    dictionary_damaged = damaged
                    if not damaged:
                        dictionary = decode_dictionary(file, column, page)
                    continue
                reason = None
                if damaged:
                    reason = "checksum"
                elif page["method"] == 1 and dictionary_damaged:
                    reason = "dictionary"
                if reason is not None:
                    lost_pages += 1
                    lost_cells += page["values"]
                    lines.append(f"lost {group_number} {column.name} {page_number} rows {page['values']} reason {reason}")
                else:
                    values = decode_page(file, column, page, dictionary)
                    for offset, value in enumerate(values):
                        rows[row_number + offset][index] = value
                row_number += page["values"]
    recovered_cells = file["rows"] * len(columns) - lost_cells
    lines.append(f"summary pages {pages_examined} damaged {damaged_count} lost_pages {lost_pages} "
                 f"lost_cells {lost_cells} recovered_cells {recovered_cells}")
    recovered = [",".join(column.name for column in columns)]
    for row in rows:
        recovered.append(",".join("?" if value is UNKNOWN_CELL else value_text(column.kind, value, null="")
                                  for column, value in zip(columns, row)))
    return lines, recovered


def main():
    columns, rows, options, queries, damaged = read_inputs()
    data, encoding_report = build_file(columns, rows, options)
    file = parse_file(data)
    metadata = verify_and_describe(file, rows)
    query_results, query_statistics = execute_queries(file, rows, queries)
    recovery, recovered = recover(damaged)
    write_outputs({"file.hex": [data[start:start + 32].hex() for start in range(0, len(data), 32)],
                   "metadata.txt": metadata, "encoding_report.csv": encoding_report,
                   "query_results.txt": query_results, "query_stats.txt": query_statistics,
                   "recovery.txt": recovery, "recovered.csv": recovered})


if __name__ == "__main__":
    main()
