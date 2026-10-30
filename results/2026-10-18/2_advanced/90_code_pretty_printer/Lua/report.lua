local M = {}
function M.tree(document, result, depth)
    result, depth = result or {}, depth or 0
    local kind, prefix = document.kind, string.rep("  ", depth)
    if kind == "concat" then
        for _, child in ipairs(document.items) do M.tree(child, result, depth) end
        return result
    end
    local description = kind
    if kind == "text" or kind == "suffix" then description = kind .. ' "' .. document.value .. '"'
    elseif kind == "if_break" then description = 'if_break "' .. document.broken .. '" "' .. document.flat .. '"'
    elseif kind == "group" then description = "group " .. document.mode
    elseif kind == "nest" then description = "nest " .. document.amount end
    result[#result + 1] = prefix .. description
    if document.child then M.tree(document.child, result, depth + 1) end
    return result
end

function M.diff(original, formatted)
    local n, m, dp = #original, #formatted, {}
    for i = 1, n + 1 do
        dp[i] = {}
        for j = 1, m + 1 do dp[i][j] = 0 end
    end
    for i = n, 1, -1 do
        for j = m, 1, -1 do
            if original[i] == formatted[j] then dp[i][j] = 1 + dp[i + 1][j + 1]
            else dp[i][j] = math.max(dp[i + 1][j], dp[i][j + 1]) end
        end
    end
    local i, j, deleted, inserted = 1, 1, 0, 0
    local hunks, current = {}, false
    local function finish()
        if current then hunks[#hunks + 1], current = current, false end
    end
    while i <= n or j <= m do
        if i <= n and j <= m and original[i] == formatted[j] then
            finish()
            i, j = i + 1, j + 1
        else
            if not current then current = { old = i - 1, new = j - 1, deleted = 0, inserted = 0, lines = {} } end
            if j > m or (i <= n and dp[i + 1][j] >= dp[i][j + 1]) then
                current.deleted, deleted = current.deleted + 1, deleted + 1
                current.lines[#current.lines + 1] = "-" .. original[i]
                i = i + 1
            else
                current.inserted, inserted = current.inserted + 1, inserted + 1
                current.lines[#current.lines + 1] = "+" .. formatted[j]
                j = j + 1
            end
        end
    end
    finish()
    local result = { string.format("hunks=%d deleted=%d inserted=%d", #hunks, deleted, inserted) }
    for _, hunk in ipairs(hunks) do
        result[#result + 1] = string.format("@@ -%d,%d +%d,%d @@",
            hunk.old + (hunk.deleted > 0 and 1 or 0), hunk.deleted,
            hunk.new + (hunk.inserted > 0 and 1 or 0), hunk.inserted)
        for _, line in ipairs(hunk.lines) do result[#result + 1] = line end
    end
    return result
end

return M
