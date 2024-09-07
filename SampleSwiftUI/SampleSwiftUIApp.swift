//
//  SampleSwiftUIApp.swift
//  SampleSwiftUI
//
//  Created by Siprix Team.
//

import SwiftUI
import Intents


@main
struct SampleSwiftUIApp: App {
    
    init() {
        SiprixModel.shared.initialize()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }    
   
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        let intraction = userActivity.interaction
        let startCallIntent = intraction?.intent as? INStartCallIntent
        
        let contact = startCallIntent?.contacts?[0]
        let contactHandle = contact?.personHandle
        if let phoneNumber = contactHandle?.value {
           print(phoneNumber)
        }
        return true
    }
    
    func handleStartCall(_ userActivity: NSUserActivity) {
        let intraction = userActivity.interaction
        let startCallIntent = intraction?.intent as? INStartCallIntent
        
        let contact = startCallIntent?.contacts?[0]
        let contactHandle = contact?.personHandle
        if let phoneNumber = contactHandle?.value {
           print(phoneNumber)
        }
    }
}
