local M = {}
function M.integer_word(word)
    return word:match("^%-?%d+$") ~= nil
end
function M.words(line)
    local result = {}
    for word in line:gmatch("[^ ]+") do
        result[#result + 1] = word
    end
    return result
end
function M.read()
    local source = {lines = 0, vertices = {}, polygons = {}, errors = {}, ignored = 0}
    local group = "default"
    local ignored = {vt = true, vn = true, s = true, o = true, usemtl = true, mtllib = true}
    for line in io.lines("input/model.obj") do
        source.lines = source.lines + 1
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local words, reason = M.words(line), nil
            local keyword = table.remove(words, 1)
            if keyword == "v" then
                local valid = #words == 3
                for _, word in ipairs(words) do
                    valid = valid and M.integer_word(word)
                end
                if valid then
                    source.vertices[#source.vertices + 1] = {tonumber(words[1]), tonumber(words[2]), tonumber(words[3])}
                else
                    reason = "bad_vertex"
                end
            elseif keyword == "f" then
                if #words < 3 then
                    reason = "short_face"
                else
                    local vertices = {}
                    for _, reference in ipairs(words) do
                        local part = reference:match("^([^/]*)")
                        if not M.integer_word(part) or tonumber(part) == 0 then
                            reason = "bad_index"
                            break
                        end
                        local number = tonumber(part)
                        if number < 0 then
                            number = #source.vertices + 1 + number
                        end
                        if number < 1 or number > #source.vertices then
                            reason = "out_of_range"
                            break
                        end
                        vertices[#vertices + 1] = number
                    end
                    if not reason then
                        source.polygons[#source.polygons + 1] = {number = #source.polygons + 1, line = source.lines, group = group, vertices = vertices}
                    end
                end
            elseif keyword == "g" then
                group = words[1] or "default"
            elseif ignored[keyword] then
                source.ignored = source.ignored + 1
            else
                reason = "unknown_keyword"
            end
            if reason then
                source.errors[#source.errors + 1] = {line = source.lines, kind = reason}
            end
        end
    end
    return source
end
function M.repaired(points, faces)
    local lines = {"# vertices " .. #points .. " faces " .. #faces}
    for _, point in ipairs(points) do
        lines[#lines + 1] = "v " .. table.concat(point, " ")
    end
    local previous
    for _, face in ipairs(faces) do
        if previous ~= face.group then
            lines[#lines + 1], previous = "g " .. face.group, face.group
        end
        lines[#lines + 1] = "f " .. table.concat(face.vertices, " ")
    end
    return lines
end
return M
