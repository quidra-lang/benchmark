require_relative 'object_parser'

module Archive
  Member = Struct.new(:object, :exports, :loaded)
  module_function

  def read(path)
    lines, members, index = ObjectParser.read_lines(path), [], 0
    while index < lines.length
      words = lines[index].split(' ')
      name = "#{File.basename(path)}(#{words[1]})"
      object, index = ObjectParser.parse(lines, index + 1, name)
      members << Member.new(object, words.drop(2), false)
    end
    members
  end

  def scan(members, undefined, extract)
    extracted = 0
    loop do
      changed = false
      members.each do |member|
        next if member.loaded
        reason = member.exports.find { |name| undefined.call(name) }
        next unless reason
        member.loaded = true
        extract.call(member.object, reason)
        extracted += 1
        changed = true
      end
      return extracted unless changed
    end
  end
end
