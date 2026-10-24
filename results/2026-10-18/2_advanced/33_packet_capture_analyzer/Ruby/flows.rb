module Flows
  SEQUENCE_MODULUS = 2**32
  MARKS = %w[retransmission out_of_order lost_segment duplicate_ack].freeze
  CONVERSATION_KINDS = %w[ipv4 tcp udp].freeze

  class Segment
    attr_reader :packet, :number, :time, :source, :destination, :seq, :ack, :window,
                :length, :syn, :fin

    def initialize(packet)
      @packet, @number, @time = packet, packet.number, packet.time
      @source = [packet.value("ip.src"), packet.value("tcp.srcport")]
      @destination = [packet.value("ip.dst"), packet.value("tcp.dstport")]
      @seq, @ack = packet.value("tcp.seq_raw"), packet.value("tcp.ack_raw")
      @syn, @fin = packet.value("tcp.flags.syn"), packet.value("tcp.flags.fin")
      @rst = packet.value("tcp.flags.rst")
      @has_ack = packet.value("tcp.flags.ack")
      @window, @length = packet.value("tcp.window"), packet.value("tcp.len")
    end

    def syn? = @syn == 1
    def fin? = @fin == 1
    def rst? = @rst == 1
    def ack? = @has_ack == 1
    def syn_only? = syn? && !ack?
    def syn_ack? = syn? && ack?
  end

  PreviousAck = Struct.new(:ack, :window, :number, :count)

  class Side
    attr_reader :name, :intervals, :marks
    attr_accessor :isn, :mss, :wscale, :base, :expected, :advanced_at, :previous_ack,
                  :packets, :payload

    def initialize(name)
      @name = name
      @isn = @mss = @wscale = @base = @expected = @advanced_at = @previous_ack = nil
      @intervals = {}
      @packets = @payload = 0
      @marks = MARKS.to_h { |mark| [mark, 0] }
    end
  end

  class Stream
    attr_reader :number, :client, :server, :history, :start, :events, :client_side, :server_side
    attr_accessor :state, :end_time, :packets, :bytes, :syn, :syn_ack, :handshake_ack,
                  :closer, :final_ack

    def initialize(number, client, server, state, segment)
      @number, @client, @server, @state = number, client, server, state
      @history = [[state, segment.number]]
      @start = @end_time = segment.time
      @packets = @bytes = 0
      @syn = @syn_ack = @handshake_ack = @closer = @final_ack = nil
      @events = []
      @client_side, @server_side = Side.new("client"), Side.new("server")
    end

    def change_state(state, number)
      @state = state
      @history << [state, number]
    end

    def record_syn(side, segment)
      side.isn = segment.seq
      side.mss = segment.packet.value("tcp.options.mss")
      side.wscale = segment.packet.value("tcp.options.wscale")
      if side.equal?(@client_side)
        @syn = segment.number
      else
        @syn_ack = segment.number
      end
    end
  end

  def self.endpoint_pair(first, second) = [first, second].sort

  class StreamTracker
    attr_reader :streams, :duplicate_acks

    def initialize
      @streams, @latest, @duplicate_acks = [], {}, {}
    end

    def open_stream(segment)
      number = @streams.length
      if segment.syn_ack?
        stream = Stream.new(number, segment.destination, segment.source, "SYN_RECEIVED", segment)
        stream.record_syn(stream.server_side, segment)
      elsif segment.syn_only?
        stream = Stream.new(number, segment.source, segment.destination, "SYN_SENT", segment)
        stream.record_syn(stream.client_side, segment)
      else
        stream = Stream.new(number, segment.source, segment.destination, "ESTABLISHED", segment)
      end
      @streams << stream
      stream
    end

    def find_stream(segment)
      key = Flows.endpoint_pair(segment.source, segment.destination)
      stream = @latest[key]
      if stream.nil? || (%w[CLOSED RESET].include?(stream.state) && segment.syn_only?)
        stream = open_stream(segment)
        @latest[key] = stream
      end
      stream
    end

    def track(packet)
      segment = Segment.new(packet)
      stream = find_stream(segment)
      packet.set("tcp.stream", stream.number)
      side, other = if segment.source == stream.client
                      [stream.client_side, stream.server_side]
                    else
                      [stream.server_side, stream.client_side]
                    end
      side.base = segment.seq if side.base.nil?
      other.base = segment.ack if segment.ack? && other.base.nil?
      relative_seq = (segment.seq - side.base) % SEQUENCE_MODULUS
      packet.set("tcp.seq", relative_seq)
      packet.set("tcp.ack", (segment.ack - other.base) % SEQUENCE_MODULUS) if segment.ack?
      analyze(stream, side, segment, relative_seq)
      packet.set("tcp.window.calc", calculated_window(stream, side, segment))
      transition(stream, side, segment)
      side.packets += 1
      side.payload += segment.length
      stream.packets += 1
      stream.bytes += packet.length
      stream.end_time = segment.time
    end

    def sequence_mark(side, start, size, time)
      return nil if side.expected.nil? || start == side.expected
      return "lost_segment" if start > side.expected
      return "retransmission" if side.intervals.key?([start, size])

      time - side.advanced_at < 3000 ? "out_of_order" : "retransmission"
    end

    def analyze(stream, side, segment, start)
      size = segment.length + segment.syn + segment.fin
      mark = nil
      if size >= 1
        mark = sequence_mark(side, start, size, segment.time)
        side.intervals[[start, size]] = true
        if side.expected.nil? || start + size > side.expected
          side.expected, side.advanced_at = start + size, segment.time
        end
      elsif segment.ack? && !segment.rst?
        previous = side.previous_ack
        if previous && segment.ack == previous.ack && segment.window == previous.window
          mark = "duplicate_ack"
          previous.count += 1
          @duplicate_acks[segment.number] = [previous.number, previous.count]
        end
      end
      if segment.ack? && mark != "duplicate_ack"
        side.previous_ack = PreviousAck.new(segment.ack, segment.window, segment.number, 0)
      end
      return if mark.nil?

      segment.packet.set("tcp.analysis.#{mark}", true)
      side.marks[mark] += 1
      stream.events << [segment.number, side.name, mark, start, size]
    end

    def calculated_window(stream, side, segment)
      scaled = !stream.client_side.wscale.nil? && !stream.server_side.wscale.nil?
      scaled && !segment.syn? ? segment.window * 2**side.wscale : segment.window
    end

    def transition(stream, side, segment)
      state, number = stream.state, segment.number
      if segment.rst?
        stream.change_state("RESET", number) unless %w[CLOSED RESET].include?(state)
      elsif state == "SYN_SENT" && segment.syn_ack? && side.equal?(stream.server_side) &&
            segment.ack == (stream.client_side.isn + 1) % SEQUENCE_MODULUS
        stream.change_state("SYN_RECEIVED", number)
        stream.record_syn(stream.server_side, segment)
      elsif state == "SYN_RECEIVED" && side.equal?(stream.client_side) && segment.ack? &&
            !segment.syn? && segment.ack == (stream.server_side.isn + 1) % SEQUENCE_MODULUS
        stream.change_state("ESTABLISHED", number)
        stream.handshake_ack = number
      elsif state == "ESTABLISHED" && segment.fin?
        stream.change_state("FIN_WAIT", number)
        stream.closer = side
      elsif state == "FIN_WAIT" && segment.fin? && !side.equal?(stream.closer)
        stream.change_state("CLOSING", number)
        stream.final_ack = (segment.seq + segment.length + 1) % SEQUENCE_MODULUS
      elsif state == "CLOSING" && side.equal?(stream.closer) && segment.ack? &&
            segment.ack == stream.final_ack
        stream.change_state("CLOSED", number)
      end
    end
  end

  class Conversation
    attr_reader :kind, :endpoint_a, :endpoint_b, :first_number, :first_time,
                :packets_a_to_b, :bytes_a_to_b, :packets_b_to_a, :bytes_b_to_a, :last_time

    def initialize(kind, endpoint_a, endpoint_b, packet)
      @kind, @endpoint_a, @endpoint_b = kind, endpoint_a, endpoint_b
      @first_number, @first_time, @last_time = packet.number, packet.time, packet.time
      @packets_a_to_b = @bytes_a_to_b = @packets_b_to_a = @bytes_b_to_a = 0
    end

    def count(source, packet)
      if source == @endpoint_a
        @packets_a_to_b += 1
        @bytes_a_to_b += packet.length
      else
        @packets_b_to_a += 1
        @bytes_b_to_a += packet.length
      end
      @last_time = packet.time
    end

    def packets = @packets_a_to_b + @packets_b_to_a
    def bytes = @bytes_a_to_b + @bytes_b_to_a
  end

  class Endpoint
    attr_reader :address
    attr_accessor :tx_packets, :tx_bytes, :rx_packets, :rx_bytes

    def initialize(address)
      @address = address
      @tx_packets = @tx_bytes = @rx_packets = @rx_bytes = 0
    end

    def packets = @tx_packets + @rx_packets
    def bytes = @tx_bytes + @rx_bytes
  end

  def self.conversation_views(packet)
    source_ip, destination_ip = packet.value("ip.src"), packet.value("ip.dst")
    views = [["ipv4", endpoint_pair(source_ip, destination_ip),
              [source_ip, nil], [destination_ip, nil]]]
    if packet.exists?("tcp.stream")
      source = [source_ip, packet.value("tcp.srcport")]
      destination = [destination_ip, packet.value("tcp.dstport")]
      views << ["tcp", packet.value("tcp.stream"), source, destination]
    end
    if packet.exists?("udp.srcport")
      source = [source_ip, packet.value("udp.srcport")]
      destination = [destination_ip, packet.value("udp.dstport")]
      views << ["udp", endpoint_pair(source, destination), source, destination]
    end
    views
  end

  def self.build_conversations(packets)
    table = {}
    packets.each do |packet|
      next unless packet.exists?("ip.src")

      conversation_views(packet).each do |kind, key, source, destination|
        conversation = table[[kind, key]] ||= Conversation.new(kind, source, destination, packet)
        conversation.count(source, packet)
      end
    end
    table.values.sort_by do |conversation|
      [-conversation.bytes, -conversation.packets,
       CONVERSATION_KINDS.index(conversation.kind), conversation.first_number]
    end
  end

  def self.build_endpoints(packets)
    table = {}
    packets.each do |packet|
      next unless packet.exists?("ip.src")

      source, destination = packet.value("ip.src"), packet.value("ip.dst")
      sender = table[source] ||= Endpoint.new(source)
      sender.tx_packets += 1
      sender.tx_bytes += packet.length
      receiver = table[destination] ||= Endpoint.new(destination)
      receiver.rx_packets += 1
      receiver.rx_bytes += packet.length
    end
    table.values.sort_by { |endpoint| [-endpoint.bytes, -endpoint.packets, endpoint.address] }
  end
end
