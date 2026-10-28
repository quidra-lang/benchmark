class Flows {
    companion object {
        val marks = listOf("retransmission","out_of_order","lost_segment","duplicate_ack")
        fun conversations(packets: List<Packet>): List<String> {
            val grouped = mutableMapOf<String,Conversation>()
            for (p in packets) for (kind in listOf("ipv4","tcp","udp")) {
                if (!p.has(when (kind) {
                    "ipv4" -> "ip.src";
                    "tcp" -> "tcp.stream";
                    else -> "udp.srcport"
                })) continue
                val source = Endpoint(p.num("ip.src"),if (kind == "ipv4") -1L else p.num("$kind.srcport"));
                val destination = Endpoint(p.num("ip.dst"),if (kind == "ipv4") -1L else p.num("$kind.dstport"))
                val pair = listOf(source.toString(),destination.toString()).sorted();
                val key = "$kind:" + if (kind == "tcp") p.num("tcp.stream").toString() else pair.joinToString("|")
                val c = grouped.getOrPut(key) {
                    Conversation(kind,source,destination,p.number,p.time)
                };
                val direction = if (source == c.a) 0 else 1
                c.packets[direction]++;
                c.bytes[direction] += p.length;
                c.end = p.time
            }
            val ordered = grouped.values.sortedWith(compareByDescending<Conversation> {
                it.totalBytes()
            }.thenByDescending {
                it.totalPackets()
            }.thenBy {
                listOf("ipv4","tcp","udp").indexOf(it.kind)
            }.thenBy {
                it.first
            })
            val result = mutableListOf("type,endpoint_a,endpoint_b,packets,bytes,packets_a_to_b,bytes_a_to_b,packets_b_to_a,bytes_b_to_a,start,duration");
            val origin = packets.first().time
            for (c in ordered) result.add("${c.kind},${c.a},${c.b},${c.totalPackets()},${c.totalBytes()},${c.packets[0]},${c.bytes[0]},${c.packets[1]},${c.bytes[1]},${seconds(c.start - origin)},${seconds(c.end - c.start)}")
            return result
        }
        fun endpoints(packets: List<Packet>): List<String> {
            val counts = mutableMapOf<Long,LongArray>()
            for (p in packets) if (p.has("ip.src")) for (side in 0..1) {
                val address = p.num(if (side == 0) "ip.src" else "ip.dst");
                val row = counts.getOrPut(address) {
                    LongArray(4)
                };
                row[side * 2]++;
                row[side * 2 + 1] += p.length
            }
            val ordered = counts.keys.sortedWith(compareByDescending<Long> {
                counts.getValue(it)[1] + counts.getValue(it)[3]
            }.thenByDescending {
                counts.getValue(it)[0] + counts.getValue(it)[2]
            }.thenBy {
                it
            })
            val result = mutableListOf("address,packets,bytes,tx_packets,tx_bytes,rx_packets,rx_bytes")
            for (address in ordered) {
                val row = counts.getValue(address);
                result.add("${LinkNetwork.ipv4(address)},${row[0] + row[2]},${row[1] + row[3]},${row[0]},${row[1]},${row[2]},${row[3]}")
            }
            return result
        }
    }
    data class Endpoint(val address: Long, val port: Long) {
        override fun toString() = LinkNetwork.ipv4(address) + if (port < 0) "" else ":$port"
    }
    class Previous(val ack: Long, val window: Long, val number: Int) {
        var count = 0
    }
    class Side(val name: String) {
        var isn = -1L;
        var mss = -1L;
        var ws = -1L;
        var base = -1L;
        var expected = -1L;
        var advanced = 0L;
        var packets = 0L;
        var payload = 0L
        val intervals = mutableSetOf<Pair<Long,Long>>();
        var previous: Previous? = null;
        val counts = LongArray(4)
    }
    class Stream(val number: Int, val client: Endpoint, val server: Endpoint, var state: String, p: Packet) {
        var syn = -1;
        var synAck = -1;
        var ack = -1;
        val clientSide = Side("client");
        val serverSide = Side("server");
        var closer: Side? = null
        val start = p.time;
        var end = p.time;
        var packets = 0L;
        var bytes = 0L;
        var finalAck = 0L;
        val history = mutableListOf("$state ${p.number}");
        val events = mutableListOf<String>()
        fun change(next: String, number: Int) {
            state = next;
            history.add("$next $number")
        }
        fun record(side: Side, p: Packet) {
            side.isn = p.num("tcp.seq_raw");
            side.mss = if (p.has("tcp.options.mss")) p.num("tcp.options.mss") else -1L;
            side.ws = if (p.has("tcp.options.wscale")) p.num("tcp.options.wscale") else -1L;
            if (side === clientSide) syn = p.number else synAck = p.number
        }
    }
    class Conversation(val kind: String, val a: Endpoint, val b: Endpoint, val first: Int, val start: Long) {
        var end = start;
        val packets = LongArray(2);
        val bytes = LongArray(2);
        fun totalBytes() = bytes.sum();
        fun totalPackets() = packets.sum()
    }
    val streams = mutableListOf<Stream>()
    fun track(p: Packet) {
        val source = Endpoint(p.num("ip.src"),p.num("tcp.srcport"));
        val destination = Endpoint(p.num("ip.dst"),p.num("tcp.dstport"))
        val syn = p.num("tcp.flags.syn") == 1L;
        val ackSet = p.num("tcp.flags.ack") == 1L;
        val fin = p.num("tcp.flags.fin") == 1L;
        val rst = p.num("tcp.flags.rst") == 1L
        val seq = p.num("tcp.seq_raw");
        val ack = if (ackSet) p.num("tcp.ack_raw") else 0L
        var found = streams.lastOrNull {
            (it.client == source && it.server == destination) || (it.client == destination && it.server == source)
        }
        if (found == null || (found.state in listOf("CLOSED","RESET") && syn && !ackSet)) {
            found = Stream(streams.size,if (syn && ackSet) destination else source,if (syn && ackSet) source else destination,if (syn) {
                if (ackSet) "SYN_RECEIVED" else "SYN_SENT"
            } else "ESTABLISHED",p)
            if (syn) found.record(if (ackSet) found.serverSide else found.clientSide,p);
            streams.add(found)
        }
        val stream = found;
        p["tcp.stream"] = stream.number
        val side = if (source == stream.client) stream.clientSide else stream.serverSide;
        val other = if (side === stream.clientSide) stream.serverSide else stream.clientSide
        if (side.base < 0) side.base = seq;
        if (ackSet && other.base < 0) other.base = ack
        val relative = (seq - side.base + 4294967296L) % 4294967296L;
        p["tcp.seq"] = relative
        if (ackSet) p["tcp.ack"] = (ack - other.base + 4294967296L) % 4294967296L
        val size = p.num("tcp.len") + (if (syn) 1 else 0) + (if (fin) 1 else 0);
        var mark = -1
        if (size >= 1) {
            if (side.expected >= 0 && relative != side.expected) mark = if (relative > side.expected) 2 else if (relative to size in side.intervals) 0 else if (p.time - side.advanced < 3000) 1 else 0
            side.intervals.add(relative to size);
            if (side.expected < 0 || relative + size > side.expected) {
                side.expected = relative + size;
                side.advanced = p.time
            }
        } else if (ackSet && !rst) {
            val previous = side.previous
            if (previous != null && ack == previous.ack && p.num("tcp.window") == previous.window) {
                mark = 3;
                previous.count++;
                p.duplicate = "[TCP Dup ACK ${previous.number}#${previous.count}] "
            }
        }
        if (ackSet && mark != 3) side.previous = Previous(ack,p.num("tcp.window"),p.number)
        if (mark >= 0) {
            p["tcp.analysis.${marks[mark]}"] = 0;
            side.counts[mark]++;
            stream.events.add("event ${p.number} ${side.name} ${marks[mark]} seq $relative len $size")
        }
        p["tcp.window.calc"] = p.num("tcp.window") * if (stream.clientSide.ws >= 0 && stream.serverSide.ws >= 0 && !syn) 1L shl side.ws.toInt() else 1L
        if (rst) {
            if (stream.state !in listOf("CLOSED","RESET")) stream.change("RESET",p.number)
        }
        else if (stream.state == "SYN_SENT" && side === stream.serverSide && syn && ackSet && ack == (stream.clientSide.isn + 1) % 4294967296L) {
            stream.change("SYN_RECEIVED",p.number);
            stream.record(side,p)
        }
        else if (stream.state == "SYN_RECEIVED" && side === stream.clientSide && ackSet && !syn && ack == (stream.serverSide.isn + 1) % 4294967296L) {
            stream.change("ESTABLISHED",p.number);
            stream.ack = p.number
        }
        else if (stream.state == "ESTABLISHED" && fin) {
            stream.change("FIN_WAIT",p.number);
            stream.closer = side
        }
        else if (stream.state == "FIN_WAIT" && fin && side !== stream.closer) {
            stream.change("CLOSING",p.number);
            stream.finalAck = (seq + p.num("tcp.len") + 1) % 4294967296L
        }
        else if (stream.state == "CLOSING" && side === stream.closer && ackSet && ack == stream.finalAck) stream.change("CLOSED",p.number)
        side.packets++;
        side.payload += p.num("tcp.len");
        stream.packets++;
        stream.bytes += p.length;
        stream.end = p.time
    }
}
