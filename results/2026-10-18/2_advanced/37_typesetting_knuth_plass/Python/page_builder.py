"""Allowed page boundaries, omitted boundary gaps, and footnote heights."""


def build_sequence(blocks, orphan_lines, widow_lines):
    lines = []
    boundaries = []
    for index, block in enumerate(blocks):
        start = len(lines)
        lines.extend(block["lines"])
        count = len(block["lines"])
        if block["kind"] == "flow":
            for kept in range(1, count):
                if kept >= orphan_lines and count - kept >= widow_lines:
                    position = start + kept
                    boundaries.append((position, position, False))
        if index + 1 == len(blocks):
            boundaries.append((len(lines), len(lines), True))
            continue

        following = blocks[index + 1]
        end = len(lines)
        gap = 0 if block["list"] and following["list"] else 1
        if gap:
            lines.append({"text": "", "footnotes": (), "indexes": ()})
        forced = following["page_break"]
        if forced or block["kind"] != "heading":
            boundaries.append((end, len(lines), forced))
    return lines, boundaries


def choose_pages(blocks, footnote_heights, height, orphan_lines, widow_lines):
    lines, boundaries = build_sequence(blocks, orphan_lines, widow_lines)
    pages = []
    start = 0
    first_boundary = 0
    while start < len(lines):
        notes = set()
        note_height = 0
        scanned = start
        chosen = None
        for index in range(first_boundary, len(boundaries)):
            end, next_start, forced = boundaries[index]
            while scanned < end:
                for number in lines[scanned]["footnotes"]:
                    if number not in notes:
                        notes.add(number)
                        note_height += footnote_heights[number]
                scanned += 1
            used = end - start + note_height + (1 if notes else 0)
            if used > height:
                break
            chosen = (index, end, next_start, forced, used, tuple(sorted(notes)))
            if forced:
                break

        # The input guarantees a fitting allowed boundary for every page.
        index, end, next_start, forced, used, page_notes = chosen
        pages.append({
            "content": lines[start:end],
            "footnotes": page_notes,
            "height": used,
            "ends_by_force": forced,
            "blank": False,
        })
        start = next_start
        first_boundary = index + 1
    return pages
