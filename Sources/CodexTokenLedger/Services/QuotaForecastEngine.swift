import Foundation

/// Forecasts quota exhaustion from observed Codex quota percentages.
struct QuotaForecastEngine: Sendable {
    private let minimumObservationSpan: TimeInterval = 120
    private let minimumMeaningfulDelta = 0.10

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
