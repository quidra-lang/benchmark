class Version
  include Comparable
  attr_reader :core, :pre
  NUMBER = /\A(?:0|[1-9][0-9]{0,3})\z/

  def initialize(core, pre = nil)
    @core = core
    @pre = pre
  end

  def self.parse(text)
    match = /\A(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})(?:-([a-z0-9]+(?:\.[a-z0-9]+)*))?\z/.match(text)
    return nil unless match
    pre = match[4]&.split('.')
    return nil if pre&.any? { |part| part.match?(/\A[0-9]+\z/) && !NUMBER.match?(part) }
    new(match.captures.take(3).map(&:to_i), pre)
  end

  def <=>(other)
    comparison = @core <=> other.core
    return comparison unless comparison.zero?
    return 0 if @pre.nil? && other.pre.nil?
    return 1 if @pre.nil?
    return -1 if other.pre.nil?
    @pre.zip(other.pre).each do |a, b|
      return 1 unless b
      next if a == b
      an = a.match?(/\A[0-9]+\z/)
      bn = b.match?(/\A[0-9]+\z/)
      return an && bn ? a.to_i <=> b.to_i : (an == bn ? a <=> b : an ? -1 : 1)
    end
    @pre.length <=> other.pre.length
  end

  def to_s
    @core.join('.') + (@pre ? '-' + @pre.join('.') : '')
  end
end

class Constraint
  attr_reader :alternatives

  def initialize(alternatives)
    @alternatives = alternatives
  end

  def self.parse(text)
    alternatives = []
    text.split(' || ', -1).each do |alternative|
      return nil if alternative.empty?
      comparators = []
      gates = []
      alternative.split(/ /, -1).each do |term|
        operator = %w[>= <= > < = ^ ~].find { |op| term.start_with?(op) } || ''
        pattern = term[operator.length..]
        version = Version.parse(pattern)
        if version && version.pre
          core = version.core
          k = 3
          gates << core
        else
          parts = pattern.split('.', -1)
          return nil unless parts.length.between?(1, 3)
          numbers = []
          wildcard = false
          parts.each do |part|
            if %w[x *].include?(part)
              wildcard = true
            elsif Version::NUMBER.match?(part) && !wildcard
              numbers << part.to_i
            else
              return nil
            end
          end
          k = numbers.length
          core = numbers + Array.new(3 - k, 0)
          version = Version.new(core)
        end
        upper = lambda do |i|
          values = core.dup
          values[i - 1] += 1
          (i...3).each { |j| values[j] = 0 }
          Version.new(values)
        end
        if k.zero?
          comparators << ['<', Version.new([0, 0, 0], ['0'])] if %w[> <].include?(operator)
        else
          case operator
          when '', '='
            comparators.concat(k == 3 ? [['=', version]] : [['>=', version], ['<', upper.call(k)]])
          when '>'
            comparators << [k == 3 ? '>' : '>=', k == 3 ? version : upper.call(k)]
          when '<='
            comparators << [k == 3 ? '<=' : '<', k == 3 ? version : upper.call(k)]
          when '>=', '<'
            comparators << [operator, version]
          when '~'
            comparators.concat([['>=', version], ['<', upper.call(k == 1 ? 1 : 2)]])
          when '^'
            i = core[0] != 0 || k == 1 ? 1 : (core[1] != 0 || k == 2 ? 2 : 3)
            comparators.concat([['>=', version], ['<', upper.call(i)]])
          end
        end
      end
      alternatives << [comparators, gates]
    end
    new(alternatives)
  end

  def match?(version)
    @alternatives.any? do |comparators, gates|
      (version.pre.nil? || gates.include?(version.core)) && comparators.all? do |operator, bound|
        comparison = version <=> bound
        case operator
        when '=' then comparison.zero?
        when '>' then comparison.positive?
        when '>=' then comparison >= 0
        when '<' then comparison.negative?
        else comparison <= 0
        end
      end
    end
  end

  def to_s
    @alternatives.map do |comparators, _|
      comparators.empty? ? '*' : comparators.map { |operator, version| operator + version.to_s }.join(' ')
    end.join(' || ')
  end
end

class PackageError < StandardError; end

class PackageManager
  def initialize
    @registry = {}
    @constraints = {}
    @requests = []
    @installed = {}
    @held = []
    @advisories = {}
    @history = []
  end

  def version(text)
    value = Version.parse(text)
    raise PackageError, "invalid version '#{text}'" unless value
    value
  end

  def constraint(text)
    @constraints[text] ||= Constraint.parse(text)
    raise PackageError, "invalid constraint '#{text}'" unless @constraints[text]
    @constraints[text]
  end

  def matches?(text, value)
    constraint(text).match?(value.is_a?(Version) ? value : Version.parse(value))
  end

  def record(name, value)
    @registry[name]&.[](value)
  end

  def versions(name)
    (@registry[name] || {}).keys.sort { |a, b| Version.parse(b) <=> Version.parse(a) }
  end

  def advisories(name, value)
    @advisories.keys.sort.select { |id| @advisories[id][0] == name && matches?(@advisories[id][1], value) }
  end

  def display(name, value)
    flags = []
    flags << 'yanked' if record(name, value)[:yanked]
    flags << 'installed' if @installed[name] == value
    "#{name}@#{value}#{flags.empty? ? '' : " (#{flags.join(', ')})"}"
  end

  def dependencies(name, installed = @installed)
    record(name, installed[name])[:deps]
  end

  def resolve(requests, preferred, audit = false)
    selected = {}
    reasons = {}
    failure = nil
    failure_depth = -1
    usable = lambda { |name, value| (!record(name, value)[:yanked] || @installed[name] == value) && (!audit || advisories(name, value).empty?) }
    save_failure = lambda do |chain, reason, other = nil|
      if selected.length > failure_depth
        failure_depth = selected.length
        failure = ['UNSATISFIABLE'] + chain.map { |line| '  ' + line } + ['  ' + reason]
        failure += other.map { |line| '    ' + line } if other
      end
    end
    search = lambda do |requirements|
      return true if requirements.empty?
      name, text, chain = requirements.first
      rest = requirements.drop(1)
      if selected.key?(name)
        return search.call(rest) if matches?(text, selected[name])
        save_failure.call(chain, "#{name}@#{selected[name]} was selected by:", reasons[name])
        return false
      end
      if @held.include?(name)
        value = @installed[name]
        unless matches?(text, value) && usable.call(name, value)
          save_failure.call(chain, "#{name}@#{value} is held")
          return false
        end
        candidates = [value]
      else
        candidates = versions(name).select { |v| matches?(text, v) && usable.call(name, v) }
        if preferred.include?(name) && candidates.include?(@installed[name])
          candidates.delete(@installed[name])
          candidates.unshift(@installed[name])
        end
        if candidates.empty?
          save_failure.call(chain, "no version of #{name} matches #{text}")
          return false
        end
      end
      candidates.each do |value|
        conflicting = selected.keys.sort.find do |q|
          record(name, value)[:conflicts].any? { |d, c| d == q && matches?(c, selected[q]) } ||
            record(q, selected[q])[:conflicts].any? { |d, c| d == name && matches?(c, value) }
        end
        if conflicting
          save_failure.call(chain, "#{name}@#{value} conflicts with #{conflicting}@#{selected[conflicting]}, which was selected by:", reasons[conflicting])
          next
        end
        selected[name] = value
        reasons[name] = chain
        extra = record(name, value)[:deps].map { |d, c| [d, c, chain + ["#{name}@#{value} requires #{d} #{c}"]] }
        return true if search.call(extra + rest)
        selected.delete(name)
        reasons.delete(name)
      end
      false
    end
    requirements = requests.map { |name, text| [name, text, ["requested #{name} #{text}"]] }
    search.call(requirements) ? [selected, nil] : [nil, failure]
  end

  def plan(new_state)
    old = @installed
    arranged = []
    counts = Hash.new(0)
    until arranged.length == new_state.length
      name = (new_state.keys - arranged).sort.find { |n| dependencies(n, new_state).all? { |d, _| arranged.include?(d) } }
      arranged << name
      value = new_state[name]
      if !old.key?(name)
        puts "install #{name}@#{value}"
        counts[:installed] += 1
      elsif old[name] != value
        kind = Version.parse(value) > Version.parse(old[name]) ? :upgraded : :downgraded
        puts "#{kind == :upgraded ? 'upgrade' : 'downgrade'} #{name} #{old[name]} -> #{value}"
        counts[kind] += 1
      end
    end
    remaining = old.keys - new_state.keys
    until remaining.empty?
      name = remaining.sort.find { |n| remaining.none? { |q| dependencies(q, old).any? { |d, _| d == n } } }
      puts "remove #{name}@#{old[name]}"
      counts[:removed] += 1
      remaining.delete(name)
    end
    if counts.empty?
      puts 'no changes'
    else
      puts "#{counts[:installed]} installed, #{counts[:upgraded]} upgraded, #{counts[:downgraded]} downgraded, #{counts[:removed]} removed"
    end
  end

  def update(requests, installed)
    @history << [@requests.map(&:dup), @installed.dup]
    @requests = requests
    @installed = installed
    @held &= installed.keys
  end

  def resolve_and_plan(requests, preferred, audit = false, simulate = false)
    installed, failure = resolve(requests, preferred, audit)
    if failure
      puts failure
    else
      plan(installed)
      update(requests, installed) unless simulate
    end
  end

  def require_installed(name)
    raise PackageError, "#{name} is not installed" unless @installed.key?(name)
  end

  def required_by(name)
    @installed.keys.sort.find { |n| dependencies(n).any? { |d, _| d == name } }
  end

  def tree(name)
    roots = name ? [name] : @requests.map(&:first).sort
    require_installed(name) if name
    if roots.empty?
      puts '(empty)'
      return
    end
    seen = []
    visit = lambda do |n, text, prefix, indent|
      body = "#{prefix}#{n}@#{@installed[n]}#{text ? " [#{text}]" : ''}"
      if seen.include?(n)
        puts body + ' (*)'
        return
      end
      puts body
      seen << n
      deps = dependencies(n)
      deps.each_with_index do |(d, c), i|
        last = i == deps.length - 1
        visit.call(d, c, indent + (last ? '`-- ' : '|-- '), indent + (last ? '    ' : '|   '))
      end
    end
    roots.each { |root| visit.call(root, @requests.find { |n, _| n == root }&.last, '', '') }
  end

  def execute(line)
    command, rest = line.split(/ /, 2)
    args = rest ? rest.split(/ /) : []
    name = args[0]
    case command
    when 'PKG'
      clauses = rest.split('; ')
      name, value = clauses.shift.split(' ')
      parsed = version(value)
      raise PackageError, "#{name}@#{value} is already registered" if record(name, value)
      deps = []
      conflicts = []
      clauses.each do |clause|
        kind, other, text = clause.split(/ /, 3)
        constraint(text)
        (kind == 'DEP' ? deps : conflicts) << [other, text]
      end
      @registry[name] ||= {}
      @registry[name][value] = { version: parsed, deps: deps, conflicts: conflicts, yanked: false }
      puts "registered #{name}@#{value}"
    when 'YANK', 'INFO'
      value = args[1]
      entry = record(name, value)
      raise PackageError, "#{name}@#{value} is not registered" unless entry
      if command == 'YANK'
        raise PackageError, "#{name}@#{value} is already yanked" if entry[:yanked]
        entry[:yanked] = true
        puts "yanked #{name}@#{value}"
      else
        puts display(name, value)
        entry[:deps].each { |d, c| puts "  requires #{d} #{c}" }
        entry[:conflicts].each { |d, c| puts "  conflicts with #{d} #{c}" }
        advisories(name, value).each { |id| puts "  advisory #{id}" }
      end
    when 'COMPARE'
      a = version(name)
      b = version(args[1])
      puts "#{name} #{['<', '=', '>'][(a <=> b) + 1]} #{args[1]}"
    when 'MATCH'
      value, text = rest.split(/ /, 2)
      parsed = version(value)
      puts(constraint(text).match?(parsed) ? 'yes' : 'no')
    when 'RANGE'
      puts constraint(rest).to_s
    when 'VERSIONS'
      name, text = rest.split(/ /, 2)
      constraint(text) if text
      raise PackageError, "unknown package #{name}" unless @registry.key?(name)
      selected = versions(name).select { |v| !text || matches?(text, v) }
      puts 'no matching versions' if selected.empty?
      selected.each { |v| puts display(name, v) }
    when 'DEPENDENTS'
      value = args[1]
      version(value) if value
      lines = []
      @registry.keys.sort.each do |n|
        versions(n).each do |v|
          record(n, v)[:deps].each { |d, c| lines << "#{n}@#{v} requires #{name} #{c}" if d == name && (!value || matches?(c, value)) }
        end
      end
      puts(lines.empty? ? ['no dependents'] : lines)
    when 'INSTALL', 'SIMULATE'
      name, text = rest.split(/ /, 2)
      text ||= '*'
      constraint(text)
      raise PackageError, "unknown package #{name}" unless @registry.key?(name)
      requests = @requests.map(&:dup)
      index = requests.index { |n, _| n == name }
      index ? requests[index] = [name, text] : requests << [name, text]
      resolve_and_plan(requests, @installed.keys, false, command == 'SIMULATE')
    when 'REMOVE'
      unless @requests.any? { |n, _| n == name }
        raise PackageError, @installed.key?(name) ? "#{name} is required by #{required_by(name)}" : "#{name} is not installed"
      end
      requests = @requests.reject { |n, _| n == name }
      keep = requests.map(&:first)
      keep.each { |n| dependencies(n).each { |d, _| keep << d unless keep.include?(d) } }
      if keep.include?(name)
        puts "#{name}@#{@installed[name]} is still required by #{required_by(name)}"
        update(requests, @installed.dup)
      else
        installed = @installed.select { |n, _| keep.include?(n) }
        plan(installed)
        update(requests, installed)
      end
    when 'UPGRADE'
      require_installed(name) if name
      resolve_and_plan(@requests.map(&:dup), name ? @installed.keys - [name] : [])
    when 'ROLLBACK'
      raise PackageError, 'nothing to roll back' if @history.empty?
      requests, installed = @history.pop
      plan(installed)
      @requests = requests
      @installed = installed
      @held &= installed.keys
    when 'HOLD'
      require_installed(name)
      raise PackageError, "#{name} is already held" if @held.include?(name)
      @held << name
      puts "held #{name}@#{@installed[name]}"
    when 'UNHOLD'
      raise PackageError, "#{name} is not held" unless @held.include?(name)
      @held.delete(name)
      puts "released #{name}"
    when 'WHY'
      require_installed(name)
      if @requests.any? { |n, _| n == name }
        puts "#{name}@#{@installed[name]} is explicitly installed"
      else
        queue = @requests.map(&:first).sort
        parent = queue.to_h { |n| [n, nil] }
        queue.each do |n|
          dependencies(n).map(&:first).sort.each do |d|
            next if parent.key?(d)
            parent[d] = n
            queue << d
          end
        end
        path = [name]
        path.unshift(parent[path.first]) while parent[path.first]
        puts path.map { |n| "#{n}@#{@installed[n]}" }.join(' -> ')
      end
    when 'TREE'
      tree(name)
    when 'OUTDATED'
      lines = []
      @installed.keys.sort.each do |n|
        current = @installed[n]
        constraints = @requests.select { |d, _| d == n }.map(&:last)
        @installed.each_key { |q| dependencies(q).each { |d, c| constraints << c if d == n } }
        wanted = versions(n).find { |v| (!record(n, v)[:yanked] || v == current) && constraints.all? { |c| matches?(c, v) } }
        latest = versions(n).find { |v| !record(n, v)[:yanked] && Version.parse(v).pre.nil? }
        lines << "#{n} #{current} #{wanted} #{latest || '-'}" if wanted != current || (latest && Version.parse(latest) > Version.parse(current))
      end
      puts(lines.empty? ? ['all packages are up to date'] : lines)
    when 'LOCK'
      puts '(empty)' if @installed.empty?
      @installed.keys.sort.each { |n| puts "#{n}@#{@installed[n]}" }
    when 'STATUS'
      puts 'no requests' if @requests.empty?
      @requests.each { |n, c| puts "#{n} #{c} -> #{@installed[n]}" }
      puts "#{@installed.length} installed, #{@held.length} held, #{@history.length} snapshots"
    when 'ADVISORY'
      id, n, text = rest.split(/ /, 3)
      raise PackageError, "advisory #{id} already exists" if @advisories.key?(id)
      constraint(text)
      @advisories[id] = [n, text]
      puts "advisory #{id} recorded"
    when 'AUDIT'
      if name == 'FIX'
        resolve_and_plan(@requests.map(&:dup), @installed.keys, true)
      else
        lines = []
        @installed.keys.sort.each do |n|
          current = @installed[n]
          ids = advisories(n, current)
          next if ids.empty?
          fix = versions(n).reverse.find { |v| Version.parse(v) > Version.parse(current) && Version.parse(v).pre.nil? && !record(n, v)[:yanked] && advisories(n, v).empty? }
          lines << "#{n}@#{current}: #{ids.join(', ')} (#{fix ? "fix: #{fix}" : 'no fix'})"
        end
        puts(lines.empty? ? ['no known vulnerabilities'] : lines)
      end
    end
  rescue PackageError => error
    puts "error: #{error.message}"
  end
end

manager = PackageManager.new
count = STDIN.gets.to_i
count.times { manager.execute(STDIN.gets.chomp) }
