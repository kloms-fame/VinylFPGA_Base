VinylFPGA lecture 11 TF card staging package
============================================

Required files in the TF card root directory:

PIC1.BMP
PIC2.BMP
PIC3.BMP
PIC4.BMP
AUDIO.PCM

Format requirements
-------------------
Volume        : FAT32
Image format  : 640x480, 24-bit, uncompressed BMP
Audio format  : raw PCM, no WAV header, 16-bit signed little-endian,
                48000 Hz, mono, padded to a 512-byte sector boundary

Safe copy
---------
Insert the card, confirm its drive letter, then run:

  powershell -ExecutionPolicy Bypass -File .\Copy-ToTfCard.ps1 -DriveLetter E

If the card is not FAT32, or if you want a clean card, run:

  powershell -ExecutionPolicy Bypass -File .\Copy-ToTfCard.ps1 -DriveLetter E -Format -Force

The -Format -Force path erases the entire target card. Confirm the drive
letter before running it.

Why AUDIO.PCM is padded
-----------------------
The player reads AUDIO.PCM as a contiguous sequence of 512-byte sectors.
Padding the final sector with zeros prevents bytes after the PCM file from
being interpreted as extra audio samples.

Recommended verification
------------------------
1. Put the five files in the FAT32 root directory, not in a subdirectory.
2. Do not delete or recopy AUDIO.PCM after this copy.
3. Safely eject the card.
4. Program VinylFPGA_lecture11_wav_timingfix2.bit.
5. Check PIC1 first, then KEY1, KEY2 short press, KEY2 long press, auto-play,
   picture-switch sound, WAV playback, and transition audio fade.
