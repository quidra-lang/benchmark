package main

import "fmt"

func main() {
	people := []struct {
		name string
		h, w int
	}{{"Aiko", 158, 45}, {"Kenji", 172, 68}, {"Mika", 165, 70}, {"Ryo", 180, 101}, {"Yuki", 150, 52}}
	for _, p := range people {
		numerator, denominator := p.w*10000, p.h*p.h
		bmi := float64(numerator) / float64(denominator)
		category := "obese"
		if bmi < 18.5 {
			category = "underweight"
		} else if bmi < 25 {
			category = "normal"
		} else if bmi < 30 {
			category = "overweight"
		}
		fmt.Printf("%s: BMI %.1f (%s)\n", p.name, bmi, category)
	}
}
