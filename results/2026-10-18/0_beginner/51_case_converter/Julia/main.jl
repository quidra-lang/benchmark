for identifier in ["user_name","maxRetryCount","ShoppingCartItem","background-color","get_last_login_time","isEmailAddressValid"]
    separated = replace(identifier,r"([A-Z])" => s" \1")
    separated = replace(separated,'_'=>' ','-'=>' ')
    words = split(lowercase(separated))
    capitals = [uppercasefirst(word) for word in words]
    println(identifier,": snake=",join(words,"_"),", camel=",words[1],join(capitals[2:end]),", pascal=",join(capitals),", kebab=",join(words,"-"))
end
