using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

public sealed class DnsApp {
    public sealed record Name(string text, int end);
    public static Name ReadName(int[] b, int start) {
        List<string> labels = new();
        int position = start, end = -1, pointers = 0;
        while (true) {
            int value = (int)LinkNetwork.Integer(b, position, 1);
            if (value == 0) {
                if (end < 0)
                    end = position + 1;
                break;
            }
            if (value >= 192) {
                int low = (int)LinkNetwork.Integer(b, position + 1, 1);
                if (end < 0)
                    end = position + 2;
                if (++pointers > 16)
                    throw new LinkNetwork.Bad("dns: compression loop");
                position = (value - 192) * 256 + low;
                if (position >= b.Length)
                    throw new LinkNetwork.Bad("dns: pointer out of range");
            } else if (value >= 64)
                throw new LinkNetwork.Bad("dns: bad label type");
            else {
                StringBuilder label = new StringBuilder();
                for (int i = 0; i < value; i++) {
                    int c = (int)LinkNetwork.Integer(b, position + 1 + i, 1);
                    if (c >= 33 && c <= 126 && c != 46 && c != 92)
                        label.Append((char)c);
                    else
                        label.Append(string.Format(CultureInfo.InvariantCulture, "\\{0:D3}", c));
                }
                labels.Add(label.ToString());
                position += value + 1;
            }
        }
        return new Name(labels.Count == 0 ? "<root>" : string.Join(".", labels), end);
    }
    public static string Type(long value) {
        return ((int)value) switch {
            1 => "A",
            2 => "NS",
            5 => "CNAME",
            6 => "SOA",
            12 => "PTR",
            15 => "MX",
            16 => "TXT",
            28 => "AAAA",
            _ => "TYPE" + value,
        };
    }
    public static string Rcode(long value) {
        string[] names = { "NoError", "FormErr", "ServFail", "NXDomain", "NotImp", "Refused" };
        return value < names.Length ? names[(int)value] : "RCODE" + value;
    }
    public static string Ipv6(int[] b, int start) {
        List<string> groups = new();
        int best = -1, length = 1;
        for (int i = 0; i < 8; i++)
            groups.Add(LinkNetwork.Word(b, start + 2 * i).ToString("x", CultureInfo.InvariantCulture));
        for (int i = 0; i < 8; i++)
            if (groups[i].Equals("0")) {
                int end = i;
                while (end < 8 && groups[end].Equals("0"))
                    end++;
                if (end - i > length) {
                    best = i;
                    length = end - i;
                }
                i = end - 1;
            }
        if (best < 0)
            return string.Join(":", groups);
        return string.Join(":", groups.GetRange(0, best - (0))) +
               "::" + string.Join(":", groups.GetRange(best + length, 8 - (best + length)));
    }
    public static int[] Dissect(Program.Packet p, int[] b) {
        LinkNetwork.Integer(b, 11, 1);
        int flags = LinkNetwork.Word(b, 2);
        p["dns.id"] = LinkNetwork.Word(b, 0);
        p["dns.flags"] = flags;
        p["dns.flags.response"] = (flags >> 15) & 1;
        p["dns.flags.opcode"] = (flags >> 11) & 15;
        p["dns.flags.rcode"] = flags & 15;
        string[] counts = { "queries", "answers", "auth_rr", "add_rr" };
        for (int i = 0; i < 4; i++)
            p["dns.count." + counts[i]] = LinkNetwork.Word(b, 4 + 2 * i);
        int position = 12;
        for (int i = 0; i < p.Num("dns.count.queries"); i++) {
            Name n = ReadName(b, position);
            LinkNetwork.Integer(b, n.end, 4);
            p.Append("dns.qry.name", n.text);
            p.Append("dns.qry.type", LinkNetwork.Word(b, n.end));
            position = n.end + 4;
        }
        string[] recordFields = { "dns.answer", "dns.authority", "dns.additional" };
        for (int group = 0; group < 3; group++)
            for (int i = 0; i < p.Num("dns.count." + counts[group + 1]); i++) {
                Name n = ReadName(b, position);
                position = n.end;
                LinkNetwork.Integer(b, position + 9, 1);
                int kind = LinkNetwork.Word(b, position), cls = LinkNetwork.Word(b, position + 2),
                    size = LinkNetwork.Word(b, position + 8);
                long ttl = LinkNetwork.Integer(b, position + 4, 4);
                int start = position + 10, end = start + size, read = end;
                if (end > b.Length)
                    throw new LinkNetwork.Bad("dns: truncated");
                string data;
                if (kind == 1) {
                    data = LinkNetwork.Ipv4(LinkNetwork.Integer(b, start, 4));
                    read = start + 4;
                } else if (kind == 28) {
                    data = Ipv6(b, start);
                    read = start + 16;
                } else if (kind == 2 || kind == 5 || kind == 12) {
                    Name target = ReadName(b, start);
                    data = target.text;
                    read = target.end;
                } else if (kind == 15) {
                    int preference = LinkNetwork.Word(b, start);
                    Name target = ReadName(b, start + 2);
                    data = preference + " " + target.text;
                    read = target.end;
                } else if (kind == 6) {
                    Name first = ReadName(b, start), second = ReadName(b, first.end);
                    read = second.end;
                    StringBuilder text = new StringBuilder(first.text + " " + second.text);
                    for (int j = 0; j < 5; j++) {
                        text.Append(" ").Append(LinkNetwork.Integer(b, read, 4));
                        read += 4;
                    }
                    data = text.ToString();
                } else
                    data = size + " bytes";
                if (read != end)
                    throw new LinkNetwork.Bad("dns: bad rdata length");
                p.Append(recordFields[group], n.text + " " + Type(kind) + " " +
                                                  (cls == 1 ? "IN" : "CLASS" + cls) + " " + ttl + " " + data);
                if (group == 0 && kind == 1)
                    p.Append("dns.a", LinkNetwork.Integer(b, start, 4));
                if (group == 0)
                    p.answers.Add(Type(kind) + " " + data);
                position = end;
            }
        return new int[0];
    }
}
