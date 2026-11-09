local M = {}
M.line, M.softline = { kind = "line" }, { kind = "softline" }
M.hardline, M.break_parent = { kind = "hardline" }, { kind = "break_parent" }
function M.text(value) return { kind = "text", value = value } end
function M.suffix(value) return { kind = "suffix", value = value } end
function M.if_break(broken, flat) return { kind = "if_break", broken = broken, flat = flat } end

function M.concat(...)
    local children = {}
    local function add(part)
        if not part then return end
        if type(part) == "string" then part = M.text(part) end
        if not part.kind or part.kind == "concat" then
            for _, child in ipairs(part.items or part) do add(child) end
        elseif part.kind == "text" then
            if part.value == "" then return end
            local last = children[#children]
            if last and last.kind == "text" then
                children[#children] = M.text(last.value .. part.value)
            else children[#children + 1] = M.text(part.value) end
        else children[#children + 1] = part end
    end
    for i = 1, select("#", ...) do add(select(i, ...)) end
    if #children == 0 then return M.text("") end
    if #children == 1 then return children[1] end
    return { kind = "concat", items = children }
end

local function forced(doc)
    if doc.kind == "hardline" or doc.kind == "break_parent" then return true end
    if doc.kind == "concat" then
        for _, child in ipairs(doc.items) do if forced(child) then return true end end
    elseif doc.child then return forced(doc.child) end
    return false
end

function M.group(child)
    child = M.concat(child)
    return { kind = "group", child = child, forced = forced(child), mode = false }
end
function M.nest(amount, child) return { kind = "nest", amount = amount, child = M.concat(child) } end
function M.align(child) return { kind = "align", child = M.concat(child) } end

function M.groups(doc, result)
    result = result or {}
    if not doc then return result end
    if doc.kind == "group" then result[#result + 1] = doc end
    if doc.child then M.groups(doc.child, result)
    elseif doc.items then for _, child in ipairs(doc.items) do M.groups(child, result) end end
    return result
end

return M
