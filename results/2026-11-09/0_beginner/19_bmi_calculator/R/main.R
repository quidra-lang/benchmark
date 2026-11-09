people <- data.frame(
  name = c("Aiko", "Kenji", "Mika", "Ryo", "Yuki"),
  height = c(158L, 172L, 165L, 180L, 150L), weight = c(45L, 68L, 70L, 101L, 52L)
)
for (i in seq_len(nrow(people))) {
  height <- people$height[i]
  weight <- people$weight[i]
  bmi <- (weight * 10000L) / (height * height)
  category <- if (bmi < 18.5) "underweight" else if (bmi < 25) "normal" else if (bmi < 30) "overweight" else "obese"
  cat(sprintf("%s: BMI %.1f (%s)\n", people$name[i], bmi, category))
}
