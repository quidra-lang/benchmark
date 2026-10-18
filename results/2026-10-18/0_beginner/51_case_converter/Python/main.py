import re

identifiers = ["user_name", "maxRetryCount", "ShoppingCartItem", "background-color", "get_last_login_time", "isEmailAddressValid"]
for identifier in identifiers:
    words = [word.lower() for word in re.split(r"[_-]|(?=[A-Z])", identifier) if word]
    snake = "_".join(words)
    camel = words[0] + "".join(word.capitalize() for word in words[1:])
    pascal = "".join(word.capitalize() for word in words)
    kebab = "-".join(words)
    print(f"{identifier}: snake={snake}, camel={camel}, pascal={pascal}, kebab={kebab}")
