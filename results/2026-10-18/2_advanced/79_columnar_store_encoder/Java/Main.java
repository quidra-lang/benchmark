import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.function.*;
public final class Main {
    static final List<String> SCAN_COUNTS = List.of(
        "row_groups_read", "row_groups_skipped", "pages_read", "pages_skipped", "pages_unneeded",
        "dictionary_pages_read", "bytes_read", "rows_scanned", "rows_matched");
    static final class Counts {
        Map<String, Integer> values = new HashMap<>();
        int get(String name) { return values.getOrDefault(name, 0); }
        void add(String name, int amount) { values.put(name, get(name) + amount); }
        String text() {
            List<String> parts = new ArrayList<>();
            for (String name : SCAN_COUNTS)
                parts.add(name + " " + get(name));
            return String.join(" ", parts);
        }
    }
    static final class Page {
        int offset, kind, method, values, nulls, bodySize, headerSize, bodyOffset, size;
        long checksum;
        Encoding.Bounds bounds;
    }
    static final class Chunk {
        byte[] data;
        int offset, size, pageCount, nulls, fallback;
        List<Integer> methods = new ArrayList<>();
        boolean hasDictionary;
        Encoding.Bounds bounds;
        Page dictionary;
        List<Page> pages = new ArrayList<>();
    }
    static final class RowGroup {
        int rows, firstRow;
        List<Chunk> chunks = new ArrayList<>();
        RowGroup(int rows, int firstRow) {
            this.rows = rows;
            this.firstRow = firstRow;
        }
    }
    record Built(byte[] data, List<String> report) {}
    record Store(byte[] data, int version, List<SchemaIo.Column> columns, int rows,
                 List<RowGroup> groups, int footerSize, int footerOffset) {}
    record BoundItem(String operation, int index) {}
    record Plan(List<BoundItem> items, List<String> headers, Query.Condition condition, int group,
                int order, boolean descending, Integer limit, boolean aggregate,
                List<Integer> needed, List<Integer> conditionColumns) {}
    record Checked(String error, Plan plan) {}
    record Zone(Encoding.Bounds bounds, int nulls, int count) {}
    record Possibilities(boolean canTrue, boolean canFalse) {}
    record Scan(List<SchemaIo.Value[]> matched, Counts counts, List<String> records) {}
    record Result(String kind, int matched, List<String> output) {}
    record QueryReports(List<String> results, List<String> statistics) {}
    record Recovery(List<String> report, List<String> rows) {}
    enum Truth { TRUE, FALSE, UNKNOWN }
    static Encoding.Bounds statistics(List<SchemaIo.Value> values) {
        SchemaIo.Value low = null, high = null;
        for (SchemaIo.Value value : values)
            if (value != null) {
                if (low == null || SchemaIo.compare(value, low) < 0)
                    low = value;
                if (high == null || SchemaIo.compare(value, high) > 0)
                    high = value;
            }
        return low == null ? null : new Encoding.Bounds(low, high);
    }
    static String statisticsText(SchemaIo.Column column, Encoding.Bounds bounds) {
        return bounds == null ? "stats none"
                              : "min " + SchemaIo.valueText(column.kind(), bounds.low()) + " max " +
                                    SchemaIo.valueText(column.kind(), bounds.high());
    }
    static String methodList(Collection<Integer> methods) {
        List<String> names = new ArrayList<>();
        for (int method : methods)
            names.add(Encoding.METHODS.get(method));
        return String.join(",", names);
    }
    static String columnLine(int index, SchemaIo.Column column) {
        return "column " + index + " " + column.name() + " " + column.kind() + " " +
            (column.nullable() ? "NULLABLE" : "REQUIRED");
    }
    static byte[] buildPage(SchemaIo.Column column, int kind, int method,
                            List<SchemaIo.Value> values, List<SchemaIo.Value> dictionary) {
        Bitstream.Writer body = new Bitstream.Writer();
        int nulls = 0;
        Encoding.Bounds bounds = null;
        if (kind == 1)
            body.bytes(Encoding.encodeValues(column.kind(), 0, values, null));
        else {
            List<SchemaIo.Value> present = new ArrayList<>();
            List<Long> levels = new ArrayList<>();
            for (SchemaIo.Value value : values) {
                levels.add(value == null ? 0L : 1L);
                if (value == null)
                    nulls++;
                else
                    present.add(value);
            }
            bounds = statistics(values);
            if (column.nullable()) {
                byte[] encoded = Bitstream.hybridEncode(levels, 1);
                body.integer(encoded.length);
                body.bytes(encoded);
            }
            body.bytes(Encoding.encodeValues(column.kind(), method, present, dictionary));
        }
        byte[] data = body.value();
        Bitstream.Writer page = new Bitstream.Writer();
        page.byteValue(kind);
        page.byteValue(method);
        page.uleb(values.size());
        page.uleb(nulls);
        page.uleb(data.length);
        page.integer(Bitstream.adler32(data));
        page.bytes(Encoding.encodeStatistics(column.kind(), bounds));
        page.bytes(data);
        return page.value();
    }
    static Chunk buildChunk(SchemaIo.Column column, List<SchemaIo.Value> values, int method,
                            int pageSize, int dictionaryLimit) {
        List<List<SchemaIo.Value>> pages = new ArrayList<>();
        for (int start = 0; start < values.size(); start += pageSize)
            pages.add(values.subList(start, Math.min(start + pageSize, values.size())));
        List<SchemaIo.Value> dictionary = new ArrayList<>();
        int dictionaryPages = 0;
        if (method == 1) {
            Set<SchemaIo.Value> known = new HashSet<>();
            int dictionaryBytes = 0;
            for (List<SchemaIo.Value> page : pages) {
                List<SchemaIo.Value> additions = new ArrayList<>();
                Set<SchemaIo.Value> proposed = new HashSet<>(known);
                for (SchemaIo.Value value : page)
                    if (value != null && proposed.add(value))
                        additions.add(value);
                int size = dictionaryBytes +
                           Encoding.encodeValues(column.kind(), 0, additions, null).length;
                if (size > dictionaryLimit)
                    break;
                dictionary.addAll(additions);
                known = proposed;
                dictionaryBytes = size;
                dictionaryPages++;
            }
            if (dictionary.isEmpty())
                dictionaryPages = 0;
        }
        Bitstream.Writer writer = new Bitstream.Writer();
        if (dictionaryPages > 0)
            writer.bytes(buildPage(column, 1, 0, dictionary, null));
        Set<Integer> methods = new TreeSet<>();
        for (int p = 0; p < pages.size(); p++) {
            int selected = method == 1 ? (p < dictionaryPages ? 1 : 0) : method;
            methods.add(selected);
            writer.bytes(buildPage(column, 0, selected, pages.get(p), dictionary));
        }
        Chunk chunk = new Chunk();
        chunk.data = writer.value();
        chunk.size = chunk.data.length;
        chunk.methods = new ArrayList<>(methods);
        chunk.hasDictionary = dictionaryPages > 0;
        chunk.pageCount = pages.size();
        for (SchemaIo.Value value : values)
            if (value == null)
                chunk.nulls++;
        chunk.bounds = statistics(values);
        chunk.fallback = method == 1 ? pages.size() - dictionaryPages : 0;
        return chunk;
    }
    static Built buildFile(SchemaIo.Inputs inputs) {
        List<SchemaIo.Column> columns = inputs.columns();
        List<SchemaIo.Value[]> rows = inputs.rows();
        SchemaIo.Options options = inputs.options();
        Bitstream.Writer data = new Bitstream.Writer();
        data.bytes("MPTC".getBytes(StandardCharsets.US_ASCII));
        List<RowGroup> groups = new ArrayList<>();
        List<String> report =
            new ArrayList<>(List.of("row_group,column,encoding,bytes,fallback_pages,chosen"));
        for (int first = 0; first < rows.size(); first += options.rowGroupSize()) {
            List<SchemaIo.Value[]> groupRows =
                rows.subList(first, Math.min(first + options.rowGroupSize(), rows.size()));
            RowGroup group = new RowGroup(groupRows.size(), first);
            int number = groups.size();
            for (int index = 0; index < columns.size(); index++) {
                SchemaIo.Column column = columns.get(index);
                List<SchemaIo.Value> values = new ArrayList<>();
                for (SchemaIo.Value[] row : groupRows)
                    values.add(row[index]);
                Map<Integer, Chunk> candidates = new LinkedHashMap<>();
                for (int method : Encoding.candidates(column.kind()))
                    candidates.put(method, buildChunk(column, values, method, options.pageSize(),
                                                      options.dictionaryLimit()));
                String requested = options.encodings().get(column.name());
                int chosen;
                if (requested.equals("AUTO")) {
                    chosen = Encoding.candidates(column.kind()).getFirst();
                    for (Map.Entry<Integer, Chunk> entry : candidates.entrySet())
                        if (entry.getValue().size < candidates.get(chosen).size)
                            chosen = entry.getKey();
                } else {
                    chosen = Encoding.METHODS.indexOf(requested);
                    if (chosen == 1 && !candidates.get(chosen).hasDictionary)
                        chosen = 0;
                }
                for (Map.Entry<Integer, Chunk> entry : candidates.entrySet()) {
                    Chunk candidate = entry.getValue();
                    report.add(number + "," + column.name() + "," +
                               Encoding.METHODS.get(entry.getKey()) + "," + candidate.size + "," +
                               candidate.fallback + "," +
                               (entry.getKey() == chosen ? "yes" : "no"));
                }
                Chunk chunk = candidates.get(chosen);
                chunk.offset = data.size();
                data.bytes(chunk.data);
                group.chunks.add(chunk);
            }
            groups.add(group);
        }
        Bitstream.Writer footer = new Bitstream.Writer();
        footer.uleb(1);
        footer.uleb(columns.size());
        for (SchemaIo.Column column : columns) {
            footer.uleb(column.name().length());
            footer.bytes(column.name().getBytes(StandardCharsets.US_ASCII));
            footer.byteValue(SchemaIo.TYPES.indexOf(column.kind()));
            footer.byteValue(column.nullable() ? 1 : 0);
        }
        footer.uleb(rows.size());
        footer.uleb(groups.size());
        for (RowGroup group : groups) {
            footer.uleb(group.rows);
            for (int i = 0; i < columns.size(); i++) {
                Chunk chunk = group.chunks.get(i);
                footer.uleb(chunk.offset);
                footer.uleb(chunk.size);
                footer.uleb(chunk.methods.size());
                for (int method : chunk.methods)
                    footer.byteValue(method);
                footer.byteValue(chunk.hasDictionary ? 1 : 0);
                footer.uleb(chunk.pageCount);
                footer.uleb(chunk.nulls);
                footer.bytes(Encoding.encodeStatistics(columns.get(i).kind(), chunk.bounds));
            }
        }
        data.bytes(footer.value());
        data.integer(footer.size());
        data.bytes("MPTC".getBytes(StandardCharsets.US_ASCII));
        return new Built(data.value(), report);
    }
    static Store parseFile(byte[] data) {
        int footerSize = (int)new Bitstream.Reader(data, data.length - 8).integer(),
            footerOffset = data.length - 8 - footerSize;
        Bitstream.Reader reader = new Bitstream.Reader(data, footerOffset);
        int version = (int)reader.uleb(), columnCount = (int)reader.uleb();
        List<SchemaIo.Column> columns = new ArrayList<>();
        for (int i = 0; i < columnCount; i++) {
            String name = new String(reader.read((int)reader.uleb()), StandardCharsets.US_ASCII);
            columns.add(new SchemaIo.Column(name, SchemaIo.TYPES.get(reader.byteValue()),
                                            reader.byteValue() != 0));
        }
        int rows = (int)reader.uleb(), groupCount = (int)reader.uleb(), firstRow = 0;
        List<RowGroup> groups = new ArrayList<>();
        for (int g = 0; g < groupCount; g++) {
            RowGroup group = new RowGroup((int)reader.uleb(), firstRow);
            for (SchemaIo.Column column : columns) {
                Chunk chunk = new Chunk();
                chunk.offset = (int)reader.uleb();
                chunk.size = (int)reader.uleb();
                int methods = (int)reader.uleb();
                for (int i = 0; i < methods; i++)
                    chunk.methods.add(reader.byteValue());
                chunk.hasDictionary = reader.byteValue() != 0;
                chunk.pageCount = (int)reader.uleb();
                chunk.nulls = (int)reader.uleb();
                chunk.bounds = Encoding.decodeStatistics(reader, column.kind());
                group.chunks.add(chunk);
            }
            groups.add(group);
            firstRow += group.rows;
        }
        for (RowGroup group : groups)
            for (int i = 0; i < columns.size(); i++) {
                Chunk chunk = group.chunks.get(i);
                reader = new Bitstream.Reader(data, chunk.offset);
                boolean first = true;
                while (reader.position < chunk.offset + chunk.size) {
                    Page page = new Page();
                    page.offset = reader.position;
                    page.kind = reader.byteValue();
                    page.method = reader.byteValue();
                    page.values = (int)reader.uleb();
                    page.nulls = (int)reader.uleb();
                    page.bodySize = (int)reader.uleb();
                    page.checksum = reader.integer();
                    page.bounds = Encoding.decodeStatistics(reader, columns.get(i).kind());
                    page.headerSize = reader.position - page.offset;
                    page.bodyOffset = reader.position;
                    page.size = page.headerSize + page.bodySize;
                    reader.position += page.bodySize;
                    if (first && chunk.hasDictionary)
                        chunk.dictionary = page;
                    else
                        chunk.pages.add(page);
                    first = false;
                }
            }
        return new Store(data, version, columns, rows, groups, footerSize, footerOffset);
    }
    static byte[] pageBody(Store file, Page page) {
        return Arrays.copyOfRange(file.data(), page.bodyOffset, page.bodyOffset + page.bodySize);
    }
    static List<SchemaIo.Value> decodeDictionary(Store file, SchemaIo.Column column, Page page) {
        return Encoding.decodeValues(new Bitstream.Reader(pageBody(file, page)), column.kind(), 0,
                                     page.values, null);
    }
    static List<SchemaIo.Value> decodePage(Store file, SchemaIo.Column column, Page page,
                                           List<SchemaIo.Value> dictionary) {
        Bitstream.Reader reader = new Bitstream.Reader(pageBody(file, page));
        List<Long> levels;
        if (column.nullable())
            levels = Bitstream.hybridDecode(
                new Bitstream.Reader(reader.read((int)reader.integer())), 1, page.values);
        else
            levels = new ArrayList<>(Collections.nCopies(page.values, 1L));
        int present = 0;
        for (long level : levels)
            if (level == 1)
                present++;
        List<SchemaIo.Value> values = Encoding.decodeValues(reader, column.kind(), page.method,
                                                            present, dictionary),
                             result = new ArrayList<>();
        int index = 0;
        for (long level : levels)
            result.add(level == 1 ? values.get(index++) : null);
        return result;
    }
    static String checksum(long value) {
        String text = Long.toHexString(value);
        return "0".repeat(8 - text.length()) + text;
    }
    static final class Summary {
        int bytes, dataPages, dictionaryPages;
        Set<Integer> methods = new TreeSet<>();
    }
    static List<String> verifyAndDescribe(Store file, List<SchemaIo.Value[]> original) {
        List<SchemaIo.Column> columns = file.columns();
        List<String> lines = new ArrayList<>(
            List.of("file bytes " + file.data().length + " footer_offset " + file.footerOffset() +
                        " footer_bytes " + file.footerSize(),
                    "table version " + file.version() + " rows " + file.rows() + " columns " +
                        columns.size() + " row_groups " + file.groups().size()));
        List<Summary> summaries = new ArrayList<>();
        for (int i = 0; i < columns.size(); i++) {
            lines.add(columnLine(i, columns.get(i)));
            summaries.add(new Summary());
        }
        int cells = 0, nulls = 0, mismatches = 0, checksumErrors = 0;
        for (int g = 0; g < file.groups().size(); g++) {
            RowGroup group = file.groups().get(g);
            int size = 0;
            for (Chunk chunk : group.chunks)
                size += chunk.size;
            lines.add("row_group " + g + " rows " + group.rows + " first_row " + group.firstRow +
                      " bytes " + size);
            for (int i = 0; i < columns.size(); i++) {
                SchemaIo.Column column = columns.get(i);
                Chunk chunk = group.chunks.get(i);
                lines.add("chunk " + g + " " + column.name() + " offset " + chunk.offset +
                          " size " + chunk.size + " encodings " + methodList(chunk.methods) +
                          " dictionary " + (chunk.hasDictionary ? "yes" : "no") + " pages " +
                          chunk.pageCount + " nulls " + chunk.nulls + " " +
                          statisticsText(column, chunk.bounds));
                Summary summary = summaries.get(i);
                summary.bytes += chunk.size;
                summary.dataPages += chunk.pageCount;
                summary.dictionaryPages += chunk.hasDictionary ? 1 : 0;
                summary.methods.addAll(chunk.methods);
                List<SchemaIo.Value> dictionary = null;
                if (chunk.dictionary != null) {
                    Page page = chunk.dictionary;
                    if (Bitstream.adler32(pageBody(file, page)) != page.checksum)
                        checksumErrors++;
                    dictionary = decodeDictionary(file, column, page);
                    lines.add("page " + g + " " + column.name() + " dict offset " + page.offset +
                              " header " + page.headerSize + " body " + page.bodySize +
                              " checksum " + checksum(page.checksum) + " entries " + page.values);
                }
                int rowNumber = group.firstRow;
                for (int p = 0; p < chunk.pages.size(); p++) {
                    Page page = chunk.pages.get(p);
                    if (Bitstream.adler32(pageBody(file, page)) != page.checksum)
                        checksumErrors++;
                    lines.add("page " + g + " " + column.name() + " " + p + " offset " +
                              page.offset + " header " + page.headerSize + " body " +
                              page.bodySize + " checksum " + checksum(page.checksum) +
                              " encoding " + Encoding.METHODS.get(page.method) + " values " +
                              page.values + " nulls " + page.nulls + " " +
                              statisticsText(column, page.bounds));
                    for (SchemaIo.Value value : decodePage(file, column, page, dictionary)) {
                        cells++;
                        if (value == null)
                            nulls++;
                        if (!Objects.equals(value, original.get(rowNumber)[i]))
                            mismatches++;
                        rowNumber++;
                    }
                }
            }
        }
        for (int i = 0; i < columns.size(); i++) {
            Summary summary = summaries.get(i);
            lines.add("summary " + columns.get(i).name() + " bytes " + summary.bytes +
                      " data_pages " + summary.dataPages + " dictionary_pages " +
                      summary.dictionaryPages + " encodings " + methodList(summary.methods));
        }
        lines.add("roundtrip " + (mismatches == 0 && checksumErrors == 0 ? "ok" : "failed") +
                  " cells " + cells + " nulls " + nulls + " mismatches " + mismatches +
                  " checksum_errors " + checksumErrors);
        return lines;
    }
    static List<Query.Comparison> conditionLeaves(Query.Condition tree) {
        List<Query.Comparison> leaves = new ArrayList<>();
        if (tree instanceof Query.Comparison leaf)
            leaves.add(leaf);
        else if (tree instanceof Query.Logical logical) {
            leaves.addAll(conditionLeaves(logical.first()));
            if (logical.second() != null)
                leaves.addAll(conditionLeaves(logical.second()));
        }
        return leaves;
    }
    static String itemHeader(Query.Item item) {
        if (item.operation().equals("COLUMN"))
            return item.name();
        if (item.operation().equals("COUNT_DISTINCT"))
            return "COUNT(DISTINCT " + item.name() + ")";
        return item.operation() + "(" + (item.name() == null ? "*" : item.name()) + ")";
    }
    static Checked checkQuery(Query.Raw raw, List<SchemaIo.Column> columns) {
        Map<String, Integer> indices = new HashMap<>();
        for (int i = 0; i < columns.size(); i++)
            indices.put(columns.get(i).name(), i);
        List<Query.Item> items = raw.items();
        if (items == null) {
            items = new ArrayList<>();
            for (SchemaIo.Column column : columns)
                items.add(new Query.Item("COLUMN", column.name()));
        }
        List<Query.Comparison> leaves = conditionLeaves(raw.condition());
        List<String> names = new ArrayList<>();
        for (Query.Item item : items)
            if (item.name() != null)
                names.add(item.name());
        for (Query.Comparison leaf : leaves)
            names.add(leaf.name);
        if (raw.group() != null)
            names.add(raw.group());
        if (raw.order() != null)
            names.add(raw.order());
        for (String name : names)
            if (!indices.containsKey(name))
                return new Checked("unknown_column", null);
        for (Query.Comparison leaf : leaves) {
            String kind = columns.get(indices.get(leaf.name)).kind(),
                   expected = kind.equals("DATE") ? "STRING" : kind;
            for (Query.Literal literal : leaf.literals)
                if (!literal.kind().equals(expected))
                    return new Checked("type_mismatch", null);
        }
        for (Query.Item item : items)
            if ((item.operation().equals("SUM") || item.operation().equals("AVG")) &&
                !columns.get(indices.get(item.name())).kind().equals("INT"))
                return new Checked("bad_aggregate", null);
        boolean aggregate = raw.group() != null;
        for (Query.Item item : items)
            if (!item.operation().equals("COLUMN"))
                aggregate = true;
        if (aggregate)
            for (Query.Item item : items)
                if (item.operation().equals("COLUMN") && !Objects.equals(item.name(), raw.group()))
                    return new Checked("not_grouped", null);
        if (aggregate && raw.order() != null)
            return new Checked("bad_order", null);
        Set<Integer> needed = new TreeSet<>(), conditionColumns = new TreeSet<>();
        for (String name : names)
            needed.add(indices.get(name));
        for (Query.Comparison leaf : leaves) {
            leaf.index = indices.get(leaf.name);
            conditionColumns.add(leaf.index);
            leaf.values = new ArrayList<>();
            for (Query.Literal literal : leaf.literals)
                leaf.values.add(columns.get(leaf.index).kind().equals("DATE")
                                    ? new SchemaIo.NumberValue(SchemaIo.dayNumber(
                                          ((SchemaIo.TextValue)literal.value()).value()))
                                    : literal.value());
        }
        List<BoundItem> bound = new ArrayList<>();
        List<String> headers = new ArrayList<>();
        for (Query.Item item : items) {
            bound.add(new BoundItem(item.operation(),
                                    item.name() == null ? -1 : indices.get(item.name())));
            headers.add(itemHeader(item));
        }
        return new Checked(null,
                           new Plan(bound, headers, raw.condition(),
                                    raw.group() == null ? -1 : indices.get(raw.group()),
                                    raw.order() == null ? -1 : indices.get(raw.order()),
                                    raw.descending(), raw.limit(), aggregate,
                                    new ArrayList<>(needed), new ArrayList<>(conditionColumns)));
    }
    static Truth logicalNot(Truth value) {
        return value == Truth.UNKNOWN ? Truth.UNKNOWN
        : value == Truth.TRUE         ? Truth.FALSE
                                      : Truth.TRUE;
    }
    static Truth logicalPair(String operation, Truth first, Truth second) {
        if (operation.equals("AND")) {
            if (first == Truth.FALSE || second == Truth.FALSE)
                return Truth.FALSE;
            return first == Truth.UNKNOWN || second == Truth.UNKNOWN ? Truth.UNKNOWN : Truth.TRUE;
        }
        if (first == Truth.TRUE || second == Truth.TRUE)
            return Truth.TRUE;
        return first == Truth.UNKNOWN || second == Truth.UNKNOWN ? Truth.UNKNOWN : Truth.FALSE;
    }
    static Truth compareValue(Query.Comparison leaf, SchemaIo.Value value) {
        if (leaf.operation.equals("IS_NULL"))
            return value == null ? Truth.TRUE : Truth.FALSE;
        if (leaf.operation.equals("IS_NOT_NULL"))
            return value != null ? Truth.TRUE : Truth.FALSE;
        if (value == null)
            return Truth.UNKNOWN;
        boolean matches;
        if (leaf.operation.equals("BETWEEN"))
            matches = SchemaIo.compare(leaf.values.get(0), value) <= 0 &&
                      SchemaIo.compare(value, leaf.values.get(1)) <= 0;
        else if (leaf.operation.equals("IN"))
            matches = leaf.values.contains(value);
        else {
            int compared = SchemaIo.compare(value, leaf.values.getFirst());
            matches = switch (leaf.operation) {
                case "=" -> compared == 0;
                case "<>" -> compared != 0;
                case "<" -> compared < 0;
                case "<=" -> compared <= 0;
                case ">" -> compared > 0;
                default -> compared >= 0;
            };
        }
        return matches ? Truth.TRUE : Truth.FALSE;
    }
    static Truth evaluate(Query.Condition tree, SchemaIo.Value[] row) {
        if (tree == null)
            return Truth.TRUE;
        if (tree instanceof Query.Comparison leaf)
            return compareValue(leaf, row[leaf.index]);
        Query.Logical logical = (Query.Logical)tree;
        Truth first = evaluate(logical.first(), row);
        return logical.operation().equals("NOT")
            ? logicalNot(first)
            : logicalPair(logical.operation(), first, evaluate(logical.second(), row));
    }
    static Possibilities rangePossibilities(Query.Comparison leaf, Encoding.Bounds bounds) {
        SchemaIo.Value low = bounds.low(), high = bounds.high();
        List<SchemaIo.Value> literals = leaf.values;
        String operation = leaf.operation;
        if (operation.equals("BETWEEN")) {
            SchemaIo.Value first = literals.get(0), last = literals.get(1);
            return new Possibilities(
                SchemaIo.compare(low, last) <= 0 && SchemaIo.compare(high, first) >= 0 &&
                    SchemaIo.compare(first, last) <= 0,
                SchemaIo.compare(low, first) < 0 || SchemaIo.compare(high, last) > 0);
        }
        if (operation.equals("IN")) {
            boolean any = false;
            for (SchemaIo.Value value : literals)
                if (SchemaIo.compare(low, value) <= 0 && SchemaIo.compare(value, high) <= 0)
                    any = true;
            return new Possibilities(any, !(low.equals(high) && literals.contains(low)));
        }
        SchemaIo.Value value = literals.getFirst();
        int lo = SchemaIo.compare(low, value), hi = SchemaIo.compare(high, value);
        return switch (operation) {
            case "=" -> new Possibilities(lo <= 0 && hi >= 0, !(lo == 0 && hi == 0));
            case "<>" -> new Possibilities(!(lo == 0 && hi == 0), lo <= 0 && hi >= 0);
            case "<" -> new Possibilities(lo < 0, hi >= 0);
            case "<=" -> new Possibilities(lo <= 0, hi > 0);
            case ">" -> new Possibilities(hi > 0, lo <= 0);
            default -> new Possibilities(hi >= 0, lo < 0);
        };
    }
    static Set<Truth> zoneValues(Query.Condition tree, Map<Integer, Zone> zones) {
        Set<Truth> values = EnumSet.noneOf(Truth.class);
        if (tree instanceof Query.Logical logical) {
            Set<Truth> first = zoneValues(logical.first(), zones);
            if (logical.operation().equals("NOT"))
                for (Truth value : first)
                    values.add(logicalNot(value));
            else
                for (Truth left : first)
                    for (Truth right : zoneValues(logical.second(), zones))
                        values.add(logicalPair(logical.operation(), left, right));
            return values;
        }
        Query.Comparison leaf = (Query.Comparison)tree;
        Zone zone = zones.get(leaf.index);
        if (leaf.operation.equals("IS_NULL") || leaf.operation.equals("IS_NOT_NULL")) {
            if (zone.nulls() > 0)
                values.add(leaf.operation.equals("IS_NULL") ? Truth.TRUE : Truth.FALSE);
            if (zone.nulls() < zone.count())
                values.add(leaf.operation.equals("IS_NOT_NULL") ? Truth.TRUE : Truth.FALSE);
            return values;
        }
        if (zone.nulls() > 0)
            values.add(Truth.UNKNOWN);
        if (zone.bounds() != null) {
            Possibilities possible = rangePossibilities(leaf, zone.bounds());
            if (possible.canTrue())
                values.add(Truth.TRUE);
            if (possible.canFalse())
                values.add(Truth.FALSE);
        }
        return values;
    }
    record PageKey(int group, int column) {}
    static List<SchemaIo.Value> readScanPage(Store file, int g, int index, int p,
                                             Map<PageKey, List<SchemaIo.Value>> dictionaries,
                                             Counts counts) {
        SchemaIo.Column column = file.columns().get(index);
        Chunk chunk = file.groups().get(g).chunks.get(index);
        Page page = chunk.pages.get(p);
        List<SchemaIo.Value> dictionary = null;
        if (page.method == 1) {
            PageKey key = new PageKey(g, index);
            if (!dictionaries.containsKey(key)) {
                dictionaries.put(key, decodeDictionary(file, column, chunk.dictionary));
                counts.add("dictionary_pages_read", 1);
                counts.add("bytes_read", chunk.dictionary.size);
            }
            dictionary = dictionaries.get(key);
        }
        counts.add("pages_read", 1);
        counts.add("bytes_read", page.size);
        return decodePage(file, column, page, dictionary);
    }
    static Scan scan(Store file, Plan plan) {
        Counts counts = new Counts();
        List<String> records = new ArrayList<>();
        List<SchemaIo.Value[]> matched = new ArrayList<>();
        Map<PageKey, List<SchemaIo.Value>> dictionaries = new HashMap<>();
        List<Integer> remaining = new ArrayList<>(plan.needed());
        remaining.removeAll(plan.conditionColumns());
        for (int g = 0; g < file.groups().size(); g++) {
            RowGroup group = file.groups().get(g);
            Map<Integer, Zone> zones = new HashMap<>();
            for (int index : plan.conditionColumns()) {
                Chunk chunk = group.chunks.get(index);
                zones.put(index, new Zone(chunk.bounds, chunk.nulls, group.rows));
            }
            if (plan.condition() != null &&
                !zoneValues(plan.condition(), zones).contains(Truth.TRUE)) {
                counts.add("row_groups_skipped", 1);
                records.add(null);
                continue;
            }
            counts.add("row_groups_read", 1);
            if (plan.needed().isEmpty()) {
                counts.add("rows_scanned", group.rows);
                for (int i = 0; i < group.rows; i++)
                    matched.add(new SchemaIo.Value[file.columns().size()]);
                records.add("-");
                continue;
            }
            StringBuilder record = new StringBuilder();
            for (int p = 0; p < group.chunks.getFirst().pageCount; p++) {
                zones = new HashMap<>();
                for (int index : plan.conditionColumns()) {
                    Page page = group.chunks.get(index).pages.get(p);
                    zones.put(index, new Zone(page.bounds, page.nulls, page.values));
                }
                if (plan.condition() != null &&
                    !zoneValues(plan.condition(), zones).contains(Truth.TRUE)) {
                    counts.add("pages_skipped", plan.needed().size());
                    record.append('s')
                    ;
                    continue;
                }
                int rowCount = group.chunks.getFirst().pages.get(p).values;
                counts.add("rows_scanned", rowCount);
                List<SchemaIo.Value[]> rows = new ArrayList<>();
                for (int i = 0; i < rowCount; i++)
                    rows.add(new SchemaIo.Value[file.columns().size()]);
                for (int index : plan.conditionColumns()) {
                    List<SchemaIo.Value> values =
                        readScanPage(file, g, index, p, dictionaries, counts);
                    for (int i = 0; i < rowCount; i++)
                        rows.get(i)[index] = values.get(i);
                }
                List<Integer> selected = new ArrayList<>();
                for (int i = 0; i < rowCount; i++)
                    if (evaluate(plan.condition(), rows.get(i)) == Truth.TRUE)
                        selected.add(i);
                if (selected.isEmpty() && !remaining.isEmpty()) {
                    counts.add("pages_unneeded", remaining.size());
                    record.append('u')
                    ;
                    continue;
                }
                for (int index : remaining) {
                    List<SchemaIo.Value> values =
                        readScanPage(file, g, index, p, dictionaries, counts);
                    for (int i = 0; i < rowCount; i++)
                        rows.get(i)[index] = values.get(i);
                }
                for (int index : selected)
                    matched.add(rows.get(index));
                record.append('r')
                ;
            }
            records.add(record.toString());
        }
        counts.add("rows_matched", matched.size());
        return new Scan(matched, counts, records);
    }
    static long gcd(long a, long b) {
        a = Math.abs(a);
        while (b != 0) {
            long next = a % b;
            a = b;
            b = next;
        }
        return a;
    }
    static String aggregateItem(List<SchemaIo.Column> columns, BoundItem item,
                                List<SchemaIo.Value[]> rows, SchemaIo.Value key) {
        String op = item.operation();
        int index = item.index();
        if (op.equals("COLUMN"))
            return SchemaIo.valueText(columns.get(index).kind(), key);
        if (op.equals("COUNT") && index < 0)
            return Integer.toString(rows.size());
        List<SchemaIo.Value> values = new ArrayList<>();
        for (SchemaIo.Value[] row : rows)
            if (row[index] != null)
                values.add(row[index]);
        if (op.equals("COUNT"))
            return Integer.toString(values.size());
        if (op.equals("COUNT_DISTINCT"))
            return Integer.toString(new HashSet<>(values).size());
        if (values.isEmpty())
            return "NULL";
        if (op.equals("SUM") || op.equals("AVG")) {
            long total = 0;
            for (SchemaIo.Value value : values)
                total += ((SchemaIo.NumberValue)value).value();
            if (op.equals("SUM"))
                return Long.toString(total);
            long divisor = gcd(total, values.size()), numerator = total / divisor,
                 denominator = values.size() / divisor;
            return denominator == 1 ? Long.toString(numerator) : numerator + "/" + denominator;
        }
        SchemaIo.Value best = values.getFirst();
        for (SchemaIo.Value value : values)
            if ((op.equals("MIN") ? SchemaIo.compare(value, best)
                                  : -SchemaIo.compare(value, best)) < 0)
                best = value;
        return SchemaIo.valueText(columns.get(index).kind(), best);
    }
    static Result buildResult(List<SchemaIo.Column> columns, Plan plan,
                              List<SchemaIo.Value[]> matched) {
        String kind;
        List<String> output = new ArrayList<>();
        if (!plan.aggregate()) {
            kind = "rows";
            List<SchemaIo.Value[]> arranged = new ArrayList<>(matched);
            if (plan.order() >= 0)
                arranged.sort((a, b)
                                  -> (plan.descending() ? -1 : 1) *
                                         SchemaIo.compare(a[plan.order()], b[plan.order()]));
            for (SchemaIo.Value[] row : arranged) {
                List<String> values = new ArrayList<>();
                for (BoundItem item : plan.items())
                    values.add(
                        SchemaIo.valueText(columns.get(item.index()).kind(), row[item.index()]));
                output.add(String.join(",", values));
            }
        } else if (plan.group() < 0) {
            kind = "aggregate";
            List<String> values = new ArrayList<>();
            for (BoundItem item : plan.items())
                values.add(aggregateItem(columns, item, matched, null));
            output.add(String.join(",", values));
        } else {
            kind = "grouped";
            Map<SchemaIo.Value, List<SchemaIo.Value[]>> groups = new TreeMap<>(SchemaIo::compare);
            for (SchemaIo.Value[] row : matched)
                groups.computeIfAbsent(row[plan.group()], key -> new ArrayList<>()).add(row);
            for (Map.Entry<SchemaIo.Value, List<SchemaIo.Value[]>> entry : groups.entrySet()) {
                List<String> values = new ArrayList<>();
                for (BoundItem item : plan.items())
                    values.add(aggregateItem(columns, item, entry.getValue(), entry.getKey()));
                output.add(String.join(",", values));
            }
        }
        if (plan.limit() != null && output.size() > plan.limit())
            output = new ArrayList<>(output.subList(0, plan.limit()));
        return new Result(kind, matched.size(), output);
    }
    static QueryReports executeQueries(Store file, List<SchemaIo.Value[]> originals,
                                       List<String> queries) {
        List<String> results = new ArrayList<>(), statistics = new ArrayList<>();
        Counts totals = new Counts();
        int errors = 0, checksOk = 0;
        for (int number = 1; number <= queries.size(); number++) {
            Checked checked =
                checkQuery(new Query.Parser(queries.get(number - 1)).parse(), file.columns());
            if (checked.error() != null) {
                String line = "query " + number + " error " + checked.error();
                results.add(line);
                statistics.add(line);
                errors++;
                continue;
            }
            Plan plan = checked.plan();
            Scan scan = scan(file, plan);
            Result result = buildResult(file.columns(), plan, scan.matched());
            List<SchemaIo.Value[]> reference = new ArrayList<>();
            for (SchemaIo.Value[] row : originals)
                if (evaluate(plan.condition(), row) == Truth.TRUE)
                    reference.add(row);
            String check =
                result.equals(buildResult(file.columns(), plan, reference)) ? "ok" : "mismatch";
            if (check.equals("ok"))
                checksOk++;
            results.add("query " + number + " " + result.kind() + " matched " + result.matched() +
                        " output " + result.output().size());
            results.add("columns " + String.join(",", plan.headers()));
            results.addAll(result.output());
            List<String> needed = new ArrayList<>();
            for (int index : plan.needed())
                needed.add(file.columns().get(index).name());
            statistics.add("query " + number + " columns " +
                           (needed.isEmpty() ? "-" : String.join(",", needed)) + " " +
                           scan.counts().text() + " check " + check);
            for (int g = 0; g < scan.records().size(); g++)
                statistics.add(
                    "query " + number + " row_group " + g + " " +
                    (scan.records().get(g) == null ? "skipped" : "pages " + scan.records().get(g)));
            for (String name : SCAN_COUNTS)
                totals.add(name, scan.counts().get(name));
        }
        statistics.add("total queries " + queries.size() + " errors " + errors + " " +
                       totals.text() + " checks_ok " + checksOk);
        return new QueryReports(results, statistics);
    }
    static Recovery recover(byte[] data) {
        Store file = parseFile(data);
        List<SchemaIo.Column> columns = file.columns();
        SchemaIo.Value[][] rows = new SchemaIo.Value[file.rows()][columns.size()];
        for (SchemaIo.Value[] row : rows)
            Arrays.fill(row, SchemaIo.Unknown.CELL);
        List<String> lines = new ArrayList<>(List.of("file bytes " + data.length + " rows " +
                                                     file.rows() + " columns " + columns.size() +
                                                     " row_groups " + file.groups().size()));
        for (int i = 0; i < columns.size(); i++)
            lines.add(columnLine(i, columns.get(i)));
        int pagesExamined = 0, damagedCount = 0, lostPages = 0, lostCells = 0;
        for (int g = 0; g < file.groups().size(); g++) {
            RowGroup group = file.groups().get(g);
            for (int i = 0; i < columns.size(); i++) {
                SchemaIo.Column column = columns.get(i);
                Chunk chunk = group.chunks.get(i);
                List<SchemaIo.Value> dictionary = null;
                boolean dictionaryDamaged = false;
                List<Page> pages = new ArrayList<>();
                if (chunk.dictionary != null)
                    pages.add(chunk.dictionary);
                pages.addAll(chunk.pages);
                int rowNumber = group.firstRow, p = 0;
                for (Page page : pages) {
                    pagesExamined++;
                    long computed = Bitstream.adler32(pageBody(file, page));
                    boolean damaged = computed != page.checksum;
                    String label = page.kind == 1 ? "dict" : Integer.toString(p);
                    if (damaged) {
                        damagedCount++;
                        lines.add("damaged " + g + " " + column.name() + " " + label + " offset " +
                                  page.offset + " stored " + checksum(page.checksum) +
                                  " computed " + checksum(computed));
                    }
                    if (page.kind == 1) {
                        dictionaryDamaged = damaged;
                        if (!damaged)
                            dictionary = decodeDictionary(file, column, page);
                        continue;
                    }
                    String reason = damaged                                 ? "checksum"
                                    : page.method == 1 && dictionaryDamaged ? "dictionary"
                                                                            : null;
                    if (reason != null) {
                        lostPages++;
                        lostCells += page.values;
                        lines.add("lost " + g + " " + column.name() + " " + p + " rows " +
                                  page.values + " reason " + reason);
                    } else {
                        List<SchemaIo.Value> values = decodePage(file, column, page, dictionary);
                        for (int j = 0; j < values.size(); j++)
                            rows[rowNumber + j][i] = values.get(j);
                    }
                    rowNumber += page.values;
                    p++;
                }
            }
        }
        lines.add("summary pages " + pagesExamined + " damaged " + damagedCount + " lost_pages " +
                  lostPages + " lost_cells " + lostCells + " recovered_cells " +
                  (file.rows() * columns.size() - lostCells));
        List<String> recovered = new ArrayList<>();
        List<String> names = new ArrayList<>();
        for (SchemaIo.Column column : columns)
            names.add(column.name());
        recovered.add(String.join(",", names));
        for (SchemaIo.Value[] row : rows) {
            List<String> values = new ArrayList<>();
            for (int i = 0; i < columns.size(); i++)
                values.add(row[i] == SchemaIo.Unknown.CELL
                               ? "?"
                               : SchemaIo.valueText(columns.get(i).kind(), row[i], ""));
            recovered.add(String.join(",", values));
        }
        return new Recovery(lines, recovered);
    }
    public static void main(String[] args) throws Exception {
        SchemaIo.Inputs inputs = SchemaIo.readInputs();
        Built built = buildFile(inputs);
        Store file = parseFile(built.data());
        List<String> metadata = verifyAndDescribe(file, inputs.rows());
        QueryReports queries = executeQueries(file, inputs.rows(), inputs.queries());
        Recovery recovery = recover(inputs.damaged());
        List<String> hex = new ArrayList<>();
        for (int start = 0; start < built.data().length; start += 32)
            hex.add(HexFormat.of().formatHex(built.data(), start,
                                             Math.min(start + 32, built.data().length)));
        Map<String, List<String>> outputs = new LinkedHashMap<>();
        outputs.put("file.hex", hex);
        outputs.put("metadata.txt", metadata);
        outputs.put("encoding_report.csv", built.report());
        outputs.put("query_results.txt", queries.results());
        outputs.put("query_stats.txt", queries.statistics());
        outputs.put("recovery.txt", recovery.report());
        outputs.put("recovered.csv", recovery.rows());
        SchemaIo.writeOutputs(outputs);
    }
}
