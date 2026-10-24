numbers = [3,8,11,15,19,24,27,31,36,42,47,53,58,64,70,77]
for target in [42,3,77,31,50,1]
    lo, hi, found = 0, length(numbers)-1, -1
    probes = Int[]
    while lo <= hi
        mid = div(lo+hi, 2)
        push!(probes, mid)
        if numbers[mid+1] == target
            found = mid
            break
        elseif numbers[mid+1] < target
            lo = mid+1
        else
            hi = mid-1
        end
    end
    result = found >= 0 ? string("index ",found) : "not found"
    println(target, ": probes ", join(probes," "), " -> ", result)
end
