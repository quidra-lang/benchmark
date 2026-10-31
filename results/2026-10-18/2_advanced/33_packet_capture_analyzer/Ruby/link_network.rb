class Malformed < StandardError; end

class Layer
  attr_reader :fields
  attr_accessor :next_layer, :payload, :remaining

  def initialize
    @fields = {}
    @next_layer = nil
    @payload, @remaining = [], []
  end

  def set(name, value)
    @fields[name] = [value]
  end

  def add(name, value)
    (@fields[name] ||= []) << value
  end

  def forward(name, payload)
    @next_layer, @payload = name, payload
  end
end

module LinkNetwork
  IP_PROTOCOLS = { 1 => "icmp", 17 => "udp", 6 => "tcp" }.freeze

  module_function

  def read_int(data, index, size)
    data[index, size].reduce(0) { |value, byte| value * 256 + byte }
  end

  def checksum_status(data)
    total = data.each_slice(2).sum { |high, low| high * 256 + (low || 0) }
    total = total % 65_536 + total / 65_536 while total > 65_535
    total == 65_535 ? "good" : "bad"
  end

  def mac_notation(value)
    5.downto(0).map { |shift| format("%02x", (value >> (shift * 8)) & 255) }.join(":")
  end

  def ipv4_notation(value)
    3.downto(0).map { |shift| (value >> (shift * 8)) & 255 }.join(".")
  end

  def dissect_ethernet(frame)
    raise Malformed, "eth: truncated" if frame.length < 14

    layer = Layer.new
    ether_type = read_int(frame, 12, 2)
    layer.set("eth.dst", read_int(frame, 0, 6))
    layer.set("eth.src", read_int(frame, 6, 6))
    layer.set("eth.type", ether_type)
    payload = frame[14..]
    case ether_type
    when 0x0806 then layer.forward("arp", payload)
    when 0x0800 then layer.forward("ip", payload)
    else layer.remaining = payload
    end
    layer
  end

  def dissect_arp(message)
    raise Malformed, "arp: truncated" if message.length < 28
    unless read_int(message, 0, 2) == 1 && read_int(message, 2, 2) == 0x0800 &&
           message[4] == 6 && message[5] == 4
      raise Malformed, "arp: unsupported format"
    end

    layer = Layer.new
    layer.set("arp.opcode", read_int(message, 6, 2))
    layer.set("arp.src.hw", read_int(message, 8, 6))
    layer.set("arp.src.ip", read_int(message, 14, 4))
    layer.set("arp.dst.hw", read_int(message, 18, 6))
    layer.set("arp.dst.ip", read_int(message, 24, 4))
    layer
  end

  def dissect_ipv4(datagram)
    available = datagram.length
    raise Malformed, "ip: truncated header" if available < 20

    version = datagram[0] / 16
    raise Malformed, "ip: bad version #{version}" unless version == 4

    header_length = datagram[0] % 16 * 4
    raise Malformed, "ip: bad header length #{header_length}" if header_length < 20
    raise Malformed, "ip: truncated header" if available < header_length

    total_length = read_int(datagram, 2, 2)
    raise Malformed, "ip: bad total length #{total_length}" if total_length < header_length
    if total_length > available
      raise Malformed, "ip: truncated (total length #{total_length}, available #{available})"
    end

    flags = read_int(datagram, 6, 2)
    more_fragments = (flags >> 13) & 1
    offset = (flags & 8191) * 8
    protocol = datagram[9]
    layer = Layer.new
    layer.set("ip.hdr_len", header_length)
    layer.set("ip.tos", datagram[1])
    layer.set("ip.len", total_length)
    layer.set("ip.id", read_int(datagram, 4, 2))
    layer.set("ip.flags.df", (flags >> 14) & 1)
    layer.set("ip.flags.mf", more_fragments)
    layer.set("ip.frag_offset", offset)
    layer.set("ip.ttl", datagram[8])
    layer.set("ip.proto", protocol)
    layer.set("ip.checksum", read_int(datagram, 10, 2))
    layer.set("ip.checksum.status", checksum_status(datagram[0, header_length]))
    layer.set("ip.src", read_int(datagram, 12, 4))
    layer.set("ip.dst", read_int(datagram, 16, 4))
    payload = datagram[header_length...total_length]
    if more_fragments == 1 || offset != 0
      layer.set("ip.fragment", true)
      layer.remaining = payload
    elsif IP_PROTOCOLS.key?(protocol)
      layer.forward(IP_PROTOCOLS[protocol], payload)
    else
      layer.remaining = payload
    end
    layer
  end
end
