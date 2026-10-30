#include "columnar.h"
static Bounds statistics(Values values) {
    Bounds out = {0};
    for (size_t i = 0; i < values.count; ++i) {
        Value v = values.items[i];
        if (v.null)
            continue;
        if (!out.present)
            out = (Bounds){true, v, v};
        else {
            if (value_compare(v, out.low) < 0)
                out.low = v;
            if (value_compare(out.high, v) < 0)
                out.high = v;
        }
    }
    return out;
}
static char *statistics_text(Column column, Bounds bounds) {
    return bounds.present ? format("min %s max %s", value_text(column.kind, bounds.low, "NULL"),
                                   value_text(column.kind, bounds.high, "NULL"))
                          : "stats none";
}
static char *method_list(unsigned mask) {
    Names names = {0};
    for (int method = 0; method < 5; ++method)
        if (mask & (1u << method))
            Names_add(&names, (char *)methods[method]);
    return join(names, ",");
}
static char *column_line(int index, Column column) {
    return format("column %d %s %s %s", index, column.name, type_names[column.kind],
                  column.nullable ? "NULLABLE" : "REQUIRED");
}
typedef struct {
    size_t offset, header_size, body_size, body_offset;
    int kind, method, count, nulls;
    Number checksum;
    Bounds bounds;
} Page;
VECTOR(Pages, Page)
typedef struct {
    size_t offset, size;
    unsigned methods;
    bool has_dictionary;
    int page_count, nulls;
    Bounds bounds;
    Page dictionary;
    Pages pages;
} Chunk;
VECTOR(Chunks, Chunk)
typedef struct {
    int rows, first_row;
    Chunks chunks;
} Group;
VECTOR(Groups, Group)
typedef struct {
    Bytes data;
    Chunk info;
    int fallback;
} BuiltChunk;
static size_t page_size(Page page) { return page.header_size + page.body_size; }
static Values values_slice(Values values, size_t start, size_t count) {
    return (Values){values.items + start, count, count};
}
static bool contains_value(Values values, Value value) {
    for (size_t i = 0; i < values.count; ++i)
        if (value_equal(values.items[i], value))
            return true;
    return false;
}
static Bytes build_page(Column column, int kind, int method, Values values, Values dictionary) {
    Bytes body = {0};
    int nulls = 0;
    Bounds bounds = {0};
    if (kind == 1)
        body = encode_values(column.kind, 0, values, (Values){0});
    else {
        Values present = {0};
        Numbers levels = {0};
        for (size_t i = 0; i < values.count; ++i) {
            Value v = values.items[i];
            Numbers_add(&levels, !v.null);
            if (v.null)
                ++nulls;
            else
                Values_add(&present, v);
        }
        bounds = statistics(values);
        if (column.nullable) {
            Bytes encoded = hybrid_encode(levels, 1);
            write_integer(&body, (Number)encoded.count);
            append_bytes(&body, encoded);
        }
        append_bytes(&body, encode_values(column.kind, method, present, dictionary));
    }
    Bytes out = {0};
    Bytes_add(&out, (unsigned char)kind);
    Bytes_add(&out, (unsigned char)method);
    write_uleb(&out, (Number)values.count);
    write_uleb(&out, nulls);
    write_uleb(&out, (Number)body.count);
    write_integer(&out, adler32(body));
    append_bytes(&out, encode_statistics(column.kind, bounds));
    append_bytes(&out, body);
    return out;
}
static BuiltChunk build_chunk(Column column, Values values, int method, Options options) {
    int page_count =
            (int)((values.count + (size_t)options.page_size - 1) / (size_t)options.page_size),
        dictionary_pages = 0;
    Values dictionary = {0};
    size_t dictionary_bytes = 0;
    if (method == 1)
        for (int page = 0; page < page_count; ++page) {
            size_t start = (size_t)page * (size_t)options.page_size, count = values.count - start;
            if (count > (size_t)options.page_size)
                count = (size_t)options.page_size;
            Values additions = {0};
            for (size_t i = start; i < start + count; ++i)
                if (!values.items[i].null && !contains_value(dictionary, values.items[i]) &&
                    !contains_value(additions, values.items[i]))
                    Values_add(&additions, values.items[i]);
            size_t proposed_bytes =
                dictionary_bytes + encode_values(column.kind, 0, additions, (Values){0}).count;
            if (proposed_bytes > (size_t)options.dictionary_limit)
                break;
            for (size_t i = 0; i < additions.count; ++i)
                Values_add(&dictionary, additions.items[i]);
            dictionary_bytes = proposed_bytes;
            ++dictionary_pages;
        }
    if (!dictionary.count)
        dictionary_pages = 0;
    BuiltChunk out = {0};
    if (dictionary_pages)
        append_bytes(&out.data, build_page(column, 1, 0, dictionary, (Values){0}));
    for (int page = 0; page < page_count; ++page) {
        size_t start = (size_t)page * (size_t)options.page_size, count = values.count - start;
        if (count > (size_t)options.page_size)
            count = (size_t)options.page_size;
        int selected = method == 1 ? (page < dictionary_pages ? 1 : 0) : method;
        out.info.methods |= 1u << selected;
        append_bytes(&out.data, build_page(column, 0, selected, values_slice(values, start, count),
                                           dictionary));
    }
    out.info.size = out.data.count;
    out.info.has_dictionary = dictionary_pages != 0;
    out.info.page_count = page_count;
    out.info.bounds = statistics(values);
    for (size_t i = 0; i < values.count; ++i)
        out.info.nulls += values.items[i].null;
    out.fallback = method == 1 ? page_count - dictionary_pages : 0;
    return out;
}
typedef struct {
    Bytes data;
    Names report;
} BuiltFile;
static BuiltFile build_file(const Inputs *inputs) {
    BuiltFile out = {0};
    const char *magic = "MPTC";
    for (int i = 0; i < 4; ++i)
        Bytes_add(&out.data, (unsigned char)magic[i]);
    Groups groups = {0};
    Names_add(&out.report, "row_group,column,encoding,bytes,fallback_pages,chosen");
    for (size_t first = 0; first < inputs->rows.count;
         first += (size_t)inputs->options.row_group_size) {
        size_t count = inputs->rows.count - first;
        if (count > (size_t)inputs->options.row_group_size)
            count = (size_t)inputs->options.row_group_size;
        Group group = {.rows = (int)count, .first_row = (int)first};
        for (size_t index = 0; index < inputs->columns.count; ++index) {
            Memory work = {0};
            memory = &work;
            Column column = inputs->columns.items[index];
            Values values = {0};
            for (size_t row = 0; row < count; ++row)
                Values_add(&values, inputs->rows.items[first + row].items[index]);
            Numbers methods_list = candidates(column.kind);
            BuiltChunk choices[5] = {0};
            for (size_t i = 0; i < methods_list.count; ++i) {
                int method = (int)methods_list.items[i];
                choices[method] = build_chunk(column, values, method, inputs->options);
            }
            int chosen = inputs->options.encoding[index];
            if (chosen < 0) {
                chosen = (int)methods_list.items[0];
                for (size_t i = 1; i < methods_list.count; ++i) {
                    int method = (int)methods_list.items[i];
                    if (choices[method].data.count < choices[chosen].data.count)
                        chosen = method;
                }
            } else if (chosen == 1 && !choices[chosen].info.has_dictionary)
                chosen = 0;
            memory = &permanent;
            for (size_t i = 0; i < methods_list.count; ++i) {
                int method = (int)methods_list.items[i];
                Names_add(&out.report,
                          format("%zu,%s,%s,%zu,%d,%s", groups.count, column.name, methods[method],
                                 choices[method].data.count, choices[method].fallback,
                                 method == chosen ? "yes" : "no"));
            }
            Chunk info = choices[chosen].info;
            info.offset = out.data.count;
            append_bytes(&out.data, choices[chosen].data);
            Chunks_add(&group.chunks, info);
            clear_memory(&work);
        }
        Groups_add(&groups, group);
    }
    Bytes footer = {0};
    write_uleb(&footer, 1);
    write_uleb(&footer, (Number)inputs->columns.count);
    for (size_t i = 0; i < inputs->columns.count; ++i) {
        Column column = inputs->columns.items[i];
        write_uleb(&footer, (Number)strlen(column.name));
        for (size_t j = 0; column.name[j]; ++j)
            Bytes_add(&footer, (unsigned char)column.name[j]);
        Bytes_add(&footer, (unsigned char)column.kind);
        Bytes_add(&footer, column.nullable);
    }
    write_uleb(&footer, (Number)inputs->rows.count);
    write_uleb(&footer, (Number)groups.count);
    for (size_t g = 0; g < groups.count; ++g) {
        Group group = groups.items[g];
        write_uleb(&footer, group.rows);
        for (size_t i = 0; i < inputs->columns.count; ++i) {
            Chunk chunk = group.chunks.items[i];
            write_uleb(&footer, (Number)chunk.offset);
            write_uleb(&footer, (Number)chunk.size);
            int count = 0;
            for (int method = 0; method < 5; ++method)
                count += (chunk.methods & (1u << method)) != 0;
            write_uleb(&footer, count);
            for (int method = 0; method < 5; ++method)
                if (chunk.methods & (1u << method))
                    Bytes_add(&footer, (unsigned char)method);
            Bytes_add(&footer, chunk.has_dictionary);
            write_uleb(&footer, chunk.page_count);
            write_uleb(&footer, chunk.nulls);
            append_bytes(&footer, encode_statistics(inputs->columns.items[i].kind, chunk.bounds));
        }
    }
    append_bytes(&out.data, footer);
    write_integer(&out.data, (Number)footer.count);
    for (int i = 0; i < 4; ++i)
        Bytes_add(&out.data, (unsigned char)magic[i]);
    return out;
}
typedef struct {
    Bytes data;
    int version, rows;
    Columns columns;
    Groups groups;
    size_t footer_size, footer_offset;
} File;
static File parse_file(Bytes data) {
    File out = {.data = data};
    Reader length = reader_create(data, data.count - 8);
    out.footer_size = (size_t)read_integer(&length, false);
    out.footer_offset = data.count - 8 - out.footer_size;
    Reader reader = reader_create(data, out.footer_offset);
    out.version = (int)read_uleb(&reader);
    int columns = (int)read_uleb(&reader);
    for (int i = 0; i < columns; ++i) {
        size_t count = (size_t)read_uleb(&reader);
        char *name = read_string(&reader, count);
        Type kind = (Type)read_byte(&reader);
        bool nullable = read_byte(&reader) != 0;
        Columns_add(&out.columns, (Column){name, kind, nullable});
    }
    out.rows = (int)read_uleb(&reader);
    int groups = (int)read_uleb(&reader), first = 0;
    for (int g = 0; g < groups; ++g) {
        Group group = {.rows = (int)read_uleb(&reader), .first_row = first};
        first += group.rows;
        for (int i = 0; i < columns; ++i) {
            Chunk chunk = {0};
            chunk.offset = (size_t)read_uleb(&reader);
            chunk.size = (size_t)read_uleb(&reader);
            int count = (int)read_uleb(&reader);
            for (int j = 0; j < count; ++j)
                chunk.methods |= 1u << read_byte(&reader);
            chunk.has_dictionary = read_byte(&reader) != 0;
            chunk.page_count = (int)read_uleb(&reader);
            chunk.nulls = (int)read_uleb(&reader);
            chunk.bounds = decode_statistics(&reader, out.columns.items[i].kind);
            Chunks_add(&group.chunks, chunk);
        }
        Groups_add(&out.groups, group);
    }
    for (size_t g = 0; g < out.groups.count; ++g)
        for (int i = 0; i < columns; ++i) {
            Chunk *chunk = &out.groups.items[g].chunks.items[i];
            Reader pages = reader_create(data, chunk->offset);
            int number = 0;
            while (pages.position < chunk->offset + chunk->size) {
                Page page = {.offset = pages.position};
                page.kind = read_byte(&pages);
                page.method = read_byte(&pages);
                page.count = (int)read_uleb(&pages);
                page.nulls = (int)read_uleb(&pages);
                page.body_size = (size_t)read_uleb(&pages);
                page.checksum = read_integer(&pages, false);
                page.bounds = decode_statistics(&pages, out.columns.items[i].kind);
                page.body_offset = pages.position;
                page.header_size = pages.position - page.offset;
                pages.position += page.body_size;
                if (chunk->has_dictionary && number == 0)
                    chunk->dictionary = page;
                else
                    Pages_add(&chunk->pages, page);
                ++number;
            }
        }
    return out;
}
static Bytes page_body(const File *file, Page page) {
    return (Bytes){file->data.items + page.body_offset, page.body_size, page.body_size};
}
static Values decode_dictionary(const File *file, Column column, Page page) {
    Reader reader = reader_create(page_body(file, page), 0);
    return decode_values(&reader, column.kind, 0, page.count, (Values){0});
}
static Values decode_page(const File *file, Column column, Page page, Values dictionary) {
    Reader reader = reader_create(page_body(file, page), 0);
    Numbers levels = {0};
    if (column.nullable) {
        size_t size = (size_t)read_integer(&reader, false);
        Bytes data = read_bytes(&reader, size);
        Reader definitions = reader_create(data, 0);
        levels = hybrid_decode(&definitions, 1, page.count);
    } else
        for (int i = 0; i < page.count; ++i)
            Numbers_add(&levels, 1);
    int present = 0;
    for (size_t i = 0; i < levels.count; ++i)
        present += levels.items[i] == 1;
    Values values = decode_values(&reader, column.kind, page.method, present, dictionary),
           out = {0};
    size_t index = 0;
    for (size_t i = 0; i < levels.count; ++i)
        Values_add(&out, levels.items[i] == 1 ? values.items[index++] : null_value());
    return out;
}
static Names verify_and_describe(const File *file, Table original) {
    Names out = {0};
    Names_add(&out, format("file bytes %zu footer_offset %zu footer_bytes %zu", file->data.count,
                           file->footer_offset, file->footer_size));
    Names_add(&out, format("table version %d rows %d columns %zu row_groups %zu", file->version,
                           file->rows, file->columns.count, file->groups.count));
    for (size_t i = 0; i < file->columns.count; ++i)
        Names_add(&out, column_line((int)i, file->columns.items[i]));
    typedef struct {
        size_t bytes;
        int data_pages, dictionary_pages;
        unsigned methods;
    } Summary;
    Summary summaries[12] = {0};
    Number cells = 0, nulls = 0, mismatches = 0, checksum_errors = 0;
    for (size_t g = 0; g < file->groups.count; ++g) {
        Group group = file->groups.items[g];
        size_t size = 0;
        for (size_t i = 0; i < group.chunks.count; ++i)
            size += group.chunks.items[i].size;
        Names_add(&out, format("row_group %zu rows %d first_row %d bytes %zu", g, group.rows,
                               group.first_row, size));
        for (size_t index = 0; index < file->columns.count; ++index) {
            Column column = file->columns.items[index];
            Chunk chunk = group.chunks.items[index];
            Names_add(
                &out,
                format(
                    "chunk %zu %s offset %zu size %zu encodings %s dictionary %s pages %d nulls %d %s",
                    g, column.name, chunk.offset, chunk.size, method_list(chunk.methods),
                    chunk.has_dictionary ? "yes" : "no", chunk.page_count, chunk.nulls,
                    statistics_text(column, chunk.bounds)));
            Summary *summary = &summaries[index];
            summary->bytes += chunk.size;
            summary->data_pages += chunk.page_count;
            summary->dictionary_pages += chunk.has_dictionary;
            summary->methods |= chunk.methods;
            Values dictionary = {0};
            if (chunk.has_dictionary) {
                Page page = chunk.dictionary;
                checksum_errors += adler32(page_body(file, page)) != page.checksum;
                dictionary = decode_dictionary(file, column, page);
                Names_add(
                    &out,
                    format("page %zu %s dict offset %zu header %zu body %zu checksum %s entries %d",
                           g, column.name, page.offset, page.header_size, page.body_size,
                           checksum_text(page.checksum), page.count));
            }
            int row = group.first_row;
            for (size_t p = 0; p < chunk.pages.count; ++p) {
                Page page = chunk.pages.items[p];
                checksum_errors += adler32(page_body(file, page)) != page.checksum;
                Names_add(
                    &out,
                    format(
                        "page %zu %s %zu offset %zu header %zu body %zu checksum %s encoding %s values %d nulls %d %s",
                        g, column.name, p, page.offset, page.header_size, page.body_size,
                        checksum_text(page.checksum), methods[page.method], page.count, page.nulls,
                        statistics_text(column, page.bounds)));
                Values values = decode_page(file, column, page, dictionary);
                for (size_t i = 0; i < values.count; ++i) {
                    ++cells;
                    nulls += values.items[i].null;
                    mismatches += !value_equal(values.items[i], original.items[row++].items[index]);
                }
            }
        }
    }
    for (size_t i = 0; i < file->columns.count; ++i) {
        Summary s = summaries[i];
        Names_add(&out,
                  format("summary %s bytes %zu data_pages %d dictionary_pages %d encodings %s",
                         file->columns.items[i].name, s.bytes, s.data_pages, s.dictionary_pages,
                         method_list(s.methods)));
    }
    Names_add(&out,
              format("roundtrip %s cells %lld nulls %lld mismatches %lld checksum_errors %lld",
                     !mismatches && !checksum_errors ? "ok" : "failed", cells, nulls, mismatches,
                     checksum_errors));
    return out;
}
VECTOR(Conditions, Condition *)
static void condition_leaves(Condition *tree, Conditions *leaves) {
    if (!tree)
        return;
    if (!strcmp(tree->operation, "NOT"))
        condition_leaves(tree->left, leaves);
    else if (!strcmp(tree->operation, "AND") || !strcmp(tree->operation, "OR")) {
        condition_leaves(tree->left, leaves);
        condition_leaves(tree->right, leaves);
    } else
        Conditions_add(leaves, tree);
}
static int find_column(Columns columns, const char *name) {
    for (size_t i = 0; i < columns.count; ++i)
        if (!strcmp(columns.items[i].name, name))
            return (int)i;
    return -1;
}
static char *item_header(Item item) {
    if (!strcmp(item.operation, "COLUMN"))
        return item.name;
    if (!strcmp(item.operation, "COUNT_DISTINCT"))
        return format("COUNT(DISTINCT %s)", item.name);
    return format("%s(%s)", item.operation, *item.name ? item.name : "*");
}
static char *check_query(Query *query, Columns columns) {
    if (query->star)
        for (size_t i = 0; i < columns.count; ++i)
            Items_add(&query->items, (Item){"COLUMN", columns.items[i].name, -1});
    Conditions leaves = {0};
    condition_leaves(query->condition, &leaves);
    Names names = {0};
    for (size_t i = 0; i < query->items.count; ++i)
        if (*query->items.items[i].name)
            Names_add(&names, query->items.items[i].name);
    for (size_t i = 0; i < leaves.count; ++i)
        Names_add(&names, leaves.items[i]->name);
    if (query->group_name)
        Names_add(&names, query->group_name);
    if (query->order_name)
        Names_add(&names, query->order_name);
    for (size_t i = 0; i < names.count; ++i)
        if (find_column(columns, names.items[i]) < 0)
            return "unknown_column";
    for (size_t i = 0; i < leaves.count; ++i) {
        Condition *leaf = leaves.items[i];
        Type kind = columns.items[find_column(columns, leaf->name)].kind,
             expected = kind == T_DATE ? T_STRING : kind;
        for (size_t j = 0; j < leaf->literals.count; ++j)
            if (leaf->literals.items[j].kind != expected)
                return "type_mismatch";
    }
    for (size_t i = 0; i < query->items.count; ++i) {
        Item item = query->items.items[i];
        if ((!strcmp(item.operation, "SUM") || !strcmp(item.operation, "AVG")) &&
            columns.items[find_column(columns, item.name)].kind != T_INT)
            return "bad_aggregate";
    }
    query->aggregate = query->group_name != NULL;
    for (size_t i = 0; i < query->items.count; ++i)
        query->aggregate |= strcmp(query->items.items[i].operation, "COLUMN") != 0;
    if (query->aggregate)
        for (size_t i = 0; i < query->items.count; ++i) {
            Item item = query->items.items[i];
            if (!strcmp(item.operation, "COLUMN") &&
                (!query->group_name || strcmp(item.name, query->group_name)))
                return "not_grouped";
        }
    if (query->aggregate && query->order_name)
        return "bad_order";
    for (size_t i = 0; i < names.count; ++i)
        query->needed |= 1u << find_column(columns, names.items[i]);
    for (size_t i = 0; i < query->items.count; ++i) {
        Item *item = &query->items.items[i];
        item->column = *item->name ? find_column(columns, item->name) : -1;
        Names_add(&query->headers, item_header(*item));
    }
    for (size_t i = 0; i < leaves.count; ++i) {
        Condition *leaf = leaves.items[i];
        leaf->column = find_column(columns, leaf->name);
        query->condition_columns |= 1u << leaf->column;
        if (columns.items[leaf->column].kind == T_DATE)
            for (size_t j = 0; j < leaf->literals.count; ++j)
                leaf->literals.items[j].value =
                    number_value(day_number(leaf->literals.items[j].value.string));
    }
    if (query->group_name)
        query->group = find_column(columns, query->group_name);
    if (query->order_name)
        query->order = find_column(columns, query->order_name);
    return NULL;
}
typedef enum { FALSE_VALUE, TRUE_VALUE, UNKNOWN_VALUE } Truth;
static Truth logical_not(Truth value) {
    return value == UNKNOWN_VALUE ? value : value == TRUE_VALUE ? FALSE_VALUE : TRUE_VALUE;
}
static Truth logical_pair(const char *operation, Truth left, Truth right) {
    if (!strcmp(operation, "AND")) {
        if (left == FALSE_VALUE || right == FALSE_VALUE)
            return FALSE_VALUE;
        return left == UNKNOWN_VALUE || right == UNKNOWN_VALUE ? UNKNOWN_VALUE : TRUE_VALUE;
    }
    if (left == TRUE_VALUE || right == TRUE_VALUE)
        return TRUE_VALUE;
    return left == UNKNOWN_VALUE || right == UNKNOWN_VALUE ? UNKNOWN_VALUE : FALSE_VALUE;
}
static Truth compare_value(const Condition *condition, Value value) {
    const char *op = condition->operation;
    if (!strcmp(op, "IS_NULL"))
        return value.null ? TRUE_VALUE : FALSE_VALUE;
    if (!strcmp(op, "IS_NOT_NULL"))
        return value.null ? FALSE_VALUE : TRUE_VALUE;
    if (value.null)
        return UNKNOWN_VALUE;
    Literals literals = condition->literals;
    bool result = false;
    if (!strcmp(op, "BETWEEN"))
        result = value_compare(value, literals.items[0].value) >= 0 &&
                 value_compare(value, literals.items[1].value) <= 0;
    else if (!strcmp(op, "IN")) {
        for (size_t i = 0; i < literals.count; ++i)
            result |= value_equal(value, literals.items[i].value);
    } else {
        int comparison = value_compare(value, literals.items[0].value);
        if (!strcmp(op, "="))
            result = comparison == 0;
        else if (!strcmp(op, "<>"))
            result = comparison != 0;
        else if (!strcmp(op, "<"))
            result = comparison < 0;
        else if (!strcmp(op, "<="))
            result = comparison <= 0;
        else if (!strcmp(op, ">"))
            result = comparison > 0;
        else
            result = comparison >= 0;
    }
    return result ? TRUE_VALUE : FALSE_VALUE;
}
static Truth evaluate(const Condition *tree, Row row) {
    if (!tree)
        return TRUE_VALUE;
    if (!strcmp(tree->operation, "NOT"))
        return logical_not(evaluate(tree->left, row));
    if (!strcmp(tree->operation, "AND") || !strcmp(tree->operation, "OR"))
        return logical_pair(tree->operation, evaluate(tree->left, row), evaluate(tree->right, row));
    return compare_value(tree, row.items[tree->column]);
}
typedef struct {
    bool can_true, can_false;
} Possibilities;
static Possibilities range_possibilities(const Condition *condition, Value low, Value high) {
    const char *op = condition->operation;
    Literals values = condition->literals;
    if (!strcmp(op, "BETWEEN")) {
        Value first = values.items[0].value, last = values.items[1].value;
        return (Possibilities){value_compare(low, last) <= 0 && value_compare(high, first) >= 0 &&
                                   value_compare(first, last) <= 0,
                               value_compare(low, first) < 0 || value_compare(high, last) > 0};
    }
    if (!strcmp(op, "IN")) {
        bool inside = false, equal = false;
        for (size_t i = 0; i < values.count; ++i) {
            Value v = values.items[i].value;
            inside |= value_compare(low, v) <= 0 && value_compare(v, high) <= 0;
            equal |= value_equal(low, v);
        }
        return (Possibilities){inside, !(value_equal(low, high) && equal)};
    }
    Value value = values.items[0].value;
    bool inside = value_compare(low, value) <= 0 && value_compare(value, high) <= 0,
         constant = value_equal(low, value) && value_equal(high, value);
    if (!strcmp(op, "="))
        return (Possibilities){inside, !constant};
    if (!strcmp(op, "<>"))
        return (Possibilities){!constant, inside};
    if (!strcmp(op, "<"))
        return (Possibilities){value_compare(low, value) < 0, value_compare(high, value) >= 0};
    if (!strcmp(op, "<="))
        return (Possibilities){value_compare(low, value) <= 0, value_compare(high, value) > 0};
    if (!strcmp(op, ">"))
        return (Possibilities){value_compare(high, value) > 0, value_compare(low, value) <= 0};
    return (Possibilities){value_compare(high, value) >= 0, value_compare(low, value) < 0};
}
typedef struct {
    Bounds bounds;
    int nulls, rows;
} Zone;
static unsigned truth_bit(Truth value) { return 1u << value; }
static unsigned zone_values(const Condition *tree, const Zone zones[12]) {
    const char *op = tree->operation;
    if (!strcmp(op, "NOT")) {
        unsigned source = zone_values(tree->left, zones), out = 0;
        for (int i = 0; i < 3; ++i)
            if (source & (1u << i))
                out |= truth_bit(logical_not((Truth)i));
        return out;
    }
    if (!strcmp(op, "AND") || !strcmp(op, "OR")) {
        unsigned left = zone_values(tree->left, zones), right = zone_values(tree->right, zones),
                 out = 0;
        for (int i = 0; i < 3; ++i)
            for (int j = 0; j < 3; ++j)
                if ((left & (1u << i)) && (right & (1u << j)))
                    out |= truth_bit(logical_pair(op, (Truth)i, (Truth)j));
        return out;
    }
    Zone zone = zones[tree->column];
    unsigned out = 0;
    if (!strcmp(op, "IS_NULL") || !strcmp(op, "IS_NOT_NULL")) {
        if (zone.nulls > 0)
            out |= truth_bit(!strcmp(op, "IS_NULL") ? TRUE_VALUE : FALSE_VALUE);
        if (zone.nulls < zone.rows)
            out |= truth_bit(!strcmp(op, "IS_NULL") ? FALSE_VALUE : TRUE_VALUE);
        return out;
    }
    if (zone.nulls > 0)
        out |= truth_bit(UNKNOWN_VALUE);
    if (zone.bounds.present) {
        Possibilities p = range_possibilities(tree, zone.bounds.low, zone.bounds.high);
        if (p.can_true)
            out |= truth_bit(TRUE_VALUE);
        if (p.can_false)
            out |= truth_bit(FALSE_VALUE);
    }
    return out;
}
static const char *scan_names[9] = {
    "row_groups_read", "row_groups_skipped", "pages_read",
    "pages_skipped",   "pages_unneeded",     "dictionary_pages_read",
    "bytes_read",      "rows_scanned",       "rows_matched"};
typedef struct {
    Number values[9];
} Counts;
typedef struct {
    Values values;
    bool ready;
} DictionaryCache;
static Values read_scan_page(const File *file, size_t group, size_t index, int p,
                             DictionaryCache *dictionaries, Counts *counts) {
    Chunk chunk = file->groups.items[group].chunks.items[index];
    Page page = chunk.pages.items[p];
    Values dictionary = {0};
    if (page.method == 1) {
        DictionaryCache *cached = &dictionaries[group * file->columns.count + index];
        if (!cached->ready) {
            cached->ready = true;
            cached->values = decode_dictionary(file, file->columns.items[index], chunk.dictionary);
            ++counts->values[5];
            counts->values[6] += (Number)page_size(chunk.dictionary);
        }
        dictionary = cached->values;
    }
    ++counts->values[2];
    counts->values[6] += (Number)page_size(page);
    return decode_page(file, file->columns.items[index], page, dictionary);
}
static Row empty_row(size_t count) {
    Row row = {.items = allocate(count * sizeof(Value)), .count = count, .capacity = count};
    for (size_t i = 0; i < count; ++i)
        row.items[i] = null_value();
    return row;
}
typedef struct {
    Table matched;
    Counts counts;
    char **records;
} Scan;
static int bit_count(unsigned value) {
    int count = 0;
    while (value) {
        value &= value - 1;
        ++count;
    }
    return count;
}
static Scan scan(const File *file, const Query *query) {
    Scan out = {.records = allocate(file->groups.count * sizeof(char *))};
    DictionaryCache *dictionaries =
        allocate(file->groups.count * file->columns.count * sizeof(DictionaryCache));
    unsigned remaining = query->needed & ~query->condition_columns;
    for (size_t g = 0; g < file->groups.count; ++g) {
        Group group = file->groups.items[g];
        Zone zones[12] = {0};
        for (size_t index = 0; index < file->columns.count; ++index)
            if (query->condition_columns & (1u << index)) {
                Chunk chunk = group.chunks.items[index];
                zones[index] = (Zone){chunk.bounds, chunk.nulls, group.rows};
            }
        if (query->condition && !(zone_values(query->condition, zones) & truth_bit(TRUE_VALUE))) {
            ++out.counts.values[1];
            continue;
        }
        ++out.counts.values[0];
        if (!query->needed) {
            out.counts.values[7] += group.rows;
            for (int row = 0; row < group.rows; ++row)
                Table_add(&out.matched, empty_row(file->columns.count));
            out.records[g] = "-";
            continue;
        }
        char *record = allocate((size_t)group.chunks.items[0].page_count + 1);
        int written = 0;
        for (int p = 0; p < group.chunks.items[0].page_count; ++p) {
            for (size_t index = 0; index < file->columns.count; ++index)
                if (query->condition_columns & (1u << index)) {
                    Page page = group.chunks.items[index].pages.items[p];
                    zones[index] = (Zone){page.bounds, page.nulls, page.count};
                }
            if (query->condition &&
                !(zone_values(query->condition, zones) & truth_bit(TRUE_VALUE))) {
                out.counts.values[3] += bit_count(query->needed);
                record[written++] = 's';
                continue;
            }
            int count = group.chunks.items[0].pages.items[p].count;
            out.counts.values[7] += count;
            Row *rows = allocate((size_t)count * sizeof(Row));
            for (int row = 0; row < count; ++row)
                rows[row] = empty_row(file->columns.count);
            for (size_t index = 0; index < file->columns.count; ++index)
                if (query->condition_columns & (1u << index)) {
                    Values values = read_scan_page(file, g, index, p, dictionaries, &out.counts);
                    for (int row = 0; row < count; ++row)
                        rows[row].items[index] = values.items[row];
                }
            bool *selected = allocate((size_t)count * sizeof(bool));
            int selected_count = 0;
            for (int row = 0; row < count; ++row) {
                selected[row] = evaluate(query->condition, rows[row]) == TRUE_VALUE;
                selected_count += selected[row];
            }
            if (!selected_count && remaining) {
                out.counts.values[4] += bit_count(remaining);
                record[written++] = 'u';
                continue;
            }
            for (size_t index = 0; index < file->columns.count; ++index)
                if (remaining & (1u << index)) {
                    Values values = read_scan_page(file, g, index, p, dictionaries, &out.counts);
                    for (int row = 0; row < count; ++row)
                        rows[row].items[index] = values.items[row];
                }
            for (int row = 0; row < count; ++row)
                if (selected[row])
                    Table_add(&out.matched, rows[row]);
            record[written++] = 'r';
        }
        out.records[g] = record;
    }
    out.counts.values[8] = (Number)out.matched.count;
    return out;
}
typedef struct {
    const Row *row;
    size_t position;
} OrderedRow;
static const Query *sorting_query;
static int row_order(const void *a, const void *b) {
    const OrderedRow *x = a, *y = b;
    int index = sorting_query->group >= 0 ? sorting_query->group : sorting_query->order;
    int comparison = value_compare(x->row->items[index], y->row->items[index]);
    if (sorting_query->group < 0 && sorting_query->descending)
        comparison = -comparison;
    if (comparison)
        return comparison;
    return x->position < y->position ? -1 : x->position > y->position;
}
static int value_order(const void *a, const void *b) {
    return value_compare(*(const Value *)a, *(const Value *)b);
}
static Number gcd_value(Number a, Number b) {
    if (a < 0)
        a = -a;
    while (b) {
        Number next = a % b;
        a = b;
        b = next;
    }
    return a;
}
static char *aggregate_item(Columns columns, Item item, const OrderedRow *rows, size_t count,
                            Value key) {
    const char *op = item.operation;
    int index = item.column;
    if (!strcmp(op, "COLUMN"))
        return value_text(columns.items[index].kind, key, "NULL");
    if (!strcmp(op, "COUNT") && index < 0)
        return format("%zu", count);
    Values values = {0};
    for (size_t i = 0; i < count; ++i)
        if (!rows[i].row->items[index].null)
            Values_add(&values, rows[i].row->items[index]);
    if (!strcmp(op, "COUNT"))
        return format("%zu", values.count);
    if (!strcmp(op, "COUNT_DISTINCT")) {
        if (values.count > 1)
            qsort(values.items, values.count, sizeof(Value), value_order);
        size_t distinct = 0;
        for (size_t i = 0; i < values.count; ++i)
            if (!i || !value_equal(values.items[i], values.items[i - 1]))
                ++distinct;
        return format("%zu", distinct);
    }
    if (!values.count)
        return "NULL";
    if (!strcmp(op, "SUM") || !strcmp(op, "AVG")) {
        Number total = 0;
        for (size_t i = 0; i < values.count; ++i)
            total += values.items[i].number;
        if (!strcmp(op, "SUM"))
            return format("%lld", total);
        Number divisor = gcd_value(total, (Number)values.count), numerator = total / divisor,
               denominator = (Number)values.count / divisor;
        return denominator == 1 ? format("%lld", numerator)
                                : format("%lld/%lld", numerator, denominator);
    }
    Value selected = values.items[0];
    for (size_t i = 1; i < values.count; ++i) {
        int comparison = value_compare(values.items[i], selected);
        if ((!strcmp(op, "MIN") && comparison < 0) || (!strcmp(op, "MAX") && comparison > 0))
            selected = values.items[i];
    }
    return value_text(columns.items[index].kind, selected, "NULL");
}
typedef struct {
    char *kind;
    size_t matched;
    Names output;
} Result;
static void aggregate_row(Result *result, Columns columns, const Query *query,
                          const OrderedRow *rows, size_t count, Value key) {
    Names values = {0};
    for (size_t i = 0; i < query->items.count; ++i)
        Names_add(&values, aggregate_item(columns, query->items.items[i], rows, count, key));
    Names_add(&result->output, join(values, ","));
}
static Result build_result(Columns columns, const Query *query, Table matched) {
    Result result = {.matched = matched.count};
    OrderedRow *ordered = allocate(matched.count * sizeof(OrderedRow));
    for (size_t i = 0; i < matched.count; ++i)
        ordered[i] = (OrderedRow){&matched.items[i], i};
    if (!query->aggregate) {
        result.kind = "rows";
        if (query->order >= 0) {
            sorting_query = query;
            if (matched.count > 1)
                qsort(ordered, matched.count, sizeof(OrderedRow), row_order);
        }
        for (size_t i = 0; i < matched.count; ++i) {
            Names values = {0};
            for (size_t j = 0; j < query->items.count; ++j) {
                int index = query->items.items[j].column;
                Names_add(&values, value_text(columns.items[index].kind,
                                              ordered[i].row->items[index], "NULL"));
            }
            Names_add(&result.output, join(values, ","));
        }
    } else if (query->group < 0) {
        result.kind = "aggregate";
        aggregate_row(&result, columns, query, ordered, matched.count, null_value());
    } else {
        result.kind = "grouped";
        sorting_query = query;
        if (matched.count > 1)
            qsort(ordered, matched.count, sizeof(OrderedRow), row_order);
        for (size_t start = 0; start < matched.count;) {
            Value key = ordered[start].row->items[query->group];
            size_t end = start + 1;
            while (end < matched.count && value_equal(key, ordered[end].row->items[query->group]))
                ++end;
            aggregate_row(&result, columns, query, ordered + start, end - start, key);
            start = end;
        }
    }
    if (query->limit >= 0 && result.output.count > (size_t)query->limit)
        result.output.count = (size_t)query->limit;
    return result;
}
static bool result_equal(Result left, Result right) {
    if (strcmp(left.kind, right.kind) || left.matched != right.matched ||
        left.output.count != right.output.count)
        return false;
    for (size_t i = 0; i < left.output.count; ++i)
        if (strcmp(left.output.items[i], right.output.items[i]))
            return false;
    return true;
}
static char *counts_text(Counts counts) {
    Names parts = {0};
    for (int i = 0; i < 9; ++i)
        Names_add(&parts, format("%s %lld", scan_names[i], counts.values[i]));
    return join(parts, " ");
}
static void execute_queries(const File *file, Table originals, Names queries) {
    FILE *results = fopen("output/query_results.txt", "wb"),
         *statistics_file = fopen("output/query_stats.txt", "wb");
    Counts totals = {0};
    int errors = 0, checks_ok = 0;
    for (size_t i = 0; i < queries.count; ++i) {
        Memory work = {0};
        memory = &work;
        Query query = parse_query(queries.items[i]);
        char *error = check_query(&query, file->columns);
        size_t number = i + 1;
        if (error) {
            fprintf(results, "query %zu error %s\n", number, error);
            fprintf(statistics_file, "query %zu error %s\n", number, error);
            ++errors;
        } else {
            Scan scanned = scan(file, &query);
            Result result = build_result(file->columns, &query, scanned.matched);
            Table reference = {0};
            for (size_t row = 0; row < originals.count; ++row)
                if (evaluate(query.condition, originals.items[row]) == TRUE_VALUE)
                    Table_add(&reference, originals.items[row]);
            bool correct = result_equal(result, build_result(file->columns, &query, reference));
            checks_ok += correct;
            fprintf(results, "query %zu %s matched %zu output %zu\ncolumns %s\n", number,
                    result.kind, result.matched, result.output.count, join(query.headers, ","));
            for (size_t row = 0; row < result.output.count; ++row)
                fprintf(results, "%s\n", result.output.items[row]);
            Names names = {0};
            for (size_t column = 0; column < file->columns.count; ++column)
                if (query.needed & (1u << column))
                    Names_add(&names, file->columns.items[column].name);
            fprintf(statistics_file, "query %zu columns %s %s check %s\n", number,
                    names.count ? join(names, ",") : "-", counts_text(scanned.counts),
                    correct ? "ok" : "mismatch");
            for (size_t g = 0; g < file->groups.count; ++g)
                fprintf(statistics_file, "query %zu row_group %zu %s\n", number, g,
                        scanned.records[g] ? format("pages %s", scanned.records[g]) : "skipped");
            for (int j = 0; j < 9; ++j)
                totals.values[j] += scanned.counts.values[j];
        }
        clear_memory(&work);
        memory = &permanent;
    }
    fprintf(statistics_file, "total queries %zu errors %d %s checks_ok %d\n", queries.count, errors,
            counts_text(totals), checks_ok);
    fclose(results);
    fclose(statistics_file);
}
static void recover(Bytes data) {
    File file = parse_file(data);
    Table rows = {0};
    for (int row = 0; row < file.rows; ++row) {
        Row values = empty_row(file.columns.count);
        for (size_t c = 0; c < values.count; ++c)
            values.items[c].unknown = true;
        Table_add(&rows, values);
    }
    Names out = {0};
    Names_add(&out, format("file bytes %zu rows %d columns %zu row_groups %zu", data.count,
                           file.rows, file.columns.count, file.groups.count));
    for (size_t i = 0; i < file.columns.count; ++i)
        Names_add(&out, column_line((int)i, file.columns.items[i]));
    Number examined = 0, damaged_count = 0, lost_pages = 0, lost_cells = 0;
    for (size_t g = 0; g < file.groups.count; ++g) {
        Group group = file.groups.items[g];
        for (size_t index = 0; index < file.columns.count; ++index) {
            Column column = file.columns.items[index];
            Chunk chunk = group.chunks.items[index];
            Values dictionary = {0};
            bool dictionary_damaged = false;
            int row = group.first_row;
            for (int p = chunk.has_dictionary ? -1 : 0; p < (int)chunk.pages.count; ++p) {
                Page page = p < 0 ? chunk.dictionary : chunk.pages.items[p];
                ++examined;
                Number checksum = adler32(page_body(&file, page));
                bool damaged = checksum != page.checksum;
                if (damaged) {
                    ++damaged_count;
                    Names_add(&out,
                              format("damaged %zu %s %s offset %zu stored %s computed %s", g,
                                     column.name, p < 0 ? "dict" : format("%d", p), page.offset,
                                     checksum_text(page.checksum), checksum_text(checksum)));
                }
                if (p < 0) {
                    dictionary_damaged = damaged;
                    if (!damaged)
                        dictionary = decode_dictionary(&file, column, page);
                    continue;
                }
                char *reason = damaged                                  ? "checksum"
                               : page.method == 1 && dictionary_damaged ? "dictionary"
                                                                        : NULL;
                if (reason) {
                    ++lost_pages;
                    lost_cells += page.count;
                    Names_add(&out, format("lost %zu %s %d rows %d reason %s", g, column.name, p,
                                           page.count, reason));
                } else {
                    Values values = decode_page(&file, column, page, dictionary);
                    for (size_t offset = 0; offset < values.count; ++offset)
                        rows.items[(size_t)row + offset].items[index] = values.items[offset];
                }
                row += page.count;
            }
        }
    }
    Names_add(
        &out,
        format(
            "summary pages %lld damaged %lld lost_pages %lld lost_cells %lld recovered_cells %lld",
            examined, damaged_count, lost_pages, lost_cells,
            (Number)file.rows * (Number)file.columns.count - lost_cells));
    write_lines("recovery.txt", out);
    Names recovered = {0}, names = {0};
    for (size_t i = 0; i < file.columns.count; ++i)
        Names_add(&names, file.columns.items[i].name);
    Names_add(&recovered, join(names, ","));
    for (size_t row = 0; row < rows.count; ++row) {
        Names values = {0};
        for (size_t c = 0; c < file.columns.count; ++c)
            Names_add(&values,
                      value_text(file.columns.items[c].kind, rows.items[row].items[c], ""));
        Names_add(&recovered, join(values, ","));
    }
    write_lines("recovered.csv", recovered);
}
int main(void) {
    Inputs inputs = read_inputs();
    BuiltFile built = build_file(&inputs);
    File file = parse_file(built.data);
    Names hexadecimal_lines = {0};
    for (size_t start = 0; start < built.data.count; start += 32) {
        size_t count = built.data.count - start;
        if (count > 32)
            count = 32;
        Bytes piece = {built.data.items + start, count, count};
        Names_add(&hexadecimal_lines, hexadecimal(piece));
    }
    write_lines("file.hex", hexadecimal_lines);
    write_lines("encoding_report.csv", built.report);
    write_lines("metadata.txt", verify_and_describe(&file, inputs.rows));
    execute_queries(&file, inputs.rows, inputs.queries);
    recover(inputs.damaged);
    clear_memory(&permanent);
    return 0;
}
