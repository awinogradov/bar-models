import Testing
@testable import UsageCore

@Suite("UsageFormat")
struct FormatTests {
    @Test("abbreviates with K/M/B and trims .0")
    func abbreviations() {
        #expect(UsageFormat.tokens(0) == "0")
        #expect(UsageFormat.tokens(999) == "999")
        #expect(UsageFormat.tokens(1_000) == "1K")
        #expect(UsageFormat.tokens(1_500) == "1.5K")
        #expect(UsageFormat.tokens(38_214_556) == "38.2M")
        #expect(UsageFormat.tokens(2_500_000_000) == "2.5B")
    }
}
