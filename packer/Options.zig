/// If non-null, a decl of this name will be created in the asset index, containing the root directory
/// handle through which the filesystem-style API can be used.
root_dir_decl: ?[]const u8 = "root",

/// When enabled, the generated index file will re-export types from assetpack's support library.
/// This is useful if you are using the filesystem-style API.
expose_types: bool = true,

/// If non-null, the assets will be placed in this namespace within the asset index.
/// This is useful to avoid naming collisions with other generated declarations.
asset_namespace: ?[]const u8 = "files",
