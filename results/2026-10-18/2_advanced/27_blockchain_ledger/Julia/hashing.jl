function digest(text)
    join(map(((1000003,11),(1500007,23),(2750159,37),(4194301,53))) do lane
        base, h = lane
        for c in codeunits(text)
            h = (h * base + c) % 2147483647
        end
        for c in (ncodeunits(text), 0, 0)
            h = (h * base + c) % 2147483647
        end
        string(h, base=16, pad=8)
    end)
end
function merkle_root(hashes)
    level = collect(hashes)
    while length(level) > 1
        isodd(length(level)) && push!(level, level[end])
        level = [digest(level[i] * level[i+1]) for i in 1:2:length(level)]
    end
    only(level)
end
short_hash(text) = text[1:8]
