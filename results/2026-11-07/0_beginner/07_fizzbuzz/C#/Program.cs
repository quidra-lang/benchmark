using System;
using System.Globalization;

for (int n = 1; n <= 30; n++)
{
    if (n % 15 == 0) Console.WriteLine("FizzBuzz");
    else if (n % 3 == 0) Console.WriteLine("Fizz");
    else if (n % 5 == 0) Console.WriteLine("Buzz");
    else Console.WriteLine(n.ToString(CultureInfo.InvariantCulture));
}
