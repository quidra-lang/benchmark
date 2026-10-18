encode(source) = join(string(length(m.match), first(m.match)) for m in eachmatch(r"([A-Z])\1*", source))
decode(encoded) = replace(encoded, r"[0-9]+[A-Z]" => run -> repeat(string(run[end]), parse(Int, run[1:end-1])))
for source in ["AAABBBCCCD","WWWWWWWWWWWWBWWWWWWWWWWWWBBB","ALGORITHM","MISSISSIPPI","XXXXXXXXXXYYYYYYYYYYYYYYYYYYYYYZ"]
    encoded = encode(source)
    println(source," -> ",encoded," -> ",decode(encoded))
end
