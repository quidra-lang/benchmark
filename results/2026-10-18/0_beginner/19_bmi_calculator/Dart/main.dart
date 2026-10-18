void main() {
    for (final p in [('Aiko', 158, 45), ('Kenji', 172, 68), ('Mika', 165, 70), ('Ryo', 180, 101),
        ('Yuki', 150, 52)]) {
        final bmi = (p.$3 * 10000) / (p.$2 * p.$2);
        final category = bmi < 18.5 ? 'underweight' : bmi < 25 ? 'normal' : bmi < 30 ? 'overweight' : 'obese';
        print('${p.$1}: BMI ${bmi.toStringAsFixed(1)} ($category)');
    }
}
