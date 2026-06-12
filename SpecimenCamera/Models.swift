import Foundation
import UIKit

// MARK: - API Configuration

struct APIConfig {
    static let baseURL = "http://192.168.3.31:8903"
    static var activeBaseURL: String {
        UserDefaults.standard.string(forKey: "api_base_url") ?? baseURL
    }
}

// MARK: - Specimen

struct Specimen: Codable, Identifiable {
    let id: Int
    let name: String
    let thirdId: Int?
    let status: Int?
    let updateTime: String?

    enum CodingKeys: String, CodingKey {
        case id, name, status, thirdId, updateTime
    }
}

struct SpecimenWithRatios: Codable {
    let id: Int
    let name: String
    let thirdId: Int?
    let status: Int?
    let updateTime: String?
    /// e.g. ["40、1", "100、1", "400、3"] — "倍数、堆叠数"
    let magnifications: [String]?

    enum CodingKeys: String, CodingKey {
        case id, name, status, magnifications, thirdId, updateTime
    }

    /// Parse magnification strings into (ratioName, stackCount) pairs
    var parsedMagnifications: [(name: String, stackCount: Int)] {
        magnifications?.compactMap { mag in
            let parts = mag.components(separatedBy: "、")
            guard parts.count == 2,
                  let count = Int(parts[1]) else { return nil }
            return (name: parts[0], stackCount: count)
        } ?? []
    }
}

struct SpecimenCollector: Codable, Identifiable {
    let id: Int
    let name: String
    let updateTime: String?

    enum CodingKeys: String, CodingKey {
        case id, name, updateTime
    }
}

// MARK: - Specimen Ratio

struct SpecimenRatio: Codable, Identifiable {
    let id: Int
    let ratio: String
    let ruler: Double?
    let status: Int?
    let updateTime: String?

    enum CodingKeys: String, CodingKey {
        case id, ratio, ruler, status, updateTime
    }
}

// MARK: - Material Pack (Stacked)

struct SpecimenTileStacked: Codable, Identifiable {
    let id: Int
    let specimenId: Int
    let ratioId: Int
    let name: String?
    let light: Double?
    let lightCircle: Double?
    let lightField: Int?
    let locX: Int?
    let locY: Int?
    let status: Int?
    let locMid: String?
    let locTop: String?
    let updateTime: String?

    enum CodingKeys: String, CodingKey {
        case id, name, light, status, locMid, locTop
        case specimenId, ratioId, lightCircle, lightField, locX, locY, updateTime
    }

    /// Display name: use `name` field, fallback to "Stack-{id}"
    var stackName: String? { name ?? "Stack-\(id)" }
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
    let status: Int?
    let updateTime: String?

    enum CodingKeys: String, CodingKey {
        case id, direction, collector, status
        case specimenId, ratioId, seqId, parentSeq, stackId
        case collectionDate, updateTime
        case canvasImage = "locMidOriCanvas"
        case cameraImage = "locMidOriCamera"
    }
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
        case up = "top"
        case down = "bottom"
        case left = "left"
        case right = "right"

        /// Chinese display name for UI
        var displayName: String {
            switch self {
            case .up: return "上"
            case .down: return "下"
            case .left: return "左"
            case .right: return "右"
            }
        }
    }
}
