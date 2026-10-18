using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
static string Fixed(double x, int places) => Math.Round(x, places, MidpointRounding.AwayFromZero).ToString("F" + places, CultureInfo.InvariantCulture);
string[] names = { "Aiko","Kenji","Mika","Ryo","Yuki" };
int[] heights = { 158,172,165,180,150 }, weights = { 45,68,70,101,52 };
for (int i = 0; i < names.Length; i++) {
    double bmi = (double)(weights[i] * 10000) / (heights[i] * heights[i]);
    string category = bmi < 18.5 ? "underweight" : bmi < 25 ? "normal" : bmi < 30 ? "overweight" : "obese";
    Console.WriteLine($"{names[i]}: BMI {Fixed(bmi, 1)} ({category})");
}
