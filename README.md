# Use of Pexip REST API with WebRTC framework in iOS

Pexip provides a flexible, scalable video conference platform that enables interoperability between video conference systems.

This sample could be used to connect with Skype For Business Meetings and Pexip Meetings.

To connect to a Pexip Meeting you need to change below parameters:

                nextViewController.node = "nodeName" //node name
                nextViewController.conferenceUri = "conferenceId" //xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx (this id is in the URL)
                nextViewController.domain = "pexipDomain" //pexip domain xxxx.xxxx.com
                nextViewController.name = "userName" //user name
               
                
To connect to a Skype For Business Meeting you need to change below parameters:

                nextViewController.node = "nodeName" //node name
                nextViewController.conferenceUri = getSFBUri(link: "https://meet.lync.com/yourURL",domain: "pexipDomain") //add your Skype For Business URL here
                nextViewController.domain = "pexipDomain" //pexip domain xxxx.xxxx.com
                nextViewController.name = "userName" //user name

References:

https://docs.pexip.com/api_client/api_rest.htm
