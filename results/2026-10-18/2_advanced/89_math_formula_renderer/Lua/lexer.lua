local Lexer = {greek = {}, symbols = {}, command_names = {}}
local function set(words)
    local result = {}
    for word in words:gmatch("%S+") do result[word] = true end
    return result
end
Lexer.greek = set("alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi pi rho sigma tau upsilon phi chi psi omega Gamma Delta Theta Lambda Xi Pi Sigma Upsilon Phi Psi Omega")
for name in pairs(Lexer.greek) do Lexer.symbols["\\" .. name] = {name, "ordinary"} end
for name in pairs(set("sin cos tan log ln exp det lim max min sum prod int")) do Lexer.symbols["\\" .. name] = {name, "operator"} end
for name, item in pairs({cdot = {"*", "binary"}, times = {"x", "binary"}, pm = {"+-", "binary"}, mp = {"-+", "binary"},
    leq = {"<=", "relation"}, geq = {">=", "relation"}, neq = {"!=", "relation"}, approx = {"~=", "relation"},
    to = {"->", "relation"}, infty = {"oo", "ordinary"}, ldots = {"...", "ordinary"}, cdots = {"...", "ordinary"}, quad = {"  ", "ordinary"}}) do
    Lexer.symbols["\\" .. name] = item
end
Lexer.symbols["\\,"], Lexer.symbols["\\{"], Lexer.symbols["\\}"] = {" ", "ordinary"}, {"{", "open"}, {"}", "close"}
for command in pairs(Lexer.symbols) do
    local name = command:sub(2)
    if name:match("^[A-Za-z]+$") then Lexer.command_names[name] = true end
end
local accents = set("overline hat vec dot tilde overbrace underbrace")
local constructs = set("frac binom overset underset sqrt left right")
local raw_commands = set("text begin end tag label eqref")
local environments = set("matrix pmatrix bmatrix vmatrix cases")
local symbols = {}
for character in ("+-*/=<>:()[],;.!|'"):gmatch(".") do symbols[character] = true end

function Lexer.fail(column, message)
    error({column = column, message = message}, 0)
end

local function letter(character)
    return character ~= "" and ((character >= "A" and character <= "Z") or (character >= "a" and character <= "z"))
end

local function digit(character)
    return character ~= "" and character >= "0" and character <= "9"
end

function Lexer.tokenize(line)
    local tokens, position, length = {}, 1, #line
    local function emit(kind, value, column)
        tokens[#tokens + 1] = {kind = kind, value = value, column = column}
    end
    while position <= length do
        local character, column = line:sub(position, position), position
        if character == " " then position = position + 1
        elseif letter(character) then
            local finish = position + 1
            while letter(line:sub(finish, finish)) do finish = finish + 1 end
            emit("identifier", line:sub(position, finish - 1), column)
            position = finish
        elseif digit(character) then
            local finish = position + 1
            while digit(line:sub(finish, finish)) do finish = finish + 1 end
            if line:sub(finish, finish) == "." and digit(line:sub(finish + 1, finish + 1)) then
                finish = finish + 2
                while digit(line:sub(finish, finish)) do finish = finish + 1 end
            end
            emit("number", line:sub(position, finish - 1), column)
            position = finish
        elseif symbols[character] or character:match("^[{}^_&]$") then
            emit(symbols[character] and "symbol" or character, character, column)
            position = position + 1
        elseif character ~= "\\" then Lexer.fail(column, "invalid character " .. character)
        else
            position = position + 1
            local escaped = line:sub(position, position)
            if escaped == "\\" or escaped == "{" or escaped == "}" or escaped == "," then
                emit(escaped == "\\" and "newline" or "command", "\\" .. escaped, column)
                position = position + 1
            else
                local start = position
                while letter(line:sub(position, position)) do position = position + 1 end
                local name = line:sub(start, position - 1)
                if name == "" then Lexer.fail(column, "invalid command") end
                if raw_commands[name] then
                    while line:sub(position, position) == " " do position = position + 1 end
                    if line:sub(position, position) ~= "{" then Lexer.fail(position, "expected {") end
                    local finish = line:find("}", position + 1, true)
                    if not finish then Lexer.fail(column, "unterminated argument") end
                    local argument = line:sub(position + 1, finish - 1)
                    if (name == "begin" or name == "end") and not environments[argument] then Lexer.fail(column, 'unknown environment "' .. argument .. '"') end
                    emit(name, argument, column)
                    position = finish + 1
                elseif Lexer.symbols["\\" .. name] then emit("command", "\\" .. name, column)
                elseif accents[name] then emit("accent", name, column)
                elseif constructs[name] then emit(name, name, column)
                else Lexer.fail(column, "unknown command \\" .. name) end
            end
        end
    end
    emit("eof", "", length + 1)
    return tokens
end

return Lexer
