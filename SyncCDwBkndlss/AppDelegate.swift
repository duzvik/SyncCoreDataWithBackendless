//
//  AppDelegate.swift
//  SyncCDwBkndlss
//
//  Created by Денис on 7/23/16.
//  Copyright © 2016 duzvik. All rights reserved.
//

import UIKit
import CoreData
import DATAStack

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

  let APP_ID = "7235F497-D2F5-2AA5-FFBA-B6263439B400"
  let SECRET_KEY = "960E14BA-402F-FB9E-FFBE-DED3BDF1EF00"
  let VERSION_NUM = "v1"
  
  var backendless = Backendless.sharedInstance()
 
  
  var dataStack: DATAStack = {
    let dataStack = DATAStack(modelName: "SyncCDwBkndlss")
    
    return dataStack
  }()

 
  
  var window: UIWindow?
  var navController: UINavigationController?


  func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
    backendless.initApp(APP_ID, secret:SECRET_KEY, version:VERSION_NUM)

    SyncEngine.sharedInstance.registerNSManagedObjectClassToSync(Todo.ofClass())

    navController = UINavigationController()
    let viewController: ViewController = ViewController()
    self.navController!.pushViewController(viewController, animated: false)
    
    self.window = UIWindow(frame: UIScreen.mainScreen().bounds)
    
    self.window!.rootViewController = navController
    
    self.window!.backgroundColor = UIColor.whiteColor()
    
    self.window!.makeKeyAndVisible()
    
    return true
 
  }

  func applicationWillResignActive(application: UIApplication) {
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
  }

  func applicationDidEnterBackground(application: UIApplication) {
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
  }

  func applicationWillEnterForeground(application: UIApplication) {
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
  }

  func applicationDidBecomeActive(application: UIApplication) {
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    SyncEngine.sharedInstance.startSync()
  }

  func applicationWillTerminate(application: UIApplication) {
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
  }


  
}

