for _, amount in ipairs({3780, 15420, 99999, 506, 48263}) do
    local remaining, total, pieces = amount, 0, {}
    for _, face in ipairs({10000, 5000, 1000, 500, 100, 50, 10, 5, 1}) do
        local quantity = remaining // face
        remaining = remaining % face
        if quantity > 0 then
            pieces[#pieces + 1] = string.format("%dx%d", face, quantity)
            total = total + quantity
        end
    end
    io.write(string.format("%d yen: %s (%d pieces)\n", amount, table.concat(pieces, " "), total))
end
