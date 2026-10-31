# frozen_string_literal: true

require_relative 'lexer'
require_relative 'schema'

module IniParser
  Statement = Struct.new(:kind, :line, :key, :value)
  Document = Struct.new(:statements, :diagnostics)

  def self.trim(parts)
    result = parts.map { |quoted, text| [quoted, text.dup] }
    unless result.empty? || result.first[0]
      result.first[1] = result.first[1].sub(/\A */, '')
      result.shift if result.first[1].empty?
    end
    unless result.empty? || result.last[0]
      result.last[1] = result.last[1].sub(/ *\z/, '')
      result.pop if result.last[1].empty?
    end
    result
  end

  def self.read(name)
    path = "input/conf/#{name}.ini"
    return nil unless File.exist?(path)

    statements = []
    diagnostics = []
    current = nil
    base = nil
    assignments = {}
    IniLexer.read(File.binread(path)).each do |logical|
      report = ->(code, message) { diagnostics << [name, logical.number, code, message] }
      if logical.error
        report.call(*logical.error)
        next
      end
      parts = trim(logical.parts)
      next if parts.empty?

      has_quotes = parts.any?(&:first)
      plain = parts.map(&:last).join
      first = parts.first[0] ? nil : parts.first[1][0]
      if first == '['
        valid = !has_quotes && plain.end_with?(']')
        section = parent = nil
        if valid
          section, separator, parent = plain[1...-1].partition(':')
          section = section.strip
          parent = separator.empty? ? nil : parent.strip
          valid = (IniSchema::SECTION_NAME.match?(section) ||
            (section.start_with?('.') && IniSchema::SECTION_NAME.match?(section[1..]))) &&
            (parent.nil? || IniSchema::SECTION_NAME.match?(parent))
        end
        if !valid
          current = nil
          report.call('E_SECTION', 'invalid section header')
        elsif section.start_with?('.') && base.nil?
          current = nil
          report.call('E_SECTION', 'relative section without base')
        else
          if section.start_with?('.')
            current = base + section
          else
            current = base = section
          end
          statements << Statement.new(:inherit, logical.number, current, parent) if parent
        end
      elsif first == '@'
        words = plain.split(/ +/)
        if has_quotes || words.length != 2 || !%w[@include @unset].include?(words[0]) || !IniSchema::NAME.match?(words[1])
          report.call('E_SYNTAX', 'invalid directive')
        elsif words[0] == '@include'
          statements << Statement.new(:include, logical.number, words[1])
        elsif current.nil?
          report.call('E_NO_SECTION', 'no current section')
        else
          statements << Statement.new(:unset, logical.number, "#{current}.#{words[1]}")
        end
      else
        equal_part = parts.index { |quoted, text| !quoted && text.include?('=') }
        if equal_part.nil?
          report.call('E_SYNTAX', 'invalid line')
          next
        end
        if parts.take(equal_part).any?(&:first)
          report.call('E_SYNTAX', 'invalid key')
          next
        end
        before, _, after = parts[equal_part][1].partition('=')
        key = (parts.take(equal_part).map(&:last).join + before).strip
        append = key.end_with?('+')
        key = key[0...-1].sub(/ *\z/, '') if append
        unless IniSchema::NAME.match?(key)
          report.call('E_SYNTAX', 'invalid key')
          next
        end
        value_parts = trim([[false, after], *parts.drop(equal_part + 1)])
        if value_parts.none?(&:first)
          value = value_parts.map(&:last).join
        elsif value_parts.length == 1 && value_parts[0][0]
          value = value_parts[0][1]
        else
          report.call('E_SYNTAX', 'invalid value')
          next
        end
        if current.nil?
          report.call('E_NO_SECTION', 'no current section')
          next
        end
        full_key = "#{current}.#{key}"
        unless append
          report.call('W_DUPLICATE', "#{full_key} already set at line #{assignments[full_key]}") if assignments.key?(full_key)
          assignments[full_key] = logical.number
        end
        statements << Statement.new(append ? :append : :assign, logical.number, full_key, value)
      end
    end
    Document.new(statements, diagnostics)
  end
end
