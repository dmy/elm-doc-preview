#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const sane = require("sane");
const tmp = require("tmp");
const chalk = require("chalk");
const express = require("express");
const expressWs = require("express-ws");
const ws = require("ws");

function error(err) {
  console.log(chalk.red("Error:"), chalk.red(err));
}

function warning(warn) {
  console.log(chalk.yellow(warn));
}

function fatal(err) {
  error(err);
  chalk.red("Exiting...");
  process.exit(1);
}

function info(...args) {
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
    const elmJsonPath = path.join(dir, "elm.json");
    elmJson = JSON.parse(fs.readFileSync(elmJsonPath, "utf8"));
  } catch (e) {
    fatal(`invalid elm.json file (${e})`);
  }
  return elmJson;
}

/*
 * Check package and return its name
 */
function getPkgName(elmJson) {
  if (!("type" in elmJson) || elmJson.type !== "package") {
    const type = "type" in elmJson ? elmJson.type : "program";
    fatal(
      `unsupported Elm ${type}, only packages documentation can be previewed`
    );
  }
  let pkgName = "name" in elmJson ? elmJson.name : "package";
  if ("version" in elmJson) {
    pkgName += ` ${elmJson.version}`;
  }

  return pkgName;
}

class DocServer {
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

    info(chalk`Previewing {magenta ${this.pkgName}} from ${path.resolve(dir)}`);

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
      express.static(path.join(__dirname, "../public"), {
        index: "../public/local.html"
      })
    );

    // websockets
    this.app.ws("/", (socket, req) => {
      info(`  |> ${req.connection.remoteAddress} connected`);
      socket.on("close", () => {
        info("  |> client disconnected");
      });

      this.sendCompilation(this.lastBuild);
      this.sendReadme();
      this.sendDocs();
    });

    // default route
    this.app.get("*", (req, res) => {
      res.sendFile(path.join(__dirname, "../public/local.html"));
    });
  }

  setupFilesWatcher() {
    const watcher = sane(this.dir, {
      glob: ["**/elm.json", "src/**/*.elm", "**/README.md"]
    });
    info(`  |> watching elm.json, README.md and *.elm files`);

    watcher.on("ready", () => {
      info(
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
      info("  |>", "detected", filepath, "modification");
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
    info("  |> building documentation");
    const build = this.elm(
      ["make", `--docs=${this.docsJson.name}`, "--report=json"],
      this.dir
    );
    if (build.error) {
      fatal(`cannot build documentation (${build.error})`);
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
    info("  |>", "updating compilation status");
    this.send("compilation", output);
  }

  sendReadme() {
    info("  |>", "updating README preview");
    const readme = path.join(this.dir, "README.md")
    this.send("readme", readFile(readme) || "");
  }

  sendDocs() {
    info("  |>", `updating ${this.docsJson.name} preview`);
    this.send("docs", readFile(this.docsJson.name) || "[]");
  }

  removeDocsJson() {
    this.docsJson.removeCallback();
  }
}

module.exports = {
  DocServer,
  info,
  warning,
  error,
  fatal
};
