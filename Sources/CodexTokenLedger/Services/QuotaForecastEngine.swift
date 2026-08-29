import Foundation

/// Forecasts quota exhaustion from observed Codex quota percentages.
struct QuotaForecastEngine: Sendable {
    private let minimumObservationSpan: TimeInterval = 120
    private let minimumMeaningfulDelta = 0.10
    private let minimumCapacityDelta = 1.0

    func forecast(
        accountID: String,
        window: CodexQuotaWindow,
        samples: [QuotaUsageSample],
        observedAt: Date? = nil,
        now: Date = Date()
    ) -> QuotaForecast {
        let observationDate = observedAt ?? now
        let current = QuotaUsageSample(
            accountID: accountID,
            windowID: window.id,
            observedAt: observationDate,
            usedPercent: window.clampedUsedPercent,
            resetsAt: window.resetsAt,
            windowMinutes: window.windowMinutes
        )
        let matching = matchingCycleSamples(for: current, in: samples)
        let merged = deduplicated((matching + [current]).sorted { $0.observedAt < $1.observedAt })
        let span = max(0, (merged.last?.observedAt ?? now).timeIntervalSince(merged.first?.observedAt ?? now))
        let resetInterval = window.resetsAt.map { max(0, $0.timeIntervalSince(now)) }
        let confidence = confidence(sampleCount: merged.count, span: span, delta: observedDelta(in: merged))

        guard merged.count >= 2, span >= minimumObservationSpan else {
            return QuotaForecast(
                state: .collecting,
                estimatedTimeToExhaustion: nil,
                timeToReset: resetInterval,
                sampleCount: merged.count,
                observationSpan: span,
                confidence: .low,
                usedPercentPerHour: nil
            )
        }

        let delta = observedDelta(in: merged)
        guard delta >= minimumMeaningfulDelta,
              let rate = robustPositiveSlopePercentPerHour(in: merged),
              rate > 0
        else {
            return QuotaForecast(
                state: .noSustainedConsumption,
                estimatedTimeToExhaustion: nil,
                timeToReset: resetInterval,
                sampleCount: merged.count,
                observationSpan: span,
                confidence: confidence,
                usedPercentPerHour: nil
            )
        }

        let timeToExhaustion = window.remainingPercent / rate * 3_600
        let lastsUntilReset = resetInterval.map { timeToExhaustion >= $0 } ?? false
        return QuotaForecast(
            state: lastsUntilReset ? .lastsUntilReset : .depletesBeforeReset,
            estimatedTimeToExhaustion: timeToExhaustion,
            timeToReset: resetInterval,
            sampleCount: merged.count,
            observationSpan: span,
            confidence: confidence,
            usedPercentPerHour: rate
        )
    }

    /// Estimates a token-equivalent capacity from two official counters
    /// observed together. It is intentionally empirical: subscription quotas
    /// are compute-weighted and OpenAI does not publish a fixed Token cap.
    func capacityEstimate(
        accountID: String,
        window: CodexQuotaWindow,
        lifetimeTokens: Int64?,
        samples: [QuotaUsageSample],
        observedAt: Date? = nil,
        now: Date = Date()
    ) -> QuotaCapacityEstimate? {
        guard let lifetimeTokens, lifetimeTokens >= 0 else { return nil }
        let observationDate = observedAt ?? now
        let current = QuotaUsageSample(
            accountID: accountID,
            windowID: window.id,
            observedAt: observationDate,
            usedPercent: window.clampedUsedPercent,
            resetsAt: window.resetsAt,
            windowMinutes: window.windowMinutes,
            lifetimeTokens: lifetimeTokens
        )
        let matching = matchingCycleSamples(for: current, in: samples)
        let merged = monotonicSuffix(
            deduplicated((matching + [current]).sorted { $0.observedAt < $1.observedAt })
        )
        guard merged.count >= 2 else { return nil }

        var estimates: [Double] = []
        for left in merged.indices {
            for right in merged.indices where right > left {
                let seconds = merged[right].observedAt.timeIntervalSince(merged[left].observedAt)
                let percentDelta = merged[right].usedPercent - merged[left].usedPercent
                guard seconds >= minimumObservationSpan,
                      percentDelta >= minimumCapacityDelta,
                      let leftTokens = merged[left].lifetimeTokens,
                      let rightTokens = merged[right].lifetimeTokens,
                      rightTokens > leftTokens
                else { continue }
                let value = Double(rightTokens - leftTokens) / percentDelta
                if value.isFinite, value > 0 { estimates.append(value) }
            }
        }
        guard let tokensPerPercent = median(estimates),
              tokensPerPercent <= Double(Int64.max) / 100
        else { return nil }

        let total = Int64((tokensPerPercent * 100).rounded())
        let remaining = Int64((tokensPerPercent * window.remainingPercent).rounded())
        let span = max(
            0,
            (merged.last?.observedAt ?? now).timeIntervalSince(merged.first?.observedAt ?? now)
        )
        let delta = observedDelta(in: merged)
        return QuotaCapacityEstimate(
            estimatedTotalTokens: total,
            estimatedRemainingTokens: remaining,
            tokensPerPercent: tokensPerPercent,
            samplePairCount: estimates.count,
            observationSpan: span,
            confidence: confidence(sampleCount: merged.count, span: span, delta: delta),
            evidence: .pairedAccountCounters,
            observedTokens: nil
        )
    }

    func currentCycleCapacityEstimate(
        window: CodexQuotaWindow,
        usage: LocalQuotaCycleUsage,
        observedAt: Date
    ) -> QuotaCapacityEstimate? {
        guard let resetsAt = window.resetsAt,
              let windowMinutes = window.windowMinutes,
              windowMinutes > 0,
              window.clampedUsedPercent >= minimumCapacityDelta,
              abs(usage.resetsAt.timeIntervalSince(resetsAt)) <= 300,
              usage.totalTokens > 0
        else { return nil }

        let cycleStart = resetsAt.addingTimeInterval(-TimeInterval(windowMinutes * 60))
        guard observedAt >= cycleStart else { return nil }
        let tokensPerPercent = Double(usage.totalTokens) / window.clampedUsedPercent
        guard tokensPerPercent.isFinite,
              tokensPerPercent > 0,
              tokensPerPercent <= Double(Int64.max) / 100
        else { return nil }

        let total = Int64((tokensPerPercent * 100).rounded())
        let remaining = Int64((tokensPerPercent * window.remainingPercent).rounded())
        let confidence: QuotaForecastConfidence = window.clampedUsedPercent >= 10 && usage.sessionCount >= 3
            ? .medium
            : .low
        return QuotaCapacityEstimate(
            estimatedTotalTokens: total,
            estimatedRemainingTokens: remaining,
            tokensPerPercent: tokensPerPercent,
            samplePairCount: 0,
            observationSpan: min(observedAt, usage.observedAt).timeIntervalSince(cycleStart),
            confidence: confidence,
            evidence: .currentCycleLocalLedger,
            observedTokens: usage.totalTokens
        )
    }

    private func matchingCycleSamples(
        for current: QuotaUsageSample,
        in samples: [QuotaUsageSample]
    ) -> [QuotaUsageSample] {
        let maximumAge = TimeInterval(max(current.windowMinutes ?? 10_080, 60) * 60)
        return samples.filter { sample in
            guard sample.accountID == current.accountID,
                  sample.windowID == current.windowID,
                  sample.observedAt <= current.observedAt,
                  current.observedAt.timeIntervalSince(sample.observedAt) <= maximumAge
            else { return false }

            switch (current.resetsAt, sample.resetsAt) {
            case let (lhs?, rhs?):
                return abs(lhs.timeIntervalSince(rhs)) <= 300
            case (nil, nil):
                return true
            default:
                return false
            }
        }
    }

    private func deduplicated(_ samples: [QuotaUsageSample]) -> [QuotaUsageSample] {
        var result: [QuotaUsageSample] = []
        for sample in samples {
            if let last = result.last,
               abs(sample.observedAt.timeIntervalSince(last.observedAt)) < 1 {
                result[result.count - 1] = sample
            } else {
                result.append(sample)
            }
        }
        return Array(result.suffix(64))
    }

    private func monotonicSuffix(_ samples: [QuotaUsageSample]) -> [QuotaUsageSample] {
        guard samples.count > 1 else { return samples }
        var start = samples.startIndex
        for index in samples.indices.dropFirst() {
            let previous = samples[samples.index(before: index)]
            let current = samples[index]
            let tokenRegression: Bool
            if let previousTokens = previous.lifetimeTokens, let currentTokens = current.lifetimeTokens {
                tokenRegression = currentTokens < previousTokens
            } else {
                tokenRegression = false
            }
            if current.usedPercent + 0.5 < previous.usedPercent || tokenRegression {
                start = index
            }
        }
        return Array(samples[start...])
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private func observedDelta(in samples: [QuotaUsageSample]) -> Double {
        guard let first = samples.first, let last = samples.last else { return 0 }
        return max(0, last.usedPercent - first.usedPercent)
    }

    /// Median of all positive pairwise slopes is resistant to one delayed or
    /// rounded quota sample while retaining a direct, reproducible calculation.
    private func robustPositiveSlopePercentPerHour(in samples: [QuotaUsageSample]) -> Double? {
        var slopes: [Double] = []
        for left in samples.indices {
            for right in samples.indices where right > left {
                let seconds = samples[right].observedAt.timeIntervalSince(samples[left].observedAt)
                let delta = samples[right].usedPercent - samples[left].usedPercent
                guard seconds >= minimumObservationSpan, delta > 0 else { continue }
                slopes.append(delta / seconds * 3_600)
            }
        }
        guard !slopes.isEmpty else { return nil }
        slopes.sort()
        let middle = slopes.count / 2
        if slopes.count.isMultiple(of: 2) {
            return (slopes[middle - 1] + slopes[middle]) / 2
        }
        return slopes[middle]
    }

    private func confidence(sampleCount: Int, span: TimeInterval, delta: Double) -> QuotaForecastConfidence {
        if sampleCount >= 8, span >= 2 * 3_600, delta >= 5 { return .high }
        if sampleCount >= 4, span >= 30 * 60, delta >= 1 { return .medium }
        return .low
    }
}
