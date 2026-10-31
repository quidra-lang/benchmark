local source_directory = (arg[0]:match("^(.*[/\\])") or "./")
package.path = source_directory .. "?.lua;" .. package.path
local Grid = require("grid")
local slots = require("slots")
local word_index = require("word_index")
local filler = require("filler")
local render = require("render")

local uppercase = word_index.uppercase
local letter_points = {A = 1, B = 3, C = 3, D = 2, E = 1, F = 4, G = 2, H = 4, I = 1,
    J = 8, K = 5, L = 1, M = 3, N = 1, O = 1, P = 3, Q = 10, R = 1, S = 1, T = 1,
    U = 1, V = 4, W = 4, X = 8, Y = 4, Z = 10}

local function extend(target, values) for _, value in ipairs(values) do target[#target + 1] = value end end
local function joined(values, separator) return #values > 0 and table.concat(values, separator) or "-" end
local function ignored(line) return line == "" or line:sub(1, 1) == "#" end
local function cell_text(grid, cell) local row, column = grid:location(cell) return row .. "," .. column end
local function read_lines(name)
    local lines = {}
    for line in io.lines("input/" .. name) do lines[#lines + 1] = line end
    return lines
end

local function read_settings(lines)
    local settings = {}
    for _, line in ipairs(lines) do
        if not ignored(line) then
            local key, value = line:match("^(.-) (.*)$")
            settings[key] = key == "symmetry" and value or tonumber(value)
        end
    end
    return settings
end

local WordList = {}
WordList.__index = WordList

function WordList.new(lines)
    local self = setmetatable({line_count = #lines, scores = {}, first_lines = {}, invalid = {}, duplicates = {}}, WordList)
    for number, line in ipairs(lines) do
        local reason = word_index.word_line_error(line)
        if reason then self.invalid[#self.invalid + 1] = {number, reason}
        else
            local word, score = line:match("^(.-) (.*)$")
            if self.scores[word] then self.duplicates[#self.duplicates + 1] = {number, word, self.first_lines[word]}
            else self.scores[word], self.first_lines[word] = tonumber(score), number end
        end
    end
    self.index = word_index.WordIndex.new(self.scores)
    return self
end

function WordList:report_lines()
    local lines = {string.format("WORDLIST lines=%d valid=%d invalid=%d duplicates=%d", self.line_count, #self.index.ranked, #self.invalid, #self.duplicates)}
    for _, item in ipairs(self.invalid) do lines[#lines + 1] = "invalid " .. item[1] .. " " .. item[2] end
    for _, item in ipairs(self.duplicates) do lines[#lines + 1] = "duplicate " .. item[1] .. " " .. item[2] .. " first=" .. item[3] end
    for length = 3, 15 do
        local words = self.index.by_length[length]
        if words then
            local total = 0
            for _, word in ipairs(words) do total = total + self.scores[word] end
            lines[#lines + 1] = "length " .. length .. " words=" .. #words .. " average=" .. render.decimal(total, #words, 2) .. " best=" .. words[1] .. ":" .. self.scores[words[1]]
        end
    end
    local bands = {}
    for low = 1, 81, 20 do
        local count = 0
        for _, score in pairs(self.scores) do if score >= low and score <= low + 19 then count = count + 1 end end
        bands[#bands + 1] = low .. "-" .. (low + 19) .. "=" .. count
    end
    lines[#lines + 1] = "bands " .. table.concat(bands, " ")
    local top = {}
    for index = 1, math.min(5, #self.index.ranked) do
        local word = self.index.ranked[index]
        top[#top + 1] = word .. ":" .. self.scores[word]
    end
    lines[#lines + 1] = "top " .. table.concat(top, " ")
    local letters = {}
    for index = 1, #uppercase do
        local letter, count = uppercase:sub(index, index), 0
        for word in pairs(self.scores) do if word:find(letter, 1, true) then count = count + 1 end end
        letters[#letters + 1] = {letter = letter, count = count}
    end
    table.sort(letters, function(a, b) return a.count < b.count or a.count == b.count and a.letter < b.letter end)
    local rare = {}
    for index = 1, 5 do rare[#rare + 1] = letters[index].letter .. ":" .. letters[index].count end
    lines[#lines + 1] = "rare_letters " .. table.concat(rare, " ")
    return lines
end

local ClueBook = {}
ClueBook.__index = ClueBook

function ClueBook.new(lines, scores)
    local self = setmetatable({entries = 0, added = 0, invalid = {}, unknown = {}, clues = {}}, ClueBook)
    for number, line in ipairs(lines) do
        if not ignored(line) then
            self.entries = self.entries + 1
            local reason = word_index.clue_line_error(line)
            if reason then self.invalid[#self.invalid + 1] = {number, reason}
            else
                local word, text = line:match("^(.-)|(.*)$")
                if not scores[word] then self.unknown[#self.unknown + 1] = {number, word}
                else
                    self.clues[word] = self.clues[word] or {}
                    local list = self.clues[word]
                    list[#list + 1] = {word = word, number = #list + 1, text = text, uses = 0}
                    self.added = self.added + 1
                end
            end
        end
    end
    return self
end

function ClueBook:choose(word)
    local list = self.clues[word]
    if not list then return nil end
    local chosen = list[1]
    for _, clue in ipairs(list) do if clue.uses < chosen.uses then chosen = clue end end
    chosen.uses = chosen.uses + 1
    return chosen.text
end

function ClueBook:report_lines()
    local names = {}
    for word in pairs(self.clues) do names[#names + 1] = word end
    table.sort(names)
    local lines = {string.format("CLUES entries=%d valid=%d invalid=%d unknown=%d words=%d", self.entries, self.added, #self.invalid, #self.unknown, #names)}
    for _, item in ipairs(self.invalid) do lines[#lines + 1] = "clue_invalid " .. item[1] .. " " .. item[2] end
    for _, item in ipairs(self.unknown) do lines[#lines + 1] = "clue_unknown " .. item[1] .. " " .. item[2] end
    local used, repeated = 0, {}
    for _, word in ipairs(names) do
        for _, clue in ipairs(self.clues[word]) do
            if clue.uses >= 1 then used = used + 1 end
            if clue.uses >= 2 then repeated[#repeated + 1] = clue end
        end
    end
    lines[#lines + 1] = "CLUE_USE used=" .. used .. " unused=" .. (self.added - used) .. " repeated=" .. #repeated
    for _, clue in ipairs(repeated) do lines[#lines + 1] = "repeated " .. clue.word .. " clue=" .. clue.number .. " uses=" .. clue.uses end
    return lines
end

local function split_blocks(lines)
    local blocks, block = {}, nil
    for _, line in ipairs(lines) do
        if not block then
            if line:sub(1, 9) == "TEMPLATE " then block = {name = line:sub(10), options = {}, rows = {}} end
        elseif line == "END" then blocks[#blocks + 1], block = block, nil
        elseif line:find(" ", 1, true) then block.options[#block.options + 1] = line
        else block.rows[#block.rows + 1] = line end
    end
    return blocks
end

local Template = {}
Template.__index = Template

function Template.new(block, settings)
    return setmetatable({name = block.name, options = block.options, rows = block.rows,
        node_budget = settings.node_budget, min_score = settings.min_score, symmetry = settings.symmetry,
        themes = {}, theme_slots = {}, attempts = {}, chosen = {}}, Template)
end

function Template:read_options()
    local seen, themes = {}, {}
    for number, line in ipairs(self.options) do
        local key, value = line:match("^(.-) (.*)$")
        if key == "theme" then
            if not word_index.is_valid_word(value) or themes[value] then return number end
            themes[value] = true
            self.themes[#self.themes + 1] = value
        else
            if seen[key] then return number end
            if key == "node_budget" and word_index.is_valid_integer(value, 1, 100000) then self.node_budget = tonumber(value)
            elseif key == "min_score" and word_index.is_valid_integer(value, 1, 100) then self.min_score = tonumber(value)
            elseif key == "symmetry" and (value == "rot180" or value == "mirror" or value == "none") then self.symmetry = value
            else return number end
        end
        seen[key] = true
    end
    return nil
end

function Template:check(earlier_names, index)
    if #self.name < 1 or #self.name > 20 or not self.name:match("^[a-z0-9_]+$") then return "bad name" end
    if earlier_names[self.name] then return "duplicate name" end
    local bad_option = self:read_options()
    if bad_option then return "bad option " .. bad_option end
    if #self.rows < 3 or #self.rows > 15 then return "bad height" end
    for number, row in ipairs(self.rows) do
        if #row < 3 or #row > 15 or #row ~= #self.rows[1] or not row:match("^[%.#A-Z]+$") then return "bad row " .. number end
    end
    self.grid = Grid.new(self.rows)
    if self.symmetry ~= "none" then
        local cell = self.grid:asymmetric_cell(self.symmetry)
        if cell then return "asymmetric at " .. cell_text(self.grid, cell) end
    end
    local components = self.grid:component_count()
    if components ~= 1 then return "disconnected components=" .. components end
    local cell, direction = slots.find_short_run(self.grid)
    if cell then return "short slot at " .. cell_text(self.grid, cell) .. " " .. direction end
    self.layout = slots.Layout.new(self.grid)
    local orphan = self.layout:orphan_cell()
    if orphan then return "orphan cell " .. cell_text(self.grid, orphan) end
    local letters, words = {}, {}
    for position = 1, self.grid:size() do letters[position] = self.grid.cells:sub(position, position) end
    for position = 1, #self.layout.slots do words[position] = false end
    local state = filler.GridState.new(letters, words)
    for number, theme in ipairs(self.themes) do
        if not index.scores[theme] then return "unknown theme " .. number end
        local chosen
        for _, slot in ipairs(self.layout.slots) do
            if not state.words[slot.index] and slot.length == #theme and word_index.matches(theme, state:pattern(slot)) then chosen = slot break end
        end
        if not chosen then return "theme " .. number .. " does not fit" end
        state:assign(chosen, theme)
        self.theme_slots[chosen.index] = true
    end
    self.initial = state
    return nil
end

function Template:process(earlier_names, index, clue_book, relax_step)
    self.error = self:check(earlier_names, index)
    if self.error then return end
    local minimum = self.min_score
    while true do
        local attempt = filler.Attempt.new(self.layout, index, self.initial, minimum, self.node_budget)
        attempt:run()
        self.attempts[#self.attempts + 1] = attempt
        self.final = attempt
        if attempt.outcome == "filled" or relax_step < 1 or minimum <= 1 then break end
        minimum = math.max(minimum - relax_step, 1)
    end
    self.state = self.final:final_state()
    for _, across in ipairs({true, false}) do
        for _, slot in ipairs(self.layout.slots) do
            if slot.across == across and self.state.words[slot.index] then
                self.chosen[slot.index] = clue_book:choose(self.state.words[slot.index]) or false
            end
        end
    end
end

function Template:is_filled() return self.error == nil and self.final.outcome == "filled" end
function Template:total_score(scores)
    local total = 0
    for _, word in ipairs(self.state.words) do total = total + scores[word] end
    return total
end
function Template:entry(slot, scores)
    local word = self.state.words[slot.index]
    return slot.label .. ":" .. word .. ":" .. scores[word]
end

function Template:grid_paragraph()
    local lines = {"TEMPLATE " .. self.name}
    if self.error then lines[#lines + 1] = "error " .. self.error return lines end
    lines[#lines + 1] = "outcome=" .. self.final.outcome .. " attempts=" .. #self.attempts .. " min_score=" .. self.final.min_score
    extend(lines, render.grid_lines(self.grid, self.state.letters))
    lines[#lines + 1] = "numbers"
    extend(lines, render.number_lines(self.layout))
    return lines
end

function Template:clue_paragraph(scores)
    local lines, clued, missing, unfilled = {"TEMPLATE " .. self.name}, 0, 0, 0
    for _, across in ipairs({true, false}) do
        local started = false
        for _, slot in ipairs(self.layout.slots) do
            if slot.across == across then
                if not started then lines[#lines + 1] = across and "ACROSS" or "DOWN" started = true end
                local word = self.state.words[slot.index]
                if not word then
                    unfilled = unfilled + 1
                    lines[#lines + 1] = render.list_line(slot, "(unfilled)", self.state:pattern(slot), "-", false)
                else
                    local clue = self.chosen[slot.index]
                    if clue then clued = clued + 1 else missing, clue = missing + 1, "(no clue)" end
                    lines[#lines + 1] = render.list_line(slot, clue, word, scores[word], self.theme_slots[slot.index])
                end
            end
        end
    end
    lines[#lines + 1] = "clued=" .. clued .. " missing=" .. missing .. " unfilled=" .. unfilled
    return lines
end

function Template:grid_summary()
    local whites, holding, givens = self.grid:white_cells(), {}, 0
    local blacks = self.grid:size() - #whites
    for _, cell in ipairs(whites) do if self.grid:is_given(cell) then givens = givens + 1 end end
    for _, name in ipairs({"rot180", "mirror"}) do if self.grid:asymmetric_cell(name) == nil then holding[#holding + 1] = name end end
    if #holding == 0 then holding[1] = "none" end
    return "grid size=" .. self.grid.width .. "x" .. self.grid.height .. " blocks=" .. blacks .. " white=" .. #whites .. " density=" .. render.decimal(100 * blacks, self.grid:size(), 1)
        .. " givens=" .. givens .. " required=" .. self.symmetry .. " symmetry=" .. table.concat(holding, ",")
end

function Template:length_counts()
    local counts = {}
    for _, slot in ipairs(self.layout.slots) do counts[slot.length] = (counts[slot.length] or 0) + 1 end
    return counts
end

function Template:slot_summary()
    local counts, lengths, total, across, longest, unchecked = self:length_counts(), {}, 0, 0, 0, 0
    for length = 3, 15 do if counts[length] then lengths[#lengths + 1] = length .. ":" .. counts[length] end end
    for _, slot in ipairs(self.layout.slots) do
        total, longest = total + slot.length, math.max(longest, slot.length)
        if slot.across then across = across + 1 end
    end
    for _, cell in ipairs(self.grid:white_cells()) do if self.layout:owner_count(cell) == 1 then unchecked = unchecked + 1 end end
    local count = #self.layout.slots
    return "slots across=" .. across .. " down=" .. (count - across) .. " total=" .. count .. " lengths=" .. table.concat(lengths, ",")
        .. " avg_length=" .. render.decimal(total, count, 2) .. " longest=" .. longest .. " unchecked=" .. unchecked
end

function Template:coverage_line(index)
    local counts, parts = self:length_counts(), {}
    for length = 3, 15 do
        if counts[length] then
            local supply = 0
            for _, word in ipairs(index.by_length[length] or {}) do if index.scores[word] >= self.min_score then supply = supply + 1 end end
            parts[#parts + 1] = length .. ":" .. supply
        end
    end
    return "coverage " .. table.concat(parts, " ")
end

function Template:tightest_line(index)
    local counts = {}
    for _, slot in ipairs(self.layout.slots) do
        if not self.theme_slots[slot.index] then
            counts[#counts + 1] = {count = #index:candidates(self.initial:pattern(slot), self.min_score, self.initial.used), slot = slot}
        end
    end
    table.sort(counts, function(a, b) return a.count < b.count or a.count == b.count and a.slot.index < b.slot.index end)
    local parts = {}
    for position = 1, math.min(3, #counts) do parts[#parts + 1] = counts[position].slot.label .. ":" .. counts[position].count end
    return "tightest " .. joined(parts, " ")
end

function Template:hotspots_line()
    local failed = {}
    for _, slot in ipairs(self.layout.slots) do if self.final.failures[slot.index] >= 1 then failed[#failed + 1] = slot end end
    table.sort(failed, function(a, b)
        local first, second = self.final.failures[a.index], self.final.failures[b.index]
        return first > second or first == second and a.index < b.index
    end)
    local parts = {}
    for position = 1, math.min(3, #failed) do local slot = failed[position] parts[#parts + 1] = slot.label .. ":" .. self.final.failures[slot.index] end
    return "hotspots " .. joined(parts, " ")
end

function Template:worst_crossing(scores)
    local worst, worst_sum
    for _, cell in ipairs(self.grid:white_cells()) do
        local across, down = self.layout.across_slot[cell], self.layout.down_slot[cell]
        if across and down then
            local total = scores[self.state.words[across]] + scores[self.state.words[down]]
            if worst == nil or total < worst_sum then worst, worst_sum = cell, total end
        end
    end
    if not worst then return "-" end
    local across, down = self.layout.slots[self.layout.across_slot[worst]], self.layout.slots[self.layout.down_slot[worst]]
    return cell_text(self.grid, worst) .. " " .. across.label .. ":" .. self.state.words[across.index] .. "+" .. down.label .. ":" .. self.state.words[down.index] .. "=" .. worst_sum
end

function Template:quality_lines(scores, weak_score)
    local weakest, weak = self.layout.slots[1], {}
    for _, slot in ipairs(self.layout.slots) do
        if scores[self.state.words[slot.index]] < scores[self.state.words[weakest.index]] then weakest = slot end
        if scores[self.state.words[slot.index]] < weak_score then weak[#weak + 1] = self:entry(slot, scores) end
    end
    local whites, distinct, points = self.grid:white_cells(), {}, 0
    for _, cell in ipairs(whites) do
        local letter = self.state.letters[cell]
        distinct[letter], points = true, points + letter_points[letter]
    end
    local missing, count = {}, 0
    for position = 1, #uppercase do
        local letter = uppercase:sub(position, position)
        if distinct[letter] then count = count + 1 else missing[#missing + 1] = letter end
    end
    local total = self:total_score(scores)
    return {"quality total=" .. total .. " average=" .. render.decimal(total, #self.layout.slots, 2) .. " weakest=" .. self:entry(weakest, scores) .. " weak=" .. joined(weak, ","),
        "letters distinct=" .. count .. " pangram=" .. (#missing == 0 and "yes" or "no") .. " missing=" .. joined(missing, "") .. " scrabble=" .. render.decimal(points, #whites, 2) .. " worst_crossing=" .. self:worst_crossing(scores)}
end

function Template:partial_line(index)
    local assigned, lettered, blocked, whites = 0, 0, {}, self.grid:white_cells()
    for _, word in ipairs(self.state.words) do if word then assigned = assigned + 1 end end
    for _, cell in ipairs(whites) do if self.state.letters[cell] ~= "." then lettered = lettered + 1 end end
    for _, slot in ipairs(self.layout.slots) do
        if not self.state.words[slot.index] and #index:candidates(self.state:pattern(slot), self.final.min_score, self.state.used) == 0 then blocked[#blocked + 1] = slot.label end
    end
    return "partial assigned=" .. assigned .. "/" .. #self.layout.slots .. " letters=" .. lettered .. "/" .. #whites .. " blocked=" .. joined(blocked, ",")
end

function Template:stats_paragraph(index, weak_score)
    local lines, themes = {"TEMPLATE " .. self.name, self:grid_summary(), self:slot_summary()}, {}
    for _, slot in ipairs(self.layout.slots) do if self.theme_slots[slot.index] then themes[#themes + 1] = self:entry(slot, index.scores) end end
    if #themes > 0 then lines[#lines + 1] = "themes " .. table.concat(themes, " ") end
    extend(lines, {self:coverage_line(index), self:tightest_line(index)})
    for number, attempt in ipairs(self.attempts) do
        lines[#lines + 1] = string.format("attempt %d min_score=%d budget=%d outcome=%s nodes=%d backtracks=%d prunes=%d dead_ends=%d max_depth=%d",
            number, attempt.min_score, attempt.budget, attempt.outcome, attempt.nodes, attempt.backtracks, attempt.prunes, attempt.dead_ends, attempt.max_depth)
    end
    extend(lines, {"trace " .. joined(self.final.trace, " "), self:hotspots_line()})
    if self:is_filled() then
        local order = {}
        for _, slot in ipairs(self.final.sequence) do order[#order + 1] = slot.label end
        lines[#lines + 1] = "order " .. joined(order, " ")
        extend(lines, self:quality_lines(index.scores, weak_score))
    else lines[#lines + 1] = self:partial_line(index) end
    return lines
end

local function ranking_paragraph(filled, scores)
    local ranked = {}
    extend(ranked, filled)
    table.sort(ranked, function(a, b)
        local left, right = a:total_score(scores) * #b.layout.slots, b:total_score(scores) * #a.layout.slots
        return left > right or left == right and a.name < b.name
    end)
    local lines = {"RANKING"}
    for position, template in ipairs(ranked) do
        local total, entries = template:total_score(scores), #template.layout.slots
        lines[#lines + 1] = "rank " .. position .. " " .. template.name .. " average=" .. render.decimal(total, entries, 2) .. " total=" .. total .. " entries=" .. entries
    end
    return lines
end

local function reuse_paragraph(filled)
    local appearances, reused = {}, {}
    for _, template in ipairs(filled) do
        for _, word in ipairs(template.state.words) do
            appearances[word] = appearances[word] or {}
            local names = appearances[word]
            names[#names + 1] = template.name
        end
    end
    for word, names in pairs(appearances) do if #names >= 2 then reused[#reused + 1] = word end end
    table.sort(reused, function(a, b) return #appearances[a] > #appearances[b] or #appearances[a] == #appearances[b] and a < b end)
    local lines = {"REUSE"}
    for _, word in ipairs(reused) do lines[#lines + 1] = "reused " .. word .. " " .. #appearances[word] .. " " .. table.concat(appearances[word], ",") end
    return lines
end

local function summary_paragraph(templates)
    local invalid, counts, attempts, nodes = 0, {filled = 0, unfillable = 0, budget = 0}, 0, 0
    for _, template in ipairs(templates) do
        if template.error then invalid = invalid + 1
        else
            counts[template.final.outcome] = counts[template.final.outcome] + 1
            attempts = attempts + #template.attempts
            for _, attempt in ipairs(template.attempts) do nodes = nodes + attempt.nodes end
        end
    end
    return {string.format("SUMMARY templates=%d invalid=%d filled=%d unfillable=%d budget=%d attempts=%d nodes=%d", #templates, invalid, counts.filled, counts.unfillable, counts.budget, attempts, nodes)}
end

local function write_lines(name, lines)
    local file = assert(io.open("output/" .. name, "w"))
    for _, line in ipairs(lines) do file:write(line, "\n") end
    file:close()
end

local function write_paragraphs(name, paragraphs)
    local lines = {}
    for _, paragraph in ipairs(paragraphs) do
        if #lines > 0 then lines[#lines + 1] = "" end
        extend(lines, paragraph)
    end
    write_lines(name, lines)
end

local function main()
    local settings = read_settings(read_lines("params.txt"))
    local word_list = WordList.new(read_lines("words.txt"))
    local index = word_list.index
    local clue_book = ClueBook.new(read_lines("clues.txt"), word_list.scores)
    local templates, valid, filled, names = {}, {}, {}, {}
    for _, block in ipairs(split_blocks(read_lines("templates.txt"))) do
        local template = Template.new(block, settings)
        template:process(names, index, clue_book, settings.relax_step)
        names[block.name] = true
        templates[#templates + 1] = template
        if template.error == nil then
            valid[#valid + 1] = template
            if template:is_filled() then filled[#filled + 1] = template end
        end
    end
    local grids, clues, statistics = {}, {}, {}
    for _, template in ipairs(templates) do grids[#grids + 1] = template:grid_paragraph() end
    for _, template in ipairs(valid) do
        clues[#clues + 1] = template:clue_paragraph(index.scores)
        statistics[#statistics + 1] = template:stats_paragraph(index, settings.weak_score)
    end
    extend(statistics, {ranking_paragraph(filled, index.scores), reuse_paragraph(filled), summary_paragraph(templates)})
    os.execute("mkdir -p output")
    write_paragraphs("grid.txt", grids)
    write_paragraphs("clues.txt", clues)
    write_paragraphs("search_stats.txt", statistics)
    local report_lines = word_list:report_lines()
    extend(report_lines, clue_book:report_lines())
    write_lines("wordlist.txt", report_lines)
end

main()
