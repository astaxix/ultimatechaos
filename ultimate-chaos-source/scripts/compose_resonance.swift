// Original score: Astral Afterhours. Offline MIDI-performance rendering with Apple's system instruments.
import AVFoundation
struct Event { let sample:Int64;let instrument:Int;let note:UInt8;let velocity:UInt8;let on:Bool }
let sr=32000.0, beat=60.0/74.0, bars=48, length=Double(48*4)*60.0/74.0
let output=CommandLine.arguments.count>1 ? CommandLine.arguments[1] : "outputs/polish/resonance-master.caf"
let engine=AVAudioEngine(), reverb=AVAudioUnitReverb(), eq=AVAudioUnitEQ(numberOfBands:2)
eq.bands[0].filterType = .highPass;eq.bands[0].frequency=65;eq.bands[0].bypass=false
eq.bands[1].filterType = .lowPass;eq.bands[1].frequency=6200;eq.bands[1].bypass=false
eq.globalGain = -4
reverb.loadFactoryPreset(.largeHall);reverb.wetDryMix=23
engine.attach(reverb);engine.attach(eq)
let format=AVAudioFormat(standardFormatWithSampleRate:sr,channels:2)!
var instruments:[AVAudioUnitSampler]=[]
let bank=URL(fileURLWithPath:"/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls")
for (program,volume,pan) in [(0,Float(0.69),Float(-0.1)),(24,Float(0.26),Float(0.28)),(48,Float(0.13),Float(-0.25)),(73,Float(0.17),Float(0.18)),(32,Float(0.29),Float(0.0))] {
 let s=AVAudioUnitSampler();engine.attach(s);try s.loadSoundBankInstrument(at:bank,program:UInt8(program),bankMSB:UInt8(kAUSampler_DefaultMelodicBankMSB),bankLSB:0);s.volume=volume;s.stereoPan=pan;engine.connect(s,to:reverb,format:format);instruments.append(s)
}
// Samplers need independent mixer buses before a shared reverb.
engine.disconnectNodeInput(reverb)
for s in instruments {engine.disconnectNodeOutput(s);engine.connect(s,to:engine.mainMixerNode,format:format)}
engine.disconnectNodeOutput(engine.mainMixerNode)
engine.connect(engine.mainMixerNode,to:eq,format:format);engine.connect(eq,to:reverb,format:format);engine.connect(reverb,to:engine.outputNode,format:format)
var events:[Event]=[]
func note(_ inst:Int,_ pitch:Int,_ at:Double,_ duration:Double,_ velocity:Int){let n=UInt8(pitch);events.append(Event(sample:Int64(max(0,at)*sr),instrument:inst,note:n,velocity:UInt8(velocity),on:true));events.append(Event(sample:Int64((max(0,at)+duration)*sr),instrument:inst,note:n,velocity:0,on:false))}
let harmony=[[50,57,60,64,69],[46,53,57,60,65],[48,55,59,62,67],[45,52,55,59,64],[53,60,64,67,72],[48,55,57,62,67],[43,50,57,60,65],[45,52,56,60,64]]
let melody=[[76,74,72,69],[74,72,69,65],[71,74,79,76],[72,71,67,64],[76,79,81,79],[74,72,69,67],[69,72,74,77],[71,68,64,69]]
for bar in 0..<bars {
 let chord=harmony[(bar/2)%8], section=bar/16, at=Double(bar)*4*beat
 if bar%2==0 {for (j,p) in chord.prefix(4).enumerated(){note(2,p,at+Double(j)*0.012,7.7*beat,27+section*2)};note(4,chord[0]-12,at,3.1*beat,43)}
 let order=bar%2==0 ? [0,2,1,3,2,4] : [0,1,3,2]
 let times=bar%2==0 ? [0.0,0.72,1.45,2.25,2.9,3.45] : [0.0,1.1,2.35,3.2]
 for (j,index) in order.enumerated(){let human=Double(((bar*13+j*7)%11)-5)*0.0024;note(0,chord[index]+12,at+times[j]*beat+human,2.9*beat,42+(bar+j)%8+(section==1 ? 3:0))}
 if bar%2==1 {let phrase=melody[(bar/2)%8];for j in 0..<2 {note(0,phrase[(j+section)%4],at+(j==0 ? 0.45:2.65)*beat,1.8*beat,48+((bar+j)%6))}}
 if bar>=8 && bar<40 {for j in 0..<3{note(1,chord[(j+1)%5]+12,at+([0.4,1.9,3.1][j])*beat,2.3*beat,36+(j*3))}}
 if section==1 && bar%4==3 {note(3,melody[(bar/2)%8][0],at+beat,2.1*beat,34)}
}
events.sort{$0.sample==$1.sample ? (!$0.on && $1.on):$0.sample<$1.sample}
try engine.enableManualRenderingMode(.offline,format:format,maximumFrameCount:4096)
try engine.start()
let file=try AVAudioFile(forWriting:URL(fileURLWithPath:output),settings:format.settings),buffer=AVAudioPCMBuffer(pcmFormat:engine.manualRenderingFormat,frameCapacity:4096)!
var index=0;let total=Int64((length+7)*sr)
while engine.manualRenderingSampleTime<total {
 let now=engine.manualRenderingSampleTime
 while index<events.count && events[index].sample<=now {let e=events[index];if e.on{instruments[e.instrument].startNote(e.note,withVelocity:e.velocity,onChannel:0)}else{instruments[e.instrument].stopNote(e.note,onChannel:0)};index+=1}
 let next=index<events.count ? events[index].sample : total
 let count=AVAudioFrameCount(min(4096,max(1,min(total-now,next-now))))
 let result=try engine.renderOffline(count,to:buffer)
 switch result{case .success:try file.write(from:buffer);case .cannotDoInCurrentContext:continue;default:throw NSError(domain:"OfflineAudio",code:1)}
}
engine.stop();print("Rendered Astral Afterhours: \(length) seconds plus reverb tail → \(output)")
