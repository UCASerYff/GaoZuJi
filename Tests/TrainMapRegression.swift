import AppKit
import SwiftUI
func tF(_ zh:String,_ en:String)->String { zh }
@main struct MapRender {
 @MainActor static func main() throws {
    _ = NSApplication.shared
    let geography=try JSONDecoder().decode(Geography.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
    func city(_ id:String,_ country:String,_ lon:Double,_ lat:Double)->City { City(id:id,name:id,english:id,aliases:"",countryID:country,provinceID:"",province:"",continent:"",longitude:lon,latitude:lat,isCustom:false) }
    let origin=city("北京","CHN",116.4,39.9)
    for destination in [city("上海","CHN",121.5,31.2),city("巴黎","FRA",2.35,48.85)] {
        let start=Date(),j=TrainJourney(origin:origin,destination:destination,startedAt:start,arrivesAt:start.addingTimeInterval(240),reward:2)
        let view=NSHostingView(rootView:TrainRouteMap(geography:geography,origin:origin,destination:destination,journey:j,now:start.addingTimeInterval(120)).frame(width:1100,height:580))
        view.frame=NSRect(x:0,y:0,width:1100,height:580);view.layoutSubtreeIfNeeded()
        let image=view.bitmapImageRepForCachingDisplay(in:view.bounds)!;view.cacheDisplay(in:view.bounds,to:image)
        try image.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"/tmp/gq358-map-\(destination.countryID).png"))
        print("Rendered map",destination.countryID)
    }
 }
}
