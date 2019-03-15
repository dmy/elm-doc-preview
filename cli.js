#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const sane = require("sane");
const spawn = require("cross-spawn");
const tmp = require("tmp");
const chalk = require("chalk");
const latestVersion = require("latest-version");
const commander = require("commander");
const express = require("express");
const expressWs = require("express-ws");
const ws = require("ws");

const npmPackage = require(path.join(__dirname, "package.json"));

/*
 * Program options and usage
 */
function init() {
  let pkgPath = ".";
  const program = commander
    .version(npmPackage.version)
    .arguments("[path_to_package]")
    .action(dir => {
      if (dir !== undefined) {
        pkgPath = dir;
      }
    })
    .option("-p, --port <port>", "the server listening port", Math.floor, 8000)
    .parse(process.argv);

  program.dir = pkgPath;
  return program;
}

function error(err) {
  console.log(chalk.red("Error:"), chalk.red(err));
}

function fatalError(err) {
  error(err);
  error("Exiting...");
  process.exit(1);
}

function log(...args) {
  console.log(...args);
}

/*
 * Get temporary file
 */
function getTmpFile(prefix, postfix) {
  tmp.setGracefulCleanup();
  const tmpFile = tmp.fileSync({ prefix, postfix });
  return tmpFile;
}

/*
 * Return synchronously read file content
 */
function readFile(filepath) {
  if (!fs.existsSync(filepath)) {
    return undefined;
  }

  return fs.readFileSync(filepath, "utf8");
}

/*
 * Get parsed elm.json
 */
function getElmJson(dir = ".") {
  let elmJson = {};
  try {
    elmJson = JSON.parse(fs.readFileSync(`${dir}/elm.json`, "utf8"));
  } catch (e) {
    fatalError(`invalid elm.json file (${e})`);
  }
  return elmJson;
}

/*
 * Check package and return its name
 */
function getPkgName(elmJson) {
  if (!("type" in elmJson) || elmJson.type !== "package") {
    const type = "type" in elmJson ? elmJson.type : "program";
    fatalError(
      `unsupported Elm ${type}, only packages documentation can be previewed`
    );
  }
  let pkgName = "name" in elmJson ? elmJson.name : "package";
  if ("version" in elmJson) {
    pkgName += ` ${elmJson.version}`;
  }

  return pkgName;
}

/*
 * Find and check Elm executable
 */
function getElm() {
  let elm = (args, cwd = ".") =>
    spawn.sync("npx", ["--no-install", "elm"].concat(args), { cwd });

  let exec = elm(["--version"]);
  if (exec.error || exec.status !== 0 || exec.stderr.toString().length > 0) {
    elm = (args, cwd = ".") => spawn.sync("elm", args, { cwd });
    exec = elm(["--version"]);
  }

  if (exec.error) {
    fatalError(`cannot run 'elm --version' (${exec.error})`);
  } else if (exec.status !== 0) {
    error(`cannot run 'elm --version':`);
    process.stderr.write(exec.stderr);
    process.exit(exec.status);
  }

  const version = exec.stdout.toString().trim();
  if (!version.startsWith("0.19")) {
    fatalError(`unsupported Elm version ${elm.version}`);
  }

  return [elm, version];
}

function checkUpdate(currentVersion) {
  latestVersion("elm-doc-preview").then(lastVersion => {
    if (lastVersion !== currentVersion) {
      log(chalk.yellow(`elm-doc-preview ${lastVersion} is available`));
    }
  });
}

class Previewer {
  constructor(dir, elm, port) {
    this.dir = dir;
    this.elm = elm;
    this.port = port;
    this.elmJson = getElmJson(dir);
    this.pkgName = getPkgName(this.elmJson);
    this.docsJson = getTmpFile("elm-docs-", ".json");
    this.timeout = null;
    this.app = null;
    this.ws = null;
    this.wss = null;

    log(chalk`Previewing {magenta ${this.pkgName}} from ${path.resolve(dir)}`);

    this.lastBuild = this.buildDocs();
    this.setupWebServer();
    this.setupFilesWatcher();
  }

  setupWebServer() {
    this.app = express();
    this.ws = expressWs(this.app);
    this.wss = this.ws.getWss();

    this.app.use(
      "/",
      express.static(path.join(__dirname, "public"), { index: "local.html" })
    );

    // websockets
    this.app.ws("/", (socket, req) => {
      log(`  |> ${req.connection.remoteAddress} connected`);
      socket.on("close", () => {
        log("  |> client disconnected");
      });

      this.sendCompilation(this.lastBuild);
      this.sendReadme();
      this.sendDocs();
    });

    // default route
    this.app.get("*", (req, res) => {
      res.sendFile(path.join(__dirname, "public/local.html"));
    });
  }

  setupFilesWatcher() {
    const watcher = sane(".", {
      glob: ["**/elm.json", "src/**/*.elm", "**/README.md"]
    });
    log(`  |> watching elm.json, README.md and *.elm files`);

    watcher.on("ready", () => {
      log(
        chalk`{blue Browse} {bold {green <http://localhost:${
          this.port
        }>}} {blue to see your documentation}`
      );
    });
    watcher.on("change", filepath => {
      this.onChange(filepath, this.docsJson);
    });
    watcher.on("add", filepath => {
      this.onChange(filepath, this.docsJson);
    });
    watcher.on("delete", filepath => {
      this.onChange(filepath, this.docsJson);
    });
  }

  run() {
    this.app.listen(this.port);
  }

  onChange(filepath) {
    // Update docs with debounce: try to batch consecutive updates
    // (for example the way vim saves files would lead to 3 rebuilds else)
    if (this.timeout) {
      clearTimeout(this.timeout);
    }
    this.timeout = setTimeout(() => {
      this.timeout = null;
      log("  |>", "detected", filepath, "modification");
      if (filepath.endsWith("README.md")) {
        this.sendReadme();
      } else {
        const build = this.buildDocs();
        this.sendCompilation(build);
        this.sendDocs();
      }
    }, 100);
  }

  // Build docs.json and return output
  buildDocs() {
    log("  |> building documentation");
    const build = this.elm(
      ["make", `--docs=${this.docsJson.name}`, "--report=json"],
      this.dir
    );
    if (build.error) {
      fatalError(`cannot build documentation (${build.error})`);
    }
    return build.stderr.toString();
  }

  broadcast(data) {
    this.wss.clients.forEach(client => {
      if (client.readyState === ws.OPEN) {
        client.send(data);
      }
    });
  }

  send(type, data) {
    this.broadcast(JSON.stringify({ type, data }));
  }

  sendCompilation(output) {
    log("  |>", "updating compilation status");
    this.send("compilation", output);
  }

  sendReadme() {
    log("  |>", "updating README preview");
    this.send("readme", readFile("README.md") || "");
  }

  sendDocs() {
    log("  |>", `updating ${this.docsJson.name} preview`);
    this.send("docs", readFile(this.docsJson.name) || "[]");
  }

  removeDocsJson() {
    this.docsJson.removeCallback();
  }
}

/*
 * Run program
 */
const program = init();
checkUpdate(npmPackage.version);
const [elm, elmVersion] = getElm();
log(
  chalk`{bold elm-doc-preview ${npmPackage.version}} using elm ${elmVersion}`
);
const previewer = new Previewer(program.dir, elm, program.port);
process.on("SIGINT", () => {
  previewer.removeDocsJson();
  process.exit(0);
});
previewer.run();
