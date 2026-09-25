import AppKit
import SwiftUI

struct AppIconView: View {
    let path: String
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

/// 统一的图标：系统功能项用 SF Symbol，其余用文件/应用图标
struct ItemIconView: View {
    let item: LaunchItem
    let size: CGFloat
    var color: Color = .primary

    var body: some View {
        Group {
            if let symbol = item.symbol {
                Image(systemName: symbol)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size * 0.78, height: size * 0.78)
                    .foregroundStyle(color)
            } else {
                AppIconView(path: item.path, size: size)
            }
        }
        .frame(width: size, height: size)
    }
}
