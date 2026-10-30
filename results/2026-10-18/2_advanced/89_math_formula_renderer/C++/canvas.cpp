#include "formula.hpp"
Lines drawCanvas(const std::vector<Placement> &roots, int width, int height) {
    Lines out(height, std::string(width, ' '));
    std::function<void(const BoxPtr &, int, int)> draw = [&](const BoxPtr &box, int x, int y) {
        for (const Drawn &drawn : box->drawn)
            for (std::size_t i = 0; i < drawn.value.size(); ++i)
                if (drawn.value[i] != ' ')
                    out[y + drawn.y][x + drawn.x + i] = drawn.value[i];
        for (const Placement &child : box->children)
            draw(child.box, x + child.x, y + child.y);
    };
    for (const Placement &root : roots)
        draw(root.box, root.x, root.y);
    for (std::string &line : out)
        line = trimRight(std::move(line));
    return out;
}
BoxDescription describeBoxes(const std::vector<Placement> &roots) {
    BoxDescription out;
    std::function<void(const Placement &, int, int, int)> walk = [&](const Placement &placement,
                                                                     int x, int y, int level) {
        x += placement.x;
        y += placement.y;
        const Box &box = *placement.box;
        out.lines.push_back(text(std::string(2 * level, ' '), placement.role, box.description,
                                 " x=", x, " y=", y, " w=", box.width, " h=", box.height,
                                 " b=", box.baseline));
        out.depth = std::max(out.depth, level + 1);
        ++out.kinds[box.description.substr(0, box.description.find(' '))];
        for (const Placement &child : box.children)
            walk(child, x, y, level + 1);
    };
    for (const Placement &root : roots)
        walk(root, 0, 0, 0);
    return out;
}
