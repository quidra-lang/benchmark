require_relative "link_network"

module DnsApp
  TYPE_NAMES = { 1 => "A", 2 => "NS", 5 => "CNAME", 6 => "SOA", 12 => "PTR",
                 15 => "MX", 16 => "TXT", 28 => "AAAA" }.freeze
  RCODE_NAMES = %w[NoError FormErr ServFail NXDomain NotImp Refused].freeze
  COUNT_FIELDS = %w[dns.count.queries dns.count.answers dns.count.auth_rr dns.count.add_rr].freeze
  SECTION_FIELDS = %w[dns.answer dns.authority dns.additional].freeze

  module_function

  def type_name(type) = TYPE_NAMES.fetch(type) { "TYPE#{type}" }
  def class_name(value) = value == 1 ? "IN" : "CLASS#{value}"
  def rcode_name(value) = RCODE_NAMES[value] || "RCODE#{value}"

  def label_text(label)
    label.map do |byte|
      byte.between?(33, 126) && ![46, 92].include?(byte) ? byte.chr : format("\\%03d", byte)
    end.join
  end

  def ipv6_notation(address)
    groups = address.each_slice(2).map { |high, low| high * 256 + low }
    best_start = nil
    best_length = 1
    index = 0
    while index < groups.length
      unless groups[index].zero?
        index += 1
        next
      end
      finish = index
      finish += 1 while finish < groups.length && groups[finish].zero?
      if finish - index > best_length
        best_start, best_length = index, finish - index
      end
      index = finish
    end
    texts = groups.map { |group| group.to_s(16) }
    return texts.join(":") if best_start.nil?

    texts[0, best_start].join(":") + "::" + texts[(best_start + best_length)..].join(":")
  end

  class Reader
    def initialize(message)
      @message = message
    end

    def chunk(position, size)
      raise Malformed, "dns: truncated" if position + size > @message.length

      @message[position, size]
    end

    def byte(position) = chunk(position, 1)[0]
    def integer(position, size) = LinkNetwork.read_int(chunk(position, size), 0, size)

    def name(position)
      labels = []
      pointers = 0
      after = nil
      loop do
        length = byte(position)
        if length.zero?
          after ||= position + 1
          break
        elsif length >= 192
          low = byte(position + 1)
          after ||= position + 2
          pointers += 1
          raise Malformed, "dns: compression loop" if pointers > 16

          target = (length - 192) * 256 + low
          raise Malformed, "dns: pointer out of range" if target >= @message.length

          position = target
        elsif length >= 64
          raise Malformed, "dns: bad label type"
        else
          labels << DnsApp.label_text(chunk(position + 1, length))
          position += length + 1
        end
      end
      [labels.empty? ? "<root>" : labels.join("."), after]
    end

    def rdata(type, start, length)
      case type
      when 1 then [LinkNetwork.ipv4_notation(integer(start, 4)), start + 4]
      when 28 then [DnsApp.ipv6_notation(chunk(start, 16)), start + 16]
      when 2, 5, 12 then name(start)
      when 15
        preference = integer(start, 2)
        exchange, finish = name(start + 2)
        ["#{preference} #{exchange}", finish]
      when 6
        primary, position = name(start)
        mailbox, position = name(position)
        parts = [primary, mailbox]
        5.times do
          parts << integer(position, 4).to_s
          position += 4
        end
        [parts.join(" "), position]
      else ["#{length} bytes", start + length]
      end
    end

    def record(position, section, layer)
      owner, position = name(position)
      fixed = chunk(position, 10)
      type = LinkNetwork.read_int(fixed, 0, 2)
      record_class = LinkNetwork.read_int(fixed, 2, 2)
      ttl = LinkNetwork.read_int(fixed, 4, 4)
      length = LinkNetwork.read_int(fixed, 8, 2)
      start = position + 10
      chunk(start, length)
      text, finish = rdata(type, start, length)
      raise Malformed, "dns: bad rdata length" unless finish == start + length

      layer.add(section, "#{owner} #{DnsApp.type_name(type)} #{DnsApp.class_name(record_class)} #{ttl} #{text}")
      layer.add("dns.a", integer(start, 4)) if section == "dns.answer" && type == 1
      start + length
    end
  end

  def dissect_dns(message)
    reader = Reader.new(message)
    header = reader.chunk(0, 12)
    flags = LinkNetwork.read_int(header, 2, 2)
    counts = (4...12).step(2).map { |index| LinkNetwork.read_int(header, index, 2) }
    layer = Layer.new
    layer.set("dns.id", LinkNetwork.read_int(header, 0, 2))
    layer.set("dns.flags", flags)
    layer.set("dns.flags.response", (flags >> 15) & 1)
    layer.set("dns.flags.opcode", (flags >> 11) & 15)
    layer.set("dns.flags.rcode", flags & 15)
    COUNT_FIELDS.zip(counts) { |field, count| layer.set(field, count) }
    position = 12
    counts[0].times do
      name, position = reader.name(position)
      tail = reader.chunk(position, 4)
      layer.add("dns.qry.name", name)
      layer.add("dns.qry.type", LinkNetwork.read_int(tail, 0, 2))
      position += 4
    end
    SECTION_FIELDS.zip(counts.drop(1)) do |section, count|
      count.times { position = reader.record(position, section, layer) }
    end
    layer
  end
end
