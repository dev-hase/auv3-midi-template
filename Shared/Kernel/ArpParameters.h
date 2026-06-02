//
//  ArpParameters.h
//  Shared parameter definitions for the Arp AUv3 MIDI plugin.
//
//  This is a plain C header so it can be included from the realtime C++ kernel,
//  the Objective-C++ AUAudioUnit subclass, and (via the bridging header) Swift.
//  Keeping the addresses in one place makes them the single source of truth.
//

#ifndef ArpParameters_h
#define ArpParameters_h

// Parameter addresses. These map 1:1 onto AUParameter.address values.
typedef enum ArpParameterAddress {
    ArpParamRate    = 0,   // indexed: note division (see ArpRateOption)
    ArpParamMode    = 1,   // indexed: arp direction (see ArpModeOption)
    ArpParamOctaves = 2,   // integer 1...4
    ArpParamGate    = 3,   // 0.05...1.0 (fraction of a step the note is held)
    ArpParamHold    = 4,   // boolean 0/1 (latch held notes)
} ArpParameterAddress;

// Note-division choices for ArpParamRate.
typedef enum ArpRateOption {
    ArpRate_1_4 = 0,   // quarter notes
    ArpRate_1_8,       // eighth notes
    ArpRate_1_16,      // sixteenth notes
    ArpRate_1_8T,      // eighth triplets
    ArpRate_1_16T,     // sixteenth triplets
    ArpRate_Count
} ArpRateOption;

// Direction choices for ArpParamMode.
typedef enum ArpModeOption {
    ArpMode_Up = 0,
    ArpMode_Down,
    ArpMode_UpDown,
    ArpMode_Random,
    ArpMode_AsPlayed,
    ArpMode_Count
} ArpModeOption;

#endif /* ArpParameters_h */
