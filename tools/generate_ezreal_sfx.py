#!/usr/bin/env python3
"""Generate procedural WAV sound effects for Ezreal skills."""
import wave
import math
import struct
import os

SAMPLE_RATE = 44100

def write_wav(path: str, samples: list[float], sr: int = SAMPLE_RATE):
    """Write float samples [-1,1] to 16-bit WAV. 自动归一化到约 80% 满幅以保真可听."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if not samples:
        return
    peak = max(abs(s) for s in samples)
    if peak < 0.001:
        peak = 1.0
    scale = 0.8 / peak
    with wave.open(path, 'wb') as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(sr)
        data = b''.join(
            struct.pack('<h', int(max(-32767, min(32767, s * scale * 32767))))
            for s in samples
        )
        f.writeframes(data)

def sine(freq: float, dur: float, amp: float = 0.5) -> list[float]:
    n = int(SAMPLE_RATE * dur)
    return [amp * math.sin(2 * math.pi * freq * i / SAMPLE_RATE) for i in range(n)]

def sweep(f_start: float, f_end: float, dur: float, amp: float = 0.4) -> list[float]:
    n = int(SAMPLE_RATE * dur)
    return [amp * math.sin(2 * math.pi * (f_start + (f_end - f_start) * i / n) * i / SAMPLE_RATE) for i in range(n)]

def noise(dur: float, amp: float = 0.3) -> list[float]:
    import random
    n = int(SAMPLE_RATE * dur)
    return [amp * (2 * random.random() - 1) * (1 - i / n) for i in range(n)]

def env_exp(samples: list[float], decay_per_sec: float = 2.0) -> list[float]:
    """指数衰减包络，decay_per_sec 为每秒衰减倍数，越大衰减越慢"""
    out = []
    e = 1.0
    decay_per_sample = decay_per_sec ** (-1.0 / SAMPLE_RATE)
    for s in samples:
        out.append(s * e)
        e *= decay_per_sample
    return out

def mix(*tracks: list[float]) -> list[float]:
    n = max(len(t) for t in tracks)
    return [sum((t[i] if i < len(t) else 0) for t in tracks) / max(1, len(tracks)) for i in range(n)]

# Q - Mystic Shot: 清脆迅捷的"啾"声，高频能量释放
def gen_q_fire():
    s = mix(
        sweep(800, 2400, 0.08, 0.7),
        sine(1200, 0.06, 0.4),
    )
    return env_exp(s, 8.0)

# Q hit: 清脆能量炸裂
def gen_q_hit():
    s = mix(
        noise(0.04, 0.5),
        sine(1800, 0.04, 0.4),
        sine(2400, 0.03, 0.3),
    )
    return env_exp(s, 6.0)

# W - Essence Flux: 空灵嗡鸣，法力波动
def gen_w_fire():
    s = mix(
        sine(400, 0.15, 0.5),
        sine(600, 0.15, 0.35),
        sine(800, 0.12, 0.3),
    )
    # 简单颤音
    n = len(s)
    for i in range(n):
        s[i] *= 0.7 + 0.3 * math.sin(2 * math.pi * 8 * i / SAMPLE_RATE)
    return env_exp(s, 5.0)

# W hit: 魔法铃铛/玻璃清响
def gen_w_hit():
    s = mix(
        sine(1200, 0.08, 0.5),
        sine(1800, 0.06, 0.4),
        sine(2400, 0.04, 0.3),
    )
    return env_exp(s, 6.0)

# E - Arcane Shift: 短促空气爆破，空间切开
def gen_e_blink():
    s = mix(
        noise(0.05, 0.7),
        sweep(200, 600, 0.04, 0.5),
        sine(300, 0.05, 0.4),
    )
    return env_exp(s, 8.0)

# E bolt: 轻微魔法火花
def gen_e_bolt():
    s = mix(
        sweep(600, 1400, 0.06, 0.5),
        sine(1000, 0.05, 0.35),
    )
    return env_exp(s, 6.0)

# R - Trueshot: 蓄力 + 冲击
def gen_r_charge():
    n = int(SAMPLE_RATE * 0.8)
    s = []
    for i in range(n):
        t = i / SAMPLE_RATE
        freq = 80 + 60 * (t / 0.8)
        amp = 0.4 * (t / 0.8)
        s.append(amp * math.sin(2 * math.pi * freq * t))
    return s

def gen_r_blast():
    s = mix(
        noise(0.15, 0.8),
        sine(150, 0.1, 0.6),
        sine(300, 0.08, 0.5),
        sweep(100, 400, 0.12, 0.5),
    )
    return env_exp(s, 4.0)

def gen_r_fire():
    s = mix(
        noise(0.12, 0.7),
        sine(150, 0.08, 0.55),
        sine(300, 0.06, 0.45),
        sweep(100, 400, 0.1, 0.5),
    )
    return env_exp(s, 4.0)

# AA - 平A
def gen_aa_fire():
    s = mix(
        sweep(400, 1200, 0.06, 0.6),
        sine(800, 0.05, 0.4),
    )
    return env_exp(s, 6.0)

def gen_aa_hit():
    s = mix(
        sine(900, 0.04, 0.5),
        sine(1400, 0.03, 0.35),
    )
    return env_exp(s, 6.0)

def main():
    out_dir = os.path.join(os.path.dirname(__file__), '..', 'assets', 'Ezreal', 'skill', 'sfx')
    os.makedirs(out_dir, exist_ok=True)

    sounds = [
        ("aa_fire.wav", gen_aa_fire()),
        ("aa_hit.wav", gen_aa_hit()),
        ("q_fire.wav", gen_q_fire()),
        ("q_hit.wav", gen_q_hit()),
        ("w_fire.wav", gen_w_fire()),
        ("w_hit.wav", gen_w_hit()),
        ("e_blink.wav", gen_e_blink()),
        ("e_bolt.wav", gen_e_bolt()),
        ("r_charge.wav", gen_r_charge()),
        ("r_blast.wav", gen_r_blast()),
        ("r_fire.wav", gen_r_fire()),
    ]
    for name, samples in sounds:
        path = os.path.join(out_dir, name)
        write_wav(path, samples)
        print("Generated:", path)

if __name__ == "__main__":
    main()
