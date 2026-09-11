/-
SHA-256 em Lean 4 — sem dependências externas (FIPS 180-4).

Por que existe: o juiz precisa RECALCULAR o hash do texto do objeto e conferir
contra o endereço declarado. Sem isso, "endereçado por conteúdo" seria fé na
ferramenta que escreveu, não prova. Aqui o próprio juiz calcula.
-/

namespace Sha256

def K : Array UInt32 := #[
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2]

def H0 : Array UInt32 := #[
  0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]

/-- rotação à direita de 32 bits -/
def rotr (x : UInt32) (n : UInt32) : UInt32 := (x >>> n) ||| (x <<< (32 - n))

/-- palavra big-endian no deslocamento i -/
def getU32 (b : ByteArray) (i : Nat) : UInt32 :=
  ((b.get! i).toUInt32 <<< 24) ||| ((b.get! (i + 1)).toUInt32 <<< 16)
  ||| ((b.get! (i + 2)).toUInt32 <<< 8) ||| (b.get! (i + 3)).toUInt32

/-- preenchimento: 0x80, zeros até ≡56 mod 64, comprimento em 8 bytes BE -/
def pad (msg : ByteArray) : ByteArray := Id.run do
  let mut out := msg.push 0x80
  while out.size % 64 != 56 do
    out := out.push 0x00
  let bitLen : UInt64 := msg.size.toUInt64 * 8
  for i in List.range 8 do
    out := out.push ((bitLen >>> ((7 - i) * 8).toUInt64).toUInt8)
  return out

def compress (h : Array UInt32) (blk : ByteArray) (off : Nat) : Array UInt32 := Id.run do
  let mut w : Array UInt32 := Array.empty
  for i in List.range 16 do
    w := w.push (getU32 blk (off + i * 4))
  for i in List.range 48 do
    let t := i + 16
    let w15 := w[t - 15]!
    let w2  := w[t - 2]!
    let s0 := rotr w15 7 ^^^ rotr w15 18 ^^^ (w15 >>> 3)
    let s1 := rotr w2 17 ^^^ rotr w2 19 ^^^ (w2 >>> 10)
    w := w.push (w[t - 16]! + s1 + w[t - 7]! + s0)
  let mut a := h[0]!; let mut b := h[1]!; let mut c := h[2]!; let mut d := h[3]!
  let mut e := h[4]!; let mut f := h[5]!; let mut g := h[6]!; let mut hh := h[7]!
  for i in List.range 64 do
    let S1 := rotr e 6 ^^^ rotr e 11 ^^^ rotr e 25
    let ch := (e &&& f) ^^^ ((~~~ e) &&& g)
    let t1 := hh + S1 + ch + K[i]! + w[i]!
    let S0 := rotr a 2 ^^^ rotr a 13 ^^^ rotr a 22
    let maj := (a &&& b) ^^^ (a &&& c) ^^^ (b &&& c)
    let t2 := S0 + maj
    hh := g; g := f; f := e; e := d + t1
    d := c; c := b; b := a; a := t1 + t2
  return #[a + h[0]!, b + h[1]!, c + h[2]!, d + h[3]!, e + h[4]!, f + h[5]!, g + h[6]!, hh + h[7]!]

/-- SHA-256 sobre bytes. -/
def hash (msg : ByteArray) : ByteArray := Id.run do
  let padded := pad msg
  let mut h := H0
  for blk in List.range (padded.size / 64) do
    h := compress h padded (blk * 64)
  let mut out : ByteArray := ByteArray.empty
  for i in List.range 8 do
    let x := h[i]!
    out := out.push ((x >>> 24).toUInt8)
    out := out.push ((x >>> 16).toUInt8)
    out := out.push ((x >>> 8).toUInt8)
    out := out.push (x.toUInt8)
  return out

def hexDigit (n : UInt8) : Char :=
  let d := n.toNat
  if d < 10 then Char.ofNat (48 + d) else Char.ofNat (87 + d)

/-- bytes → string hexadecimal minúscula -/
def toHex (b : ByteArray) : String := Id.run do
  let mut s := ""
  for byte in b do
    s := s.push (hexDigit (byte >>> 4))
    s := s.push (hexDigit (byte &&& 0x0f))
  return s

/-- SHA-256 hexadecimal do texto (UTF-8). É o ENDEREÇO de um objeto. -/
def endereco (s : String) : String := toHex (hash s.toUTF8)

/- ============ TDD: vetores oficiais (FIPS 180-4) ============ -/
-- vazio
example : endereco "" = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" := by native_decide
-- "abc"
example : endereco "abc" = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" := by native_decide
-- mensagem de 56 bytes (força bloco extra no preenchimento)
example : endereco "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
    = "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1" := by native_decide

#eval endereco "abc"

end Sha256
