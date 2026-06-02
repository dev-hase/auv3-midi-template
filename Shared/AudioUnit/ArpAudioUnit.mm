//
//  ArpAudioUnit.mm
//  Objective-C++ AUAudioUnit subclass that drives the C++ ArpKernel.
//
//  Responsibilities:
//    * Build the AUParameterTree (single source of truth: ArpParameters.h).
//    * Advertise a MIDI output (MIDIOutputNames) so hosts route generated MIDI.
//    * Provide a silent audio output bus for host compatibility.
//    * Translate the host render call into kernel input/output each cycle.
//
//  All realtime work lives in ArpKernel (no allocation / no ObjC messaging on
//  the audio thread). The render block only does cheap pointer reads.
//

#import "ArpAudioUnit.h"
#import <AVFoundation/AVFoundation.h>
#import "ArpKernel.hpp"
#include <cstring>
#include <cmath>

// Per-render send context: lets the C++ kernel emit MIDI through the host's
// output block without the kernel knowing anything about AudioToolbox.
namespace {
struct SendContext {
    AUMIDIOutputEventBlock __unsafe_unretained block;
    AUEventSampleTime now;
};

void ArpSend(void* context, int frameOffset, uint8_t b0, uint8_t b1, uint8_t b2) {
    SendContext* ctx = static_cast<SendContext*>(context);
    if (!ctx->block) return;
    uint8_t bytes[3] = { b0, b1, b2 };
    ctx->block(ctx->now + frameOffset, 0, 3, bytes);
}
} // namespace

@implementation ArpAudioUnit {
    ArpKernel              _kernel;
    AUAudioUnitBusArray   *_outputBusArray;
    AVAudioFormat         *_format;        // strong ref kept alive for the bus
}

@synthesize parameterTree = _parameterTree;

- (instancetype)initWithComponentDescription:(AudioComponentDescription)componentDescription
                                     options:(AudioComponentInstantiationOptions)options
                                       error:(NSError **)outError {
    self = [super initWithComponentDescription:componentDescription options:options error:outError];
    if (self == nil) { return nil; }

    _format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100.0 channels:2];
    _kernel.setSampleRate(_format.sampleRate);

    [self setupParameterTree];

    // A single (silent) output bus keeps the unit valid in audio-effect slots.
    AUAudioUnitBus *outBus = [[AUAudioUnitBus alloc] initWithFormat:_format error:outError];
    if (outBus == nil) { return nil; }
    _outputBusArray = [[AUAudioUnitBusArray alloc] initWithAudioUnit:self
                                                            busType:AUAudioUnitBusTypeOutput
                                                             busses:@[outBus]];

    self.maximumFramesToRender = 4096;
    return self;
}

#pragma mark - Parameters

- (void)setupParameterTree {
    AUParameter *rate = [AUParameterTree createParameterWithIdentifier:@"rate" name:@"Rate"
        address:ArpParamRate min:0 max:ArpRate_Count - 1
        unit:kAudioUnitParameterUnit_Indexed unitName:nil
        flags:kAudioUnitParameterFlag_IsReadable | kAudioUnitParameterFlag_IsWritable | kAudioUnitParameterFlag_ValuesHaveStrings
        valueStrings:@[@"1/4", @"1/8", @"1/16", @"1/8T", @"1/16T"] dependentParameters:nil];
    rate.value = ArpRate_1_16;

    AUParameter *mode = [AUParameterTree createParameterWithIdentifier:@"mode" name:@"Mode"
        address:ArpParamMode min:0 max:ArpMode_Count - 1
        unit:kAudioUnitParameterUnit_Indexed unitName:nil
        flags:kAudioUnitParameterFlag_IsReadable | kAudioUnitParameterFlag_IsWritable | kAudioUnitParameterFlag_ValuesHaveStrings
        valueStrings:@[@"Up", @"Down", @"Up/Down", @"Random", @"As Played"] dependentParameters:nil];
    mode.value = ArpMode_Up;

    AUParameter *octaves = [AUParameterTree createParameterWithIdentifier:@"octaves" name:@"Octaves"
        address:ArpParamOctaves min:1 max:4
        unit:kAudioUnitParameterUnit_Indexed unitName:nil
        flags:kAudioUnitParameterFlag_IsReadable | kAudioUnitParameterFlag_IsWritable | kAudioUnitParameterFlag_ValuesHaveStrings
        valueStrings:@[@"1", @"2", @"3", @"4"] dependentParameters:nil];
    octaves.value = 1;

    AUParameter *gate = [AUParameterTree createParameterWithIdentifier:@"gate" name:@"Gate"
        address:ArpParamGate min:0.05 max:1.0
        unit:kAudioUnitParameterUnit_Percent unitName:nil
        flags:kAudioUnitParameterFlag_IsReadable | kAudioUnitParameterFlag_IsWritable
        valueStrings:nil dependentParameters:nil];
    gate.value = 0.5;

    AUParameter *hold = [AUParameterTree createParameterWithIdentifier:@"hold" name:@"Hold"
        address:ArpParamHold min:0 max:1
        unit:kAudioUnitParameterUnit_Boolean unitName:nil
        flags:kAudioUnitParameterFlag_IsReadable | kAudioUnitParameterFlag_IsWritable
        valueStrings:nil dependentParameters:nil];
    hold.value = 0;

    _parameterTree = [AUParameterTree createTreeWithChildren:@[rate, mode, octaves, gate, hold]];

    // Seed the kernel with the initial values.
    ArpKernel *kernel = &_kernel;
    for (AUParameter *p in @[rate, mode, octaves, gate, hold]) {
        kernel->setParameter((ArpParameterAddress)p.address, p.value);
    }

    __block ArpKernel *blockKernel = &_kernel;
    _parameterTree.implementorValueObserver = ^(AUParameter *param, AUValue value) {
        blockKernel->setParameter((ArpParameterAddress)param.address, value);
    };
    _parameterTree.implementorValueProvider = ^AUValue(AUParameter *param) {
        return blockKernel->getParameter((ArpParameterAddress)param.address);
    };
    _parameterTree.implementorStringFromValueCallback = ^NSString *(AUParameter *param, const AUValue *valuePtr) {
        AUValue value = valuePtr ? *valuePtr : param.value;
        if (param.valueStrings != nil) {
            NSInteger index = (NSInteger)lround(value);
            if (index >= 0 && index < (NSInteger)param.valueStrings.count) {
                return param.valueStrings[index];
            }
        }
        return [NSString stringWithFormat:@"%.2f", value];
    };
}

#pragma mark - Busses

- (AUAudioUnitBusArray *)outputBusses { return _outputBusArray; }

#pragma mark - MIDI output advertisement

// Declaring an output name is what tells hosts this unit emits MIDI.
- (NSArray<NSString *> *)MIDIOutputNames { return @[@"Arp Out"]; }

#pragma mark - Resource allocation

- (BOOL)allocateRenderResourcesAndReturnError:(NSError **)outError {
    if (![super allocateRenderResourcesAndReturnError:outError]) { return NO; }
    _kernel.setSampleRate(self.outputBusses[0].format.sampleRate);
    _kernel.reset();
    return YES;
}

- (void)deallocateRenderResources {
    [super deallocateRenderResources];
}

#pragma mark - Render

- (AUInternalRenderBlock)internalRenderBlock {
    // Capture only what the realtime thread needs. __unsafe_unretained avoids
    // ARC retain/release traffic on the audio thread.
    __unsafe_unretained ArpAudioUnit *unit = self;
    ArpKernel *kernel = &_kernel;

    return ^AUAudioUnitStatus(AudioUnitRenderActionFlags *actionFlags,
                              const AudioTimeStamp       *timestamp,
                              AUAudioFrameCount           frameCount,
                              NSInteger                   outputBusNumber,
                              AudioBufferList            *outputData,
                              const AURenderEvent        *realtimeEventListHead,
                              AURenderPullInputBlock      pullInputBlock) {
        // 1. Pull musical context from the host.
        double tempo = 120.0, beat = 0.0;
        BOOL playing = NO, contextValid = NO;

        AUHostMusicalContextBlock musicalContext = unit.musicalContextBlock;
        if (musicalContext) {
            double tsNumerator = 0, downbeat = 0;
            NSInteger tsDenominator = 0, sampleOffsetToNextBeat = 0;
            if (musicalContext(&tempo, &tsNumerator, &tsDenominator,
                               &beat, &sampleOffsetToNextBeat, &downbeat)) {
                contextValid = YES;
            }
        }
        AUHostTransportStateBlock transport = unit.transportStateBlock;
        if (transport) {
            AUHostTransportStateFlags flags = 0; double pos = 0, start = 0;
            if (transport(&flags, &pos, &start, NULL)) {
                playing = (flags & AUHostTransportStateMoving) != 0;
            }
        }
        kernel->setMusicalContext(contextValid, tempo, beat, playing);

        // 2. Feed incoming MIDI into the kernel.
        AUEventSampleTime now = (AUEventSampleTime)timestamp->mSampleTime;
        for (const AURenderEvent *event = realtimeEventListHead; event != NULL; event = event->head.next) {
            if (event->head.eventType == AURenderEventMIDI) {
                const AUMIDIEvent *midi = &event->MIDI;
                int offset = (int)(midi->eventSampleTime - now);
                if (offset < 0) offset = 0;
                if (offset >= (int)frameCount) offset = (int)frameCount - 1;
                uint8_t d1 = midi->length > 1 ? midi->data[1] : 0;
                uint8_t d2 = midi->length > 2 ? midi->data[2] : 0;
                kernel->handleMIDIInput(offset, midi->data[0], d1, d2);
            }
        }

        // 3. Run the engine, sending generated MIDI through the host block.
        SendContext sendCtx { unit.MIDIOutputEventBlock, now };
        kernel->setSendCallback(ArpSend, &sendCtx);
        kernel->process((int)frameCount);
        kernel->setSendCallback(nullptr, nullptr);

        // 4. We are a MIDI processor: output silence.
        if (outputData != NULL) {
            for (UInt32 i = 0; i < outputData->mNumberBuffers; ++i) {
                AudioBuffer *b = &outputData->mBuffers[i];
                if (b->mData != NULL) memset(b->mData, 0, b->mDataByteSize);
            }
        }
        return noErr;
    };
}

@end
