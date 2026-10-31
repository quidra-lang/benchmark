module GCSim
  CollectorEntry = Data.define(:name, :type, :young, :age)
  Config = Data.define(:heap_size, :collectors, :maps, :windows, :width)
  Command = Data.define(:line, :name, :args)

  module Mutator
    extend self

    FORMS = {
      'ALLOC' => %i[number number], 'PUSH' => %i[source],
      'LOAD' => %i[number number], 'POP' => %i[number],
      'SET' => %i[number number source], 'OVERWRITE' => %i[number source],
      'CHECKPOINT' => %i[label]
    }.freeze
    COMMAND_NAMES = FORMS.keys.freeze

    def read_config(path)
      heap_size = width = 0
      collectors, maps, windows = [], [], []
      File.readlines(path, chomp: true).each do |text|
        name, *args = text.split(' ')
        case name
        when 'HEAP' then heap_size = args[0].to_i
        when 'COLLECTOR'
          collectors << CollectorEntry.new(args[0], args[1], args[2].to_i, args[3].to_i)
        when 'MAPS' then maps = args
        when 'MMU' then windows = args.map(&:to_i)
        when 'WIDTH' then width = args[0].to_i
        end
      end
      Config.new(heap_size, collectors, maps, windows, width)
    end

    def matches?(kind, token)
      case kind
      when :number then /\A(?:0|[1-9][0-9]{0,3})\z/.match?(token)
      when :source then token == '-' || matches?(:number, token)
      when :label then /\A[a-z0-9_]{1,16}\z/.match?(token)
      end
    end

    def parse(line, text)
      # A regexp separator preserves empty tokens at every individual space.
      name, *tokens = text.split(/ /, -1)
      form = FORMS[name]
      unless form && tokens.length == form.length && form.zip(tokens).all? { |kind, token| matches?(kind, token) }
        return [nil, 'syntax']
      end

      args = form.zip(tokens).map do |kind, token|
        kind == :label ? token : (token == '-' ? nil : token.to_i)
      end
      if (name == 'ALLOC' && (args[0] > 6 || args[1] > 24)) || (name == 'POP' && args[0].zero?)
        return [nil, 'range']
      end
      [Command.new(line, name, args), nil]
    end

    def read_script(path)
      File.readlines(path, chomp: true).each_with_index.map { |text, index| parse(index + 1, text) }
    end
  end
end
