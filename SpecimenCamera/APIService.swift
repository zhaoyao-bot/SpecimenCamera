import Foundation
import UIKit

@MainActor
class APIService: ObservableObject {
    static let shared = APIService()

    @Published var isLoading = false
    @Published var errorMessage: String?

    private var baseURL: String { APIConfig.activeBaseURL }

    private init() {}

    // MARK: - Generic Request

    private func request<T: Decodable>(_ path: String,
                                        method: String = "GET",
                                        body: Encodable? = nil,
                                        queryParams: [String: String]? = nil) async throws -> T {
        var components = URLComponents(string: "\(baseURL)\(path)")
        if let params = queryParams {
            components?.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        if let body = body {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            request.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.serverError(msg)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - Multipart Upload

    private func uploadMultipart(_ path: String,
                                  fields: [String: String],
                                 files: [(String, Data, String)] = []) async throws -> SpecimenTile {
        let boundary = "Boundary-\(UUID().uuidString)"
        let url = URL(string: "\(baseURL)\(path)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        var body = Data()

        // Text fields
        for (key, value) in fields {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        // File fields
        for (key, fileData, filename) in files {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(fileData)
            body.append("\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Upload failed"
            throw APIError.serverError(msg)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(SpecimenTile.self, from: data)
    }

    // MARK: - Specimens

    func fetchSpecimens() async throws -> [Specimen] {
        try await request("/manager/specimens/list")
    }

    func fetchSpecimensWithMagnifications() async throws -> SpecimensListResponse {
        try await request("/manager/specimens/list-with-magnifications")
    }

    // MARK: - Ratios

    func fetchRatios(specimenId: Int) async throws -> [SpecimenRatio] {
        try await request("/manager/specimen-ratios/list",
                          queryParams: ["specimen_id": "\(specimenId)"])
    }

    /// Fetch all specimen ratios (no specimen filter — for calibration)
    func fetchAllRatios() async throws -> [SpecimenRatio] {
        try await request("/manager/specimen-ratios/list")
    }

    func fetchRatiosByTiles(specimenId: Int) async throws -> [SpecimenRatio] {
        try await request("/manager/specimen-tiles/ratio",
                          queryParams: ["specimen_id": "\(specimenId)"])
    }

    func updateRatioRuler(ratioId: Int, ruler: Double) async throws -> SpecimenRatio {
        struct RulerUpdate: Encodable {
            let ruler: Double
        }
        return try await request("/manager/specimen-ratios/\(ratioId)",
                                  method: "PUT",
                                  body: RulerUpdate(ruler: ruler))
    }

    // MARK: - Collectors

    func fetchCollectors() async throws -> [SpecimenCollector] {
        try await request("/manager/specimens/collectors")
    }

    // MARK: - Stacks (Material Packs)

    func fetchStacks(specimenId: Int, ratioId: Int) async throws -> [SpecimenTileStacked] {
        try await request("/manager/specimen-tile-stacked/list",
                          queryParams: ["specimen_id": "\(specimenId)", "ratio_id": "\(ratioId)"])
    }

    func createStack(specimenId: Int, ratioId: Int, stackName: String,
                     light: Double? = nil, lightCircle: Double? = nil, lightField: Int? = nil) async throws -> SpecimenTileStacked {
        struct StackCreate: Encodable {
            let specimenId: Int
            let ratioId: Int
            let name: String
            let light: Double?
            let lightCircle: Double?
            let lightField: Int?
        }
        return try await request("/manager/specimen-tile-stacked/create",
                                  method: "POST",
                                  body: StackCreate(specimenId: specimenId,
                                                    ratioId: ratioId,
                                                    name: stackName,
                                                    light: light,
                                                    lightCircle: lightCircle,
                                                    lightField: lightField))
    }

    // MARK: - Tile Upload

    func uploadTile(specimenId: Int,
                    ratioId: Int,
                    seqId: Int,
                    parentSeq: Int,
                    direction: String,
                    stackId: Int,
                    collectionDate: String?,
                    collector: String?,
                    canvasImage: Data?,
                    cameraImage: Data?) async throws -> SpecimenTile {
        var fields: [String: String] = [
            "specimen_id": "\(specimenId)",
            "ratio_id": "\(ratioId)",
            "seq_id": "\(seqId)",
            "parent_seq": "\(parentSeq)",
            "direction": direction,
            "stack_id": "\(stackId)"
        ]
        if let date = collectionDate { fields["collection_date"] = date }
        if let person = collector { fields["collector"] = person }

        var files: [(String, Data, String)] = []
        if let data = canvasImage {
            files.append(("canvasImage", data, "canvas_\(seqId).jpg"))
        }
        if let data = cameraImage {
            files.append(("cameraImage", data, "camera_\(seqId).jpg"))
        }

        return try await uploadMultipart("/manager/specimen-tiles/mid",
                                          fields: fields,
                                          files: files)
    }

    // MARK: - Fetch Tile Image

    func fetchTileImage(urlString: String) async throws -> UIImage {
        guard let url = URL(string: "\(baseURL)/manager/specimen-tiles/image?image_url=\(urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString)") else {
            throw APIError.invalidURL
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let image = UIImage(data: data) else {
            throw APIError.invalidImage
        }
        return image
    }

    /// Fetch tile image and downscale to thumbnail size for faster loading
    func fetchTileThumbnail(urlString: String, maxSize: CGFloat = 88) async throws -> UIImage {
        guard let url = URL(string: "\(baseURL)/manager/specimen-tiles/image?image_url=\(urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString)") else {
            throw APIError.invalidURL
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let image = UIImage(data: data) else {
            throw APIError.invalidImage
        }
        // Downscale to thumbnail
        let scale = min(maxSize / image.size.width, maxSize / image.size.height)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let thumbnail = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return thumbnail
    }

    // MARK: - Fetch Tiles

    func fetchTiles(specimenId: Int, ratioId: Int, stackId: Int?) async throws -> TilesListResponse {
        var params = ["specimen_id": "\(specimenId)", "ratio_id": "\(ratioId)"]
        if let sid = stackId { params["stack_id"] = "\(sid)" }
        return try await request("/manager/specimen-tiles/list", queryParams: params)
    }

    /// Fetch a single tile by ID (returns full data including image URLs)
    func fetchTileById(tileId: Int) async throws -> SpecimenTile {
        return try await request("/manager/specimen-tiles/find/\(tileId)")
    }
}

// MARK: - Response Types

struct SpecimensListResponse: Decodable {
    let specimens: [SpecimenWithRatios]?
    let total: Int?
}

struct TilesListResponse: Decodable {
    let tiles: [SpecimenTile]?
    let total: Int?
    let skip: Int?
    let limit: Int?
}

// MARK: - Errors

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(String)
    case invalidImage
    case encodingError

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的URL"
        case .invalidResponse: return "无效的响应"
        case .serverError(let msg): return "服务器错误: \(msg)"
        case .invalidImage: return "图片解析失败"
        case .encodingError: return "数据编码失败"
        }
    }
}
