local phrases = {"Never odd or even", "Race a car", "Was it a car or a cat I saw?", "Hello, World!", "Step on no pets.", "No lemon, no melon"}
for _, phrase in ipairs(phrases) do
    local clean = phrase:gsub("[^A-Za-z]", ""):lower()
    io.write(phrase, " -> ", clean == clean:reverse() and "yes" or "no", "\n")
end
