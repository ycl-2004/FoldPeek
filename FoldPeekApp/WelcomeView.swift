import SwiftUI

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image("FoldPeekMark")
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)

            VStack(spacing: 8) {
                Text("FoldPeek")
                    .font(.largeTitle.bold())
                Text("A read-only Quick Look preview for folders")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("Shows folder names and basic file metadata", systemImage: "folder")
                Label("Previews bounded text, Markdown, and images", systemImage: "doc.text.magnifyingglass")
                Label("Does not use the network or run background helpers", systemImage: "network.slash")
            }

            VStack(spacing: 5) {
                Text("System Settings → General → Login Items & Extensions → Quick Look")
                    .font(.callout.weight(.medium))
                Text("Enable FoldPeek, then select a folder in Finder and press Space.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(40)
        .frame(minWidth: 560, minHeight: 420)
    }
}
