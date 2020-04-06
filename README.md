# elm-doc-preview

This is an Elm 0.19 **offline** documentation previewer for **packages**,
**applications**, their **dependencies** and **all cached packages**.

It aims at rendering documentation exactly like the
[official package website](https://package.elm-lang.org) to avoid
any surprise when releasing a package.

# Features

- **Packages** and **Applications** support with **documentation hot reloading**
- **Offline cached packages documentation server**
- Source and documentation compilation errors display
- Online documentation sharing for reviews (using the
 [online version](#online-version))

![elm-doc-preview](https://github.com/dmy/elm-doc-preview/raw/fa63e1d/screenshots/elm-doc-preview.png)

# Installation

```sh
$ npm install -g elm-doc-preview
```

# Synopsis

```text
Usage: edp [options] [path_to_package_or_application]

Options:
  -V, --version             output the version number
  -b, --no-browser          do not open in browser when server starts
  -o, --output <docs.json>  generate docs and exit with status code (/dev/null supported)
  -p, --port <port>         the server listening port (default: 8000)
  -r, --no-reload           disable hot reloading
  -h, --help                output usage information

Environment variables:
  ELM_HOME           Elm home directory (cache)
```

For example, from the directory where your project `elm.json` is:

```sh
$ elm-doc-preview
```

or

```sh
$ edp
```

or from anywhere:

```sh
$ elm-doc-preview path/to/package_or_application
```
When no package or application is found, `elm-doc-preview` will just run as an
offline documentation server for local cached packages.

# Applications support
Application documentation is
[not yet supported by Elm](https://github.com/elm/compiler/issues/1835#issuecomment-440080525),
so `elm-doc-preview` will generate a package from the application with the same
modules and build the documentation from it. There are two consequences:
1. You have to define an `elm-application.json` file to list the application
documented modules (**exposed-modules**) and to customize the application
**name**, **summary** or **version** that are included in the documentation.
2. The application ports will be stubbed with fake versions as ports are
forbidden in packages. This means that ports will appear as normal functions in
the documentation. Also currently, this requires ports declarations to be on
one line, if this is an issue for you, please
[open an issue](https://github.com/dmy/elm-doc-preview/issues).

Without an `elm-application.json` file, `elm-doc-preview` will show an
application as `my/application 1.0.0` and will report an error about
missing `exposed-modules` unless some are eventually found in forked or
local packages included in the application `source-directories`.

**To configure the application, add an `elm-application.json` file with at least
an `exposed-modules` value.**

For example, here is the
[elm-application.json](https://github.com/dmy/elm-doc-preview/blob/master/elm-application.json)
file for the `elm-doc-preview` Elm application followed by a description of
each field:

`elm-application.json`:
```elm-application.json
{
    "name": "dmy/elm-doc-preview",
    "summary": "Offline documentation previewer",
    "version": "3.0.0",
    "exposed-modules": [
        "Href",
        "Session",
        "Page.Docs.Block",
        "Page.Search",
        "Page.Diff",
        "Page.Problem",
        "Page.Docs",
        "Page.Search.Entry",
        "Release",
        "Utils.Spinner",
        "Utils.OneOrMore",
        "Utils.Logo",
        "Utils.Error",
        "Utils.Markdown",
        "Main",
        "Skeleton"
    ]
}
```
#### **"name"**
It should use the same `author/project` format than packages, but the
repository does not have to exist on GitHub.

The default name is `my/application`.

#### **"summary"**
A short summary for the application in less than 80 characters.

The default summary is "Elm application".

#### **"version"**
A version using `MAJOR.MINOR.PATCH` format.

The default version is "1.0.0".

#### **"exposed-modules"**
The modules to include in the documentation.
All exposed symbols inside these modules must be documented or the
documentation build will fail.

Port modules will be shown as normal modules.

Exposed modules contain by default those found in forked and local
packages (see next section). Setting the field does not remove those
modules from the list.

# Forked and local packages in applications
`elm-doc-preview` will automatically exposes documentation for forked or local
packages modules if their are exposed in an `elm.json` file located in the
directory above the one declared in `source-directories`.

Typically, to import a forked package and keep its documentation, just clone it
in the application directory, and add the forked packages `src` sub-directory
in `elm.json` `source-directories`.


# Online version

There is also an online version supporting documentations loading from github
to share them for online reviews:

https://elm-doc-preview.netlify.com

It does not support hot-reloading or dependencies documentation though.

# API
```javascript
const DocServer = require('elm-doc-preview');
const server = new DocServer();
server.listen();
```

or with custom options:

```javascript
const DocServer = require('elm-doc-preview');

// constructor(options) {
//   const {
//     dir = ".",
//     port = 8000,
//     browser = true,
//     reload = true
//   } = options || {};
//   ...
const server = new DocServer({ port: 9000, browser: false });

server.listen();
```

# FAQ

## Is elm-doc-preview secure enough to publicly host documentation?
`elm-doc-preview` is a development tool and is not designed to be
exposed on internet. As such, no effort at all has been made to secure it
and it most likely contains severe vulnerabilities. If you want to
publicly share some documentation, use the online version or maybe host
static web pages of the documentation (see below).

## How to generate static web pages of the documentation
This is not supported by `elm-doc-preview`, you could use [ento/elm-doc](https://github.com/ento/elm-doc) instead.


## Why adding elm-application.json instead of using elm.json?
Extending `elm.json` would not be convenient because `elm install`
will remove any unexpected field from it when run, and all the additional
fields used by `elm-doc-preview` are currently unexpected for an application,
even if they are valid for a package.

## Why my forked/local/vendored packages modules are not automatically documented?
They are automatically added in the documentation if you kept the package
`elm.json` file in the directory above the package `src` one.

# Credits

- Documentation rendering from [package.elm-lang.org](https://github.com/elm/package.elm-lang.org) by Evan Czaplicki.
- Markdown rendering from [Marked.js](https://github.com/markedjs/marked) by Christopher Jeffrey.
- Code highlighting from [highlight.js](https://github.com/highlightjs/highlight.js) by Ivan Sagalaev.
- Code highlighting theme from [Solarized](ethanschoonover.com/solarized) by Jeremy Hull.
- CSS spinner from [SpinKit](https://github.com/tobiasahlin/SpinKit) by Tobias Ahlin.
- [Source Sans Pro](https://github.com/adobe-fonts/source-sans-pro) and
  [Source Code Pro](https://github.com/adobe-fonts/source-code-pro) fonts by Paul D. Hunt.
