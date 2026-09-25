const b = require("b");
exports.describe = () => `a ${require("./package.json").version} uses b ${b.version}`;
