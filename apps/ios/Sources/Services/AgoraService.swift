import Foundation
import AgoraRtcKit

@Observable
class AgoraService: NSObject {
    static let appId = "55dd93fbff4946d7bcbff6f6ebcee462"
    
    private var agoraKit: AgoraRtcEngineKit?
    private(set) var isInCall = false
    
    func initialize() {
        let config = AgoraRtcEngineConfig()
        config.appId = AgoraService.appId
        config.channelProfile = .communication
        
        agoraKit = AgoraRtcEngineKit.sharedEngine(with: config, delegate: self)
        agoraKit?.enableAudio()
        
        print("[Agora] Engine initialized")
    }
    
    func joinChannel(channelName: String, token: String, uid: UInt) {
        guard let agoraKit = agoraKit else {
            print("[Agora] Error: Engine not initialized")
            return
        }
        
        let mediaOptions = AgoraRtcChannelMediaOptions()
        mediaOptions.clientRoleType = .broadcaster
        mediaOptions.channelProfile = .communication
        
        let result = agoraKit.joinChannel(
            byToken: token,
            channelId: channelName,
            uid: uid,
            mediaOptions: mediaOptions
        )
        
        if result == 0 {
            print("[Agora] Joining channel")
        } else {
            print("[Agora] Failed to join channel")
        }
    }
    
    func leaveChannel() {
        agoraKit?.leaveChannel { stats in
            print("[Agora] Left channel")
        }
        isInCall = false
    }
    
    func cleanup() {
        leaveChannel()
        AgoraRtcEngineKit.destroy()
        agoraKit = nil
        print("[Agora] Engine destroyed")
    }
}

extension AgoraService: AgoraRtcEngineDelegate {
    func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinChannel channel: String, withUid uid: UInt, elapsed: Int) {
        print("[Agora] Joined channel successfully")
        isInCall = true
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinedOfUid uid: UInt, elapsed: Int) {
        print("[Agora] Remote user joined")
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, didLeaveChannelWith stats: AgoraChannelStats) {
        print("[Agora] Left channel")
        isInCall = false
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, didOccurError errorCode: AgoraErrorCode) {
        print("[Agora] Error occurred")
    }
}
