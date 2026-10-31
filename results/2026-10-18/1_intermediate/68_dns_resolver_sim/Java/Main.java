import java.io.*;
import java.util.*;

public class Main {
    static final String[] TYPES = {"A", "NS", "CNAME", "SOA", "PTR", "MX", "TXT", "AAAA"};
    static final String[] KINDS = {"ANSWER", "CNAME", "REFERRAL", "NODATA", "NXDOMAIN", "LAME", "TIMEOUT"};
    static class Problem extends RuntimeException {
        Problem(String message) {
            super(message);
        }
    }
    record Record(String owner, int ttl, int type, String data) {
        Record ttl(int value) {
            return new Record(owner, value, type, data);
        }
        Record owner(String value) {
            return new Record(value, ttl, type, data);
        }
        public String toString() {
            return owner + " " + ttl + " " + TYPES[type] + " " + data;
        }
    }

    static class Zone {
        String origin;
        long server;
        int line;
        List<Record> records = new ArrayList<>();
        Zone(String origin, long server, int line) {
            this.origin = origin;
            this.server = server;
            this.line = line;
        }
        Record soa() {
            return records.stream().filter(r -> r.type() == 3).findFirst().orElse(null);
        }
    }
    record Key(String name, int type) {}
    record CacheEntry(String kind, List<Record> records, int expiry) {}
    static class Response {
        String kind, cut;
        List<Record> answer = new ArrayList<>(), authority = new ArrayList<>(), additional = new ArrayList<>();
        Response(String kind) {
            this.kind = kind;
        }
        String description() {
            return kind.equals("REFERRAL") ? kind + " " + cut : kind.equals("CNAME") ? kind + " " + answer.getFirst().data() : kind;
        }
    }
    record Result(String status, List<Record> answer) {}

    static final List<Long> roots = new ArrayList<>();
    static final List<Zone> zones = new ArrayList<>();
    static Zone current;
    static final Set<Long> down = new HashSet<>();
    static final Map<Key, CacheEntry> cache = new HashMap<>();
    static final TreeMap<Long, int[]> queries = new TreeMap<>();
    static final int[] resolutions = new int[4];
    static int now, minTtl = 1, maxTtl = 86400, negTtl = 3600, hits;
    static void require(boolean condition, String reason) {
        if (!condition) throw new Problem(reason);
    }

    static int type(String word) {
        for (int i = 0; i < TYPES.length; i++) if (TYPES[i].equals(word)) return i;
        throw new Problem("bad type " + word);
    }

    static String name(String word, boolean wildcard, String origin) {
        if (origin != null && word.equals("@")) return origin;
        if (word.equals(".")) return ".";
        String text = word.endsWith(".") ? word.substring(0, word.length() - 1) : word;
        String[] labels = text.split("\\.", -1);
        for (int i = 0; i < labels.length; i++) require(wildcard && i == 0 && labels[i].equals("*") || labels[i].matches("[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?"), "bad name " + word);
        String result = text.toLowerCase(Locale.ROOT) + ".";
        if (origin != null && !word.endsWith(".") && !origin.equals(".")) result += origin;
        return result;
    }

    static String[] labels(String name) {
        return name.equals(".") ? new String[0] : name.substring(0, name.length() - 1).split("\\.");
    }

    static int length(String name) {
        return labels(name).length;
    }

    static boolean below(String name, String ancestor) {
        return ancestor.equals(".") || name.equals(ancestor) || name.endsWith("." + ancestor);
    }

    static String parent(String name) {
        int dot = name.indexOf('.');
        return dot == name.length() - 1 ? "." : name.substring(dot + 1);
    }

    static int compareNames(String left, String right) {
        String[] a = labels(left), b = labels(right);
        for (int i = 1; i <= Math.min(a.length, b.length); i++) {
            int c = a[a.length - i].compareTo(b[b.length - i]);
            if (c != 0) return c;
        }
        return Integer.compare(a.length, b.length);
    }

    static long ipv4(String word) {
        String[] fields = word.split("\\.", -1);
        require(fields.length == 4, "bad address " + word);
        long value = 0;
        for (String field : fields) {
            require(field.matches("0|[1-9][0-9]{0,2}"), "bad address " + word);
            int n = Integer.parseInt(field);
            require(n <= 255, "bad address " + word);
            value = value * 256 + n;
        }
        return value;
    }

    static String address(long value) {
        return (value >>> 24) + "." + ((value >>> 16) & 255) + "." + ((value >>> 8) & 255) + "." + (value & 255);
    }

    static int[] ipv6(String word) {
        int doubleColon = word.indexOf("::");
        String left = doubleColon < 0 ? word : word.substring(0, doubleColon), right = doubleColon < 0 ? "" : word.substring(doubleColon + 2);
        require(doubleColon < 0 || doubleColon == word.lastIndexOf("::"), "bad address " + word);
        String[] a = left.isEmpty() ? new String[0] : left.split(":", -1), b = right.isEmpty() ? new String[0] : right.split(":", -1);
        require(doubleColon < 0 ? a.length == 8 : a.length + b.length <= 7, "bad address " + word);
        int[] groups = new int[8];
        for (int i = 0; i < a.length; i++) {
            require(a[i].matches("[0-9a-fA-F]{1,4}"), "bad address " + word);
            groups[i] = Integer.parseInt(a[i], 16);
        }
        for (int i = 0; i < b.length; i++) {
            require(b[i].matches("[0-9a-fA-F]{1,4}"), "bad address " + word);
            groups[8 - b.length + i] = Integer.parseInt(b[i], 16);
        }
        return groups;
    }

    static String address6(int[] groups) {
        int best = -1, count = 1;
        for (int i = 0; i < 8;) {
            if (groups[i] != 0) {
                i++;
                continue;
            }
            int end = i;
            while (end < 8 && groups[end] == 0) end++;
            if (end - i > count) {
                best = i;
                count = end - i;
            }
            i = end;
        }
        List<String> left = new ArrayList<>(), right = new ArrayList<>();
        if (best < 0) {
            for (int group : groups) left.add(Integer.toHexString(group));
            return String.join(":", left);
        }
        for (int i = 0; i < best; i++) left.add(Integer.toHexString(groups[i]));
        for (int i = best + count; i < 8; i++) right.add(Integer.toHexString(groups[i]));
        return String.join(":", left) + "::" + String.join(":", right);
    }

    static Integer integer(String word) {
        return word.matches("0|[1-9][0-9]{0,8}") ? Integer.valueOf(word) : null;
    }

    static int ttl(String word) {
        Integer plain = integer(word);
        long total = plain == null ? 0 : plain;
        if (plain == null) {
            int at = 0, previous = -1;
            String units = "wdhms";
            int[] seconds = {604800, 86400, 3600, 60, 1};
            while (at < word.length()) {
                int start = at;
                while (at < word.length() && word.charAt(at) >= '0' && word.charAt(at) <= '9') at++;
                String number = word.substring(start, at);
                require(number.length() >= 1 && number.length() <= 3 && integer(number) != null && at < word.length(), "bad ttl " + word);
                int unit = units.indexOf(Character.toLowerCase(word.charAt(at++)));
                require(unit > previous, "bad ttl " + word);
                previous = unit;
                total += (long)Integer.parseInt(number) * seconds[unit];
            }
        }
        require(total >= 1 && total <= 604800, "bad ttl " + word);
        return (int)total;
    }

    static int compareData(Record a, Record b) {
        return switch (a.type()) {
            case 0 -> Long.compare(ipv4(a.data()), ipv4(b.data()));
            case 7 -> Arrays.compare(ipv6(a.data()), ipv6(b.data()));
            case 1, 2, 4 -> compareNames(a.data(), b.data());
            case 5 -> {
                String[] x = a.data().split(" "), y = b.data().split(" ");
                int order = Integer.compare(Integer.parseInt(x[0]), Integer.parseInt(y[0]));
                yield order == 0 ? compareNames(x[1], y[1]) : order;
            }
            case 6 -> a.data().compareTo(b.data());
            default -> 0;
        };
    }

    static List<Record> sorted(List<Record> records) {
        return records.stream().sorted(Main::compareData).toList();
    }

    static List<Record> records(Zone zone, String owner, int type) {
        return sorted(zone.records.stream().filter(r -> r.owner().equals(owner) && r.type() == type).toList());
    }

    static void zoneLine(String[] words, int line) {
        if (words[0].equals("ROOT")) {
            List<Long> additions = new ArrayList<>();
            for (String word : Arrays.copyOfRange(words, 1, words.length)) {
                long value = ipv4(word);
                require(!roots.contains(value) && !additions.contains(value), "duplicate root " + word);
                additions.add(value);
            }
            roots.addAll(additions);
            return;
        }
        if (words[0].equals("ZONE")) {
            current = null;
            String origin = name(words[1], false, null);
            long server = ipv4(words[2]);
            require(zones.stream().noneMatch(z -> z.origin.equals(origin) && z.server == server), "duplicate zone " + origin + " at " + words[2]);
            current = new Zone(origin, server, line);
            zones.add(current);
            return;
        }
        require(current != null, "no current zone");
        String owner = name(words[0], true, current.origin);
        require(below(owner, current.origin), "out of zone " + owner);
        int ttl = ttl(words[1]), type = type(words[2]);
        String[] data = Arrays.copyOfRange(words, 3, words.length);
        require(type == 6 || data.length == (type == 5 ? 2 : type == 3 ? 7 : 1), "wrong field count");
        String text;
        if (type == 0) text = address(ipv4(data[0]));
        else if (type == 7) text = address6(ipv6(data[0]));
        else if (type == 1 || type == 2 || type == 4) text = name(data[0], false, current.origin);
        else if (type == 5) {
            Integer preference = integer(data[0]);
            require(preference != null && preference <= 65535, "bad preference " + data[0]);
            text = preference + " " + name(data[1], false, current.origin);
        } else if (type == 6) {
            text = String.join(" ", data);
            require(text.length() >= 2 && text.startsWith("\"") && text.endsWith("\"") && !text.substring(1, text.length() - 1).contains("\""), "bad text " + text);
        } else {
            List<String> fields = new ArrayList<>();
            fields.add(name(data[0], false, current.origin));
            fields.add(name(data[1], false, current.origin));
            for (int i = 2; i < 6; i++) {
                require(integer(data[i]) != null, "bad number " + data[i]);
                fields.add(data[i]);
            }
            Integer minimum = integer(data[6]);
            require(minimum != null && minimum >= 1 && minimum <= 86400, "bad minimum " + data[6]);
            fields.add(data[6]);
            text = String.join(" ", fields);
        }
        require(type != 1 || !owner.startsWith("*."), "ns at wildcard");
        require(type != 3 || owner.equals(current.origin), "soa not at origin");
        require(type != 3 || current.soa() == null, "duplicate soa");
        String normalized = text;
        require(current.records.stream().noneMatch(r -> r.owner().equals(owner) && r.type() == type && r.data().equals(normalized)), "duplicate record");
        require(current.records.stream().noneMatch(r -> r.owner().equals(owner) && (type == 2 || r.type() == 2)), "cname conflict " + owner);
        current.records.add(new Record(owner, ttl, type, text));
    }

    static void finishZones() {
        List<Zone> valid = new ArrayList<>();
        for (Zone zone : zones) if (zone.soa() == null) System.out.println("error line " + zone.line + ": zone " + zone.origin + " at " + address(zone.server) + " has no soa");
        else {
            System.out.println("zone " + zone.origin + " at " + address(zone.server) + " records=" + zone.records.size());
            valid.add(zone);
        }
        zones.clear();
        zones.addAll(valid);
        System.out.println("loaded roots=" + roots.size() + " zones=" + zones.size() + " records=" + zones.stream().mapToInt(z -> z.records.size()).sum());
    }

    static boolean exists(Zone zone, String name) {
        return zone.records.stream().anyMatch(r -> below(r.owner(), name));
    }

    static Response authoritative(long server, String name, int type, String cut) {
        if (down.contains(server) || zones.stream().noneMatch(z -> z.server == server)) return new Response("TIMEOUT");
        Zone zone = null;
        for (Zone candidate : zones) if (candidate.server == server && below(name, candidate.origin) && (zone == null || length(candidate.origin) > length(zone.origin))) zone = candidate;
        if (zone == null || length(zone.origin) < length(cut)) return new Response("LAME");
        String delegation = null;
        for (Record record : zone.records) if (record.type() == 1 && !record.owner().equals(zone.origin) && below(name, record.owner()) && (delegation == null || length(record.owner()) < length(delegation))) delegation = record.owner();
        if (delegation != null) {
            Response response = new Response("REFERRAL");
            response.cut = delegation;
            response.authority = records(zone, delegation, 1);
            for (Record ns : response.authority) response.additional.addAll(records(zone, ns.data(), 0));
            return response;
        }
        List<Record> chosen = new ArrayList<>();
        for (Record record : zone.records) if (record.owner().equals(name)) chosen.add(record);
        if (chosen.isEmpty() && !exists(zone, name)) {
            String ancestor = parent(name);
            while (!exists(zone, ancestor)) ancestor = parent(ancestor);
            String wildcard = ancestor.equals(".") ? "*." : "*." + ancestor;
            for (Record record : zone.records) if (record.owner().equals(wildcard)) chosen.add(record);
        }
        Response response;
        if (chosen.isEmpty()) response = new Response(exists(zone, name) ? "NODATA" : "NXDOMAIN");
        else {
            List<Record> answer = chosen.stream().filter(r -> r.type() == type).map(r -> r.owner(name)).toList();
            if (!answer.isEmpty()) {
                response = new Response("ANSWER");
                response.answer = sorted(answer);
                return response;
            }
            if (type != 2) for (Record record : chosen) if (record.type() == 2) {
                response = new Response("CNAME");
                response.answer.add(record.owner(name));
                return response;
            }
            response = new Response("NODATA");
        }
        response.authority.add(zone.soa());
        return response;
    }

    static Response ask(long server, String name, int type, String cut) {
        Response response = authoritative(server, name, type, cut);
        queries.computeIfAbsent(server, ignored -> new int[7])[Arrays.asList(KINDS).indexOf(response.kind)]++;
        return response;
    }

    static void trace(int depth, String text) {
        System.out.println("  ".repeat(depth + 1) + text);
    }

    static int store(List<Record> records) {
        int ttl = Math.min(maxTtl, Math.max(minTtl, records.stream().mapToInt(Record::ttl).min().orElseThrow()));
        Record first = records.getFirst();
        cache.put(new Key(first.owner(), first.type()), new CacheEntry("POS", sorted(records), now + ttl));
        return ttl;
    }

    static List<Record> cachedRecords(CacheEntry entry) {
        return entry.records().stream().map(r -> r.ttl(entry.expiry() - now)).toList();
    }

    static Response queryServers(String name, int type, String cut, List<String> servers, int depth, List<Key> resolving) {
        if (servers == null) {
            for (long server : roots) {
                Response response = ask(server, name, type, cut);
                trace(depth, "ASK " + address(server) + " " + name + " " + TYPES[type] + " -> " + response.description());
                if (!response.kind.equals("LAME") && !response.kind.equals("TIMEOUT")) return response;
            }
        } else {
            List<String> ordered = new ArrayList<>(new HashSet<>(servers));
            ordered.sort(Main::compareNames);
            for (String host : ordered) {
                TreeSet<Long> addresses = new TreeSet<>();
                CacheEntry entry = cache.get(new Key(host, 0));
                if (entry != null && entry.kind().equals("POS")) for (Record record : entry.records()) addresses.add(ipv4(record.data()));
                else if (resolving.contains(new Key(host, 0))) trace(depth, "GLUELESS " + host + " -> LOOP");
                else {
                    trace(depth, "GLUELESS " + host);
                    Result result = resolve(host, 0, depth + 1, resolving);
                    if (result.status().equals("NOERROR")) for (Record record : result.answer()) if (record.type() == 0) addresses.add(ipv4(record.data()));
                }
                for (long server : addresses) {
                    Response response = ask(server, name, type, cut);
                    trace(depth, "ASK " + address(server) + " " + name + " " + TYPES[type] + " -> " + response.description());
                    if (!response.kind.equals("LAME") && !response.kind.equals("TIMEOUT")) return response;
                }
            }
        }
        return null;
    }

    static Response lookup(String name, int type, int depth, List<Key> resolving) {
        CacheEntry exact = cache.get(new Key(name, type));
        Response cached = null;
        if (exact != null) {
            cached = new Response(exact.kind().equals("POS") ? "ANSWER" : exact.kind());
            if (exact.kind().equals("POS")) cached.answer = cachedRecords(exact);
        }
        if (cached == null) for (var entry : cache.entrySet()) if (entry.getValue().kind().equals("NXDOMAIN") && below(name, entry.getKey().name())) {
            cached = new Response("NXDOMAIN");
            break;
        }
        if (cached == null && type != 2) {
            CacheEntry cname = cache.get(new Key(name, 2));
            if (cname != null && cname.kind().equals("POS")) {
                cached = new Response("CNAME");
                cached.answer = cachedRecords(cname);
            }
        }
        if (cached != null) {
            hits++;
            trace(depth, "CACHE HIT " + name + " " + TYPES[type] + " -> " + cached.description());
            return cached;
        }
        String cut = ".";
        List<String> servers = null;
        for (var entry : cache.entrySet()) if (entry.getKey().type() == 1 && entry.getValue().kind().equals("POS") && below(name, entry.getKey().name()) && (servers == null || length(entry.getKey().name()) > length(cut))) {
            cut = entry.getKey().name();
            servers = entry.getValue().records().stream().map(Record::data).toList();
        }
        if (servers != null) {
            hits++;
            trace(depth, "CACHE HIT " + name + " " + TYPES[type] + " -> REFERRAL " + cut);
        }
        while (true) {
            Response response = queryServers(name, type, cut, servers, depth, resolving);
            if (response == null) return new Response("SERVFAIL no server for " + cut);
            if (response.kind.equals("REFERRAL")) {
                store(response.authority);
                Map<String, List<Record>> glue = new LinkedHashMap<>();
                for (Record record : response.additional) glue.computeIfAbsent(record.owner(), ignored -> new ArrayList<>()).add(record);
                for (List<Record> group : glue.values()) store(group);
                cut = response.cut;
                servers = response.authority.stream().map(Record::data).toList();
                continue;
            }
            if (response.kind.equals("ANSWER") || response.kind.equals("CNAME")) {
                int ttl = store(response.answer);
                response.answer = response.answer.stream().map(r -> r.ttl(ttl)).toList();
            } else {
                Record soa = response.authority.getFirst();
                int minimum = Integer.parseInt(soa.data().split(" ")[6]);
                cache.put(new Key(name, type), new CacheEntry(response.kind, List.of(), now + Math.min(negTtl, Math.min(soa.ttl(), minimum))));
            }
            return response;
        }
    }

    static Result resolve(String name, int type, int depth, List<Key> resolving) {
        resolving.add(new Key(name, type));
        List<Record> aliases = new ArrayList<>();
        Set<String> seen = new HashSet<>();
        seen.add(name);
        String current = name, status;
        List<Record> answer;
        while (true) {
            Response response = lookup(current, type, depth, resolving);
            if (response.kind.equals("CNAME")) {
                Record alias = response.answer.getFirst();
                aliases.add(alias);
                String target = alias.data();
                if (seen.contains(target)) {
                    status = "SERVFAIL cname loop";
                    answer = List.of();
                    break;
                }
                if (aliases.size() == 9) {
                    status = "SERVFAIL cname chain too long";
                    answer = List.of();
                    break;
                }
                seen.add(target);
                current = target;
                continue;
            }
            if (response.kind.equals("ANSWER")) {
                status = "NOERROR";
                answer = new ArrayList<>(aliases);
                answer.addAll(response.answer);
            } else if (response.kind.equals("NODATA") || response.kind.equals("NXDOMAIN")) {
                status = response.kind;
                answer = aliases;
            } else {
                status = response.kind;
                answer = List.of();
            }
            break;
        }
        resolving.removeLast();
        resolutions[status.equals("NOERROR") ? 0 : status.equals("NODATA") ? 1 : status.equals("NXDOMAIN") ? 2 : 3]++;
        return new Result(status, answer);
    }

    static Result resolve(String name, int type) {
        return resolve(name, type, 0, new ArrayList<>());
    }

    static void answer(Result result) {
        for (Record record : result.answer()) System.out.println("answer " + record);
        System.out.println("status " + result.status());
    }

    static void addresses(String host, String prefix) {
        Result a = resolve(host, 0), aaaa = resolve(host, 7);
        List<String> addresses = new ArrayList<>();
        if (a.status().equals("NOERROR")) for (Record record : a.answer()) if (record.type() == 0) addresses.add(record.data());
        if (aaaa.status().equals("NOERROR")) for (Record record : aaaa.answer()) if (record.type() == 7) addresses.add(record.data());
        System.out.println(prefix + host + " -> " + (addresses.isEmpty() ? "no address" : String.join(" ", addresses)));
    }

    static List<Map.Entry<Key, CacheEntry>> selected(String name) {
        return cache.entrySet().stream().filter(e -> name == null || below(e.getKey().name(), name)).sorted((a, b) -> {
            int order = compareNames(a.getKey().name(), b.getKey().name()); return order == 0 ? Integer.compare(a.getKey().type(), b.getKey().type()) : order;
        }).toList();
    }

    static void command(String[] words) {
        switch (words[0]) {
            case "RESOLVE":
                {
                    String name = name(words[1], true, null);
                    int type = type(words[2]);
                    System.out.println("resolve " + name + " " + TYPES[type]);
                    answer(resolve(name, type));
                    break;
                }
            case "REVERSE":
                {
                    String output, reverse;
                    if (words[1].contains(":")) {
                        int[] groups = ipv6(words[1]);
                        output = address6(groups);
                        StringBuilder digits = new StringBuilder();
                        for (int group : groups) digits.append(String.format(Locale.ROOT, "%04x", group));
                        List<String> parts = new ArrayList<>();
                        for (int i = 31; i >= 0; i--) parts.add("" + digits.charAt(i));
                        reverse = String.join(".", parts) + ".ip6.arpa.";
                    } else {
                        long ip = ipv4(words[1]);
                        output = address(ip);
                        String[] fields = output.split("\\.");
                        reverse = fields[3] + "." + fields[2] + "." + fields[1] + "." + fields[0] + ".in-addr.arpa.";
                    }
                    System.out.println("reverse " + output + " " + reverse);
                    answer(resolve(reverse, 4));
                    break;
                }
            case "MX":
                {
                    String name = name(words[1], true, null);
                    System.out.println("mx " + name);
                    Result result = resolve(name, 5);
                    answer(result);
                    if (result.status().equals("NOERROR")) for (Record record : result.answer()) if (record.type() == 5) {
                        String[] fields = record.data().split(" ");
                        if (fields[1].equals(".")) System.out.println("exchange " + fields[0] + " . -> null");
                        else addresses(fields[1], "exchange " + fields[0] + " ");
                    }
                    if (result.status().equals("NODATA")) {
                        String host = name;
                        for (Record record : result.answer()) if (record.type() == 2) host = record.data();
                        addresses(host, "implicit ");
                    }
                    break;
                }
            case "QUERY":
                {
                    long server = ipv4(words[1]);
                    String name = name(words[2], true, null);
                    int type = type(words[3]);
                    Response response = ask(server, name, type, ".");
                    System.out.println("query " + address(server) + " " + name + " " + TYPES[type] + " -> " + response.description());
                    for (Record record : response.answer) System.out.println("answer " + record);
                    for (Record record : response.authority) System.out.println("authority " + record);
                    for (Record record : response.additional) System.out.println("additional " + record);
                    break;
                }
            case "DUMP":
                {
                    long server = ipv4(words[1]);
                    String name = name(words[2], false, null);
                    if (down.contains(server) || zones.stream().noneMatch(z -> z.server == server)) {
                        System.out.println("dump " + address(server) + " " + name + " -> TIMEOUT");
                        break;
                    }
                    Zone zone = zones.stream().filter(z -> z.server == server && z.origin.equals(name)).findFirst().orElse(null);
                    if (zone == null) System.out.println("dump " + address(server) + " " + name + " -> REFUSED");
                    else {
                        System.out.println("dump " + address(server) + " " + name + " records=" + zone.records.size());
                        zone.records.stream().sorted((a, b) -> {
                            int order = compareNames(a.owner(), b.owner()); if (order == 0) order = Integer.compare(a.type(), b.type()); return order == 0 ? compareData(a, b) : order;
                        }).forEach(r -> System.out.println("  " + r));
                    }
                    break;
                }
            case "DOWN", "UP":
                {
                    long server = ipv4(words[1]);
                    boolean disable = words[0].equals("DOWN");
                    require(disable ? !down.contains(server) : down.contains(server), "server " + words[1] + (disable ? " already down" : " not down"));
                    if (disable) down.add(server);
                    else down.remove(server);
                    System.out.println((disable ? "down " : "up ") + address(server));
                    break;
                }
            case "SET":
                {
                    require(Set.of("MINTTL", "MAXTTL", "NEGTTL").contains(words[1]), "bad setting " + words[1]);
                    Integer value = integer(words[2]);
                    require(value != null && value >= 1 && value <= 604800, "bad value " + words[2]);
                    require((words[1].equals("MINTTL") ? value : minTtl) <= (words[1].equals("MAXTTL") ? value : maxTtl), "minttl above maxttl");
                    if (words[1].equals("MINTTL")) minTtl = value;
                    else if (words[1].equals("MAXTTL")) maxTtl = value;
                    else negTtl = value;
                    System.out.println("set " + words[1] + "=" + value);
                    break;
                }
            case "TIME":
                {
                    Integer value = integer(words[1]);
                    require(value != null && value >= 1 && value <= 1000000, "bad time " + words[1]);
                    now += value;
                    int before = cache.size();
                    cache.entrySet().removeIf(e -> e.getValue().expiry() <= now);
                    System.out.println("time now=" + now + " expired=" + (before - cache.size()));
                    break;
                }
            case "CACHE", "FLUSH":
                {
                    String name = words.length == 2 ? name(words[1], false, null) : null;
                    var entries = selected(name);
                    if (words[0].equals("FLUSH")) {
                        for (var entry : entries) cache.remove(entry.getKey());
                        System.out.println("flush removed=" + entries.size());
                    } else {
                        System.out.println("cache entries=" + entries.size());
                        for (var entry : entries) if (entry.getValue().kind().equals("POS")) for (Record record : cachedRecords(entry.getValue())) System.out.println("  " + record);
                        else System.out.println("  " + entry.getKey().name() + " " + (entry.getValue().expiry() - now) + " " + TYPES[entry.getKey().type()] + " " + entry.getValue().kind());
                    }
                    break;
                }
                case "STATS": System.out.println("stats queries=" + queries.values().stream().mapToInt(a -> Arrays.stream(a).sum()).sum() + " hits=" + hits);
                queries.forEach((server, counts) -> {
                    StringBuilder line = new StringBuilder("  " + address(server) + " sent=" + Arrays.stream(counts).sum()); for (int i = 0; i < KINDS.length; i++) line.append(" ").append(KINDS[i].toLowerCase(Locale.ROOT)).append("=").append(counts[i]); System.out.println(line);
                });
                System.out.println("resolutions noerror=" + resolutions[0] + " nodata=" + resolutions[1] + " nxdomain=" + resolutions[2] + " servfail=" + resolutions[3]);
        }
    }

    public static void main(String[] args) throws IOException {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
        String line;
        int number = 0;
        while (!(line = input.readLine()).equals("END ZONES")) {
            number++;
            try {
                zoneLine(line.split(" "), number);
            } catch (Problem ex) {
                System.out.println("error line " + number + ": " + ex.getMessage());
            }
        }
        number++;
        finishZones();
        while (!(line = input.readLine()).equals("END")) {
            number++;
            try {
                command(line.split(" "));
            } catch (Problem ex) {
                System.out.println("error line " + number + ": " + ex.getMessage());
            }
        }
    }
}
