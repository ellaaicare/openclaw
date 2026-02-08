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
        guard let token = ProcessInfo.processInfo.environment["OPENCLAW_GATEWAY_TOKEN"],
              !token.isEmpty
        else {
            debugLog.warning("[DEBUG-TOKEN] No OPENCLAW_GATEWAY_TOKEN env var found")
            return
        }
        let instanceId = UserDefaults.standard.string(forKey: "node.instanceId")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !instanceId.isEmpty else {
            debugLog.error("[DEBUG-TOKEN] No instanceId in UserDefaults")
            return
        }
        debugLog.notice("[DEBUG-TOKEN] Saving token for instanceId=\(instanceId)")
        GatewaySettingsStore.saveGatewayToken(token, instanceId: instanceId)
        // Verify round-trip
        let loaded = GatewaySettingsStore.loadGatewayToken(instanceId: instanceId)
        debugLog.notice("[DEBUG-TOKEN] Verify load: \(loaded != nil ? "OK" : "FAILED")")
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
