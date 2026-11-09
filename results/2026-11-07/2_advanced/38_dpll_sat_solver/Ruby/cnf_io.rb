module CnfIO
  module_function

  def valid_number?(token)
    /\A(?:0|[1-9][0-9]{0,5})\z/.match?(token)
  end

  def read(filename)
    header = nil
    clauses = []
    partial = []
    File.foreach(File.join('input', filename)).with_index(1) do |line, number|
      next if line.start_with?('c')
      tokens = line.split
      next if tokens.empty?
      if tokens.first == 'p'
        raise ArgumentError, "duplicate header at line #{number}" if header
        unless tokens.length == 4 && tokens[1] == 'cnf' && tokens.drop(2).all? { |t| valid_number?(t) }
          raise ArgumentError, "bad header at line #{number}"
        end
        header = tokens.drop(2).map(&:to_i)
        next
      end
      raise ArgumentError, 'missing header' unless header
      tokens.each do |token|
        unless /\A(?:0|-?[1-9][0-9]{0,5})\z/.match?(token)
          raise ArgumentError, "bad token #{token} at line #{number}"
        end
        literal = token.to_i
        raise ArgumentError, "literal out of range #{token} at line #{number}" if literal.abs > header[0]
        if literal.zero?
          clauses << partial
          partial = []
        else
          partial << literal
        end
      end
    end
    raise ArgumentError, 'missing header' unless header
    raise ArgumentError, 'unterminated clause' unless partial.empty?
    if clauses.length != header[1]
      raise ArgumentError, "clause count mismatch header=#{header[1]} found=#{clauses.length}"
    end
    [header[0], clauses]
  end

  def model_lines(model)
    tokens = (1...model.length).map { |v| (model[v] ? v : -v).to_s } << '0'
    tokens.each_slice(10).map { |group| "v #{group.join(' ')}" }
  end
end
