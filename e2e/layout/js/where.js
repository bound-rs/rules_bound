// Reports where node runs and what PATH holds, relative to the bundle:
// rules_bound's cwd = bundle_path(...) and list variables, seen from inside.
const path = require("path");
const root = process.env.BOUND_ROOT;
const entries = process.env.PATH.split(path.delimiter);
const relative = (p) => path.relative(root, p).split(path.sep).join("/");
const nodeFirst = entries[0] === path.dirname(process.execPath);
console.log(`cwd=${relative(process.cwd())} | node first on PATH: ${nodeFirst} | last on PATH: ${relative(entries[entries.length - 1])}`);
