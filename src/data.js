export const reserves = [
 { id:1,name:'Jim Corbett National Park',state:'Uttarakhand',animals:18,risk:'Elevated',zones:4,health:94,abbr:'JC',x:23,y:34 },
 { id:2,name:'Ranthambore National Park',state:'Rajasthan',animals:24,risk:'Critical',zones:5,health:89,abbr:'RN',x:62,y:25 },
 { id:3,name:'Kaziranga National Park',state:'Assam',animals:31,risk:'Elevated',zones:6,health:97,abbr:'KN',x:78,y:48 },
 { id:4,name:'Bandipur National Park',state:'Karnataka',animals:16,risk:'Stable',zones:3,health:92,abbr:'BN',x:34,y:68 },
 { id:5,name:'Periyar Tiger Reserve',state:'Kerala',animals:13,risk:'Stable',zones:3,health:96,abbr:'PT',x:18,y:79 },
 { id:6,name:'Sundarbans National Park',state:'West Bengal',animals:22,risk:'Critical',zones:5,health:87,abbr:'SN',x:85,y:72 }
]
export const initialAnimals = [
 {id:1,tag:'TAG-001',name:'Aarav',species:'Bengal Tiger',scientific:'Panthera tigris tigris',status:'Active',sex:'Male',year:2015,reserve:'Jim Corbett National Park',state:'Uttarakhand',lat:29.56,lng:78.98,speed:2.2,battery:82,health:'Healthy',lastSeen:'2 min ago',risk:'Medium',x:22,y:33},
 {id:2,tag:'TAG-002',name:'Maya',species:'Asian Elephant',scientific:'Elephas maximus',status:'Active',sex:'Female',year:2022,reserve:'Ranthambore National Park',state:'Rajasthan',lat:26.03,lng:76.51,speed:3.9,battery:64,health:'Healthy',lastSeen:'4 min ago',risk:'Critical',x:61,y:26},
 {id:3,tag:'TAG-003',name:'Raja',species:'Indian Rhinoceros',scientific:'Rhinoceros unicornis',status:'Active',sex:'Unknown',year:2014,reserve:'Kaziranga National Park',state:'Assam',lat:26.61,lng:93.42,speed:5.6,battery:19,health:'Needs review',lastSeen:'11 min ago',risk:'High',x:79,y:48},
 {id:4,tag:'TAG-004',name:'Veera',species:'Asiatic Lion',scientific:'Panthera leo persica',status:'Active',sex:'Male',year:2021,reserve:'Bandipur National Park',state:'Karnataka',lat:11.68,lng:76.64,speed:7.3,battery:91,health:'Healthy',lastSeen:'7 min ago',risk:'Low',x:34,y:67},
 {id:5,tag:'TAG-005',name:'Tara',species:'Indian Leopard',scientific:'Panthera pardus fusca',status:'Active',sex:'Female',year:2013,reserve:'Periyar Tiger Reserve',state:'Kerala',lat:9.49,lng:77.22,speed:9,battery:43,health:'Healthy',lastSeen:'19 min ago',risk:'Medium',x:18,y:79},
 {id:6,tag:'TAG-006',name:'Kavi',species:'Sloth Bear',scientific:'Melursus ursinus',status:'Active',sex:'Unknown',year:2020,reserve:'Sundarbans National Park',state:'West Bengal',lat:21.96,lng:88.91,speed:1.7,battery:12,health:'Healthy',lastSeen:'28 min ago',risk:'High',x:85,y:72},
 {id:7,tag:'TAG-007',name:'Surya',species:'Gaur',scientific:'Bos gaurus',status:'Active',sex:'Male',year:2012,reserve:'Jim Corbett National Park',state:'Uttarakhand',lat:29.52,lng:78.91,speed:3.4,battery:76,health:'Healthy',lastSeen:'8 min ago',risk:'Low',x:28,y:39},
 {id:8,tag:'TAG-008',name:'Nila',species:'Dhole',scientific:'Cuon alpinus',status:'Unknown',sex:'Female',year:2019,reserve:'Ranthambore National Park',state:'Rajasthan',lat:26.11,lng:76.57,speed:0,battery:7,health:'Unknown',lastSeen:'3 hr ago',risk:'Critical',x:67,y:30},
 {id:9,tag:'TAG-009',name:'Muthu',species:'Lion-tailed Macaque',scientific:'Macaca silenus',status:'Active',sex:'Unknown',year:2011,reserve:'Bandipur National Park',state:'Karnataka',lat:11.73,lng:76.18,speed:1.8,battery:58,health:'Healthy',lastSeen:'13 min ago',risk:'Low',x:39,y:73},
 {id:10,tag:'TAG-010',name:'Ira',species:'Nilgiri Tahr',scientific:'Nilgiritragus hylocrius',status:'Inactive',sex:'Male',year:2018,reserve:'Periyar Tiger Reserve',state:'Kerala',lat:9.51,lng:77.19,speed:0,battery:0,health:'Needs review',lastSeen:'1 day ago',risk:'Medium',x:14,y:83}
]
export const initialAlerts = [
 {id:3,animal:'Raja',tag:'TAG-003',species:'Indian Rhinoceros',reserve:'Kaziranga National Park',type:'Poaching-zone proximity',kind:'Detected',severity:'Critical',status:'Resolved',time:'06:24',distance:'0 m',ranger:'Dhruba Gogoi',description:'GPS fix intersects a mapped critical-risk zone.'},
 {id:2,animal:'Maya',tag:'TAG-002',species:'Asian Elephant',reserve:'Ranthambore National Park',type:'Boundary approach predicted',kind:'Predicted',severity:'Critical',status:'Acknowledged',time:'06:21',distance:'180 m',ranger:'Meera Shekhawat',description:'Movement pattern indicates a likely approach to a road corridor.'},
 {id:9,animal:'Muthu',tag:'TAG-009',species:'Lion-tailed Macaque',reserve:'Bandipur National Park',type:'Animal position unknown',kind:'Detected',severity:'High',status:'Open',time:'06:42',distance:'—',ranger:'Kiran Gowda',description:'Collar has not reported within the expected tracking window.'},
 {id:5,animal:'Tara',tag:'TAG-005',species:'Indian Leopard',reserve:'Periyar Tiger Reserve',type:'Risk-zone proximity',kind:'Detected',severity:'Warning',status:'Open',time:'06:30',distance:'640 m',ranger:'Anil Varghese',description:'Animal approaching a mapped human-activity buffer.'},
 {id:17,animal:'Surya',tag:'TAG-007',species:'Gaur',reserve:'Jim Corbett National Park',type:'Predicted corridor crossing',kind:'Predicted',severity:'Warning',status:'Open',time:'07:06',distance:'1.2 km',ranger:'Arjun Rawat',description:'Predicted movement path nears a human settlement zone.'},
 {id:1,animal:'Aarav',tag:'TAG-001',species:'Bengal Tiger',reserve:'Jim Corbett National Park',type:'Risk zone nearby',kind:'Detected',severity:'Info',status:'Open',time:'06:18',distance:'2.1 km',ranger:'Arjun Rawat',description:'Routine proximity notification for ranger awareness.'}
]
export const rangers = [
 {id:1,name:'Arjun Rawat',reserve:'Jim Corbett National Park',assigned:4,pending:2,progress:1,contact:'+91 98191 04729',initials:'AR'},
 {id:2,name:'Meera Shekhawat',reserve:'Ranthambore National Park',assigned:6,pending:1,progress:3,contact:'+91 98382 09458',initials:'MS'},
 {id:3,name:'Dhruba Gogoi',reserve:'Kaziranga National Park',assigned:3,pending:0,progress:1,contact:'+91 98573 14187',initials:'DG'},
 {id:4,name:'Kiran Gowda',reserve:'Bandipur National Park',assigned:5,pending:2,progress:2,contact:'+91 98764 18916',initials:'KG'},
 {id:5,name:'Anil Varghese',reserve:'Periyar Tiger Reserve',assigned:2,pending:1,progress:1,contact:'+91 98955 23645',initials:'AV'}
]
export const predictions = [
 {id:2,animal:'Maya',tag:'TAG-002',species:'Asian Elephant',risk:'Critical',probability:97.6,review:'Confirmed',reserve:'Ranthambore National Park',horizon:'Next 30 min'},
 {id:6,animal:'Kavi',tag:'TAG-006',species:'Sloth Bear',risk:'Critical',probability:86.1,review:'Unreviewed',reserve:'Sundarbans National Park',horizon:'Next 45 min'},
 {id:1,animal:'Aarav',tag:'TAG-001',species:'Bengal Tiger',risk:'High',probability:71.2,review:'Unreviewed',reserve:'Jim Corbett National Park',horizon:'Next 60 min'},
 {id:8,animal:'Nila',tag:'TAG-008',species:'Dhole',risk:'Medium',probability:52.3,review:'Overridden',reserve:'Ranthambore National Park',horizon:'Next 30 min'},
 {id:4,animal:'Veera',tag:'TAG-004',species:'Asiatic Lion',risk:'Medium',probability:45.1,review:'Rejected',reserve:'Bandipur National Park',horizon:'Next 60 min'}
]
