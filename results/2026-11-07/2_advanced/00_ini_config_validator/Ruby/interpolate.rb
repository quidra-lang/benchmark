# frozen_string_literal: true

require 'set'
require_relative 'lexer'
require_relative 'schema'

class Interpolator
  Frame = Struct.new(:key, :index, :result, :pending)

  def initialize(configuration, report)
    @configuration = configuration
    @report = report
    @memo = {}
    @cycles = Set.new
  end

  def expand_all
    IniSchema.key_order(@configuration.keys).each { |key| expand(key) unless @memo.key?(key) }
    @memo
  end

  def diagnostic(key, code, message)
    @report.call(@configuration.fetch(key).origin, code, message)
  end

  def reference_failure(key, target)
    diagnostic(key, 'E_DEPENDENCY', "#{key}: depends on failed key #{target}") unless @cycles.include?(key)
  end

  def expand(root)
    frames = [Frame.new(root, 0, +'', nil)]
    active = { root => 0 }
    finish = lambda do |frame, result|
      @memo[frame.key] = result
      active.delete(frame.key)
      frames.pop
    end
    until frames.empty?
      frame = frames.last
      key = frame.key
      if frame.pending
        target = frame.pending
        frame.pending = nil
        if @memo[target].nil?
          reference_failure(key, target)
          finish.call(frame, nil)
        else
          frame.result << @memo[target]
        end
        next
      end
      value = @configuration.fetch(key).value
      if frame.index == value.length
        finish.call(frame, frame.result)
        next
      end
      character = value[frame.index]
      if character == IniLexer::LITERAL_DOLLAR
        frame.result << '$'
        frame.index += 1
      elsif character != '$' || value[frame.index + 1] != '{'
        frame.result << character
        frame.index += 1
      else
        closing = value.index('}', frame.index + 2)
        reference = closing ? value[(frame.index + 2)...closing] : nil
        unless reference && IniSchema::SECTION_NAME.match?(reference)
          diagnostic(key, 'E_BAD_REF', "#{key}: invalid reference")
          finish.call(frame, nil)
          next
        end
        section, = IniSchema.split_key(key)
        target = reference.include?('.') ? reference : "#{section}.#{reference}"
        unless @configuration.key?(target)
          diagnostic(key, 'E_UNDEFINED', "#{key}: undefined reference #{target}")
          finish.call(frame, nil)
          next
        end
        if active.key?(target)
          path = frames[active[target]..].map(&:key) + [target]
          @cycles.merge(path)
          diagnostic(target, 'E_CYCLE', "interpolation cycle #{path.join(' -> ')}")
          reference_failure(key, target)
          finish.call(frame, nil)
          next
        end
        frame.index = closing + 1
        if @memo.key?(target)
          if @memo[target].nil?
            reference_failure(key, target)
            finish.call(frame, nil)
          else
            frame.result << @memo[target]
          end
        else
          frame.pending = target
          active[target] = frames.length
          frames << Frame.new(target, 0, +'', nil)
        end
      end
    end
  end
end
