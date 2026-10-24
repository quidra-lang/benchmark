class Checker
  PROPERTIES = %w[ELECTION_SAFETY LEADER_COMPLETENESS LOG_MATCHING STATE_MACHINE_SAFETY COMMITTED_KEPT].freeze
  attr_reader :violations, :committed, :applied

  def initialize
    @violations = Hash.new(0)
    @leaders, @committed, @applied = {}, {}, {}
    @elected = @log_checks = @pair_checks = @applies = @truncations = @removed = 0
  end

  def leader(node)
    @elected += 1
    if @leaders.key?(node.term)
      @violations['ELECTION_SAFETY'] += 1 if @leaders[node.term] != node.number
    else
      @leaders[node.term] = node.number
    end
    if @committed.any? { |index, (term, _)| index > node.last_index || node.term_at(index) != term }
      @violations['LEADER_COMPLETENESS'] += 1
    end
  end

  def commit(index, term, time)
    @committed[index] ||= [term, time]
  end

  def apply(index, entry, result)
    @applies += 1
    if @applied.key?(index)
      @violations['STATE_MACHINE_SAFETY'] += 1 if @applied[index][0] != entry
    else
      @applied[index] = [entry, result]
    end
  end

  def truncate(first, entries)
    @truncations += 1
    @removed += entries.length
    entries.each_with_index do |entry, offset|
      record = @committed[first + offset]
      @violations['COMMITTED_KEPT'] += 1 if record && record[0] == entry.term
    end
  end

  def check_logs(nodes)
    @log_checks += 1
    nodes.combination(2) do |first, second|
      @pair_checks += 1
      limit = [first.last_index, second.last_index].min
      greatest = limit.downto(1).find { |index| first.term_at(index) == second.term_at(index) } || 0
      if (0...greatest).any? { |index| first.log[index] != second.log[index] }
        @violations['LOG_MATCHING'] += 1
      end
    end
  end

  def lines(maximum_term)
    details = ["terms #{maximum_term} leaders #{@leaders.length} elected #{@elected}",
               "checks #{@elected} committed #{@committed.length}",
               "checks #{@log_checks} pairs #{@pair_checks}",
               "applies #{@applies} indices #{@applied.length}",
               "truncations #{@truncations} removed #{@removed}"]
    PROPERTIES.each_with_index.map do |name, index|
      count = @violations[name]
      "#{name} #{count.zero? ? 'OK' : 'FAIL'} violations #{count} #{details[index]}"
    end
  end
end
