import Foundation
import WebRTC


class Call: NSObject, RTCPeerConnectionDelegate {

    var factory: RTCPeerConnectionFactory? = nil
    var rtcConfg: RTCConfiguration? = nil
    var rtcConst: RTCMediaConstraints? = nil
    var peerConnection: RTCPeerConnection? = nil

    var videoTrack: RTCVideoTrack? = nil
    var audioTrack: RTCAudioTrack? = nil
    var mediaStream: RTCMediaStream? = nil
    var videoEnabled: Bool = false
    var videoView: RTCEAGLVideoView? = nil
    var selfView: RTCCameraPreviewView? = nil
    
    var connected = false

    var resolution: Resolution? = nil

    var localSdpCompletion: (RTCSessionDescription) -> Void
    var remoteSdpCompletion: ((NSError?) -> Void)? = nil
    var uuid: UUID?

    var capturer: RTCCameraVideoCapturer? = nil
    var coverView: UIView? = nil


    init(uri: URI, videoView: RTCEAGLVideoView, selfView: RTCCameraPreviewView, videoEnabled: Bool, resolution: Resolution, completion: @escaping (RTCSessionDescription) -> Void) {

        RTCInitializeSSL()

        self.factory = RTCPeerConnectionFactory()

        self.resolution = resolution

        self.videoView = videoView

        self.selfView = selfView

        self.videoEnabled = videoEnabled

        self.rtcConfg = RTCConfiguration()

        // Set this to maxCompat for correct operation with Pexip MCU
        self.rtcConfg?.bundlePolicy = RTCBundlePolicy.maxCompat

        // If your ICE servers need credentials, create them in here as RTCIceServer objects
        self.rtcConfg?.iceServers = []
        
        self.rtcConst = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio" : "true",
                "OfferToReceiveVideo" : self.videoEnabled ? "true" : "false"
            ],
            optionalConstraints: [:]
        )

        self.localSdpCompletion = completion
        super.init()

        self.peerConnection = self.factory?.peerConnection(with: rtcConfg!, constraints: rtcConst!, delegate: self)

        self.mediaStream = self.factory?.mediaStream(withStreamId: "PEXIP")

        if self.videoEnabled {
            
            DispatchQueue.main.async {
            self.coverView = UIView(frame: self.selfView!.bounds)
            self.selfView!.addSubview(self.coverView!);
            self.coverView!.backgroundColor = UIColor.black
            self.coverView?.isHidden = true
            }
            
            self.createLocalVideoTrack(useBackCamera: false)
        }
    
        self.audioTrack = self.factory?.audioTrack(withTrackId: "PEXIPa0")

        self.mediaStream?.addAudioTrack(self.audioTrack!)
        
        self.peerConnection?.add(self.mediaStream!)

        if !self.videoEnabled {
              self.peerConnection?.offer(for: self.rtcConst!, completionHandler: self.offerCompletionHandler)
        }

    }

    func offerCompletionHandler(rtcSessionDescription: RTCSessionDescription?, error: Error?) {

        if error != nil {
            print("Error with completion handler for RTCSessionDescription: \(String(describing: error))")
        } else {
            self.peerConnection?.setLocalDescription(rtcSessionDescription!) { error in
                print("Error: \(String(describing: error))")
            }
        }
    }

    func setRemoteSdp(sdp: RTCSessionDescription, completion: @escaping (_ error: Error?) -> Void) {
        //print("mutating remote SDP bandwidth")
        let mutated = self.mutateSdpToBandwidth(sdp: sdp)
        self.peerConnection?.setRemoteDescription(mutated) { error in
            //print("Setting remote SDP on connection, status: \(error)")
            self.remoteSdpCompletion = completion
            completion(nil)
        }
    }

    // RTCPeerConnectionDelegate functions
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        //print("peer connection stateChanged%@", peerConnection)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        //print("peer connection didAddStream")
        if stream.videoTracks.count > 0 && self.videoEnabled {
            //print("Got video track")
            self.videoTrack = stream.videoTracks[0]
            self.videoTrack?.add(self.videoView!)
        }
        if stream.audioTracks.count > 0 {
            //print("Got audio track")
            self.audioTrack = stream.audioTracks[0]
            // at this point you should be able to route media to different audio
            // outputs - see docs.
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        //print("peer connection didRemoveStream")
    }

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        //print("peer connection should neg")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        //print("We've established media",newState.rawValue)

        /*if newState.rawValue == RTCIceConnectionState.connected.rawValue {
        }*/
    
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        if newState.rawValue == RTCIceGatheringState.complete.rawValue {
            //print("We've completed ICE gathering, send up the completed SDP")
            // Now we can mangle the SDP to set the correct resolution settings
               //let mutated = self.mutateSdpToBandwidth(sdp: (self.peerConnection?.localDescription)!)
                let mutated = self.mutateSdpToBandwidth(sdp: (self.peerConnection?.localDescription)!)
                self.localSdpCompletion(mutated)

            }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        //print("generate ice candidate")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        //print("removed ice candidate")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        //print("opened datachannel")
    }

    // SDP Mangling for BW/Resolution stuff
    private func mutateSdpToBandwidth(sdp: RTCSessionDescription) -> RTCSessionDescription {
        let h264BitsPerPixel = 0.06
        let fps = 30.0
        // if using AAC-LD --> 128.0
        let audioBw = 64.0
        let videoBw = Double(self.resolution!.width()) * Double(self.resolution!.height()) * fps * h264BitsPerPixel
        let asValue = Int((videoBw / 1000) + audioBw)
        let tiasValue = Int(videoBw + audioBw)
        let range = sdp.sdp.range(of: "m=video.*\\r\\nc=IN.*\\r\\n", options: .regularExpression)
        var origSdp = sdp.sdp
        let bwLine = "b=AS:\(asValue)\r\nb=TIAS:\(tiasValue)\r\n"
        if range != nil {
            origSdp.insert(contentsOf: bwLine, at: range!.upperBound)
            return RTCSessionDescription(type: sdp.type, sdp: origSdp)
        } else {
            return sdp
        }
    }
    
    /*func createLocalVideoTrack(useBackCamera: Bool) {
        let constraints = RTCMediaConstraints.init(mandatoryConstraints: [:], optionalConstraints: [:])
        let videoSource = self.factory?.avFoundationVideoSource(with: constraints)
        videoSource!.useBackCamera = useBackCamera
        let videoTrack = self.factory?.videoTrack(with: videoSource!, trackId: "PEXIPv0")
        videoTrack!.add(self.selfView!)
        self.mediaStream?.addVideoTrack(videoTrack!)
    }*/

    
    func createLocalVideoTrack(useBackCamera: Bool) {
    
        let videoSource = self.factory?.videoSource()
        self.capturer = RTCCameraVideoCapturer(delegate: videoSource!)

        if let camera = (RTCCameraVideoCapturer.captureDevices().first { $0.position == (useBackCamera ? .back : .front) }),

        let format = RTCCameraVideoCapturer.supportedFormats(for: camera).last,
        let fps = format.videoSupportedFrameRateRanges.first?.maxFrameRate
        {
            self.capturer!.startCapture(with: camera,
            format: format,
            fps: Int(fps),
            completionHandler:
            {
                (error: Error?) in
                if error != nil {
                    //print("Error RTCCameraVideoCapturer startCapture \(captureError)")
                }
                else {
        
                    DispatchQueue.main.async {
        
                    let videoTrack = self.factory?.videoTrack(with: videoSource!, trackId: "PEXIPv0")
                    self.mediaStream?.addVideoTrack(videoTrack!)
                    self.selfView!.captureSession = self.capturer?.captureSession
                        
                    self.peerConnection?.offer(for: self.rtcConst!, completionHandler: self.offerCompletionHandler)
                    }
                }
            })
        }

    }


    func switchCamera(useBackCamera: Bool) {
        
        if ((self.mediaStream?.videoTracks.count)! > 0 && (self.mediaStream?.videoTracks[0].isEnabled)!)
        {
            let localStream = peerConnection?.localStreams.first
            
            if let videoTrack = localStream?.videoTracks.first {
                localStream?.removeVideoTrack(videoTrack)
            }
            
            createLocalVideoTrack(useBackCamera: useBackCamera)
            
            if let ls = localStream {
                peerConnection?.remove(ls)
                peerConnection?.add(ls)
            }
            
        }
    }
    
    func turnOffVideo() -> String
    {
                
        if (self.mediaStream?.videoTracks.count)! > 0 {
            self.mediaStream?.videoTracks[0].isEnabled =             !((self.mediaStream?.videoTracks[0].isEnabled)!)
            
            if((self.mediaStream?.videoTracks[0].isEnabled)!)
            {
                self.coverView?.isHidden = true
                self.selfView?.captureSession.startRunning()
        
            }
            else
            {
                self.coverView?.isHidden = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if(!self.coverView!.isHidden)
                    {
                    self.selfView?.captureSession.stopRunning()
                    }
                }
            }
            
            return ((self.mediaStream?.videoTracks[0].isEnabled)!) ? "on" : "off"
        }
        return "";
    }
    
    func turnOffAudio() -> String
    {
        if (self.mediaStream?.audioTracks.count)! > 0 {
            self.mediaStream?.audioTracks[0].isEnabled =             !((self.mediaStream?.audioTracks[0].isEnabled)!)
            return ((self.mediaStream?.audioTracks[0].isEnabled)!) ? "on" : "off"
        }
        return "";
    }
}


class URI {

    var conference: String? = nil
    var domain: String? = nil
    var host: String? = nil
    var display_name: String? = nil

    public init?(node: String, conference: String, domain:String, name: String)
    {
        self.conference = conference;
        self.domain = domain;
        self.host = node;
        self.display_name = name;
    }
    
}

// Although not really a "resolution", this is a simple way to provide a notion of
// quality or bandwidth for a call.
public enum Resolution: Int, CustomStringConvertible {
    case wcif, p448, p576, hd

    public func width() -> Int {
        switch (self) {
        case .wcif:
            return 512
        case .p448:
            return 768
        case .p576:
            return 1024
        case .hd:
            return 1280
        }
    }

    public func height() -> Int {
        switch (self) {
        case .wcif:
            return 288
        case .p448:
            return 448
        case .p576:
            return 576
        case .hd:
            return 720
        }
    }

    public func maxFs() -> Int {
        let maxFs = (self.width() * self.height()) / (16 * 16)
        return maxFs
    }

    public func maxMbps() -> Int {
        return (self.maxFs() * 30)
    }

    public var description: String {
        switch (self) {
        case .wcif: return "wCIF"
        case .p448: return "448p"
        case .p576: return "576p"
        case .hd: return "720p"
        }
    }

    static let count: Int = {
        var max: Int = 0
        while let _ = Resolution(rawValue: max) { max += 1 }
        return max
    }()
}

