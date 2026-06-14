import Foundation

/// USD cost for a period, split per model, with the tokens of any unpriced
/// model surfaced separately so they're flagged rather than silently dropped.
public struct CostBreakdown: Sendable, Equatable {
    public var total: Double
    public var byModel: [String: Double]
    public var unknownModelTokens: UInt64

    public init(total: Double = 0, byModel: [String: Double] = [:], unknownModelTokens: UInt64 = 0) {
        self.total = total
        self.byModel = byModel
        self.unknownModelTokens = unknownModelTokens
    }
}

/// Turns a per-model token map into USD using a `PricingTable`. Each model is
/// priced on its own four-bucket rates, then summed — never a blended rate.
public struct CostCalculator: Sendable {
    public let pricing: PricingTable

    public init(pricing: PricingTable = .claude) {
        self.pricing = pricing
    }

    public func cost(of byModel: [String: TokenCounts]) -> CostBreakdown {
        var total = 0.0
        var perModel: [String: Double] = [:]
        var unknown: UInt64 = 0
        for (model, tokens) in byModel {
            if let c = pricing.cost(tokens, model: model) {
                total += c
                perModel[model] = c
            } else {
                unknown += tokens.billableTotal // unpriced model → flag, don't zero into the total
            }
        }
        return CostBreakdown(total: total, byModel: perModel, unknownModelTokens: unknown)
    }
}
