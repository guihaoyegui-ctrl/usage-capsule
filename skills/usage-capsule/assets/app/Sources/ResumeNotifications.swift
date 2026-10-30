import Foundation
import AppKit
import UserNotifications

/// Notifications are explicitly enabled in the manager. No permission prompt
/// appears on launch, and model execution is never part of reporting a result.
@MainActor final class ResumeNotificationController:NSObject, UNUserNotificationCenterDelegate {
    private weak var store:QuotaStore?
    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private var revision = 0
    init(store:QuotaStore) { self.store = store; super.init() }
    func install() {
        center.delegate = self
        store?.configureResumeNotifications = { [weak self] enabled in self?.configure(enabled) }
        store?.deliverResumeNotification = { [weak self] record in self?.deliver(record) }
        guard defaults.bool(forKey:"resumeNotificationsEnabled") else { return }
        Task {
            let current = revision
            let settings = await center.notificationSettings()
            guard current == revision else { return }
            store?.resumeNotificationsEnabled = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            if store?.resumeNotificationsEnabled != true { store?.resumeNotificationNotice = L10n.text("系统通知未开启，结果仍会保留在续跑记录中。") }
        }
    }
    private func configure(_ enabled:Bool) {
        revision += 1
        let current = revision
        store?.resumeNotificationNotice = nil
        guard enabled else {
            defaults.set(false,forKey:"resumeNotificationsEnabled")
            store?.resumeNotificationsEnabled = false
            return
        }
        Task {
            do {
                let granted = try await center.requestAuthorization(options:[.alert,.sound])
                guard revision == current else { return }
                defaults.set(granted,forKey:"resumeNotificationsEnabled")
                store?.resumeNotificationsEnabled = granted
                if !granted { store?.resumeNotificationNotice = L10n.text("系统通知未开启，结果仍会保留在续跑记录中。") }
            } catch {
                guard revision == current else { return }
                store?.resumeNotificationsEnabled = false
                store?.resumeNotificationNotice = L10n.text("通知暂不可用，请在续跑记录中查看结果。")
            }
        }
    }
    private func deliver(_ record:HandoffRecord) {
        guard store?.resumeNotificationsEnabled == true else { return }
        let content = UNMutableNotificationContent()
        content.title = record.turnStatus == "completed" ? L10n.text("续跑本轮已结束") : L10n.text("续跑需要你处理")
        content.body = String(record.title.prefix(140))
        content.userInfo = ["threadID":record.threadID]
        content.sound = .default
        let request = UNNotificationRequest(identifier:"usage-capsule-resume-"+record.id,content:content,trigger:nil)
        Task {
            do { try await center.add(request) }
            catch { store?.resumeNotificationNotice = L10n.text("通知暂不可用，请在续跑记录中查看结果。") }
        }
    }
    nonisolated func userNotificationCenter(_ center:UNUserNotificationCenter,didReceive response:UNNotificationResponse,withCompletionHandler completionHandler:@escaping ()->Void) {
        let id = response.notification.request.content.userInfo["threadID"] as? String
        Task { @MainActor [weak self] in if let id { self?.store?.openResumeThread(id) } }
        completionHandler()
    }
    nonisolated func userNotificationCenter(_ center:UNUserNotificationCenter,willPresent notification:UNNotification,withCompletionHandler completionHandler:@escaping (UNNotificationPresentationOptions)->Void) {
        completionHandler([.banner,.sound])
    }
}
