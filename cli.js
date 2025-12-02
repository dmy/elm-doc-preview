#!/usr/bin/env node

import chalk from "chalk";
import { Command } from "commander";
import latestVersion from "latest-version";
import DocServer from "./lib/elm-doc-server.js";
import { version } from "./lib/version.js";

/*
 * Program options and usage
 */
function init() {
  let pkgPath = ".";
  const program = new Command();
  program
    .version(version)
    .arguments("[path_to_package_or_application]")
    .action((dir) => {
      if (dir !== undefined) {
        pkgPath = dir;
      }
    })
    .option("-a, --address <address>", "the server listen address", "127.0.0.1")
    .option("-b, --no-browser", "do not open in browser when server starts")
    .option(
      "-d, --debug",
      "enable debug (display watched files and keep temporary files)"
    )
    .option(
      "-o, --output <docs.json>",
      "generate docs and exit with status code (/dev/null supported)"
    )
    .option("-p, --port <port>", "the server listen port", Math.floor, 8000)
    .option("-r, --no-reload", "disable hot reloading")
    .option("-v, --verbose", "verbose console output (including documentation errors in server mode, output mode always shows errors)");

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
  latestVersion("elm-doc-preview")
    .then((lastVersion) => {
      if (lastVersion !== currentVersion) {
        console.log(
          chalk.yellow(`elm-doc-preview ${lastVersion} is available`)
        );
      }
    })
    .catch(() => {});
}

/*
 * Run program
 */
const program = init();
checkUpdate(version);

const options = program.opts();

process
  .on("SIGINT", () => process.exit(0))
  .on("uncaughtException", (e) => {
    if (e.errno === "EADDRINUSE") {
      console.log(
        chalk.red(`port ${program.port} already used, use --port option`)
      );
    } else {
      console.log(chalk.red(e));
    }
    process.exit(1);
  });

const docServer = new DocServer(options);

if (options.output) {
  docServer.make(options.output);
} else {
  docServer.listen();
}
