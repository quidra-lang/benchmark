local text = "The cat sat on the mat. The dog sat on the rug, and the cat watched the dog. A bird sang on the fence, and the Dog barked at the bird. The cat slept in the sun, the bird flew away, and the dog sat by the door."
local frequencies = {}
for word in text:lower():gmatch("[a-z]+") do frequencies[word] = (frequencies[word] or 0)+1 end
local words = {}; for word in pairs(frequencies) do words[#words+1] = word end
table.sort(words,function(a,b) if frequencies[a] ~= frequencies[b] then return frequencies[a] > frequencies[b] end return a < b end)
for i = 1,5 do io.write(string.format("%s: %d\n",words[i],frequencies[words[i]])) end
io.write(string.format("distinct words: %d\n",#words))
