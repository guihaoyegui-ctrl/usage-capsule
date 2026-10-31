import Foundation

@MainActor final class ConfirmationTestConnection: CodexServing {
    var notification: ((String,[String:Any])->Void)?
    var replies: [Data]
    var events: [String] = []
    var consumed: [[String:Any]] = []
    var delayReads = false
    init(_ replies:[Data]) { self.replies=replies }
    func connect() async throws {}
    func disconnect() {}
    func request(_ method:String,params:[String:Any]) async throws -> Data {
        events.append(method)
        switch method {
        case "account/rateLimits/read":
            if delayReads { try await Task.sleep(nanoseconds:10_000_000) }
            return replies.count > 1 ? replies.removeFirst() : replies[0]
        case "account/usage/read": return Data("{\"dailyUsageBuckets\":[]}".utf8)
        case "account/rateLimitResetCredit/consume":
            consumed.append(params)
            return Data("{\"outcome\":\"reset\"}".utf8)
        default: throw ServiceError(message:"Unexpected test request: \(method)")
        }
    }
}

@main struct ResetConfirmationTests {
    @MainActor static func main() async throws {
        var failures=0
        func check(_ condition:Bool,_ name:String) {
            if condition { print("PASS: \(name)") } else { print("FAIL: \(name)"); failures+=1 }
        }
        func response(account:String="account-a",credit:String="credit-a",count:Int=1) -> Data {
            try! JSONSerialization.data(withJSONObject:["accountId":account,"rateLimits":["primary":["usedPercent":100,"windowDurationMins":300]],"rateLimitResetCredits":["availableCount":count,"credits":[["id":credit,"status":"available","expiresAt":2000000000]]]])
        }
        var suites:[String]=[]
        defer { for suite in suites { UserDefaults.standard.removePersistentDomain(forName:suite) } }
        func fixture(_ replies:[Data],prompt:@escaping (ResetConfirmation)->Bool) -> (QuotaStore,ConfirmationTestConnection,RedemptionLedger) {
            let suite="usage-capsule.confirmation-tests.\(UUID().uuidString)"; suites.append(suite)
            let ledger=RedemptionLedger(defaults:UserDefaults(suiteName:suite)!)
            let rpc=ConfirmationTestConnection(replies)
            let store=QuotaStore(connection:rpc,redemption:ledger,confirmReset:prompt)
            store.limits=try! JSONDecoder().decode(LimitsResponse.self,from:replies[0]); store.lastSync=Date()
            return (store,rpc,ledger)
        }
        var prompts=0
        let (cancelled,cancelRPC,cancelLedger)=fixture([response()]) { _ in prompts+=1; return false }
        await cancelled.redeem()
        check(prompts==1,"a reset must ask the customer before submission")
        check(cancelRPC.consumed.isEmpty,"cancel or dismissal cannot submit a reset")
        check(cancelLedger.pending==nil,"cancel cannot create a persisted redemption attempt")
        check(!cancelled.redeeming,"cancel releases the reset lock")

        let (approved,approveRPC,_)=fixture([response()]) { _ in true }
        await approved.redeem()
        check(approveRPC.consumed.count==1,"explicit customer approval submits exactly one reset")
        check(Array(approveRPC.events.prefix(3))==["account/rateLimits/read","account/rateLimits/read","account/rateLimitResetCredit/consume"],"account and card are checked again after confirmation")

        let (switched,switchRPC,switchLedger)=fixture([response(),response(account:"account-b")]) { _ in true }
        await switched.redeem()
        check(switchRPC.consumed.isEmpty && switchLedger.pending==nil,"an account switch during confirmation cancels submission")

        let (changed,changeRPC,changeLedger)=fixture([response(),response(credit:"credit-b")]) { _ in true }
        await changed.redeem()
        check(changeRPC.consumed.isEmpty && changeLedger.pending==nil,"a card change during confirmation requires a new customer decision")

        let (retryCancelled,retryCancelRPC,retryCancelLedger)=fixture([response(count:0)]) { _ in false }
        let pending=retryCancelLedger.begin(creditID:"original-credit",accountID:"account-a")
        await retryCancelled.redeem()
        check(retryCancelRPC.consumed.isEmpty && retryCancelLedger.pending?.key==pending.key,"cancelled reconciliation preserves the old attempt without a request")

        let (retryApproved,retryRPC,retryLedger)=fixture([response(count:0)]) { context in context.pendingKey != nil }
        let retry=retryLedger.begin(creditID:"original-credit",accountID:"account-a")
        await retryApproved.redeem()
        check(retryRPC.consumed.count==1 && retryRPC.consumed.first?["idempotencyKey"] as? String==retry.key && retryRPC.consumed.first?["creditId"] as? String=="original-credit","confirmed reconciliation reuses the original request and card")

        var decisions=[true,false]
        let (repeatStore,repeatRPC,_)=fixture([response()]) { _ in decisions.removeFirst() }
        await repeatStore.redeem(); await repeatStore.redeem()
        check(repeatRPC.consumed.count==1 && decisions.isEmpty,"a previous approval cannot authorize a later reset")

        var concurrentPrompts=0
        let (concurrent,concurrentRPC,_)=fixture([response()]) { _ in concurrentPrompts+=1; return true }
        concurrentRPC.delayReads=true
        async let first:Void=concurrent.redeem()
        async let second:Void=concurrent.redeem()
        _ = await (first,second)
        check(concurrentPrompts==1 && concurrentRPC.consumed.count==1,"repeated activation cannot create multiple confirmation requests")

        var backgroundPrompts=0
        let (background,backgroundRPC,_)=fixture([response()]) { _ in backgroundPrompts+=1; return true }
        await background.refresh()
        check(backgroundPrompts==0 && backgroundRPC.consumed.isEmpty,"refresh never asks for or consumes a reset card")
        background.loadDemo(); await background.redeem()
        check(backgroundPrompts==0 && backgroundRPC.consumed.isEmpty,"demo mode cannot ask for or submit a reset")
        failures += await RefreshRecoveryTests.run()
        failures += await AutoResumeTests.run()
        failures += await NativeQueueTests.run()
        failures += await ContinuousResumeTests.run()
        print("Reset confirmation and refresh recovery: \(failures) failures")
        if failures>0 { exit(1) }
    }
}
