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
  
  lazy var refreshButton: UIBarButtonItem = {
    let b = UIBarButtonItem(title: "refresh", style: .Plain , target: self, action: #selector(ViewController.refresh))
    return b
  }()
  
  lazy var dataSource: DATASource = {
    let request: NSFetchRequest = NSFetchRequest(entityName: "Todo")
    request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
    request.predicate = NSPredicate(format: "syncStatus != %d", ObjectSyncStatus.SDObjectDeleted.rawValue)
    
    
    let dataSource = DATASource(tableView: self.tableView, cellIdentifier: "MyCell", fetchRequest: request, mainContext: SyncEngine.sharedInstance.mainMOC, configuration: { cell, item, indexPath in
      let one = item.valueForKey("task") as? String ?? ""
      let two = item.valueForKey("objectId") as? String ?? ""
      let tree = item.valueForKey("syncStatus") as? Int ?? -999
      
      
      cell.textLabel?.text = "\(one)-\(tree)-\(two)  "
    })
    
    dataSource.delegate = self
    
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
    
    
    self.dataStack.performInNewBackgroundContext { (backgroundContext) in
      let entity = NSEntityDescription.entityForName("Todo", inManagedObjectContext: backgroundContext)!
      let object = NSManagedObject(entity: entity, insertIntoManagedObjectContext: backgroundContext)
      
      object.setValue("test1", forKey: "task")
      object.setValue(NSNumber(bool: false), forKey: "completed")
      object.setValue(NSDate(), forKey: "updatedAt")
      object.setValue(NSDate(), forKey: "createdAt")
      object.setValue(NSNumber(integer: ObjectSyncStatus.SDObjectCreated.rawValue), forKey: "syncStatus")
      
      do {
        try backgroundContext.save()
      } catch let error as NSError {
        print("failed to save obj! \(object) \(error.localizedDescription)")
        return
      }
      
      
      self.dataSource.fetch()
      self.tableView.reloadData()
      SyncEngine.sharedInstance.startSync()
      
    }
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
    if keyPath == "syncInProgress" {
      self.checkSyncStatus()
    }
    
  }
  
}


extension ViewController: DATASourceDelegate {
  func dataSource(dataSource: DATASource, tableView: UITableView, canEditRowAtIndexPath indexPath: NSIndexPath) -> Bool {
    return true
  }
}


// MARK: - UITableViewDelegate

extension ViewController {
  override func tableView(tableView: UITableView, editActionsForRowAtIndexPath indexPath: NSIndexPath) -> [UITableViewRowAction]? {
    let delete = UITableViewRowAction(style: .Default, title: "Delete") { action, indexPath in
      let item = self.dataSource.objectAtIndexPath(indexPath)!
      let objectId = item.valueForKey("objectId") as? String
      
      SyncEngine.sharedInstance.mainMOC.performBlockAndWait({
        if (objectId == nil || objectId == "") {
          SyncEngine.sharedInstance.mainMOC.deleteObject(item)
        } else {
          item.setValue(NSNumber(integer: ObjectSyncStatus.SDObjectDeleted.rawValue), forKey: "syncStatus")
        }
        
        do {
          try SyncEngine.sharedInstance.mainMOC.save()
        } catch let error as NSError {
          print("Error saving main context: \(error.localizedDescription)");
        }
      })
      self.dataSource.fetch()
      self.tableView.reloadData()
    }
    
    return [delete]
  }
  
  
  override func tableView(tableView: UITableView, canEditRowAtIndexPath indexPath: NSIndexPath) -> Bool {
    return true
  }
  
  
}
