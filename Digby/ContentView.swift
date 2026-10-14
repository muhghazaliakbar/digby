import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Hello, Digby!")
                .font(.largeTitle.bold())
        }
        .padding(40)
        .frame(minWidth: 480, minHeight: 320)
    }
}

#Preview {
    ContentView()
}
