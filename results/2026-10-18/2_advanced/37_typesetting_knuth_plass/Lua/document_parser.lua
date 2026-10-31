local M = {}
M.body_kinds = {paragraph = true, item = true, enum = true, quote = true, term = true}
local settings = {width = true, indent = true, align = true}
local preamble = {page = true, header = true, footer = true}
local blocks = {title = true, author = true, h1 = true, h2 = true, item = true, enum = true, quote = true,
    term = true, table = true, verbatim = true, toc = true, lot = true, index = true, bibliography = true}
local empty = {newpage = true, verbatim = true, toc = true, lot = true, index = true, bibliography = true}
function M.split(text, separator)
    local parts, start = {}, 1
    while true do
        local first, last = text:find(separator, start, true)
        if not first then
            parts[#parts + 1] = text:sub(start)
            return parts
        end
        parts[#parts + 1] = text:sub(start, first - 1)
        start = last + 1
    end
end
function M.partition(text, separator)
    local first, last = text:find(separator, 1, true)
    if first then
        return text:sub(1, first - 1), text:sub(last + 1), true
    end
    return text, "", false
end
local function dictionary_word(word)
    return #word > 0 and word:match("^[a-z%-]+$") ~= nil and word:sub(1, 1) ~= "-"
        and word:sub(-1) ~= "-" and not word:find("--", 1, true)
end
local function valid(name, argument)
    if name == "width" or name == "indent" or name == "page" then
        if #argument < 1 or #argument > 9 or not argument:match("^%d+$") then
            return false
        end
        local limits = ({width = {20, 80}, indent = {0, 8}, page = {10, 100}})[name]
        local value = tonumber(argument)
        return value >= limits[1] and value <= limits[2]
    elseif name == "align" then
        return argument == "left" or argument == "right" or argument == "center" or argument == "justify"
    elseif name == "header" or name == "footer" then
        return #M.split(argument, "|") == 3
    elseif empty[name] then
        return argument == ""
    elseif name == "hyphenation" then
        for _, word in ipairs(M.split(argument, " ")) do
            if not dictionary_word(word) then
                return false
            end
        end
        return true
    elseif name == "bib" then
        local key, rest, separator = M.partition(argument, " ")
        local parts = M.split(rest, "|")
        return separator and key:match("^[a-z0-9]+$") ~= nil and #parts == 3
            and #parts[1] > 0 and #parts[3] > 0 and parts[2]:match("^%d%d%d%d$") ~= nil
    elseif name == "term" then
        local term, description, separator = M.partition(argument, "|")
        return separator and #term > 0 and #description > 0
    elseif name == "table" then
        local columns = M.partition(argument, " ")
        return columns:match("^[lrc]+$") ~= nil
    end
    return argument ~= ""
end
function M.parse(lines)
    local document = {blocks = {}, warnings = {}, height = 40, page_width = 60, header = {"", "", ""}, footer = {"", "", ""}, hyphenation_words = {}, bibliography = {}}
    local width, indent, align = 60, 0, "left"
    local accepted, open_body, inner_block, pending = {}, nil, nil, false
    local function warn(number, message)
        document.warnings[#document.warnings + 1] = {line = number, message = message}
    end
    local function create(kind, number, argument)
        if #document.blocks == 0 then
            document.page_width = width
        end
        local block = {kind = kind, line = number, argument = argument or "", page_break = pending,
            width = width, indent = indent, align = align, body_lines = {}, inner_lines = {}}
        pending = false
        document.blocks[#document.blocks + 1] = block
        return block
    end
    for number, line in ipairs(lines) do
        if inner_block then
            if line == ".end" then
                inner_block = nil
            else
                inner_block.inner_lines[#inner_block.inner_lines + 1] = {line = number, text = line}
            end
        elseif line == "" then
            open_body = nil
        elseif line:sub(1, 1) ~= "." then
            if not open_body then
                open_body = create("paragraph", number)
            end
            open_body.body_lines[#open_body.body_lines + 1] = {line = number, text = line}
        else
            open_body = nil
            local name, argument = M.partition(line:sub(2), " ")
            local warning
            if not (settings[name] or preamble[name] or blocks[name] or name == "newpage" or name == "hyphenation" or name == "bib") then
                warning = "unknown directive ." .. name
            elseif not valid(name, argument) then
                warning = "bad argument for ." .. name
            elseif preamble[name] and #document.blocks > 0 then
                warning = "." .. name .. " ignored after the preamble"
            elseif preamble[name] and accepted[name] then
                warning = "duplicate ." .. name
            end
            if warning then
                warn(number, warning)
            elseif settings[name] then
                if name == "width" then
                    width = tonumber(argument)
                elseif name == "indent" then
                    indent = tonumber(argument)
                else
                    align = argument
                end
            elseif preamble[name] then
                accepted[name] = true
                if name == "page" then
                    document.height = tonumber(argument)
                else
                    document[name] = M.split(argument, "|")
                end
            elseif name == "newpage" then
                pending = true
            elseif name == "hyphenation" then
                for _, word in ipairs(M.split(argument, " ")) do
                    document.hyphenation_words[#document.hyphenation_words + 1] = word
                end
            elseif name == "bib" then
                local key, rest = M.partition(argument, " ")
                local parts = M.split(rest, "|")
                document.bibliography[#document.bibliography + 1] = {line = number, key = key, author = parts[1], year = parts[2], title = parts[3]}
            else
                local block = create(name, number, argument)
                if name == "item" or name == "enum" or name == "quote" then
                    block.body_lines[1], open_body = {line = number, text = argument}, block
                elseif name == "term" then
                    local term, description = M.partition(argument, "|")
                    block.term = term
                    block.body_lines[1], open_body = {line = number, text = description}, block
                elseif name == "table" then
                    block.columns, block.caption = M.partition(argument, " ")
                    inner_block = block
                elseif name == "verbatim" then
                    inner_block = block
                end
            end
        end
    end
    if inner_block then
        warn(inner_block.line, "unterminated " .. inner_block.kind)
    end
    return document
end
return M
