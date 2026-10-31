# frozen_string_literal: true

require_relative 'schema'

module IniEmitter
  STRING_ESCAPES = { '\\' => '\\\\', '"' => '\\"', "\n" => '\\n', "\t" => '\\t' }.freeze

  def self.string_notation(value)
    '"' + value.each_char.map { |character| STRING_ESCAPES.fetch(character, character) }.join + '"'
  end

  def self.notation(value, type, item_type = 'string')
    case type
    when 'string' then string_notation(value)
    when 'bool' then value ? 'true' : 'false'
    when 'list' then '[' + value.map { |item| notation(item, item_type) }.join(', ') + ']'
    else value.to_s
    end
  end

  def self.display(entry)
    entry.spec&.attributes&.key?('secret') ? '********' : entry.notation
  end

  def self.normalized(profile)
    lines = ["profile #{profile.name}"]
    previous = nil
    IniSchema.key_order(profile.output.keys).each do |key|
      section, name = IniSchema.split_key(key)
      lines << "[#{section}]" if section != previous
      previous = section
      lines << "#{name} = #{display(profile.output.fetch(key))}"
    end
    lines
  end

  def self.diagnostics(profile)
    ["profile #{profile.name} errors #{profile.errors} warnings #{profile.warnings}"] +
      profile.diagnostics.map { |document, line, code, message| "#{document}:#{line} #{code} #{message}" }
  end

  def self.difference(diff)
    lines = ["diff #{diff[:from]} -> #{diff[:to]}: #{diff[:added]} added, #{diff[:removed]} removed, #{diff[:changed]} changed"]
    diff[:changes].each do |kind, key, before, after|
      lines << case kind
               when :added then "+ #{key} = #{display(after)}"
               when :removed then "- #{key} = #{display(before)}"
               when :changed then "~ #{key}: #{display(before)} -> #{display(after)}"
               end
    end
    lines
  end

  def self.report(profile)
    lines = ["profile #{profile.name}", 'includes']
    profile.includes.each { |depth, text| lines << ' ' * (2 + 2 * depth) + text }
    lines << 'overridden'
    if profile.overridden.empty?
      lines << '  (none)'
    else
      profile.overridden.each { |key, history| lines << "  #{key}: #{history.join(' -> ')}" }
    end
    lines << "keys #{profile.output.length} documents #{profile.counts[:documents]} manifest #{profile.counts[:manifest]} defaults #{profile.counts[:defaults]}"
    lines << "dropped #{profile.dropped}"
    lines << "errors #{profile.errors} warnings #{profile.warnings}"
    lines
  end

  def self.write(profiles, differences)
    files = {
      'normalized.txt' => profiles.map { |profile| normalized(profile) },
      'diagnostics.txt' => profiles.map { |profile| diagnostics(profile) },
      'diff.txt' => differences.map { |diff| difference(diff) },
      'report.txt' => profiles.map { |profile| report(profile) }
    }
    Dir.mkdir('output') unless Dir.exist?('output')
    files.each do |name, blocks|
      text = blocks.map { |block| block.join("\n") }.join("\n\n")
      File.binwrite("output/#{name}", text + (blocks.empty? ? '' : "\n"))
    end
  end
end
