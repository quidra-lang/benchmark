# frozen_string_literal: true

require 'set'
require_relative 'ini_parser'
require_relative 'schema'
require_relative 'interpolate'
require_relative 'emitter'

Definition = Struct.new(:value, :origin, :number, :history)
OutputValue = Struct.new(:value, :type, :spec, :definition, :notation)
Profile = Struct.new(:name, :root, :configuration, :output, :diagnostics, :includes,
                     :counts, :overridden, :dropped, :errors, :warnings, keyword_init: true)

class Validator
  def initialize
    @schema = IniSchema::Schema.new('input/schema.txt')
    @documents = {}
    @fixed = {}
  end

  def report(origin, code, message)
    document, _, number = origin.rpartition(':')
    @diagnostics.add([document, number.to_i, code, message])
  end

  def define(key, value, origin)
    @definition_number += 1
    history = @configuration.key?(key) ? @configuration[key].history.dup : []
    history << origin unless history.last == origin
    @configuration[key] = Definition.new(value, origin, @definition_number, history)
  end

  def document(name)
    @documents[name] = IniParser.read(name) unless @documents.key?(name)
    @documents[name]
  end

  def apply_document(name, chain)
    parsed = document(name)
    @includes << [chain.length - 1, name]
    parsed.diagnostics.each { |diagnostic| @diagnostics.add(diagnostic) }
    parsed.statements.each do |statement|
      origin = "#{name}:#{statement.line}"
      case statement.kind
      when :assign
        define(statement.key, statement.value, origin)
      when :append
        old = @configuration[statement.key]
        value = old && !old.value.empty? ? old.value + ',' + statement.value : statement.value
        define(statement.key, value, origin)
      when :unset
        if @configuration.key?(statement.key)
          @configuration.delete(statement.key)
        else
          report(origin, 'W_UNSET', "#{statement.key} is not set")
        end
      when :inherit
        @parents[statement.key] = [statement.value, origin]
      when :include
        target = statement.key
        if chain.include?(target)
          path = chain[chain.index(target)..] + [target]
          report(origin, 'E_INCLUDE_CYCLE', "include cycle #{path.join(' -> ')}")
          @includes << [chain.length, "#{target} (cycle)"]
        elsif document(target).nil?
          report(origin, 'E_INCLUDE_MISSING', "missing document #{target}")
          @includes << [chain.length, "#{target} (missing)"]
        else
          apply_document(target, chain + [target])
        end
      end
    end
  end

  def inherit_sections
    own = Hash.new { |hash, section| hash[section] = {} }
    @configuration.each do |key, definition|
      section, name = IniSchema.split_key(key)
      own[section][name] = definition
    end
    @parents.each do |section, (parent, origin)|
      path = [section]
      seen = Set.new(path)
      while @parents.key?(path.last) && !seen.include?(@parents[path.last][0])
        path << @parents[path.last][0]
        seen.add(path.last)
      end
      if @parents.key?(path.last)
        path << @parents[path.last][0]
        report(origin, 'E_INHERIT_CYCLE', "inheritance cycle #{path.join(' -> ')}")
        next
      end
      if !@parents.key?(parent) && own[parent].empty?
        report(origin, 'W_PARENT_EMPTY', "section #{section} inherits from empty section #{parent}")
      end
      path.drop(1).each do |ancestor|
        own[ancestor].each do |name, definition|
          key = "#{section}.#{name}"
          @configuration[key] = definition unless @configuration.key?(key)
        end
      end
    end
  end

  def resolve_aliases
    @schema.specs.each do |spec|
      aliases = spec.attributes['alias']&.split(',')
      next if aliases.nil?

      candidates = [spec.pattern, *aliases].select { |key| @configuration.key?(key) }
      next unless aliases.any? { |key| @configuration.key?(key) }

      winner = candidates.first
      candidates.drop(1).each do |key|
        winner = key if @configuration[key].number > @configuration[winner].number
      end
      aliases.each do |key|
        report(@configuration[key].origin, 'W_DEPRECATED', "#{key} is deprecated, use #{spec.pattern}") if @configuration.key?(key)
      end
      candidates.each do |key|
        next if key == winner

        report(@configuration[key].origin, 'W_SHADOWED', "#{key} is superseded by #{winner} at #{@configuration[winner].origin}")
      end
      @configuration[spec.pattern] = @configuration[winner]
      aliases.each { |key| @configuration.delete(key) }
    end
  end

  def defaults
    @sections = Set.new(@configuration.keys.map { |key| IniSchema.split_key(key)[0] })
    @schema.specs.each do |spec|
      next unless spec.attributes.key?('default')

      @schema.targets(spec, @sections).each do |key|
        define(key, spec.attributes['default'], "schema:#{spec.line}") unless @configuration.key?(key)
      end
    end
  end

  def integer(value)
    match = /\A([+-]?)(?:0[xX]([0-9a-fA-F]{1,10})|([0-9](?:_?[0-9])*))\z/.match(value)
    return nil unless match

    if match[2]
      number = match[2].to_i(16)
    else
      digits = match[3].delete('_')
      return nil if digits.length > 12

      number = digits.to_i(10)
    end
    match[1] == '-' ? -number : number
  end

  def size(value)
    match = /\A([0-9]{1,6})(?:\.([0-9]{1,3}))?(B|KB|MB|GB)?\z/i.match(value)
    return nil unless match

    factor = { '' => 1, 'B' => 1, 'KB' => 1024, 'MB' => 1_048_576, 'GB' => 1_073_741_824 }.fetch((match[3] || '').upcase)
    result = match[1].to_i * factor
    if match[2]
      numerator = match[2].to_i * factor
      denominator = 10**match[2].length
      return nil unless (numerator % denominator).zero?

      result += numerator / denominator
    end
    result
  end

  def duration(value)
    return value.to_i if /\A[0-9]{1,6}\z/.match?(value)

    match = /\A(?:([0-9]{1,6})h)?(?:([0-9]{1,6})m)?(?:([0-9]{1,6})s)?\z/.match(value)
    return nil if match.nil? || value.empty?

    match[1].to_i * 3600 + match[2].to_i * 60 + match[3].to_i
  end

  def host(value)
    labels = value.split('.', -1)
    if /\A[0-9.]*\z/.match?(value)
      valid = labels.length == 4 && labels.all? { |label|
        /\A[0-9]{1,3}\z/.match?(label) && (label == '0' || !label.start_with?('0')) && label.to_i <= 255
      }
      return nil unless valid

      value
    else
      return nil if value.length > 253 || labels.empty?
      valid = labels.all? { |label|
        /\A[A-Za-z0-9-]{1,63}\z/.match?(label) && !label.start_with?('-') && !label.end_with?('-')
      }
      return nil unless valid

      value.downcase
    end
  end

  def path(value)
    return nil if value.empty? || /[ \n\t]/.match?(value)

    absolute = value.start_with?('/')
    parts = []
    value.split('/', -1).each do |part|
      next if part.empty? || part == '.'

      if part == '..'
        if !parts.empty? && parts.last != '..'
          parts.pop
        elsif absolute
          return nil
        else
          parts << part
        end
      else
        parts << part
      end
    end
    return '/' + parts.join('/') if absolute

    parts.empty? ? '.' : parts.join('/')
  end

  def url(value)
    scheme, separator, rest = value.partition('://')
    return nil if separator.empty? || !/\A[A-Za-z][A-Za-z0-9+.-]*\z/.match?(scheme) || /[?#]/.match?(rest)

    authority, _, tail = rest.partition('/')
    hostname, colon, port = authority.partition(':')
    normalized_host = host(hostname)
    normalized_path = path('/' + tail)
    return nil if normalized_host.nil? || normalized_path.nil?

    unless colon.empty?
      return nil unless /\A[1-9][0-9]{0,4}\z/.match?(port) && port.to_i <= 65_535
    end
    scheme = scheme.downcase
    default = { 'http' => 80, 'https' => 443 }[scheme]
    suffix = !colon.empty? && port.to_i != default ? ':' + port : ''
    scheme + '://' + normalized_host + suffix + normalized_path
  end

  def date(value)
    match = /\A([0-9]{4})-([0-9]{2})-([0-9]{2})\z/.match(value)
    return nil unless match

    year, month, day = match.captures.map(&:to_i)
    return nil unless year >= 1 && month.between?(1, 12)

    leap = (year % 4).zero? && (!(year % 100).zero? || (year % 400).zero?)
    days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    day.between?(1, days[month - 1]) ? value : nil
  end

  def scalar(value, type, attributes)
    case type
    when 'string' then value
    when 'int' then integer(value)
    when 'bool'
      return true if %w[true yes on 1].include?(value.downcase)
      return false if %w[false no off 0].include?(value.downcase)

      nil
    when 'enum' then attributes.fetch('values').split(',').find { |entry| entry.downcase == value.downcase }
    when 'size' then size(value)
    when 'duration' then duration(value)
    when 'host' then host(value)
    when 'path' then path(value)
    when 'url' then url(value)
    when 'date' then date(value)
    end
  end

  def type_error(key, value, type, attributes, item = false)
    displayed = attributes.key?('secret') ? '********' : IniEmitter.string_notation(value)
    displayed = 'item ' + displayed if item
    if type == 'enum'
      report(@configuration[key].origin, 'E_ENUM', "#{key}: #{displayed} is not one of #{attributes['values']}")
    else
      report(@configuration[key].origin, 'E_TYPE', "#{key}: #{displayed} is not a valid #{type}")
    end
  end

  def normalize(key, value, spec)
    attributes = spec.attributes
    if spec.type == 'list'
      item_type = attributes.fetch('item', 'string')
      items = /\A *\z/.match?(value) ? [] : value.split(',', -1).map { |item| item.sub(/\A */, '').sub(/ *\z/, '') }
      if items.any?(&:empty?)
        report(@configuration[key].origin, 'W_EMPTY_ITEM', "#{key}: empty list item ignored")
        items.reject!(&:empty?)
      end
      normalized = []
      items.each do |item|
        result = scalar(item, item_type, attributes)
        if result.nil?
          type_error(key, item, item_type, attributes, true)
          return nil
        end
        normalized << result
      end
      if attributes.key?('unique') && normalized.uniq.length != normalized.length
        report(@configuration[key].origin, 'W_DUPLICATE_ITEM', "#{key}: duplicate items removed")
        normalized = normalized.uniq
      end
    else
      normalized = scalar(value, spec.type, attributes)
      if normalized.nil?
        type_error(key, value, spec.type, attributes)
        return nil
      end
    end
    return nil unless in_range?(key, normalized, spec)

    OutputValue.new(normalized, spec.type, spec, @configuration[key],
                    IniEmitter.notation(normalized, spec.type, attributes.fetch('item', 'string')))
  end

  def in_range?(key, value, spec)
    return true unless spec.attributes.key?('range')

    count_type = %w[string list].include?(spec.type)
    bounds = spec.attributes['range'].split('..', -1).map do |bound|
      bound.empty? ? nil : count_type ? bound.to_i : scalar(bound, spec.type, spec.attributes)
    end
    measured = count_type ? value.length : value
    lower, upper = bounds
    return true unless (!lower.nil? && measured < lower) || (!upper.nil? && measured > upper)

    displayed = if spec.type == 'string'
                  "length #{value.length}"
                elsif spec.type == 'list'
                  "count #{value.length}"
                elsif spec.attributes.key?('secret')
                  '********'
                else
                  IniEmitter.notation(value, spec.type)
                end
    bound_text = bounds.map { |bound| bound.nil? ? '' : bound.to_s }.join('..')
    report(@configuration[key].origin, 'E_RANGE', "#{key}: #{displayed} is out of range #{bound_text}")
    false
  end

  def check_types
    expansion = Interpolator.new(@configuration, method(:report)).expand_all
    @output = {}
    IniSchema.key_order(@configuration.keys).each do |key|
      value = expansion[key]
      next if value.nil?

      spec = @schema.find(key)
      if spec.nil?
        report(@configuration[key].origin, 'W_UNKNOWN', "#{key} is not in the schema")
        @output[key] = OutputValue.new(value, 'string', nil, @configuration[key], IniEmitter.string_notation(value))
      else
        entry = normalize(key, value, spec)
        @output[key] = entry unless entry.nil?
      end
    end
  end

  def check_order
    rejected = []
    IniSchema.key_order(@output.keys).each do |key|
      entry = @output[key]
      other_name = entry.spec&.attributes&.[]('le')
      next if other_name.nil?

      section, = IniSchema.split_key(key)
      other_key = "#{section}.#{other_name}"
      other = @output[other_key]
      next if other.nil? || entry.value <= other.value

      report(entry.definition.origin, 'E_ORDER', "#{key}: #{IniEmitter.display(entry)} is greater than #{other_key} (#{IniEmitter.display(other)})")
      rejected << key
    end
    rejected.each { |key| @output.delete(key) }
  end

  def check_required(root)
    @schema.specs.each do |spec|
      next unless spec.attributes.key?('required')

      @schema.targets(spec, @sections).each do |key|
        next if @configuration.key?(key)

        condition = spec.attributes['when']
        if condition.nil?
          report("#{root}:0", 'E_REQUIRED', "#{key} is required")
        else
          section, = IniSchema.split_key(key)
          condition_key = "#{section}.#{condition}"
          if @output[condition_key]&.value == true
            report("#{root}:0", 'E_REQUIRED', "#{key} is required when #{condition_key} is true")
          end
        end
      end
    end
  end

  def check_fixed(profile)
    IniSchema.key_order(@output.keys).each do |key|
      entry = @output[key]
      next unless entry.spec&.attributes&.key?('fixed')

      if @fixed.key?(key) && @fixed[key][1] != entry.notation
        report(entry.definition.origin, 'E_FIXED', "#{key}: value differs from profile #{@fixed[key][0]}")
        @output.delete(key)
      elsif !@fixed.key?(key)
        @fixed[key] = [profile, entry.notation]
      end
    end
  end

  def process(words, manifest_line)
    name, root, *overrides = words
    @configuration = {}
    @parents = {}
    @diagnostics = Set.new
    @includes = []
    @definition_number = 0
    apply_document(root, [root])
    overrides.each do |override|
      key, _, value = override.partition('=')
      define(key, value, "manifest:#{manifest_line}")
    end
    inherit_sections
    resolve_aliases
    defaults
    check_types
    check_order
    check_required(root)
    check_fixed(name)
    diagnostics = @diagnostics.to_a.sort
    errors = diagnostics.count { |entry| entry[2].start_with?('E_') }
    counts = { documents: 0, manifest: 0, defaults: 0 }
    overridden = []
    IniSchema.key_order(@output.keys).each do |key|
      definition = @output[key].definition
      document = definition.origin.rpartition(':')[0]
      source = document == 'manifest' ? :manifest : document == 'schema' ? :defaults : :documents
      counts[source] += 1
      overridden << [key, definition.history] if definition.history.length >= 2
    end
    Profile.new(name: name, root: root, configuration: @configuration, output: @output, diagnostics: diagnostics,
                includes: @includes, counts: counts, overridden: overridden, dropped: @configuration.length - @output.length,
                errors: errors, warnings: diagnostics.length - errors)
  end

  def difference(before, after)
    result = { from: before.name, to: after.name, added: 0, removed: 0, changed: 0, changes: [] }
    IniSchema.key_order(before.output.keys | after.output.keys).each do |key|
      left = before.output[key]
      right = after.output[key]
      kind = if left.nil?
               :added
             elsif right.nil?
               :removed
             elsif left.notation != right.notation
               :changed
             end
      next if kind.nil?

      result[kind] += 1
      result[:changes] << [kind, key, left, right]
    end
    result
  end

  def run
    profiles = File.readlines('input/manifest.txt', chomp: true).each_with_index.map do |line, index|
      process(line.split(' '), index + 1)
    end
    differences = profiles.each_cons(2).map { |before, after| difference(before, after) }
    IniEmitter.write(profiles, differences)
  end
end

Validator.new.run
