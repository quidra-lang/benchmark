const TABLE_KEYS = ((0,0),(1,0),(0,1),(1,1))
const TABLE_NAMES = ("dc_luma","ac_luma","dc_chroma","ac_chroma")
function category(value)
    n,magnitude = 0,abs(value)
    while magnitude!=0
        n += 1
        magnitude >>= 1
    end
    n
end
function extra_bits(value)
    n = category(value)
    (value>=0 ? value : value+(1<<n)-1),n
end
amplitude(bits,n) = n==0 ? 0 : bits>=(1<<(n-1)) ? bits : bits-(1<<n)+1
struct HuffmanTable
    counts::Vector{Int}
    symbols::Vector{Int}
    codes::Dict{Int,Tuple{Int,Int}}
    decode::Dict{Tuple{Int,Int},Int}
end
function HuffmanTable(counts,symbols)
    codes,decode = Dict{Int,Tuple{Int,Int}}(),Dict{Tuple{Int,Int},Int}()
    code,offset = 0,0
    for code_length in 1:16
        for symbol in symbols[offset+1:offset+counts[code_length]]
            codes[symbol],decode[(code_length,code)] = (code_length,code),symbol
            code += 1
        end
        offset += counts[code_length]
        code *= 2
    end
    HuffmanTable(copy(counts),copy(symbols),codes,decode)
end
function optimized_table(frequencies)
    frequencies = [frequencies;1]
    sizes,others = zeros(Int,257),fill(0,257)
    while true
        available = sort!(findall(>(0),frequencies);by=i->(frequencies[i],-i))
        length(available)<2 && break
        first,second = available[1:2]
        frequencies[first] += frequencies[second]
        frequencies[second] = 0
        sizes[first] += 1
        while others[first]!=0
            first = others[first]
            sizes[first] += 1
        end
        others[first] = second
        sizes[second] += 1
        while others[second]!=0
            second = others[second]
            sizes[second] += 1
        end
    end
    counts = zeros(Int,257)
    for size in sizes
        size>0 && (counts[size]+=1)
    end
    for code_length in maximum(sizes):-1:17
        while counts[code_length]>0
            shorter = code_length-2
            while counts[shorter]==0
                shorter -= 1
            end
            counts[code_length] -= 2
            counts[code_length-1] += 1
            counts[shorter+1] += 2
            counts[shorter] -= 1
        end
    end
    longest = findlast(>(0),counts[1:16])
    counts[longest] -= 1
    symbols = sort!([i-1 for i in 1:256 if sizes[i]>0];by=v->(sizes[v+1],v))
    HuffmanTable(counts[1:16],symbols)
end
