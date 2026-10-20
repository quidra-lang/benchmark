# frozen_string_literal: true

require 'set'
require_relative 'clues'
require_relative 'line_solver'
require_relative 'propagation'
require_relative 'search'
require_relative 'render'

class NonogramAnalysis
  STATS_HEADER = 'puzzle,status,difficulty,width,height,givens,simple_known,logic_known,line_solves,guesses,max_depth,solutions,answer'
  DIFFICULTIES = { 'easy' => 0, 'medium' => 1, 'hard' => 2 }.freeze

  def read_blocks(path, marker)
    lines = File.readlines(path, chomp: true)
    blocks = []
    index = 0
    while index < lines.length
      if lines[index].empty? || lines[index].start_with?('#')
        index += 1
        next
      end
      name = lines[index].delete_prefix(marker + ' ')
      index += 1
      body = []
      until lines[index] == 'END'
        body << lines[index]
        index += 1
      end
      blocks << { name: name, body: body }
      index += 1
    end
    blocks
  end

  def parse_puzzle(block)
    body = block[:body]
    _, width, height = body.first.split(' ')
    columns_start = body.index('COLUMNS')
    answer_start = body.index('ANSWER')
    givens_start = body.index { |line| line.start_with?('GIVEN ') }
    columns_end = givens_start || answer_start || body.length
    given_lines = body[columns_end...(answer_start || body.length)]
    givens = given_lines.map do |line|
      _, row, column, value = line.split(' ')
      [row.to_i, column.to_i, value]
    end
    { name: block[:name], width: width.to_i, height: height.to_i,
      raw_rows: body[2...columns_start], raw_columns: body[(columns_start + 1)...columns_end],
      raw_givens: givens,
      raw_answer: answer_start ? body.drop(answer_start + 1) : nil }
  end

  def valid_name?(name)
    /\A[a-z0-9_]{1,20}\z/.match?(name)
  end

  def validate_puzzle(puzzle, duplicate)
    return 'bad name' unless valid_name?(puzzle[:name])
    return 'duplicate name' if duplicate

    width = puzzle[:width]
    height = puzzle[:height]
    return 'bad size' unless width.between?(1, 30) && height.between?(1, 30)
    return "row count #{puzzle[:raw_rows].length} expected #{height}" unless puzzle[:raw_rows].length == height
    return "column count #{puzzle[:raw_columns].length} expected #{width}" unless puzzle[:raw_columns].length == width

    [['row', :raw_rows, :rows, width], ['column', :raw_columns, :columns, height]].each do |name, raw, parsed, length|
      puzzle[parsed] = []
      puzzle[raw].each_with_index do |text, index|
        clue = Clues.parse(text)
        return "bad clue #{name} #{index + 1}" if clue.nil?
        return "#{name} #{index + 1} too long" unless Clues.fits?(clue, length)

        puzzle[parsed] << clue
      end
    end
    row_total = puzzle[:rows].sum(&:sum)
    column_total = puzzle[:columns].sum(&:sum)
    return "total mismatch rows=#{row_total} columns=#{column_total}" unless row_total == column_total

    used = Set.new
    puzzle[:givens] = []
    puzzle[:raw_givens].each_with_index do |(row, column, value), index|
      return "bad given #{index + 1}" unless row.between?(1, height) && column.between?(1, width) && %w[# .].include?(value)
      return "duplicate given #{index + 1}" if used.include?([row, column])

      used.add([row, column])
      puzzle[:givens] << [row - 1, column - 1, Render::STATES.fetch(value)]
    end
    answer = puzzle[:raw_answer]
    if answer && (answer.length != height || answer.any? { |row| row.length != width || !/\A[#.?]+\z/.match?(row) })
      return 'bad answer'
    end
    puzzle[:answer] = answer&.map { |row| Render.parse(row) }
    nil
  end

  def logical(puzzle, givens, kind)
    grid = Array.new(puzzle[:height]) { Array.new(puzzle[:width], LineSolver::UNKNOWN) }
    givens.each { |row, column, value| grid[row][column] = value }
    Propagation.run(grid, puzzle[:rows], puzzle[:columns], kind)
  end

  def analyze(puzzle, givens)
    simple = logical(puzzle, givens, :simple)
    logic = logical(puzzle, givens, :precise)
    search = nil
    if logic[:status] == 'contradiction'
      status = 'contradiction'
      difficulty = '-'
      solutions = []
    elsif logic[:status] == 'solved'
      status = 'unique'
      difficulty = simple[:status] == 'solved' ? 'easy' : 'medium'
      solutions = [logic[:grid]]
    else
      search = Search.run(logic[:grid], puzzle[:rows], puzzle[:columns])
      solutions = search[:solutions]
      status = %w[none unique multiple][solutions.length]
      difficulty = status == 'unique' ? 'hard' : '-'
    end
    { simple: simple, logic: logic, search: search, status: status, difficulty: difficulty, solutions: solutions,
      line_solves: logic[:record].length + (search ? search[:line_solves] : 0),
      guesses: search ? search[:guesses] : 0, max_depth: search ? search[:max_depth] : 0 }
  end

  def clue_statistics(puzzle)
    rows = puzzle[:rows]
    columns = puzzle[:columns]
    fixed = rows.count { |clue| clue.empty? || clue.sum + clue.length - 1 == puzzle[:width] }
    fixed += columns.count { |clue| clue.empty? || clue.sum + clue.length - 1 == puzzle[:height] }
    { row_blocks: rows.sum(&:length), column_blocks: columns.sum(&:length), filled: rows.sum(&:sum),
      max_block: (rows + columns).flatten.max || 0, fixed_lines: fixed }
  end

  def clue_text(puzzle)
    clue_statistics(puzzle).map { |name, value| "#{name}=#{value}" }.join(' ')
  end

  def line_clue(puzzle, index)
    index < puzzle[:height] ? puzzle[:rows][index] : puzzle[:columns][index - puzzle[:height]]
  end

  def different_cells(first, second)
    cells = []
    first.each_with_index do |line, row|
      line.each_index { |column| cells << [row, column] if line[column] != second[row][column] }
    end
    cells
  end

  def features(grid)
    height = grid.length
    width = grid.first.length
    filled = []
    grid.each_with_index do |line, row|
      line.each_with_index { |state, column| filled << [row, column] if state == LineSolver::FILLED }
    end
    visited = Set.new
    components = 0
    largest = 0
    filled.each do |cell|
      next if visited.include?(cell)

      components += 1
      size = 0
      stack = [cell]
      visited.add(cell)
      until stack.empty?
        row, column = stack.pop
        size += 1
        [[row - 1, column], [row + 1, column], [row, column - 1], [row, column + 1]].each do |neighbor|
          r, c = neighbor
          next unless r.between?(0, height - 1) && c.between?(0, width - 1)
          next unless grid[r][c] == LineSolver::FILLED && !visited.include?(neighbor)

          visited.add(neighbor)
          stack << neighbor
        end
      end
      largest = [largest, size].max
    end
    box = if filled.empty?
            '-'
          else
            rows = filled.map(&:first)
            columns = filled.map(&:last)
            [rows.min + 1, columns.min + 1, rows.max + 1, columns.max + 1].join(',')
          end
    symmetry = []
    symmetry << 'lr' if grid.all? { |row| row == row.reverse }
    symmetry << 'ud' if grid == grid.reverse
    symmetry << 'rot180' if grid == grid.reverse.map(&:reverse)
    "filled=#{filled.length} components=#{components} largest=#{largest} bbox=#{box} symmetry=#{symmetry.empty? ? 'none' : symmetry.join(',')}"
  end

  def evaluate_givens(puzzle, analysis)
    givens = puzzle[:givens]
    return nil if givens.empty? || analysis[:status] == 'multiple'

    numbers = []
    givens.each_index do |index|
      trial = analyze(puzzle, givens.take(index) + givens.drop(index + 1))
      qualifies = analysis[:status] == 'unique' ? trial[:status] == 'unique' : %w[unique multiple].include?(trial[:status])
      numbers << index + 1 if qualifies
    end
    { kind: analysis[:status] == 'unique' ? 'redundant' : 'blame', numbers: numbers }
  end

  def grade_answer(puzzle, analysis)
    answer = puzzle[:answer]
    return nil if answer.nil?

    rows = []
    columns = []
    puzzle[:rows].each_with_index { |clue, index| rows << index + 1 unless LineSolver.consistent?(answer[index], clue) }
    puzzle[:columns].each_with_index do |clue, index|
      columns << index + 1 unless LineSolver.consistent?(answer.map { |line| line[index] }, clue)
    end
    givens = []
    puzzle[:givens].each_with_index do |(row, column, value), index|
      givens << index + 1 if answer[row][column] != LineSolver::UNKNOWN && answer[row][column] != value
    end
    known = Propagation.known(answer)
    consistent = rows.empty? && columns.empty? && givens.empty?
    result = known < puzzle[:width] * puzzle[:height] ? 'partial' : consistent ? 'correct' : 'wrong'
    grading = { result: result, known: known, rows: rows, columns: columns, givens: givens }
    if result == 'partial'
      extendable = false
      if consistent
        original = Set.new(puzzle[:givens].map { |row, column, _| [row, column] })
        additional = []
        answer.each_with_index do |line, row|
          line.each_with_index do |state, column|
            additional << [row, column, state] if state != LineSolver::UNKNOWN && !original.include?([row, column])
          end
        end
        trial = analyze(puzzle, puzzle[:givens] + additional)
        extendable = %w[unique multiple].include?(trial[:status])
      end
      grading[:extendable] = extendable ? 'yes' : 'no'
    end
    if analysis[:status] == 'unique'
      solution = analysis[:solutions].first
      grading[:differs] = different_cells(answer, solution).count { |row, column| answer[row][column] != LineSolver::UNKNOWN }
    end
    grading
  end

  def number_list(numbers)
    numbers.empty? ? '-' : numbers.join(',')
  end

  def cell_text(cell)
    "#{cell[0] + 1},#{cell[1] + 1}"
  end

  def logical_result(outcome, height)
    outcome[:status] == 'contradiction' ? "contradiction at=#{Propagation.label(outcome[:conflict], height)}" : outcome[:status]
  end

  def line_statistics(record, height)
    ordinary = record.reject { |entry| entry[:gain].nil? }
    best = ordinary.map { |entry| entry[:gain] }.max || 0
    at = best.zero? ? '-' : Propagation.label(ordinary.find { |entry| entry[:gain] == best }[:line], height)
    "steps productive=#{ordinary.count { |entry| entry[:gain].positive? }} idle=#{ordinary.count { |entry| entry[:gain].zero? }} best=#{best} at=#{at}"
  end

  def grading_lines(puzzle, grading)
    line = "answer result=#{grading[:result]} known=#{grading[:known]} rows=#{number_list(grading[:rows])} columns=#{number_list(grading[:columns])} givens=#{number_list(grading[:givens])}"
    line += " extendable=#{grading[:extendable]}" if grading[:result] == 'partial'
    line += " differs=#{grading[:differs]}" if grading.key?(:differs)
    lines = [line]
    indices = grading[:rows].map { |row| row - 1 } + grading[:columns].map { |column| puzzle[:height] + column - 1 }
    indices.each do |index|
      cells = Propagation.line(puzzle[:answer], index)
      observed = grading[:result] == 'partial' ? "cells=#{Render.line(cells)}" : "got=#{Clues.text(Clues.runs(cells), ',')}"
      lines << "mismatch #{Propagation.label(index, puzzle[:height])} expected=#{Clues.text(line_clue(puzzle, index), ',')} #{observed}"
    end
    lines
  end

  def puzzle_lines(puzzle)
    lines = ["PUZZLE #{puzzle[:name]}"]
    return lines + ["error #{puzzle[:error]}"] if puzzle[:error]

    analysis = puzzle[:analysis]
    height = puzzle[:height]
    width = puzzle[:width]
    simple = analysis[:simple]
    logic = analysis[:logic]
    lines << "size=#{width}x#{height} givens=#{puzzle[:givens].length} status=#{analysis[:status]} difficulty=#{analysis[:difficulty]}"
    lines << "clues #{clue_text(puzzle)}"
    lines << "simple known=#{simple[:known]} line_solves=#{simple[:record].length} result=#{logical_result(simple, height)}"
    lines << "logic known=#{logic[:known]} line_solves=#{logic[:record].length} result=#{logical_result(logic, height)}"
    lines << line_statistics(logic[:record], height)
    if height * width <= 49
      trace = logic[:record].map do |entry|
        label = Propagation.label(entry[:line], height)
        entry[:gain].nil? ? label + '!' : "#{label}+#{entry[:gain]}"
      end
      lines << "trace #{trace.join(' ')}"
    end
    if logic[:status] == 'stuck'
      rows = logic[:grid].each_with_index.filter_map do |row, index|
        count = row.count(LineSolver::UNKNOWN)
        "#{index + 1}:#{count}" if count.positive?
      end
      columns = (0...width).filter_map do |column|
        count = logic[:grid].count { |row| row[column] == LineSolver::UNKNOWN }
        "#{column + 1}:#{count}" if count.positive?
      end
      lines << "stuck rows=#{rows.join(' ')} columns=#{columns.join(' ')}"
    end
    if analysis[:status] == 'contradiction'
      index = logic[:conflict]
      lines << "conflict line=#{Propagation.label(index, height)} clue=#{Clues.text(line_clue(puzzle, index), ',')} cells=#{Render.line(Propagation.line(logic[:grid], index))}"
    end
    if analysis[:search]
      search = analysis[:search]
      lines << "search guesses=#{search[:guesses]} max_depth=#{search[:max_depth]} backtracks=#{search[:backtracks]} solutions=#{search[:solutions].length} line_solves=#{search[:line_solves]}"
      search[:records].each do |guess|
        lines << "guess #{guess[:number]} depth=#{guess[:depth]} cell=#{cell_text([guess[:row], guess[:column]])} value=#{Render.symbol(guess[:value])} solves=#{guess[:solves]} known=#{guess[:known]} result=#{guess[:result]}"
      end
    end
    if analysis[:status] == 'multiple'
      differences = different_cells(*analysis[:solutions])
      lines << "differ count=#{differences.length} cells=#{differences.map { |cell| cell_text(cell) }.join(' ')}"
    end
    grids = []
    if analysis[:status] == 'contradiction'
      grids << ['partial', logic[:grid]]
    else
      grids << ['simple', simple[:grid]] if simple[:status] == 'stuck'
      grids << ['logic', logic[:grid]] if logic[:status] == 'stuck'
      if analysis[:status] == 'multiple'
        grids << ['first', analysis[:solutions][0]]
        grids << ['second', analysis[:solutions][1]]
      end
    end
    lines.concat(Render.side_by_side(grids, height)) unless grids.empty?
    if analysis[:status] == 'unique'
      lines << 'sheet'
      lines.concat(Render.sheet(puzzle[:rows], puzzle[:columns], analysis[:solutions].first))
      lines << "picture #{features(analysis[:solutions].first)}"
    end
    evaluation = puzzle[:given_evaluation]
    lines << "givens #{evaluation[:kind]}=#{number_list(evaluation[:numbers])}" if evaluation
    lines.concat(grading_lines(puzzle, puzzle[:grading])) if puzzle[:grading]
    lines
  end

  def statistics_line(puzzle)
    return ([puzzle[:name], 'invalid'] + Array.new(11, '-')).join(',') if puzzle[:error]

    analysis = puzzle[:analysis]
    [puzzle[:name], analysis[:status], analysis[:difficulty], puzzle[:width], puzzle[:height], puzzle[:givens].length,
     analysis[:simple][:known], analysis[:logic][:known], analysis[:line_solves], analysis[:guesses], analysis[:max_depth],
     analysis[:solutions].length, puzzle[:grading] ? puzzle[:grading][:result] : '-'].join(',')
  end

  def puzzle_reports
    seen = Set.new
    @puzzles = read_blocks('input/puzzles.txt', 'PUZZLE').map do |block|
      puzzle = parse_puzzle(block)
      duplicate = seen.include?(puzzle[:name])
      seen.add(puzzle[:name])
      puzzle[:error] = validate_puzzle(puzzle, duplicate)
      unless puzzle[:error]
        puzzle[:analysis] = analyze(puzzle, puzzle[:givens])
        puzzle[:given_evaluation] = evaluate_givens(puzzle, puzzle[:analysis])
        puzzle[:grading] = grade_answer(puzzle, puzzle[:analysis])
      end
      puzzle
    end
    @valid_puzzles = @puzzles.reject { |puzzle| puzzle[:error] }
    paragraphs = @puzzles.map { |puzzle| puzzle_lines(puzzle) }
    ranking = @valid_puzzles.select { |puzzle| puzzle[:analysis][:status] == 'unique' }.sort_by do |puzzle|
      analysis = puzzle[:analysis]
      [DIFFICULTIES.fetch(analysis[:difficulty]), analysis[:line_solves] + 25 * analysis[:guesses], puzzle[:name]]
    end
    ranks = ranking.each_with_index.map do |puzzle, index|
      analysis = puzzle[:analysis]
      "rank #{index + 1} #{puzzle[:name]} #{analysis[:difficulty]} score=#{analysis[:line_solves] + 25 * analysis[:guesses]} size=#{puzzle[:width]}x#{puzzle[:height]}"
    end
    paragraphs << ['RANKING', *ranks]
    counts = Hash.new(0)
    @valid_puzzles.each do |puzzle|
      analysis = puzzle[:analysis]
      counts[analysis[:status]] += 1
      counts[analysis[:difficulty]] += 1
      counts['line_solves'] += analysis[:line_solves]
      counts['guesses'] += analysis[:guesses]
    end
    paragraphs << ["SUMMARY puzzles=#{@puzzles.length} invalid=#{@puzzles.length - @valid_puzzles.length} contradiction=#{counts['contradiction']} none=#{counts['none']} unique=#{counts['unique']} multiple=#{counts['multiple']} easy=#{counts['easy']} medium=#{counts['medium']} hard=#{counts['hard']} line_solves=#{counts['line_solves']} guesses=#{counts['guesses']}"]
    [paragraphs, [STATS_HEADER] + @puzzles.map { |puzzle| statistics_line(puzzle) }]
  end

  def validate_picture(block, duplicate)
    return 'bad name' unless valid_name?(block[:name])
    return 'duplicate name' if duplicate
    return 'bad height' unless block[:body].length.between?(1, 30)

    width = block[:body].first.length
    block[:body].each_with_index do |row, index|
      return "bad row #{index + 1}" unless row.length.between?(1, 30) && row.length == width && /\A[#.]+\z/.match?(row)
    end
    nil
  end

  def generated_picture(block)
    grid = block[:body].map { |row| Render.parse(row) }
    puzzle = { name: block[:name], width: grid.first.length, height: grid.length,
               rows: grid.map { |row| Clues.runs(row) }, columns: grid.transpose.map { |column| Clues.runs(column) } }
    duplicate = @valid_puzzles.find do |other|
      %i[width height rows columns].all? { |key| puzzle[key] == other[key] }
    end
    lines = ["# picture #{puzzle[:name]} size=#{puzzle[:width]}x#{puzzle[:height]} #{features(grid)}",
             "# clues #{clue_text(puzzle)} duplicate_of=#{duplicate ? duplicate[:name] : '-'}"]
    givens = []
    plain = analyze(puzzle, givens)
    current = plain
    lines << "# plain status=#{plain[:status]} difficulty=#{plain[:difficulty]} line_solves=#{plain[:line_solves]} guesses=#{plain[:guesses]}"
    while current[:status] == 'multiple'
      row, column = different_cells(*current[:solutions]).first
      value = grid[row][column]
      givens << [row, column, value]
      current = analyze(puzzle, givens)
      lines << "# hint #{givens.length} cell=#{cell_text([row, column])} value=#{Render.symbol(value)} status=#{current[:status]}"
    end
    givens.dup.each do |given|
      trial_list = givens - [given]
      trial = analyze(puzzle, trial_list)
      if trial[:status] == 'unique'
        givens = trial_list
        lines << "# drop cell=#{cell_text(given)}"
      end
    end
    current = analyze(puzzle, givens)
    logic_hints = 0
    while current[:difficulty] == 'hard'
      row, column = Search.choose(current[:logic][:grid])
      value = grid[row][column]
      givens << [row, column, value]
      logic_hints += 1
      current = analyze(puzzle, givens)
      lines << "# logic hint #{logic_hints} cell=#{cell_text([row, column])} value=#{Render.symbol(value)} difficulty=#{current[:difficulty]}"
    end
    lines << "# final status=#{current[:status]} difficulty=#{current[:difficulty]} hints=#{givens.length} line_solves=#{current[:line_solves]} guesses=#{current[:guesses]}"
    lines.concat(["PUZZLE #{puzzle[:name]}", "SIZE #{puzzle[:width]} #{puzzle[:height]}", 'ROWS'])
    lines.concat(puzzle[:rows].map { |clue| Clues.text(clue) })
    lines << 'COLUMNS'
    lines.concat(puzzle[:columns].map { |clue| Clues.text(clue) })
    givens.sort_by { |row, column, _| [row, column] }.each do |row, column, value|
      lines << "GIVEN #{row + 1} #{column + 1} #{Render.symbol(value)}"
    end
    lines << 'END'
    [lines, plain, givens.length]
  end

  def picture_reports
    seen = Set.new
    blocks = read_blocks('input/pictures.txt', 'PICTURE')
    counts = { invalid: 0, unique: 0, line_logic: 0, hinted: 0, hints: 0 }
    paragraphs = blocks.map do |block|
      duplicate = seen.include?(block[:name])
      seen.add(block[:name])
      error = validate_picture(block, duplicate)
      if error
        counts[:invalid] += 1
        ["# picture #{block[:name]} error #{error}"]
      else
        lines, plain, hints = generated_picture(block)
        counts[:unique] += 1 if plain[:status] == 'unique'
        counts[:line_logic] += 1 if %w[easy medium].include?(plain[:difficulty])
        counts[:hinted] += 1 if hints.positive?
        counts[:hints] += hints
        lines
      end
    end
    paragraphs << ["# SUMMARY pictures=#{blocks.length} invalid=#{counts[:invalid]} unique=#{counts[:unique]} line_logic=#{counts[:line_logic]} hinted=#{counts[:hinted]} hints=#{counts[:hints]}"]
    paragraphs
  end

  def paragraph_text(paragraphs)
    paragraphs.map { |lines| lines.join("\n") }.join("\n\n") + "\n"
  end

  def run
    solutions, statistics = puzzle_reports
    Dir.mkdir('output') unless Dir.exist?('output')
    File.binwrite('output/solutions.txt', paragraph_text(solutions))
    File.binwrite('output/stats.csv', statistics.join("\n") + "\n")
    generated = picture_reports
    File.binwrite('output/generated.txt', paragraph_text(generated))
  end
end

NonogramAnalysis.new.run
