#!/usr/bin/env node

const path = require("path");
const chalk = require("chalk");
const spawn = require("cross-spawn");
const commander = require("commander");
const latestVersion = require("latest-version");
const {
  DocServer,
  info,
  warning,
  error,
  fatal
} = require("./lib/elm-doc-server");

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

/*
 * Check if a newer version is available
 */
function checkUpdate(currentVersion) {
  latestVersion("elm-doc-preview").then(lastVersion => {
    if (lastVersion !== currentVersion) {
      warning(`elm-doc-preview ${lastVersion} is available`);
    }
  });
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
    fatal(`unsupported Elm version ${elm.version}`);
  }

  return [elm, version];
}

/*
 * Run program
 */
const program = init();
checkUpdate(npmPackage.version);
const [elm, elmVersion] = getElm();
info(
  chalk`{bold elm-doc-preview ${npmPackage.version}} using elm ${elmVersion}`
);

const docServer = new DocServer(program.dir, elm, program.port);

process
  .on("SIGINT", () => {
    docServer.removeDocsJson();
    process.exit(0);
  })
  .on("uncaughtException", e => {
    if (e.errno === "EADDRINUSE") {
      fatal(chalk.red(`port ${program.port} already used, use --port option`));
    } else {
      console.log(chalk.red(e));
      process.exit(1);
    }
  });

docServer.run();
