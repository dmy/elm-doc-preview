#!/usr/bin/env node

const path = require("path");
const chalk = require("chalk");
const commander = require("commander");
const latestVersion = require("latest-version");
const DocServer = require("./lib/elm-doc-server");

const npmPackage = require(path.join(__dirname, "package.json"));

/*
 * Program options and usage
 */
function init() {
  let pkgPath = ".";
  const program = commander
    .version(npmPackage.version)
    .arguments("[path_to_package_or_application]")
    .action(dir => {
      if (dir !== undefined) {
        pkgPath = dir;
      }
    })
    .option("-p, --port <port>", "the server listening port", Math.floor, 8000);

  program.on("--help", () => {
    console.log("");
    console.log("Environment variables:");
    console.log("  ELM_HOME           Elm home directory (cache)");
  });

  program.parse(process.argv);
  program.dir = pkgPath;
  return program;
}

/*
 * Check if a newer version is available
 */
function checkUpdate(currentVersion) {
  latestVersion("elm-doc-preview").then(lastVersion => {
    if (lastVersion !== currentVersion) {
      console.log(chalk.yellow(`elm-doc-preview ${lastVersion} is available`));
    }
  });
}

/*
 * Run program
 */
const program = init();
checkUpdate(npmPackage.version);

const docServer = new DocServer(program.dir);

process
  .on("SIGINT", () => {
    process.exit(0);
  })
  .on("uncaughtException", e => {
    if (e.errno === "EADDRINUSE") {
      console.log(
        chalk.red(`port ${program.port} already used, use --port option`)
      );
    } else {
      console.log(chalk.red(e));
    }
    process.exit(1);
  });

docServer.listen(program.port);
