#!/usr/bin/env python3
"""
Offline builder for Unity Shape-Gen Knowledge-Base.
Run ONCE after you collect new successful *.hlsl files.
Output is a self-contained folder you simply drag into Assets.
"""
import os
import json
import re
import argparse
from pathlib import Path
from typing import List, Dict

import numpy as np
from sentence_transformers import SentenceTransformer
import faiss                   # optional – we keep plain JSON for Unity side

# ---------- CONFIG -------------------------------------------------
CHUNK_TYPES = [
    # SDF primitives
    r"float\s+sdCircle\s*\([^)]*\)\s*\{[^}]*\}",
    r"float\s+sdBox\s*\([^)]*\)\s*\{[^}]*\}",
    r"float\s+sdRoundedBox\s*\([^)]*\)\s*\{[^}]*\}",
    r"float\s+sdSegment\s*\([^)]*\)\s*\{[^}]*\}",
    # Boolean ops
    r"float\s+opUnion\s*\([^)]*\)\s*\{[^}]*\}",
    r"float\s+opSubtract\s*\([^)]*\)\s*\{[^}]*\}",
    r"float\s+opIntersection\s*\([^)]*\)\s*\{[^}]*\}",
    r"float\s+opSmoothUnion\s*\([^)]*\)\s*\{[^}]*\}",
    # Smooth min/max
    r"float\s+smin\s*\([^)]*\)\s*\{[^}]*\}",
    r"float\s+smax\s*\([^)]*\)\s*\{[^}]*\}",
    # 2D rotation
    r"float2\s+rotate2D\s*\([^)]*\)\s*\{[^}]*\}",
    # Anti-alias helper
    r"float\s+shapeMaskAA\s*\([^)]*\)\s*\{[^}]*\}",
    # Any #define block
    r"#ifndef\s+(\w+).*?#define\s+\1.*?#endif",
]
DESC_REGEX = re.compile(r"^// DESC:\s*(.+)$", re.MULTILINE)
CHUNK_REGEX = [re.compile(p, re.DOTALL) for p in CHUNK_TYPES]

# ---------- UTILS --------------------------------------------------
def embed(texts: List[str]) -> np.ndarray:
    """Return (N,768) float32 matrix."""
    model = SentenceTransformer("all-MiniLM-L6-v2")
    return model.encode(texts, convert_to_numpy=True, normalize_embeddings=True)

def cosine_similarity_matrix(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """a: (N,d)  b: (M,d)  -> (N,M)"""
    return np.dot(a, b.T)  # both already L2-normalised

# ---------- CHUNK EXTRACTION ---------------------------------------
def extract_chunks(file_id: str, code: str) -> List[Dict]:
    out = []
    for rx in CHUNK_REGEX:
        for m in rx.finditer(code):
            txt = m.group(0).strip()
            out.append({"id": f"{file_id}_{len(out):03d}",
                        "text": txt})
    return out

# ---------- METADATA ----------------------------------------------
def extract_description(path: Path) -> str:
    txt = path.read_text(encoding="utf-8")
    m = DESC_REGEX.search(txt)
    return m.group(1).strip() if m else path.stem.replace("_", " ")

# ---------- THUMBNAIL (dummy 128x128 png) -------------------------
def save_dummy_thumb(out_path: Path, name: str):
    # 1-byte grey PNG – Unity can read it, keeps repo small
    PNG_GREY_128 = (
        b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x80\x00\x00\x00\x80\x08\x00\x00\x00\x00@5\xe5\x9e"
        b"\x00\x00\x00\x0cIDATx\x9cc```\x00\x00\x00\x04\x00\x01\xdd\x8d\xb4\x1c\x00\x00\x00\x00IEND\xaeB`\x82"
    )
    out_path.write_bytes(PNG_GREY_128)

# ---------- MAIN ---------------------------------------------------
def build(hlsl_folder: Path, out_folder: Path):
    out_folder.mkdir(parents=True, exist_ok=True)
    chunks_jsonl = out_folder / "chunks.jsonl"
    shapes_jsonl = out_folder / "shapes.jsonl"
    thumb_dir  = out_folder / "thumbnails"
    thumb_dir.mkdir(exist_ok=True)

    hlsl_files = list(hlsl_folder.glob("*.hlsl"))
    if not hlsl_files:
        raise SystemExit("No *.hlsl files found in input folder.")

    all_chunks: List[Dict] = []
    all_descs : List[str]   = []

    # ---- 1. scan & extract ----
    for path in hlsl_files:
        file_id = path.stem
        code = path.read_text(encoding="utf-8")
        desc = extract_description(path)

        chunks = extract_chunks(file_id, code)
        for c in chunks:
            c["file"] = file_id
            c["desc"] = desc
        all_chunks.extend(chunks)
        all_descs.append(desc)

        # dummy thumbnail
        save_dummy_thumb(thumb_dir / f"{file_id}.png", file_id)

    print(f"Extracted {len(all_chunks)} chunks from {len(hlsl_files)} files.")

    # ---- 2. embed ----
    chunk_texts = [c["text"] for c in all_chunks]
    chunk_emb   = embed(chunk_texts)          # (N,768)
    shape_emb   = embed(all_descs)            # (M,768)

    for c, vec in zip(all_chunks, chunk_emb):
        c["embedding"] = vec.tolist()

    # ---- 3. write ----
    with chunks_jsonl.open("w", encoding="utf-8") as f:
        for c in all_chunks:
            f.write(json.dumps(c, ensure_ascii=False) + "\n")

    with shapes_jsonl.open("w", encoding="utf-8") as f:
        for path, emb in zip(hlsl_files, shape_emb):
            f.write(json.dumps({
                "file_id": path.stem,
                "description": extract_description(path),
                "embedding": emb.tolist()
            }) + "\n")

    print("Knowledge-Base ready at:", out_folder.resolve())
    print("Drag the whole folder into Unity Assets.")

# ---------- ENTRY --------------------------------------------------
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Build Shape-Gen Knowledge-Base")
    parser.add_argument("--hlsl_folder", required=True, type=Path,
                        help="Folder with 200 successful *.hlsl files")
    parser.add_argument("--out_folder",  required=True, type=Path,
                        help="Output KB folder (will be created)")
    args = parser.parse_args()
    build(args.hlsl_folder, args.out_folder)