local source_directory = (arg[0]:match("^(.*[/\\])") or "./")
package.path = source_directory .. "?.lua;" .. package.path
local addresses = require("addresses")
local dates = require("dates")
local headers = require("headers")
local mime = require("mime")
local threader = require("threader")

local checked_fields = {"From", "To", "Cc", "Subject", "Date", "Message-ID", "In-Reply-To", "References", "MIME-Version", "Content-Type", "Content-Transfer-Encoding", "Content-Disposition"}
local identity_encodings = {["7bit"] = true, ["8bit"] = true, binary = true}
local hidden_tags = {head = true, style = true, script = true}
local paragraph_tags = {p = true, div = true, ul = true, ol = true, table = true, tr = true,
    blockquote = true, h1 = true, h2 = true, h3 = true, h4 = true, h5 = true, h6 = true}
local character_references = {amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = " "}

local function extend(target, values) for _, value in ipairs(values) do target[#target + 1] = value end end
local function read_lines(path)
    local lines = {}
    for line in io.lines(path) do lines[#lines + 1] = line end
    return lines
end
local function split_sections(lines)
    local header, body, in_body = {}, {}, false
    for _, line in ipairs(lines) do
        if in_body then body[#body + 1] = line
        elseif line[2] == "" then in_body = true
        else header[#header + 1] = line end
    end
    return header, body
end
local function read_mailbox(path)
    local messages = {}
    for number, line in ipairs(read_lines(path)) do
        if line:sub(1, 5) == "From " then messages[#messages + 1] = {}
        elseif #messages > 0 then
            if line:match("^>+From ") then line = line:sub(2) end
            local lines = messages[#messages]
            lines[#lines + 1] = {number, line}
        end
    end
    for _, lines in ipairs(messages) do if #lines > 0 and lines[#lines][2] == "" then table.remove(lines) end end
    return messages
end

local function is_message_id(text)
    if #text < 3 or text:sub(1, 1) ~= "<" or text:sub(-1) ~= ">" then return false end
    local inside = text:sub(2, -2)
    local _, count = inside:gsub("@", "")
    if count ~= 1 or inside:sub(1, 1) == "@" or inside:sub(-1) == "@" then return false end
    for position = 1, #inside do
        local char, code = inside:sub(position, position), inside:byte(position)
        if code < 33 or code > 126 or ('<>()"\\'):find(char, 1, true) then return false end
    end
    return true
end
local function extract_ids(value)
    local ids, position = {}, 1
    while true do
        local first = value:find("<", position, true)
        if first == nil then break end
        local last = value:find(">", first + 1, true)
        if last == nil then break end
        local id = value:sub(first, last)
        if is_message_id(id) then ids[#ids + 1] = id end
        position = last + 1
    end
    return ids
end
local function date_notation(seconds) return seconds == nil and "invalid" or dates.format_utc(seconds) end
local function subject_notation(subject) return subject == "" and "(no subject)" or subject end

local Message = {}
Message.__index = Message
function Message.new(number)
    return setmetatable({number = number, problems = {}, to = {}, cc = {}, subject = "", base_subject = "",
        reply = false, id = "", references = {}, thread = 0, depth = 0}, Message)
end
function Message:problem(text) self.problems[#self.problems + 1] = text end

function Message:read_sender(value)
    if value == nil then self:problem("missing From") return end
    local list, encoding_error = addresses.parse_address_list(value)
    if list == nil or #list ~= 1 or list[1].mailboxes ~= nil then self:problem("bad From") return end
    self.sender = list[1]
    if encoding_error then self:problem("bad encoded word in From") end
end
function Message:read_recipients(value, name)
    if value == nil then return {} end
    local list, encoding_error = addresses.parse_address_list(value)
    if list == nil then self:problem("bad " .. name) return {} end
    local recipients = {}
    for _, address in ipairs(list) do
        if address.mailboxes then
            for _, mailbox in ipairs(address.mailboxes) do recipients[#recipients + 1] = mailbox.address end
        else recipients[#recipients + 1] = address.address end
    end
    if encoding_error then self:problem("bad encoded word in " .. name) end
    return recipients
end

function Message:parse_entity(number, header, lines, enabled)
    local entity = {number = number, main_type = "text", subtype = "plain", parameters = {}, content = ""}
    local content_type = header:value("Content-Type")
    if enabled and content_type ~= nil then
        local parsed = headers.parse_parameters(content_type, true)
        if parsed == nil then self:problem("bad Content-Type in part " .. number)
        else entity.main_type, entity.subtype, entity.parameters = parsed[1], parsed[2], parsed[3] end
    end
    local disposition = header:value("Content-Disposition")
    if enabled and disposition ~= nil then
        local parsed = headers.parse_parameters(disposition, false)
        if parsed == nil then self:problem("bad Content-Disposition in part " .. number)
        else entity.disposition, entity.filename = parsed[1], parsed[3].filename end
    end
    if entity.filename == nil or entity.filename == "" then entity.filename = entity.parameters.name end
    local charset = entity.parameters.charset
    if entity.main_type == "text" and charset ~= nil and charset:lower() ~= "us-ascii" then self:problem('unsupported charset "' .. charset:lower() .. '" in part ' .. number) end
    if enabled and entity.main_type == "multipart" then
        local boundary = entity.parameters.boundary or ""
        if boundary ~= "" then
            local parts, closed = {}, false
            for _, line in ipairs(lines) do
                local text = headers.rstrip(line[2])
                if text == "--" .. boundary .. "--" then closed = true break
                elseif text == "--" .. boundary then parts[#parts + 1] = {}
                elseif #parts > 0 then local part = parts[#parts] part[#part + 1] = line end
            end
            if #parts == 0 then self:problem("no parts in part " .. number)
            elseif not closed then self:problem("unterminated multipart in part " .. number) end
            entity.children = {}
            for index, part in ipairs(parts) do
                local header_lines, body_lines = split_sections(part)
                local child_header = headers.parse_fields(header_lines)
                for _, line_number in ipairs(child_header.invalid_lines) do self:problem("bad header line " .. line_number) end
                entity.children[#entity.children + 1] = self:parse_entity(number .. "." .. index, child_header, body_lines, true)
            end
            return entity
        end
        self:problem("missing boundary in part " .. number)
    end
    local body = {}
    for _, line in ipairs(lines) do body[#body + 1] = line[2] end
    local original, encoding = table.concat(body, "\n"), "7bit"
    local transfer = header:value("Content-Transfer-Encoding")
    if enabled and transfer ~= nil then encoding = transfer:lower() end
    if encoding == "base64" then
        entity.content = mime.decode_base64_body(original)
        if entity.content == nil then self:problem("bad base64 in part " .. number) entity.content = "" end
    elseif encoding == "quoted-printable" then
        local error
        entity.content, error = mime.decode_quoted_printable(original)
        if error then self:problem("bad quoted-printable in part " .. number) end
    else
        entity.content = original
        if not identity_encodings[encoding] then self:problem('unknown encoding "' .. encoding .. '" in part ' .. number) end
    end
    return entity
end

function Message:process(lines, known_ids)
    local header_lines, body_lines = split_sections(lines)
    local header = headers.parse_fields(header_lines)
    for _, number in ipairs(header.invalid_lines) do self:problem("bad header line " .. number) end
    for _, name in ipairs(checked_fields) do if header:count(name) > 1 then self:problem("duplicate " .. name) end end
    self:read_sender(header:value("From"))
    self.to = self:read_recipients(header:value("To"), "To")
    self.cc = self:read_recipients(header:value("Cc"), "Cc")
    local encoding_error
    self.subject, encoding_error = headers.decode_unstructured(header:value("Subject") or "")
    if encoding_error then self:problem("bad encoded word in Subject") end
    self.base_subject = self.subject
    while self.base_subject:sub(1, 3):lower() == "re:" do self.base_subject = self.base_subject:sub(4):gsub("^ +", "") self.reply = true end
    local date = header:value("Date")
    if date == nil then self:problem("missing Date")
    else local reason self.date, reason = dates.parse_date(date) if reason then self:problem(reason) end end
    local id = header:value("Message-ID")
    if id == nil then self:problem("missing Message-ID")
    elseif not is_message_id(id) then self:problem("bad Message-ID")
    elseif known_ids[id] ~= nil then self:problem("Message-ID already used by message " .. known_ids[id])
    else self.id, known_ids[id] = id, self.number end
    self.references = extract_ids(header:value("References") or "")
    local replies = extract_ids(header:value("In-Reply-To") or "")
    if #replies > 0 and self.references[#self.references] ~= replies[1] then self.references[#self.references + 1] = replies[1] end
    local version, enabled = header:value("MIME-Version"), false
    if version ~= nil then
        local text = headers.remove_comments(version)
        if text ~= nil and text:gsub("[ \t]", "") == "1.0" then enabled = true else self:problem("bad MIME-Version") end
    end
    self.body = self:parse_entity("1", header, body_lines, enabled)
    self.sort_key = {self.date == nil and 1 or 0, self.date or 0, self.id, self.number}
end

local function collect_text_parts(entity, allow_html)
    if entity.children == nil then
        if entity.disposition == "attachment" or entity.main_type ~= "text" then return {} end
        if entity.subtype == "plain" or entity.subtype == "html" and allow_html then return {entity} end
        return {}
    end
    if entity.subtype == "alternative" then
        for _, html_pass in ipairs({false, true}) do
            for _, child in ipairs(entity.children) do
                local parts = collect_text_parts(child, html_pass)
                if #parts > 0 then return parts end
            end
        end
        return {}
    end
    local parts = {}
    for _, child in ipairs(entity.children) do extend(parts, collect_text_parts(child, allow_html)) end
    return parts
end

local function quote_prefix(depth) return depth > 0 and string.rep(">", depth) .. " " or "" end
local function wrap(text, prefix)
    local lines, current = {}, ""
    for _, word in ipairs(headers.split_words(text)) do
        if current ~= "" and #current + 1 + #word > 72 then lines[#lines + 1], current = prefix .. current, word
        elseif current ~= "" then current = current .. " " .. word
        else current = word end
    end
    lines[#lines + 1] = prefix .. current
    return lines
end

local function flowed_lines(content, delete_space)
    if content == "" then return {} end
    local logical = {}
    for _, line in ipairs(headers.split(content, "\n")) do
        local text = line:gsub("^>+", "")
        local depth = #line - #text
        if text:sub(1, 1) == " " then text = text:sub(2) end
        local flowing = text:sub(-1) == " " and text ~= "-- "
        local previous = logical[#logical]
        if previous and previous.flowing and previous.depth == depth then
            if delete_space then previous.text = previous.text:sub(1, -2) end
            previous.text, previous.flowing = previous.text .. text, flowing
        else logical[#logical + 1] = {depth = depth, text = text, flowing = flowing} end
    end
    local lines = {}
    for _, line in ipairs(logical) do extend(lines, wrap(line.text, quote_prefix(line.depth))) end
    return lines
end

local function replace_references(text)
    local result, position = {}, 1
    while position <= #text do
        local replacement, ending
        if text:sub(position, position) == "&" then
            ending = text:find(";", position + 1, true)
            if ending then
                local name = text:sub(position + 1, ending - 1)
                replacement = character_references[name]
                local digits = name:match("^#(%d%d?%d?)$")
                if replacement == nil and digits then
                    local code = tonumber(digits)
                    if code >= 32 and code <= 126 then replacement = string.char(code) end
                end
            end
        end
        if replacement ~= nil then result[#result + 1], position = replacement, ending + 1
        else result[#result + 1], position = text:sub(position, position), position + 1 end
    end
    return table.concat(result)
end

local function html_lines(content)
    local blocks, depth, text, hide, position = {}, 0, "", nil, 1
    while position <= #content do
        local char = content:sub(position, position)
        local close = char == "<" and content:find(">", position + 1, true) or nil
        if close == nil then
            if hide == nil then text = text .. char end
            position = position + 1
        else
            local inside = content:sub(position + 1, close - 1)
            position = close + 1
            local end_tag = inside:sub(1, 1) == "/"
            local name = ((end_tag and inside:sub(2) or inside):match("^[A-Za-z0-9]*")):lower()
            if hide then if end_tag and name == hide then hide = nil end
            elseif not end_tag and hidden_tags[name] then hide = name
            elseif name == "br" or name == "li" and not end_tag then
                blocks[#blocks + 1] = {depth = depth, text = text}
                text = name == "li" and "* " or ""
            elseif paragraph_tags[name] then
                blocks[#blocks + 1] = {depth = depth, text = text}
                blocks[#blocks + 1] = {depth = depth, text = ""}
                text = ""
                if name == "blockquote" then depth = end_tag and math.max(depth - 1, 0) or depth + 1 end
            end
        end
    end
    blocks[#blocks + 1] = {depth = depth, text = text}
    local lines = {}
    for _, block in ipairs(blocks) do
        local normalized = headers.collapse_whitespace((block.text:gsub("\n", " ")))
        normalized = replace_references(normalized):gsub("^ +", ""):gsub(" +$", "")
        if normalized ~= "" then extend(lines, wrap(normalized, quote_prefix(block.depth)))
        elseif #lines > 0 and lines[#lines] ~= "" then lines[#lines + 1] = "" end
    end
    while #lines > 0 and lines[#lines] == "" do table.remove(lines) end
    return lines
end

local function display_lines(entity)
    if entity.subtype == "html" then return "html", html_lines(entity.content) end
    if (entity.parameters.format or ""):lower() == "flowed" then return "flowed", flowed_lines(entity.content, (entity.parameters.delsp or ""):lower() == "yes") end
    return "plain", entity.content == "" and {} or headers.split(entity.content, "\n")
end

local function container_notation(node)
    local message = node.message
    if message then return "[" .. message.number .. "] " .. date_notation(message.date) .. " " .. (message.sender and message.sender.address or "-") .. " " .. subject_notation(message.subject) end
    if node.subject ~= nil then return "[subject] " .. node.subject end
    return "[missing] " .. node.id
end

local function make_thread(number, root)
    local thread = {number = number, root = root, entries = {}, messages = {}}
    local function walk(node, prefix, stem, depth)
        thread.entries[#thread.entries + 1] = {node = node, prefix = prefix, depth = depth}
        if node.message then
            local message = node.message
            message.thread, message.depth, message.parent = number, depth, node.parent and node.parent.message or nil
            thread.messages[#thread.messages + 1] = message
        end
        for index, child in ipairs(node.children) do
            local last = index == #node.children
            walk(child, stem .. (last and "`- " or "+- "), stem .. (last and "   " or "|  "), depth + 1)
        end
    end
    walk(root, "", "", 0)
    return thread
end

local function thread_report(thread)
    local depth, senders, sender_count, first, last = 0, {}, 0, nil, nil
    for _, entry in ipairs(thread.entries) do depth = math.max(depth, entry.depth) end
    for _, message in ipairs(thread.messages) do
        if message.sender and not senders[message.sender.address] then senders[message.sender.address], sender_count = true, sender_count + 1 end
        if message.date ~= nil then first = first == nil and message.date or math.min(first, message.date) last = last == nil and message.date or math.max(last, message.date) end
    end
    local subject = thread.root.subject or threader.root_subject(thread.root)
    local lines = {"thread " .. thread.number .. " messages " .. #thread.messages .. " depth " .. depth .. " senders " .. sender_count,
        first == nil and "span -" or "span " .. dates.format_utc(first) .. " .. " .. dates.format_utc(last), "subject " .. subject_notation(subject)}
    for _, entry in ipairs(thread.entries) do lines[#lines + 1] = entry.prefix .. container_notation(entry.node) end
    return lines
end

local function entity_lines(entity, lines)
    local line = "part " .. entity.number .. " " .. entity.main_type .. "/" .. entity.subtype
    if entity.children ~= nil then
        lines[#lines + 1] = line
        for _, child in ipairs(entity.children) do entity_lines(child, lines) end
        return
    end
    line = line .. " " .. #entity.content
    if entity.disposition ~= nil then line = line .. " " .. entity.disposition end
    if entity.filename ~= nil and entity.filename ~= "" then line = line .. ' "' .. entity.filename .. '"' end
    lines[#lines + 1] = line
end

local function message_report(message)
    local sender = "-"
    if message.sender then sender = message.sender.address if message.sender.name ~= "" then sender = message.sender.name .. " <" .. sender .. ">" end end
    local lines = {"message " .. message.number, "id " .. (message.id == "" and "-" or message.id), "date " .. date_notation(message.date), "from " .. sender,
        "to " .. (#message.to == 0 and "-" or table.concat(message.to, ", ")), "cc " .. (#message.cc == 0 and "-" or table.concat(message.cc, ", ")),
        "subject " .. subject_notation(message.subject), "refs " .. (#message.references == 0 and "-" or table.concat(message.references, " ")),
        "thread " .. message.thread .. " depth " .. message.depth .. " parent " .. (message.parent and message.parent.number or "-")}
    entity_lines(message.body, lines)
    return lines
end

local function body_report(request, by_id)
    local lines, message = {"request " .. request}, by_id[request]
    if message == nil then lines[#lines + 1] = "not found" return lines end
    local parts = collect_text_parts(message.body, true)
    lines[#lines + 1] = "message " .. message.number .. " text parts " .. #parts
    for _, part in ipairs(parts) do
        local format, display = display_lines(part)
        local quoted, signature = 0, 0
        for index, line in ipairs(display) do
            line = headers.rstrip(line)
            if line:sub(1, 1) == ">" then quoted = quoted + 1 end
            if line == "--" then signature = #display - index end
        end
        lines[#lines + 1] = "part " .. part.number .. " " .. format .. " lines " .. #display .. " quoted " .. quoted .. " signature " .. signature
        for _, line in ipairs(display) do line = headers.rstrip(line) lines[#lines + 1] = line == "" and "|" or "| " .. line end
    end
    return lines
end

local function csv_field(text)
    if text:find(",", 1, true) or text:find('"', 1, true) then return '"' .. text:gsub('"', '""') .. '"' end
    return text
end
local function senders_report(messages)
    local stats, ordered = {}, {}
    for _, message in ipairs(messages) do
        if message.sender then
            local address = message.sender.address
            if stats[address] == nil then stats[address] = {address = address, count = 0, threads = {}, name = ""} ordered[#ordered + 1] = stats[address] end
            local entry = stats[address]
            entry.count, entry.threads[message.thread] = entry.count + 1, true
            if message.date ~= nil then
                entry.first = entry.first == nil and message.date or math.min(entry.first, message.date)
                entry.last = entry.last == nil and message.date or math.max(entry.last, message.date)
            end
            if message.sender.name ~= "" then entry.name = message.sender.name end
        end
    end
    table.sort(ordered, function(a, b) return a.count > b.count or a.count == b.count and a.address < b.address end)
    local lines = {"address,name,messages,threads,first,last"}
    for _, entry in ipairs(ordered) do
        local count = 0
        for _ in pairs(entry.threads) do count = count + 1 end
        lines[#lines + 1] = table.concat({entry.address, csv_field(entry.name), tostring(entry.count), tostring(count),
            entry.first == nil and "-" or dates.format_utc(entry.first), entry.last == nil and "-" or dates.format_utc(entry.last)}, ",")
    end
    return lines
end

local function malformed_report(messages)
    local flagged, total = 0, 0
    for _, message in ipairs(messages) do total = total + #message.problems if #message.problems > 0 then flagged = flagged + 1 end end
    local lines = {"messages " .. #messages .. " malformed " .. flagged .. " problems " .. total}
    for _, message in ipairs(messages) do for _, problem in ipairs(message.problems) do lines[#lines + 1] = "message " .. message.number .. ": " .. problem end end
    return lines
end
local function join_blocks(blocks)
    local lines = {}
    for _, block in ipairs(blocks) do if #lines > 0 then lines[#lines + 1] = "" end extend(lines, block) end
    return lines
end
local function write_output(name, lines)
    local file = assert(io.open("output/" .. name, "w"))
    for _, line in ipairs(lines) do file:write(headers.rstrip(line), "\n") end
    file:close()
end

local function main()
    local messages, known_ids = {}, {}
    for number, lines in ipairs(read_mailbox("input/mailbox.mbox")) do
        local message = Message.new(number)
        message:process(lines, known_ids)
        messages[#messages + 1] = message
    end
    local threads = {}
    for number, root in ipairs(threader.build_threads(messages)) do threads[#threads + 1] = make_thread(number, root) end
    local by_id = {}
    for _, message in ipairs(messages) do
        if message.parent and message.date ~= nil and message.parent.date ~= nil and message.date < message.parent.date then message:problem("dated before parent message " .. message.parent.number) end
        if message.id ~= "" then by_id[message.id] = message end
    end
    local thread_blocks, message_blocks, body_blocks = {}, {}, {}
    for _, thread in ipairs(threads) do thread_blocks[#thread_blocks + 1] = thread_report(thread) end
    for _, message in ipairs(messages) do message_blocks[#message_blocks + 1] = message_report(message) end
    for _, request in ipairs(read_lines("input/requests.txt")) do body_blocks[#body_blocks + 1] = body_report(request, by_id) end
    os.execute("mkdir -p output")
    write_output("threads.txt", join_blocks(thread_blocks))
    write_output("messages.txt", join_blocks(message_blocks))
    write_output("bodies.txt", join_blocks(body_blocks))
    write_output("senders.csv", senders_report(messages))
    write_output("malformed.txt", malformed_report(messages))
end

main()
