using System.Collections.Generic;
using System.Text;
public static class Modes {
    public record Item(char sign, char character, string argument);
    public static List<Item> ChannelItems(string mode, List<string> arguments) {
        List<Item> items = new();
        char sign = '+';
        int position = 0;
        foreach (char c in mode) {
            if (c == '+' || c == '-') {
                sign = c;
                continue;
            }
            string argument = null;
            if ("ovbk".IndexOf(c) >= 0 || c == 'l' && sign == '+')
                if (position < arguments.Count)
                    argument = arguments[position++];
            if (c == 'k' && sign == '-')
                argument = "*";
            else if (c == 'l' && sign == '+') {
                if (argument == null || !Protocol.Digits(argument) || argument.Length > 4 ||
                    int.Parse(argument) < 1)
                    argument = null;
            }
            items.Add(new(sign, c, argument));
        }
        return items;
    }
    public static string ChangeString(List<Item> changes) {
        StringBuilder mode = new();
        List<string> arguments = new();
        char previous = '\0';
        foreach (Item item in changes) {
            if (item.sign != previous) {
                mode.Append(item.sign);
                previous = item.sign;
            }
            mode.Append(item.character);
            if (item.argument != null)
                arguments.Add(item.argument);
        }
        foreach (string argument in arguments)
            mode.Append(" ").Append(argument);
        return mode.ToString();
    }
}
