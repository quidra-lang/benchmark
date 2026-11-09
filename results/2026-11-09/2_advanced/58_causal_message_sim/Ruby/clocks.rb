module Clocks
  def self.advance(process, own, sender = nil)
    process[:lamport] = sender ? [process[:lamport], sender[:lamport]].max + 1 : process[:lamport] + 1
    process[:vector] = process[:vector].zip(sender[:vector]).map { |a, b| [a, b].max } if sender
    process[:vector][own] += 1
  end

  def self.before?(a, b)
    a != b && a.zip(b).all? { |x, y| x <= y }
  end

  def self.relation(a, b)
    return '->' if before?(a, b)
    return '<-' if before?(b, a)
    '||'
  end

  def self.deliverable?(stamp, counter, source)
    stamp.each_index.all? { |k| k == source ? stamp[k] == counter[k] + 1 : stamp[k] <= counter[k] }
  end

  def self.missing(stamp, counter, source)
    stamp.each_index.select { |k| stamp[k] > counter[k] + (k == source ? 1 : 0) }
  end

  def self.text(vector) = vector.join(',')
end
