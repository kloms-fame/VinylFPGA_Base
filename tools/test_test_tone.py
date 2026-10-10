"""Contract tests for the raw 48 kHz mono PCM demo tone."""
import math
import struct
import unittest

from tools.gen_test_tone import generate_pcm


class TestTestTone(unittest.TestCase):
    def test_default_output_is_five_seconds_of_raw_48k_mono_s16le(self):
        pcm = generate_pcm()
        self.assertEqual(len(pcm), 5 * 48_000 * 2)
        self.assertNotEqual(pcm[:4], b"RIFF")

    def test_default_output_is_exactly_one_kilohertz_at_minus_twelve_dbfs(self):
        pcm = generate_pcm()
        samples = struct.unpack("<" + "h" * (len(pcm) // 2), pcm)
        period = 48
        self.assertTrue(all(samples[i] == samples[i % period] for i in range(len(samples))))
        peak = max(abs(sample) for sample in samples)
        measured_dbfs = 20.0 * math.log10(peak / 32767.0)
        self.assertAlmostEqual(measured_dbfs, -12.0, delta=0.01)

    def test_rejects_frequency_at_or_above_nyquist(self):
        with self.assertRaises(ValueError):
            generate_pcm(frequency_hz=24_000)

    def test_rejects_nonpositive_duration(self):
        with self.assertRaises(ValueError):
            generate_pcm(duration_seconds=0)


if __name__ == "__main__":
    unittest.main()
