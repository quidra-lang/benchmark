#include "columnar.hpp"
static Bounds statistics(const Values &values) {
    Bounds out;
    for (const Value &v : values)
        if (!v.null) {
            if (!out)
                out = std::make_pair(v, v);
            else {
                if (v < out->first)
                    out->first = v;
                if (out->second < v)
                    out->second = v;
            }
        }
    return out;
}
static std::string statistics_text(const Column &column, const Bounds &bounds) {
    return bounds ? text("min ", value_text(column.kind, bounds->first), " max ",
                         value_text(column.kind, bounds->second))
                  : "stats none";
}
static std::string method_list(const std::vector<int> &values) {
    Lines names;
    for (int method : values)
        names.push_back(methods[method]);
    return join(names);
}
static std::string column_line(int index, const Column &column) {
    return text("column ", index, " ", column.name, " ", type_names[int(column.kind)], " ",
                column.nullable ? "NULLABLE" : "REQUIRED");
}
struct Page {
    std::size_t offset, header_size, body_size, body_offset;
    int kind, method, count, nulls;
    Number checksum;
    Bounds bounds;
    std::size_t size() const { return header_size + body_size; }
};
struct Chunk {
    std::size_t offset = 0, size = 0;
    std::vector<int> methods;
    bool has_dictionary = false;
    int page_count = 0, nulls = 0;
    Bounds bounds;
    std::optional<Page> dictionary;
    std::vector<Page> pages;
};
struct Group {
    int rows, first_row = 0;
    std::vector<Chunk> chunks;
};
struct BuiltChunk {
    Bytes data;
    Chunk info;
    int fallback = 0;
};
static Bytes build_page(const Column &column, int kind, int method, const Values &values,
                        const Values &dictionary = {}) {
    Bytes body;
    int nulls = 0;
    Bounds bounds;
    if (kind == 1)
        body = encode_values(column.kind, 0, values);
    else {
        Values present;
        Numbers levels;
        for (const Value &v : values) {
            levels.push_back(!v.null);
            if (v.null)
                ++nulls;
            else
                present.push_back(v);
        }
        bounds = statistics(values);
        if (column.nullable) {
            Bytes encoded = hybrid_encode(levels, 1);
            write_integer(body, Number(encoded.size()));
            append(body, encoded);
        }
        append(body, encode_values(column.kind, method, present, dictionary));
    }
    Bytes out{std::uint8_t(kind), std::uint8_t(method)};
    write_uleb(out, Number(values.size()));
    write_uleb(out, nulls);
    write_uleb(out, Number(body.size()));
    write_integer(out, adler32(body));
    append(out, encode_statistics(column.kind, bounds));
    append(out, body);
    return out;
}
static BuiltChunk build_chunk(const Column &column, const Values &values, int method,
                              const Options &options) {
    std::vector<Values> pages;
    for (std::size_t start = 0; start < values.size(); start += options.page_size)
        pages.emplace_back(values.begin() + start,
                           values.begin() + std::min(start + options.page_size, values.size()));
    Values dictionary;
    int dictionary_pages = 0;
    if (method == 1) {
        std::set<Value> known;
        std::size_t dictionary_bytes = 0;
        for (const Values &page : pages) {
            Values additions;
            std::set<Value> proposed = known;
            for (const Value &v : page)
                if (!v.null && proposed.insert(v).second)
                    additions.push_back(v);
            std::size_t size = dictionary_bytes + encode_values(column.kind, 0, additions).size();
            if (size > std::size_t(options.dictionary_limit))
                break;
            dictionary.insert(dictionary.end(), additions.begin(), additions.end());
            known = std::move(proposed);
            dictionary_bytes = size;
            ++dictionary_pages;
        }
        if (dictionary.empty())
            dictionary_pages = 0;
    }
    BuiltChunk out;
    if (dictionary_pages)
        append(out.data, build_page(column, 1, 0, dictionary));
    std::set<int> used;
    for (int p = 0; p < int(pages.size()); ++p) {
        int selected = method == 1 ? (p < dictionary_pages ? 1 : 0) : method;
        used.insert(selected);
        append(out.data, build_page(column, 0, selected, pages[p], dictionary));
    }
    out.info.size = out.data.size();
    out.info.methods.assign(used.begin(), used.end());
    out.info.has_dictionary = dictionary_pages != 0;
    out.info.page_count = int(pages.size());
    out.info.bounds = statistics(values);
    for (const Value &v : values)
        out.info.nulls += v.null;
    out.fallback = method == 1 ? int(pages.size()) - dictionary_pages : 0;
    return out;
}
static std::pair<Bytes, Lines> build_file(const Inputs &inputs) {
    Bytes data{'M', 'P', 'T', 'C'};
    std::vector<Group> groups;
    Lines report{"row_group,column,encoding,bytes,fallback_pages,chosen"};
    for (std::size_t first = 0; first < inputs.rows.size();
         first += inputs.options.row_group_size) {
        int count =
            int(std::min(std::size_t(inputs.options.row_group_size), inputs.rows.size() - first));
        Group group{count, int(first), {}};
        int number = int(groups.size());
        for (int index = 0; index < int(inputs.columns.size()); ++index) {
            const Column &column = inputs.columns[index];
            Values values;
            for (int row = 0; row < count; ++row)
                values.push_back(inputs.rows[first + row][index]);
            std::map<int, BuiltChunk> choices;
            for (int method : candidates(column.kind))
                choices.emplace(method, build_chunk(column, values, method, inputs.options));
            int chosen = inputs.options.encoding[index];
            if (chosen < 0) {
                chosen = choices.begin()->first;
                for (const auto &choice : choices)
                    if (choice.second.data.size() < choices.at(chosen).data.size())
                        chosen = choice.first;
            } else if (chosen == 1 && !choices.at(1).info.has_dictionary)
                chosen = 0;
            for (const auto &choice : choices)
                line(report, number, ",", column.name, ",", methods[choice.first], ",",
                     choice.second.data.size(), ",", choice.second.fallback, ",",
                     choice.first == chosen ? "yes" : "no");
            BuiltChunk &chunk = choices.at(chosen);
            chunk.info.offset = data.size();
            append(data, chunk.data);
            group.chunks.push_back(std::move(chunk.info));
        }
        groups.push_back(std::move(group));
    }
    Bytes footer;
    write_uleb(footer, 1);
    write_uleb(footer, Number(inputs.columns.size()));
    for (const Column &column : inputs.columns) {
        write_uleb(footer, Number(column.name.size()));
        footer.insert(footer.end(), column.name.begin(), column.name.end());
        footer.push_back(std::uint8_t(column.kind));
        footer.push_back(column.nullable);
    }
    write_uleb(footer, Number(inputs.rows.size()));
    write_uleb(footer, Number(groups.size()));
    for (const Group &group : groups) {
        write_uleb(footer, group.rows);
        for (int c = 0; c < int(inputs.columns.size()); ++c) {
            const Chunk &chunk = group.chunks[c];
            write_uleb(footer, Number(chunk.offset));
            write_uleb(footer, Number(chunk.size));
            write_uleb(footer, Number(chunk.methods.size()));
            for (int method : chunk.methods)
                footer.push_back(std::uint8_t(method));
            footer.push_back(chunk.has_dictionary);
            write_uleb(footer, chunk.page_count);
            write_uleb(footer, chunk.nulls);
            append(footer, encode_statistics(inputs.columns[c].kind, chunk.bounds));
        }
    }
    append(data, footer);
    write_integer(data, Number(footer.size()));
    append(data, Bytes{'M', 'P', 'T', 'C'});
    return {data, report};
}
struct File {
    Bytes data;
    int version, rows;
    std::vector<Column> columns;
    std::vector<Group> groups;
    std::size_t footer_size, footer_offset;
};
static File parse_file(Bytes data) {
    File out;
    out.data = std::move(data);
    Reader length{out.data, out.data.size() - 8};
    out.footer_size = std::size_t(length.integer());
    out.footer_offset = out.data.size() - 8 - out.footer_size;
    Reader reader{out.data, out.footer_offset};
    out.version = int(reader.uleb());
    int columns = int(reader.uleb());
    for (int i = 0; i < columns; ++i) {
        std::size_t size = std::size_t(reader.uleb());
        std::string name = reader.string(size);
        Type kind = Type(reader.byte());
        bool nullable = reader.byte() != 0;
        out.columns.push_back({name, kind, nullable});
    }
    out.rows = int(reader.uleb());
    int groups = int(reader.uleb()), first = 0;
    for (int g = 0; g < groups; ++g) {
        Group group{int(reader.uleb()), first, {}};
        first += group.rows;
        for (const Column &column : out.columns) {
            Chunk chunk;
            chunk.offset = std::size_t(reader.uleb());
            chunk.size = std::size_t(reader.uleb());
            int count = int(reader.uleb());
            for (int i = 0; i < count; ++i)
                chunk.methods.push_back(reader.byte());
            chunk.has_dictionary = reader.byte() != 0;
            chunk.page_count = int(reader.uleb());
            chunk.nulls = int(reader.uleb());
            chunk.bounds = decode_statistics(reader, column.kind);
            group.chunks.push_back(std::move(chunk));
        }
        out.groups.push_back(std::move(group));
    }
    for (Group &group : out.groups)
        for (int index = 0; index < columns; ++index) {
            Chunk &chunk = group.chunks[index];
            Reader pages{out.data, chunk.offset};
            int number = 0;
            while (pages.position < chunk.offset + chunk.size) {
                Page page{};
                page.offset = pages.position;
                page.kind = pages.byte();
                page.method = pages.byte();
                page.count = int(pages.uleb());
                page.nulls = int(pages.uleb());
                page.body_size = std::size_t(pages.uleb());
                page.checksum = pages.integer();
                page.bounds = decode_statistics(pages, out.columns[index].kind);
                page.body_offset = pages.position;
                page.header_size = pages.position - page.offset;
                pages.position += page.body_size;
                if (chunk.has_dictionary && number == 0)
                    chunk.dictionary = page;
                else
                    chunk.pages.push_back(page);
                ++number;
            }
        }
    return out;
}
static Bytes page_body(const File &file, const Page &page) {
    return Bytes(file.data.begin() + page.body_offset,
                 file.data.begin() + page.body_offset + page.body_size);
}
static Values decode_dictionary(const File &file, const Column &column, const Page &page) {
    Bytes body = page_body(file, page);
    Reader reader{body};
    return decode_values(reader, column.kind, 0, page.count);
}
static Values decode_page(const File &file, const Column &column, const Page &page,
                          const Values &dictionary = {}) {
    Bytes body = page_body(file, page);
    Reader reader{body};
    Numbers levels(page.count, 1);
    if (column.nullable) {
        std::size_t size = std::size_t(reader.integer());
        Bytes data = reader.read(size);
        Reader definitions{data};
        levels = hybrid_decode(definitions, 1, page.count);
    }
    int present = int(std::count(levels.begin(), levels.end(), 1));
    Values values = decode_values(reader, column.kind, page.method, present, dictionary);
    Values out;
    int index = 0;
    for (Number level : levels)
        out.push_back(level == 1 ? values[index++] : Value{});
    return out;
}
static Lines verify_and_describe(const File &file, const Table &original) {
    Lines out;
    line(out, "file bytes ", file.data.size(), " footer_offset ", file.footer_offset,
         " footer_bytes ", file.footer_size);
    line(out, "table version ", file.version, " rows ", file.rows, " columns ", file.columns.size(),
         " row_groups ", file.groups.size());
    for (int i = 0; i < int(file.columns.size()); ++i)
        out.push_back(column_line(i, file.columns[i]));
    struct Summary {
        std::size_t bytes = 0;
        int data_pages = 0, dictionary_pages = 0;
        std::set<int> methods;
    };
    std::vector<Summary> summaries(file.columns.size());
    Number cells = 0, nulls = 0, mismatches = 0, checksum_errors = 0;
    for (int g = 0; g < int(file.groups.size()); ++g) {
        const Group &group = file.groups[g];
        std::size_t size = 0;
        for (const Chunk &chunk : group.chunks)
            size += chunk.size;
        line(out, "row_group ", g, " rows ", group.rows, " first_row ", group.first_row, " bytes ",
             size);
        for (int index = 0; index < int(file.columns.size()); ++index) {
            const Column &column = file.columns[index];
            const Chunk &chunk = group.chunks[index];
            line(out, "chunk ", g, " ", column.name, " offset ", chunk.offset, " size ", chunk.size,
                 " encodings ", method_list(chunk.methods), " dictionary ",
                 chunk.has_dictionary ? "yes" : "no", " pages ", chunk.page_count, " nulls ",
                 chunk.nulls, " ", statistics_text(column, chunk.bounds));
            Summary &summary = summaries[index];
            summary.bytes += chunk.size;
            summary.data_pages += chunk.page_count;
            summary.dictionary_pages += chunk.has_dictionary;
            summary.methods.insert(chunk.methods.begin(), chunk.methods.end());
            Values dictionary;
            if (chunk.dictionary) {
                const Page &page = *chunk.dictionary;
                checksum_errors += adler32(page_body(file, page)) != page.checksum;
                dictionary = decode_dictionary(file, column, page);
                line(out, "page ", g, " ", column.name, " dict offset ", page.offset, " header ",
                     page.header_size, " body ", page.body_size, " checksum ",
                     checksum_text(page.checksum), " entries ", page.count);
            }
            int row = group.first_row;
            for (int p = 0; p < int(chunk.pages.size()); ++p) {
                const Page &page = chunk.pages[p];
                checksum_errors += adler32(page_body(file, page)) != page.checksum;
                line(out, "page ", g, " ", column.name, " ", p, " offset ", page.offset, " header ",
                     page.header_size, " body ", page.body_size, " checksum ",
                     checksum_text(page.checksum), " encoding ", methods[page.method], " values ",
                     page.count, " nulls ", page.nulls, " ", statistics_text(column, page.bounds));
                for (const Value &value : decode_page(file, column, page, dictionary)) {
                    ++cells;
                    nulls += value.null;
                    mismatches += !(value == original[row++][index]);
                }
            }
        }
    }
    for (int i = 0; i < int(file.columns.size()); ++i) {
        const Summary &s = summaries[i];
        line(out, "summary ", file.columns[i].name, " bytes ", s.bytes, " data_pages ",
             s.data_pages, " dictionary_pages ", s.dictionary_pages, " encodings ",
             method_list(std::vector<int>(s.methods.begin(), s.methods.end())));
    }
    line(out, "roundtrip ", !mismatches && !checksum_errors ? "ok" : "failed", " cells ", cells,
         " nulls ", nulls, " mismatches ", mismatches, " checksum_errors ", checksum_errors);
    return out;
}
static void condition_leaves(const Cond &tree, std::vector<Condition *> &leaves) {
    if (!tree)
        return;
    if (tree->operation == "NOT")
        condition_leaves(tree->left, leaves);
    else if (tree->operation == "AND" || tree->operation == "OR") {
        condition_leaves(tree->left, leaves);
        condition_leaves(tree->right, leaves);
    } else
        leaves.push_back(tree.get());
}
static std::string item_header(const Item &item) {
    if (item.operation == "COLUMN")
        return item.name;
    if (item.operation == "COUNT_DISTINCT")
        return "COUNT(DISTINCT " + item.name + ")";
    return item.operation + "(" + (item.name.empty() ? "*" : item.name) + ")";
}
static std::string check_query(Query &query, const std::vector<Column> &columns) {
    std::map<std::string, int> indices;
    for (int i = 0; i < int(columns.size()); ++i)
        indices[columns[i].name] = i;
    if (query.star)
        for (const Column &column : columns)
            query.items.push_back({"COLUMN", column.name});
    std::vector<Condition *> leaves;
    condition_leaves(query.condition, leaves);
    Lines names;
    for (const Item &item : query.items)
        if (!item.name.empty())
            names.push_back(item.name);
    for (const Condition *leaf : leaves)
        names.push_back(leaf->name);
    if (query.group_name)
        names.push_back(*query.group_name);
    if (query.order_name)
        names.push_back(*query.order_name);
    for (const std::string &name : names)
        if (!indices.count(name))
            return "unknown_column";
    for (const Condition *leaf : leaves) {
        Type kind = columns[indices.at(leaf->name)].kind,
             expected = kind == Type::Date ? Type::String : kind;
        for (const Literal &literal : leaf->literals)
            if (literal.kind != expected)
                return "type_mismatch";
    }
    for (const Item &item : query.items)
        if ((item.operation == "SUM" || item.operation == "AVG") &&
            columns[indices.at(item.name)].kind != Type::Int)
            return "bad_aggregate";
    query.aggregate = query.group_name.has_value();
    for (const Item &item : query.items)
        query.aggregate |= item.operation != "COLUMN";
    if (query.aggregate)
        for (const Item &item : query.items)
            if (item.operation == "COLUMN" && (!query.group_name || item.name != *query.group_name))
                return "not_grouped";
    if (query.aggregate && query.order_name)
        return "bad_order";
    std::set<int> needed, conditions;
    for (const std::string &name : names)
        needed.insert(indices.at(name));
    for (Item &item : query.items) {
        item.column = item.name.empty() ? -1 : indices.at(item.name);
        query.headers.push_back(item_header(item));
    }
    for (Condition *leaf : leaves) {
        leaf->column = indices.at(leaf->name);
        conditions.insert(leaf->column);
        if (columns[leaf->column].kind == Type::Date)
            for (Literal &literal : leaf->literals)
                literal.value = Value::integer(day_number(literal.value.string));
    }
    if (query.group_name)
        query.group = indices.at(*query.group_name);
    if (query.order_name)
        query.order = indices.at(*query.order_name);
    query.needed.assign(needed.begin(), needed.end());
    query.condition_columns.assign(conditions.begin(), conditions.end());
    return "";
}
enum class Truth { False, True, Unknown };
static Truth logical_not(Truth value) {
    return value == Truth::Unknown ? value : value == Truth::True ? Truth::False : Truth::True;
}
static Truth logical_pair(const std::string &operation, Truth a, Truth b) {
    if (operation == "AND") {
        if (a == Truth::False || b == Truth::False)
            return Truth::False;
        return a == Truth::Unknown || b == Truth::Unknown ? Truth::Unknown : Truth::True;
    }
    if (a == Truth::True || b == Truth::True)
        return Truth::True;
    return a == Truth::Unknown || b == Truth::Unknown ? Truth::Unknown : Truth::False;
}
static Truth compare_value(const Condition &condition, const Value &value) {
    const std::string &op = condition.operation;
    if (op == "IS_NULL")
        return value.null ? Truth::True : Truth::False;
    if (op == "IS_NOT_NULL")
        return value.null ? Truth::False : Truth::True;
    if (value.null)
        return Truth::Unknown;
    bool result = false;
    const auto &literals = condition.literals;
    if (op == "BETWEEN")
        result = !(value < literals[0].value) && !(literals[1].value < value);
    else if (op == "IN") {
        for (const Literal &literal : literals)
            result |= value == literal.value;
    } else {
        const Value &other = literals[0].value;
        if (op == "=")
            result = value == other;
        else if (op == "<>")
            result = !(value == other);
        else if (op == "<")
            result = value < other;
        else if (op == "<=")
            result = !(other < value);
        else if (op == ">")
            result = other < value;
        else
            result = !(value < other);
    }
    return result ? Truth::True : Truth::False;
}
static Truth evaluate(const Cond &tree, const Row &row) {
    if (!tree)
        return Truth::True;
    if (tree->operation == "NOT")
        return logical_not(evaluate(tree->left, row));
    if (tree->operation == "AND" || tree->operation == "OR")
        return logical_pair(tree->operation, evaluate(tree->left, row), evaluate(tree->right, row));
    return compare_value(*tree, row[tree->column]);
}
static std::pair<bool, bool> range_possibilities(const Condition &condition, const Value &lo,
                                                 const Value &hi) {
    const std::string &op = condition.operation;
    const auto &values = condition.literals;
    if (op == "BETWEEN") {
        const Value &a = values[0].value, &b = values[1].value;
        return {!(b < lo) && !(hi < a) && !(b < a), lo < a || b < hi};
    }
    if (op == "IN") {
        bool inside = false, equal = false;
        for (const Literal &literal : values) {
            inside |= !(literal.value < lo) && !(hi < literal.value);
            equal |= lo == literal.value;
        }
        return {inside, !(lo == hi && equal)};
    }
    const Value &v = values[0].value;
    bool inside = !(v < lo) && !(hi < v), constant = lo == v && hi == v;
    if (op == "=")
        return {inside, !constant};
    if (op == "<>")
        return {!constant, inside};
    if (op == "<")
        return {lo < v, !(hi < v)};
    if (op == "<=")
        return {!(v < lo), v < hi};
    if (op == ">")
        return {v < hi, !(v < lo)};
    return {!(hi < v), lo < v};
}
struct Zone {
    Bounds bounds;
    int nulls, rows;
};
static unsigned truth_bit(Truth value) { return 1u << int(value); }
static unsigned zone_values(const Cond &tree, const std::vector<Zone> &zones) {
    const std::string &op = tree->operation;
    if (op == "NOT") {
        unsigned source = zone_values(tree->left, zones), out = 0;
        for (int i = 0; i < 3; ++i)
            if (source & (1u << i))
                out |= truth_bit(logical_not(Truth(i)));
        return out;
    }
    if (op == "AND" || op == "OR") {
        unsigned left = zone_values(tree->left, zones), right = zone_values(tree->right, zones),
                 out = 0;
        for (int i = 0; i < 3; ++i)
            for (int j = 0; j < 3; ++j)
                if ((left & (1u << i)) && (right & (1u << j)))
                    out |= truth_bit(logical_pair(op, Truth(i), Truth(j)));
        return out;
    }
    const Zone &zone = zones[tree->column];
    unsigned out = 0;
    if (op == "IS_NULL" || op == "IS_NOT_NULL") {
        if (zone.nulls > 0)
            out |= truth_bit(op == "IS_NULL" ? Truth::True : Truth::False);
        if (zone.nulls < zone.rows)
            out |= truth_bit(op == "IS_NULL" ? Truth::False : Truth::True);
        return out;
    }
    if (zone.nulls > 0)
        out |= truth_bit(Truth::Unknown);
    if (zone.bounds) {
        auto possible = range_possibilities(*tree, zone.bounds->first, zone.bounds->second);
        if (possible.first)
            out |= truth_bit(Truth::True);
        if (possible.second)
            out |= truth_bit(Truth::False);
    }
    return out;
}
static const std::array<std::string, 9> scan_names{
    "row_groups_read", "row_groups_skipped", "pages_read",
    "pages_skipped",   "pages_unneeded",     "dictionary_pages_read",
    "bytes_read",      "rows_scanned",       "rows_matched"};
using Counts = std::array<Number, 9>;
using Dictionaries = std::map<std::pair<int, int>, Values>;
static Values read_scan_page(const File &file, int g, int column, int p, Dictionaries &dictionaries,
                             Counts &counts) {
    const Chunk &chunk = file.groups[g].chunks[column];
    const Page &page = chunk.pages[p];
    Values dictionary;
    if (page.method == 1) {
        auto key = std::make_pair(g, column);
        auto found = dictionaries.find(key);
        if (found == dictionaries.end()) {
            const Page &entry = *chunk.dictionary;
            found = dictionaries.emplace(key, decode_dictionary(file, file.columns[column], entry))
                        .first;
            ++counts[5];
            counts[6] += Number(entry.size());
        }
        dictionary = found->second;
    }
    ++counts[2];
    counts[6] += Number(page.size());
    return decode_page(file, file.columns[column], page, dictionary);
}
struct Scan {
    Table matched;
    Counts counts{};
    std::vector<std::optional<std::string>> records;
};
static Scan scan(const File &file, const Query &query) {
    Scan out;
    Dictionaries dictionaries;
    std::vector<int> remaining;
    for (int index : query.needed)
        if (!std::binary_search(query.condition_columns.begin(), query.condition_columns.end(),
                                index))
            remaining.push_back(index);
    for (int g = 0; g < int(file.groups.size()); ++g) {
        const Group &group = file.groups[g];
        std::vector<Zone> zones(file.columns.size());
        for (int index : query.condition_columns) {
            const Chunk &chunk = group.chunks[index];
            zones[index] = {chunk.bounds, chunk.nulls, group.rows};
        }
        if (query.condition && !(zone_values(query.condition, zones) & truth_bit(Truth::True))) {
            ++out.counts[1];
            out.records.push_back({});
            continue;
        }
        ++out.counts[0];
        if (query.needed.empty()) {
            out.counts[7] += group.rows;
            out.matched.insert(out.matched.end(), group.rows, Row(file.columns.size()));
            out.records.push_back("-");
            continue;
        }
        std::string record;
        for (int p = 0; p < group.chunks[0].page_count; ++p) {
            for (int index : query.condition_columns) {
                const Page &page = group.chunks[index].pages[p];
                zones[index] = {page.bounds, page.nulls, page.count};
            }
            if (query.condition &&
                !(zone_values(query.condition, zones) & truth_bit(Truth::True))) {
                out.counts[3] += Number(query.needed.size());
                record += 's';
                continue;
            }
            int count = group.chunks[0].pages[p].count;
            out.counts[7] += count;
            Table rows(count, Row(file.columns.size()));
            for (int index : query.condition_columns) {
                Values values = read_scan_page(file, g, index, p, dictionaries, out.counts);
                for (int row = 0; row < count; ++row)
                    rows[row][index] = values[row];
            }
            std::vector<int> selected;
            for (int row = 0; row < count; ++row)
                if (evaluate(query.condition, rows[row]) == Truth::True)
                    selected.push_back(row);
            if (selected.empty() && !remaining.empty()) {
                out.counts[4] += Number(remaining.size());
                record += 'u';
                continue;
            }
            for (int index : remaining) {
                Values values = read_scan_page(file, g, index, p, dictionaries, out.counts);
                for (int row = 0; row < count; ++row)
                    rows[row][index] = values[row];
            }
            for (int row : selected)
                out.matched.push_back(std::move(rows[row]));
            record += 'r';
        }
        out.records.push_back(record);
    }
    out.counts[8] = Number(out.matched.size());
    return out;
}
static std::string aggregate_item(const std::vector<Column> &columns, const Item &item,
                                  const Table &rows, const Value &key) {
    const std::string &op = item.operation;
    int index = item.column;
    if (op == "COLUMN")
        return value_text(columns[index].kind, key);
    if (op == "COUNT" && index < 0)
        return std::to_string(rows.size());
    Values values;
    for (const Row &row : rows)
        if (!row[index].null)
            values.push_back(row[index]);
    if (op == "COUNT")
        return std::to_string(values.size());
    if (op == "COUNT_DISTINCT")
        return std::to_string(std::set<Value>(values.begin(), values.end()).size());
    if (values.empty())
        return "NULL";
    if (op == "SUM" || op == "AVG") {
        Number total = 0;
        for (const Value &v : values)
            total += v.number;
        if (op == "SUM")
            return std::to_string(total);
        Number divisor = std::gcd(total, Number(values.size())), numerator = total / divisor,
               denominator = Number(values.size()) / divisor;
        return denominator == 1 ? std::to_string(numerator) : text(numerator, "/", denominator);
    }
    Value value = op == "MIN" ? *std::min_element(values.begin(), values.end())
                              : *std::max_element(values.begin(), values.end());
    return value_text(columns[index].kind, value);
}
struct Result {
    std::string kind;
    std::size_t matched;
    Lines output;
    bool operator==(const Result &other) const {
        return kind == other.kind && matched == other.matched && output == other.output;
    }
};
static Result build_result(const std::vector<Column> &columns, const Query &query,
                           const Table &matched) {
    Result result;
    result.matched = matched.size();
    if (!query.aggregate) {
        result.kind = "rows";
        std::vector<const Row *> arranged;
        for (const Row &row : matched)
            arranged.push_back(&row);
        if (query.order) {
            int index = *query.order;
            std::stable_sort(arranged.begin(), arranged.end(), [&](const Row *a, const Row *b) {
                return query.descending ? (*b)[index] < (*a)[index] : (*a)[index] < (*b)[index];
            });
        }
        for (const Row *row : arranged) {
            Lines values;
            for (const Item &item : query.items)
                values.push_back(value_text(columns[item.column].kind, (*row)[item.column]));
            result.output.push_back(join(values));
        }
    } else {
        result.kind = query.group ? "grouped" : "aggregate";
        std::map<Value, Table> groups;
        if (query.group) {
            for (const Row &row : matched)
                groups[row[*query.group]].push_back(row);
        } else
            groups[Value{}] = matched;
        for (const auto &group : groups) {
            Lines values;
            for (const Item &item : query.items)
                values.push_back(aggregate_item(columns, item, group.second, group.first));
            result.output.push_back(join(values));
        }
    }
    if (query.limit && result.output.size() > std::size_t(*query.limit))
        result.output.resize(*query.limit);
    return result;
}
static std::string counts_text(const Counts &counts) {
    Lines parts;
    for (int i = 0; i < 9; ++i)
        parts.push_back(text(scan_names[i], " ", counts[i]));
    return join(parts, " ");
}
static std::pair<Lines, Lines> execute_queries(const File &file, const Table &originals,
                                               const Lines &queries) {
    Lines results, statistics;
    Counts totals{};
    int errors = 0, checks_ok = 0;
    for (int i = 0; i < int(queries.size()); ++i) {
        int number = i + 1;
        Query query = parse_query(queries[i]);
        std::string error = check_query(query, file.columns);
        if (!error.empty()) {
            std::string source = text("query ", number, " error ", error);
            results.push_back(source);
            statistics.push_back(source);
            ++errors;
            continue;
        }
        Scan scanned = scan(file, query);
        Result result = build_result(file.columns, query, scanned.matched);
        Table reference;
        for (const Row &row : originals)
            if (evaluate(query.condition, row) == Truth::True)
                reference.push_back(row);
        bool correct = result == build_result(file.columns, query, reference);
        checks_ok += correct;
        line(results, "query ", number, " ", result.kind, " matched ", result.matched, " output ",
             result.output.size());
        line(results, "columns ", join(query.headers));
        extend(results, result.output);
        Lines names;
        for (int index : query.needed)
            names.push_back(file.columns[index].name);
        line(statistics, "query ", number, " columns ", names.empty() ? "-" : join(names), " ",
             counts_text(scanned.counts), " check ", correct ? "ok" : "mismatch");
        for (int g = 0; g < int(scanned.records.size()); ++g)
            line(statistics, "query ", number, " row_group ", g, " ",
                 scanned.records[g] ? "pages " + *scanned.records[g] : "skipped");
        for (int j = 0; j < 9; ++j)
            totals[j] += scanned.counts[j];
    }
    line(statistics, "total queries ", queries.size(), " errors ", errors, " ", counts_text(totals),
         " checks_ok ", checks_ok);
    return {results, statistics};
}
static std::pair<Lines, Lines> recover(Bytes data) {
    File file = parse_file(std::move(data));
    Value unknown;
    unknown.unknown = true;
    Table rows(file.rows, Row(file.columns.size(), unknown));
    Lines out;
    line(out, "file bytes ", file.data.size(), " rows ", file.rows, " columns ",
         file.columns.size(), " row_groups ", file.groups.size());
    for (int c = 0; c < int(file.columns.size()); ++c)
        out.push_back(column_line(c, file.columns[c]));
    Number examined = 0, damaged_count = 0, lost_pages = 0, lost_cells = 0;
    for (int g = 0; g < int(file.groups.size()); ++g) {
        const Group &group = file.groups[g];
        for (int index = 0; index < int(file.columns.size()); ++index) {
            const Column &column = file.columns[index];
            const Chunk &chunk = group.chunks[index];
            Values dictionary;
            bool dictionary_damaged = false;
            int row = group.first_row;
            std::vector<std::pair<int, const Page *>> pages;
            if (chunk.dictionary)
                pages.push_back({-1, &*chunk.dictionary});
            for (int p = 0; p < int(chunk.pages.size()); ++p)
                pages.push_back({p, &chunk.pages[p]});
            for (const auto &entry : pages) {
                int number = entry.first;
                const Page &page = *entry.second;
                ++examined;
                Number checksum = adler32(page_body(file, page));
                bool damaged = checksum != page.checksum;
                if (damaged) {
                    ++damaged_count;
                    line(out, "damaged ", g, " ", column.name, " ",
                         number < 0 ? "dict" : std::to_string(number), " offset ", page.offset,
                         " stored ", checksum_text(page.checksum), " computed ",
                         checksum_text(checksum));
                }
                if (number < 0) {
                    dictionary_damaged = damaged;
                    if (!damaged)
                        dictionary = decode_dictionary(file, column, page);
                    continue;
                }
                std::string reason = damaged                                  ? "checksum"
                                     : page.method == 1 && dictionary_damaged ? "dictionary"
                                                                              : "";
                if (!reason.empty()) {
                    ++lost_pages;
                    lost_cells += page.count;
                    line(out, "lost ", g, " ", column.name, " ", number, " rows ", page.count,
                         " reason ", reason);
                } else {
                    Values values = decode_page(file, column, page, dictionary);
                    for (int offset = 0; offset < int(values.size()); ++offset)
                        rows[row + offset][index] = std::move(values[offset]);
                }
                row += page.count;
            }
        }
    }
    line(out, "summary pages ", examined, " damaged ", damaged_count, " lost_pages ", lost_pages,
         " lost_cells ", lost_cells, " recovered_cells ",
         Number(file.rows) * Number(file.columns.size()) - lost_cells);
    Lines recovered, names;
    for (const Column &column : file.columns)
        names.push_back(column.name);
    recovered.push_back(join(names));
    for (const Row &row : rows) {
        Lines values;
        for (int c = 0; c < int(file.columns.size()); ++c)
            values.push_back(value_text(file.columns[c].kind, row[c], ""));
        recovered.push_back(join(values));
    }
    return {out, recovered};
}
int main() {
    Inputs inputs = read_inputs();
    auto built = build_file(inputs);
    File file = parse_file(built.first);
    Lines metadata = verify_and_describe(file, inputs.rows);
    auto queries = execute_queries(file, inputs.rows, inputs.queries);
    auto recovery = recover(inputs.damaged);
    Lines hexadecimal;
    for (std::size_t start = 0; start < built.first.size(); start += 32)
        hexadecimal.push_back(
            hex(Bytes(built.first.begin() + start,
                      built.first.begin() + std::min(start + 32, built.first.size()))));
    write_outputs({{"file.hex", hexadecimal},
                   {"metadata.txt", metadata},
                   {"encoding_report.csv", built.second},
                   {"query_results.txt", queries.first},
                   {"query_stats.txt", queries.second},
                   {"recovery.txt", recovery.first},
                   {"recovered.csv", recovery.second}});
}
