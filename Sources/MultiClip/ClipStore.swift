import Foundation
import CryptoKit
import SQLite3

protocol ClipStore: AnyObject {
    func loadAll() -> [Clip]
    func upsert(_ clip: Clip)
    func delete(id: UUID)
    func clear()
}

// MARK: - Paths

enum StorePaths {
    static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("MultiClip", isDirectory: true)
    }
    static var jsonHistoryURL: URL { supportDir.appendingPathComponent("history.json") }
    static var sqliteURL: URL { supportDir.appendingPathComponent("history.sqlite") }

    static func ensureDir() {
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    }
}

// MARK: - JSON file store (default, unencrypted)

final class FileClipStore: ClipStore {
    private let url: URL
    private let queue = DispatchQueue(label: "clip.filestore")

    init(url: URL = StorePaths.jsonHistoryURL) {
        self.url = url
    }

    func loadAll() -> [Clip] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        if let clips = try? JSONDecoder().decode([Clip].self, from: data) {
            return clips
        }
        // Legacy migration: history.json used to be [String].
        if let strings = try? JSONDecoder().decode([String].self, from: data) {
            return strings.map { Clip(kind: .text, text: $0) }
        }
        return []
    }

    func upsert(_ clip: Clip) { writeAll(mergeIn: clip) }

    func delete(id: UUID) {
        queue.sync {
            var clips = loadAll()
            clips.removeAll { $0.id == id }
            persist(clips)
        }
    }

    func clear() {
        queue.sync { persist([]) }
    }

    /// Bulk replace — used by the monitor after applying eviction rules.
    func replaceAll(_ clips: [Clip]) {
        queue.sync { persist(clips) }
    }

    private func writeAll(mergeIn clip: Clip) {
        queue.sync {
            var clips = loadAll()
            if let idx = clips.firstIndex(where: { $0.id == clip.id }) {
                clips[idx] = clip
            } else {
                clips.insert(clip, at: 0)
            }
            persist(clips)
        }
    }

    private func persist(_ clips: [Clip]) {
        StorePaths.ensureDir()
        guard let data = try? JSONEncoder().encode(clips) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - Encrypted SQLite store (opt-in)

final class SQLiteClipStore: ClipStore {
    private var db: OpaquePointer?
    private let key: SymmetricKey
    private let queue = DispatchQueue(label: "clip.sqlite")

    init(url: URL = StorePaths.sqliteURL, passphrase: String) throws {
        StorePaths.ensureDir()
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else {
            throw NSError(domain: "MultiClip.SQLite", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not open SQLite database"])
        }
        self.db = handle
        let digest = SHA256.hash(data: Data(passphrase.utf8))
        self.key = SymmetricKey(data: Data(digest))
        try exec("""
            CREATE TABLE IF NOT EXISTS clips (
                id TEXT PRIMARY KEY,
                captured_at REAL NOT NULL,
                nonce BLOB NOT NULL,
                payload BLOB NOT NULL
            );
        """)
        try exec("CREATE INDEX IF NOT EXISTS idx_captured ON clips(captured_at DESC);")
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    func loadAll() -> [Clip] {
        queue.sync {
            var out: [Clip] = []
            let sql = "SELECT nonce, payload FROM clips ORDER BY captured_at DESC;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                let nonce = blob(stmt, column: 0)
                let payload = blob(stmt, column: 1)
                if let clip = decrypt(nonce: nonce, payload: payload) {
                    out.append(clip)
                }
            }
            return out
        }
    }

    func upsert(_ clip: Clip) {
        queue.sync {
            guard let (nonce, payload) = encrypt(clip) else { return }
            let sql = """
                INSERT INTO clips (id, captured_at, nonce, payload)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    captured_at = excluded.captured_at,
                    nonce = excluded.nonce,
                    payload = excluded.payload;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            let idStr = clip.id.uuidString
            sqlite3_bind_text(stmt, 1, (idStr as NSString).utf8String, -1, nil)
            sqlite3_bind_double(stmt, 2, clip.capturedAt.timeIntervalSince1970)
            nonce.withUnsafeBytes { buf in
                _ = sqlite3_bind_blob(stmt, 3, buf.baseAddress, Int32(buf.count), SQLITE_TRANSIENT)
            }
            payload.withUnsafeBytes { buf in
                _ = sqlite3_bind_blob(stmt, 4, buf.baseAddress, Int32(buf.count), SQLITE_TRANSIENT)
            }
            _ = sqlite3_step(stmt)
        }
    }

    func delete(id: UUID) {
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "DELETE FROM clips WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            let s = id.uuidString
            sqlite3_bind_text(stmt, 1, (s as NSString).utf8String, -1, nil)
            _ = sqlite3_step(stmt)
        }
    }

    func clear() {
        queue.sync { _ = try? exec("DELETE FROM clips;") }
    }

    // MARK: helpers

    private func exec(_ sql: String) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errMsg)
            throw NSError(domain: "MultiClip.SQLite", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }

    private func blob(_ stmt: OpaquePointer?, column: Int32) -> Data {
        guard let ptr = sqlite3_column_blob(stmt, column) else { return Data() }
        let len = Int(sqlite3_column_bytes(stmt, column))
        return Data(bytes: ptr, count: len)
    }

    private func encrypt(_ clip: Clip) -> (nonce: Data, payload: Data)? {
        guard let plaintext = try? JSONEncoder().encode(clip) else { return nil }
        let nonce = AES.GCM.Nonce()
        guard let sealed = try? AES.GCM.seal(plaintext, using: key, nonce: nonce) else { return nil }
        // Payload = ciphertext || tag; nonce stored separately.
        return (Data(nonce), sealed.ciphertext + sealed.tag)
    }

    private func decrypt(nonce: Data, payload: Data) -> Clip? {
        guard payload.count >= 16 else { return nil }
        let tag = payload.suffix(16)
        let cipher = payload.prefix(payload.count - 16)
        guard let nonceObj = try? AES.GCM.Nonce(data: nonce),
              let sealed = try? AES.GCM.SealedBox(nonce: nonceObj, ciphertext: cipher, tag: tag),
              let plain = try? AES.GCM.open(sealed, using: key) else { return nil }
        return try? JSONDecoder().decode(Clip.self, from: plain)
    }
}

// SQLITE_TRANSIENT is a macro in C; recreate the sentinel Swift needs.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
