local scoring = {}

function scoring.is_letter(c)
    return c:match("^[A-Za-z]$") ~= nil
end

function scoring.value(c)
    local code = string.byte(c)
    return code >= 97 and code - 97 or code - 65
end

function scoring.upper(value)
    return string.char(65 + value)
end

function scoring.letters(text)
    return (text:gsub("[A-Za-z]", function(c)
        return scoring.upper(scoring.value(c))
    end):gsub("[^A-Z]", ""))
end

function scoring.groups(text)
    local lines, words = {}, {}
    for i = 1, #text, 5 do
        words[#words + 1] = text:sub(i, i + 4)
        if #words == 10 then
            lines[#lines + 1] = table.concat(words, " ")
            words = {}
        end
    end
    if #words > 0 then
        lines[#lines + 1] = table.concat(words, " ")
    end
    return lines
end

function scoring.monogram(text, weights)
    local score = 0
    for i = 1, #text do
        score = score + weights[string.byte(text, i) - 64]
    end
    return score
end

function scoring.bigram(text, weights)
    local score = 0
    for i = 2, #text do
        score = score + weights[string.byte(text, i - 1) - 64]
            [string.byte(text, i) - 64]
    end
    return score
end

function scoring.read(path)
    local lines = {}
    for line in io.lines(path) do
        lines[#lines + 1] = line
    end
    local function values(line)
        local result = {}
        for number in line:gmatch("%d+") do
            result[#result + 1] = tonumber(number)
        end
        return result
    end
    local mono, bi = values(lines[2]), {}
    for row = 1, 26 do
        bi[row] = values(lines[row + 3])
    end
    return mono, bi
end

return scoring
