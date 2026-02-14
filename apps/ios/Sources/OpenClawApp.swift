import os
import SwiftUI

private let debugLog = Logger(subsystem: "ai.openclaw.ios", category: "debug")

@main
struct OpenClawApp: App {
    @State private var appModel: NodeAppModel
    @State private var gatewayController: GatewayConnectionController
    @Environment(\.scenePhase) private var scenePhase

    init() {
        GatewaySettingsStore.bootstrapPersistence()
        #if DEBUG
        Self.injectDebugGatewayToken()
        #endif
        let appModel = NodeAppModel()
        _appModel = State(initialValue: appModel)
        _gatewayController = State(initialValue: GatewayConnectionController(appModel: appModel))
    }

    #if DEBUG
    private static func injectDebugGatewayToken() {
        let defaults = UserDefaults.standard

        // Try env var first (simulator), then fall back to hardcoded dev gateway.
        // Real device uses TLS proxy on Mac (wss://doge1-2.taild355d6.ts.net:19002).
        // Simulator uses localhost proxy (ws://localhost:19001).
        let isSimulator = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil
        let token = ProcessInfo.processInfo.environment["OPENCLAW_GATEWAY_TOKEN"]
            ?? "72c00bd34f87d6277ca6e11037a8f206312940fdd29db74d"
        let host = ProcessInfo.processInfo.environment["OPENCLAW_GATEWAY_HOST"]
            ?? (isSimulator ? "localhost" : "doge1-2.taild355d6.ts.net")
        let port = ProcessInfo.processInfo.environment["OPENCLAW_GATEWAY_PORT"]
            ?? (isSimulator ? "19001" : "19002")

        // Ensure instanceId exists (create one if first launch).
        var instanceId = defaults.string(forKey: "node.instanceId")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if instanceId.isEmpty {
            instanceId = UUID().uuidString
            defaults.set(instanceId, forKey: "node.instanceId")
            debugLog.notice("[DEBUG-TOKEN] Created new instanceId=\(instanceId)")
        }

        debugLog.notice("[DEBUG-TOKEN] Saving token for instanceId=\(instanceId)")
        GatewaySettingsStore.saveGatewayToken(token, instanceId: instanceId)

        // Configure manual gateway connection.
        defaults.set(true, forKey: "gateway.manual.enabled")
        defaults.set(host, forKey: "gateway.manual.host")
        defaults.set(Int(port) ?? 19001, forKey: "gateway.manual.port")
        defaults.set(!isSimulator, forKey: "gateway.manual.tls")
        defaults.set(true, forKey: "gateway.autoconnect")
        defaults.set(true, forKey: "gateway.onboardingComplete")
        defaults.set(true, forKey: "gateway.hasConnectedOnce")
        debugLog.notice("[DEBUG-TOKEN] Manual gateway configured: \(host):\(port) tls=\(!isSimulator)")
    }
    #endif

    var body: some Scene {
        WindowGroup {
            RootCanvas()
                .environment(self.appModel)
                .environment(self.appModel.voiceWake)
                .environment(self.gatewayController)
                .onOpenURL { url in
                    Task { await self.appModel.handleDeepLink(url: url) }
                }
                .onChange(of: self.scenePhase) { _, newValue in
                    self.appModel.setScenePhase(newValue)
                    self.gatewayController.setScenePhase(newValue)
                }
        }
    }
}
