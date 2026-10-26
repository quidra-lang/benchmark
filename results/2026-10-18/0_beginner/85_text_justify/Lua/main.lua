local paragraph = "Good software is written for people first and for machines second. A clear program explains its purpose through careful names, small functions and honest tests. When a team agrees on shared rules for internationalization, documentation and code review, every newcomer can read the code quickly, change it safely and ship new improvements with confidence instead of fear, week after week."
local lines, current, letters = {}, {}, 0
for word in paragraph:gmatch("%S+") do
    if #current > 0 and letters + #current + #word > 30 then
        lines[#lines + 1] = current
        current, letters = {}, 0
    end
    current[#current + 1] = word
    letters = letters + #word
end
lines[#lines + 1] = current
for number, words in ipairs(lines) do
    local line
    if number == #lines or #words == 1 then
        line = table.concat(words, " ")
        line = line .. string.rep(" ", 30 - #line)
    else
        local total = 0
        for _, word in ipairs(words) do total = total + #word end
        local spaces, gaps = 30 - total, #words - 1
        local base, extra = spaces // gaps, spaces % gaps
        line = words[1]
        for i = 1, gaps do
            line = line .. string.rep(" ", base + (i <= extra and 1 or 0)) .. words[i + 1]
        end
    end
    io.write("|", line, "|\n")
end
