//
//  ViewController.swift
//  SyncCDwBkndlss
//
//  Created by Денис on 7/23/16.
//  Copyright © 2016 duzvik. All rights reserved.
//

import UIKit
import DATASource
import DATAStack

class ViewController: UITableViewController {
  
  lazy var dataStack: DATAStack = {
    let dataStack = DATAStack(modelName: "SyncCDwBkndlss")
    return dataStack
  }()
  
  lazy var maintCtx: NSManagedObjectContext = {
    return SyncEngine.sharedInstance.mainMOC
  }()
  
  var zzz: String = "asdas"
  
  lazy var refreshButton: UIBarButtonItem = {
    let b = UIBarButtonItem(title: "refresh", style: .Plain , target: self, action: #selector(ViewController.refresh))
    return b
  }()
  
  lazy var dataSource: DATASource = {
    let request: NSFetchRequest = NSFetchRequest(entityName: "Todo")
    request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
    
    let dataSource = DATASource(tableView: self.tableView, cellIdentifier: "MyCell", fetchRequest: request, mainContext: self.maintCtx, configuration: { cell, item, indexPath in
      
      //  if let cell = cell  {
      
      let one = item.valueForKey("task") as? String ?? ""
      let two = item.valueForKey("objectId") as? String ?? ""
      
      cell.textLabel?.text = "\(one) \(two)"
      //}
    })
    
    return dataSource
  }()
  
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    
    
    self.navigationItem.leftBarButtonItem = self.refreshButton
    
    
    let b = UIBarButtonItem(title: "+", style: .Plain , target: self, action: #selector(ViewController.add))
    self.navigationItem.rightBarButtonItem = b
    
    self.tableView.registerClass(UITableViewCell.self, forCellReuseIdentifier: "MyCell")
    
    
    tableView.dataSource = dataSource
    
    self.dataSource.fetch()
    tableView.reloadData()
    
    
    
    /*do {
     try self.fetchedResultsController.performFetch()
     } catch {
     let fetchError = error as NSError
     print("\(fetchError), \(fetchError.userInfo)")
     }*/
    
  }
  
  
  override func viewDidAppear(animated: Bool) {
    super.viewDidAppear(animated)
    NSNotificationCenter.defaultCenter().addObserverForName(SyncEngine.sharedInstance.kSDSyncEngineSyncCompletedNotificationName, object: nil, queue: nil) { (note) in
      self.dataSource.fetch()
      self.tableView.reloadData()
    }
    
    SyncEngine.sharedInstance.addObserver(self, forKeyPath: "syncInProgress", options: NSKeyValueObservingOptions.New, context: nil)
  }
  
  override func viewDidDisappear(animated: Bool) {
    super.viewDidDisappear(animated)
    
    NSNotificationCenter.defaultCenter().removeObserver(self, name: SyncEngine.sharedInstance.kSDSyncEngineSyncCompletedNotificationName, object: nil)
    
    SyncEngine.sharedInstance.removeObserver(self, forKeyPath: "syncInProgress")
  }
  
  
  func refresh() {
    SyncEngine.sharedInstance.startSync()
  }
  
  func add(){
    //createMain
    //let ctx = SyncEngine.sharedInstance.backgroundMOC
    let ctx = self.dataStack.newBackgroundContext()
    let entity = NSEntityDescription.entityForName("Todo", inManagedObjectContext: ctx)!
    let object = NSManagedObject(entity: entity, insertIntoManagedObjectContext: ctx)
    
    //object.setValue("this is added task \(NSUUID().UUIDString)", forKey: "task")
    object.setValue("test1", forKey: "task")
    object.setValue(NSNumber(bool: false), forKey: "completed")
    object.setValue(NSDate(), forKey: "updatedAt")
    object.setValue(NSDate(), forKey: "createdAt")
    //object.setValue(NSUUID().UUIDString, forKey: "objectId") set UUID after sync with server
    object.setValue(NSNumber(integer: ObjectSyncStatus.SDObjectCreated.rawValue), forKey: "syncStatus")
    
    
    do {
      try ctx.save()
      print("object persisted!")
    } catch let error as NSError {
      print("failed to save obj! \(object) \(error.localizedDescription)")
      return
    }
    
    //TODO
    //try! self.fetchedResultsController.performFetch()
    self.dataSource.fetch()
    self.tableView.reloadData()
    print("going to sync")
    SyncEngine.sharedInstance.startSync()
  }
  
  
  override func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
    // Dispose of any resources that can be recreated.
  }
  
  
  func checkSyncStatus() {
    if SyncEngine.sharedInstance.syncInProgress {
      self.replaceRefreshButtonWithActivityIndicator()
    } else {
      self.removeActivityIndicatorFromRefreshButton()
    }
  }
  
  
  
  func replaceRefreshButtonWithActivityIndicator() {
    let activityIndicator = UIActivityIndicatorView(frame: CGRectMake(0,0,25,25))
    activityIndicator.autoresizingMask = [.FlexibleLeftMargin, .FlexibleRightMargin, .FlexibleTopMargin, .FlexibleBottomMargin]
    activityIndicator.startAnimating()
    let activityItem = UIBarButtonItem(customView: activityIndicator)
    self.navigationItem.leftBarButtonItem = activityItem
  }
  
  func removeActivityIndicatorFromRefreshButton() {
    self.navigationItem.leftBarButtonItem = self.refreshButton
  }
  
  
  override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
    print("observeValueForKeyPath => \(keyPath)")
    if keyPath == "syncInProgress" {
      self.checkSyncStatus()
    }
    
  }
  
}


extension ViewController: DATASourceDelegate {
  func dataSource(dataSource: DATASource, tableView: UITableView, canEditRowAtIndexPath indexPath: NSIndexPath) -> Bool {
    return true
  }
  
  // This doesn't seem to be needed when implementing tableView(_:editActionsForRowAtIndexPath).
  //func dataSource(dataSource: DATASource, tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
  
  //}
}


// MARK: - UITableViewDelegate

extension ViewController {
  override func tableView(tableView: UITableView, editActionsForRowAtIndexPath indexPath: NSIndexPath) -> [UITableViewRowAction]? {
    let delete = UITableViewRowAction(style: .Default, title: "Delete") { action, indexPath in
      let item = self.dataSource.objectAtIndexPath(indexPath)!
      print("delete")
      print(item)
      
      //self.dataStack!.mainContext.deleteObject(item)
      //try! self.dataStack!.mainContext.save()
    }
    
    return [delete]
  }
  
  
  override func tableView(tableView: UITableView, canEditRowAtIndexPath indexPath: NSIndexPath) -> Bool {
    return true
  }
  
  override func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
    if (editingStyle == UITableViewCellEditingStyle.Delete) {
      // handle delete (by removing the data from your array and updating the tableview)
      print("deel!")
    }
  }
}
