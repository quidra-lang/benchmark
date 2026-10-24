function main()
    row = [1]
    for n in 0:11
        println(join(row, " "))
        row = vcat(1, row[1:end-1] .+ row[2:end], 1)
    end
end
main()
