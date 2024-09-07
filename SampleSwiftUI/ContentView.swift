//
//  ContentView.swift
//  SampleSwiftUI
//
//  Created by Siprix Team.
//

import SwiftUI
import siprix

///////////////////////////////////////////////////////////////////////////////////////////////////
///AccountView
///
struct AccountRowView: View {
    private var accList : AccountsListModel
    @StateObject private var acc : AccountModel
    @State private var delAccAlert = false
    
    init(_ acc: AccountModel, accList: AccountsListModel) {
        self._acc = StateObject(wrappedValue: acc)
        self.accList = accList
    }
    
    private var regStateImgName: String {
        get {
            switch acc.regState{
                case .success: return "checkmark.icloud"
                case .failed:  return "xmark.icloud"
                case .removed: return "checkmark"
                default: return "arrow.clockwise.icloud"
            }
        }
    }
    
    private var regStateImgColor : Color {
        get {
            switch acc.regState {
                case .success: return .green
                case .failed:  return .red
                default: return .gray
            }
        }
    }

    var body: some View {
        VStack {
            HStack {
                if(acc.regState == RegState.inProgress) {
                    ProgressView()
                }else {
                    Image(systemName: regStateImgName)
                        .foregroundColor(regStateImgColor)
                        .font(.title)
                }
                
                VStack(alignment: .leading) {
                    Text(acc.name).font(.headline)
                    Text("ID: \(acc.id) REG:\(acc.regText)")
                        .font(.subheadline).foregroundColor(.gray).italic()
                }
                
                Spacer()
                Menu() {
                    Button("Register")   { accList.reg(  acc.id) }
                    Button("Unregister") { accList.unReg(acc.id) }
                    Button("Delete")     { delAccAlert = true    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill").font(.title)
                }
                .padding(10)
                .alert(isPresented: $delAccAlert) {
                    Alert(
                        title: Text("Confirm deleting account?"),
                        message: Text(acc.name),
                        primaryButton: .destructive(Text("Delete")) {
                            accList.del(acc.id);
                        },
                        secondaryButton: .cancel()
                    )
                }
            }
            Divider()
        }//VStack
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
///AccountsListView

struct AccountsListView: View {
    @StateObject private var accList : AccountsListModel
    @State private var addAccNavTag = false
    @State private var addAccSheet = false
            
    init(_ accList: AccountsListModel) {
        self._accList = StateObject(wrappedValue: accList)
    }
    
    var body: some View {
        VStack {
            if(accList.accounts.isEmpty) {
                getAddAccBtn(fontTitle:true)
            }else {
                HStack {
                    Spacer()
                    getAddAccBtn(fontTitle:false).padding(.trailing)
                }
                Divider()
                
                ScrollView {
                    ForEach(accList.accounts) {
                        acc in AccountRowView(acc, accList:accList)
                            .onTapGesture { accList.selectAcc(acc.id) }
                            .overlay(alignment: .topTrailing) {
                                if(accList.isSelectedAcc(acc.id)) {
                                    Circle().foregroundStyle(.blue).frame(width: 10, height: 10)
                                }
                            }
                    }
                }
            }
        }
        .sheet(isPresented: $addAccSheet) {
            AccountAddView(accList)
        }
    }
  
    func getAddAccBtn(fontTitle: Bool) -> some View {
        Button(action: { addAccSheet = true  }) {
            Text("Add account")
            Image(systemName: fontTitle ? "text.badge.plus" : "plus.rectangle")
                .font(fontTitle ? /*@START_MENU_TOKEN@*/.title/*@END_MENU_TOKEN@*/ : .body)
        }
    }
    
}//AccountsListView


///////////////////////////////////////////////////////////////////////////////////////////////////
///AccountAddView

struct AccountAddView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>
    private var accList : AccountsListModel
    
    @State private var sipServer = ""
    @State private var sipExtension = ""
    @State private var sipPassword = ""
    @State private var transport = SipTransport.udp
    
    @State private var addAccAlert = false
    @State private var addAccErr = ""
    
    init(_ accList: AccountsListModel) {
        self.accList = accList
    }
        
    var body: some View {
        Form {
            HStack {
                Spacer()
                Text("Add account").font(.headline)
                Spacer()
                
                Button(action: addAcc) {
                    Image(systemName: "plus.rectangle").font(.title2)
                }
                .disabled(sipServer.isEmpty ||
                          sipExtension.isEmpty ||
                          sipPassword.isEmpty)
                .alert("Can't add account", isPresented: $addAccAlert) {}
                message: { Text(addAccErr) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets())
            .background(Color(UIColor.systemGroupedBackground))
            
            Section(header: Text("Credentials:")) {
                TextField("Sip server/Domain:", text: $sipServer)
                TextField("Sip extension:", text: $sipExtension)
                SecureField("Sip password:", text: $sipPassword)
            }
            
            Section(header: Text("Transport:")) {
                Picker("Protocol:", selection: $transport) {
                    Text(String("UDP")).tag(SipTransport.udp)
                    Text(String("TCP")).tag(SipTransport.tcp)
                    Text(String("TLS")).tag(SipTransport.tls)
                }
                .pickerStyle(.menu)
            }
        }
    }
    
    private func addAcc() {
        let accData = SiprixAccData()
        accData.sipServer = sipServer
        accData.sipExtension = sipExtension
        accData.sipPassword = sipPassword
        accData.transport = transport
        accData.keepAliveTime = 0
        accData.expireTime=300
        //Use this line when TLS transport required and certificate of SIP server signed by Let's Encrypt CA
        //accData.tlsCaCertPath = Bundle.main.path(forResource: "isrg_root_x1", ofType: "pem")
        
        let errCode = accList.add(accData)
        if(errCode == kErrorCodeEOK) {
            self.dismiss()
        } else {
            addAccErr = SiprixModel.shared.getErrorText(errCode)
            addAccAlert = true
        }
    }
    
}//AccountAddView




///////////////////////////////////////////////////////////////////////////////////////////////////
///CallRowView
///
struct CallRowView: View {
    private var callsList : CallsListModel
    @StateObject private var call : CallModel
    @State private var switchedCallId : Int
    
    init(_ call: CallModel, callsList : CallsListModel) {
        self._call = StateObject(wrappedValue: call)
        self._switchedCallId = State(wrappedValue: callsList.switchedCallId)
        self.callsList = callsList
    }
    
    private var micMuted: String { get { return call.isMicMuted ? "MicMuted" : ""; }  }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: call.isIncoming ? "phone.arrow.down.left"
                        : "phone.arrow.up.right")
                    .font(.title2)
                
                VStack(alignment: .leading) {
                    Text(call.remoteSide).font(.headline).lineLimit(1)
                    Text(call.stateStr)
                }
                Spacer()
            
                if(call.callState != .connected)&&(call.callState != .held){
                    ProgressView()
                }
            
                if(call.callState == .connected) {
                    Text(call.durationStr)
                }
                getMenu()
                
            }//HStack
            .background(callsList.isSwitchedCall(call.id) ? Color.blue.opacity(0.3) : Color.clear)
            
            Divider()
        }//VStack
        .padding(EdgeInsets())
    }

    func getMenu() -> some View {
        Menu() {
            if(call.callState == .ringing){
                Button("Accept") { call.accept() }
                Button("Reject") { call.reject() }
            }
            else {
                if(call.callState == .connected) {
                    if(!callsList.isSwitchedCall(call.id)) {
                        Button(action: { callsList.switchToCall(call.id) }) {
                            Image(systemName: "arrow.triangle.swap")
                            Text("SwitchTo")
                        }
                    }
                    Button("Hold")      { call.hold()  }
                    
                    //Button("SendDtmf") { call.sendDtmf("123") }
                    //Button("MuteMic")  { call.muteMic(!call.isMicMuted)  }
                    //Button("Transfer") { call.transfer()  }
                }
                
                if((call.holdState == .local)||(call.holdState == .localAndRemote)) {
                    Button("UnHold")     { call.hold()  }
                }
                
                Button("Hangup")    { call.bye() }
            }
        } label: {
            Image(systemName: "ellipsis.circle.fill").font(.title)
        }
        .disabled(callsList.isSwitchedCall(call.id))//disable menu of current call
        .padding(5)
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
///SiprixVideoView
///
struct SiprixVideoView: UIViewRepresentable {
    private var call : CallModel
    private let isPreview : Bool
    
    init(_ call: CallModel, isPreview : Bool) {
        self.call = call
        self.isPreview = isPreview
    }
    //deinit {
    //    call.setVideoView(nil, isPreview:isPreview)
    //}
    
    func makeUIView(context: Context) -> UIView {
        let view = SiprixModel.shared.createVideoView()
        call.setVideoView(view, isPreview:isPreview)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) { }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
///CallSwitchedView
///
struct CallSwitchedView: View {
    @StateObject private var call : CallModel
    private let addCallAction: () -> Void
    
    @State var transferShow = false
    @State var transferExt = ""
    
    @State var dtmfShow = false
    @State var dtmfSent = ""
            
    init(_ call: CallModel, addCallAction: @escaping () -> Void) {
        self._call = StateObject(wrappedValue: call)
        self.addCallAction = addCallAction
    }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if(call.withVideo) {
                SiprixVideoView(call, isPreview:false)
                SiprixVideoView(call, isPreview:true)
                    .frame(width:130, height:100)
                
                Button(action:{ call.muteCam(!call.isCamMuted) }) {
                    Image(systemName: call.isCamMuted ? "video.slash.circle":"video.circle").font(.title)
                }
            }
            
            VStack(alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/) {
                Text(call.stateStr).font(.title2).padding(.bottom)
                
                VStack(alignment: .leading) {
                    Text("From: \(call.remoteSide)")
                    Text("To: \(call.localSide)")
                    Text("CallId: \(call.id)").font(.headline)
                    Text("DTMF: \(call.receivedDtmf)")
                }
                
                //Call duration
                if(call.callState == .connected) {  Text(call.durationStr).italic() }
                else if(call.callState == .held) {  Text(call.holdStr).italic()     }
                else                             {  Text("-:-").italic()            }
                
                Spacer()
                
                //[Ctrls]/[DTMF]/[Transfer] sections
                if((call.callState == .connected)||(call.callState == .held)) {
                    if(transferShow)  {   getTransView()  }
                    else if(dtmfShow) {   getDtmfView()   }
                    else              {   getCtrlsView()  }
                }
                
                //Accept/Reject/Hangup buttons
                if(call.callState == .ringing) { getAcceptRejectView()  }
                else                           { getHangupView()        }
                
                Divider()
            }//.border(.green)
        }
    }
    
    func getRoundBtn(iconName: String, action: @escaping () -> Void) -> some View {
        Button(action:action) {
            ZStack {
                Image(systemName: iconName).font(.title)//.foregroundColor(.blue)
                Circle().strokeBorder(.blue, lineWidth: 2)
            }.frame(width: 45, height: 45)
        }.padding()
    }
    
    func getFilledBtn(iconName: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: iconName)
                .resizable()
                .scaledToFit()
                .foregroundColor(color)
                .frame(width: 50, height: 50)
        }.padding()
    }
    
    func getDtmfBtn(_ tone: String) -> some View {
        Button(action: {
            if(call.sendDtmf(tone)) {  dtmfSent += tone }
        }) {
            ZStack {
                Text(tone).font(.title)//.foregroundColor(.blue)
                Circle().strokeBorder(.blue, lineWidth: 2)
            }.frame(width: 40, height: 40)
        }//.padding()
    }
    
    func getTransView() -> some View {
        HStack {
            TextField("Extension to transfer", text:$transferExt)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding()
            
            Button(action: {
                transferShow = false
                call.transferBlind(toExt: transferExt)
            }) {
                Image(systemName: "checkmark.circle").font(.title).foregroundColor(.green)
            }
            .padding()
            .disabled(transferExt.isEmpty)
            
            Button(action: { transferShow = false }) {
                Image(systemName: "xmark.circle.fill").font(.title)
            }.padding()
        }
    }
       
    func getDtmfView() -> some View {
        VStack(spacing: 10) {
            Divider()
            HStack(spacing: 20) {
                Text(dtmfSent).underline().frame(maxWidth: .infinity, alignment: .center)
                Spacer()
                Button(action: { dtmfShow = false }) {
                    Image(systemName: "xmark.circle.fill").font(.title)
                }.padding(.trailing)
            }
            HStack(spacing: 20) { getDtmfBtn("1"); getDtmfBtn("2"); getDtmfBtn("3")  }
            HStack(spacing: 20) { getDtmfBtn("4"); getDtmfBtn("5"); getDtmfBtn("6")  }
            HStack(spacing: 20) { getDtmfBtn("7"); getDtmfBtn("8"); getDtmfBtn("9")  }
            HStack(spacing: 20) { getDtmfBtn("*"); getDtmfBtn("0"); getDtmfBtn("#")  }
            Divider()
        }
    }
    
    func getCtrlsView() -> some View {
        VStack(spacing: 20) {
            HStack(spacing: 40) {
                getRoundBtn(iconName:call.isMicMuted ? "mic.slash":"mic",
                            action:{ call.muteMic(!call.isMicMuted)  })
                
                getRoundBtn(iconName:"circle.grid.3x3",
                            action:{ dtmfShow = true; dtmfSent="" })
                
                getRoundBtn(iconName:call.isSpeakerOn ? "speaker.zzz.fill" : "speaker.wave.2",
                            action:{ call.switchSpeaker(!call.isSpeakerOn) })
            }
            
            HStack(spacing: 40) {
                getRoundBtn(iconName:"plus",
                            action: addCallAction)
                getRoundBtn(iconName: (call.isLocalHold) ? "play" : "pause",
                            action:{ call.hold() })
                
                Menu() {
                    Button("Route audio to BT")      { call.routeAudioToBluetoth()  }
                    Button("Route audio to BuiltIn") { call.routeAudioToBuiltIn()   }
                    Divider()
                    Button("Transfer attended")   { }//TODO add impl
                    Button("Transfer")      { transferShow = true }
                    Button("Play file")     { call.playFile()     }
                } label: {
                    getRoundBtn(iconName:"ellipsis", action:{})
                }
            }
        }
    }
    
    func getAcceptRejectView() -> some View {
        HStack(spacing: 40) {
            getFilledBtn(iconName:"phone.down.circle.fill", color:.red, action: { call.reject() })
            getFilledBtn(iconName:"phone.circle.fill", color:.green, action: { call.accept() })
        }
    }
    
    func getHangupView() -> some View {
        getFilledBtn(iconName:"phone.down.circle.fill", color:.red, action:{ call.bye() })
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
///CallsListView

struct CallsListView: View {
    let timer = Timer.publish(every: 1, on: .current, in: .common).autoconnect()
    @StateObject private var callsList : CallsListModel
    @State private var addCallSheet = false
        
    init(_ callsList: CallsListModel) {
        self._callsList = StateObject(wrappedValue: callsList)
    }
    
    var body: some View {
        VStack {
            if(callsList.calls.isEmpty) {
                Button(action: addCallNav) {
                    Text("Make call")
                    Image(systemName: "phone.badge.plus.fill").font(/*@START_MENU_TOKEN@*/.title/*@END_MENU_TOKEN@*/)
                }
            }
            else {
                ScrollView{
                    ForEach(callsList.calls) {
                        call in CallRowView(call, callsList:callsList)
                    }
                }
                .frame(height:200)
                .onReceive(timer) { curTime in
                    callsList.updateDuration(curTime)
                }
                
                if(callsList.switchedCallId != kInvalidId) {
                    CallSwitchedView(callsList.switchedCall!, addCallAction:addCallNav)
                        .id(callsList.switchedCall!.uuid)//force new instance creation when call switched
                }
            }
        }//VStack
        .sheet(isPresented: $addCallSheet) {
            CallAddView()
        }
    }
    
    private func addCallNav() {
        addCallSheet = true
    }
    
}//CallsListView

///////////////////////////////////////////////////////////////////////////////////////////////////
///CallAddView

struct CallAddView: View {
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>
    
    let accList = SiprixModel.shared.accountsListModel
    @FocusState private var destInFocus: Bool
    
    @State private var addCallAlert = false
    @State private var addCallErr = ""
   
    @State private var ext = ""
    @State private var withVideo = false
    @State private var accId : Int
    
    init() {
        ext = "1012"//"u113355448"
        accId = accList.selectedAccId
    }
    
    var body: some View {
        Form {
            HStack {
                Spacer()
                Text("Add call").font(.headline)
                Spacer()
                
                Button {
                    addCall()
                } label: {
                    Image(systemName: "phone.badge.plus.fill").font(.title2)
                }
                .disabled(ext.isEmpty || accList.isEmpty)
                .alert("Can't add call", isPresented: $addCallAlert) {}
                    message: { Text(addCallErr) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets())
            .background(Color(UIColor.systemGroupedBackground))
            
            Section(header: Text("Destination")) {
                TextField("Phone number (extension)", text:$ext)
                    .focused($destInFocus)
                    .onAppear {
                      DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                        self.destInFocus = true
                      }
                    }
            }
                        
            Section(header: Text("From account:")) {
                if(accList.isEmpty) {
                    Text("Can\'t make calls. Required to add account")
                        .foregroundStyle(.red)
                } else {
                    Picker("Account:", selection: $accId) {
                        ForEach(accList.accounts) { acc in
                            Text(acc.name).tag(acc.id)
                        }
                    }
                }
            }
            
            Section {
                Toggle(isOn: $withVideo) {
                    Text("Call with video:")
                }
            }
        }
    }

    func addCall() {
        let dest = SiprixDestData()
        dest.toExt = ext
        dest.fromAccId = Int32(accId)
        dest.withVideo = NSNumber(value:withVideo)
        
        let errCode = SiprixModel.shared.callsListModel.invite(dest)
        
        if(errCode == kErrorCodeEOK) {
            self.presentationMode.wrappedValue.dismiss()
        } else {
            addCallErr = SiprixModel.shared.getErrorText(errCode)
            addCallAlert = true
        }
    }
    
}//CallAddView

///////////////////////////////////////////////////////////////////////////////////////////////////
///LogsListView

struct LogsListView: View {
    @StateObject private var logsModel : LogsModel
    
    init(_ model:LogsModel){
        self._logsModel = StateObject(wrappedValue: model)
    }
    
    var body: some View {
        TextEditor(text: .constant(logsModel.text))
            .textSelection(.enabled)
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
///ContentView

struct ContentView: View {
    @StateObject var accList = SiprixModel.shared.accountsListModel
    @StateObject var callsList = SiprixModel.shared.callsListModel
    @StateObject var networkModel = SiprixModel.shared.networkModel
    
    @State private var selectedTab = Tab.accounts
    enum Tab { case accounts, calls, logs }
            
    var body: some View {
        TabView(selection: $selectedTab) {
            AccountsListView(accList)
            .tabItem {
                Label("Accounts", systemImage: "list.dash")
            }
            .tag(Tab.accounts)
            
            CallsListView(callsList)
            .tabItem {
                Label("Calls", systemImage: "phone.circle")
            }
            .tag(Tab.calls)
            .badge(callsList.calls.count)
            
            LogsListView((SiprixModel.shared.logs==nil) ?
                         LogsModel() : SiprixModel.shared.logs!)
            .tabItem {
                Label("Logs", systemImage: "doc.plaintext")
            }
            .tag(Tab.logs)
        }
        .onReceive(callsList.$switchedCallId, perform: { _ in
            selectedTab = .calls
        })
        .padding(.bottom, networkModel.lost ? 20 : 0)
        .overlay(alignment: .bottom) {
            if(networkModel.lost) {
                Text("Network connection lost").foregroundStyle(.red)
                    .frame(maxWidth: .infinity).border(Color.pink)
            }
        }
    }//body
    
}//ContentView


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

