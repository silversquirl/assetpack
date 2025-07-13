# assetpack

This is a simple build-time Zig library for packing a directory tree into your binary.
It's primarily designed for use in games and other graphical applications, where it can be useful to
embed some (or all, if they're particularly small) of your asset files directly into the binary.

For example, you might want to embed your fonts so you can still display error messages even when
the rest of your game assets fail to load, or you might want to embed icons so your graphical
application can be distributed as a single binary.

## Usage

First, add the dependency:

```sh
zig fetch --save git+https://github.com/silversquirl/assetpack
```

Then, in your build script, import and use the library:

```zig
const assetpack = @import("assetpack");
const assets_module = assetpack.pack(b, b.path("path/to/asset/dir"));
exe.root_module.addImport("assets", assets_module);
```

Once you've added the generated assets module to your Zig program, you can access the file data by
importing it. Each directory is represented as a namespace, and each file is a constant string.

```zig
const assets = @import("assets");
std.log.debug("content of foo/bar/baz.txt: {s}", .{assets.foo.bar.@"baz.txt"});
```

## Alternatives

There are several ways to solve this problem. Here's how `assetpack` compares:

- The simplest option is to manually call `@embedFile` for every file you need.
  This works great in simple cases, however it is quite common to have a project structure that
  puts assets in a separate directory from the Zig source code. Since Zig does not allow importing
  or embedding paths outside the module root, this approach doesn't work for those cases.

- A common approach is to call `std.fs.Dir.walk` inside `build.zig` and create a new module for each
  discovered file. This solves the issues with the first approach, as `@embedFile("module_name")`
  has no problems with the module being in a separate directory.

  However, this is actually a very bad idea, as it slows down *every* usage of `build.zig`,
  including things like `zig build --help`, or completely unrelated build steps that don't need any
  knowledge of the asset directory.

  This option will also become impossible if [build.zig logic is run in a sandbox][build_sandbox].

- [PhysicsFS][physfs] is a C library that allows merging multiple data sources into a single
  "filesystem" with a unified API. Using this, or similar libraries, it is possible to pack an asset
  directory into a zip file and access it with the same API as you would use for regular files.

  `assetpack` does not yet support this kind of API, but I am interested in the idea of adding
  support for it. One major benefit of `assetpack` over PhysicsFS is that the files are packed into
  the actual binary, rather than simply a zip file distributed next to the binary.

- A variant on the PhysicsFS approach is to pack assets into a zip file, and then expose that file
  as a module to be used with `@embedFile`. This has some unique advantages over both PhysicsFS and
  `assetpack`, as it combines compression with embedding into the binary.

  However, the API for this is not very pleasant, and the embedded files are next to impossible to
  use at comptime, due to the complexity of zip decompression.
  There are also some performance issues with this approach, since DEFLATE decompression is
  relatively slow, and file lookup in zip files requires iteration over the entire index.

[build_sandbox]: https://github.com/ziglang/zig/issues/14286
[physfs]: https://icculus.org/physfs/

## Future features

`assetpack` is currently very simple and somewhat limited.
In future, I'd like to support some additional features:

- Filename filtering, eg. ignore files with specific extensions, or those in `.gitignore`. 
  A sensible default would be to check the containing package's `paths` field in its `build.zig.zon`.

- Modifying files before they enter the asset index. For example running a shader compiler or an
  image converters. This would make it much easier to move an entire game development asset pipeline
  into `build.zig`

- Optional compression. This could be implemented using the file modification system, but having it
  built-in is likely to result in a nicer API.

- Filesystem-style API, similar to PhysicsFS. Ideally, this could integrate directly into Zig's
  standard library APIs through a custom `std.Io` implementation.

- Support for structured data formats such as JSON and ZON. I would like this to be able to provide
  both parsed representations and the raw byte data.

  This can already be done by parsing the data at comptime, however implementing this in `assetpack`
  directly could result in a nicer API and faster build times. 
