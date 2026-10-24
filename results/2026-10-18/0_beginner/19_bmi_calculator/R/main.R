people <- list(c("Aiko", 158, 45), c("Kenji", 172, 68), c("Mika", 165, 70), c("Ryo", 180, 101), c("Yuki", 150, 52))
for (person in people) {
    height <- as.integer(person[2])
    weight <- as.integer(person[3])
    bmi <- (weight * 10000L) / (height * height)
    category <- if (bmi < 18.5) "underweight" else if (bmi < 25) "normal" else if (bmi < 30) "overweight" else "obese"
    cat(sprintf("%s: BMI %.1f (%s)\n", person[1], bmi, category))
}
