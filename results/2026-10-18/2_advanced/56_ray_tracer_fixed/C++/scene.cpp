#include "renderer.hpp"
const char *kind_name(ObjectKind kind) {
    static const char *names[] = {"sphere", "plane", "box"};
    return names[int(kind)];
}
const char *kind_name(LightKind kind) {
    static const char *names[] = {"point", "spot", "sun", "area"};
    return names[int(kind)];
}
Scene load_scene() {
    std::ifstream input("input/scene.txt");
    Scene scene;
    std::string line;
    auto material = [&](const std::string &name) {
        for (int i = 0; i < int(scene.materials.size()); ++i)
            if (scene.materials[i].name == name)
                return i;
        return -1;
    };
    while (std::getline(input, line)) {
        if (line.empty() || line[0] == '#')
            continue;
        std::istringstream row(line);
        std::string kind;
        row >> kind;
        auto vector = [&](Vec &value) { row >> value[0] >> value[1] >> value[2]; };
        if (kind == "eye")
            vector(scene.eye);
        else if (kind == "forward")
            vector(scene.forward);
        else if (kind == "right")
            vector(scene.right);
        else if (kind == "up")
            vector(scene.up);
        else if (kind == "view")
            row >> scene.half_width >> scene.half_height;
        else if (kind == "background")
            vector(scene.background);
        else if (kind == "ambient")
            row >> scene.ambient;
        else if (kind == "fog") {
            scene.fog = true;
            vector(scene.fog_color);
            row >> scene.fog_start >> scene.fog_end;
        } else if (kind == "material") {
            Material value;
            row >> value.name;
            vector(value.color);
            row >> value.kd >> value.ks >> value.exponent >> value.kr >> value.kt >> value.ior;
            scene.materials.push_back(value);
        } else if (kind == "checker") {
            std::string name;
            row >> name;
            Material &value = scene.materials[material(name)];
            vector(value.second);
            row >> value.checker_size;
        } else if (kind == "point" || kind == "spot" || kind == "sun" || kind == "area") {
            Light light;
            light.kind = kind == "point"  ? LightKind::point
                         : kind == "spot" ? LightKind::spot
                         : kind == "sun"  ? LightKind::sun
                                          : LightKind::area;
            if (light.kind == LightKind::sun) {
                vector(light.direction);
                light.direction = norm(negate(light.direction));
                row >> light.intensity;
            } else {
                vector(light.position);
                if (light.kind == LightKind::spot) {
                    vector(light.direction);
                    light.direction = norm(light.direction);
                    row >> light.outer >> light.inner;
                } else if (light.kind == LightKind::area) {
                    vector(light.u);
                    vector(light.v);
                    row >> light.divisions;
                }
                row >> light.intensity;
            }
            scene.lights.push_back(light);
        } else {
            Object object;
            std::string name;
            row >> object.label >> name;
            object.material = material(name);
            object.kind = kind == "sphere"  ? ObjectKind::sphere
                          : kind == "plane" ? ObjectKind::plane
                                            : ObjectKind::box;
            vector(object.first);
            if (object.kind == ObjectKind::sphere)
                row >> object.radius;
            else {
                vector(object.second);
                if (object.kind == ObjectKind::plane)
                    object.second = norm(object.second);
            }
            scene.objects.push_back(object);
        }
    }
    return scene;
}
