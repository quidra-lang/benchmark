module ConfigIO
  module_function

  def decimal_integer?(text, maximum = nil)
    /\A(?:0|[1-9][0-9]*)\z/.match?(text) && (!maximum || text.length <= maximum)
  end

  def hex_address?(text)
    /\A[0-9a-f]{8}\z/.match?(text)
  end

  def hex(value)
    format('%08x', value)
  end

  def read_config(path = 'input/config.txt')
    config = { scenarios: [], regions: [], watch: [] }
    File.foreach(path, chomp: true) do |line|
      kind, *values = line.split(' ')
      case kind
      when 'CORES' then config[:cores] = values[0].to_i
      when 'LINE' then config[:line] = values[0].to_i
      when 'L1', 'L2'
        prefix = kind.downcase
        config["#{prefix}_size".to_sym], config["#{prefix}_ways".to_sym] = values.map(&:to_i)
      when 'LATENCY'
        %i[t1 t2 tm tb].zip(values.map(&:to_i)) { |key, value| config[key] = value }
      when 'SCENARIO'
        config[:scenarios] << { name: values[0], protocol: values[1], l1: values[2], l2: values[3], order: config[:scenarios].length }
      when 'PRIMARY' then config[:primary] = values[0]
      when 'INTERVAL' then config[:interval] = values[0].to_i
      when 'TOP' then config[:top] = values[0].to_i
      when 'REGION'
        config[:regions] << { name: values[0], start: values[1].to_i(16), end: values[2].to_i(16) }
      when 'WATCH' then config[:watch] << values[0].to_i(16) / config[:line]
      end
    end
    %i[l1 l2].each do |level|
      config["#{level}_sets".to_sym] = config["#{level}_size".to_sym] / (config[:line] * config["#{level}_ways".to_sym])
    end
    config[:cap] = config[:l1_sets] * config[:l1_ways]
    config
  end

  def read_trace(path = 'input/trace.txt')
    File.readlines(path, chomp: true)
  end

  def write_lines(name, lines)
    Dir.mkdir('output') unless Dir.exist?('output')
    File.write(File.join('output', name), lines.empty? ? '' : lines.join("\n") + "\n")
  end
end
