local Lexer = require("lexer")
local Box = {}
Box.__index = Box
Box.command_display, Box.command_types, Box.symbol_types = {}, {}, {}
for name, item in pairs(Lexer.symbols) do Box.command_display[name], Box.command_types[name] = item[1], item[2] end
for _, item in ipairs({{"+-*", "binary"}, {"=<>:", "relation"}, {"([", "open"}, {")]!", "close"}, {",;", "punctuation"}}) do
    for character in item[1]:gmatch(".") do Box.symbol_types[character] = item[2] end
end
Box.large_glyphs = {["\\sum"] = {"\\--", " > ", "/--"}, ["\\prod"] = {"___", "| |", "| |"}, ["\\int"] = {" /", " |", "/ "}}

function Box.new(width, height, baseline, description)
    return setmetatable({width = width, height = height, baseline = baseline, description = description,
        children = {}, strings = {}}, Box)
end

function Box:descent()
    return self.height - 1 - self.baseline
end

function Box:add(child, x, y, role)
    self.children[#self.children + 1] = {box = child, x = x, y = y, role = role or ""}
end

function Box:draw(text, x, y)
    self.strings[#self.strings + 1] = {text = text, x = x or 0, y = y or 0}
end

function Box.delimiter_glyph(delimiter, height)
    if delimiter == "." then return {} end
    if height == 1 then return {delimiter:sub(-1)} end
    local result = {}
    if delimiter == "[" or delimiter == "]" or delimiter == "|" then
        for i = 1, height do result[i] = delimiter end
    else
        local left = delimiter == "(" or delimiter == "\\{"
        for i = 1, height do result[i] = "|" end
        result[1], result[height] = left and "/" or "\\", left and "\\" or "/"
        if (delimiter == "\\{" or delimiter == "\\}") and height >= 3 then result[(height - 1) // 2 + 1] = left and "<" or ">" end
    end
    return result
end

return Box
