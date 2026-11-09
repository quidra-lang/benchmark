using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

public sealed class LinkNetwork {
    public sealed class Bad : Exception {
        public Bad(string reason) : base(reason) {
        }
    }
    public static long Integer(int[] bytes, int position, int count) {
        if (position < 0 || position + count > bytes.Length)
            throw new Bad("dns: truncated");
        long value = 0;
        for (int i = 0; i < count; i++)
            value = value * 256 + bytes[position + i];
        return value;
    }
    public static int Word(int[] bytes, int position) {
        return (int)Integer(bytes, position, 2);
    }
    public static int[] Slice(int[] bytes, int start, int end) {
        return bytes[start..end];
    }
    public static string Checksum(int[] bytes) {
        long sum = 0;
        for (int i = 0; i < bytes.Length; i += 2)
            sum += bytes[i] * 256 + (i + 1 < bytes.Length ? bytes[i + 1] : 0);
        while (sum > 65535)
            sum = (sum & 65535) + (sum >> 16);
        return sum == 65535 ? "good" : "bad";
    }
    public static string Ipv4(long value) {
        return ((value >> 24) & 255) + "." + ((value >> 16) & 255) + "." + ((value >> 8) & 255) + "." +
               (value & 255);
    }
    public static string Mac(long value) {
        List<string> parts = new();
        for (int shift = 40; shift >= 0; shift -= 8)
            parts.Add(string.Format(CultureInfo.InvariantCulture, "{0:x2}", (value >> shift) & 255));
        return string.Join(":", parts);
    }
    public static int[] Ethernet(Program.Packet p, int[] b) {
        if (b.Length < 14)
            throw new Bad("eth: truncated");
        p["eth.dst"] = Integer(b, 0, 6);
        p["eth.src"] = Integer(b, 6, 6);
        p["eth.type"] = Word(b, 12);
        return Slice(b, 14, b.Length);
    }
    public static int[] Arp(Program.Packet p, int[] b) {
        if (b.Length < 28)
            throw new Bad("arp: truncated");
        if (Word(b, 0) != 1 || Word(b, 2) != 2048 || b[4] != 6 || b[5] != 4)
            throw new Bad("arp: unsupported format");
        p["arp.opcode"] = Word(b, 6);
        p["arp.src.hw"] = Integer(b, 8, 6);
        p["arp.src.ip"] = Integer(b, 14, 4);
        p["arp.dst.hw"] = Integer(b, 18, 6);
        p["arp.dst.ip"] = Integer(b, 24, 4);
        return new int[0];
    }
    public static int[] Ipv4(Program.Packet p, int[] b) {
        if (b.Length < 20)
            throw new Bad("ip: truncated header");
        int version = b[0] / 16, h = b[0] % 16 * 4;
        if (version != 4)
            throw new Bad("ip: bad version " + version);
        if (h < 20)
            throw new Bad("ip: bad header length " + h);
        if (b.Length < h)
            throw new Bad("ip: truncated header");
        int total = Word(b, 2);
        if (total < h)
            throw new Bad("ip: bad total length " + total);
        if (total > b.Length)
            throw new Bad("ip: truncated (total length " + total + ", available " + b.Length + ")");
        int flags = Word(b, 6);
        p["ip.hdr_len"] = h;
        p["ip.tos"] = b[1];
        p["ip.len"] = total;
        p["ip.id"] = Word(b, 4);
        p["ip.flags.df"] = (flags >> 14) & 1;
        p["ip.flags.mf"] = (flags >> 13) & 1;
        p["ip.frag_offset"] = flags % 8192 * 8;
        p["ip.ttl"] = b[8];
        p["ip.proto"] = b[9];
        p["ip.checksum"] = Word(b, 10);
        p["ip.checksum.status"] = Checksum(Slice(b, 0, h));
        p["ip.src"] = Integer(b, 12, 4);
        p["ip.dst"] = Integer(b, 16, 4);
        if ((flags & 8192) != 0 || flags % 8192 != 0)
            p["ip.fragment"] = 0;
        return Slice(b, h, total);
    }
}
