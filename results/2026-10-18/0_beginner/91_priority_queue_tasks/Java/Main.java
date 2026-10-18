import java.util.*;
import java.math.*;

public class Main {
    record Task(String name, int priority, int sequence) {}
    public static void main(String[] args) {
        String[] operations = {"add email 3", "add backup 5", "add deploy 1", "run", "add report 3", "add test 2",
            "add lint 3", "run", "run", "add cleanup 5", "add review 2", "run", "add build 1",
            "add docs 4", "run", "run"};
        PriorityQueue<Task> queue = new PriorityQueue<>(Comparator.comparingInt(Task::priority).thenComparingInt(Task::sequence));
        int sequence = 0;
        for (String operation : operations) {
            String[] parts = operation.split(" ");
            if (parts[0].equals("add")) queue.add(new Task(parts[1],Integer.parseInt(parts[2]),sequence++));
            else {
                Task task = queue.remove();
                System.out.println("run: " + task.name() + " (priority " + task.priority() + ")");
            }
        }
        List<String> remaining = new ArrayList<>();
        while (!queue.isEmpty()) remaining.add(queue.remove().name());
        System.out.println("remaining: " + String.join(" ",remaining));
    }
}
