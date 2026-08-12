#!/usr/bin/env python3
"""dns-query.py — Minimal DNS A-record lookup using only the standard library.

Usage: python3 dns-query.py <name> [server] [port]
Example: python3 dns-query.py redis.service.consul 127.0.0.1 8600

Prints one IPv4 answer per line (like `dig +short`) and exits 0; exits 1 when
the name has no A record or the server is unreachable.
"""

import random
import socket
import struct
import sys


def build_query(name: str, qid: int) -> bytes:
    header = struct.pack(">HHHHHH", qid, 0x0100, 1, 0, 0, 0)
    labels = name.rstrip(".").split(".")
    question = b"".join(bytes([len(lbl)]) + lbl.encode() for lbl in labels) + b"\x00"
    # QTYPE=1 (A), QCLASS=1 (IN)
    return header + question + struct.pack(">HH", 1, 1)


def skip_name(data: bytes, offset: int) -> int:
    while True:
        length = data[offset]
        if length & 0xC0 == 0xC0:  # compression pointer
            return offset + 2
        if length == 0:
            return offset + 1
        offset += length + 1


def parse_response(data: bytes, qid: int) -> list:
    if len(data) < 12:
        raise RuntimeError("truncated DNS response")
    resp_id, _flags, qdcount, ancount, _ns, _ar = struct.unpack(">HHHHHH", data[:12])
    if resp_id != qid:
        raise RuntimeError("response id mismatch")
    offset = 12
    for _ in range(qdcount):
        offset = skip_name(data, offset) + 4  # skip QTYPE + QCLASS
    answers = []
    for _ in range(ancount):
        offset = skip_name(data, offset)
        rtype, rclass, _ttl, rdlen = struct.unpack(">HHIH", data[offset:offset + 10])
        offset += 10
        rdata = data[offset:offset + rdlen]
        offset += rdlen
        if rtype == 1 and rclass == 1 and rdlen == 4:  # A record
            answers.append(".".join(str(b) for b in rdata))
    return answers


def main() -> int:
    name = sys.argv[1] if len(sys.argv) > 1 else "redis.service.consul"
    server = sys.argv[2] if len(sys.argv) > 2 else "127.0.0.1"
    port = int(sys.argv[3]) if len(sys.argv) > 3 else 8600
    qid = random.randint(0, 0xFFFF)
    query = build_query(name, qid)
    for _attempt in range(3):
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.settimeout(2)
            sock.sendto(query, (server, port))
            data, _addr = sock.recvfrom(4096)
            answers = parse_response(data, qid)
            sock.close()
            if answers:
                for address in answers:
                    print(address)
                return 0
            sys.stderr.write("no A record for %s\n" % name)
            return 1
        except socket.timeout:
            sys.stderr.write("timeout, retrying...\n")
        except OSError as exc:
            sys.stderr.write("network error: %s\n" % exc)
        finally:
            try:
                sock.close()
            except NameError:
                pass
    return 1


if __name__ == "__main__":
    sys.exit(main())
