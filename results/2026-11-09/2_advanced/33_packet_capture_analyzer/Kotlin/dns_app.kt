import java.util.Locale
object DnsApp {
    data class Name(val text: String, val end: Int)
    fun name(b: IntArray, start: Int): Name {
        val labels = mutableListOf<String>();
        var position = start;
        var end = -1;
        var pointers = 0
        while (true) {
            val value = LinkNetwork.integer(b,position,1).toInt()
            if (value == 0) {
                if (end < 0) end = position + 1;
                break
            }
            if (value >= 192) {
                val low = LinkNetwork.integer(b,position + 1,1).toInt();
                if (end < 0) end = position + 2
                pointers++;
                if (pointers > 16) throw LinkNetwork.Bad("dns: compression loop")
                position = (value - 192) * 256 + low;
                if (position >= b.size) throw LinkNetwork.Bad("dns: pointer out of range")
            } else if (value >= 64) throw LinkNetwork.Bad("dns: bad label type")
            else {
                val label = StringBuilder()
                for (i in 0 until value) {
                    val c = LinkNetwork.integer(b,position + 1 + i,1).toInt();
                    if (c in 33..126 && c != 46 && c != 92) label.append(c.toChar()) else label.append(String.format(Locale.ROOT,"\\%03d",c))
                }
                labels.add(label.toString());
                position += value + 1
            }
        }
        return Name(if (labels.isEmpty()) "<root>" else labels.joinToString("."), end)
    }
    fun type(value: Long): String = when (value) {
        1L -> "A";
        2L -> "NS";
        5L -> "CNAME";
        6L -> "SOA";
        12L -> "PTR";
        15L -> "MX";
        16L -> "TXT";
        28L -> "AAAA";
        else -> "TYPE$value"
    }
    fun rcode(value: Long): String {
        val names = listOf("NoError","FormErr","ServFail","NXDomain","NotImp","Refused");
        return if (value < names.size) names[value.toInt()] else "RCODE$value"
    }
    fun ipv6(b: IntArray, start: Int): String {
        val groups = (0..7).map {
            LinkNetwork.word(b,start + 2 * it).toString(16)
        };
        var best = -1;
        var length = 1;
        var i = 0
        while (i < 8) {
            if (groups[i] == "0") {
                var end = i;
                while (end < 8 && groups[end] == "0") end++;
                if (end - i > length) {
                    best = i;
                    length = end - i
                };
                i = end
            } else i++
        }
        return if (best < 0) groups.joinToString(":") else groups.take(best).joinToString(":") + "::" + groups.drop(best + length).joinToString(":")
    }
    fun dissect(p: Packet, b: IntArray): IntArray {
        LinkNetwork.integer(b,11,1);
        val flags = LinkNetwork.word(b,2)
        p["dns.id"] = LinkNetwork.word(b,0);
        p["dns.flags"] = flags;
        p["dns.flags.response"] = (flags shr 15) and 1;
        p["dns.flags.opcode"] = (flags shr 11) and 15;
        p["dns.flags.rcode"] = flags and 15
        val counts = listOf("queries","answers","auth_rr","add_rr");
        counts.forEachIndexed {
            i, count -> p["dns.count.$count"] = LinkNetwork.word(b,4 + 2 * i)
        }
        var position = 12
        repeat(p.num("dns.count.queries").toInt()) {
            val n = name(b,position);
            LinkNetwork.integer(b,n.end,4);
            p.append("dns.qry.name",n.text);
            p.append("dns.qry.type",LinkNetwork.word(b,n.end));
            position = n.end + 4
        }
        val fields = listOf("dns.answer","dns.authority","dns.additional")
        for (group in 0..2) repeat(p.num("dns.count.${counts[group + 1]}").toInt()) {
            val n = name(b,position);
            position = n.end;
            LinkNetwork.integer(b,position + 9,1)
            val kind = LinkNetwork.word(b,position);
            val cls = LinkNetwork.word(b,position + 2);
            val size = LinkNetwork.word(b,position + 8);
            val ttl = LinkNetwork.integer(b,position + 4,4)
            val start = position + 10;
            val end = start + size;
            var read = end
            if (end > b.size) throw LinkNetwork.Bad("dns: truncated")
            val data = when (kind) {
                1 -> {
                    read = start + 4;
                    LinkNetwork.ipv4(LinkNetwork.integer(b,start,4))
                }
                28 -> {
                    read = start + 16;
                    ipv6(b,start)
                }
                2,5,12 -> {
                    val target = name(b,start);
                    read = target.end;
                    target.text
                }
                15 -> {
                    val preference = LinkNetwork.word(b,start);
                    val target = name(b,start + 2);
                    read = target.end;
                    "$preference ${target.text}"
                }
                6 -> {
                    val first = name(b,start);
                    val second = name(b,first.end);
                    read = second.end;
                    val text = StringBuilder("${first.text} ${second.text}");
                    repeat(5) {
                        text.append(" ").append(LinkNetwork.integer(b,read,4));
                        read += 4
                    };
                    text.toString()
                }
                else -> "$size bytes"
            }
            if (read != end) throw LinkNetwork.Bad("dns: bad rdata length")
            p.append(fields[group],"${n.text} ${type(kind.toLong())} ${if (cls == 1) "IN" else "CLASS$cls"} $ttl $data")
            if (group == 0 && kind == 1) p.append("dns.a",LinkNetwork.integer(b,start,4))
            if (group == 0) p.answers.add("${type(kind.toLong())} $data")
            position = end
        }
        return intArrayOf()
    }
}
