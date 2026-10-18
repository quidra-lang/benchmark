function main()
    counts = zeros(Int, 26)
    for letter in lowercase("Peter Piper picked a peck of pickled peppers!")
        if 'a' <= letter <= 'z'
            counts[Int(letter)-Int('a')+1] += 1
        end
    end
    for (index, letter) in enumerate('a':'z')
        if counts[index] > 0
            println(letter, ": ", counts[index])
        end
    end
end
main()
