local parser = require("document_parser")
local hyphenation = require("hyphenation")
local line_breaker = require("line_breaker")
local page_builder = require("page_builder")
local renderer = require("renderer")
local function append(target, values)
    for _, value in ipairs(values) do
        target[#target + 1] = value
    end
end
local function read_lines(path)
    local lines = {}
    for line in io.lines(path) do
        lines[#lines + 1] = line
    end
    return lines
end
local function words_in(text)
    local words = {}
    for word in text:gmatch("[^ ]+") do
        words[#words + 1] = word
    end
    return words
end
local function keys(values, comparator)
    local names = {}
    for name in pairs(values) do
        names[#names + 1] = name
    end
    table.sort(names, comparator)
    return names
end
local function split_label(text)
    local start = nil
    local position = 1
    while true do
        local found = text:find(" {#", position, true)
        if not found then
            break
        end
        start, position = found, found + 3
    end
    if start and text:sub(-1) == "}" then
        return text:sub(1, start - 1), text:sub(start + 3, -2)
    end
    return text, nil
end
local function text_line(text)
    return {text = text, footnotes = {}, indexes = {}}
end
local Metrics = {}
Metrics.__index = Metrics
function Metrics.new(words, first_capacity, later_capacity, dictionary)
    local self = setmetatable({words = words, first_capacity = first_capacity, later_capacity = later_capacity,
        offsets = {}, breaks = {[0] = {start_word = 0, start_position = 0, end_word = 0, end_position = 0, midword = false, append_hyphen = false}}}, Metrics)
    local offset, count = 0, 0
    for index, word in ipairs(words) do
        self.offsets[index - 1] = offset
        offset = offset + #word + 1
        for _, point in ipairs(dictionary:split_points(word)) do
            count = count + 1
            self.breaks[count] = {start_word = index - 1, start_position = point[1], end_word = index - 1, end_position = point[1], midword = true, append_hyphen = point[2]}
        end
        count = count + 1
        self.breaks[count] = {start_word = index, start_position = 0, end_word = index - 1, end_position = #word, midword = false, append_hyphen = false}
    end
    self.finish = count
    return self
end
function Metrics:capacity(start)
    return start == 0 and self.first_capacity or self.later_capacity
end
function Metrics:length(start, finish)
    local first, last = self.breaks[start], self.breaks[finish]
    return self.offsets[last.end_word] + last.end_position - self.offsets[first.start_word] - first.start_position + (last.append_hyphen and 1 or 0)
end
function Metrics:slack(start, finish)
    return self:capacity(start) - self:length(start, finish)
end
function Metrics:measure(start, finish)
    local first, last = self.breaks[start], self.breaks[finish]
    local pieces, ranges = {}, {}
    for word = first.start_word, last.end_word do
        local left = word == first.start_word and first.start_position or 0
        local right = word == last.end_word and last.end_position or #self.words[word + 1]
        pieces[#pieces + 1] = self.words[word + 1]:sub(left + 1, right)
        ranges[#ranges + 1] = {word, left, right}
    end
    if last.append_hyphen then
        pieces[#pieces] = pieces[#pieces] .. "-"
    end
    return {start = start, finish = finish, pieces = pieces, ranges = ranges, gaps = #pieces - 1,
        length = self:length(start, finish), capacity = self:capacity(start), slack = self:slack(start, finish),
        last = finish == self.finish, midword = last.midword}
end
local Typesetter = {}
Typesetter.__index = Typesetter
function Typesetter:warn(number, message)
    self.warnings[#self.warnings + 1] = {line = number, message = message}
end
function Typesetter:register_document()
    local chapter, section, table_number, previous = 0, 0, 0, nil
    for index, block in ipairs(self.blocks) do
        block.id = index
        local kind = block.kind
        if kind == "h1" or kind == "h2" then
            block.text, block.label = split_label(block.argument)
            if kind == "h1" then
                chapter, section = chapter + 1, 0
                block.number = tostring(chapter)
                if index > 1 then
                    block.page_break = true
                end
            else
                section = section + 1
                block.number = chapter .. "." .. section
            end
            self.headings[#self.headings + 1] = block
        elseif kind == "enum" then
            block.number = previous and previous.kind == "enum" and previous.number + 1 or 1
        elseif kind == "table" then
            block.caption, block.label = split_label(block.caption)
            if block.caption ~= "" then
                table_number = table_number + 1
                block.number = tostring(table_number)
                self.numbered_tables[#self.numbered_tables + 1] = block
            end
        end
        if block.label then
            if self.labels[block.label] then
                self:warn(block.line, "duplicate label " .. block.label)
                block.label = nil
            else
                self.labels[block.label] = block
            end
        end
        if kind == "paragraph" and previous and (previous.kind == "h1" or previous.kind == "h2") then
            block.indent = 0
        end
        if parser.body_kinds[kind] then
            self.body_blocks[#self.body_blocks + 1] = block
            block.paragraph_number = #self.body_blocks
        end
        previous = block
    end
    for _, entry in ipairs(self.document.bibliography) do
        if self.bibliography[entry.key] then
            self:warn(entry.line, "duplicate bibliography key " .. entry.key)
        else
            entry.cited = false
            self.bibliography[entry.key] = entry
            self.bibliography_entries[#self.bibliography_entries + 1] = entry
        end
    end
end
function Typesetter:accept_command(name, argument, number)
    if name == "ref" or name == "page" then
        if not self.labels[argument] then
            self:warn(number, "undefined label " .. argument)
        end
    elseif name == "cite" then
        for _, key in ipairs(parser.split(argument, ",")) do
            if self.bibliography[key] then
                self.bibliography[key].cited = true
            else
                self:warn(number, "undefined citation " .. key)
            end
        end
    elseif name == "fn" then
        self.footnotes[#self.footnotes + 1] = argument
        argument = #self.footnotes
    elseif name == "idx" then
        self.index_marks[#self.index_marks + 1] = argument
        argument = #self.index_marks
    end
    return {name = name, argument = argument}
end
function Typesetter:parse_body_line(text, number)
    local tokens, position = {}, 1
    while position <= #text do
        local opening = text:find("{", position, true)
        if not opening then
            tokens[#tokens + 1] = text:sub(position)
            break
        end
        if opening > position then
            tokens[#tokens + 1] = text:sub(position, opening - 1)
        end
        local closing = text:find("}", opening + 1, true)
        if not closing then
            self:warn(number, "unclosed brace")
            tokens[#tokens + 1] = text:sub(opening)
            break
        end
        local content = text:sub(opening + 1, closing - 1)
        local name, argument, separator = parser.partition(content, ":")
        if (name == "ref" or name == "page" or name == "fn" or name == "idx" or name == "cite") and separator and argument ~= "" then
            tokens[#tokens + 1] = self:accept_command(name, argument, number)
        else
            self:warn(number, "bad command {" .. content .. "}")
        end
        position = closing + 1
    end
    return tokens
end
function Typesetter:check_document()
    for _, block in ipairs(self.blocks) do
        if block.kind == "table" then
            local rows, count = {}, #block.columns
            for _, line in ipairs(block.inner_lines) do
                local cells = parser.split(line.text, "|")
                for i, cell in ipairs(cells) do
                    cells[i] = cell:match("^ *(.-) *$")
                end
                if #cells ~= count then
                    self:warn(line.line, "table row has " .. #cells .. " cells, expected " .. count)
                end
                while #cells > count do
                    table.remove(cells)
                end
                while #cells < count do
                    cells[#cells + 1] = ""
                end
                rows[#rows + 1] = cells
            end
            block.rows = rows
            block.table_lines = renderer.format_table(rows, block.columns, block.caption, block.number)
            local longest = 0
            for _, line in ipairs(block.table_lines) do
                longest = math.max(longest, #line)
            end
            if longest > block.width then
                self:warn(block.line, "table too wide by " .. (longest - block.width))
            end
        elseif block.kind == "verbatim" then
            for _, line in ipairs(block.inner_lines) do
                if #line.text > block.width then
                    self:warn(line.line, "verbatim line too long by " .. (#line.text - block.width))
                end
            end
        elseif parser.body_kinds[block.kind] then
            block.tokens = {}
            for i, line in ipairs(block.body_lines) do
                if i > 1 then
                    block.tokens[#block.tokens + 1] = " "
                end
                append(block.tokens, self:parse_body_line(line.text, line.line))
            end
        end
    end
    for _, entry in ipairs(self.bibliography_entries) do
        if not entry.cited then
            self:warn(entry.line, "unused bibliography entry " .. entry.key)
        end
    end
end
function Typesetter:assign_bibliography_labels()
    for _, entry in ipairs(self.bibliography_entries) do
        if entry.cited then
            local surnames, base = parser.split(entry.author, " and "), ""
            if #surnames == 1 then
                base = surnames[1]:sub(1, 3)
            else
                for i = 1, math.min(#surnames, #surnames >= 5 and 3 or 4) do
                    base = base .. surnames[i]:sub(1, 1)
                end
                if #surnames >= 5 then
                    base = base .. "+"
                end
            end
            entry.base = base .. entry.year:sub(-2)
            self.cited_entries[#self.cited_entries + 1] = entry
        end
    end
    table.sort(self.cited_entries, function(a, b)
        for _, field in ipairs({"base", "author", "title", "key"}) do
            if a[field] ~= b[field] then
                return a[field] < b[field]
            end
        end
        return false
    end)
    local index = 1
    while index <= #self.cited_entries do
        local finish = index
        while finish < #self.cited_entries and self.cited_entries[finish + 1].base == self.cited_entries[index].base do
            finish = finish + 1
        end
        for i = index, finish do
            self.cited_entries[i].label = self.cited_entries[i].base .. (finish > index and string.char(97 + i - index) or "")
        end
        index = finish + 1
    end
end
function Typesetter:prepare_index()
    for number, phrase in ipairs(self.index_marks) do
        local entry_part, reference, has_reference = parser.partition(phrase, "|")
        local parent_name, child_name, has_child = parser.partition(entry_part, "!")
        local parent = self.index_entries[parent_name]
        if not parent then
            parent = {name = parent_name, marks = {}, references = {}, children = {}}
            self.index_entries[parent_name] = parent
        end
        local entry = parent
        if has_child then
            if not parent.children[child_name] then
                parent.children[child_name] = {name = child_name, marks = {}, references = {}}
            end
            entry = parent.children[child_name]
        end
        if has_reference then
            entry.references[reference] = true
        else
            entry.marks[#entry.marks + 1] = number
        end
    end
end
function Typesetter.new(document, params, dictionary_lines)
    local self = setmetatable({document = document, params = params, blocks = document.blocks, warnings = document.warnings,
        labels = {}, bibliography = {}, bibliography_entries = {}, cited_entries = {}, body_blocks = {}, headings = {},
        numbered_tables = {}, footnotes = {}, index_marks = {}, index_entries = {},
        dictionary = hyphenation.new(dictionary_lines, document.hyphenation_words, params.left_min, params.right_min)}, Typesetter)
    self:register_document()
    self:check_document()
    self:assign_bibliography_labels()
    self:prepare_index()
    for index, warning in ipairs(self.warnings) do
        warning.index = index
    end
    table.sort(self.warnings, function(a, b) return a.line < b.line or (a.line == b.line and a.index < b.index) end)
    return self
end
function Typesetter:citation_text(argument)
    local labels, undefined = {}, false
    for _, key in ipairs(parser.split(argument, ",")) do
        local entry = self.bibliography[key]
        if entry then
            labels[entry.label] = true
        else
            undefined = true
        end
    end
    local parts = keys(labels)
    if undefined then
        parts[#parts + 1] = "?"
    end
    return "[" .. table.concat(parts, ", ") .. "]"
end
function Typesetter:expand_body(block, page_values)
    local parts, marks, offset = {}, {}, 0
    for _, token in ipairs(block.tokens) do
        local text
        if type(token) == "string" then
            text = token
        elseif token.name == "idx" then
            marks[#marks + 1] = {offset = offset - 1, kind = "idx", number = token.argument}
            text = ""
        elseif token.name == "fn" then
            marks[#marks + 1] = {offset = offset, kind = "fn", number = token.argument}
            text = "[" .. token.argument .. "]"
        elseif token.name == "ref" then
            local target = self.labels[token.argument]
            text = target and target.number or "??"
        elseif token.name == "page" then
            text = page_values[token.argument] or "??"
        else
            text = self:citation_text(token.argument)
        end
        parts[#parts + 1] = text
        offset = offset + #text
    end
    local expanded, words, starts = table.concat(parts), {}, {}
    local position = 1
    while true do
        local first, last = expanded:find("[^ ]+", position)
        if not first then
            break
        end
        words[#words + 1], starts[#starts + 1] = expanded:sub(first, last), first - 1
        position = last + 1
    end
    local word_marks = {}
    for _, mark in ipairs(marks) do
        local word = #starts
        while starts[word] > mark.offset do
            word = word - 1
        end
        word_marks[word - 1] = word_marks[word - 1] or {}
        local list = word_marks[word - 1]
        list[#list + 1] = {kind = mark.kind, number = mark.number, position = mark.offset - starts[word]}
    end
    return words, word_marks
end
function Typesetter:lay_out_text(words, capacities, alignment, prefixes, method, marks)
    local metrics = Metrics.new(words, capacities[1], capacities[2], self.dictionary)
    local breaking, cost = line_breaker.break_text(metrics, method, self.params)
    local lines, measured_lines, start = {}, {}, 0
    for index, finish in ipairs(breaking) do
        local measured = metrics:measure(start, finish)
        local text = renderer.display_line(measured.pieces, measured.slack, alignment, measured.last)
        local line = text_line(prefixes[index == 1 and 1 or 2] .. text)
        for _, range in ipairs(measured.ranges) do
            for _, mark in ipairs(marks and marks[range[1]] or {}) do
                if mark.position >= range[2] and mark.position < range[3] then
                    local target = mark.kind == "fn" and line.footnotes or line.indexes
                    target[#target + 1] = mark.number
                end
            end
        end
        lines[#lines + 1], measured_lines[#measured_lines + 1], start = line, measured, finish
    end
    return {lines = lines, broken = measured_lines, cost = cost}
end
function Typesetter:lay_out_body(block, page_values, method)
    local words, marks = self:expand_body(block, page_values)
    local width, capacities, prefixes = block.width
    if block.kind == "paragraph" then
        capacities, prefixes = {width - block.indent, width}, {string.rep(" ", block.indent), ""}
    elseif block.kind == "item" then
        capacities, prefixes = {width - 2, width - 2}, {"- ", "  "}
    elseif block.kind == "enum" then
        capacities, prefixes = {width - 4, width - 4}, {string.format("%2d. ", block.number), "    "}
    elseif block.kind == "quote" then
        capacities, prefixes = {width - 8, width - 8}, {"    ", "    "}
    else
        local first = #block.term <= 10 and (block.term .. string.rep(" ", 12 - #block.term)) or string.rep(" ", 12)
        capacities, prefixes = {width - 12, width - 12}, {first, string.rep(" ", 12)}
    end
    local result = self:lay_out_text(words, capacities, block.align, prefixes, method, marks)
    if block.kind == "term" and #block.term >= 11 then
        table.insert(result.lines, 1, text_line(block.term))
    end
    return result
end
function Typesetter:lay_out_footnotes(method)
    local results = {}
    for number, text in ipairs(self.footnotes) do
        local prefix = "[" .. number .. "] "
        local capacity = self.document.page_width - #prefix
        results[number] = self:lay_out_text(words_in(text), {capacity, capacity}, "left", {prefix, string.rep(" ", #prefix)}, method)
    end
    return results
end
function Typesetter:lay_out_reference(entry, width, method)
    local margin = 0
    for _, item in ipairs(self.cited_entries) do
        margin = math.max(margin, #item.label + 3)
    end
    local prefix = "[" .. entry.label .. "]"
    prefix = prefix .. string.rep(" ", margin - #prefix)
    return self:lay_out_text(words_in(entry.author .. ". " .. entry.year .. ". " .. entry.title),
        {width - margin, width - margin}, "left", {prefix, string.rep(" ", margin)}, method)
end
local function page_list(numbers)
    local seen = {}
    for _, number in ipairs(numbers) do
        seen[number] = true
    end
    numbers = keys(seen)
    local parts, index = {}, 1
    while index <= #numbers do
        local finish = index
        while finish < #numbers and numbers[finish + 1] == numbers[finish] + 1 do
            finish = finish + 1
        end
        if finish - index >= 2 then
            parts[#parts + 1] = numbers[index] .. "-" .. numbers[finish]
        else
            for i = index, finish do
                parts[#parts + 1] = tostring(numbers[i])
            end
        end
        index = finish + 1
    end
    return table.concat(parts, ", ")
end
local function index_order(a, b)
    return a:lower() < b:lower() or (a:lower() == b:lower() and a < b)
end
function Typesetter:index_entry_line(entry, mark_pages, child)
    local text, numbers = (child and "  " or "") .. entry.name, {}
    for _, number in ipairs(entry.marks) do
        if mark_pages[number] ~= nil then
            numbers[#numbers + 1] = mark_pages[number]
        end
    end
    if #numbers > 0 then
        text = text .. ", " .. page_list(numbers)
    end
    local references = keys(entry.references)
    if #references > 0 then
        text = text .. ", see " .. table.concat(references, ", ")
    end
    return text
end
function Typesetter:index_lines(mark_pages)
    local lines, previous_group = {}, nil
    for _, name in ipairs(keys(self.index_entries, index_order)) do
        local parent = self.index_entries[name]
        local first = name:sub(1, 1)
        local group = hyphenation.is_letter(first) and first:upper() or "Symbols"
        if group ~= previous_group then
            lines[#lines + 1] = group
            previous_group = group
        end
        lines[#lines + 1] = self:index_entry_line(parent, mark_pages, false)
        for _, child in ipairs(keys(parent.children, index_order)) do
            lines[#lines + 1] = self:index_entry_line(parent.children[child], mark_pages, true)
        end
    end
    return lines
end
function Typesetter:contents_lines(block, block_pages)
    local entries = block.kind == "toc" and self.headings or self.numbered_tables
    local lines = {}
    for _, entry in ipairs(entries) do
        local left
        if block.kind == "toc" then
            left = (entry.kind == "h2" and "  " or "") .. entry.number .. " " .. entry.text
        else
            left = "Table " .. entry.number .. ". " .. entry.caption
        end
        local page = block_pages[entry.id]
        local number = page and page.display or "??"
        lines[#lines + 1] = left .. " " .. string.rep(".", block.width - #left - #number - 2) .. " " .. number
    end
    return lines
end
local function add_layout_block(layout, source, kind, lines, list_mark, first)
    if first == nil then
        first = true
    end
    if first then
        lines[1].anchor = source.id
        lines[1].chapter_start = source.kind == "h1"
    end
    layout[#layout + 1] = {kind = kind, lines = lines, list = list_mark or false, page_break = first and source.page_break or false}
end
local function text_lines(texts)
    local lines = {}
    for i, text in ipairs(texts) do
        lines[i] = text_line(text)
    end
    return lines
end
function Typesetter:build_layout_blocks(page_values, method, result)
    local layout = {}
    for _, block in ipairs(self.blocks) do
        local kind = block.kind
        if parser.body_kinds[kind] then
            local body = self:lay_out_body(block, page_values, method)
            result.bodies[block.id] = body
            result.warning_texts[#result.warning_texts + 1] = {name = "paragraph " .. block.paragraph_number, result = body, justify = block.align == "justify"}
            add_layout_block(layout, block, "flow", body.lines, kind == "item" or kind == "enum" or kind == "term")
        elseif kind == "title" or kind == "author" then
            local text = kind == "title" and block.argument:upper() or block.argument
            text = string.rep(" ", (block.width - #text) // 2) .. text
            add_layout_block(layout, block, "heading", {text_line(text)})
        elseif kind == "h1" or kind == "h2" then
            local text = block.number .. " " .. (kind == "h1" and block.text:upper() or block.text)
            add_layout_block(layout, block, "heading", {text_line(text), text_line(string.rep(kind == "h1" and "=" or "-", #text))})
        elseif kind == "table" then
            add_layout_block(layout, block, "solid", text_lines(block.table_lines))
        elseif kind == "verbatim" then
            local lines = {}
            for i, inner in ipairs(block.inner_lines) do
                lines[i] = text_line(inner.text)
            end
            add_layout_block(layout, block, "flow", lines)
        elseif kind == "toc" or kind == "lot" or kind == "index" then
            local title = ({toc = "CONTENTS", lot = "TABLES", index = "INDEX"})[kind]
            add_layout_block(layout, block, "heading", {text_line(title), text_line(string.rep("=", #title))})
            local entries = kind == "index" and self:index_lines({}) or self:contents_lines(block, {})
            local lines = text_lines(entries)
            add_layout_block(layout, block, "flow", lines, false, false)
            result.generated[#result.generated + 1] = {block = block, lines = lines}
        else
            add_layout_block(layout, block, "heading", {text_line("REFERENCES"), text_line("==========")})
            for _, entry in ipairs(self.cited_entries) do
                local reference = self:lay_out_reference(entry, block.width, method)
                result.warning_texts[#result.warning_texts + 1] = {name = "reference " .. entry.label, result = reference, justify = false}
                add_layout_block(layout, block, "flow", reference.lines, true, false)
            end
        end
    end
    return layout
end
local function roman(number)
    local units = {[0] = "", "i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix"}
    return string.rep("x", number // 10) .. units[number % 10]
end
function Typesetter:number_pages(pages, result)
    local numbered = {}
    for _, page in ipairs(pages) do
        local chapter_start = page.content[1].chapter_start or false
        local serial = #numbered + 1
        if chapter_start and serial % 2 == 0 then
            numbered[#numbered + 1] = {serial = serial, blank = true, content = {}, footnotes = {}, height = 0, ends_by_force = true, chapter_start = false}
            serial = serial + 1
        end
        page.serial, page.chapter_start = serial, chapter_start
        numbered[#numbered + 1] = page
    end
    local block_pages = {}
    for _, page in ipairs(numbered) do
        for _, line in ipairs(page.content) do
            if line.anchor then
                block_pages[line.anchor] = page
            end
        end
    end
    local front_matter = #self.headings > 0 and block_pages[self.headings[1].id].serial - 1 or 0
    local mark_pages = {}
    for _, page in ipairs(numbered) do
        page.body_number = page.serial - front_matter
        page.display = page.serial <= front_matter and roman(page.serial) or tostring(page.body_number)
        for _, line in ipairs(page.content) do
            for _, mark in ipairs(line.indexes) do
                mark_pages[mark] = page.body_number
            end
        end
    end
    result.pages, result.front_matter, result.block_pages, result.mark_pages = numbered, front_matter, block_pages, mark_pages
    result.label_values = {}
    for label, block in pairs(self.labels) do
        result.label_values[label] = block_pages[block.id].display
    end
end
function Typesetter:layout_once(page_values, method)
    local footnotes = self:lay_out_footnotes(method)
    local result = {method = method, bodies = {}, footnotes = footnotes, warning_texts = {}, generated = {}}
    local layout = self:build_layout_blocks(page_values, method, result)
    local heights = {}
    for i, note in ipairs(footnotes) do
        heights[i] = #note.lines
    end
    local pages = page_builder.choose_pages(layout, heights, self.document.height, self.params.orphan_lines, self.params.widow_lines)
    self:number_pages(pages, result)
    for number, note in ipairs(footnotes) do
        result.warning_texts[#result.warning_texts + 1] = {name = "footnote " .. number, result = note, justify = false}
    end
    return result
end
function Typesetter:assemble_pages(result)
    for _, generated in ipairs(result.generated) do
        local texts = generated.block.kind == "index" and self:index_lines(result.mark_pages) or self:contents_lines(generated.block, result.block_pages)
        for i, line in ipairs(generated.lines) do
            line.text = texts[i]
        end
    end
    local chapter, section, height = "", "", self.document.height
    local total = #result.pages - result.front_matter
    for _, page in ipairs(result.pages) do
        if page.blank then
            page.header, page.footer, page.body = "", "", {}
            for i = 1, height do
                page.body[i] = ""
            end
        else
            for _, line in ipairs(page.content) do
                if line.anchor then
                    local block = self.blocks[line.anchor]
                    if block.kind == "h1" then
                        chapter, section = block.number .. " " .. block.text, ""
                    elseif block.kind == "h2" then
                        section = block.number .. " " .. block.text
                    end
                end
            end
            local values = {page = page.display, pages = tostring(total), chapter = chapter, section = section}
            page.header = page.chapter_start and "" or renderer.running_head(self.document.header, values, self.document.page_width, page.serial)
            page.footer = renderer.running_head(self.document.footer, values, self.document.page_width, page.serial)
            local body, notes = {}, {}
            for _, line in ipairs(page.content) do
                body[#body + 1] = line.text
            end
            for _, number in ipairs(page.footnotes) do
                for _, line in ipairs(result.footnotes[number].lines) do
                    notes[#notes + 1] = line.text
                end
            end
            local padding = height - #body - #notes - (#notes > 0 and 1 or 0)
            for _ = 1, padding do
                body[#body + 1] = ""
            end
            if #notes > 0 then
                body[#body + 1] = "----------"
                append(body, notes)
            end
            page.body = body
        end
    end
end
function Typesetter:layout(method)
    local values = {}
    for label in pairs(self.labels) do
        values[label] = "??"
    end
    while true do
        local result = self:layout_once(values, method)
        local same = true
        for label, value in pairs(values) do
            if result.label_values[label] ~= value then
                same = false
            end
        end
        if same then
            self:assemble_pages(result)
            return result
        end
        values = result.label_values
    end
end
function Typesetter:layout_warnings(result)
    local warnings = {}
    local function add(message)
        warnings[#warnings + 1] = result.method .. ": " .. message
    end
    for _, entry in ipairs(result.warning_texts) do
        for number, line in ipairs(entry.result.broken) do
            if line.slack < 0 then
                add(entry.name .. " line " .. number .. ": overfull by " .. -line.slack)
            elseif entry.justify and not line.last and line.slack >= self.params.underfull_slack then
                add(entry.name .. " line " .. number .. ": underfull, slack " .. line.slack)
            end
        end
    end
    for _, page in ipairs(result.pages) do
        local empty = self.document.height - page.height
        if not page.blank and not page.ends_by_force and empty >= self.params.underfull_page then
            add("page " .. page.serial .. ": underfull, " .. empty .. " empty lines")
        end
    end
    local hyphenated = 0
    for _, block in ipairs(self.body_blocks) do
        for _, line in ipairs(result.bodies[block.id].broken) do
            if line.midword then
                hyphenated = hyphenated + 1
            end
        end
    end
    add(#result.pages .. " pages, " .. hyphenated .. " hyphenated lines")
    return warnings
end
function Typesetter:statistics(optimal, greedy)
    local lines, totals = {"paragraph,lines_kp,cost_kp,lines_greedy,cost_greedy"}, {0, 0, 0, 0}
    for _, block in ipairs(self.body_blocks) do
        local kp, other = optimal.bodies[block.id], greedy.bodies[block.id]
        local values = {#kp.broken, kp.cost, #other.broken, other.cost}
        local fields = {tostring(block.paragraph_number)}
        for i, value in ipairs(values) do
            totals[i] = totals[i] + value
            fields[#fields + 1] = tostring(value)
        end
        lines[#lines + 1] = table.concat(fields, ",")
    end
    local fields = {"total"}
    for _, total in ipairs(totals) do
        fields[#fields + 1] = tostring(total)
    end
    lines[#lines + 1] = table.concat(fields, ",")
    return lines
end
local function write_lines(name, lines)
    local file = assert(io.open("output/" .. name, "w"))
    for _, line in ipairs(lines) do
        file:write(line, "\n")
    end
    file:close()
end
local params = {}
for _, line in ipairs(read_lines("input/params.txt")) do
    local name, value = parser.partition(line, " ")
    params[name] = tonumber(value)
end
local typesetter = Typesetter.new(parser.parse(read_lines("input/document.txt")), params, read_lines("input/hyphenation.txt"))
local optimal, greedy = typesetter:layout("kp"), typesetter:layout("greedy")
local warnings = {}
for _, warning in ipairs(typesetter.warnings) do
    warnings[#warnings + 1] = "line " .. warning.line .. ": " .. warning.message
end
append(warnings, typesetter:layout_warnings(optimal))
append(warnings, typesetter:layout_warnings(greedy))
os.execute('mkdir -p output')
write_lines("pages.txt", renderer.pages_lines(optimal.pages))
write_lines("greedy_pages.txt", renderer.pages_lines(greedy.pages))
write_lines("stats.csv", typesetter:statistics(optimal, greedy))
write_lines("log.txt", warnings)
