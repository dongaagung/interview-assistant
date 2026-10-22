import Foundation

/// A prepared behavioral story in Situation / Task / Action / Result form.
struct StarStory: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var title = ""
    var situation = ""
    var task = ""
    var action = ""
    var result = ""
    var tags: [String] = []
}
