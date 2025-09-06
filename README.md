# ZERV

> A short and simple web server written in Zig.

# !!WARNING!!

This is not a finished project, and may feature breaking bugs

## Installation

To install, clone the repo

```sh
$ git clone https://github.com/AtleSkaanes/zerv
$ cd zerv
```

and compile manually

```sh
$ zig build --release=fast
```

## Usage

Simply call `zerv`, and give the path to the directory which holds the files you want to serve

```sh
$ ./zerv -d ./path/to/dir
```

Then simply open your browser and visit `localhost:8000`.
Addionally you can give the address to bind to, as well as the port, with the `-b` and the `-p` flag
