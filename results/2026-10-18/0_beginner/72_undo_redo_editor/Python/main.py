commands = [
    "undo",
    "type hello world",
    "delete 5",
    "type there",
    "undo",
    "undo",
    "redo",
    "type friend",
    "redo",
    "delete 20",
    "undo",
    "redo",
    "redo",
    "type see you",
]
buffer = ""
undo_stack, redo_stack = [], []
for command in commands:
    if command == "undo":
        if not undo_stack:
            print("undo => nothing to undo")
            continue
        redo_stack.append(buffer)
        buffer = undo_stack.pop()
    elif command == "redo":
        if not redo_stack:
            print("redo => nothing to redo")
            continue
        undo_stack.append(buffer)
        buffer = redo_stack.pop()
    else:
        undo_stack.append(buffer)
        redo_stack.clear()
        if command.startswith("type "):
            buffer += command[5:]
        else:
            buffer = buffer[: -int(command[7:])]
    print(f'{command} => "{buffer}"')
