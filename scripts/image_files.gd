# image_files.gd
#
# The file-name rules of the folders that hold pictures: res://icons (IconRegistry),
# the folders of the tilesets (TilesetManager) and the test that checks the icon index.
# Such a folder also holds readmes, import sidecars and *.uid files; only a file with
# a picture extension is a picture itself.

# Godot imports these as textures, so a picture may be drawn in any of them.
const IMAGE_SUFFIXES: Array[String] = [".png", ".svg", ".webp", ".jpg", ".jpeg", ".bmp", ".tga"]

# Files generated next to an asset: the import sidecar, the export remap and the uid.
const SKIP_SUFFIXES: Array[String] = [".import", ".remap", ".uid"]

static func is_image(file_name: String) -> bool:
    if file_name.begins_with("."):
        return false
    var lower := file_name.to_lower()
    for suffix in SKIP_SUFFIXES:
        if lower.ends_with(suffix):
            return false
    for suffix in IMAGE_SUFFIXES:
        if lower.ends_with(suffix):
            return true
    return false
