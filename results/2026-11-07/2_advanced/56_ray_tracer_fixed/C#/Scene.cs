using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Scene {
    public record Color(long r, long g, long b) {
        public long Component(int axis) {
            return axis == 0 ? r : axis == 1 ? g : b;
        }
        public static Color Of(long[] values) {
            return new Color(values[0], values[1], values[2]);
        }
        public override string ToString() {
            return r + " " + g + " " + b;
        }
    }
    public sealed class Material {
        public string name;
        public Color color, checker;
        public long kd, ks, kr, kt, ior, checkerSize;
        public int exponent;
    }
    public sealed class Obj {
        public int number, leafDepth;
        public char label;
        public string kind;
        public Material material;
        public Vector3 center, point, normal, lo, hi;
        public long radius;
        public Intersect.Bounds bounds;
    }
    public sealed class Light {
        public int number, divisions = 1;
        public string kind;
        public Vector3 position, direction, u, v;
        public long outer, inner, intensity;
        public int Samples() {
            return kind.Equals("area") ? divisions * divisions : 1;
        }
    }
    public sealed class Data {
        public Vector3 eye, forward, right, up;
        public long hw, hh, ambient, fogStart, fogEnd;
        public Color background, fog;
        public Dictionary<string, Material> materials = new();
        public List<Obj> objects = new();
        public List<Light> lights = new();
    }
    public static long Value(string[] words, int index) {
        return long.Parse(words[index]);
    }
    public static Vector3 Vector(string[] words, int start) {
        return new Vector3(Value(words, start), Value(words, start + 1), Value(words, start + 2));
    }
    public static Color ReadColor(string[] words, int start) {
        return new Color(Value(words, start), Value(words, start + 1), Value(words, start + 2));
    }
    public static Data Read() {
        Data scene = new Data();
        foreach (string line in File.ReadAllLines(Path.Combine("input", "scene.txt"), Encoding.ASCII)
                     .ToList()) {
            if (line.Length == 0 || line.StartsWith("#"))
                continue;
            string[] w = line.Split(' ');
            switch (w[0]) {
            case "eye":
                scene.eye = Vector(w, 1);
                break;
            case "forward":
                scene.forward = Vector(w, 1);
                break;
            case "right":
                scene.right = Vector(w, 1);
                break;
            case "up":
                scene.up = Vector(w, 1);
                break;
            case "view": {
                scene.hw = Value(w, 1);
                scene.hh = Value(w, 2);
                break;
            }
            case "background":
                scene.background = ReadColor(w, 1);
                break;
            case "ambient":
                scene.ambient = Value(w, 1);
                break;
            case "fog": {
                scene.fog = ReadColor(w, 1);
                scene.fogStart = Value(w, 4);
                scene.fogEnd = Value(w, 5);
                break;
            }
            case "material": {
                Material material = new Material();
                material.name = w[1];
                material.color = ReadColor(w, 2);
                material.kd = Value(w, 5);
                material.ks = Value(w, 6);
                material.exponent = (int)Value(w, 7);
                material.kr = Value(w, 8);
                material.kt = Value(w, 9);
                material.ior = Value(w, 10);
                scene.materials[material.name] = material;
                break;
            }
            case "checker": {
                Material material = scene.materials[w[1]];
                material.checker = ReadColor(w, 2);
                material.checkerSize = Value(w, 5);
                break;
            }
            case "sphere":
            case "plane":
            case "box": {
                Obj sceneObject = new Obj();
                sceneObject.number = scene.objects.Count + 1;
                sceneObject.label = w[1][0];
                sceneObject.kind = w[0];
                sceneObject.material = scene.materials[w[2]];
                if (sceneObject.kind.Equals("sphere")) {
                    sceneObject.center = Vector(w, 3);
                    sceneObject.radius = Value(w, 6);
                } else if (sceneObject.kind.Equals("plane")) {
                    sceneObject.point = Vector(w, 3);
                    sceneObject.normal = Vector(w, 6).Normalize();
                } else {
                    sceneObject.lo = Vector(w, 3);
                    sceneObject.hi = Vector(w, 6);
                }
                scene.objects.Add(sceneObject);
                break;
            }
            default: {
                Light light = new Light();
                light.number = scene.lights.Count + 1;
                light.kind = w[0];
                switch (light.kind) {
                case "point": {
                    light.position = Vector(w, 1);
                    light.intensity = Value(w, 4);
                    break;
                }
                case "spot": {
                    light.position = Vector(w, 1);
                    light.direction = Vector(w, 4).Normalize();
                    light.outer = Value(w, 7);
                    light.inner = Value(w, 8);
                    light.intensity = Value(w, 9);
                    break;
                }
                case "sun": {
                    light.direction = Vector(w, 1).Negate().Normalize();
                    light.intensity = Value(w, 4);
                    break;
                }
                case "area": {
                    light.position = Vector(w, 1);
                    light.u = Vector(w, 4);
                    light.v = Vector(w, 7);
                    light.divisions = (int)Value(w, 10);
                    light.intensity = Value(w, 11);
                    break;
                }
                }
                scene.lights.Add(light);
                break;
            }
            }
        }
        return scene;
    }
}
