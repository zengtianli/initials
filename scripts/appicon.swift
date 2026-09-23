// Writes the Finder icon of each app as a 512 px PNG: appicon.swift out_dir /path/A.app ...
import AppKit
let out = URL(fileURLWithPath: CommandLine.arguments[1])
for path in CommandLine.arguments.dropFirst(2) {
    let image = NSWorkspace.shared.icon(forFile: path)
    image.size = NSSize(width: 512, height: 512)
    guard let tiff = image.tiffRepresentation(using: .none, factor: 1),
          let rep = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
    let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    try rep.write(to: out.appendingPathComponent(name + ".png"))
}
