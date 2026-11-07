import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.io.IOException;
import java.util.*;
import java.util.function.Predicate;
public final class Main {
    static final class Packet {
        int number, length;
        long time;
        int[] bytes = new int[0], data = new int[0];
        String reason, duplicate = "";
        List<String> layers = new ArrayList<>(), answers = new ArrayList<>();
        Map<String, List<Object>> fields = new HashMap<>();
        Packet(int number, long time, int length) {
            this.number = number;
            this.time = time;
            this.length = length;
        }
        void put(String name, long value) {
            fields.put(name, new ArrayList<>(List.of(value)));
        }
        void put(String name, String value) {
            fields.put(name, new ArrayList<>(List.of(value)));
        }
        void append(String name, long value) {
            fields.computeIfAbsent(name, key -> new ArrayList<>()).add(value);
        }
        void append(String name, String value) {
            fields.computeIfAbsent(name, key -> new ArrayList<>()).add(value);
        }
        boolean has(String name) {
            return fields.containsKey(name);
        }
        long num(String name) {
            return (Long)fields.get(name).getFirst();
        }
        String text(String name) {
            return (String)fields.get(name).getFirst();
        }
        List<Object> values(String name) {
            return fields.getOrDefault(name, List.of());
        }
    }
    static final String[][] FIELDS = {{"frame.number", "integer"},
                                      {"frame.time", "integer"},
                                      {"frame.len", "integer"},
                                      {"frame.protocols", "string"},
                                      {"frame.malformed", "string"},
                                      {"frame.bad_checksum", "presence"},
                                      {"eth.dst", "mac"},
                                      {"eth.src", "mac"},
                                      {"eth.type", "hex4"},
                                      {"arp.opcode", "integer"},
                                      {"arp.src.hw", "mac"},
                                      {"arp.src.ip", "ipv4"},
                                      {"arp.dst.hw", "mac"},
                                      {"arp.dst.ip", "ipv4"},
                                      {"ip.hdr_len", "integer"},
                                      {"ip.tos", "hex2"},
                                      {"ip.len", "integer"},
                                      {"ip.id", "hex4"},
                                      {"ip.flags.df", "integer"},
                                      {"ip.flags.mf", "integer"},
                                      {"ip.frag_offset", "integer"},
                                      {"ip.ttl", "integer"},
                                      {"ip.proto", "integer"},
                                      {"ip.checksum", "hex4"},
                                      {"ip.checksum.status", "string"},
                                      {"ip.src", "ipv4"},
                                      {"ip.dst", "ipv4"},
                                      {"ip.fragment", "presence"},
                                      {"icmp.type", "integer"},
                                      {"icmp.code", "integer"},
                                      {"icmp.checksum", "hex4"},
                                      {"icmp.checksum.status", "string"},
                                      {"icmp.id", "integer"},
                                      {"icmp.seq", "integer"},
                                      {"udp.srcport", "integer"},
                                      {"udp.dstport", "integer"},
                                      {"udp.length", "integer"},
                                      {"udp.checksum", "hex4"},
                                      {"udp.checksum.status", "string"},
                                      {"tcp.srcport", "integer"},
                                      {"tcp.dstport", "integer"},
                                      {"tcp.stream", "integer"},
                                      {"tcp.seq", "integer"},
                                      {"tcp.seq_raw", "integer"},
                                      {"tcp.ack", "integer"},
                                      {"tcp.ack_raw", "integer"},
                                      {"tcp.hdr_len", "integer"},
                                      {"tcp.flags", "hex2"},
                                      {"tcp.flags.fin", "integer"},
                                      {"tcp.flags.syn", "integer"},
                                      {"tcp.flags.rst", "integer"},
                                      {"tcp.flags.psh", "integer"},
                                      {"tcp.flags.ack", "integer"},
                                      {"tcp.flags.urg", "integer"},
                                      {"tcp.window", "integer"},
                                      {"tcp.window.calc", "integer"},
                                      {"tcp.checksum", "hex4"},
                                      {"tcp.checksum.status", "string"},
                                      {"tcp.urgent", "integer"},
                                      {"tcp.option", "string"},
                                      {"tcp.options.mss", "integer"},
                                      {"tcp.options.wscale", "integer"},
                                      {"tcp.options.malformed", "presence"},
                                      {"tcp.len", "integer"},
                                      {"tcp.analysis.retransmission", "presence"},
                                      {"tcp.analysis.out_of_order", "presence"},
                                      {"tcp.analysis.lost_segment", "presence"},
                                      {"tcp.analysis.duplicate_ack", "presence"},
                                      {"dns.id", "hex4"},
                                      {"dns.flags", "hex4"},
                                      {"dns.flags.response", "integer"},
                                      {"dns.flags.opcode", "integer"},
                                      {"dns.flags.rcode", "integer"},
                                      {"dns.count.queries", "integer"},
                                      {"dns.count.answers", "integer"},
                                      {"dns.count.auth_rr", "integer"},
                                      {"dns.count.add_rr", "integer"},
                                      {"dns.qry.name", "string"},
                                      {"dns.qry.type", "integer"},
                                      {"dns.answer", "string"},
                                      {"dns.authority", "string"},
                                      {"dns.additional", "string"},
                                      {"dns.a", "ipv4"},
                                      {"data.len", "integer"}};
    static final String[][] ALIASES = {{"eth.addr", "mac", "eth.dst", "eth.src"},
                                       {"ip.addr", "ipv4", "ip.src", "ip.dst"},
                                       {"udp.port", "integer", "udp.srcport", "udp.dstport"},
                                       {"tcp.port", "integer", "tcp.srcport", "tcp.dstport"}};
    static final List<String> PROTOCOLS = List.of("eth", "arp", "ip", "icmp", "udp", "tcp", "dns", "data");
    static final String[] FLAGS = {"FIN", "SYN", "RST", "PSH", "ACK", "URG", "ECE", "CWR"};
    static final String[] CHECKSUMS = {"ip", "icmp", "udp", "tcp"},
                          CHECKSUM_NAMES = {"IPv4", "ICMP", "UDP", "TCP"};
    static String type(String name) {
        for (String[] row : FIELDS)
            if (row[0].equals(name))
                return row[1];
        for (String[] row : ALIASES)
            if (row[0].equals(name))
                return row[1];
        return PROTOCOLS.contains(name) ? "presence" : null;
    }
    static List<Object> values(Packet p, String name) {
        for (String[] row : ALIASES)
            if (row[0].equals(name)) {
                List<Object> result = new ArrayList<>(p.values(row[2]));
                result.addAll(p.values(row[3]));
                return result;
            }
        return p.values(name);
    }
    static String notation(String type, Object value) {
        if (type.equals("string"))
            return (String)value;
        long n = (Long)value;
        return switch (type) {
            case "hex2" -> String.format(Locale.ROOT, "0x%02x", n);
            case "hex4" -> String.format(Locale.ROOT, "0x%04x", n);
            case "ipv4" -> LinkNetwork.ipv4(n);
            case "mac" -> LinkNetwork.mac(n);
            default -> Long.toString(n);
        };
    }
    static String shown(Packet p, String name) {
        return notation(type(name), p.values(name).getFirst());
    }
    static String seconds(long time) {
        return (time / 1000000) + "." + String.format(Locale.ROOT, "%06d", time % 1000000);
    }
    static String optional(long value) {
        return value < 0 ? "-" : Long.toString(value);
    }
    static void dissect(Packet p, long origin) {
        if (p.reason == null) {
            String layer = "eth";
            int[] payload = p.bytes;
            while (layer != null) {
                p.layers.add(layer);
                Packet temporary = new Packet(p.number, p.time, p.length);
                temporary.fields.putAll(p.fields);
                try {
                    int[] remaining = switch (layer) {
                        case "eth" -> LinkNetwork.ethernet(temporary, payload);
                        case "arp" -> LinkNetwork.arp(temporary, payload);
                        case "ip" -> LinkNetwork.ipv4(temporary, payload);
                        case "icmp" -> Transport.icmp(temporary, payload);
                        case "udp" -> Transport.udp(temporary, payload);
                        case "tcp" -> Transport.tcp(temporary, payload);
                        case "dns" -> DnsApp.dissect(temporary, payload);
                        default -> new int[0];
                    };
                    p.fields = temporary.fields;
                    p.answers = temporary.answers;
                    String next = null;
                    if (layer.equals("eth")) {
                        if (p.num("eth.type") == 2054)
                            next = "arp";
                        else if (p.num("eth.type") == 2048)
                            next = "ip";
                    } else if (layer.equals("ip") && !p.has("ip.fragment"))
                        next = switch ((int)p.num("ip.proto")) {
                            case 1 -> "icmp";
                            case 17 -> "udp";
                            case 6 -> "tcp";
                            default -> null;
                        };
                    else if (layer.equals("udp") &&
                             (p.num("udp.srcport") == 53 || p.num("udp.dstport") == 53))
                        next = "dns";
                    payload = remaining;
                    layer = next;
                } catch (LinkNetwork.Bad error) {
                    p.reason = error.getMessage();
                    payload = new int[0];
                    break;
                }
            }
            if (p.reason == null && payload.length > 0) {
                p.data = payload;
                p.layers.add("data");
                p.put("data.len", payload.length);
            }
        }
        p.put("frame.number", p.number);
        p.put("frame.time", p.time - origin);
        p.put("frame.len", p.length);
        if (!p.layers.isEmpty())
            p.put("frame.protocols", String.join(":", p.layers));
        if (p.reason != null)
            p.put("frame.malformed", p.reason);
        for (String layer : CHECKSUMS)
            if (p.has(layer + ".checksum.status") && p.text(layer + ".checksum.status").equals("bad"))
                p.put("frame.bad_checksum", 0);
    }
    static String summary(Packet p) {
        String source = "-", destination = "-";
        if (p.has("ip.src")) {
            source = shown(p, "ip.src");
            destination = shown(p, "ip.dst");
        } else if (p.has("eth.src")) {
            source = shown(p, "eth.src");
            destination = shown(p, "eth.dst");
        }
        String last = "dump";
        for (String layer : p.layers)
            if (!layer.equals("data"))
                last = layer;
        String protocol = switch (last) {
            case "eth" -> "ETH";
            case "arp" -> "ARP";
            case "ip" -> "IPv4";
            case "icmp" -> "ICMP";
            case "udp" -> "UDP";
            case "tcp" -> "TCP";
            case "dns" -> "DNS";
            default -> "DUMP";
        };
        String info = p.reason;
        if (info == null) {
            if (last.equals("eth"))
                info = "EtherType " + shown(p, "eth.type");
            else if (last.equals("arp"))
                info = p.num("arp.opcode") == 1
                           ? "Who has " + shown(p, "arp.dst.ip") + "? Tell " + shown(p, "arp.src.ip")
                       : p.num("arp.opcode") == 2
                           ? shown(p, "arp.src.ip") + " is at " + shown(p, "arp.src.hw")
                           : "Opcode " + p.num("arp.opcode");
            else if (last.equals("ip"))
                info = p.has("ip.fragment")
                           ? "Fragment id=" + shown(p, "ip.id") + " off=" + p.num("ip.frag_offset") +
                                 (p.num("ip.flags.mf") == 1 ? " MF" : "")
                           : "Protocol " + p.num("ip.proto");
            else if (last.equals("icmp"))
                info = p.num("icmp.type") == 0 || p.num("icmp.type") == 8
                           ? (p.num("icmp.type") == 8 ? "Echo request" : "Echo reply") +
                                 " id=" + p.num("icmp.id") + " seq=" + p.num("icmp.seq")
                           : "Type " + p.num("icmp.type") + " code " + p.num("icmp.code");
            else if (last.equals("udp"))
                info = p.num("udp.srcport") + " -> " + p.num("udp.dstport") +
                       " Len=" + (p.num("udp.length") - 8);
            else if (last.equals("tcp")) {
                String mark = p.duplicate;
                String[] labels = {"[TCP Retransmission] ", "[TCP Out-Of-Order] ",
                                   "[TCP Previous segment not captured] "};
                for (int i = 0; i < 3; i++)
                    if (p.has("tcp.analysis." + Flows.MARKS[i]))
                        mark = labels[i];
                List<String> flags = new ArrayList<>();
                for (int i = 0; i < FLAGS.length; i++)
                    if ((p.num("tcp.flags") & (1L << i)) != 0)
                        flags.add(FLAGS[i]);
                info = mark + p.num("tcp.srcport") + " -> " + p.num("tcp.dstport") + " [" +
                       (flags.isEmpty() ? "<None>" : String.join(", ", flags)) + "] Seq=" + p.num("tcp.seq");
                if (p.num("tcp.flags.ack") == 1)
                    info += " Ack=" + p.num("tcp.ack");
                info += " Win=" + p.num("tcp.window.calc") + " Len=" + p.num("tcp.len");
                for (Object value : p.values("tcp.option")) {
                    String option = (String)value;
                    String[] parts = option.split(" ");
                    if (parts[0].equals("MSS"))
                        info += " MSS=" + parts[1];
                    else if (parts[0].equals("WS"))
                        info += " WS=" + (1L << Integer.parseInt(parts[1]));
                    else if (option.equals("SACK_PERM"))
                        info += " SACK_PERM";
                    else if (parts[0].equals("TS"))
                        info += " TSval=" + parts[1] + " TSecr=" + parts[2];
                }
            } else if (last.equals("dns")) {
                info = (p.num("dns.flags.response") == 1 ? "Response" : "Query") + " " + shown(p, "dns.id");
                if (p.num("dns.flags.rcode") != 0)
                    info += " " + DnsApp.rcode(p.num("dns.flags.rcode"));
                List<Object> names = p.values("dns.qry.name"), types = p.values("dns.qry.type");
                for (int i = 0; i < names.size(); i++)
                    info += " " + DnsApp.type((Long)types.get(i)) + " " + names.get(i);
                for (String answer : p.answers)
                    info += " " + answer;
            }
        }
        if (p.has("tcp.options.malformed"))
            info += " [bad TCP options]";
        for (int i = 0; i < CHECKSUMS.length; i++)
            if (p.has(CHECKSUMS[i] + ".checksum.status") &&
                p.text(CHECKSUMS[i] + ".checksum.status").equals("bad"))
                info += " [bad " + CHECKSUM_NAMES[i] + " checksum]";
        return p.number + " " + seconds(p.num("frame.time")) + " " + source + " -> " + destination + " " +
            protocol + " " + p.length + " " + info;
    }
    record Token(String kind, String text, int column) {}
    static final class FilterError extends RuntimeException {
        FilterError(String message) {
            super(message);
        }
    }
    static List<Token> tokenize(String expression) {
        List<Token> tokens = new ArrayList<>();
        int i = 0;
        while (i < expression.length()) {
            char c = expression.charAt(i);
            int start = i;
            if (c == ' ') {
                i++;
                continue;
            }
            String pair = i + 1 < expression.length() ? expression.substring(i, i + 2) : "";
            if (List.of("==", "!=", "<=", ">=", "&&", "||").contains(pair)) {
                tokens.add(new Token(pair, pair, i + 1));
                i += 2;
            } else if ("()!<>".indexOf(c) >= 0) {
                tokens.add(new Token(Character.toString(c), Character.toString(c), i + 1));
                i++;
            } else if (c == '"') {
                int end = expression.indexOf('"', i + 1);
                if (end < 0)
                    throw new FilterError("unterminated string at column " + (i + 1));
                tokens.add(new Token("string", expression.substring(i, end + 1), i + 1));
                i = end + 1;
            } else if (word(c)) {
                while (i < expression.length() && word(expression.charAt(i)))
                    i++;
                String text = expression.substring(start, i);
                String kind = switch (text) {
                    case "and" -> "&&";
                    case "or" -> "||";
                    case "not" -> "!";
                    default -> "word";
                };
                tokens.add(new Token(kind, text, start + 1));
            } else
                throw new FilterError("invalid character '" + c + "' at column " + (i + 1));
        }
        return tokens;
    }
    static boolean word(char c) {
        return c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || "._:".indexOf(c) >= 0;
    }
    static Object convert(Token token, String type) {
        String value = token.text;
        if (type.equals("string"))
            return token.kind.equals("string") ? value.substring(1, value.length() - 1) : null;
        if (!token.kind.equals("word"))
            return null;
        if (List.of("integer", "hex2", "hex4").contains(type)) {
            if (value.matches("[0-9]{1,15}"))
                return Long.parseLong(value);
            if (value.matches("0x[0-9a-fA-F]{1,12}"))
                return Long.parseLong(value.substring(2), 16);
        } else if (type.equals("ipv4") || type.equals("mac")) {
            boolean mac = type.equals("mac");
            String[] parts = value.split(mac ? ":" : "\\.", -1);
            if (parts.length != (mac ? 6 : 4))
                return null;
            long result = 0;
            for (String part : parts) {
                if (!part.matches(mac ? "[0-9a-fA-F]{2}" : "[0-9]{1,3}"))
                    return null;
                int n = Integer.parseInt(part, mac ? 16 : 10);
                if (n > 255)
                    return null;
                result = result * 256 + n;
            }
            return result;
        }
        return null;
    }
    static final class Parser {
        List<Token> tokens;
        int position;
        Parser(String expression) {
            tokens = tokenize(expression);
        }
        Token take() {
            if (position >= tokens.size())
                throw new FilterError("unexpected end of filter");
            return tokens.get(position++);
        }
        boolean next(String kind) {
            return position < tokens.size() && tokens.get(position).kind.equals(kind);
        }
        FilterError unexpected(Token token) {
            return new FilterError("unexpected '" + token.text + "' at column " + token.column);
        }
        Predicate<Packet> expression() {
            Predicate<Packet> result = product();
            while (next("||")) {
                take();
                Predicate<Packet> left = result, right = product();
                result = p -> left.test(p) || right.test(p);
            }
            return result;
        }
        Predicate<Packet> product() {
            Predicate<Packet> result = negation();
            while (next("&&")) {
                take();
                Predicate<Packet> left = result, right = negation();
                result = p -> left.test(p) && right.test(p);
            }
            return result;
        }
        Predicate<Packet> negation() {
            if (next("!")) {
                take();
                Predicate<Packet> child = negation();
                return p -> !child.test(p);
            }
            Token token = take();
            if (token.kind.equals("(")) {
                Predicate<Packet> result = expression();
                Token closing = take();
                if (!closing.kind.equals(")"))
                    throw unexpected(closing);
                return result;
            }
            if (!token.kind.equals("word"))
                throw unexpected(token);
            String name = token.text, fieldType = type(name);
            if (fieldType == null)
                throw new FilterError("unknown field " + name);
            if (position >= tokens.size() ||
                !List.of("==", "!=", "<", ">", "<=", ">=").contains(tokens.get(position).kind))
                return p -> PROTOCOLS.contains(name) ? p.layers.contains(name) : !values(p, name).isEmpty();
            String operator = take().text;
            if (fieldType.equals("presence") ||
                fieldType.equals("string") && !operator.equals("==") && !operator.equals("!="))
                throw new FilterError("operator " + operator + " not allowed for " + name);
            Token valueToken = take();
            if (!valueToken.kind.equals("word") && !valueToken.kind.equals("string"))
                throw unexpected(valueToken);
            Object target = convert(valueToken, fieldType);
            if (target == null)
                throw new FilterError("invalid value " + valueToken.text + " for " + name);
            return p -> {
                List<Object> actual = values(p, name);
                if (actual.isEmpty())
                    return false;
                for (Object value : actual) {
                    int comparison = fieldType.equals("string") ? ((String)value).compareTo((String)target)
                                                                : Long.compare((Long)value, (Long)target);
                    boolean matches = switch (operator) {
                        case "==" -> comparison == 0;
                        case "!=" -> comparison != 0;
                        case "<" -> comparison < 0;
                        case ">" -> comparison > 0;
                        case "<=" -> comparison <= 0;
                        default -> comparison >= 0;
                    };
                    if (operator.equals("!=")) {
                        if (!matches)
                            return false;
                    } else if (matches)
                        return true;
                }
                return operator.equals("!=");
            };
        }
        Predicate<Packet> parse() {
            Predicate<Packet> result = expression();
            if (position < tokens.size())
                throw unexpected(tokens.get(position));
            return result;
        }
    }
    static List<String> details(List<Packet> packets, int number) {
        List<String> output = new ArrayList<>();
        if (number < 1 || number > packets.size()) {
            output.add("packet " + number + " not found");
            return output;
        }
        Packet p = packets.get(number - 1);
        output.add("packet " + number);
        List<String> layers = new ArrayList<>(List.of("frame"));
        layers.addAll(p.layers);
        for (String layer : layers) {
            output.add(layer);
            for (String[] field : FIELDS)
                if (field[0].startsWith(layer + "."))
                    for (Object value : p.values(field[0]))
                        output.add("  " + field[0] +
                                   (field[1].equals("presence") ? "" : " = " + notation(field[1], value)));
            if (layer.equals("data"))
                for (String line : Hexdump.lines(p.data))
                    output.add("  " + line);
        }
        return output;
    }
    static List<String> stats(List<Packet> packets) {
        List<String> output = new ArrayList<>();
        long total = 0;
        for (Packet p : packets)
            total += p.length;
        output.add("packets " + packets.size());
        output.add("bytes " + total);
        output.add("duration " + seconds(packets.getLast().time - packets.getFirst().time));
        output.add("hierarchy");
        String[] hierarchy = {"eth", "  arp", "  ip", "    icmp", "    udp", "      dns", "    tcp"};
        for (String item : hierarchy) {
            String layer = item.strip();
            long count = 0, bytes = 0;
            for (Packet p : packets)
                if (p.layers.contains(layer)) {
                    count++;
                    bytes += p.length;
                }
            output.add(item + " " + count + " " + bytes);
        }
        output.add("checksums");
        for (String layer : CHECKSUMS) {
            long good = 0, bad = 0, none = 0;
            for (Packet p : packets)
                if (p.has(layer + ".checksum.status")) {
                    String status = p.text(layer + ".checksum.status");
                    if (status.equals("good"))
                        good++;
                    else if (status.equals("bad"))
                        bad++;
                    else
                        none++;
                }
            output.add(layer + " good " + good + " bad " + bad +
                       (layer.equals("udp") ? " none " + none : ""));
        }
        output.add("malformed");
        for (String layer : List.of("dump", "eth", "arp", "ip", "icmp", "udp", "tcp", "dns")) {
            long count = 0;
            for (Packet p : packets)
                if (p.reason != null && (p.layers.isEmpty() ? "dump" : p.layers.getLast()).equals(layer))
                    count++;
            output.add(layer + " " + count);
        }
        output.add("tcp analysis");
        for (String mark : Flows.MARKS) {
            long count = 0;
            for (Packet p : packets)
                if (p.has("tcp.analysis." + mark))
                    count++;
            output.add(mark + " " + count);
        }
        List<Packet> pending = new ArrayList<>();
        List<Long> responseTimes = new ArrayList<>();
        long queries = 0, responses = 0;
        long[] rcodes = new long[16];
        Map<String, Integer> names = new HashMap<>();
        for (Packet p : packets)
            if (p.has("dns.id")) {
                if (p.num("dns.flags.response") == 0) {
                    queries++;
                    pending.add(p);
                    for (Object value : p.values("dns.qry.name"))
                        names.merge((String)value, 1, Integer::sum);
                } else {
                    responses++;
                    rcodes[(int)p.num("dns.flags.rcode")]++;
                    for (int i = 0; i < pending.size(); i++) {
                        Packet q = pending.get(i);
                        if (q.num("dns.id") == p.num("dns.id") && q.num("ip.src") == p.num("ip.dst") &&
                            q.num("ip.dst") == p.num("ip.src") &&
                            q.num("udp.srcport") == p.num("udp.dstport") &&
                            q.num("udp.dstport") == p.num("udp.srcport")) {
                            responseTimes.add(p.time - q.time);
                            pending.remove(i);
                            break;
                        }
                    }
                }
            }
        output.add("dns");
        output.add("queries " + queries);
        output.add("responses " + responses);
        output.add("transactions " + responseTimes.size());
        output.add("unanswered " + pending.size());
        output.add(responseTimes.isEmpty() ? "response_time -"
                                           : "response_time min " + seconds(Collections.min(responseTimes)) +
                                                 " max " + seconds(Collections.max(responseTimes)));
        for (int i = 0; i < rcodes.length; i++)
            if (rcodes[i] > 0)
                output.add("rcode " + DnsApp.rcode(i) + " " + rcodes[i]);
        output.add("names");
        List<String> ordered = new ArrayList<>(names.keySet());
        ordered.sort(
            Comparator.<String>comparingInt(names::get).reversed().thenComparing(Comparator.naturalOrder()));
        for (String name : ordered)
            output.add(name + " " + names.get(name));
        return output;
    }
    static List<String> streamLines(Flows flows, List<Packet> packets) {
        List<String> output = new ArrayList<>();
        long origin = packets.getFirst().time;
        for (Flows.Stream stream : flows.streams) {
            if (!output.isEmpty())
                output.add("");
            output.add("stream " + stream.number + " " + stream.client + " -> " + stream.server);
            output.add("packets " + stream.packets + " bytes " + stream.bytes + " start " +
                       seconds(stream.start - origin) + " duration " + seconds(stream.end - stream.start));
            output.add("states " + String.join(", ", stream.history));
            output.add("handshake syn " + optional(stream.syn) + " syn_ack " + optional(stream.synAck) +
                       " ack " + optional(stream.ack) + " rtt " +
                       (stream.syn >= 0 && stream.ack >= 0
                            ? seconds(packets.get(stream.ack - 1).time - packets.get(stream.syn - 1).time)
                            : "-"));
            output.add("options client mss " + optional(stream.clientSide.mss) + " wscale " +
                       optional(stream.clientSide.ws) + " server mss " + optional(stream.serverSide.mss) +
                       " wscale " + optional(stream.serverSide.ws));
            for (Flows.Side side : List.of(stream.clientSide, stream.serverSide)) {
                String text = side.name + " packets " + side.packets + " payload " + side.payload;
                for (int i = 0; i < Flows.MARKS.length; i++)
                    text += " " + Flows.MARKS[i] + " " + side.marks[i];
                output.add(text);
            }
            output.addAll(stream.events);
        }
        return output;
    }
    static void write(String name, List<String> lines) throws IOException {
        Files.writeString(Path.of("output", name), lines.isEmpty() ? "" : String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
    public static void main(String[] args) throws IOException {
        List<Packet> packets = Hexdump.read();
        long origin = packets.getFirst().time;
        Flows flows = new Flows();
        for (Packet p : packets) {
            dissect(p, origin);
            if (p.has("tcp.srcport"))
                flows.track(p);
        }
        List<String> summaries = new ArrayList<>();
        for (Packet p : packets)
            summaries.add(summary(p));
        List<String> summaryOutput = new ArrayList<>(summaries), detailOutput = new ArrayList<>();
        boolean firstDetail = true;
        for (String line : Files.readAllLines(Path.of("input/filters.txt"), StandardCharsets.US_ASCII)) {
            if (line.startsWith("FILTER ")) {
                String expression = line.substring(7);
                summaryOutput.add("");
                summaryOutput.add("filter " + expression);
                try {
                    Predicate<Packet> filter = new Parser(expression).parse();
                    int matched = 0;
                    for (int i = 0; i < packets.size(); i++)
                        if (filter.test(packets.get(i))) {
                            matched++;
                            summaryOutput.add(summaries.get(i));
                        }
                    summaryOutput.add("matched " + matched + " of " + packets.size());
                } catch (FilterError error) {
                    summaryOutput.add("error: " + error.getMessage());
                }
            } else if (line.startsWith("DETAIL ")) {
                if (!firstDetail)
                    detailOutput.add("");
                firstDetail = false;
                detailOutput.addAll(details(packets, Integer.parseInt(line.substring(7))));
            }
        }
        Files.createDirectories(Path.of("output"));
        write("summary.txt", summaryOutput);
        write("details.txt", detailOutput);
        write("conversations.csv", Flows.conversations(packets));
        write("endpoints.csv", Flows.endpoints(packets));
        write("protocol_stats.txt", stats(packets));
        write("tcp_streams.txt", streamLines(flows, packets));
    }
}
