"""Validate the built USB partition tables, FAT volumes and A77F driver payload.
Run in the Linux builder with Python, dosfstools, mtools and wimlib installed.
"""
import hashlib
from pathlib import Path
import struct
import subprocess
import tempfile
import uuid
import zlib

image = Path('dist/pchh-usb.img')
source = Path('winpe/drivers/Intel-IRST_12-15G')
required = ['iaStorVD.inf', 'iaStorVD.cat', 'iaStorVD.sys',
            'RstMwService.exe', 'RstMwEventLogMsg.dll']
basic_data = 'ebd0a0a2-b9e5-4433-87c0-68b6b72699c7'

def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout

def header(f, lba):
    f.seek(lba * 512)
    raw = f.read(512)
    assert raw[:8] == b'EFI PART'
    size, checksum = struct.unpack_from('<II', raw, 12)
    clean = bytearray(raw[:size])
    clean[16:20] = bytes(4)
    assert zlib.crc32(clean) == checksum, 'Invalid GPT header CRC'
    entries_lba, count, stride, entries_crc = struct.unpack_from('<QIII', raw, 72)
    f.seek(entries_lba * 512)
    entries = f.read(count * stride)
    assert zlib.crc32(entries) == entries_crc, 'Invalid GPT entries CRC'
    return raw, entries, stride

with image.open('rb') as f:
    mbr = f.read(512)
    assert mbr[510:512] == b'\x55\xaa'
    assert mbr[450] == 0xee, 'Missing protective MBR'
    assert mbr[462:510] == bytes(48), 'Hybrid MBR remains'
    assert any(mbr[:440]), 'GRUB BIOS boot code lost'
    primary, entries, stride = header(f, 1)
    backup_lba = struct.unpack_from('<Q', primary, 32)[0]
    assert backup_lba == image.stat().st_size // 512 - 1
    _, backup_entries, _ = header(f, backup_lba)
    assert entries == backup_entries
    parts = {}
    for offset in range(0, len(entries), stride):
        entry = entries[offset:offset + stride]
        if entry[:16] == bytes(16):
            continue
        name = entry[56:128].decode('utf-16le').rstrip('\0')
        start, end, attributes = struct.unpack_from('<QQQ', entry, 32)
        if name in ('PCHH_DATA', 'PCHH_WINPE'):
            assert str(uuid.UUID(bytes_le=entry[:16])) == basic_data
            assert attributes == 0, 'Partition hidden or not automounted'
            parts[name] = (start * 512, (end - start + 1) * 512)
    assert len(parts) == 2
    assert parts['PCHH_DATA'][1] == 512 * 1024 * 1024

    with tempfile.TemporaryDirectory() as temp:
        temp = Path(temp)
        for label, (offset, length) in parts.items():
            volume = temp / (label + '.fat')
            f.seek(offset)
            with volume.open('wb') as out:
                remaining = length
                while remaining:
                    chunk = f.read(min(4 * 1024 * 1024, remaining))
                    assert chunk
                    out.write(chunk)
                    remaining -= len(chunk)
            result = run('fsck.fat', '-n', str(volume))
            assert label in run('mlabel', '-i', str(volume), '-s', '::')
            print(label + ': FAT32 label and read-only filesystem check passed')
            if label == 'PCHH_DATA':
                for name in required:
                    target = temp / name
                    run('mcopy', '-i', str(volume),
                        '::/drivers/Intel-IRST_12-15G/' + name, str(target))
                    assert target.read_bytes() == (source / name).read_bytes(), name
            else:
                for name in ['pchh-gui.hta', 'startnet.cmd']:
                    target = temp / name
                    run('mcopy', '-i', str(volume), '::/' + name, str(target))
                    assert target.read_bytes() == Path('winpe/Windows/System32', name).read_bytes()
                wim = temp / 'boot.wim'
                run('mcopy', '-i', str(volume), '::/boot.wim', str(wim))
                print(run('wimlib-imagex', 'dir', str(wim), '1',
                          '--path=/Windows/System32/manage-bde.exe').strip())
                extracted = temp / 'extracted'
                for name in required:
                    run('wimlib-imagex', 'extract', str(wim), '1',
                        'PCHH/Drivers/Intel-IRST_12-15G/' + name,
                        '--dest-dir=' + str(extracted))
                    assert (extracted / name).read_bytes() == (source / name).read_bytes()
print('USB GPT, protective MBR, GUI/startup assets, complete VMD driver package and BitLocker verified')
print('Image SHA-256: ' + hashlib.file_digest(image.open('rb'), 'sha256').hexdigest())
