const people = [
  {name: "Aiko", height: 158, weight: 45}, {name: "Kenji", height: 172, weight: 68},
  {name: "Mika", height: 165, weight: 70}, {name: "Ryo", height: 180, weight: 101},
  {name: "Yuki", height: 150, weight: 52}
];
for (const {name, height, weight} of people) {
  const bmi = weight * 10000 / (height * height);
  const category = bmi < 18.5 ? "underweight" : bmi < 25 ? "normal" : bmi < 30 ? "overweight" : "obese";
  console.log(`${name}: BMI ${bmi.toFixed(1)} (${category})`);
}
