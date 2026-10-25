function caesar(message, shift)
    return map(message) do c
        if 'A' <= c <= 'Z'
            Char(Int('A') + mod(Int(c)-Int('A')+shift, 26))
        elseif 'a' <= c <= 'z'
            Char(Int('a') + mod(Int(c)-Int('a')+shift, 26))
        else
            c
        end
    end
end
ciphertext = caesar("Zoe, meet Max by the Old Bridge at six!", 3)
println(ciphertext)
println(caesar(ciphertext, -3))
