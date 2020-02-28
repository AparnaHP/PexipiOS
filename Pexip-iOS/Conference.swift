import Foundation
import WebRTC

enum ServiceError {
    case ok, error
}

class Conference {

    var tokenResp: [String: AnyObject]?
    var token: String?
    var pin: String?
    var httpAuth: String?
    var conferenceExtension: String?
    var refreshTimer: Timer?
    var myParticipantUUID: UUID?

    var videoView: RTCEAGLVideoView?
    var selfView: RTCCameraPreviewView?
    var call: Call?
    var uri: URI

    var queryTimeout: TimeInterval = 7
    var callQueryTimeout: TimeInterval = 62
    let baseUri = "/api/client/v2/conferences/"
    
    init(node: String, conference: String, domain:String, name: String)
    {
        var conferenceEdited = ""
        if conference.contains("meet.lync.com")
        {
            let pathNameArray = conference.split{$0 == "/"}.map(String.init)
            if(pathNameArray.count >= 3)
            {
                let focusId = pathNameArray[pathNameArray.count - 1]
                let userName = pathNameArray[pathNameArray.count - 2];
                _ = pathNameArray[pathNameArray.count - 3]; //host name
                
                conferenceEdited = focusId+"-"+userName+"@"+domain
                conferenceEdited  =   conferenceEdited.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)!
            }
        }
        else
        {
            conferenceEdited = conference
        }
        
        self.uri = URI(node: node, conference: conferenceEdited, domain: domain, name: name)!
    }

    
    func tryToJoin(completion: @escaping (ServiceError) -> Void) {

        self.requestToken() { token in
            guard let token = token else {
                return
            }

            if token["status"] as! String == "success" {
            
                    self.tokenResp = token["result"] as! [String : AnyObject]?
                    self.token = self.tokenResp?["token"] as? String

                    // At this point you could store the token information for later usage.
                    // For now let's stash the participant_uuid (needed later for participant operations)

                    let uuidString = self.tokenResp?["participant_uuid"] as! String
                    self.myParticipantUUID = UUID(uuidString: uuidString)

                    // Let's setup a timer to refresh the token
                    if let expires = self.tokenResp?["expires"] as? String,
                        let exp = Int(expires) {
                        DispatchQueue.main.async {
                            self.refreshTimer = Timer.scheduledTimer(timeInterval: TimeInterval(exp/4), target: self, selector: .refreshSelector, userInfo: nil, repeats: true);
                        }
                    }

                    completion(ServiceError.ok)
                
            } else {
                if (token["result"] as? String) != nil {
                    completion(ServiceError.error)
                }
            }
        }
    }


    func requestToken(completion: @escaping ([String: AnyObject]?) -> Void) {

        guard let url = URL(string: "https://\(self.uri.host!)\(self.baseUri)\(self.uri.conference!)/request_token?display_name=\(self.uri.display_name!)")  else {
            return
        }
        
        /*let callOffer = [
            "conference_extension": "mssip",
        ]*/
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = self.queryTimeout
        request.cachePolicy = URLRequest.CachePolicy.reloadIgnoringCacheData
        request.addValue("application/json", forHTTPHeaderField: "Content-type")
        //let jsonBody = try? JSONSerialization.data(withJSONObject: callOffer, options: [])
        //request.httpBody = jsonBody
        
        if let auth = self.httpAuth {
            request.addValue(auth, forHTTPHeaderField: "Authorization")
        }
        if let pin = self.pin {
            request.addValue(pin, forHTTPHeaderField: "pin")
        }
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            do {
                guard error == nil else {
                    print("Error with request token: \(String(describing: error))")
                    return
                }
                guard let data = data else {
                    return
                }
                guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: AnyObject] else {
                    return
                }
                completion(json)
            } catch {
                print("Error with request token")
                return
            }
        }
        task.resume()
    }

    @objc func refreshToken(timer: Timer) {

        guard let url = URL(string: "https://\(self.uri.host!)\(self.baseUri)\(self.uri.conference!)/refresh_token")  else {
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = self.queryTimeout
        request.cachePolicy = URLRequest.CachePolicy.reloadIgnoringCacheData
    
        if let auth = self.httpAuth {
            request.addValue(auth, forHTTPHeaderField: "Authorization")
        }
        if let pin = self.pin {
            request.addValue(pin, forHTTPHeaderField: "pin")
        }
        if let token = self.token {
            request.addValue(token, forHTTPHeaderField: "token")
        }
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            do {
                guard error == nil else {
                    print("Error with refresh token: \(String(describing: error))")
                    return
                }
                guard let data = data else {
                    return
                }
                guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: AnyObject] else {
                    return
                }
                if let status = json["status"] as? String {
                    if status.lowercased() == "success" {
                        if let result = json["result"] as? [String: AnyObject] {
                            self.token = result["token"] as? String
                        }
                    }
                }
            } catch {
                print("Error with refresh token")
            }
        }
        task.resume()
    }

    func tryToEscalate(video: Bool, resolution: Resolution, completion: @escaping (ServiceError) -> Void) {
        
        self.call = Call(uri: self.uri, videoView: self.videoView!, selfView: self.selfView!, videoEnabled: video, resolution: resolution) { sdp in
            
            let callOffer = [
                "call_type": "WEBRTC",
                "sdp": sdp.sdp
            ]
            let uuidString = self.myParticipantUUID!.uuidString.lowercased()
            let urlString = "https://\(self.uri.host!)\(self.baseUri)\(self.uri.conference!)/participants/\(uuidString)/calls"
            let jsonBody = try? JSONSerialization.data(withJSONObject: callOffer, options: [])
            guard let url = URL(string: urlString)  else {
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = self.callQueryTimeout
            request.cachePolicy = URLRequest.CachePolicy.reloadIgnoringCacheData
            request.addValue("application/json", forHTTPHeaderField: "Content-type")
            request.httpBody = jsonBody
            if let auth = self.httpAuth {
                request.addValue(auth, forHTTPHeaderField: "Authorization")
            }
            
            if let pin = self.pin {
                request.addValue(pin, forHTTPHeaderField: "pin")
            }
            if let token = self.token {
                request.addValue(token, forHTTPHeaderField: "token")
            }
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                do {
                    guard error == nil else {
                        print("Error with video request: \(String(describing: error))")
                        return
                    }
                    guard let data = data else {
                        return
                    }
                    guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: AnyObject] else {
                        return
                    }
                    if let status = json["status"] as? String {
                        if status.lowercased() == "success" {
                            if let result = json["result"] as? [String: AnyObject] {
                                
                                let uuidString = result["call_uuid"] as! String
                                self.call?.uuid = UUID(uuidString: uuidString)
                                let remoteSdp = result["sdp"] as! String
                                
                                self.call?.setRemoteSdp(sdp: RTCSessionDescription(type: RTCSdpType.answer, sdp: remoteSdp)) { status in
                                    print("Remote SDP status :  \(String(describing: status))")
                                    self.ack()
                            
                                    completion(.ok)
                                }
                            }
                        }
                    }
                } catch {
                    print("Error with video request")
                }
            }
            task.resume()
            
        }
    }
    

    func ack() {

        let uuidString = self.myParticipantUUID!.uuidString.lowercased()
        let urlString = "https://\(self.uri.host!)\(self.baseUri)\(self.uri.conference!)/participants/\(uuidString)/calls/\(self.call!.uuid!.uuidString.lowercased())/ack"
        guard let url = URL(string: urlString)  else {
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = URLRequest.CachePolicy.reloadIgnoringCacheData
        if let auth = self.httpAuth {
            request.addValue(auth, forHTTPHeaderField: "Authorization")
        }


        if let token = self.token {
            request.addValue(token, forHTTPHeaderField: "token")
        }
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
                guard error == nil else {
                print("Error with ack : \(String(describing: error))")
                return
            }
        }
        task.resume()
    }
    
    func muteUnmute(status: String, completion: @escaping (ServiceError) -> Void) {
          
            let uuidString = self.myParticipantUUID!.uuidString.lowercased()
            let urlString = "https://\(self.uri.host!)\(self.baseUri)\(self.uri.conference!)/participants/\(uuidString)/mute"
        
            guard let url = URL(string: urlString)  else {
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = self.queryTimeout
            request.cachePolicy = URLRequest.CachePolicy.reloadIgnoringCacheData
            request.addValue("application/json", forHTTPHeaderField: "Content-type")

            if let auth = self.httpAuth {
                request.addValue(auth, forHTTPHeaderField: "Authorization")
            }
        
            if let pin = self.pin {
                request.addValue(pin, forHTTPHeaderField: "pin")
            }
        
            if let token = self.token {
                request.addValue(token, forHTTPHeaderField: "token")
            }
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                do {
                    guard error == nil else {
                        print("Error with mute request: \(String(describing: error))")
                        return
                    }
                    guard let data = data else {
                        return
                    }
                    guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: AnyObject] else {
                        return
                    }
                    
                    if let status = json["status"] as? String {
                        if status.lowercased() == "success" {
                            completion(.ok)
                        }
                    }
                    else
                    {
                        completion(.error)
                    }
                    
                } catch {
                    print("Error with mute request")
                }
            }
            task.resume()
    }
    
    func turnOffVideo() -> String
    {
        return (self.call?.turnOffVideo())!
    }
     
    func turnOffAudio() -> String
    {
        return (self.call?.turnOffAudio())!
    }
    
    func switchCamera(useBackCamera: Bool)
    {
        self.call?.switchCamera(useBackCamera: useBackCamera)
    }

    func disconnectMedia(completion: @escaping (ServiceError) -> Void) {
      
        let uuidString = self.myParticipantUUID!.uuidString.lowercased()
        let callUUIDString =  self.call!.uuid?.uuidString.lowercased() ?? ""
        let urlString = "https://\(self.uri.host!)\(self.baseUri)\(self.uri.conference!)/participants/\(uuidString)/calls/\(callUUIDString)/disconnect"
        
        guard let url = URL(string: urlString)  else {
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = URLRequest.CachePolicy.reloadIgnoringCacheData
        if let auth = self.httpAuth {
            request.addValue(auth, forHTTPHeaderField: "Authorization")
        }

        if let pin = self.pin {
            request.addValue(pin, forHTTPHeaderField: "pin")
        }
        if let token = self.token {
            request.addValue(token, forHTTPHeaderField: "token")
        }
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard error == nil else {
                print("Error with request: \(String(describing: error))")
                return
            }

            DispatchQueue.main.async {
                self.call?.peerConnection?.remove((self.call?.mediaStream)!)
                self.call?.mediaStream = nil
                self.call?.audioTrack = nil
                self.call?.videoTrack = nil

                self.call?.peerConnection?.close()
                self.call?.peerConnection = nil
                self.call?.videoView = nil
                self.call?.selfView = nil
                self.call?.factory = nil
                RTCCleanupSSL()
            }
            completion(.ok)
        }
        task.resume()

    }

    func quit(completion: @escaping (ServiceError) -> Void) {

        if self.call != nil {
            self.disconnectMedia { status in
                print("Disconnected media stack")
            }
        }

        // Cancel the refresh timer, we're done
        DispatchQueue.main.async {
            print("Cancelled token refresh timer")
            self.refreshTimer?.invalidate()
        }

        let urlString = "https://\(self.uri.host!)\(self.baseUri)\(self.uri.conference!)/release_token"
        guard let url = URL(string: urlString)  else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = URLRequest.CachePolicy.reloadIgnoringCacheData
        if let auth = self.httpAuth {
            request.addValue(auth, forHTTPHeaderField: "Authorization")
        }
        if let token = self.token {
            request.addValue(token, forHTTPHeaderField: "token")
        }
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard error == nil else {
                print("Error with request: \(String(describing: error))")
                return
            }
            completion(.ok)
        }
        task.resume()
    }
    
    func tryToPresent(completion: @escaping (ServiceError) -> Void) {
        completion(.ok)
    }
    
}

class Participant {
    var name: String
    var uri: String
    var uuid: UUID

    init(name: String, uri: String, uuid: UUID) {
        self.name = name
        self.uri = uri
        self.uuid = uuid
    }

}

private extension Selector {
    static let refreshSelector =
        #selector(Conference.refreshToken(timer:))    
}
