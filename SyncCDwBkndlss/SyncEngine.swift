import CoreData
import ObjectMapper
import DATAStack


enum ObjectSyncStatus : Int {
  case SDObjectSynced = 0
  case SDObjectCreated
  case SDObjectDeleted
}


class SyncEngine: NSObject{
  var registeredClassesToSync: [AnyClass] = []
  dynamic var syncInProgress: Bool {
    get {
      return _syncInProgress
    }
  }
  
  private var _syncInProgress: Bool = false {
    willSet{
      self.willChangeValueForKey("syncInProgress")
    }
    didSet{
      self.didChangeValueForKey("syncInProgress")
    }
  }
  
  
  
  var dataStack: DATAStack!
  var backgroundMOC: NSManagedObjectContext!
  var mainMOC: NSManagedObjectContext!
  
  
  let kSDSyncEngineInitialCompleteKey: String = "SyncEngineInitialSyncCompleted"
  let kSDSyncEngineSyncCompletedNotificationName: String = "SyncEngineSyncCompleted"
  
  static let sharedInstance = SyncEngine()
  
  override init(){
    self.dataStack = DATAStack(modelName: "SyncCDwBkndlss")
    //try! self.dataStack.drop()
    
    self.backgroundMOC = dataStack.newBackgroundContext()
    self.mainMOC = dataStack.mainContext
  }
  
  func registerNSManagedObjectClassToSync(aClass: AnyClass) {
    
    if aClass.isSubclassOfClass(NSManagedObject.self) {
      if !self.registeredClassesToSync.contains({$0 == aClass}) {
        self.registeredClassesToSync.append(aClass)
      }
      else {
        print("Unable to register \(NSStringFromClass(aClass)) as it is already registered")
      }
    } else {
      print("Unable to register \(NSStringFromClass(aClass)) as it is not a subclass of NSManagedObject")
    }
  }
  
  func startSync() {
    if _syncInProgress {
      return
    }
    _syncInProgress = true
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)) {
      self.downloadDataForRegisteredObjects(true, toDeleteLocalRecords: false)
    }
  }
  
  func initialSyncComplete() -> Bool {
    guard let res = NSUserDefaults.standardUserDefaults().valueForKey(kSDSyncEngineInitialCompleteKey) else {
      return false
    }
    return res.boolValue
  }
  
  func setInitialSyncCompleted() {
    NSUserDefaults.standardUserDefaults().setValue(true, forKey: kSDSyncEngineInitialCompleteKey)
    NSUserDefaults.standardUserDefaults().synchronize()
  }
  
  func executeSyncCompletedOperations() {
    dispatch_async(dispatch_get_main_queue()) {
      self.setInitialSyncCompleted()
      NSNotificationCenter.defaultCenter().postNotificationName(self.kSDSyncEngineSyncCompletedNotificationName, object: nil)
      self._syncInProgress = false
    }
  }
  
  
  func mostRecentUpdatedAtDateForEntityWithName(entityName: String) -> NSDate? {
    var date: NSDate? = nil
    // Create a new fetch request for the specified entity
    let request: NSFetchRequest = NSFetchRequest(entityName: entityName)
    
    // Set the sort descriptors on the request to sort by updatedAt in descending order
    request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false )]
    
    // You are only interested in 1 result so limit the request to 1
    request.fetchLimit = 1
    
    SyncEngine.sharedInstance.backgroundMOC.performBlockAndWait {
      do {
        let results: [AnyObject] = try SyncEngine.sharedInstance.backgroundMOC.executeFetchRequest(request)
        if let last = results.last  as? NSManagedObject, let dt = last.valueForKey("updatedAt")  as? NSDate {
          date = dt
        }
      } catch {
        print("Failed execute fetchrequest for mostRecentUpdatedAtDateForEntityWithName")
        abort()
      }
    }
    
    return date
  }
  
  func newManagedObjectWithClassName(className: String,  forRecord record: NSDictionary) {
    let ctx = SyncEngine.sharedInstance.backgroundMOC
    var newManagedObject = NSEntityDescription.insertNewObjectForEntityForName(className, inManagedObjectContext: ctx)
    record.enumerateKeysAndObjectsUsingBlock { (key, obj, stop) in
      self.setValue(obj, forKey: key as! String, forManagedObject: &newManagedObject)
    }
    record.setValue(NSNumber(integer: ObjectSyncStatus.SDObjectSynced.rawValue), forKey: "syncStatus")
  }
  
  
  func postLocalObjectsToServer() {
    var savedObjsCnt = 0
    // Iterate over all register classes to sync
    for className in self.registeredClassesToSync {
      // Fetch all objects from Core Data whose syncStatus is equal to SDObjectCreated
      let objectsToCreate = self.managedObjectsForClass(String(className), withSyncStatus: .SDObjectCreated)
      // Iterate over all fetched objects who syncStatus is equal to SDObjectCreated
      for objectToCreate in objectsToCreate {
        // Get the JSON representation of the NSManagedObject
        let obj = objectToCreate.JSONToCreateObjectOnServer()
        
        var fault: Fault? = nil
        let bc = Backendless.sharedInstance().data.of(className)
        let savedObj = bc.save(obj, fault: &fault)
        
        
        if fault != nil {
          print("Failed to save obj. err: \(fault!.detail)")
        } else {
          savedObjsCnt += 1
          print("SAVE OK  updating syncStatus and objectId")
          
          objectToCreate.setValue(NSNumber(integer: ObjectSyncStatus.SDObjectSynced.rawValue), forKey: "syncStatus")
          //set up createdAt updatedAt
          
          let objectId  = savedObj.valueForKey("objectId") as! String //id from BaaS
          objectToCreate.setValue(objectId, forKey: "objectId")
        }
        
      }
    }
    
    if savedObjsCnt > 0 {
      SyncEngine.sharedInstance.backgroundMOC.performBlockAndWait({
        do  {
          try SyncEngine.sharedInstance.backgroundMOC.save()
        } catch let error as NSError {
          print(")Could not save background context due to \(error.localizedDescription)")
        }
      })
    }
    self.deleteObjectsOnServer()
  }
  
  
  func deleteObjectsOnServer() {
    // Iterate over all registered classes to sync
    for className in self.registeredClassesToSync {
      // Fetch all records from Core Data whose syncStatus is equal to SDObjectDeleted
      let objectsToDelete = self.managedObjectsForClass(String(className), withSyncStatus: .SDObjectDeleted)
      // Iterate over all fetched records from Core Data
      for objectToDelete in objectsToDelete {
        // Create a request for each record
        if let objectId = objectToDelete.valueForKey("objectId") as? String {
          let dataStore = Backendless.sharedInstance().data.of(className)
          dataStore.removeID(objectId, response: { (oId) in
            print("Success deletion: \(oId)")
            SyncEngine.sharedInstance.backgroundMOC.deleteObject(objectToDelete)
            }, error: { (fault) in
              print("Failed to delete obj with id: \(objectToDelete.valueForKey("objectId")) error: \(fault.detail)")
          })
        }
      }
    }
    
    if SyncEngine.sharedInstance.backgroundMOC.hasChanges {
      SyncEngine.sharedInstance.backgroundMOC.performBlockAndWait {
        do {
          try SyncEngine.sharedInstance.backgroundMOC.save()
        } catch  let error as NSError {
          print("Failed to save context \(error.localizedDescription)")
        }
      }
    }
    
    self.executeSyncCompletedOperations()
  }
  
  
  
  
  
  func  updateManagedObject(inout managedObject: NSManagedObject,  withRecord record: NSDictionary) {
    record.enumerateKeysAndObjectsUsingBlock { (key, obj, stop) in
      self.setValue(obj, forKey: key as! String, forManagedObject: &managedObject)
    }
  }
  
  func setValue(value: AnyObject, forKey key: String, inout forManagedObject managedObject: NSManagedObject) {
    if key == "__meta" || key == "___class" || key == "updated" || key == "created" {
      return
    }
    
    managedObject.setValue(value, forKey: key)
  }
  
  func managedObjectsForClass(className: String, withSyncStatus syncStatus:ObjectSyncStatus) -> [NSManagedObject] {
    let managedObjectContext = SyncEngine.sharedInstance.backgroundMOC
    let fetchRequest = NSFetchRequest(entityName: className)
    let predicate = NSPredicate(format: "syncStatus = %d", syncStatus.rawValue)
    fetchRequest.predicate = predicate
    
    var results = [NSManagedObject]()
    managedObjectContext.performBlockAndWait {
      do {
        results = try managedObjectContext.executeFetchRequest(fetchRequest) as! [NSManagedObject]
      } catch {
        print("\(#function) failed perform fetch request. error: \(error)")
      }
    }
    return results
  }
  
  func managedObjectsForClass(className: String,  sortedByKey key: String,  usingArrayOfIds idArray: [String],  inArrayOfIds inIds: Bool) -> [NSManagedObject] {
    let managedObjectContext = SyncEngine.sharedInstance.backgroundMOC
    
    let fetchRequest = NSFetchRequest(entityName: className)
    let whereCondition = inIds ? "objectId IN %@" : "NOT (objectId IN %@)"
    let  predicate = NSPredicate(format: whereCondition, idArray)
    fetchRequest.predicate = predicate
    fetchRequest.sortDescriptors = [NSSortDescriptor(key: "objectId", ascending: true)]
    
    var result = [NSManagedObject]()
    managedObjectContext.performBlockAndWait {
      do {
        result = try managedObjectContext.executeFetchRequest(fetchRequest) as! [NSManagedObject]
      } catch {
        print("\(#function) failed perform fetch request. error: \(error)")
      }
    }
    return result
  }
  
  
  func downloadDataForRegisteredObjects(useUpdatedAtDate: Bool, toDeleteLocalRecords toDelete: Bool) {
    for className: AnyClass in self.registeredClassesToSync {
      let dataQuery = BackendlessDataQuery()
      if useUpdatedAtDate {
        
        if let mostRecentUpdatedDate = self.mostRecentUpdatedAtDateForEntityWithName(String(className)) {
          //time returned from timeIntervalSince1970 is in Seconds
          //time that stored at backendless  - in milliseconds
          
          let t = mostRecentUpdatedDate.timeIntervalSince1970 * 1000
          dataQuery.whereClause = "updatedAt > \(t)"
        }
      }
      
      var error: Fault?
      let bc = Backendless.sharedInstance().data.of(className).find(dataQuery, fault: &error)
      
      if error != nil {
        print("Server reported an error: \(error)")
        return
      }
      
      var dic = [NSDictionary]()
      for d in (bc.data as? [BaseMobelObject])! {
        let tmpDic = NSMutableDictionary()
        
        
        for key in d.toJSON().keys {
          var tmpVal: AnyObject? = nil
          d.getPropertyIfResolved(key, value: &tmpVal)
          if tmpVal != nil {
            tmpDic[key] = tmpVal!
          }
        }
        dic.append(tmpDic)
        
      }
      
      let responce = NSDictionary(dictionary: ["results": dic])
      self.writeJSONresponce(responce, toDiskForClassWithName: String(className))
    }
    
    // Need to process JSON records into Core Data
    if (!toDelete) {
      self.processJSONDataRecordsIntoCoreData()
    } else {
      self.processJSONDataRecordsForDeletion()
    }
  }
  
  
  func processJSONDataRecordsIntoCoreData() {
    let managedObjectContext = SyncEngine.sharedInstance.backgroundMOC
    
    // Iterate over all registered classes to sync
    for  className in self.registeredClassesToSync {
      if !self.initialSyncComplete() { // import all downloaded data to Core Data for initial sync
        // If this is the initial sync then the logic is pretty simple, you will fetch the JSON data from disk
        // for the class of the current iteration and create new NSManagedObjects for each record
        let JSONDictionary = self.JSONDictionaryForClassWithName(String(className))
        if let records = JSONDictionary?.objectForKey("results") as? [AnyObject] {
          for record in records {
            self.newManagedObjectWithClassName(String(className), forRecord: record as! NSDictionary)
          }
        } else {
          print("\(#function) failed get records fron json dict \(JSONDictionary)")
        }
      } else {
        // Otherwise you need to do some more logic to determine if the record is new or has been updated.
        // First get the downloaded records from the JSON response, verify there is at least one object in
        // the data, and then fetch all records stored in Core Data whose objectId matches those from the JSON response.
        let downloadedRecords = self.JSONDataRecordsForClass(String(className), sortedByKey: "objectId")
        
        if  downloadedRecords.count > 0 {
          // Now you have a set of objects from the remote service and all of the matching objects
          // (based on objectId) from your Core Data store. Iterate over all of the downloaded records
          // from the remote service.
          //
          let arrayOfIds = downloadedRecords.flatMap{ $0.valueForKey("objectId") as? String }
          
          var storedRecords =  self.managedObjectsForClass(String(className), sortedByKey: "objectId",  usingArrayOfIds: arrayOfIds, inArrayOfIds: true)
          
          
          var currentIndex = 0;
          // If the number of records in your Core Data store is less than the currentIndex, you know that
          // you have a potential match between the downloaded records and stored records because you sorted
          // both lists by objectId, this means that an update has come in from the remote service
          //
          for record in downloadedRecords {
            var storedManagedObject: NSManagedObject? = nil
            
            // Make sure we don't access an index that is out of bounds as we are iterating over both collections together
            if storedRecords.count > currentIndex {
              storedManagedObject = storedRecords[currentIndex]
            }
            
            //var runNewObjectCreation = true
            
            if let one = storedManagedObject?.valueForKey("objectId") as? String,
              let two = record.valueForKey("objectId") as? String where one == two {
              self.updateManagedObject(&storedRecords[currentIndex], withRecord: record as! NSDictionary)
            } else {
              self.newManagedObjectWithClassName(String(className), forRecord: record as! NSDictionary)

            }
            
/*
            if let one = storedManagedObject?.valueForKey("objectId") as? String,
              let two = record.valueForKey("objectId") as? String{
              
              if one == two {
                self.updateManagedObject(&storedRecords[currentIndex], withRecord: record as! NSDictionary)
              } else {
                print(record)
                self.newManagedObjectWithClassName(String(className), forRecord: record as! NSDictionary)
                
              }
              
            } else {
              
              self.newManagedObjectWithClassName(String(className), forRecord: record as! NSDictionary)
              
            }*/
            currentIndex += 1
          }
        }
      }
      
      // Once all NSManagedObjects are created in your context you can save the context to persist the objects
      // to your persistent store. In this case though you used an NSManagedObjectContext who has a parent context
      // so all changes will be pushed to the parent context
      managedObjectContext.performBlockAndWait({
        do {
          try managedObjectContext.save()
        } catch {
          print("Unable to save context for class \(className) \(error)")
          fatalError()
        }
      })
      
      // You are now done with the downloaded JSON responses so you can delete them to clean up after yourself,
      // then call your -executeSyncCompletedOperations to save off your master context and set the
      // syncInProgress flag to NO
      self.deleteJSONDataRecordsForClassWithName(String(className))
      self.downloadDataForRegisteredObjects(false, toDeleteLocalRecords: true)
    }
  }
  
  func processJSONDataRecordsForDeletion() {
    let managedObjectContext =  SyncEngine.sharedInstance.backgroundMOC
    // Iterate over all registered classes to sync
    for className in self.registeredClassesToSync {
      // Retrieve the JSON response records from disk
      let JSONRecords = self.JSONDataRecordsForClass(String(className), sortedByKey: "objectId")
      let arrayOfIds = JSONRecords.flatMap{ $0.valueForKey("objectId") as? String }
      if JSONRecords.count > 0 {
        
        // If there are any records fetch all locally stored records that are NOT in the list of downloaded records
        let storedRecords = self.managedObjectsForClass(String(className), sortedByKey: "objectId", usingArrayOfIds: arrayOfIds, inArrayOfIds: false)
        // Schedule the NSManagedObject for deletion and save the context
        managedObjectContext.performBlockAndWait({
          for managedObject in storedRecords {
            managedObjectContext.deleteObject(managedObject)
          }
          
          do {
            try managedObjectContext.save()
          } catch {
            print("Unable to save context after deleting records for class \(className) because \(error)")
            
          }
        })
      }
      
      // Delete all JSON Record response files to clean up after yourself
      self.deleteJSONDataRecordsForClassWithName(String(className))
    }
    
    // Execute the sync completion operations as this is now the final step of the sync process
    self.postLocalObjectsToServer()
  }
  
  
  
  //MARK: File Managment
  func applicationCacheDirectory() -> NSURL {
    return NSFileManager.defaultManager().URLsForDirectory(.CachesDirectory , inDomains: .UserDomainMask).last!
  }
  
  func JSONDataRecordsDirectory() -> NSURL {
    let filemanager = NSFileManager.defaultManager()
    let url = NSURL(string: "JSONRecords/", relativeToURL: self.applicationCacheDirectory())
    if !filemanager.fileExistsAtPath(url!.path!) {
      do {
        try filemanager.createDirectoryAtPath(url!.path!, withIntermediateDirectories: true, attributes: nil)
      } catch {
        print("Failed create directory \(url!.path!) err: \(error)")
        abort()
      }
    }
    return url!
  }
  
  func writeJSONresponce(response: NSDictionary, toDiskForClassWithName classname: String) {
    if let fileURL = NSURL(string: classname, relativeToURL: self.JSONDataRecordsDirectory()){
      
      if !response.writeToFile(fileURL.path!, atomically: true) {
        print("Error saving response to disk, will attempt to remove NSNull values and try again.")
        // remove NSNulls and try again...
        var nullFreeRecords = [NSMutableDictionary]()
        
        if let records = response.objectForKey("results") as?  [NSMutableDictionary] {
          for dic in records {
            
            dic.removeObjectForKey("__meta")
            dic.removeObjectForKey("___class")
            dic.removeObjectForKey("updated")
            dic.enumerateKeysAndObjectsUsingBlock({ (key, obj, stop) in
              if key as! String == "__meta" || key as! String == "___class" {
                
              } else {
                if obj .isKindOfClass(NSNull.ofClass()) {
                  dic.setValue(nil, forKey: key as! String)
                }
              }
            })
            nullFreeRecords.append(dic)
          }
        }
        
        let nullFreeDictionary = NSDictionary(dictionary: ["results" : nullFreeRecords])
        
        if !nullFreeDictionary.writeToFile(fileURL.path!, atomically: true) {
          print("Failed all attempts to save response to disk: \(response)");
        }
      }
    } else {
      print("failed to write \(#function) ")
    }
  }
  
  
  func JSONDataRecordsForClass(className: String, sortedByKey key:String)  -> [AnyObject] {
    if let JSONDictionary = self.JSONDictionaryForClassWithName(className),
      let records = JSONDictionary.objectForKey("results") as? NSArray {
      return records.sortedArrayUsingDescriptors([NSSortDescriptor(key: key, ascending: true)])
    }
    return []
  }
  
  func deleteJSONDataRecordsForClassWithName(className: String) {
    if let url = NSURL(string: className, relativeToURL: JSONDataRecordsDirectory()) {
      do {
        try NSFileManager.defaultManager().removeItemAtURL(url)
      } catch {
        print("Unable to delete JSON Records at \(url.path), reason: \(error)")
      }
    }
  }
  
  func JSONDictionaryForClassWithName(className: String) -> NSDictionary? {
    guard let fileURL = NSURL(string: className, relativeToURL: self.JSONDataRecordsDirectory()) else {
      return nil
    }
    return NSDictionary(contentsOfURL: fileURL)
  }
}