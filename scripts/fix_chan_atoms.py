#!/usr/bin/env python3
"""
fix_chan_atoms.py - Convert MOV chan atoms from UseChannelBitmap to UseChannelDescriptions.
Matches the format used by professional tools (DaVinci Resolve, Pro Tools, etc.)

Handles:
- UseChannelBitmap → UseChannelDescriptions (grows atom from 24 to 44 bytes)
- Mono layout tag (0x00640001) → UseChannelDescriptions label=3 (Center)
- MatrixStereo tag (0x00670002) → left as-is (already correct)

Must be run AFTER ffmpeg encoding. Fixes parent atom sizes. Assumes moov is after mdat.
"""
import struct
import sys

# CoreAudio channel bitmap bit → channel label mapping
BITMAP_TO_LABEL = {
    0x00000001: 1,   # Left
    0x00000002: 2,   # Right
    0x00000004: 3,   # Center
    0x00000008: 4,   # LFEScreen
    0x00000010: 5,   # LeftSurround
    0x00000020: 6,   # RightSurround
    0x00000040: 7,   # LeftCenter
    0x00000080: 8,   # RightCenter
    0x00000100: 9,   # CenterSurround
    0x00000200: 10,  # LeftSurroundDirect
    0x00000400: 11,  # RightSurroundDirect
}


def make_chan_desc(labels):
    """Create a UseChannelDescriptions chan atom with given labels."""
    ndesc = len(labels)
    size = 24 + ndesc * 20  # header(8) + ver(4) + tag(4) + bitmap(4) + ndesc(4) + descs
    parts = [struct.pack('>I4sIIII', size, b'chan', 0, 0, 0, ndesc)]
    for label in labels:
        parts.append(struct.pack('>IIfff', label, 0, 0.0, 0.0, 0.0))
    return b''.join(parts)


def find_chan_atoms(data):
    """Find all chan atoms in the file."""
    atoms = []
    offset = 0
    while True:
        pos = data.find(b'chan', offset)
        if pos == -1:
            break
        if pos >= 4:
            atom_start = pos - 4
            size = struct.unpack_from('>I', data, atom_start)[0]
            if 16 <= size <= 200:
                tag = struct.unpack_from('>I', data, pos + 8)[0]
                bitmap = struct.unpack_from('>I', data, pos + 12)[0]
                atoms.append({
                    'pos': atom_start,
                    'size': size,
                    'tag': tag,
                    'bitmap': bitmap,
                })
        offset = pos + 4
    return atoms


def find_ancestors(data, target_pos):
    """Find all ancestor atoms that contain target_pos."""
    ancestors = []

    def walk(start, end):
        offset = start
        while offset + 8 <= end:
            asize = struct.unpack_from('>I', data, offset)[0]
            atype = data[offset+4:offset+8]
            if asize < 8 or offset + asize > len(data):
                break
            atom_end = offset + asize
            if target_pos >= offset and target_pos < atom_end:
                if offset != target_pos:
                    ancestors.append(offset)
                # Determine header size for recursion
                header = 8
                if atype == b'stsd':
                    header = 16
                elif atype in [b'in24', b'sowt', b'lpcm', b'twos', b'raw ',
                               b'fl32', b'fl64', b'alaw', b'ulaw', b'NONE']:
                    header = 36
                walk(offset + header, atom_end)
                return
            offset += asize

    walk(0, len(data))
    return ancestors


def fix_chan_atoms(filepath):
    with open(filepath, 'rb') as f:
        data = bytearray(f.read())

    atoms = find_chan_atoms(data)
    if not atoms:
        print(f'  No chan atoms found')
        return False

    # Process from end to start (so earlier positions remain valid)
    atoms.sort(key=lambda x: x['pos'], reverse=True)

    changes = 0
    for atom in atoms:
        pos = atom['pos']
        old_size = atom['size']

        if atom['tag'] == 0x00010000:  # UseChannelBitmap
            label = BITMAP_TO_LABEL.get(atom['bitmap'])
            if label is None:
                print(f'  WARNING: Unknown bitmap 0x{atom["bitmap"]:08x} at {pos}')
                continue
            new_atom = make_chan_desc([label])
            growth = len(new_atom) - old_size

        elif atom['tag'] == 0x00640001:  # Mono
            new_atom = make_chan_desc([3])  # Center
            growth = len(new_atom) - old_size

        elif atom['tag'] == 0x00670002:  # MatrixStereo - already correct
            continue

        elif atom['tag'] == 0:  # Already UseChannelDescriptions
            continue

        else:
            print(f'  Skipping unknown tag 0x{atom["tag"]:08x} at {pos}')
            continue

        # Replace the atom
        data[pos:pos + old_size] = new_atom

        # Fix ancestor sizes
        ancestors = find_ancestors(data, pos)
        for anc_pos in ancestors:
            anc_size = struct.unpack_from('>I', data, anc_pos)[0]
            struct.pack_into('>I', data, anc_pos, anc_size + growth)

        changes += 1

    if changes > 0:
        with open(filepath, 'wb') as f:
            f.write(data)
        print(f'  Fixed {changes} chan atoms -> UseChannelDescriptions')
        return True
    else:
        print(f'  No changes needed')
        return False


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(f'Usage: {sys.argv[0]} <file.mov>')
        sys.exit(1)
    filepath = sys.argv[1]
    print(f'Processing: {filepath}')
    fix_chan_atoms(filepath)
