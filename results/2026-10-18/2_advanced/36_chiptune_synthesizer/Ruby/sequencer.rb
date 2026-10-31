require_relative 'song_parser'

module Chiptune
  module Sequencer
    module_function

    def samples_per_tick(rate, tempo)
      rate * 5 / (tempo * 2)
    end

    def next_row(song, position, row)
      jump = pattern_break = nil
      song.cells(position, row).each do |cell|
        effect = cell.effect
        next unless effect
        return if effect.name == 'F' && effect.value.zero?

        jump = effect.value if effect.name == 'B'
        pattern_break = effect.value if effect.name == 'D'
      end
      if jump.nil? && pattern_break.nil?
        return row < SongParser::ROWS - 1 ? [position, row + 1] : [position + 1, 0]
      end

      [jump || position + 1, pattern_break && pattern_break < SongParser::ROWS ? pattern_break : 0]
    end

    def reachable_rows(song)
      reached = {}
      current = [0, 0]
      while current && current[0] < song.order.length && !reached.key?(current)
        reached[current] = true
        current = next_row(song, *current)
      end
      reached
    end
  end
end
