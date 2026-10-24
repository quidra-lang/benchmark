class Packet
  attr_reader :number, :time, :length, :data, :layers, :fields
  attr_accessor :error, :remaining

  def initialize(number, time, length)
    @number, @time, @length = number, time, length
    @data, @layers, @fields, @remaining = [], [], {}, []
    @error = nil
  end

  def values(name) = @fields.fetch(name, [])
  def value(name) = @fields[name]&.first
  def exists?(name) = @fields.key?(name)

  def set(name, value)
    @fields[name] = [value]
  end
end

module Hexdump
  DATA_LINE = /\A[0-9a-f]{4}  [0-9a-f]{2}(?: [0-9a-f]{2}){0,15}\z/

  module_function

  def finish_packet(packet)
    return unless packet && packet.error.nil? && packet.data.length != packet.length

    packet.error = "dump: length mismatch (header #{packet.length}, data #{packet.data.length})"
  end

  def read_capture(path)
    packets = []
    packet = nil
    File.foreach(path, chomp: true).with_index(1) do |line, line_number|
      if line.start_with?("PACKET ")
        finish_packet(packet)
        number, time, length = line.split.drop(1).map(&:to_i)
        packet = Packet.new(number, time, length)
        packets << packet
      elsif !line.empty? && packet.error.nil?
        if !DATA_LINE.match?(line)
          packet.error = "dump: bad line #{line_number}"
        elsif line[0, 4].to_i(16) != packet.data.length
          packet.error = "dump: offset mismatch at line #{line_number}"
        else
          packet.data.concat(line[6..].split.map { |byte| byte.to_i(16) })
        end
      end
    end
    finish_packet(packet)
    packets
  end

  def hex_dump_lines(data)
    data.each_slice(16).with_index.map do |piece, index|
      hex = piece.map { |byte| format("%02x", byte) }.join(" ").ljust(47)
      text = piece.map { |byte| byte.between?(32, 126) ? byte.chr : "." }.join
      format("%04x  %s  |%s|", index * 16, hex, text)
    end
  end
end
