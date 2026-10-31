import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collection;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.TreeSet;

public class Main {
    static final String WRONG_TYPE = "WRONGTYPE Operation against a key holding the wrong kind of value";
    static final String NOT_INTEGER = "ERR value is not an integer or out of range";
    static final String POSITIVE = "ERR value is out of range, must be positive";

    static final class CommandError extends RuntimeException {
        CommandError(String message) { super(message); }
    }

    sealed interface Value permits TextValue, ListValue, HashValue, SetValue, SortedSetValue {
        default String kind() {
            return switch (this) {
                case TextValue ignored -> "string";
                case ListValue ignored -> "list";
                case HashValue ignored -> "hash";
                case SetValue ignored -> "set";
                case SortedSetValue ignored -> "zset";
            };
        }
        default boolean empty() {
            return switch (this) {
                case TextValue ignored -> false;
                case ListValue value -> value.items.isEmpty();
                case HashValue value -> value.fields.isEmpty();
                case SetValue value -> value.members.isEmpty();
                case SortedSetValue value -> value.scores.isEmpty();
            };
        }
    }
    record TextValue(String text) implements Value {}
    record ListValue(List<String> items) implements Value {
        ListValue { items = List.copyOf(items); }
    }
    record HashValue(Map<String, String> fields) implements Value {
        HashValue { fields = Map.copyOf(fields); }
    }
    record SetValue(Set<String> members) implements Value {
        SetValue { members = Set.copyOf(members); }
    }
    record SortedSetValue(Map<String, Integer> scores) implements Value {
        SortedSetValue { scores = Map.copyOf(scores); }
    }
    record Entry(Value value, Integer expiry) {}
    record Range(int start, int end) {}

    static String quoted(String text) {
        return text == null ? "(nil)" : "\"" + text.replace("\\", "\\\\").replace("\"", "\\\"") + "\"";
    }
    static String integerReply(int value) { return "(integer) " + value; }
    static String arrayReply(Collection<String> values) {
        if (values.isEmpty()) return "(empty array)";
        int width = Integer.toString(values.size()).length(), index = 0;
        var result = new StringBuilder();
        for (String value : values) {
            if (index > 0) result.append('\n');
            String number = Integer.toString(++index);
            result.append(" ".repeat(width - number.length())).append(number).append(") ").append(quoted(value));
        }
        return result.toString();
    }

    static List<String> splitLine(String line) {
        var words = new ArrayList<String>();
        int position = 0;
        while (position < line.length()) {
            if (line.charAt(position) == ' ') { position++; continue; }
            if (line.charAt(position) != '"') {
                int start = position;
                while (position < line.length() && line.charAt(position) != ' ') position++;
                words.add(line.substring(start, position));
                continue;
            }
            position++;
            var word = new StringBuilder();
            while (position < line.length() && line.charAt(position) != '"') {
                char c = line.charAt(position++);
                if (c == '\\') {
                    if (position == line.length()) return null;
                    c = line.charAt(position++);
                    if (c != '\\' && c != '"') return null;
                }
                word.append(c);
            }
            if (position == line.length()) return null;
            position++;
            if (position < line.length() && line.charAt(position) != ' ') return null;
            words.add(word.toString());
        }
        return words;
    }

    static Integer parseInteger(String text) {
        if (text.equals("0")) return 0;
        int start = text.startsWith("-") ? 1 : 0;
        int length = text.length() - start;
        if (length < 1 || length > 9 || text.charAt(start) < '1' || text.charAt(start) > '9') return null;
        for (int i = start; i < text.length(); i++) if (text.charAt(i) < '0' || text.charAt(i) > '9') return null;
        return Integer.valueOf(text);
    }
    static int number(String text) {
        Integer value = parseInteger(text);
        if (value == null) throw new CommandError(NOT_INTEGER);
        return value;
    }
    static int increment(int old, int delta) {
        int value = old + delta;
        if (value < -999_999_999 || value > 999_999_999)
            throw new CommandError("ERR increment or decrement would overflow");
        return value;
    }
    static Range range(int length, int start, int stop) {
        if (start < 0) start += length;
        if (stop < 0) stop += length;
        start = Math.max(0, start);
        stop = Math.min(length - 1, stop);
        return start <= stop ? new Range(start, stop + 1) : new Range(0, 0);
    }

    sealed interface Bound permits Infinity, FiniteBound { boolean accepts(int score, boolean lower); }
    enum Infinity implements Bound {
        NEGATIVE, POSITIVE;
        public boolean accepts(int score, boolean lower) { return lower == (this == NEGATIVE); }
    }
    record FiniteBound(int value, boolean exclusive) implements Bound {
        public boolean accepts(int score, boolean lower) {
            return (lower ? score > value : score < value) || (!exclusive && score == value);
        }
    }
    static Bound bound(String text) {
        if (text.equals("-inf")) return Infinity.NEGATIVE;
        if (text.equals("+inf")) return Infinity.POSITIVE;
        boolean exclusive = text.startsWith("(");
        Integer value = parseInteger(exclusive ? text.substring(1) : text);
        if (value == null) throw new CommandError("ERR min or max is not a float");
        return new FiniteBound(value, exclusive);
    }

    sealed interface PatternPart permits Literal, Wildcard, CharacterClass { boolean accepts(char c); }
    record Literal(char value) implements PatternPart {
        public boolean accepts(char c) { return value == c; }
    }
    enum Wildcard implements PatternPart {
        ANY, STAR;
        public boolean accepts(char c) { return true; }
    }
    record CharacterClass(boolean[] members, boolean negated) implements PatternPart {
        public boolean accepts(char c) { return members[c] != negated; }
    }
    static List<PatternPart> pattern(String text) {
        var parts = new ArrayList<PatternPart>();
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            if (c == '\\') {
                if (++i == text.length()) throw new CommandError("ERR invalid pattern");
                parts.add(new Literal(text.charAt(i)));
            } else if (c == '[') {
                int end = text.indexOf(']', i + 1);
                if (end < 0) throw new CommandError("ERR invalid pattern");
                i++;
                boolean negated = i < end && text.charAt(i) == '^';
                if (negated) i++;
                if (i == end) throw new CommandError("ERR invalid pattern");
                var members = new boolean[128];
                while (i < end) {
                    int first = text.charAt(i);
                    if (i + 2 < end && text.charAt(i + 1) == '-') {
                        int last = text.charAt(i + 2);
                        Arrays.fill(members, Math.min(first, last), Math.max(first, last) + 1, true);
                        i += 3;
                    } else { members[first] = true; i++; }
                }
                parts.add(new CharacterClass(members, negated));
            } else if (c == '*') parts.add(Wildcard.STAR);
            else if (c == '?') parts.add(Wildcard.ANY);
            else parts.add(new Literal(c));
        }
        return parts;
    }
    static boolean matches(List<PatternPart> parts, String text) {
        var previous = new boolean[text.length() + 1];
        previous[0] = true;
        for (var part : parts) {
            var next = new boolean[previous.length];
            if (part == Wildcard.STAR) {
                next[0] = previous[0];
                for (int i = 1; i < next.length; i++) next[i] = previous[i] || next[i - 1];
            } else {
                for (int i = 0; i < text.length(); i++) next[i + 1] = previous[i] && part.accepts(text.charAt(i));
            }
            previous = next;
        }
        return previous[text.length()];
    }

    record Arity(int minimum, int maximum, int parity) {
        Arity(int count) { this(count, count, -1); }
        Arity(int minimum, int maximum) { this(minimum, maximum, -1); }
        boolean accepts(int count) {
            return count >= minimum && (maximum < 0 || count <= maximum) && (parity < 0 || count % 2 == parity);
        }
    }
    static Arity arity(String command) {
        return switch (command) {
            case "TIME", "DBSIZE", "FLUSH", "INFO", "BEGIN", "COMMIT", "ROLLBACK" -> new Arity(0);
            case "GET", "INCR", "DECR", "STRLEN", "LLEN", "HGETALL", "HLEN", "HKEYS", "HVALS",
                 "SMEMBERS", "SCARD", "ZCARD", "TYPE", "KEYS", "TTL", "PERSIST", "TICK", "SNAPSHOT", "RESTORE" -> new Arity(1);
            case "INCRBY", "DECRBY", "APPEND", "LINDEX", "HGET", "HEXISTS", "SISMEMBER", "ZSCORE", "ZRANK", "RENAME", "RENAMENX" -> new Arity(2);
            case "GETRANGE", "LRANGE", "LSET", "LREM", "LTRIM", "HINCRBY", "ZINCRBY" -> new Arity(3);
            case "LINSERT" -> new Arity(4);
            case "LPOP", "RPOP" -> new Arity(1, 2);
            case "EXPIRE" -> new Arity(2, 3);
            case "ZRANGE", "ZRANGEBYSCORE" -> new Arity(3, 4);
            case "MGET", "SINTER", "SUNION", "SDIFF", "DEL", "EXISTS" -> new Arity(1, -1);
            case "SET", "LPUSH", "RPUSH", "HDEL", "SADD", "SREM", "ZREM", "SINTERSTORE", "SUNIONSTORE", "SDIFFSTORE" -> new Arity(2, -1);
            case "MSET" -> new Arity(2, -1, 0);
            case "HSET", "ZADD" -> new Arity(3, -1, 1);
            default -> null;
        };
    }

    static final class Store {
        TreeMap<String, Entry> database = new TreeMap<>();
        final ArrayDeque<TreeMap<String, Entry>> stack = new ArrayDeque<>();
        final TreeMap<String, TreeMap<String, Entry>> snapshots = new TreeMap<>();
        int time;

        <T extends Value> T read(String key, Class<T> type, T empty) {
            var entry = database.get(key);
            if (entry == null) return empty;
            if (!type.isInstance(entry.value)) throw new CommandError(WRONG_TYPE);
            return type.cast(entry.value);
        }
        String text(String key) { return read(key, TextValue.class, new TextValue("")).text; }
        List<String> list(String key) { return read(key, ListValue.class, new ListValue(List.of())).items; }
        Map<String, String> hash(String key) { return read(key, HashValue.class, new HashValue(Map.of())).fields; }
        Set<String> set(String key) { return read(key, SetValue.class, new SetValue(Set.of())).members; }
        Map<String, Integer> sortedSet(String key) { return read(key, SortedSetValue.class, new SortedSetValue(Map.of())).scores; }
        void replace(String key, Value value, Integer expiry) {
            if (value.empty()) database.remove(key);
            else database.put(key, new Entry(value, expiry));
        }
        void update(String key, Value value) {
            var old = database.get(key);
            replace(key, value, old == null ? null : old.expiry);
        }
        int purge() {
            int before = database.size();
            database.values().removeIf(entry -> entry.expiry != null && entry.expiry <= time);
            return before - database.size();
        }

        String textCommand(String command, List<String> a) {
            String key = a.getFirst();
            switch (command) {
                case "SET" -> {
                    var options = new TreeSet<String>();
                    String secondsText = null;
                    for (int i = 2; i < a.size(); i++) {
                        String option = a.get(i).toUpperCase(Locale.ROOT);
                        if (!Set.of("NX", "XX", "EX", "KEEPTTL", "GET").contains(option) || !options.add(option))
                            throw new CommandError("ERR syntax error");
                        if (option.equals("EX")) {
                            if (++i == a.size()) throw new CommandError("ERR syntax error");
                            secondsText = a.get(i);
                        }
                    }
                    if ((options.contains("NX") && options.contains("XX")) || (options.contains("EX") && options.contains("KEEPTTL")))
                        throw new CommandError("ERR syntax error");
                    Integer expiry = null;
                    if (secondsText != null) {
                        int seconds = number(secondsText);
                        if (seconds <= 0) throw new CommandError("ERR invalid expire time in 'set' command");
                        expiry = time + seconds;
                    }
                    var old = database.get(key);
                    String oldText = null;
                    if (options.contains("GET")) { String value = text(key); if (old != null) oldText = value; }
                    boolean blocked = (options.contains("NX") && old != null) || (options.contains("XX") && old == null);
                    if (!blocked) {
                        if (options.contains("KEEPTTL") && old != null) expiry = old.expiry;
                        replace(key, new TextValue(a.get(1)), expiry);
                    }
                    return options.contains("GET") ? quoted(oldText) : blocked ? "(nil)" : "OK";
                }
                case "MSET" -> {
                    for (int i = 0; i < a.size(); i += 2) replace(a.get(i), new TextValue(a.get(i + 1)), null);
                    return "OK";
                }
                case "MGET" -> {
                    var values = new ArrayList<String>();
                    for (String name : a) {
                        var entry = database.get(name);
                        values.add(entry != null && entry.value instanceof TextValue value ? value.text : null);
                    }
                    return arrayReply(values);
                }
                case "INCR", "DECR", "INCRBY", "DECRBY" -> {
                    int delta = a.size() == 2 ? number(a.get(1)) : 1;
                    if (command.startsWith("DECR")) delta = -delta;
                    String old = text(key);
                    int value = increment(database.containsKey(key) ? number(old) : 0, delta);
                    update(key, new TextValue(Integer.toString(value)));
                    return integerReply(value);
                }
                case "APPEND" -> {
                    String value = text(key) + a.get(1);
                    update(key, new TextValue(value));
                    return integerReply(value.length());
                }
                case "GETRANGE" -> {
                    int start = number(a.get(1)), stop = number(a.get(2));
                    String value = text(key);
                    var selected = range(value.length(), start, stop);
                    return quoted(value.substring(selected.start, selected.end));
                }
                case "STRLEN" -> { return integerReply(text(key).length()); }
                default -> { String value = text(key); return quoted(database.containsKey(key) ? value : null); }
            }
        }

        String listCommand(String command, List<String> a) {
            String key = a.getFirst();
            switch (command) {
                case "LPUSH", "RPUSH" -> {
                    var values = new ArrayList<>(list(key));
                    for (String value : a.subList(1, a.size())) {
                        if (command.equals("LPUSH")) values.addFirst(value); else values.add(value);
                    }
                    update(key, new ListValue(values));
                    return integerReply(values.size());
                }
                case "LPOP", "RPOP" -> {
                    Integer count = null;
                    if (a.size() == 2) {
                        count = parseInteger(a.get(1));
                        if (count == null || count < 0) throw new CommandError(POSITIVE);
                    }
                    var values = new ArrayList<>(list(key));
                    if (!database.containsKey(key)) return "(nil)";
                    int amount = Math.min(count == null ? 1 : count, values.size());
                    var removed = new ArrayList<String>();
                    for (int i = 0; i < amount; i++) removed.add(command.equals("LPOP") ? values.removeFirst() : values.removeLast());
                    update(key, new ListValue(values));
                    return count == null ? quoted(removed.getFirst()) : arrayReply(removed);
                }
                case "LRANGE", "LTRIM" -> {
                    int start = number(a.get(1)), stop = number(a.get(2));
                    var values = list(key);
                    var selected = range(values.size(), start, stop);
                    var kept = values.subList(selected.start, selected.end);
                    if (command.equals("LRANGE")) return arrayReply(kept);
                    update(key, new ListValue(kept));
                    return "OK";
                }
                case "LLEN" -> { return integerReply(list(key).size()); }
                case "LINDEX", "LSET" -> {
                    int index = number(a.get(1));
                    var values = list(key);
                    if (index < 0) index += values.size();
                    if (command.equals("LINDEX")) return quoted(index >= 0 && index < values.size() ? values.get(index) : null);
                    if (!database.containsKey(key)) throw new CommandError("ERR no such key");
                    if (index < 0 || index >= values.size()) throw new CommandError("ERR index out of range");
                    var changed = new ArrayList<>(values);
                    changed.set(index, a.get(2));
                    update(key, new ListValue(changed));
                    return "OK";
                }
                case "LREM" -> {
                    int count = number(a.get(1));
                    var values = new ArrayList<>(list(key));
                    if (count < 0) Collections.reverse(values);
                    var kept = new ArrayList<String>();
                    int removed = 0;
                    for (String value : values) {
                        if (value.equals(a.get(2)) && (count == 0 || removed < Math.abs(count))) removed++;
                        else kept.add(value);
                    }
                    if (count < 0) Collections.reverse(kept);
                    update(key, new ListValue(kept));
                    return integerReply(removed);
                }
                default -> {
                    String where = a.get(1).toUpperCase(Locale.ROOT);
                    if (!where.equals("BEFORE") && !where.equals("AFTER")) throw new CommandError("ERR syntax error");
                    var values = new ArrayList<>(list(key));
                    if (!database.containsKey(key)) return integerReply(0);
                    int index = values.indexOf(a.get(2));
                    if (index < 0) return integerReply(-1);
                    values.add(index + (where.equals("AFTER") ? 1 : 0), a.get(3));
                    update(key, new ListValue(values));
                    return integerReply(values.size());
                }
            }
        }

        String hashCommand(String command, List<String> a) {
            String key = a.getFirst();
            if (command.equals("HINCRBY")) {
                int delta = number(a.get(2));
                var fields = new TreeMap<>(hash(key));
                Integer old = 0;
                if (fields.containsKey(a.get(1))) old = parseInteger(fields.get(a.get(1)));
                if (old == null) throw new CommandError("ERR hash value is not an integer");
                int value = increment(old, delta);
                fields.put(a.get(1), Integer.toString(value));
                update(key, new HashValue(fields));
                return integerReply(value);
            }
            var fields = new TreeMap<>(hash(key));
            switch (command) {
                case "HSET" -> {
                    int added = 0;
                    for (int i = 1; i < a.size(); i += 2) if (fields.put(a.get(i), a.get(i + 1)) == null) added++;
                    update(key, new HashValue(fields));
                    return integerReply(added);
                }
                case "HDEL" -> {
                    int removed = 0;
                    for (String field : a.subList(1, a.size())) if (fields.remove(field) != null) removed++;
                    update(key, new HashValue(fields));
                    return integerReply(removed);
                }
                case "HGET" -> { return quoted(fields.get(a.get(1))); }
                case "HEXISTS" -> { return integerReply(fields.containsKey(a.get(1)) ? 1 : 0); }
                case "HLEN" -> { return integerReply(fields.size()); }
                case "HKEYS" -> { return arrayReply(fields.keySet()); }
                case "HVALS" -> { return arrayReply(fields.values()); }
                default -> {
                    var result = new ArrayList<String>();
                    fields.forEach((field, value) -> { result.add(field); result.add(value); });
                    return arrayReply(result);
                }
            }
        }

        String setCommand(String command, List<String> a) {
            String key = a.getFirst();
            boolean store = command.endsWith("STORE");
            if (command.startsWith("SINTER") || command.startsWith("SUNION") || command.startsWith("SDIFF")) {
                var sources = new ArrayList<Set<String>>();
                for (String source : a.subList(store ? 1 : 0, a.size())) sources.add(set(source));
                var result = new TreeSet<>(sources.getFirst());
                for (var source : sources.subList(1, sources.size())) {
                    if (command.startsWith("SINTER")) result.retainAll(source);
                    else if (command.startsWith("SUNION")) result.addAll(source);
                    else result.removeAll(source);
                }
                if (!store) return arrayReply(result);
                replace(key, new SetValue(result), null);
                return integerReply(result.size());
            }
            var members = new TreeSet<>(set(key));
            return switch (command) {
                case "SADD", "SREM" -> {
                    int changed = 0;
                    for (String member : a.subList(1, a.size()))
                        if (command.equals("SADD") ? members.add(member) : members.remove(member)) changed++;
                    update(key, new SetValue(members));
                    yield integerReply(changed);
                }
                case "SCARD" -> integerReply(members.size());
                case "SISMEMBER" -> integerReply(members.contains(a.get(1)) ? 1 : 0);
                default -> arrayReply(members);
            };
        }

        String sortedSetCommand(String command, List<String> a) {
            String key = a.getFirst();
            if (command.equals("ZADD")) {
                int[] values = new int[(a.size() - 1) / 2];
                for (int i = 0; i < values.length; i++) values[i] = number(a.get(2 * i + 1));
                var scores = new TreeMap<>(sortedSet(key));
                int added = 0;
                for (int i = 0; i < values.length; i++) if (scores.put(a.get(2 * i + 2), values[i]) == null) added++;
                update(key, new SortedSetValue(scores));
                return integerReply(added);
            }
            if (command.equals("ZINCRBY")) {
                int delta = number(a.get(1));
                var scores = new TreeMap<>(sortedSet(key));
                int value = increment(scores.getOrDefault(a.get(2), 0), delta);
                scores.put(a.get(2), value);
                update(key, new SortedSetValue(scores));
                return quoted(Integer.toString(value));
            }
            boolean withScores = false;
            int start = 0, stop = 0;
            Bound minimum = null, maximum = null;
            if (command.equals("ZRANGE") || command.equals("ZRANGEBYSCORE")) {
                withScores = a.size() == 4;
                if (withScores && !a.get(3).equalsIgnoreCase("WITHSCORES")) throw new CommandError("ERR syntax error");
                if (command.equals("ZRANGE")) { start = number(a.get(1)); stop = number(a.get(2)); }
                else { minimum = bound(a.get(1)); maximum = bound(a.get(2)); }
            }
            var scores = new TreeMap<>(sortedSet(key));
            if (command.equals("ZREM")) {
                int removed = 0;
                for (String member : a.subList(1, a.size())) if (scores.remove(member) != null) removed++;
                update(key, new SortedSetValue(scores));
                return integerReply(removed);
            }
            if (command.equals("ZCARD")) return integerReply(scores.size());
            if (command.equals("ZSCORE")) {
                Integer score = scores.get(a.get(1));
                return quoted(score == null ? null : score.toString());
            }
            var ordered = new ArrayList<>(scores.entrySet());
            ordered.sort(Comparator.<Map.Entry<String, Integer>>comparingInt(Map.Entry::getValue).thenComparing(Map.Entry::getKey));
            if (command.equals("ZRANK")) {
                for (int i = 0; i < ordered.size(); i++) if (ordered.get(i).getKey().equals(a.get(1))) return integerReply(i);
                return "(nil)";
            }
            var selected = command.equals("ZRANGE") ? range(ordered.size(), start, stop) : new Range(0, ordered.size());
            var result = new ArrayList<String>();
            for (var item : ordered.subList(selected.start, selected.end)) {
                if (minimum != null && (!minimum.accepts(item.getValue(), true) || !maximum.accepts(item.getValue(), false))) continue;
                result.add(item.getKey());
                if (withScores) result.add(item.getValue().toString());
            }
            return arrayReply(result);
        }

        String keyCommand(String command, List<String> a) {
            switch (command) {
                case "TIME" -> { return integerReply(time); }
                case "DBSIZE" -> { return integerReply(database.size()); }
                case "FLUSH" -> { database.clear(); return "OK"; }
                case "INFO" -> {
                    var counts = new TreeMap<String, Integer>();
                    int expires = 0;
                    for (var entry : database.values()) {
                        counts.merge(entry.value.kind(), 1, Integer::sum);
                        if (entry.expiry != null) expires++;
                    }
                    return "keys=" + database.size() + ",expires=" + expires + ",string=" + counts.getOrDefault("string", 0)
                        + ",list=" + counts.getOrDefault("list", 0) + ",hash=" + counts.getOrDefault("hash", 0)
                        + ",set=" + counts.getOrDefault("set", 0) + ",zset=" + counts.getOrDefault("zset", 0)
                        + ",time=" + time + ",depth=" + stack.size() + ",snapshots=" + snapshots.size();
                }
                case "DEL", "EXISTS" -> {
                    int count = 0;
                    for (String key : a) if (command.equals("DEL") ? database.remove(key) != null : database.containsKey(key)) count++;
                    return integerReply(count);
                }
                case "KEYS" -> {
                    var parts = pattern(a.getFirst());
                    return arrayReply(database.keySet().stream().filter(key -> matches(parts, key)).toList());
                }
                case "TICK" -> {
                    int ticks = number(a.getFirst());
                    if (ticks <= 0) throw new CommandError(POSITIVE);
                    time += ticks;
                    return integerReply(purge());
                }
            }
            String key = a.getFirst();
            if (command.equals("EXPIRE")) {
                String condition = a.size() == 3 ? a.get(2).toUpperCase(Locale.ROOT) : "";
                if (a.size() == 3 && !Set.of("NX", "XX", "GT", "LT").contains(condition))
                    throw new CommandError("ERR Unsupported option " + a.get(2));
                int seconds = number(a.get(1));
                var entry = database.get(key);
                if (entry == null) return integerReply(0);
                int expiry = time + seconds;
                boolean rejected = switch (condition) {
                    case "NX" -> entry.expiry != null;
                    case "XX" -> entry.expiry == null;
                    case "GT" -> entry.expiry == null || expiry <= entry.expiry;
                    case "LT" -> entry.expiry != null && expiry >= entry.expiry;
                    default -> false;
                };
                if (rejected) return integerReply(0);
                if (seconds <= 0) database.remove(key);
                else database.put(key, new Entry(entry.value, expiry));
                return integerReply(1);
            }
            var entry = database.get(key);
            switch (command) {
                case "TYPE" -> { return entry == null ? "none" : entry.value.kind(); }
                case "TTL" -> { return integerReply(entry == null ? -2 : entry.expiry == null ? -1 : entry.expiry - time); }
                case "PERSIST" -> {
                    if (entry == null || entry.expiry == null) return integerReply(0);
                    database.put(key, new Entry(entry.value, null));
                    return integerReply(1);
                }
                default -> {
                    if (entry == null) throw new CommandError("ERR no such key");
                    String destination = a.get(1);
                    if (command.equals("RENAMENX") && database.containsKey(destination)) return integerReply(0);
                    if (!key.equals(destination)) { database.remove(key); database.put(destination, entry); }
                    return command.equals("RENAME") ? "OK" : integerReply(1);
                }
            }
        }

        String controlCommand(String command, List<String> a) {
            switch (command) {
                case "BEGIN" -> stack.addLast(new TreeMap<>(database));
                case "COMMIT", "ROLLBACK" -> {
                    if (stack.isEmpty()) throw new CommandError("ERR no transaction");
                    var saved = stack.removeLast();
                    if (command.equals("ROLLBACK")) { database = saved; purge(); }
                }
                case "SNAPSHOT" -> snapshots.put(a.getFirst(), new TreeMap<>(database));
                case "RESTORE" -> {
                    var saved = snapshots.get(a.getFirst());
                    if (saved == null) throw new CommandError("ERR no such snapshot");
                    database = new TreeMap<>(saved);
                    purge();
                }
            }
            return "OK";
        }

        String execute(String command, List<String> args) {
            return switch (command) {
                case "SET", "GET", "MSET", "MGET", "INCR", "DECR", "INCRBY", "DECRBY", "APPEND", "STRLEN", "GETRANGE" -> textCommand(command, args);
                case "LPUSH", "RPUSH", "LPOP", "RPOP", "LRANGE", "LLEN", "LINDEX", "LSET", "LREM", "LTRIM", "LINSERT" -> listCommand(command, args);
                case "HSET", "HGET", "HDEL", "HGETALL", "HLEN", "HEXISTS", "HKEYS", "HVALS", "HINCRBY" -> hashCommand(command, args);
                case "SADD", "SREM", "SISMEMBER", "SMEMBERS", "SCARD", "SINTER", "SUNION", "SDIFF", "SINTERSTORE", "SUNIONSTORE", "SDIFFSTORE" -> setCommand(command, args);
                case "ZADD", "ZSCORE", "ZINCRBY", "ZREM", "ZCARD", "ZRANK", "ZRANGE", "ZRANGEBYSCORE" -> sortedSetCommand(command, args);
                case "BEGIN", "COMMIT", "ROLLBACK", "SNAPSHOT", "RESTORE" -> controlCommand(command, args);
                default -> keyCommand(command, args);
            };
        }
    }

    public static void main(String[] args) throws Exception {
        var input = new BufferedReader(new InputStreamReader(System.in));
        var output = new BufferedWriter(new OutputStreamWriter(System.out));
        int count = Integer.parseInt(input.readLine());
        var store = new Store();
        for (int i = 0; i < count; i++) {
            var words = splitLine(input.readLine());
            String result;
            if (words == null) result = "Invalid argument(s)";
            else {
                String command = words.getFirst().toUpperCase(Locale.ROOT);
                var format = arity(command);
                if (format == null) result = "(error) ERR unknown command '" + words.getFirst() + "'";
                else if (!format.accepts(words.size() - 1))
                    result = "(error) ERR wrong number of arguments for '" + command.toLowerCase(Locale.ROOT) + "' command";
                else {
                    try { result = store.execute(command, words.subList(1, words.size())); }
                    catch (CommandError error) { result = "(error) " + error.getMessage(); }
                }
            }
            output.write(result);
            output.write('\n');
        }
        output.flush();
    }
}
