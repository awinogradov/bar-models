import Testing
@testable import UsageCore

@Suite("UsageStore")
struct UsageStoreTests {
    @Test("starts empty and idle")
    @MainActor
    func startsEmpty() {
        let store = UsageStore()
        #expect(store.snapshot == nil)
        #expect(store.isScanning == false)
    }
}
