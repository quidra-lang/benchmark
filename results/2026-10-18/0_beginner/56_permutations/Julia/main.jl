function main()
    characters = collect("ABCD")
    used = falses(4)
    counter = Ref(0)
    function visit(prefix)
        if length(prefix) == 4
            counter[] += 1
            println(counter[],": ",prefix)
            return
        end
        for i in 1:4
            if !used[i]
                used[i] = true
                visit(string(prefix,characters[i]))
                used[i] = false
            end
        end
    end
    visit("")
end
main()
