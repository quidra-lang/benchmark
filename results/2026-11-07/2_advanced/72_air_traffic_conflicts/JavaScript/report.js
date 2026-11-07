"use strict";

const fs = require("fs");

function decimal(value, digits = 3) {
  const result = Number(value).toFixed(digits);
  return result.startsWith("-") && Number(result) === 0 ? result.slice(1) : result;
}

function named(items) {
  return Object.entries(items).map(([key, value]) => key + "=" + value).join(" ");
}

function chart(lines) {
  const border = "+" + "-".repeat(lines[0].length) + "+";
  return [border, ...lines.map(line => "|" + line + "|"), border];
}

function signed(value) {
  return value > 0 ? "+" + value : String(value);
}

function writeLines(filename, lines) {
  fs.mkdirSync("output", {recursive: true});
  fs.writeFileSync("output/" + filename, lines.length ? lines.join("\n") + "\n" : "", "ascii");
}

module.exports = {decimal, named, chart, signed, writeLines};
