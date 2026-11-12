import SwiftUI

/// Lumen's accent. Selected / active controls were yellow; they are now a vampire rose.
/// It is deliberately pinker than the system red used for the recording indicators, so
/// "this control is on" never looks like "recording".
enum LumenTheme {
    static let accent = Color(red: 1.0, green: 0.302, blue: 0.427)   // #FF4D6D
    static let blood  = Color(red: 0.620, green: 0.059, blue: 0.157) // #9E0F28
    static let void   = Color(red: 0.020, green: 0.008, blue: 0.012) // #050203
}
