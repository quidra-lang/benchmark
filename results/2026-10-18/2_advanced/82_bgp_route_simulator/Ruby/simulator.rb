require_relative 'topology'

module Simulator
  Message = Data.define(:serial, :sender, :receiver, :link, :prefix, :content, :arrival) do
    def key = [arrival, receiver, sender, serial]
  end

  class MessageQueue
    def initialize
      @messages, @serial = [], 0
    end

    def send(time, sender, receiver, link, prefix, content)
      @serial += 1
      message = Message.new(@serial, sender, receiver, link, prefix, content, time + link.delay)
      @messages << message
      @messages.sort_by!(&:key)
      message
    end

    def next_time = @messages.first&.arrival
    def take = @messages.shift

    def remove_link(link)
      removed, @messages = @messages.partition { |message| message.link.equal?(link) }
      removed
    end

    def state(time)
      @messages.map do |message|
        [message.arrival - time, message.receiver, message.sender, message.link.number,
         message.prefix, message.content]
      end
    end
  end

  Event = Data.define(:time, :text) do
    def fields = text.split(' ')
    def kind = ['LINK', 'POLICY'].include?(fields.first) ? fields.take(2).join('_') : fields.first
  end

  def self.read_events
    events = [Event.new(0, 'INITIAL')]
    File.foreach('input/events.txt', chomp: true) do |line|
      time, text = line.split(' ', 2)
      events << Event.new(time.to_i, text)
    end
    events
  end

  def self.read_params
    lines = File.readlines('input/params.txt', chomp: true)
    defaults = %w[customer peer provider].zip(lines[0].split.drop(1).map(&:to_i)).to_h
    cap = lines[1].split[1].to_i
    traces = lines.drop(2).map do |line|
      _, source, address = line.split(' ')
      [source.to_i, address, Topology.address(address)]
    end
    [defaults, cap, traces]
  end
end
