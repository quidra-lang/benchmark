import java.util.*;
import java.math.*;

public class Main {
    static int hanoi(int n, char source, char target, char auxiliary) {
        if (n == 0) return 0;
        int count = hanoi(n - 1, source, auxiliary, target);
        System.out.println("move disk " + n + " from " + source + " to " + target);
        return count + 1 + hanoi(n - 1, auxiliary, target, source);
    }
    public static void main(String[] args) {
        System.out.println("total moves: " + hanoi(4, 'A', 'C', 'B'));
    }
}
