import Foundation
func tF(_ zh:String,_ en:String)->String { zh }
@main struct TrainGameRegression {
 static func main() throws {
  var s=TrainState();var journal=Journal();let now=Date()
  journal.trips=[Trip(id:"trip",name:"test")]
  journal.visits=[Visit(id:"visit",cityID:"city",tripID:"trip",note:"一次旅行",photoIDs:["photo","photo"])]
  assert(TrainEngine.settle(&s,journal:journal)==10)
  let initial=s
  assert(TrainEngine.settle(&s,journal:journal)==0);assert(s==initial)
  journal.visits=[];_ = TrainEngine.settle(&s,journal:journal)
  journal.visits=[Visit(id:"visit",cityID:"city",tripID:"trip",note:"一次旅行",photoIDs:["photo"])]
  assert(TrainEngine.settle(&s,journal:journal)==0)
  func city(_ id:String,_ country:String,_ lon:Double,_ lat:Double)->City { City(id:id,name:id,english:id,aliases:"",countryID:country,provinceID:"",province:"",continent:"",longitude:lon,latitude:lat,isCustom:false) }
  let beijing=city("a","CHN",116.4,39.9),shanghai=city("b","CHN",121.5,31.2),paris=city("c","FRA",2.35,48.85)
  assert(!TrainEngine.depart(state:&s,destination:beijing,now:now))
  TrainEngine.prepare(&s,cities:[shanghai,beijing]);assert(s.currentStation==beijing && s.routeCityID==shanghai.id)
  assert(!TrainEngine.depart(state:&s,destination:beijing,now:now))
  let before=s.materials
  assert(TrainEngine.depart(state:&s,destination:shanghai,now:now));assert(s.materials==before && s.cruiseCount==0)
  let moving=s;assert(!TrainEngine.depart(state:&s,destination:paris,now:now));assert(s==moving)
  let j=s.journey!;assert(j.domestic)
  assert(abs(j.progress(at:now.addingTimeInterval(j.arrivesAt.timeIntervalSince(now)/2))-0.5)<0.0001)
  assert(!TrainEngine.arrive(&s,now:j.arrivesAt.addingTimeInterval(-0.1)))
  s=try JSONDecoder().decode(TrainState.self,from:JSONEncoder().encode(s))
  assert(TrainEngine.arrive(&s,now:j.arrivesAt.addingTimeInterval(500)))
  assert(s.materials==before+2 && s.currentStation==shanghai && s.cruiseCount==1)
  let paid=s;assert(!TrainEngine.arrive(&s,now:j.arrivesAt.addingTimeInterval(600)));assert(s==paid)
  var sightseeing=s
  assert(TrainEngine.depart(state:&sightseeing,destination:paris,now:now.addingTimeInterval(86399)))
  assert(sightseeing.journey!.reward==0 && sightseeing.lastCruiseAt==s.lastCruiseAt)
  assert(TrainEngine.arrive(&sightseeing,now:now.addingTimeInterval(90000)))
  assert(sightseeing.materials==s.materials && sightseeing.lifetimeMaterials==s.lifetimeMaterials)
  assert(TrainEngine.depart(state:&s,destination:paris,now:now.addingTimeInterval(86400)))
  assert(!s.journey!.domestic)
  let cross=TrainJourney(origin:city("west","USA",179,30),destination:city("east","USA",-179,30),startedAt:now,arrivesAt:now.addingTimeInterval(120),reward:2)
  assert(abs(cross.coordinate(at:0.5).lon)>179)
  assert(cross.progress(at:now.addingTimeInterval(-1))==0)
  let old=try JSONDecoder().decode(TrainState.self,from:Data("{}".utf8));assert(old.journey==nil && old.currentStation==nil)
  s.lastCruiseAt=now;s.carriageLevels["sleeper"]=4
  assert(TrainEngine.nextCruise(at:now,state:s)==now.addingTimeInterval(16*3600))
  s.materials=0;let empty=s;assert(!TrainEngine.upgrade(.dining,state:&s));assert(s==empty)
  try TrainEngine.validate(s)
  let restored=try JSONDecoder().decode(TrainState.self,from:JSONEncoder().encode(s));assert(restored==s)
  print("PASS Train: duplicate/deleted/readded visits, photos and trips; durable journey, domestic/international, dateline, offline one-time arrival, cooldown boundary; sleeper bonus; atomic failed upgrade; save roundtrip")
 }
}
