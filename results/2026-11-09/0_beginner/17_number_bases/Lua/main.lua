local function binary(n)
    if n == 0 then return "0" end
    local result = ""
    while n > 0 do
        result = (n % 2) .. result
        n = n // 2
    end
    return result
end

for _, n in ipairs({0, 10, 255, 1000, 43981, 65535}) do
    io.write(string.format("%d: bin=%s oct=%o hex=%X\n", n, binary(n), n, n))
end
