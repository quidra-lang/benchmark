local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
local codes = ".- -... -.-. -.. . ..-. --. .... .. .--- -.- .-.. -- -. --- .--. --.- .-. ... - ..- ...- .-- -..- -.-- --.. ----- .---- ..--- ...-- ....- ..... -.... --... ---.. ----."
local mapping,reverse_mapping,index = {},{},1
for code in codes:gmatch("%S+") do local letter = alphabet:sub(index,index); mapping[letter] = code; reverse_mapping[code] = letter; index = index+1 end
local words = {}
for word in ("MEET ME AT PIER 9 AT 1745"):gmatch("%S+") do
    local letters = {}; for letter in word:gmatch(".") do letters[#letters+1] = mapping[letter] end
    words[#words+1] = table.concat(letters," ")
end
local encoded = table.concat(words," / ")
local decoded_words = {}
for word in encoded:gmatch("[^/]+") do
    local letters = {}; for code in word:gmatch("%S+") do letters[#letters+1] = reverse_mapping[code] end
    decoded_words[#decoded_words+1] = table.concat(letters)
end
io.write(encoded,"\n",table.concat(decoded_words," "),"\n")
