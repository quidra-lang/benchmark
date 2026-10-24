local function fail(message)
    error({command_error = true, message = message}, 0)
end

local function load_error(line, message)
    error({load_error = true, line = line, message = message}, 0)
end

local function split(text, separator)
    local parts, start = {}, 1
    while true do
        local position = text:find(separator, start, true)
        if not position then break end
        parts[#parts + 1] = text:sub(start, position - 1)
        start = position + #separator
    end
    parts[#parts + 1] = text:sub(start)
    return parts
end

local known_fields = split("author editor title journal booktitle edition volume number pages publisher institution school address howpublished month year doi note", " ")
local small_words = {}
for _, word in ipairs(split("a an and as at but by for from in into nor of on or over per so the to up via with yet", " ")) do small_words[word] = true end
local month_names = split("January February March April May June July August September October November December", " ")
local month_short = split("Jan. Feb. Mar. Apr. May June July Aug. Sep. Oct. Nov. Dec.", " ")
local known = {}
for _, field in ipairs(known_fields) do known[field] = true end

local function ascii_less(a, b)
    for i = 1, math.min(#a, #b) do
        local x, y = a:byte(i), b:byte(i)
        if x ~= y then return x < y end
    end
    return #a < #b
end

local function sorted_keys(values)
    local keys = {}
    for key in pairs(values) do keys[#keys + 1] = key end
    table.sort(keys, ascii_less)
    return keys
end

local function lower(text)
    return (text:gsub("[A-Z]", function(c) return string.char(c:byte() + 32) end))
end

local function upper(text)
    return (text:gsub("[a-z]", function(c) return string.char(c:byte() - 32) end))
end

local function plain(text) return (text:gsub("[{}]", "")) end
local function letters(text) return lower((text:gsub("[^A-Za-z]", ""))) end
local function digits(text) return text:match("^[0-9]+$") ~= nil end
local function is_letter(c) return c:match("^[A-Za-z]$") ~= nil end
local function trim(text) return (text:gsub("^ +", ""):gsub(" +$", "")) end

local function split_top(text, separator)
    local parts, depth, start, i = {}, 0, 1, 1
    while i <= #text do
        if depth == 0 and text:sub(i, i + #separator - 1) == separator then
            parts[#parts + 1] = text:sub(start, i - 1)
            i = i + #separator
            start = i
        else
            local c = text:sub(i, i)
            if c == "{" then depth = depth + 1 end
            if c == "}" then depth = depth - 1 end
            i = i + 1
        end
    end
    parts[#parts + 1] = text:sub(start)
    return parts
end

local function accent(text, i)
    if i + 1 > #text or text:sub(i, i) ~= "\\" then return nil end
    local command = text:sub(i + 1, i + 1)
    if command == "&" then return {value = "&", length = 2} end
    local symbol = ("'\"`^~=."):find(command, 1, true) ~= nil
    if i + 4 <= #text and (symbol or ("cuvH"):find(command, 1, true)) and
        text:sub(i + 2, i + 2) == "{" and is_letter(text:sub(i + 3, i + 3)) and text:sub(i + 4, i + 4) == "}" then
        return {value = text:sub(i + 3, i + 3), length = 5}
    end
    if symbol and i + 2 <= #text and is_letter(text:sub(i + 2, i + 2)) then
        return {value = text:sub(i + 2, i + 2), length = 3}
    end
end

local function normalize(text)
    local result, i = {}, 1
    while i <= #text do
        local wrapped = text:sub(i, i) == "{" and accent(text, i + 1) or nil
        if wrapped and text:sub(i + wrapped.length + 1, i + wrapped.length + 1) == "}" then
            result[#result + 1] = wrapped.value
            i = i + wrapped.length + 2
        else
            local direct = accent(text, i)
            if direct then
                result[#result + 1] = direct.value
                i = i + direct.length
            else
                result[#result + 1] = text:sub(i, i)
                i = i + 1
            end
        end
    end
    return trim((table.concat(result):gsub("~", " "):gsub(" +", " ")))
end

local function title_case(text, style)
    if style == "IEEE" then return text end
    if style == "APA" then
        local result, depth = {}, 0
        for i = 1, #text do
            local c = text:sub(i, i)
            if c == "{" then depth = depth + 1
            elseif c == "}" then depth = depth - 1
            elseif depth == 0 and is_letter(c) then
                c = (i == 1 or i >= 3 and text:sub(i - 2, i - 1) == ": ") and upper(c) or lower(c)
            end
            result[#result + 1] = c
        end
        return table.concat(result)
    end
    local words = split_top(text, " ")
    for i, word in ipairs(words) do
        if word:sub(1, 1) ~= "{" then
            local make_lower = i > 1 and i < #words and words[i - 1]:sub(-1) ~= ":" and small_words[letters(word)]
            local result, depth, found_letter = {}, 0, false
            for j = 1, #word do
                local c = word:sub(j, j)
                if c == "{" then depth = depth + 1
                elseif c == "}" then depth = depth - 1
                elseif is_letter(c) then
                    if make_lower then
                        if depth == 0 then c = lower(c) end
                    elseif not found_letter then
                        if depth == 0 then c = upper(c) end
                        found_letter = true
                    end
                end
                result[#result + 1] = c
            end
            words[i] = table.concat(result)
        end
    end
    return table.concat(words, " ")
end

local function list_names(names, conjunction, list_b)
    if #names == 1 then return names[1] end
    if list_b and #names == 2 then return names[1] .. " " .. conjunction .. " " .. names[2] end
    return table.concat(names, ", ", 1, #names - 1) .. ", " .. conjunction .. " " .. names[#names]
end

local Person = {}
Person.__index = Person

function Person.parse(text)
    local parts = split_top(text, ",")
    for i, part in ipairs(parts) do parts[i] = trim(part) end
    local words = split_top(parts[1], " ")
    local first_lower, last_lower = nil, 0
    for i = 1, #words - 1 do
        if words[i]:match("^[a-z]") then
            first_lower = first_lower or i
            last_lower = i
        end
    end
    local first, von, last, jr = "", "", "", ""
    if #parts == 1 then
        if first_lower then
            first = table.concat(words, " ", 1, first_lower - 1)
            von = table.concat(words, " ", first_lower, last_lower)
            last = table.concat(words, " ", last_lower + 1)
        else
            first = table.concat(words, " ", 1, #words - 1)
            last = words[#words]
        end
    else
        first = parts[#parts]
        von = table.concat(words, " ", 1, last_lower)
        last = table.concat(words, " ", last_lower + 1)
        if #parts == 3 then jr = parts[2] end
    end
    return setmetatable({first = first, von = von, last = last, jr = jr}, Person)
end

function Person:same(other)
    return self.first == other.first and self.von == other.von and self.last == other.last and self.jr == other.jr
end

function Person:surname() return plain(self.von == "" and self.last or self.von .. " " .. self.last) end

function Person:initials()
    local words = {}
    for word in plain(self.first):gmatch("[^ ]+") do
        local pieces = {}
        for _, piece in ipairs(split(word, "-")) do pieces[#pieces + 1] = upper(piece:match("[A-Za-z]")) .. "." end
        words[#words + 1] = table.concat(pieces, "-")
    end
    return table.concat(words, " ")
end

function Person:notation(inverted, abbreviated)
    local given = abbreviated and self:initials() or plain(self.first)
    local result = self:surname()
    if self.first ~= "" then result = inverted and result .. ", " .. given or given .. " " .. result end
    if self.jr ~= "" then result = result .. ", " .. plain(self.jr) end
    return result
end

local NameList = {}
NameList.__index = NameList

function NameList.parse(text)
    local parts = split_top(text, " and ")
    local et_al = parts[#parts] == "others"
    if et_al then table.remove(parts) end
    local names = {}
    for i, part in ipairs(parts) do names[i] = Person.parse(part) end
    return setmetatable({names = names, et_al = et_al}, NameList)
end

function NameList:single() return #self.names == 1 and not self.et_al end
function NameList:same(other)
    if self.et_al ~= other.et_al or #self.names ~= #other.names then return false end
    for i, name in ipairs(self.names) do if not name:same(other.names[i]) then return false end end
    return true
end

function NameList:authors(style)
    local values = {}
    for i, name in ipairs(self.names) do
        values[i] = name:notation(style == "APA" or style ~= "IEEE" and i == 1, style == "APA" or style == "IEEE")
    end
    if style == "APA" then
        if self.et_al then return table.concat(values, ", ") .. ", et al." end
        if #values > 20 then return table.concat(values, ", ", 1, 19) .. ", . . . " .. values[#values] end
        return list_names(values, "&")
    elseif style == "IEEE" then
        if self.et_al or #values >= 7 then return values[1] .. " et al." end
        return list_names(values, "and", true)
    elseif style == "CHICAGO" then
        if self.et_al or #values >= 11 then return table.concat(values, ", ", 1, math.min(7, #values)) .. ", et al." end
        return list_names(values, "and")
    end
    if self.et_al or #values >= 3 then return values[1] .. ", et al." end
    return list_names(values, "and")
end

function NameList:editors(style)
    local values = {}
    for i, name in ipairs(self.names) do values[i] = name:notation(false, style == "APA" or style == "IEEE") end
    if self.et_al then return values[1] .. " et al." end
    return list_names(values, style == "APA" and "&" or "and", true)
end

local Entry = {}
Entry.__index = Entry

function Entry.new(kind, key, fields)
    local entry = setmetatable({kind = kind, key = key, fields = fields, suffix = ""}, Entry)
    entry.authors = fields.author and NameList.parse(fields.author) or nil
    entry.editors = fields.editor and NameList.parse(fields.editor) or nil
    entry.sort_last = lower(plain(entry:primary().names[1].last))
    entry.sort_title = lower(entry:value("title"))
    for _, prefix in ipairs({"a ", "an ", "the "}) do
        if entry.sort_title:sub(1, #prefix) == prefix then entry.sort_title = entry.sort_title:sub(#prefix + 1); break end
    end
    return entry
end

function Entry:primary() return self.authors or self.editors end
function Entry:value(field) return plain(self.fields[field] or "") end
function Entry:year(style) return self:value("year") .. ((style == "APA" or style == "CHICAGO") and self.suffix or "") end

function Entry.less(a, b)
    local left = {a.sort_last, a:value("year"), a.sort_title, a.key}
    local right = {b.sort_last, b:value("year"), b.sort_title, b.key}
    for i = 1, 4 do if left[i] ~= right[i] then return ascii_less(left[i], right[i]) end end
    return false
end

local required_fields = {
    article = {"author", "title", "journal", "year"}, book = {"author", "title", "publisher", "year"},
    inproceedings = {"author", "title", "booktitle", "year"}, incollection = {"author", "title", "booktitle", "publisher", "year"},
    techreport = {"author", "title", "institution", "year"}, phdthesis = {"author", "title", "school", "year"}, misc = {"author", "title", "year"},
}
local Database = {}
Database.__index = Database

function Database:evaluate(expression, line)
    local depth = 0
    for c in expression:gmatch(".") do
        if c == "{" then depth = depth + 1 end
        if c == "}" then depth = depth - 1 end
        if depth < 0 then load_error(line, "unbalanced braces") end
    end
    if depth ~= 0 then load_error(line, "unbalanced braces") end
    local values = {}
    for _, term in ipairs(split(expression, " # ")) do
        local first = term:sub(1, 1)
        if first == "{" or first == '"' then values[#values + 1] = term:sub(2, -2)
        elseif digits(term) then values[#values + 1] = term
        elseif self.macros[term] ~= nil then values[#values + 1] = self.macros[term]
        else load_error(line, "unknown macro '" .. term .. "'") end
    end
    return table.concat(values)
end

function Database:read_entry(lines, start, finish, kind, key)
    local required = required_fields[kind]
    if not required then load_error(start, "unknown type '" .. kind .. "'") end
    if self.by_key[key] then load_error(start, "duplicate key") end
    local fields = {}
    for i = start + 1, finish - 1 do
        local separator = lines[i]:find(" = ", 1, true)
        local name = lines[i]:sub(3, separator - 1)
        local expression = lines[i]:sub(separator + 3)
        if expression:sub(-1) == "," then expression = expression:sub(1, -2) end
        local value = self:evaluate(expression, i)
        if fields[name] ~= nil then load_error(i, "duplicate field '" .. name .. "'") end
        fields[name] = normalize(value)
    end
    for _, name in ipairs(required) do
        if fields[name] == nil and not (kind == "book" and name == "author" and fields.editor ~= nil) then
            load_error(finish, "missing field '" .. name .. "'")
        end
    end
    local entry = Entry.new(kind, key, fields)
    self.entries[#self.entries + 1], self.by_key[key] = entry, entry
end

function Database:assign_suffixes()
    local done = {}
    for _, entry in ipairs(self.entries) do
        if not done[entry] then
            local group = {}
            for _, other in ipairs(self.entries) do
                if entry:primary():same(other:primary()) and entry.fields.year == other.fields.year then group[#group + 1] = other end
            end
            table.sort(group, function(a, b)
                if a.sort_title ~= b.sort_title then return ascii_less(a.sort_title, b.sort_title) end
                return ascii_less(a.key, b.key)
            end)
            for i, other in ipairs(group) do
                done[other] = true
                if #group > 1 then other.suffix = string.char(96 + i) end
            end
        end
    end
end

function Database.new(lines)
    local db = setmetatable({entries = {}, by_key = {}, macros = {}, messages = {}}, Database)
    local month_keys = split("jan feb mar apr may jun jul aug sep oct nov dec", " ")
    for i, key in ipairs(month_keys) do db.macros[key] = month_names[i] end
    local i, macro_count, errors = 1, 0, 0
    while i <= #lines do
        local text = lines[i]
        if text ~= "" and text:sub(1, 1) ~= "%" then
            local name, okay, problem
            if text:sub(1, 8) == "@string{" then
                local separator = text:find(" = ", 1, true)
                name = text:sub(9, separator - 1)
                okay, problem = pcall(function()
                    local value = db:evaluate(text:sub(separator + 3, -2), i)
                    if db.macros[name] ~= nil then load_error(i, "duplicate macro") end
                    db.macros[name] = value
                    macro_count = macro_count + 1
                end)
            else
                local finish = i + 1
                while lines[finish] ~= "}" do finish = finish + 1 end
                local brace = text:find("{", 1, true)
                name = text:sub(brace + 1, -2)
                okay, problem = pcall(function() db:read_entry(lines, i, finish, text:sub(2, brace - 1), name) end)
                i = finish
            end
            if not okay then
                if type(problem) ~= "table" or not problem.load_error then error(problem, 0) end
                errors = errors + 1
                db.messages[#db.messages + 1] = "ERROR line " .. problem.line .. ": " .. name .. ": " .. problem.message
            end
        end
        i = i + 1
    end
    db:assign_suffixes()
    db.messages[#db.messages + 1] = "LOADED entries=" .. #db.entries .. " macros=" .. macro_count .. " errors=" .. errors
    return db
end

local raw_templates = {
    APA = {
        article = "{author}. ({year}). {title}. {journal}<, {volume}<({number})>><, {pages}>.< https://doi.org/{doi}>",
        book = "{author}. ({year}). {title}< ({edition})>. {publisher}.",
        inproceedings = "{author}. ({year}). {title}. In <{editor} ({eds}), >{booktitle}< ({pp})>.< {publisher}.>",
        techreport = "{author}. ({year}). {title}< (Report No. {number})>. {institution}.",
        phdthesis = "{author}. ({year}). {title} [Doctoral dissertation, {school}].",
        misc = "{author}. ({year}<, {month}>). {title}.< {howpublished}.>< {note}.>",
    },
    IEEE = {
        article = '{author}, "{title}," {journal}<, vol. {volume}><, no. {number}><, {pp}>, <{mon} >{year}<, doi: {doi}>.',
        book = "{author}, {title}<, {edition}>. <{address}: >{publisher}, {year}.",
        inproceedings = '{author}, "{title}," in {booktitle}<, {editor}, {eds}><, {address}><, {publisher}>, {year}<, {pp}>.',
        techreport = '{author}, "{title}," {institution}<, {address}>, Tech. Rep.< {number}>, {year}.',
        phdthesis = '{author}, "{title}," Ph.D. dissertation, {school}<, {address}>, {year}.',
        misc = '{author}, "{title},"< {howpublished},> <{mon} >{year}.< {note}.>',
    },
    CHICAGO = {
        article = '{author}. {year}. "{title}." {journal}< {volume}>< ({number})><: {pages}>.< https://doi.org/{doi}.>',
        book = "{author}. {year}. {title}.< {edition}.> <{address}: >{publisher}.",
        inproceedings = '{author}. {year}. "{title}." In {booktitle}<, edited by {editor}><, {pages}>.< <{address}: >{publisher}.>',
        techreport = "{author}. {year}. {title}. Technical Report< {number}>. <{address}: >{institution}.",
        phdthesis = '{author}. {year}. "{title}." PhD diss., {school}.',
        misc = "{author}. {year}. {title}.< {howpublished}.>< {note}.>",
    },
    MLA = {
        article = '{author}. "{title}." {journal}<, vol. {volume}><, no. {number}>, <{mon} >{year}<, {pp}>.< https://doi.org/{doi}.>',
        book = "{author}. {title}.< {edition},> {publisher}, {year}.",
        inproceedings = '{author}. "{title}." {booktitle},< edited by {editor},>< {publisher},> {year}<, {pp}>.',
        techreport = "{author}. {title}. {institution}, {year}.< Technical Report {number}.>",
        phdthesis = "{author}. {title}. {year}. {school}, PhD dissertation.",
        misc = "{author}. {title}.< {howpublished},> <{mon} >{year}.< {note}.>",
    },
}

local function parse_template(text)
    local i = 1
    local function read()
        local parts = {}
        while i <= #text and text:sub(i, i) ~= ">" do
            local c = text:sub(i, i)
            if c == "{" then
                local finish = text:find("}", i, true)
                parts[#parts + 1] = {kind = "field", name = text:sub(i + 1, finish - 1)}
                i = finish + 1
            elseif c == "<" then
                i = i + 1
                parts[#parts + 1] = {kind = "optional", children = read()}
                i = i + 1
            else
                parts[#parts + 1] = {kind = "literal", text = c}
                i = i + 1
            end
        end
        return parts
    end
    return read()
end

local templates = {}
for style, types in pairs(raw_templates) do
    templates[style] = {}
    for kind, text in pairs(types) do templates[style][kind] = parse_template(text) end
end

local function editor_suffix(entry, style)
    if entry.authors then return "" end
    local labels = {APA = {" (Ed.)", " (Eds.)"}, IEEE = {", Ed.", ", Eds."}, CHICAGO = {", ed.", ", eds."}, MLA = {", editor", ", editors"}}
    return labels[style][entry:primary():single() and 1 or 2]
end

local function edition(text)
    if not digits(text) then return text .. " ed." end
    local number = tonumber(text, 10)
    local suffix = "th"
    if number % 100 < 11 or number % 100 > 13 then suffix = ({[1] = "st", [2] = "nd", [3] = "rd"})[number % 10] or "th" end
    return text .. suffix .. " ed."
end

local function placeholder_values(entry, style, repeated)
    local values = {}
    for _, field in ipairs(known_fields) do values[field] = entry:value(field) end
    values.author = (repeated and "---" or entry:primary():authors(style)) .. editor_suffix(entry, style)
    values.editor = entry.editors and entry.editors:editors(style) or ""
    values.eds = entry.editors and (entry.editors:single() and "Ed." or "Eds.") or ""
    values.title, values.year = plain(title_case(entry.fields.title, style)), entry:year(style)
    values.pp = ""
    if entry.fields.pages ~= nil then
        values.pages = (values.pages:gsub("%-%-", "-"))
        values.pp = (values.pages:find("-", 1, true) and "pp. " or "p. ") .. values.pages
    end
    if entry.fields.edition ~= nil then values.edition = edition(values.edition) end
    values.mon = entry:value("month")
    for i, month in ipairs(month_names) do if values.mon == month then values.mon = month_short[i]; break end end
    return values
end

local function reference(entry, style, number, repeated)
    local values, output, last = placeholder_values(entry, style, repeated), {}, ""
    local function append(text)
        if text ~= "" then output[#output + 1], last = text, text:sub(-1) end
    end
    local function render(parts)
        for _, part in ipairs(parts) do
            if part.kind == "field" then append(values[part.name] or "")
            elseif part.kind == "optional" then
                local visible = true
                for _, child in ipairs(part.children) do
                    if child.kind == "field" and (values[child.name] or "") == "" then visible = false; break end
                end
                if visible then render(part.children) end
            elseif part.text ~= "." or last ~= "." and last ~= "?" and last ~= "!" then append(part.text) end
        end
    end
    render(templates[style][entry.kind == "incollection" and "inproceedings" or entry.kind])
    return (style == "IEEE" and "[" .. number .. "] " or "") .. table.concat(output)
end

local Manager = {}
Manager.__index = Manager

function Manager.new(database) return setmetatable({database = database, record = {}, recorded = {}}, Manager) end
function Manager:lookup(key)
    return self.database.by_key[key] or fail("unknown key '" .. key .. "'")
end

function Manager:ieee_order()
    local order, rest = {}, {}
    for _, entry in ipairs(self.record) do order[#order + 1] = entry end
    for _, entry in ipairs(self.database.entries) do if not self.recorded[entry] then rest[#rest + 1] = entry end end
    table.sort(rest, function(a, b) return ascii_less(a.key, b.key) end)
    for _, entry in ipairs(rest) do order[#order + 1] = entry end
    return order
end

function Manager:ieee_numbers()
    local numbers = {}
    for i, entry in ipairs(self:ieee_order()) do numbers[entry] = i end
    return numbers
end

local function short_name(entry, style, parenthetical)
    local primary, names = entry:primary(), {}
    for i, name in ipairs(primary.names) do names[i] = name:surname() end
    if primary.et_al or #names >= (style == "CHICAGO" and 4 or 3) then return names[1] .. " et al." end
    return list_names(names, style == "APA" and parenthetical and "&" or "and", true)
end

local function number_ranges(numbers)
    table.sort(numbers)
    local parts, i = {}, 1
    while i <= #numbers do
        local finish = i
        while finish < #numbers and numbers[finish + 1] == numbers[finish] + 1 do finish = finish + 1 end
        if finish - i >= 2 then parts[#parts + 1] = "[" .. numbers[i] .. "]-[" .. numbers[finish] .. "]"
        else for j = i, finish do parts[#parts + 1] = "[" .. numbers[j] .. "]" end end
        i = finish + 1
    end
    return table.concat(parts, ", ")
end

local function citation_text(citation, style, numbers)
    local entries, parts = {}, {}
    for i, entry in ipairs(citation.entries) do entries[i] = entry end
    if citation.kind == "citeauthor" or citation.kind == "citeyear" then
        for i, entry in ipairs(entries) do parts[i] = citation.kind == "citeauthor" and short_name(entry, style, false) or entry:year(style) end
        return table.concat(parts, citation.kind == "citeauthor" and "; " or ", ")
    end
    local parenthetical = citation.kind ~= "citet"
    if style == "IEEE" then
        for i, entry in ipairs(entries) do parts[i] = parenthetical and numbers[entry] or short_name(entry, style, false) .. " [" .. numbers[entry] .. "]" end
        return parenthetical and number_ranges(parts) or table.concat(parts, "; ")
    elseif style == "MLA" then
        for i, entry in ipairs(entries) do parts[i] = short_name(entry, style, parenthetical) end
        local text = table.concat(parts, "; ")
        return parenthetical and "(" .. text .. ")" or text
    end
    if parenthetical then table.sort(entries, Entry.less) end
    local i = 1
    while i <= #entries do
        local name, finish = short_name(entries[i], style, parenthetical), i + 1
        while finish <= #entries and short_name(entries[finish], style, parenthetical) == name do finish = finish + 1 end
        local years = {}
        for j = i, finish - 1 do years[#years + 1] = entries[j]:year(style) end
        local joined = table.concat(years, ", ")
        parts[#parts + 1] = parenthetical and name .. (style == "APA" and ", " or " ") .. joined or name .. " (" .. joined .. ")"
        i = finish
    end
    local text = table.concat(parts, "; ")
    return parenthetical and "(" .. text .. ")" or text
end

function Manager:cite(text, style)
    local citations, start = {}, text:find("\\", 1, true)
    while start do
        local brace = text:find("{", start, true)
        local finish = text:find("}", brace, true)
        local entries, seen = {}, {}
        for _, key in ipairs(split(text:sub(brace + 1, finish - 1), ",")) do
            local entry = self:lookup(key)
            if not seen[entry] then seen[entry] = true; entries[#entries + 1] = entry end
        end
        citations[#citations + 1] = {start = start, finish = finish, kind = text:sub(start + 1, brace - 1), entries = entries}
        start = text:find("\\", finish + 1, true)
    end
    -- Validation is complete before the citation record is updated.
    for _, citation in ipairs(citations) do
        for _, entry in ipairs(citation.entries) do
            if not self.recorded[entry] then self.recorded[entry] = true; self.record[#self.record + 1] = entry end
        end
    end
    local numbers, output, position = self:ieee_numbers(), {}, 1
    for _, citation in ipairs(citations) do
        output[#output + 1] = text:sub(position, citation.start - 1)
        output[#output + 1] = citation_text(citation, style, numbers)
        position = citation.finish + 1
    end
    output[#output + 1] = text:sub(position)
    return table.concat(output)
end

local function base_key(entry)
    local result = letters(plain(entry:primary().names[1].last)) .. entry.fields.year:gsub("[^0-9]", "")
    for _, word in ipairs(split(entry:value("title"), " ")) do
        local candidate = letters(word)
        if candidate ~= "" and not small_words[candidate] then return result .. candidate end
    end
    return result
end

function Manager:keygen()
    local bases, counts, used, output = {}, {}, {}, {}
    for i, entry in ipairs(self.database.entries) do
        local base = base_key(entry)
        bases[i], counts[base] = base, (counts[base] or 0) + 1
    end
    for i, entry in ipairs(self.database.entries) do
        local base, suffix = bases[i], ""
        if counts[base] > 1 then
            suffix = string.char(97 + (used[base] or 0))
            used[base] = (used[base] or 0) + 1
        end
        output[#output + 1] = entry.key .. " -> " .. base .. suffix
    end
    return output
end

local function unknown_fields(entry)
    local names = {}
    for name in pairs(entry.fields) do if not known[name] then names[#names + 1] = name end end
    table.sort(names, ascii_less)
    return names
end

function Manager:check()
    local output, titles = {}, {}
    for _, entry in ipairs(self.database.entries) do
        local warnings = {}
        if entry.fields.pages ~= nil then
            local pages, pieces = entry:value("pages"), {}
            if pages:find("-", 1, true) and not pages:find("--", 1, true) then warnings[#warnings + 1] = "pages use a single hyphen" end
            for _, piece in ipairs(split(pages, "-")) do if piece ~= "" then pieces[#pieces + 1] = piece end end
            if #pieces == 2 and digits(pieces[1]) and digits(pieces[2]) and tonumber(pieces[1], 10) > tonumber(pieces[2], 10) then
                warnings[#warnings + 1] = "pages are reversed"
            end
        end
        local year, title = entry:value("year"), entry:value("title")
        if #year ~= 4 or not digits(year) then warnings[#warnings + 1] = "year is not 4 digits" end
        local _, upper_count = title:gsub("[A-Z]", "")
        if not title:find("[a-z]") and upper_count >= 2 then warnings[#warnings + 1] = "title is all caps" end
        if entry.kind == "article" and entry.fields.doi == nil then warnings[#warnings + 1] = "article has no doi" end
        local lowered = lower(title)
        if titles[lowered] then warnings[#warnings + 1] = "same title as " .. titles[lowered] else titles[lowered] = entry.key end
        for _, field in ipairs(unknown_fields(entry)) do warnings[#warnings + 1] = "unknown field '" .. field .. "'" end
        for _, warning in ipairs(warnings) do output[#output + 1] = "WARN " .. entry.key .. ": " .. warning end
    end
    output[#output + 1] = "CHECK warnings=" .. #output
    return output
end

local function export_entry(entry)
    local fields, output = {}, {"@" .. entry.kind .. "{" .. entry.key .. ","}
    for _, field in ipairs(known_fields) do if entry.fields[field] ~= nil then fields[#fields + 1] = field end end
    for _, field in ipairs(unknown_fields(entry)) do fields[#fields + 1] = field end
    for i, field in ipairs(fields) do
        output[#output + 1] = "  " .. field .. " = {" .. entry.fields[field] .. "}" .. (i < #fields and "," or "")
    end
    output[#output + 1] = "}"
    return output
end

function Manager:stats()
    local types, years, authors, pair_counts = {}, {}, {}, {}
    for _, entry in ipairs(self.database.entries) do
        types[entry.kind] = (types[entry.kind] or 0) + 1
        local year = entry:value("year")
        years[year] = (years[year] or 0) + 1
        if entry.authors then
            local distinct = {}
            for _, name in ipairs(entry.authors.names) do
                local text = name:notation(false, false)
                distinct[text], authors[text] = true, true
            end
            local names = sorted_keys(distinct)
            for i = 1, #names do
                for j = i + 1, #names do
                    local a, b = names[i], names[j]
                    pair_counts[a] = pair_counts[a] or {}
                    pair_counts[a][b] = (pair_counts[a][b] or 0) + 1
                end
            end
        end
    end
    local output = {"ENTRIES " .. #self.database.entries}
    for _, kind in ipairs(sorted_keys(types)) do output[#output + 1] = "TYPE " .. kind .. " " .. types[kind] end
    for _, year in ipairs(sorted_keys(years)) do output[#output + 1] = "YEAR " .. year .. " " .. years[year] end
    output[#output + 1] = "AUTHORS " .. #sorted_keys(authors)
    local best
    for a, seconds in pairs(pair_counts) do
        for b, count in pairs(seconds) do
            if not best or count > best.count or count == best.count and
                (ascii_less(a, best.a) or a == best.a and ascii_less(b, best.b)) then best = {a = a, b = b, count = count} end
        end
    end
    output[#output + 1] = best and "PAIR " .. best.a .. " & " .. best.b .. " " .. best.count or "PAIR none"
    return output
end

function Manager:execute(text)
    local command = text:match("^[^ ]+")
    local arity = {FORMAT = 2, BIBLIOGRAPHY = 1, CITE = 2, KEYGEN = 0, CHECK = 0, SEARCH = 2, EXPORT = 1, STATS = 0}
    local expected = arity[command]
    if expected == nil then fail("unknown command '" .. command .. "'") end
    local words
    if command == "CITE" or command == "SEARCH" then
        words = {command}
        local first = text:find(" ", 1, true)
        if first then
            local second = text:find(" ", first + 1, true)
            if second then words[2], words[3] = text:sub(first + 1, second - 1), text:sub(second + 1)
            else words[2] = text:sub(first + 1) end
        end
    else words = split(text, " ") end
    if command == "FORMAT" and #words - 1 < 2 or command ~= "FORMAT" and #words - 1 ~= expected then fail("wrong number of arguments") end
    local style = words[2]
    if (command == "FORMAT" or command == "BIBLIOGRAPHY" or command == "CITE") and templates[style] == nil then
        fail("unknown style '" .. style .. "'")
    end
    local output = {}
    if command == "FORMAT" then
        local numbers = self:ieee_numbers()
        for i = 3, #words do
            local key = words[i]
            local entry = self.database.by_key[key]
            output[#output + 1] = entry and reference(entry, style, numbers[entry], false) or "ERROR unknown key '" .. key .. "'"
        end
    elseif command == "BIBLIOGRAPHY" then
        output[1] = style == "MLA" and "Works Cited" or "References"
        local numbers, entries = self:ieee_numbers(), self:ieee_order()
        if style ~= "IEEE" then table.sort(entries, Entry.less) end
        local previous
        for _, entry in ipairs(entries) do
            local repeated = (style == "CHICAGO" or style == "MLA") and previous and previous:same(entry:primary())
            output[#output + 1] = reference(entry, style, numbers[entry], repeated)
            previous = entry:primary()
        end
    elseif command == "CITE" then return {self:cite(words[3], style)}
    elseif command == "KEYGEN" then return self:keygen()
    elseif command == "CHECK" then return self:check()
    elseif command == "SEARCH" then
        local matches, needle = {}, lower(words[3])
        for _, entry in ipairs(self.database.entries) do
            if entry.fields[words[2]] ~= nil and lower(entry:value(words[2])):find(needle, 1, true) then matches[#matches + 1] = entry.key end
        end
        return {#matches == 0 and "MATCHES 0" or "MATCHES " .. #matches .. ": " .. table.concat(matches, " ")}
    elseif command == "EXPORT" then return export_entry(self:lookup(words[2]))
    else return self:stats() end
    return output
end

local function read_line()
    local text = io.read("*l")
    return text and (text:gsub("\r$", "")) or nil
end

local lines = {}
while true do
    local text = read_line()
    if text == nil or text == "%%" then break end
    lines[#lines + 1] = text
end
local database = Database.new(lines)
for _, message in ipairs(database.messages) do print(message) end
local manager = Manager.new(database)
local count = tonumber(read_line(), 10)
for _ = 1, count do
    local okay, result = pcall(function() return manager:execute(read_line()) end)
    if okay then
        for _, message in ipairs(result) do print(message) end
    elseif type(result) == "table" and result.command_error then print("ERROR " .. result.message)
    else error(result, 0) end
end
