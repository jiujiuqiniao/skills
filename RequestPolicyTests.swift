import Foundation

@main
enum RequestPolicyTests {
    static func main() {
        precondition(RequestPolicy.isCancellation(CancellationError()))
        precondition(RequestPolicy.isCancellation(URLError(.cancelled)))
        let wrapped = NSError(domain: "Wrapped", code: 1,
                              userInfo: [NSUnderlyingErrorKey: URLError(.cancelled)])
        precondition(RequestPolicy.isCancellation(wrapped))
        precondition(!RequestPolicy.isCancellation(URLError(.timedOut)))
        precondition(!RequestPolicy.isCancellation(NSError(domain: "Other", code: -999)))
        precondition(!RequestPolicy.isProtectedAudio([:]))
        precondition(!RequestPolicy.isProtectedAudio([
            "encrypt_info": ["encrypt": false, "spade_a": ""], "PlayAuth": "", "Encrypt": 0]))
        precondition(!RequestPolicy.isProtectedAudio(["Encrypt": "0"]))
        precondition(RequestPolicy.isProtectedAudio(["encrypt_info": ["encrypt": true]]))
        precondition(RequestPolicy.isProtectedAudio(["encrypt_info": ["encrypt": 1]]))
        precondition(RequestPolicy.isProtectedAudio(["encrypt_info": ["spade_a": "test-protected"]]))
        precondition(RequestPolicy.isProtectedAudio(["PlayAuth": "test-protected"]))
        precondition(RequestPolicy.isProtectedAudio(["Encrypt": "1"]))
        precondition(RequestPolicy.isProtectedAudio(["Encrypt": "2"]))
        print("PASS: cancellation and protected-audio regression checks")
    }
}
