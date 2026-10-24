local WHITESPACE = " \n"
local PUNCTUATION = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
local TOC_MARKER = "\0toc\0"
local HTML_ESCAPES = { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;" }
local ALERT_TYPES = { NOTE = true, TIP = true, IMPORTANT = true, WARNING = true, CAUTION = true }

local function starts(text, prefix, at)
  at = at or 1
  return text:sub(at, at + #prefix - 1) == prefix
end

local function contains(text, character)
  return character ~= "" and text:find(character, 1, true) ~= nil
end

local function trim(text)
  return (text:gsub("^ +", ""):gsub(" +$", ""))
end

local function escape(text)
  return (text:gsub('[&<>"]', HTML_ESCAPES))
end

local function strip_tags(text)
  return (text:gsub("<[^>]*>", ""))
end

local function normalize(text)
  return (text:lower():gsub("[ \n]+", " "):gsub("^ ", ""):gsub(" $", ""))
end

local function skip_space(text, at)
  while at <= #text and contains(WHITESPACE, text:sub(at, at)) do at = at + 1 end
  return at
end

local function escaped_read(text, at, stops)
  local parts = {}
  while at <= #text and not contains(stops, text:sub(at, at)) do
    if text:sub(at, at) == "\\" and contains(PUNCTUATION, text:sub(at + 1, at + 1)) then at = at + 1 end
    parts[#parts + 1] = text:sub(at, at)
    at = at + 1
  end
  return table.concat(parts), at
end

local function run_end(text, at)
  local stop = at + 1
  while stop <= #text and text:sub(stop, stop) == text:sub(at, at) do stop = stop + 1 end
  return stop
end

local function backtick_closer(text, at, length)
  while at <= #text do
    at = text:find("`", at, true)
    if not at then return nil end
    local stop = run_end(text, at)
    if stop - at == length then return at end
    at = stop
  end
end

local function closing_bracket(text, at)
  local depth = 0
  while at <= #text do
    local character = text:sub(at, at)
    if character == "\\" then at = at + 2
    elseif character == "`" then
      local stop = run_end(text, at)
      local close = backtick_closer(text, stop, stop - at)
      at = close and close + stop - at or stop
    else
      if character == "[" then depth = depth + 1
      elseif character == "]" then
        depth = depth - 1
        if depth == 0 then return at end
      end
      at = at + 1
    end
  end
end

local function opening_fence(line)
  if not contains("`~", line:sub(1, 1)) then return nil end
  local stop = run_end(line, 1)
  if stop < 4 then return nil end
  local info = trim(line:sub(stop))
  if line:sub(1, 1) == "`" and contains(info, "`") then return nil end
  return line:sub(1, stop - 1), info
end

local function atx_heading(line)
  local hashes = line:match("^(#+)")
  if not hashes or #hashes > 6 or (#line > #hashes and line:sub(#hashes + 1, #hashes + 1) ~= " ") then return nil end
  local text = trim(line:sub(#hashes + 1))
  local stripped = text:gsub("#+$", "")
  if stripped == "" or stripped:sub(-1) == " " then text = trim(stripped) end
  return { kind = "heading", number = #hashes, text = text }
end

local function is_rule(line)
  local compact = line:gsub(" ", "")
  return #compact >= 3 and contains("-*_", compact:sub(1, 1))
    and compact == compact:sub(1, 1):rep(#compact)
end

local function list_marker(line)
  if is_rule(line) then return nil end
  local marker, spaces, content = line:match("^([%-%*+])( +)(.*)$")
  if marker then return { marker = marker, ordered = false, number = 1, content = content } end
  local digits
  digits, marker, spaces, content = line:match("^(%d+)([%.%)])( +)(.*)$")
  if digits and #digits <= 9 then
    return { marker = marker, ordered = true, number = tonumber(digits), content = content }
  end
end

local function interrupts(line)
  if line == "" or starts(line, " ") then return false end
  return opening_fence(line) ~= nil or atx_heading(line) ~= nil or is_rule(line)
    or starts(line, ">") or list_marker(line) ~= nil
end

local function split_cells(line)
  local text = trim(line)
  if starts(text, "|") then text = text:sub(2) end
  local cells, parts, at, final_separator = {}, {}, 1, false
  while at <= #text do
    local character = text:sub(at, at)
    final_separator = false
    if character == "\\" and at < #text then
      local following = text:sub(at + 1, at + 1)
      parts[#parts + 1] = following == "|" and "|" or "\\" .. following
      at = at + 2
    elseif character == "|" then
      cells[#cells + 1] = trim(table.concat(parts))
      parts, final_separator, at = {}, true, at + 1
    else parts[#parts + 1], at = character, at + 1 end
  end
  if not final_separator then cells[#cells + 1] = trim(table.concat(parts)) end
  return cells
end

local Parser = {}
Parser.__index = Parser

function Parser:definition(line)
  local name, body = line:match("^%[%^([A-Za-z0-9_-]+)%]:(.*)$")
  if name and trim(body) ~= "" then
    name = name:lower()
    if self.footnotes[name] == nil then self.footnotes[name] = trim(body) end
    return true
  end
  if not starts(line, "[") then return false end
  local close = line:find("]", 1, true)
  if not close or line:sub(close + 1, close + 1) ~= ":" then return false end
  local label = line:sub(2, close - 1)
  if contains(label, "[") or trim(label) == "" or starts(label, "^") then return false end
  local url, stop = escaped_read(line, skip_space(line, close + 2), " ")
  if url == "" then return false end
  local at, title = skip_space(line, stop), nil
  if at <= #line then
    local quote = line:sub(at, at)
    if at == stop or not contains("\"'", quote) then return false end
    local finish
    title, finish = escaped_read(line, at + 1, quote)
    if finish ~= #line then return false end
  end
  name = normalize(label)
  if self.references[name] == nil then self.references[name] = { url = url, title = title } end
  return true
end

function Parser:parse(lines)
  local blocks, at = {}, 1
  while at <= #lines do
    local line, block = lines[at], nil
    if line == "" then at = at + 1
    elseif starts(line, "    ") then
      local stop = at
      while stop <= #lines and (lines[stop] == "" or starts(lines[stop], "    ")) do stop = stop + 1 end
      while lines[stop - 1] == "" do stop = stop - 1 end
      block = { kind = "code", text = "", lines = {} }
      while at < stop do
        block.lines[#block.lines + 1] = lines[at] == "" and "" or lines[at]:sub(5)
        at = at + 1
      end
    else
      if not starts(line, " ") then
        local fence, info = opening_fence(line)
        local heading = atx_heading(line)
        local marker = list_marker(line)
        if fence then
          block = { kind = "code", text = info:match("^[^ ]*") or "", lines = {} }
          at = at + 1
          while at <= #lines do
            local row = lines[at]
            at = at + 1
            if #row >= #fence and row == fence:sub(1, 1):rep(#row) then break end
            block.lines[#block.lines + 1] = row
          end
        elseif heading then block, at = heading, at + 1
        elseif is_rule(line) then block, at = { kind = "rule" }, at + 1
        elseif starts(line, ">") then
          local content = {}
          while at <= #lines and starts(lines[at], ">") do
            local row = lines[at]:sub(2)
            if starts(row, " ") then row = row:sub(2) end
            content[#content + 1], at = row, at + 1
          end
          block = { kind = "quote" }
          local alert = content[1]:match("^%[!(%u+)%]$")
          if ALERT_TYPES[alert] then block.kind, block.text = "alert", alert; table.remove(content, 1) end
          block.children = self:parse(content)
        elseif marker then
          block = { kind = "list", ordered = marker.ordered, number = marker.number, items = {} }
          local kind = marker.marker
          while true do
            local content = { marker.content }
            at = at + 1
            while at <= #lines and starts(lines[at], "  ") do content[#content + 1], at = lines[at]:sub(3), at + 1 end
            block.items[#block.items + 1] = self:parse(content)
            local following = at
            while following <= #lines and lines[following] == "" do following = following + 1 end
            marker = following <= #lines and list_marker(lines[following]) or nil
            if not marker or marker.marker ~= kind or marker.ordered ~= block.ordered then break end
            at = following
          end
        elseif self:definition(line) then at = at + 1; block = false
        elseif at < #lines and contains(line, "|") and contains(lines[at + 1], "|") then
          local header, delimiters = split_cells(line), split_cells(lines[at + 1])
          local valid = #header == #delimiters
          for _, cell in ipairs(delimiters) do if not cell:match("^:?-+:?$") then valid = false end end
          if valid then
            block = { kind = "table", lines = header, alignments = {}, rows = {} }
            for index, cell in ipairs(delimiters) do
              local left, right = starts(cell, ":"), cell:sub(-1) == ":"
              block.alignments[index] = left and (right and "center" or "left") or (right and "right" or "")
            end
            at = at + 2
            while at <= #lines and lines[at] ~= "" and contains(lines[at], "|") do
              local cells, row = split_cells(lines[at]), {}
              for index = 1, #delimiters do row[index] = cells[index] or "" end
              block.rows[#block.rows + 1], at = row, at + 1
            end
          end
        end
      end
      if block == nil then
        local text, level = { (line:gsub("^ +", "")) }, nil
        at = at + 1
        while at <= #lines and lines[at] ~= "" do
          local row = lines[at]
          if row:match("^===+$") or row:match("^%-%-%-+$") then
            level, at = starts(row, "=") and 1 or 2, at + 1
            break
          end
          if interrupts(row) then break end
          text[#text + 1], at = row:gsub("^ +", ""), at + 1
        end
        local combined = table.concat(text, "\n")
        block = { kind = level and "heading" or (combined == "[TOC]" and "toc" or "paragraph"), text = combined, number = level }
      end
    end
    if block then blocks[#blocks + 1] = block end
  end
  return blocks
end

local function emphasis(pieces, start, stop)
  local parts, at = {}, start
  while at <= stop do
    local piece = pieces[at]
    if type(piece) == "string" then parts[#parts + 1] = piece
    else
      local close
      if piece.open then
        for following = at + 1, stop do
          local other = pieces[following]
          if type(other) == "table" and other.character == piece.character and other.length == piece.length and other.close then close = following; break end
        end
      end
      if close then
        local opening, closing = "<del>", "</del>"
        if piece.character ~= "~" then
          if piece.length == 1 then opening, closing = "<em>", "</em>"
          elseif piece.length == 2 then opening, closing = "<strong>", "</strong>"
          else opening, closing = "<em><strong>", "</strong></em>" end
        end
        parts[#parts + 1] = opening .. emphasis(pieces, at + 1, close - 1) .. closing
        at = close
      else parts[#parts + 1] = piece.character:rep(piece.length) end
    end
    at = at + 1
  end
  return table.concat(parts)
end

local function email(text)
  local local_part, domain = text:match("^([^@]+)@([^@]+)$")
  if not local_part or not local_part:match("^[A-Za-z0-9%.+_-]+$") then return false end
  local parts = 0
  for part in (domain .. "."):gmatch("(.-)%.") do
    if not part:match("^[A-Za-z0-9-]+$") then return false end
    parts = parts + 1
  end
  return parts >= 2
end

local Renderer = {}
Renderer.__index = Renderer

function Renderer:destination(text, at, label)
  if text:sub(at, at) == "[" then
    local close = text:find("]", at + 1, true)
    if close then
      local key = text:sub(at + 1, close - 1)
      if not contains(key, "[") then
        local reference = self.references[normalize(key == "" and label or key)]
        if not reference then return nil end
        return reference, close + 1
      end
    end
  elseif text:sub(at, at) == "(" then
    local url, stop = escaped_read(text, skip_space(text, at + 1), " \n)")
    local following, title, valid = skip_space(text, stop), nil, true
    local quote = text:sub(following, following)
    if following > stop and contains("\"'", quote) then
      local finish
      title, finish = escaped_read(text, following + 1, quote)
      if finish > #text then valid = false else following = skip_space(text, finish + 1) end
    end
    if valid and text:sub(following, following) == ")" then return { url = url, title = title }, following + 1 end
  end
  local reference = self.references[normalize(label)]
  if reference then return reference, at end
end

local function reference_id(number, count)
  return "fnref-" .. number .. (count > 1 and "-" .. count or "")
end

function Renderer:footnote_reference(name)
  local number = self.footnote_numbers[name]
  if not number then
    number = #self.footnote_names + 1
    self.footnote_numbers[name], self.footnote_names[number], self.footnote_counts[number] = number, name, 0
  end
  self.footnote_counts[number] = self.footnote_counts[number] + 1
  return '<sup id="' .. reference_id(number, self.footnote_counts[number]) .. '"><a href="#fn-' .. number .. '">' .. number .. '</a></sup>'
end

function Renderer:bracket(text, at, links, notes)
  if links and notes and starts(text, "[^", at) then
    local close = text:find("]", at + 2, true)
    if close then
      local name = text:sub(at + 2, close - 1):lower()
      if self.footnotes[name] then return self:footnote_reference(name), close + 1 end
    end
  end
  local image = text:sub(at, at) == "!"
  if not image and not links then return nil end
  local opening = image and at + 1 or at
  local closing = closing_bracket(text, opening)
  if not closing then return nil end
  local label = text:sub(opening + 1, closing - 1)
  local reference, stop = self:destination(text, closing + 1, label)
  if not reference then return nil end
  local content = self:inline(label, false, false)
  local title = reference.title and ' title="' .. escape(reference.title) .. '"' or ""
  if image then return '<img src="' .. escape(reference.url) .. '" alt="' .. strip_tags(content) .. '"' .. title .. ' />', stop end
  return '<a href="' .. escape(reference.url) .. '"' .. title .. '>' .. content .. '</a>', stop
end

function Renderer:next_piece(text, at, links, notes)
  local character, following = text:sub(at, at), text:sub(at + 1, at + 1)
  if character == "\\" then
    if contains(PUNCTUATION, following) then return escape(following), at + 2 end
    if following == "\n" then return "<br />\n", at + 2 end
    return "\\", at + 1
  end
  if character == "`" then
    local stop = run_end(text, at)
    local close = backtick_closer(text, stop, stop - at)
    if not close then return text:sub(at, stop - 1), stop end
    local code = text:sub(stop, close - 1):gsub("\n", " ")
    if starts(code, " ") and code:sub(-1) == " " and code:find("[^ ]") then code = code:sub(2, -2) end
    return "<code>" .. escape(code) .. "</code>", close + stop - at
  end
  if links and character == "<" then
    local close = text:find(">", at + 1, true)
    if close then
      local target, href = text:sub(at + 1, close - 1), nil
      if not target:find("[ \n<]") and ((starts(target, "http://") and #target > 7) or (starts(target, "https://") and #target > 8)) then href = target
      elseif email(target) then href = "mailto:" .. target end
      if href then return '<a href="' .. escape(href) .. '">' .. escape(target) .. '</a>', close + 1 end
    end
  end
  if links and (starts(text, "http://", at) or starts(text, "https://", at))
    and (at == 1 or contains(" \n*_~(", text:sub(at - 1, at - 1))) then
    local stop = at
    while stop <= #text and not contains(" \n<", text:sub(stop, stop)) do stop = stop + 1 end
    while stop > at and contains(".,:;!?*_~)", text:sub(stop - 1, stop - 1)) do stop = stop - 1 end
    local url = text:sub(at, stop - 1)
    if url ~= "http://" and url ~= "https://" then
      local escaped = escape(url)
      return '<a href="' .. escaped .. '">' .. escaped .. '</a>', stop
    end
  end
  if character == "[" or (character == "!" and following == "[") then
    local html, stop = self:bracket(text, at, links, notes)
    return html or character, stop or at + 1
  end
  if contains("*_~", character) then
    local stop = run_end(text, at)
    local length = stop - at
    local before = at == 1 and " " or text:sub(at - 1, at - 1)
    local after = stop > #text and " " or text:sub(stop, stop)
    local can_open, can_close = not contains(WHITESPACE, after), not contains(WHITESPACE, before)
    if character == "_" and before:match("^[A-Za-z0-9]$") and after:match("^[A-Za-z0-9]$") then can_open, can_close = false, false end
    if (character ~= "~" and length <= 3) or (character == "~" and length == 2) then
      return { character = character, length = length, open = can_open, close = can_close }, stop
    end
    return character:rep(length), stop
  end
  return escape(character), at + 1
end

function Renderer:inline(text, links, notes)
  local pieces, at = {}, 1
  while at <= #text do
    local piece
    piece, at = self:next_piece(text, at, links, notes)
    pieces[#pieces + 1] = piece
  end
  return emphasis(pieces, 1, #pieces)
end

function Renderer:blocks(blocks)
  local parts = {}
  for _, block in ipairs(blocks) do parts[#parts + 1] = self:render(block) .. "\n" end
  return table.concat(parts)
end

function Renderer:heading(level, text)
  local identifier, start = nil, nil
  local at = 1
  while true do
    local found = text:find(" {#", at, true)
    if not found then break end
    start, at = found, found + 1
  end
  if text:sub(-1) == "}" and start then
    local candidate = text:sub(start + 3, -2)
    if candidate:match("^[A-Za-z0-9_-]+$") then identifier, text = candidate, (text:sub(1, start - 1):gsub(" +$", "")) end
  end
  if not identifier then
    local base = text:lower():gsub("[^a-z0-9_ \n-]", ""):gsub("[ \n]", "-")
    if base == "" then base = "heading" end
    identifier = base
    local suffix = 1
    while self.used_ids[identifier] do identifier, suffix = base .. "-" .. suffix, suffix + 1 end
  end
  self.used_ids[identifier] = true
  local html = self:inline(text, true, true)
  self.headings[#self.headings + 1] = { level = level, id = identifier, label = strip_tags(html), children = {} }
  return '<h' .. level .. ' id="' .. identifier .. '">' .. html .. '</h' .. level .. '>'
end

function Renderer:item(blocks)
  local parts, newline = { "<li>" }, false
  for index, block in ipairs(blocks) do
    if block.kind == "paragraph" then
      local text = block.text
      if index == 1 and #text > 4 and (starts(text, "[ ] ") or starts(text, "[x] ") or starts(text, "[X] ")) then
        parts[#parts + 1] = text:sub(2, 2) == " " and '<input type="checkbox" disabled="" /> ' or '<input type="checkbox" checked="" disabled="" /> '
        text = text:sub(5)
      end
      local html = self:inline(text, true, true)
      parts[#parts + 1] = html
      if html ~= "" then newline = html:sub(-1) == "\n" end
    else
      if not newline then parts[#parts + 1] = "\n" end
      parts[#parts + 1], newline = self:render(block) .. "\n", true
    end
  end
  parts[#parts + 1] = "</li>"
  return table.concat(parts)
end

function Renderer:table_cells(tag, block, cells)
  local parts = {}
  for index, cell in ipairs(cells) do
    local alignment = block.alignments[index]
    local style = alignment ~= "" and ' style="text-align:' .. alignment .. '"' or ""
    parts[#parts + 1] = '<' .. tag .. style .. '>' .. self:inline(cell, true, true) .. '</' .. tag .. '>\n'
  end
  return table.concat(parts)
end

function Renderer:render(block)
  local kind = block.kind
  if kind == "heading" then return self:heading(block.number, block.text)
  elseif kind == "paragraph" then return "<p>" .. self:inline(block.text, true, true) .. "</p>"
  elseif kind == "rule" then return "<hr />"
  elseif kind == "code" then
    local attribute = block.text ~= "" and ' class="language-' .. escape(block.text) .. '"' or ""
    local parts = { "<pre><code" .. attribute .. ">" }
    for _, line in ipairs(block.lines) do parts[#parts + 1] = escape(line) .. "\n" end
    parts[#parts + 1] = "</code></pre>"
    return table.concat(parts)
  elseif kind == "quote" then return "<blockquote>\n" .. self:blocks(block.children) .. "</blockquote>"
  elseif kind == "alert" then
    local name = block.text:lower()
    local title = name:sub(1, 1):upper() .. name:sub(2)
    return '<div class="alert alert-' .. name .. '">\n<p class="alert-title">' .. title .. '</p>\n' .. self:blocks(block.children) .. '</div>'
  elseif kind == "list" then
    local tag = block.ordered and "ol" or "ul"
    local attribute = block.ordered and block.number ~= 1 and ' start="' .. block.number .. '"' or ""
    local parts = { '<' .. tag .. attribute .. '>\n' }
    for _, item in ipairs(block.items) do parts[#parts + 1] = self:item(item) .. "\n" end
    parts[#parts + 1] = '</' .. tag .. '>'
    return table.concat(parts)
  elseif kind == "table" then
    local parts = { "<table>\n<thead>\n<tr>\n", self:table_cells("th", block, block.lines), "</tr>\n</thead>\n" }
    if #block.rows > 0 then
      parts[#parts + 1] = "<tbody>\n"
      for _, row in ipairs(block.rows) do parts[#parts + 1] = "<tr>\n" .. self:table_cells("td", block, row) .. "</tr>\n" end
      parts[#parts + 1] = "</tbody>\n"
    end
    parts[#parts + 1] = "</table>"
    return table.concat(parts)
  elseif kind == "toc" then return TOC_MARKER end
end

local function toc_list(entries)
  local parts = { "<ul>\n" }
  for _, entry in ipairs(entries) do
    parts[#parts + 1] = '<li><a href="#' .. entry.id .. '">' .. entry.label .. '</a>'
    if #entry.children > 0 then parts[#parts + 1] = "\n" .. toc_list(entry.children) .. "\n" end
    parts[#parts + 1] = "</li>\n"
  end
  parts[#parts + 1] = "</ul>"
  return table.concat(parts)
end

function Renderer:toc()
  if #self.headings == 0 then return '<nav class="toc">\n</nav>' end
  local roots, parents = {}, {}
  for _, heading in ipairs(self.headings) do
    while #parents > 0 and parents[#parents].level >= heading.level do table.remove(parents) end
    local siblings = #parents > 0 and parents[#parents].children or roots
    siblings[#siblings + 1], parents[#parents + 1] = heading, heading
  end
  return '<nav class="toc">\n' .. toc_list(roots) .. '\n</nav>'
end

function Renderer:footnote_list()
  local parts = { '<section class="footnotes">\n<ol>\n' }
  for number, name in ipairs(self.footnote_names) do
    parts[#parts + 1] = '<li id="fn-' .. number .. '">' .. self:inline(self.footnotes[name], true, false)
    for count = 1, self.footnote_counts[number] do parts[#parts + 1] = ' <a href="#' .. reference_id(number, count) .. '">&#8617;</a>' end
    parts[#parts + 1] = '</li>\n'
  end
  parts[#parts + 1] = '</ol>\n</section>\n'
  return table.concat(parts)
end

local function main()
  local lines = {}
  for line in io.lines() do
    if line == "@@END@@" then break end
    lines[#lines + 1] = line
  end
  local parser = setmetatable({ references = {}, footnotes = {} }, Parser)
  local blocks = parser:parse(lines)
  local renderer = setmetatable({ references = parser.references, footnotes = parser.footnotes,
    used_ids = {}, headings = {}, footnote_numbers = {}, footnote_names = {}, footnote_counts = {},
  }, Renderer)
  local html = renderer:blocks(blocks)
  local toc = renderer:toc()
  local parts, at = {}, 1
  while true do
    local found = html:find(TOC_MARKER, at, true)
    if not found then parts[#parts + 1] = html:sub(at); break end
    parts[#parts + 1], parts[#parts + 2], at = html:sub(at, found - 1), toc, found + #TOC_MARKER
  end
  if #renderer.footnote_names > 0 then parts[#parts + 1] = renderer:footnote_list() end
  io.write(table.concat(parts))
end

main()
