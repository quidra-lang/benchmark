import java.util.*;
final class DnsApp {
    record Name(String text, int end) {}
    static Name name(int[] b, int start) {
        List<String> labels = new ArrayList<>();
        int position = start, end = -1, pointers = 0;
        while (true) {
            int value = (int)LinkNetwork.integer(b, position, 1);
            if (value == 0) {
                if (end < 0)
                    end = position + 1;
                break;
            }
            if (value >= 192) {
                int low = (int)LinkNetwork.integer(b, position + 1, 1);
                if (end < 0)
                    end = position + 2;
                if (++pointers > 16)
                    throw new LinkNetwork.Bad("dns: compression loop");
                position = (value - 192) * 256 + low;
                if (position >= b.length)
                    throw new LinkNetwork.Bad("dns: pointer out of range");
            } else if (value >= 64)
                throw new LinkNetwork.Bad("dns: bad label type");
            else {
                StringBuilder label = new StringBuilder();
                for (int i = 0; i < value; i++) {
                    int c = (int)LinkNetwork.integer(b, position + 1 + i, 1);
                    if (c >= 33 && c <= 126 && c != 46 && c != 92)
                        label.append((char)c);
                    else
                        label.append(String.format(Locale.ROOT, "\\%03d", c));
                }
                labels.add(label.toString());
                position += value + 1;
            }
        }
        return new Name(labels.isEmpty() ? "<root>" : String.join(".", labels), end);
    }
    static String type(long value) {
        return switch ((int)value) {
            case 1 -> "A";
            case 2 -> "NS";
            case 5 -> "CNAME";
            case 6 -> "SOA";
            case 12 -> "PTR";
            case 15 -> "MX";
            case 16 -> "TXT";
            case 28 -> "AAAA";
            default -> "TYPE" + value;
        };
    }
    static String rcode(long value) {
        String[] names = {"NoError", "FormErr", "ServFail", "NXDomain", "NotImp", "Refused"};
        return value < names.length ? names[(int)value] : "RCODE" + value;
    }
    static String ipv6(int[] b, int start) {
        List<String> groups = new ArrayList<>();
        int best = -1, length = 1;
        for (int i = 0; i < 8; i++)
            groups.add(Integer.toHexString(LinkNetwork.word(b, start + 2 * i)));
        for (int i = 0; i < 8; i++)
            if (groups.get(i).equals("0")) {
                int end = i;
                while (end < 8 && groups.get(end).equals("0"))
                    end++;
                if (end - i > length) {
                    best = i;
                    length = end - i;
                }
                i = end - 1;
            }
        if (best < 0)
            return String.join(":", groups);
        return String.join(":", groups.subList(0, best)) +
            "::" + String.join(":", groups.subList(best + length, 8));
    }
    static int[] dissect(Main.Packet p, int[] b) {
        LinkNetwork.integer(b, 11, 1);
        int flags = LinkNetwork.word(b, 2);
        p.put("dns.id", LinkNetwork.word(b, 0));
        p.put("dns.flags", flags);
        p.put("dns.flags.response", (flags >> 15) & 1);
        p.put("dns.flags.opcode", (flags >> 11) & 15);
        p.put("dns.flags.rcode", flags & 15);
        String[] counts = {"queries", "answers", "auth_rr", "add_rr"};
        for (int i = 0; i < 4; i++)
            p.put("dns.count." + counts[i], LinkNetwork.word(b, 4 + 2 * i));
        int position = 12;
        for (int i = 0; i < p.num("dns.count.queries"); i++) {
            Name n = name(b, position);
            LinkNetwork.integer(b, n.end, 4);
            p.append("dns.qry.name", n.text);
            p.append("dns.qry.type", LinkNetwork.word(b, n.end));
            position = n.end + 4;
        }
        String[] recordFields = {"dns.answer", "dns.authority", "dns.additional"};
        for (int group = 0; group < 3; group++)
            for (int i = 0; i < p.num("dns.count." + counts[group + 1]); i++) {
                Name n = name(b, position);
                position = n.end;
                LinkNetwork.integer(b, position + 9, 1);
                int kind = LinkNetwork.word(b, position), cls = LinkNetwork.word(b, position + 2),
                    size = LinkNetwork.word(b, position + 8);
                long ttl = LinkNetwork.integer(b, position + 4, 4);
                int start = position + 10, end = start + size, read = end;
                if (end > b.length)
                    throw new LinkNetwork.Bad("dns: truncated");
                String data;
                if (kind == 1) {
                    data = LinkNetwork.ipv4(LinkNetwork.integer(b, start, 4));
                    read = start + 4;
                } else if (kind == 28) {
                    data = ipv6(b, start);
                    read = start + 16;
                } else if (kind == 2 || kind == 5 || kind == 12) {
                    Name target = name(b, start);
                    data = target.text;
                    read = target.end;
                } else if (kind == 15) {
                    int preference = LinkNetwork.word(b, start);
                    Name target = name(b, start + 2);
                    data = preference + " " + target.text;
                    read = target.end;
                } else if (kind == 6) {
                    Name first = name(b, start), second = name(b, first.end);
                    read = second.end;
                    StringBuilder text = new StringBuilder(first.text + " " + second.text);
                    for (int j = 0; j < 5; j++) {
                        text.append(" ").append(LinkNetwork.integer(b, read, 4));
                        read += 4;
                    }
                    data = text.toString();
                } else
                    data = size + " bytes";
                if (read != end)
                    throw new LinkNetwork.Bad("dns: bad rdata length");
                p.append(recordFields[group], n.text + " " + type(kind) + " " +
                                                  (cls == 1 ? "IN" : "CLASS" + cls) + " " + ttl + " " + data);
                if (group == 0 && kind == 1)
                    p.append("dns.a", LinkNetwork.integer(b, start, 4));
                if (group == 0)
                    p.answers.add(type(kind) + " " + data);
                position = end;
            }
        return new int[0];
    }
}
