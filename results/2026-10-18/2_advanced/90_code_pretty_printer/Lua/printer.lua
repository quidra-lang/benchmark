local M = {}
local function push_children(stack, indent, mode, doc)
    for i = #doc.items, 1, -1 do stack[#stack + 1] = { indent, mode, doc.items[i] } end
end

local function fits(remaining, candidate, rest)
    if remaining < 0 then return false end
    local stack, next_rest = { candidate }, #rest
    while true do
        if #stack == 0 then
            if next_rest == 0 then return true end
            stack[1], next_rest = rest[next_rest], next_rest - 1
        end
        local entry = table.remove(stack)
        local indent, mode, doc = entry[1], entry[2], entry[3]
        local kind = doc.kind
        if kind == "text" then remaining = remaining - #doc.value
        elseif kind == "if_break" then remaining = remaining - #(mode == "break" and doc.broken or doc.flat)
        elseif kind == "line" then
            if mode == "break" then return true end
            remaining = remaining - 1
        elseif kind == "softline" then
            if mode == "break" then return true end
        elseif kind == "hardline" then return true
        elseif kind == "concat" then push_children(stack, indent, mode, doc)
        elseif kind == "group" then
            stack[#stack + 1] = { indent, doc.forced and "break" or mode, doc.child }
        elseif kind == "nest" or kind == "align" then
            stack[#stack + 1] = { indent, mode, doc.child }
        end
        if remaining < 0 then return false end
    end
end

function M.layout(document, profile)
    local result, pending = {}, {}
    local current = ""
    local stack = { { 0, "break", document } }
    local function finish()
        local output = current:gsub(" +$", "")
        if #pending > 0 then
            local comment = table.concat(pending, " ")
            local column = profile.comment_column
            if column > 0 and #output < column - 1 and column - 1 + #comment <= profile.width then
                output = output .. string.rep(" ", column - 1 - #output) .. comment
            else output = output .. " " .. comment end
            pending = {}
        end
        result[#result + 1] = output
    end
    while #stack > 0 do
        local entry = table.remove(stack)
        local indent, mode, doc = entry[1], entry[2], entry[3]
        local kind = doc.kind
        if kind == "text" then current = current .. doc.value
        elseif kind == "if_break" then current = current .. (mode == "break" and doc.broken or doc.flat)
        elseif kind == "line" and mode == "flat" then current = current .. " "
        elseif kind == "hardline" or ((kind == "line" or kind == "softline") and mode == "break") then
            finish()
            current = string.rep(" ", indent)
        elseif kind == "concat" then push_children(stack, indent, mode, doc)
        elseif kind == "nest" then stack[#stack + 1] = { indent + doc.amount, mode, doc.child }
        elseif kind == "align" then stack[#stack + 1] = { #current, mode, doc.child }
        elseif kind == "suffix" then pending[#pending + 1] = doc.value
        elseif kind == "group" then
            local selected
            if mode == "flat" then selected = "flat"
            elseif doc.forced then selected = "forced"
            elseif fits(profile.width - #current, { indent, "flat", doc.child }, stack) then selected = "flat"
            else selected = "break" end
            doc.mode = selected
            stack[#stack + 1] = { indent, selected == "flat" and "flat" or "break", doc.child }
        end
    end
    finish()
    return result
end

return M
