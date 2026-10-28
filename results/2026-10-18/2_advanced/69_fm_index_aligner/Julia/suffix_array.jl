const SYMBOLS = ['\$','#','A','C','G','T']
const SYMBOL_NUMBER = Dict(symbol=>i-1 for (i,symbol) in enumerate(SYMBOLS))
const BASES = ['A','C','G','T']
function counting_sort(positions,keys,key_count)
    counts = zeros(Int,key_count)
    for position in positions
        counts[keys[position+1]+1] += 1
    end
    offset = 0
    for key in eachindex(counts)
        n = counts[key]
        counts[key] = offset
        offset += n
    end
    result = zeros(Int,length(positions))
    for position in positions
        key = keys[position+1]+1
        result[counts[key]+1] = position
        counts[key] += 1
    end
    result
end
function build_suffix_array(text)
    n = length(text)
    codes = [SYMBOL_NUMBER[symbol] for symbol in text]
    order = counting_sort(0:n-1,codes,length(SYMBOLS))
    ranks,count_classes,previous = zeros(Int,n),0,-1
    for position in order
        if codes[position+1]!=previous
            count_classes += 1
            previous = codes[position+1]
        end
        ranks[position+1] = count_classes-1
    end
    classes,width = [count_classes],1
    while count_classes<n
        second = [position+width<n ? ranks[position+width+1]+1 : 0 for position in 0:n-1]
        order = counting_sort(0:n-1,second,count_classes+1)
        order = counting_sort(order,ranks,count_classes)
        updated,count_classes,previous = zeros(Int,n),0,(-1,-1)
        for position in order
            key = (ranks[position+1],second[position+1])
            if key!=previous
                count_classes += 1
                previous = key
            end
            updated[position+1] = count_classes-1
        end
        ranks = updated
        push!(classes,count_classes)
        width *= 2
    end
    order,classes
end
direct_sort(text) = sort!(collect(0:length(text)-1);by=position->text[position+1:end])
function adjacent_check(text,suffixes)
    ordered,lcp_sum,longest,longest_row = 0,0,-1,1
    for row in 1:length(suffixes)-1
        left,right = suffixes[row],suffixes[row+1]
        common = 0
        while text[left+common+1]==text[right+common+1]
            common += 1
        end
        ordered += SYMBOL_NUMBER[text[left+common+1]]<SYMBOL_NUMBER[text[right+common+1]]
        lcp_sum += common
        common>longest && ((longest,longest_row)=(common,row))
    end
    (ordered=ordered,lcp_sum=lcp_sum,longest=longest,row=longest_row)
end
