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

### GUI
To run the tool in GUI mode, double-click the executable file in your file
explorer or run it from the command line without any additional arguments (i.e. 
`reqtool` and nothing after that).

Use the file browser to navigate to the directory that contains the files you
want to include in the .req file. Directory names are light blue and have a `->`
beside them, and can be double-clicked to enter them.

Toggle the selection of individual files by single-clicking them in the file
browser. Directories can be selected by single-clicking them, which essentially
selects each file immediately inside that directory (but not in sub-directories).

Once one or more files are selected, enter the desired name for the output .req
file in the text area at the bottom of the window. The name defaults to the base
name of the directory you have browsed to - for example, if the current path is
`/home/user/BF2_ModTools/data_ABC/Sides/imp` the output file will default to
`imp.req` unless you change it.

Press "Generate REQ" to create the .req file. Currently it is created in the
same location where you launched **reqtool** from.

There are options in the "Options" pane on the right side of the window that can
be adjusted as needed.

### Command Line
Open `cmd` or Powershell on Windows, or a shell such as `bash` or `zsh` on 
Linux. Invoke the tool using the following pattern:

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

- [x] Basic GUI
- [ ] Automatic handling of platform-specific sub-directories, e.g. `msh/PC`

## Compiling from Source
1. Install `zig` on your machine; version `0.12.0` (minimum) is required 
2. Clone this repository: `git clone https://github.com/jdrempel/reqtool.git`
3. From within the repository root (`cd reqtool`) run 
   `zig build -Doptimize=ReleaseSafe` (use `zig build -h` and look under
   "Project-Specific Options" for a list of, well, project-specific build options)
