import java.util.*;
final class Modes {
    record Item(char sign, char character, String argument) {}
    static List<Item> channelItems(String mode, List<String> arguments) {
        List<Item> items = new ArrayList<>();
        char sign = '+';
        int position = 0;
        for (char c : mode.toCharArray()) {
            if (c == '+' || c == '-') {
                sign = c;
                continue;
            }
            String argument = null;
            if ("ovbk".indexOf(c) >= 0 || c == 'l' && sign == '+')
                if (position < arguments.size())
                    argument = arguments.get(position++);
            if (c == 'k' && sign == '-')
                argument = "*";
            else if (c == 'l' && sign == '+') {
                if (argument == null || !Protocol.digits(argument) || argument.length() > 4 ||
                    Integer.parseInt(argument) < 1)
                    argument = null;
            }
            items.add(new Item(sign, c, argument));
        }
        return items;
    }
    static String changeString(List<Item> changes) {
        StringBuilder mode = new StringBuilder();
        List<String> arguments = new ArrayList<>();
        char previous = 0;
        for (Item item : changes) {
            if (item.sign() != previous) {
                mode.append(item.sign());
                previous = item.sign();
            }
            mode.append(item.character());
            if (item.argument() != null)
                arguments.add(item.argument());
        }
        for (String argument : arguments)
            mode.append(" ").append(argument);
        return mode.toString();
    }
}
