local row = {1}
for _ = 0, 11 do
    io.write(table.concat(row, " "), "\n")
    local next_row = {1}
    for k = 2, #row do next_row[k] = row[k - 1] + row[k] end
    next_row[#row + 1] = 1
    row = next_row
end
