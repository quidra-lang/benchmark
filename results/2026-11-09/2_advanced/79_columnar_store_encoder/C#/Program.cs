using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
public static class Program {
    public static readonly List<string> SCAN_COUNTS =
        new List<string> { "row_groups_read", "row_groups_skipped", "pages_read",
                           "pages_skipped",   "pages_unneeded",     "dictionary_pages_read",
                           "bytes_read",      "rows_scanned",       "rows_matched" };
    public sealed class Counts {
        public Dictionary<string, int> values = new();
        public int Get(string name) { return values.GetValueOrDefault(name, 0); }
        public void Add(string name, int amount) { values[name] = Get(name) + amount; }
        public string Text() {
            List<string> parts = new();
            foreach (string name in SCAN_COUNTS)
                parts.Add(name + " " + Get(name));
            return string.Join(" ", parts);
        }
    }
    public sealed class Page {
        public int offset, kind, method, values, nulls, bodySize, headerSize, bodyOffset, size;
        public long checksum;
        public Encoding.Bounds bounds;
    }
    public sealed class Chunk {
        public byte[] data;
        public int offset, size, pageCount, nulls, fallback;
        public List<int> methods = new();
        public bool hasDictionary;
        public Encoding.Bounds bounds;
        public Page dictionary;
        public List<Page> pages = new();
    }
    public sealed class RowGroup {
        public int rows, firstRow;
        public List<Chunk> chunks = new();
        public RowGroup(int rows, int firstRow) {
            this.rows = rows;
            this.firstRow = firstRow;
        }
    }
    public record Built(byte[] data, List<string> report) {}
    public record Store(byte[] data, int version, List<SchemaIo.Column> columns, int rows,
                        List<RowGroup> groups, int footerSize, int footerOffset) {}
    public record BoundItem(string operation, int index) {}
    public record Plan(List<BoundItem> items, List<string> headers, Query.Condition condition,
                       int group, int order, bool descending, int? limit, bool aggregate,
                       List<int> needed, List<int> conditionColumns) {}
    public record Checked(string error, Plan plan) {}
    public record Zone(Encoding.Bounds bounds, int nulls, int count) {}
    public record Possibilities(bool canTrue, bool canFalse) {}
    public record Scan(List<SchemaIo.Value[]> matched, Counts counts, List<string> records) {}
    public record Result(string kind, int matched, List<string> output) {}
    public record QueryReports(List<string> results, List<string> statistics) {}
    public record Recovery(List<string> report, List<string> rows) {}
    public enum Truth { TRUE, FALSE, UNKNOWN }
    public static Encoding.Bounds Statistics(List<SchemaIo.Value> values) {
        SchemaIo.Value low = null, high = null;
        foreach (SchemaIo.Value value in values)
            if (value != null) {
                if (low == null || SchemaIo.Compare(value, low) < 0)
                    low = value;
                if (high == null || SchemaIo.Compare(value, high) > 0)
                    high = value;
            }
        return low == null ? null : new Encoding.Bounds(low, high);
    }
    public static string StatisticsText(SchemaIo.Column column, Encoding.Bounds bounds) {
        return bounds == null ? "stats none"
                              : "min " + SchemaIo.ValueText(column.kind, bounds.low) + " max " +
                                    SchemaIo.ValueText(column.kind, bounds.high);
    }
    public static string MethodList(IEnumerable<int> methods) {
        List<string> names = new();
        foreach (int method in methods)
            names.Add(Encoding.METHODS[method]);
        return string.Join(",", names);
    }
    public static string ColumnLine(int index, SchemaIo.Column column) {
        return "column " + index + " " + column.name + " " + column.kind + " " +
               (column.nullable ? "NULLABLE" : "REQUIRED");
    }
    public static byte[] BuildPage(SchemaIo.Column column, int kind, int method,
                                   List<SchemaIo.Value> values, List<SchemaIo.Value> dictionary) {
        Bitstream.Writer body = new Bitstream.Writer();
        int nulls = 0;
        Encoding.Bounds bounds = null;
        if (kind == 1)
            body.Bytes(Encoding.EncodeValues(column.kind, 0, values, null));
        else {
            List<SchemaIo.Value> present = new();
            List<long> levels = new();
            foreach (SchemaIo.Value value in values) {
                levels.Add(value == null ? 0L : 1L);
                if (value == null)
                    nulls++;
                else
                    present.Add(value);
            }
            bounds = Statistics(values);
            if (column.nullable) {
                byte[] encoded = Bitstream.HybridEncode(levels, 1);
                body.Integer(encoded.Length);
                body.Bytes(encoded);
            }
            body.Bytes(Encoding.EncodeValues(column.kind, method, present, dictionary));
        }
        byte[] data = body.Value();
        Bitstream.Writer page = new Bitstream.Writer();
        page.ByteValue(kind);
        page.ByteValue(method);
        page.Uleb(values.Count);
        page.Uleb(nulls);
        page.Uleb(data.Length);
        page.Integer(Bitstream.Adler32(data));
        page.Bytes(Encoding.EncodeStatistics(column.kind, bounds));
        page.Bytes(data);
        return page.Value();
    }
    public static Chunk BuildChunk(SchemaIo.Column column, List<SchemaIo.Value> values, int method,
                                   int pageSize, int dictionaryLimit) {
        List<List<SchemaIo.Value>> pages = new();
        for (int start = 0; start < values.Count; start += pageSize)
            pages.Add(values.GetRange(start, Math.Min(start + pageSize, values.Count) - start));
        List<SchemaIo.Value> dictionary = new();
        int dictionaryPages = 0;
        if (method == 1) {
            HashSet<SchemaIo.Value> known = new();
            int dictionaryBytes = 0;
            foreach (List<SchemaIo.Value> page in pages) {
                List<SchemaIo.Value> additions = new();
                HashSet<SchemaIo.Value> proposed = new HashSet<SchemaIo.Value>(known);
                foreach (SchemaIo.Value value in page)
                    if (value != null && proposed.Add(value))
                        additions.Add(value);
                int size =
                    dictionaryBytes + Encoding.EncodeValues(column.kind, 0, additions, null).Length;
                if (size > dictionaryLimit)
                    break;
                dictionary.AddRange(additions);
                known = proposed;
                dictionaryBytes = size;
                dictionaryPages++;
            }
            if (dictionary.Count == 0)
                dictionaryPages = 0;
        }
        Bitstream.Writer writer = new Bitstream.Writer();
        if (dictionaryPages > 0)
            writer.Bytes(BuildPage(column, 1, 0, dictionary, null));
        SortedSet<int> methods = new();
        for (int p = 0; p < pages.Count; p++) {
            int selected = method == 1 ? (p < dictionaryPages ? 1 : 0) : method;
            methods.Add(selected);
            writer.Bytes(BuildPage(column, 0, selected, pages[p], dictionary));
        }
        Chunk chunk = new Chunk();
        chunk.data = writer.Value();
        chunk.size = chunk.data.Length;
        chunk.methods = new(methods);
        chunk.hasDictionary = dictionaryPages > 0;
        chunk.pageCount = pages.Count;
        foreach (SchemaIo.Value value in values)
            if (value == null)
                chunk.nulls++;
        chunk.bounds = Statistics(values);
        chunk.fallback = method == 1 ? pages.Count - dictionaryPages : 0;
        return chunk;
    }
    public static Built BuildFile(SchemaIo.Inputs inputs) {
        List<SchemaIo.Column> columns = inputs.columns;
        List<SchemaIo.Value[]> rows = inputs.rows;
        SchemaIo.Options options = inputs.options;
        Bitstream.Writer data = new Bitstream.Writer();
        data.Bytes(System.Text.Encoding.ASCII.GetBytes("MPTC"));
        List<RowGroup> groups = new();
        List<string> report =
            new(new List<string> { "row_group,column,encoding,bytes,fallback_pages,chosen" });
        for (int first = 0; first < rows.Count; first += options.rowGroupSize) {
            List<SchemaIo.Value[]> groupRows =
                rows.GetRange(first, Math.Min(first + options.rowGroupSize, rows.Count) - first);
            RowGroup group = new RowGroup(groupRows.Count, first);
            int number = groups.Count;
            for (int index = 0; index < columns.Count; index++) {
                SchemaIo.Column column = columns[index];
                List<SchemaIo.Value> values = new();
                foreach (SchemaIo.Value[] row in groupRows)
                    values.Add(row[index]);
                Dictionary<int, Chunk> candidates = new();
                foreach (int method in Encoding.Candidates(column.kind))
                    candidates[method] = BuildChunk(column, values, method, options.pageSize,
                                                    options.dictionaryLimit);
                string requested = options.encodings[column.name];
                int chosen;
                if (requested.Equals("AUTO")) {
                    chosen = Encoding.Candidates(column.kind)[0];
                    foreach (KeyValuePair<int, Chunk> entry in candidates)
                        if (entry.Value.size < candidates[chosen].size)
                            chosen = entry.Key;
                } else {
                    chosen = Encoding.METHODS.IndexOf(requested);
                    if (chosen == 1 && !candidates[chosen].hasDictionary)
                        chosen = 0;
                }
                foreach (KeyValuePair<int, Chunk> entry in candidates) {
                    Chunk candidate = entry.Value;
                    report.Add(number + "," + column.name + "," + Encoding.METHODS[entry.Key] +
                               "," + candidate.size + "," + candidate.fallback + "," +
                               (entry.Key == chosen ? "yes" : "no"));
                }
                Chunk chunk = candidates[chosen];
                chunk.offset = data.Size();
                data.Bytes(chunk.data);
                group.chunks.Add(chunk);
            }
            groups.Add(group);
        }
        Bitstream.Writer footer = new Bitstream.Writer();
        footer.Uleb(1);
        footer.Uleb(columns.Count);
        foreach (SchemaIo.Column column in columns) {
            footer.Uleb(column.name.Length);
            footer.Bytes(System.Text.Encoding.ASCII.GetBytes(column.name));
            footer.ByteValue(SchemaIo.TYPES.IndexOf(column.kind));
            footer.ByteValue(column.nullable ? 1 : 0);
        }
        footer.Uleb(rows.Count);
        footer.Uleb(groups.Count);
        foreach (RowGroup group in groups) {
            footer.Uleb(group.rows);
            for (int i = 0; i < columns.Count; i++) {
                Chunk chunk = group.chunks[i];
                footer.Uleb(chunk.offset);
                footer.Uleb(chunk.size);
                footer.Uleb(chunk.methods.Count);
                foreach (int method in chunk.methods)
                    footer.ByteValue(method);
                footer.ByteValue(chunk.hasDictionary ? 1 : 0);
                footer.Uleb(chunk.pageCount);
                footer.Uleb(chunk.nulls);
                footer.Bytes(Encoding.EncodeStatistics(columns[i].kind, chunk.bounds));
            }
        }
        data.Bytes(footer.Value());
        data.Integer(footer.Size());
        data.Bytes(System.Text.Encoding.ASCII.GetBytes("MPTC"));
        return new Built(data.Value(), report);
    }
    public static Store ParseFile(byte[] data) {
        int footerSize = (int)new Bitstream.Reader(data, data.Length - 8).Integer(),
            footerOffset = data.Length - 8 - footerSize;
        Bitstream.Reader reader = new Bitstream.Reader(data, footerOffset);
        int version = (int)reader.Uleb(), columnCount = (int)reader.Uleb();
        List<SchemaIo.Column> columns = new();
        for (int i = 0; i < columnCount; i++) {
            string name = System.Text.Encoding.ASCII.GetString(reader.Read((int)reader.Uleb()));
            columns.Add(new SchemaIo.Column(name, SchemaIo.TYPES[reader.ByteValue()],
                                            reader.ByteValue() != 0));
        }
        int rows = (int)reader.Uleb(), groupCount = (int)reader.Uleb(), firstRow = 0;
        List<RowGroup> groups = new();
        for (int g = 0; g < groupCount; g++) {
            RowGroup group = new RowGroup((int)reader.Uleb(), firstRow);
            foreach (SchemaIo.Column column in columns) {
                Chunk chunk = new Chunk();
                chunk.offset = (int)reader.Uleb();
                chunk.size = (int)reader.Uleb();
                int methods = (int)reader.Uleb();
                for (int i = 0; i < methods; i++)
                    chunk.methods.Add(reader.ByteValue());
                chunk.hasDictionary = reader.ByteValue() != 0;
                chunk.pageCount = (int)reader.Uleb();
                chunk.nulls = (int)reader.Uleb();
                chunk.bounds = Encoding.DecodeStatistics(reader, column.kind);
                group.chunks.Add(chunk);
            }
            groups.Add(group);
            firstRow += group.rows;
        }
        foreach (RowGroup group in groups)
            for (int i = 0; i < columns.Count; i++) {
                Chunk chunk = group.chunks[i];
                reader = new Bitstream.Reader(data, chunk.offset);
                bool first = true;
                while (reader.position < chunk.offset + chunk.size) {
                    Page page = new Page();
                    page.offset = reader.position;
                    page.kind = reader.ByteValue();
                    page.method = reader.ByteValue();
                    page.values = (int)reader.Uleb();
                    page.nulls = (int)reader.Uleb();
                    page.bodySize = (int)reader.Uleb();
                    page.checksum = reader.Integer();
                    page.bounds = Encoding.DecodeStatistics(reader, columns[i].kind);
                    page.headerSize = reader.position - page.offset;
                    page.bodyOffset = reader.position;
                    page.size = page.headerSize + page.bodySize;
                    reader.position += page.bodySize;
                    if (first && chunk.hasDictionary)
                        chunk.dictionary = page;
                    else
                        chunk.pages.Add(page);
                    first = false;
                }
            }
        return new Store(data, version, columns, rows, groups, footerSize, footerOffset);
    }
    public static byte[] PageBody(Store file, Page page) {
        return file.data[(page.bodyOffset)..(page.bodyOffset + page.bodySize)];
    }
    public static List<SchemaIo.Value> DecodeDictionary(Store file, SchemaIo.Column column,
                                                        Page page) {
        return Encoding.DecodeValues(new Bitstream.Reader(PageBody(file, page)), column.kind, 0,
                                     page.values, null);
    }
    public static List<SchemaIo.Value> DecodePage(Store file, SchemaIo.Column column, Page page,
                                                  List<SchemaIo.Value> dictionary) {
        Bitstream.Reader reader = new Bitstream.Reader(PageBody(file, page));
        List<long> levels;
        if (column.nullable)
            levels = Bitstream.HybridDecode(
                new Bitstream.Reader(reader.Read((int)reader.Integer())), 1, page.values);
        else
            levels = new(Enumerable.Repeat(1L, page.values));
        int present = 0;
        foreach (long level in levels)
            if (level == 1)
                present++;
        List<SchemaIo.Value> values = Encoding.DecodeValues(reader, column.kind, page.method,
                                                            present, dictionary),
                             result = new();
        int index = 0;
        foreach (long level in levels)
            result.Add(level == 1 ? values[index++] : null);
        return result;
    }
    public static string Checksum(long value) {
        string text = value.ToString("x");
        return new string('0', 8 - text.Length) + text;
    }
    public sealed class Summary {
        public int bytes, dataPages, dictionaryPages;
        public SortedSet<int> methods = new();
    }
    public static List<string> VerifyAndDescribe(Store file, List<SchemaIo.Value[]> original) {
        List<SchemaIo.Column> columns = file.columns;
        List<string> lines =
            new(new List<string> { "file bytes " + file.data.Length + " footer_offset " +
                                       file.footerOffset + " footer_bytes " + file.footerSize,
                                   "table version " + file.version + " rows " + file.rows +
                                       " columns " + columns.Count + " row_groups " +
                                       file.groups.Count });
        List<Summary> summaries = new();
        for (int i = 0; i < columns.Count; i++) {
            lines.Add(ColumnLine(i, columns[i]));
            summaries.Add(new Summary());
        }
        int cells = 0, nulls = 0, mismatches = 0, checksumErrors = 0;
        for (int g = 0; g < file.groups.Count; g++) {
            RowGroup group = file.groups[g];
            int size = 0;
            foreach (Chunk chunk in group.chunks)
                size += chunk.size;
            lines.Add("row_group " + g + " rows " + group.rows + " first_row " + group.firstRow +
                      " bytes " + size);
            for (int i = 0; i < columns.Count; i++) {
                SchemaIo.Column column = columns[i];
                Chunk chunk = group.chunks[i];
                lines.Add("chunk " + g + " " + column.name + " offset " + chunk.offset + " size " +
                          chunk.size + " encodings " + MethodList(chunk.methods) + " dictionary " +
                          (chunk.hasDictionary ? "yes" : "no") + " pages " + chunk.pageCount +
                          " nulls " + chunk.nulls + " " + StatisticsText(column, chunk.bounds));
                Summary summary = summaries[i];
                summary.bytes += chunk.size;
                summary.dataPages += chunk.pageCount;
                summary.dictionaryPages += chunk.hasDictionary ? 1 : 0;
                summary.methods.UnionWith(chunk.methods);
                List<SchemaIo.Value> dictionary = null;
                if (chunk.dictionary != null) {
                    Page page = chunk.dictionary;
                    if (Bitstream.Adler32(PageBody(file, page)) != page.checksum)
                        checksumErrors++;
                    dictionary = DecodeDictionary(file, column, page);
                    lines.Add("page " + g + " " + column.name + " dict offset " + page.offset +
                              " header " + page.headerSize + " body " + page.bodySize +
                              " checksum " + Checksum(page.checksum) + " entries " + page.values);
                }
                int rowNumber = group.firstRow;
                for (int p = 0; p < chunk.pages.Count; p++) {
                    Page page = chunk.pages[p];
                    if (Bitstream.Adler32(PageBody(file, page)) != page.checksum)
                        checksumErrors++;
                    lines.Add("page " + g + " " + column.name + " " + p + " offset " + page.offset +
                              " header " + page.headerSize + " body " + page.bodySize +
                              " checksum " + Checksum(page.checksum) + " encoding " +
                              Encoding.METHODS[page.method] + " values " + page.values + " nulls " +
                              page.nulls + " " + StatisticsText(column, page.bounds));
                    foreach (SchemaIo.Value value in DecodePage(file, column, page, dictionary)) {
                        cells++;
                        if (value == null)
                            nulls++;
                        if (!object.Equals(value, original[rowNumber][i]))
                            mismatches++;
                        rowNumber++;
                    }
                }
            }
        }
        for (int i = 0; i < columns.Count; i++) {
            Summary summary = summaries[i];
            lines.Add("summary " + columns[i].name + " bytes " + summary.bytes + " data_pages " +
                      summary.dataPages + " dictionary_pages " + summary.dictionaryPages +
                      " encodings " + MethodList(summary.methods));
        }
        lines.Add("roundtrip " + (mismatches == 0 && checksumErrors == 0 ? "ok" : "failed") +
                  " cells " + cells + " nulls " + nulls + " mismatches " + mismatches +
                  " checksum_errors " + checksumErrors);
        return lines;
    }
    public static List<Query.Comparison> ConditionLeaves(Query.Condition tree) {
        List<Query.Comparison> leaves = new();
        if (tree is Query.Comparison leaf)
            leaves.Add(leaf);
        else if (tree is Query.Logical logical) {
            leaves.AddRange(ConditionLeaves(logical.first));
            if (logical.second != null)
                leaves.AddRange(ConditionLeaves(logical.second));
        }
        return leaves;
    }
    public static string ItemHeader(Query.Item item) {
        if (item.operation.Equals("COLUMN"))
            return item.name;
        if (item.operation.Equals("COUNT_DISTINCT"))
            return "COUNT(DISTINCT " + item.name + ")";
        return item.operation + "(" + (item.name == null ? "*" : item.name) + ")";
    }
    public static Checked CheckQuery(Query.Raw raw, List<SchemaIo.Column> columns) {
        Dictionary<string, int> indices = new();
        for (int i = 0; i < columns.Count; i++)
            indices[columns[i].name] = i;
        List<Query.Item> items = raw.items;
        if (items == null) {
            items = new();
            foreach (SchemaIo.Column column in columns)
                items.Add(new Query.Item("COLUMN", column.name));
        }
        List<Query.Comparison> leaves = ConditionLeaves(raw.condition);
        List<string> names = new();
        foreach (Query.Item item in items)
            if (item.name != null)
                names.Add(item.name);
        foreach (Query.Comparison leaf in leaves)
            names.Add(leaf.name);
        if (raw.group != null)
            names.Add(raw.group);
        if (raw.order != null)
            names.Add(raw.order);
        foreach (string name in names)
            if (!indices.ContainsKey(name))
                return new Checked("unknown_column", null);
        foreach (Query.Comparison leaf in leaves) {
            string kind = columns[indices[leaf.name]].kind,
                   expected = kind.Equals("DATE") ? "STRING" : kind;
            foreach (Query.Literal literal in leaf.literals)
                if (!literal.kind.Equals(expected))
                    return new Checked("type_mismatch", null);
        }
        foreach (Query.Item item in items)
            if ((item.operation.Equals("SUM") || item.operation.Equals("AVG")) &&
                !columns[indices[item.name]].kind.Equals("INT"))
                return new Checked("bad_aggregate", null);
        bool aggregate = raw.group != null;
        foreach (Query.Item item in items)
            if (!item.operation.Equals("COLUMN"))
                aggregate = true;
        if (aggregate)
            foreach (Query.Item item in items)
                if (item.operation.Equals("COLUMN") && !object.Equals(item.name, raw.group))
                    return new Checked("not_grouped", null);
        if (aggregate && raw.order != null)
            return new Checked("bad_order", null);
        SortedSet<int> needed = new(), conditionColumns = new();
        foreach (string name in names)
            needed.Add(indices[name]);
        foreach (Query.Comparison leaf in leaves) {
            leaf.index = indices[leaf.name];
            conditionColumns.Add(leaf.index);
            leaf.values = new();
            foreach (Query.Literal literal in leaf.literals)
                leaf.values.Add(columns[leaf.index].kind.Equals("DATE")
                                    ? new SchemaIo.NumberValue(SchemaIo.DayNumber(
                                          ((SchemaIo.TextValue)literal.value).value))
                                    : literal.value);
        }
        List<BoundItem> bound = new();
        List<string> headers = new();
        foreach (Query.Item item in items) {
            bound.Add(new BoundItem(item.operation, item.name == null ? -1 : indices[item.name]));
            headers.Add(ItemHeader(item));
        }
        return new Checked(null,
                           new Plan(bound, headers, raw.condition,
                                    raw.group == null ? -1 : indices[raw.group],
                                    raw.order == null ? -1 : indices[raw.order], raw.descending,
                                    raw.limit, aggregate, new(needed), new(conditionColumns)));
    }
    public static Truth LogicalNot(Truth value) {
        return value == Truth.UNKNOWN ? Truth.UNKNOWN
               : value == Truth.TRUE  ? Truth.FALSE
                                      : Truth.TRUE;
    }
    public static Truth LogicalPair(string operation, Truth first, Truth second) {
        if (operation.Equals("AND")) {
            if (first == Truth.FALSE || second == Truth.FALSE)
                return Truth.FALSE;
            return first == Truth.UNKNOWN || second == Truth.UNKNOWN ? Truth.UNKNOWN : Truth.TRUE;
        }
        if (first == Truth.TRUE || second == Truth.TRUE)
            return Truth.TRUE;
        return first == Truth.UNKNOWN || second == Truth.UNKNOWN ? Truth.UNKNOWN : Truth.FALSE;
    }
    public static Truth CompareValue(Query.Comparison leaf, SchemaIo.Value value) {
        if (leaf.operation.Equals("IS_NULL"))
            return value == null ? Truth.TRUE : Truth.FALSE;
        if (leaf.operation.Equals("IS_NOT_NULL"))
            return value != null ? Truth.TRUE : Truth.FALSE;
        if (value == null)
            return Truth.UNKNOWN;
        bool matches;
        if (leaf.operation.Equals("BETWEEN"))
            matches = SchemaIo.Compare(leaf.values[0], value) <= 0 &&
                      SchemaIo.Compare(value, leaf.values[1]) <= 0;
        else if (leaf.operation.Equals("IN"))
            matches = leaf.values.Contains(value);
        else {
            int compared = SchemaIo.Compare(value, leaf.values[0]);
            matches = (leaf.operation) switch {
                "=" => compared == 0,  "<>" => compared != 0, "<" => compared < 0,
                "<=" => compared <= 0, ">" => compared > 0,
                _ => compared >= 0,
            };
        }
        return matches ? Truth.TRUE : Truth.FALSE;
    }
    public static Truth Evaluate(Query.Condition tree, SchemaIo.Value[] row) {
        if (tree == null)
            return Truth.TRUE;
        if (tree is Query.Comparison leaf)
            return CompareValue(leaf, row[leaf.index]);
        Query.Logical logical = (Query.Logical)tree;
        Truth first = Evaluate(logical.first, row);
        return logical.operation.Equals("NOT")
                   ? LogicalNot(first)
                   : LogicalPair(logical.operation, first, Evaluate(logical.second, row));
    }
    public static Possibilities RangePossibilities(Query.Comparison leaf, Encoding.Bounds bounds) {
        SchemaIo.Value low = bounds.low, high = bounds.high;
        List<SchemaIo.Value> literals = leaf.values;
        string operation = leaf.operation;
        if (operation.Equals("BETWEEN")) {
            SchemaIo.Value first = literals[0], last = literals[1];
            return new Possibilities(
                SchemaIo.Compare(low, last) <= 0 && SchemaIo.Compare(high, first) >= 0 &&
                    SchemaIo.Compare(first, last) <= 0,
                SchemaIo.Compare(low, first) < 0 || SchemaIo.Compare(high, last) > 0);
        }
        if (operation.Equals("IN")) {
            bool any = false;
            foreach (SchemaIo.Value literalValue in literals)
                if (SchemaIo.Compare(low, literalValue) <= 0 &&
                    SchemaIo.Compare(literalValue, high) <= 0)
                    any = true;
            return new Possibilities(any, !(low.Equals(high) && literals.Contains(low)));
        }
        SchemaIo.Value value = literals[0];
        int lo = SchemaIo.Compare(low, value), hi = SchemaIo.Compare(high, value);
        return (operation) switch {
            "=" => new Possibilities(lo <= 0 && hi >= 0, !(lo == 0 && hi == 0)),
            "<>" => new Possibilities(!(lo == 0 && hi == 0), lo <= 0 && hi >= 0),
            "<" => new Possibilities(lo < 0, hi >= 0),
            "<=" => new Possibilities(lo <= 0, hi > 0),
            ">" => new Possibilities(hi > 0, lo <= 0),
            _ => new Possibilities(hi >= 0, lo < 0),
        };
    }
    public static HashSet<Truth> ZoneValues(Query.Condition tree, Dictionary<int, Zone> zones) {
        HashSet<Truth> values = new HashSet<Truth>();
        if (tree is Query.Logical logical) {
            HashSet<Truth> first = ZoneValues(logical.first, zones);
            if (logical.operation.Equals("NOT"))
                foreach (Truth value in first)
                    values.Add(LogicalNot(value));
            else
                foreach (Truth left in first)
                    foreach (Truth right in ZoneValues(logical.second, zones))
                        values.Add(LogicalPair(logical.operation, left, right));
            return values;
        }
        Query.Comparison leaf = (Query.Comparison)tree;
        Zone zone = zones[leaf.index];
        if (leaf.operation.Equals("IS_NULL") || leaf.operation.Equals("IS_NOT_NULL")) {
            if (zone.nulls > 0)
                values.Add(leaf.operation.Equals("IS_NULL") ? Truth.TRUE : Truth.FALSE);
            if (zone.nulls < zone.count)
                values.Add(leaf.operation.Equals("IS_NOT_NULL") ? Truth.TRUE : Truth.FALSE);
            return values;
        }
        if (zone.nulls > 0)
            values.Add(Truth.UNKNOWN);
        if (zone.bounds != null) {
            Possibilities possible = RangePossibilities(leaf, zone.bounds);
            if (possible.canTrue)
                values.Add(Truth.TRUE);
            if (possible.canFalse)
                values.Add(Truth.FALSE);
        }
        return values;
    }
    public record PageKey(int group, int column) {}
    public static List<SchemaIo.Value>
    ReadScanPage(Store file, int g, int index, int p,
                 Dictionary<PageKey, List<SchemaIo.Value>> dictionaries, Counts counts) {
        SchemaIo.Column column = file.columns[index];
        Chunk chunk = file.groups[g].chunks[index];
        Page page = chunk.pages[p];
        List<SchemaIo.Value> dictionary = null;
        if (page.method == 1) {
            PageKey key = new PageKey(g, index);
            if (!dictionaries.ContainsKey(key)) {
                dictionaries[key] = DecodeDictionary(file, column, chunk.dictionary);
                counts.Add("dictionary_pages_read", 1);
                counts.Add("bytes_read", chunk.dictionary.size);
            }
            dictionary = dictionaries[key];
        }
        counts.Add("pages_read", 1);
        counts.Add("bytes_read", page.size);
        return DecodePage(file, column, page, dictionary);
    }
    public static Scan PerformScan(Store file, Plan plan) {
        Counts counts = new Counts();
        List<string> records = new();
        List<SchemaIo.Value[]> matched = new();
        Dictionary<PageKey, List<SchemaIo.Value>> dictionaries = new();
        List<int> remaining = new(plan.needed);
        remaining.RemoveAll(x => plan.conditionColumns.Contains(x));
        for (int g = 0; g < file.groups.Count; g++) {
            RowGroup group = file.groups[g];
            Dictionary<int, Zone> zones = new();
            foreach (int index in plan.conditionColumns) {
                Chunk chunk = group.chunks[index];
                zones[index] = new Zone(chunk.bounds, chunk.nulls, group.rows);
            }
            if (plan.condition != null && !ZoneValues(plan.condition, zones).Contains(Truth.TRUE)) {
                counts.Add("row_groups_skipped", 1);
                records.Add(null);
                continue;
            }
            counts.Add("row_groups_read", 1);
            if (plan.needed.Count == 0) {
                counts.Add("rows_scanned", group.rows);
                for (int i = 0; i < group.rows; i++)
                    matched.Add(new SchemaIo.Value[file.columns.Count]);
                records.Add("-");
                continue;
            }
            StringBuilder record = new StringBuilder();
            for (int p = 0; p < group.chunks[0].pageCount; p++) {
                zones = new();
                foreach (int index in plan.conditionColumns) {
                    Page page = group.chunks[index].pages[p];
                    zones[index] = new Zone(page.bounds, page.nulls, page.values);
                }
                if (plan.condition != null &&
                    !ZoneValues(plan.condition, zones).Contains(Truth.TRUE)) {
                    counts.Add("pages_skipped", plan.needed.Count);
                    record.Append('s');
                    continue;
                }
                int rowCount = group.chunks[0].pages[p].values;
                counts.Add("rows_scanned", rowCount);
                List<SchemaIo.Value[]> rows = new();
                for (int i = 0; i < rowCount; i++)
                    rows.Add(new SchemaIo.Value[file.columns.Count]);
                foreach (int index in plan.conditionColumns) {
                    List<SchemaIo.Value> values =
                        ReadScanPage(file, g, index, p, dictionaries, counts);
                    for (int i = 0; i < rowCount; i++)
                        rows[i][index] = values[i];
                }
                List<int> selected = new();
                for (int i = 0; i < rowCount; i++)
                    if (Evaluate(plan.condition, rows[i]) == Truth.TRUE)
                        selected.Add(i);
                if (selected.Count == 0 && remaining.Count != 0) {
                    counts.Add("pages_unneeded", remaining.Count);
                    record.Append('u');
                    continue;
                }
                foreach (int index in remaining) {
                    List<SchemaIo.Value> values =
                        ReadScanPage(file, g, index, p, dictionaries, counts);
                    for (int i = 0; i < rowCount; i++)
                        rows[i][index] = values[i];
                }
                foreach (int index in selected)
                    matched.Add(rows[index]);
                record.Append('r');
            }
            records.Add(record.ToString());
        }
        counts.Add("rows_matched", matched.Count);
        return new Scan(matched, counts, records);
    }
    public static long Gcd(long a, long b) {
        a = Math.Abs(a);
        while (b != 0) {
            long next = a % b;
            a = b;
            b = next;
        }
        return a;
    }
    public static string AggregateItem(List<SchemaIo.Column> columns, BoundItem item,
                                       List<SchemaIo.Value[]> rows, SchemaIo.Value key) {
        string op = item.operation;
        int index = item.index;
        if (op.Equals("COLUMN"))
            return SchemaIo.ValueText(columns[index].kind, key);
        if (op.Equals("COUNT") && index < 0)
            return Convert.ToString(rows.Count);
        List<SchemaIo.Value> values = new();
        foreach (SchemaIo.Value[] row in rows)
            if (row[index] != null)
                values.Add(row[index]);
        if (op.Equals("COUNT"))
            return Convert.ToString(values.Count);
        if (op.Equals("COUNT_DISTINCT"))
            return Convert.ToString(new HashSet<SchemaIo.Value>(values).Count);
        if (values.Count == 0)
            return "NULL";
        if (op.Equals("SUM") || op.Equals("AVG")) {
            long total = 0;
            foreach (SchemaIo.Value value in values)
                total += ((SchemaIo.NumberValue)value).value;
            if (op.Equals("SUM"))
                return total.ToString(CultureInfo.InvariantCulture);
            long divisor = Gcd(total, values.Count), numerator = total / divisor,
                 denominator = values.Count / divisor;
            return denominator == 1 ? numerator.ToString(CultureInfo.InvariantCulture)
                                    : numerator + "/" + denominator;
        }
        SchemaIo.Value best = values[0];
        foreach (SchemaIo.Value value in values)
            if ((op.Equals("MIN") ? SchemaIo.Compare(value, best)
                                  : -SchemaIo.Compare(value, best)) < 0)
                best = value;
        return SchemaIo.ValueText(columns[index].kind, best);
    }
    public record GroupKey(SchemaIo.Value value);
    public static bool SameResult(Result a, Result b) => a.kind == b.kind && a.matched == b.matched
                                                         && a.output.SequenceEqual(b.output);
    public static Result BuildResult(List<SchemaIo.Column> columns, Plan plan,
                                     List<SchemaIo.Value[]> matched) {
        string kind;
        List<string> output = new();
        if (!plan.aggregate) {
            kind = "rows";
            IEnumerable<SchemaIo.Value[]> arranged = matched;
            if (plan.order >= 0)
                arranged = matched.OrderBy(
                    row => row[plan.order],
                    Comparer<SchemaIo.Value>.Create((a, b) => (plan.descending ? -1 : 1) *
                                                              SchemaIo.Compare(a, b)));
            foreach (SchemaIo.Value[] row in arranged) {
                List<string> values = new();
                foreach (BoundItem item in plan.items)
                    values.Add(SchemaIo.ValueText(columns[item.index].kind, row[item.index]));
                output.Add(string.Join(",", values));
            }
        } else if (plan.group < 0) {
            kind = "aggregate";
            List<string> values = new();
            foreach (BoundItem item in plan.items)
                values.Add(AggregateItem(columns, item, matched, null));
            output.Add(string.Join(",", values));
        } else {
            kind = "grouped";
            SortedDictionary<GroupKey, List<SchemaIo.Value[]>> groups =
                new(Comparer<GroupKey>.Create((a, b) => SchemaIo.Compare(a.value, b.value)));
            foreach (SchemaIo.Value[] row in matched) {
                GroupKey key = new(row[plan.group]);
                if (!groups.ContainsKey(key))
                    groups[key] = new();
                groups[key].Add(row);
            }
            foreach (var entry in groups) {
                List<string> values = new();
                foreach (BoundItem item in plan.items)
                    values.Add(AggregateItem(columns, item, entry.Value, entry.Key.value));
                output.Add(string.Join(",", values));
            }
        }
        if (plan.limit != null)
            output = output.Take(plan.limit.Value).ToList();
        return new(kind, matched.Count, output);
    }
    public static QueryReports ExecuteQueries(Store file, List<SchemaIo.Value[]> originals,
                                              List<string> queries) {
        List<string> results = new(), statistics = new();
        Counts totals = new Counts();
        int errors = 0, checksOk = 0;
        for (int number = 1; number <= queries.Count; number++) {
            Checked checkedQuery =
                CheckQuery(new Query.Parser(queries[number - 1]).Parse(), file.columns);
            if (checkedQuery.error != null) {
                string line = "query " + number + " error " + checkedQuery.error;
                results.Add(line);
                statistics.Add(line);
                errors++;
                continue;
            }
            Plan plan = checkedQuery.plan;
            Scan scan = PerformScan(file, plan);
            Result result = BuildResult(file.columns, plan, scan.matched);
            List<SchemaIo.Value[]> reference = new();
            foreach (SchemaIo.Value[] row in originals)
                if (Evaluate(plan.condition, row) == Truth.TRUE)
                    reference.Add(row);
            string check =
                SameResult(result, BuildResult(file.columns, plan, reference)) ? "ok" : "mismatch";
            if (check.Equals("ok"))
                checksOk++;
            results.Add("query " + number + " " + result.kind + " matched " + result.matched +
                        " output " + result.output.Count);
            results.Add("columns " + string.Join(",", plan.headers));
            results.AddRange(result.output);
            List<string> needed = new();
            foreach (int index in plan.needed)
                needed.Add(file.columns[index].name);
            statistics.Add("query " + number + " columns " +
                           (needed.Count == 0 ? "-" : string.Join(",", needed)) + " " +
                           scan.counts.Text() + " check " + check);
            for (int g = 0; g < scan.records.Count; g++)
                statistics.Add("query " + number + " row_group " + g + " " +
                               (scan.records[g] == null ? "skipped" : "pages " + scan.records[g]));
            foreach (string name in SCAN_COUNTS)
                totals.Add(name, scan.counts.Get(name));
        }
        statistics.Add("total queries " + queries.Count + " errors " + errors + " " +
                       totals.Text() + " checks_ok " + checksOk);
        return new QueryReports(results, statistics);
    }
    public static Recovery Recover(byte[] data) {
        Store file = ParseFile(data);
        List<SchemaIo.Column> columns = file.columns;
        SchemaIo.Value[][] rows = Enumerable.Range(0, file.rows)
                                      .Select(
                                          _ => new SchemaIo.Value[columns.Count])
                                      .ToArray();
        foreach (SchemaIo.Value[] row in rows)
            Array.Fill(row, SchemaIo.UnknownCell);
        List<string> lines = new(new List<string> { "file bytes " + data.Length + " rows " +
                                                    file.rows + " columns " + columns.Count +
                                                    " row_groups " + file.groups.Count });
        for (int i = 0; i < columns.Count; i++)
            lines.Add(ColumnLine(i, columns[i]));
        int pagesExamined = 0, damagedCount = 0, lostPages = 0, lostCells = 0;
        for (int g = 0; g < file.groups.Count; g++) {
            RowGroup group = file.groups[g];
            for (int i = 0; i < columns.Count; i++) {
                SchemaIo.Column column = columns[i];
                Chunk chunk = group.chunks[i];
                List<SchemaIo.Value> dictionary = null;
                bool dictionaryDamaged = false;
                List<Page> pages = new();
                if (chunk.dictionary != null)
                    pages.Add(chunk.dictionary);
                pages.AddRange(chunk.pages);
                int rowNumber = group.firstRow, p = 0;
                foreach (Page page in pages) {
                    pagesExamined++;
                    long computed = Bitstream.Adler32(PageBody(file, page));
                    bool damaged = computed != page.checksum;
                    string label = page.kind == 1 ? "dict" : Convert.ToString(p);
                    if (damaged) {
                        damagedCount++;
                        lines.Add("damaged " + g + " " + column.name + " " + label + " offset " +
                                  page.offset + " stored " + Checksum(page.checksum) +
                                  " computed " + Checksum(computed));
                    }
                    if (page.kind == 1) {
                        dictionaryDamaged = damaged;
                        if (!damaged)
                            dictionary = DecodeDictionary(file, column, page);
                        continue;
                    }
                    string reason = damaged                                 ? "checksum"
                                    : page.method == 1 && dictionaryDamaged ? "dictionary"
                                                                            : null;
                    if (reason != null) {
                        lostPages++;
                        lostCells += page.values;
                        lines.Add("lost " + g + " " + column.name + " " + p + " rows " +
                                  page.values + " reason " + reason);
                    } else {
                        List<SchemaIo.Value> values = DecodePage(file, column, page, dictionary);
                        for (int j = 0; j < values.Count; j++)
                            rows[rowNumber + j][i] = values[j];
                    }
                    rowNumber += page.values;
                    p++;
                }
            }
        }
        lines.Add("summary pages " + pagesExamined + " damaged " + damagedCount + " lost_pages " +
                  lostPages + " lost_cells " + lostCells + " recovered_cells " +
                  (file.rows * columns.Count - lostCells));
        List<string> recovered = new();
        List<string> names = new();
        foreach (SchemaIo.Column column in columns)
            names.Add(column.name);
        recovered.Add(string.Join(",", names));
        foreach (SchemaIo.Value[] row in rows) {
            List<string> values = new();
            for (int i = 0; i < columns.Count; i++)
                values.Add(row[i] == SchemaIo.UnknownCell
                               ? "?"
                               : SchemaIo.ValueText(columns[i].kind, row[i], ""));
            recovered.Add(string.Join(",", values));
        }
        return new Recovery(lines, recovered);
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        SchemaIo.Inputs inputs = SchemaIo.ReadInputs();
        Built built = BuildFile(inputs);
        Store file = ParseFile(built.data);
        List<string> metadata = VerifyAndDescribe(file, inputs.rows);
        QueryReports queries = ExecuteQueries(file, inputs.rows, inputs.queries);
        Recovery recovery = Recover(inputs.damaged);
        List<string> hex = new();
        for (int start = 0; start < built.data.Length; start += 32)
            hex.Add(Convert.ToHexString(built.data[start..Math.Min(start + 32, built.data.Length)])
                        .ToLowerInvariant());
        Dictionary<string, List<string>> outputs = new();
        outputs["file.hex"] = hex;
        outputs["metadata.txt"] = metadata;
        outputs["encoding_report.csv"] = built.report;
        outputs["query_results.txt"] = queries.results;
        outputs["query_stats.txt"] = queries.statistics;
        outputs["recovery.txt"] = recovery.report;
        outputs["recovered.csv"] = recovery.rows;
        SchemaIo.WriteOutputs(outputs);
    }
}
