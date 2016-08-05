 
import Foundation
import CoreData
import ObjectMapper

class Todo: /*baseCDobj*/ NSManagedObject {
 
  @NSManaged var task: String!
  @NSManaged var completed: NSNumber! //bool
  @NSManaged var updatedAt: NSDate!
  @NSManaged var createdAt: NSDate!
  @NSManaged var objectId: String?
  @NSManaged var syncStatus: NSNumber!
 
 
  override func JSONToCreateObjectOnServer() -> BaseMobelObject? {
    let obj =  todo()
    
    obj.completed  = self.completed.boolValue
    obj.task = self.task
    obj.createdAt = self.createdAt
    obj.updatedAt = self.updatedAt
    
    return obj
  }
}
 
 
 extension NSManagedObject {
  func JSONToCreateObjectOnServer() -> BaseMobelObject? {
    let e = NSException(name: "JSONStringToCreateObjectOnServer Not Overridden", reason: "Must override JSONStringToCreateObjectOnServer on NSManagedObject class", userInfo: nil)
    e.raise()
    return nil;
  }
 }