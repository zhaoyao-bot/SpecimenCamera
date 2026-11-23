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

        var request = URLRequest(url: url,
                                 cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                                 timeoutInterval: 30)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // 内网环境：每次都直接请求后台，不使用任何缓存
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

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

    /// 通过后台代理接口获取图片数据。
    /// 会检查 HTTP 状态码 —— 否则后台返回 404/500 的错误 JSON 时，
    /// 会被笼统报成"图片解析失败"，掩盖真实原因。
    /// 内网环境：每次都直接请求后台，完全绕过本地/远程缓存
    /// (弱网下若缓存到损坏/不完整的响应，会导致后续反复失败)
    func fetchTileImageData(urlString: String) async throws -> Data {
        guard let url = URL(string: "\(baseURL)/manager/specimen-tiles/image?image_url=\(urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url,
                                 cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                                 timeoutInterval: 30)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse {
            let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? "nil"
            print("🖼 图片响应: HTTP \(http.statusCode), Content-Type: \(contentType), 大小: \(data.count) 字节")
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data.prefix(300), encoding: .utf8) ?? ""
                print("❌ 图片请求失败 HTTP \(http.statusCode), 返回: \(body)")
                throw APIError.serverError("HTTP \(http.statusCode) \(body)")
            }
        }

        guard UIImage(data: data) != nil else {
            let preview = String(data: data.prefix(300), encoding: .utf8) ?? "非文本内容"
            print("❌ 图片解析失败(不是有效图片数据)，返回前 300 字节: \(preview)")
            throw APIError.invalidImage
        }
        return data
    }

    /// 探测图片字节数(用于区分空白占位瓦片与有内容的瓦片)。失败返回 0。
    /// 先 HEAD 拿 Content-Length; 服务器不回长度/不支持 HEAD 时,
    /// 用 Range: bytes=0-0 的 206 响应解析 Content-Range 总长。
    func fetchTileContentLength(urlString: String) async -> Int {
        guard let url = URL(string: "\(baseURL)/manager/specimen-tiles/image?image_url=\(urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString)") else {
            return 0
        }

        // 1. HEAD
        var head = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 15)
        head.httpMethod = "HEAD"
        if let (_, response) = try? await URLSession.shared.data(for: head),
           let http = response as? HTTPURLResponse,
           (200..<300).contains(http.statusCode) {
            let len = http.expectedContentLength > 0
                ? Int(http.expectedContentLength)
                : (http.value(forHTTPHeaderField: "Content-Length")).flatMap(Int.init) ?? 0
            if len > 0 { return len }
        }

        // 2. Range GET(代理服务器常不支持 HEAD 或不回长度)
        var range = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 15)
        range.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        if let (_, response) = try? await URLSession.shared.data(for: range),
           let http = response as? HTTPURLResponse {
            if http.statusCode == 206,
               let contentRange = http.value(forHTTPHeaderField: "Content-Range") {
                // 形如 "bytes 0-0/389433"
                if let total = contentRange.split(separator: "/").last, let n = Int(total) {
                    return n
                }
            }
            if (200..<300).contains(http.statusCode) {
                return http.value(forHTTPHeaderField: "Content-Length").flatMap(Int.init) ?? 0
            }
        }
        return 0
    }

    /// 获取父图/大图。弱网(实验室)下会自动重试，最多 3 次，逐次退避。
    /// 每次请求都是全新的(不走缓存)，避免拿到弱网时缓存下来的损坏数据。
    func fetchTileImage(urlString: String) async throws -> UIImage {
        let maxAttempts = 3
        var lastError: Error = APIError.invalidImage

        for attempt in 1...maxAttempts {
            do {
                let data = try await fetchTileImageData(urlString: urlString)
                return UIImage(data: data)!
            } catch {
                lastError = error
                // 404 说明确实没有这张图，重试无意义
                if case APIError.serverError(let msg) = error, msg.contains("HTTP 404") {
                    throw error
                }
                print("⚠️ 第 \(attempt)/\(maxAttempts) 次加载图片失败: \(error.localizedDescription)")
                if attempt < maxAttempts {
                    // 退避等待后重试(0.5s → 1s)，给弱网一个恢复机会
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 500_000_000)
                }
            }
        }
        throw lastError
    }

    /// Fetch tile image and downscale to thumbnail size for faster loading
    func fetchTileThumbnail(urlString: String, maxSize: CGFloat = 88) async throws -> UIImage {
        let data = try await fetchTileImageData(urlString: urlString)
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

    // MARK: - Tile Products (瓦片产品: 显微镜模拟器数据源)

    /// 兼容两种响应风格: 直接返回数组, 或 { products: [...] } / { data: [...] } 包裹
    struct TileProductsEnvelope: Decodable {
        let products: [SpecimenTileProduct]

        init(from decoder: Decoder) throws {
            let single = try decoder.singleValueContainer()
            if let list = try? single.decode([SpecimenTileProduct].self) {
                products = list
                return
            }
            struct Inner: Decodable {
                let products: [SpecimenTileProduct]?
                let data: [SpecimenTileProduct]?
                let tileProducts: [SpecimenTileProduct]?
            }
            let obj = try single.decode(Inner.self)
            products = obj.products ?? obj.data ?? obj.tileProducts ?? []
        }
    }

    func fetchTileProducts(specimenId: Int, ratioId: Int, stackId: Int) async throws -> [SpecimenTileProduct] {
        let env: TileProductsEnvelope = try await request(
            "/manager/specimen-tile-products/list",
            queryParams: [
                "specimen_id": "\(specimenId)",
                "ratio_id": "\(ratioId)",
                "stack_id": "\(stackId)"
            ]
        )
        return env.products
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
