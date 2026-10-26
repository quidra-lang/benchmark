local polygon = {{1, 1}, {11, 2}, {13, 9}, {9, 7}, {7, 12}, {5, 6}, {2, 10}, {3, 5}}
for _, point in ipairs({{4, 8}, {6, 4}, {10, 8}, {7, 11}, {14, 3}, {12, 8}}) do
    local px, py = table.unpack(point)
    local crossings = 0
    for i, vertex in ipairs(polygon) do
        local x1, y1 = table.unpack(vertex)
        local x2, y2 = table.unpack(polygon[i % #polygon + 1])
        if (y1 > py) ~= (y2 > py) then
            local intersection = x1 + (x2 - x1) * (py - y1) / (y2 - y1)
            if intersection > px then crossings = crossings + 1 end
        end
    end
    io.write(string.format("(%d, %d): %s\n", px, py, crossings % 2 == 1 and "inside" or "outside"))
end
