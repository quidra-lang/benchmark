using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

public static class Program {
    static int CompareLong(long a, long b) => a.CompareTo(b);
    public sealed class Packet {
        public object this[string name] {
            set {
                fields[name] = [value is int number ? (long)number : value];
            }
        }
        public void AppendValue(string name, object value) {
            if (!fields.TryGetValue(name, out List<object> list)) {
                list = new();
                fields[name] = list;
            }
            list.Add(value);
        }
        public int number, length;
        public long time;
        public int[] bytes = new int[0], data = new int[0];
        public string reason, duplicate = "";
        public List<string> layers = new(), answers = new();
        public Dictionary<string, List<object>> fields = new();
        public Packet(int number, long time, int length) {
            this.number = number;
            this.time = time;
            this.length = length;
        }
        public void Put(string name, long value) {
            fields[name] = new([value]);
        }
        public void Put(string name, string value) {
            fields[name] = new([value]);
        }
        public void Append(string name, long value) {
            AppendValue(name, value);
        }
        public void Append(string name, string value) {
            AppendValue(name, value);
        }
        public bool Has(string name) {
            return fields.ContainsKey(name);
        }
        public long Num(string name) {
            return (long)fields[name][0];
        }
        public string Text(string name) {
            return (string)fields[name][0];
        }
        public List<object> Values(string name) {
            return fields.GetValueOrDefault(name, []);
        }
    }
    static readonly string[][] FIELDS = [
        ["frame.number", "integer"],
        ["frame.time", "integer"],
        ["frame.len", "integer"],
        ["frame.protocols", "string"],
        ["frame.malformed", "string"],
        ["frame.bad_checksum", "presence"],
        ["eth.dst", "mac"],
        ["eth.src", "mac"],
        ["eth.type", "hex4"],
        ["arp.opcode", "integer"],
        ["arp.src.hw", "mac"],
        ["arp.src.ip", "ipv4"],
        ["arp.dst.hw", "mac"],
        ["arp.dst.ip", "ipv4"],
        ["ip.hdr_len", "integer"],
        ["ip.tos", "hex2"],
        ["ip.len", "integer"],
        ["ip.id", "hex4"],
        ["ip.flags.df", "integer"],
        ["ip.flags.mf", "integer"],
        ["ip.frag_offset", "integer"],
        ["ip.ttl", "integer"],
        ["ip.proto", "integer"],
        ["ip.checksum", "hex4"],
        ["ip.checksum.status", "string"],
        ["ip.src", "ipv4"],
        ["ip.dst", "ipv4"],
        ["ip.fragment", "presence"],
        ["icmp.type", "integer"],
        ["icmp.code", "integer"],
        ["icmp.checksum", "hex4"],
        ["icmp.checksum.status", "string"],
        ["icmp.id", "integer"],
        ["icmp.seq", "integer"],
        ["udp.srcport", "integer"],
        ["udp.dstport", "integer"],
        ["udp.length", "integer"],
        ["udp.checksum", "hex4"],
        ["udp.checksum.status", "string"],
        ["tcp.srcport", "integer"],
        ["tcp.dstport", "integer"],
        ["tcp.stream", "integer"],
        ["tcp.seq", "integer"],
        ["tcp.seq_raw", "integer"],
        ["tcp.ack", "integer"],
        ["tcp.ack_raw", "integer"],
        ["tcp.hdr_len", "integer"],
        ["tcp.flags", "hex2"],
        ["tcp.flags.fin", "integer"],
        ["tcp.flags.syn", "integer"],
        ["tcp.flags.rst", "integer"],
        ["tcp.flags.psh", "integer"],
        ["tcp.flags.ack", "integer"],
        ["tcp.flags.urg", "integer"],
        ["tcp.window", "integer"],
        ["tcp.window.calc", "integer"],
        ["tcp.checksum", "hex4"],
        ["tcp.checksum.status", "string"],
        ["tcp.urgent", "integer"],
        ["tcp.option", "string"],
        ["tcp.options.mss", "integer"],
        ["tcp.options.wscale", "integer"],
        ["tcp.options.malformed", "presence"],
        ["tcp.len", "integer"],
        ["tcp.analysis.retransmission", "presence"],
        ["tcp.analysis.out_of_order", "presence"],
        ["tcp.analysis.lost_segment", "presence"],
        ["tcp.analysis.duplicate_ack", "presence"],
        ["dns.id", "hex4"],
        ["dns.flags", "hex4"],
        ["dns.flags.response", "integer"],
        ["dns.flags.opcode", "integer"],
        ["dns.flags.rcode", "integer"],
        ["dns.count.queries", "integer"],
        ["dns.count.answers", "integer"],
        ["dns.count.auth_rr", "integer"],
        ["dns.count.add_rr", "integer"],
        ["dns.qry.name", "string"],
        ["dns.qry.type", "integer"],
        ["dns.answer", "string"],
        ["dns.authority", "string"],
        ["dns.additional", "string"],
        ["dns.a", "ipv4"],
        ["data.len", "integer"]
    ];
    static readonly string[][] ALIASES = [
        ["eth.addr", "mac", "eth.dst", "eth.src"], ["ip.addr", "ipv4", "ip.src", "ip.dst"],
        ["udp.port", "integer", "udp.srcport", "udp.dstport"],
        ["tcp.port", "integer", "tcp.srcport", "tcp.dstport"]
    ];
    public static readonly List<string> PROTOCOLS = ["eth", "arp", "ip", "icmp", "udp", "tcp", "dns", "data"];
    public static readonly string[] FLAGS = { "FIN", "SYN", "RST", "PSH", "ACK", "URG", "ECE", "CWR" };
    public static readonly string[] CHECKSUMS = { "ip", "icmp", "udp", "tcp" },
                                    CHECKSUM_NAMES = { "IPv4", "ICMP", "UDP", "TCP" };
    public static string Type(string name) {
        foreach (string[] row in FIELDS)
            if (row[0].Equals(name))
                return row[1];
        foreach (string[] row in ALIASES)
            if (row[0].Equals(name))
                return row[1];
        return PROTOCOLS.Contains(name) ? "presence" : null;
    }
    public static List<object> Values(Packet p, string name) {
        foreach (string[] row in ALIASES)
            if (row[0].Equals(name)) {
                List<object> result = new(p.Values(row[2]));
                result.AddRange(p.Values(row[3]));
                return result;
            }
        return p.Values(name);
    }
    public static string Notation(string type, object value) {
        if (type.Equals("string"))
            return (string)value;
        long n = (long)value;
        return (type) switch {
            "hex2" => string.Format(CultureInfo.InvariantCulture, "0x{0:x2}", n),
            "hex4" => string.Format(CultureInfo.InvariantCulture, "0x{0:x4}", n),
            "ipv4" => LinkNetwork.Ipv4(n),
            "mac" => LinkNetwork.Mac(n),
            _ => n.ToString(CultureInfo.InvariantCulture),
        };
    }
    public static string Shown(Packet p, string name) {
        return Notation(Type(name), p.Values(name)[0]);
    }
    public static string Seconds(long time) {
        return (time / 1000000) + "." + string.Format(CultureInfo.InvariantCulture, "{0:D6}", time % 1000000);
    }
    public static string Optional(long value) {
        return value < 0 ? "-" : value.ToString(CultureInfo.InvariantCulture);
    }
    public static void Dissect(Packet p, long origin) {
        if (p.reason == null) {
            string layer = "eth";
            int[] payload = p.bytes;
            while (layer != null) {
                p.layers.Add(layer);
                Packet temporary = new Packet(p.number, p.time, p.length);
                temporary.fields = new Dictionary<string, List<object>>(p.fields);
                try {
                    int[] remaining = (layer) switch {
                        "eth" => LinkNetwork.Ethernet(temporary, payload),
                        "arp" => LinkNetwork.Arp(temporary, payload),
                        "ip" => LinkNetwork.Ipv4(temporary, payload),
                        "icmp" => Transport.Icmp(temporary, payload),
                        "udp" => Transport.Udp(temporary, payload),
                        "tcp" => Transport.Tcp(temporary, payload),
                        "dns" => DnsApp.Dissect(temporary, payload),
                        _ => new int[0],
                    };
                    p.fields = temporary.fields;
                    p.answers = temporary.answers;
                    string next = null;
                    if (layer.Equals("eth")) {
                        if (p.Num("eth.type") == 2054)
                            next = "arp";
                        else if (p.Num("eth.type") == 2048)
                            next = "ip";
                    } else if (layer.Equals("ip") && !p.Has("ip.fragment"))
                        next = ((int)p.Num("ip.proto")) switch {
                            1 => "icmp",
                            17 => "udp",
                            6 => "tcp",
                            _ => null,
                        };
                    else if (layer.Equals("udp") &&
                             (p.Num("udp.srcport") == 53 || p.Num("udp.dstport") == 53))
                        next = "dns";
                    payload = remaining;
                    layer = next;
                } catch (LinkNetwork.Bad error) {
                    p.reason = error.Message;
                    payload = new int[0];
                    break;
                }
            }
            if (p.reason == null && payload.Length > 0) {
                p.data = payload;
                p.layers.Add("data");
                p["data.len"] = payload.Length;
            }
        }
        p["frame.number"] = p.number;
        p["frame.time"] = p.time - origin;
        p["frame.len"] = p.length;
        if (p.layers.Count != 0)
            p["frame.protocols"] = string.Join(":", p.layers);
        if (p.reason != null)
            p["frame.malformed"] = p.reason;
        foreach (string layer in CHECKSUMS)
            if (p.Has(layer + ".checksum.status") && p.Text(layer + ".checksum.status").Equals("bad"))
                p["frame.bad_checksum"] = 0;
    }
    public static string Summary(Packet p) {
        string source = "-", destination = "-";
        if (p.Has("ip.src")) {
            source = Shown(p, "ip.src");
            destination = Shown(p, "ip.dst");
        } else if (p.Has("eth.src")) {
            source = Shown(p, "eth.src");
            destination = Shown(p, "eth.dst");
        }
        string last = "dump";
        foreach (string layer in p.layers)
            if (!layer.Equals("data"))
                last = layer;
        string protocol = (last) switch {
            "eth" => "ETH", "arp" => "ARP", "ip" => "IPv4", "icmp" => "ICMP",
            "udp" => "UDP", "tcp" => "TCP", "dns" => "DNS",
            _ => "DUMP",
        };
        string info = p.reason;
        if (info == null) {
            if (last.Equals("eth"))
                info = "EtherType " + Shown(p, "eth.type");
            else if (last.Equals("arp"))
                info = p.Num("arp.opcode") == 1
                           ? "Who has " + Shown(p, "arp.dst.ip") + "? Tell " + Shown(p, "arp.src.ip")
                       : p.Num("arp.opcode") == 2
                           ? Shown(p, "arp.src.ip") + " is at " + Shown(p, "arp.src.hw")
                           : "Opcode " + p.Num("arp.opcode");
            else if (last.Equals("ip"))
                info = p.Has("ip.fragment")
                           ? "Fragment id=" + Shown(p, "ip.id") + " off=" + p.Num("ip.frag_offset") +
                                 (p.Num("ip.flags.mf") == 1 ? " MF" : "")
                           : "Protocol " + p.Num("ip.proto");
            else if (last.Equals("icmp"))
                info = p.Num("icmp.type") == 0 || p.Num("icmp.type") == 8
                           ? (p.Num("icmp.type") == 8 ? "Echo request" : "Echo reply") +
                                 " id=" + p.Num("icmp.id") + " seq=" + p.Num("icmp.seq")
                           : "Type " + p.Num("icmp.type") + " code " + p.Num("icmp.code");
            else if (last.Equals("udp"))
                info = p.Num("udp.srcport") + " -> " + p.Num("udp.dstport") +
                       " Len=" + (p.Num("udp.length") - 8);
            else if (last.Equals("tcp")) {
                string mark = p.duplicate;
                string[] labels = { "[TCP Retransmission] ", "[TCP Out-Of-Order] ",
                                    "[TCP Previous segment not captured] " };
                for (int i = 0; i < 3; i++)
                    if (p.Has("tcp.analysis." + Flows.MARKS[i]))
                        mark = labels[i];
                List<string> flags = new();
                for (int i = 0; i < FLAGS.Length; i++)
                    if ((p.Num("tcp.flags") & (1L << i)) != 0)
                        flags.Add(FLAGS[i]);
                info = mark + p.Num("tcp.srcport") + " -> " + p.Num("tcp.dstport") + " [" +
                       (flags.Count == 0 ? "<None>" : string.Join(", ", flags)) + "] Seq=" + p.Num("tcp.seq");
                if (p.Num("tcp.flags.ack") == 1)
                    info += " Ack=" + p.Num("tcp.ack");
                info += " Win=" + p.Num("tcp.window.calc") + " Len=" + p.Num("tcp.len");
                foreach (object value in p.Values("tcp.option")) {
                    string option = (string)value;
                    string[] parts = option.Split(" ");
                    if (parts[0].Equals("MSS"))
                        info += " MSS=" + parts[1];
                    else if (parts[0].Equals("WS"))
                        info += " WS=" + (1L << int.Parse(parts[1]));
                    else if (option.Equals("SACK_PERM"))
                        info += " SACK_PERM";
                    else if (parts[0].Equals("TS"))
                        info += " TSval=" + parts[1] + " TSecr=" + parts[2];
                }
            } else if (last.Equals("dns")) {
                info = (p.Num("dns.flags.response") == 1 ? "Response" : "Query") + " " + Shown(p, "dns.id");
                if (p.Num("dns.flags.rcode") != 0)
                    info += " " + DnsApp.Rcode(p.Num("dns.flags.rcode"));
                List<object> names = p.Values("dns.qry.name"), types = p.Values("dns.qry.type");
                for (int i = 0; i < names.Count; i++)
                    info += " " + DnsApp.Type((long)types[i]) + " " + names[i];
                foreach (string answer in p.answers)
                    info += " " + answer;
            }
        }
        if (p.Has("tcp.options.malformed"))
            info += " [bad TCP options]";
        for (int i = 0; i < CHECKSUMS.Length; i++)
            if (p.Has(CHECKSUMS[i] + ".checksum.status") &&
                p.Text(CHECKSUMS[i] + ".checksum.status").Equals("bad"))
                info += " [bad " + CHECKSUM_NAMES[i] + " checksum]";
        return p.number + " " + Seconds(p.Num("frame.time")) + " " + source + " -> " + destination + " " +
               protocol + " " + p.length + " " + info;
    }
    public sealed record Token(string kind, string text, int column);
    public sealed class FilterError : Exception {
        public FilterError(string message) : base(message) {
        }
    }
    public static List<Token> Tokenize(string expression) {
        List<Token> tokens = new();
        int i = 0;
        while (i < expression.Length) {
            char c = expression[i];
            int start = i;
            if (c == ' ') {
                i++;
                continue;
            }
            string pair = i + 1 < expression.Length ? expression.Substring(i, 2) : "";
            if (new string[] { "==", "!=", "<=", ">=", "&&", "||" }.Contains(pair)) {
                tokens.Add(new Token(pair, pair, i + 1));
                i += 2;
            } else if ("()!<>".IndexOf(c) >= 0) {
                tokens.Add(new Token(c.ToString(), c.ToString(), i + 1));
                i++;
            } else if (c == '"') {
                int end = expression.IndexOf('"', i + 1);
                if (end < 0)
                    throw new FilterError("unterminated string at column " + (i + 1));
                tokens.Add(new Token("string", expression.Substring(i, end + 1 - i), i + 1));
                i = end + 1;
            } else if (Word(c)) {
                while (i < expression.Length && Word(expression[i]))
                    i++;
                string text = expression.Substring(start, i - start);
                string kind = (text) switch {
                    "and" => "&&",
                    "or" => "||",
                    "not" => "!",
                    _ => "word",
                };
                tokens.Add(new Token(kind, text, start + 1));
            } else
                throw new FilterError("invalid character '" + c + "' at column " + (i + 1));
        }
        return tokens;
    }
    public static bool Word(char c) {
        return c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || "._:".IndexOf(c) >= 0;
    }
    public static object Convert(Token token, string type) {
        string value = token.text;
        if (type.Equals("string"))
            return token.kind.Equals("string") ? value.Substring(1, value.Length - 2) : null;
        if (!token.kind.Equals("word"))
            return null;
        if (new string[] { "integer", "hex2", "hex4" }.Contains(type)) {
            if (Regex.IsMatch(value, "\\A" + "[0-9]{1,15}" + "\\z"))
                return long.Parse(value);
            if (Regex.IsMatch(value, "\\A" + "0x[0-9a-fA-F]{1,12}" + "\\z"))
                return System.Convert.ToInt64(value.Substring(2), 16);
        } else if (type.Equals("ipv4") || type.Equals("mac")) {
            bool mac = type.Equals("mac");
            string[] parts = value.Split(mac ? ':' : '.');
            if (parts.Length != (mac ? 6 : 4))
                return null;
            long result = 0;
            foreach (string part in parts) {
                if (!Regex.IsMatch(part, "\\A" + (mac ? "[0-9a-fA-F]{2}" : "[0-9]{1,3}") + "\\z"))
                    return null;
                int n = System.Convert.ToInt32(part, mac ? 16 : 10);
                if (n > 255)
                    return null;
                result = result * 256 + n;
            }
            return result;
        }
        return null;
    }
    public sealed class Parser {
        public List<Token> tokens;
        public int position;
        public Parser(string expression) {
            tokens = Tokenize(expression);
        }
        public Token Take() {
            if (position >= tokens.Count)
                throw new FilterError("unexpected end of filter");
            return tokens[position++];
        }
        public bool Next(string kind) {
            return position < tokens.Count && tokens[position].kind.Equals(kind);
        }
        public FilterError Unexpected(Token token) {
            return new FilterError("unexpected '" + token.text + "' at column " + token.column);
        }
        public Func<Packet, bool> Expression() {
            Func<Packet, bool> result = Product();
            while (Next("||")) {
                Take();
                Func<Packet, bool> left = result, right = Product();
                result = p => left(p) || right(p);
            }
            return result;
        }
        public Func<Packet, bool> Product() {
            Func<Packet, bool> result = Negation();
            while (Next("&&")) {
                Take();
                Func<Packet, bool> left = result, right = Negation();
                result = p => left(p) && right(p);
            }
            return result;
        }
        public Func<Packet, bool> Negation() {
            if (Next("!")) {
                Take();
                Func<Packet, bool> child = Negation();
                return p => !child(p);
            }
            Token token = Take();
            if (token.kind.Equals("(")) {
                Func<Packet, bool> result = Expression();
                Token closing = Take();
                if (!closing.kind.Equals(")"))
                    throw Unexpected(closing);
                return result;
            }
            if (!token.kind.Equals("word"))
                throw Unexpected(token);
            string name = token.text, fieldType = Type(name);
            if (fieldType == null)
                throw new FilterError("unknown field " + name);
            if (position >= tokens.Count ||
                !new string[] { "==", "!=", "<", ">", "<=", ">=" }.Contains(tokens[position].kind))
                return p => PROTOCOLS.Contains(name) ? p.layers.Contains(name) : Values(p, name).Count != 0;
            string comparisonOperator = Take().text;
            if (fieldType.Equals("presence") || fieldType.Equals("string") &&
                                                    !comparisonOperator.Equals("==") &&
                                                    !comparisonOperator.Equals("!="))
                throw new FilterError("operator " + comparisonOperator + " not allowed for " + name);
            Token valueToken = Take();
            if (!valueToken.kind.Equals("word") && !valueToken.kind.Equals("string"))
                throw Unexpected(valueToken);
            object target = Convert(valueToken, fieldType);
            if (target == null)
                throw new FilterError("invalid value " + valueToken.text + " for " + name);
            return p => {
                List<object> actual = Values(p, name);
                if (actual.Count == 0)
                    return false;
                foreach (object value in actual) {
                    int comparison = fieldType.Equals("string")
                                         ? string.CompareOrdinal((string)value, (string)target)
                                         : CompareLong((long)value, (long)target);
                    bool matches = (comparisonOperator) switch {
                        "==" => comparison == 0, "!=" => comparison != 0, "<" => comparison < 0,
                        ">" => comparison > 0,   "<=" => comparison <= 0,
                        _ => comparison >= 0,
                    };
                    if (comparisonOperator.Equals("!=")) {
                        if (!matches)
                            return false;
                    } else if (matches)
                        return true;
                }
                return comparisonOperator.Equals("!=");
            };
        }
        public Func<Packet, bool> Parse() {
            Func<Packet, bool> result = Expression();
            if (position < tokens.Count)
                throw Unexpected(tokens[position]);
            return result;
        }
    }
    public static List<string> Details(List<Packet> packets, int number) {
        List<string> output = new();
        if (number < 1 || number > packets.Count) {
            output.Add("packet " + number + " not found");
            return output;
        }
        Packet p = packets[number - 1];
        output.Add("packet " + number);
        List<string> layers = new(["frame"]);
        layers.AddRange(p.layers);
        foreach (string layer in layers) {
            output.Add(layer);
            foreach (string[] field in FIELDS)
                if (field[0].StartsWith(layer + "."))
                    foreach (object value in p.Values(field[0]))
                        output.Add("  " + field[0] +
                                   (field[1].Equals("presence") ? "" : " = " + Notation(field[1], value)));
            if (layer.Equals("data"))
                foreach (string line in Hexdump.Lines(p.data))
                    output.Add("  " + line);
        }
        return output;
    }
    public static List<string> Stats(List<Packet> packets) {
        List<string> output = new();
        long total = 0;
        foreach (Packet p in packets)
            total += p.length;
        output.Add("packets " + packets.Count);
        output.Add("bytes " + total);
        output.Add("duration " + Seconds(packets[^1].time - packets[0].time));
        output.Add("hierarchy");
        string[] hierarchy = { "eth", "  arp", "  ip", "    icmp", "    udp", "      dns", "    tcp" };
        foreach (string item in hierarchy) {
            string layer = item.Trim();
            long count = 0, bytes = 0;
            foreach (Packet p in packets)
                if (p.layers.Contains(layer)) {
                    count++;
                    bytes += p.length;
                }
            output.Add(item + " " + count + " " + bytes);
        }
        output.Add("checksums");
        foreach (string layer in CHECKSUMS) {
            long good = 0, bad = 0, none = 0;
            foreach (Packet p in packets)
                if (p.Has(layer + ".checksum.status")) {
                    string status = p.Text(layer + ".checksum.status");
                    if (status.Equals("good"))
                        good++;
                    else if (status.Equals("bad"))
                        bad++;
                    else
                        none++;
                }
            output.Add(layer + " good " + good + " bad " + bad +
                       (layer.Equals("udp") ? " none " + none : ""));
        }
        output.Add("malformed");
        foreach (string layer in new string[] { "dump", "eth", "arp", "ip", "icmp", "udp", "tcp", "dns" }) {
            long count = 0;
            foreach (Packet p in packets)
                if (p.reason != null && (p.layers.Count == 0 ? "dump" : p.layers[^1]).Equals(layer))
                    count++;
            output.Add(layer + " " + count);
        }
        output.Add("tcp analysis");
        foreach (string mark in Flows.MARKS) {
            long count = 0;
            foreach (Packet p in packets)
                if (p.Has("tcp.analysis." + mark))
                    count++;
            output.Add(mark + " " + count);
        }
        List<Packet> pending = new();
        List<long> responseTimes = new();
        long queries = 0, responses = 0;
        long[] rcodes = new long[16];
        Dictionary<string, int> names = new();
        foreach (Packet p in packets)
            if (p.Has("dns.id")) {
                if (p.Num("dns.flags.response") == 0) {
                    queries++;
                    pending.Add(p);
                    foreach (object value in p.Values("dns.qry.name"))
                        names[(string)value] = names.GetValueOrDefault((string)value) + 1;
                } else {
                    responses++;
                    rcodes[(int)p.Num("dns.flags.rcode")]++;
                    for (int i = 0; i < pending.Count; i++) {
                        Packet q = pending[i];
                        if (q.Num("dns.id") == p.Num("dns.id") && q.Num("ip.src") == p.Num("ip.dst") &&
                            q.Num("ip.dst") == p.Num("ip.src") &&
                            q.Num("udp.srcport") == p.Num("udp.dstport") &&
                            q.Num("udp.dstport") == p.Num("udp.srcport")) {
                            responseTimes.Add(p.time - q.time);
                            pending.RemoveAt(i);
                            break;
                        }
                    }
                }
            }
        output.Add("dns");
        output.Add("queries " + queries);
        output.Add("responses " + responses);
        output.Add("transactions " + responseTimes.Count);
        output.Add("unanswered " + pending.Count);
        output.Add(responseTimes.Count == 0 ? "response_time -"
                                            : "response_time min " + Seconds(responseTimes.Min()) + " max " +
                                                  Seconds(responseTimes.Max()));
        for (int i = 0; i < rcodes.Length; i++)
            if (rcodes[i] > 0)
                output.Add("rcode " + DnsApp.Rcode(i) + " " + rcodes[i]);
        output.Add("names");
        List<string> ordered = new(names.Keys);
        ordered.Sort((a, b) =>
                         names[a] != names[b] ? names[b].CompareTo(names[a]) : string.CompareOrdinal(a, b));
        foreach (string name in ordered)
            output.Add(name + " " + names[name]);
        return output;
    }
    public static List<string> StreamLines(Flows flows, List<Packet> packets) {
        List<string> output = new();
        long origin = packets[0].time;
        foreach (Flows.Stream stream in flows.streams) {
            if (output.Count != 0)
                output.Add("");
            output.Add("stream " + stream.number + " " + stream.client + " -> " + stream.server);
            output.Add("packets " + stream.packets + " bytes " + stream.bytes + " start " +
                       Seconds(stream.start - origin) + " duration " + Seconds(stream.end - stream.start));
            output.Add("states " + string.Join(", ", stream.history));
            output.Add("handshake syn " + Optional(stream.syn) + " syn_ack " + Optional(stream.synAck) +
                       " ack " + Optional(stream.ack) + " rtt " +
                       (stream.syn >= 0 && stream.ack >= 0
                            ? Seconds(packets[stream.ack - 1].time - packets[stream.syn - 1].time)
                            : "-"));
            output.Add("options client mss " + Optional(stream.clientSide.mss) + " wscale " +
                       Optional(stream.clientSide.ws) + " server mss " + Optional(stream.serverSide.mss) +
                       " wscale " + Optional(stream.serverSide.ws));
            foreach (Flows.Side side in new Flows.Side[] { stream.clientSide, stream.serverSide }) {
                string text = side.name + " packets " + side.packets + " payload " + side.payload;
                for (int i = 0; i < Flows.MARKS.Length; i++)
                    text += " " + Flows.MARKS[i] + " " + side.marks[i];
                output.Add(text);
            }
            output.AddRange(stream.events);
        }
        return output;
    }
    public static void Write(string name, List<string> lines) {
        File.WriteAllText(Path.Combine("output", name),
                          lines.Count == 0 ? "" : string.Join("\n", lines) + "\n", Encoding.ASCII);
    }
    public static void Main(string[] args) {
        List<Packet> packets = Hexdump.Read();
        long origin = packets[0].time;
        Flows flows = new Flows();
        foreach (Packet p in packets) {
            Dissect(p, origin);
            if (p.Has("tcp.srcport"))
                flows.Track(p);
        }
        List<string> summaries = new();
        foreach (Packet p in packets)
            summaries.Add(Summary(p));
        List<string> summaryOutput = new(summaries), detailOutput = new();
        bool firstDetail = true;
        foreach (string line in File.ReadAllLines(Path.Combine("input/filters.txt"), Encoding.ASCII)) {
            if (line.StartsWith("FILTER ")) {
                string expression = line.Substring(7);
                summaryOutput.Add("");
                summaryOutput.Add("filter " + expression);
                try {
                    Func<Packet, bool> filter = new Parser(expression).Parse();
                    int matched = 0;
                    for (int i = 0; i < packets.Count; i++)
                        if (filter(packets[i])) {
                            matched++;
                            summaryOutput.Add(summaries[i]);
                        }
                    summaryOutput.Add("matched " + matched + " of " + packets.Count);
                } catch (FilterError error) {
                    summaryOutput.Add("error: " + error.Message);
                }
            } else if (line.StartsWith("DETAIL ")) {
                if (!firstDetail)
                    detailOutput.Add("");
                firstDetail = false;
                detailOutput.AddRange(Details(packets, int.Parse(line.Substring(7))));
            }
        }
        Directory.CreateDirectory(Path.Combine("output"));
        Write("summary.txt", summaryOutput);
        Write("details.txt", detailOutput);
        Write("conversations.csv", Flows.Conversations(packets));
        Write("endpoints.csv", Flows.Endpoints(packets));
        Write("protocol_stats.txt", Stats(packets));
        Write("tcp_streams.txt", StreamLines(flows, packets));
    }
}
