import Foundation
import CoreLocation

// MARK: - Mock 地图服务 (Simulator / Preview)

final class MockMapService: MapServiceProtocol {
    func searchPlaces(query: String, region: MapRegion, filters: [PlaceCategoryType]?) async throws -> [MapPlace] {
        // 模拟网络延迟
        try await Task.sleep(nanoseconds: 500_000_000)

        return [
            MapPlace(
                id: "mock_1",
                name: "\(query) - 搜索结果1",
                address: "模拟地址 123号",
                coordinate: CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074),
                poiID: "B000A1",
                category: "餐饮",
                phone: "010-12345678",
                coverImageURL: nil,
                rating: 4.3,
                distance: 350
            ),
            MapPlace(
                id: "mock_2",
                name: "\(query) - 搜索结果2",
                address: "模拟地址 456号",
                coordinate: CLLocationCoordinate2D(latitude: 39.9142, longitude: 116.4174),
                poiID: "B000A2",
                category: "咖啡",
                phone: nil,
                coverImageURL: nil,
                rating: 4.7,
                distance: 1200
            )
        ]
    }

    func reverseGeocode(coordinate: CLLocationCoordinate2D) async throws -> String {
        try await Task.sleep(nanoseconds: 200_000_000)
        return "模拟地址·北京市朝阳区"
    }

    func fetchPlaceDetail(poiID: String) async throws -> MapPlaceDetail {
        try await Task.sleep(nanoseconds: 300_000_000)
        return MapPlaceDetail(
            place: MapPlace(
                id: poiID,
                name: "模拟地点",
                address: "模拟地址",
                coordinate: CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4),
                poiID: poiID,
                category: "餐饮",
                phone: nil,
                coverImageURL: nil,
                rating: 4.5,
                distance: nil
            ),
            rating: 4.5,
            openingHours: "10:00-22:00",
            priceRange: "¥100-200",
            photos: [],
            description: "这是一个模拟的地点描述"
        )
    }

    func calculateRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> MapRoute {
        MapRoute(
            distance: 3500,
            duration: 1800,
            polyline: [from, to]
        )
    }

    func searchNearby(coordinate: CLLocationCoordinate2D, radius: Double, category: PlaceCategoryType?) async throws -> [MapPlace] {
        try await Task.sleep(nanoseconds: 400_000_000)
        return []
    }
}

// MARK: - Mock API Client (v1.0 空实现)

final class MockAPIClient: APIClientProtocol {
    func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T {
        throw APIError.unavailable
    }

    func upload(_ data: Data, to endpoint: APIEndpoint) async throws -> UploadResponse {
        throw APIError.unavailable
    }
}

// MARK: - 智能导入服务

final class SmartImportService: ImportCoordinatorProtocol {
    func detectImportPreview(from text: String) async -> ImportPreview? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        if let url = extractFirstURL(from: cleaned),
           let preview = await previewForKnownURL(url, rawText: cleaned) {
            return preview
        }

        guard looksLikeImportableText(cleaned) else { return nil }
        return previewForSharedText(cleaned)
    }

    func detectClipboardPreview(from text: String) async -> ImportPreview? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        if let url = extractFirstURL(from: cleaned),
           let preview = await previewForKnownURL(url, rawText: cleaned) {
            return preview
        }

        guard looksLikeClipboardCandidate(cleaned) else { return nil }
        return previewForSharedText(cleaned)
    }

    func extractCollectionPayload(from preview: ImportPreview) async -> ImportCollectionPayload? {
        guard preview.kind == .collection else { return nil }

        var collectedTitle = preview.title
        var collectedSummary = preview.subtitle
        var places: [ImportablePlace] = []

        func merge(_ candidates: [ImportablePlace]) {
            for candidate in candidates {
                let alreadyExists = places.contains {
                    $0.name.caseInsensitiveCompare(candidate.name) == .orderedSame &&
                    (($0.address ?? "").caseInsensitiveCompare(candidate.address ?? "") == .orderedSame)
                }
                if !alreadyExists {
                    places.append(candidate)
                }
            }
        }

        if let sourceURL = preview.sourceURL,
           let fetched = await fetchRemoteHTML(from: sourceURL) {
            let parsed = parseCollectionPlaces(from: fetched.html, sourceURL: fetched.url)
            if let parsedTitle = parsed.title, !parsedTitle.isEmpty {
                collectedTitle = parsedTitle
            }
            if let summary = parsed.summary, !summary.isEmpty {
                collectedSummary = summary
            }
            merge(parsed.items)
        }

        if places.isEmpty {
            let fallback = parseCollectionPlaces(from: preview.rawText, sourceURL: preview.sourceURL)
            if let parsedTitle = fallback.title, !parsedTitle.isEmpty {
                collectedTitle = parsedTitle
            }
            merge(fallback.items)
        }

        guard !places.isEmpty else { return nil }
        return ImportCollectionPayload(
            title: collectedTitle,
            sourceType: preview.sourceType,
            sourceURL: preview.sourceURL,
            items: places,
            summary: collectedSummary
        )
    }

    private func previewForKnownURL(_ url: URL, rawText: String) async -> ImportPreview? {
        let resolved = await resolveURLContext(for: url)
        let resolvedURL = resolved.url ?? url
        let host = (resolvedURL.host ?? "").lowercased()
        let lines = meaningfulLines(from: rawText.isEmpty ? (resolved.title ?? "") : rawText)

        if let amapFolder = amapFolderContext(from: resolvedURL) ?? amapFolderContext(fromRawText: rawText) {
            return ImportPreview(
                kind: .collection,
                sourceType: .amapFavorite,
                sourceURL: resolvedURL,
                rawText: rawText,
                title: "高德收藏夹",
                subtitle: "已识别到高德收藏夹分享，接下来可以把里面保存的地点批量带进步步。",
                suggestedQuery: "",
                searchQueries: [],
                candidateAddress: nil,
                coordinate: nil,
                collectionContext: amapFolder
            )
        }

        if host.contains("xiaohongshu.com") || host.contains("xhslink.com") {
            let resolvedTitle = resolved.title.flatMap(cleanImportedTitle)
            let resolvedDescription = resolved.description.flatMap(cleanImportedTitle)
            let title = firstUsefulTitle(from: lines)
                ?? resolvedTitle
                ?? resolvedDescription
                ?? "小红书分享链接"
            let address = firstAddressLine(from: lines)
                ?? firstAddressLine(from: [resolved.description ?? ""])
                ?? extractAddressLikeText(from: rawText)
                ?? extractAddressLikeText(from: resolved.description ?? "")
            return ImportPreview(
                kind: .singlePlace,
                sourceType: .redbook,
                sourceURL: resolvedURL,
                rawText: rawText,
                title: title,
                subtitle: address ?? (resolvedTitle == nil ? "已识别到小红书链接，但还没提到具体店名，建议补一行店名再解析" : "已识别到小红书链接，会尝试用标题为你匹配地点"),
                suggestedQuery: bestQuery(title: title, address: address),
                searchQueries: searchQueries(title: title, address: address, rawText: rawText),
                candidateAddress: address,
                coordinate: nil
                ,
                collectionContext: nil
            )
        }

        if host.contains("amap.com") {
            let amapContent = parseAmapSharedContent(rawText)
            let title = amapContent.title
                ?? firstUsefulTitle(from: lines)
                ?? queryValue("poiname", from: resolvedURL)
                ?? queryValue("name", from: resolvedURL)
                ?? resolved.title.flatMap(cleanImportedTitle)
                ?? "来自高德的地点"
            let address = amapContent.address
                ?? firstAddressLine(from: lines)
                ?? extractAddressLikeText(from: rawText)
                ?? queryValue("address", from: resolvedURL)
                ?? extractAddressLikeText(from: resolved.description ?? "")
            let subtitle = amapContent.subtitle ?? amapSubtitle(from: lines, address: address)
            return ImportPreview(
                kind: .singlePlace,
                sourceType: .amapFavorite,
                sourceURL: resolvedURL,
                rawText: rawText,
                title: title,
                subtitle: subtitle ?? "已识别到高德分享链接",
                suggestedQuery: bestQuery(title: title, address: address),
                searchQueries: searchQueries(title: title, address: address, rawText: rawText),
                candidateAddress: address,
                coordinate: coordinate(from: resolvedURL),
                collectionContext: nil
            )
        }

        return nil
    }

    private func previewForSharedText(_ text: String) -> ImportPreview? {
        let lines = meaningfulLines(from: text)
        guard !lines.isEmpty else { return nil }

        let title = inferredPlaceTitle(from: text, lines: lines) ?? firstUsefulTitle(from: lines) ?? lines[0]
        let address = firstAddressLine(from: lines) ?? extractAddressLikeText(from: text)

        return ImportPreview(
            kind: .singlePlace,
            sourceType: .manual,
            sourceURL: nil,
            rawText: text,
            title: title,
            subtitle: address ?? "将根据这段文本为你匹配地点",
            suggestedQuery: bestQuery(title: title, address: address),
            searchQueries: searchQueries(title: title, address: address, rawText: text),
            candidateAddress: address,
            coordinate: nil,
            collectionContext: nil
        )
    }

    private func extractFirstURL(from text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(location: 0, length: text.utf16.count)
        return detector?.firstMatch(in: text, options: [], range: range)?.url
    }

    private func meaningfulLines(from text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter {
                !$0.isEmpty &&
                !$0.hasPrefix("http") &&
                !$0.contains("复制") &&
                !$0.contains("打开小红书") &&
                !$0.contains("一起标记") &&
                !$0.contains("分享")
            }
    }

    private func looksLikeImportableText(_ text: String) -> Bool {
        if text.count < 2 || text.count > 220 { return false }
        if looksLikeCodeOrLogs(text) { return false }

        let lines = text.components(separatedBy: .newlines)
        if lines.count > 8 { return false }

        let codeLikeCharacters = text.filter { "{}[]<>;=\\".contains($0) }.count
        if codeLikeCharacters > max(8, text.count / 8) { return false }

        let locationHints = ["路", "街", "号", "广场", "商场", "园区", "大厦", "层", "酒店", "咖啡", "餐厅", "公园", "博物馆", "展览", "书店", "酒吧", "店"]
        return locationHints.contains(where: { text.contains($0) })
    }

    private func looksLikeClipboardCandidate(_ text: String) -> Bool {
        if text.count < 2 || text.count > 160 { return false }
        if looksLikeCodeOrLogs(text) { return false }

        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if lines.count > 5 { return false }

        let locationTokens = ["路", "街", "号", "广场", "商场", "园区", "大厦", "酒店", "公园", "博物馆", "书店"]
        let venueTokens = ["咖啡", "餐厅", "料理", "寿司", "烧肉", "火锅", "酒吧", "小馆", "饭店", "食堂", "拉面", "面馆", "面包", "甜品", "茶室", "茶馆", "民宿", "展览", "买手店", "店"]
        let hasLocation = locationTokens.contains(where: { text.contains($0) })
        let hasVenue = venueTokens.contains(where: { text.contains($0) })
        let likelyAddressPattern = text.contains("市") || text.contains("区") || text.contains("镇")
        let singleVenueLine = lines.count == 1 && lines[0].count <= 24 && hasVenue
        let inferredVenue = inferredPlaceTitle(from: text, lines: lines)

        return (hasLocation && hasVenue) || (hasLocation && likelyAddressPattern) || singleVenueLine || inferredVenue != nil
    }

    private func looksLikeCodeOrLogs(_ text: String) -> Bool {
        let blockedTokens = [
            "0x", "symbol stub", "<+", "Exception", "BUILD FAILED", "error:",
            "func ", "struct ", "class ", "import ", "Thread ", "fatal error",
            "xcodebuild", "SIGABRT", "assertion failed", "Undefined symbol"
        ]
        if blockedTokens.contains(where: { text.localizedCaseInsensitiveContains($0) }) {
            return true
        }

        let longSymbolRuns = text.split(separator: "\n").contains { line in
            let symbols = line.filter { "{}[]<>;=:_()".contains($0) }.count
            return line.count > 24 && symbols > max(6, line.count / 5)
        }
        return longSymbolRuns
    }

    private func firstUsefulTitle(from lines: [String]) -> String? {
        lines.first(where: {
            $0.count >= 2 &&
            $0.count <= 40 &&
            !$0.contains("¥") &&
            !$0.contains("/人") &&
            !$0.contains("步行")
        })
    }

    private func firstAddressLine(from lines: [String]) -> String? {
        lines.first(where: {
            $0.contains("路") || $0.contains("街") || $0.contains("号") ||
            $0.contains("广场") || $0.contains("商场") || $0.contains("区") ||
            $0.contains("厦") || $0.contains("层") || $0.contains("弄")
        })
    }

    private func bestQuery(title: String, address: String?) -> String {
        if title == "来自小红书的种草" || title == "小红书分享链接" {
            return address ?? title
        }
        if let address, !address.isEmpty, title != address {
            return "\(title) \(address)"
        }
        return title
    }

    private func amapSubtitle(from lines: [String], address: String?) -> String? {
        let categoryLine = lines.first(where: { $0.contains("¥") || $0.contains("/人") })
        if let categoryLine, let address {
            return "\(categoryLine)\n\(address)"
        }
        return address ?? categoryLine
    }

    private func parseAmapSharedContent(_ text: String) -> (title: String?, subtitle: String?, address: String?) {
        let urlStripped = text.replacingOccurrences(of: "https?://\\S+", with: "", options: .regularExpression)
        let normalized = sanitizeSearchKeyword(urlStripped)
        guard !normalized.isEmpty else { return (nil, nil, nil) }

        let rawLines = normalized
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if rawLines.count >= 2 {
            let title = rawLines.first
            let address = rawLines.first(where: { looksLikeAddressLine($0) && $0 != title })
            let categoryLine = rawLines.first(where: { $0.contains("¥") || $0.contains("/人") })
            let subtitle = categoryLine.map { line in
                if let address { return "\(line)\n\(address)" }
                return line
            } ?? address
            return (title, subtitle, address)
        }

        let compact = normalized.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let categoryRange = compact.range(of: "¥\\s*\\d+\\s*/人[^\\s]*", options: .regularExpression)
        let addressMatch = firstMatch(in: compact, pattern: "([\\p{Han}A-Za-z0-9\\-]{2,40}(?:路|街|大道|巷|号|弄|广场|商场|园区|大厦|中心)[^\\n]{0,40})")

        var title: String?
        if let categoryRange {
            let prefix = compact[..<categoryRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            title = prefix.isEmpty ? nil : prefix
        } else if let addressMatch, let range = compact.range(of: addressMatch) {
            let prefix = compact[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            title = prefix.isEmpty ? nil : prefix
        } else {
            title = compact
        }

        let categoryLine = categoryRange.map { String(compact[$0]).trimmingCharacters(in: .whitespacesAndNewlines) }
        let subtitle = categoryLine.map { line in
            if let addressMatch { return "\(line)\n\(addressMatch)" }
            return line
        } ?? addressMatch

        return (title.flatMap(cleanImportedTitle), subtitle, addressMatch)
    }

    private func looksLikeAddressLine(_ line: String) -> Bool {
        line.contains("路") ||
        line.contains("街") ||
        line.contains("号") ||
        line.contains("弄") ||
        line.contains("大道") ||
        line.contains("广场") ||
        line.contains("商场") ||
        line.contains("园区") ||
        line.contains("大厦") ||
        line.contains("中心")
    }

    private func searchQueries(title: String, address: String?, rawText: String) -> [String] {
        var candidates: [String] = []

        func append(_ value: String?) {
            guard let value else { return }
            let cleaned = sanitizeSearchKeyword(value)
            guard cleaned.count >= 2 else { return }
            guard !candidates.contains(cleaned) else { return }
            candidates.append(cleaned)
        }

        append(bestQuery(title: title, address: address))
        append(title)
        append(address)

        for fragment in titleFragments(from: title) {
            append(fragment)
        }
        for fragment in titleFragments(from: rawText) {
            append(fragment)
        }

        return Array(candidates.prefix(6))
    }

    private func sanitizeSearchKeyword(_ value: String) -> String {
        value
            .replacingOccurrences(of: "#", with: " ")
            .replacingOccurrences(of: "📍", with: " ")
            .replacingOccurrences(of: "｜", with: " ")
            .replacingOccurrences(of: "|", with: " ")
            .replacingOccurrences(of: "·", with: " ")
            .replacingOccurrences(of: "「", with: " ")
            .replacingOccurrences(of: "」", with: " ")
            .replacingOccurrences(of: "【", with: " ")
            .replacingOccurrences(of: "】", with: " ")
            .replacingOccurrences(of: "(", with: " ")
            .replacingOccurrences(of: ")", with: " ")
            .replacingOccurrences(of: "（", with: " ")
            .replacingOccurrences(of: "）", with: " ")
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func titleFragments(from value: String) -> [String] {
        let separators = CharacterSet(charactersIn: "|｜/、,，。；;：:")
        let rawParts = value
            .components(separatedBy: separators)
            .map { sanitizeSearchKeyword($0) }
            .filter { $0.count >= 2 && $0.count <= 24 }

        let usefulParts = rawParts.filter { fragment in
            let blocked = ["攻略", "分享", "收藏", "打卡", "推荐", "vlog", "plog", "旅行", "日常", "周末", "好去处", "合集"]
            return !blocked.contains(where: { fragment.localizedCaseInsensitiveContains($0) })
        }

        return usefulParts
    }

    private func queryValue(_ key: String, from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name.lowercased() == key.lowercased() })?
            .value?
            .removingPercentEncoding
    }

    private func amapFolderContext(from url: URL) -> ImportCollectionContext? {
        let schema = queryValue("schema", from: url) ?? url.absoluteString
        return amapFolderContext(fromSchemaString: schema)
    }

    private func amapFolderContext(fromRawText text: String) -> ImportCollectionContext? {
        guard let link = extractFirstURL(from: text) else { return nil }
        return amapFolderContext(from: link)
    }

    private func amapFolderContext(fromSchemaString schemaString: String) -> ImportCollectionContext? {
        guard schemaString.contains("ajx_favorites/folder") else { return nil }

        let decoded = schemaString.removingPercentEncoding ?? schemaString
        guard let dataMatch = firstMatch(in: decoded, pattern: "data=\\{([^\\}]*)\\}") else { return nil }
        let jsonLike = "{\(dataMatch)}"
        guard let data = jsonLike.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ugcId = object["ugcId"] as? String else { return nil }

        return ImportCollectionContext(
            provider: .amapFavorite,
            collectionID: ugcId,
            pathID: object["pathID"] as? Int ?? object["pathId"] as? Int,
            isCreatorShare: object["isCreatorShare"] as? Bool ?? false
        )
    }

    private func fetchRemoteHTML(from url: URL) async -> (url: URL, html: String)? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            request.setValue("zh-CN,zh-Hans;q=0.9,en;q=0.7", forHTTPHeaderField: "Accept-Language")

            let (data, response) = try await URLSession.shared.data(for: request)
            let finalURL = response.url ?? url
            let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            return (finalURL, html)
        } catch {
            return nil
        }
    }

    private func parseCollectionPlaces(from raw: String, sourceURL: URL?) -> (title: String?, summary: String?, items: [ImportablePlace]) {
        let decoded = decodeEscapes(in: raw)
        let title = extractCollectionTitle(from: decoded)
        let summary = extractCollectionSummary(from: decoded)

        var items: [ImportablePlace] = []
        var seen = Set<String>()

        func append(name: String?, address: String?, coordinate: CLLocationCoordinate2D? = nil) {
            guard let name else { return }
            let cleanedName = sanitizeImportedPlaceName(name)
            guard cleanedName.count >= 2 else { return }
            let cleanedAddress = address?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "。！，,;；:："))
            let key = "\(cleanedName.lowercased())|\((cleanedAddress ?? "").lowercased())"
            guard !seen.contains(key) else { return }
            seen.insert(key)
            items.append(
                ImportablePlace(
                    name: cleanedName,
                    address: cleanedAddress,
                    coordinate: coordinate,
                    category: nil,
                    imageURL: nil,
                    sourceURL: sourceURL,
                    sourceType: .amapFavorite,
                    note: nil
                )
            )
        }

        let nameThenAddressPattern = "\"(?:poiName|name|title|storeName|shopName)\"\\s*:\\s*\"([^\"]{2,60})\"[\\s\\S]{0,220}?\"(?:address|addr|snippet|displayAddress)\"\\s*:\\s*\"([^\"]{2,140})\""
        for groups in allMatches(in: decoded, pattern: nameThenAddressPattern) where groups.count >= 2 {
            append(name: groups[0], address: groups[1])
        }

        let addressThenNamePattern = "\"(?:address|addr|snippet|displayAddress)\"\\s*:\\s*\"([^\"]{2,140})\"[\\s\\S]{0,220}?\"(?:poiName|name|title|storeName|shopName)\"\\s*:\\s*\"([^\"]{2,60})\""
        for groups in allMatches(in: decoded, pattern: addressThenNamePattern) where groups.count >= 2 {
            append(name: groups[1], address: groups[0])
        }

        if items.isEmpty {
            let lines = meaningfulLines(from: decoded)
            for index in lines.indices {
                let line = lines[index]
                let name = inferredPlaceTitle(from: line, lines: [line]) ?? sanitizeImportedPlaceName(line)
                guard looksLikeVenueName(name) else { continue }

                let nextLine = lines.indices.contains(index + 1) ? lines[index + 1] : nil
                let address = firstAddressLine(from: [line, nextLine].compactMap { $0 }) ?? nextLine.flatMap(extractAddressLikeText)
                append(name: name, address: address)
            }
        }

        return (title, summary, items)
    }

    private func coordinate(from url: URL) -> CLLocationCoordinate2D? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let lng = components?.queryItems?.first(where: { ["lon", "longitude", "lng"].contains($0.name.lowercased()) })?.value
        let lat = components?.queryItems?.first(where: { ["lat", "latitude"].contains($0.name.lowercased()) })?.value

        if let lng, let lat, let longitude = Double(lng), let latitude = Double(lat) {
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }

        if let locations = components?.queryItems?.first(where: { ["location", "locations", "coordinate"].contains($0.name.lowercased()) })?.value {
            let parts = locations.split(separator: ",")
            if parts.count == 2,
               let longitude = Double(parts[0]),
               let latitude = Double(parts[1]) {
                return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            }
        }

        return nil
    }

    private func resolveURLContext(for url: URL) async -> (url: URL?, title: String?, description: String?) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return (url, nil, nil)
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            request.setValue("zh-CN,zh-Hans;q=0.9,en;q=0.7", forHTTPHeaderField: "Accept-Language")

            let (data, response) = try await URLSession.shared.data(for: request)
            let finalURL = response.url ?? url
            let html = String(data: data, encoding: .utf8) ?? ""
            let extractedDescription = extractMetaContent(named: "description", from: html)
                ?? extractMetaContent(named: "og:description", from: html)
                ?? extractMetaContent(named: "twitter:description", from: html)
                ?? extractJSONField(in: html, keys: ["address", "poiName", "poi", "location", "storeName", "shopName"])
            let extractedAddress = extractAddressLikeText(from: html)
            return (
                finalURL,
                cleanedResolvedTitle(from: html),
                extractedAddress.map { address in
                    if let extractedDescription, !extractedDescription.localizedCaseInsensitiveContains(address) {
                        return "\(extractedDescription)\n\(address)"
                    }
                    return address
                } ?? extractedDescription
            )
        } catch {
            return (url, nil, nil)
        }
    }

    private func cleanedResolvedTitle(from html: String) -> String? {
        let rawTitle = extractMetaContent(named: "og:title", from: html)
            ?? extractMetaContent(named: "twitter:title", from: html)
            ?? firstMatch(in: html, pattern: "\"noteTitle\"\\s*:\\s*\"([^\"]+)\"")
            ?? firstMatch(in: html, pattern: "\"title\"\\s*:\\s*\"([^\"]{2,80})\"")
            ?? firstMatch(in: html, pattern: "\"desc\"\\s*:\\s*\"([^\"]{2,120})\"")
            ?? extractJSONField(in: html, keys: ["noteTitle", "poiName", "storeName", "shopName"])
            ?? extractHTMLTitle(from: html)

        return rawTitle.flatMap(cleanImportedTitle)
    }

    private func cleanImportedTitle(_ rawTitle: String) -> String? {
        let cleaned = rawTitle
            .replacingOccurrences(of: "\\u002F", with: "/")
            .replacingOccurrences(of: "\\u003C", with: "<")
            .replacingOccurrences(of: "\\u003E", with: ">")
            .replacingOccurrences(of: "\\u0026", with: "&")
            .replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "_小红书", with: "")
            .replacingOccurrences(of: "- 小红书", with: "")
            .replacingOccurrences(of: " | 小红书", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let genericTitles = [
            "小红书",
            "小红书 - 你的生活指南",
            "发现精彩，分享生活",
            "xhslink",
            "小红书分享链接"
        ]

        guard !genericTitles.contains(where: { cleaned.caseInsensitiveCompare($0) == .orderedSame }) else {
            return nil
        }
        guard cleaned.count >= 2 else { return nil }
        return cleaned
    }

    private func extractAddressLikeText(from text: String) -> String? {
        let cleaned = sanitizeSearchKeyword(text)
        guard cleaned.count >= 4 else { return nil }

        let patterns = [
            "([\\p{Han}A-Za-z0-9]{2,30}(?:省|市|区|县|镇)[\\p{Han}A-Za-z0-9]{0,40}(?:路|街|大道|巷|号|弄|广场|商场|园区|大厦|中心|层)[\\p{Han}A-Za-z0-9\\-]{0,20})",
            "([\\p{Han}A-Za-z0-9]{2,30}(?:路|街|大道|巷|号|弄)[\\p{Han}A-Za-z0-9\\-]{0,20})",
            "([\\p{Han}A-Za-z0-9]{2,30}(?:广场|商场|园区|大厦|中心|公园|博物馆|书店|酒店|民宿)[\\p{Han}A-Za-z0-9\\-]{0,20})"
        ]

        for pattern in patterns {
            if let match = firstMatch(in: cleaned, pattern: pattern) {
                return match
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "。！，,;；:："))
            }
        }
        return nil
    }

    private func inferredPlaceTitle(from text: String, lines: [String]) -> String? {
        let venueTokens = ["咖啡", "餐厅", "料理", "寿司", "烧肉", "火锅", "酒吧", "小馆", "饭店", "食堂", "拉面", "面馆", "面包", "甜品", "茶室", "茶馆", "民宿", "展览", "买手店", "书店", "馆", "店", "庄"]
        let stopPhrases = ["我永远的爱人", "我永远的爱", "我的爱", "太好吃了", "太绝了", "狠狠爱住", "狠狠爱上", "强烈推荐", "真的很好吃", "救命", "啊啊啊"]

        func cleanCandidate(_ value: String) -> String {
            sanitizeSearchKeyword(value)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "。！，,;；:：!?？！~～"))
        }

        func score(_ value: String) -> Int {
            guard value.count >= 2 && value.count <= 24 else { return Int.min }
            if value.contains("¥") || value.contains("/人") || looksLikeAddressLine(value) { return Int.min }

            var score = 0
            if venueTokens.contains(where: { value.contains($0) }) { score += 4 }
            if value.rangeOfCharacter(from: .decimalDigits) == nil { score += 1 }
            if value.count <= 12 { score += 1 }
            if stopPhrases.contains(where: { value.contains($0) }) { score -= 5 }
            if value.contains("推荐") || value.contains("收藏") || value.contains("打卡") || value.contains("分享") { score -= 3 }
            return score
        }

        var candidates: [String] = []
        candidates.append(contentsOf: lines)

        let punctuationSeparated = text.components(separatedBy: CharacterSet(charactersIn: "\n!！?？。；;，,:：~～|｜"))
        candidates.append(contentsOf: punctuationSeparated)

        return candidates
            .map(cleanCandidate)
            .filter { !$0.isEmpty }
            .sorted { score($0) > score($1) }
            .first(where: { score($0) > 0 })
    }

    private func looksLikeVenueName(_ value: String) -> Bool {
        let venueTokens = ["咖啡", "餐厅", "料理", "寿司", "烧肉", "火锅", "酒吧", "小馆", "饭店", "食堂", "拉面", "面馆", "面包", "甜品", "茶室", "茶馆", "民宿", "展览", "买手店", "书店", "馆", "店", "庄"]
        return value.count >= 2 && value.count <= 28 && venueTokens.contains(where: { value.contains($0) })
    }

    private func sanitizeImportedPlaceName(_ raw: String) -> String {
        sanitizeSearchKeyword(raw)
            .replacingOccurrences(of: "¥\\s*\\d+\\s*/人[^\\s]*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\b\\d+人收藏\\b", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "。！，,;；:：!?？！~～"))
    }

    private func extractCollectionTitle(from text: String) -> String? {
        let candidates = [
            extractJSONField(in: text, keys: ["folderName", "favName", "name", "title"]),
            firstMatch(in: text, pattern: "\"collectionName\"\\s*:\\s*\"([^\"]{2,80})\""),
            firstMatch(in: text, pattern: "\"folder_title\"\\s*:\\s*\"([^\"]{2,80})\"")
        ]

        return candidates
            .compactMap { $0 }
            .map { sanitizeImportedPlaceName($0) }
            .first(where: { $0.count >= 2 && !$0.localizedCaseInsensitiveContains("高德收藏夹") })
    }

    private func extractCollectionSummary(from text: String) -> String? {
        extractMetaContent(named: "description", from: text)
            ?? extractMetaContent(named: "og:description", from: text)
            ?? firstMatch(in: text, pattern: "\"description\"\\s*:\\s*\"([^\"]{2,160})\"")
    }

    private func decodeEscapes(in text: String) -> String {
        text
            .replacingOccurrences(of: "\\u002F", with: "/")
            .replacingOccurrences(of: "\\u003A", with: ":")
            .replacingOccurrences(of: "\\u003D", with: "=")
            .replacingOccurrences(of: "\\u0026", with: "&")
            .replacingOccurrences(of: "\\\\/", with: "/")
            .replacingOccurrences(of: "\\n", with: "\n")
    }

    private func extractJSONField(in text: String, keys: [String]) -> String? {
        for key in keys {
            let escapedKey = NSRegularExpression.escapedPattern(for: key)
            let patterns = [
                "\"\(escapedKey)\"\\s*:\\s*\"([^\"]{2,120})\"",
                "\"\(escapedKey)\"\\s*:\\s*\\{[^\\}]*\"name\"\\s*:\\s*\"([^\"]{2,120})\""
            ]

            for pattern in patterns {
                if let match = firstMatch(in: text, pattern: pattern) {
                    let cleaned = cleanImportedTitle(match) ?? sanitizeSearchKeyword(match)
                    if cleaned.count >= 2 {
                        return cleaned
                    }
                }
            }
        }
        return nil
    }

    private func extractHTMLTitle(from html: String) -> String? {
        guard let raw = firstMatch(in: html, pattern: "<title[^>]*>(.*?)</title>") else { return nil }
        return raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractMetaContent(named name: String, from html: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let patterns = [
            "<meta[^>]+(?:property|name)=[\"']\(escapedName)[\"'][^>]+content=[\"']([^\"']+)[\"']",
            "<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+(?:property|name)=[\"']\(escapedName)[\"']"
        ]

        for pattern in patterns {
            if let raw = firstMatch(in: html, pattern: pattern) {
                return raw.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let resultRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[resultRange])
    }

    private func allMatches(in text: String, pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: range).map { match in
            (1..<match.numberOfRanges).compactMap { index in
                guard let range = Range(match.range(at: index), in: text) else { return nil }
                return String(text[range])
            }
        }
    }
}
