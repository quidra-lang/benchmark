function encode(source)
    result = IOBuffer()
    i = 1
    while i <= length(source)
        j = i+1
        while j <= length(source) && source[j] == source[i]
            j += 1
        end
        print(result,j-i,source[i])
        i = j
    end
    return String(take!(result))
end
function decode(encoded)
    result = IOBuffer()
    quantity = 0
    for c in encoded
        if '0' <= c <= '9'
            quantity = quantity*10 + Int(c)-Int('0')
        else
            print(result,repeat(string(c),quantity))
            quantity = 0
        end
    end
    return String(take!(result))
end
for source in ["AAABBBCCCD","WWWWWWWWWWWWBWWWWWWWWWWWWBBB","ALGORITHM","MISSISSIPPI","XXXXXXXXXXYYYYYYYYYYYYYYYYYYYYYZ"]
    encoded = encode(source)
    println(source," -> ",encoded," -> ",decode(encoded))
end
