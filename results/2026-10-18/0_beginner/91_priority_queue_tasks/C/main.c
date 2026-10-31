#include <stdio.h>
#include <string.h>

typedef struct {
    char name[32];
    int priority, order;
} Task;

int before(Task a, Task b) {
    return a.priority != b.priority ? a.priority < b.priority : a.order < b.order;
}

void push(Task *heap, int *size, Task task) {
    int i = (*size)++;
    while (i > 0) {
        int p = (i - 1) / 2;
        if (!before(task, heap[p]))
            break;
        heap[i] = heap[p];
        i = p;
    }
    heap[i] = task;
}

Task pop(Task *heap, int *size) {
    Task result = heap[0], last = heap[--*size];
    if (*size) {
        int i = 0;
        while (2 * i + 1 < *size) {
            int c = 2 * i + 1;
            if (c + 1 < *size && before(heap[c + 1], heap[c]))
                c++;
            if (!before(heap[c], last))
                break;
            heap[i] = heap[c];
            i = c;
        }
        heap[i] = last;
    }
    return result;
}

int main(void) {
    const char *operations[] = {"add email 3", "add backup 5", "add deploy 1", "run", "add report 3",
        "add test 2", "add lint 3", "run", "run", "add cleanup 5", "add review 2", "run", "add build 1",
        "add docs 4", "run", "run"};
    Task heap[16];
    int size = 0, sequence = 0;
    for (int i = 0; i < 16; i++) {
        if (strcmp(operations[i], "run") == 0) {
            Task task = pop(heap, &size);
            printf("run: %s (priority %d)\n", task.name, task.priority);
        } else {
            Task task;
            sscanf(operations[i], "add %31s %d", task.name, &task.priority);
            task.order = sequence++;
            push(heap, &size, task);
        }
    }
    printf("remaining:");
    while (size) {
        Task task = pop(heap, &size);
        printf(" %s", task.name);
    }
    putchar('\n');
    return 0;
}
