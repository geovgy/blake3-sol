#!/usr/bin/env python3
"""Independent validation of the Yul emitted in src/BLAKE3Lib.sol.

No generator code is imported. A small evaluator reads the checked-in Yul and
compares it to a conventional scalar compression and the blake3 Python package.
--smt additionally proves packed primitives, every G step, endian conversion,
compaction, dirty-tail loads, lane permutations, and all 28 message gathers
using 256-bit Z3 words.

Install optional dependencies in a venv:
  pip install blake3==1.0.11 z3-solver==5.3.3.0
Run:
  python scripts/verify_packed.py --smt --cases 1000
This checks source semantics, not solc/EVM correctness or Solidity memory safety.
"""
import argparse
import functools
from pathlib import Path
import random
import re
import time

U32 = (1 << 32) - 1
U256 = (1 << 256) - 1
LANE_MASK = sum(U32 << i for i in (0, 64, 128, 192))
IV = [0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
      0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19]
# Explicit schedules independent of scripts/generate.py's permutation recurrence.
SCHEDULE = [
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
    [2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8],
    [3, 4, 10, 12, 13, 2, 7, 14, 6, 5, 9, 0, 11, 15, 8, 1],
    [10, 7, 12, 9, 14, 3, 13, 15, 4, 0, 11, 2, 5, 8, 1, 6],
    [12, 13, 9, 11, 15, 10, 14, 8, 7, 2, 5, 3, 0, 1, 6, 4],
    [9, 14, 11, 5, 8, 12, 15, 1, 13, 3, 0, 10, 2, 6, 4, 7],
    [11, 15, 5, 0, 1, 9, 8, 6, 14, 10, 2, 12, 3, 4, 7, 13],
]


class Parser:
    def __init__(self, source):
        source = re.sub(r'//[^\n]*|/\*.*?\*/', '', source, flags=re.S)
        self.tokens = re.findall(r'0x[0-9a-fA-F]+|\d+|[A-Za-z_][A-Za-z_0-9]*|:=|->|[{}(),]', source)
        assert ''.join(self.tokens) == re.sub(r'\s+', '', source), 'unsupported Yul syntax'
        self.i = 0
        self.functions = {}

    def peek(self):
        return self.tokens[self.i]

    def take(self, expected=None):
        t = self.peek()
        if expected is not None:
            assert t == expected, (t, expected, self.tokens[max(0, self.i-5):self.i+5])
        self.i += 1
        return t

    def names(self, end):
        names = []
        if self.peek() != end:
            names.append(self.take())
            while self.peek() == ',':
                self.take(',')
                names.append(self.take())
        return names

    def expr(self):
        t = self.take()
        if t.startswith('0x') or t.isdigit():
            return int(t, 0) if t.startswith('0x') else int(t)
        if self.peek() != '(':
            return t
        self.take('(')
        args = []
        if self.peek() != ')':
            args.append(self.expr())
            while self.peek() == ',':
                self.take(',')
                args.append(self.expr())
        self.take(')')
        return (t, args)

    def block(self):
        self.take('{')
        stmts = []
        while self.peek() != '}':
            t = self.peek()
            if t == '{':
                stmts.append(('block', self.block()))
            elif t == 'function':
                self.take()
                name = self.take()
                self.take('(')
                args = self.names(')')
                self.take(')')
                returns = []
                if self.peek() == '->':
                    self.take()
                    returns = self.names('{')
                self.functions[name] = (args, returns, self.block())
            elif t == 'for':
                self.take()
                init = self.block()
                cond = self.expr()
                post = self.block()
                stmts.append(('for', init, cond, post, self.block()))
            elif t == 'if':
                self.take()
                stmts.append(('if', self.expr(), self.block()))
            elif t == 'switch':
                self.take()
                expr = self.expr()
                cases, default = [], []
                while self.peek() in ('case', 'default'):
                    case = self.take()
                    if case == 'default':
                        default = self.block()
                    else:
                        value = self.expr()
                        cases.append((value, self.block()))
                stmts.append(('switch', expr, cases, default))
            elif t == 'let':
                self.take()
                names = self.names(':=')
                value = 0
                if self.peek() == ':=':
                    self.take()
                    value = self.expr()
                stmts.append(('set', names, value))
            elif self.tokens[self.i + 1] in (':=', ','):
                names = self.names(':=')
                self.take(':=')
                stmts.append(('set', names, self.expr()))
            else:
                stmts.append(('expr', self.expr()))
        self.take('}')
        return stmts


def pack(words):
    return functools.reduce(lambda a, iw: a | (iw[1] << (192-64*iw[0])), enumerate(words), 0)


def words256(words):
    return functools.reduce(lambda a, w: (a << 32) | w, words, 0)


class Evaluator:
    def __init__(self, parser):
        self.functions = parser.functions
        self.memory = {}

    def call(self, name, args):
        params, returns, body = self.functions[name]
        assert len(params) == len(args)
        env = dict(zip(params, args))
        env.update(dict.fromkeys(returns, 0))
        self.run(body, env)
        result = tuple(env[k] for k in returns)
        return result[0] if len(result) == 1 else result

    def expr(self, expr, env):
        if isinstance(expr, int):
            return expr
        if isinstance(expr, str):
            return env[expr]
        name, expressions = expr
        args = [self.expr(e, env) for e in expressions]
        if name in self.functions:
            return self.call(name, args)
        if name == 'mload':
            return int.from_bytes(bytes(self.memory.get(args[0]+i, 0) for i in range(32)), 'big')
        if name == 'mstore':
            self.memory.update({args[0]+i: b for i, b in enumerate(args[1].to_bytes(32, 'big'))})
            return 0
        if name == 'add':
            result = args[0] + args[1]
        elif name == 'sub':
            result = args[0] - args[1]
        elif name == 'mul':
            result = args[0] * args[1]
        elif name == 'and':
            result = args[0] & args[1]
        elif name == 'or':
            result = args[0] | args[1]
        elif name == 'xor':
            result = args[0] ^ args[1]
        elif name == 'not':
            result = ~args[0]
        elif name == 'shl':
            result = args[1] << args[0]
        elif name == 'shr':
            result = args[1] >> args[0] if isinstance(args[1], int) else z3.LShR(args[1], args[0])
        elif name in ('lt', 'gt', 'eq', 'iszero'):
            assert all(isinstance(x, int) for x in args), 'symbolic branches are unsupported'
            if name == 'lt':
                result = int(args[0] < args[1])
            elif name == 'gt':
                result = int(args[0] > args[1])
            elif name == 'eq':
                result = int(args[0] == args[1])
            else:
                result = int(args[0] == 0)
        else:
            raise AssertionError(name)
        return result & U256 if isinstance(result, int) else result

    def run(self, body, env):
        for stmt in body:
            kind = stmt[0]
            if kind == 'set':
                _, names, expr = stmt
                values = self.expr(expr, env)
                values = values if isinstance(values, tuple) else (values,)
                assert len(names) == len(values), stmt
                env.update(zip(names, values))
            elif kind == 'expr':
                self.expr(stmt[1], env)
            elif kind == 'block':
                self.run(stmt[1], env)
            elif kind == 'if':
                if self.expr(stmt[1], env):
                    self.run(stmt[2], env)
            elif kind == 'for':
                _, init, cond, post, loop = stmt
                self.run(init, env)
                while self.expr(cond, env):
                    self.run(loop, env)
                    self.run(post, env)
            elif kind == 'switch':
                _, expr, cases, default = stmt
                value = self.expr(expr, env)
                self.run(next((body for val, body in cases if self.expr(val, env) == value), default), env)
            else:
                raise AssertionError(kind)


def rotr(x, n):
    return ((x >> n) | (x << (32-n))) & U32


def scalar_g(a, b, c, d, x, y):
    a = (a + b + x) & U32
    d = rotr(d ^ a, 16)
    c = (c + d) & U32
    b = rotr(b ^ c, 12)
    a = (a + b + y) & U32
    d = rotr(d ^ a, 8)
    c = (c + d) & U32
    b = rotr(b ^ c, 7)
    return a, b, c, d


def scalar_compress(message, cv, counter, size, flags):
    v = list(cv) + IV[:4] + [counter & U32, counter >> 32, size, flags]
    for schedule in SCHEDULE:
        for group in range(8):
            indices = (group, group+4, group+8, group+12) if group < 4 else (
                group-4, 4+(group-3) % 4, 8+(group-2) % 4, 12+(group-1) % 4)
            a, b, c, d = indices
            v[a], v[b], v[c], v[d] = scalar_g(
                v[a], v[b], v[c], v[d], message[schedule[2*group]], message[schedule[2*group+1]])
    return [v[i] ^ v[i+8] for i in range(8)]


def concrete_checks(ev, main, empty_hash, cases, seed):
    from blake3 import blake3
    rng = random.Random(seed)
    # Artificial compression exposes both counter halves without 2**32 chunks.
    counters = [0, 1, U32-1, U32, U32+1, (1 << 63), (1 << 64)-1]
    for i in range(cases):
        message = [rng.getrandbits(32) for _ in range(16)]
        cv = [rng.getrandbits(32) for _ in range(8)]
        counter = counters[i % len(counters)] if i < len(counters)*20 else rng.getrandbits(64)
        size, flags = rng.randrange(65), rng.randrange(128)
        actual = ev.call('compress', [words256(message[:8]), words256(message[8:]),
                                      pack(cv[:4]), pack(cv[4:]), pack([counter & U32, counter >> 32, size, flags])])
        expected = scalar_compress(message, cv, counter, size, flags)
        assert actual == (pack(expected[:4]), pack(expected[4:])), ('compression', i, counter)
    print(f'PASS {cases} scalar compression comparisons with arbitrary CV/message/flags and full 64-bit counters', flush=True)
    # Check chunk's own counter packing and all possible final-block sizes.
    for counter in counters + [rng.getrandbits(64) for _ in range(9)]:
        for size in list(range(65)) + [65, 127, 128, 129, 960, 1023, 1024]:
            data = rng.randbytes(size)
            ev.memory = {0x100+i: b for i, b in enumerate(data)}
            actual = ev.call('chunk', [0x100, size, counter, 8 if size % 2 else 0])
            cv = IV[:]
            blocks = [data[j:j+64] for j in range(0, len(data), 64)] or [b'']
            for j, block in enumerate(blocks):
                message = [int.from_bytes(block[k:k+4].ljust(4, b'\0'), 'little') for k in range(0, 64, 4)]
                flags = (1 if j == 0 else 0) | ((2 | (8 if size % 2 else 0)) if j == len(blocks)-1 else 0)
                cv = scalar_compress(message, cv, counter, len(block), flags)
            assert actual == (pack(cv[:4]), pack(cv[4:])), ('chunk', size, counter)
    print('PASS 1152 scalar chunk comparisons, including every 0..64 tail and counter carries', flush=True)
    lengths = set(range(258))
    for chunks in [1, 2, 3, 4, 5, 6, 7, 8, 15, 16, 17, 31, 32, 33, 63, 64, 65]:
        lengths.update(chunks*1024 + d for d in [-65, -64, -63, -1, 0, 1, 63, 64, 65])
    lengths.update(rng.randrange(0, 65537) for _ in range(max(20, cases // 10)))
    checks = 0
    for size in sorted(lengths):
        for pattern in range(3 if size < 258 else 1):
            data = rng.randbytes(size) if pattern == 0 else bytes([0 if pattern == 1 else 255])*size
            ev.memory = {0x100+i: b for i, b in enumerate(data + b'\xff'*64)}
            # Scratch must start beyond allocations, like Solidity's free memory.
            scratch = ((0x100+len(data)+127)//32)*32
            ev.expr(('mstore', [0x40, scratch]), {})
            env = {'p': 0x100, 'n': size, 'result': 0}
            if size:
                ev.run(main, env)
                digest = env['result'].to_bytes(32, 'big')
            else:
                digest = empty_hash.to_bytes(32, 'big')
            assert digest == blake3(data).digest(), ('hash', size, pattern, digest.hex())
            checks += 1
    print(f'PASS {checks} checked-in Yul full-hash comparisons with blake3 1.0.11; lengths 0..{max(lengths)} bytes', flush=True)


def smt_checks(ev):
    global z3
    import z3
    proved = 0

    def prove(label, actual, expected):
        nonlocal proved
        solver = z3.Solver()
        solver.set(timeout=60000)
        solver.add(actual != expected)
        result = solver.check()
        assert result == z3.unsat, (label, result, solver.model() if result == z3.sat else solver.reason_unknown())
        proved += 1

    def unpack(value):
        return [z3.Extract(192-64*i+31, 192-64*i, value) for i in range(4)]

    symbolic = [z3.BitVec(f'p{i}', 32) for i in range(24)]
    registers = [pack([z3.ZeroExt(224, x) for x in symbolic[i:i+4]]) for i in range(0, 24, 4)]
    a, b, c, d, x, y = registers
    prove('sum2', (a+b) & LANE_MASK,
          pack([z3.ZeroExt(224, u+v) for u, v in zip(unpack(a), unpack(b))]))
    prove('sum3', (a+b+x) & LANE_MASK,
          pack([z3.ZeroExt(224, u+v+w) for u, v, w in zip(unpack(a), unpack(b), unpack(x))]))
    for rotation in (7, 8, 12, 16):
        actual = z3.LShR(a * 0x100000001, rotation) & LANE_MASK
        expected = pack([z3.ZeroExt(224, z3.RotateRight(w, rotation)) for w in unpack(a)])
        prove(f'rotate{rotation}', actual, expected)
    # Prove every emitted G state transition under the packed-lane invariant.
    # Each proof quantifies over fresh arbitrary packed inputs, so composing
    # these transitions proves G while avoiding a monolithic cryptographic miter.
    env = dict(zip(['a', 'b', 'c', 'd', 'x', 'y'], registers))
    env['mask'] = LANE_MASK
    assert ev.functions['g'][:2] == (['d', 'c', 'b', 'a', 'y', 'x'], ['dd', 'cc', 'bb', 'aa'])
    g_body = ev.functions['g'][2]
    assert g_body[0][0] == 'block'
    steps = g_body[0][1]
    assert steps[0] == ('set', ['mask'], LANE_MASK)
    descriptions = [
        ('a', lambda a,b,c,d,x,y: a+b+x),
        ('d', lambda a,b,c,d,x,y: d ^ a),
        ('d', lambda a,b,c,d,x,y: z3.RotateRight(d, 16)),
        ('c', lambda a,b,c,d,x,y: c+d),
        ('b', lambda a,b,c,d,x,y: b ^ c),
        ('b', lambda a,b,c,d,x,y: z3.RotateRight(b, 12)),
        ('a', lambda a,b,c,d,x,y: a+b+y),
        ('d', lambda a,b,c,d,x,y: d ^ a),
        ('d', lambda a,b,c,d,x,y: z3.RotateRight(d, 8)),
        ('c', lambda a,b,c,d,x,y: c+d),
        ('b', lambda a,b,c,d,x,y: b ^ c),
        ('b', lambda a,b,c,d,x,y: z3.RotateRight(b, 7)),
    ]
    assert len(steps) == 13
    for i, (stmt, (target, scalar)) in enumerate(zip(steps[1:], descriptions)):
        assert stmt[:2] == ('set', [target])
        expected = pack([z3.ZeroExt(224, scalar(*lane)) for lane in zip(*(unpack(v) for v in registers))])
        prove(f'G transition{i}', ev.expr(stmt[2], env), expected)
    assert g_body[1:] == [('set', [ret], var) for ret, var in [('aa','a'), ('bb','b'), ('cc','c'), ('dd','d')]]
    raw = z3.BitVec('raw', 256)
    swapped = functools.reduce(lambda acc, i: acc | (z3.ZeroExt(248, z3.Extract(8*i+7, 8*i, raw)) << (8*((i//4)*4+3-i%4))), range(32), 0)
    prove('wordEndian', ev.call('wordEndian', [raw]), swapped)
    prove('compact', ev.call('compact', [a]),
          functools.reduce(lambda acc, w: (acc << 32) | z3.ZeroExt(224, w), unpack(a), 0))
    # Quantify over arbitrary dirty data beyond every logical block length.
    class SymbolicLoadEvaluator(Evaluator):
        def expr(self, expr, env):
            if isinstance(expr, tuple) and expr[0] == 'mload':
                address = self.expr(expr[1][0], env)
                self.loads.append(address)
                assert address in (0x100, 0x120)
                return self.raw[(address-0x100)//32]
            return super().expr(expr, env)

    loader = SymbolicLoadEvaluator(ev)
    loader.raw = [z3.BitVec('dirtyLo', 256), z3.BitVec('dirtyHi', 256)]
    for size in range(65):
        loader.loads = []
        loaded = loader.call('loadBlock', [0x100, size])
        assert loader.loads == ([0x100] if size else []) + ([0x120] if size > 32 else [])
        for half in range(2):
            valid = min(32, max(0, size-32*half))
            expected = z3.BitVecVal(0, 256)
            for output_byte in range(32):
                source_byte = 4*(output_byte//4) + 3-output_byte % 4
                if source_byte < valid:
                    bit = 248-8*source_byte
                    expected |= z3.ZeroExt(248, z3.Extract(bit+7, bit, loader.raw[half])) << (248-8*output_byte)
            prove(f'loadBlock size{size} half{half}', loaded[half], expected)
    message = [z3.BitVec(f'm{i}', 32) for i in range(16)]
    env = {'m0': words256([z3.ZeroExt(224, v) for v in message[:8]]),
           'm1': words256([z3.ZeroExt(224, v) for v in message[8:]])}
    assert ev.functions['compress'][:2] == (['m0', 'm1', 'a', 'b', 'd'], ['oa', 'ob'])
    body = ev.functions['compress'][2]
    assert len(body) == 59
    assert body[0] == ('set', ['c'], pack(IV[:4]))
    assert body[-2:] == [('set', ['oa'], ('xor', ['a','c'])), ('set', ['ob'], ('xor', ['b','d']))]
    # The exact sequence matters to the compositional compression proof.
    for r in range(7):
        for half in range(2):
            offset = 1 + 8*r + 4*half
            stmt = body[offset]
            assert stmt[:2] == ('set', ['d','c','b','a'])
            assert stmt[2][0] == 'g' and stmt[2][1][:4] == ['d','c','b','a']
            assert [s[1] for s in body[offset+1:offset+4]] == [['b'], ['c'], ['d']]
    calls = [stmt[2] for stmt in body if stmt[0] == 'set' and isinstance(stmt[2], tuple) and stmt[2][0] == 'g']
    assert len(calls) == 14
    for round_index in range(7):
        for half in range(2):
            _, args = calls[2*round_index+half]
            for parity, arg in [(0, args[5]), (1, args[4])]:
                wanted = SCHEDULE[round_index][8*half+parity:8*half+8:2]
                prove(f'gather round{round_index} half{half} parity{parity}', ev.expr(arg, env),
                      pack([z3.ZeroExt(224, message[i]) for i in wanted]))
    # Prove emitted diagonal/undo shifts preserve all four packed lane values.
    permutations = [stmt for stmt in body if stmt[0] == 'set' and stmt[1] in [['b'], ['c'], ['d']] and isinstance(stmt[2], tuple) and stmt[2][0] == 'or']
    assert len(permutations) == 42
    expected_shifts = [(1, 'b'), (2, 'c'), (3, 'd'), (3, 'b'), (2, 'c'), (1, 'd')]
    for i, stmt in enumerate(permutations):
        shift, register = expected_shifts[i % 6]
        values = unpack(a)
        expected = pack([z3.ZeroExt(224, v) for v in values[shift:]+values[:shift]])
        prove(f'permutation{i}', ev.expr(stmt[2], {register: a}), expected)
    print(f'PASS {proved} Z3 UNSAT equivalence proofs plus exact round/control-flow assertions (all values; no solver timeouts)', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--smt', action='store_true')
    parser.add_argument('--cases', type=int, default=1000)
    parser.add_argument('--smt-only', action='store_true', help='prove packed arithmetic without concrete fuzzing')
    parser.add_argument('--seed', type=int, default=0xB1A3E3)
    args = parser.parse_args()
    source = (Path(__file__).resolve().parents[1] / 'src/BLAKE3Lib.sol').read_text()
    assembly = source[source.index('assembly ("memory-safe")', source.index('function _hash')):]
    assembly = assembly[assembly.index('{'):]
    parsed = Parser(assembly)
    main_body = parsed.block()
    assert parsed.i == len(parsed.tokens)-2, parsed.tokens[parsed.i:]
    ev = Evaluator(parsed)
    started = time.monotonic()
    if args.smt or args.smt_only:
        smt_checks(ev)
    if args.smt_only:
        print(f'Complete in {time.monotonic()-started:.1f}s', flush=True)
        return
    empty_hash = int(re.search(r'if \(n == 0\) return (0x[0-9a-f]+);', source)[1], 16)
    concrete_checks(ev, main_body, empty_hash, args.cases, args.seed)
    print(f'Complete in {time.monotonic()-started:.1f}s; seed={args.seed}', flush=True)


if __name__ == '__main__':
    main()
