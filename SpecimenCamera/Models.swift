import Foundation
import UIKit

// MARK: - API Configuration

struct APIConfig {
    static let baseURL = "http://192.168.4.31:8903"
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

// MARK: - Specimen Tile Product (瓦片产品: 拆分堆叠后的 512x512 瓦片)

/// 瓦片产品记录, 显微镜模拟器的数据源。
/// 后台字段命名存在多种可能, 这里做多 key 宽容解码, 后台字段调整后 App 仍可工作。
struct SpecimenTileProduct: Decodable, Identifiable {
    let id: Int
    let specimenId: Int
    let ratioId: Int
    let stackId: Int
    let locMid: String?
    let locTop: String?
    let locBottom: String?
    let locX: Int?
    let locY: Int?
    let locZ: Int?
    let layer: String?
    let status: Int?
    let updateTime: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)

        func str(_ keys: [String]) -> String? {
            for k in keys {
                if let v = try? c.decode(String.self, forKey: AnyKey(k)), !v.isEmpty { return v }
            }
            return nil
        }
        func int(_ keys: [String]) -> Int? {
            for k in keys {
                if let v = try? c.decode(Int.self, forKey: AnyKey(k)) { return v }
                if let d = try? c.decode(Double.self, forKey: AnyKey(k)) { return Int(d) }
            }
            return nil
        }

        id = int(["id", "tile_product_id"]) ?? 0
        specimenId = int(["specimen_id", "specimenId"]) ?? 0
        ratioId = int(["ratio_id", "ratioId"]) ?? 0
        stackId = int(["stack_id", "stackId"]) ?? 0
        locMid = str(["loc_mid", "locMid", "mid", "url", "image_url"])
        locTop = str(["loc_top", "locTop", "top"])
        locBottom = str(["loc_bottom", "locBottom", "bottom"])
        locX = int(["loc_x", "locX", "x", "col"])
        locY = int(["loc_y", "locY", "y", "row"])
        locZ = int(["loc_z", "locZ", "z"])
        layer = str(["layer", "type", "loc_type"])
        status = int(["status"])
        updateTime = str(["update_time", "updateTime"])
    }

    struct AnyKey: CodingKey {
        let stringValue: String
        init(_ s: String) { stringValue = s }
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
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
