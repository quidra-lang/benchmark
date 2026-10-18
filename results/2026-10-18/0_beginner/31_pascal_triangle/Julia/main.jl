function main()
    row = [1]
    for n in 0:11
        println(join(row, " "))
        next = ones(Int, length(row)+1)
        for k in 2:length(row)
            next[k] = row[k-1] + row[k]
        end
        row = next
    end
end
main()
