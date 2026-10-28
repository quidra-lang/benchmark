object Transport {
    fun pseudo(p: Packet, bytes: IntArray, protocol: Int): IntArray {
        val result = IntArray(12 + bytes.size);
        val source = p.num("ip.src");
        val destination = p.num("ip.dst")
        for (i in 0..3) {
            result[i] = ((source shr (24 - 8 * i)) and 255).toInt();
            result[i + 4] = ((destination shr (24 - 8 * i)) and 255).toInt()
        }
        result[9] = protocol;
        result[10] = bytes.size / 256;
        result[11] = bytes.size % 256;
        bytes.copyInto(result,12);
        return result
    }
    fun icmp(p: Packet, b: IntArray): IntArray {
        if (b.size < 8) throw LinkNetwork.Bad("icmp: truncated")
        p["icmp.type"] = b[0];
        p["icmp.code"] = b[1];
        p["icmp.checksum"] = LinkNetwork.word(b,2);
        p["icmp.checksum.status"] = LinkNetwork.checksum(b)
        if (b[0] == 0 || b[0] == 8) {
            p["icmp.id"] = LinkNetwork.word(b,4);
            p["icmp.seq"] = LinkNetwork.word(b,6)
        }
        return LinkNetwork.slice(b,8,b.size)
    }
    fun udp(p: Packet, b: IntArray): IntArray {
        if (b.size < 8) throw LinkNetwork.Bad("udp: truncated")
        val length = LinkNetwork.word(b,4);
        if (length < 8 || length > b.size) throw LinkNetwork.Bad("udp: bad length $length")
        p["udp.srcport"] = LinkNetwork.word(b,0);
        p["udp.dstport"] = LinkNetwork.word(b,2);
        p["udp.length"] = length;
        p["udp.checksum"] = LinkNetwork.word(b,6)
        p["udp.checksum.status"] = if (p.num("udp.checksum") == 0L) "none" else LinkNetwork.checksum(pseudo(p,LinkNetwork.slice(b,0,length),17))
        return LinkNetwork.slice(b,8,length)
    }
    fun tcp(p: Packet, b: IntArray): IntArray {
        if (b.size < 20) throw LinkNetwork.Bad("tcp: truncated header")
        val h = b[12] / 16 * 4
        if (h < 20) throw LinkNetwork.Bad("tcp: bad header length $h")
        if (h > b.size) throw LinkNetwork.Bad("tcp: truncated header")
        p["tcp.srcport"] = LinkNetwork.word(b,0);
        p["tcp.dstport"] = LinkNetwork.word(b,2);
        p["tcp.seq_raw"] = LinkNetwork.integer(b,4,4);
        p["tcp.hdr_len"] = h;
        p["tcp.flags"] = b[13];
        p["tcp.window"] = LinkNetwork.word(b,14);
        p["tcp.checksum"] = LinkNetwork.word(b,16);
        p["tcp.checksum.status"] = LinkNetwork.checksum(pseudo(p,b,6));
        p["tcp.urgent"] = LinkNetwork.word(b,18);
        p["tcp.len"] = b.size - h
        listOf("fin","syn","rst","psh","ack","urg").forEachIndexed {
            i, name -> p["tcp.flags.$name"] = (b[13] shr i) and 1
        }
        if ((b[13] and 16) != 0) p["tcp.ack_raw"] = LinkNetwork.integer(b,8,4)
        var i = 20
        while (i < h) {
            val kind = b[i]
            if (kind == 0) {
                p.append("tcp.option","EOL");
                break
            }
            if (kind == 1) {
                p.append("tcp.option","NOP");
                i++;
                continue
            }
            val n = if (i + 1 < h) b[i + 1] else 0
            val valid = when (kind) {
                2 -> n == 4;
                3 -> n == 3;
                4 -> n == 2;
                5 -> n in listOf(10,18,26,34);
                8 -> n == 10;
                else -> true
            }
            if (n < 2 || i + n > h || !valid) {
                p["tcp.options.malformed"] = 0;
                break
            }
            val option = when (kind) {
                2 -> {
                    val value = LinkNetwork.word(b,i + 2);
                    p["tcp.options.mss"] = value;
                    "MSS $value"
                }
                3 -> {
                    p["tcp.options.wscale"] = b[i + 2];
                    "WS ${b[i + 2]}"
                }
                4 -> "SACK_PERM"
                5 -> "SACK" + (i + 2 until i + n step 8).joinToString("") {
                    " ${LinkNetwork.integer(b,it,4)}-${LinkNetwork.integer(b,it + 4,4)}"
                }
                8 -> "TS ${LinkNetwork.integer(b,i + 2,4)} ${LinkNetwork.integer(b,i + 6,4)}"
                else -> "kind $kind len $n"
            }
            p.append("tcp.option",option);
            i += n
        }
        return LinkNetwork.slice(b,h,b.size)
    }
}
