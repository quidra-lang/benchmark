import java.nio.file.Files
import java.nio.file.Path
import java.nio.charset.StandardCharsets
import java.util.Locale
class Packet(val number: Int, val time: Long, val length: Int) {
    var bytes = intArrayOf();
    var data = intArrayOf();
    var reason = "";
    var duplicate = ""
    val layers = mutableListOf<String>();
    var answers = mutableListOf<String>();
    var fields = mutableMapOf<String,MutableList<Any>>()
    fun normalized(value: Any): Any = if (value is Number) value.toLong() else value
    operator fun set(name: String, value: Any) {
        fields[name] = mutableListOf(normalized(value))
    }
    fun append(name: String, value: Any) {
        fields.getOrPut(name) {
            mutableListOf()
        }.add(normalized(value))
    }
    fun has(name: String) = fields.containsKey(name)
    fun num(name: String) = fields.getValue(name).first() as Long
    fun text(name: String) = fields.getValue(name).first() as String
    fun values(name: String): List<Any> = fields[name] ?: emptyList()
}
val fields = listOf(
listOf("frame.number","integer"),
listOf("frame.time","integer"),
listOf("frame.len","integer"),
listOf("frame.protocols","string"),
listOf("frame.malformed","string"),
listOf("frame.bad_checksum","presence"),
listOf("eth.dst","mac"),
listOf("eth.src","mac"),
listOf("eth.type","hex4"),
listOf("arp.opcode","integer"),
listOf("arp.src.hw","mac"),
listOf("arp.src.ip","ipv4"),
listOf("arp.dst.hw","mac"),
listOf("arp.dst.ip","ipv4"),
listOf("ip.hdr_len","integer"),
listOf("ip.tos","hex2"),
listOf("ip.len","integer"),
listOf("ip.id","hex4"),
listOf("ip.flags.df","integer"),
listOf("ip.flags.mf","integer"),
listOf("ip.frag_offset","integer"),
listOf("ip.ttl","integer"),
listOf("ip.proto","integer"),
listOf("ip.checksum","hex4"),
listOf("ip.checksum.status","string"),
listOf("ip.src","ipv4"),
listOf("ip.dst","ipv4"),
listOf("ip.fragment","presence"),
listOf("icmp.type","integer"),
listOf("icmp.code","integer"),
listOf("icmp.checksum","hex4"),
listOf("icmp.checksum.status","string"),
listOf("icmp.id","integer"),
listOf("icmp.seq","integer"),
listOf("udp.srcport","integer"),
listOf("udp.dstport","integer"),
listOf("udp.length","integer"),
listOf("udp.checksum","hex4"),
listOf("udp.checksum.status","string"),
listOf("tcp.srcport","integer"),
listOf("tcp.dstport","integer"),
listOf("tcp.stream","integer"),
listOf("tcp.seq","integer"),
listOf("tcp.seq_raw","integer"),
listOf("tcp.ack","integer"),
listOf("tcp.ack_raw","integer"),
listOf("tcp.hdr_len","integer"),
listOf("tcp.flags","hex2"),
listOf("tcp.flags.fin","integer"),
listOf("tcp.flags.syn","integer"),
listOf("tcp.flags.rst","integer"),
listOf("tcp.flags.psh","integer"),
listOf("tcp.flags.ack","integer"),
listOf("tcp.flags.urg","integer"),
listOf("tcp.window","integer"),
listOf("tcp.window.calc","integer"),
listOf("tcp.checksum","hex4"),
listOf("tcp.checksum.status","string"),
listOf("tcp.urgent","integer"),
listOf("tcp.option","string"),
listOf("tcp.options.mss","integer"),
listOf("tcp.options.wscale","integer"),
listOf("tcp.options.malformed","presence"),
listOf("tcp.len","integer"),
listOf("tcp.analysis.retransmission","presence"),
listOf("tcp.analysis.out_of_order","presence"),
listOf("tcp.analysis.lost_segment","presence"),
listOf("tcp.analysis.duplicate_ack","presence"),
listOf("dns.id","hex4"),
listOf("dns.flags","hex4"),
listOf("dns.flags.response","integer"),
listOf("dns.flags.opcode","integer"),
listOf("dns.flags.rcode","integer"),
listOf("dns.count.queries","integer"),
listOf("dns.count.answers","integer"),
listOf("dns.count.auth_rr","integer"),
listOf("dns.count.add_rr","integer"),
listOf("dns.qry.name","string"),
listOf("dns.qry.type","integer"),
listOf("dns.answer","string"),
listOf("dns.authority","string"),
listOf("dns.additional","string"),
listOf("dns.a","ipv4"),
listOf("data.len","integer")
)
val aliases = listOf(listOf("eth.addr","mac","eth.dst","eth.src"),listOf("ip.addr","ipv4","ip.src",
    "ip.dst"),listOf("udp.port","integer","udp.srcport","udp.dstport"),listOf("tcp.port","integer",
    "tcp.srcport","tcp.dstport"))
val protocols = listOf("eth","arp","ip","icmp","udp","tcp","dns","data")
val flagNames = listOf("FIN","SYN","RST","PSH","ACK","URG","ECE","CWR")
val checksums = listOf("ip","icmp","udp","tcp");
val checksumNames = listOf("IPv4","ICMP","UDP","TCP")
fun type(name: String): String? = fields.firstOrNull {
    it[0] == name
}
?.get(1) ?: aliases.firstOrNull {
    it[0] == name
}
?.get(1) ?: if (name in protocols) "presence" else null
fun values(p: Packet, name: String): List<Any> {
    val alias = aliases.firstOrNull {
        it[0] == name
    };
    return if (alias == null) p.values(name) else p.values(alias[2]) + p.values(alias[3])
}
fun notation(type: String, value: Any): String {
    if (type == "string") return value as String
    val n = value as Long
    return when (type) {
        "hex2" -> String.format(Locale.ROOT,"0x%02x",n);
        "hex4" -> String.format(Locale.ROOT,"0x%04x",n);
        "ipv4" -> LinkNetwork.ipv4(n);
        "mac" -> LinkNetwork.mac(n);
        else -> n.toString()
    }
}
fun shown(p: Packet, name: String) = notation(type(name)!!,p.values(name).first())
fun seconds(time: Long) = "${time / 1000000}." + String.format(Locale.ROOT,"%06d",time % 1000000)
fun optional(value: Long) = if (value < 0) "-" else value.toString()
fun dissect(p: Packet, origin: Long) {
    if (p.reason.isEmpty()) {
        var layer: String? = "eth";
        var payload = p.bytes
        while (layer != null) {
            p.layers.add(layer);
            val temporary = Packet(p.number,p.time,p.length);
            temporary.fields = p.fields.toMutableMap()
            try {
                val remaining = when (layer) {
                    "eth" -> LinkNetwork.ethernet(temporary,payload);
                    "arp" -> LinkNetwork.arp(temporary,payload);
                    "ip" -> LinkNetwork.ipv4(temporary,payload);
                    "icmp" -> Transport.icmp(temporary,payload);
                    "udp" -> Transport.udp(temporary,payload);
                    "tcp" -> Transport.tcp(temporary,payload);
                    "dns" -> DnsApp.dissect(temporary,payload);
                    else -> intArrayOf()
                }
                p.fields = temporary.fields;
                p.answers = temporary.answers
                val next = when {
                    layer == "eth" -> when (p.num("eth.type")) {
                        2054L -> "arp";
                        2048L -> "ip";
                        else -> null
                    }
                    layer == "ip" && !p.has("ip.fragment") -> when (p.num("ip.proto")) {
                        1L -> "icmp";
                        17L -> "udp";
                        6L -> "tcp";
                        else -> null
                    }
                    layer == "udp" && (p.num("udp.srcport") == 53L || p.num("udp.dstport") == 53L) -> "dns"
                    else -> null
                }
                payload = remaining;
                layer = next
            } catch (error: LinkNetwork.Bad) {
                p.reason = error.message!!;
                payload = intArrayOf();
                break
            }
        }
        if (p.reason.isEmpty() && payload.isNotEmpty()) {
            p.data = payload;
            p.layers.add("data");
            p["data.len"] = payload.size
        }
    }
    p["frame.number"] = p.number;
    p["frame.time"] = p.time - origin;
    p["frame.len"] = p.length
    if (p.layers.isNotEmpty()) p["frame.protocols"] = p.layers.joinToString(":")
    if (p.reason.isNotEmpty()) p["frame.malformed"] = p.reason
    if (checksums.any {
        p.has("$it.checksum.status") && p.text("$it.checksum.status") == "bad"
    }) p["frame.bad_checksum"] = 0
}
fun summary(p: Packet): String {
    val source = if (p.has("ip.src")) shown(p,"ip.src") else if (p.has("eth.src")) shown(p,"eth.src") else "-"
    val destination = if (p.has("ip.src")) shown(p,"ip.dst") else if (p.has("eth.src")) shown(p,"eth.dst") else "-"
    val last = p.layers.lastOrNull {
        it != "data"
    }
    ?: "dump"
    val protocol = when (last) {
        "eth" -> "ETH";
        "arp" -> "ARP";
        "ip" -> "IPv4";
        "icmp" -> "ICMP";
        "udp" -> "UDP";
        "tcp" -> "TCP";
        "dns" -> "DNS";
        else -> "DUMP"
    }
    var info = p.reason
    if (info.isEmpty()) info = when (last) {
        "eth" -> "EtherType ${shown(p,"eth.type")}"
        "arp" -> when (p.num("arp.opcode")) {
            1L -> "Who has ${shown(p,"arp.dst.ip")}? Tell ${shown(p,"arp.src.ip")}";
            2L -> "${shown(p,"arp.src.ip")} is at ${shown(p,"arp.src.hw")}";
            else -> "Opcode ${p.num("arp.opcode")}"
        }
        "ip" -> if (p.has("ip.fragment")) "Fragment id=${shown(p,"ip.id")} off=${p.num("ip.frag_offset")}" + if (p.num("ip.flags.mf") == 1L) " MF" else "" else "Protocol ${p.num("ip.proto")}"
        "icmp" -> if (p.num("icmp.type") in listOf(0L,8L)) "${if (p.num("icmp.type") == 8L) "Echo request" else "Echo reply"} id=${p.num("icmp.id")} seq=${p.num("icmp.seq")}" else "Type ${p.num("icmp.type")} code ${p.num("icmp.code")}"
        "udp" -> "${p.num("udp.srcport")} -> ${p.num("udp.dstport")} Len=${p.num("udp.length") - 8}"
        "tcp" -> {
            var mark = p.duplicate;
            val labels = listOf("[TCP Retransmission] ","[TCP Out-Of-Order] ","[TCP Previous segment not captured] ")
            for (i in 0..2) if (p.has("tcp.analysis.${Flows.marks[i]}")) mark = labels[i]
            val flags = flagNames.filterIndexed {
                i, _ -> (p.num("tcp.flags") and (1L shl i)) != 0L
            }
            var text = "$mark${p.num("tcp.srcport")} -> ${p.num("tcp.dstport")} [${if (flags.isEmpty()) "<None>" else flags.joinToString(", ")}] Seq=${p.num("tcp.seq")}"
            if (p.num("tcp.flags.ack") == 1L) text += " Ack=${p.num("tcp.ack")}"
            text += " Win=${p.num("tcp.window.calc")} Len=${p.num("tcp.len")}"
            for (value in p.values("tcp.option")) {
                val option = value as String;
                val parts = option.split(' ');
                text += when (parts[0]) {
                    "MSS" -> " MSS=${parts[1]}";
                    "WS" -> " WS=${1L shl parts[1].toInt()}";
                    "SACK_PERM" -> " SACK_PERM";
                    "TS" -> " TSval=${parts[1]} TSecr=${parts[2]}";
                    else -> ""
                }
            }
            text
        }
        "dns" -> {
            var text = "${if (p.num("dns.flags.response") == 1L) "Response" else "Query"} ${shown(p,"dns.id")}"
            if (p.num("dns.flags.rcode") != 0L) text += " ${DnsApp.rcode(p.num("dns.flags.rcode"))}"
            val names = p.values("dns.qry.name");
            val types = p.values("dns.qry.type")
            for (i in names.indices) text += " ${DnsApp.type(types[i] as Long)} ${names[i]}"
            p.answers.forEach {
                text += " $it"
            };
            text
        }
        else -> ""
    }
    if (p.has("tcp.options.malformed")) info += " [bad TCP options]"
    for (i in checksums.indices) if (p.has("${checksums[i]}.checksum.status") && p.text("${checksums[i]}.checksum.status") == "bad") info += " [bad ${checksumNames[i]} checksum]"
    return "${p.number} ${seconds(p.num("frame.time"))} $source -> $destination $protocol ${p.length} $info"
}
data class Token(val kind: String, val text: String, val column: Int)
class FilterError(message: String): RuntimeException(message)
fun word(c: Char) = c in 'A'..'Z' || c in 'a'..'z' || c in '0'..'9' || c in "._:"
fun tokenize(expression: String): List<Token> {
    val result = mutableListOf<Token>();
    var i = 0
    while (i < expression.length) {
        val c = expression[i];
        val start = i
        if (c == ' ') {
            i++;
            continue
        }
        val pair = if (i + 1 < expression.length) expression.substring(i,i + 2) else ""
        if (pair in listOf("==","!=","<=",">=","&&","||")) {
            result.add(Token(pair,pair,i + 1));
            i += 2
        }
        else if (c in "()!<>") {
            result.add(Token(c.toString(),c.toString(),i + 1));
            i++
        }
        else if (c == '"') {
            val end = expression.indexOf('"',i + 1);
            if (end < 0) throw FilterError("unterminated string at column ${i + 1}");
            result.add(Token("string",expression.substring(i,end + 1),i + 1));
            i = end + 1
        }
        else if (word(c)) {
            while (i < expression.length && word(expression[i])) i++;
            val text = expression.substring(start,i);
            val kind = when (text) {
                "and" -> "&&";
                "or" -> "||";
                "not" -> "!";
                else -> "word"
            };
            result.add(Token(kind,text,start + 1))
        }
        else throw FilterError("invalid character '$c' at column ${i + 1}")
    }
    return result
}
fun convert(token: Token, type: String): Any? {
    val value = token.text
    if (type == "string") return if (token.kind == "string") value.substring(1,value.length - 1) else null
    if (token.kind != "word") return null
    if (type in listOf("integer","hex2","hex4")) {
        if (Regex("[0-9]{1,15}").matches(value)) return value.toLong();
        if (Regex("0x[0-9a-fA-F]{1,12}").matches(value)) return value.substring(2).toLong(16)
    }
    else if (type == "ipv4" || type == "mac") {
        val mac = type == "mac";
        val parts = value.split(if (mac) ':' else '.');
        if (parts.size != if (mac) 6 else 4) return null;
        var result = 0L;
        for (part in parts) {
            if (!Regex(if (mac) "[0-9a-fA-F]{2}" else "[0-9]{1,3}").matches(part)) return null;
            val n = part.toInt(if (mac) 16 else 10);
            if (n > 255) return null;
            result = result * 256 + n
        };
        return result
    }
    return null
}
class Parser(expression: String) {
    val tokens = tokenize(expression);
    var position = 0
    fun take(): Token {
        if (position >= tokens.size) throw FilterError("unexpected end of filter");
        return tokens[position++]
    }
    fun next(kind: String) = position < tokens.size && tokens[position].kind == kind
    fun unexpected(token: Token) = FilterError("unexpected '${token.text}' at column ${token.column}")
    fun expression(): (Packet) -> Boolean {
        var result = product();
        while (next("||")) {
            take();
            val left = result;
            val right = product();
            result = {
                left(it) || right(it)
            }
        };
        return result
    }
    fun product(): (Packet) -> Boolean {
        var result = negation();
        while (next("&&")) {
            take();
            val left = result;
            val right = negation();
            result = {
                left(it) && right(it)
            }
        };
        return result
    }
    fun negation(): (Packet) -> Boolean {
        if (next("!")) {
            take();
            val child = negation();
            return {
                !child(it)
            }
        }
        val token = take()
        if (token.kind == "(") {
            val result = expression();
            val closing = take();
            if (closing.kind != ")") throw unexpected(closing);
            return result
        }
        if (token.kind != "word") throw unexpected(token)
        val name = token.text;
        val fieldType = type(name) ?: throw FilterError("unknown field $name")
        if (position >= tokens.size || tokens[position].kind !in listOf("==","!=","<",">","<=",">=")) return {
            if (name in protocols) name in it.layers else values(it,name).isNotEmpty()
        }
        val operator = take().text
        if (fieldType == "presence" || fieldType == "string" && operator !in listOf("==","!=")) throw FilterError("operator $operator not allowed for $name")
        val valueToken = take();
        if (valueToken.kind !in listOf("word","string")) throw unexpected(valueToken)
        val target = convert(valueToken,fieldType) ?: throw FilterError("invalid value ${valueToken.text} for $name")
        return {
            p ->
            val actual = values(p,name)
            fun matches(value: Any): Boolean {
                val c = if (fieldType == "string") (value as String).compareTo(target as String) else (value as Long).compareTo(target as Long);
                return when (operator) {
                    "==" -> c == 0;
                    "!=" -> c != 0;
                    "<" -> c < 0;
                    ">" -> c > 0;
                    "<=" -> c <= 0;
                    else -> c >= 0
                }
            }
            actual.isNotEmpty() && if (operator == "!=") actual.all {
                matches(it)
            } else actual.any {
                matches(it)
            }
        }
    }
    fun parse(): (Packet) -> Boolean {
        val result = expression();
        if (position < tokens.size) throw unexpected(tokens[position]);
        return result
    }
}
fun details(packets: List<Packet>, number: Int): List<String> {
    if (number < 1 || number > packets.size) return listOf("packet $number not found")
    val result = mutableListOf("packet $number");
    val p = packets[number - 1]
    for (layer in listOf("frame") + p.layers) {
        result.add(layer);
        for (field in fields) if (field[0].startsWith("$layer.")) for (value in p.values(field[0])) result.add("  ${field[0]}" + if (field[1] == "presence") "" else " = ${notation(field[1],value)}");
        if (layer == "data") Hexdump.lines(p.data).forEach {
            result.add("  $it")
        }
    }
    return result
}
fun stats(packets: List<Packet>): List<String> {
    val result = mutableListOf("packets ${packets.size}","bytes ${packets.sumOf { it.length.toLong() }}",
        "duration ${seconds(packets.last().time - packets.first().time)}","hierarchy")
    for (item in listOf("eth","  arp","  ip","    icmp","    udp","      dns","    tcp")) {
        val selected = packets.filter {
            item.trim() in it.layers
        };
        result.add("$item ${selected.size} ${selected.sumOf { it.length.toLong() }}")
    }
    result.add("checksums")
    for (layer in checksums) {
        val values = packets.filter {
            it.has("$layer.checksum.status")
        }.map {
            it.text("$layer.checksum.status")
        };
        result.add("$layer good ${values.count { it == "good" }} bad ${values.count { it == "bad" }}" + if (layer == "udp") " none ${values.count { it == "none" }}" else "")
    }
    result.add("malformed")
    for (layer in listOf("dump","eth","arp","ip","icmp","udp","tcp","dns")) result.add("$layer ${packets.count { it.reason.isNotEmpty() && (it.layers.lastOrNull() ?: "dump") == layer }}")
    result.add("tcp analysis");
    for (mark in Flows.marks) result.add("$mark ${packets.count { it.has("tcp.analysis.$mark") }}")
    val pending = mutableListOf<Packet>();
    val responseTimes = mutableListOf<Long>();
    var queries = 0;
    var responses = 0;
    val rcodes = IntArray(16);
    val names = mutableMapOf<String,Int>()
    for (p in packets) if (p.has("dns.id")) {
        if (p.num("dns.flags.response") == 0L) {
            queries++;
            pending.add(p);
            for (value in p.values("dns.qry.name")) {
                val name = value as String;
                names[name] = names.getOrDefault(name,0) + 1
            }
        }
        else {
            responses++;
            rcodes[p.num("dns.flags.rcode").toInt()]++;
            val index = pending.indexOfFirst {
                q -> q.num("dns.id") == p.num("dns.id") && q.num("ip.src") == p.num("ip.dst") && q.num("ip.dst") == p.num("ip.src") && q.num("udp.srcport") == p.num("udp.dstport") && q.num("udp.dstport") == p.num("udp.srcport")
            };
            if (index >= 0) {
                val q = pending.removeAt(index);
                responseTimes.add(p.time - q.time)
            }
        }
    }
    result.addAll(listOf("dns","queries $queries","responses $responses","transactions ${responseTimes.size}","unanswered ${pending.size}"))
    result.add(if (responseTimes.isEmpty()) "response_time -" else "response_time min ${seconds(responseTimes.min())} max ${seconds(responseTimes.max())}")
    for (i in rcodes.indices) if (rcodes[i] > 0) result.add("rcode ${DnsApp.rcode(i.toLong())} ${rcodes[i]}")
    result.add("names");
    for (name in names.keys.sortedWith(compareByDescending<String> {
        names.getValue(it)
    }.thenBy {
        it
    })) result.add("$name ${names.getValue(name)}")
    return result
}
fun streamLines(flows: Flows, packets: List<Packet>): List<String> {
    val result = mutableListOf<String>();
    val origin = packets.first().time
    for (stream in flows.streams) {
        if (result.isNotEmpty()) result.add("")
        result.add("stream ${stream.number} ${stream.client} -> ${stream.server}")
        result.add("packets ${stream.packets} bytes ${stream.bytes} start ${seconds(stream.start - origin)} duration ${seconds(stream.end - stream.start)}")
        result.add("states ${stream.history.joinToString(", ")}")
        result.add("handshake syn ${optional(stream.syn.toLong())} syn_ack ${optional(stream.synAck.toLong())} ack ${optional(stream.ack.toLong())} rtt ${if (stream.syn >= 0 && stream.ack >= 0) seconds(packets[stream.ack - 1].time - packets[stream.syn - 1].time) else "-"}")
        result.add("options client mss ${optional(stream.clientSide.mss)} wscale ${optional(stream.clientSide.ws)} server mss ${optional(stream.serverSide.mss)} wscale ${optional(stream.serverSide.ws)}")
        for (side in listOf(stream.clientSide,stream.serverSide)) result.add("${side.name} packets ${side.packets} payload ${side.payload}" + Flows.marks.indices.joinToString("") {
            " ${Flows.marks[it]} ${side.counts[it]}"
        })
        result.addAll(stream.events)
    }
    return result
}
fun write(name: String, lines: List<String>) {
    Files.writeString(Path.of("output",name),if (lines.isEmpty()) "" else lines.joinToString("\n") + "\n",StandardCharsets.US_ASCII)
}
fun main() {
    val packets = Hexdump.read();
    val origin = packets.first().time;
    val flows = Flows()
    for (p in packets) {
        dissect(p,origin);
        if (p.has("tcp.srcport")) flows.track(p)
    }
    val summaries = packets.map {
        summary(it)
    };
    val summaryOutput = summaries.toMutableList();
    val detailOutput = mutableListOf<String>();
    var firstDetail = true
    for (line in Files.readAllLines(Path.of("input/filters.txt"),StandardCharsets.US_ASCII)) {
        if (line.startsWith("FILTER ")) {
            val expression = line.substring(7);
            summaryOutput.add("");
            summaryOutput.add("filter $expression");
            try {
                val filter = Parser(expression).parse();
                var matched = 0;
                for (i in packets.indices) if (filter(packets[i])) {
                    matched++;
                    summaryOutput.add(summaries[i])
                };
                summaryOutput.add("matched $matched of ${packets.size}")
            } catch (error: FilterError) {
                summaryOutput.add("error: ${error.message}")
            }
        }
        else if (line.startsWith("DETAIL ")) {
            if (!firstDetail) detailOutput.add("");
            firstDetail = false;
            detailOutput.addAll(details(packets,line.substring(7).toInt()))
        }
    }
    Files.createDirectories(Path.of("output"));
    write("summary.txt",summaryOutput);
    write("details.txt",detailOutput);
    write("conversations.csv",Flows.conversations(packets));
    write("endpoints.csv",Flows.endpoints(packets));
    write("protocol_stats.txt",stats(packets));
    write("tcp_streams.txt",streamLines(flows,packets))
}
