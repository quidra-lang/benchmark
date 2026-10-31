using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.RegularExpressions;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

string[] lines = { "width = 12", "height = width - 5", "area = width * height", "(area + 6) / 4",
    "shift = -area / 8 + 3", "height = 100 / (height - 7) + bonus", "volume = area * depth",
    "width = (width+3)*-(2-4)", "width * shift - height" };
var variables = new Dictionary<string, int>();
foreach (string line in lines)
{
    var tokens = Regex.Matches(line, "[0-9]+|[a-z]+|[^ ]")
        .Select(match => match.Value).ToList();
    bool assignment = tokens.Count > 1 && tokens[1] == "=";
    string? name = assignment ? tokens[0] : null;
    try
    {
        int result = new Parser(tokens, assignment ? 2 : 0, variables).Expression();
        if (assignment)
        {
            variables[name!] = result;
            Console.WriteLine($"{name} = {result}");
        }
        else
        {
            Console.WriteLine(result);
        }
    }
    catch (InvalidOperationException error)
    {
        Console.WriteLine($"error: {error.Message}");
    }
}

class Parser
{
    readonly List<string> tokens;
    readonly Dictionary<string, int> variables;
    int position;

    public Parser(List<string> tokens, int position, Dictionary<string, int> variables)
    {
        this.tokens = tokens;
        this.position = position;
        this.variables = variables;
    }

    bool Take(string token)
    {
        if (position >= tokens.Count || tokens[position] != token) return false;
        position++;
        return true;
    }

    public int Expression()
    {
        int result = Term();
        while (position < tokens.Count && (tokens[position] == "+" || tokens[position] == "-"))
        {
            string operation = tokens[position++];
            int right = Term();
            result = operation == "+" ? result + right : result - right;
        }
        return result;
    }

    int Term()
    {
        int result = Unary();
        while (position < tokens.Count && (tokens[position] == "*" || tokens[position] == "/"))
        {
            string operation = tokens[position++];
            int right = Unary();
            if (operation == "/" && right == 0) throw new InvalidOperationException("division by zero");
            result = operation == "*" ? result * right : result / right;
        }
        return result;
    }

    int Unary()
    {
        if (Take("-")) return -Unary();
        if (Take("("))
        {
            int result = Expression();
            Take(")");
            return result;
        }
        string token = tokens[position++];
        if (char.IsAsciiDigit(token[0])) return int.Parse(token, CultureInfo.InvariantCulture);
        if (!variables.TryGetValue(token, out int value))
            throw new InvalidOperationException("undefined variable " + token);
        return value;
    }
}
