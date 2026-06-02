//
//  ArpAudioUnit.h
//  The AUAudioUnit subclass for the Arp AUv3 MIDI plugin.
//
//  This header is pure Objective-C (no C++ leaks out) so it can be imported
//  from Swift via the bridging header. The C++ kernel is held privately in the
//  .mm implementation.
//

#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudioKit/CoreAudioKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ArpAudioUnit : AUAudioUnit

// Exposed so the view controller / UI can read & observe parameters.
@property (nonatomic, readonly) AUParameterTree *parameterTree;

@end

NS_ASSUME_NONNULL_END
