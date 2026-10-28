import Foundation
import Darwin

// The ledger is separate from task selection: removing a selection cannot
// erase an unresolved submission or its controls.
enum HandoffState: String, Codable {
    case submitting, uncertain, queued, handedOff, cancelled, acknowledged
    var unresolved: Bool { self == .submitting || self == .uncertain || self == .queued }
}

struct HandoffRecord: Codable, Identifiable, Equatable {
    let threadID: String
    let accountID: String
    let title: String
    let failedTurnID: String
    let clientMessageID: String
    var queueID: String?
    var state: HandoffState
    var hidden: Bool
    var ownerPID: Int32? = nil
    var id: String { clientMessageID }
}

@MainActor final class HandoffLedger {
    private let fileURL: URL
    private(set) var records: [HandoffRecord] = []
    private(set) var storageError: String?
    var storageCorrupted: Bool { storageError != nil }

    init(fileURL:URL? = nil) {
        let applicationSupport = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first
            ?? URL(fileURLWithPath:NSHomeDirectory(),isDirectory:true).appendingPathComponent("Library/Application Support",isDirectory:true)
        // Personal and public builds share this ledger so two installations
        // cannot independently submit the same continuation.
        self.fileURL = fileURL ?? applicationSupport.appendingPathComponent("Usage Capsule",isDirectory:true).appendingPathComponent("auto-resume-handoffs.json")
        _ = locked(false) { reload(convertSubmitting:true) }
    }
    var visibleRecords: [HandoffRecord] { records.filter { !$0.hidden } }
    var hasUnresolved: Bool { storageCorrupted || records.contains { $0.state.unresolved || Self.ownerIsAlive($0.ownerPID) } }
    private static func ownerIsAlive(_ pid:Int32?) -> Bool {
        guard let pid, pid > 0 else { return false }
        if Darwin.kill(pid,0) == 0 { return true }
        return errno != ESRCH
    }
    func canAcknowledge(_ record:HandoffRecord) -> Bool {
        (record.state == .uncertain || record.state == .submitting) && !Self.ownerIsAlive(record.ownerPID)
    }

    // Returns only after the intent and client ID are saved. Callers must not
    // send a request when this returns nil, including when storage is invalid.
    func begin(threadID:String,accountID:String,title:String,failedTurnID:String) -> HandoffRecord? {
        guard !storageCorrupted, !threadID.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
              !accountID.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
              !failedTurnID.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return nil }
        return locked(nil as HandoffRecord?) {
            guard reload(convertSubmitting:false), !hasUnresolved,
                  !records.contains(where: { $0.threadID == threadID && $0.accountID == accountID && $0.failedTurnID == failedTurnID }) else { return nil }
            let item = HandoffRecord(threadID:threadID,accountID:accountID,title:title,failedTurnID:failedTurnID,
                                     clientMessageID:UUID().uuidString.lowercased(),queueID:nil,state:.submitting,hidden:false,ownerPID:Darwin.getpid())
            records.append(item)
            guard persist() else { records.removeLast(); return nil }
            return item
        }
    }
    @discardableResult func refresh() -> Bool {
        guard !storageCorrupted else { return false }
        return locked(false) { reload(convertSubmitting:false) }
    }

    @discardableResult func markQueued(clientMessageID:String,queueID:String) -> Bool {
        guard !queueID.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return false }
        return change(clientMessageID) { item in
            if item.state == .queued { return item.queueID == queueID }
            guard item.state == .submitting || item.state == .uncertain else { return false }
            item.queueID = queueID; item.state = .queued
            return true
        }
    }
    @discardableResult func markUncertain(clientMessageID:String) -> Bool {
        change(clientMessageID) { item in
            guard item.state == .submitting || item.state == .uncertain || item.state == .queued else { return false }
            item.state = .uncertain
            return true
        }
    }
    // The caller must first verify that Codex accepted or consumed the item.
    @discardableResult func markHandedOff(clientMessageID:String) -> Bool {
        change(clientMessageID) { item in
            guard item.state == .queued || item.state == .uncertain || item.state == .submitting else { return false }
            item.state = .handedOff
            return true
        }
    }
    // The caller must verify deletion from Codex's queue first.
    @discardableResult func markCancelled(clientMessageID:String) -> Bool {
        change(clientMessageID) { item in
            guard item.state == .queued else { return false }
            item.state = .cancelled
            return true
        }
    }
    // Invoke only for an explicit owner acknowledgement after inspecting Codex.
    @discardableResult func acknowledgeUncertain(clientMessageID:String) -> Bool {
        change(clientMessageID) { item in
            guard (item.state == .uncertain || item.state == .submitting), !Self.ownerIsAlive(item.ownerPID) else { return false }
            item.ownerPID = nil
            item.state = .acknowledged
            return true
        }
    }
    @discardableResult func finishSubmission(clientMessageID:String) -> Bool {
        change(clientMessageID) { item in
            guard item.ownerPID == Darwin.getpid() else { return false }
            item.ownerPID = nil
            if item.state == .submitting { item.state = .uncertain }
            return true
        }
    }
    @discardableResult func dismissResolved(clientMessageID:String) -> Bool {
        change(clientMessageID) { item in
            guard !item.state.unresolved, !Self.ownerIsAlive(item.ownerPID) else { return false }
            item.hidden = true
            return true
        }
    }
    private func change(_ id:String, update:(inout HandoffRecord)->Bool) -> Bool {
        guard !storageCorrupted else { return false }
        return locked(false) {
            guard reload(convertSubmitting:false), let index = records.firstIndex(where: { $0.clientMessageID == id }) else { return false }
            let previous = records[index]
            guard update(&records[index]) else { records[index] = previous; return false }
            guard persist() else { records[index] = previous; return false }
            return true
        }
    }
    // The lock is separate from the atomically replaced data file. It protects
    // both the read and the write when more than one capsule is running.
    private func locked<T>(_ fallback:T, _ body:()->T) -> T {
        guard !storageCorrupted else { return fallback }
        do {
            try FileManager.default.createDirectory(at:fileURL.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            let lockPath = fileURL.appendingPathExtension("lock").path
            let fd = Darwin.open(lockPath,O_CREAT | O_RDWR | O_NOFOLLOW,mode_t(0o600))
            guard fd >= 0 else { throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno)) }
            defer { Darwin.close(fd) }
            guard Darwin.lockf(fd,F_LOCK,0) == 0 else { throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno)) }
            defer { _ = Darwin.lockf(fd,F_ULOCK,0) }
            return body()
        } catch {
            storageError = error.localizedDescription
            return fallback
        }
    }
    private func reload(convertSubmitting:Bool) -> Bool {
        do {
            let data = try Data(contentsOf:fileURL)
            records = try JSONDecoder().decode([HandoffRecord].self,from:data)
            var changed = false
            if convertSubmitting {
                for index in records.indices where records[index].state == .submitting && !Self.ownerIsAlive(records[index].ownerPID) {
                    records[index].state = .uncertain
                    records[index].ownerPID = nil
                    changed = true
                }
            }
            return !changed || persist()
        } catch {
            let error = error as NSError
            if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
                records = []
                return true
            }
            storageError = error.localizedDescription
            return false
        }
    }
    private func persist() -> Bool {
        do {
            try FileManager.default.createDirectory(at:fileURL.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            let data = try JSONEncoder().encode(records)
            try data.write(to:fileURL,options:.atomic)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:fileURL.path)
            let handle = try FileHandle(forWritingTo:fileURL)
            defer { try? handle.close() }
            try handle.synchronize()
            return true
        } catch {
            storageError = error.localizedDescription
            return false
        }
    }
}
