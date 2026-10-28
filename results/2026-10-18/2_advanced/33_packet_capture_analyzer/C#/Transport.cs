using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

public sealed class Transport {
    public static int[] Pseudo(Program.Packet p, int[] bytes, int protocol) {
        int[] result = new int[12 + bytes.Length];
        long source = p.Num("ip.src"), destination = p.Num("ip.dst");
        for (int i = 0; i < 4; i++) {
            result[i] = (int)((source >> (24 - 8 * i)) & 255);
            result[i + 4] = (int)((destination >> (24 - 8 * i)) & 255);
        }
        result[9] = protocol;
        result[10] = bytes.Length / 256;
        result[11] = bytes.Length % 256;
        Array.Copy(bytes, 0, result, 12, bytes.Length);
        return result;
    }
    public static int[] Icmp(Program.Packet p, int[] b) {
        if (b.Length < 8)
            throw new LinkNetwork.Bad("icmp: truncated");
        p["icmp.type"] = b[0];
        p["icmp.code"] = b[1];
        p["icmp.checksum"] = LinkNetwork.Word(b, 2);
        p["icmp.checksum.status"] = LinkNetwork.Checksum(b);
        if (b[0] == 0 || b[0] == 8) {
            p["icmp.id"] = LinkNetwork.Word(b, 4);
            p["icmp.seq"] = LinkNetwork.Word(b, 6);
        }
        return LinkNetwork.Slice(b, 8, b.Length);
    }
    public static int[] Udp(Program.Packet p, int[] b) {
        if (b.Length < 8)
            throw new LinkNetwork.Bad("udp: truncated");
        int length = LinkNetwork.Word(b, 4);
        if (length < 8 || length > b.Length)
            throw new LinkNetwork.Bad("udp: bad length " + length);
        p["udp.srcport"] = LinkNetwork.Word(b, 0);
        p["udp.dstport"] = LinkNetwork.Word(b, 2);
        p["udp.length"] = length;
        p["udp.checksum"] = LinkNetwork.Word(b, 6);
        p["udp.checksum.status"] = p.Num("udp.checksum") == 0
                                       ? "none"
                                       : LinkNetwork.Checksum(Pseudo(p, LinkNetwork.Slice(b, 0, length), 17));
        return LinkNetwork.Slice(b, 8, length);
    }
    public static int[] Tcp(Program.Packet p, int[] b) {
        if (b.Length < 20)
            throw new LinkNetwork.Bad("tcp: truncated header");
        int h = b[12] / 16 * 4;
        if (h < 20)
            throw new LinkNetwork.Bad("tcp: bad header length " + h);
        if (h > b.Length)
            throw new LinkNetwork.Bad("tcp: truncated header");
        p["tcp.srcport"] = LinkNetwork.Word(b, 0);
        p["tcp.dstport"] = LinkNetwork.Word(b, 2);
        p["tcp.seq_raw"] = LinkNetwork.Integer(b, 4, 4);
        p["tcp.hdr_len"] = h;
        p["tcp.flags"] = b[13];
        p["tcp.window"] = LinkNetwork.Word(b, 14);
        p["tcp.checksum"] = LinkNetwork.Word(b, 16);
        p["tcp.checksum.status"] = LinkNetwork.Checksum(Pseudo(p, b, 6));
        p["tcp.urgent"] = LinkNetwork.Word(b, 18);
        p["tcp.len"] = b.Length - h;
        string[] names = { "fin", "syn", "rst", "psh", "ack", "urg" };
        for (int flagIndex = 0; flagIndex < names.Length; flagIndex++)
            p["tcp.flags." + names[flagIndex]] = (b[13] >> flagIndex) & 1;
        if ((b[13] & 16) != 0)
            p["tcp.ack_raw"] = LinkNetwork.Integer(b, 8, 4);
        int i = 20;
        while (i < h) {
            int kind = b[i];
            if (kind == 0) {
                p.Append("tcp.option", "EOL");
                break;
            }
            if (kind == 1) {
                p.Append("tcp.option", "NOP");
                i++;
                continue;
            }
            int n = i + 1 < h ? b[i + 1] : 0;
            bool valid = (kind) switch {
                2 => n == 4,
                3 => n == 3,
                4 => n == 2,
                5 => n == 10 || n == 18 || n == 26 || n == 34,
                8 => n == 10,
                _ => true,
            };
            if (n < 2 || i + n > h || !valid) {
                p["tcp.options.malformed"] = 0;
                break;
            }
            string option;
            if (kind == 2) {
                long value = LinkNetwork.Word(b, i + 2);
                option = "MSS " + value;
                p["tcp.options.mss"] = value;
            } else if (kind == 3) {
                option = "WS " + b[i + 2];
                p["tcp.options.wscale"] = b[i + 2];
            } else if (kind == 4)
                option = "SACK_PERM";
            else if (kind == 5) {
                StringBuilder text = new StringBuilder("SACK");
                for (int j = i + 2; j < i + n; j += 8)
                    text.Append(" ")
                        .Append(LinkNetwork.Integer(b, j, 4))
                        .Append("-")
                        .Append(LinkNetwork.Integer(b, j + 4, 4));
                option = text.ToString();
            } else if (kind == 8)
                option = "TS " + LinkNetwork.Integer(b, i + 2, 4) + " " + LinkNetwork.Integer(b, i + 6, 4);
            else
                option = "kind " + kind + " len " + n;
            p.Append("tcp.option", option);
            i += n;
        }
        return LinkNetwork.Slice(b, h, b.Length);
    }
}
