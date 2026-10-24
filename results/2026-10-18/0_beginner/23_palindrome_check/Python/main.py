phrases = ["Never odd or even", "Race a car", "Was it a car or a cat I saw?", "Hello, World!", "Step on no pets.", "No lemon, no melon"]
for phrase in phrases:
    letters = "".join(c for c in phrase.lower() if "a" <= c <= "z")
    result = "yes" if letters == letters[::-1] else "no"
    print(f"{phrase} -> {result}")
