import WebKit

extension WKWebView {
    /// Thay cho `callAsyncJavaScript(_:arguments:contentWorld:) async` của Swift. Bản async đó nằm ở
    /// libswiftWebKit.dylib (SDK iOS 26 tách riêng), iOS < 26 không có file này → dyld giết app ngay lúc
    /// mở (CI simulator iOS 18.5 crash từ commit 6cf4d19). Gọi thẳng method Objective-C thì không kéo
    /// thư viện đó vào. Chạy trong world `.page` như cũ; body được bọc async function nên dùng
    /// được `await`/`return`.
    @MainActor
    func goiJS(_ body: String, arguments: [String: Any] = [:]) async throws -> Any? {
        try await withCheckedThrowingContinuation { cont in
            __callAsyncJavaScript(body, arguments: arguments, inFrame: nil, in: .page) { value, error in
                if let error { cont.resume(throwing: error) } else { cont.resume(returning: value) }
            }
        }
    }
}
