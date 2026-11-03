using System.Globalization;

static class Report
{
    public static string Fixed(double value, int places = 4)
    {
        string text = value.ToString("F" + places, CultureInfo.InvariantCulture);
        return text.StartsWith('-') && double.Parse(text, CultureInfo.InvariantCulture) == 0 ? text[1..] : text;
    }
    public static double FourDecimal(double value) => double.Parse(Fixed(value), CultureInfo.InvariantCulture);
    public static string Ratio(int numerator, int denominator) => $"{numerator}/{denominator} {Fixed((double)numerator / denominator)}";
    public static string Fraction(int numerator, int denominator)
    {
        if (denominator == 0) return "- -";
        int a = numerator, b = denominator; while (b != 0) (a, b) = (b, a % b);
        return $"{numerator / a}/{denominator / a} {Fixed((double)numerator / denominator)}";
    }
    public static void Write(string name, List<string> lines)
    {
        Directory.CreateDirectory("output"); File.WriteAllText(Path.Combine("output", name), string.Join("\n", lines) + "\n", System.Text.Encoding.ASCII);
    }
}
