for _, seconds in ipairs({0, 59, 3725, 45296, 86400, 312047}) do
    local hours = seconds // 3600
    local minutes = (seconds % 3600) // 60
    io.write(string.format("%d seconds = %02d:%02d:%02d\n", seconds, hours, minutes, seconds % 60))
end
