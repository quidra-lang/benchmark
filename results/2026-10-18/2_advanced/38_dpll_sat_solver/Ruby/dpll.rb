class DPLL
  def self.run(variables, clauses)
    new(variables, clauses).run
  end

  def initialize(variables, clauses)
    @clauses = clauses.map(&:dup)
    @values = Array.new(variables + 1)
    @watches = Hash.new { |h, literal| h[literal] = [] }
    @trail = []
    @queue_head = 0
    @trace = []
    @stats = {decisions: 0, propagations: 0, conflicts: 0, max_depth: 0}
    @clauses.each_with_index do |clause, index|
      next if clause.length < 2
      @watches[clause[0]] << index
      @watches[clause[1]] << index
    end
  end

  def run
    @clauses.each do |clause|
      if clause.empty? || (clause.length == 1 && value(clause[0]) == false)
        conflict
        return [nil, @trace, @stats]
      end
      assign(clause[0], :propagation) if clause.length == 1 && value(clause[0]).nil?
    end
    loop do
      unless propagate
        while !@trail.empty? && @trail.last[1] != :decision
          literal, = @trail.pop
          @values[literal.abs] = nil
        end
        return [nil, @trace, @stats] if @trail.empty?
        literal, = @trail.pop
        @values[literal.abs] = nil
        assign(-literal, :flip)
        @queue_head = @trail.length - 1
        next
      end

      counts = Hash.new(0)
      @clauses.each do |clause|
        next if clause.any? { |literal| value(literal) == true }
        clause.each { |literal| counts[literal] += 1 if value(literal).nil? }
      end
      return [@values.map { |v| v == true }, @trace, @stats] if counts.empty?
      best = counts.keys.min_by { |literal| [-counts[literal], literal.abs, literal.positive? ? 0 : 1] }
      assign(best, :decision)
      depth = @trail.count { |_, kind| kind != :propagation }
      @stats[:max_depth] = [@stats[:max_depth], depth].max
    end
  end

  private

  def value(literal)
    current = @values[literal.abs]
    current.nil? ? nil : (literal.positive? ? current : !current)
  end

  def assign(literal, kind)
    @values[literal.abs] = literal.positive?
    @trail << [literal, kind]
    prefix = {decision: 'D', flip: 'F', propagation: 'P'}.fetch(kind)
    @trace << "#{prefix}#{literal}"
    @stats[:decisions] += 1 if kind == :decision
    @stats[:propagations] += 1 if kind == :propagation
  end

  def conflict
    @stats[:conflicts] += 1
    @trace << 'C'
  end

  def propagate
    while @queue_head < @trail.length
      false_literal = -@trail[@queue_head][0]
      @queue_head += 1
      list = @watches[false_literal]
      index = 0
      while index < list.length
        clause_id = list[index]
        clause = @clauses[clause_id]
        clause[0], clause[1] = clause[1], clause[0] if clause[0] == false_literal
        if value(clause[0]) == true
          index += 1
          next
        end
        substitute = (2...clause.length).find { |j| value(clause[j]) != false }
        if substitute
          clause[1], clause[substitute] = clause[substitute], clause[1]
          list.delete_at(index)
          @watches[clause[1]] << clause_id
          next
        end
        if value(clause[0]) == false
          conflict
          return false
        end
        assign(clause[0], :propagation) if value(clause[0]).nil?
        index += 1
      end
    end
    true
  end
end
