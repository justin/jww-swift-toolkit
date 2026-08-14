import Foundation

/// Potential errors that can be thrown by the JWWNetworking library.
public enum JWWNetworkError: Error, CustomNSError, CustomStringConvertible {
    /// A string containing the error domain.
    public static let domain: String = "JWWNetworkErrorDomain"

    /// The request requires an API key but one was not provided in the request.
    case missingAPIKey

    /// A request couldn't be generated because a valid access token was unable to be retrieved.
    case authenticationError(any Error)

    /// A request couldn't be generated because the URL was invalid.
    case invalidRequest

    /// A request couldn't be generated because the template is invalid.
    ///
    /// - Parameter template: The invalid template.
    case invalidTemplate(any NetworkRequestTemplate)

    /// An error occurred in the underlying `URLSession` object.
    ///
    /// - Parameter error: The underlying error returned by the `URLSessionTask`.
    case networkError(Error)

    /// The response returned was not of the expected type.
    ///
    /// - Parameter response: Optional, the type of URLResponse returned if the response cannot be parsed into an `HTTPURLResponse`.
    case invalidResponse(URLResponse?)

    /// The request was successful, but the data payload was empty.
    case emptyResponse

    /// The response returned a non-success status code.
    ///
    /// - Parameters:
    ///     - code: The HTTP status code. See [RFC 2616](http://www.ietf.org/rfc/rfc2616.txt) for details.
    ///     - message: The error message associated with the HTTP status code.
    case requestFailed(code: Int, message: String)

    /// The request was successful, but we were unable to decode the JSON payload.
    ///
    /// - Parameters:
    ///     - type: The object type that decoding was attempted for.
    ///     - data: The `Data` payload that decoding was attempted on.
    ///     - error: The underlying `DecodingError` returned during parsing.
    case decodingError(Any.Type, Data, Error)

    /// An error not explicitly defined in JWWNetworking SDK was captured.
    ///
    /// - Parameter error: The underlying error.
    case untypedError(error: Error)

    /// Boolean that returns whether a `JWWNetworkError` is a request error.
    ///
    /// An error is considered a request error if it happens before any network connection is made, and has an error code between 1001 and 1999.
    var isRequestError: Bool {
        1001...1999 ~= errorCode
    }

    /// Boolean that returns whether a `JWWNetworkError` is a response error.
    ///
    /// An error is considered a response error if it happens after network request is made, and has an error code between 2001 and 2999.
    var isResponseError: Bool {
        2001...2999 ~= errorCode
    }

    /// Boolean that returns true if the error returned is because the request was cancelled.
    var isCancellation: Bool {
        switch self {
        case .networkError(let error as URLError) where error.code == .cancelled:
            return true
        default:
            return false
        }
    }

    /// Boolean that returns true if the error returned is capable of being retried.
    var isRetriableError: Bool {
        let retriableErrors: [URLError.Code] = [
            .cannotFindHost,
            .cannotConnectToHost,
            .dnsLookupFailed,
            .networkConnectionLost,
            .timedOut
        ]

        switch self {
        case .networkError(let error as URLError) where retriableErrors.contains(error.code):
            return true
        default:
            return false
        }
    }

    /// Boolean that returns true for any network related issue: either not online or failing to find a host.
    var isNetworkIssue: Bool {
        let codes: [URLError.Code] = [
            .cannotFindHost,
            .cannotConnectToHost,
            .notConnectedToInternet,
            .networkConnectionLost,
            .timedOut,
            .dnsLookupFailed,
            .internationalRoamingOff,
            .callIsActive,
            .dataNotAllowed
        ]

        switch self {
        case .networkError(let error as URLError) where codes.contains(error.code):
            return true
        default:
            return false
        }
    }

    /// Boolean that returns true for any SSL related issue. This is usually related to a VPN or Firewall.
    var isCausedBySSL: Bool {
        let codes: [URLError.Code] = [
            .secureConnectionFailed,
            .serverCertificateHasBadDate,
            .serverCertificateUntrusted,
            .serverCertificateHasUnknownRoot,
            .serverCertificateNotYetValid,
            .clientCertificateRejected,
            .clientCertificateRequired,
            .cannotLoadFromNetwork
        ]

        switch self {
        case .networkError(let error as URLError) where codes.contains(error.code):
            return true
        default:
            return false
        }
    }

    /// The error code.
    ///
    /// Errors with codes from 1001-1999 are considered 'request' errors that happen before we actually send any data to the server.
    ///
    /// Errors with codes from 2001-2999 are considered 'rseponse' errors that happen when we have received a response from the server.
    public var code: Int {
        switch self {
        /*
         JWW: 12/20/22

         Errors with codes from 1001-1999 are considered 'request' errors that happen before we actually send any data to the server.

         Errors with codes from 2001-2999 are considered 'rseponse' errors that happen when we have received a response from the server.

         If you need to add additional code ranges to this type, please discuss to @justin.
         */
        case .missingAPIKey:
            return 1001
        case .invalidRequest:
            return 1002
        case .authenticationError:
            return 1003
        case .invalidTemplate:
            return 1004
        case .networkError:
            return 2001
        case .emptyResponse:
            return 2002
        case .decodingError:
            return 2003
        case .invalidResponse:
            return 2004
        case .requestFailed:
            return 2005
        case .untypedError:
            return -1
        }
    }

    /// The reason for the given error.
    public var message: String {
        let message: String
        switch self {
        case .missingAPIKey:
            message = "Request requires authentication. No API Key provided."
        case .invalidRequest:
            message = "The generated request was invalid."
        case .invalidTemplate(let template):
            message = "The template \(String(describing: template)) was invalid."
        case .authenticationError(let error):
            message = "An error occurred while attempting to authenticate the request. \(error.localizedDescription)"
        case .networkError(let error):
            message = "The network request finished with error: \(error.localizedDescription)"
        case .requestFailed(let code, let errorMessage):
            message = "[\(code)] \(errorMessage)"
        case .invalidResponse(let response):
            let responseType = response != nil ? "type: \(type(of: response!))" : ""
            message = "Response returned was invalid. \(responseType)"
        case .emptyResponse:
            message = "Request returned empty payload response."
        case .decodingError(let type, _, let error):
            if let error = error as? DecodingError {
                let debugDescription = (error as any CustomDebugStringConvertible).debugDescription
                message = "Decoding response data to \(type) failed. \(debugDescription)"
            } else {
                message = "Decoding response data to \(type) failed. \(error.localizedDescription)"
            }
        case .untypedError(error: let error):
            message = "An error not captured by JWWNetworking was returned: \(error.localizedDescription)"
        }

        return message
    }

    /// The user info dictionary.
    public var userInfo: [JWWNetworkErrorUserInfoKey: Any] {
        var userInfo: [JWWNetworkErrorUserInfoKey: Any] = [:]
        userInfo[.messageKey] = String(describing: self)
        switch self {
        case .missingAPIKey:
            break
        case .invalidRequest:
            break
        case .invalidTemplate(let template):
            userInfo[.networkTemplateKey] = template
        case .authenticationError(let error):
            userInfo[.underlyingErrorKey] = error
        case .requestFailed:
            break
        case .invalidResponse(let response):
            userInfo[.responsePayloadKey] = response
        case .networkError(let error):
            userInfo[.underlyingErrorKey] = error
        case .emptyResponse:
            break
        case .decodingError(let type, let data, let error):
            userInfo[.underlyingErrorKey] = error
            userInfo[.decodingErrorTypeKey] = type
            userInfo[.decodingErrorDataKey] = data
        case .untypedError(error: let error):
            userInfo[.underlyingErrorKey] = error
        }

        return userInfo
    }

    // MARK: CustomNSError Conformance
    // ====================================
    // CustomNSError Conformance
    // ====================================

    public var errorCode: Int {
        code
    }

    public var errorUserInfo: [String: Any] {
        Dictionary(uniqueKeysWithValues: userInfo.map { ($0.rawValue, $1) })
    }

    public static var errorDomain: String {
        Self.domain
    }

    public var description: String {
        message
    }
}

extension Error {
    /// Convenience wrapper that can convert any `Error` object into a `JWWNetworkError`.
    ///
    /// If the passed in error is already of type `JWWNetworkError` that value will be returned. Otherwise, an `untypedError` with the original error
    /// set as the associated value will be returned.
    var JWWNetworkError: JWWNetworkError {
        return self as? JWWNetworkError ?? .untypedError(error: self)
    }
}

/// Value type that declares the different payload keys that can be used in a `CustomNSError.userInfo` payload.
@available(iOS 13, macCatalyst 13.0, macOS 10.15, *)
public struct JWWNetworkErrorUserInfoKey: Hashable, Sendable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public extension JWWNetworkErrorUserInfoKey {
    /// `String`. A key that declares the error message.
    static let messageKey = JWWNetworkErrorUserInfoKey(rawValue: NSLocalizedDescriptionKey)

    /// `any Error`. The underlying error received by a system or third-party framework that caused the error.
    static let underlyingErrorKey = JWWNetworkErrorUserInfoKey(rawValue: NSUnderlyingErrorKey)

    /// `Any.Type`. The type that caused the error when parsing or decoding data fails.
    static let decodingErrorTypeKey = JWWNetworkErrorUserInfoKey(rawValue: "JWWDecodingErrorTypeKey")

    /// `Data`. The payload that caused the error when parsing or decoding fails.
    static let decodingErrorDataKey = JWWNetworkErrorUserInfoKey(rawValue: "JWWDecodingErrorDataKey")

    /// `String`. The JSON key that caused a decoding error.
    static let decodingErrorKeyNameKey = JWWNetworkErrorUserInfoKey(rawValue: "JWWDecodingErrorKeyNameKey")

    /// `URLResponse`. The response payload that caused the error.
    static let responsePayloadKey = JWWNetworkErrorUserInfoKey(rawValue: "JWWResponsePayloadKey")

    /// `any NetworkRequest`. The template that caused the error.
    static let networkTemplateKey = JWWNetworkErrorUserInfoKey(rawValue: "JWWNetworkTemplateKey")
}
