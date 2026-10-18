let value = 1
    for n in 0:12
        if n > 0
            value *= n
        end
        println(n, "! = ", value)
    end
end
