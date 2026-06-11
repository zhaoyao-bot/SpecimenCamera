import Foundation

// MARK: - API Configuration

struct APIConfig {
    static let baseURL = "https://specimen.example.com"
    static var activeBaseURL: String {
        UserDefaults.standard.string(forKey: "api_base_url") ?? baseURL
    }
}

// MARK: - Specimen

struct Specimen: Codable, Identifiable {
    let id: Int
    let name: String
    let thirdId: String?
    let status: Int?
    let createdAt: String?
    let updatedAt: String?
}

struct SpecimenWithRatios: Codable {
    let id: Int
    let name: String
    let thirdId: String?
    let status: Int?
    let ratios: [SpecimenRatio]?
}

struct SpecimenCollector: Codable, Identifiable {
    var id: String { collector }
    let collector: String
}

// MARK: - Specimen Ratio

struct SpecimenRatio: Codable, Identifiable {
    let id: Int
    let name: String
    let specimenId: Int?
    let ratio: String?
    let status: Int?
    let createdAt: String?
    let updatedAt: String?
}

// MARK: - Material Pack (Stacked)

struct SpecimenTileStacked: Codable, Identifiable {
    let id: Int
    let specimenId: Int
    let ratioId: Int
    let stackName: String?
    let light: Double?
    let lightCircle: Double?
    let lightField: Int?
    let ruler: String?
    let status: Int?
    let locMid: String?
    let locTop: String?
    let createdAt: String?
    let updatedAt: String?
}

// MARK: - Specimen Tile

struct SpecimenTile: Codable, Identifiable {
    let id: Int
    let specimenId: Int
    let ratioId: Int
    let seqId: Int
    let parentSeq: Int
    let direction: String?
    let stackId: Int?
    let collectionDate: String?
    let collector: String?
    let canvasImage: String?
    let cameraImage: String?
    let createdAt: String?
    let updatedAt: String?
}

// MARK: - Tile Queue Item (Local)

struct TileQueueItem: Identifiable {
    let id = UUID()
    let direction: Direction
    var parentSeq: Int
    var seqId: Int
    let image: UIImage?
    let cameraImage: UIImage?
    let timestamp: Date

    enum Direction: String, CaseIterable, Codable {
        case up = "上"
        case down = "下"
        case left = "左"
        case right = "右"
        case center = "中"
    }
}
