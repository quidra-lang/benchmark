function merge_sort!(numbers, lo, hi)
    lo == hi && return 0
    mid = div(lo+hi, 2)
    inversions = merge_sort!(numbers, lo, mid)
    inversions += merge_sort!(numbers, mid+1, hi)
    left, right = numbers[lo:mid], numbers[(mid+1):hi]
    merged = Int[]
    i, j = 1, 1
    while i <= length(left) && j <= length(right)
        if left[i] <= right[j]
            push!(merged, left[i])
            i += 1
        else
            push!(merged, right[j])
            j += 1
            inversions += length(left)-i+1
        end
    end
    append!(merged, left[i:end])
    append!(merged, right[j:end])
    numbers[lo:hi] = merged
    println("merge [", lo-1, "..", hi-1, "]: ", join(merged, " "))
    return inversions
end

numbers = [47, 12, 85, 33, 6, 71, 29, 58, 90, 14]
inversions = merge_sort!(numbers, 1, length(numbers))
println("sorted: ", join(numbers, " "))
println("inversions: ", inversions)
