import java.io.*;
import java.util.*;

public class Main {
    record Prefix(long address, int length) {
        long network() {
            return address & mask(length);
        }
        boolean contains(long value) {
            return (value & mask(length)) == network();
        }
        public String toString() {
            return ip(address) + "/" + length;
        }
    }
    record Ports(int first, int last, boolean any) {
        boolean contains(int port) {
            return first <= port && port <= last;
        }
        public String toString() {
            return any ? "any" : first == last ? "" + first : first + "-" + last;
        }
    }

    static class Iface {
        String name, rpf = "off";
        Prefix prefix;
        boolean up = true, outside;
        int pool, rx, tx, drop;
        List<TreeMap<Integer, Rule>> acl = List.of(new TreeMap<>(), new TreeMap<>());
        int[] defaults = new int[2];
        Iface(String name, Prefix prefix) {
            this.name = name;
            this.prefix = prefix;
        }
    }

    static class Route {
        char type;
        Prefix prefix;
        Iface output;
        Long hop;
        int metric, hits;
        Route(char type, Prefix prefix, Iface output, Long hop, int metric) {
            this.type = type;
            this.prefix = prefix;
            this.output = output;
            this.hop = hop;
            this.metric = metric;
        }
        public String toString() {
            return type + " " + prefix + (hop == null ? "" : " via " + ip(hop)) + " dev " + output.name + " metric " + metric;
        }
    }

    static class Rule {
        int sequence, hits;
        String action, proto;
        Prefix source, destination;
        Ports sports, dports;
        boolean established;
    }
    record StaticNat(long inside, long outside) {}
    record Forward(Iface iface, String proto, int port, long inside, int inport) {}
    static class Pat {
        Iface iface;
        String proto;
        long inside;
        int inport, port, last;
        Pat(Iface iface, String proto, long inside, int inport, int port) {
            this.iface = iface;
            this.proto = proto;
            this.inside = inside;
            this.inport = inport;
            this.port = port;
            this.last = clock;
        }
    }
    record Tuple(String proto, long source, int sport, long destination, int dport) {}
    static class Connection {
        int number, origPackets, replyPackets, last;
        Tuple orig, reply;
        Iface input, output;
        String state;
        boolean origFin, replyFin;
    }

    static class CommandError extends RuntimeException {
        CommandError(String message) {
            super(message);
        }
    }

    static final List<Iface> interfaces = new ArrayList<>();
    static final List<Route> routes = new ArrayList<>();
    static final List<StaticNat> statics = new ArrayList<>();
    static final List<Forward> forwards = new ArrayList<>();
    static final List<Pat> pats = new ArrayList<>();
    static final List<Connection> connections = new ArrayList<>();
    static final Map<String, Integer> timeouts = new HashMap<>(Map.of("TCP", 300, "UDP", 60, "ICMP", 30));
    static final String[] REASONS = {"down", "martian", "rpf", "invalid", "acl_in", "ttl", "noroute", "acl_out", "exhausted"};
    static final int[] drops = new int[9];
    static int clock, packetNumber, connectionNumber, forwarded, local, errors;
    static void error(String text) {
        throw new CommandError(text);
    }

    static long mask(int length) {
        return length == 0 ? 0 : (0xffffffffL << (32 - length)) & 0xffffffffL;
    }

    static String ip(long value) {
        return (value >>> 24) + "." + ((value >>> 16) & 255) + "." + ((value >>> 8) & 255) + "." + (value & 255);
    }

    static Long parseAddress(String text) {
        String[] fields = text.split("\\.", -1);
        if (fields.length != 4) return null;
        long value = 0;
        for (String field : fields) {
            if (!field.matches("0|[1-9][0-9]{0,2}")) return null;
            int part = Integer.parseInt(field);
            if (part > 255) return null;
            value = (value << 8) | part;
        }
        return value;
    }

    static long address(String text) {
        Long value = parseAddress(text);
        if (value == null) error("bad address " + text);
        return value;
    }

    static Prefix parsePrefix(String text) {
        String[] parts = text.split("/", -1);
        if (parts.length != 2 || !parts[1].matches("0|[1-9][0-9]?")) return null;
        Long value = parseAddress(parts[0]);
        int length = Integer.parseInt(parts[1]);
        return value == null || length > 32 ? null : new Prefix(value, length);
    }

    static Prefix prefix(String text, boolean any) {
        if (any && text.equals("ANY")) return new Prefix(0, 0);
        Prefix prefix = parsePrefix(text);
        if (prefix == null) error("bad prefix " + text);
        if (prefix.address() != prefix.network()) error("host bits set in " + text);
        return prefix;
    }

    static Iface iface(String name) {
        for (Iface iface : interfaces) if (iface.name.equals(name)) return iface;
        error("no interface " + name);
        return null;
    }

    static Iface localAddress(long address) {
        for (Iface iface : interfaces) if (iface.prefix.address() == address) return iface;
        return null;
    }

    static int range(String text, int low, int high, String reason) {
        int value = Integer.parseInt(text);
        if (value < low || value > high) error(reason + " " + text);
        return value;
    }

    static Ports ports(String text) {
        if (text.equals("ANY")) return new Ports(0, 65535, true);
        String[] parts = text.split("-");
        int first = Integer.parseInt(parts[0]), last = Integer.parseInt(parts[parts.length - 1]);
        if (first > 65535 || last > 65535 || first > last) error("bad port range " + text);
        return new Ports(first, last, false);
    }

    static Route select(long address) {
        Route best = null;
        for (Route route : routes) if (route.output.up && route.prefix.contains(address) && (best == null || route.prefix.length() > best.prefix.length() || route.prefix.length() == best.prefix.length() && route.metric < best.metric)) best = route;
        return best;
    }

    static String acl(Iface iface, int direction, Tuple tuple, long source, int sport, long destination, int dport, boolean established) {
        var rules = iface.acl.get(direction);
        if (rules.isEmpty()) return null;
        String dir = direction == 0 ? "in" : "out";
        for (Rule rule : rules.values()) {
            if (!(rule.proto.equals("ANY") || rule.proto.equals(tuple.proto())) || !rule.source.contains(source) || !rule.destination.contains(destination) || rule.established && !established) continue;
            if ((rule.proto.equals("TCP") || rule.proto.equals("UDP")) && (!rule.sports.contains(sport) || !rule.dports.contains(dport))) continue;
            rule.hits++;
            if (rule.action.equals("PERMIT")) return null;
            return (rule.action.equals("DENY") ? "DROP" : "REJECT") + " acl " + iface.name + " " + dir + " " + rule.sequence + (rule.action.equals("REJECT") ? tuple.proto().equals("TCP") ? " tcp-reset" : " icmp-prohibited" : "");
        }
        iface.defaults[direction]++;
        return "DROP acl " + iface.name + " " + dir + " default";
    }

    static boolean martian(long value) {
        return (value >>> 24) == 0 || (value >>> 24) == 127 || (value >>> 29) == 7;
    }

    static String drop(Iface input, int reason, String verdict) {
        drops[reason]++;
        input.drop++;
        return verdict;
    }

    static String packet(Iface input, Tuple original, String flags, int ttl) {
        input.rx++;
        if (!input.up) return drop(input, 0, "DROP down");
        if (martian(original.source()) || martian(original.destination()) || localAddress(original.source()) != null) return drop(input, 1, "DROP martian");
        if (!input.rpf.equals("off")) {
            Route reverse = select(original.source());
            if (reverse == null || input.rpf.equals("strict") && reverse.output != input) return drop(input, 2, "DROP rpf");
        }
        boolean pureSyn = original.proto().equals("TCP") && flags.equals("S");
        Connection connection = null;
        String direction = "new";
        for (Connection candidate : connections) {
            if (candidate.orig.equals(original)) {
                connection = candidate;
                direction = "orig";
                break;
            }
            if (candidate.reply.equals(original)) {
                connection = candidate;
                direction = "reply";
                break;
            }
        }
        if (connection != null && connection.state.equals("CLOSED") && pureSyn) {
            connections.remove(connection);
            connection = null;
            direction = "new";
        }
        if (original.proto().equals("TCP") && connection == null && !pureSyn) return drop(input, 3, "DROP invalid");
        String verdict = acl(input, 0, original, original.source(), original.sport(), original.destination(), original.dport(), connection != null);
        if (verdict != null) return drop(input, 4, verdict);
        long destination = original.destination(), source = original.source();
        int dport = original.dport(), sport = original.sport();
        Pat used = null;
        if (input.outside) {
            StaticNat mapping = null;
            for (StaticNat candidate : statics) if (candidate.outside() == destination) {
                mapping = candidate;
                break;
            }
            if (mapping != null) destination = mapping.inside();
            else if (destination == input.prefix.address()) {
                Forward forwarding = null;
                for (Forward candidate : forwards) if (candidate.iface() == input && candidate.proto().equals(original.proto()) && candidate.port() == dport) {
                    forwarding = candidate;
                    break;
                }
                if (forwarding != null) {
                    destination = forwarding.inside();
                    dport = forwarding.inport();
                } else for (Pat candidate : pats) if (candidate.iface == input && candidate.proto.equals(original.proto()) && candidate.port == dport) {
                    used = candidate;
                    destination = candidate.inside;
                    dport = candidate.inport;
                    break;
                }
            }
        }
        Iface target = localAddress(destination);
        if (target != null) {
            local++;
            return "LOCAL " + target.name;
        }
        if (ttl == 1) return drop(input, 5, "DROP ttl");
        Route route = select(destination);
        if (route == null) return drop(input, 6, "DROP noroute");
        Iface output = route.output;
        verdict = acl(output, 1, original, source, sport, destination, dport, connection != null);
        if (verdict != null) return drop(input, 7, verdict);
        if (!input.outside && output.outside) {
            StaticNat mapping = null;
            for (StaticNat candidate : statics) if (candidate.inside() == source) {
                mapping = candidate;
                break;
            }
            if (mapping != null) source = mapping.outside();
            else {
                Forward forwarding = null;
                for (Forward candidate : forwards) if (candidate.iface() == output && candidate.proto().equals(original.proto()) && candidate.inside() == source && candidate.inport() == sport) {
                    forwarding = candidate;
                    break;
                }
                if (forwarding != null) {
                    source = output.prefix.address();
                    sport = forwarding.port();
                } else if (output.pool > 0) {
                    for (Pat candidate : pats) if (candidate.iface == output && candidate.proto.equals(original.proto()) && candidate.inside == source && candidate.inport == sport) {
                        used = candidate;
                        break;
                    }
                    if (used == null) {
                        int port;
                        for (port = 20000; port < 20000 + output.pool; port++) {
                            boolean occupied = false;
                            for (Pat candidate : pats) if (candidate.iface == output && candidate.port == port) occupied = true;
                            for (Forward candidate : forwards) if (candidate.iface() == output && candidate.port() == port) occupied = true;
                            if (!occupied) break;
                        }
                        if (port == 20000 + output.pool) return drop(input, 8, "DROP exhausted");
                        used = new Pat(output, original.proto(), source, sport, port);
                        pats.add(used);
                    }
                    source = output.prefix.address();
                    sport = used.port;
                }
            }
        }
        if (used != null) used.last = clock;
        if (connection == null) {
            connection = new Connection();
            connection.number = ++connectionNumber;
            connection.orig = original;
            connection.reply = new Tuple(original.proto(), destination, dport, source, sport);
            connection.input = input;
            connection.output = output;
            connection.state = original.proto().equals("TCP") ? "SYN_SENT" : "UNREPLIED";
            connections.add(connection);
        }
        if (direction.equals("reply")) connection.replyPackets++;
        else connection.origPackets++;
        connection.last = clock;
        if (!original.proto().equals("TCP")) {
            if (direction.equals("reply")) connection.state = "REPLIED";
        } else if (flags.contains("R")) connection.state = "CLOSED";
        else {
            if (connection.state.equals("SYN_SENT") && direction.equals("reply") && flags.contains("S") && flags.contains("A")) connection.state = "ESTABLISHED";
            if (flags.contains("F") && (connection.state.equals("ESTABLISHED") || connection.state.equals("FIN_WAIT"))) {
                if (direction.equals("reply")) connection.replyFin = true;
                else connection.origFin = true;
                connection.state = connection.origFin && connection.replyFin ? "CLOSED" : "FIN_WAIT";
            }
        }
        output.tx++;
        route.hits++;
        forwarded++;
        return "FORWARD " + output.name + (route.hop == null ? " direct" : " via " + ip(route.hop)) + " ttl=" + (ttl - 1) + (destination != original.destination() || dport != original.dport() ? " dnat=" + ip(destination) + ":" + dport : "") + (source != original.source() || sport != original.sport() ? " snat=" + ip(source) + ":" + sport : "") + " conn=" + connection.number + " " + direction;
    }

    static List<Iface> sortedInterfaces() {
        return interfaces.stream().sorted(Comparator.comparing(i -> i.name)).toList();
    }

    static String aclPrefix(Prefix prefix) {
        return prefix.length() == 0 ? "any" : prefix.toString();
    }

    static void show(String what) {
        switch (what) {
            case "IFACES": System.out.println("show ifaces count=" + interfaces.size());
            for (Iface iface : sortedInterfaces()) System.out.println(iface.name + " " + iface.prefix + " " + (iface.up ? "up" : "down") + " " + (iface.outside ? "outside" : "inside") + " rpf=" + iface.rpf + (iface.pool == 0 ? "" : " pat=" + pats.stream().filter(p -> p.iface == iface).count() + "/" + iface.pool));
            break;
            case "ROUTES": System.out.println("show routes count=" + routes.size());
            routes.stream().sorted(Comparator.comparingLong((Route r) -> r.prefix.address()).thenComparingInt(r -> r.prefix.length()).thenComparingInt(r -> r.metric)).forEach(r -> System.out.println(r + " hits=" + r.hits + (r.output.up ? "" : " inactive")));
            break;
            case "ACL": int count = 0;
            for (Iface iface : interfaces) for (var rules : iface.acl) count += rules.size();
            System.out.println("show acl count=" + count);
            for (Iface iface : sortedInterfaces()) for (int d = 0; d < 2; d++) {
                var rules = iface.acl.get(d);
                if (rules.isEmpty()) continue;
                String dir = d == 0 ? "in" : "out";
                for (Rule rule : rules.values()) System.out.println("acl " + iface.name + " " + dir + " " + rule.sequence + " " + rule.action + " " + rule.proto + " " + aclPrefix(rule.source) + " " + rule.sports + " " + aclPrefix(rule.destination) + " " + rule.dports + (rule.established ? " established" : "") + " hits=" + rule.hits);
                System.out.println("acl " + iface.name + " " + dir + " default DENY hits=" + iface.defaults[d]);
            }
            break;
            case "NAT": System.out.println("show nat static=" + statics.size() + " forward=" + forwards.size() + " pat=" + pats.size());
            statics.stream().sorted(Comparator.comparingLong(StaticNat::inside)).forEach(n -> System.out.println("static " + ip(n.inside()) + " " + ip(n.outside())));
            forwards.stream().sorted(Comparator.comparing((Forward n) -> n.iface().name).thenComparingInt(Forward::port).thenComparing(Forward::proto)).forEach(n -> System.out.println("forward " + n.iface().name + " " + n.proto() + " " + n.port() + " " + ip(n.inside()) + ":" + n.inport()));
            pats.stream().sorted(Comparator.comparing((Pat n) -> n.iface.name).thenComparingInt(n -> n.port)).forEach(n -> System.out.println("pat " + n.iface.name + " " + n.port + " " + n.proto + " " + ip(n.inside) + ":" + n.inport + " idle=" + (clock - n.last)));
            break;
            case "CONNS": System.out.println("show conns count=" + connections.size());
            for (Connection c : connections) System.out.println("conn " + c.number + " " + c.orig.proto() + " " + ip(c.orig.source()) + ":" + c.orig.sport() + " > " + ip(c.orig.destination()) + ":" + c.orig.dport() + " reply " + ip(c.reply.source()) + ":" + c.reply.sport() + " > " + ip(c.reply.destination()) + ":" + c.reply.dport() + " in=" + c.input.name + " out=" + c.output.name + " state=" + c.state + " pkts=" + c.origPackets + "/" + c.replyPackets + " idle=" + (clock - c.last));
            break;
            case "COUNTERS": int dropped = Arrays.stream(drops).sum();
            System.out.println("show counters packets=" + (forwarded + local + dropped) + " forwarded=" + forwarded + " local=" + local + " dropped=" + dropped + " errors=" + errors);
            StringBuilder line = new StringBuilder("drops");
            for (int i = 0; i < REASONS.length; i++) line.append(" ").append(REASONS[i]).append("=").append(drops[i]);
            System.out.println(line);
            for (Iface iface : sortedInterfaces()) System.out.println("iface " + iface.name + " rx=" + iface.rx + " tx=" + iface.tx + " drop=" + iface.drop);
        }
    }

    static void execute(String[] a) {
        switch (a[0]) {
            case "IFACE": {
                for (Iface iface : interfaces) if (iface.name.equals(a[1])) error("duplicate interface " + a[1]);
                Prefix p = parsePrefix(a[2]);
                if (p == null || p.length() < 8 || p.length() > 30) error("bad prefix " + a[2]);
                long host = p.address() & (0xffffffffL ^ mask(p.length()));
                if (host == 0 || host == (0xffffffffL ^ mask(p.length()))) error("bad host address " + a[2]);
                for (Iface iface : interfaces) if ((p.address() & mask(Math.min(p.length(), iface.prefix.length()))) == (iface.prefix.address() & mask(Math.min(p.length(), iface.prefix.length())))) error("subnet overlaps " + iface.name);
                Iface iface = new Iface(a[1], p);
                interfaces.add(iface);
                routes.add(new Route('C', new Prefix(p.network(), p.length()), iface, null, 0));
                System.out.println("ok iface " + a[1] + " " + a[2] + " network " + ip(p.network()) + "/" + p.length());
                break;
            }
            case "UP": case "DOWN": {
                Iface iface = iface(a[1]);
                boolean up = a[0].equals("UP");
                if (iface.up == up) error("interface " + a[1] + " already " + (up ? "up" : "down"));
                iface.up = up;
                System.out.println("ok " + a[0].toLowerCase(Locale.ROOT) + " " + a[1]);
                break;
            }
            case "ROUTE": {
                Prefix p = prefix(a[1], false);
                boolean via = a[2].equals("VIA");
                Long hop = via ? address(a[3]) : null;
                Iface output = via ? null : iface(a[3]);
                int metric = range(a[4], 1, 255, "bad metric");
                if (via) {
                    if (localAddress(hop) != null) error("nexthop " + a[3] + " is local");
                    for (Iface iface : interfaces) if (iface.prefix.contains(hop)) {
                        output = iface;
                        break;
                    }
                    if (output == null) error("nexthop " + a[3] + " unreachable");
                }
                for (Route route : routes) if (route.type == 'S' && route.prefix.equals(p) && route.output == output && Objects.equals(route.hop, hop)) error("duplicate route " + a[1]);
                Route route = new Route('S', p, output, hop, metric);
                routes.add(route);
                System.out.println("ok route " + route);
                break;
            }
            case "NOROUTE": {
                Prefix p = prefix(a[1], false);
                int old = routes.size();
                boolean exists = routes.stream().anyMatch(r -> r.type == 'S' && r.prefix.equals(p));
                if (!exists) error("no static route " + a[1]);
                routes.removeIf(r -> r.type == 'S' && r.prefix.equals(p));
                System.out.println("ok noroute " + a[1] + " removed=" + (old - routes.size()));
                break;
            }
            case "LOOKUP": {
                Route route = select(address(a[1]));
                System.out.println("lookup " + a[1] + " " + (route == null ? "none" : route));
                break;
            }
            case "ACL": {
                Iface iface = iface(a[1]);
                int d = a[2].equals("IN") ? 0 : 1;
                Rule rule = new Rule();
                rule.sequence = range(a[3], 1, 9999, "bad sequence");
                rule.action = a[4];
                rule.proto = a[5];
                rule.source = prefix(a[6], true);
                rule.sports = ports(a[7]);
                rule.destination = prefix(a[8], true);
                rule.dports = ports(a[9]);
                if ((a[5].equals("ICMP") || a[5].equals("ANY")) && (!a[7].equals("ANY") || !a[9].equals("ANY"))) error("ports not allowed for " + a[5]);
                if (iface.acl.get(d).containsKey(rule.sequence)) error("duplicate sequence " + a[3]);
                rule.established = a.length == 11;
                iface.acl.get(d).put(rule.sequence, rule);
                System.out.println("ok acl " + a[1] + " " + a[2].toLowerCase(Locale.ROOT) + " " + a[3]);
                break;
            }
            case "NOACL": {
                Iface iface = iface(a[1]);
                int d = a[2].equals("IN") ? 0 : 1;
                Rule rule = iface.acl.get(d).get(Integer.parseInt(a[3]));
                if (rule == null) error("no rule " + a[3] + " on " + a[1] + " " + a[2].toLowerCase(Locale.ROOT));
                iface.acl.get(d).remove(rule.sequence);
                System.out.println("ok noacl " + a[1] + " " + a[2].toLowerCase(Locale.ROOT) + " " + a[3] + " hits=" + rule.hits);
                break;
            }
            case "NAT": {
                if (a[1].equals("STATIC")) {
                    long inside = address(a[2]), outside = address(a[3]);
                    if (localAddress(inside) != null) error("address " + a[2] + " is local");
                    if (localAddress(outside) != null) error("address " + a[3] + " is local");
                    for (StaticNat n : statics) if (n.inside() == inside) error("duplicate static " + a[2]);
                    for (StaticNat n : statics) if (n.outside() == outside) error("duplicate static " + a[3]);
                    statics.add(new StaticNat(inside, outside));
                    System.out.println("ok nat static " + a[2] + " " + a[3]);
                } else {
                    Iface iface = iface(a[2]);
                    if (a[1].equals("OUTSIDE")) {
                        if (iface.outside) error("interface " + a[2] + " already outside");
                        iface.outside = true;
                        System.out.println("ok nat outside " + a[2]);
                    } else if (a[1].equals("PAT")) {
                        int pool = range(a[3], 1, 1000, "bad pool size");
                        if (iface.pool > 0) error("pat already on " + a[2]);
                        iface.pool = pool;
                        iface.outside = true;
                        System.out.println("ok nat pat " + a[2] + " " + ip(iface.prefix.address()) + " 20000-" + (19999 + pool));
                    } else {
                        int port = range(a[4], 1, 65535, "bad port");
                        long inside = address(a[5]);
                        int inport = range(a[6], 1, 65535, "bad port");
                        if (!iface.outside) error("interface " + a[2] + " not outside");
                        if (localAddress(inside) != null) error("address " + a[5] + " is local");
                        for (Forward f : forwards) if (f.iface() == iface && f.proto().equals(a[3]) && f.port() == port) error("duplicate forward " + a[2] + " " + a[3] + " " + a[4]);
                        forwards.add(new Forward(iface, a[3], port, inside, inport));
                        System.out.println("ok nat forward " + a[2] + " " + a[3] + " " + a[4] + " " + a[5] + ":" + a[6]);
                    }
                }
                break;
            }
            case "RPF": {
                Iface iface = iface(a[1]);
                iface.rpf = a[2].toLowerCase(Locale.ROOT);
                System.out.println("ok rpf " + a[1] + " " + iface.rpf);
                break;
            }
            case "TIMEOUT": {
                int seconds = range(a[2], 1, 86400, "bad timeout");
                timeouts.put(a[1], seconds);
                System.out.println("ok timeout " + a[1] + " " + a[2]);
                break;
            }
            case "TICK": {
                clock += range(a[1], 1, 86400, "bad tick");
                int c = connections.size(), n = pats.size();
                connections.removeIf(x -> clock - x.last >= (x.orig.proto().equals("TCP") ? switch (x.state) {
                    case "SYN_SENT", "FIN_WAIT" -> 60; case "CLOSED" -> 10; default -> timeouts.get("TCP");
                }
                : timeouts.get(x.orig.proto())));
                pats.removeIf(x -> clock - x.last >= timeouts.get(x.proto));
                System.out.println("ok tick time=" + clock + " expired conns=" + (c - connections.size()) + " nat=" + (n - pats.size()));
                break;
            }
            case "PACKET": {
                Iface iface = iface(a[1]);
                if (!a[2].equals("TCP") && !a[3].equals("-")) error("flags not allowed for " + a[2]);
                if (a[2].equals("TCP") && !a[3].equals("-")) {
                    Set<Character> seen = new HashSet<>();
                    for (char c : a[3].toCharArray()) if ("SAFR".indexOf(c) < 0 || !seen.add(c)) error("bad flags " + a[3]);
                }
                long source = address(a[4]);
                int sport = range(a[5], 0, 65535, "bad port");
                long destination = address(a[6]);
                int dport = range(a[7], 0, 65535, "bad port"), ttl = range(a[8], 1, 255, "bad ttl");
                packetNumber++;
                String verdict = packet(iface, new Tuple(a[2], source, sport, destination, dport), a[3], ttl);
                System.out.println("#" + packetNumber + " " + a[2] + " " + a[3] + " " + a[4] + ":" + a[5] + " > " + a[6] + ":" + a[7] + " " + verdict);
                break;
            }
            case "SHOW": show(a[1]);
            break;
            case "CLEAR": if (a[1].equals("CONNS")) {
                System.out.println("ok clear conns=" + connections.size() + " nat=" + pats.size());
                connections.clear();
                pats.clear();
            } else {
                forwarded = local = errors = 0;
                Arrays.fill(drops, 0);
                for (Iface iface : interfaces) {
                    iface.rx = iface.tx = iface.drop = 0;
                    Arrays.fill(iface.defaults, 0);
                    for (var rules : iface.acl) for (Rule rule : rules.values()) rule.hits = 0;
                }
                for (Route route : routes) route.hits = 0;
                System.out.println("ok clear counters");
            }
        }
    }

    public static void main(String[] args) throws IOException {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
        int commands = Integer.parseInt(input.readLine());
        for (int i = 0; i < commands; i++) try {
            execute(input.readLine().split(" "));
        } catch (CommandError ex) {
            errors++;
            System.out.println("error: " + ex.getMessage());
        }
    }
}
