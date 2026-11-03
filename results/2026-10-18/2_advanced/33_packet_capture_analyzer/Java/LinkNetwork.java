import java.util.*;
final class LinkNetwork {
    static final class Bad extends RuntimeException {
        Bad(String reason) {
            super(reason);
        }
    }
    static long integer(int[] bytes, int position, int count) {
        if (position < 0 || position + count > bytes.length)
            throw new Bad("dns: truncated");
        long value = 0;
        for (int i = 0; i < count; i++)
            value = value * 256 + bytes[position + i];
        return value;
    }
    static int word(int[] bytes, int position) {
        return (int)integer(bytes, position, 2);
    }
    static int[] slice(int[] bytes, int start, int end) {
        return Arrays.copyOfRange(bytes, start, end);
    }
    static String checksum(int[] bytes) {
        long sum = 0;
        for (int i = 0; i < bytes.length; i += 2)
            sum += bytes[i] * 256 + (i + 1 < bytes.length ? bytes[i + 1] : 0);
        while (sum > 65535)
            sum = (sum & 65535) + (sum >> 16);
        return sum == 65535 ? "good" : "bad";
    }
    static String ipv4(long value) {
        return ((value >> 24) & 255) + "." + ((value >> 16) & 255) + "." + ((value >> 8) & 255) + "." +
            (value & 255);
    }
    static String mac(long value) {
        List<String> parts = new ArrayList<>();
        for (int shift = 40; shift >= 0; shift -= 8)
            parts.add(String.format(Locale.ROOT, "%02x", (value >> shift) & 255));
        return String.join(":", parts);
    }
    static int[] ethernet(Main.Packet p, int[] b) {
        if (b.length < 14)
            throw new Bad("eth: truncated");
        p.put("eth.dst", integer(b, 0, 6));
        p.put("eth.src", integer(b, 6, 6));
        p.put("eth.type", word(b, 12));
        return slice(b, 14, b.length);
    }
    static int[] arp(Main.Packet p, int[] b) {
        if (b.length < 28)
            throw new Bad("arp: truncated");
        if (word(b, 0) != 1 || word(b, 2) != 2048 || b[4] != 6 || b[5] != 4)
            throw new Bad("arp: unsupported format");
        p.put("arp.opcode", word(b, 6));
        p.put("arp.src.hw", integer(b, 8, 6));
        p.put("arp.src.ip", integer(b, 14, 4));
        p.put("arp.dst.hw", integer(b, 18, 6));
        p.put("arp.dst.ip", integer(b, 24, 4));
        return new int[0];
    }
    static int[] ipv4(Main.Packet p, int[] b) {
        if (b.length < 20)
            throw new Bad("ip: truncated header");
        int version = b[0] / 16, h = b[0] % 16 * 4;
        if (version != 4)
            throw new Bad("ip: bad version " + version);
        if (h < 20)
            throw new Bad("ip: bad header length " + h);
        if (b.length < h)
            throw new Bad("ip: truncated header");
        int total = word(b, 2);
        if (total < h)
            throw new Bad("ip: bad total length " + total);
        if (total > b.length)
            throw new Bad("ip: truncated (total length " + total + ", available " + b.length + ")");
        int flags = word(b, 6);
        p.put("ip.hdr_len", h);
        p.put("ip.tos", b[1]);
        p.put("ip.len", total);
        p.put("ip.id", word(b, 4));
        p.put("ip.flags.df", (flags >> 14) & 1);
        p.put("ip.flags.mf", (flags >> 13) & 1);
        p.put("ip.frag_offset", flags % 8192 * 8);
        p.put("ip.ttl", b[8]);
        p.put("ip.proto", b[9]);
        p.put("ip.checksum", word(b, 10));
        p.put("ip.checksum.status", checksum(slice(b, 0, h)));
        p.put("ip.src", integer(b, 12, 4));
        p.put("ip.dst", integer(b, 16, 4));
        if ((flags & 8192) != 0 || flags % 8192 != 0)
            p.put("ip.fragment", 0);
        return slice(b, h, total);
    }
}
