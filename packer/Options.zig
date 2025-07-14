/// If non-null, a namespace of this name will be created in the asset index, through which
/// "getter" functions which allow accessing files by path can be accessed.
getter_namespace: ?[]const u8 = "get",

/// If non-null, included assets will be placed in this namespace within the asset index.
/// This is useful to avoid naming collisions with other namespaces, such as `getter_namespace`.
asset_namespace: ?[]const u8 = null,
