people = [['Aiko', 158, 45], ['Kenji', 172, 68], ['Mika', 165, 70], ['Ryo', 180, 101], ['Yuki', 150, 52]]
people.each do |name, height, weight|
  bmi = (weight * 10000).fdiv(height * height)
  category = bmi < 18.5 ? 'underweight' : bmi < 25 ? 'normal' : bmi < 30 ? 'overweight' : 'obese'
  puts format('%s: BMI %.1f (%s)', name, bmi, category)
end
