class Minstd
  attr_reader :draws

  def initialize(seed)
    @state = seed
    @draws = 0
  end

  def draw
    @draws += 1
    @state = 48_271 * @state % 2_147_483_647
  end
end

module Network
  def self.read_topology(path = 'input/topology.txt')
    lines = File.readlines(path, chomp: true)
    names = lines.shift.split.drop(1)
    channels = {}
    lines.each do |line|
      _, source, destination, kind, a, b = line.split
      channels[[source, destination]] = {
        kind: kind, a: a.to_i, b: (b || a).to_i, sequence: 0,
        last_arrival: 0, messages: 0, markers: 0, buffered: 0,
        max_delay: 0, entries: 0, previous: Array.new(names.size, 0)
      }
    end
    [names, channels]
  end

  def self.dispatch(channels, source, destination, packet, time, random)
    channel = channels.fetch([source, destination])
    channel[:sequence] += 1
    delay = channel[:a]
    delay += random.draw % (channel[:b] - channel[:a] + 1) if channel[:a] != channel[:b]
    arrival = time + delay
    arrival = [arrival, channel[:last_arrival]].max if channel[:kind] == 'FIFO'
    channel[:last_arrival] = [arrival, channel[:last_arrival]].max
    channel[:max_delay] = [channel[:max_delay], arrival - time].max
    packet.merge!(source: source, destination: destination, sequence: channel[:sequence], arrival: arrival)
    if packet[:marker]
      channel[:markers] += 1
    else
      channel[:messages] += 1
      vector = packet[:send_event][:vector]
      channel[:entries] += vector.zip(channel[:previous]).count { |a, b| a != b }
      channel[:previous] = vector.dup
    end
    yield arrival, destination, :arrival, packet
  end

  def self.delay_text(channel)
    channel[:a] == channel[:b] ? channel[:a].to_s : "#{channel[:a]}-#{channel[:b]}"
  end
end
