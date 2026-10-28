import CryptoKit
import Foundation
import Security
import UIKit

typealias JSONObject = [String: Any]

enum SodaError: LocalizedError {
    case message(String)
    case apiCode(Int)
    case protectedAudio
    case sessionExpired

    var errorDescription: String? {
        switch self {
        case let .message(text): return text
        case let .apiCode(code): return "汽水服务拒绝了请求（\(code)）"
        case .protectedAudio: return "汽水接口仅提供加密音源，此版本暂不支持在应用内播放。可在官方汽水音乐中继续收听。"
        case .sessionExpired: return "汽水登录凭证已失效，请重新用抖音扫码登录。"
        }
    }
}

struct Track: Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    let artwork: URL?

    static func == (lhs: Track, rhs: Track) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    init?(_ raw: JSONObject) {
        let track = raw.object("track_entity") ?? raw.object("entity")?.object("media")?.object("track_entity")
            ?? raw.object("track") ?? raw
        let base = track.object("base_info") ?? track
        let display = track.object("display_info") ?? [:]
        guard let id = base.text("id") ?? track.text("id"), !id.isEmpty else { return nil }
        self.id = id
        self.title = base.text("name") ?? base.text("title") ?? display.text("name") ?? "未知歌曲"
        let related = track.object("related_info") ?? [:]
        let artists = related.array("artist_links") ?? related.array("artists")
            ?? related.array("artist_list") ?? []
        self.artist = artists.compactMap { ($0 as? JSONObject)?.text("name") }.joined(separator: "、")
            .nonEmpty ?? related.text("artist_name") ?? "未知艺人"
        let cover = related.text("cover_url")
            ?? (related.object("cover_url")?.array("urls")?.first as? String)
            ?? display.text("cover_url")
            ?? (related.object("album")?.text("cover_url")) ?? base.text("cover_url")
        self.artwork = cover.flatMap(URL.init(string:))
    }
}

struct Playlist: Identifiable {
    let id: String
    let title: String
    let artwork: URL?
    let ownerId: String
    let type: Int

    init?(_ raw: JSONObject) {
        let item = raw.object("playlist") ?? raw
        let base = item.object("base_info") ?? item
        guard let id = base.text("id"), !id.isEmpty else { return nil }
        self.id = id
        title = base.text("name") ?? base.text("title") ?? "未命名歌单"
        artwork = (base.text("cover_url") ?? item.text("cover_url")).flatMap(URL.init(string:))
        ownerId = base.text("owner_id") ?? ""
        type = Int(base.text("type") ?? "0") ?? 0
    }
}

struct Account: Codable {
    var deviceId: String
    var userId: String
    var nickname: String
    var avatarURL: String?
    var isVIP: Bool
    var ticket: String
    var guardKey: String
    var guardCert: String
    var guardTsSign: String
    var accessCode: String
    var openId: String
    var expiresAt: TimeInterval
}

struct LoginCode {
    let token: String
    let image: UIImage
    let expiresAt: Date
}

enum LoginStatus {
    case waiting, scanned, confirmed(Account), expired, refused
}

private extension Dictionary where Key == String, Value == Any {
    func object(_ key: String) -> JSONObject? { self[key] as? JSONObject }
    func array(_ key: String) -> [Any]? { self[key] as? [Any] }
    func text(_ key: String) -> String? {
        if let value = self[key] as? String { return value }
        if let value = self[key] as? NSNumber { return value.stringValue }
        return nil
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

private enum KeyStore {
    static func read() -> Account? {
        let query: JSONObject = [kSecClass as String: kSecClassGenericPassword,
                                 kSecAttrService as String: "SodaNativeAccount",
                                 kSecReturnData as String: true,
                                 kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Account.self, from: data)
    }

    static func save(_ account: Account?) {
        let query: JSONObject = [kSecClass as String: kSecClassGenericPassword,
                                 kSecAttrService as String: "SodaNativeAccount"]
        SecItemDelete(query as CFDictionary)
        guard let account, let data = try? JSONEncoder().encode(account) else { return }
        var values = query
        values[kSecValueData as String] = data
        values[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(values as CFDictionary, nil)
    }
}

@MainActor
final class QishuiService {
    static let shared = QishuiService()
    private let prefix = "/api/luna/v1/platform"
    private let clientKey = "aw4bbxfujo741d09"
    private let session = URLSession.shared
    private(set) var account = KeyStore.read()
    private var publicToken: String?

    private(set) var deviceId: String = {
        if let saved = UserDefaults.standard.string(forKey: "qishuiDeviceId"), saved.count == 19 {
            return saved
        }
        let value = String(Int64.random(in: 1_000_000_000_000_000_000...9_000_000_000_000_000_000))
        UserDefaults.standard.set(value, forKey: "qishuiDeviceId")
        return value
    }()

    private var common: JSONObject {
        let requestDeviceId = account?.deviceId ?? deviceId
        return ["aid": "765213", "app_id": "765213", "app_name": "byte_autoservice_lite",
         "version_code": "100010", "version_name": "1.0.10", "channel": "bydSong",
         "sdk_aid": "753999", "caller_name": "luna_open_sdk", "sdk_version_code": "100000100",
         "sdk_version_name": "0.0.1", "sdk_channel": "Test", "vehicle_type": "BYD",
         "device_brand": "BYD", "device_type": "BYD", "device_platform": "android",
         "resolution": "1920x1080", "os_version": "13", "ac": "wifi",
         "device_id": requestDeviceId, "did": requestDeviceId, "iid": requestDeviceId,
         "vehicle_id": "qishui-\(requestDeviceId)", "_timestamp": String(Int(Date().timeIntervalSince1970)),
         "_nonce": String(Int.random(in: 0...65535))]
    }

    private func url(_ base: String, _ parameters: JSONObject = [:]) throws -> URL {
        guard var components = URLComponents(string: base) else { throw SodaError.message("无效的请求地址") }
        components.queryItems = common.merging(parameters) { _, new in new }
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: String(describing: $0.value)) }
        guard let result = components.url else { throw SodaError.message("无法生成请求地址") }
        return result
    }

    private func plainURL(_ base: String, _ parameters: JSONObject = [:]) throws -> URL {
        guard var components = URLComponents(string: base) else { throw SodaError.message("无效的请求地址") }
        components.queryItems = parameters.sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: String(describing: $0.value)) }
        guard let result = components.url else { throw SodaError.message("无法生成请求地址") }
        return result
    }

    private func send(_ url: URL, body: JSONObject? = nil, form: Bool = false,
                      headers: [String: String] = [:]) async throws -> (JSONObject, HTTPURLResponse) {
        try Task.checkCancellation()
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("LunaOpenSDK/1.0.10", forHTTPHeaderField: "User-Agent")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        if let body {
            request.httpMethod = "POST"
            if form {
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                var components = URLComponents()
                components.queryItems = body.map { URLQueryItem(name: $0.key, value: String(describing: $0.value)) }
                request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
            } else {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            }
        }
        let (bytes, rawResponse) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = rawResponse as? HTTPURLResponse else { throw SodaError.message("服务没有返回 HTTP 响应") }
        guard (200..<300).contains(response.statusCode) else {
            throw SodaError.message("汽水服务返回 HTTP \(response.statusCode)")
        }
        guard let json = try JSONSerialization.jsonObject(with: bytes) as? JSONObject else {
            throw SodaError.message("汽水服务返回了无法识别的数据")
        }
        let error = (json["err_no"] as? Int)
            ?? (json["err_no"] as? String).flatMap(Int.init)
            ?? (json.object("data")?["error_code"] as? Int)
            ?? (json.object("data")?["error_code"] as? String).flatMap(Int.init)
            ?? 0
        guard error == 0 else { throw SodaError.apiCode(error) }
        return (json, response)
    }

    private func token() async throws -> String {
        if let publicToken { return publicToken }
        let address = try url("https://open.qishui.com\(prefix)/client/token/get/",
                              ["trigger_type": "cold_start"])
        let (data, _) = try await send(address)
        guard let value = data.text("client_token"), !value.isEmpty else {
            throw SodaError.message("无法取得汽水客户端令牌")
        }
        publicToken = value
        return value
    }

    private func platform(_ path: String, body: JSONObject = [:], signed: Bool = false) async throws -> JSONObject {
        if signed, path != "/me/info/" { try await refreshAccountStatus() }
        let address = try url("https://open.douyin.com\(prefix)\(path)")
        var payload = body
        payload["common_params"] = account.map { ["user_id": $0.userId] } ?? [:]
        var headers: [String: String]
        if signed {
            guard let account else { throw SodaError.message("请先用抖音扫码登录") }
            headers = try guardHeaders(account, path)
        } else {
            headers = ["access-token": try await token()]
        }
        do {
            let (response, _) = try await send(address, body: payload, headers: headers)
            guard let data = response.object("data") else { throw SodaError.message("汽水返回内容为空") }
            return data
        } catch let error as SodaError {
            if signed, case .apiCode(let code) = error,
               [28001003, 28001007, 28001008, 10007].contains(code) {
                logout()
                throw SodaError.sessionExpired
            }
            if !signed, case .apiCode(28001008) = error {
                publicToken = nil
                headers = ["access-token": try await token()]
                let (response, _) = try await send(address, body: payload, headers: headers)
                guard let data = response.object("data") else { throw SodaError.message("汽水返回内容为空") }
                return data
            }
            throw error
        } catch {
            if !signed, error.localizedDescription.contains("28001008") {
                publicToken = nil
                headers = ["access-token": try await token()]
                let (response, _) = try await send(address, body: payload, headers: headers)
                guard let data = response.object("data") else { throw SodaError.message("汽水返回内容为空") }
                return data
            }
            throw error
        }
    }

    private func refreshAccountStatus() async throws {
        guard let saved = account else { throw SodaError.message("请先用抖音扫码登录") }
        do {
            try await renewAccountIfNeeded()
            guard let current = account else { throw SodaError.sessionExpired }
            let address = try url("https://open.douyin.com\(prefix)/me/info/")
            let payload: JSONObject = ["common_params": ["user_id": current.userId]]
            let (response, _) = try await send(address, body: payload,
                                               headers: guardHeaders(current, "/me/info/"))
            guard let data = response.object("data"),
                  let user = data.object("my_info"),
                  let userId = user.text("id"), !userId.isEmpty else {
                throw SodaError.message("无法验证汽水账号")
            }
            guard userId == saved.userId else {
                logout()
                throw SodaError.sessionExpired
            }
        } catch let error as SodaError {
            if case .apiCode(let code) = error,
               [28001003, 28001007, 28001008, 10007].contains(code) {
                logout()
                throw SodaError.sessionExpired
            }
            throw error
        }
    }

    func search(_ query: String) async throws -> [Track] {
        let searchId = UUID().uuidString
        let data = try await platform("/search/", body: [
            "q": query, "cursor": "0", "search_id": searchId,
            "from_search_id": searchId, "search_method": "input", "search_type": "track",
            "search_scene": "normal", "scene_name": "search", "ab_param": "",
            "last_viewed_media": [:] as JSONObject])
        let groups = data.array("result_groups")?.compactMap { $0 as? JSONObject } ?? []
        let group = groups.first { $0.text("id") == "tracks" } ?? groups.first
        let rows = group?.array("data") ?? []
        return rows.compactMap { value in
            guard let item = value as? JSONObject else { return nil }
            return Track(item.object("entity")?.object("track") ?? item)
        }
    }

    func audio(for track: Track) async throws -> (URL, Bool) {
        var sawProtectedAudio = false
        let data = try await platform("/media/mget/", body: [
            "media_list": [["id": track.id, "type": "track"]], "card_context": [:] as JSONObject],
            signed: account != nil)
        let list = data.array("media_list")?.compactMap { $0 as? JSONObject } ?? []
        guard let found = list.first(where: { $0.text("media_id") == track.id }) ?? list.first,
              let detail = found.object("track_entity"),
              let player = detail.object("player_info") else {
            throw SodaError.message("没有找到这首歌的播放信息")
        }
        for variant in ["full", "preview"] {
            guard let info = player.object(variant)?.object("video_model_info") else { continue }
            var model = info.object("video_model")
            if model == nil, let raw = info.text("video_model"), let bytes = raw.data(using: .utf8) {
                model = try? JSONSerialization.jsonObject(with: bytes) as? JSONObject
            }
            let sources = model?.array("video_list")?.compactMap { $0 as? JSONObject } ?? []
            for item in sources {
                if RequestPolicy.isProtectedAudio(item) {
                    sawProtectedAudio = true
                    continue
                }
                if let raw = item.text("main_url"), let source = trustedMediaURL(raw) {
                    return (source, variant == "preview")
                }
            }
            if let raw = info.text("url_player_info"), let infoURL = trustedMediaURL(raw) {
                let (details, _) = try await send(infoURL)
                let sources = (details.object("Result")?.object("Data")?.array("PlayInfoList"))
                    ?? details.object("data")?.array("PlayInfoList")
                    ?? details.array("PlayInfoList") ?? []
                for value in sources {
                    guard let item = value as? JSONObject else { continue }
                    if RequestPolicy.isProtectedAudio(item) {
                        sawProtectedAudio = true
                        continue
                    }
                    guard let raw = item.text("MainPlayUrl"), let source = trustedMediaURL(raw) else { continue }
                    return (source, variant == "preview")
                }
            }
        }
        if sawProtectedAudio { throw SodaError.protectedAudio }
        throw SodaError.message("汽水接口暂未提供可播放音源，请稍后重试。")
    }

    private func trustedMediaURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw), url.scheme == "https", url.user == nil,
              let host = url.host?.lowercased() else { return nil }
        let domains = ["douyinvod.com", "douyinscdn.com", "bytefcdn.com", "bytecdn.cn",
                       "byteicdn.com", "ibytedtos.com", "pstatp.com", "snssdk.com",
                       "bytedance.com", "bytetos.com", "volcvideo.com", "volccdn.com",
                       "volces.com", "douyin.com", "qishui.com", "zijieapi.com", "zjcdn.com"]
        return domains.contains { host == $0 || host.hasSuffix(".\($0)") } ? url : nil
    }

    func likedTracks() async throws -> [Track] {
        guard let liked = try await playlists().first(where: { $0.type == 1 }) else {
            throw SodaError.message("账号未返回‘我喜欢的音乐’歌单")
        }
        return try await playlistTracks(liked)
    }

    func playlists() async throws -> [Playlist] {
        let data = try await platform("/me/playlist/", body: ["count": 100, "cursor": ""], signed: true)
        let rows = data.array("playlists") ?? data.array("playlist_list") ?? []
        return rows.compactMap { ($0 as? JSONObject).flatMap(Playlist.init) }
    }

    func collectedPlaylists() async throws -> [Playlist] {
        let data = try await platform("/me/collection/mixed/", body: [
            "count": 100, "cursor": "", "item_types": ["playlist"]], signed: true)
        return (data.array("mixed_collections") ?? [])
            .compactMap { ($0 as? JSONObject).flatMap(Playlist.init) }
    }

    func recentTracks() async throws -> [Track] {
        let data = try await platform("/me/recent-played/", body: [
            "count": 100, "cursor": "", "media_type": "track", "scene": "me_tab"], signed: true)
        return (data.array("media") ?? []).compactMap { value in
            guard let row = value as? JSONObject, let media = row.object("media") else { return nil }
            return Track(media)
        }
    }

    func playlistTracks(_ playlist: Playlist) async throws -> [Track] {
        var cursor = "0"
        var tracks: [Track] = []
        var seen = Set<String>()
        for _ in 0..<20 {
            guard seen.insert(cursor).inserted else { throw SodaError.message("歌单分页游标重复") }
            let data = try await platform("/playlist/detail/", body: [
                "playlist_id": playlist.id, "owner_id": playlist.ownerId,
                "count": 100, "cursor": cursor,
                "type": playlist.type == 1 ? (1 as Any) : (NSNull() as Any)])
            let rows = data.array("media_entities") ?? data.array("media_list") ?? []
            tracks.append(contentsOf: rows.compactMap { ($0 as? JSONObject).flatMap(Track.init) })
            guard data["has_more"] as? Bool == true else { break }
            guard let next = data.text("next_cursor"), !next.isEmpty else {
                throw SodaError.message("歌单分页中断")
            }
            cursor = next
        }
        return tracks
    }

    private func qrParameters() -> JSONObject {
        ["aid": "1128", "client_key": clientKey,
         "scope": "user_info,luna.openapi.platform.interaction,luna.openapi.platform.me_tab,luna.commerce.openapi_platform.vip_info",
         "state": "", "next": "", "jump_type": "native", "optional_scope_check": "",
         "optional_scope_uncheck": "", "customize_params": "{\"source\":\"pc_auth\",\"not_skip_confirm\":\"true\"}",
         "source_from": "native", "device_platform": "android",
         "app_identity": "82a0737a3f8d93d9958c8a7938bbc365",
         "signature": "cf9024ea72d9c71813238b13ea107a3d"]
    }

    func startLogin() async throws -> LoginCode {
        let address = try plainURL("https://open.douyin.com/oauth/get_qrcode/", qrParameters())
        let (result, _) = try await send(address)
        guard let data = result.object("data"), let token = data.text("token"),
              let encoded = data.text("qrcode"), let bytes = Data(base64Encoded: encoded),
              let image = UIImage(data: bytes) else { throw SodaError.message("无法生成抖音登录二维码") }
        return LoginCode(token: token, image: image, expiresAt: Date().addingTimeInterval(300))
    }

    func checkLogin(_ code: LoginCode) async throws -> LoginStatus {
        if Date() >= code.expiresAt { return .expired }
        var params = qrParameters()
        params["token"] = code.token
        params["timestamp"] = String(Int(Date().timeIntervalSince1970 * 1000))
        let address = try plainURL("https://open.douyin.com/oauth/check_qrcode/", params)
        let (result, _) = try await send(address)
        guard let data = result.object("data"), let status = data.text("status") else {
            throw SodaError.message("扫码状态无法识别")
        }
        switch status {
        case "new": return .waiting
        case "scanned": return .scanned
        case "expired": return .expired
        case "refused": return .refused
        case "confirmed":
            guard let authCode = data.text("code") ?? data.text("auth_code") else {
                throw SodaError.message("抖音没有返回授权码")
            }
            let account = try await exchange(authCode)
            self.account = account
            KeyStore.save(account)
            return .confirmed(account)
        default: throw SodaError.message("未知的扫码状态：\(status)")
        }
    }

    private func exchange(_ authCode: String) async throws -> Account {
        let accessAddress = try url("https://open.qishui.com\(prefix)/access/code/get/", ["auth_code": authCode])
        let (response, _) = try await send(accessAddress)
        let access = response.object("data") ?? response
        guard let accessCode = access.text("access_code") else { throw SodaError.message("未取得汽水授权") }
        let openId = access.text("open_id") ?? access.text("open_uid") ?? ""
        let key = P256.Signing.PrivateKey()
        let csr = try makeCSR(key: key)
        let ticketAddress = try plainURL("https://open-client.douyin.com/passport/open/get_access_ticket/",
                                         ["aid": "1128", "client_key": clientKey, "device_platform": "android"])
        let (_, ticketResponse) = try await send(ticketAddress,
            body: ["access_code": accessCode, "open_id": openId], form: true,
            headers: ["bd-ticket-guard-version": "1", "bd-ticket-guard-client-csr": csr])
        guard let serverData = ticketResponse.value(forHTTPHeaderField: "bd-ticket-guard-server-data"),
              let decoded = Data(base64Encoded: serverData),
              let guardData = try JSONSerialization.jsonObject(with: decoded) as? JSONObject,
              let ticket = guardData.text("ticket"),
              let signature = guardData.text("ts_sign"),
              let certificate = guardData.text("client_cert") else {
            throw SodaError.message("汽水没有返回账号凭证")
        }
        let cert = certificate.contains("-----BEGIN")
            ? Data(certificate.utf8).base64EncodedString() : certificate
        var account = Account(deviceId: deviceId, userId: "", nickname: "", avatarURL: nil,
                              isVIP: false, ticket: ticket,
                              guardKey: key.rawRepresentation.base64EncodedString(),
                              guardCert: cert, guardTsSign: signature,
                              accessCode: accessCode, openId: openId,
                              expiresAt: credentialExpiry(access.text("expires_time")))
        self.account = account
        let userData = try await platform("/me/info/", signed: true)
        guard let user = userData.object("my_info"), let userId = user.text("id") else {
            throw SodaError.message("无法验证汽水账号")
        }
        account.userId = userId
        account.nickname = user.text("nickname") ?? "汽水用户"
        account.avatarURL = user.text("medium_avatar_url") ?? user.text("avatar_url")
        account.isVIP = user["is_vip"] as? Bool ?? false
        return account
    }

    private func guardHeaders(_ account: Account, _ path: String) throws -> [String: String] {
        guard let raw = Data(base64Encoded: account.guardKey) else { throw SodaError.message("登录凭证无效") }
        let key = try P256.Signing.PrivateKey(rawRepresentation: raw)
        let timestamp = Int(Date().timeIntervalSince1970)
        let content = "ticket=\(account.ticket)&path=\(prefix)\(path)&timestamp=\(timestamp)"
        let signature = try key.signature(for: Data(content.utf8)).derRepresentation.base64EncodedString()
        let payload: JSONObject = ["ts_sign": account.guardTsSign,
                                   "req_content": "ticket,path,timestamp",
                                   "req_sign": signature, "timestamp": timestamp]
        return ["access-token": account.ticket,
                "bd-ticket-guard-version": "1",
                "bd-ticket-guard-client-cert": account.guardCert,
                "bd-ticket-guard-client-data": try JSONSerialization.data(withJSONObject: payload).base64EncodedString()]
    }

    private func renewAccountIfNeeded() async throws {
        guard var saved = account, saved.expiresAt < Date().addingTimeInterval(3600).timeIntervalSince1970 else {
            return
        }
        let refreshURL = try url("https://open.qishui.com\(prefix)/access/code/refresh/",
                                 ["access_code": saved.accessCode])
        let (result, _) = try await send(refreshURL)
        let access = result.object("data") ?? result
        guard let newCode = access.text("access_code") else {
            throw SodaError.message("账号续期失败，请重新扫码")
        }
        let ticketURL = try plainURL("https://open-client.douyin.com/passport/open/get_access_ticket/",
                                     ["aid": "1128", "client_key": clientKey, "device_platform": "android"])
        let (_, response) = try await send(ticketURL,
            body: ["access_code": newCode, "open_id": access.text("open_id") ?? saved.openId],
            form: true,
            headers: ["bd-ticket-guard-version": "1", "bd-ticket-guard-client-cert": saved.guardCert])
        guard let raw = response.value(forHTTPHeaderField: "bd-ticket-guard-server-data"),
              let decoded = Data(base64Encoded: raw),
              let ticket = try JSONSerialization.jsonObject(with: decoded) as? JSONObject,
              let newTicket = ticket.text("ticket"),
              let newSignature = ticket.text("ts_sign"),
              let newCert = ticket.text("client_cert") else {
            throw SodaError.message("账号续期没有返回新凭证")
        }
        saved.accessCode = newCode
        saved.ticket = newTicket
        saved.guardTsSign = newSignature
        saved.guardCert = newCert.contains("-----BEGIN")
            ? Data(newCert.utf8).base64EncodedString() : newCert
        saved.expiresAt = credentialExpiry(access.text("expires_time"))
        account = saved
        KeyStore.save(saved)
    }

    private func makeCSR(key: P256.Signing.PrivateKey) throws -> String {
        func der(_ tag: UInt8, _ children: Data...) -> Data {
            let content = children.reduce(into: Data()) { $0.append($1) }
            var result = Data([tag])
            if content.count < 128 { result.append(UInt8(content.count)) }
            else if content.count < 256 { result.append(contentsOf: [0x81, UInt8(content.count)]) }
            else { result.append(contentsOf: [0x82, UInt8(content.count >> 8), UInt8(content.count & 255)]) }
            result.append(content)
            return result
        }
        func attribute(_ id: UInt8, _ value: String) -> Data {
            der(0x31, der(0x30, der(0x06, Data([0x55, 0x04, id])), der(0x0c, Data(value.utf8))))
        }
        let subject = der(0x30, attribute(3, "bd-ticket-guard"), attribute(11, ""), attribute(10, ""))
        let spki = der(0x30,
                       der(0x30,
                           der(0x06, Data([0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01])),
                           der(0x06, Data([0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07]))),
                       der(0x03, Data([0]) + key.publicKey.x963Representation))
        let info = der(0x30, der(0x02, Data([0])), subject, spki, der(0xa0))
        let algorithm = der(0x30, der(0x06, Data([0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x02])))
        let signature = try key.signature(for: info).derRepresentation
        let request = der(0x30, info, algorithm, der(0x03, Data([0]) + signature))
        let encoded = request.base64EncodedString()
        let lines = stride(from: 0, to: encoded.count, by: 64).map { index -> String in
            let start = encoded.index(encoded.startIndex, offsetBy: index)
            let end = encoded.index(start, offsetBy: min(64, encoded.count - index))
            return String(encoded[start..<end])
        }
        let pem = "-----BEGIN CERTIFICATE REQUEST-----\n\(lines.joined(separator: "\n"))\n-----END CERTIFICATE REQUEST-----\n"
        return Data(pem.utf8).base64EncodedString()
    }

    private func credentialExpiry(_ raw: String?) -> TimeInterval {
        guard let raw, let value = Double(raw), value > 0 else {
            return Date().addingTimeInterval(6 * 3600).timeIntervalSince1970
        }
        if value > 1_000_000_000_000 { return value / 1000 }
        if value > 1_000_000_000 { return value }
        return Date().addingTimeInterval(value).timeIntervalSince1970
    }

    func logout() {
        account = nil
        KeyStore.save(nil)
    }
}
