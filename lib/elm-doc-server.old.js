#!/usr/bin/env node

const fs = require("fs");
const os = require("os");
const path = require("path");
const sane = require("sane");
const tmp = require("tmp");
const chalk = require("chalk");
const spawn = require("cross-spawn");
const express = require("express");
const expressWs = require("express-ws");
const ws = require("ws");

const npmPackage = require(path.join(__dirname, "../package.json"));

function info(...args) {
  console.log(...args);
}

function warning(...args) {
  console.log(chalk.yellow(...args));
}

function error(...args) {
  console.log(chalk.red("Error:"), chalk.red(...args));
}

function fatal(...args) {
  error(...args);
  chalk.red("Exiting...");
  process.exit(1);
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
    fatal(`cannot run 'elm --version' (${exec.error})`);
  } else if (exec.status !== 0) {
    error(`cannot run 'elm --version':`);
    process.stderr.write(exec.stderr);
    process.exit(exec.status);
  }

  const version = exec.stdout.toString().trim();
  if (!version.startsWith("0.19")) {
    fatal(`unsupported Elm version ${version}`);
  }

  return [elm, version];
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

function identify(elmJson) {
  const type = "type" in elmJson ? elmJson.type : "program";
  let name = "name" in elmJson ? elmJson.name : type;
  if ("version" in elmJson) {
    name += ` ${elmJson.version}`;
  }

  return [type, name];
}

function toSemVer(str) {
  const versions = str.split(".").map(n => parseInt(n, 10));
  if (versions.length === 3 && versions.every(v => !Number.isNaN(v))) {
    return { major: versions[0], minor: versions[1], patch: versions[2] };
  }
  return undefined;
}

function cmpSemVer(v1, v2) {
  if (v1.major !== v2.major) {
    return v1.major - v2.major;
  }
  if (v1.minor !== v2.minor) {
    return v1.minor - v2.minor;
  }
  return v1.patch - v2.patch;
}

function findLastPkgVersion(pkgPath, constraint) {
  const semvers = constraint.split(" ");
  const [min, max] = [toSemVer(semvers[0]), toSemVer(semvers.pop())];
  let maxOrder = 0;
  if (semvers.length === 0 || semvers.pop() === "<=") {
    maxOrder = 1;
  }

  try {
    return fs
      .readdirSync(pkgPath)
      .map(toSemVer)
      .filter(v => cmpSemVer(v, min) >= 0 && cmpSemVer(v, max) < maxOrder)
      .sort(cmpSemVer)
      .pop();
  } catch (e) {
    warning(e);
    return undefined;
  }
}

function getDeps(elmJson, elmCache) {
  info(`  |> gathering dependencies from ${elmCache}`);

  const deps = {};
  const dependencies = elmJson.dependencies.direct || elmJson.dependencies;
  Object.keys(dependencies).forEach(pkg => {
    const [name, constraint] = [pkg, dependencies[pkg]];
    const pkgDir = path.join(elmCache, name);
    const semver = findLastPkgVersion(pkgDir, constraint);

    if (semver !== undefined) {
      const version = [semver.major, semver.minor, semver.patch].join(".");
      const versionDir = path.join(pkgDir, version);
      const readme = readFile(path.join(versionDir, "README.md")) || "";
      const docs = readFile(path.join(versionDir, "docs.json"));
      if (readme !== undefined && docs !== undefined) {
        deps[name] = { version, readme, docs };
      }
    }
  });

  return deps;
}

function getElmCache(elmVersion) {
  const dir = os.platform() === "win32" ? "AppData/Roaming/elm" : ".elm";
  const home = process.env.ELM_HOME || path.join(os.homedir(), dir);
  const packages = elmVersion === "0.19.0" ? "package" : "packages";
  const cache = path.join(home, elmVersion, packages);
  return cache;
}

class DocServer {
  constructor(dir = ".") {
    this.dir = fs.lstatSync(dir).isFile() ? path.dirname(dir) : dir;
    [this.elm, this.elmVersion] = getElm();
    this.elmCache = getElmCache(this.elmVersion);
    this.elmJson = getElmJson(dir);
    [this.type, this.name] = identify(this.elmJson);
    this.tmpDocsJson = getTmpFile("elm-docs-", ".json");
    this.timeout = null;
    this.app = null;
    this.ws = null;
    this.wss = null;
    this.lastBuild = "";
    this.deps = {};

    info(
      chalk`{bold elm-doc-preview ${npmPackage.version}} using elm ${
        this.elmVersion
      }`
    );
    info(chalk`Previewing {magenta ${this.name}} from ${path.resolve(dir)}`);

    this.buildDocs();
    this.updateDeps();
    this.setupWebServer();
    this.setupFilesWatcher();
  }

  setupWebServer() {
    this.app = express();
    this.ws = expressWs(this.app);
    this.wss = this.ws.getWss();

    this.app.use(
      "/",
      express.static(path.join(__dirname, "../static"), {
        index: "../static/index.html"
      })
    );

    // websockets
    this.app.ws("/", (socket, req) => {
      info(`  |> ${req.connection.remoteAddress} connected`);
      socket.on("close", () => {
        info("  |> client disconnected");
      });

      this.sendName();
      this.sendCompilation();
      this.sendReadme();
      this.sendDocs();
      this.sendDeps();
    });

    // default route
    this.app.get("*", (req, res) => {
      res.sendFile(path.join(__dirname, "../static/index.html"));
    });
  }

  listen(port = 8000) {
    return this.app.listen(port, () => {
      info(
        chalk`{blue Browse} {bold {green <http://localhost:${port}>}} {blue to see your documentation}`
      );
    });
  }

  setupFilesWatcher() {
    const glob = ["**/elm.json", "**/README.md"];
    if (this.type === "package") {
      glob.push("src/**/*.elm");
    }
    const watcher = sane(this.dir, {
      glob,
      ignored: ["**/node_modules", "**/elm-stuff"]
    });

    watcher.on("ready", () => {
      if (this.type === "package") {
        info(`  |> watching elm.json, README.md and *.elm files`);
      } else {
        info(`  |> watching elm.json and README.md files`);
      }
    });
    watcher.on("change", filepath => {
      this.onChange(filepath);
    });
    watcher.on("add", filepath => {
      this.onChange(filepath);
    });
    watcher.on("delete", filepath => {
      this.onChange(filepath);
    });

    if (this.type === "application") {
      const cacheWatcher = sane(this.elmCache, { glob: "**/*" });
      cacheWatcher.on("ready", () => {
        info("  |> watching cache");
      });
      cacheWatcher.on("add", filepath => {
        this.onChange(filepath);
      });
      cacheWatcher.on("change", filepath => {
        this.onChange(filepath);
      });
    }
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
      } else if (filepath === "elm.json") {
        this.elmJson = getElmJson(this.dir);
        [this.type, this.name] = identify(this.elmJson);
        this.sendName();
        this.buildDocs();
        this.sendCompilation();
        this.sendDocs();
        this.updateDeps();
        this.sendDeps();
      } else if (filepath.endsWith("documentation.json")) {
        // cache documentation update
        this.updateDeps();
        this.sendDeps();
      } else if (filepath.startsWith("src")) {
        this.buildDocs();
        this.sendCompilation();
        this.sendDocs();
      }
    }, 100);
  }

  // Build docs.json
  buildDocs() {
    if (this.type === "application") {
      return;
    }
    info(`  |> building documentation in ${this.tmpDocsJson.name}`);
    const build = this.elm(
      ["make", `--docs=${this.tmpDocsJson.name}`, "--report=json"],
      this.dir
    );
    if (build.error) {
      fatal(`cannot build documentation (${build.error})`);
    }
    this.lastBuild = build.stderr.toString();
  }

  updateDeps() {
    this.deps = getDeps(this.elmJson, this.elmCache);
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

  sendName() {
    info("  |>", "sending name");
    this.send("name", this.name);
  }

  sendCompilation() {
    if (this.type === "application") {
      return;
    }
    info("  |>", "sending compilation status");
    this.send("compilation", this.lastBuild);
  }

  sendReadme() {
    info("  |>", "sending README");
    const readme = path.join(this.dir, "README.md");
    this.send("readme", readFile(readme) || "");
  }

  sendDocs() {
    if (this.type === "application") {
      return;
    }
    info("  |>", `sending docs`);
    this.send("docs", readFile(this.tmpDocsJson.name) || "[]");
  }

  sendDeps() {
    info("  |>", `sending dependencies docs`);
    this.send("deps", this.deps);
  }
}

module.exports = DocServer;
