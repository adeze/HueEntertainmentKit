#ifndef HUE_ENTERTAINMENT_AUDIO_RT_H
#define HUE_ENTERTAINMENT_AUDIO_RT_H

#include <stdatomic.h>
#include <stdint.h>

typedef struct {
    _Atomic(uint64_t) sequence;
    _Atomic(uint64_t) host_time;
    _Atomic(uint32_t) rms_bits;
    _Atomic(uint32_t) peak_bits;
    _Atomic(uint32_t) centroid_bits;
    _Atomic(uint32_t) transient_bits;
    _Atomic(uint32_t) band_bits[8];
} hue_feature_mailbox_t;

void hue_feature_mailbox_init(hue_feature_mailbox_t *mailbox);
void hue_feature_mailbox_publish(hue_feature_mailbox_t *mailbox, uint64_t host_time,
    float rms, float peak, float centroid, float transient, const float bands[8]);
int hue_feature_mailbox_read(const hue_feature_mailbox_t *mailbox, uint64_t *host_time,
    float *rms, float *peak, float *centroid, float *transient, float bands[8]);

#endif
