local function merge_sort(numbers,lo,hi)
    if lo == hi then return 0 end
    local mid = (lo+hi)//2
    local inversions = merge_sort(numbers,lo,mid)
    inversions = inversions+merge_sort(numbers,mid+1,hi)
    local left,right = {},{}
    for i = lo,mid do left[#left+1] = numbers[i] end
    for i = mid+1,hi do right[#right+1] = numbers[i] end
    local merged,i,j = {},1,1
    while i <= #left and j <= #right do
        if left[i] <= right[j] then
            merged[#merged+1] = left[i]
            i = i+1
        else
            merged[#merged+1] = right[j]
            j = j+1
            inversions = inversions+#left-i+1
        end
    end
    for k = i,#left do merged[#merged+1] = left[k] end
    for k = j,#right do merged[#merged+1] = right[k] end
    for k,value in ipairs(merged) do numbers[lo+k-1] = value end
    io.write(string.format("merge [%d..%d]: %s\n",lo-1,hi-1,table.concat(merged," ")))
    return inversions
end
local numbers = {47,12,85,33,6,71,29,58,90,14}
local inversions = merge_sort(numbers,1,#numbers)
io.write("sorted: ",table.concat(numbers," "),"\n",string.format("inversions: %d\n",inversions))
