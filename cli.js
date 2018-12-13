#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const sane = require("sane");
const spawn = require("cross-spawn");
const express = require("express");
const tmp = require("tmp");
const chalk = require("chalk");
const program = require("commander");

const pkg = require(path.join(__dirname, "package.json"));

function error(log) {
  console.log(chalk.red("Error:"), chalk.red(log));
}

program
  .version(pkg.version)
  .arguments("[path_to_package]")
  .action(dir => {
    if (fs.existsSync(dir)) {
      try {
        process.chdir(dir);
      } catch (err) {
        error(`cannot change directory to ${dir} (${err})`);
        process.exit(1);
      }
    }
  })
  .option("-p, --port <port>", "the server listening port", Math.floor, 8000)
  .parse(process.argv);

function getFile(filepath) {
  if (!fs.existsSync(filepath)) {
    return "";
  }

  const data = fs.readFileSync(filepath, "utf8");
  if (data) {
    return data;
  }
  return "";
}
/*
 * Get temp file for docs.json
 */
tmp.setGracefulCleanup();

const docs = tmp.fileSync({
  prefix: "elm-docs-",
  postfix: ".json"
});

process.on("SIGINT", () => {
  docs.removeCallback();
  process.exit(0);
});

/*
 * Check package
 */
const elmJsonPath = path.join(process.cwd(), "elm.json");
let elmJson = {};
try {
  elmJson = JSON.parse(fs.readFileSync(elmJsonPath, "utf8"));
} catch (e) {
  error(`invalid elm.json file (${e})`);
  process.exit(1);
}

if (!("type" in elmJson) || elmJson.type !== "package") {
  const type = "type" in elmJson ? elmJson.type : "program";
  error(
    `unsupported Elm ${type}, only packages documentation can be previewed`
  );
  process.exit(1);
}
let pkgName = "name" in elmJson ? elmJson.name : "package";
if ("version" in elmJson) {
  pkgName += ` ${elmJson.version}`;
}

/*
 * Find and check Elm
 */
let elm = args => spawn.sync("npx", ["--no-install", "elm"].concat(args));

let exec = elm(["--version"]);
if (exec.error || exec.status !== 0 || exec.stderr.toString().length > 0) {
  elm = args => spawn.sync("elm", args);
  exec = elm(["--version"]);
}

if (exec.error) {
  error(`cannot run 'elm --version' (${exec.error})`);
  process.exit(1);
} else if (exec.status !== 0) {
  error(`cannot run 'elm --version':`);
  process.stderr.write(exec.stderr);
  process.exit(exec.status);
}

const elmVersion = exec.stdout.toString().trim();
if (!elmVersion.startsWith("0.19")) {
  error(`unsupported Elm version ${elmVersion}`);
  process.exit(1);
}

function buildDoc() {
  console.log("  |> building documentation");
  const build = elm(["make", `--docs=${docs.name}`, "--report=json"]);
  if (build.error) {
    error(`cannot build documentation (${build.error})`);
    process.exit(1);
  }
  return build.stderr.toString();
}

/*
 * Starting message
 */
console.log(
  chalk`{bold elm-doc-preview ${pkg.version}} using elm ${elmVersion}`
);

console.log(chalk`Previewing {magenta ${pkgName}} from ${process.cwd()}`);

/*
 * Set web server
 */
let ws = null;

function send(type, data) {
  if (ws !== null) {
    ws.send(JSON.stringify({ type, data }));
  }
}

function sendCompilation(output) {
  console.log("  |>", "updating compilation status");
  send("compilation", output);
}
function sendReadme() {
  console.log("  |>", "updating README preview");
  send("readme", getFile("README.md"));
}
function sendDocs() {
  console.log("  |>", `updating ${docs.name} preview`);
  send("docs", getFile(docs.name));
}

const app = express();
require("express-ws")(app);

app.use(
  "/",
  express.static(path.join(__dirname, "public"), { index: "local.html" })
);

let buildReport = buildDoc();

app.ws("/", _ws => {
  ws = _ws;
  sendCompilation(buildReport);
  sendReadme();
  sendDocs();
});

app.get("*", (req, res) => {
  res.sendFile(path.join(__dirname, "public/local.html"));
});

let timeout = null;
function onChange(filepath) {
  if (timeout) {
    clearTimeout(timeout);
  }
  timeout = setTimeout(() => {
    timeout = null;
    console.log("  |>", "detected", filepath, "modification");
    if (filepath.endsWith("README.md")) {
      sendReadme();
    } else {
      buildReport = buildDoc();
      sendCompilation(buildReport);
      sendDocs();
    }
  }, 100);
}

/*
 * Set files watcher
 */
const watcher = sane(".", {
  glob: ["**/elm.json", "src/**/*.elm", "**/README.md"]
});
console.log(`  |> watching elm.json, README.md and *.elm files`);

function ready() {
  console.log(
    chalk`{blue Browse} {bold {green <http://localhost:${
      program.port
    }>}} {blue to see your documentation}`
  );
}

watcher.on("ready", () => {
  ready();
});
watcher.on("change", filepath => {
  onChange(filepath);
});
watcher.on("add", filepath => {
  onChange(filepath);
});
watcher.on("delete", filepath => {
  onChange(filepath);
});

/*
 * Run web server
 */
app.listen(program.port);
