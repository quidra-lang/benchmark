require_relative "link_network"

module Transport
  FLAG_FIELDS = %w[fin syn rst psh ack urg].freeze
  OPTION_LENGTHS = { 2 => [4], 3 => [3], 4 => [2], 5 => [10, 18, 26, 34], 8 => [10] }.freeze

  module_function

  def pseudo_header(source, destination, protocol, length)
    [source, destination].flat_map do |address|
      3.downto(0).map { |shift| (address >> (shift * 8)) & 255 }
    end + [0, protocol, length / 256, length % 256]
  end

  def dissect_icmp(message)
    raise Malformed, "icmp: truncated" if message.length < 8

    layer = Layer.new
    type = message[0]
    layer.set("icmp.type", type)
    layer.set("icmp.code", message[1])
    layer.set("icmp.checksum", LinkNetwork.read_int(message, 2, 2))
    layer.set("icmp.checksum.status", LinkNetwork.checksum_status(message))
    if [0, 8].include?(type)
      layer.set("icmp.id", LinkNetwork.read_int(message, 4, 2))
      layer.set("icmp.seq", LinkNetwork.read_int(message, 6, 2))
    end
    layer.remaining = message[8..]
    layer
  end

  def dissect_udp(datagram, source, destination)
    raise Malformed, "udp: truncated" if datagram.length < 8

    length = LinkNetwork.read_int(datagram, 4, 2)
    raise Malformed, "udp: bad length #{length}" if length < 8 || length > datagram.length

    source_port = LinkNetwork.read_int(datagram, 0, 2)
    destination_port = LinkNetwork.read_int(datagram, 2, 2)
    checksum = LinkNetwork.read_int(datagram, 6, 2)
    status = if checksum.zero?
               "none"
             else
               covered = pseudo_header(source, destination, 17, length) + datagram[0, length]
               LinkNetwork.checksum_status(covered)
             end
    layer = Layer.new
    layer.set("udp.srcport", source_port)
    layer.set("udp.dstport", destination_port)
    layer.set("udp.length", length)
    layer.set("udp.checksum", checksum)
    layer.set("udp.checksum.status", status)
    payload = datagram[8...length]
    if source_port == 53 || destination_port == 53
      layer.forward("dns", payload)
    else
      layer.remaining = payload
    end
    layer
  end

  def option_text(kind, length, body, layer)
    case kind
    when 2
      mss = LinkNetwork.read_int(body, 0, 2)
      layer.set("tcp.options.mss", mss)
      "MSS #{mss}"
    when 3
      layer.set("tcp.options.wscale", body[0])
      "WS #{body[0]}"
    when 4 then "SACK_PERM"
    when 5
      blocks = body.each_slice(8).map do |block|
        " #{LinkNetwork.read_int(block, 0, 4)}-#{LinkNetwork.read_int(block, 4, 4)}"
      end
      "SACK#{blocks.join}"
    when 8 then "TS #{LinkNetwork.read_int(body, 0, 4)} #{LinkNetwork.read_int(body, 4, 4)}"
    else "kind #{kind} len #{length}"
    end
  end

  def parse_options(options, layer)
    index = 0
    while index < options.length
      kind = options[index]
      if kind == 0
        layer.add("tcp.option", "EOL")
        return
      elsif kind == 1
        layer.add("tcp.option", "NOP")
        index += 1
        next
      end
      length = options[index + 1] || 0
      if length < 2 || index + length > options.length ||
         (OPTION_LENGTHS.key?(kind) && !OPTION_LENGTHS[kind].include?(length))
        layer.set("tcp.options.malformed", true)
        return
      end
      body = options[index + 2, length - 2]
      layer.add("tcp.option", option_text(kind, length, body, layer))
      index += length
    end
  end

  def dissect_tcp(segment, source, destination)
    raise Malformed, "tcp: truncated header" if segment.length < 20

    header_length = segment[12] / 16 * 4
    raise Malformed, "tcp: bad header length #{header_length}" if header_length < 20
    raise Malformed, "tcp: truncated header" if header_length > segment.length

    flags = segment[13]
    covered = pseudo_header(source, destination, 6, segment.length) + segment
    layer = Layer.new
    layer.set("tcp.srcport", LinkNetwork.read_int(segment, 0, 2))
    layer.set("tcp.dstport", LinkNetwork.read_int(segment, 2, 2))
    layer.set("tcp.seq_raw", LinkNetwork.read_int(segment, 4, 4))
    layer.set("tcp.hdr_len", header_length)
    layer.set("tcp.flags", flags)
    FLAG_FIELDS.each_with_index { |name, bit| layer.set("tcp.flags.#{name}", (flags >> bit) & 1) }
    layer.set("tcp.window", LinkNetwork.read_int(segment, 14, 2))
    layer.set("tcp.checksum", LinkNetwork.read_int(segment, 16, 2))
    layer.set("tcp.checksum.status", LinkNetwork.checksum_status(covered))
    layer.set("tcp.urgent", LinkNetwork.read_int(segment, 18, 2))
    layer.set("tcp.len", segment.length - header_length)
    layer.set("tcp.ack_raw", LinkNetwork.read_int(segment, 8, 4)) unless (flags & 16).zero?
    parse_options(segment[20...header_length], layer)
    layer.remaining = segment[header_length..]
    layer
  end
end
