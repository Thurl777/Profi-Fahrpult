#!/usr/bin/env python3
"""
Einfacher Z21-Simulator zum Testen der App ohne echte Zentrale.

Start:   python3 tools/z21_simulator.py [--port 21105]
In der App unter System als IP die Adresse des Rechners eintragen
(beim iPad-Simulator auf demselben Mac: 127.0.0.1).

Unterstützt: Gleisspannung, Nothalt, Lok fahren/Funktionen (Broadcast an alle
Clients), Weichen, CV lesen/schreiben (Programmiergleis + POM), Systemzustand,
R-Bus-Rückmelder (Kontakte wechseln zufällig).
"""
import argparse
import random
import socket
import struct
import time

HW_TYPE = 0x201          # Z21 (schwarz)
FIRMWARE = 0x0143        # 1.43 (BCD)
SERIAL = 123456


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


class Loco:
    def __init__(self, addr):
        self.addr = addr
        self.steps_code = 4      # 128 FS
        self.speed_byte = 0x80   # vorwärts, Halt
        self.functions = 0

    def info(self):
        msb, lsb = loco_addr_bytes(self.addr)
        f = self.functions
        db4 = ((f & 1) << 4) | ((f >> 1) & 0x0F)
        return xbus([0xEF, msb, lsb, self.steps_code, self.speed_byte, db4,
                     (f >> 5) & 0xFF, (f >> 13) & 0xFF, (f >> 21) & 0xFF, (f >> 29) & 0x07])


class Simulator:
    def __init__(self, port):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind(("0.0.0.0", port))
        self.sock.settimeout(0.5)
        self.clients = {}           # addr -> {"flags": int, "locos": [..], "seen": t}
        self.locos = {}
        self.turnouts = {}
        self.cvs = {1: 3, 7: 42, 8: 151, 29: 6}
        self.power = True
        self.estop = False
        self.prog_mode = False
        self.feedback = bytearray(20)
        self.last_feedback_change = time.time()

    def loco(self, addr):
        if addr not in self.locos:
            self.locos[addr] = Loco(addr)
        return self.locos[addr]

    def send(self, client, data):
        self.sock.sendto(data, client)

    def broadcast(self, data, flag=0x1, loco=None):
        for c, st in list(self.clients.items()):
            if loco is not None and loco not in st["locos"]:
                continue
            if st["flags"] & flag or flag == 0:
                self.send(c, data)

    def central_state(self):
        s = 0
        if self.estop:
            s |= 0x01
        if not self.power:
            s |= 0x02
        if self.prog_mode:
            s |= 0x20
        return s

    def system_state(self):
        current = 0 if not self.power else 150 + sum(
            (l.speed_byte & 0x7F) * 8 for l in self.locos.values())
        return packet(0x84, struct.pack("<hhhhHHBBBB", current, 0, current, 31,
                                        18500, 17800, self.central_state(), 0, 0, 0))

    def power_msg(self):
        if self.prog_mode:
            return xbus([0x61, 0x02])
        return xbus([0x61, 0x01 if self.power else 0x00])

    def handle(self, data, client):
        st = self.clients.setdefault(client, {"flags": 0, "locos": [], "seen": 0})
        st["seen"] = time.time()
        while len(data) >= 4:
            length, header = struct.unpack_from("<HH", data)
            if length < 4 or length > len(data):
                break
            payload = data[4:length]
            data = data[length:]
            self.handle_packet(header, payload, client, st)

    def handle_packet(self, header, p, client, st):
        if header == 0x10:
            self.send(client, packet(0x10, struct.pack("<I", SERIAL)))
        elif header == 0x1A:
            self.send(client, packet(0x1A, struct.pack("<II", HW_TYPE, FIRMWARE)))
        elif header == 0x18:
            self.send(client, packet(0x18, b"\x00"))
        elif header == 0x30:
            self.clients.pop(client, None)
            print("Client abgemeldet:", client)
        elif header == 0x50:
            st["flags"] = struct.unpack("<I", p[:4])[0]
            print("Client %s Broadcast-Flags 0x%08X" % (client, st["flags"]))
        elif header == 0x51:
            self.send(client, packet(0x51, struct.pack("<I", st["flags"])))
        elif header == 0x85:
            self.send(client, self.system_state())
        elif header == 0x81:
            group = p[0] if p else 0
            self.send(client, packet(0x80, bytes([group]) + bytes(self.feedback[group * 10:group * 10 + 10])))
        elif header == 0x40:
            self.handle_xbus(p, client, st)

    def handle_xbus(self, p, client, st):
        x = 0
        for b in p:
            x ^= b
        if x != 0:
            print("XOR-Fehler:", p.hex())
            return
        d = p[:-1]
        if d[:2] == b"\x21\x21":
            self.send(client, xbus([0x63, 0x21, 0x30, 0x12]))
        elif d[:2] == b"\x21\x24":
            self.send(client, xbus([0x62, 0x22, self.central_state()]))
        elif d[:2] == b"\xF1\x0A":
            self.send(client, xbus([0xF3, 0x0A, 0x01, 0x43]))
        elif d[:2] == b"\x21\x80":
            self.power, self.estop, self.prog_mode = False, False, False
            print("Gleisspannung AUS")
            self.broadcast(self.power_msg())
        elif d[:2] == b"\x21\x81":
            self.power, self.estop, self.prog_mode = True, False, False
            print("Gleisspannung EIN")
            self.broadcast(self.power_msg())
        elif d[:1] == b"\x80":
            self.estop = True
            for l in self.locos.values():
                l.speed_byte &= 0x80
            print("NOTHALT")
            self.broadcast(xbus([0x81, 0x00]))
        elif d[:2] == b"\xE3\xF0":
            addr = ((d[2] & 0x3F) << 8) | d[3]
            if addr not in st["locos"]:
                st["locos"] = (st["locos"] + [addr])[-16:]
            self.send(client, self.loco(addr).info())
        elif d[:1] == b"\xE4" and d[1] in (0x10, 0x12, 0x13):
            addr = ((d[2] & 0x3F) << 8) | d[3]
            l = self.loco(addr)
            l.steps_code = {0x10: 0, 0x12: 2, 0x13: 4}[d[1]]
            l.speed_byte = d[4]
            self.estop = False
            print("Lok %d: FS-Code %d, Byte 0x%02X" % (addr, l.steps_code, l.speed_byte))
            self.broadcast(l.info(), loco=addr)
            if addr not in st["locos"]:
                self.send(client, l.info())
        elif d[:2] == b"\xE4\xF8":
            addr = ((d[2] & 0x3F) << 8) | d[3]
            l = self.loco(addr)
            fn = d[4] & 0x3F
            action = d[4] >> 6
            mask = 1 << fn
            if action == 0:
                l.functions &= ~mask
            elif action == 1:
                l.functions |= mask
            else:
                l.functions ^= mask
            print("Lok %d: F%d %s" % (addr, fn, "an" if l.functions & mask else "aus"))
            self.broadcast(l.info(), loco=addr)
            if addr not in st["locos"]:
                self.send(client, l.info())
        elif d[:1] == b"\x92":
            addr = ((d[1] & 0x3F) << 8) | d[2]
            l = self.loco(addr)
            l.speed_byte = (l.speed_byte & 0x80) | 0x01
            self.broadcast(l.info(), loco=addr)
        elif d[:1] == b"\x53":
            fadr = (d[1] << 8) | d[2]
            if d[3] & 0x08:
                pos = 2 if d[3] & 0x01 else 1
                self.turnouts[fadr] = pos
                print("Weiche %d -> Ausgang %d" % (fadr + 1, pos))
                self.broadcast(xbus([0x43, d[1], d[2], pos]))
        elif d[:1] == b"\x43":
            fadr = (d[1] << 8) | d[2]
            self.send(client, xbus([0x43, d[1], d[2], self.turnouts.get(fadr, 0)]))
        elif d[:2] == b"\x23\x11":
            cv = ((d[2] << 8) | d[3]) + 1
            self.prog_mode = True
            self.broadcast(xbus([0x61, 0x02]))
            time.sleep(0.3)
            if cv in self.cvs:
                print("CV%d lesen = %d" % (cv, self.cvs[cv]))
                self.send(client, xbus([0x64, 0x14, d[2], d[3], self.cvs[cv]]))
            else:
                print("CV%d lesen -> NACK" % cv)
                self.send(client, xbus([0x61, 0x13]))
        elif d[:2] == b"\x24\x12":
            cv = ((d[2] << 8) | d[3]) + 1
            self.prog_mode = True
            self.broadcast(xbus([0x61, 0x02]))
            self.cvs[cv] = d[4]
            print("CV%d schreiben = %d" % (cv, d[4]))
            time.sleep(0.3)
            self.send(client, xbus([0x64, 0x14, d[2], d[3], d[4]]))
        elif d[:2] == b"\xE6\x30":
            addr = ((d[2] & 0x3F) << 8) | d[3]
            cv = (((d[4] & 0x03) << 8) | d[5]) + 1
            if d[4] & 0xFC == 0xEC:
                print("POM Lok %d: CV%d = %d" % (addr, cv, d[6]))
                self.cvs[cv] = d[6]
            elif d[4] & 0xFC == 0xE4:
                val = self.cvs.get(cv, 0)
                self.send(client, xbus([0x64, 0x14, d[4] & 0x03, d[5], val]))
        else:
            self.send(client, xbus([0x61, 0x82]))

    def run(self):
        print("Z21-Simulator läuft auf UDP-Port %d" % self.sock.getsockname()[1])
        next_state = time.time()
        while True:
            try:
                data, client = self.sock.recvfrom(1500)
                self.handle(data, client)
            except socket.timeout:
                pass
            now = time.time()
            # Clients, die sich 60 s nicht gemeldet haben, entfernen (wie die echte Z21)
            for c, st in list(self.clients.items()):
                if now - st["seen"] > 60:
                    self.clients.pop(c)
                    print("Client Timeout:", c)
            if now >= next_state:
                next_state = now + 1
                self.broadcast(self.system_state(), flag=0x100)
            if now - self.last_feedback_change > 3:
                self.last_feedback_change = now
                module = random.randrange(4)
                self.feedback[module] ^= 1 << random.randrange(8)
                self.broadcast(packet(0x80, bytes([0]) + bytes(self.feedback[0:10])), flag=0x2)


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, default=21105)
    args = ap.parse_args()
    Simulator(args.port).run()
