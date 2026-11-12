import Foundation

/// Per-agent screen fingerprints for Working agents, to say "no output for 10m". Holds hashes and times only,
/// never screen text. The store decides when to check; this decides who is due and what the results mean.
struct NoOutputWatch {
    struct Entry {
        /// Changes whenever the agent (re)enters Working, so a check started before that is thrown away.
        var id: Int
        var hash: Int?
        /// When the current hash was first seen.
        var since: Date?
        /// Last good check that saw the screen (failed checks confirm nothing).
        var confirmed: Date?
        /// Last check, good or not: paces the next one.
        var lastCheck: Date
        var failures = 0
        /// The check in flight (its number and start), if any.
        var attempt = 0
        var checkStarted: Date?
    }

    /// Identifies one check, so a late or abandoned one can't land.
    struct Ticket: Equatable {
        var address: String
        var id: Int
        var attempt: Int
    }

    private(set) var entries: [String: Entry] = [:]
    private var nextID = 0

    /// Keeps one entry per Working agent. A new one waits a full interval before its first check, so short
    /// turns never cost a read.
    mutating func sync(working: Set<String>, now: Date) {
        entries = entries.filter { working.contains($0.key) }
        for address in working where entries[address] == nil {
            nextID += 1
            entries[address] = Entry(id: nextID, lastCheck: now)
        }
    }

    mutating func removeAll() { entries.removeAll() }

    /// The agent waiting longest past its interval, if any. A check still unanswered after two intervals is
    /// given up as failed, so a read that never returns doesn't stop the checks.
    mutating func takeDue(now: Date, interval: TimeInterval) -> Ticket? {
        for (address, entry) in entries {
            if let started = entry.checkStarted, now.timeIntervalSince(started) >= 2 * interval {
                entries[address]?.checkStarted = nil
                entries[address]?.failures += 1
                entries[address]?.lastCheck = now
            }
        }
        let due = entries.filter { $0.value.checkStarted == nil && now.timeIntervalSince($0.value.lastCheck) >= interval }
        guard let (address, entry) = due.min(by: { $0.value.lastCheck < $1.value.lastCheck }) else { return nil }
        entries[address]?.attempt += 1
        entries[address]?.checkStarted = now
        return Ticket(address: address, id: entry.id, attempt: entry.attempt + 1)
    }

    /// A check's result: a fingerprint, or nil when the read failed. A failure neither resets the count nor
    /// confirms anything.
    mutating func record(_ ticket: Ticket, hash: Int?, now: Date) {
        guard var entry = entries[ticket.address], entry.id == ticket.id, entry.attempt == ticket.attempt,
              entry.checkStarted != nil else { return }
        entry.checkStarted = nil
        entry.lastCheck = now
        if let hash {
            entry.failures = 0
            entry.confirmed = now
            if hash != entry.hash {
                entry.hash = hash
                entry.since = now
            }
        } else {
            entry.failures += 1
        }
        entries[ticket.address] = entry
    }

    /// Since when the screen hasn't changed, once good checks confirmed it for `threshold`; nil after two
    /// failed checks in a row.
    func quietSince(_ address: String, threshold: TimeInterval) -> Date? {
        guard let entry = entries[address], entry.failures < 2, let since = entry.since, let confirmed = entry.confirmed,
              confirmed.timeIntervalSince(since) >= threshold else { return nil }
        return since
    }
}
