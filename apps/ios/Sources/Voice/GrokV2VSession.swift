@preconcurrency import AVFAudio
import Foundation
import OpenClawKit
import OSLog

/// Full-duplex voice-to-voice session via the Ella voice proxy.
///
/// Connects to `wss://voice.ella-ai-care.com/ws` and streams raw PCM16 audio
/// bidirectionally. The proxy handles Grok Realtime API auth, function calling,
/// and memory writeback — iOS just sends/receives audio and parses JSON events.
@MainActor
final class GrokV2VSession {

    // MARK: - Types

    enum State: Sendable, Equatable {
        case idle
        case connecting
        case connected
        case error(String)
    }

    struct TranscriptEvent: Sendable {
        enum Role: String, Sendable { case user, assistant }
        let role: Role
        let text: String
    }

    struct FunctionCallEvent: Sendable {
        let function: String
        let callId: String
        let executed: Bool
    }

    // MARK: - Configuration

    private let uid: String
    private let mode: String
    private let proxyURL: String
    private let proxyKey: String?
    private let pcmPlayer: PCMStreamingAudioPlaying
    private let logger = Logger(subsystem: "ai.openclaw.ios", category: "GrokV2V")

    /// Target PCM format for Grok: 24kHz, 16-bit signed, mono.
    private static let grokSampleRate: Double = 24_000
    private nonisolated static let grokFormat: AVAudioFormat? = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 24_000,
        channels: 1,
        interleaved: true
    )

    // MARK: - State

    private(set) var state: State = .idle {
        didSet { self.onStateChange?(self.state) }
    }

    var onStateChange: ((State) -> Void)?
    var onTranscript: ((TranscriptEvent) -> Void)?
    var onFunctionCall: ((FunctionCallEvent) -> Void)?
    var onSessionEnd: ((String) -> Void)?

    // MARK: - WebSocket

    private var urlSession: URLSession?
    private var wsTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var stopped = false

    // MARK: - Audio

    private var audioEngine: AVAudioEngine?
    private var inputTapInstalled = false
    /// Converter and wsTask are accessed from the audio tap thread via nonisolated helper.
    /// They are set on MainActor before the tap is installed and read atomically.
    private let sendState = AudioSendState()
    private var playbackContinuation: AsyncThrowingStream<Data, Error>.Continuation?
    private var playbackTask: Task<Void, Never>?

    // MARK: - Init

    init(
        uid: String,
        mode: String = "v3",
        proxyURL: String = "wss://voice.ella-ai-care.com/ws",
        proxyKey: String? = nil,
        pcmPlayer: PCMStreamingAudioPlaying
    ) {
        self.uid = uid
        self.mode = mode
        self.proxyURL = proxyURL
        self.proxyKey = proxyKey
        self.pcmPlayer = pcmPlayer
    }

    // MARK: - Lifecycle

    /// Start the V2V session. Installs an audio tap on the provided engine's input node.
    func start(audioEngine: AVAudioEngine) async {
        self.audioEngine = audioEngine
        await self.startWebSocketOnly()
        self.installAudioTap()
    }

    /// Connect WebSocket and start receive loop, but don't install audio tap.
    func startWebSocketOnly() async {
        guard self.state == .idle || self.state != .connecting else { return }
        self.stopped = false
        self.state = .connecting

        var queryString = "\(self.proxyURL)?uid=\(self.uid)&mode=\(self.mode)"
        if let key = self.proxyKey, !key.isEmpty {
            queryString += "&key=\(key)"
        }
        guard let url = URL(string: queryString) else {
            self.state = .error("Invalid proxy URL")
            return
        }

        self.logger.info("connecting to \(url.absoluteString, privacy: .public)")
        GatewayDiagnostics.log("grok-v2v: connecting uid=\(self.uid) mode=\(self.mode)")

        let session = URLSession(configuration: .default)
        self.urlSession = session
        let ws = session.webSocketTask(with: url)
        ws.maximumMessageSize = 4 * 1024 * 1024
        self.wsTask = ws
        ws.resume()

        self.state = .connected
        self.logger.info("websocket connected")
        GatewayDiagnostics.log("grok-v2v: connected")

        self.startReceiveLoop()
    }

    /// Set up the converter for the given hardware format and return a tap block.
    /// The returned block is `nonisolated` and safe to call from the audio render thread.
    func configureConverterAndMakeTapBlock(hwFormat: AVAudioFormat) -> AVAudioNodeTapBlock? {
        guard let targetFormat = Self.grokFormat else {
            self.logger.error("failed to create target audio format")
            return nil
        }
        guard let converter = AVAudioConverter(from: hwFormat, to: targetFormat) else {
            self.logger.error("failed to create audio converter")
            return nil
        }
        self.sendState.converter = converter
        self.sendState.wsTask = self.wsTask
        // Capture only the sendState (Sendable), not self (@MainActor).
        let state = self.sendState
        return { buffer, _ in
            Self.convertAndSend(buffer: buffer, state: state)
        }
    }

    /// Stop the session and clean up all resources.
    func stop() {
        self.stopped = true
        self.state = .idle
        self.receiveTask?.cancel()
        self.receiveTask = nil
        self.reconnectTask?.cancel()
        self.reconnectTask = nil
        self.removeAudioTap()
        self.finishPlayback()
        self.wsTask?.cancel(with: .goingAway, reason: nil)
        self.wsTask = nil
        self.urlSession?.invalidateAndCancel()
        self.urlSession = nil
        self.sendState.clear()
        self.logger.info("stopped")
        GatewayDiagnostics.log("grok-v2v: stopped")
    }

    // MARK: - Audio Send (Mic → WebSocket)

    private func installAudioTap() {
        guard let engine = self.audioEngine else { return }
        let input = engine.inputNode
        let hwFormat = input.inputFormat(forBus: 0)

        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
            self.logger.error(
                "invalid input format: sr=\(hwFormat.sampleRate) ch=\(hwFormat.channelCount)")
            self.state = .error("Invalid audio input")
            return
        }

        // Create converter from hardware format to Grok's 24kHz PCM16 mono.
        guard let targetFormat = Self.grokFormat else {
            self.logger.error("failed to create target audio format")
            self.state = .error("Audio format failed")
            return
        }
        guard let converter = AVAudioConverter(from: hwFormat, to: targetFormat) else {
            self.logger.error("failed to create audio converter")
            self.state = .error("Audio converter failed")
            return
        }

        self.sendState.converter = converter
        self.sendState.wsTask = self.wsTask

        let state = self.sendState
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: hwFormat) { _, _ in
            // No-op: isolate whether the tap callback itself causes the crash
        }
        self.inputTapInstalled = true

        if !engine.isRunning {
            engine.prepare()
            do {
                try engine.start()
            } catch {
                self.logger.error(
                    "engine start failed: \(error.localizedDescription, privacy: .public)")
                self.state = .error("Audio engine failed")
            }
        }

        GatewayDiagnostics.log(
            "grok-v2v: audio tap installed hwRate=\(hwFormat.sampleRate) ch=\(hwFormat.channelCount)")
    }

    private func removeAudioTap() {
        guard self.inputTapInstalled, let engine = self.audioEngine else { return }
        engine.inputNode.removeTap(onBus: 0)
        self.inputTapInstalled = false
        self.sendState.clear()
    }

    /// Convert a hardware audio buffer to PCM16 24kHz and send over WebSocket.
    /// Called on the audio render thread — must not touch MainActor state.
    private nonisolated static func convertAndSend(
        buffer: AVAudioPCMBuffer, state: AudioSendState
    ) {
        guard let converter = state.converter, let ws = state.wsTask,
              let targetFormat = grokFormat else { return }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard outputFrameCount > 0 else { return }

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat, frameCapacity: outputFrameCount
        ) else { return }

        var error: NSError?
        let inputBox = InputBufferBox(buffer: buffer)
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            guard let buf = inputBox.take() else {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            return buf
        }

        guard error == nil, outputBuffer.frameLength > 0 else { return }

        // Extract raw PCM16 bytes.
        let byteCount = Int(outputBuffer.frameLength) * MemoryLayout<Int16>.size
        let data: Data
        if let channelData = outputBuffer.int16ChannelData {
            data = Data(bytes: channelData[0], count: byteCount)
        } else {
            let audioBuffer = outputBuffer.audioBufferList.pointee.mBuffers
            guard let ptr = audioBuffer.mData else { return }
            data = Data(bytes: ptr, count: byteCount)
        }

        Task { try? await ws.send(.data(data)) }
    }

    // MARK: - Audio Receive (WebSocket → Speaker)

    private func startPlaybackStream() {
        self.finishPlayback()

        let (stream, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
        self.playbackContinuation = continuation

        self.playbackTask = Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.pcmPlayer.play(stream: stream, sampleRate: Self.grokSampleRate)
        }
    }

    private func feedPlayback(_ data: Data) {
        if self.playbackContinuation == nil {
            self.startPlaybackStream()
        }
        self.playbackContinuation?.yield(data)
    }

    private func finishPlayback() {
        self.playbackContinuation?.finish()
        self.playbackContinuation = nil
        self.playbackTask?.cancel()
        self.playbackTask = nil
    }

    // MARK: - WebSocket Receive Loop

    private func startReceiveLoop() {
        self.receiveTask = Task { [weak self] in
            guard let self else { return }
            await MainActor.run { GatewayDiagnostics.log("grok-v2v: receive loop started") }
            while !Task.isCancelled {
                guard let ws = await MainActor.run(body: { self.wsTask }) else {
                    await MainActor.run { GatewayDiagnostics.log("grok-v2v: receive loop: wsTask nil, exiting") }
                    break
                }
                do {
                    let message = try await ws.receive()
                    await self.handleMessage(message)
                } catch {
                    await MainActor.run {
                        if !self.stopped {
                            self.logger.warning("receive error: \(error.localizedDescription, privacy: .public)")
                            GatewayDiagnostics.log("grok-v2v: receive error: \(error.localizedDescription)")
                            self.handleDisconnect()
                        }
                    }
                    break
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .data(let data):
            // Binary frame = PCM16 audio from Grok.
            GatewayDiagnostics.log("grok-v2v: recv audio \(data.count) bytes")
            self.feedPlayback(data)

        case .string(let text):
            // JSON event from the voice proxy.
            GatewayDiagnostics.log("grok-v2v: recv event \(text.prefix(120))")
            self.parseEvent(text)

        @unknown default:
            self.logger.debug("unknown ws message type")
        }
    }

    // MARK: - JSON Event Parsing

    private func parseEvent(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else {
            self.logger.debug("unparseable event: \(text.prefix(200), privacy: .public)")
            return
        }

        switch type {
        case "user_transcript":
            if let transcript = json["text"] as? String {
                GatewayDiagnostics.log("grok-v2v: user said: \(transcript.prefix(100))")
                self.onTranscript?(TranscriptEvent(role: .user, text: transcript))
            }

        case "transcript":
            if let transcript = json["text"] as? String {
                self.onTranscript?(TranscriptEvent(role: .assistant, text: transcript))
            }

        case "audio_done":
            GatewayDiagnostics.log("grok-v2v: audio_done")
            self.finishPlayback()

        case "function_calling":
            let fn = json["function"] as? String ?? "unknown"
            let callId = json["call_id"] as? String ?? ""
            GatewayDiagnostics.log("grok-v2v: function_calling \(fn)")
            self.onFunctionCall?(FunctionCallEvent(function: fn, callId: callId, executed: false))

        case "function_executed":
            let fn = json["function"] as? String ?? "unknown"
            let callId = json["call_id"] as? String ?? ""
            GatewayDiagnostics.log("grok-v2v: function_executed \(fn)")
            self.onFunctionCall?(FunctionCallEvent(function: fn, callId: callId, executed: true))

        case "session_end":
            let reason = json["reason"] as? String ?? "unknown"
            GatewayDiagnostics.log("grok-v2v: session_end reason=\(reason)")
            self.onSessionEnd?(reason)
            self.finishPlayback()

        case "error":
            let message = json["message"] as? String ?? "Unknown error"
            self.logger.error("proxy error: \(message, privacy: .public)")
            GatewayDiagnostics.log("grok-v2v: error: \(message)")
            self.state = .error(message)

        default:
            self.logger.debug("unhandled event type: \(type, privacy: .public)")
        }
    }

    // MARK: - Reconnection

    private func handleDisconnect() {
        guard !self.stopped else { return }
        self.state = .error("Disconnected")
        self.removeAudioTap()
        self.finishPlayback()
        self.wsTask = nil

        // Auto-reconnect after a short delay.
        // Only reconnect WebSocket — audio tap is managed by TalkModeManager.
        self.reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !self.stopped else { return }
            self.logger.info("attempting reconnect")
            GatewayDiagnostics.log("grok-v2v: reconnecting")
            self.state = .idle
            await self.startWebSocketOnly()
            // Re-wire sendState to the new WebSocket task.
            self.sendState.wsTask = self.wsTask
        }
    }
}

// MARK: - Audio Send Helpers

/// Thread-safe container for state accessed from the audio render thread.
/// Avoids MainActor isolation issues in the audio tap callback.
private final class AudioSendState: @unchecked Sendable {
    var converter: AVAudioConverter?
    var wsTask: URLSessionWebSocketTask?

    func clear() {
        self.converter = nil
        self.wsTask = nil
    }
}

/// One-shot buffer box for AVAudioConverter's input callback.
/// Replaces a mutable `var inputConsumed` flag to satisfy Swift 6 concurrency.
private final class InputBufferBox: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func take() -> AVAudioPCMBuffer? {
        let b = self.buffer
        self.buffer = nil
        return b
    }
}
