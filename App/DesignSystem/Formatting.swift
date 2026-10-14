import Foundation

extension TimeInterval {
    /// "1 hr, 5 min" / "1 Std., 5 Min."
    var durationText: String {
        Duration.seconds(self).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
    }

    /// "1:05:12" / "5:12" for the player.
    var clockText: String {
        Duration.seconds(self.rounded(.down)).formatted(.time(pattern: self >= 3_600 ? .hourMinuteSecond : .minuteSecond))
    }
}

extension Double {
    /// Playback speed: "1.5×" / "1,5×".
    var speedText: String {
        String(localized: "\(self.formatted(.number.precision(.fractionLength(1))))×")
    }
}

extension TimeInterval {
    /// Short settings values: "45 sec" / "1 min, 30 sec" ("45 Sek." / "1 Min., 30 Sek.").
    var secondsText: String {
        Duration.seconds(self).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated))
    }
}
