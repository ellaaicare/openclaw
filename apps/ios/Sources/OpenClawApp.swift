import Foundation
import os
import SwiftUI
import UIKit

final class OpenClawAppDelegate: NSObject, UIApplicationDelegate {
    private let logger = Logger(subsystem: "ai.openclaw.ios", category: "Push")
    private var pendingAPNsDeviceToken: Data?
    weak var appModel: NodeAppModel? {
        didSet {
            guard let model = self.appModel, let token = self.pendingAPNsDeviceToken else { return }
            self.pendingAPNsDeviceToken = nil
            Task { @MainActor in
                model.updateAPNsDeviceToken(token)
            }
        }
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool
    {
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        if let appModel = self.appModel {
            Task { @MainActor in
                appModel.updateAPNsDeviceToken(deviceToken)
            }
            return
        }

        self.pendingAPNsDeviceToken = deviceToken
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        self.logger.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void)
    {
        self.logger.info("APNs remote notification received keys=\(userInfo.keys.count, privacy: .public)")
        Task { @MainActor in
            guard let appModel = self.appModel else {
                self.logger.info("APNs wake skipped: appModel unavailable")
                completionHandler(.noData)
                return
            }
            let handled = await appModel.handleSilentPushWake(userInfo)
            self.logger.info("APNs wake handled=\(handled, privacy: .public)")
            completionHandler(handled ? .newData : .noData)
        }
    }
}

private let debugLog = Logger(subsystem: "ai.openclaw.ios", category: "debug")

@main
struct OpenClawApp: App {
    @State private var appModel: NodeAppModel
    @State private var gatewayController: GatewayConnectionController
    @UIApplicationDelegateAdaptor(OpenClawAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Self.installUncaughtExceptionLogger()
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

        // Try env var first (simulator), then fall back to public gateway.
        // Real device uses public endpoint (wss://gateway.ella-ai-care.com).
        // Simulator uses localhost proxy (ws://localhost:19001).
        let isSimulator = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil
        let token = ProcessInfo.processInfo.environment["OPENCLAW_GATEWAY_TOKEN"]
            ?? "7a98075ef48a40f33b0be0921d62cfaa273f43779f88daca"
        let host = ProcessInfo.processInfo.environment["OPENCLAW_GATEWAY_HOST"]
            ?? (isSimulator ? "localhost" : "gateway.ella-ai-care.com")
        let port = ProcessInfo.processInfo.environment["OPENCLAW_GATEWAY_PORT"]
            ?? (isSimulator ? "19001" : "443")

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
                .task {
                    self.appDelegate.appModel = self.appModel
                }
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

extension OpenClawApp {
    private static func installUncaughtExceptionLogger() {
        NSLog("OpenClaw: installing uncaught exception handler")
        NSSetUncaughtExceptionHandler { exception in
            // Useful when the app hits NSExceptions from SwiftUI/WebKit internals; these do not
            // produce a normal Swift error backtrace.
            let reason = exception.reason ?? "(no reason)"
            NSLog("UNCAUGHT EXCEPTION: %@ %@", exception.name.rawValue, reason)
            for line in exception.callStackSymbols {
                NSLog("  %@", line)
            }
        }
    }
}
