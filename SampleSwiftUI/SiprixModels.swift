//
//  SiprixModels.swift
//
//  Created by Siprix Team.
//

import Foundation
import SwiftUI
import CallKit
import AVFoundation
import siprix

///////////////////////////////////////////////////////////////////////////////////////////////////
///AccountModel
///
class AccountModel : ObservableObject, Identifiable, Equatable  {
    @Published var regText = ""
    @Published var regState = RegState.inProgress
    
    let data : SiprixAccData;
    
    var id : Int { get { return Int(data.myAccId); } }
    
    var name: String {  get { return data.sipExtension + "@" + data.sipServer; }  }
    var accData: SiprixAccData {  get { return data }  }
            
    init(data : SiprixAccData) {
        self.data = data;
        regState = (data.expireTime==0) ? RegState.removed : RegState.inProgress
        regText  = (data.expireTime==0) ? "Removed" : "In progress..."
    }
    
    static func ==(lhs: AccountModel, rhs: AccountModel) -> Bool {
        return lhs.data.myAccId == rhs.data.myAccId
    }
    
    func updRegState(expireTime : Int32) {
        regState = .inProgress
        accData.expireTime = NSNumber(value: expireTime)
    }
}


///////////////////////////////////////////////////////////////////////////////////////////////////
///AccountsListModel
///
class AccountsListModel : ObservableObject {
    private let siprixModule_ : SiprixModule;
    private let logs : LogsModel?
    
    @Published private(set) var accounts: [AccountModel] = []
    @Published private(set) var selectedAccId = kInvalidId
        
    init(_ module: SiprixModule, logs: LogsModel?) {
        self.siprixModule_ = module
        self.logs = logs
    }
    
    public func add(_ accData : SiprixAccData) -> Int32 {
        let errCode = addInternal(accData);
        if(errCode==kErrorCodeEOK) { store() }
        return errCode
    }
    
    @discardableResult
    private func addInternal(_ accData : SiprixAccData) -> Int32 {
        logs?.printl("Adding account: \(accData.sipExtension)@\(accData.sipServer)")
        
        let errCode = siprixModule_.accountAdd(accData);
        if(errCode==kErrorCodeEOK) {
            accounts.append(AccountModel(data:accData))
            logs?.printl("Account added with id: \(accData.myAccId)")
            
            if(selectedAccId == kInvalidId) {
                selectedAccId = Int(accData.myAccId)
            }
        }
        else {
            logs?.printl("Can't add account: \(siprixModule_.getErrorText(errCode))")
        }
        return errCode
    }
    
    public func del(_ accId: Int) {
        let errCode = siprixModule_.accountDelete(Int32(accId));
        
        if(errCode == kErrorCodeEOK) {
            //Del from collection
            let accModelIdx = accounts.firstIndex(where: {$0.id == accId})
            if(accModelIdx != nil) {  accounts.remove(at:accModelIdx!) }
            
            logs?.printl("Deleted account id:\(accId)")
            
            if(selectedAccId == Int(accId)) {
                selectedAccId = accounts.isEmpty ? kInvalidId : accounts[0].id
            }
            
            store()
        }
        else {
            logs?.printl("Can't delete account id:\(accId) Error: \(siprixModule_.getErrorText(errCode))")
        }
    }
    
    public func reg(_ accId: Int) {
        let expireTime = Int32(300)
        let errCode = siprixModule_.accountRegister((Int32(accId)), expireTime:expireTime)
        
        if(errCode == kErrorCodeEOK) {
            let accModel = accounts.first(where: {$0.id == accId})
            accModel?.updRegState(expireTime:expireTime)
            store()
            
            logs?.printl("Refreshing registration account id:\(accId)")
        }
        else {
            logs?.printl("Can't register account id:\(accId) Error:\(siprixModule_.getErrorText(errCode))")
        }
    }
    
    public func unReg(_ accId: Int) {
        let errCode = siprixModule_.accountUnRegister((Int32(accId)))
        
        if(errCode == kErrorCodeEOK) {
            let accModel = accounts.first(where: {$0.id == accId})
            accModel?.updRegState(expireTime:0)
            store()
            
            logs?.printl("Unregistering account id:\(accId)")
        }
        else {
            logs?.printl("Can't unregister account id:\(accId) Error:\(siprixModule_.getErrorText(errCode))")
        }
    }
    
    var isEmpty : Bool { get { return accounts.isEmpty; }  }
    
    public func selectAcc(_ accId:Int) {
        selectedAccId = accId
    }
    
    public func isSelectedAcc(_ accId:Int) -> Bool {
        return (selectedAccId == accId)
    }
    
    public func getAccName(_ accId:Int) ->String {
        let accModel = accounts.first(where: {$0.data.myAccId == accId});
        return (accModel==nil) ? "-" : accModel!.name
    }
    
    //Serialize -----------------
    func store() {
        do {
            var accDictList = [[AnyHashable: Any]]()
            for acc in accounts  {
                accDictList.append(acc.accData.toDictionary())
            }
            
            let jsonData = try JSONSerialization.data(withJSONObject:accDictList)
            let jsonStr = String(data: jsonData, encoding: .utf8)
                        
            //Store selectedAcc as name because Siprix may assign another account id after app restart
            UserDefaults.standard.set(getAccName(selectedAccId), forKey: "selAccName")
            UserDefaults.standard.set(jsonStr, forKey: "accounts")
        } catch let error {
            print("Error storing accounts: \(error)")
        }
    }
    
    func load() {
        logs?.printl("Loading saved accounts")
        let selAccName = UserDefaults.standard.string(forKey: "selAccName")
        let jsonStr = UserDefaults.standard.string(forKey: "accounts")
        if (jsonStr == nil) { return }

        do {
            let accDictList = try JSONSerialization.jsonObject(with: Data(jsonStr!.utf8), options: []) as? [[String: Any]]
            accDictList?.forEach{
                let accData = SiprixAccData()
                accData.fromDictionary($0)
                
                addInternal(accData)
            }
            
            for acc in accounts {
                if(acc.name == selAccName) { selectAcc(acc.id); break; }
            }
            
            logs?.printl("Loaded '\(accounts.count)' account(s)")
        } catch let error {
            logs?.printl("Loading error: \(error)")
        }
    }
    
    //Event ---------------------
    
    public func onAccountRegState(_ accId: Int, regState: RegState, response: String) {
        logs?.printl("onAccountRegState id:\(accId) response:\(response)")
        
        let accModel = accounts.first(where: {$0.data.myAccId == accId});
        accModel?.regState = regState;
        accModel?.regText = response;
    }
}



///////////////////////////////////////////////////////////////////////////////////////////////////
///CallModel

class CallModel : ObservableObject, Identifiable, Equatable {
    private let siprixModule_ : SiprixModule;
    private let callKit : SiprixCxProvider?
    private let logs : LogsModel?
        
    @Published private(set) var callState : CallState
    @Published private(set) var isMicMuted = false
    @Published private(set) var isCamMuted = false    
    @Published private(set) var isSpeakerOn = false
    @Published private(set) var receivedDtmf = ""
    @Published private(set) var durationStr = ""
    
    private(set) var uuid = UUID()
    private(set) var myCallId : Int  //Assigned by Siprix module.
    //When this instance created by push - 'myCallId' will set to 'kInvalidId
    //  and proper value assigned only when received SIP INVITE
    //App has to match call by comparing data from push and SIP.
        
    private(set) var holdState = HoldState.none
    private(set) var withVideo = false
    private(set) var connectedTime = Date()
    private(set) var playerId = kInvalidId
    
    public  let isIncoming : Bool
    private(set) var accId : Int
    private(set) var from : String
    private(set) var to : String
    
    private(set) var connectedSuccessfully = false
    private(set) var endedByLocalSide = false
    
    #if os(iOS)
    public var cxAnswerAction : CXAnswerCallAction?
    public var cxEndAction : CXEndCallAction?
    #endif
           
    init(_ module: SiprixModule, logs: LogsModel?, callKit : SiprixCxProvider?,
         callId: Int, accId:Int, from:String, to:String, withVideo:Bool) {
        self.siprixModule_ = module
        self.callKit = callKit
        self.logs = logs
        
        self.myCallId = callId
        self.isIncoming = true
        self.callState = .ringing

        self.withVideo = withVideo
        self.accId = accId
        self.from = from
        self.to = to
    }

    init(_ module: SiprixModule, logs: LogsModel?, callKit : SiprixCxProvider?, destData:SiprixDestData) {
        self.siprixModule_ = module
        self.callKit = callKit
        self.logs = logs
        
        self.myCallId = Int(destData.myCallId)
        self.isIncoming = false
        self.callState = .dialing
        
        self.withVideo = (destData.withVideo != nil) ? destData.withVideo!.boolValue : false
        self.accId = Int(destData.fromAccId)
        self.from = SiprixModel.shared.accountsListModel.getAccName(Int(destData.fromAccId))
        self.to = destData.toExt
    }
    
    var id : Int { get { return myCallId } }
    var remoteSide : String { get { return isIncoming ? from : to } }
    var localSide  : String { get { return isIncoming ? to : from } }
    var isLocalHold  : Bool { get { return (holdState == .local)||(holdState == .localAndRemote) } }
    var isRemoteHold : Bool { get { return (holdState == .remote)||(holdState == .localAndRemote) } }
    var holdDisabled : Bool { get { return (callState != .connected)&&(callState != .held) } }
    
    static func ==(lhs: CallModel, rhs: CallModel) -> Bool {
        return lhs.uuid == rhs.uuid
    }
    
    public func updateDuration(_ curTime:Date) {
        if(callState == .connected) {
            let diff = Calendar.current.dateComponents([.minute, .second], from: connectedTime, to: curTime)
            durationStr = String(format: "%02d:%02d", diff.minute!, diff.second!)
        }
    }
    
    public var stateStr : String { get{
        switch self.callState {
            case .dialing:    return "Dialing"
            case .proceeding: return "Proceeding"
            case .ringing:    return "Ringing"
            case .rejecting:  return "Rejecting"
            case .accepting:  return "Accepting"
            case .connected:  return "Connected"
            case .disconnecting: return "Disconnecting"
            case .holding:    return "Holding"
            case .held:       return "Held"
            case .transferring:  return "Transferring"
            default:          return "Unknown"
        }
    }}
    
    public var holdStr : String { get {
        switch self.holdState {
            case .none:   return "None"
            case .local:  return "Local hold"
            case .remote: return "Remote hold"
            case .localAndRemote: return "LocalAndRemote hold"
            default:      return "Unknown"
        }
    }}
    
    public func playFile() {
        playFile(Bundle.main.path(forResource: "office_ringtone", ofType: "mp3"))
    }
    
    public func playFile(_ path: String?) {
        if (path == nil) {
            return
        }
               
        let playerData = SiprixPlayerData()
        let errCode = siprixModule_.callPlayFile(Int32(myCallId), pathToMp3File: path!, loop:false, playerData: playerData)
        if(errCode == kErrorCodeEOK) {
            playerId = Int(playerData.playerId)
            logs?.printl("PlayFile started playerId:\(playerId)")
        } else {
            logs?.printl("Can't playFile call id:\(myCallId) Error:\(siprixModule_.getErrorText(errCode))")
        }
    }

    public func reject() {
        logs?.printl("Rejecting call id:\(myCallId)")
        
        let errCode = siprixModule_.callReject(Int32(myCallId), statusCode:486)
        if(errCode == kErrorCodeEOK) {
            callState = .rejecting
        } else {
            logs?.printl("Can't reject call id:\(myCallId) Error:\(siprixModule_.getErrorText(errCode))")
        }
    }
    
    @discardableResult
    public func accept(cxPost:Bool = true) -> Bool {
        logs?.printl("Accepting call id:\(myCallId) cxPost:\(cxPost)")
        
        if((callKit != nil) && cxPost) {
            callKit!.cxActionAnswer(self)
            return true
        }
        
        let errCode = siprixModule_.callAccept(Int32(myCallId), withVideo:withVideo)
        if(errCode == kErrorCodeEOK) {
            callState = .accepting
            return true
        } else {
            logs?.printl("Can't accept call id:\(myCallId) Error:\(siprixModule_.getErrorText(errCode))")
            return false
        }
    }
    
    @discardableResult
    public func muteMic(_ mute: Bool, cxPost:Bool = true) -> Bool {
        logs?.printl("Muting mic call id:\(myCallId) mute:\(mute) cxPost:\(cxPost)")
        
        if((callKit != nil) && cxPost) {
            callKit!.cxActionSetMuted(self, muted:mute)
            return true
        }

        let errCode = siprixModule_.callMuteMic(Int32(myCallId), mute:mute)
        if(errCode == kErrorCodeEOK) {
            isMicMuted = mute
            return true
        } else {
            logs?.printl("Can't mute call id:\(myCallId) Error:\(siprixModule_.getErrorText(errCode))")
            return false
        }
    }
    
    @discardableResult
    public func muteCam(_ mute: Bool) -> Bool {
        logs?.printl("Muting cam call id:\(myCallId) mute:\(mute)")
        
        let errCode = siprixModule_.callMuteCam(Int32(myCallId), mute:mute)
        if(errCode == kErrorCodeEOK) {
            isCamMuted = mute
            return true
        } else {
            logs?.printl("Can't mute cam call id:\(myCallId) Error:\(siprixModule_.getErrorText(errCode))")
            return false
        }
    }
    
    @discardableResult
    public func sendDtmf(_ digits: String, cxPost:Bool = true) -> Bool {
        logs?.printl("Sending dtmf call id:\(myCallId) digits:\(digits) cxPost:\(cxPost)")
        
        if((callKit != nil) && cxPost) {
            callKit!.cxActionPlayDtmf(self, digits:digits)
            return true
        }
        
        let errCode = siprixModule_.callSendDtmf(Int32(myCallId), dtmfs:digits)
        if(errCode != kErrorCodeEOK) {
            logs?.printl("Can't send dtmf Error:\(siprixModule_.getErrorText(errCode))")
            return false
        }
        return true
    }
    
    @discardableResult
    public func hold(cxPost:Bool = true) -> Bool {
        logs?.printl("Hold call id:\(myCallId) cxPost:\(cxPost)")
        if(holdDisabled) {
            return false
        }
        
        if((callKit != nil) && cxPost) {
            callKit!.cxActionSetHeld(self, hold:(holdState == .none))
            return true
        }
        
        let errCode = siprixModule_.callHold(Int32(myCallId))
        if(errCode == kErrorCodeEOK) {
            callState = .holding
            return true
        } else {
            logs?.printl("Can't hold call id:\(myCallId) Error:\(siprixModule_.getErrorText(errCode))")
            return false
        }
    }
    
    public func transferBlind(toExt: String) {
        logs?.printl("Transfer blind callId:\(myCallId) to: \(toExt)")
        if(toExt.isEmpty) {
            return;
        }
        
        let errCode = siprixModule_.callTransferBlind(Int32(myCallId), toExt:toExt)
        if(errCode == kErrorCodeEOK) {
            self.callState = .transferring
        } else {
            logs?.printl("Can't transfer call id:\(myCallId) Error:\(siprixModule_.getErrorText(errCode))")
        }
    }
    
    @discardableResult
    public func bye(cxPost:Bool = true) -> Bool {
        logs?.printl("Ending call id:\(myCallId) cxPost:\(cxPost)")
        
        if((callKit != nil) && cxPost) {
            callKit!.cxActionEndCall(self)
            return true
        }
        
        let errCode = siprixModule_.callBye(Int32(myCallId))
        if(errCode == kErrorCodeEOK) {
            endedByLocalSide = true
            callState = .disconnecting
            return true
        } else {
            logs?.printl("Can't bye call id:\(myCallId). Error:\(siprixModule_.getErrorText(errCode))")
            return false
        }
    }
    
    public func updateByInvite(callId:Int, accId:Int,
                               from:String, to:String, withVideo:Bool) {
        logs?.printl("updateByInvite call id:\(myCallId) uuid:\(uuid))")
        
        self.myCallId = callId
        self.accId  = accId
        self.from = from
        self.to = to
        self.withVideo = withVideo
        
        //if callKitAnswered {
        //               let bRet = answerCallWithUUID(uuid: session.uuid, isVideo: existsVideo)
        //               session.callKitCompletionCallback?(bRet)
        //               reportUpdateCall(uuid: session.uuid, hasVideo: existsVideo, from: remoteParty)
        //TODO update call
    }
    
    #if os(iOS)
    public func switchSpeaker(_ on: Bool) {
        let res = siprixModule_.overrideAudioOutput(toSpeaker: on)
        if(res) { self.isSpeakerOn = on  }
        logs?.printl("SwitchSpeaker \(res ? "success" : "error")")
    }
       
    public func routeAudioToBluetoth() {
        let res = siprixModule_.routeAudioToBluetoth()
        if(res) { self.isSpeakerOn = false }
        logs?.printl("RouteAudioToBluetoth \(res ? "success" : "error")")
    }
    
    public func routeAudioToBuiltIn() {
        let res = siprixModule_.routeAudioToBuiltIn()
        if(res) { self.isSpeakerOn = false  }
        logs?.printl("RouteAudioToBuiltIn \(res ? "success" : "error")")
    }
    
    public func setVideoView(_ view: UIView?, isPreview : Bool) {
        siprixModule_.callSetVideoWindow(isPreview ? 0 : Int32(myCallId), view: view)
    }
    #elseif os(macOS)
    public func setVideoView(_ view: NSView?, isPreview : Bool) {
        siprixModule_.callSetVideoWindow(isPreview ? 0 : Int32(myCallId), view: view)
    }
    #endif
    
    //-----------------------------------------------------------------
    //Events
    
    public func onCallProceeding(_ response:String) {
        callState = .proceeding
        //response = response
    }
    
    public func onCallConnected(hdrFrom:String, hdrTo:String, withVideo:Bool) {
        self.withVideo = withVideo
        connectedSuccessfully = true
        connectedTime = Date()//update time
        callState = .connected
        from = hdrFrom
        to = hdrTo
    }
    
    public func onCallDtmfReceived(_ tone:Int) {
        switch(tone) {
            case 10: self.receivedDtmf += "*"
            case 11: self.receivedDtmf += "#"
            default: self.receivedDtmf += String(tone)
        }
    }
    
    public func onTransferred(_ statusCode: Int) {
        self.callState = CallState.connected
    }
    
    public func onCallHeld(_ holdState: HoldState) {
        self.holdState = holdState
        self.callState = (holdState == .none) ? .connected : .held
    }
    
    public func onPlayerState(_ playerState: PlayerState) {
        if((playerState == .failed)||(playerState == .stopped)) {
            self.playerId = kInvalidId
        }
    }
}


///////////////////////////////////////////////////////////////////////////////////////////////////
///CallsListModel

class CallsListModel : ObservableObject {
    private let siprixModule_ : SiprixModule
    private var callKit : SiprixCxProvider?
    private let logs : LogsModel?
    
    @Published private(set) var calls: [CallModel] = []
    @Published private(set) var switchedCallId = kInvalidId
    @Published private(set) var switchedCall : CallModel? = nil
    
    init(_ module: SiprixModule, logs: LogsModel?) {
        self.siprixModule_ = module;
        self.logs = logs
    }
    
    public func setCallKitProvider(_ callKit : SiprixCxProvider?) {
        self.callKit = callKit
    }
    
    public func isSwitchedCall(_ callId: Int) ->Bool {
        return (switchedCallId == callId)
    }
    
    public func switchToCall(_ callId: Int) {
        logs?.printl("SwitchToCall Id: \(callId)")
        
        siprixModule_.mixerSwitchCall(Int32(callId))
        
        //Don't set 'switchedCallId' here, it updated by 'onCallSwitched' callback
    }
    
    public func makeConference() {
        logs?.printl("MakeConference")
        
        siprixModule_.mixerMakeConference()
    }
    
    public func updateDuration(_ curTime:Date) {
        for c in calls {
            c.updateDuration(curTime)
        }
    }
    
    public func invite(_ destData: SiprixDestData) -> Int32 {
        logs?.printl("Trying to invite \(destData.toExt) from account:\(destData.fromAccId)")
        
        let errCode = siprixModule_.callInvite(destData)
        if(errCode == kErrorCodeEOK) {
            let call = CallModel(siprixModule_, logs:logs, callKit:callKit, destData:destData)
            calls.append(call)
            
            logs?.printl("Added call with Id: \(destData.myCallId)")
            
            callKit?.cxActionNewOutgoingCall(call)
        }
        else {
            logs?.printl("Can't invite. Error:\(siprixModule_.getErrorText(errCode))")
        }
        return errCode
    }
    
    public func  getCallByUUID(_ uuid: UUID) -> CallModel? {
        return calls.first(where: {$0.uuid == uuid})
    }
    
    private func matchExistingCallCreatedByPush(from:String, to:String) -> CallModel? {
        //TODO debug PushKit redesign depending on the data received in push
        return calls.first(where: {($0.from == from)&&($0.to == to)&&($0.id == 0) })
    }
    
    public func onPushIncoming(_ withVideo:Bool, hdrFrom:String, hdrTo:String) {
        logs?.printl("onPushIncoming hdrFrom:\(hdrFrom) hdrTo:\(hdrTo)")
        
        //Add temporary call, present UI and wait INVITE - see 'onIncomingCall'
        let call = CallModel(siprixModule_, logs:logs, callKit:callKit, callId:kInvalidId, accId:kInvalidId,
                                 from:hdrFrom, to:hdrTo, withVideo:withVideo)
        
        calls.append(call)
        
        callKit?.cxActionNewIncomingCall(call)
    }
    
    #if os(iOS)
    func activateSession(_ audioSession: AVAudioSession) {
        siprixModule_.activate(audioSession)
    }

    func deactivateSession(_ audioSession: AVAudioSession) {
        siprixModule_.deactivate(audioSession)
    }
    #endif
    
    //---------------------
    //Events
    public func onCallSwitched(_ callId: Int) {
        logs?.printl("onSwitched callId: \(callId)")
        
        switchedCallId = callId
        switchedCall = calls.first(where: {$0.id == callId})
    }
    
    public func onCallProceeding(_ callId: Int, response:String) {
        logs?.printl("onProceeding callId: \(callId) response:\(response)")
        
        let call = calls.first(where: {$0.id == callId})
        call?.onCallProceeding(response)
        
        callKit?.cxActionProceeding(call)
    }
    
    public func onCallTerminated(_ callId: Int, statusCode:Int) {
        logs?.printl("onTerminated callId: \(callId) statusCode:\(statusCode)")
        
        let callIdx = calls.firstIndex(where: {$0.id == callId})
        if(callIdx != nil) {
            callKit?.cxActionTerminated(calls[callIdx!])
            
            calls.remove(at:callIdx!)
        }
    }
    
    public func onCallConnected(_ callId: Int, hdrFrom:String, hdrTo:String, withVideo:Bool) {
        logs?.printl("onConnected callId: \(callId) hdrFrom:\(hdrFrom) hdrTo:\(hdrTo)")
        
        let call = calls.first(where: {$0.id == callId})
        call?.onCallConnected(hdrFrom:hdrFrom, hdrTo:hdrTo, withVideo:withVideo)
        
        callKit?.cxActionConnected(call)
    }
    
    public func onCallIncoming(_ callId:Int, accId:Int, withVideo:Bool, hdrFrom:String, hdrTo:String) {
        logs?.printl("onIncoming callId: \(callId) accId:\(accId) hdrFrom:\(hdrFrom) hdrTo:\(hdrTo)")
        
        //Search existing item (created by push) which matches this SIP call
        var call = matchExistingCallCreatedByPush(from:hdrFrom, to:hdrTo)
        if(call != nil) {
            call!.updateByInvite(callId:callId, accId:accId,
                                from:hdrFrom, to:hdrTo, withVideo:withVideo)
        } else {
            call = CallModel(siprixModule_, logs:logs, callKit:callKit, callId:callId, accId:accId,
                                 from:hdrFrom, to:hdrTo, withVideo:withVideo)
            calls.append(call!)
            callKit?.cxActionNewIncomingCall(call!)
        }
    }
    
    public func onCallDtmfReceived(_ callId:Int, tone:Int) {
        logs?.printl("onDtmfReceived callId: \(callId) tone:\(tone)")
        
        let call = calls.first(where: {$0.id == callId})
        call?.onCallDtmfReceived(tone)
    }
    
    public func onCallHeld(_ callId: Int, holdState: HoldState) {
        logs?.printl("onHeld callId: \(callId) holdState:\(holdState)")
        
        let call = calls.first(where: {$0.id == callId})
        call?.onCallHeld(holdState)
    }
    
    public func onCallTransferred(_ callId: Int, statusCode: Int) {
        logs?.printl("onTransferred callId:\(callId) statusCode:\(statusCode)")
           
        let call = calls.first(where: {$0.id == callId})
        call?.onTransferred(statusCode)
    }

    public func onCallRedirected(origCallId: Int, relatedCallId: Int,
                                 referTo: String) {
        logs?.printl("onRedirected origCallId:\(origCallId) relatedCallId:\(relatedCallId) to:\(referTo)")
    
        //Find 'origCallId'
        let origCall = calls.first(where: {$0.id == origCallId})
        if(origCall != nil) {
            //Clone 'origCall' and add to collection of calls as related one
            calls.append(CallModel(siprixModule_, logs:logs, callKit:callKit,
                                       callId:relatedCallId, accId:origCall!.accId,
                                       from:origCall!.from, to:referTo,
                                       withVideo:origCall!.withVideo))//TODO CallKit case
        }
    }
    
    public func onPlayerState(_ playerId: Int, playerState: PlayerState) {
        logs?.printl("onPlayerState playerId: \(playerId) playerState:\(playerState)")
        
        let call = calls.first(where: {$0.playerId == playerId})
        call?.onPlayerState(playerState)
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
///LogsModel

class LogsModel : ObservableObject {
    @Published private(set) var text = ""
    
    public func printl(_ txt:String) {
        print(txt)
        
        //Comment code below when displaying logs text on UI is not required
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss "
                
        text += dateFormatter.string(from: Date())
        text += txt
        text += "\n"
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
///NetworkModel

class NetworkModel : ObservableObject {
    @Published private(set) var lost = false
    @Published private(set) var name = ""
    private let logs : LogsModel?
      
    init(logs : LogsModel?) {
        self.logs = logs
    }
    
    public func onNetworkState(_ name: String, netState: NetworkState)  {
        logs?.printl("onNetworkState name:\(name) netState:\(netState)")
           
        self.lost = netState == .lost
        self.name = name
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
///SiprixModel

class SiprixModel : NSObject, SiprixEventDelegate {
    private let siprixModule_  : SiprixModule
    private let siprixCxProvider : SiprixCxProvider?
    public  let accountsListModel : AccountsListModel
    public  let callsListModel : CallsListModel
    public  let networkModel : NetworkModel
    public  let logs : LogsModel?
    public  let singleCallMode : Bool
    private let ringer : Ringer?
    
    static let shared = SiprixModel()
    
    private override init() {
        siprixModule_  = SiprixModule()
        
        //If multiple simultaneous calls not required set to 'true'
        singleCallMode = false
        
        //If logging not required - set to nil
        logs = LogsModel()
        //logs_ = nil
        
        accountsListModel = AccountsListModel(siprixModule_, logs:logs)
        callsListModel    = CallsListModel(siprixModule_, logs:logs)
        networkModel      = NetworkModel(logs:logs)

        //If callKit support not required - set to nil
        #if os(iOS) && !targetEnvironment(simulator)           
        siprixCxProvider = SiprixCxProvider(callsListModel, logs:logs, singleCallMode:singleCallMode)
        #else
        siprixCxProvider = nil
        #endif
        
        //Ringer (create only when CallKit disabled)
        ringer = (siprixCxProvider==nil) ? Ringer(logs:logs) : nil
        
        super.init()
    }
    
    deinit {
        uninitialize()
    }
    
    public func initialize() {
        //Path where SDK will store log file
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        //Set init data params
        let iniData = SiprixIniData()
        iniData.license = "...license-credentials..."
        iniData.homeFolder = documentsURL.path + "/"
        iniData.singleCallMode = NSNumber(value: singleCallMode)
        iniData.logLevelIde  = NSNumber(value: LogLevel.debug.rawValue)
        iniData.logLevelFile = NSNumber(value: LogLevel.info.rawValue)
        //iniData.tlsVerifyServer = true
        
        //Initialize module
        let errCode = siprixModule_.initialize(self, iniData:iniData)
        if(errCode == kErrorCodeEOK) {
            logs?.printl("Siprix module initialized successfully")
            logs?.printl("Version: \(siprixModule_.version())")
            
            #if os(iOS)
            siprixModule_.enableCallKit(siprixCxProvider != nil)
            #endif
            
            accountsListModel.load()
        }
        else {
            logs?.printl("Can't initialize siprix module")
            logs?.printl(getErrorText(errCode))
        }
    }
    
    
    public func uninitialize() {
        siprixModule_.unInitialize();
    }

        
    public func getErrorText(_ errCode : Int32) ->String {
        return siprixModule_.getErrorText(errCode)
    }
    
    #if os(iOS)
    public func createVideoView() -> UIView {
        return siprixModule_.createVideoWindow()
    }
    #elseif os(macOS)
    public func createVideoView() -> NSView {
        return siprixModule_.createVideoWindow()
    }
    #endif
    
    ///------------------------------------------------------------------------------
    ///SiprixEventDelegate
    public func onTrialModeNotified() {
        DispatchQueue.main.async {
            self.logs?.printl("--- SIPRIX SDK is working in TRIAL mode ---")
        }
    }
    
    public func onDevicesAudioChanged() {
    }
    
    public func onAccountRegState(_ accId: Int, regState: RegState, response: String) {
        DispatchQueue.main.async {
            self.accountsListModel.onAccountRegState(accId, regState: regState, response: response)
        }
    }
    public func onNetworkState(_ name: String, netState: NetworkState) {
        DispatchQueue.main.async {
            self.networkModel.onNetworkState(name, netState:netState)
        }
    }
    
    public func onPlayerState(_ playerId: Int, playerState: PlayerState) {
        DispatchQueue.main.async {
            self.callsListModel.onPlayerState(playerId, playerState:playerState)
        }
    }
    
    public func onRingerState(_ started: Bool) {
        DispatchQueue.main.async {
            if(started) { self.ringer?.play() }
            else        { self.ringer?.stop() }
        }
    }

    public func onCallProceeding(_ callId: Int, response:String) {
        DispatchQueue.main.async {
            self.callsListModel.onCallProceeding(callId, response:response)
        }
    }

    public func onCallTerminated(_ callId: Int, statusCode:Int) {
        DispatchQueue.main.async {
            self.callsListModel.onCallTerminated(callId, statusCode:statusCode)
        }
    }

    public func onCallConnected(_ callId: Int, hdrFrom:String, hdrTo:String, withVideo:Bool) {
        DispatchQueue.main.async {
            self.callsListModel.onCallConnected(callId, hdrFrom:hdrFrom, hdrTo:hdrTo, withVideo:withVideo)
        }
    }

    public func onCallIncoming(_ callId:Int, accId:Int, withVideo:Bool, hdrFrom:String, hdrTo:String) {
        DispatchQueue.main.async {
            self.callsListModel.onCallIncoming(callId, accId:accId, withVideo:withVideo, hdrFrom:hdrFrom, hdrTo:hdrTo)
        }
    }

    public func onCallDtmfReceived(_ callId:Int, tone:Int) {
        DispatchQueue.main.async {
            self.callsListModel.onCallDtmfReceived(callId, tone:tone)
        }
    }
                    
    public func onCallSwitched(_ callId: Int) {
        DispatchQueue.main.async {
            self.callsListModel.onCallSwitched(callId)
        }
    }

    public func onCallTransferred(_ callId: Int, statusCode: Int) {
        DispatchQueue.main.async {
            self.callsListModel.onCallTransferred(callId, statusCode:statusCode)
        }
    }

    public func onCallRedirected(_ origCallId: Int, relatedCallId: Int,
                                 referTo: String) {
        DispatchQueue.main.async {
            self.callsListModel.onCallRedirected(origCallId:origCallId, relatedCallId:relatedCallId, referTo:referTo)
        }
    }

    public func onCallHeld(_ callId: Int, holdState: HoldState) {
        DispatchQueue.main.async {
            self.callsListModel.onCallHeld(callId, holdState:holdState)
        }
    }
    
    func onSubscriptionState(_ subscrId: Int, subscrState: SubscrState, response: String) {
        //Handle subscription state
    }
    
    func onMessageSentState(_ messageId: Int, success: Bool, response: String) {
        //Handle message sent state
    }
    
    func onMessageIncoming(_ accId: Int, hdrFrom: String, body: String) {
        //handle received message request
    }
        
}//SiprixModel

#if os(iOS)
///////////////////////////////////////////////////////////////////////////////////////////////////
///SiprixCxProvider

class SiprixCxProvider : NSObject, CXProviderDelegate {
    private(set) var cxProvider: CXProvider!
    private(set) var cxCallCtrl: CXCallController
    private let callsListModel : CallsListModel
    private let logs : LogsModel?
      
    init(_ callsListModel : CallsListModel, logs : LogsModel?, singleCallMode:Bool) {
        self.callsListModel = callsListModel
        self.cxCallCtrl = CXCallController()
        self.logs = logs
        
        super.init()
                
        createCxProvider(singleCallMode)
        
        self.callsListModel.setCallKitProvider(self)
    }
    
    private func createCxProvider(_ singleCallMode : Bool) {
        let providerConfiguration = CXProviderConfiguration()
        providerConfiguration.supportsVideo = true
        providerConfiguration.maximumCallsPerCallGroup = singleCallMode ? 1 : 5
        providerConfiguration.maximumCallGroups = singleCallMode ? 1 : 5
        providerConfiguration.supportedHandleTypes = [.phoneNumber, .generic]
        //providerConfiguration.includesCallsInRecents: Bool
        
        if let iconMaskImage = UIImage(named: "CallkitIcon") {
            providerConfiguration.iconTemplateImageData = iconMaskImage.pngData()
        }

        self.cxProvider = CXProvider(configuration: providerConfiguration)
        self.cxProvider.setDelegate(self, queue: DispatchQueue.main)
    }
    
    
    func cxActionNewOutgoingCall(_ call : CallModel) {
        let handle = CXHandle(type: .generic, value: call.to)
        let action = CXStartCallAction(call: call.uuid, handle: handle)
        action.isVideo = call.withVideo
        
        let transaction = CXTransaction(action: action)
        cxCallCtrl.request(transaction) { error in self.printResult("CXStart", err:error) }
    }
    
    func cxActionNewIncomingCall(_ call : CallModel) {
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: call.from)
        update.hasVideo = call.withVideo
        update.supportsUngrouping = true
        update.supportsGrouping = true
        update.supportsHolding = true
        update.supportsDTMF = true
        
        cxProvider.reportNewIncomingCall(with: call.uuid, update: update,
                                         completion: { error in self.printResult("CXCallUpdate", err:error)
        })
    }
   
    func cxActionProceeding(_ call: CallModel?) {
        if(call != nil) {
            cxProvider.reportOutgoingCall(with:call!.uuid, startedConnectingAt: nil)
        }
    }
    
    func cxActionConnected(_ call: CallModel?) {
        if(call != nil) {
            cxProvider.reportOutgoingCall(with:call!.uuid, connectedAt: nil)
        }
    }
    
    func cxActionTerminated(_ call: CallModel) {
        if(!call.endedByLocalSide) {
            var reason : CXCallEndedReason = .failed
            if(call.connectedSuccessfully||call.isIncoming) {  reason = .remoteEnded } else
            if(!call.isIncoming) { reason = .unanswered }
            
            cxProvider.reportCall(with:call.uuid, endedAt: nil, reason: reason)
        }
    }

    func cxActionPlayDtmf(_ call: CallModel, digits: String) {
        let action = CXPlayDTMFCallAction(call: call.uuid, digits: digits, type: .singleTone)
        let transaction = CXTransaction(action: action)
        
        cxCallCtrl.request(transaction) { error in self.printResult("CXPlayDTMF", err:error) }
    }

    func cxActionSetHeld(_ call: CallModel, hold: Bool) {
        let action = CXSetHeldCallAction(call: call.uuid, onHold: hold)
        let transaction = CXTransaction(action: action)
        
        cxCallCtrl.request(transaction) { error in self.printResult("CXSetHeld", err:error) }
    }

    func cxActionSetMuted(_ call: CallModel, muted: Bool) {
        let action = CXSetMutedCallAction(call: call.uuid, muted: muted)
        let transaction = CXTransaction(action: action)
        
        cxCallCtrl.request(transaction) { error in self.printResult("CXSetMuted", err:error) }
    }
    
    func cxActionEndCall(_ call: CallModel) {
        let action = CXEndCallAction(call: call.uuid)
        let transaction = CXTransaction(action: action)
        
        cxCallCtrl.request(transaction) { error in self.printResult("CXEndCall", err:error) }
    }

    func cxActionAnswer(_ call: CallModel) {
        let action = CXAnswerCallAction(call: call.uuid)
        let transaction = CXTransaction(action: action)
        
        cxCallCtrl.request(transaction) { error in self.printResult("CXAnswer", err:error) }
    }
    
    func printResult(_ name: String, err: Error?) {
        let strErr = (err != nil) ? ("Error requesting \(name) :\(err!)") : ("\(name) requested successfully")
        DispatchQueue.main.async {
            self.logs?.printl(strErr)
        }
    }

    ///------------------------------------------------------------------------------
    ///CXProviderDelegate
    ///
    func providerDidReset(_ provider: CXProvider) {
        logs?.printl("providerDidReset")
    }
    
    func provider(_: CXProvider, perform action: CXStartCallAction) {
        logs?.printl("CXStartCall uuid:\(action.callUUID)")
        //TODO Case starting call from NativeUI
        
        let call = callsListModel.getCallByUUID(action.callUUID)
        if(call != nil) {
           //if(callsListModel.inviteWithUUID(callee: action.handle.value,
            //      displayName: action.handle.value, videoCall: action.isVideo, uuid: action.callUUID))  {
            action.fulfill()
        } else {
            action.fail()
        }
    }
    
    func provider(_: CXProvider, perform action: CXEndCallAction) {
        logs?.printl("CXEndCall uuid:\(action.callUUID)")
        
        let call = callsListModel.getCallByUUID(action.callUUID)
        if(call != nil) {
            if(call!.callState == .ringing) { call!.reject() }
            else                            { call!.bye(cxPost:false) }
        }
        
        action.fulfill()
    }
    
    func provider(_: CXProvider, perform action: CXPlayDTMFCallAction) {
        logs?.printl("CXPlayDTMF uuid:\(action.callUUID) dtmf:\(action.digits)")
       
        let call = callsListModel.getCallByUUID(action.callUUID)
        if((call != nil) && call!.sendDtmf(action.digits, cxPost:false)) {
            action.fulfill()
        }
        else {
            action.fail()
        }
    }

    func provider(_: CXProvider, perform action: CXSetHeldCallAction) {
        logs?.printl("CXSetHeld uuid:\(action.callUUID) isOnHold:\(action.isOnHold)")
       
        let call = callsListModel.getCallByUUID(action.callUUID)
        if((call != nil) && call!.hold(cxPost:false)) { //TODO use 'action.isOnHold'
            action.fulfill()
        }
        else {
            action.fail()
        }
    }
    
    func provider(_: CXProvider, perform action: CXSetMutedCallAction) {
        logs?.printl("CXSetMuted uuid:\(action.callUUID) muted:\(action.isMuted)")
       
        let call = callsListModel.getCallByUUID(action.callUUID)
        if((call != nil) && call!.muteMic(action.isMuted, cxPost:false)) {
            action.fulfill()
        }
        else {
            action.fail()
        }
    }
    
    func provider(_: CXProvider, perform action: CXAnswerCallAction) {
        let call = callsListModel.getCallByUUID(action.callUUID)
        if(call == nil) {
            logs?.printl("CXAnswer not found uuid:\(action.callUUID)")
            action.fail()
            return
        }
       
        logs?.printl("CXAnswer uuid:\(action.callUUID) call id:\(call!.id)")
        if (call!.id == kInvalidId) {
            //INVITE hasn't received yet
            call!.cxAnswerAction = action
            return;
        }
            
        if (call!.accept(cxPost:false)) {
            action.fulfill()
        } else {
            action.fail()
        }
    }
    
    func provider(_: CXProvider, timedOutPerforming _: CXAction) {
    }
    
    func provider(_: CXProvider, perform action: CXSetGroupCallAction) {
        let call = callsListModel.getCallByUUID(action.callUUID)
        if(call == nil) {
            logs?.printl("CXSetGroup not found uuid:\(action.callUUID)")
            action.fail()
            return
        }
        
        if (action.callUUIDToGroupWith != nil) {
            logs?.printl("CXSetGroup group uuid:\(action.callUUID) with:\(action.callUUIDToGroupWith!)")
            callsListModel.makeConference()
        } else {
            logs?.printl("CXSetGroup ungroup uuid:\(action.callUUID)")
            callsListModel.switchToCall(call!.id)
        }
        action.fulfill()
    }
   
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        callsListModel.activateSession(audioSession)
    }

    func provider(_: CXProvider, didDeactivate audioSession: AVAudioSession) {
        callsListModel.deactivateSession(audioSession)
    }
    
}//SiprixCxProvider

#elseif os(macOS)
class SiprixCxProvider : NSObject {
    func cxActionNewOutgoingCall(_ call : CallModel) {}
    func cxActionAnswer(_ call: CallModel) {}
    func cxActionSetMuted(_ call: CallModel, muted: Bool) {}
    func cxActionPlayDtmf(_ call: CallModel, digits: String) {}
    func cxActionSetHeld(_ call: CallModel, hold: Bool) {}
    func cxActionNewIncomingCall(_ call : CallModel) {}
    func cxActionProceeding(_ call: CallModel?) {}
    func cxActionTerminated(_ call: CallModel) {}
    func cxActionConnected(_ call: CallModel?) {}
    func cxActionEndCall(_ call: CallModel) {}
}
#endif
    
///////////////////////////////////////////////////////////////////////////////////////////////////
///Ringer

class Ringer {
    private var player: AVAudioPlayer!
    private(set) var speakerOn: Bool!
    private let logs : LogsModel?
    
    init(logs : LogsModel?) {
        self.logs = logs
    }

    func initPlayerWithPath(_ path: String) -> AVAudioPlayer {
        let url = URL(fileURLWithPath: Bundle.main.path(forResource: path, ofType: nil)!)

        var avPlayer: AVAudioPlayer!
        do {
            avPlayer = try AVAudioPlayer(contentsOf: url)
        } catch {}

        return avPlayer
    }

    func unInit() {
        if player != nil {
            if player.isPlaying {
                player.stop()
            }
        }
    }

    private func enableSpeaker(_ enabled: Bool) {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        var options = session.categoryOptions

        if enabled {
            options.insert(AVAudioSession.CategoryOptions.defaultToSpeaker)
        } else {
            options.remove(AVAudioSession.CategoryOptions.defaultToSpeaker)
        }
        do {
            try session.setCategory(AVAudioSession.Category.playAndRecord, options: options)
            logs?.printl("Ringer started playing successfully")
        } catch {
            logs?.printl("Can't start ringer: error \(error)")
        }
        #endif
    }

    func isSpeakerEnabled() -> Bool {
        speakerOn
    }

    @discardableResult
    func play() -> Bool {
        if player == nil {
            player = initPlayerWithPath("office_ringtone.mp3")
        }
        if player != nil {
            player.numberOfLoops = -1
            enableSpeaker(true)
            player.play()
            return true
        }
        return false
    }

    @discardableResult
    func stop() -> Bool {
        if player != nil, player.isPlaying {
            player.stop()
            enableSpeaker(false)
        }
        return true
    }
    
}//Ringer

