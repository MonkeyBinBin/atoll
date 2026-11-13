import Foundation

/// "Still waiting" reminders: one timer per live Needs-you episode, firing once `delay` after the episode was
/// first seen here (so a snapshot carrying an old `waitingSince` doesn't remind the moment it arrives), and
/// never twice for the same episode.
@MainActor
final class WaitingReminderTracker {
    private struct Entry {
        /// The episode the pending timer is for.
        var pending: Date?
        var timer: ScheduledAction?
        /// The last episode reminded (or skipped).
        var reminded: Date?
    }

    /// nil turns reminders off; a change drops the pending ones (the next `sync` reschedules).
    var delay: TimeInterval? {
        didSet {
            guard delay != oldValue else { return }
            for address in entries.keys { cancelPending(address) }
        }
    }
    /// Asked when a timer fires: is the agent still in that episode?
    var isStillWaiting: @MainActor (_ address: String, _ episode: Date) -> Bool = { _, _ in false }
    /// The episode outlasted `delay` (and is now marked reminded).
    var onDue: @MainActor (_ address: String, _ episode: Date) -> Void = { _, _ in }

    private let scheduler: IslandScheduler
    private var entries: [String: Entry] = [:]

    init(scheduler: IslandScheduler) {
        self.scheduler = scheduler
    }

    var addresses: some Collection<String> { entries.keys }

    /// `waiting`: the visible Needs-you agents and their episodes. `waitingSince`: any known agent's episode,
    /// offline ones included, so a reconnect doesn't re-remind the same episode.
    func sync(waiting: [String: Date], waitingSince: (String) -> Date?) {
        let waiting = delay == nil ? [:] : waiting
        for (address, entry) in entries {
            if let pending = entry.pending, waiting[address] != pending { cancelPending(address) }
            if let reminded = entry.reminded, waitingSince(address) != reminded { entries[address]?.reminded = nil }
            if entries[address]?.pending == nil, entries[address]?.reminded == nil { entries[address] = nil }
        }
        guard let delay else { return }
        for (address, since) in waiting where entries[address]?.pending != since && entries[address]?.reminded != since {
            entries[address]?.timer?.cancel()
            let timer = scheduler.schedule(after: delay) { [weak self] in
                self?.fire(address, episode: since)
            }
            entries[address, default: Entry()].pending = since
            entries[address]?.timer = timer
        }
    }

    func remove(_ address: String) {
        entries.removeValue(forKey: address)?.timer?.cancel()
    }

    private func cancelPending(_ address: String) {
        entries[address]?.timer?.cancel()
        entries[address]?.timer = nil
        entries[address]?.pending = nil
    }

    private func fire(_ address: String, episode: Date) {
        entries[address]?.pending = nil
        entries[address]?.timer = nil
        guard isStillWaiting(address, episode) else { return }
        entries[address]?.reminded = episode
        onDue(address, episode)
    }
}
