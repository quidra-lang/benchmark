#include "railway.hpp"
#include <algorithm>

Layout readLayout() {
    Layout layout;
    const auto position = [&](int row, int col) {
        layout.height = std::max(layout.height, row + 1);
        layout.width = std::max(layout.width, col + 1);
    };
    for (const std::string &line : readLines("input/layout.txt")) {
        std::vector<std::string> a = words(line);
        if (a[0] == "SECTION") {
            std::unique_ptr<Section> value = std::make_unique<Section>();
            Section *s = value.get();
            s->name = a[1];
            s->length = std::stoi(a[2]);
            s->row = std::stoi(a[3]);
            s->first = std::stoi(a[4]);
            s->last = std::stoi(a[5]);
            layout.sectionNames[s->name] = s;
            position(s->row, s->last);
            layout.sections.push_back(std::move(value));
        } else if (a[0] == "JOINT") {
            Section *x = layout.sectionNames.at(a[1]), *y = layout.sectionNames.at(a[2]);
            layout.ends[{x->name, 'R'}] = Endpoint{EndKind::Section, "", y};
            layout.ends[{y->name, 'L'}] = Endpoint{EndKind::Section, "", x};
        } else if (a[0] == "POINT") {
            std::unique_ptr<Point> value = std::make_unique<Point>();
            Point *p = value.get();
            p->name = a[1];
            p->side = a[2][0];
            p->common = layout.sectionNames.at(a[3]);
            p->normal = layout.sectionNames.at(a[4]);
            p->reverse = layout.sectionNames.at(a[5]);
            p->row = std::stoi(a[6]);
            p->col = std::stoi(a[7]);
            layout.pointNames[p->name] = p;
            position(p->row, p->col);
            char branchEnd = p->side == 'R' ? 'L' : 'R';
            layout.ends[{p->common->name, p->side}] =
                Endpoint{EndKind::Point, "", nullptr, p, true};
            layout.ends[{p->normal->name, branchEnd}] =
                Endpoint{EndKind::Point, "", nullptr, p, false};
            layout.ends[{p->reverse->name, branchEnd}] =
                Endpoint{EndKind::Point, "", nullptr, p, false};
            layout.points.push_back(std::move(value));
        } else if (a[0] == "SIGNAL") {
            std::unique_ptr<Signal> value = std::make_unique<Signal>();
            Signal *g = value.get();
            g->name = a[1];
            g->section = layout.sectionNames.at(a[2]);
            g->direction = a[3] == "UP" ? Direction::Up : Direction::Down;
            g->row = std::stoi(a[4]);
            g->col = std::stoi(a[5]);
            layout.signalNames[g->name] = g;
            layout.signalAt[{g->section->name, g->direction}] = g;
            position(g->row, g->col);
            layout.signals.push_back(std::move(value));
        } else if (a[0] == "BUFFER") {
            std::unique_ptr<Buffer> value = std::make_unique<Buffer>();
            Buffer *b = value.get();
            b->name = a[1];
            b->section = layout.sectionNames.at(a[2]);
            b->end = a[3][0];
            b->row = std::stoi(a[4]);
            b->col = std::stoi(a[5]);
            layout.bufferNames[b->name] = b;
            layout.ends[{b->section->name, b->end}] = Endpoint{EndKind::Buffer, b->name};
            position(b->row, b->col);
            layout.buffers.push_back(std::move(value));
        } else if (a[0] == "BOUNDARY") {
            std::unique_ptr<Boundary> value = std::make_unique<Boundary>();
            Boundary *b = value.get();
            b->name = a[1];
            b->section = layout.sectionNames.at(a[2]);
            b->end = a[3][0];
            layout.boundaryNames[b->name] = b;
            layout.ends[{b->section->name, b->end}] = Endpoint{EndKind::Boundary, b->name};
            layout.boundaries.push_back(std::move(value));
        } else {
            Label label{std::stoi(a[1]), std::stoi(a[2]), a[3]};
            layout.labels.push_back(label);
            position(label.row, label.col + int(label.text.size()) - 1);
        }
    }
    return layout;
}
Endpoint Layout::beyond(Section *section, Direction direction) const {
    Endpoint endpoint = ends.at({section->name, direction == Direction::Up ? 'R' : 'L'});
    if (endpoint.kind != EndKind::Point)
        return endpoint;
    Point *point = endpoint.point;
    if (point->moving)
        return Endpoint{};
    Section *selected = point->position == 'N' ? point->normal : point->reverse;
    if (endpoint.common)
        return Endpoint{EndKind::Section, "", selected};
    if (selected != section)
        return Endpoint{};
    return Endpoint{EndKind::Section, "", point->common};
}
Signal *Layout::signal(Section *section, Direction direction) const {
    std::map<std::pair<std::string, Direction>, Signal *>::const_iterator found =
        signalAt.find({section->name, direction});
    return found == signalAt.end() ? nullptr : found->second;
}
