using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

public sealed class Flows {
    static int CompareLong(long a, long b) => a.CompareTo(b);
    static long[] GetCounts(Dictionary<long, long[]> counts, long address) {
        if (!counts.TryGetValue(address, out long[] row)) {
            row = new long[4];
            counts[address] = row;
        }
        return row;
    }
    public static readonly string[] MARKS = { "retransmission", "out_of_order", "lost_segment",
                                              "duplicate_ack" };
    public sealed record Endpoint(long address, long port) {
        public override string ToString() {
            return LinkNetwork.Ipv4(address) + (port < 0 ? "" : ":" + port);
        }
    }
    public sealed class Previous {
        public long ack, window;
        public int number, count;
        public Previous(long ack, long window, int number) {
            this.ack = ack;
            this.window = window;
            this.number = number;
        }
    }
    public sealed class Side {
        public string name;
        public long isn = -1, mss = -1, ws = -1, sequenceBase = -1, expected = -1, advanced, packets, payload;
        public HashSet<string> intervals = new();
        public Previous previous;
        public long[] marks = new long[4];
        public Side(string name) {
            this.name = name;
        }
    }
    public sealed class Stream {
        public int number, syn = -1, synAck = -1, ack = -1;
        public Endpoint client, server;
        public string state;
        public Side clientSide = new Side("client"), serverSide = new Side("server"), closer;
        public long start, end, packets, bytes, finalAck;
        public List<string> history = new(), events = new();
        public Stream(int number, Endpoint client, Endpoint server, string state, Program.Packet p) {
            this.number = number;
            this.client = client;
            this.server = server;
            this.state = state;
            start = p.time;
            Change(state, p.number);
        }
        public void Change(string state, int number) {
            this.state = state;
            history.Add(state + " " + number);
        }
        public void Record(Side side, Program.Packet p) {
            side.isn = p.Num("tcp.seq_raw");
            side.mss = p.Has("tcp.options.mss") ? p.Num("tcp.options.mss") : -1;
            side.ws = p.Has("tcp.options.wscale") ? p.Num("tcp.options.wscale") : -1;
            if (side == clientSide)
                syn = p.number;
            else
                synAck = p.number;
        }
    }
    public readonly List<Stream> streams = new();
    public void Track(Program.Packet p) {
        Endpoint source = new Endpoint(p.Num("ip.src"), p.Num("tcp.srcport")),
                 destination = new Endpoint(p.Num("ip.dst"), p.Num("tcp.dstport"));
        bool syn = p.Num("tcp.flags.syn") == 1, ackSet = p.Num("tcp.flags.ack") == 1,
             fin = p.Num("tcp.flags.fin") == 1, rst = p.Num("tcp.flags.rst") == 1;
        long seq = p.Num("tcp.seq_raw"), ack = ackSet ? p.Num("tcp.ack_raw") : 0;
        Stream stream = null;
        for (int i = streams.Count - 1; i >= 0; i--) {
            Stream candidate = streams[i];
            if ((candidate.client.Equals(source) && candidate.server.Equals(destination)) ||
                (candidate.client.Equals(destination) && candidate.server.Equals(source))) {
                stream = candidate;
                break;
            }
        }
        if (stream == null ||
            ((stream.state.Equals("CLOSED") || stream.state.Equals("RESET")) && syn && !ackSet)) {
            stream = new Stream(streams.Count, syn && ackSet ? destination : source,
                                syn && ackSet ? source : destination,
                                syn ? (ackSet ? "SYN_RECEIVED" : "SYN_SENT") : "ESTABLISHED", p);
            if (syn)
                stream.Record(ackSet ? stream.serverSide : stream.clientSide, p);
            streams.Add(stream);
        }
        p["tcp.stream"] = stream.number;
        Side side = source.Equals(stream.client) ? stream.clientSide : stream.serverSide,
             other = side == stream.clientSide ? stream.serverSide : stream.clientSide;
        if (side.sequenceBase < 0)
            side.sequenceBase = seq;
        if (ackSet && other.sequenceBase < 0)
            other.sequenceBase = ack;
        long relative = (seq - side.sequenceBase + 4294967296L) % 4294967296L;
        p["tcp.seq"] = relative;
        if (ackSet)
            p["tcp.ack"] = (ack - other.sequenceBase + 4294967296L) % 4294967296L;
        long size = p.Num("tcp.len") + (syn ? 1 : 0) + (fin ? 1 : 0);
        int mark = -1;
        if (size >= 1) {
            if (side.expected >= 0 && relative != side.expected) {
                if (relative > side.expected)
                    mark = 2;
                else if (side.intervals.Contains(relative + ":" + size))
                    mark = 0;
                else
                    mark = p.time - side.advanced < 3000 ? 1 : 0;
            }
            side.intervals.Add(relative + ":" + size);
            if (side.expected < 0 || relative + size > side.expected) {
                side.expected = relative + size;
                side.advanced = p.time;
            }
        } else if (ackSet && !rst && side.previous != null && ack == side.previous.ack &&
                   p.Num("tcp.window") == side.previous.window) {
            mark = 3;
            side.previous.count++;
            p.duplicate = "[TCP Dup ACK " + side.previous.number + "#" + side.previous.count + "] ";
        }
        if (ackSet && mark != 3)
            side.previous = new Previous(ack, p.Num("tcp.window"), p.number);
        if (mark >= 0) {
            p["tcp.analysis." + MARKS[mark]] = 0;
            side.marks[mark]++;
            stream.events.Add("event " + p.number + " " + side.name + " " + MARKS[mark] + " seq " + relative +
                              " len " + size);
        }
        p["tcp.window.calc"] =
            p.Num("tcp.window") *
            (stream.clientSide.ws >= 0 && stream.serverSide.ws >= 0 && !syn ? 1L << (int)side.ws : 1);
        if (rst) {
            if (!stream.state.Equals("CLOSED") && !stream.state.Equals("RESET"))
                stream.Change("RESET", p.number);
        } else if (stream.state.Equals("SYN_SENT") && side == stream.serverSide && syn && ackSet &&
                   ack == (stream.clientSide.isn + 1) % 4294967296L) {
            stream.Change("SYN_RECEIVED", p.number);
            stream.Record(side, p);
        } else if (stream.state.Equals("SYN_RECEIVED") && side == stream.clientSide && ackSet && !syn &&
                   ack == (stream.serverSide.isn + 1) % 4294967296L) {
            stream.Change("ESTABLISHED", p.number);
            stream.ack = p.number;
        } else if (stream.state.Equals("ESTABLISHED") && fin) {
            stream.Change("FIN_WAIT", p.number);
            stream.closer = side;
        } else if (stream.state.Equals("FIN_WAIT") && fin && side != stream.closer) {
            stream.Change("CLOSING", p.number);
            stream.finalAck = (seq + p.Num("tcp.len") + 1) % 4294967296L;
        } else if (stream.state.Equals("CLOSING") && side == stream.closer && ackSet &&
                   ack == stream.finalAck)
            stream.Change("CLOSED", p.number);
        side.packets++;
        side.payload += p.Num("tcp.len");
        stream.packets++;
        stream.bytes += p.length;
        stream.end = p.time;
    }
    public sealed class Conversation {
        public string kind;
        public Endpoint a, b;
        public int first;
        public long start, end;
        public long[] packets = new long[2], bytes = new long[2];
        public Conversation(string kind, Endpoint a, Endpoint b, Program.Packet p) {
            this.kind = kind;
            this.a = a;
            this.b = b;
            first = p.number;
            start = p.time;
        }
        public long TotalBytes() {
            return bytes[0] + bytes[1];
        }
        public long TotalPackets() {
            return packets[0] + packets[1];
        }
    }
    public static List<string> Conversations(List<Program.Packet> packets) {
        Dictionary<string, Conversation> grouped = new();
        foreach (Program.Packet p in packets)
            foreach (string kind in new string[] { "ipv4", "tcp", "udp" }) {
                if (!p.Has(kind.Equals("ipv4")  ? "ip.src"
                           : kind.Equals("tcp") ? "tcp.stream"
                                                : "udp.srcport"))
                    continue;
                Endpoint source = new Endpoint(p.Num("ip.src"),
                                               kind.Equals("ipv4") ? -1 : p.Num(kind + ".srcport")),
                         destination = new Endpoint(p.Num("ip.dst"),
                                                    kind.Equals("ipv4") ? -1 : p.Num(kind + ".dstport"));
                string first = source.ToString(), second = destination.ToString();
                string key = kind + ":" +
                             (kind.Equals("tcp") ? p.Num("tcp.stream").ToString(CultureInfo.InvariantCulture)
                              : string.CompareOrdinal(first, second) < 0 ? first + ":" + second
                                                                         : second + ":" + first);
                Conversation c = grouped.GetValueOrDefault(key);
                if (c == null) {
                    c = new Conversation(kind, source, destination, p);
                    grouped[key] = c;
                }
                int direction = source.Equals(c.a) ? 0 : 1;
                c.packets[direction]++;
                c.bytes[direction] += p.length;
                c.end = p.time;
            }
        List<Conversation> ordered = new(grouped.Values);
        ordered.Sort((a, b) =>
                         a.TotalBytes() != b.TotalBytes()       ? b.TotalBytes().CompareTo(a.TotalBytes())
                         : a.TotalPackets() != b.TotalPackets() ? b.TotalPackets().CompareTo(a.TotalPackets())
                         : a.kind != b.kind
                             ? Array.IndexOf(new string[] { "ipv4", "tcp", "udp" }, a.kind)
                                   .CompareTo(Array.IndexOf(new string[] { "ipv4", "tcp", "udp" }, b.kind))
                             : a.first.CompareTo(b.first));
        List<string> output = new();
        output.Add(
            "type,endpoint_a,endpoint_b,packets,bytes,packets_a_to_b,bytes_a_to_b,packets_b_to_a,bytes_b_to_a,start,duration");
        long origin = packets[0].time;
        foreach (Conversation c in ordered)
            output.Add(c.kind + "," + c.a + "," + c.b + "," + c.TotalPackets() + "," + c.TotalBytes() + "," +
                       c.packets[0] + "," + c.bytes[0] + "," + c.packets[1] + "," + c.bytes[1] + "," +
                       Program.Seconds(c.start - origin) + "," + Program.Seconds(c.end - c.start));
        return output;
    }
    public static List<string> Endpoints(List<Program.Packet> packets) {
        Dictionary<long, long[]> counts = new();
        foreach (Program.Packet p in packets)
            if (p.Has("ip.src"))
                for (int side = 0; side < 2; side++) {
                    long address = p.Num(side == 0 ? "ip.src" : "ip.dst");
                    long[] row = GetCounts(counts, address);
                    row[side * 2]++;
                    row[side * 2 + 1] += p.length;
                }
        List<long> ordered = new(counts.Keys);
        ordered.Sort((a, b) => {
            long[] x = counts[a], y = counts[b];
            int c = CompareLong(y[1] + y[3], x[1] + x[3]);
            if (c == 0)
                c = CompareLong(y[0] + y[2], x[0] + x[2]);
            return c != 0 ? c : CompareLong(a, b);
        });
        List<string> output = new();
        output.Add("address,packets,bytes,tx_packets,tx_bytes,rx_packets,rx_bytes");
        foreach (long address in ordered) {
            long[] row = counts[address];
            output.Add(LinkNetwork.Ipv4(address) + "," + (row[0] + row[2]) + "," + (row[1] + row[3]) + "," +
                       row[0] + "," + row[1] + "," + row[2] + "," + row[3]);
        }
        return output;
    }
}
