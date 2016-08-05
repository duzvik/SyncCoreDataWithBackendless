import ObjectMapper



class BaseMobelObject: NSObject,   Mappable {
  var type: String?
  
  class func objectForMapping(map: Map) -> Mappable? {
    
    print("objectForMapping")
    if let type: String = map["type"].value() {
      switch type {
      case "todo":
        print("Return instance of TODO")
        return todo(map)
      default:
        print("Return instance of TODO")

        return nil
      }
    }
    return nil
  }
  
 
  
  override init() {
  }
  required init?(_ map: Map){
  }
  
  func mapping(map: Map) {
    type <- map["type"]
  }
}

class todo: BaseMobelObject {
  
  var objectId: String?
  var created: NSDate?
  var updated: NSDate?
  
  
  var task: String!
  var completed: Bool = false
  var updatedAt: NSDate!
  var createdAt: NSDate!
 
  override class func objectForMapping(map: Map) -> Mappable? {
    return nil
  }
 
  let transform = TransformOf<Int, String>(fromJSON: { (value: String?) -> Int? in
    // transform value from String? to Int?
    return Int(value!)
    }, toJSON: { (value: Int?) -> String? in
      // transform value from Int? to String?
      if let value = value {
        return String(value)
      }
      return ""
  })

  let transform1 = TransformOf<String, NSDate>(fromJSON: { (value: NSDate?) -> String? in
    // transform value from String? to Int?
    let formatter = NSDateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
    
    return formatter.stringFromDate(value!)
    //return Int(value!)
    }, toJSON: { (value: String?) -> NSDate? in
      let formatter = NSDateFormatter()
      formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
      
      return formatter.dateFromString(value!)

  })

  
  
  // Mappable
  override func mapping(map: Map) {
   // super.mapping(map)

    let formatter = NSDateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
    let dateTransform  = DateFormatterTransform(dateFormatter: formatter)

        objectId   <- map["objectId"]
    created    <- (map["created"],  dateTransform)
    updated    <- (map["updated"], dateTransform)
    task       <- map["task"]
    completed  <- map["completed"]
    updatedAt  <- (map["updatedAt"], DateTransform())
    createdAt  <- (map["createdAt"], dateTransform)
  }
  
 
}
 