import fs from "fs";
import os from "os";
import path from "path";
import process from "process";
import tmp from "tmp";
import chalk from "chalk";
import spawn from "cross-spawn";
import express from "express";
import serveIndex from "serve-index";
import expressWs from "express-ws";
import ws from "ws";
import { SpawnSyncReturns } from "child_process";
import glob from "glob";
import sane from "sane";
import open from "opn";

// For node < 8
require('util.promisify/shim')();
import 'core-js/features/object/entries';
import 'core-js/features/object/values';

import util from "util";
const readFileAsync = util.promisify(fs.readFile);
const globAsync = util.promisify(glob);
const statAsync = util.promisify(fs.stat);

tmp.setGracefulCleanup();

express.static.mime.define({ "text/plain; charset=UTF-8": ["elm"] });
express.static.mime.define({ "text/plain; charset=UTF-8": ["md"] });

interface Manifest {
  type: string;
  name?: string;
  summary?: string;
  license?: string;
  version?: string;
  "exposed-modules": string[] | Record<string, string[]>;
  "elm-version": string;
  dependencies: Record<string, string> | Record<string, Record<string, string>>;
  "test-dependencies": Record<string, string> | Record<string, Record<string, string>>;
  "source-directories"?: string[];

  // dynamically added for convenience
  timestamp: number;
}

interface Package {
  name: string;
  summary: string;
  license: string;
  versions: string[];
}

type Release = Record<string, number>;
type Elm = (args: string[], cwd?: string) => SpawnSyncReturns<Buffer>;

const npmPackage = require(path.join(__dirname, "../package.json"));

function info(...args: any[]) {
  console.log(...args);
}

function warning(...args: any[]) {
  console.log(chalk.yellow(...args));
}

function error(...args: any[]) {
  console.log(chalk.red(...args));
}

function fatal(...args: any[]) {
  error(...args);
  chalk.red("Exiting...");
  process.exit(1);
}

/*
 * Find and check Elm executable
 */
function getElm(): [Elm, string] {
  let elm: Elm = (args, cwd = ".") =>
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

function getElmCache(elmVersion: string) {
  const dir = os.platform() === "win32" ? "AppData/Roaming/elm" : ".elm";
  const home = process.env.ELM_HOME || path.join(os.homedir(), dir);
  const packages = elmVersion === "0.19.0" ? "package" : "packages";
  const cache = path.join(home, elmVersion, packages);
  return cache;
}

async function getManifest(manifestPath: string): Promise<Manifest> {
  return readFileAsync(manifestPath, "utf8")
    .then(async (json) => {
      let manifest = JSON.parse(json);
      let stat = await statAsync(manifestPath);
      manifest["timestamp"] = Math.round(stat.mtime.getTime() / 1000);
      manifest = completeApplication(manifestPath, manifest);
      return manifest;
    })
    .catch(err => error(err));
}

function getManifestSync(manifestPath: string): Manifest | null {
  try {
    const json = fs.readFileSync(manifestPath, "utf8");
    let manifest = JSON.parse(json);
    let stat = fs.statSync(manifestPath);
    manifest["timestamp"] = Math.round(stat.mtime.getTime() / 1000);
    return completeApplication(manifestPath, manifest);
  } catch (err) {
    return null;
  }
}

function completeApplication(manifestPath: string, manifest: Manifest): Manifest {
  if (manifest.type !== "application") {
    return manifest;
  }
  try {
    const elmAppPath = path.resolve(path.dirname(manifestPath), "elm-application.json");
    if (fs.existsSync(elmAppPath)) {
      const elmApp = JSON.parse(fs.readFileSync(elmAppPath).toString());
      Object.assign(manifest, elmApp);
    }
  } catch (err) {
    error(err);
  }
  if (!("name" in manifest)) {
    manifest.name = "my/application";
  }
  if (!("version" in manifest)) {
    manifest.version = "1.0.0";
  }
  if (!("summary" in manifest)) {
    manifest.summary = "Elm application";
  }
  if (!("license" in manifest)) {
    manifest.license = "Fair";
  }
  return manifest;
}

function fullname(manifest: Manifest): string {
  return `${manifest.name}/${manifest.version}`;
}

async function searchPackages(pattern: string): Promise<Record<string, Package>> {
  let paths = await globAsync(pattern + "/elm.json", { realpath: true });
  const manifests = await Promise.all(paths.map(path => getManifest(path)));
  let packages = manifests.reduce((acc, pkg: Manifest) => {
    if (pkg.name && pkg.name in acc && pkg.version) {
      acc[pkg.name].versions.push(pkg.version);
      return acc;
    } else if (pkg.name && pkg.version) {
      acc[pkg.name] = {
        name: pkg.name,
        summary: pkg.summary || "",
        license: pkg.license || "Fair",
        versions: [pkg.version]
      };
      return acc;
    } else {
      warning("invalid elm.json", pkg);
      return acc;
    }
  }, {} as Record<string, Package>);
  return packages;
}

async function packageReleases(pattern: string): Promise<Release> {
  const paths = await globAsync(pattern + "/elm.json", {
    realpath: true
  });
  const manifests = await Promise.all(paths.map(path => getManifest(path)));
  let releases = manifests.reduce((releases, pkg: Manifest) => {
    if (pkg.version && pkg.timestamp) {
      releases[pkg.version] = pkg.timestamp;
      return releases;
    } else {
      return releases;
    }
  }, {} as Release);
  return releases;
}

function merge(objects: object[]): object {
  return objects.reduce((acc, obj) => Object.assign(acc, obj));
}

function buildDocs(manifest: Manifest, dir: string, elm: Elm): object {
  try {
    if (manifest.type == "package") {
      return buildPackageDocs(dir, elm);
    } else if (manifest.type == "application") {
      return buildApplicationDocs(manifest, dir, elm);
    }
  } catch (err) {
    error(err);
  }
  return {};
}

// Return a docs.json or a json error report
function buildPackageDocs(dir: string, elm: Elm): object {
  const tmpFile = tmp.fileSync({ prefix: "elm-docs-", postfix: ".json" });
  const buildDir = path.resolve(dir);
  info(`  |> building ${buildDir} documentation`);
  const build = elm(["make", `--docs=${tmpFile.name}`, "--report=json"], buildDir);
  if (build.error) {
    error(`cannot build documentation (${build.error})`);
  }
  let docs;
  try {
    docs = JSON.parse(fs.readFileSync(tmpFile.name).toString());
  } catch (err) {
    try {
      // Return Errors JSON report
      docs = JSON.parse(build.stderr.toString());
    } catch (err) {
      docs = {};
    }
  }
  tmpFile.removeCallback();
  return docs;
}

function buildApplicationDocs(manifest: Manifest, dir: string, elm: Elm): object {
  info(`  |> building ${path.resolve(dir)} documentation`);
  // Build package from application manifest
  const elmStuff = path.resolve(dir, "elm-stuff");
  if (!fs.existsSync(elmStuff)) {
    fs.mkdirSync(elmStuff);
  }
  const tmpDir = tmp.dirSync({
    dir: elmStuff,
    prefix: "elm-application-",
    unsafeCleanup: true
  });
  const tmpDirSrc = path.resolve(tmpDir.name, "src");
  fs.mkdirSync(tmpDirSrc);

  // Build package manifest
  let pkg: Manifest = {
    type: "package",
    name: manifest.name,
    summary: manifest.summary,
    license: manifest.license,
    version: manifest.version,
    "exposed-modules": manifest["exposed-modules"],
    "elm-version": versionToConstraint(manifest["elm-version"]),
    dependencies: {},
    "test-dependencies": {},
    timestamp: manifest.timestamp
  };

  // Add dependencies constraints
  if (manifest.dependencies.direct) {
    for (const [name, version] of Object.entries(manifest.dependencies.direct)) {
      pkg.dependencies[name] = versionToConstraint(version);
    }
  }

  // Add source directories exposed-modules
  let exposedModules: string[] = getExposedModules(pkg["exposed-modules"]);

  if (manifest["source-directories"]) {
    manifest["source-directories"].forEach(src => {
      const srcDir = path.resolve(src);
      importModules(srcDir, tmpDirSrc);
      const elmJsonPath = path.resolve(src, "../elm.json");

      if (fs.existsSync(elmJsonPath)) {
        try {
          const srcManifest = getManifestSync(elmJsonPath);
          if (srcManifest && srcManifest.type === "package") {
            const srcModules = getExposedModules(srcManifest["exposed-modules"]);
            exposedModules = exposedModules.concat(srcModules);
          }
        } catch (err) {
          error(err);
        }
      }
    });
  }
  pkg["exposed-modules"] = exposedModules;

  // Write elm.json and generate package documentation
  const elmJson = JSON.stringify(pkg);
  fs.writeFileSync(tmpDir.name + "/elm.json", elmJson, "utf8");
  const docs = buildPackageDocs(tmpDir.name, elm);

  // remove temporary directory
  tmpDir.removeCallback();
  return docs;
}

function getExposedModules(manifestExposedModules: string[] | Record<string, string[]> | null): string[] {
  let exposedModules: string[] = [];

  if (manifestExposedModules) {
    if (Array.isArray(manifestExposedModules)) {
      exposedModules = manifestExposedModules;
    } else if (typeof manifestExposedModules === "object") {
      Object.values(manifestExposedModules).forEach(modules => {
        exposedModules = exposedModules.concat(modules);
      });
    }
  }
  return exposedModules;
}

function importModules(srcDir: string, dstDir: string) {
  glob.sync("**/*.elm", { cwd: srcDir }).forEach(elm => {
    try {
      const dir = path.resolve(dstDir, path.dirname(elm));
      mkdirSyncRecursive(path.resolve(dstDir, dir));
      const srcModulePath = path.resolve(srcDir, elm);
      const dstModulePath = path.resolve(dstDir, elm);
      let module = fs.readFileSync(srcModulePath).toString();
      if (module.match(/^port +module /) !== null) {
        // Stub ports by subscriptions and commands that do nothing
        info(`  |> stubbing ${elm} ports`);
        module = module.replace(/^port +([^ :]+)([^\n]+)$/mg, (match, name, decl, off, str) => {
          if (name === "module") {
            return ["module", decl].join(" ");
          } else if (decl.includes("Sub")) {
            info("  |> stubbing incoming port", name);
            return name + " " + decl + "\n" + name + " = always Sub.none\n";
          } else if (decl.includes("Cmd")) {
            info("  |> stubbing outgoing port", name);
            return name + " " + decl + "\n" + name + " = always Cmd.none\n";
          } else {
            warning("unmatched", match);
          }
          return match;
        });
        fs.writeFileSync(dstModulePath, module);
      } else {
        linkModule(srcModulePath, dstModulePath);
      }
    } catch (err) {
      error(err);
    }
  });
}

function mkdirSyncRecursive(dir: string) {
  const absoluteDir = path.resolve(dir);
  const sep = path.sep;
  absoluteDir.split(sep).reduce((parent, child) => {
    const d = path.resolve(parent, child);
    try {
      if (!fs.existsSync(d)) {
        fs.mkdirSync(d);
      }
    } catch (err) {
      error(err);
    }
    return d;
  }, "/");
}

function linkModule(linked: string, link: string) {
  try {
    if (!fs.existsSync(link)) {
      if (os.platform() === "win32") {
        // Windows requires to be admin to create symlinks
        fs.copyFileSync(linked, link);
      } else {
        fs.symlinkSync(linked, link);
      }
    }
  } catch (err) {
    error(err);
  }
}

function versionToConstraint(version: string): string {
  const [major, minor, patch] = version.split(".", 3);
  const nextPatch = parseInt(patch) + 1;
  return `${major}.${minor}.${patch} <= v < ${major}.${minor}.${nextPatch}`;
}

class DocServer {
  dir: string;
  elm: Elm;
  elmVersion: string;
  elmCache: string;
  app: expressWs.Application;
  ws: expressWs.Instance;
  wss: ws.Server;
  manifest: Manifest | null;
  timeout: NodeJS.Timeout | null;

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
    this.manifest = getManifestSync("elm.json");
    this.timeout = null;

    info(
      chalk`{bold elm-doc-preview ${npmPackage.version}} using elm ${
        this.elmVersion
        }`
    );
    if (this.manifest && this.manifest.name && this.manifest.version) {
      info(chalk`Previewing {magenta ${this.manifest.name} ${this.manifest.version}}`,
        `from ${path.resolve(dir)}`);
    } else {
      info(
        `No package or application found in ${this.dir},`,
        "running documentation server only"
      );
    }

    this.setupWebServer();
    if (this.manifest) {
      this.setupFilesWatcher();
    }
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

    // preview
    this.app.get("/preview", (req, res) => {
      if (this.manifest) {
        res.json(this.manifest);
      }
    });
    // search.json
    this.app.get("/search.json", (req, res) => {
      Promise.all([`${this.elmCache}/*/*/*`, "."]
        .map(pattern => searchPackages(pattern)))
        .then(packagesArray => {
          // add/overwrite cache with project
          res.json(Object.values(merge(packagesArray)));
        })
        .catch(err => error(err));
    });

    // releases.json
    this.app.get("/packages/:author/:project/releases.json", (req, res) => {
      const p = req.params;
      const name = `${p.author}/${p.project}`;
      let dirs = [`${this.elmCache}/${name}/*`];
      if (this.manifest && this.manifest.name === name) {
        dirs.push(".");
      }
      Promise.all(dirs.map(dir => packageReleases(dir)))
        .then(releasesArray => {
          // add/overwrite cache with project
          res.json(merge(releasesArray));
        })
        .catch(err => error(err));
    });

    // docs.json
    this.app.get("/packages/:author/:project/:version/docs.json", (req, res) => {
      const p = req.params;
      const name = `${p.author}/${p.project}/${p.version}`;
      if (this.manifest && fullname(this.manifest) === name) {
        res.json(buildDocs(this.manifest, ".", this.elm));
      } else {
        res.sendFile(path.resolve(this.elmCache, name, "docs.json"));
      }
    }
    );

    // Serve README.md files
    this.app.get("/packages/:author/:project/:version/README.md", (req, res) => {
      const p = req.params;
      const name = [p.author, p.project, p.version].join("/");
      if (this.manifest && fullname(this.manifest) === name) {
        res.sendFile(path.resolve(".", "README.md"));
      } else {
        res.sendFile(path.resolve(this.elmCache, name, "README.md"));
      }
    });

    // Serve elm.json files
    this.app.get("/packages/:author/:project/:version/elm.json", (req, res) => {
      const p = req.params;
      const name = `${p.author}/${p.project}/${p.version}`;
      if (this.manifest && fullname(this.manifest) === name) {
        const manifest = getManifestSync("elm.json");
        res.json(manifest);
      } else {
        res.sendFile(path.resolve(this.elmCache, name, "elm.json"));
      }
    });

    let setHeaders = (res: express.Response, path: string, stat: any) => {
      if (path.endsWith("/LICENSE")) {
        res.setHeader("Content-Type", "text/plain; charset=UTF-8");
      }
    };
    // Serve project source
    if (this.manifest) {
      this.app.use(`/source/${fullname(this.manifest)}`,
        express.static(".", { setHeaders: setHeaders }),
        serveIndex(".", { icons: true })
      );
    }
    // Serve cached packages source
    this.app.use("/source",
      express.static(this.elmCache, { setHeaders: setHeaders }),
      serveIndex(this.elmCache, { icons: true })
    );

    // default route
    this.app.get("*", (req, res) => {
      res.sendFile(path.join(__dirname, "../static/index.html"));
    });
  }

  setupFilesWatcher() {
    const glob = ["elm.json", "elm-application.json", "README.md"];
    if (this.manifest && this.manifest["source-directories"]) {
      this.manifest["source-directories"].forEach(src => {
        glob.push(src + "/**/*.elm");
        glob.push(path.normalize(src + "/../elm.json"));
      });
    } else if (this.manifest) {
      glob.push("src/**/*.elm");
    }
    const watcher = sane(this.dir, {
      glob,
      ignored: ["**/node_modules", "**/elm-stuff"]
    });

    watcher.on("ready", () => {
      if (this.manifest && this.manifest.type === "package") {
        info(`  |> watching package`);
      } else if (this.manifest && this.manifest.type === "application") {
        info(`  |> watching application`);
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
  }

  onChange(filepath: string) {
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
      } else if (filepath.endsWith(".json")) {
        this.manifest = getManifestSync("elm.json");
        this.sendManifest();
        this.sendDocs();
      } else if (filepath.endsWith(".elm")) {
        this.sendDocs();
      }
    }, 100);
  }

  sendReadme() {
    const readme = path.join(this.dir, "README.md");
    if (this.manifest && this.manifest.name && this.manifest.name.includes("/")) {
      const [author, project] = this.manifest.name.split("/", 2);
      try {
        info("  |>", "sending README");
        this.broadcast({
          type: "readme",
          data: {
            author: author,
            project: project,
            version: this.manifest.version,
            readme: fs.readFileSync(readme).toString()
          }
        });
      } catch (err) {
        error(err);
      }
    }
  }

  sendManifest() {
    if (this.manifest) {
      if (this.manifest && this.manifest.name && this.manifest.name.includes("/")) {
        const [author, project] = this.manifest.name.split("/", 2);
        info("  |>", "sending Manifest");
        this.broadcast({
          type: "manifest",
          data: {
            author: author,
            project: project,
            version: this.manifest.version,
            docs: this.manifest
          }
        });
      }
    }
  }

  sendDocs() {
    if (this.manifest) {
      if (this.manifest && this.manifest.name && this.manifest.name.includes("/")) {
        const docs = buildDocs(this.manifest, this.dir, this.elm);
        const [author, project] = this.manifest.name.split("/", 2);
        info("  |>", "sending Docs");
        this.broadcast({
          type: "docs",
          data: {
            author: author,
            project: project,
            version: this.manifest.version,
            time: this.manifest.timestamp,
            docs: docs
          }
        });
      }
    }
  }

  listen(port = 8000, browser = true) {
    return this.app.listen(port, () => {
      if (browser && this.manifest && this.manifest.name && this.manifest.version) {
        open(`http://localhost:${port}/packages/${this.manifest.name}/${this.manifest.version}/`);
      } else if (browser) {
        open(`http://localhost:${port}`);
      }
      info(
        chalk`{blue Browse} {bold {green <http://localhost:${port.toString()}>}}`,
        chalk`{blue to see your documentation}`
      );
    });
  }

  broadcast(obj: object) {
    this.wss.clients.forEach(client => {
      if (client.readyState === ws.OPEN) {
        client.send(JSON.stringify(obj));
      }
    });
  }

}

module.exports = DocServer;
