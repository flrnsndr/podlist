import Foundation
import Testing
@testable import PodlistKit

/// Why a feed could not be loaded, as the OPML import names it (Slice 4). The cases come from a
/// real-network import: 404, a URL that redirects to an HTML page, a certificate for another host.
struct FeedFailureReasonTests {
    @Test(arguments: [
        (FeedLoadError.http(status: 404), FeedFailureReason.notFound),
        (FeedLoadError.http(status: 410), .notFound),
        (FeedLoadError.http(status: 401), .accessDenied),
        (FeedLoadError.http(status: 403), .accessDenied),
        (FeedLoadError.http(status: 500), .httpStatus(500)),
        (FeedLoadError.http(status: 503), .httpStatus(503)),
        (FeedLoadError.notHTTP, .other),
    ] as [(FeedLoadError, FeedFailureReason)])
    func httpErrors(error: FeedLoadError, reason: FeedFailureReason) {
        #expect(FeedFailureReason(error) == reason)
    }

    @Test func parserErrors() {
        #expect(FeedFailureReason(FeedParserError.notAFeed) == .notAFeed)
        #expect(FeedFailureReason(FeedParserError.malformed("line 3")) == .malformedFeed)
        #expect(FeedFailureReason(FeedRefreshError.invalidURL) == .invalidURL)
        #expect(FeedFailureReason(FeedRefreshError.unexpectedNotModified) == .other)
    }

    @Test(arguments: [
        (URLError.Code.serverCertificateHasBadDate, FeedFailureReason.invalidCertificate),
        (.serverCertificateUntrusted, .invalidCertificate),
        (.serverCertificateHasUnknownRoot, .invalidCertificate),
        (.serverCertificateNotYetValid, .invalidCertificate),
        (.clientCertificateRejected, .invalidCertificate),
        (.secureConnectionFailed, .invalidCertificate),
        (.appTransportSecurityRequiresSecureConnection, .insecureConnection),
        (.cannotFindHost, .serverNotFound),
        (.cannotConnectToHost, .serverNotFound),
        (.dnsLookupFailed, .serverNotFound),
        (.notConnectedToInternet, .offline),
        (.networkConnectionLost, .offline),
        (.dataNotAllowed, .offline),
        (.timedOut, .timedOut),
        (.badURL, .invalidURL),
        (.unsupportedURL, .invalidURL),
        (.cancelled, .other),
    ] as [(URLError.Code, FeedFailureReason)])
    func urlErrors(code: URLError.Code, reason: FeedFailureReason) {
        #expect(FeedFailureReason(URLError(code)) == reason)
    }

    /// The import logged `NSURLErrorDomain -1202` (certificate for another host): an `NSError`,
    /// not a `URLError` value.
    @Test func nsErrorFromTheURLDomain() {
        let error = NSError(domain: NSURLErrorDomain, code: -1202)
        #expect(FeedFailureReason(error) == .invalidCertificate)
    }

    @Test func unknownErrors() {
        struct Unknown: Error {}
        #expect(FeedFailureReason(Unknown()) == .other)
        #expect(FeedFailureReason(NSError(domain: NSCocoaErrorDomain, code: 4)) == .other)
    }
}
