# SampleSwiftUI

Project contains ready to use SIP VoIP Client application for iOS, written on SwiftUI and also includes CallKit implementation.
As SIP engine it uses Siprix SDK, included in binary form.

Application (Siprix) has ability to:

- Add multiple SIP accounts
- Send/receive multiple audio/video calls
- Manage calls with:
   - Hold/unhold
   - Mute microphone/camera
   - Play sound to call from mp3 file
   - Record received sound to file
   - Send/receive DTMF
   - Transfer
   - ...

Application's UI may not contain all the features, avialable in the SDK, they will be added later.

## Limitations

Siprix doesn't provide VoIP services, but in the same time doesn't have nay backend limitations and can connect to any SIP PBX.
For testing app you need an account(s) credentials from a SIP service provider(s). 
Some features may be not supported by all SIP providers.

Attached Siprix SDK works in trial mode and has limited call duration - it drops call after 60sec.
Upgrading to a paid license removes this restriction, enabling calls of any length.

Please contact [sales@siprix-voip.com](mailto:sales@siprix-voip.com) for more details.

## More resources

Product web site: https://siprix-voip.com

Manual: https://docs.siprix-voip.com


## Screeshots

<a href="https://docs.siprix-voip.com/screenshots/SampleSwiftUI_Accounts.png"  title="Accounts screenshot">
<img src="https://docs.siprix-voip.com/screenshots/SampleSwiftUI_Accounts_Mini.jpg" width="50"></a>|<a href="https://docs.siprix-voip.com/screenshots/SampleSwiftUI_CallKit.png"  title="example image">
<img src="https://docs.siprix-voip.com/screenshots/SampleSwiftUI_CallKit_Mini.jpg" width="50"></a>|<a href="https://docs.siprix-voip.com/screenshots/SampleSwiftUI_Calls.png"  title="example image">
<img src="https://docs.siprix-voip.com/screenshots/SampleSwiftUI_Calls_Mini.jpg" width="50"></a>|<a href="https://docs.siprix-voip.com/screenshots/SampleSwiftUI_Logs.png"  title="example image">
<img src="https://docs.siprix-voip.com/screenshots/SampleSwiftUI_Logs_Mini.jpg" width="50"></a>

