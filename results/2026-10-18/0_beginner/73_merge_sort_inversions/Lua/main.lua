local function merge_sort(numbers, lo, hi)
    if lo == hi then return 0 end
    local mid = (lo + hi) // 2
    local inversions = merge_sort(numbers, lo, mid)
    inversions = inversions + merge_sort(numbers, mid + 1, hi)
    local left = {table.unpack(numbers, lo, mid)}
    local right = {table.unpack(numbers, mid + 1, hi)}
    local merged, i, j = {}, 1, 1
    while i <= #left and j <= #right do
        if left[i] <= right[j] then
            merged[#merged + 1] = left[i]
            i = i + 1
        else
            merged[#merged + 1] = right[j]
            j = j + 1
            inversions = inversions + #left - i + 1
        end
    end
    table.move(left, i, #left, #merged + 1, merged)
    table.move(right, j, #right, #merged + 1, merged)
    table.move(merged, 1, #merged, lo, numbers)
    io.write(string.format("merge [%d..%d]: %s\n", lo - 1, hi - 1, table.concat(merged, " ")))
    return inversions
end

local numbers = {47, 12, 85, 33, 6, 71, 29, 58, 90, 14}
local inversions = merge_sort(numbers, 1, #numbers)
io.write("sorted: ", table.concat(numbers, " "), "\n", string.format("inversions: %d\n", inversions))
