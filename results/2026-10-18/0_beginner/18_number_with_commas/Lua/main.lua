for _, n in ipairs({0, 7, 999, 1000, -456789, 3141592, 9876543210}) do
    local digits, groups = tostring(math.abs(n)), {}
    while #digits > 3 do
        table.insert(groups, 1, digits:sub(-3))
        digits = digits:sub(1, -4)
    end
    table.insert(groups, 1, digits)
    io.write(n < 0 and "-" or "", table.concat(groups, ","), "\n")
end
