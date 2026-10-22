import CloudKit
import Foundation
import UIKit

/// CloudKit relay between the dog camera and the owner's phone. No server of
/// our own: records live in the owner's iCloud (private database, custom zone),
/// and a second iCloud account joins through a zone-wide CKShare.
///
/// Records in the zone:
/// - `LinkControl/control`   owner → camera commands (start / stop)
/// - `LinkStatus/status`     camera heartbeat (armed / running, battery, level)
/// - `LinkSnapshot/snapshot` latest camera frame for the near-live view
/// - `DistressEvent/<uuid>`  one per detected sign; creation triggers a push
@MainActor
final class CloudRelay {
    enum RelayError: LocalizedError {
        case noAccount
        case shareUnavailable
        case notLinked

        var errorDescription: String? {
            switch self {
            case .noAccount: String(localized: "iCloud isn't available on this device. Sign in to iCloud in Settings to get alerts away from home.")
            case .shareUnavailable: String(localized: "That pairing code has expired. Show a new code on your phone and scan it again.")
            case .notLinked: String(localized: "This device isn't paired yet.")
            }
        }
    }

    struct Control: Equatable, Sendable {
        enum Command: String, Sendable {
            case start
            case stop
        }

        var command: Command
        var start: LinkSessionStart?
        var sessionID: UUID?
        var issuedAt: Date
    }

    struct OwnerPoll: Sendable {
        var events: [LinkEvent] = []
        var status: LinkStatus?
        var snapshot: (image: UIImage, takenAt: Date, sessionID: UUID?)?
        var token: CKServerChangeToken?
    }

    static let zonePrefix = "StayLink-"
    static let distressSubscriptionID = "stay-distress-events"

    private lazy var container: CKContainer = {
        let identifier = Bundle.main.object(forInfoDictionaryKey: "StayICloudContainer") as? String
        if let identifier, !identifier.isEmpty, !identifier.contains("$(") {
            return CKContainer(identifier: identifier)
        }
        return CKContainer.default()
    }()

    func isAccountAvailable() async -> Bool {
        (try? await container.accountStatus()) == .available
    }

    // MARK: Owner side

    /// Creates the link zone and a zone-wide share the camera can join.
    func prepareOwnerLink(linkID: String) async throws -> DeviceLink {
        guard await isAccountAvailable() else { throw RelayError.noAccount }
        let database = container.privateCloudDatabase
        let zone = CKRecordZone(zoneName: Self.zonePrefix + linkID)
        _ = try await database.modifyRecordZones(saving: [zone], deleting: [])

        let share = CKShare(recordZoneID: zone.zoneID)
        share[CKShare.SystemFieldKey.title] = String(localized: "Stay dog camera") as CKRecordValue
        share.publicPermission = .readWrite
        let result = try await database.modifyRecords(saving: [share], deleting: [], savePolicy: .allKeys)
        var shareURL: URL?
        if case .success(let saved)? = result.saveResults[share.recordID], let savedShare = saved as? CKShare {
            shareURL = savedShare.url
        }
        await installOwnerSubscription(zoneID: zone.zoneID)
        return DeviceLink(linkID: linkID, database: .privateDB, zoneName: zone.zoneID.zoneName, zoneOwnerName: nil, shareURL: shareURL)
    }

    /// Push alert for every new distress event, even when Stay isn't running.
    func installOwnerSubscription(zoneID: CKRecordZone.ID) async {
        let subscription = CKQuerySubscription(
            recordType: "DistressEvent",
            predicate: NSPredicate(value: true),
            subscriptionID: Self.distressSubscriptionID,
            options: [.firesOnRecordCreation]
        )
        subscription.zoneID = zoneID
        let info = CKSubscription.NotificationInfo()
        info.titleLocalizationKey = "ALERT_DISTRESS_TITLE"
        info.titleLocalizationArgs = ["dogName"]
        info.alertLocalizationKey = "ALERT_DISTRESS_BODY"
        info.alertLocalizationArgs = ["kindTitle"]
        info.soundName = "default"
        info.shouldSendContentAvailable = true
        info.category = "DISTRESS"
        subscription.notificationInfo = info
        _ = try? await container.privateCloudDatabase.modifySubscriptions(saving: [subscription], deleting: [])
    }

    func sendStart(_ start: LinkSessionStart, link: DeviceLink) async {
        let record = CKRecord(recordType: "LinkControl", recordID: CKRecord.ID(recordName: "control", zoneID: zoneID(link)))
        record["command"] = Control.Command.start.rawValue
        record["sessionID"] = start.sessionID.uuidString
        record["dogName"] = start.dogName
        record["targetSeconds"] = start.targetSeconds
        record["sensitivity"] = start.sensitivity.rawValue
        record["startedAt"] = start.startedAt
        record["issuedAt"] = Date.now
        await save([record], link: link)
    }

    func sendStop(sessionID: UUID, link: DeviceLink) async {
        let record = CKRecord(recordType: "LinkControl", recordID: CKRecord.ID(recordName: "control", zoneID: zoneID(link)))
        record["command"] = Control.Command.stop.rawValue
        record["sessionID"] = sessionID.uuidString
        record["issuedAt"] = Date.now
        await save([record], link: link)
    }

    /// Fetches everything new in the zone and deletes processed events.
    func pollOwner(link: DeviceLink, since token: CKServerChangeToken?) async -> OwnerPoll {
        let database = database(for: link)
        var poll = OwnerPoll(token: token)
        do {
            var more = true
            var current = token
            var processed: [CKRecord.ID] = []
            while more {
                let changes = try await database.recordZoneChanges(inZoneWith: zoneID(link), since: current)
                for (_, result) in changes.modificationResultsByID {
                    guard case .success(let modification) = result else { continue }
                    let record = modification.record
                    switch record.recordType {
                    case "DistressEvent":
                        if let event = Self.event(from: record) { poll.events.append(event) }
                        processed.append(record.recordID)
                    case "LinkStatus":
                        poll.status = Self.status(from: record)
                    case "LinkSnapshot":
                        if let asset = record["image"] as? CKAsset, let url = asset.fileURL,
                           let image = UIImage(contentsOfFile: url.path) {
                            let sessionID = (record["sessionID"] as? String).flatMap(UUID.init(uuidString:))
                            poll.snapshot = (image, record["takenAt"] as? Date ?? .now, sessionID)
                        }
                    default:
                        break
                    }
                }
                current = changes.changeToken
                more = changes.moreComing
            }
            poll.token = current
            if !processed.isEmpty {
                _ = try? await database.modifyRecords(saving: [], deleting: processed)
            }
        } catch {
            // A zone that no longer exists means the link was removed elsewhere.
        }
        return poll
    }

    // MARK: Camera side

    /// Resolves a scanned pairing code into a link, joining the share if the
    /// camera uses a different iCloud account from the owner.
    func joinLink(_ payload: PairingPayload) async throws -> DeviceLink {
        let zoneName = Self.zonePrefix + payload.linkID
        guard await isAccountAvailable() else {
            return DeviceLink(linkID: payload.linkID, database: .nearbyOnly, zoneName: zoneName, partnerName: payload.ownerName)
        }
        if let shareURL = payload.shareURL {
            let metadata = try await container.shareMetadata(for: shareURL)
            if metadata.participantRole == .owner {
                return DeviceLink(linkID: payload.linkID, database: .privateDB, zoneName: zoneName, shareURL: shareURL, partnerName: payload.ownerName)
            }
            _ = try await container.accept(metadata)
            let zoneID = metadata.share.recordID.zoneID
            return DeviceLink(linkID: payload.linkID, database: .sharedDB, zoneName: zoneID.zoneName, zoneOwnerName: zoneID.ownerName, shareURL: shareURL, partnerName: payload.ownerName)
        }
        // Typed code: works when both devices share an iCloud account.
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        if (try? await container.privateCloudDatabase.recordZone(for: zoneID)) != nil {
            return DeviceLink(linkID: payload.linkID, database: .privateDB, zoneName: zoneName, partnerName: payload.ownerName)
        }
        return DeviceLink(linkID: payload.linkID, database: .nearbyOnly, zoneName: zoneName, partnerName: payload.ownerName)
    }

    func fetchControl(link: DeviceLink) async -> Control? {
        guard link.database != .nearbyOnly else { return nil }
        let id = CKRecord.ID(recordName: "control", zoneID: zoneID(link))
        guard let record = try? await database(for: link).record(for: id),
              let raw = record["command"] as? String, let command = Control.Command(rawValue: raw) else { return nil }
        let sessionID = (record["sessionID"] as? String).flatMap(UUID.init(uuidString:))
        var start: LinkSessionStart?
        if command == .start, let sessionID {
            start = LinkSessionStart(
                sessionID: sessionID,
                dogName: record["dogName"] as? String ?? "",
                targetSeconds: record["targetSeconds"] as? Double ?? 0,
                sensitivity: (record["sensitivity"] as? String).flatMap(DetectionSensitivity.init(rawValue:)) ?? .balanced,
                startedAt: record["startedAt"] as? Date ?? .now
            )
        }
        return Control(command: command, start: start, sessionID: sessionID, issuedAt: record["issuedAt"] as? Date ?? .distantPast)
    }

    func postStatus(_ status: LinkStatus, link: DeviceLink) async {
        guard link.database != .nearbyOnly else { return }
        let record = CKRecord(recordType: "LinkStatus", recordID: CKRecord.ID(recordName: "status", zoneID: zoneID(link)))
        record["state"] = status.state.rawValue
        record["sessionID"] = status.sessionID?.uuidString
        record["elapsed"] = status.elapsed
        record["level"] = Double(status.level)
        record["batteryLevel"] = Double(status.batteryLevel)
        record["isCharging"] = status.isCharging ? 1 : 0
        record["thermalWarning"] = status.thermalWarning ? 1 : 0
        record["deviceName"] = status.deviceName
        record["sentAt"] = status.sentAt
        await save([record], link: link)
    }

    func postEvent(_ event: LinkEvent, dogName: String, link: DeviceLink) async {
        guard link.database != .nearbyOnly else { return }
        let record = CKRecord(recordType: "DistressEvent", recordID: CKRecord.ID(recordName: event.id.uuidString, zoneID: zoneID(link)))
        record["sessionID"] = event.sessionID.uuidString
        record["offset"] = event.offset
        record["kind"] = event.kind.rawValue
        record["kindTitle"] = event.kind.title
        record["dogName"] = dogName.isEmpty ? String(localized: "Your dog") : dogName
        record["confidence"] = event.confidence
        record["duration"] = event.duration
        record["levels"] = event.levels.map(Double.init)
        if let snapshot = event.snapshot, let url = Self.writeTemp(snapshot) {
            record["snapshot"] = CKAsset(fileURL: url)
        }
        await save([record], link: link)
    }

    func postSnapshot(_ jpeg: Data, sessionID: UUID?, link: DeviceLink) async {
        guard link.database != .nearbyOnly, let url = Self.writeTemp(jpeg) else { return }
        let record = CKRecord(recordType: "LinkSnapshot", recordID: CKRecord.ID(recordName: "snapshot", zoneID: zoneID(link)))
        record["image"] = CKAsset(fileURL: url)
        record["takenAt"] = Date.now
        record["sessionID"] = sessionID?.uuidString
        await save([record], link: link)
    }

    // MARK: Helpers

    private func database(for link: DeviceLink) -> CKDatabase {
        link.database == .sharedDB ? container.sharedCloudDatabase : container.privateCloudDatabase
    }

    private func zoneID(_ link: DeviceLink) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: link.zoneName, ownerName: link.zoneOwnerName ?? CKCurrentUserDefaultName)
    }

    private func save(_ records: [CKRecord], link: DeviceLink) async {
        _ = try? await database(for: link).modifyRecords(saving: records, deleting: [], savePolicy: .allKeys)
    }

    private static func writeTemp(_ data: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    private static func event(from record: CKRecord) -> LinkEvent? {
        guard let id = UUID(uuidString: record.recordID.recordName),
              let session = (record["sessionID"] as? String).flatMap(UUID.init(uuidString:)),
              let kind = (record["kind"] as? String).flatMap(DistressKind.init(rawValue:)) else { return nil }
        var snapshot: Data?
        if let asset = record["snapshot"] as? CKAsset, let url = asset.fileURL {
            snapshot = try? Data(contentsOf: url)
        }
        return LinkEvent(
            id: id,
            sessionID: session,
            offset: record["offset"] as? Double ?? 0,
            kind: kind,
            confidence: record["confidence"] as? Double ?? 0.5,
            duration: record["duration"] as? Double ?? 1,
            levels: (record["levels"] as? [Double] ?? []).map(Float.init),
            snapshot: snapshot
        )
    }

    private static func status(from record: CKRecord) -> LinkStatus? {
        guard let state = (record["state"] as? String).flatMap(LinkStatus.State.init(rawValue:)) else { return nil }
        return LinkStatus(
            state: state,
            sessionID: (record["sessionID"] as? String).flatMap(UUID.init(uuidString:)),
            elapsed: record["elapsed"] as? Double ?? 0,
            level: Float(record["level"] as? Double ?? 0),
            batteryLevel: Float(record["batteryLevel"] as? Double ?? -1),
            isCharging: (record["isCharging"] as? Int ?? 0) == 1,
            thermalWarning: (record["thermalWarning"] as? Int ?? 0) == 1,
            deviceName: record["deviceName"] as? String ?? "",
            sentAt: record["sentAt"] as? Date ?? .now
        )
    }
}
