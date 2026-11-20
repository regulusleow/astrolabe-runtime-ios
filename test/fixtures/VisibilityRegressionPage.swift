import SwiftUI

struct VisibilityRegressionPage: View {
    /// Revision changes visibility without giving the inspector expected values.
    let revision: Int
    var body: some View {
        if revision == 2 {
            Text("VIS Unsupported clip").frame(width: 160, height: 60).clipShape(Circle())
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("VIS Normal")
                Text("VIS Opacity zero").opacity(revision == 0 ? 0 : 1)
                Text("VIS Boundary").opacity(revision == 0 ? 0.01 : 1)
                VStack { Text("VIS Nested opacity").opacity(0.05) }.opacity(revision == 0 ? 0.1 : 1)
                Text("VIS Opacity low").opacity(revision == 0 ? 0.005 : 0.5)
                VStack { Text("VIS Parent opacity") }.opacity(revision == 0 ? 0.005 : 1)
                Text("VIS Hidden").hidden()
                Text("VIS Offscreen").offset(x: revision == 0 ? 600 : 0)
                VStack { Text("VIS Clipped").offset(x: revision == 0 ? 160 : 0) }
                    .frame(width: 100, height: 30).clipped()
                ZStack { Text("VIS Covered"); Color.blue.frame(width: 220, height: 30).allowsHitTesting(false) }
                    .frame(height: 30)
                Text("VIS Noninteractive").allowsHitTesting(false)
            }.font(.system(size: 18)).padding(20)
        }
    }
}
