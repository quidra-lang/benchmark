local B = require("builtins")
local S = {}
S.__index = S
local function letter(ch) return ch ~= "" and ((ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z")) end
local function digit(ch) return ch ~= "" and ch >= "0" and ch <= "9" end
local function valid_name(name)
    if name == "" or (not letter(name:sub(1, 1)) and name:sub(1, 1) ~= "_") then return false end
    for i = 1, #name do
        local ch = name:sub(i, i)
        if not letter(ch) and not digit(ch) and ch ~= "_" then return false end
    end
    return true
end
function S.valid_filename(name)
    if name == "" or name:sub(1, 1) == "." then return false end
    for i = 1, #name do
        local ch = name:sub(i, i)
        if not letter(ch) and not digit(ch) and ch ~= "." and ch ~= "_" and ch ~= "-" then return false end
    end
    return true
end
function S.arguments()
    local options, operands = {}, {}
    for line in io.lines("input/args.txt") do
        local at = line:find("=", 1, true)
        if line:sub(1, 3) == "-F " then options[#options + 1] = { "FS", line:sub(4) }
        elseif line:sub(1, 3) == "-v " then options[#options + 1] = { line:sub(4, at - 1), line:sub(at + 1) }
        elseif at and valid_name(line:sub(1, at - 1)) then
            operands[#operands + 1] = { kind = "assignment", name = line:sub(1, at - 1), value = line:sub(at + 1), records = 0 }
        else operands[#operands + 1] = { kind = "file", name = line, records = 0 } end
    end
    return options, operands
end
function S.read_records(name)
    local file = io.open("input/" .. name, "r")
    if not file then return nil end
    local contents = file:read("*a")
    file:close()
    if contents == nil then return nil end
    local lines = {}
    local position = 1
    while position <= #contents do
        local ending = contents:find("\n", position, true)
        if not ending then lines[#lines + 1] = contents:sub(position); break end
        lines[#lines + 1], position = contents:sub(position, ending - 1), ending + 1
    end
    return lines
end
local function output_stream() return { parts = {}, open = false, writes = 0, bytes = 0 } end
local function add(output, text)
    output.parts[#output.parts + 1], output.writes, output.bytes = text, output.writes + 1, output.bytes + #text
end
function S.new() return setmetatable({ stdout = output_stream(), outputs = {}, inputs = {}, output_order = {}, input_order = {} }, S) end
function S:write(text, name, mode, position)
    if name == nil then add(self.stdout, text); return end
    if not S.valid_filename(name) or name == "stdout.txt" or name == "stats.txt" then B.fail(position, "invalid output file name") end
    if not self.outputs[name] then self.outputs[name] = output_stream(); self.output_order[#self.output_order + 1] = name end
    local output = self.outputs[name]
    if not output.open then
        output.open = true
        if mode == ">" then output.parts, output.bytes = {}, 0 end
    end
    add(output, text)
end
function S:getline(name)
    if not self.inputs[name] then
        self.inputs[name] = { open = false, ever_opened = false, lines = {}, position = 1, reads = 0 }
        self.input_order[#self.input_order + 1] = name
    end
    local source = self.inputs[name]
    if not source.open then
        if not S.valid_filename(name) then return -1 end
        local lines = S.read_records(name)
        if not lines then return -1 end
        source.lines, source.position, source.open, source.ever_opened = lines, 1, true, true
    end
    if source.position > #source.lines then return 0 end
    local line = source.lines[source.position]
    source.position, source.reads = source.position + 1, source.reads + 1
    return 1, line
end
function S:close(name)
    local closed = false
    for _, values in ipairs({ self.outputs, self.inputs }) do
        if values[name] and values[name].open then values[name].open, closed = false, true end
    end
    return closed and 0 or -1
end
function S:save()
    local function write(name, stream)
        local file = assert(io.open("output/" .. name, "w"))
        for _, part in ipairs(stream.parts) do file:write(part) end
        file:close()
    end
    write("stdout.txt", self.stdout)
    for _, name in ipairs(self.output_order) do write(name, self.outputs[name]) end
end
return S
