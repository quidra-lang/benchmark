module PageBuilder
  def self.build_sequence(blocks, orphan_lines, widow_lines)
    lines, boundaries = [], []
    blocks.each_with_index do |block, i|
      start = lines.length
      lines.concat(block[:lines])
      count = block[:lines].length
      if block[:kind] == 'flow'
        (1...count).each do |kept|
          if kept >= orphan_lines && count - kept >= widow_lines
            position = start + kept
            boundaries << [position, position, false]
          end
        end
      end
      if i + 1 == blocks.length
        boundaries << [lines.length, lines.length, true]
        next
      end

      following = blocks[i + 1]
      finish = lines.length
      lines << { text: '', footnotes: [], indexes: [] } unless block[:list] && following[:list]
      forced = following[:page_break]
      boundaries << [finish, lines.length, forced] if forced || block[:kind] != 'heading'
    end
    [lines, boundaries]
  end

  def self.choose_pages(blocks, footnote_heights, height, orphan_lines, widow_lines)
    lines, boundaries = build_sequence(blocks, orphan_lines, widow_lines)
    pages, start, first_boundary = [], 0, 0
    while start < lines.length
      notes, note_height, scanned, chosen = {}, 0, start, nil
      (first_boundary...boundaries.length).each do |i|
        finish, next_start, forced = boundaries[i]
        while scanned < finish
          lines[scanned][:footnotes].each do |number|
            next if notes.key?(number)

            notes[number] = true
            note_height += footnote_heights[number]
          end
          scanned += 1
        end
        used = finish - start + note_height + (notes.empty? ? 0 : 1)
        break if used > height

        chosen = [i, finish, next_start, forced, used, notes.keys.sort]
        break if forced
      end
      # Every page has a fitting allowed boundary by the input constraints.
      i, finish, next_start, forced, used, page_notes = chosen
      pages << { content: lines[start...finish], footnotes: page_notes, height: used,
                 ends_by_force: forced, blank: false }
      start = next_start
      first_boundary = i + 1
    end
    pages
  end
end
