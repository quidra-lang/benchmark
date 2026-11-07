local DATA_COMMANDS = { "FILE", "PATCH", "EDIT" }
local FORMATS_WITH_ARGUMENT = { "IFDEF", "UNIFIED", "CONTEXT", "SIDE" }
local OFFSETS = { 0, 1, -1, 2, -2, 3, -3 }
local GRAPH_WIDTH = 20
local NUMBER = "(%d%d?%d?%d?)"
local NUMBER_PAIR = "^" .. NUMBER .. "," .. NUMBER .. "$"
local SINGLE_NUMBER = "^" .. NUMBER .. "$"
local MARKER_PREFIXES = { ["<<<<<<<"] = "start", ["|||||||"] = "base", [">>>>>>>"] = "end" }
local SEPARATOR = "======="

local function fail(message)
  error({ message = message })
end

local function contains(list, value)
  for _, item in ipairs(list) do
    if item == value then
      return true
    end
  end
  return false
end

local function slice(list, first, last)
  return table.move(list, first, last or #list, 1, {})
end

local function extend(target, items)
  return table.move(items, 1, #items, #target + 1, target)
end

local function add_prefixed(target, prefix, items)
  for _, item in ipairs(items) do
    target[#target + 1] = prefix .. item
  end
end

local function lists_equal(first, second)
  if #first ~= #second then
    return false
  end
  for index = 1, #first do
    if first[index] ~= second[index] then
      return false
    end
  end
  return true
end

local function split(text, separator)
  local parts = {}
  for part in (text .. separator):gmatch("(.-)" .. separator) do
    parts[#parts + 1] = part
  end
  return parts
end

local function parse_number_pair(text)
  local first, second = text:match(NUMBER_PAIR)
  if first then
    return tonumber(first), tonumber(second)
  end
  first = text:match(SINGLE_NUMBER)
  return first and tonumber(first)
end

local function range_r(start, count)
  if count >= 2 then
    return (start + 1) .. "," .. (start + count)
  elseif count == 1 then
    return tostring(start + 1)
  end
  return tostring(start)
end

local function range_u(start, count)
  if count >= 2 then
    return (start + 1) .. "," .. count
  elseif count == 1 then
    return tostring(start + 1)
  end
  return start .. ",0"
end

local function range_m(start, count)
  return (start + 1) .. "," .. count
end

local function comparison_key(line, options)
  if contains(options, "ICASE") then
    line = line:lower()
  end
  if contains(options, "IWHITE") then
    line = line:gsub(" ", "")
  end
  if contains(options, "ISPACE") then
    line = line:gsub("  +", " ")
  end
  return line
end

local function matched_pairs(first, second)
  local rows, columns = #first, #second
  local lengths = {}
  for i = 0, rows do
    lengths[i] = {}
    for j = 0, columns do
      if i == 0 or j == 0 then
        lengths[i][j] = 0
      elseif first[i] == second[j] then
        lengths[i][j] = lengths[i - 1][j - 1] + 1
      else
        lengths[i][j] = math.max(lengths[i - 1][j], lengths[i][j - 1])
      end
    end
  end
  local matches = { { rows + 1, columns + 1 } }
  local i, j = rows, columns
  while i >= 1 and j >= 1 do
    if first[i] == second[j] then
      matches[#matches + 1] = { i, j }
      i, j = i - 1, j - 1
    elseif lengths[i - 1][j] >= lengths[i][j - 1] then
      i = i - 1
    else
      j = j - 1
    end
  end
  matches[#matches + 1] = { 0, 0 }
  local ordered = {}
  for index = #matches, 1, -1 do
    ordered[#ordered + 1] = matches[index]
  end
  return ordered
end

local ChangeBlock = {}
ChangeBlock.__index = ChangeBlock

function ChangeBlock.new(p, q, x, y)
  return setmetatable({ p = p, q = q, x = x, y = y }, ChangeBlock)
end

function ChangeBlock:letter()
  if self.x >= 1 and self.y >= 1 then
    return "c"
  end
  return self.y == 0 and "d" or "a"
end

local function change_blocks(first, second)
  local matches = matched_pairs(first, second)
  local blocks = {}
  for index = 1, #matches - 1 do
    local i, j = table.unpack(matches[index])
    local next_i, next_j = table.unpack(matches[index + 1])
    if next_i - i > 1 or next_j - j > 1 then
      blocks[#blocks + 1] = ChangeBlock.new(i, j, next_i - i - 1, next_j - j - 1)
    end
  end
  return blocks
end

local function walk(blocks, old_start, new_start, old_end)
  local steps = {}
  local old_index, new_index = old_start, new_start
  for _, block in ipairs(blocks) do
    while old_index < block.p do
      old_index, new_index = old_index + 1, new_index + 1
      steps[#steps + 1] = { old_line = old_index, new_line = new_index }
    end
    steps[#steps + 1] = { block = block }
    old_index, new_index = block.p + block.x, block.q + block.y
  end
  while old_index < old_end do
    old_index, new_index = old_index + 1, new_index + 1
    steps[#steps + 1] = { old_line = old_index, new_line = new_index }
  end
  return steps
end

local function side_row(left, symbol, right, width)
  local row = string.format("%-" .. width .. "s %s %s", left:sub(1, width), symbol, right:sub(1, width))
  return (row:gsub(" +$", ""))
end

local function stat_graph(inserted, deleted)
  local total = inserted + deleted
  local plus, minus = inserted, deleted
  if total > GRAPH_WIDTH then
    plus = GRAPH_WIDTH * inserted // total
    minus = GRAPH_WIDTH * deleted // total
    if inserted >= 1 and plus == 0 then
      plus = 1
    end
    if deleted >= 1 and minus == 0 then
      minus = 1
    end
  end
  return string.rep("+", plus) .. string.rep("-", minus)
end

local Hunk = {}
Hunk.__index = Hunk

function Hunk.new(blocks, context, old_total)
  local first, last = blocks[1], blocks[#blocks]
  local before = math.min(context, first.p)
  local after = math.min(context, old_total - last.p - last.x)
  local hunk = setmetatable({ blocks = blocks }, Hunk)
  hunk.old_start = first.p - before
  hunk.old_count = last.p + last.x + after - hunk.old_start
  hunk.new_start = first.q - before
  hunk.new_count = last.q + last.y + after - hunk.new_start
  return hunk
end

function Hunk:steps()
  return walk(self.blocks, self.old_start, self.new_start, self.old_start + self.old_count)
end

local LineDiff = {}
LineDiff.__index = LineDiff

function LineDiff.new(old, new, options)
  options = options or {}
  local old_keys, new_keys = {}, {}
  for index, line in ipairs(old) do
    old_keys[index] = comparison_key(line, options)
  end
  for index, line in ipairs(new) do
    new_keys[index] = comparison_key(line, options)
  end
  return setmetatable({ old = old, new = new, blocks = change_blocks(old_keys, new_keys) }, LineDiff)
end

function LineDiff:deleted(block)
  return slice(self.old, block.p + 1, block.p + block.x)
end

function LineDiff:inserted(block)
  return slice(self.new, block.q + 1, block.q + block.y)
end

function LineDiff:hunks(context)
  local groups = {}
  local previous
  for _, block in ipairs(self.blocks) do
    if previous and block.p - (previous.p + previous.x) <= 2 * context then
      table.insert(groups[#groups], block)
    else
      groups[#groups + 1] = { block }
    end
    previous = block
  end
  local hunks = {}
  for index, group in ipairs(groups) do
    hunks[index] = Hunk.new(group, context, #self.old)
  end
  return hunks
end

function LineDiff:normal()
  local lines = {}
  for _, block in ipairs(self.blocks) do
    local letter = block:letter()
    lines[#lines + 1] = range_r(block.p, block.x) .. letter .. range_r(block.q, block.y)
    add_prefixed(lines, "< ", self:deleted(block))
    if letter == "c" then
      lines[#lines + 1] = "---"
    end
    add_prefixed(lines, "> ", self:inserted(block))
  end
  return lines
end

function LineDiff:ed()
  local lines = {}
  for index = #self.blocks, 1, -1 do
    local block = self.blocks[index]
    local letter = block:letter()
    lines[#lines + 1] = range_r(block.p, block.x) .. letter
    if letter ~= "d" then
      extend(lines, self:inserted(block))
      lines[#lines + 1] = "."
    end
  end
  return lines
end

function LineDiff:rcs()
  local lines = {}
  for _, block in ipairs(self.blocks) do
    if block.x >= 1 then
      lines[#lines + 1] = "d" .. (block.p + 1) .. " " .. block.x
    end
    if block.y >= 1 then
      lines[#lines + 1] = "a" .. (block.p + block.x) .. " " .. block.y
      extend(lines, self:inserted(block))
    end
  end
  return lines
end

function LineDiff:ifdef(macro)
  local lines = {}
  for _, step in ipairs(walk(self.blocks, 0, 0, #self.old)) do
    local block = step.block
    if not block then
      lines[#lines + 1] = self.old[step.old_line]
    elseif block.x >= 1 and block.y >= 1 then
      lines[#lines + 1] = "#ifndef " .. macro
      extend(lines, self:deleted(block))
      lines[#lines + 1] = "#else /* " .. macro .. " */"
      extend(lines, self:inserted(block))
      lines[#lines + 1] = "#endif /* " .. macro .. " */"
    elseif block.y == 0 then
      lines[#lines + 1] = "#ifndef " .. macro
      extend(lines, self:deleted(block))
      lines[#lines + 1] = "#endif /* ! " .. macro .. " */"
    else
      lines[#lines + 1] = "#ifdef " .. macro
      extend(lines, self:inserted(block))
      lines[#lines + 1] = "#endif /* " .. macro .. " */"
    end
  end
  return lines
end

function LineDiff:unified(context, old_name, new_name)
  local lines = { "--- " .. old_name, "+++ " .. new_name }
  for _, hunk in ipairs(self:hunks(context)) do
    local old_range = range_u(hunk.old_start, hunk.old_count)
    local new_range = range_u(hunk.new_start, hunk.new_count)
    lines[#lines + 1] = "@@ -" .. old_range .. " +" .. new_range .. " @@"
    for _, step in ipairs(hunk:steps()) do
      if step.block then
        add_prefixed(lines, "-", self:deleted(step.block))
        add_prefixed(lines, "+", self:inserted(step.block))
      else
        lines[#lines + 1] = " " .. self.old[step.old_line]
      end
    end
  end
  return lines
end

function LineDiff:context(context, old_name, new_name)
  local lines = { "*** " .. old_name, "--- " .. new_name }
  for _, hunk in ipairs(self:hunks(context)) do
    local has_deleted, has_inserted = false, false
    for _, block in ipairs(hunk.blocks) do
      has_deleted = has_deleted or block.x >= 1
      has_inserted = has_inserted or block.y >= 1
    end
    lines[#lines + 1] = string.rep("*", 15)
    lines[#lines + 1] = "*** " .. range_r(hunk.old_start, hunk.old_count) .. " ****"
    if has_deleted then
      for _, step in ipairs(hunk:steps()) do
        local block = step.block
        if block then
          add_prefixed(lines, block.y >= 1 and "! " or "- ", self:deleted(block))
        else
          lines[#lines + 1] = "  " .. self.old[step.old_line]
        end
      end
    end
    lines[#lines + 1] = "--- " .. range_r(hunk.new_start, hunk.new_count) .. " ----"
    if has_inserted then
      for _, step in ipairs(hunk:steps()) do
        local block = step.block
        if block then
          add_prefixed(lines, block.x >= 1 and "! " or "+ ", self:inserted(block))
        else
          lines[#lines + 1] = "  " .. self.new[step.new_line]
        end
      end
    end
  end
  return lines
end

function LineDiff:side_by_side(width)
  local lines = {}
  for _, step in ipairs(walk(self.blocks, 0, 0, #self.old)) do
    local block = step.block
    if not block then
      lines[#lines + 1] = side_row(self.old[step.old_line], " ", self.new[step.new_line], width)
    else
      for row = 1, math.max(block.x, block.y) do
        local left, symbol, right
        if row <= block.x and row <= block.y then
          left, symbol, right = self.old[block.p + row], "|", self.new[block.q + row]
        elseif row <= block.x then
          left, symbol, right = self.old[block.p + row], "<", ""
        else
          left, symbol, right = "", ">", self.new[block.q + row]
        end
        lines[#lines + 1] = side_row(left, symbol, right, width)
      end
    end
  end
  return lines
end

local function split_tokens(line, by_word)
  local tokens = {}
  for token in line:gmatch(by_word and "%S+" or ".") do
    tokens[#tokens + 1] = token
  end
  return tokens
end

local function deletion(tokens, separator)
  return "[-" .. table.concat(tokens, separator) .. "-]"
end

local function insertion(tokens, separator)
  return "{+" .. table.concat(tokens, separator) .. "+}"
end

local function compare_tokens(old_tokens, new_tokens, separator, totals)
  local parts = {}
  local blocks = change_blocks(old_tokens, new_tokens)
  for _, step in ipairs(walk(blocks, 0, 0, #old_tokens)) do
    local block = step.block
    if not block then
      parts[#parts + 1] = old_tokens[step.old_line]
      totals.common = totals.common + 1
    else
      if block.x >= 1 then
        parts[#parts + 1] = deletion(slice(old_tokens, block.p + 1, block.p + block.x), separator)
      end
      if block.y >= 1 then
        parts[#parts + 1] = insertion(slice(new_tokens, block.q + 1, block.q + block.y), separator)
      end
      totals.deleted = totals.deleted + block.x
      totals.inserted = totals.inserted + block.y
    end
  end
  return table.concat(parts, separator)
end

local PatchHunk = {}
PatchHunk.__index = PatchHunk

function PatchHunk.new(line_number, old_start, old_count, new_start, new_count)
  return setmetatable({
    line_number = line_number,
    old_start = old_start,
    old_count = old_count,
    new_start = new_start,
    new_count = new_count,
    body = {},
  }, PatchHunk)
end

function PatchHunk:sequences(reverse)
  local old_kind = reverse and "+" or "-"
  local new_kind = reverse and "-" or "+"
  local old, new = {}, {}
  for _, entry in ipairs(self.body) do
    if entry.kind == " " or entry.kind == old_kind then
      old[#old + 1] = entry.text
    end
    if entry.kind == " " or entry.kind == new_kind then
      new[#new + 1] = entry.text
    end
  end
  return old, new
end

function PatchHunk:start(reverse)
  return reverse and self.new_start or self.old_start
end

function PatchHunk:leading_context()
  local count = 0
  while count < #self.body and self.body[count + 1].kind == " " do
    count = count + 1
  end
  return count
end

function PatchHunk:trailing_context()
  local count = 0
  while count < #self.body and self.body[#self.body - count].kind == " " do
    count = count + 1
  end
  return count
end

local HunkMatch = {}
HunkMatch.__index = HunkMatch

function HunkMatch.new(fuzz, delta, position, lines)
  return setmetatable({ fuzz = fuzz, delta = delta, position = position, lines = lines }, HunkMatch)
end

function HunkMatch:report(number)
  local text = "Hunk #" .. number .. " succeeded at " .. (self.position + 1)
  if self.fuzz >= 1 then
    text = text .. " with fuzz " .. self.fuzz
  end
  if self.delta == 1 or self.delta == -1 then
    text = text .. " (offset " .. self.delta .. " line)"
  elseif self.delta ~= 0 then
    text = text .. " (offset " .. self.delta .. " lines)"
  end
  return text
end

local function parse_range(text, sign)
  if text:sub(1, 1) ~= sign then
    return nil
  end
  local start, count = parse_number_pair(text:sub(2))
  if not start then
    return nil
  end
  count = count or 1
  if start == 0 and count ~= 0 then
    return nil
  end
  return start, count
end

local function parse_hunk_header(line, line_number)
  local parts = split(line, " ")
  local old_start, old_count, new_start, new_count
  if #parts == 4 and parts[1] == "@@" and parts[4] == "@@" then
    old_start, old_count = parse_range(parts[2], "-")
    new_start, new_count = parse_range(parts[3], "+")
  end
  if not old_start or not new_start then
    fail("PATCH ERROR line " .. line_number .. ": bad hunk header")
  end
  return PatchHunk.new(line_number, old_start, old_count, new_start, new_count)
end

local function parse_patch(patch_lines)
  local index = 1
  while index <= #patch_lines and patch_lines[index]:sub(1, 2) ~= "@@" do
    index = index + 1
  end
  if index > #patch_lines then
    fail("PATCH ERROR no hunks")
  end
  local hunks = {}
  while index <= #patch_lines do
    local hunk = parse_hunk_header(patch_lines[index], index)
    index = index + 1
    local old_seen, new_seen = 0, 0
    while old_seen < hunk.old_count or new_seen < hunk.new_count do
      if index > #patch_lines then
        fail("PATCH ERROR line " .. hunk.line_number .. ": truncated hunk")
      end
      local line = patch_lines[index]
      local kind = line:sub(1, 1)
      local in_old = kind == " " or kind == "-"
      local in_new = kind == " " or kind == "+"
      if
        #line < 2
        or not (in_old or in_new)
        or (in_old and old_seen == hunk.old_count)
        or (in_new and new_seen == hunk.new_count)
      then
        fail("PATCH ERROR line " .. index .. ": bad hunk line")
      end
      hunk.body[#hunk.body + 1] = { kind = kind, text = line:sub(2) }
      if in_old then
        old_seen = old_seen + 1
      end
      if in_new then
        new_seen = new_seen + 1
      end
      index = index + 1
    end
    local has_changes = false
    for _, entry in ipairs(hunk.body) do
      has_changes = has_changes or entry.kind ~= " "
    end
    if not has_changes then
      fail("PATCH ERROR line " .. hunk.line_number .. ": no changes")
    end
    hunks[#hunks + 1] = hunk
  end
  return hunks
end

local function search_hunk(hunk, lines, adjustment, reverse, max_fuzz)
  local old, new = hunk:sequences(reverse)
  local start = hunk:start(reverse)
  local expected = #old > 0 and start - 1 + adjustment or start + adjustment
  local leading, trailing = hunk:leading_context(), hunk:trailing_context()
  for fuzz = 0, max_fuzz do
    local head, tail = math.min(fuzz, leading), math.min(fuzz, trailing)
    local old_part = slice(old, head + 1, #old - tail)
    local new_part = slice(new, head + 1, #new - tail)
    for _, delta in ipairs(OFFSETS) do
      local position = expected + head + delta
      local finish = position + #old_part
      if position >= 0 and finish <= #lines then
        if lists_equal(slice(lines, position + 1, finish), old_part) then
          local result = extend(extend(slice(lines, 1, position), new_part), slice(lines, finish + 1))
          return HunkMatch.new(fuzz, delta, position, result)
        end
      end
    end
  end
  return nil
end

local function parse_edit_command(line)
  local instruction, address = line:sub(-1), line:sub(1, -2)
  local first, last = parse_number_pair(address)
  if not contains({ "a", "c", "d" }, instruction) or not first then
    return nil
  end
  if instruction == "a" and last then
    return nil
  end
  return instruction, first, last or first
end

local function run_edit_script(original, script)
  local lines = slice(original, 1)
  local executed = 0
  local index = 1
  while index <= #script do
    local line_number = index
    local instruction, first, last = parse_edit_command(script[index])
    if not instruction then
      fail("EDIT ERROR line " .. line_number .. ": bad command")
    end
    local valid
    if instruction == "a" then
      valid = first <= #lines
    else
      valid = 1 <= first and first <= last and last <= #lines
    end
    if not valid then
      fail("EDIT ERROR line " .. line_number .. ": bad range")
    end
    index = index + 1
    local text = {}
    if instruction ~= "d" then
      local stop = index
      while stop <= #script and script[stop] ~= "." do
        stop = stop + 1
      end
      if stop > #script then
        fail("EDIT ERROR line " .. line_number .. ": missing terminator")
      end
      text = slice(script, index, stop - 1)
      index = stop + 1
    end
    if instruction == "a" then
      lines = extend(extend(slice(lines, 1, first), text), slice(lines, first + 1))
    else
      lines = extend(extend(slice(lines, 1, first - 1), text), slice(lines, last + 1))
    end
    executed = executed + 1
  end
  return lines, executed
end

local Chunk = {}
Chunk.__index = Chunk

function Chunk.new(kind, base_start, ours_start, theirs_start, base, ours, theirs)
  return setmetatable({
    kind = kind,
    base_start = base_start,
    ours_start = ours_start,
    theirs_start = theirs_start,
    base = base,
    ours = ours,
    theirs = theirs,
  }, Chunk)
end

function Chunk:location()
  return string.format(
    "base %s a %s b %s",
    range_m(self.base_start, #self.base),
    range_m(self.ours_start, #self.ours),
    range_m(self.theirs_start, #self.theirs)
  )
end

local function chunk_kind(base, ours, theirs)
  if lists_equal(ours, base) then
    return "b"
  elseif lists_equal(theirs, base) then
    return "a"
  elseif lists_equal(ours, theirs) then
    return "both"
  end
  return "conflict"
end

local function match_table(first, second)
  local matches = {}
  for index = 1, #first do
    matches[index] = 0
  end
  local matched = matched_pairs(first, second)
  for index = 2, #matched - 1 do
    local i, j = table.unpack(matched[index])
    matches[i] = j
  end
  return matches
end

local function three_way_chunks(base, ours, theirs)
  local ours_match = match_table(base, ours)
  local theirs_match = match_table(base, theirs)
  local chunks = {}
  local x, y, z = 0, 0, 0
  while x < #base or y < #ours or z < #theirs do
    if x < #base and ours_match[x + 1] == y + 1 and theirs_match[x + 1] == z + 1 then
      chunks[#chunks + 1] =
        Chunk.new("stable", x, y, z, { base[x + 1] }, { ours[y + 1] }, { theirs[z + 1] })
      x, y, z = x + 1, y + 1, z + 1
    else
      local anchor = x + 1
      while anchor <= #base and (ours_match[anchor] == 0 or theirs_match[anchor] == 0) do
        anchor = anchor + 1
      end
      local next_x, next_y, next_z
      if anchor <= #base then
        next_x, next_y, next_z = anchor - 1, ours_match[anchor] - 1, theirs_match[anchor] - 1
      else
        next_x, next_y, next_z = #base, #ours, #theirs
      end
      local base_part = slice(base, x + 1, next_x)
      local ours_part = slice(ours, y + 1, next_y)
      local theirs_part = slice(theirs, z + 1, next_z)
      local kind = chunk_kind(base_part, ours_part, theirs_part)
      chunks[#chunks + 1] = Chunk.new(kind, x, y, z, base_part, ours_part, theirs_part)
      x, y, z = next_x, next_y, next_z
    end
  end
  return chunks
end

local function kind_counts(chunks)
  local counts = { a = 0, b = 0, both = 0, conflict = 0 }
  for _, chunk in ipairs(chunks) do
    if chunk.kind ~= "stable" then
      counts[chunk.kind] = counts[chunk.kind] + 1
    end
  end
  return string.format(
    "a=%d b=%d both=%d conflicts=%d",
    counts.a,
    counts.b,
    counts.both,
    counts.conflict
  )
end

local function common_prefix_length(first, second)
  local length = 0
  while length < #first and length < #second and first[length + 1] == second[length + 1] do
    length = length + 1
  end
  return length
end

local function common_suffix_length(first, second, limit)
  local length = 0
  while length < limit and first[#first - length] == second[#second - length] do
    length = length + 1
  end
  return length
end

local function conflict_lines(chunk, mode, base_name, ours_name, theirs_name)
  if mode == "OURS" then
    return chunk.ours
  elseif mode == "THEIRS" then
    return chunk.theirs
  elseif mode == "DIFF3" then
    local lines = { "<<<<<<< " .. ours_name }
    extend(lines, chunk.ours)
    lines[#lines + 1] = "||||||| " .. base_name
    extend(lines, chunk.base)
    lines[#lines + 1] = SEPARATOR
    extend(lines, chunk.theirs)
    lines[#lines + 1] = ">>>>>>> " .. theirs_name
    return lines
  end
  local ours, theirs = chunk.ours, chunk.theirs
  local head = common_prefix_length(ours, theirs)
  local tail = common_suffix_length(ours, theirs, math.min(#ours, #theirs) - head)
  local ours_middle = slice(ours, head + 1, #ours - tail)
  local theirs_middle = slice(theirs, head + 1, #theirs - tail)
  local lines = slice(ours, 1, head)
  if mode == "UNION" then
    extend(lines, ours_middle)
    extend(lines, theirs_middle)
  else
    lines[#lines + 1] = "<<<<<<< " .. ours_name
    extend(lines, ours_middle)
    lines[#lines + 1] = SEPARATOR
    extend(lines, theirs_middle)
    lines[#lines + 1] = ">>>>>>> " .. theirs_name
  end
  return extend(lines, slice(ours, #ours - tail + 1))
end

local function marker_kind(line)
  if line == SEPARATOR then
    return "separator"
  end
  local kind = MARKER_PREFIXES[line:sub(1, 7)]
  if kind and (#line == 7 or line:sub(8, 8) == " ") then
    return kind
  end
  return nil
end

local function next_marker(lines, index)
  index = index + 1
  while index <= #lines and not marker_kind(lines[index]) do
    index = index + 1
  end
  return index
end

local ConflictRegion = {}
ConflictRegion.__index = ConflictRegion

function ConflictRegion.new(start_line, end_line, ours, base, theirs)
  return setmetatable({
    start_line = start_line,
    end_line = end_line,
    ours = ours,
    base = base,
    theirs = theirs,
  }, ConflictRegion)
end

function ConflictRegion:part(side)
  if side == "OURS" then
    return self.ours
  elseif side == "THEIRS" then
    return self.theirs
  elseif side == "BASE" then
    return self.base
  end
  return extend(slice(self.ours, 1), self.theirs)
end

local function region_at(lines, start)
  if marker_kind(lines[start]) ~= "start" then
    return nil
  end
  local middle = next_marker(lines, start)
  local base_marker
  if middle <= #lines and marker_kind(lines[middle]) == "base" then
    base_marker = middle
    middle = next_marker(lines, middle)
  end
  if middle > #lines or marker_kind(lines[middle]) ~= "separator" then
    return nil
  end
  local finish = next_marker(lines, middle)
  if finish > #lines or marker_kind(lines[finish]) ~= "end" then
    return nil
  end
  local ours, base
  if base_marker then
    ours = slice(lines, start + 1, base_marker - 1)
    base = slice(lines, base_marker + 1, middle - 1)
  else
    ours = slice(lines, start + 1, middle - 1)
  end
  return ConflictRegion.new(start, finish, ours, base, slice(lines, middle + 1, finish - 1))
end

local function conflict_regions(lines)
  local regions = {}
  local index = 1
  while index <= #lines do
    local region = region_at(lines, index)
    if region then
      regions[#regions + 1] = region
      index = region.end_line + 1
    else
      index = index + 1
    end
  end
  return regions
end

local Workspace = {}
Workspace.__index = Workspace

function Workspace.new()
  return setmetatable({ files = {}, history = {}, output = {} }, Workspace)
end

function Workspace:emit(line)
  self.output[#self.output + 1] = line
end

function Workspace:require_files(...)
  for _, name in ipairs({ ... }) do
    if not self.files[name] then
      fail("ERROR no such file " .. name)
    end
  end
end

function Workspace:save(name, lines)
  local states = self.history[name] or {}
  self.history[name] = states
  states[#states + 1] = self.files[name] or false
  self.files[name] = slice(lines, 1)
end

function Workspace:load_file(arguments, data)
  local name = arguments[1]
  self:save(name, data)
  self:emit("FILE " .. name .. " lines=" .. #data)
end

function Workspace:copy(arguments)
  local source, target = arguments[1], arguments[2]
  self:require_files(source)
  local lines = self.files[source]
  self:save(target, lines)
  self:emit(string.format("COPY %s %s lines=%d", source, target, #lines))
end

function Workspace:print_file(arguments)
  local name = arguments[1]
  self:require_files(name)
  local lines = self.files[name]
  self:emit("PRINT " .. name .. " lines=" .. #lines)
  for number, line in ipairs(lines) do
    self:emit(string.format("%3d| %s", number, line))
  end
end

function Workspace:list_files()
  local names = {}
  for name in pairs(self.files) do
    names[#names + 1] = name
  end
  table.sort(names)
  self:emit("FILES count=" .. #names)
  for _, name in ipairs(names) do
    self:emit(string.format("%s lines=%d undo=%d", name, #self.files[name], #self.history[name]))
  end
end

function Workspace:undo(arguments)
  local name = arguments[1]
  local states = self.history[name] or {}
  if #states == 0 then
    fail("ERROR nothing to undo " .. name)
  end
  local state = table.remove(states)
  if state then
    self.files[name] = state
    self:emit("UNDO " .. name .. " lines=" .. #state)
  else
    self.files[name] = nil
    self:emit("UNDO " .. name .. " removed")
  end
end

function Workspace:diff(arguments)
  local old_name, new_name, form = arguments[1], arguments[2], arguments[3]
  self:require_files(old_name, new_name)
  local parameter
  local options = slice(arguments, 4)
  if contains(FORMATS_WITH_ARGUMENT, form) then
    parameter = arguments[4]
    options = slice(arguments, 5)
  end
  local diff = LineDiff.new(self.files[old_name], self.files[new_name], options)
  if #diff.blocks == 0 then
    self:emit(string.format("Files %s and %s are identical", old_name, new_name))
  elseif form == "BRIEF" then
    self:emit(string.format("Files %s and %s differ", old_name, new_name))
  elseif form == "NORMAL" then
    extend(self.output, diff:normal())
  elseif form == "ED" then
    extend(self.output, diff:ed())
  elseif form == "RCS" then
    extend(self.output, diff:rcs())
  elseif form == "IFDEF" then
    extend(self.output, diff:ifdef(parameter))
  elseif form == "UNIFIED" then
    extend(self.output, diff:unified(tonumber(parameter), old_name, new_name))
  elseif form == "CONTEXT" then
    extend(self.output, diff:context(tonumber(parameter), old_name, new_name))
  else
    extend(self.output, diff:side_by_side(tonumber(parameter)))
  end
end

function Workspace:token_diff(arguments, by_word)
  local old_name, new_name = arguments[1], arguments[2]
  self:require_files(old_name, new_name)
  local old, new = self.files[old_name], self.files[new_name]
  local diff = LineDiff.new(old, new)
  if #diff.blocks == 0 then
    self:emit(string.format("Files %s and %s are identical", old_name, new_name))
    return
  end
  local separator = by_word and " " or ""
  local totals = { deleted = 0, inserted = 0, common = 0 }
  for _, block in ipairs(diff.blocks) do
    for row = 1, math.max(block.x, block.y) do
      local old_number, new_number = block.p + row, block.q + row
      if row <= block.x and row <= block.y then
        local old_tokens = split_tokens(old[old_number], by_word)
        local new_tokens = split_tokens(new[new_number], by_word)
        local text = compare_tokens(old_tokens, new_tokens, separator, totals)
        self:emit(string.format("a%d b%d: %s", old_number, new_number, text))
      elseif row <= block.x then
        local old_tokens = split_tokens(old[old_number], by_word)
        totals.deleted = totals.deleted + #old_tokens
        self:emit(string.format("a%d: %s", old_number, deletion(old_tokens, separator)))
      else
        local new_tokens = split_tokens(new[new_number], by_word)
        totals.inserted = totals.inserted + #new_tokens
        self:emit(string.format("b%d: %s", new_number, insertion(new_tokens, separator)))
      end
    end
  end
  self:emit(string.format(
    "%s deleted=%d inserted=%d common=%d",
    by_word and "WORDS" or "CHARS",
    totals.deleted,
    totals.inserted,
    totals.common
  ))
end

function Workspace:word_diff(arguments)
  self:token_diff(arguments, true)
end

function Workspace:char_diff(arguments)
  self:token_diff(arguments, false)
end

function Workspace:stat(arguments)
  local old_name, new_name = arguments[1], arguments[2]
  self:require_files(old_name, new_name)
  local old, new = self.files[old_name], self.files[new_name]
  local diff = LineDiff.new(old, new, slice(arguments, 3))
  local deleted, inserted = 0, 0
  for _, block in ipairs(diff.blocks) do
    deleted = deleted + block.x
    inserted = inserted + block.y
  end
  local total = deleted + inserted
  local unchanged = #old - deleted
  local summary = string.format("%s -> %s | %d", old_name, new_name, total)
  if total > 0 then
    summary = summary .. " " .. stat_graph(inserted, deleted)
  end
  self:emit(summary)
  local line_total = #old + #new
  local similarity = line_total > 0 and 200 * unchanged // line_total or 100
  self:emit(string.format(
    "changes=%d insertions=%d deletions=%d unchanged=%d similarity=%d%%",
    #diff.blocks,
    inserted,
    deleted,
    unchanged,
    similarity
  ))
end

function Workspace:patch(arguments, data)
  local name = arguments[1]
  self:require_files(name)
  local options = slice(arguments, 3)
  local reverse = contains(options, "REVERSE")
  local dry_run = contains(options, "DRYRUN")
  local max_fuzz = 0
  for index, option in ipairs(options) do
    if option == "FUZZ" then
      max_fuzz = tonumber(options[index + 1])
    end
  end
  local hunks = parse_patch(data)
  self:emit((dry_run and "checking file " or "patching file ") .. name)
  local lines = self.files[name]
  local first = hunks[1]
  if
    not search_hunk(first, lines, 0, reverse, max_fuzz)
    and search_hunk(first, lines, 0, not reverse, max_fuzz)
  then
    self:emit("Reversed (or previously applied) patch detected! Skipping patch.")
    self:emit(string.format("RESULT applied=0 failed=0 ignored=%d lines=%d", #hunks, #lines))
    return
  end
  local adjustment = 0
  local applied, failed = 0, 0
  for number, hunk in ipairs(hunks) do
    local match = search_hunk(hunk, lines, adjustment, reverse, max_fuzz)
    if match then
      local old, new = hunk:sequences(reverse)
      lines = match.lines
      adjustment = adjustment + match.delta + #new - #old
      applied = applied + 1
      self:emit(match:report(number))
    else
      failed = failed + 1
      self:emit("Hunk #" .. number .. " FAILED at " .. hunk:start(reverse))
    end
  end
  self:emit(string.format("RESULT applied=%d failed=%d ignored=0 lines=%d", applied, failed, #lines))
  if not dry_run and applied >= 1 then
    self:save(name, lines)
  end
end

function Workspace:edit(arguments, data)
  local name = arguments[1]
  self:require_files(name)
  local lines, executed = run_edit_script(self.files[name], data)
  self:emit(string.format("EDIT %s commands=%d lines=%d", name, executed, #lines))
  self:save(name, lines)
end

function Workspace:three_way(base_name, ours_name, theirs_name)
  self:require_files(base_name, ours_name, theirs_name)
  return three_way_chunks(self.files[base_name], self.files[ours_name], self.files[theirs_name])
end

function Workspace:diff3(arguments)
  local chunks = self:three_way(arguments[1], arguments[2], arguments[3])
  local changes = 0
  for _, chunk in ipairs(chunks) do
    if chunk.kind ~= "stable" then
      changes = changes + 1
      self:emit("==== " .. chunk.kind .. " " .. chunk:location())
      add_prefixed(self.output, "O ", chunk.base)
      if chunk.kind ~= "b" then
        add_prefixed(self.output, "A ", chunk.ours)
      end
      if chunk.kind == "b" or chunk.kind == "conflict" then
        add_prefixed(self.output, "B ", chunk.theirs)
      end
    end
  end
  self:emit(string.format("DIFF3 chunks=%d %s", changes, kind_counts(chunks)))
end

function Workspace:merge(arguments)
  local base_name, ours_name, theirs_name, target = table.unpack(arguments, 1, 4)
  local mode = arguments[5] or "MARKERS"
  local chunks = self:three_way(base_name, ours_name, theirs_name)
  local result, conflicts = {}, {}
  for _, chunk in ipairs(chunks) do
    if chunk.kind == "b" then
      extend(result, chunk.theirs)
    elseif chunk.kind == "conflict" then
      extend(result, conflict_lines(chunk, mode, base_name, ours_name, theirs_name))
      conflicts[#conflicts + 1] = chunk
    else
      extend(result, chunk.ours)
    end
  end
  self:emit(string.format("MERGE %s lines=%d %s", target, #result, kind_counts(chunks)))
  for number, chunk in ipairs(conflicts) do
    self:emit(string.format("CONFLICT %d %s", number, chunk:location()))
  end
  self:save(target, result)
end

function Workspace:conflicts(arguments)
  local name = arguments[1]
  self:require_files(name)
  local regions = conflict_regions(self.files[name])
  self:emit("CONFLICTS " .. name .. " count=" .. #regions)
  for number, region in ipairs(regions) do
    local base = region.base and #region.base or "none"
    self:emit(string.format(
      "%d: lines %d-%d ours=%d base=%s theirs=%d",
      number,
      region.start_line,
      region.end_line,
      #region.ours,
      base,
      #region.theirs
    ))
  end
end

function Workspace:resolve(arguments)
  local name, number_text, side = arguments[1], arguments[2], arguments[3]
  self:require_files(name)
  local number = tonumber(number_text)
  local lines = self.files[name]
  local regions = conflict_regions(lines)
  if #regions < number then
    fail(string.format("ERROR no conflict %d in %s", number, name))
  end
  local region = regions[number]
  if side == "BASE" and not region.base then
    fail("ERROR no base section in conflict " .. number)
  end
  local content = slice(lines, 1, region.start_line - 1)
  extend(content, region:part(side))
  extend(content, slice(lines, region.end_line + 1))
  local remaining = #conflict_regions(content)
  self:emit(string.format(
    "RESOLVE %s %d %s lines=%d remaining=%d",
    name,
    number,
    side,
    #content,
    remaining
  ))
  self:save(name, content)
end

local HANDLERS = {
  FILE = Workspace.load_file,
  COPY = Workspace.copy,
  PRINT = Workspace.print_file,
  FILES = Workspace.list_files,
  DIFF = Workspace.diff,
  WORDDIFF = Workspace.word_diff,
  CHARDIFF = Workspace.char_diff,
  STAT = Workspace.stat,
  PATCH = Workspace.patch,
  EDIT = Workspace.edit,
  DIFF3 = Workspace.diff3,
  MERGE = Workspace.merge,
  CONFLICTS = Workspace.conflicts,
  RESOLVE = Workspace.resolve,
  UNDO = Workspace.undo,
}

function Workspace:execute(words, data)
  local ok, err = pcall(HANDLERS[words[1]], self, slice(words, 2), data)
  if not ok then
    if type(err) ~= "table" then
      error(err, 0)
    end
    self:emit(err.message)
  end
end

local function main()
  local lines = {}
  for line in io.lines() do
    lines[#lines + 1] = line
  end
  local workspace = Workspace.new()
  local position = 2
  for _ = 1, tonumber(lines[1]) do
    local words = split(lines[position], " ")
    position = position + 1
    local data = {}
    if contains(DATA_COMMANDS, words[1]) then
      local count = tonumber(words[3])
      data = slice(lines, position, position + count - 1)
      position = position + count
    end
    workspace:execute(words, data)
  end
  io.write(table.concat(workspace.output, "\n"), "\n")
end

main()
