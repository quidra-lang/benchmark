#include "mail.hpp"
#include <functional>

static bool ancestor(const Container* first, const Container* second) { for (; second; second = second->parent) if (first == second) return true; return false; }
static void adopt(Container* parent, Container* child) { child->parent = parent; parent->children.push_back(child); }
static std::vector<Container*> prune(std::vector<Container*> containers, bool atRoot) {
    std::vector<Container*> result;
    for (Container* container : containers) {
        container->children = prune(container->children, false);
        if (container->message >= 0 || (atRoot && container->children.size() >= 2)) result.push_back(container);
        else { for (Container* child : container->children) child->parent = atRoot ? nullptr : container->parent; result.insert(result.end(), container->children.begin(), container->children.end()); }
    }
    return result;
}
static SortKey containerKey(const Container* container, const std::vector<Message>& messages) {
    if (container->message >= 0) return messages[container->message].key();
    SortKey key = containerKey(container->children.front(), messages);
    for (const Container* child : container->children) key = std::min(key, containerKey(child, messages));
    return key;
}
static void sortContainers(std::vector<Container*>& containers, const std::vector<Message>& messages) {
    for (Container* container : containers) sortContainers(container->children, messages);
    std::sort(containers.begin(), containers.end(), [&messages](const Container* first, const Container* second) { return containerKey(first, messages) < containerKey(second, messages); });
}
std::string rootSubject(const Container* root, const std::vector<Message>& messages) { return root->message >= 0 ? messages[root->message].baseSubject : messages[root->children.front()->message].baseSubject; }
ThreadForest buildThreads(const std::vector<Message>& messages) {
    ThreadForest forest; std::map<std::string, Container*> table;
    std::function<Container*(const std::string&, bool)> create = [&](const std::string& id, bool registered) {
        if (registered) { std::map<std::string, Container*>::const_iterator found = table.find(id); if (found != table.end()) return found->second; }
        forest.storage.push_back(std::make_unique<Container>()); Container* container = forest.storage.back().get(); container->id = id;
        if (registered) table[id] = container;
        return container;
    };
    for (int index = 0; index < static_cast<int>(messages.size()); ++index) {
        const Message& message = messages[index]; Container* container = create(message.id, !message.id.empty()); container->message = index;
        std::vector<Container*> references; for (const std::string& id : message.references) references.push_back(create(id, true));
        for (std::size_t i = 0; i + 1 < references.size(); ++i) if (!references[i + 1]->parent && !ancestor(references[i + 1], references[i])) adopt(references[i], references[i + 1]);
        if (container->parent) { std::vector<Container*>& siblings = container->parent->children; siblings.erase(std::find(siblings.begin(), siblings.end(), container)); container->parent = nullptr; }
        if (!references.empty() && !ancestor(container, references.back())) adopt(references.back(), container);
    }
    for (const std::unique_ptr<Container>& container : forest.storage) if (!container->parent) forest.roots.push_back(container.get());
    forest.roots = prune(forest.roots, true); sortContainers(forest.roots, messages);
    std::map<std::string, std::vector<Container*>> groups;
    for (Container* root : forest.roots) { std::string subject = rootSubject(root, messages); if (!subject.empty()) groups[subject].push_back(root); }
    std::vector<Container*> merged;
    for (Container* root : forest.roots) { std::string subject = rootSubject(root, messages); if (subject.empty() || groups[subject].size() == 1) merged.push_back(root); }
    for (const std::pair<const std::string, std::vector<Container*>>& entry : groups) {
        if (entry.second.size() < 2) continue;
        Container* target = nullptr; std::vector<Container*> originals;
        for (Container* root : entry.second) { if (root->message < 0 && !target) target = root; if (root->message >= 0 && !messages[root->message].reply) originals.push_back(root); }
        if (!target && originals.size() == 1) target = originals.front();
        if (!target) { target = create("", false); target->subject = entry.first; }
        for (Container* root : entry.second) if (root != target) { if (root->message >= 0) adopt(target, root); else for (Container* child : root->children) adopt(target, child); }
        merged.push_back(target);
    }
    forest.roots = std::move(merged); sortContainers(forest.roots, messages); return forest;
}
