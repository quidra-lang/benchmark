local source_directory = arg[0]:match("^(.*[/\\])") or "./"
package.path = source_directory .. "?.lua;" .. package.path
local parser = require("tz_parser")
local days = require("day_rules")
local transitions = require("transitions")
local resolver = require("resolver")
local report = require("report")
local field_counts = {Rule = {10, 10}, Zone = {5, 9}, continuation = {3, 7}, Link = {3, 3}}
local argument_types = {TOUTC = {"zone", "local"}, TOLOCAL = {"zone", "ut"}, CONVERT = {"zone", "zone", "local"},
    OFFSET = {"zone", "ut"}, TRANSITIONS = {"zone", "year", "year"}, DURATION = {"zone", "local", "local"}}

local function read_lines(path)
    local lines = {}
    for line in io.lines(path) do lines[#lines + 1] = line end
    return lines
end
local function slice(values, first)
    local result = {}
    for index = first, #values do result[#result + 1] = values[index] end
    return result
end
local function extend(target, values) for _, value in ipairs(values) do target[#target + 1] = value end end
local function year_start(year) return days.day_number(year, 1, 1) * 86400 end
local function clock_seconds(text) return tonumber(text:sub(1, 2)) * 3600 + tonumber(text:sub(4, 5)) * 60 end
local function names_or_none(names, separator) return #names == 0 and "none" or table.concat(names, separator) end
local function indented(lines)
    local result = {lines[1]}
    for index = 2, #lines do result[index] = "  " .. lines[index] end
    return result
end
local function merge_intervals(intervals)
    table.sort(intervals, function(a, b) return a[1] < b[1] or a[1] == b[1] and a[2] < b[2] end)
    local merged = {}
    for _, interval in ipairs(intervals) do
        local last = merged[#merged]
        if last and interval[1] <= last[2] then last[2] = math.max(last[2], interval[2])
        else merged[#merged + 1] = {interval[1], interval[2]} end
    end
    return merged
end
local function intersect_intervals(first, second)
    local pieces = {}
    for _, one in ipairs(first) do
        for _, other in ipairs(second) do
            local low, high = math.max(one[1], other[1]), math.min(one[2], other[2])
            if low < high then pieces[#pieces + 1] = {low, high} end
        end
    end
    return merge_intervals(pieces)
end

local SourceLine = {}
SourceLine.__index = SourceLine
function SourceLine.new(number, content)
    local fields = parser.split_fields(content)
    local known = fields[1] == "Rule" or fields[1] == "Zone" or fields[1] == "Link"
    local kind = parser.is_continuation(content) and "continuation" or known and fields[1] or "unknown"
    return setmetatable({number = number, fields = fields, kind = kind, position = 0, field_error = false}, SourceLine)
end
function SourceLine:accepts_continuation()
    return self.kind == "Zone" and #self.fields >= 6 or self.kind == "continuation" and #self.fields >= 4
end
local Block = {}
Block.__index = Block
function Block.new(first)
    local self = setmetatable({name = first.fields[2], number = first.number, lines = {}, defined = false}, Block)
    self:add(first)
    return self
end
function Block:add(line) line.block, line.position = self, #self.lines + 1 self.lines[#self.lines + 1] = line end

local ZoneLine = {}
ZoneLine.__index = ZoneLine
function ZoneLine.new(fields)
    local self = setmetatable({stdoff = parser.parse_stdoff(fields[1]), rules_text = fields[2], save = 0,
        format_text = fields[3], start = days.NEG_INFINITY, ending = days.POS_INFINITY}, ZoneLine)
    if self.rules_text:match("^[0-9]") then self.save = parser.parse_save(self.rules_text)
    elseif self.rules_text ~= "-" then self.rule_set = self.rules_text end
    parser.check_format(self.format_text, self.rule_set ~= nil)
    if #fields > 3 then self.until_value = parser.parse_until(slice(fields, 4)) end
    return self
end
function ZoneLine:rules_notation()
    if self.rule_set then return self.rule_set end
    return self.rules_text == "-" and "-" or report.clock_text(self.save)
end
function ZoneLine:until_notation()
    local value = self.until_value
    return value.year_text .. " " .. value.month_text .. " " .. value.day_text .. " " .. report.clock_text(value.time) .. value.time_type
end
local Zone = {}
Zone.__index = Zone
function Zone.new(name, lines) return setmetatable({name = name, lines = lines, aliases = {}, applied = {}}, Zone) end
function Zone:rule_sets()
    local names, seen = {}, {}
    for _, line in ipairs(self.lines) do if line.rule_set and not seen[line.rule_set] then names[#names + 1] = line.rule_set seen[line.rule_set] = true end end
    return names
end
function Zone:line_number_at(time)
    for number, line in ipairs(self.lines) do if line.start <= time and time < line.ending then return number end end
end
local function parse_rule(line)
    local fields = line.fields
    local from_year = parser.parse_year(fields[3])
    local to_year = parser.parse_to(fields[4], from_year)
    if fields[5] ~= "-" then parser.field_error("syntax error") end
    local month = parser.parse_month(fields[6])
    local day = parser.parse_day_spec(fields[7], month)
    local at, at_type = parser.parse_time(fields[8])
    local save = parser.parse_save(fields[9])
    local letter = parser.parse_letter(fields[10])
    return {number = line.number, fields = fields, name = fields[2], from_year = from_year, to_year = to_year,
        month = month, day = day, at = at, at_type = at_type, save = save, letter = letter}
end
local function standard_letter(instances)
    for _, instance in ipairs(instances) do if instance.rule.save == 0 then return instance.rule.letter end end
    return ""
end

local Database = {}
Database.__index = Database
function Database.new(raw_lines)
    local self = setmetatable({lines = {}, blocks = {}, rules = {}, rule_order = {}, sequences = {}, zones = {}, aliases = {}}, Database)
    for number, raw in ipairs(raw_lines) do
        local content = parser.line_content(raw)
        if content ~= "" then self.lines[#self.lines + 1] = SourceLine.new(number, content) end
    end
    self:assemble_blocks()
    for _, line in ipairs(self.lines) do
        local ok, problem = pcall(function() self:parse_fields(line) end)
        if not ok then
            if type(problem) ~= "table" or not problem.field_error then error(problem, 0) end
            line.field_error, line.error = true, problem.field_error
        end
    end
    local zone_names = {}
    for _, line in ipairs(self.lines) do if line.zone_line then line.error = self:structural_error(line, zone_names) end end
    for _, name in ipairs(self.rule_order) do self.sequences[name] = transitions.instance_sequence(self.rules[name]) end
    for _, block in ipairs(self.blocks) do
        block.defined = true
        for _, line in ipairs(block.lines) do if line.error then block.defined = false end end
        if block.defined then self:define_zone(block) end
    end
    for _, line in ipairs(self.lines) do if line.kind == "Link" and line.error == nil then self:register_link(line) end end
    return self
end
function Database:assemble_blocks()
    local previous
    for _, line in ipairs(self.lines) do
        if line.kind == "Zone" then self.blocks[#self.blocks + 1] = Block.new(line)
        elseif line.kind == "continuation" and previous and previous.block and previous:accepts_continuation() then previous.block:add(line) end
        previous = line
    end
end
function Database:parse_fields(line)
    if line.kind == "unknown" or line.kind == "continuation" and not line.block then parser.field_error("syntax error") end
    local limits = field_counts[line.kind]
    if #line.fields < limits[1] or #line.fields > limits[2] then parser.field_error("syntax error") end
    if line.kind == "Rule" then
        local rule = parse_rule(line)
        if not self.rules[rule.name] then self.rules[rule.name] = {} self.rule_order[#self.rule_order + 1] = rule.name end
        self.rules[rule.name][#self.rules[rule.name] + 1] = rule
    elseif line.kind == "Zone" then line.zone_line = ZoneLine.new(slice(line.fields, 3))
    elseif line.kind == "continuation" then line.zone_line = ZoneLine.new(line.fields) end
end
function Database:structural_error(line, zone_names)
    local zone_line = line.zone_line
    if line.kind == "Zone" then
        local name = line.fields[2]
        if zone_names[name] then return "duplicate zone " .. name end
        zone_names[name] = true
    end
    if zone_line.rule_set and not self.rules[zone_line.rule_set] then return "unknown rule " .. zone_line.rule_set end
    if not zone_line.until_value then return nil end
    local block_lines = line.block.lines
    if line.kind == "continuation" then
        local previous = block_lines[line.position - 1]
        if not previous.field_error and zone_line.until_value.value <= previous.zone_line.until_value.value then return "until not increasing" end
    end
    if line.position == #block_lines then return "missing continuation" end
end
function Database:line_switches(zone, line)
    local until_value = line.until_value
    if not line.rule_set then
        if until_value then line.ending = until_value.value - transitions.adjustment(until_value.time_type, line.stdoff, line.save) end
        return {{time = line.start, save = line.save, letter = ""}}
    end
    local instances = self.sequences[line.rule_set]
    local run = transitions.run_instances(instances, line.stdoff, line.start, until_value)
    line.ending = run.ending
    local first = {time = line.start, save = 0, letter = standard_letter(instances)}
    if #run.pre_start > 0 then local last = run.pre_start[#run.pre_start] first.save, first.letter = last.save, last.letter end
    local switches = {first}
    for _, item in ipairs(run.applied) do
        local rule = item.rule
        switches[#switches + 1] = {time = item.time, save = rule.save, letter = rule.letter}
        zone.applied[rule.number] = (zone.applied[rule.number] or 0) + 1
    end
    return switches
end
function Database:define_zone(block)
    local lines = {} for _, line in ipairs(block.lines) do lines[#lines + 1] = line.zone_line end
    local zone, periods, start = Zone.new(block.name, lines), {}, days.NEG_INFINITY
    for _, line in ipairs(zone.lines) do
        line.start = start
        for _, switch in ipairs(self:line_switches(zone, line)) do
            local period = resolver.period(switch.time, line.stdoff + switch.save, switch.save ~= 0, transitions.abbreviation(line.format_text, switch.save, switch.letter))
            local previous = periods[#periods]
            if not previous or previous.offset ~= period.offset or previous.dst ~= period.dst or previous.abbreviation ~= period.abbreviation then periods[#periods + 1] = period end
        end
        start = line.ending
    end
    zone.timeline = resolver.Timeline.new(periods)
    self.zones[zone.name] = zone
end
function Database:register_link(line)
    local target, alias = line.fields[2], line.fields[3]
    if not self.zones[target] then line.error = "unknown link target " .. target
    elseif self.zones[alias] or self.aliases[alias] then line.error = "duplicate link " .. alias
    else self.aliases[alias] = self.zones[target] self.zones[target].aliases[#self.zones[target].aliases + 1] = alias end
end
function Database:find_zone(word) return self.zones[word] or self.aliases[word] end
function Database:error_lines()
    local lines = {}
    for _, line in ipairs(self.lines) do if line.error then lines[#lines + 1] = "line " .. line.number .. ": " .. line.error end end
    return lines
end

local function offset_shift(timeline, index) return timeline.periods[index].offset - timeline.periods[index - 1].offset end
local function transitions_between(timeline, low, high)
    local indices = {}
    for index = 2, #timeline.periods do if low <= timeline.periods[index].start and timeline.periods[index].start < high then indices[#indices + 1] = index end end
    return indices
end
local function change_at(timeline, index) return report.change_text(timeline.periods[index].start, timeline.periods[index - 1], timeline.periods[index]) end
local function transition_line(timeline, index)
    local time, shift = timeline.periods[index].start, offset_shift(timeline, index)
    local kind = shift > 0 and "gap " .. report.duration_text(shift) or shift < 0 and "overlap " .. report.duration_text(-shift) or "no shift"
    return change_at(timeline, index) .. " (local " .. report.local_text(time + timeline.periods[index - 1].offset) .. " -> " .. report.local_text(time + timeline.periods[index].offset) .. ", " .. kind .. ")"
end
local function shifts_text(timeline, indices)
    local gaps, overlaps, unchanged = 0, 0, 0
    for _, index in ipairs(indices) do
        local shift = offset_shift(timeline, index)
        if shift > 0 then gaps = gaps + 1 elseif shift < 0 then overlaps = overlaps + 1 else unchanged = unchanged + 1 end
    end
    return "gaps " .. gaps .. ", overlaps " .. overlaps .. ", no shift " .. unchanged
end
local function candidate_text(timeline, local_time, index)
    local period = timeline.periods[index]
    return report.ut_text(local_time - period.offset) .. " (" .. report.state_text(period) .. ")"
end
local function chosen_candidate(candidates, option)
    if #candidates == 1 or #candidates == 2 and option == "EARLIER" then return candidates[1] end
    if #candidates == 2 and option == "LATER" then return candidates[2] end
end
local function unresolved_text(timeline, local_time, candidates)
    if #candidates > 0 then
        local texts = {}
        for _, index in ipairs(candidates) do texts[#texts + 1] = candidate_text(timeline, local_time, index) end
        return "AMBIGUOUS " .. table.concat(texts, " or ")
    end
    local index = timeline:skipping_transition(local_time)
    local time = timeline.periods[index].start
    return "NONEXISTENT gap " .. report.local_text(time + timeline.periods[index - 1].offset) .. " to " .. report.local_text(time + timeline.periods[index].offset) .. " at " .. report.ut_text(time)
end
local function working_hours(timeline, start, ending)
    local pieces = {}
    local first, last = timeline:nearby(start, ending)
    for index = first, last do
        local period = timeline.periods[index]
        local low, high = math.max(start - period.offset, period.start), math.min(ending - period.offset, timeline:end_of(index))
        if low < high then pieces[#pieces + 1] = {low, high} end
    end
    return merge_intervals(pieces)
end
local function parse_value(kind, word)
    local year = tonumber(word:sub(1, 4))
    if year < 1800 or year > 2099 then return nil end
    if kind == "year" then return year end
    local month, day = tonumber(word:sub(6, 7)), tonumber(word:sub(9, 10))
    if month < 1 or month > 12 or day < 1 or day > days.days_in_month(year, month) then return nil end
    if kind == "date" then return days.day_number(year, month, day) end
    local hour, minute, second = tonumber(word:sub(12, 13)), tonumber(word:sub(15, 16)), tonumber(word:sub(18, 19))
    if hour > 23 or minute > 59 or second > 59 then return nil end
    return days.time_value(year, month, day, hour, minute, second)
end

local QueryRunner = {}
QueryRunner.__index = QueryRunner
function QueryRunner.new(database, work_start, work_end)
    return setmetatable({database = database, work_start = work_start, work_end = work_end, answers = {}, transition_blocks = {}}, QueryRunner)
end
local function query_error(message) error({query_error = message}, 0) end
function QueryRunner:argument(kind, word)
    if kind == "zone" then
        local zone = self.database:find_zone(word)
        if not zone then query_error("unknown zone " .. word) end
        return zone
    end
    local value = parse_value(kind, word)
    if value == nil then query_error("invalid value " .. word) end
    return value
end
function QueryRunner:run(line)
    local words = parser.split_fields(line)
    local command = table.remove(words, 1)
    local option
    if (command == "TOUTC" or command == "CONVERT") and (words[#words] == "EARLIER" or words[#words] == "LATER") then option = table.remove(words) end
    local kinds = argument_types[command]
    if command == "MEETING" then kinds = {"date"} for index = 2, #words do kinds[index] = "zone" end end
    local ok, result = pcall(function()
        local values = {}
        for index, kind in ipairs(kinds) do values[index] = self:argument(kind, words[index]) end
        return self:answer(line, command, values, words, option)
    end)
    if not ok then
        if type(result) ~= "table" or not result.query_error then error(result, 0) end
        result = "ERROR " .. result.query_error
    end
    self.answers[#self.answers + 1] = line .. " => " .. result
end
function QueryRunner:answer(line, command, values, words, option)
    if command == "TOUTC" then return self:to_utc(values[1], values[2], option) end
    if command == "TOLOCAL" then return self:to_local(values[1], values[2]) end
    if command == "CONVERT" then return self:convert(values[1], values[2], values[3], option) end
    if command == "OFFSET" then return self:offset(values[1], values[2]) end
    if command == "TRANSITIONS" then return self:list_transitions(line, values[1], values[2], values[3]) end
    if command == "DURATION" then return self:duration(values[1], slice(values, 2), slice(words, 2)) end
    return self:meeting(values[1], slice(values, 2), slice(words, 2))
end
function QueryRunner:to_utc(zone, local_time, option)
    local candidates = zone.timeline:candidates(local_time)
    local index = chosen_candidate(candidates, option)
    return index and candidate_text(zone.timeline, local_time, index) or unresolved_text(zone.timeline, local_time, candidates)
end
function QueryRunner:to_local(zone, time)
    local period = zone.timeline:period_at(time)
    return report.local_text(time + period.offset) .. " (" .. report.state_text(period) .. ")"
end
function QueryRunner:convert(source, target, local_time, option)
    local candidates = source.timeline:candidates(local_time)
    local index = chosen_candidate(candidates, option)
    if not index then return unresolved_text(source.timeline, local_time, candidates) end
    local time = local_time - source.timeline.periods[index].offset
    local period = target.timeline:period_at(time)
    local target_local = time + period.offset
    local shift = target_local // 86400 - local_time // 86400
    return report.local_text(target_local) .. " (" .. report.state_text(period) .. ") at " .. report.ut_text(time) .. ", day shift " .. (shift > 0 and "+" or "") .. shift
end
function QueryRunner:offset(zone, time)
    local timeline = zone.timeline
    local index = timeline:index_at(time)
    local text = report.state_text(timeline.periods[index])
    if index >= 2 then text = text .. " since " .. report.ut_text(timeline.periods[index].start) end
    if index < #timeline.periods then text = text .. " until " .. report.ut_text(timeline.periods[index + 1].start) end
    return text
end
function QueryRunner:list_transitions(line, zone, first_year, last_year)
    if first_year > last_year then query_error("invalid range") end
    local timeline = zone.timeline
    local selected = transitions_between(timeline, year_start(first_year), year_start(last_year + 1))
    local block = {line}
    for _, index in ipairs(selected) do block[#block + 1] = transition_line(timeline, index) end
    block[#block + 1] = shifts_text(timeline, selected)
    self.transition_blocks[#self.transition_blocks + 1] = block
    return "transitions: " .. #selected
end
function QueryRunner:duration(zone, local_times, words)
    local periods, timeline = {}, zone.timeline
    for position, local_time in ipairs(local_times) do
        local candidates = timeline:candidates(local_time)
        if #candidates == 2 then return "AMBIGUOUS " .. words[position] end
        if #candidates == 0 then return "NONEXISTENT " .. words[position] end
        periods[position] = timeline.periods[candidates[1]]
    end
    local elapsed = (local_times[2] - periods[2].offset) - (local_times[1] - periods[1].offset)
    return elapsed .. " s (" .. report.duration_text(elapsed) .. "), wall clock " .. report.duration_text(local_times[2] - local_times[1])
        .. ", offset change " .. report.offset_text(periods[2].offset - periods[1].offset)
end
function QueryRunner:meeting(day, zones, words)
    local start, ending = day * 86400 + self.work_start, day * 86400 + self.work_end
    local common = working_hours(zones[1].timeline, start, ending)
    for index = 2, #zones do common = intersect_intervals(common, working_hours(zones[index].timeline, start, ending)) end
    if #common == 0 then return "NONE" end
    local parts = {}
    for _, interval in ipairs(common) do
        local members = {}
        for index, zone in ipairs(zones) do
            local period = zone.timeline:period_at(interval[1])
            members[#members + 1] = words[index] .. " " .. report.local_text(interval[1] + period.offset) .. " " .. period.abbreviation
        end
        parts[#parts + 1] = report.ut_text(interval[1]) .. " to " .. report.ut_text(interval[2]) .. " (" .. report.duration_text(interval[2] - interval[1]) .. ") [" .. table.concat(members, ", ") .. "]"
    end
    return table.concat(parts, "; ")
end

local function rule_text(rule)
    local fields = rule.fields
    return "rule " .. rule.name .. " " .. fields[3] .. " " .. fields[4] .. " " .. fields[6] .. " " .. fields[7] .. " "
        .. report.clock_text(rule.at) .. rule.at_type .. " " .. report.clock_text(rule.save) .. " " .. fields[10]
end
local function database_block(database)
    local rule_count, valid_rules, link_count, valid_links, defined, zone_lines = 0, 0, 0, 0, 0, 0
    for _, line in ipairs(database.lines) do
        if line.kind == "Rule" then rule_count = rule_count + 1 if not line.error then valid_rules = valid_rules + 1 end end
        if line.kind == "Link" then link_count = link_count + 1 if not line.error then valid_links = valid_links + 1 end end
    end
    local used, usage, invalid, unused = {}, {}, {}, {}
    for _, zone in pairs(database.zones) do
        defined, zone_lines = defined + 1, zone_lines + #zone.lines
        for _, name in ipairs(zone:rule_sets()) do used[name] = true usage[name] = (usage[name] or 0) + 1 end
    end
    for _, name in ipairs(database.rule_order) do if not used[name] then unused[#unused + 1] = name end end
    for _, block in ipairs(database.blocks) do if not block.defined then invalid[#invalid + 1] = block.name .. " (line " .. block.number .. ")" end end
    local lines = {"DATABASE", "rule lines: " .. valid_rules .. " valid, " .. (rule_count - valid_rules) .. " invalid",
        "zones: " .. defined .. " defined, " .. (#database.blocks - defined) .. " invalid", "zone lines: " .. zone_lines .. " in defined zones",
        "links: " .. valid_links .. " defined, " .. (link_count - valid_links) .. " invalid", "errors: " .. #database:error_lines(),
        "unused rules: " .. names_or_none(unused, " "), "invalid zones: " .. names_or_none(invalid, ", ")}
    for _, name in ipairs(database.rule_order) do
        local rules, first, last, maximum = database.rules[name], 2099, 1800, false
        for _, rule in ipairs(rules) do
            first, last = math.min(first, rule.from_year), math.max(last, rule.to_year)
            if rule.fields[4] == "max" then maximum = true end
        end
        lines[#lines + 1] = "rule set " .. name .. ": lines " .. #rules .. ", years " .. first .. "-" .. (maximum and "max" or tostring(last)) .. ", zones " .. (usage[name] or 0)
    end
    return lines
end
local function dst_lines(timeline, reference)
    local indices, first_year, last_year = {}, nil, nil
    for index, period in ipairs(timeline.periods) do
        if period.dst then
            indices[#indices + 1] = index
            local year = days.split_time(period.start)
            first_year, last_year = first_year and math.min(first_year, year) or year, last_year and math.max(last_year, year) or year
        end
    end
    local lines = {first_year and "dst years: " .. first_year .. "-" .. last_year or "dst years: none"}
    local year = days.split_time(reference)
    local low, high, pieces = year_start(year), year_start(year + 1), {}
    for _, index in ipairs(indices) do
        local start, ending = math.max(low, timeline.periods[index].start), math.min(high, timeline:end_of(index))
        if start < ending then pieces[#pieces + 1] = {start, ending} end
    end
    local total = 0
    for _, interval in ipairs(merge_intervals(pieces)) do
        lines[#lines + 1] = "dst period: " .. report.ut_text(interval[1]) .. " to " .. report.ut_text(interval[2]) .. " (" .. report.duration_text(interval[2] - interval[1]) .. ")"
        total = total + interval[2] - interval[1]
    end
    lines[#lines + 1] = "dst total " .. year .. ": " .. report.duration_text(total)
    return lines
end
local function zone_block(database, zone, reference)
    local timeline = zone.timeline
    local lines = {"ZONE " .. zone.name, "aliases: " .. names_or_none(zone.aliases, " ")}
    for number, line in ipairs(zone.lines) do
        local text = "line " .. number .. ": " .. report.offset_text(line.stdoff) .. " " .. line:rules_notation() .. " " .. line.format_text
        if number >= 2 then text = text .. " from " .. report.ut_text(line.start) end
        if line.until_value then text = text .. " until " .. line:until_notation() .. " = " .. report.ut_text(line.ending) end
        lines[#lines + 1] = text .. ", transitions " .. #transitions_between(timeline, line.start, line.ending)
    end
    for _, name in ipairs(zone:rule_sets()) do
        for _, rule in ipairs(database.rules[name]) do lines[#lines + 1] = rule_text(rule) .. ", applied " .. (zone.applied[rule.number] or 0) end
    end
    local minimum, maximum = timeline.periods[1].offset, timeline.periods[1].offset
    local state_counts, state_order = {}, {}
    for _, period in ipairs(timeline.periods) do
        minimum, maximum = math.min(minimum, period.offset), math.max(maximum, period.offset)
        local state = report.state_text(period)
        if not state_counts[state] then state_order[#state_order + 1] = state state_counts[state] = 0 end
        state_counts[state] = state_counts[state] + 1
    end
    lines[#lines + 1] = "offset range: " .. report.offset_text(minimum) .. " to " .. report.offset_text(maximum)
    for _, state in ipairs(state_order) do lines[#lines + 1] = "state " .. state .. ", periods " .. state_counts[state] end
    local index = timeline:index_at(reference)
    local period = timeline.periods[index]
    lines[#lines + 1] = "reference: " .. report.local_text(reference + period.offset) .. " (" .. report.state_text(period) .. "), line " .. zone:line_number_at(reference)
    lines[#lines + 1] = "previous transition: " .. (index >= 2 and change_at(timeline, index) or "none")
    lines[#lines + 1] = "next transition: " .. (index < #timeline.periods and change_at(timeline, index + 1) or "none")
    local every = {} for position = 2, #timeline.periods do every[#every + 1] = position end
    lines[#lines + 1] = "transitions: " .. #every .. ", " .. shifts_text(timeline, every)
    extend(lines, dst_lines(timeline, reference))
    return lines
end

local function main()
    local database = Database.new(read_lines("input/tzdata.txt"))
    local params = read_lines("input/params.txt")
    local reference = parse_value("ut", parser.split_fields(params[1])[2])
    local workday = parser.split_fields(params[2])
    local runner = QueryRunner.new(database, clock_seconds(workday[2]), clock_seconds(workday[3]))
    for _, line in ipairs(read_lines("input/queries.txt")) do runner:run(line) end
    local blocks, names = {indented(database_block(database))}, {}
    for name in pairs(database.zones) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do blocks[#blocks + 1] = indented(zone_block(database, database.zones[name], reference)) end
    os.execute("mkdir -p output")
    report.write_lines("output/answers.txt", runner.answers)
    report.write_lines("output/errors.txt", database:error_lines())
    report.write_blocks("output/transitions.txt", runner.transition_blocks)
    report.write_blocks("output/zone_summary.txt", blocks)
end

main()
