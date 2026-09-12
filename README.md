<!-- doc: tipo=capa autoridade=pitch -->

# Il — Individuação Livre

**Il** (*free individuation*) is a project to become oneself through **libre technology** — built so that no empire, platform or gatekeeper holds the keys to your culture, memory or tools.

Its first fruit is **Bolha**, a deterministic file format that groups and references media (texts, images, videos, audio) while carrying the **use-license of each component**.

## Why it matters

Most formats treat license as metadata — a tag you may ignore. Bolha makes license **structural**: you cannot reference a component without declaring what may be done with it, and the same machinery scales from content to programs and services.

- **A license is itself a bolha** — or the state `reservado` (deliberately no rights granted). A license bolha points to a **real catalog** — Creative Commons for content, SPDX for programs — so the system never invents legal terms, and there is no prose document to drift from the truth.
- **Content-addressed, always** — every reference is a sha256. A bolha is the deterministic manifesto of its parts; the render is a byproduct.
- **Hand and judge** — the harness (`arreio.py`) writes the manifesto; a **Lean 4** judge proves the *form*; a person confirms the *truth*.

## The form lives in the judge (see `juiz/`)

The specification is executable, not prose:

- `juiz/Bolha.lean` — the abstract valid bolha: content addressed by hash, license always explicit.
- `juiz/Ponte.lean` — the bridge: checks real manifestos against a collection of bolhas.

## Repository layout

- `juiz/` — the Lean 4 specification (abstract + bridge to real manifestos).
- `arreio.py` — the harness: creates a license bolha from a real catalog, imports content by hash,
  and carries the **music flow** — a lyric file in, numbered `parte` bolhas and the `musica` bolha out.
- `.github/workflows/verificar.yml` — CI runs the harness (the music flow) and the judge.


## Status

Early prototype. The judge is verified locally (exit 0) with Lean 4.33.1 and in CI.

## The two repositories

- **Il** (this one) — public trunk: the product. Code is developed here first.
- **IltS** — private workshop (a fork): the diary, the plan, and personal content. It pulls from here and never pushes back.

## License

AGPL-3.0 — see `LICENSE`.
