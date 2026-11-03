"""Flat MLP parameters, forward caches, backpropagation and input gradients."""

from layers import (
    backward_sum, hidden_activation, hidden_derivative,
    output_scores, weighted_pre_activation,
)


def layout_for(architecture):
    previous = architecture["width"] * architecture["height"]
    layout = []
    weights_mask = []
    index = 0
    for definition in architecture["layers"]:
        outputs = definition["units"]
        weights = outputs * previous
        layer = {
            "inputs": previous, "outputs": outputs,
            "activation": definition["activation"], "kind": definition["kind"],
            "weight_start": index, "weight_end": index + weights,
            "bias_start": index + weights,
            "bias_end": index + weights + outputs,
        }
        layout.append(layer)
        weights_mask.extend([True] * weights + [False] * outputs)
        index += weights + outputs
        previous = outputs
    return {"layers": layout, "is_weight": weights_mask, "parameters": index,
            "weight_count": sum(weights_mask)}


def layer_values(theta, layer):
    width = layer["inputs"]
    flat = theta[layer["weight_start"]:layer["weight_end"]]
    weights = [
        flat[i * width:(i + 1) * width]
        for i in range(layer["outputs"])
    ]
    biases = theta[layer["bias_start"]:layer["bias_end"]]
    return weights, biases


def forward(architecture, layout, theta, image):
    activations = [image["vector"]]
    preactivations = []
    all_weights = []
    output_error = None
    loss = None
    scores = None
    last = len(layout["layers"]) - 1
    for index, layer in enumerate(layout["layers"]):
        weights, biases = layer_values(theta, layer)
        all_weights.append(weights)
        z = weighted_pre_activation(weights, biases, activations[-1])
        preactivations.append(z)
        if index == last:
            scores, loss, output_error = output_scores(
                layer["activation"], z, image["label"],
            )
            activations.append(scores)
        else:
            activations.append([
                hidden_activation(layer["activation"], value) for value in z
            ])
    return {
        "z": preactivations, "a": activations,
        "weights": all_weights, "scores": scores,
        "loss": loss, "output_delta": output_error,
    }


def gradient(architecture, layout, theta, image, input_gradient=False):
    cache = forward(architecture, layout, theta, image)
    layers = layout["layers"]
    deltas = [None] * len(layers)
    deltas[-1] = cache["output_delta"]
    for index in range(len(layers) - 2, -1, -1):
        propagated = backward_sum(
            cache["weights"][index + 1], deltas[index + 1]
        )
        layer = layers[index]
        deltas[index] = [
            value * hidden_derivative(
                layer["activation"], cache["z"][index][j],
                cache["a"][index + 1][j],
            )
            for j, value in enumerate(propagated)
        ]
    grad = [0.0] * layout["parameters"]
    for index, layer in enumerate(layers):
        destination = layer["weight_start"]
        for j in range(layer["outputs"]):
            for i in range(layer["inputs"]):
                grad[destination] = (
                    deltas[index][j] * cache["a"][index][i]
                )
                destination += 1
        for j in range(layer["outputs"]):
            grad[layer["bias_start"] + j] = deltas[index][j]
    if not input_gradient:
        return grad, cache
    original_gradient = backward_sum(cache["weights"][0], deltas[0])
    return grad, cache, original_gradient


def average_gradient(architecture, layout, theta, images):
    result = [0.0] * layout["parameters"]
    loss = 0.0
    for image in images:
        grad, cache = gradient(architecture, layout, theta, image)
        loss += cache["loss"]
        for i, value in enumerate(grad):
            result[i] += value
    count = len(images)
    return [value / count for value in result], loss / count


def evaluate(architecture, layout, theta, images):
    """Preserve sequence order for means and tied predictions."""
    outcomes = []
    loss = 0.0
    correct = 0
    for image in images:
        cache = forward(architecture, layout, theta, image)
        scores = cache["scores"]
        prediction = max(range(len(scores)), key=lambda k: (scores[k], -k))
        outcome = {
            "id": image["id"], "label": image["label"],
            "predicted": prediction, "confidence": scores[prediction],
            "scores": scores, "loss": cache["loss"], "hidden": cache["a"][1:-1],
        }
        outcomes.append(outcome)
        loss += cache["loss"]
        correct += prediction == image["label"]
    return {
        "loss": loss / len(images), "correct": correct,
        "outcomes": outcomes,
    }
