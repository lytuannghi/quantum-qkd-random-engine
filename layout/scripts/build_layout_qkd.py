#!/usr/bin/env python3
"""
ASIC Physical Layout Generator (GDSII Stream Format)
Design: Quantum Key Distribution (QKD) Hardware Engine & NIST TRNG ASIC
Process: TSMC 28nm HPC+ CMOS
Dimensions: 1400 um x 1400 um
"""

import struct
import os

def create_gds_record(rec_type, data_type, data_bytes=b""):
    rec_length = len(data_bytes) + 4
    header = struct.pack(">HH", rec_length, (rec_type << 8) | data_type)
    return header + data_bytes

def create_boundary(layer, datatype, coords):
    res = bytearray()
    res += create_gds_record(0x08, 0x00) # BOUNDARY
    res += create_gds_record(0x0D, 0x02, struct.pack(">h", layer))
    res += create_gds_record(0x0E, 0x02, struct.pack(">h", datatype))
    coord_bytes = bytearray()
    for x, y in coords:
        coord_bytes += struct.pack(">ii", int(x), int(y))
    coord_bytes += struct.pack(">ii", int(coords[0][0]), int(coords[0][1]))
    res += create_gds_record(0x10, 0x03, coord_bytes) # XY
    res += create_gds_record(0x11, 0x00) # ENDEL
    return res

def create_box(layer, datatype, x1, y1, x2, y2):
    return create_boundary(layer, datatype, [(x1, y1), (x2, y1), (x2, y2), (x1, y2)])

def main():
    out_dir = os.path.join(os.path.dirname(__file__), "..", "gds")
    os.makedirs(out_dir, exist_ok=True)
    gds_path = os.path.join(out_dir, "quantum_qkd_top.gds")

    stream = bytearray()
    # HEADER
    stream += create_gds_record(0x00, 0x02, struct.pack(">h", 600))
    # BGNLIB
    stream += create_gds_record(0x01, 0x02, struct.pack(">12h", 2026, 11, 22, 12, 0, 0, 2026, 11, 22, 12, 0, 0))
    # LIBNAME
    lib_name = b"QUANTUM_QKD_LIB\0"
    if len(lib_name) % 2 != 0: lib_name += b"\0"
    stream += create_gds_record(0x02, 0x06, lib_name)
    # UNITS (0.001 um database unit = 1 nm)
    stream += create_gds_record(0x03, 0x05, struct.pack(">dd", 0.001, 1e-9))

    # BGNSTR
    stream += create_gds_record(0x05, 0x02, struct.pack(">12h", 2026, 11, 22, 12, 0, 0, 2026, 11, 22, 12, 0, 0))
    # STRNAME
    cell_name = b"quantum_qkd_top\0"
    if len(cell_name) % 2 != 0: cell_name += b"\0"
    stream += create_gds_record(0x06, 0x06, cell_name)

    # 1. Chip Sealring & Boundary: 1400um x 1400um
    stream += create_box(100, 0, 0, 0, 1400000, 1400000)
    stream += create_box(100, 1, 20000, 20000, 1380000, 1380000)

    # 2. IO Pad Ring (Outer perimeter: APD/SPAD detector interface pads, APB3 pads)
    for i in range(12):
        pos = 60000 + i * 110000
        stream += create_box(105, 0, pos, 25000, pos + 70000, 95000)      # Bottom Pads
        stream += create_box(105, 0, pos, 1305000, pos + 70000, 1375000) # Top Pads
        stream += create_box(105, 0, 25000, pos, 95000, pos + 70000)      # Left Pads
        stream += create_box(105, 0, 1305000, pos, 1375000, pos + 70000) # Right Pads

    # 3. Core Logic Floorplan Blocks
    # u_regs: APB3 Register Bank & Control
    stream += create_box(30, 0, 140000, 140000, 450000, 420000)
    # u_sifting: BB84 Sifting & QBER Calculator
    stream += create_box(31, 0, 490000, 140000, 880000, 450000)
    # u_trng_health: NIST SP 800-90B Health Monitor (RCT/APT)
    stream += create_box(32, 0, 920000, 140000, 1260000, 450000)
    # u_reconciler: Modified Cascade Information Reconciliation Engine
    stream += create_box(33, 0, 140000, 500000, 680000, 880000)
    # u_privacy: Universal Toeplitz Hashing Privacy Amplification Engine
    stream += create_box(34, 0, 720000, 500000, 1260000, 880000)
    # Sifted Key & Secret Key Storage RAM Macro
    stream += create_box(35, 0, 140000, 940000, 1260000, 1260000)

    # 4. Power Grid Network (VDD / VSS Straps in Metal 8 & Metal 9)
    for p in range(160000, 1250000, 80000):
        stream += create_box(48, 0, p, 120000, p + 12000, 1280000)      # M8 VDD/VSS Vertical Straps
        stream += create_box(49, 0, 120000, p, 1280000, p + 12000)      # M9 VDD/VSS Horizontal Straps

    # ENDSTR
    stream += create_gds_record(0x07, 0x00)
    # ENDLIB
    stream += create_gds_record(0x04, 0x00)

    with open(gds_path, "wb") as f:
        f.write(stream)

    print(f"[INFO] GDSII physical layout generated successfully: {gds_path} ({len(stream)} bytes)")

if __name__ == "__main__":
    main()
