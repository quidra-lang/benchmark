# frozen_string_literal: true

module IniSchema
  NAME = /\A[a-z][a-z0-9_]*\z/
  SECTION_NAME = /\A[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*\z/
  Spec = Struct.new(:pattern, :section, :key, :type, :attributes, :line, :wildcard)

  def self.split_key(key)
    section, _, name = key.rpartition('.')
    [section, name]
  end

  def self.key_order(keys)
    keys.sort_by { |key| split_key(key) }
  end

  class Schema
    attr_reader :specs

    def initialize(path)
      @specs = []
      @exact = {}
      @wildcards = []
      File.readlines(path, chomp: true).each_with_index do |line, index|
        next if line.strip.empty? || line.start_with?('#')

        pattern, type, *words = line.split(' ')
        attributes = {}
        words.each do |word|
          name, separator, value = word.partition('=')
          attributes[name] = separator.empty? ? true : value
        end
        section, key = IniSchema.split_key(pattern)
        spec = Spec.new(pattern, section.split('.'), key, type, attributes, index + 1, pattern.include?('*'))
        @specs << spec
        if spec.wildcard
          @wildcards << spec
        else
          @exact[pattern] = spec
        end
      end
    end

    def matches?(spec, section)
      parts = section.split('.')
      parts.length == spec.section.length &&
        parts.each_index.all? { |index| spec.section[index] == '*' || spec.section[index] == parts[index] }
    end

    def find(key)
      return @exact[key] if @exact.key?(key)

      section, name = IniSchema.split_key(key)
      @wildcards.find { |spec| spec.key == name && matches?(spec, section) }
    end

    def targets(spec, sections)
      return [spec.pattern] unless spec.wildcard

      sections.sort.filter_map do |section|
        key = "#{section}.#{spec.key}"
        key if matches?(spec, section) && find(key).equal?(spec)
      end
    end
  end
end
