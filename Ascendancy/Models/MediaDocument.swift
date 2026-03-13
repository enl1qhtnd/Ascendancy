import Foundation
import SwiftData
import SwiftUI

@Model
final class MediaDocument {
    var id: UUID
    var title: String
    @Attribute(.externalStorage) var imageData: Data?
    var fileExtension: String?
    var dateAdded: Date
    
    init(id: UUID = UUID(), title: String = "Untitled", imageData: Data? = nil, fileExtension: String? = nil, dateAdded: Date = Date()) {
        self.id = id
        self.title = title
        self.imageData = imageData
        self.fileExtension = fileExtension
        self.dateAdded = dateAdded
    }
}
