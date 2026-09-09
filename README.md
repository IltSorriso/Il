# Il — Individuação Livre

**Il** (*free individuation*) is a project to become oneself through **libre technology** — built so that no empire, platform or gatekeeper holds the keys to your culture, memory or tools.

Its first fruit is **Bolha**, a deterministic file format that groups and references media (texts, images, videos, audio) while carrying the **use-license of each component**.

## Why it matters

Most formats treat license as metadata — a tag you may ignore. Bolha makes license **structural**: you cannot reference a component without declaring what may be done with it, and the same machinery scales from content to programs and services.

- **Licenses as bolhas** — a license is itself a bolha (manifesto + hash), referenced by hash. One grammar for content, code and service.
- **Recipe, not dish** — a bolha is the deterministic manifesto of its parts and pipeline. Content is content-addressed (sha256), immutable, stored apart; the render is a byproduct.
- **Ceiling (*teto*)** — each license declares the ceiling of its references: freeze at an exact version (`hash`) or follow history (`ref`). The license is the temporal guardian of reproducibility.
- **Hand and judge** — the harness writes the manifesto; a **Lean 4** judge proves the *form*; a person confirms the *truth*.

## Repository layout

- `juiz/Bolha.lean` — Lean 4 specification of the *valid bolha*: license ceilings, the three founding licenses, two proven theorems.
- `arreio.py` — the harness: imports an annotation, hashes content, writes the manifesto.
- `LICENCAS.md` — the founding licenses: `uso-restrito`, `uso-livre`, `uso-privado`.
- `.forgejo/workflows/verificar.yml` — CI running Lean over the judge.

## Status

Early prototype. The judge's theorems are verified locally (exit 0); the first CI run is pending.

## License

AGPL-3.0 — see `LICENSE`.
