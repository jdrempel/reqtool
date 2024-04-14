# reqtool
*A utility for creating .req files for the process of modding Star Wars Battlefront*
*II (2005)*

## Purpose
**reqtool** allows users to pass in a set of files and/or directories and get an
appropriately organized .req file as an output. For example, .odf files will have
their names put under the "class" section, and .tga files will be put under the 
"texture" section.

## Installation
1. Download and unzip the latest release (choose the one appropriate for your OS)
2. Place the `reqtool` or `reqtool.exe` binary file in an accessible location

## Usage
Currently the tool must be run from a command line as there is no GUI available.
This can be accomplished with `cmd` or Powershell on Windows, or a shell such as
`bash` or `zsh` on Linux. Invoke the tool using the following pattern:

```sh
reqtool [OPTIONS...] FILE [FILES...]
```

Use the `-h/--help` option to get a full and up-to-date help message with the
available options. `FILES` can refer to files or directories. If a directory is
given, all of the files within it will be considered *non-recursively* (i.e. any
files inside sub-directories will not be considered).

## Roadmap
*This is not a commitment to these features, just an idea of where I might like*
*to take the project in the future if I am motivated to do so (PRs welcome).*

- [ ] Automatic handling of platform-specific sub-directories, e.g. `msh/PC`
- [ ] Basic GUI

## Compiling from Source
1. Install `zig` on your computer; version `0.12.0-dev.2154` ~~or newer~~ is required (GUI dependencies start to break 
   with 3631; in the future I will try to figure out a proper solution)
2. Clone this repository: `git clone https://github.com/jdrempel/reqtool.git`
3. From within the repository root (`cd reqtool`) run `zig build -Doptimize=ReleaseSafe`
