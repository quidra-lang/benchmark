import java.util.*;
final class Flows {
    static final String[] MARKS = {"retransmission", "out_of_order", "lost_segment", "duplicate_ack"};
    record Endpoint(long address, long port) {
        public String toString() {
            return LinkNetwork.ipv4(address) + (port < 0 ? "" : ":" + port);
        }
    }
    static final class Previous {
        long ack, window;
        int number, count;
        Previous(long ack, long window, int number) {
            this.ack = ack;
            this.window = window;
            this.number = number;
        }
    }
    static final class Side {
        String name;
        long isn = -1, mss = -1, ws = -1, base = -1, expected = -1, advanced, packets, payload;
        Set<String> intervals = new HashSet<>();
        Previous previous;
        long[] marks = new long[4];
        Side(String name) {
            this.name = name;
        }
    }
    static final class Stream {
        int number, syn = -1, synAck = -1, ack = -1;
        Endpoint client, server;
        String state;
        Side clientSide = new Side("client"), serverSide = new Side("server"), closer;
        long start, end, packets, bytes, finalAck;
        List<String> history = new ArrayList<>(), events = new ArrayList<>();
        Stream(int number, Endpoint client, Endpoint server, String state, Main.Packet p) {
            this.number = number;
            this.client = client;
            this.server = server;
            this.state = state;
            start = p.time;
            change(state, p.number);
        }
        void change(String state, int number) {
            this.state = state;
            history.add(state + " " + number);
        }
        void record(Side side, Main.Packet p) {
            side.isn = p.num("tcp.seq_raw");
            side.mss = p.has("tcp.options.mss") ? p.num("tcp.options.mss") : -1;
            side.ws = p.has("tcp.options.wscale") ? p.num("tcp.options.wscale") : -1;
            if (side == clientSide)
                syn = p.number;
            else
                synAck = p.number;
        }
    }
    final List<Stream> streams = new ArrayList<>();
    void track(Main.Packet p) {
        Endpoint source = new Endpoint(p.num("ip.src"), p.num("tcp.srcport")),
                 destination = new Endpoint(p.num("ip.dst"), p.num("tcp.dstport"));
        boolean syn = p.num("tcp.flags.syn") == 1, ackSet = p.num("tcp.flags.ack") == 1,
                fin = p.num("tcp.flags.fin") == 1, rst = p.num("tcp.flags.rst") == 1;
        long seq = p.num("tcp.seq_raw"), ack = ackSet ? p.num("tcp.ack_raw") : 0;
        Stream stream = null;
        for (int i = streams.size() - 1; i >= 0; i--) {
            Stream candidate = streams.get(i);
            if ((candidate.client.equals(source) && candidate.server.equals(destination)) ||
                (candidate.client.equals(destination) && candidate.server.equals(source))) {
                stream = candidate;
                break;
            }
        }
        if (stream == null ||
            ((stream.state.equals("CLOSED") || stream.state.equals("RESET")) && syn && !ackSet)) {
            stream = new Stream(streams.size(), syn && ackSet ? destination : source,
                                syn && ackSet ? source : destination,
                                syn ? (ackSet ? "SYN_RECEIVED" : "SYN_SENT") : "ESTABLISHED", p);
            if (syn)
                stream.record(ackSet ? stream.serverSide : stream.clientSide, p);
            streams.add(stream);
        }
        p.put("tcp.stream", stream.number);
        Side side = source.equals(stream.client) ? stream.clientSide : stream.serverSide,
             other = side == stream.clientSide ? stream.serverSide : stream.clientSide;
        if (side.base < 0)
            side.base = seq;
        if (ackSet && other.base < 0)
            other.base = ack;
        long relative = (seq - side.base + 4294967296L) % 4294967296L;
        p.put("tcp.seq", relative);
        if (ackSet)
            p.put("tcp.ack", (ack - other.base + 4294967296L) % 4294967296L);
        long size = p.num("tcp.len") + (syn ? 1 : 0) + (fin ? 1 : 0);
        int mark = -1;
        if (size >= 1) {
            if (side.expected >= 0 && relative != side.expected) {
                if (relative > side.expected)
                    mark = 2;
                else if (side.intervals.contains(relative + ":" + size))
                    mark = 0;
                else
                    mark = p.time - side.advanced < 3000 ? 1 : 0;
            }
            side.intervals.add(relative + ":" + size);
            if (side.expected < 0 || relative + size > side.expected) {
                side.expected = relative + size;
                side.advanced = p.time;
            }
        } else if (ackSet && !rst && side.previous != null && ack == side.previous.ack &&
                   p.num("tcp.window") == side.previous.window) {
            mark = 3;
            side.previous.count++;
            p.duplicate = "[TCP Dup ACK " + side.previous.number + "#" + side.previous.count + "] ";
        }
        if (ackSet && mark != 3)
            side.previous = new Previous(ack, p.num("tcp.window"), p.number);
        if (mark >= 0) {
            p.put("tcp.analysis." + MARKS[mark], 0);
            side.marks[mark]++;
            stream.events.add("event " + p.number + " " + side.name + " " + MARKS[mark] + " seq " + relative +
                              " len " + size);
        }
        p.put("tcp.window.calc",
              p.num("tcp.window") *
                  (stream.clientSide.ws >= 0 && stream.serverSide.ws >= 0 && !syn ? 1L << (int)side.ws : 1));
        if (rst) {
            if (!stream.state.equals("CLOSED") && !stream.state.equals("RESET"))
                stream.change("RESET", p.number);
        } else if (stream.state.equals("SYN_SENT") && side == stream.serverSide && syn && ackSet &&
                   ack == (stream.clientSide.isn + 1) % 4294967296L) {
            stream.change("SYN_RECEIVED", p.number);
            stream.record(side, p);
        } else if (stream.state.equals("SYN_RECEIVED") && side == stream.clientSide && ackSet && !syn &&
                   ack == (stream.serverSide.isn + 1) % 4294967296L) {
            stream.change("ESTABLISHED", p.number);
            stream.ack = p.number;
        } else if (stream.state.equals("ESTABLISHED") && fin) {
            stream.change("FIN_WAIT", p.number);
            stream.closer = side;
        } else if (stream.state.equals("FIN_WAIT") && fin && side != stream.closer) {
            stream.change("CLOSING", p.number);
            stream.finalAck = (seq + p.num("tcp.len") + 1) % 4294967296L;
        } else if (stream.state.equals("CLOSING") && side == stream.closer && ackSet &&
                   ack == stream.finalAck)
            stream.change("CLOSED", p.number);
        side.packets++;
        side.payload += p.num("tcp.len");
        stream.packets++;
        stream.bytes += p.length;
        stream.end = p.time;
    }
    static final class Conversation {
        String kind;
        Endpoint a, b;
        int first;
        long start, end;
        long[] packets = new long[2], bytes = new long[2];
        Conversation(String kind, Endpoint a, Endpoint b, Main.Packet p) {
            this.kind = kind;
            this.a = a;
            this.b = b;
            first = p.number;
            start = p.time;
        }
        long totalBytes() {
            return bytes[0] + bytes[1];
        }
        long totalPackets() {
            return packets[0] + packets[1];
        }
    }
    static List<String> conversations(List<Main.Packet> packets) {
        Map<String, Conversation> grouped = new HashMap<>();
        for (Main.Packet p : packets)
            for (String kind : List.of("ipv4", "tcp", "udp")) {
                if (!p.has(kind.equals("ipv4")  ? "ip.src"
                           : kind.equals("tcp") ? "tcp.stream"
                                                : "udp.srcport"))
                    continue;
                Endpoint source = new Endpoint(p.num("ip.src"),
                                               kind.equals("ipv4") ? -1 : p.num(kind + ".srcport")),
                         destination = new Endpoint(p.num("ip.dst"),
                                                    kind.equals("ipv4") ? -1 : p.num(kind + ".dstport"));
                String first = source.toString(), second = destination.toString();
                String key = kind + ":" +
                             (kind.equals("tcp")            ? p.num("tcp.stream")
                              : first.compareTo(second) < 0 ? first + ":" + second
                                                            : second + ":" + first);
                Conversation c = grouped.get(key);
                if (c == null) {
                    c = new Conversation(kind, source, destination, p);
                    grouped.put(key, c);
                }
                int direction = source.equals(c.a) ? 0 : 1;
                c.packets[direction]++;
                c.bytes[direction] += p.length;
                c.end = p.time;
            }
        List<Conversation> ordered = new ArrayList<>(grouped.values());
        ordered.sort(Comparator.comparingLong(Conversation::totalBytes)
                         .reversed()
                         .thenComparing(Comparator.comparingLong(Conversation::totalPackets).reversed())
                         .thenComparingInt(c -> List.of("ipv4", "tcp", "udp").indexOf(c.kind))
                         .thenComparingInt(c -> c.first));
        List<String> output = new ArrayList<>();
        output.add(
            "type,endpoint_a,endpoint_b,packets,bytes,packets_a_to_b,bytes_a_to_b,packets_b_to_a,bytes_b_to_a,start,duration");
        long origin = packets.getFirst().time;
        for (Conversation c : ordered)
            output.add(c.kind + "," + c.a + "," + c.b + "," + c.totalPackets() + "," + c.totalBytes() + "," +
                       c.packets[0] + "," + c.bytes[0] + "," + c.packets[1] + "," + c.bytes[1] + "," +
                       Main.seconds(c.start - origin) + "," + Main.seconds(c.end - c.start));
        return output;
    }
    static List<String> endpoints(List<Main.Packet> packets) {
        Map<Long, long[]> counts = new HashMap<>();
        for (Main.Packet p : packets)
            if (p.has("ip.src"))
                for (int side = 0; side < 2; side++) {
                    long address = p.num(side == 0 ? "ip.src" : "ip.dst");
                    long[] row = counts.computeIfAbsent(address, key -> new long[4]);
                    row[side * 2]++;
                    row[side * 2 + 1] += p.length;
                }
        List<Long> ordered = new ArrayList<>(counts.keySet());
        ordered.sort((a, b) -> {
            long[] x = counts.get(a), y = counts.get(b);
            int c = Long.compare(y[1] + y[3], x[1] + x[3]);
            if (c == 0)
                c = Long.compare(y[0] + y[2], x[0] + x[2]);
            return c != 0 ? c : Long.compare(a, b);
        });
        List<String> output = new ArrayList<>();
        output.add("address,packets,bytes,tx_packets,tx_bytes,rx_packets,rx_bytes");
        for (long address : ordered) {
            long[] row = counts.get(address);
            output.add(LinkNetwork.ipv4(address) + "," + (row[0] + row[2]) + "," + (row[1] + row[3]) + "," +
                       row[0] + "," + row[1] + "," + row[2] + "," + row[3]);
        }
        return output;
    }
}
