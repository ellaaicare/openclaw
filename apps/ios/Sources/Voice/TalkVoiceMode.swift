import Foundation

/// Selects the voice engine used by Talk Mode.
///
/// - ``elevenLabsTTS``: Existing pipeline — Apple STT → gateway chat.send → ElevenLabs TTS.
/// - ``grokV2V``: Direct voice-to-voice via Grok Realtime API through the voice proxy.
enum TalkVoiceMode: String, CaseIterable, Sendable {
    case elevenLabsTTS = "elevenlabs"
    case grokV2V = "grok-v2v"

    /// Whether this mode uses the Grok V2V voice proxy.
    var isV2V: Bool { self != .elevenLabsTTS }
}

/// Selects the Grok V2V proxy mode, which controls context depth and memory sync.
enum GrokV2VMode: String, CaseIterable, Sendable {
    case v3Fast = "v3-fast"
    case v3Rich = "v3-rich"
    case v3Live = "v3-live"

    var displayName: String {
        switch self {
        case .v3Fast: "Fast"
        case .v3Rich: "Rich"
        case .v3Live: "Live"
        }
    }

    var description: String {
        switch self {
        case .v3Fast: "Low latency, end-of-session memory sync"
        case .v3Rich: "SOUL.md + Mem0 context, per-turn memory sync"
        case .v3Live: "Rich context + live sync with main agent"
        }
    }
}
