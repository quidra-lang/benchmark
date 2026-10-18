local pi = 3.141592653589793
for _, radius in ipairs({3, 7, 12, 25, 41}) do
    local area = pi * radius * radius
    local circumference = 2 * pi * radius
    area = math.floor(area * 1000 + 0.5) / 1000
    circumference = math.floor(circumference * 1000 + 0.5) / 1000
    io.write(string.format("r=%d area=%.3f circumference=%.3f\n", radius, area, circumference))
end
