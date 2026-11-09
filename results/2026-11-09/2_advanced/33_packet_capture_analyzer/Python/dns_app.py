from link_network import Layer, Malformed, ipv4_notation, read_int


DNS_HEADER_LENGTH = 12
QUESTION_TAIL_LENGTH = 4
RECORD_FIXED_LENGTH = 10
MAX_POINTERS = 16
TYPE_NAMES = {1: "A", 2: "NS", 5: "CNAME", 6: "SOA", 12: "PTR", 15: "MX", 16: "TXT", 28: "AAAA"}
NAME_TYPES = (2, 5, 12)
RCODE_NAMES = ("NoError", "FormErr", "ServFail", "NXDomain", "NotImp", "Refused")
COUNT_FIELDS = ("dns.count.queries", "dns.count.answers", "dns.count.auth_rr", "dns.count.add_rr")
SECTION_FIELDS = ("dns.answer", "dns.authority", "dns.additional")


def type_name(record_type):
    return TYPE_NAMES.get(record_type, f"TYPE{record_type}")


def class_name(record_class):
    return "IN" if record_class == 1 else f"CLASS{record_class}"


def rcode_name(rcode):
    return RCODE_NAMES[rcode] if rcode < len(RCODE_NAMES) else f"RCODE{rcode}"


def label_text(label):
    characters = []
    for byte in label:
        if 33 <= byte <= 126 and byte not in (46, 92):
            characters.append(chr(byte))
        else:
            characters.append(f"\\{byte:03d}")
    return "".join(characters)


def ipv6_notation(address):
    groups = [read_int(address, index, 2) for index in range(0, 16, 2)]
    best_start = -1
    best_length = 1
    index = 0
    while index < len(groups):
        if groups[index] != 0:
            index += 1
            continue
        end = index
        while end < len(groups) and groups[end] == 0:
            end += 1
        if end - index > best_length:
            best_start = index
            best_length = end - index
        index = end
    texts = [f"{group:x}" for group in groups]
    if best_start < 0:
        return ":".join(texts)
    left = ":".join(texts[:best_start])
    right = ":".join(texts[best_start + best_length:])
    return left + "::" + right


class DnsReader:
    def __init__(self, message):
        self.message = message

    def chunk(self, position, size):
        if position + size > len(self.message):
            raise Malformed("dns: truncated")
        return self.message[position:position + size]

    def byte(self, position):
        return self.chunk(position, 1)[0]

    def integer(self, position, size):
        return read_int(self.chunk(position, size), 0, size)

    def name(self, position):
        labels = []
        pointers = 0
        after = None
        while True:
            length = self.byte(position)
            if length == 0:
                if after is None:
                    after = position + 1
                break
            if length >= 192:
                low = self.byte(position + 1)
                if after is None:
                    after = position + 2
                pointers += 1
                if pointers > MAX_POINTERS:
                    raise Malformed("dns: compression loop")
                target = (length - 192) * 256 + low
                if target >= len(self.message):
                    raise Malformed("dns: pointer out of range")
                position = target
            elif length >= 64:
                raise Malformed("dns: bad label type")
            else:
                labels.append(label_text(self.chunk(position + 1, length)))
                position += length + 1
        notation = ".".join(labels) if labels else "<root>"
        return notation, after

    def rdata(self, record_type, start, length):
        if record_type == 1:
            return ipv4_notation(self.integer(start, 4)), start + 4
        if record_type == 28:
            return ipv6_notation(self.chunk(start, 16)), start + 16
        if record_type in NAME_TYPES:
            return self.name(start)
        if record_type == 15:
            preference = self.integer(start, 2)
            exchange, end = self.name(start + 2)
            return f"{preference} {exchange}", end
        if record_type == 6:
            primary, position = self.name(start)
            mailbox, position = self.name(position)
            parts = [primary, mailbox]
            for _ in range(5):
                parts.append(str(self.integer(position, 4)))
                position += 4
            return " ".join(parts), position
        return f"{length} bytes", start + length

    def record(self, position, section, layer):
        name, position = self.name(position)
        fixed = self.chunk(position, RECORD_FIXED_LENGTH)
        record_type = read_int(fixed, 0, 2)
        record_class = read_int(fixed, 2, 2)
        ttl = read_int(fixed, 4, 4)
        length = read_int(fixed, 8, 2)
        start = position + RECORD_FIXED_LENGTH
        if start + length > len(self.message):
            raise Malformed("dns: truncated")
        rdata, end = self.rdata(record_type, start, length)
        if end != start + length:
            raise Malformed("dns: bad rdata length")
        layer.add(section, f"{name} {type_name(record_type)} {class_name(record_class)} {ttl} {rdata}")
        if section == "dns.answer" and record_type == 1:
            layer.add("dns.a", read_int(self.message, start, 4))
        return start + length


def dissect_dns(message):
    reader = DnsReader(message)
    header = reader.chunk(0, DNS_HEADER_LENGTH)
    flags = read_int(header, 2, 2)
    counts = [read_int(header, index, 2) for index in range(4, DNS_HEADER_LENGTH, 2)]
    layer = Layer()
    layer.set("dns.id", read_int(header, 0, 2))
    layer.set("dns.flags", flags)
    layer.set("dns.flags.response", flags // 32768 % 2)
    layer.set("dns.flags.opcode", flags // 2048 % 16)
    layer.set("dns.flags.rcode", flags % 16)
    for name, count in zip(COUNT_FIELDS, counts):
        layer.set(name, count)
    position = DNS_HEADER_LENGTH
    for _ in range(counts[0]):
        name, position = reader.name(position)
        tail = reader.chunk(position, QUESTION_TAIL_LENGTH)
        layer.add("dns.qry.name", name)
        layer.add("dns.qry.type", read_int(tail, 0, 2))
        position += QUESTION_TAIL_LENGTH
    for section, count in zip(SECTION_FIELDS, counts[1:]):
        for _ in range(count):
            position = reader.record(position, section, layer)
    return layer
