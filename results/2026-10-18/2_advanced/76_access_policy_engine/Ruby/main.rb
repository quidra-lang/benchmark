require_relative 'rbac'
require_relative 'policy_parser'
require_relative 'combining'
require_relative 'analysis'

DEFINITE = %w[PERMIT DENY].freeze
Request = Struct.new(:id, :user, :roles, :action, :resource, :environment, :explain)
EvalError = Struct.new(:reason)

def input_value(text)
  return text == 'true' if %w[true false].include?(text)
  return text[1...-1].split(',') if text.start_with?('[')
  return text.to_i if text.match?(/\A-?[0-9]+\z/)
  text
end

def attributes(fields)
  fields.to_h { |field| name, value = field.split('=', 2); [name, input_value(value)] }
end

def value_notation(value)
  case value
  when true then 'true'
  when false then 'false'
  when Integer then value.to_s
  when String then '"' + value + '"'
  else '[' + value.map { |item| value_notation(item) }.join(',') + ']'
  end
end

def boolean?(value) = value.equal?(true) || value.equal?(false)
def first_error(values) = values.find { |value| value.is_a?(EvalError) }

def boolean_result(values, veto, name)
  checked = values.map { |v| boolean?(v) || v.is_a?(EvalError) ? v : EvalError.new("type #{name}") }
  return veto if checked.any? { |v| v.equal?(veto) }
  first_error(checked) || !veto
end

def operation(name, values)
  error = first_error(values)
  return error if error
  a, b = values
  case name
  when '+', '-', '*', '<', '<=', '>', '>='
    if values.all? { |v| v.is_a?(Integer) }
      return -a if values.length == 1
      return a.public_send(name, b)
    end
  when '==', '!='
    same_type = (a.is_a?(Integer) && b.is_a?(Integer)) || (a.is_a?(String) && b.is_a?(String)) || (boolean?(a) && boolean?(b))
    return name == '==' ? a == b : a != b if same_type
  when 'in'
    return b.include?(a) if a.is_a?(String) && b.is_a?(Array)
  when 'not'
    return !a if boolean?(a)
  when 'starts_with', '^='
    return a.start_with?(b) if a.is_a?(String) && b.is_a?(String)
  when 'size'
    return a.length if a.is_a?(Array)
  end
  EvalError.new("type #{name}")
end

def expression(tree, values, current = nil)
  name, *arguments = tree
  case name
  when 'literal' then return arguments.first
  when 'attribute' then return values.fetch(arguments.first) { EvalError.new("missing #{arguments.first}") }
  when 'it' then return current
  when 'present' then return values.key?(arguments.first[1])
  when 'any_of', 'all_of'
    bag = expression(arguments.first, values, current)
    return bag if bag.is_a?(EvalError)
    return EvalError.new("type #{name}") unless bag.is_a?(Array)
    return boolean_result(bag.map { |item| expression(arguments[1], values, item) }, name == 'any_of', name)
  end
  operands = arguments.map { |argument| expression(argument, values, current) }
  return boolean_result(operands, name == 'or', name) if %w[and or].include?(name)
  operation(name, operands)
end

def target_group(results, conjunction)
  if conjunction
    return ['NO_MATCH', nil] if results.any? { |result, _| result == 'NO_MATCH' }
    return ['MATCH', nil] if results.all? { |result, _| result == 'MATCH' }
  else
    return ['MATCH', nil] if results.any? { |result, _| result == 'MATCH' }
  end
  results.find { |result, _| result == 'INDETERMINATE' } || ['NO_MATCH', nil]
end

def match_clause(clause, values)
  reference, mandatory, name, literal = clause
  unless values.key?(reference)
    return mandatory ? ['INDETERMINATE', "missing #{reference}"] : ['NO_MATCH', nil]
  end
  source = values[reference]
  items = source.is_a?(Array) ? source : [source]
  comparison = expression(literal, values)
  results = items.map { |item| operation(name, [item, comparison]) }
  return ['MATCH', nil] if results.any? { |result| result.equal?(true) }
  error = first_error(results)
  error ? ['INDETERMINATE', error.reason] : ['NO_MATCH', nil]
end

def decision_notation(decision, reason)
  decision.start_with?('INDETERMINATE') ? "#{decision} (#{reason})" : decision
end

def final_notation(result)
  text = decision_notation(result.decision, result.reason)
  text += " by #{result.decisive.id}" if DEFINITE.include?(result.decision)
  text
end

class Evaluation
  attr_accessor :element, :target, :decision, :reason, :decisive, :condition, :children, :obligations, :advice

  def initialize(element, target)
    @element, @target, @decision = element, target, Combining::NA
    @children, @obligations, @advice = [], [], []
  end
end

class Evaluator
  def initialize(values, coverage = nil)
    @values, @coverage = values, coverage
  end

  def target(element)
    lines = element.targets.map do |line|
      alternatives = line.map { |alternative| target_group(alternative.map { |clause| match_clause(clause, @values) }, true) }
      target_group(alternatives, false)
    end
    target_group(lines, true)
  end

  def attachments(result, supporters)
    supporters.each do |supporter|
      result.obligations.concat(supporter.obligations)
      result.advice.concat(supporter.advice)
    end
    effect = result.decision
    [[true, result.element.obligations], [false, result.element.advice]].each do |obligatory, definitions|
      definitions.each do |required_effect, id, arguments|
        next unless required_effect == effect
        evaluated = arguments.map { |name, tree| [name, expression(tree, @values)] }
        error = first_error(evaluated.map(&:last))
        if error
          if obligatory
            result.decision = effect == 'DENY' ? Combining::ID : Combining::IP
            result.reason = "obligation #{id}: #{error.reason}"
            result.decisive = nil
            result.obligations, result.advice = [], []
            return
          end
          next
        end
        item = id + evaluated.map { |name, value| " #{name}=#{value_notation(value)}" }.join
        (obligatory ? result.obligations : result.advice) << [id, item]
      end
    end
  end

  def rule(element, obligations = true)
    result = Evaluation.new(element, target(element))
    match, reason = result.target
    indeterminate = element.behavior == 'DENY' ? Combining::ID : Combining::IP
    if match == 'INDETERMINATE'
      result.decision, result.reason = indeterminate, reason
    elsif match == 'MATCH'
      condition = element.condition ? expression(element.condition, @values) : true
      condition = EvalError.new('type condition') unless boolean?(condition) || condition.is_a?(EvalError)
      result.condition = condition
      if condition.is_a?(EvalError)
        result.decision, result.reason = indeterminate, condition.reason
      elsif condition
        result.decision, result.decisive = element.behavior, element
        attachments(result, []) if obligations
      end
    end
    @coverage[element.id] = { 'PERMIT' => 'P', 'DENY' => 'D', Combining::NA => '-' }.fetch(result.decision, 'I') if @coverage
    result
  end

  def evaluate(element)
    return rule(element) if element.kind == 'rule'
    result = Evaluation.new(element, target(element))
    match, reason = result.target
    return result if match == 'NO_MATCH'
    result.decision, result.reason, result.children = Combining.combine(element.behavior, element.children, method(:evaluate), method(:target))
    if match == 'INDETERMINATE'
      result.decision = result.decision == 'DENY' ? Combining::ID : Combining::IP if DEFINITE.include?(result.decision)
      result.reason = reason if result.decision.start_with?('INDETERMINATE')
    end
    if DEFINITE.include?(result.decision)
      supporters = result.children.filter_map { |state| state[1] if state && state[0] == :evaluated && state[1].decision == result.decision }
      result.decisive = supporters.empty? ? element : supporters.first.decisive
      attachments(result, supporters)
    end
    result
  end
end

def tree_lines(result, depth = 0)
  element, target = result.element, result.target.first
  prefix = ' ' * (2 + 2 * depth)
  line = "#{prefix}#{element.kind} #{element.id} #{element.behavior} target #{target}"
  if element.kind == 'rule' && target == 'MATCH'
    condition = result.condition.is_a?(EvalError) ? 'INDETERMINATE' : (result.condition ? 'TRUE' : 'FALSE')
    line += " condition #{condition}"
  end
  lines = [line + ' -> ' + decision_notation(result.decision, result.reason)]
  if element.kind != 'rule' && target != 'NO_MATCH'
    element.children.zip(result.children).each do |child, state|
      if state && state.first == :evaluated
        lines.concat(tree_lines(state[1], depth + 1))
      elsif state.nil?
        lines << "#{prefix}  #{child.kind} #{child.id} skipped"
      else
        checked, reason = state[1]
        text = "#{prefix}  #{child.kind} #{child.id} #{child.behavior} target #{checked}"
        text += " (#{reason})" if checked == 'INDETERMINATE'
        lines << text
      end
    end
  end
  lines
end

def join_blocks(blocks) = blocks.map { |block| block.join("\n") }.join("\n\n")

class Engine
  def initialize
    @rbac = RBAC.new
    @root, @elements = PolicyParser.read
    @rules = @elements.select { |element| element.kind == 'rule' }
    @subjects, @resources, @domains, @reference = {}, {}, [], {}
    File.foreach('input/attributes.txt') do |line|
      kind, *fields = line.split
      case kind
      when 'SUBJECT' then @subjects[fields[0]] = attributes(fields.drop(1))
      when 'RESOURCE' then @resources[fields[0]] = [fields[1], attributes(fields.drop(2))]
      when 'DOMAIN' then @domains << [fields[0], fields.drop(1).map { |value| input_value(value) }]
      when 'REFERENCE' then @reference = attributes(fields)
      end
    end
    @requests = File.readlines('input/requests.txt').map do |line|
      fields = line.split
      explain = fields.last == 'EXPLAIN'
      fields.pop if explain
      Request.new(*fields.first(5), attributes(fields.drop(5)), explain)
    end
    @coverage = @rules.to_h { |rule| [rule.id, []] }
    @grant_counts, @decisions, @decisive = Hash.new(0), Hash.new(0), Hash.new(0)
    @obligations, @advice, @refused = Hash.new(0), Hash.new(0), 0
  end

  def check_request(request)
    return "unknown user #{request.user}" unless @subjects.key?(request.user)
    return "unknown resource #{request.resource}" unless @resources.key?(request.resource)
    day = request.environment['day']
    return 'bad day' unless day.is_a?(Integer) && day.between?(1, 365)
    nil
  end

  def activate(user, specification, day)
    authorized = @rbac.authorized(user, day)
    candidates = specification == '-' ? [] : (specification == '*' ? authorized.sort : specification.split(','))
    active, seen, activations = [], Set.new, []
    candidates.each do |candidate|
      reason = if !@rbac.roles.include?(candidate)
                 'unknown'
               elsif seen.include?(candidate)
                 'duplicate'
               elsif !authorized.include?(candidate)
                 'unauthorized'
               else
                 closure = @rbac.closure([*active, candidate])
                 constraint = @rbac.dsd.find { |_, cardinality, roles| (roles & closure).size >= cardinality }
                 "dsd #{constraint.first}" if constraint
               end
      seen << candidate
      active << candidate unless reason
      activations << [candidate, reason]
    end
    [activations, @rbac.closure(active).sort]
  end

  def prepare(request)
    activations, roles = activate(request.user, request.roles, request.environment['day'])
    type, resource_attributes = @resources[request.resource]
    grant = roles.find { |role| @rbac.permissions[role].include?([request.action, type]) }
    values = @subjects[request.user].to_h { |name, value| ["subject.#{name}", value] }
    values.merge!('subject.id' => request.user, 'subject.role' => roles, 'subject.rbac' => !grant.nil?)
    resource_attributes.each { |name, value| values["resource.#{name}"] = value }
    values.merge!('resource.id' => request.resource, 'resource.type' => type, 'action.id' => request.action)
    request.environment.each { |name, value| values["environment.#{name}"] = value }
    [activations, roles, grant, values]
  end

  def trace(request, activations, roles, grant, result)
    type = @resources[request.resource].first
    lines = ["request #{request.id}", "  user #{request.user} resource #{request.resource} type #{type} action #{request.action} day #{request.environment['day']}"]
    activations.each { |role, reason| lines << "  activate #{role} " + (reason ? "refused #{reason}" : 'ok') }
    lines << '  roles ' + (roles.empty? ? '-' : roles.join(','))
    lines << '  rbac ' + (grant ? "yes #{grant}" : 'no')
    lines.concat(tree_lines(result))
    lines << '  decision ' + final_notation(result)
  end

  def process_requests
    lines, explanations = [], []
    @requests.each do |request|
      coverage = @rules.to_h { |rule| [rule.id, '.'] }
      error = check_request(request)
      if error
        lines << "#{request.id} ERROR #{error}"
        @decisions['ERROR'] += 1
        explanations << ["request #{request.id}", "  error #{error}"] if request.explain
      else
        activations, roles, grant, values = prepare(request)
        result = Evaluator.new(values, coverage).evaluate(@root)
        lines << "#{request.id} #{final_notation(result)}"
        activations.each do |role, reason|
          next unless reason
          lines << "  refused #{role} #{reason}"
          @refused += 1
        end
        [['obligation', result.obligations, @obligations], ['advice', result.advice, @advice]].each do |kind, items, counts|
          items.each do |id, item|
            lines << "  #{kind} #{item}"
            counts[id] += 1
          end
        end
        @grant_counts[[grant, request.action, @resources[request.resource].first]] += 1 if grant
        category = result.decision.start_with?('INDETERMINATE') ? 'INDETERMINATE' : result.decision
        @decisions[category] += 1
        @decisive[result.decisive.id] += 1 if DEFINITE.include?(result.decision)
        explanations << trace(request, activations, roles, grant, result) if request.explain
      end
      @rules.each { |rule| @coverage[rule.id] << coverage[rule.id] }
    end
    [lines, join_blocks(explanations)]
  end

  def permission_report
    blocks = @rbac.assignments.map(&:first).uniq.sort.map do |user|
      assigned = Hash.new { |hash, role| hash[role] = Set.new }
      authorized = Hash.new { |hash, role| hash[role] = Set.new }
      @rbac.assignments.each { |owner, role, first, last| assigned[role].merge(first..last) if owner == user }
      assigned.each { |role, days| @rbac.closure([role]).each { |inherited| authorized[inherited].merge(days) } }
      lines = ["user #{user}"]
      [['assigned', assigned], ['authorized', authorized]].each do |kind, mapping|
        mapping.keys.sort.each { |role| lines << "  #{kind} #{role} #{Analysis.day_notation(mapping[role])}" }
      end
      via = Hash.new { |hash, pair| hash[pair] = [] }
      authorized.keys.sort.each { |role| @rbac.permissions[role].each { |pair| via[pair] << role } }
      via.keys.sort.each do |action, type|
        roles = via[[action, type]]
        days = roles.each_with_object(Set.new) { |role, set| set.merge(authorized[role]) }
        effective = '-'
        if @subjects.key?(user)
          resources = @resources.keys.select { |id| @resources[id].first == type }
          permitted = resources.count do |resource|
            request = Request.new('', user, '*', action, resource, @reference, false)
            values = prepare(request).last
            Evaluator.new(values).evaluate(@root).decision == 'PERMIT'
          end
          effective = "#{permitted}/#{resources.length}"
        end
        lines << "  permission #{action} #{type} #{Analysis.day_notation(days)} via #{roles.join(',')} effective #{effective}"
      end
      lines
    end
    join_blocks(blocks)
  end

  def domain_analysis
    counts, examples, conflict_counts = Hash.new(0), {}, Hash.new(0)
    ancestors = @rules.to_h do |rule|
      chain, parent = [], rule.parent
      while parent
        chain << parent.id
        parent = parent.parent
      end
      [rule.id, chain]
    end
    shadowed = @rules.select { |rule| rule.parent.behavior == 'first-applicable' }.map(&:id).to_set
    blockers = Hash.new { |hash, id| hash[id] = Set.new }
    pairs = @elements.select { |e| e.kind == 'policy' }.flat_map do |policy|
      policy.children.combination(2).filter_map { |a, b| [policy, a, b] if a.behavior != b.behavior }
    end
    point_count = 0
    Analysis.points(@domains) do |values|
      point_count += 1
      evaluator = Evaluator.new(values)
      targets = @elements.reject { |e| e.kind == 'rule' }.to_h { |e| [e.id, evaluator.target(e).first] }
      standalone = @rules.to_h { |rule| [rule.id, evaluator.rule(rule, false).decision] }
      applying = Set.new
      @rules.each do |rule|
        id = rule.id
        next unless DEFINITE.include?(standalone[id]) && ancestors[id].all? { |parent| targets[parent] == 'MATCH' }
        applying << id
        counts[id] += 1
        examples[id] ||= @domains.filter_map { |name, candidates| "#{name}=#{value_notation(values[name])}" if candidates.length >= 2 }.join(' ')
        next unless shadowed.include?(id)
        earlier = Analysis.blocker(rule, standalone)
        earlier ? blockers[id].add(earlier) : shadowed.delete(id)
      end
      pairs.each { |policy, a, b| conflict_counts[[policy.id, a.id, b.id]] += 1 if applying.include?(a.id) && applying.include?(b.id) }
    end
    lines = ["applicability #{point_count}"]
    @rules.each { |rule| lines << "  #{rule.id} #{counts[rule.id]} #{examples.fetch(rule.id, '-')}" }
    dead = @rules.select { |rule| counts[rule.id].zero? }.map(&:id)
    lines << "dead #{dead.length}"
    lines.concat(dead.map { |id| "  #{id}" })
    shadowed.subtract(dead)
    lines << "shadowed #{shadowed.size}"
    @rules.each do |rule|
      next unless shadowed.include?(rule.id)
      names = @rules.map(&:id).select { |id| blockers[rule.id].include?(id) }
      lines << "  #{rule.id} by #{names.join(',')}"
    end
    conflicts = pairs.select { |policy, a, b| conflict_counts[[policy.id, a.id, b.id]] > 0 }
    lines << "conflicts #{conflicts.length}"
    conflicts.each do |policy, a, b|
      lines << "  #{policy.id} #{a.id} #{b.id} #{conflict_counts[[policy.id, a.id, b.id]]} #{Analysis.conflict_winner(policy, a, b)}"
    end
    lines
  end

  def analysis_report
    lines = ["rbac #{@rbac.diagnostics.length}"]
    @rbac.diagnostics.each { |number, keyword, message| lines << "  line #{number} #{keyword} #{message}" }
    lines << "grants #{@rbac.grants.size}"
    @rbac.grants.sort.each { |role, action, type| lines << "  #{role} #{action} #{type} #{@grant_counts[[role, action, type]]}" }
    lines.concat(domain_analysis)
    lines << "coverage #{@requests.length}"
    uncovered = []
    @rules.each do |rule|
      symbols = @coverage[rule.id].join
      count = symbols.count('PD')
      lines << "  #{rule.id} #{symbols} #{count}"
      uncovered << rule.id if count.zero?
    end
    lines << "uncovered #{uncovered.length}"
    lines.concat(uncovered.map { |id| "  #{id}" })
    lines << 'summary'
    ['PERMIT', 'DENY', Combining::NA, 'INDETERMINATE', 'ERROR'].each { |name| lines << "  decision #{name} #{@decisions[name]}" }
    lines << "  refused #{@refused}"
    @elements.each { |element| lines << "  decisive #{element.id} #{@decisive[element.id]}" if @decisive[element.id] > 0 }
    [['obligation', @obligations], ['advice', @advice]].each do |kind, counts|
      counts.keys.sort.each { |id| lines << "  #{kind} #{id} #{counts[id]}" }
    end
    lines
  end

  def run
    decisions, traces = process_requests
    reports = { 'decisions.txt' => decisions.join("\n"), 'traces.txt' => traces,
                'permissions.txt' => permission_report, 'analysis.txt' => analysis_report.join("\n") }
    Dir.mkdir('output') unless Dir.exist?('output')
    reports.each { |name, text| File.write("output/#{name}", text.empty? ? '' : text + "\n") }
  end
end

Engine.new.run if $PROGRAM_NAME == __FILE__
