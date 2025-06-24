#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A preference level for transport selection properties.
///
/// Preference values are used to express the level of preference for a given
/// property during protocol and path selection, as defined in RFC 9622 §6.2.
///
/// Most Selection Properties use the Preference enumeration to denote the level
/// of preference for a given property during protocol selection. The Transport
/// Services System uses these preferences to select appropriate protocols and
/// network paths.
///
/// ## Preference Levels
///
/// The five preference levels form a spectrum from most restrictive to least:
/// - ``prohibit``: Most restrictive - fails if property is present
/// - ``avoid``: Prefers absence but proceeds if necessary
/// - ``noPreference``: Neutral - no influence on selection
/// - ``prefer``: Prefers presence but proceeds without
/// - ``require``: Most restrictive - fails if property is absent
///
/// ## Usage
///
/// ```swift
/// let properties = TransportProperties()
/// properties.reliability = .require           // Must have reliable delivery
/// properties.preserveOrder = .prefer         // Prefer ordered delivery
/// properties.multipath = .avoid             // Avoid multipath if possible
/// properties.zeroRTT = .noPreference       // No preference on 0-RTT
/// ```
///
/// ## Selection Behavior
///
/// According to RFC 9622 §6.2, the implementation MUST ensure an outcome
/// consistent with all requirements expressed using ``require`` and ``prohibit``.
/// Preferences expressed using ``prefer`` and ``avoid`` influence selection,
/// but outcomes can vary based on available protocols and paths.
///
/// ## Post-Establishment Behavior
///
/// After a connection is established, Selection Properties become read-only
/// and their Preference type effectively becomes Boolean:
/// - ``require`` and ``prefer`` → true (feature is available)
/// - ``prohibit`` and ``avoid`` → false (feature is not available)
/// - ``noPreference`` → actual availability
///
/// ## Topics
///
/// ### Preference Values
/// - ``prohibit``
/// - ``avoid``
/// - ``noPreference``
/// - ``prefer``
/// - ``require``
public enum Preference: Int, Sendable, CaseIterable {
    /// Select only protocols/paths NOT providing the property; otherwise, fail.
    ///
    /// This is the most restrictive negative preference. The connection
    /// establishment will fail if all available protocols or paths provide
    /// this property.
    case prohibit = 0
    
    /// Prefer protocols/paths NOT providing the property; otherwise, proceed.
    ///
    /// The system will attempt to select options without this property,
    /// but will use options with the property if no alternatives exist.
    case avoid = 1
    
    /// No preference.
    ///
    /// This property does not influence protocol or path selection.
    /// This is the default value for most properties.
    case noPreference = 2
    
    /// Prefer protocols/paths providing the property; otherwise, proceed.
    ///
    /// The system will attempt to select options with this property,
    /// but will proceed without it if necessary.
    case prefer = 3
    
    /// Select only protocols/paths providing the property; otherwise, fail.
    ///
    /// This is the most restrictive positive preference. The connection
    /// establishment will fail if no available protocols or paths provide
    /// this property.
    case require = 4
}

// MARK: - Convenience Properties

extension Preference {
    /// Returns true if this preference mandates a specific behavior.
    ///
    /// Mandatory preferences (``require`` and ``prohibit``) must be
    /// satisfied for connection establishment to succeed.
    public var isMandatory: Bool {
        self == .require || self == .prohibit
    }
    
    /// Returns true if this preference indicates a positive inclination.
    ///
    /// Positive preferences (``require`` and ``prefer``) indicate the
    /// property should be present.
    public var isPositive: Bool {
        self == .require || self == .prefer
    }
    
    /// Returns true if this preference indicates a negative inclination.
    ///
    /// Negative preferences (``prohibit`` and ``avoid``) indicate the
    /// property should be absent.
    public var isNegative: Bool {
        self == .prohibit || self == .avoid
    }
}

// MARK: - CustomStringConvertible

extension Preference: CustomStringConvertible {
    public var description: String {
        switch self {
        case .prohibit: return "Prohibit"
        case .avoid: return "Avoid"
        case .noPreference: return "No Preference"
        case .prefer: return "Prefer"
        case .require: return "Require"
        }
    }
}

// MARK: - Comparable

extension Preference: Comparable {
    /// Compares preferences by their restriction level.
    ///
    /// The ordering from least to most restrictive:
    /// noPreference < avoid < prohibit (for negative preferences)
    /// noPreference < prefer < require (for positive preferences)
    public static func < (lhs: Preference, rhs: Preference) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}