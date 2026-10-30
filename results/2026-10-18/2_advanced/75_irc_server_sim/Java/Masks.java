final class Masks {
    static boolean matches(String inputMask, String inputValue) {
        String mask = Protocol.fold(inputMask), value = Protocol.fold(inputValue);
        int pattern = 0, position = 0, star = -1, restart = 0;
        while (position < value.length()) {
            if (pattern < mask.length() && mask.charAt(pattern) == '*') {
                star = pattern++;
                restart = position;
            } else if (pattern < mask.length() &&
                       (mask.charAt(pattern) == '?' ||
                        mask.charAt(pattern) == value.charAt(position))) {
                pattern++;
                position++;
            } else if (star >= 0) {
                position = ++restart;
                pattern = star + 1;
            } else
                return false;
        }
        while (pattern < mask.length() && mask.charAt(pattern) == '*')
            pattern++;
        return pattern == mask.length();
    }
    static String normalize(String argument) {
        if (argument.contains("!") && argument.contains("@"))
            return argument;
        if (argument.contains("@"))
            return "*!" + argument;
        if (argument.contains("!"))
            return argument + "@*";
        if (argument.contains("."))
            return "*!*@" + argument;
        return argument + "!*@*";
    }
}
