import UIKit
import WebRTC

class CallController: UIViewController {

    var node: String?
    var conferenceUri: String?
    var domain: String?
    var name: String?
    
    @IBOutlet weak var connectingLabel: UILabel!
    @IBOutlet var videoView: RTCEAGLVideoView!
    @IBOutlet weak var endCall: UIButton!
    @IBOutlet weak var muteUnmute: UIButton!
    @IBOutlet weak var videoOnOff: UIButton!
    @IBOutlet weak var switchCamera: UIButton!
    @IBOutlet weak var selfView: RTCCameraPreviewView!
    @IBOutlet weak var cp: UIStackView!
    @IBOutlet weak var back: UIButton!
    @IBOutlet weak var meetingName: UILabel!
    @IBOutlet var rootView: UIView!
    
    var conference: Conference?
    var muteStatus: String? = "unmute"
    var resolution: Resolution = Resolution.p576

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.makeViewCircular(view: self.videoOnOff)
        self.makeViewCircular(view: self.muteUnmute)

        self.connectingLabel.isHidden = false
        self.selfView.isHidden = true
        
        self.videoOnOff.isEnabled = false
        self.muteUnmute.isEnabled = false
        self.switchCamera.isEnabled = false

        self.switchCamera.tag = 1

        self.view.bringSubviewToFront(self.connectingLabel)
        self.view.bringSubviewToFront(self.selfView)
        self.view.bringSubviewToFront(self.cp)

        self.connectingLabel.text = NSLocalizedString("Connect_Camera", comment: "")
        
        if UIDevice.current.orientation.isLandscape {
            self.onLandscape()
        } else {
            self.onPortrait()
        }
    
    }
    
    override func viewDidAppear(_ animated: Bool) {
        self.checkAccess()
    }
    
    
    func checkAccess()
    {
        #if targetEnvironment(simulator)
        self.showSimulatorAlert()
        #else
        self.startMeeting()
        #endif
    }
    
    func showSimulatorAlert()
    {
      let alert = UIAlertController(title: NSLocalizedString("Alert", comment: ""), message: NSLocalizedString("Not_Supported", comment: ""), preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: { action in
        self.endVideoCall()
      }))
      self.present(alert, animated: true, completion: nil)
    }
    
    func startMeeting()
    {
        self.conference = Conference(node: node!, conference: conferenceUri!,domain: domain!, name: name!.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)!)
        
        self.conference?.videoView = self.videoView
        self.conference?.selfView = self.selfView

        self.conference?.tryToJoin { status in
            print("Join status : \(status)")
                        
            self.conference?.tryToEscalate(video: true, resolution: self.resolution) { status in
                DispatchQueue.main.async {
                    print("Video status : \(status)")
                    self.connectingLabel.isHidden = true
                    self.selfView.isHidden = false
                    
                    self.videoOnOff.isEnabled = true
                    self.muteUnmute.isEnabled = true
                    self.switchCamera.isEnabled = true
                }
            }
        }
    }
    
    func disconnect()
    {
        self.conference?.quit { status in
            print("Disconnect status : \(status)")
        }
    }
    
    func endVideoCall()
    {
        self.dismiss(animated: false, completion: nil)
    }

    @IBAction func muteUnmute(_ sender: Any)
    {
        let status = self.conference?.turnOffAudio()
        
        if(status == "on")
        {
            DispatchQueue.main.async {
                self.muteUnmute.setImage(UIImage(named: "unmute.png"), for: UIControl.State.normal)
            }
        }
        else if(status == "off")
        {
            DispatchQueue.main.async {
                self.muteUnmute.setImage(UIImage(named: "mute.png"), for: UIControl.State.normal)
            }
        }
    }
    
    @IBAction func endCall(_ sender: Any) {
        
        self.endVideoCall()
    }

    @IBAction func videoOnOff(_ sender: Any)
    {
        let status = self.conference?.turnOffVideo()

        if(status == "on")
        {
            DispatchQueue.main.async {
                self.videoOnOff.setImage(UIImage(named: "videoon.png"), for: UIControl.State.normal)
            }
        }
        else if(status == "off")
        {
            DispatchQueue.main.async {
                self.videoOnOff.setImage(UIImage(named: "videooff.png"), for: UIControl.State.normal)
            }
        }

    }
    
    @IBAction func switchCamera(_ sender: Any)
    {
        if(self.switchCamera.tag == 1)
        {
            self.conference?.switchCamera(useBackCamera: true)
            self.switchCamera.tag = 0
        }
        else
        {
            self.conference?.switchCamera(useBackCamera: false)
            self.switchCamera.tag = 1
        }
    }
    
    @IBAction func back(_ sender: Any)
    {
        self.endVideoCall()
    }
    
    @IBAction func onTouchVideoView(_ sender: Any) {
        self.showHideControlPanel()
    }

    
    func makeViewCircular(view: UIView) {
        view.layer.borderWidth = 1
        view.layer.borderColor = primaryColor?.cgColor
    }
    
    func onLandscape()
    {
        rootView.backgroundColor = UIColor.black

        videoOnOff.tintColor = UIColor.white
        muteUnmute.tintColor = UIColor.white

        videoOnOff.layer.borderColor = UIColor.white.cgColor
        muteUnmute.layer.borderColor = UIColor.white.cgColor
        
        meetingName.isHidden = true
        back.isHidden = true

        self.showHideControlPanel()
    }
    
    func onPortrait()
    {
        rootView.backgroundColor = UIColor.white
        
        videoOnOff.tintColor = primaryColor
        muteUnmute.tintColor = primaryColor
        
        videoOnOff.layer.borderColor = primaryColor?.cgColor
        muteUnmute.layer.borderColor = primaryColor?.cgColor
        
        meetingName.isHidden = false
        back.isHidden = false

        self.showHideControlPanel()

    }
    
    func showHideControlPanel()
    {
        self.cp.isHidden = false
        
        if UIDevice.current.orientation.isLandscape {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                
                if UIDevice.current.orientation.isLandscape {
                self.cp.isHidden = true
                }
            }
        }
    }
    
    override var supportedInterfaceOrientations:UIInterfaceOrientationMask {
        return UIInterfaceOrientationMask.all
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        if UIDevice.current.orientation.isLandscape {
            self.onLandscape()

        } else {
            self.onPortrait()
        }
    }
    
   override func viewDidDisappear(_ animated: Bool) {
       self.disconnect();
   }

    
}

