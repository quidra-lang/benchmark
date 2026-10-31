local M = {}
function M.choose_pages(blocks, footnote_heights, height, orphan, widow)
    local lines, boundaries = {}, {}
    for i, block in ipairs(blocks) do
        local start = #lines
        for _, line in ipairs(block.lines) do
            lines[#lines + 1] = line
        end
        local count = #block.lines
        if block.kind == "flow" then
            for kept = 1, count - 1 do
                if kept >= orphan and count - kept >= widow then
                    boundaries[#boundaries + 1] = {finish = start + kept, next_start = start + kept, forced = false}
                end
            end
        end
        if i == #blocks then
            boundaries[#boundaries + 1] = {finish = #lines, next_start = #lines, forced = true}
        else
            local following, finish = blocks[i + 1], #lines
            if not (block.list and following.list) then
                lines[#lines + 1] = {text = "", footnotes = {}, indexes = {}}
            end
            if following.page_break or block.kind ~= "heading" then
                boundaries[#boundaries + 1] = {finish = finish, next_start = #lines, forced = following.page_break}
            end
        end
    end
    local pages, start, first_boundary = {}, 0, 1
    while start < #lines do
        local notes, note_height, scanned, chosen = {}, 0, start, nil
        for i = first_boundary, #boundaries do
            local boundary = boundaries[i]
            while scanned < boundary.finish do
                scanned = scanned + 1
                for _, number in ipairs(lines[scanned].footnotes) do
                    if not notes[number] then
                        notes[number] = true
                        note_height = note_height + footnote_heights[number]
                    end
                end
            end
            local page_notes = {}
            for number in pairs(notes) do
                page_notes[#page_notes + 1] = number
            end
            table.sort(page_notes)
            local used = boundary.finish - start + note_height + (#page_notes > 0 and 1 or 0)
            if used > height then
                break
            end
            chosen = {index = i, finish = boundary.finish, next_start = boundary.next_start,
                ends_by_force = boundary.forced, height = used, footnotes = page_notes}
            if boundary.forced then
                break
            end
        end
        local content = {}
        for i = start + 1, chosen.finish do
            content[#content + 1] = lines[i]
        end
        pages[#pages + 1] = {content = content, footnotes = chosen.footnotes, height = chosen.height, ends_by_force = chosen.ends_by_force, blank = false}
        start, first_boundary = chosen.next_start, chosen.index + 1
    end
    return pages
end
return M
