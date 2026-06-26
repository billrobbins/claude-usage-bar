import Foundation

enum T {
    static var failures = 0
    static var total = 0

    static func ok(_ cond: Bool, _ name: String, file: StaticString = #file, line: UInt = #line) {
        total += 1
        if cond {
            print("ok   - \(name)")
        } else {
            failures += 1
            print("FAIL - \(name)  (\(file):\(line))")
        }
    }

    static func eq<V: Equatable>(_ a: V, _ b: V, _ name: String, file: StaticString = #file, line: UInt = #line) {
        ok(a == b, "\(name)  [got \(a), want \(b)]", file: file, line: line)
    }

    static func finish() -> Never {
        print("\n\(total - failures)/\(total) passed")
        exit(failures == 0 ? 0 : 1)
    }
}
