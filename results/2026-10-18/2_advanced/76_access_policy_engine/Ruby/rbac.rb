require 'set'

class RBAC
  attr_reader :roles, :inherits, :permissions, :ssd, :dsd, :assignments, :diagnostics, :grants

  def initialize(path = 'input/rbac.txt')
    @roles, @inherits, @permissions, @grants = Set.new, {}, {}, Set.new
    @ssd, @dsd, @assignments, @diagnostics = [], [], [], []
    lines = File.readlines(path).map.with_index(1) { |line, number| [number, line.split] }
    %w[ROLE INHERITS PERMIT SSD DSD ASSIGN].each do |keyword|
      lines.each do |number, fields|
        next unless fields.first == keyword
        error = accept(keyword, fields.drop(1))
        @diagnostics << [number, keyword, error] if error
      end
    end
    @diagnostics.sort_by!(&:first)
  end

  def closure(roles)
    reached = roles.to_set.dup
    pending = reached.to_a
    until pending.empty?
      @inherits[pending.pop].each do |junior|
        pending << junior if reached.add?(junior)
      end
    end
    reached
  end

  def path(start, finish, failed = Set.new)
    return [start] if start == finish
    return nil if failed.include?(start)
    @inherits[start].sort.each do |junior|
      suffix = path(junior, finish, failed)
      return [start, *suffix] if suffix
    end
    failed << start
    nil
  end

  def assigned(user, day)
    @assignments.filter_map { |owner, role, first, last| role if owner == user && day.between?(first, last) }.to_set
  end

  def authorized(user, day) = closure(assigned(user, day))

  def accept(keyword, fields)
    case keyword
    when 'ROLE'
      role = fields.first
      return "duplicate role #{role}" if @roles.include?(role)
      @roles << role
      @inherits[role], @permissions[role] = Set.new, Set.new
    when 'INHERITS'
      senior, junior = fields
      fields.each { |role| return "unknown role #{role}" unless @roles.include?(role) }
      return "duplicate inheritance #{senior} #{junior}" if @inherits[senior].include?(junior)
      return 'cycle ' + [senior, *path(junior, senior)].join(' > ') if closure([junior]).include?(senior)
      @inherits[senior] << junior
    when 'PERMIT'
      role, action, type = fields
      return "unknown role #{role}" unless @roles.include?(role)
      return "duplicate permission #{role} #{action} #{type}" if @permissions[role].include?([action, type])
      @permissions[role] << [action, type]
      @grants << fields
    when 'SSD', 'DSD'
      name, cardinality, list = fields
      constraints = keyword == 'SSD' ? @ssd : @dsd
      return "duplicate constraint #{name}" if constraints.any? { |item| item.first == name }
      roles = list.split(',')
      roles.each { |role| return "unknown role #{role}" unless @roles.include?(role) }
      cardinality = cardinality.to_i
      return "bad cardinality #{name} #{cardinality}" unless cardinality.between?(2, roles.length)
      constraints << [name, cardinality, roles.to_set]
    when 'ASSIGN'
      user, role, first, last = fields
      return "unknown role #{role}" unless @roles.include?(role)
      first, last = first.to_i, last.to_i
      return "bad range #{first} #{last}" unless first >= 1 && first <= last && last <= 365
      @ssd.each do |name, cardinality, roles|
        (first..last).each do |day|
          intersection = roles & closure(assigned(user, day).add(role))
          return "ssd #{name} day #{day} roles #{intersection.sort.join(',')}" if intersection.size >= cardinality
        end
      end
      @assignments << [user, role, first, last]
    end
    nil
  end
end
