import fs from "fs";
import os from "os";
import path from "path";
import process from "process";
import sane from "sane";
import tmp from "tmp";
import chalk from "chalk";
import spawn from "cross-spawn";
import express from "express";
import serveIndex from "serve-index";
import expressWs from "express-ws";
import ws from "ws";
import {SpawnSyncReturns } from "child_process";
import glob from "glob";
import { promisify } from "util";
const readFileAsync = promisify(fs.readFile);
const globAsync = promisify(glob);

express.static.mime.define({ "text/plain": ["elm"] });
express.static.mime.define({ "text/plain": ["md"] });

interface Manifest {
  type: string;
  license: string;
  summary?: string;
  name?: string;
  version?: string;
  timestamp: number;
}

interface Package {
  name: string;
  summary: string;
  license: string;
  versions: string[];
}

enum Type {
  Package,
  Application
}

type Elm = (args: string[], cwd?: string) => SpawnSyncReturns<Buffer>;

const npmPackage = require(path.join(__dirname, "../package.json"));

function info(...args: string[]) {
  console.log(...args);
}

function warning(...args: string[]) {
  console.log(chalk.yellow(...args));
}

function error(...args: string[]) {
  console.log(chalk.red(...args));
}

function fatal(...args: string[]) {
  error(...args);
  chalk.red("Exiting...");
  process.exit(1);
}

/*
 * Find and check Elm executable
 */
function getElm(): [Elm, string] {
  let elm = (args: string[], cwd: string = ".") =>
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
    process.exit(exec.status ? exec.status : 1);
  }

  const version = exec.stdout.toString().trim();
  if (!version.startsWith("0.19")) {
    fatal(`unsupported Elm version ${version}`);
  }

  return [elm, version];
}

function identify(manifest: Manifest): [Type, string] {
  const type = manifest.type ? manifest.type : "application";
  let name = manifest.name ? manifest.name : type;
  if ("version" in manifest) {
    name += ` ${manifest.version}`;
  }

  return [type === "package" ? Type.Package : Type.Application, name];
}

function getElmCache(elmVersion: string) {
  const dir = os.platform() === "win32" ? "AppData/Roaming/elm" : ".elm";
  const home = process.env.ELM_HOME || path.join(os.homedir(), dir);
  const packages = elmVersion === "0.19.0" ? "package" : "packages";
  const cache = path.join(home, elmVersion, packages);
  return cache;
}

async function getManifest(manifestPath: string): Promise<Manifest> {
  return readFileAsync(manifestPath, "utf8")
    .then(json => {
      let manifest = JSON.parse(json);
      let stat = fs.statSync(manifestPath);
      manifest["timestamp"] = stat.mtimeMs / 1000;
      return manifest;
    })
    .catch(err => error(err.toString()));
}

async function searchPackages(elmCache: string): Promise<Package[]> {
  const paths = await globAsync("*/*/*/elm.json", {
    cwd: elmCache,
    realpath: true
  });
  const manifests = await Promise.all(paths.map(path => getManifest(path)));
  let search: Record<string, Package> = {};
  search = manifests.reduce((acc: Record<string,Package>, pkg: Manifest) => {
    if (pkg.name && pkg.name in acc && pkg.version) {
      acc[pkg.name].versions.push(pkg.version);
      return acc;
    } else if (pkg.name && pkg.version) {
      acc[pkg.name] = {
        name: pkg.name,
        summary: pkg.summary || "",
        license: pkg.license,
        versions: [pkg.version]
      };
      return acc;
    } else {
      warning("invalid elm.json", pkg.toString());
      return acc;
    }
  }, search);
  return Object.values(search);
}

async function packageReleases(
  elmCache: string,
  author: string,
  project: string
): Promise<Record<string, number>> {
  const paths = await globAsync("*/elm.json", {
    cwd: path.resolve(elmCache, author, project),
    realpath: true
  });
  const manifests = await Promise.all(paths.map(path => getManifest(path)));
  let releases: Record<string, number> = {};
  releases = manifests.reduce((releases: Record<string, number>, pkg: Manifest) => {
    if (pkg.version && pkg.timestamp) {
      releases[pkg.version] = pkg.timestamp;
      return releases;
    } else {
      return releases;
    }
  }, releases);
  return releases;
}

class DocServer {
  dir: string;
  elm: Elm;
  elmVersion: string;
  elmCache: string;
  app: expressWs.Application;
  ws: expressWs.Instance;
  wss: ws.Server;

  constructor(dir = ".") {
    this.dir = fs.lstatSync(dir).isFile() ? path.dirname(dir) : dir;
    try {
      process.chdir(dir);
    } catch (err) {
      error(err);
    }
    [this.elm, this.elmVersion] = getElm();
    this.elmCache = getElmCache(this.elmVersion);
    let app = express();
    this.ws = expressWs(app);
    this.app = this.ws.app;
    this.wss = this.ws.getWss();

    info(
      chalk`{bold elm-doc-preview ${npmPackage.version}} using elm ${
        this.elmVersion
        }`
    );

    this.setupWebServer();
  }

  setupWebServer() {
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
    });

    // search.json
    this.app.get("/search.json", (req, res) => {
      searchPackages(this.elmCache)
        .then(packages => res.json(packages))
        .catch(err => error(err.toString()));
    });

    // releases.json
    this.app.get("/packages/:author/:project/releases.json", (req, res) => {
      packageReleases(this.elmCache, req.params.author, req.params.project)
        .then(releases => res.json(releases))
        .catch(err => error(err.toString()));
    });

    // docs.json
    this.app.get(
      "/packages/:author/:project/:version/docs.json",
      (req, res) => {
        const docsPath = path.resolve(
          this.elmCache,
          req.params.author,
          req.params.project,
          req.params.version,
          "docs.json"
        );
        res.sendFile(docsPath);
      }
    );

    // README
    this.app.get(
      "/packages/:author/:project/:version/README.md",
      (req, res) => {
        const readmePath = path.resolve(
          this.elmCache,
          req.params.author,
          req.params.project,
          req.params.version,
          "README.md"
        );
        res.sendFile(readmePath);
      }
    );

    // elm.json
    this.app.get("/packages/:author/:project/:version/elm.json", (req, res) => {
      const manifestPath = path.resolve(
        this.elmCache,
        req.params.author,
        req.params.project,
        req.params.version,
        "elm.json"
      );
      res.sendFile(manifestPath);
    });

    // Source
    this.app.use(
      "/source",
      express.static(this.elmCache, {
        setHeaders: (res, path, stat) => {
          if (path.endsWith("/LICENSE")) {
            res.setHeader("Content-Type", "text/plain");
          }
        }
      }),
      serveIndex(this.elmCache, { icons: true })
    );

    // default route
    this.app.get("*", (req, res) => {
      res.sendFile(path.join(__dirname, "../static/index.html"));
    });
  }

  listen(port = 8000) {
    return this.app.listen(port, () => {
      info(
        chalk`{blue Browse} {bold {green <http://localhost:${port.toString()}>}} {blue to see your documentation}`
      );
    });
  }

  broadcast(data: string) {
    this.wss.clients.forEach(client => {
      if (client.readyState === ws.OPEN) {
        client.send(data);
      }
    });
  }

  send(type: string, data: string) {
    this.broadcast(JSON.stringify({ type, data }));
  }
}

module.exports = DocServer;
