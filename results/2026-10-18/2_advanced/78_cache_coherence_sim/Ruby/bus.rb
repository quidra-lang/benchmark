require_relative 'config_io'

class Bus
  attr_reader :free, :wait, :transactions

  def initialize(latency)
    @latency, @free, @wait = latency, 0, 0
    @transactions = []
  end

  def assign(core, kind, block, requested)
    start = [requested, @free].max
    @wait += start - requested
    @free = start + @latency
    transaction = { number: @transactions.length + 1, start: start, core: core, kind: kind, block: block,
                    snoop: [], snoop_hits: 0, invalidations: 0, supplier: nil, flush: false, l2: nil, eviction: nil }
    @transactions << transaction
    transaction
  end

  def busy
    @latency * @transactions.length
  end

  def log_line(tx, line_size)
    result = "#{tx[:number]} #{tx[:start]} c#{tx[:core]} #{tx[:kind]} #{ConfigIO.hex(tx[:block] * line_size)}"
    return result if tx[:kind] == 'WB'
    result += ' snoop ' + (tx[:snoop].empty? ? 'none' : tx[:snoop].join(' '))
    return result if tx[:kind] == 'BusUpgr'
    result += " data #{tx[:source]}" if %w[BusRd BusRdX].include?(tx[:kind])
    result += " l2 #{tx[:l2]}"
    if (eviction = tx[:eviction])
      copies = eviction[:copies].empty? ? 'none' : eviction[:copies].join(' ')
      result += " evict #{ConfigIO.hex(eviction[:block] * line_size)} #{copies} #{eviction[:dirty] ? 'dirty' : 'clean'}"
    end
    result
  end
end
