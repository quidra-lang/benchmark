require "fileutils"
require_relative "hexdump"
require_relative "link_network"
require_relative "transport"
require_relative "dns_app"
require_relative "flows"

module Analyzer
  FIELDS = {
    "frame.number" => :integer,
    "frame.time" => :integer,
    "frame.len" => :integer,
    "frame.protocols" => :string,
    "frame.malformed" => :string,
    "frame.bad_checksum" => :presence,
    "eth.dst" => :mac,
    "eth.src" => :mac,
    "eth.type" => :hex4,
    "arp.opcode" => :integer,
    "arp.src.hw" => :mac,
    "arp.src.ip" => :ipv4,
    "arp.dst.hw" => :mac,
    "arp.dst.ip" => :ipv4,
    "ip.hdr_len" => :integer,
    "ip.tos" => :hex2,
    "ip.len" => :integer,
    "ip.id" => :hex4,
    "ip.flags.df" => :integer,
    "ip.flags.mf" => :integer,
    "ip.frag_offset" => :integer,
    "ip.ttl" => :integer,
    "ip.proto" => :integer,
    "ip.checksum" => :hex4,
    "ip.checksum.status" => :string,
    "ip.src" => :ipv4,
    "ip.dst" => :ipv4,
    "ip.fragment" => :presence,
    "icmp.type" => :integer,
    "icmp.code" => :integer,
    "icmp.checksum" => :hex4,
    "icmp.checksum.status" => :string,
    "icmp.id" => :integer,
    "icmp.seq" => :integer,
    "udp.srcport" => :integer,
    "udp.dstport" => :integer,
    "udp.length" => :integer,
    "udp.checksum" => :hex4,
    "udp.checksum.status" => :string,
    "tcp.srcport" => :integer,
    "tcp.dstport" => :integer,
    "tcp.stream" => :integer,
    "tcp.seq" => :integer,
    "tcp.seq_raw" => :integer,
    "tcp.ack" => :integer,
    "tcp.ack_raw" => :integer,
    "tcp.hdr_len" => :integer,
    "tcp.flags" => :hex2,
    "tcp.flags.fin" => :integer,
    "tcp.flags.syn" => :integer,
    "tcp.flags.rst" => :integer,
    "tcp.flags.psh" => :integer,
    "tcp.flags.ack" => :integer,
    "tcp.flags.urg" => :integer,
    "tcp.window" => :integer,
    "tcp.window.calc" => :integer,
    "tcp.checksum" => :hex4,
    "tcp.checksum.status" => :string,
    "tcp.urgent" => :integer,
    "tcp.option" => :string,
    "tcp.options.mss" => :integer,
    "tcp.options.wscale" => :integer,
    "tcp.options.malformed" => :presence,
    "tcp.len" => :integer,
    "tcp.analysis.retransmission" => :presence,
    "tcp.analysis.out_of_order" => :presence,
    "tcp.analysis.lost_segment" => :presence,
    "tcp.analysis.duplicate_ack" => :presence,
    "dns.id" => :hex4,
    "dns.flags" => :hex4,
    "dns.flags.response" => :integer,
    "dns.flags.opcode" => :integer,
    "dns.flags.rcode" => :integer,
    "dns.count.queries" => :integer,
    "dns.count.answers" => :integer,
    "dns.count.auth_rr" => :integer,
    "dns.count.add_rr" => :integer,
    "dns.qry.name" => :string,
    "dns.qry.type" => :integer,
    "dns.answer" => :string,
    "dns.authority" => :string,
    "dns.additional" => :string,
    "dns.a" => :ipv4,
    "data.len" => :integer
  }.freeze
  ALIASES = {
    "eth.addr" => [:mac, "eth.dst", "eth.src"],
    "ip.addr" => [:ipv4, "ip.src", "ip.dst"],
    "udp.port" => [:integer, "udp.srcport", "udp.dstport"],
    "tcp.port" => [:integer, "tcp.srcport", "tcp.dstport"]
  }.freeze
  PROTOCOL_FIELDS = %w[eth arp ip icmp udp tcp dns data].freeze
  PROTOCOL_LABELS = { "eth" => "ETH", "arp" => "ARP", "ip" => "IPv4", "icmp" => "ICMP",
                      "udp" => "UDP", "tcp" => "TCP", "dns" => "DNS" }.freeze
  CHECKSUM_LAYERS = [["ip", "IPv4"], ["icmp", "ICMP"], ["udp", "UDP"], ["tcp", "TCP"]].freeze
  FLAG_NAMES = %w[FIN SYN RST PSH ACK URG ECE CWR].freeze
  MARK_LABELS = {
    "retransmission" => "[TCP Retransmission] ",
    "out_of_order" => "[TCP Out-Of-Order] ",
    "lost_segment" => "[TCP Previous segment not captured] "
  }.freeze
  TWO_CHARACTER_TOKENS = %w[== != <= >= && ||].freeze
  KEYWORDS = { "and" => "&&", "or" => "||", "not" => "!" }.freeze
  WORD_CHARACTER = /[A-Za-z0-9._:]/
  COMPARISONS = %w[== != < > <= >=].freeze
  HIERARCHY = [["eth", 0], ["arp", 2], ["ip", 2], ["icmp", 4], ["udp", 4],
               ["dns", 6], ["tcp", 4]].freeze
  MALFORMED_LAYERS = %w[eth arp ip icmp udp tcp dns].freeze
  CONVERSATION_HEADER = "type,endpoint_a,endpoint_b,packets,bytes,packets_a_to_b," \
                        "bytes_a_to_b,packets_b_to_a,bytes_b_to_a,start,duration"
  ENDPOINT_HEADER = "address,packets,bytes,tx_packets,tx_bytes,rx_packets,rx_bytes"

  module_function

  def seconds(time) = format("%d.%06d", time / 1_000_000, time % 1_000_000)
  def optional(value) = value.nil? ? "-" : value.to_s

  def notation(type, value)
    case type
    when :hex2 then format("0x%02x", value)
    when :hex4 then format("0x%04x", value)
    when :ipv4 then LinkNetwork.ipv4_notation(value)
    when :mac then LinkNetwork.mac_notation(value)
    else value.to_s
    end
  end

  def shown(packet, name) = notation(FIELDS.fetch(name), packet.value(name))

  def endpoint_text(endpoint)
    address, port = endpoint
    text = LinkNetwork.ipv4_notation(address)
    port.nil? ? text : "#{text}:#{port}"
  end

  def field_type_of(name)
    return FIELDS[name] if FIELDS.key?(name)
    return ALIASES[name][0] if ALIASES.key?(name)
    return :presence if PROTOCOL_FIELDS.include?(name)

    nil
  end

  def field_values(packet, name)
    if ALIASES.key?(name)
      _, first, second = ALIASES[name]
      packet.values(first) + packet.values(second)
    else
      packet.values(name)
    end
  end

  def dissect_layer(packet, name, payload)
    case name
    when "eth" then LinkNetwork.dissect_ethernet(payload)
    when "arp" then LinkNetwork.dissect_arp(payload)
    when "ip" then LinkNetwork.dissect_ipv4(payload)
    when "icmp" then Transport.dissect_icmp(payload)
    when "udp" then Transport.dissect_udp(payload, packet.value("ip.src"), packet.value("ip.dst"))
    when "tcp" then Transport.dissect_tcp(payload, packet.value("ip.src"), packet.value("ip.dst"))
    when "dns" then DnsApp.dissect_dns(payload)
    end
  end

  def dissect_layers(packet)
    name, payload = "eth", packet.data
    loop do
      packet.layers << name
      layer = dissect_layer(packet, name, payload)
      packet.fields.merge!(layer.fields)
      if layer.next_layer.nil?
        packet.remaining = layer.remaining
        return nil
      end
      name, payload = layer.next_layer, layer.payload
    end
  rescue Malformed => error
    error.message
  end

  def dissect(packet, base_time)
    reason = packet.error || dissect_layers(packet)
    if reason.nil? && !packet.remaining.empty?
      packet.layers << "data"
      packet.set("data.len", packet.remaining.length)
    end
    packet.set("frame.number", packet.number)
    packet.set("frame.time", packet.time - base_time)
    packet.set("frame.len", packet.length)
    packet.set("frame.protocols", packet.layers.join(":")) unless packet.layers.empty?
    packet.set("frame.malformed", reason) unless reason.nil?
    if CHECKSUM_LAYERS.any? { |layer, _| packet.value("#{layer}.checksum.status") == "bad" }
      packet.set("frame.bad_checksum", true)
    end
  end

  def addresses(packet)
    if packet.exists?("ip.src")
      [shown(packet, "ip.src"), shown(packet, "ip.dst")]
    elsif packet.exists?("eth.src")
      [shown(packet, "eth.src"), shown(packet, "eth.dst")]
    else
      ["-", "-"]
    end
  end

  def protocol_label(packet)
    layer = packet.layers.reverse.find { |name| name != "data" }
    layer ? PROTOCOL_LABELS.fetch(layer) : "DUMP"
  end

  def arp_info(packet)
    case packet.value("arp.opcode")
    when 1 then "Who has #{shown(packet, 'arp.dst.ip')}? Tell #{shown(packet, 'arp.src.ip')}"
    when 2 then "#{shown(packet, 'arp.src.ip')} is at #{shown(packet, 'arp.src.hw')}"
    else "Opcode #{packet.value('arp.opcode')}"
    end
  end

  def ipv4_info(packet)
    return "Protocol #{packet.value('ip.proto')}" unless packet.exists?("ip.fragment")

    text = "Fragment id=#{shown(packet, 'ip.id')} off=#{packet.value('ip.frag_offset')}"
    text += " MF" if packet.value("ip.flags.mf") == 1
    text
  end

  def icmp_info(packet)
    type = packet.value("icmp.type")
    if [0, 8].include?(type)
      kind = type == 8 ? "request" : "reply"
      "Echo #{kind} id=#{packet.value('icmp.id')} seq=#{packet.value('icmp.seq')}"
    else
      "Type #{type} code #{packet.value('icmp.code')}"
    end
  end

  def mark_notation(packet, duplicate_acks)
    if packet.exists?("tcp.analysis.duplicate_ack")
      original, count = duplicate_acks.fetch(packet.number)
      return "[TCP Dup ACK #{original}##{count}] "
    end
    MARK_LABELS.each do |mark, label|
      return label if packet.exists?("tcp.analysis.#{mark}")
    end
    ""
  end

  def flag_notation(flags)
    names = FLAG_NAMES.each_with_index.filter_map { |name, bit| name unless ((flags >> bit) & 1).zero? }
    names.empty? ? "<None>" : names.join(", ")
  end

  def option_summary(options)
    options.map do |option|
      words = option.split
      case words[0]
      when "MSS" then " MSS=#{words[1]}"
      when "WS" then " WS=#{2**words[1].to_i}"
      when "SACK_PERM" then " SACK_PERM"
      when "TS" then " TSval=#{words[1]} TSecr=#{words[2]}"
      else ""
      end
    end.join
  end

  def tcp_info(packet, duplicate_acks)
    text = mark_notation(packet, duplicate_acks) +
           "#{packet.value('tcp.srcport')} -> #{packet.value('tcp.dstport')}" +
           " [#{flag_notation(packet.value('tcp.flags'))}] Seq=#{packet.value('tcp.seq')}"
    text += " Ack=#{packet.value('tcp.ack')}" if packet.value("tcp.flags.ack") == 1
    text += " Win=#{packet.value('tcp.window.calc')} Len=#{packet.value('tcp.len')}"
    text + option_summary(packet.values("tcp.option"))
  end

  def dns_info(packet)
    parts = [packet.value("dns.flags.response") == 1 ? "Response" : "Query", shown(packet, "dns.id")]
    rcode = packet.value("dns.flags.rcode")
    parts << DnsApp.rcode_name(rcode) unless rcode.zero?
    packet.values("dns.qry.name").zip(packet.values("dns.qry.type")) do |name, type|
      parts.concat([DnsApp.type_name(type), name])
    end
    packet.values("dns.answer").each do |record|
      _, type, _, _, rdata = record.split(" ", 5)
      parts.concat([type, rdata])
    end
    parts.join(" ")
  end

  def basic_info(packet, protocol, duplicate_acks)
    return packet.value("frame.malformed") if packet.exists?("frame.malformed")

    case protocol
    when "ETH" then "EtherType #{shown(packet, 'eth.type')}"
    when "ARP" then arp_info(packet)
    when "IPv4" then ipv4_info(packet)
    when "ICMP" then icmp_info(packet)
    when "UDP"
      "#{packet.value('udp.srcport')} -> #{packet.value('udp.dstport')} Len=#{packet.value('udp.length') - 8}"
    when "TCP" then tcp_info(packet, duplicate_acks)
    when "DNS" then dns_info(packet)
    end
  end

  def annotations(packet)
    text = packet.exists?("tcp.options.malformed") ? " [bad TCP options]" : ""
    CHECKSUM_LAYERS.each do |layer, label|
      text += " [bad #{label} checksum]" if packet.value("#{layer}.checksum.status") == "bad"
    end
    text
  end

  def summary_line(packet, duplicate_acks)
    source, destination = addresses(packet)
    protocol = protocol_label(packet)
    info = basic_info(packet, protocol, duplicate_acks) + annotations(packet)
    "#{packet.number} #{seconds(packet.value('frame.time'))} #{source} -> #{destination} " \
      "#{protocol} #{packet.length} #{info}"
  end

  class FilterError < StandardError; end
  Token = Data.define(:kind, :text, :column)

  def tokenize(expression)
    tokens = []
    index = 0
    while index < expression.length
      character, column = expression[index], index + 1
      pair = expression[index, 2]
      if character == " "
        index += 1
      elsif TWO_CHARACTER_TOKENS.include?(pair)
        tokens << Token.new(pair, pair, column)
        index += 2
      elsif "()!<>".include?(character)
        tokens << Token.new(character, character, column)
        index += 1
      elsif character == '"'
        finish = expression.index('"', index + 1)
        raise FilterError, "unterminated string at column #{column}" if finish.nil?

        tokens << Token.new("string", expression[index..finish], column)
        index = finish + 1
      elsif WORD_CHARACTER.match?(character)
        finish = index
        finish += 1 while finish < expression.length && WORD_CHARACTER.match?(expression[finish])
        word = expression[index...finish]
        tokens << Token.new(KEYWORDS.fetch(word, "word"), word, column)
        index = finish
      else
        raise FilterError, "invalid character '#{character}' at column #{column}"
      end
    end
    tokens
  end

  def parse_number(text)
    return text.to_i if /\A[0-9]{1,15}\z/.match?(text)
    return text[2..].to_i(16) if /\A0x[0-9a-fA-F]{1,12}\z/.match?(text)

    nil
  end

  def parse_ipv4(text)
    parts = text.split(".", -1)
    return nil unless parts.length == 4
    return nil unless parts.all? { |part| /\A[0-9]{1,3}\z/.match?(part) && part.to_i <= 255 }

    parts.reduce(0) { |address, part| address * 256 + part.to_i }
  end

  def parse_mac(text)
    parts = text.split(":", -1)
    return nil unless parts.length == 6 && parts.all? { |part| /\A[0-9a-fA-F]{2}\z/.match?(part) }

    parts.reduce(0) { |address, part| address * 256 + part.to_i(16) }
  end

  def convert_value(type, token)
    return token.kind == "string" ? token.text[1...-1] : nil if type == :string
    return nil unless token.kind == "word"

    case type
    when :integer, :hex2, :hex4 then parse_number(token.text)
    when :ipv4 then parse_ipv4(token.text)
    when :mac then parse_mac(token.text)
    end
  end

  def unexpected(token)
    FilterError.new("unexpected '#{token.text}' at column #{token.column}")
  end

  class FilterParser
    def initialize(tokens)
      @tokens, @position = tokens, 0
    end

    def next_kind = @tokens[@position]&.kind

    def take
      raise FilterError, "unexpected end of filter" if @position >= @tokens.length

      token = @tokens[@position]
      @position += 1
      token
    end

    def parse
      node = expression
      raise Analyzer.unexpected(@tokens[@position]) if @position < @tokens.length

      node
    end

    def expression
      node = product
      while next_kind == "||"
        take
        node = [:or, node, product]
      end
      node
    end

    def product
      node = negation
      while next_kind == "&&"
        take
        node = [:and, node, negation]
      end
      node
    end

    def negation
      if next_kind == "!"
        take
        return [:not, negation]
      end
      token = take
      if token.kind == "("
        node = expression
        closing = take
        raise Analyzer.unexpected(closing) unless closing.kind == ")"

        node
      elsif token.kind == "word"
        read_test(token.text)
      else
        raise Analyzer.unexpected(token)
      end
    end

    def read_test(name)
      type = Analyzer.field_type_of(name)
      raise FilterError, "unknown field #{name}" if type.nil?
      return [:exists, name] unless COMPARISONS.include?(next_kind)

      operator = take.kind
      if type == :presence || (type == :string && !%w[== !=].include?(operator))
        raise FilterError, "operator #{operator} not allowed for #{name}"
      end
      token = take
      raise Analyzer.unexpected(token) unless %w[word string].include?(token.kind)

      value = Analyzer.convert_value(type, token)
      raise FilterError, "invalid value #{token.text} for #{name}" if value.nil?

      [:compare, name, operator, value]
    end
  end

  def compare(left, operator, right)
    case operator
    when "==" then left == right
    when "<" then left < right
    when ">" then left > right
    when "<=" then left <= right
    when ">=" then left >= right
    end
  end

  def evaluate(node, packet)
    case node[0]
    when :or then evaluate(node[1], packet) || evaluate(node[2], packet)
    when :and then evaluate(node[1], packet) && evaluate(node[2], packet)
    when :not then !evaluate(node[1], packet)
    when :exists
      name = node[1]
      PROTOCOL_FIELDS.include?(name) ? packet.layers.include?(name) : !field_values(packet, name).empty?
    when :compare
      _, name, operator, expected = node
      values = field_values(packet, name)
      return false if values.empty?

      if operator == "!="
        values.all? { |value| value != expected }
      else
        values.any? { |value| compare(value, operator, expected) }
      end
    end
  end

  def filter_block(expression, packets, summaries)
    lines = ["", "filter #{expression}"]
    begin
      tree = FilterParser.new(tokenize(expression)).parse
    rescue FilterError => error
      return lines << "error: #{error.message}"
    end
    matched = packets.select { |packet| evaluate(tree, packet) }
    lines.concat(matched.map { |packet| summaries[packet.number - 1] })
    lines << "matched #{matched.length} of #{packets.length}"
  end

  def detail_lines(packets, number)
    return ["packet #{number} not found"] unless number.between?(1, packets.length)

    packet = packets[number - 1]
    lines = ["packet #{number}"]
    (["frame"] + packet.layers).each do |layer|
      lines << layer
      FIELDS.each do |name, type|
        next unless name.start_with?("#{layer}.")

        packet.values(name).each do |value|
          lines << (type == :presence ? "  #{name}" : "  #{name} = #{notation(type, value)}")
        end
      end
      lines.concat(Hexdump.hex_dump_lines(packet.remaining).map { |line| "  #{line}" }) if layer == "data"
    end
    lines
  end

  def is_answer?(query, response)
    query.value("dns.id") == response.value("dns.id") &&
      query.value("ip.src") == response.value("ip.dst") &&
      query.value("udp.srcport") == response.value("udp.dstport") &&
      query.value("ip.dst") == response.value("ip.src") &&
      query.value("udp.dstport") == response.value("udp.srcport")
  end

  class DnsTransactions
    attr_reader :queries, :responses, :response_times, :unanswered

    def initialize(packets)
      @queries, @responses, @response_times = [], [], []
      pending = []
      packets.each do |packet|
        next unless packet.exists?("dns.id")

        if packet.value("dns.flags.response").zero?
          @queries << packet
          pending << packet
        else
          @responses << packet
          index = pending.index { |query| Analyzer.is_answer?(query, packet) }
          unless index.nil?
            query = pending.delete_at(index)
            @response_times << packet.time - query.time
          end
        end
      end
      @unanswered = pending.length
    end
  end

  def layer_statistics(packets)
    lines = ["hierarchy"]
    HIERARCHY.each do |name, indent|
      members = packets.select { |packet| packet.layers.include?(name) }
      lines << "#{' ' * indent}#{name} #{members.length} #{members.sum(&:length)}"
    end
    lines << "checksums"
    CHECKSUM_LAYERS.each do |layer, _|
      statuses = packets.map { |packet| packet.value("#{layer}.checksum.status") }
      line = "#{layer} good #{statuses.count('good')} bad #{statuses.count('bad')}"
      line += " none #{statuses.count('none')}" if layer == "udp"
      lines << line
    end
    lines.concat(["malformed", "dump #{packets.count { |packet| !packet.error.nil? }}"])
    MALFORMED_LAYERS.each do |name|
      count = packets.count do |packet|
        packet.error.nil? && packet.exists?("frame.malformed") && packet.layers.last == name
      end
      lines << "#{name} #{count}"
    end
    lines << "tcp analysis"
    Flows::MARKS.each do |mark|
      lines << "#{mark} #{packets.count { |packet| packet.exists?("tcp.analysis.#{mark}") }}"
    end
    lines
  end

  def dns_statistics(transactions)
    times = transactions.response_times
    lines = ["dns", "queries #{transactions.queries.length}", "responses #{transactions.responses.length}",
             "transactions #{times.length}", "unanswered #{transactions.unanswered}"]
    lines << if times.empty?
               "response_time -"
             else
               "response_time min #{seconds(times.min)} max #{seconds(times.max)}"
             end
    rcodes = transactions.responses.map { |packet| packet.value("dns.flags.rcode") }.tally
    16.times do |rcode|
      lines << "rcode #{DnsApp.rcode_name(rcode)} #{rcodes[rcode]}" if rcodes.key?(rcode)
    end
    lines << "names"
    names = transactions.queries.flat_map { |packet| packet.values("dns.qry.name") }.tally
    names.sort_by { |name, count| [-count, name] }.each { |name, count| lines << "#{name} #{count}" }
    lines
  end

  def protocol_stats_lines(packets, transactions)
    ["packets #{packets.length}", "bytes #{packets.sum(&:length)}",
     "duration #{seconds(packets.last.time - packets.first.time)}"] +
      layer_statistics(packets) + dns_statistics(transactions)
  end

  def conversation_lines(conversations, base_time)
    [CONVERSATION_HEADER] + conversations.map do |conversation|
      [conversation.kind, endpoint_text(conversation.endpoint_a), endpoint_text(conversation.endpoint_b),
       conversation.packets, conversation.bytes, conversation.packets_a_to_b, conversation.bytes_a_to_b,
       conversation.packets_b_to_a, conversation.bytes_b_to_a, seconds(conversation.first_time - base_time),
       seconds(conversation.last_time - conversation.first_time)].join(",")
    end
  end

  def endpoint_lines(endpoints)
    [ENDPOINT_HEADER] + endpoints.map do |endpoint|
      [LinkNetwork.ipv4_notation(endpoint.address), endpoint.packets, endpoint.bytes,
       endpoint.tx_packets, endpoint.tx_bytes, endpoint.rx_packets, endpoint.rx_bytes].join(",")
    end
  end

  def side_line(side)
    counts = Flows::MARKS.map { |mark| "#{mark} #{side.marks[mark]}" }.join(" ")
    "#{side.name} packets #{side.packets} payload #{side.payload} #{counts}"
  end

  def stream_lines(stream, packets)
    client, server = stream.client_side, stream.server_side
    rtt = if stream.syn && stream.handshake_ack
            seconds(packets[stream.handshake_ack - 1].time - packets[stream.syn - 1].time)
          else
            "-"
          end
    history = stream.history.map { |state, number| "#{state} #{number}" }.join(", ")
    lines = [
      "stream #{stream.number} #{endpoint_text(stream.client)} -> #{endpoint_text(stream.server)}",
      "packets #{stream.packets} bytes #{stream.bytes} start #{seconds(stream.start - packets.first.time)}" \
        " duration #{seconds(stream.end_time - stream.start)}",
      "states #{history}",
      "handshake syn #{optional(stream.syn)} syn_ack #{optional(stream.syn_ack)}" \
        " ack #{optional(stream.handshake_ack)} rtt #{rtt}",
      "options client mss #{optional(client.mss)} wscale #{optional(client.wscale)}" \
        " server mss #{optional(server.mss)} wscale #{optional(server.wscale)}",
      side_line(client), side_line(server)
    ]
    stream.events.each do |number, side, mark, start, size|
      lines << "event #{number} #{side} #{mark} seq #{start} len #{size}"
    end
    lines
  end

  def joined_blocks(blocks)
    blocks.each_with_index.flat_map { |block, index| index.zero? ? block : [""] + block }
  end

  def read_requests(path)
    filters, details = [], []
    File.foreach(path, chomp: true) do |line|
      if line.start_with?("FILTER ")
        filters << line[7..]
      elsif line.start_with?("DETAIL ")
        details << line[7..].to_i
      end
    end
    [filters, details]
  end

  def write_lines(name, lines)
    File.binwrite(File.join("output", name), lines.map { |line| "#{line}\n" }.join)
  end

  def main
    packets = Hexdump.read_capture(File.join("input", "capture.txt"))
    filters, detail_numbers = read_requests(File.join("input", "filters.txt"))
    base_time = packets.first.time
    packets.each { |packet| dissect(packet, base_time) }
    tracker = Flows::StreamTracker.new
    packets.each { |packet| tracker.track(packet) if packet.exists?("tcp.srcport") }
    summaries = packets.map { |packet| summary_line(packet, tracker.duplicate_acks) }
    summary = summaries.dup
    filters.each { |expression| summary.concat(filter_block(expression, packets, summaries)) }
    details = joined_blocks(detail_numbers.map { |number| detail_lines(packets, number) })
    streams = joined_blocks(tracker.streams.map { |stream| stream_lines(stream, packets) })
    FileUtils.mkdir_p("output")
    write_lines("summary.txt", summary)
    write_lines("details.txt", details)
    write_lines("conversations.csv", conversation_lines(Flows.build_conversations(packets), base_time))
    write_lines("endpoints.csv", endpoint_lines(Flows.build_endpoints(packets)))
    write_lines("protocol_stats.txt", protocol_stats_lines(packets, DnsTransactions.new(packets)))
    write_lines("tcp_streams.txt", streams)
  end
end

Analyzer.main if $PROGRAM_NAME == __FILE__
