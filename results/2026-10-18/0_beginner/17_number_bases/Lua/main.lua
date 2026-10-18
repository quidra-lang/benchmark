local function to_base(n, base)
    if n == 0 then return "0" end
    local alphabet, result = "0123456789ABCDEF", ""
    while n > 0 do
        local digit = n % base + 1
        result = alphabet:sub(digit, digit) .. result
        n = n // base
    end
    return result
end
for _, n in ipairs({0, 10, 255, 1000, 43981, 65535}) do
    io.write(string.format("%d: bin=%s oct=%s hex=%s\n", n, to_base(n, 2), to_base(n, 8), to_base(n, 16)))
end
