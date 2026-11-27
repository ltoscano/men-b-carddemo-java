#!/usr/bin/env python3
"""Iniezione di guasti per le prove negative di check.sh (mai attiva senza INV_FAULT). Uso: fault.py proc-byte DIR"""
import os
import sys

if sys.argv[1] == "proc-byte":
    p = os.path.join(sys.argv[2], sorted(os.listdir(sys.argv[2]))[0])
    b = bytearray(open(p, "rb").read())
    b[-1] ^= 0x01
    open(p, "wb").write(bytes(b))
else:
    sys.exit("guasto sconosciuto")
