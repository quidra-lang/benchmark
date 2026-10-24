module TraceIO
  extend self

  def parse_hex(text)
    text.match?(/\A[0-9a-f]{8}\z/) ? text.to_i(16) : nil
  end

  def parse_register(text)
    text.match?(/\Ar(?:[0-9]|[12][0-9]|3[01])\z/) ? text[1..].to_i : nil
  end

  def read_inputs
    trace = File.readlines('input/trace.txt', chomp: true)
    config = { predictors: [], variants: [] }
    File.foreach('input/config.txt', chomp: true) do |line|
      key, *values = line.split
      case key
      when 'BTB', 'RAS', 'TOP', 'INTERVAL' then config[key.downcase.to_sym] = values[0].to_i
      when 'PREDICTOR'
        config[:predictors] << { name: values[0], scheme: values[1], parameters: values.drop(2).map(&:to_i) }
      when 'VARIANT'
        config[:variants] << { name: values[0], forwarding: values[1] == 'ON', stage: values[2], latency: values[3].to_i }
      when 'PRIMARY' then config[:primary] = values
      when 'WINDOW' then config[:window] = values.map(&:to_i)
      end
    end
    [trace, config]
  end
end
