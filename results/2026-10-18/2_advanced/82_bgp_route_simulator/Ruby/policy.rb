require_relative 'topology'

module Policy
  NO_EXPORT = [65_535, 65_281].freeze

  def self.community(text)
    text == 'NO_EXPORT' ? NO_EXPORT : text.split(':').map(&:to_i).freeze
  end

  def self.communities(values) = values.map { |value| community(value) }.uniq.sort.freeze
  def self.community_text(value) = value == NO_EXPORT ? 'NO_EXPORT' : value.join(':')

  def self.communities_text(values)
    values.empty? ? '-' : values.sort.map { |value| community_text(value) }.join(',')
  end

  def self.edit(communities, rule)
    edited = communities.dup
    rule.actions.each do |action, value|
      edited << value if action == 'ADD' && !edited.include?(value)
      edited.delete(value) if action == 'REMOVE'
    end
    edited.sort.freeze
  end

  class Rule
    attr_reader :name, :owner, :direction, :target, :conditions, :actions
    attr_accessor :active, :hits

    def initialize(name, state, owner, direction, target, conditions, actions)
      @name, @owner, @direction, @target = name, owner, direction, target
      @conditions, @actions, @settings = conditions, actions, actions.to_h
      @active, @hits = state == 'ON', 0
    end

    def has?(action) = @settings.key?(action)
    def value(action, default) = @settings.fetch(action, default)
  end

  class Policies
    attr_reader :rules, :by_name

    def initialize(lists, rules)
      @lists, @rules = lists, rules
      @by_name = rules.to_h { |rule| [rule.name, rule] }
      @by_direction = rules.group_by { |rule| [rule.owner, rule.direction] }
    end

    def permitted?(name, prefix)
      @lists.fetch(name).each do |permit, base, low, high|
        return permit if prefix[1].between?(low, high) && Topology.contains?(base, prefix[0])
      end
      false
    end

    def matches?(rule, owner, link, prefix, path, communities)
      return false unless rule.active && rule.owner == owner
      return false unless ['*', link.other(owner).to_s, link.name].include?(rule.target)

      rule.conditions.all? do |condition, value|
        case condition
        when 'PREFIX' then permitted?(value, prefix)
        when 'CONTAINS' then path.include?(value)
        when 'ORIGINAS' then (path.last || owner) == value
        when 'LENGTH' then path.length.between?(*value)
        when 'COMMUNITY' then communities.include?(value)
        end
      end
    end

    def applied(direction, owner, link, prefix, path, communities)
      @by_direction.fetch([owner, direction], []).find do |rule|
        matches?(rule, owner, link, prefix, path, communities)
      end
    end
  end

  def self.read
    lists = Hash.new { |hash, key| hash[key] = [] }
    rules = []
    File.foreach('input/policies.txt', chomp: true) do |line|
      fields = line.split(' ')
      if fields[0] == 'PLIST'
        base = Topology.prefix(fields[3])
        bounds = fields.drop(4).each_slice(2).to_h
        low = bounds.fetch('GE', base[1]).to_i
        high = bounds.fetch('LE', bounds.key?('GE') ? 32 : base[1]).to_i
        lists[fields[1]] << [fields[2] == 'PERMIT', base, low, high]
        next
      end
      separator = fields.index('THEN')
      conditions = fields[6...separator].each_slice(2).map do |condition, value|
        value = case condition
                when 'CONTAINS', 'ORIGINAS' then value.to_i
                when 'LENGTH' then value.split('-').map(&:to_i)
                when 'COMMUNITY' then community(value)
                else value
                end
        [condition, value]
      end
      actions = []
      index = separator + 1
      while index < fields.length
        action = fields[index]
        index += 1
        value = nil
        unless ['DENY', 'ALLOW'].include?(action)
          value = ['ADD', 'REMOVE'].include?(action) ? community(fields[index]) : fields[index].to_i
          index += 1
        end
        actions << [action, value]
      end
      rules << Rule.new(fields[1], fields[2], fields[3].to_i, fields[4], fields[5], conditions, actions)
    end
    Policies.new(lists, rules)
  end
end
