local function capitalize(word) return word:sub(1,1):upper()..word:sub(2) end
for _, identifier in ipairs({"user_name","maxRetryCount","ShoppingCartItem","background-color","get_last_login_time","isEmailAddressValid"}) do
    local separated = identifier:gsub("([A-Z])"," %1"):gsub("[_-]"," "):lower()
    local words,capitals = {},{}
    for word in separated:gmatch("%S+") do
        words[#words+1] = word
        capitals[#capitals+1] = capitalize(word)
    end
    local camel = words[1]..table.concat(capitals,"",2)
    io.write(string.format("%s: snake=%s, camel=%s, pascal=%s, kebab=%s\n",identifier,table.concat(words,"_"),camel,table.concat(capitals),table.concat(words,"-")))
end
