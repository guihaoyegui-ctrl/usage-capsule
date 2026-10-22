import Foundation
import AppKit
import SwiftUI

struct ServiceError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
@MainActor final class CodexConnection {
    private var process: Process?
    private var input: Pipe?
    private var buffer = Data()
    private var counter = 0
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var initialized = false
    var notification: ((String, [String: Any]) -> Void)?
    static func executable() -> String? {
        let args=ProcessInfo.processInfo.arguments
        if let i=args.firstIndex(of:"--codex-cli"), args.indices.contains(i+1), FileManager.default.isExecutableFile(atPath:args[i+1]) {
            UserDefaults.standard.set(args[i+1],forKey:"codexCLIPath")
            return args[i+1]
        }
        let paths = [ProcessInfo.processInfo.environment["CODEX_CLI_PATH"],
            UserDefaults.standard.string(forKey:"codexCLIPath"),
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
            .compactMap { $0 } + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/codex" }
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    func connect() async throws {
        if initialized, process?.isRunning == true { return }
        disconnect()
        guard let binary = Self.executable() else { throw ServiceError(message: L10n.text("未找到 Codex，请先安装或打开 Codex 桌面应用。")) }
        let p = Process(), stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        p.executableURL = URL(fileURLWithPath: binary); p.arguments = ["app-server", "--stdio"]
        p.standardInput = stdin; p.standardOutput = stdout; p.standardError = stderr
        p.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let bytes = handle.availableData
            if bytes.isEmpty { handle.readabilityHandler = nil; return }
            Task { @MainActor in self?.receive(bytes) }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in if handle.availableData.isEmpty { handle.readabilityHandler = nil } }
        p.terminationHandler = { [weak self] child in
            Task { @MainActor in
                guard self?.process === child else { return }
                self?.failAll(ServiceError(message: L10n.text("Codex 连接已关闭，请重试刷新。"))); self?.initialized = false
            }
        }
        process = p; input = stdin; buffer.removeAll()
        try p.run()
        _ = try await request("initialize", params: ["clientInfo": ["name":"usage_capsule", "title":"Usage Capsule", "version":"0.7.0"], "capabilities": ["experimentalApi":true]])
        try send(["method":"initialized", "params": [:]])
        initialized = true
    }
    func disconnect() {
        failAll(ServiceError(message: L10n.text("连接已断开"))); initialized = false
        process?.terminationHandler = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil; input = nil; buffer.removeAll()
    }
    private func failAll(_ error: Error) {
        let waiting = pending; pending.removeAll(); for c in waiting.values { c.resume(throwing:error) }
    }
    private func send(_ message: [String: Any]) throws {
        guard let input, process?.isRunning == true else { throw ServiceError(message:L10n.text("Codex 未连接")) }
        var data = try JSONSerialization.data(withJSONObject: message); data.append(10)
        try input.fileHandleForWriting.write(contentsOf:data)
    }
    func request(_ method: String, params: [String: Any] = [:]) async throws -> Data {
        counter += 1; let id = counter
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do { try send(["id":id,"method":method,"params":params]) }
            catch { pending.removeValue(forKey:id)?.resume(throwing:error); return }
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                self?.pending.removeValue(forKey:id)?.resume(throwing:ServiceError(message:L10n.text("请求超时，请检查网络后刷新。")))
            }
        }
    }
    private func receive(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of:10) {
            let line = buffer.subdata(in:0..<newline); buffer.removeSubrange(0...newline)
            guard let message = try? JSONSerialization.jsonObject(with:line) as? [String:Any] else { continue }
            if let id = message["id"] as? Int, let c = pending.removeValue(forKey:id) {
                if let error = message["error"] as? [String:Any] {
                    c.resume(throwing:ServiceError(message:error["message"] as? String ?? L10n.text("服务请求失败")))
                } else if let result = message["result"] {
                    do { c.resume(returning:try JSONSerialization.data(withJSONObject:result,options:.fragmentsAllowed)) }
                    catch { c.resume(throwing:error) }
                } else { c.resume(throwing:ServiceError(message:L10n.text("服务未返回数据"))) }
            } else if let method = message["method"] as? String {
                notification?(method,message["params"] as? [String:Any] ?? [:])
            }
        }
    }
}

@MainActor final class QuotaStore: ObservableObject {
    @Published var limits: LimitsResponse?
    @Published var days: [DayUsage] = recentDays(buckets:nil)
    @Published var selectedDay = todayKey()
    @Published var refreshing = false
    @Published var redeeming = false
    @Published var lastSync: Date?
    @Published var error: String?
    @Published var usageError: String?
    @Published var notice: String?
    @Published var demo = false
    @Published var pinned = false
    @Published var alwaysOnTop = true
    @Published var scale = 1.0
    @Published var language = UserDefaults.standard.string(forKey:"interfaceLanguage") ?? "system"
    let connection = CodexConnection()
    private var timer: Timer?
    let redemption = RedemptionLedger()
    var pendingRedemption: Bool { redemption.pending != nil }
    var primary: QuotaWindow? { limits?.bucket?.primary }
    var secondary: QuotaWindow? { limits?.bucket?.secondary }
    var resetCount: Int? { limits?.rateLimitResetCredits?.availableCount }
    var selected: DayUsage? { days.first { $0.date == selectedDay } ?? days.last }
    var canRedeem: Bool { !demo && mayRedeem(cardCount:resetCount,pending:redemption.pending,busy:redeeming || refreshing,connected:error == nil && lastSync != nil,accountID:limits?.accountId) }
    var redemptionLabel:String {
        if demo { return L10n.text("演示模式") }
        if pendingRedemption {
            return redemption.pending?.accountID == limits?.accountId && limits?.accountId != nil ? L10n.text("长按核实上次兑换") : L10n.text("切回原账号以核实兑换")
        }
        if limits?.accountId == nil { return L10n.text("暂无法确认兑换账号") }
        return resetCount == 0 ? L10n.text("暂无重置卡") : L10n.text("长按 0.8 秒使用")
    }
    func start() {
        if pendingRedemption { notice = L10n.text("上次兑换待核实，长按按钮可核实同一次兑换。") }
        if ProcessInfo.processInfo.arguments.contains("--demo") { loadDemo(); return }
        connection.notification = { [weak self] method, _ in
            if method == "account/login/completed" || method == "account/rateLimits/updated" { Task { await self?.refresh() } }
        }
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval:60,repeats:true) { [weak self] _ in Task { @MainActor in await self?.refresh() } }
    }
    func stop() { timer?.invalidate(); connection.disconnect() }
    func refresh() async {
        guard !refreshing, !redeeming, !demo else { return }
        refreshing = true; defer { refreshing = false }
        do {
            try await connection.connect()
            limits = try JSONDecoder().decode(LimitsResponse.self,from:await connection.request("account/rateLimits/read"))
            lastSync = Date(); error = nil
            do {
                let usage = try JSONDecoder().decode(UsageResponse.self,from:await connection.request("account/usage/read"))
                days = recentDays(buckets:usage.dailyUsageBuckets); usageError = nil
                if !days.contains(where:{$0.date == selectedDay}) { selectedDay = days.last?.date ?? todayKey() }
            } catch { usageError = L10n.format("日用量暂无法读取：%@", String(describing: (error.localizedDescription))) }
        } catch { self.error = error.localizedDescription }
    }
    func redeem() async {
        guard canRedeem else { return }
        redeeming = true; notice = nil
        do {
            let fresh = try JSONDecoder().decode(LimitsResponse.self,from:await connection.request("account/rateLimits/read"))
            guard let accountID = fresh.accountId, accountID == limits?.accountId,
                  mayRedeem(cardCount:fresh.rateLimitResetCredits?.availableCount,pending:redemption.pending,busy:false,connected:true,accountID:accountID) else {
                limits = fresh; notice = L10n.text("账号或可用卡已变化，请核实后再长按。"); redeeming = false; return
            }
            limits = fresh
        } catch { notice = L10n.format("暂无法核实兑换账号：%@", String(describing: (error.localizedDescription))); redeeming = false; return }
        let creditID = limits?.rateLimitResetCredits?.credits?.filter { $0.status == "available" }
            .sorted { ($0.expiresAt ?? .greatestFiniteMagnitude) < ($1.expiresAt ?? .greatestFiniteMagnitude) }.first?.id
        let attempt = redemption.begin(creditID:creditID,accountID:limits!.accountId!)
        var params: [String:Any] = ["idempotencyKey":attempt.key]
        if let creditID = attempt.creditID { params["creditId"] = creditID }
        do {
            let data = try await connection.request("account/rateLimitResetCredit/consume",params:params)
            let result = try JSONSerialization.jsonObject(with:data) as? [String:Any]
            let outcome = result?["outcome"] as? String ?? ""
            redemption.resolve(outcome)
            switch resetDecision(outcome) {
            case .refresh: notice = L10n.text("重置已完成，正在核实额度")
            case .noCredit: notice = L10n.text("暂无有效重置卡")
            case .nothingToReset: notice = L10n.text("当前没有可重置的额度窗口")
            case .unknown: notice = L10n.text("结果暂不明确，请刷新核实；再次使用会复用本次请求。")
            }
        } catch { notice = L10n.format("兑换结果未确认：%@；重试将核实同一次兑换。", String(describing: (error.localizedDescription))) }
        redeeming = false
        await refresh()
    }
    func login() async {
        do {
            try await connection.connect()
            let data = try await connection.request("account/login/start",params:["type":"chatgpt"])
            let r = try JSONSerialization.jsonObject(with:data) as? [String:Any]
            if let urlString = r?["authUrl"] as? String, let url = URL(string:urlString), url.scheme == "https" { NSWorkspace.shared.open(url); notice = L10n.text("请在浏览器完成登录，然后刷新") }
        } catch { notice = error.localizedDescription }
    }
    func loadDemo() {
        demo = true; error = nil; lastSync = Date()
        limits = try? JSONDecoder().decode(LimitsResponse.self,from:Data("""
        {"rateLimits":{"primary":{"usedPercent":32,"windowDurationMins":300,"resetsAt":\(Date().timeIntervalSince1970+8300)},"secondary":{"usedPercent":58,"windowDurationMins":10080,"resetsAt":\(Date().timeIntervalSince1970+280000)}},"rateLimitResetCredits":{"availableCount":1}}
        """.utf8))
        let values: [Int64] = [8200,14500,3100,22400,9800,0,15420]
        days = recentDays(buckets:nil).enumerated().map { DayUsage(date:$0.element.date,tokens:values[$0.offset]) }
        selectedDay = days.last!.date
    }
}
