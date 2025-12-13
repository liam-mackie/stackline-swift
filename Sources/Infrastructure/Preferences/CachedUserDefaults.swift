import Foundation

public final class CachedUserDefaults: @unchecked Sendable {
    private let userDefaults: UserDefaults
    private var cache: [String: Any] = [:]
    private let lock = NSLock()

    public init(suiteName: String? = nil) {
        self.userDefaults = suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    public func value<T>(forKey key: String) -> T? {
        lock.lock()
        defer { lock.unlock() }

        if let cachedValue = cache[key] as? T {
            return cachedValue
        }

        let value = userDefaults.object(forKey: key) as? T
        if let value = value {
            cache[key] = value
        }
        return value
    }

    public func set<T>(_ value: T, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }

        cache[key] = value

        if let encodable = value as? any Encodable,
           let data = try? JSONEncoder().encode(AnyEncodable(encodable)) {
            userDefaults.set(data, forKey: key)
        } else {
            userDefaults.set(value, forKey: key)
        }
    }

    public func data(forKey key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }

        if let cachedData = cache[key] as? Data {
            return cachedData
        }

        let data = userDefaults.data(forKey: key)
        if let data = data {
            cache[key] = data
        }
        return data
    }

    public func setData(_ data: Data, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }

        cache[key] = data
        userDefaults.set(data, forKey: key)
    }

    public func bool(forKey key: String, default defaultValue: Bool = false) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if let cachedValue = cache[key] as? Bool {
            return cachedValue
        }

        if userDefaults.object(forKey: key) == nil {
            return defaultValue
        }

        let value = userDefaults.bool(forKey: key)
        cache[key] = value
        return value
    }

    public func setBool(_ value: Bool, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }

        cache[key] = value
        userDefaults.set(value, forKey: key)
    }

    public func double(forKey key: String, default defaultValue: Double = 0) -> Double {
        lock.lock()
        defer { lock.unlock() }

        if let cachedValue = cache[key] as? Double {
            return cachedValue
        }

        if userDefaults.object(forKey: key) == nil {
            return defaultValue
        }

        let value = userDefaults.double(forKey: key)
        cache[key] = value
        return value
    }

    public func setDouble(_ value: Double, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }

        cache[key] = value
        userDefaults.set(value, forKey: key)
    }

    public func string(forKey key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }

        if let cachedValue = cache[key] as? String {
            return cachedValue
        }

        let value = userDefaults.string(forKey: key)
        if let value = value {
            cache[key] = value
        }
        return value
    }

    public func setString(_ value: String, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }

        cache[key] = value
        userDefaults.set(value, forKey: key)
    }

    public func removeObject(forKey key: String) {
        lock.lock()
        defer { lock.unlock() }

        cache.removeValue(forKey: key)
        userDefaults.removeObject(forKey: key)
    }

    public func clearCache() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }

    public func synchronize() {
        userDefaults.synchronize()
    }
}

private struct AnyEncodable: Encodable {
    private let encode: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        self.encode = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try encode(encoder)
    }
}
