// Checks that node resolves packages through a pnpm-style node_modules
// tree: node_modules/a links into the store, and a finds its own dependency
// b next to it there. b is not a dependency of the application.
const path = require("path");
const a = require("a");

let strict = false;
try {
  require("b");
} catch (e) {
  strict = e.code === "MODULE_NOT_FOUND";
}
const resolved = path.relative(__dirname, require.resolve("a")).split(path.sep).slice(0, 2).join("/");
console.log(`${a.describe()} | a resolved in ${resolved} | ${strict ? "b is not visible" : "b is visible"} | ${process.argv.slice(2).join(" ")}`);
