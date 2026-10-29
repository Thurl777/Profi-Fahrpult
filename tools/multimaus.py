#!/usr/bin/env python3
"""
Ahmt einen Handregler (z.B. Roco Multimaus) nach: schickt einen Fahr- oder
Funktionsbefehl als eigener LAN-Client an die Z21 bzw. an tools/z21_simulator.py.
Damit lässt sich ohne echte Multimaus prüfen, ob die App einem Lokwechsel folgt.

Beispiele:
    python3 tools/multimaus.py 23 fahre 40          # Lok 23, Fahrstufe 40 vorwärts
    python3 tools/multimaus.py 23 fahre 40 rueck    # rückwärts
    python3 tools/multimaus.py 23 halt
    python3 tools/multimaus.py 23 f 0 an            # Licht an
    python3 tools/multimaus.py 23 f 1 aus
"""
import argparse
import socket
import struct


def packet(header, payload=b""):
    return struct.pack("<HH", 4 + len(payload), header) + bytes(payload)


def xbus(data):
    x = 0
    for b in data:
        x ^= b
    return packet(0x40, bytes(data) + bytes([x]))


def loco_addr_bytes(addr):
    msb = (addr >> 8) & 0x3F
    if addr >= 128:
        msb |= 0xC0
    return msb, addr & 0xFF


def drive(addr, step, forward):
    msb, lsb = loco_addr_bytes(addr)
    step = max(0, min(step, 126))
    speed = (0x80 if forward else 0) | (step + 1 if step else 0)
    return xbus([0xE4, 0x13, msb, lsb, speed])     # 128 Fahrstufen


def function(addr, fn, on):
    msb, lsb = loco_addr_bytes(addr)
    return xbus([0xE4, 0xF8, msb, lsb, (0x40 if on else 0x00) | (fn & 0x1F)])


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=21105)
    ap.add_argument("adresse", type=int)
    ap.add_argument("befehl", choices=["fahre", "halt", "f"])
    ap.add_argument("werte", nargs="*")
    args = ap.parse_args()

    if args.befehl == "fahre":
        if not args.werte:
            ap.error("fahre braucht eine Fahrstufe, z.B. fahre 40")
        forward = not (len(args.werte) > 1 and args.werte[1].startswith("r"))
        data = drive(args.adresse, int(args.werte[0]), forward)
    elif args.befehl == "halt":
        data = drive(args.adresse, 0, True)
    else:
        if len(args.werte) < 2 or args.werte[1] not in ("an", "aus"):
            ap.error("f braucht Nummer und an/aus, z.B. f 0 an")
        data = function(args.adresse, int(args.werte[0]), args.werte[1] == "an")

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.sendto(data, (args.host, args.port))
    sock.sendto(packet(0x30), (args.host, args.port))   # LAN_LOGOFF
    print("gesendet:", data.hex(" "))


if __name__ == "__main__":
    main()
