#include "HueEntertainmentAudioRT.h"
#include <string.h>

static uint32_t bits(float value) { uint32_t output; memcpy(&output, &value, sizeof(output)); return output; }
static float value(uint32_t input) { float output; memcpy(&output, &input, sizeof(output)); return output; }

void hue_feature_mailbox_init(hue_feature_mailbox_t *m) {
    atomic_init(&m->sequence, 0); atomic_init(&m->host_time, 0);
    atomic_init(&m->rms_bits, 0); atomic_init(&m->peak_bits, 0);
    atomic_init(&m->centroid_bits, 0); atomic_init(&m->transient_bits, 0);
    for (int i = 0; i < 8; i++) atomic_init(&m->band_bits[i], 0);
}

void hue_feature_mailbox_publish(hue_feature_mailbox_t *m, uint64_t host_time,
    float rms, float peak, float centroid, float transient, const float bands[8]) {
    uint64_t sequence = atomic_load_explicit(&m->sequence, memory_order_relaxed);
    atomic_store_explicit(&m->sequence, sequence + 1, memory_order_release);
    atomic_store_explicit(&m->host_time, host_time, memory_order_relaxed);
    atomic_store_explicit(&m->rms_bits, bits(rms), memory_order_relaxed);
    atomic_store_explicit(&m->peak_bits, bits(peak), memory_order_relaxed);
    atomic_store_explicit(&m->centroid_bits, bits(centroid), memory_order_relaxed);
    atomic_store_explicit(&m->transient_bits, bits(transient), memory_order_relaxed);
    for (int i = 0; i < 8; i++) atomic_store_explicit(&m->band_bits[i], bits(bands[i]), memory_order_relaxed);
    atomic_store_explicit(&m->sequence, sequence + 2, memory_order_release);
}

int hue_feature_mailbox_read(const hue_feature_mailbox_t *m, uint64_t *host_time,
    float *rms, float *peak, float *centroid, float *transient, float bands[8]) {
    for (int attempt = 0; attempt < 3; attempt++) {
        uint64_t before = atomic_load_explicit(&m->sequence, memory_order_acquire);
        if (before & 1) continue;
        *host_time = atomic_load_explicit(&m->host_time, memory_order_relaxed);
        *rms = value(atomic_load_explicit(&m->rms_bits, memory_order_relaxed));
        *peak = value(atomic_load_explicit(&m->peak_bits, memory_order_relaxed));
        *centroid = value(atomic_load_explicit(&m->centroid_bits, memory_order_relaxed));
        *transient = value(atomic_load_explicit(&m->transient_bits, memory_order_relaxed));
        for (int i = 0; i < 8; i++) bands[i] = value(atomic_load_explicit(&m->band_bits[i], memory_order_relaxed));
        uint64_t after = atomic_load_explicit(&m->sequence, memory_order_acquire);
        if (before == after) return before != 0;
    }
    return 0;
}
