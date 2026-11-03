require 'set'
require_relative 'schema_io'
require_relative 'bitstream'
require_relative 'encoding'
require_relative 'query'

SCAN_COUNTS = %w[row_groups_read row_groups_skipped pages_read pages_skipped pages_unneeded dictionary_pages_read bytes_read rows_scanned rows_matched].freeze
UNKNOWN_CELL = Object.new.freeze

def statistics(values)
  present = values.compact
  present.empty? ? nil : present.minmax { |first, second| SchemaIO.compare(first, second) }
end

def statistics_text(column, bounds)
  bounds ? "min #{SchemaIO.value_text(column[:type], bounds[0])} max #{SchemaIO.value_text(column[:type], bounds[1])}" : 'stats none'
end

def method_list(methods)
  methods.map { |method| ValueEncoding::METHODS[method] }.join(',')
end

def column_line(index, column)
  "column #{index} #{column[:name]} #{column[:type]} #{column[:nullable] ? 'NULLABLE' : 'REQUIRED'}"
end

def build_page(column, kind, method, values, dictionary = nil)
  if kind == 1
    body = ValueEncoding.encode_values(column[:type], 0, values)
    nulls, bounds = 0, nil
  else
    present = values.compact
    nulls, bounds = values.length - present.length, statistics(values)
    body = ''.b
    if column[:nullable]
      levels = Bitstream.hybrid_encode(values.map { |value| value.nil? ? 0 : 1 }, 1)
      body << Bitstream.integer(levels.bytesize) << levels
    end
    body << ValueEncoding.encode_values(column[:type], method, present, dictionary)
  end
  header = [kind, method].pack('C*') + Bitstream.uleb(values.length) + Bitstream.uleb(nulls) + Bitstream.uleb(body.bytesize)
  header + Bitstream.integer(Bitstream.adler32(body)) + ValueEncoding.encode_statistics(column[:type], bounds) + body
end

def build_chunk(column, values, method, page_size, limit)
  pages = values.each_slice(page_size).to_a
  dictionary, dictionary_pages = [], 0
  if method == 1
    known, bytes = Set.new, 0
    pages.each do |page|
      additions, proposed = [], known.dup
      page.each do |value|
        next if value.nil? || proposed.include?(value)
        additions << value
        proposed.add(value)
      end
      size = bytes + ValueEncoding.encode_values(column[:type], 0, additions).bytesize
      break if size > limit
      dictionary.concat(additions)
      known, bytes = proposed, size
      dictionary_pages += 1
    end
    dictionary_pages = 0 if dictionary.empty?
  end
  data, methods = ''.b, Set.new
  data << build_page(column, 1, 0, dictionary) if dictionary_pages > 0
  pages.each_with_index do |page, index|
    selected = method == 1 ? (index < dictionary_pages ? 1 : 0) : method
    methods.add(selected)
    data << build_page(column, 0, selected, page, dictionary)
  end
  { data: data, size: data.bytesize, methods: methods.to_a.sort, has_dictionary: dictionary_pages > 0,
    page_count: pages.length, nulls: values.count(nil), statistics: statistics(values),
    fallback: method == 1 ? pages.length - dictionary_pages : 0 }
end

def build_file(columns, rows, options)
  data, groups = 'MPTC'.b, []
  report = ['row_group,column,encoding,bytes,fallback_pages,chosen']
  rows.each_slice(options[:row_group_size]) do |group_rows|
    group = { rows: group_rows.length, chunks: [] }
    columns.each_with_index do |column, index|
      values = group_rows.map { |row| row[index] }
      candidates = ValueEncoding::CANDIDATES[column[:type]].to_h do |method|
        [method, build_chunk(column, values, method, options[:page_size], options[:dictionary_limit])]
      end
      requested = options[:encoding][column[:name]]
      chosen = if requested == 'AUTO'
                 candidates.keys.min_by { |method| [candidates[method][:size], method] }
               else
                 ValueEncoding::METHODS.index(requested)
               end
      chosen = 0 if chosen == 1 && !candidates[chosen][:has_dictionary]
      candidates.each do |method, candidate|
        report << "#{groups.length},#{column[:name]},#{ValueEncoding::METHODS[method]},#{candidate[:size]},#{candidate[:fallback]},#{method == chosen ? 'yes' : 'no'}"
      end
      chunk = candidates[chosen]
      chunk[:offset] = data.bytesize
      data << chunk[:data]
      group[:chunks] << chunk
    end
    groups << group
  end
  footer = Bitstream.uleb(1) + Bitstream.uleb(columns.length)
  columns.each do |column|
    footer << Bitstream.uleb(column[:name].bytesize) << column[:name].b
    footer << [SchemaIO::TYPES.index(column[:type]), column[:nullable] ? 1 : 0].pack('C*')
  end
  footer << Bitstream.uleb(rows.length) << Bitstream.uleb(groups.length)
  groups.each do |group|
    footer << Bitstream.uleb(group[:rows])
    columns.zip(group[:chunks]).each do |column, chunk|
      footer << Bitstream.uleb(chunk[:offset]) << Bitstream.uleb(chunk[:size])
      footer << Bitstream.uleb(chunk[:methods].length) << chunk[:methods].pack('C*')
      footer << [chunk[:has_dictionary] ? 1 : 0].pack('C')
      footer << Bitstream.uleb(chunk[:page_count]) << Bitstream.uleb(chunk[:nulls])
      footer << ValueEncoding.encode_statistics(column[:type], chunk[:statistics])
    end
  end
  [data + footer + Bitstream.integer(footer.bytesize) + 'MPTC'.b, report]
end

def parse_file(data)
  footer_size = Bitstream::Reader.new(data, data.bytesize - 8).integer
  footer_offset = data.bytesize - 8 - footer_size
  reader = Bitstream::Reader.new(data, footer_offset)
  version = reader.uleb
  columns = Array.new(reader.uleb) do
    name = reader.read(reader.uleb)
    { name: name, type: SchemaIO::TYPES[reader.byte], nullable: reader.byte == 1 }
  end
  rows, group_count, first_row = reader.uleb, reader.uleb, 0
  groups = Array.new(group_count) do
    count = reader.uleb
    chunks = columns.map do |column|
      offset, size = reader.uleb, reader.uleb
      methods = Array.new(reader.uleb) { reader.byte }
      has_dictionary = reader.byte == 1
      pages, nulls = reader.uleb, reader.uleb
      { offset: offset, size: size, methods: methods, has_dictionary: has_dictionary,
        page_count: pages, nulls: nulls, statistics: ValueEncoding.decode_statistics(reader, column[:type]) }
    end
    group = { rows: count, first_row: first_row, chunks: chunks }
    first_row += count
    group
  end
  groups.each do |group|
    columns.zip(group[:chunks]).each do |column, chunk|
      reader = Bitstream::Reader.new(data, chunk[:offset])
      pages = []
      while reader.position < chunk[:offset] + chunk[:size]
        start = reader.position
        kind, method = reader.byte, reader.byte
        count, nulls, size = reader.uleb, reader.uleb, reader.uleb
        checksum = reader.integer
        bounds = ValueEncoding.decode_statistics(reader, column[:type])
        header_size = reader.position - start
        pages << { offset: start, kind: kind, method: method, values: count, nulls: nulls,
                   body_size: size, checksum: checksum, statistics: bounds, header_size: header_size,
                   body_offset: reader.position, size: header_size + size }
        reader.position += size
      end
      chunk[:dictionary] = chunk[:has_dictionary] ? pages.shift : nil
      chunk[:pages] = pages
    end
  end
  { data: data, version: version, columns: columns, rows: rows, groups: groups, footer_size: footer_size, footer_offset: footer_offset }
end

def page_body(file, page)
  file[:data].byteslice(page[:body_offset], page[:body_size])
end

def decode_dictionary(file, column, page)
  ValueEncoding.decode_values(Bitstream::Reader.new(page_body(file, page)), column[:type], 0, page[:values])
end

def decode_page(file, column, page, dictionary = nil)
  reader = Bitstream::Reader.new(page_body(file, page))
  count = page[:values]
  levels = if column[:nullable]
             Bitstream.hybrid_decode(Bitstream::Reader.new(reader.read(reader.integer)), 1, count)
           else
             Array.new(count, 1)
           end
  values = ValueEncoding.decode_values(reader, column[:type], page[:method], levels.count(1), dictionary)
  index = 0
  levels.map do |level|
    next nil unless level == 1
    value = values[index]
    index += 1
    value
  end
end

def verify_and_describe(file, original)
  columns = file[:columns]
  lines = ["file bytes #{file[:data].bytesize} footer_offset #{file[:footer_offset]} footer_bytes #{file[:footer_size]}",
           "table version #{file[:version]} rows #{file[:rows]} columns #{columns.length} row_groups #{file[:groups].length}"]
  columns.each_with_index { |column, index| lines << column_line(index, column) }
  summaries = Array.new(columns.length) { { bytes: 0, data_pages: 0, dictionary_pages: 0, methods: Set.new } }
  cells, nulls, mismatches, checksum_errors = 0, 0, 0, 0
  file[:groups].each_with_index do |group, number|
    lines << "row_group #{number} rows #{group[:rows]} first_row #{group[:first_row]} bytes #{group[:chunks].sum { |chunk| chunk[:size] }}"
    columns.zip(group[:chunks]).each_with_index do |(column, chunk), index|
      lines << "chunk #{number} #{column[:name]} offset #{chunk[:offset]} size #{chunk[:size]} encodings #{method_list(chunk[:methods])} dictionary #{chunk[:has_dictionary] ? 'yes' : 'no'} pages #{chunk[:page_count]} nulls #{chunk[:nulls]} #{statistics_text(column, chunk[:statistics])}"
      summary = summaries[index]
      summary[:bytes] += chunk[:size]
      summary[:data_pages] += chunk[:page_count]
      summary[:dictionary_pages] += 1 if chunk[:has_dictionary]
      summary[:methods].merge(chunk[:methods])
      dictionary = nil
      if (page = chunk[:dictionary])
        checksum_errors += 1 if Bitstream.adler32(page_body(file, page)) != page[:checksum]
        dictionary = decode_dictionary(file, column, page)
        lines << "page #{number} #{column[:name]} dict offset #{page[:offset]} header #{page[:header_size]} body #{page[:body_size]} checksum #{format('%08x', page[:checksum])} entries #{page[:values]}"
      end
      row_number = group[:first_row]
      chunk[:pages].each_with_index do |page, page_number|
        checksum_errors += 1 if Bitstream.adler32(page_body(file, page)) != page[:checksum]
        lines << "page #{number} #{column[:name]} #{page_number} offset #{page[:offset]} header #{page[:header_size]} body #{page[:body_size]} checksum #{format('%08x', page[:checksum])} encoding #{ValueEncoding::METHODS[page[:method]]} values #{page[:values]} nulls #{page[:nulls]} #{statistics_text(column, page[:statistics])}"
        decode_page(file, column, page, dictionary).each do |value|
          cells += 1
          nulls += 1 if value.nil?
          mismatches += 1 if value != original[row_number][index]
          row_number += 1
        end
      end
    end
  end
  columns.zip(summaries).each do |column, summary|
    lines << "summary #{column[:name]} bytes #{summary[:bytes]} data_pages #{summary[:data_pages]} dictionary_pages #{summary[:dictionary_pages]} encodings #{method_list(summary[:methods].to_a.sort)}"
  end
  lines << "roundtrip #{mismatches.zero? && checksum_errors.zero? ? 'ok' : 'failed'} cells #{cells} nulls #{nulls} mismatches #{mismatches} checksum_errors #{checksum_errors}"
  lines
end

def condition_leaves(tree)
  return [] unless tree
  case tree[0]
  when 'NOT' then condition_leaves(tree[1])
  when 'AND', 'OR' then condition_leaves(tree[1]) + condition_leaves(tree[2])
  else [tree]
  end
end

def convert_condition(tree, columns, indices)
  return nil unless tree
  operation = tree[0]
  return [operation, convert_condition(tree[1], columns, indices)] if operation == 'NOT'
  if %w[AND OR].include?(operation)
    return [operation, convert_condition(tree[1], columns, indices), convert_condition(tree[2], columns, indices)]
  end
  index = indices[tree[1]]
  literals = tree[2].map { |_type, value| columns[index][:type] == 'DATE' ? SchemaIO.day_number(value) : value }
  [operation, index, literals]
end

def item_header(operation, name)
  return name if operation == 'COLUMN'
  return "COUNT(DISTINCT #{name})" if operation == 'COUNT_DISTINCT'
  "#{operation}(#{name || '*'})"
end

def check_query(raw, columns)
  indices = columns.each_with_index.to_h { |column, index| [column[:name], index] }
  items = raw[:items] || columns.map { |column| ['COLUMN', column[:name]] }
  leaves = condition_leaves(raw[:condition])
  names = items.map(&:last).compact + leaves.map { |leaf| leaf[1] } + [raw[:group], raw[:order]].compact
  return ['unknown_column', nil] if names.any? { |name| !indices.key?(name) }
  leaves.each do |_operation, name, literals|
    type = columns[indices[name]][:type]
    expected = type == 'DATE' ? 'STRING' : type
    return ['type_mismatch', nil] if literals.any? { |literal_type, _value| literal_type != expected }
  end
  if items.any? { |operation, name| %w[SUM AVG].include?(operation) && columns[indices[name]][:type] != 'INT' }
    return ['bad_aggregate', nil]
  end
  aggregate = !raw[:group].nil? || items.any? { |operation, _name| operation != 'COLUMN' }
  return ['not_grouped', nil] if aggregate && items.any? { |operation, name| operation == 'COLUMN' && name != raw[:group] }
  return ['bad_order', nil] if aggregate && raw[:order]
  plan = { items: items.map { |operation, name| [operation, name && indices[name]] },
           headers: items.map { |operation, name| item_header(operation, name) },
           condition: convert_condition(raw[:condition], columns, indices),
           group: raw[:group] && indices[raw[:group]], order: raw[:order] && indices[raw[:order]],
           descending: raw[:descending], limit: raw[:limit], aggregate: aggregate,
           needed: names.map { |name| indices[name] }.uniq.sort,
           condition_columns: leaves.map { |leaf| indices[leaf[1]] }.uniq.sort }
  [nil, plan]
end

def logical_not(value)
  value.nil? ? nil : !value
end

def logical_pair(operation, first, second)
  if operation == 'AND'
    return false if first == false || second == false
    first.nil? || second.nil? ? nil : true
  else
    return true if first == true || second == true
    first.nil? || second.nil? ? nil : false
  end
end

def compare_value(operation, value, literals)
  return value.nil? if operation == 'IS_NULL'
  return !value.nil? if operation == 'IS_NOT_NULL'
  return nil if value.nil?
  if operation == 'BETWEEN'
    return SchemaIO.compare(literals[0], value) <= 0 && SchemaIO.compare(value, literals[1]) <= 0
  end
  return literals.include?(value) if operation == 'IN'
  comparison = SchemaIO.compare(value, literals[0])
  case operation
  when '=' then comparison.zero?
  when '<>' then comparison != 0
  when '<' then comparison < 0
  when '<=' then comparison <= 0
  when '>' then comparison > 0
  when '>=' then comparison >= 0
  end
end

def evaluate(tree, row)
  return true unless tree
  operation = tree[0]
  return logical_not(evaluate(tree[1], row)) if operation == 'NOT'
  return logical_pair(operation, evaluate(tree[1], row), evaluate(tree[2], row)) if %w[AND OR].include?(operation)
  compare_value(operation, row[tree[1]], tree[2])
end

def range_possibilities(operation, low, high, literals)
  if operation == 'BETWEEN'
    first, last = literals
    return [SchemaIO.compare(low, last) <= 0 && SchemaIO.compare(high, first) >= 0 && SchemaIO.compare(first, last) <= 0,
            SchemaIO.compare(low, first) < 0 || SchemaIO.compare(high, last) > 0]
  end
  if operation == 'IN'
    return [literals.any? { |value| SchemaIO.compare(low, value) <= 0 && SchemaIO.compare(value, high) <= 0 },
            !(low == high && literals.include?(low))]
  end
  value = literals[0]
  lo, hi = SchemaIO.compare(low, value), SchemaIO.compare(high, value)
  case operation
  when '=' then [lo <= 0 && hi >= 0, !(lo.zero? && hi.zero?)]
  when '<>' then [!(lo.zero? && hi.zero?), lo <= 0 && hi >= 0]
  when '<' then [lo < 0, hi >= 0]
  when '<=' then [lo <= 0, hi > 0]
  when '>' then [hi > 0, lo <= 0]
  when '>=' then [hi >= 0, lo < 0]
  end
end

def zone_values(tree, zones)
  operation = tree[0]
  return zone_values(tree[1], zones).map { |value| logical_not(value) }.uniq if operation == 'NOT'
  if %w[AND OR].include?(operation)
    return zone_values(tree[1], zones).product(zone_values(tree[2], zones)).map { |first, second| logical_pair(operation, first, second) }.uniq
  end
  bounds, nulls, count = zones.fetch(tree[1])
  values = []
  if %w[IS_NULL IS_NOT_NULL].include?(operation)
    values << (operation == 'IS_NULL') if nulls > 0
    values << (operation == 'IS_NOT_NULL') if nulls < count
  else
    values << nil if nulls > 0
    if bounds
      can_true, can_false = range_possibilities(operation, *bounds, tree[2])
      values << true if can_true
      values << false if can_false
    end
  end
  values.uniq
end

def read_scan_page(file, group, index, number, dictionaries, counts)
  column, chunk = file[:columns][index], file[:groups][group][:chunks][index]
  page = chunk[:pages][number]
  dictionary = nil
  if page[:method] == 1
    key = [group, index]
    unless dictionaries.key?(key)
      dictionary_page = chunk[:dictionary]
      dictionaries[key] = decode_dictionary(file, column, dictionary_page)
      counts['dictionary_pages_read'] += 1
      counts['bytes_read'] += dictionary_page[:size]
    end
    dictionary = dictionaries[key]
  end
  counts['pages_read'] += 1
  counts['bytes_read'] += page[:size]
  decode_page(file, column, page, dictionary)
end

def scan(file, plan)
  counts, records, matched, dictionaries = Hash.new(0), [], [], {}
  condition, condition_columns = plan.values_at(:condition, :condition_columns)
  remaining = plan[:needed] - condition_columns
  file[:groups].each_with_index do |group, group_number|
    zones = condition_columns.to_h do |index|
      chunk = group[:chunks][index]
      [index, [chunk[:statistics], chunk[:nulls], group[:rows]]]
    end
    if condition && !zone_values(condition, zones).include?(true)
      counts['row_groups_skipped'] += 1
      records << nil
      next
    end
    counts['row_groups_read'] += 1
    if plan[:needed].empty?
      counts['rows_scanned'] += group[:rows]
      matched.concat(Array.new(group[:rows]) { Array.new(file[:columns].length) })
      records << '-'
      next
    end
    record = +''
    group[:chunks][0][:page_count].times do |number|
      zones = condition_columns.to_h do |index|
        page = group[:chunks][index][:pages][number]
        [index, [page[:statistics], page[:nulls], page[:values]]]
      end
      if condition && !zone_values(condition, zones).include?(true)
        counts['pages_skipped'] += plan[:needed].length
        record << 's'
        next
      end
      row_count = group[:chunks][0][:pages][number][:values]
      counts['rows_scanned'] += row_count
      rows = Array.new(row_count) { Array.new(file[:columns].length) }
      condition_columns.each do |index|
        read_scan_page(file, group_number, index, number, dictionaries, counts).each_with_index { |value, offset| rows[offset][index] = value }
      end
      selected = rows.each_index.select { |offset| evaluate(condition, rows[offset]) == true }
      if selected.empty? && !remaining.empty?
        counts['pages_unneeded'] += remaining.length
        record << 'u'
        next
      end
      remaining.each do |index|
        read_scan_page(file, group_number, index, number, dictionaries, counts).each_with_index { |value, offset| rows[offset][index] = value }
      end
      matched.concat(selected.map { |offset| rows[offset] })
      record << 'r'
    end
    records << record
  end
  counts['rows_matched'] = matched.length
  [matched, counts, records]
end

def aggregate_item(columns, operation, index, rows, key)
  return SchemaIO.value_text(columns[index][:type], key) if operation == 'COLUMN'
  return rows.length.to_s if operation == 'COUNT' && index.nil?
  values = rows.map { |row| row[index] }.compact
  return values.length.to_s if operation == 'COUNT'
  return values.uniq.length.to_s if operation == 'COUNT_DISTINCT'
  return 'NULL' if values.empty?
  return values.sum.to_s if operation == 'SUM'
  if operation == 'AVG'
    total = values.sum
    divisor = total.gcd(values.length)
    numerator, denominator = total / divisor, values.length / divisor
    return denominator == 1 ? numerator.to_s : "#{numerator}/#{denominator}"
  end
  bounds = values.minmax { |first, second| SchemaIO.compare(first, second) }
  SchemaIO.value_text(columns[index][:type], operation == 'MIN' ? bounds[0] : bounds[1])
end

def nullable_compare(first, second)
  return 0 if first.nil? && second.nil?
  return -1 if first.nil?
  return 1 if second.nil?
  SchemaIO.compare(first, second)
end

def build_result(columns, plan, matched)
  unless plan[:aggregate]
    kind, arranged = 'rows', matched
    unless plan[:order].nil?
      index = plan[:order]
      arranged = matched.each_with_index.sort do |(first, a), (second, b)|
        comparison = nullable_compare(first[index], second[index])
        comparison = -comparison if plan[:descending]
        comparison.zero? ? a <=> b : comparison
      end.map(&:first)
    end
    output = arranged.map do |row|
      plan[:items].map { |_operation, index| SchemaIO.value_text(columns[index][:type], row[index]) }.join(',')
    end
  else
    if plan[:group].nil?
      kind, groups = 'aggregate', [[nil, matched]]
    else
      kind = 'grouped'
      grouped = matched.group_by { |row| row[plan[:group]] }
      groups = grouped.keys.sort { |first, second| nullable_compare(first, second) }.map { |key| [key, grouped[key]] }
    end
    output = groups.map do |key, rows|
      plan[:items].map { |operation, index| aggregate_item(columns, operation, index, rows, key) }.join(',')
    end
  end
  output = output.first(plan[:limit]) if plan[:limit]
  [kind, matched.length, output]
end

def counts_text(counts)
  SCAN_COUNTS.map { |name| "#{name} #{counts[name]}" }.join(' ')
end

def execute_queries(file, originals, queries)
  results, stats, totals = [], [], Hash.new(0)
  errors, checks_ok = 0, 0
  columns = file[:columns]
  queries.each_with_index do |text, index|
    number = index + 1
    error, plan = check_query(QueryParser.new(text).parse, columns)
    if error
      line = "query #{number} error #{error}"
      results << line
      stats << line
      errors += 1
      next
    end
    matched, counts, records = scan(file, plan)
    result = build_result(columns, plan, matched)
    reference = originals.select { |row| evaluate(plan[:condition], row) == true }
    check = result == build_result(columns, plan, reference) ? 'ok' : 'mismatch'
    checks_ok += 1 if check == 'ok'
    kind, matched_count, output = result
    results << "query #{number} #{kind} matched #{matched_count} output #{output.length}"
    results << "columns #{plan[:headers].join(',')}"
    results.concat(output)
    needed = plan[:needed].map { |column| columns[column][:name] }.join(',')
    stats << "query #{number} columns #{needed.empty? ? '-' : needed} #{counts_text(counts)} check #{check}"
    records.each_with_index { |record, group| stats << "query #{number} row_group #{group} #{record ? "pages #{record}" : 'skipped'}" }
    SCAN_COUNTS.each { |name| totals[name] += counts[name] }
  end
  stats << "total queries #{queries.length} errors #{errors} #{counts_text(totals)} checks_ok #{checks_ok}"
  [results, stats]
end

def recover(data)
  file = parse_file(data)
  columns = file[:columns]
  rows = Array.new(file[:rows]) { Array.new(columns.length, UNKNOWN_CELL) }
  lines = ["file bytes #{data.bytesize} rows #{file[:rows]} columns #{columns.length} row_groups #{file[:groups].length}"]
  columns.each_with_index { |column, index| lines << column_line(index, column) }
  examined, damaged_count, lost_pages, lost_cells = 0, 0, 0, 0
  file[:groups].each_with_index do |group, number|
    columns.zip(group[:chunks]).each_with_index do |(column, chunk), index|
      dictionary, dictionary_damaged = nil, false
      pages = chunk[:pages].each_with_index.map { |page, p| [p, page] }
      pages.unshift(['dict', chunk[:dictionary]]) if chunk[:dictionary]
      row_number = group[:first_row]
      pages.each do |page_number, page|
        examined += 1
        checksum = Bitstream.adler32(page_body(file, page))
        damaged = checksum != page[:checksum]
        if damaged
          damaged_count += 1
          lines << "damaged #{number} #{column[:name]} #{page_number} offset #{page[:offset]} stored #{format('%08x', page[:checksum])} computed #{format('%08x', checksum)}"
        end
        if page_number == 'dict'
          dictionary_damaged = damaged
          dictionary = decode_dictionary(file, column, page) unless damaged
          next
        end
        reason = damaged ? 'checksum' : page[:method] == 1 && dictionary_damaged ? 'dictionary' : nil
        if reason
          lost_pages += 1
          lost_cells += page[:values]
          lines << "lost #{number} #{column[:name]} #{page_number} rows #{page[:values]} reason #{reason}"
        else
          decode_page(file, column, page, dictionary).each_with_index { |value, offset| rows[row_number + offset][index] = value }
        end
        row_number += page[:values]
      end
    end
  end
  lines << "summary pages #{examined} damaged #{damaged_count} lost_pages #{lost_pages} lost_cells #{lost_cells} recovered_cells #{file[:rows] * columns.length - lost_cells}"
  recovered = [columns.map { |column| column[:name] }.join(',')]
  rows.each do |row|
    recovered << columns.zip(row).map { |column, value| value.equal?(UNKNOWN_CELL) ? '?' : SchemaIO.value_text(column[:type], value, '') }.join(',')
  end
  [lines, recovered]
end

def main
  columns, rows, options, queries, damaged = SchemaIO.read_inputs
  data, encoding_report = build_file(columns, rows, options)
  file = parse_file(data)
  metadata = verify_and_describe(file, rows)
  results, query_stats = execute_queries(file, rows, queries)
  recovery, recovered = recover(damaged)
  hex = data.unpack1('H*').scan(/.{1,64}/)
  SchemaIO.write_outputs('file.hex' => hex, 'metadata.txt' => metadata, 'encoding_report.csv' => encoding_report,
                         'query_results.txt' => results, 'query_stats.txt' => query_stats,
                         'recovery.txt' => recovery, 'recovered.csv' => recovered)
end

main if $PROGRAM_NAME == __FILE__
