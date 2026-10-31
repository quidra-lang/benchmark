module Report
  def self.tree(doc, depth = 0)
    prefix = '  ' * depth
    return [prefix + "text \"#{doc}\""] if doc.is_a?(String)
    case doc[:kind]
    when :concat then doc[:parts].flat_map { |part| tree(part, depth) }
    when :group then [prefix + "group #{doc[:mode]}"] + tree(doc[:child], depth + 1)
    when :nest then [prefix + "nest #{doc[:amount]}"] + tree(doc[:child], depth + 1)
    when :align then [prefix + 'align'] + tree(doc[:child], depth + 1)
    when :suffix then [prefix + "suffix \"#{doc[:text]}\""]
    when :if_break then [prefix + "if_break \"#{doc[:broken]}\" \"#{doc[:flat]}\""]
    else [prefix + doc[:kind].to_s]
    end
  end

  def self.diff(a, b)
    n, m = a.length, b.length
    lcs = Array.new(n + 1) { Array.new(m + 1, 0) }
    (n - 1).downto(0) do |i|
      (m - 1).downto(0) do |j|
        lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : [lcs[i + 1][j], lcs[i][j + 1]].max
      end
    end
    i = j = 0
    hunks, hunk = [], nil
    while i < n || j < m
      if i < n && j < m && a[i] == b[j]
        hunks << hunk if hunk
        hunk = nil
        i += 1
        j += 1
      else
        hunk ||= {i: i, j: j, deleted: 0, inserted: 0, rows: []}
        if j == m || (i < n && lcs[i + 1][j] >= lcs[i][j + 1])
          hunk[:rows] << '-' + a[i]
          hunk[:deleted] += 1
          i += 1
        else
          hunk[:rows] << '+' + b[j]
          hunk[:inserted] += 1
          j += 1
        end
      end
    end
    hunks << hunk if hunk
    rows = ["hunks=#{hunks.length} deleted=#{hunks.sum { |h| h[:deleted] }} inserted=#{hunks.sum { |h| h[:inserted] }}"]
    hunks.each do |h|
      d, e = h.values_at(:deleted, :inserted)
      rows << "@@ -#{h[:i] + (d > 0 ? 1 : 0)},#{d} +#{h[:j] + (e > 0 ? 1 : 0)},#{e} @@"
      rows.concat(h[:rows])
    end
    rows
  end
end
