# frozen_string_literal: true

require_relative 'headers'

module Addresses
  class Invalid < StandardError; end

  class Parser
    def initialize(tokens)
      @tokens = tokens
      @index = 0
      @encoded_error = false
    end

    def parse
      result = [address(false)]
      while kind == ','
        @index += 1
        result << address(false)
      end
      raise Invalid unless @index == @tokens.length

      [result, @encoded_error]
    end

    private

    def kind
      @tokens[@index]&.kind
    end

    def take(expected)
      raise Invalid unless kind == expected

      @index += 1
    end

    def phrase(kinds)
      start = @index
      @index += 1 while kinds.include?(kind)
      @tokens[start...@index]
    end

    def valid_part?(tokens)
      !tokens.empty? && tokens.length.odd? && tokens.each_with_index.all? do |token, index|
        token.kind == (index.even? ? :word : '.')
      end
    end

    def display_name(tokens)
      text = +''
      previous_success = false
      tokens.each_with_index do |token, index|
        decoded, success, error = token.kind == :word ? Headers.encoded_word(token.text) : [token.text, false, false]
        text << ' ' if index.positive? && token.spaced && !(previous_success && success)
        text << decoded
        previous_success = success
        @encoded_error ||= error
      end
      name = Headers.collapse(text)
      name.empty? ? nil : name
    end

    def address(inside_group)
      name_tokens = phrase([:word, :quoted, '.'])
      case kind
      when '<'
        take('<')
        local = phrase([:word, '.'])
        take('@')
        domain = phrase([:word, '.'])
        take('>')
        name = display_name(name_tokens)
      when '@'
        local = name_tokens
        take('@')
        domain = phrase([:word, '.'])
        name = nil
      when ':'
        raise Invalid if inside_group || name_tokens.empty?

        take(':')
        members = []
        unless kind == ';'
          members << address(true)
          while kind == ','
            take(',')
            members << address(true)
          end
        end
        take(';')
        return { kind: :group, members: members }
      else
        raise Invalid
      end
      raise Invalid unless valid_part?(local) && valid_part?(domain)

      address = (local.map(&:text).join + '@' + domain.map(&:text).join).downcase
      { kind: :mailbox, address: address, name: name }
    end
  end

  def self.parse(text)
    tokens = Headers.tokens(text, :address)
    return nil unless tokens && !tokens.empty?

    Parser.new(tokens).parse
  rescue Invalid
    nil
  end
end
