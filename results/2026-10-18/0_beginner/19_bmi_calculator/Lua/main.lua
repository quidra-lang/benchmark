local people = {{"Aiko", 158, 45}, {"Kenji", 172, 68}, {"Mika", 165, 70}, {"Ryo", 180, 101}, {"Yuki", 150, 52}}
for _, person in ipairs(people) do
    local name, height, weight = person[1], person[2], person[3]
    local bmi = (weight * 10000) / (height * height)
    local category = bmi < 18.5 and "underweight" or bmi < 25 and "normal" or bmi < 30 and "overweight" or "obese"
    local rounded = math.floor(bmi * 10 + 0.5) / 10
    io.write(string.format("%s: BMI %.1f (%s)\n", name, rounded, category))
end
