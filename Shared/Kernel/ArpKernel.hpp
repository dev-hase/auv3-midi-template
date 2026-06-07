//
//  ArpKernel.hpp
//  Realtime-safe arpeggiator engine.
//
//  This is plain C++ with NO Objective-C, no allocation on the render thread,
//  and no AudioToolbox dependency. It is owned by ArpAudioUnit (Objective-C++)
//  which feeds it incoming MIDI + musical context and pumps it once per render
//  cycle. Generated MIDI is pushed back out through a C function-pointer
//  callback so the kernel stays framework-agnostic and unit-testable.
//
//  Header-only on purpose: one fewer file to wire into the Xcode targets.
//

#ifndef ArpKernel_hpp
#define ArpKernel_hpp

#include <cstdint>
#include <cmath>
#include "ArpParameters.h"

class ArpKernel {
public:
    // status, data1, data2 are raw MIDI 1.0 bytes. frameOffset is the sample
    // offset within the current render cycle.
    typedef void (*SendFn)(void* context, int frameOffset,
                           uint8_t status, uint8_t data1, uint8_t data2);

    ArpKernel() { reset(); }

    void setSampleRate(double sampleRate) { mSampleRate = sampleRate; }

    void setSendCallback(SendFn fn, void* context) { mSend = fn; mSendCtx = context; }

    // Called from the AU's parameter observer. value is the raw AUValue.
    void setParameter(ArpParameterAddress address, float value) {
        switch (address) {
            case ArpParamRate:    mRate    = clampInt((int)value, 0, ArpRate_Count - 1); break;
            case ArpParamMode:    mMode    = clampInt((int)value, 0, ArpMode_Count - 1); break;
            case ArpParamOctaves: mOctaves = clampInt((int)value, 1, 4); break;
            case ArpParamGate:    mGate    = clampFloat(value, 0.05f, 1.0f); break;
            case ArpParamHold:    setHold(value > 0.5f); break;
        }
    }

    float getParameter(ArpParameterAddress address) const {
        switch (address) {
            case ArpParamRate:    return (float)mRate;
            case ArpParamMode:    return (float)mMode;
            case ArpParamOctaves: return (float)mOctaves;
            case ArpParamGate:    return mGate;
            case ArpParamHold:    return mHold ? 1.0f : 0.0f;
        }
        return 0.0f;
    }

    // Provided once per render cycle, before process().
    void setMusicalContext(bool valid, double tempoBPM, double beatPosition, bool isPlaying) {
        mContextValid = valid;
        if (valid && tempoBPM > 0.0) mTempo = tempoBPM;
        mBeatPosition = beatPosition;
        mIsPlaying = isPlaying;
    }

    void reset() {
        mHeldCount = 0;
        mPhysicalCount = 0;
        mPendingOffCount = 0;
        mInputCount = 0;
        mArpIndex = 0;
        mPingPos = 0;
        mDirectionUp = true;
        mSamplesToNextStep = 0.0;
        mActiveNote = -1;
        for (int i = 0; i < 128; ++i) mVel[i] = 100;
    }

    // Queue an incoming MIDI event for this render cycle (called per event).
    void handleMIDIInput(int frameOffset, uint8_t status, uint8_t data1, uint8_t data2) {
        if (mInputCount < kMaxInput) {
            mInput[mInputCount++] = { frameOffset, status, data1, data2 };
        }
    }

    // Advance the engine by frameCount samples, emitting MIDI via the callback.
    void process(int frameCount) {
        const double samplesPerBeat = (60.0 / mTempo) * mSampleRate;
        const double samplesPerStep = samplesPerBeat / stepsPerBeat(mRate);

        // When the host transport is running we lock the step grid to the host
        // beat position; otherwise we free-run from wherever we are.
        if (mContextValid && mIsPlaying && mHeldCount > 0) {
            const double steps = mBeatPosition * stepsPerBeat(mRate);
            const double frac  = steps - std::floor(steps);
            mSamplesToNextStep = (frac < 1e-6) ? 0.0 : (1.0 - frac) * samplesPerStep;
        }

        int inCursor = 0;
        for (int f = 0; f < frameCount; ++f) {
            // 1. Apply any input events landing on this frame.
            while (inCursor < mInputCount && mInput[inCursor].offset == f) {
                applyInput(mInput[inCursor], f);
                ++inCursor;
            }

            // 2. Fire any scheduled note-offs that are now due.
            for (int i = mPendingOffCount - 1; i >= 0; --i) {
                if ((mPendingOff[i].framesRemaining -= 1.0) <= 0.0) {
                    send(f, 0x80, (uint8_t)mPendingOff[i].note, 0);
                    if (mPendingOff[i].note == mActiveNote) mActiveNote = -1;
                    mPendingOff[i] = mPendingOff[--mPendingOffCount];
                }
            }

            // 3. Advance the step clock (only while notes are held/latched).
            if (mHeldCount > 0) {
                if ((mSamplesToNextStep -= 1.0) <= 0.0) {
                    triggerStep(f, samplesPerStep);
                    mSamplesToNextStep += samplesPerStep;
                }
            }
        }

        // Any events queued past frameCount carry over to the next cycle.
        int carry = 0;
        for (int i = inCursor; i < mInputCount; ++i) {
            mInput[carry] = mInput[i];
            mInput[carry].offset -= frameCount;
            ++carry;
        }
        mInputCount = carry;
    }

private:
    static constexpr int kMaxInput = 256;
    static constexpr int kMaxPending = 64;

    struct InEvent { int offset; uint8_t status, data1, data2; };
    struct PendingOff { int note; double framesRemaining; };

    static int clampInt(int v, int lo, int hi) { return v < lo ? lo : (v > hi ? hi : v); }
    static float clampFloat(float v, float lo, float hi) { return v < lo ? lo : (v > hi ? hi : v); }

    // Steps per quarter-note for each rate option.
    static double stepsPerBeat(int rate) {
        switch (rate) {
            case ArpRate_1_4:   return 1.0;
            case ArpRate_1_8:   return 2.0;
            case ArpRate_1_16:  return 4.0;
            case ArpRate_1_8T:  return 3.0;
            case ArpRate_1_16T: return 6.0;
            default:            return 4.0;
        }
    }

    void send(int frameOffset, uint8_t b0, uint8_t b1, uint8_t b2) {
        if (mSend) mSend(mSendCtx, frameOffset, b0, b1, b2);
    }

    void applyInput(const InEvent& e, int frameOffset) {
        const uint8_t type = e.status & 0xF0;
        const bool noteOn  = (type == 0x90) && (e.data2 > 0);
        const bool noteOff = (type == 0x80) || ((type == 0x90) && (e.data2 == 0));

        if (noteOn) {
            const bool wasEmpty = (mHeldCount == 0);
            // In hold mode, the first key of a fresh chord clears the latch.
            if (mHold && mPhysicalCount == 0) clearHeld();
            addPhysical(e.data1);
            addHeld(e.data1, e.data2);
            if (wasEmpty) mSamplesToNextStep = 0.0; // start stepping immediately
        } else if (noteOff) {
            removePhysical(e.data1);
            if (!mHold) {
                removeHeld(e.data1);
                if (mHeldCount == 0 && mActiveNote >= 0) {
                    send(frameOffset, 0x80, (uint8_t)mActiveNote, 0);
                    mActiveNote = -1;
                    mPendingOffCount = 0;
                }
            }
        }
    }

    void setHold(bool on) {
        if (mHold == on) return;
        mHold = on;
        // Turning hold off while no keys are physically down releases the latch.
        if (!mHold && mPhysicalCount == 0) clearHeld();
    }

    void clearHeld() { mHeldCount = 0; }

    void addHeld(uint8_t note, uint8_t vel) {
        mVel[note] = vel;
        for (int i = 0; i < mHeldCount; ++i) if (mHeld[i] == note) return;
        if (mHeldCount < 128) mHeld[mHeldCount++] = note;
    }

    void removeHeld(uint8_t note) {
        for (int i = 0; i < mHeldCount; ++i) {
            if (mHeld[i] == note) {
                for (int j = i; j < mHeldCount - 1; ++j) mHeld[j] = mHeld[j + 1];
                --mHeldCount;
                return;
            }
        }
    }

    void addPhysical(uint8_t note) {
        for (int i = 0; i < mPhysicalCount; ++i) if (mPhysical[i] == note) return;
        if (mPhysicalCount < 128) mPhysical[mPhysicalCount++] = note;
    }

    void removePhysical(uint8_t note) {
        for (int i = 0; i < mPhysicalCount; ++i) {
            if (mPhysical[i] == note) {
                for (int j = i; j < mPhysicalCount - 1; ++j) mPhysical[j] = mPhysical[j + 1];
                --mPhysicalCount;
                return;
            }
        }
    }

    // Expand the held notes across octaves into an ordered play sequence.
    // Returns the count; fills notes[] and vels[].
    int buildSequence(uint8_t* notes, uint8_t* vels, int maxOut) {
        // Base order: arrival order for As-Played, otherwise pitch-sorted.
        uint8_t base[128];
        int n = mHeldCount;
        for (int i = 0; i < n; ++i) base[i] = mHeld[i];

        if (mMode != ArpMode_AsPlayed) {
            // insertion sort ascending (n is tiny)
            for (int i = 1; i < n; ++i) {
                uint8_t v = base[i];
                int j = i - 1;
                while (j >= 0 && base[j] > v) { base[j + 1] = base[j]; --j; }
                base[j + 1] = v;
            }
        }

        int count = 0;
        for (int oct = 0; oct < mOctaves; ++oct) {
            for (int i = 0; i < n && count < maxOut; ++i) {
                int pitch = base[i] + 12 * oct;
                if (pitch > 127) continue;
                notes[count] = (uint8_t)pitch;
                vels[count]  = mVel[base[i]];
                ++count;
            }
        }
        if (mMode == ArpMode_Down && count > 1) {
            for (int i = 0; i < count / 2; ++i) {
                uint8_t tn = notes[i]; notes[i] = notes[count - 1 - i]; notes[count - 1 - i] = tn;
                uint8_t tv = vels[i];  vels[i]  = vels[count - 1 - i];  vels[count - 1 - i]  = tv;
            }
        }
        return count;
    }

    void triggerStep(int frameOffset, double samplesPerStep) {
        uint8_t notes[128], vels[128];
        const int n = buildSequence(notes, vels, 128);
        if (n == 0) { mActiveNote = -1; return; }

        int idx;
        switch (mMode) {
            case ArpMode_Random:
                idx = (int)(nextRand() % (uint32_t)n);
                break;
            case ArpMode_UpDown:
                idx = clampInt(mPingPos, 0, n - 1);
                if (n == 1) { mPingPos = 0; }
                else if (mDirectionUp) {
                    if (++mPingPos >= n - 1) { mPingPos = n - 1; mDirectionUp = false; }
                } else {
                    if (--mPingPos <= 0) { mPingPos = 0; mDirectionUp = true; }
                }
                break;
            default: // Up, Down (pre-reversed), As-Played
                idx = mArpIndex % n;
                mArpIndex = (mArpIndex + 1) % n;
                break;
        }

        const uint8_t note = notes[idx];
        const uint8_t vel  = vels[idx] ? vels[idx] : 100;

        send(frameOffset, 0x90, note, vel);                 // note on
        mActiveNote = note;

        // Schedule the matching note-off after gate * step length.
        if (mPendingOffCount < kMaxPending) {
            double dur = mGate * samplesPerStep;
            if (dur < 1.0) dur = 1.0;
            mPendingOff[mPendingOffCount++] = { note, dur };
        }
    }

    uint32_t nextRand() {
        mRng ^= mRng << 13; mRng ^= mRng >> 17; mRng ^= mRng << 5;
        return mRng;
    }

    // --- configuration ---
    double mSampleRate = 44100.0;
    int    mRate = ArpRate_1_16;
    int    mMode = ArpMode_Up;
    int    mOctaves = 1;
    float  mGate = 0.5f;
    bool   mHold = false;

    // --- musical context (per render cycle) ---
    bool   mContextValid = false;
    bool   mIsPlaying = false;
    double mTempo = 120.0;
    double mBeatPosition = 0.0;

    // --- live note state ---
    uint8_t mHeld[128];      int mHeldCount = 0;      // notes feeding the arp
    uint8_t mPhysical[128];  int mPhysicalCount = 0;  // keys physically down
    uint8_t mVel[128];                                // last velocity per note

    // --- scheduling ---
    double mSamplesToNextStep = 0.0;
    int    mArpIndex = 0;
    int    mPingPos = 0;
    bool   mDirectionUp = true;
    int    mActiveNote = -1;

    PendingOff mPendingOff[kMaxPending]; int mPendingOffCount = 0;
    InEvent    mInput[kMaxInput];        int mInputCount = 0;

    uint32_t mRng = 0x9E3779B9u;

    SendFn mSend = nullptr;
    void*  mSendCtx = nullptr;
};

#endif /* ArpKernel_hpp */
