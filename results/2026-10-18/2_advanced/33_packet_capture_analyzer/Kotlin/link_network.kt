import java.util.Locale
object LinkNetwork {
    class Bad(reason: String): RuntimeException(reason)
    fun integer(bytes: IntArray, position: Int, count: Int): Long {
        if (position < 0 || position + count > bytes.size) throw Bad("dns: truncated")
        var value = 0L;
        for (i in 0 until count) value = value * 256 + bytes[position + i];
        return value
    }
    fun word(bytes: IntArray, position: Int) = integer(bytes, position, 2).toInt()
    fun slice(bytes: IntArray, start: Int, end: Int) = bytes.copyOfRange(start, end)
    fun checksum(bytes: IntArray): String {
        var sum = 0L
        for (i in bytes.indices step 2) sum += bytes[i] * 256 + if (i + 1 < bytes.size) bytes[i + 1] else 0
        while (sum > 65535) sum = (sum and 65535) + (sum shr 16)
        return if (sum == 65535L) "good" else "bad"
    }
    fun ipv4(value: Long) = listOf(24,16,8,0).joinToString(".") {
        ((value shr it) and 255).toString()
    }
    fun mac(value: Long) = listOf(40,32,24,16,8,0).joinToString(":") {
        String.format(Locale.ROOT, "%02x", (value shr it) and 255)
    }
    fun ethernet(p: Packet, b: IntArray): IntArray {
        if (b.size < 14) throw Bad("eth: truncated")
        p["eth.dst"] = integer(b,0,6);
        p["eth.src"] = integer(b,6,6);
        p["eth.type"] = word(b,12)
        return slice(b,14,b.size)
    }
    fun arp(p: Packet, b: IntArray): IntArray {
        if (b.size < 28) throw Bad("arp: truncated")
        if (word(b,0) != 1 || word(b,2) != 2048 || b[4] != 6 || b[5] != 4) throw Bad("arp: unsupported format")
        p["arp.opcode"] = word(b,6);
        p["arp.src.hw"] = integer(b,8,6);
        p["arp.src.ip"] = integer(b,14,4);
        p["arp.dst.hw"] = integer(b,18,6);
        p["arp.dst.ip"] = integer(b,24,4)
        return intArrayOf()
    }
    fun ipv4(p: Packet, b: IntArray): IntArray {
        if (b.size < 20) throw Bad("ip: truncated header")
        val version = b[0] / 16;
        val h = b[0] % 16 * 4
        if (version != 4) throw Bad("ip: bad version $version")
        if (h < 20) throw Bad("ip: bad header length $h")
        if (b.size < h) throw Bad("ip: truncated header")
        val total = word(b,2)
        if (total < h) throw Bad("ip: bad total length $total")
        if (total > b.size) throw Bad("ip: truncated (total length $total, available ${b.size})")
        val flags = word(b,6)
        p["ip.hdr_len"] = h;
        p["ip.tos"] = b[1];
        p["ip.len"] = total;
        p["ip.id"] = word(b,4);
        p["ip.flags.df"] = (flags shr 14) and 1;
        p["ip.flags.mf"] = (flags shr 13) and 1;
        p["ip.frag_offset"] = flags % 8192 * 8;
        p["ip.ttl"] = b[8];
        p["ip.proto"] = b[9];
        p["ip.checksum"] = word(b,10);
        p["ip.checksum.status"] = checksum(slice(b,0,h));
        p["ip.src"] = integer(b,12,4);
        p["ip.dst"] = integer(b,16,4)
        if ((flags and 8192) != 0 || flags % 8192 != 0) p["ip.fragment"] = 0
        return slice(b,h,total)
    }
}
