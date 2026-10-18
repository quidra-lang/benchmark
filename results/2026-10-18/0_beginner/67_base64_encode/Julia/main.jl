function encode64(source)
    alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    bytes = codeunits(source)
    output = IOBuffer()
    for first in 1:3:length(bytes)
        remaining = min(3,length(bytes)-first+1)
        value = 0
        for offset in 0:2
            value = value*256+(offset < remaining ? Int(bytes[first+offset]) : 0)
        end
        for (offset,divisor) in enumerate([262144,4096,64,1])
            print(output,offset <= remaining+1 ? alphabet[div(value,divisor)%64+1] : '=')
        end
    end
    return String(take!(output))
end
for source in ["Man","Hello, World!","","<b>bold</b>","a+b=c?"]
    println('"',source,"\" -> \"",encode64(source),'"')
end
