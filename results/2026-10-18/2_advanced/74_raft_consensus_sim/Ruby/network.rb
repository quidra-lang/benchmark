Message = Data.define(:kind, :source, :destination, :term, :data)
Link = Struct.new(:delay, :loss, :passed, :drops, :stats)

class Network
  TYPES = %w[RV RVR AE AER TN].freeze
  FIELDS = %w[sent delivered inflight partition rule loss down].freeze
  REASONS = %w[partition rule loss down].freeze
  attr_reader :links, :total, :by_type

  def initialize(count, path = 'input/network.txt')
    lines = File.readlines(path, chomp: true).map(&:split)
    default = lines.shift[1].to_i
    @links = {}
    (1..count).each do |a|
      (1..count).each do |b|
        @links[[a, b]] = Link.new(default, 0, 0, [], Hash.new(0)) unless a == b
      end
    end
    lines.each do |kind, a, b, *values|
      @links.each do |(source, destination), link|
        next unless (a == '*' || a.to_i == source) && (b == '*' || b.to_i == destination)
        case kind
        when 'DELAY' then link.delay = values[0].to_i
        when 'LOSS' then link.loss = values[0].to_i
        when 'DROP' then link.drops << [values[0], values[1].to_i, values[2].to_i]
        end
      end
    end
    @groups = Array.new(count + 1, 0)
    @total = Hash.new(0)
    @by_type = TYPES.to_h { |kind| [kind, Hash.new(0)] }
    @queue = Hash.new { |hash, time| hash[time] = [] }
    @serial = 0
  end

  def partition(groups)
    groups.each_with_index { |group, index| group.each { |number| @groups[number] = index } }
  end

  def heal = @groups.fill(0)
  def separated?(a, b) = @groups[a] != @groups[b]

  def count(message, field, amount = 1)
    [@total, @by_type[message.kind], @links[[message.source, message.destination]].stats].each do |stats|
      stats[field] += amount
    end
  end

  def send(time, source, destination, term, kind, data)
    message = Message.new(kind, source, destination, term, data)
    @serial += 1
    count(message, 'sent')
    link = @links[[source, destination]]
    reason = if separated?(source, destination)
               'partition'
             elsif link.drops.any? { |type, first, last| (type == kind || type == 'ALL') && time.between?(first, last) }
               'rule'
             else
               link.passed += 1
               'loss' if link.loss.positive? && (link.passed % link.loss).zero?
             end
    if reason
      count(message, reason)
    else
      count(message, 'inflight')
      @queue[time + link.delay] << [source, @serial, message]
    end
  end

  def arrivals(time)
    (@queue.delete(time) || []).sort_by { |source, serial, _| [source, serial] }.map do |_, _, message|
      count(message, 'inflight', -1)
      message
    end
  end

  def deliver(message, destination_up)
    reason = if !destination_up
               'down'
             elsif separated?(message.source, message.destination)
               'partition'
             end
    count(message, reason || 'delivered')
    reason.nil?
  end
end
