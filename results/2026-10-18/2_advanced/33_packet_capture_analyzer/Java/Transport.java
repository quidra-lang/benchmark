import java.util.*;
final class Transport {
    static int[] pseudo(Main.Packet p, int[] bytes, int protocol) {
        int[] result = new int[12 + bytes.length];
        long source = p.num("ip.src"), destination = p.num("ip.dst");
        for (int i = 0; i < 4; i++) {
            result[i] = (int)((source >> (24 - 8 * i)) & 255);
            result[i + 4] = (int)((destination >> (24 - 8 * i)) & 255);
        }
        result[9] = protocol;
        result[10] = bytes.length / 256;
        result[11] = bytes.length % 256;
        System.arraycopy(bytes, 0, result, 12, bytes.length);
        return result;
    }
    static int[] icmp(Main.Packet p, int[] b) {
        if (b.length < 8)
            throw new LinkNetwork.Bad("icmp: truncated");
        p.put("icmp.type", b[0]);
        p.put("icmp.code", b[1]);
        p.put("icmp.checksum", LinkNetwork.word(b, 2));
        p.put("icmp.checksum.status", LinkNetwork.checksum(b));
        if (b[0] == 0 || b[0] == 8) {
            p.put("icmp.id", LinkNetwork.word(b, 4));
            p.put("icmp.seq", LinkNetwork.word(b, 6));
        }
        return LinkNetwork.slice(b, 8, b.length);
    }
    static int[] udp(Main.Packet p, int[] b) {
        if (b.length < 8)
            throw new LinkNetwork.Bad("udp: truncated");
        int length = LinkNetwork.word(b, 4);
        if (length < 8 || length > b.length)
            throw new LinkNetwork.Bad("udp: bad length " + length);
        p.put("udp.srcport", LinkNetwork.word(b, 0));
        p.put("udp.dstport", LinkNetwork.word(b, 2));
        p.put("udp.length", length);
        p.put("udp.checksum", LinkNetwork.word(b, 6));
        p.put("udp.checksum.status",
              p.num("udp.checksum") == 0
                  ? "none"
                  : LinkNetwork.checksum(pseudo(p, LinkNetwork.slice(b, 0, length), 17)));
        return LinkNetwork.slice(b, 8, length);
    }
    static int[] tcp(Main.Packet p, int[] b) {
        if (b.length < 20)
            throw new LinkNetwork.Bad("tcp: truncated header");
        int h = b[12] / 16 * 4;
        if (h < 20)
            throw new LinkNetwork.Bad("tcp: bad header length " + h);
        if (h > b.length)
            throw new LinkNetwork.Bad("tcp: truncated header");
        p.put("tcp.srcport", LinkNetwork.word(b, 0));
        p.put("tcp.dstport", LinkNetwork.word(b, 2));
        p.put("tcp.seq_raw", LinkNetwork.integer(b, 4, 4));
        p.put("tcp.hdr_len", h);
        p.put("tcp.flags", b[13]);
        p.put("tcp.window", LinkNetwork.word(b, 14));
        p.put("tcp.checksum", LinkNetwork.word(b, 16));
        p.put("tcp.checksum.status", LinkNetwork.checksum(pseudo(p, b, 6)));
        p.put("tcp.urgent", LinkNetwork.word(b, 18));
        p.put("tcp.len", b.length - h);
        String[] names = {"fin", "syn", "rst", "psh", "ack", "urg"};
        for (int i = 0; i < names.length; i++)
            p.put("tcp.flags." + names[i], (b[13] >> i) & 1);
        if ((b[13] & 16) != 0)
            p.put("tcp.ack_raw", LinkNetwork.integer(b, 8, 4));
        int i = 20;
        while (i < h) {
            int kind = b[i];
            if (kind == 0) {
                p.append("tcp.option", "EOL");
                break;
            }
            if (kind == 1) {
                p.append("tcp.option", "NOP");
                i++;
                continue;
            }
            int n = i + 1 < h ? b[i + 1] : 0;
            boolean valid = switch (kind) {
                case 2 -> n == 4;
                case 3 -> n == 3;
                case 4 -> n == 2;
                case 5 -> n == 10 || n == 18 || n == 26 || n == 34;
                case 8 -> n == 10;
                default -> true;
            };
            if (n < 2 || i + n > h || !valid) {
                p.put("tcp.options.malformed", 0);
                break;
            }
            String option;
            if (kind == 2) {
                long value = LinkNetwork.word(b, i + 2);
                option = "MSS " + value;
                p.put("tcp.options.mss", value);
            } else if (kind == 3) {
                option = "WS " + b[i + 2];
                p.put("tcp.options.wscale", b[i + 2]);
            } else if (kind == 4)
                option = "SACK_PERM";
            else if (kind == 5) {
                StringBuilder text = new StringBuilder("SACK");
                for (int j = i + 2; j < i + n; j += 8)
                    text.append(" ")
                        .append(LinkNetwork.integer(b, j, 4))
                        .append("-")
                        .append(LinkNetwork.integer(b, j + 4, 4));
                option = text.toString();
            } else if (kind == 8)
                option = "TS " + LinkNetwork.integer(b, i + 2, 4) + " " + LinkNetwork.integer(b, i + 6, 4);
            else
                option = "kind " + kind + " len " + n;
            p.append("tcp.option", option);
            i += n;
        }
        return LinkNetwork.slice(b, h, b.length);
    }
}
