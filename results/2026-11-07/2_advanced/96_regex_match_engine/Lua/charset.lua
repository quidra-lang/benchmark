local C = {}
C.ASCII, C.DIGITS, C.WORD, C.SPACE = {}, {}, {}, {}
function C.letter(code) return code and ((code >= 65 and code <= 90) or (code >= 97 and code <= 122)) or false end
function C.digit(code) return code and code >= 48 and code <= 57 or false end
function C.switched(code)
    if code >= 65 and code <= 90 then return code + 32 elseif code >= 97 and code <= 122 then return code - 32 end
    return code
end
for code = 0, 127 do
    C.ASCII[code] = true
    if C.digit(code) then C.DIGITS[code] = true end
    if C.letter(code) or C.digit(code) or code == 95 then C.WORD[code] = true end
end
for _, code in ipairs({ 9, 10, 11, 12, 13, 32 }) do C.SPACE[code] = true end
local standard = { d = C.DIGITS, D = C.DIGITS, w = C.WORD, W = C.WORD, s = C.SPACE, S = C.SPACE }
function C.standard(letter) return standard[letter], letter == "D" or letter == "W" or letter == "S" end
function C.escaped(letter)
    local set, negate = C.standard(letter)
    if not set then return false end
    if not negate then return set end
    local result = {}
    for code = 0, 127 do if not set[code] then result[code] = true end end
    return result
end
function C.equal(a, b, flags) return a == b or (flags.i and C.letter(a) and C.switched(a) == b) end
function C.class(code, set, negate, flags)
    local present = set[code] or (flags.i and C.letter(code) and set[C.switched(code)]) or false
    return present ~= negate
end
function C.test(instruction, text, position, flags)
    if position >= #text then return false end
    local code = text:byte(position + 1)
    if instruction.op == "CHAR" then return C.equal(code, instruction.char, flags)
    elseif instruction.op == "ANY" then return flags.s or code ~= 10 end
    return C.class(code, instruction.set, instruction.neg, flags)
end
local function word_at(text, position)
    return position >= 0 and position < #text and C.WORD[text:byte(position + 1)] or false
end
function C.assertion(kind, text, position, flags)
    if kind == "BOL" then return position == 0 or (flags.m and text:byte(position) == 10) or false
    elseif kind == "EOL" then return position == #text or (flags.m and text:byte(position + 1) == 10) or false end
    local edge = word_at(text, position - 1) ~= word_at(text, position)
    if kind == "WORD" then return edge end
    return not edge
end
return C
