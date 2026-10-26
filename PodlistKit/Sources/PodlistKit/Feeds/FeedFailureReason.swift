import Foundation

/// Why a feed could not be loaded, in terms the user can act on (the OPML import names it
/// for every podcast that failed).
public enum FeedFailureReason: Hashable, Sendable {
    /// HTTP 404 or 410.
    case notFound
    /// HTTP 401 or 403 (private feed, login needed).
    case accessDenied
    /// Any other HTTP error status.
    case httpStatus(Int)
    /// The URL delivers something else, e.g. an HTML page after a redirect.
    case notAFeed
    /// Looks like XML but is broken.
    case malformedFeed
    /// The server's certificate is invalid (expired, untrusted, for another host) or TLS failed.
    case invalidCertificate
    /// The feed is only reachable over plain `http` (A11).
    case insecureConnection
    /// The host does not exist or does not answer.
    case serverNotFound
    case offline
    case timedOut
    case invalidURL
    case other

    public init(_ error: any Error) {
        switch error {
        case FeedLoadError.http(let status):
            switch status {
            case 404, 410: self = .notFound
            case 401, 403: self = .accessDenied
            default: self = .httpStatus(status)
            }
        case FeedParserError.notAFeed:
            self = .notAFeed
        case FeedParserError.malformed:
            self = .malformedFeed
        case ARDSoundsError.notFound:
            self = .notFound
        case ARDSoundsError.malformed:
            self = .notAFeed
        case FeedRefreshError.invalidURL:
            self = .invalidURL
        case let error as URLError:
            self = Self.reason(for: error.code)
        default:
            self = .other
        }
    }

    private static func reason(for code: URLError.Code) -> FeedFailureReason {
        switch code {
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected,
             .clientCertificateRequired:
            .invalidCertificate
        case .appTransportSecurityRequiresSecureConnection:
            .insecureConnection
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            .serverNotFound
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            .offline
        case .timedOut:
            .timedOut
        case .badURL, .unsupportedURL:
            .invalidURL
        default:
            .other
        }
    }
}
