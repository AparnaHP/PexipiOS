import UIKit

class ViewController: UIViewController {
    
    var node: String?
    var conference: String?
    var domain: String?
    var name: String?

    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    @IBAction func sfbMeeting(_ sender: Any)
    {
        let storyBoard : UIStoryboard = UIStoryboard(name: "Main", bundle:nil)
        let nextViewController = storyBoard.instantiateViewController(withIdentifier: "callController") as! CallController
        
        nextViewController.node = "nodeName"
        nextViewController.conferenceUri = getSFBUri(link: "https://meet.lync.com/yourURL",domain: "pexipDomain")
        nextViewController.domain = "pexipDomain"
        nextViewController.name = "userName"

        self.present(nextViewController, animated:true, completion:nil)
    }
    
    @IBAction func pexipMeeting(_ sender: Any)
    {
        let storyBoard : UIStoryboard = UIStoryboard(name: "Main", bundle:nil)
        let nextViewController = storyBoard.instantiateViewController(withIdentifier: "callController") as! CallController
        
        nextViewController.node = "nodeName"
        nextViewController.conferenceUri = "conferenceId"
        nextViewController.domain = "pexipDomain"
        nextViewController.name = "userName"

        self.present(nextViewController, animated:true, completion:nil)
       
    }
    
    func getSFBUri(link : String, domain: String) -> String
    {
        let pathNameArray = link.split{$0 == "/"}.map(String.init)
        if(pathNameArray.count >= 3)
        {
            let focusId = pathNameArray[pathNameArray.count - 1]
            let userName = pathNameArray[pathNameArray.count - 2];
            let hostName = pathNameArray[pathNameArray.count - 3];
            
            let conferenceEdited = focusId+"-"+userName+"-"+hostName+"@"+domain
            return conferenceEdited.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)!
        }
        return ""
    }
    
    override var supportedInterfaceOrientations:UIInterfaceOrientationMask {
        return UIInterfaceOrientationMask.portrait
    }
  
}
