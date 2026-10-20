module Stats
  TRANSACTIONS = %w[BusRd BusRdX BusUpgr BusWr WB].freeze
  SERVICES = %w[l1 upgrade through cache l2 memory].freeze
  MISSES = %w[compulsory capacity conflict coherence].freeze
  SNOOPS = %w[invalidations_sent invalidations_received supplied back_invalidations].freeze
  DISTANCE = %w[1 2-4 5-16 17-64 65-256 257+].freeze
  LATENCY = %w[1 2-9 10-29 30-99 100-299 300+].freeze
  module_function

  def fraction(p, q)
    divisor = p.gcd(q)
    "#{p / divisor}/#{q / divisor}"
  end

  def decimal(p, q)
    value = (2 * p * 100 + q) / (2 * q)
    format('%d.%02d', value / 100, value % 100)
  end

  def cores(values)
    values.empty? ? '-' : values.to_a.sort.join
  end

  def pairs(keys, counts, separator = ' ')
    keys.map { |key| "#{key}#{separator}#{counts[key]}" }.join(' ')
  end

  def counters
    { simple: Hash.new(0), misses: Hash.new(0), service: Hash.new(0), bus: Hash.new(0), snoop: Hash.new(0), finish: 0 }
  end

  def total(entries)
    entries.each_with_object(counters) do |item, result|
      %i[simple misses service bus snoop].each do |section|
        item[section].each { |key, value| result[section][key] += value }
      end
      result[:finish] = [result[:finish], item[:finish]].max
    end
  end

  def six_lines(label, entry)
    simple = entry[:simple]
    latency, accesses = simple['latency'], simple['accesses']
    ["#{label} #{pairs(%w[accesses reads writes hits misses fences], simple)}",
     "#{label} misses #{pairs(MISSES + %w[true_sharing false_sharing], entry[:misses])}",
     "#{label} service #{pairs(SERVICES, entry[:service])}",
     "#{label} bus #{pairs(TRANSACTIONS, entry[:bus])}",
     "#{label} snoop #{pairs(SNOOPS, entry[:snoop])}",
     "#{label} time latency #{latency} amat #{fraction(latency, accesses)} #{decimal(latency, accesses)} fence_stall #{simple['fence_stall']} finish #{entry[:finish]}"]
  end
end
