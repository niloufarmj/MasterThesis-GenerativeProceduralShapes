# Generative Procedural Shapes — AI-Powered Shader Generator for Unity

> **Master Thesis Project** — An AI-assisted pipeline for generating, editing, animating, and applying effects to procedural 2D shapes in Unity using HLSL shaders, ShaderGraph, and large language models.

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Pipeline Flows](#pipeline-flows)
- [Chatbot Interface](#chatbot-interface)
- [Knowledge Base](#knowledge-base)
- [Setup & Installation](#setup--installation)
- [Configuration](#configuration)
- [Editor Windows](#editor-windows)
- [Output File Locations](#output-file-locations)
- [API Reference](#api-reference)
- [Project Structure](#project-structure)
- [Tech Stack](#tech-stack)

---

## Overview

This Unity Editor tool enables non-programmers to create, edit, animate, and apply effects to 2D procedural shapes entirely through natural language — no HLSL coding required.

The system combines a **RAG (Retrieval-Augmented Generation)** pipeline, multiple **LLM providers** (Google Gemini, OpenAI GPT-4o, Anthropic Claude), and an interactive **chatbot interface** to guide users through the full asset creation lifecycle.

```
User Prompt / Reference Image
        ↓
  Shape Decomposition
        ↓
  Knowledge Base Retrieval (184+ shapes, embedding search)
        ↓
  LLM HLSL Code Generation (Gemini)
        ↓
  ShaderGraph + Material Build
        ↓
  VLM Visual Evaluation (GPT-4o) — iterates until score > 7/10
        ↓
  Preview Quad in Scene + PNG Screenshot
        ↓
  Edit / Animate / Add Effects (follow-up flows)
```

---

## Features

| Feature | Description |
|---|---|
| **Text-to-Shape** | Describe any 2D shape in natural language; get an HLSL shader + Unity material |
| **Image-to-Shape** | Upload a reference image; Gemini Vision recreates it as a procedural shader |
| **HLSL Import** | Upload an existing `.hlsl` file; the tool wraps it in ShaderGraph with sensible property values |
| **Shape Editing** | AI classifies whether an edit needs a property tweak or full HLSL rewrite, then applies it |
| **Animation** | AI generates a C# `MonoBehaviour` to animate material properties; adds new shader properties when needed |
| **Pixelation Effect** | Client-side ShaderGraph node injection (Floor/Divide UV quantisation) — no LLM call required |
| **VLM Quality Loop** | GPT-4o scores rendered previews 1–10; automatically refines until threshold is met |
| **RAG Knowledge Base** | 184+ verified shapes with embeddings for semantic retrieval; grows with each accepted generation |
| **Chatbot UI** | Conversational editor window with state machine, quick replies, material/image pickers |
| **Human Review** | EditorWindow for scoring, accepting, and curating generated shapes into the knowledge base |

---

## Architecture

```
Assets/ShaderGraphGenerator/
├── ShaderGraphJSONGenerator.cs      ← HLSL → ShaderGraph JSON (with optional pixelation nodes)
├── ShaderGraphNodeFactory.cs        ← Creates typed ShaderGraph node objects
├── ShaderGraphPropertyFactory.cs    ← Creates shader property definitions
├── ShaderGraphSlotFactory.cs        ← Creates node input/output slot definitions
├── HLSLFunctionInfo.cs              ← Parsed HLSL function metadata
├── FunctionParameter.cs             ← Single parameter (name, type, direction)
│
├── Editor/
│   ├── Core/
│   │   ├── API/
│   │   │   ├── GeminiApiService.cs      ← Gemini text & vision (HLSL generation, classification)
│   │   │   ├── OpenAIApiService.cs      ← GPT-4o Vision (VLM scoring, image description)
│   │   │   └── ClaudeApiService.cs      ← Claude (alternative structured HLSL generation)
│   │   ├── LLMDataModels.cs             ← Serialisable LLM request/response structures
│   │   ├── MaterialPreviewHelper.cs     ← Preview quads, screenshots, property application
│   │   ├── ShaderGenerationPipeline.cs  ← Core: HLSL → ShaderGraph → Material → Preview
│   │   └── ShaderPromptBuilder.cs       ← Prompt construction for shape generation
│   │
│   ├── Chat/
│   │   ├── ChatbotWindow.cs             ← IMGUI chat window (bubbles, quick replies, pickers)
│   │   ├── ChatBridge.cs                ← HTTP server (port 7723) + all pipeline triggers
│   │   ├── ChatBridgeLocal.cs           ← Direct (non-HTTP) entry point for the IMGUI window
│   │   └── ChatSession.cs               ← Static state machine (26 states) + message history
│   │
│   ├── KnowledgeBase/
│   │   ├── SemanticShapeSearch.cs       ← Cosine-similarity search over embedding vectors
│   │   ├── ShapeEmbeddingService.cs     ← Generates embeddings via OpenAI API
│   │   ├── ShapeMetadata.cs             ← Data structures: ShapeMetadata, AnimatorEntry, etc.
│   │   ├── HLSLParser.cs                ← Parses HLSL to extract function signatures
│   │   └── KnowledgeBaseLLMService.cs   ← LLM-powered shape analysis and metadata extraction
│   │
│   └── RAG/
│       ├── Pipelines/
│       │   ├── RAGPipelineManager.cs           ← Full text-to-shape pipeline (7 steps + VLM loop)
│       │   ├── ImageToShaderPipelineManager.cs ← Image-to-shader with Gemini Vision
│       │   └── HLSLUpdatePipelineManager.cs    ← Edit pipeline: before/after VLM comparison
│       ├── Generation/
│       │   ├── RAGShapeGenerator.cs            ← Decompose → retrieve → LLM compose
│       │   ├── ShapeDecompositionService.cs    ← Breaks complex shapes into components
│       │   ├── ShaderGraphBuilder.cs           ← HLSL + LLM response → ShaderGraph + Material
│       │   └── HLSLCompositionEngine.cs        ← Merges multiple HLSL primitives
│       ├── Animation/
│       │   ├── MaterialAnimatorPipelineManager.cs ← C# animation script pipeline (domain-reload safe)
│       │   ├── AnimationScriptGenerator.cs        ← LLM C# generation + animation classification
│       │   └── AnimationKnowledgeBase.cs          ← Animation KB helpers + embedding search
│       ├── Edit/
│       │   └── EditClassifier.cs               ← Classifies edits: property-only vs HLSL update
│       ├── Curation/
│       │   └── KnowledgeBaseUpdater.cs         ← Ingests shapes into knowledge base
│       └── Windows/
│           ├── UnifiedGeneratorWindow.cs       ← Main RAG generator UI (text + image modes)
│           ├── MaterialAnimatorWindow.cs       ← Animation generation UI
│           ├── RAGHumanReviewWindow.cs         ← Human scoring and KB curation
│           ├── RAGAutoLearnWindow.cs           ← Auto-ingest successful results
│           ├── RAGUpdateWindow.cs              ← Shape editing UI
│           └── ImageToShaderWindow.cs          ← Image upload + generation controls
```

---

## Pipeline Flows

### 1. Text-to-Shape (RAG Pipeline)

```
User text prompt
→ ShapeDecompositionService      (break into visual components)
→ SemanticShapeSearch            (find top-2 KB examples per component)
→ RAGShapeGenerator              (build augmented prompt with retrieved HLSL)
→ GeminiApiService               (generate new HLSL code)
→ ShaderGraphBuilder             (HLSL → .shadergraph JSON)
→ MaterialPreviewHelper          (create .mat + render 512×512 PNG)
→ OpenAIApiService               (VLM score 1–10; if < 7 refine, max 3 tries)
→ Result: .hlsl + .shadergraph + .mat + preview PNG
```

### 2. Image-to-Shape

```
Reference image (PNG/JPG)
→ OpenAIApiService.DescribeImage (GPT-4o: detailed visual description)
→ ShapeDecompositionService      (decompose description)
→ SemanticShapeSearch            (retrieve KB examples)
→ GeminiApiService.Vision        (generate HLSL with both text + original image)
→ (same as text pipeline from ShaderGraphBuilder onward)
```

### 3. HLSL Import (Chatbot)

```
User uploads .hlsl file
→ Copy to Assets/ShaderGraphs/Generated/HLSL/
→ ShaderGraphJSONGenerator.GenerateFromHLSL (no pixelation)
→ MaterialPreviewHelper.CreateMaterialForShaderGraph
→ MaterialPreviewHelper.SetRandomMaterialProperties  (safe baseline)
→ GeminiApiService (read HLSL → suggest sensible property values)
→ MaterialPreviewHelper.SetDefaultMaterialProperties (override with LLM values)
→ MaterialPreviewHelper.CreatePreviewQuad
→ Result: shadergraph + material with good defaults + preview
```

### 4. Shape Editing

```
User edit request + material
→ EditClassifier.ClassifyEditRequestAsync (Gemini)
   ├── needs_hlsl_change = false → ApplyMaterialPropertyChanges (SetFloat/SetColor/SetVector)
   │                             → Preview quad in scene
   └── needs_hlsl_change = true  → HLSLUpdatePipelineManager
                                    (extract HLSL → Gemini update → before/after VLM verify)
                                  → Preview quad + result image in chat
```

### 5. Animation

```
User animation request + material
→ AnimationScriptGenerator.ClassifyAnimationRequirementsAsync (Gemini)
   ├── C# only → AnimationScriptGenerator.GenerateAnimationScriptAsync
   │            → Write .cs → Unity recompiles → [domain reload] → attach to preview quad
   └── HLSL needed → HLSLUpdatePipelineManager (add missing properties)
                   → AnimationScriptGenerator.GenerateAnimationScriptAsync (on updated material)
                   → Write .cs → domain reload → attach to quad
```

### 6. Pixelation Effect (no LLM)

```
Source material
→ HLSLUpdatePipelineManager.ExtractHlslPathFromMaterial
→ ShaderGraphJSONGenerator.GenerateFromHLSL (..., usePixelation: true)
   (injects: UV × PixelCount → Floor → ÷ PixelCount nodes)
→ MaterialPreviewHelper.CreateMaterialForShaderGraph
→ CopyMatchingMaterialProperties (original → effect)
→ SetFloat("PixelCount", 64)
→ CreatePreviewQuad → named "Pixelation Effect — {name}" in scene
```

---

## Chatbot Interface

The chatbot (`ChatbotWindow.cs` + `ChatBridge.cs`) is driven by a 26-state machine:

```
MainMenu
├── new_shape → NewShape_InputMode → [Text | Image] → Generating → Reviewing → PostGen
│                                                                              ├── edit   → Edit_Describe → Edit_Running → PostGen
│                                                                              ├── animate→ Animate_Describe → Animate_Running → PostGen
│                                                                              └── effect → Effect_Pick → Animate_Running → PostGen
├── edit    → Edit_Attach   → Edit_Describe   → Edit_Running   → PostGen
├── animate → Animate_Attach → Animate_Describe → Animate_Running → PostGen
├── effect  → Effect_Attach → Effect_Pick → Animate_Running → PostGen
├── hlsl    → HLSL_Attach   → HLSL_Running   → HLSL_Done
├── explain → Explain → MainMenu
└── contact → Contact_Name → Contact_Intent → Contact_Email → Contact_Message → MainMenu
```

The chatbot also runs as an HTTP server on **port 7723** with the following endpoints:

| Endpoint | Method | Purpose |
|---|---|---|
| `/` or `/chat` | GET | Serves the web-based chat UI (`chat.html`) |
| `/send` | POST | Main message handler; triggers pipeline or state transition |
| `/image` | POST | Accepts base64-encoded image uploads |
| `/status` | GET | Returns current status message and last preview path |
| `/abort` | GET | Cancels the current in-progress pipeline |
| `/history` | GET | Returns full chat history, current state, and state config |

---

## Knowledge Base

**Location**: `Assets/ShaderGraphGenerator/KnowledgeBase/shape_metadata.json`

**Size**: 184 verified shapes (as of thesis submission)

**Schema**:
```json
{
  "totalShapes": 184,
  "shapes": [{
    "id": "_259cbb14",
    "fileName": "RoundedRectangle",
    "filePath": "Assets/ShaderGraphs/SuccessfulResults/RoundedRectangle.hlsl",
    "originalPrompt": "a rounded rectangle with adjustable corner radius...",
    "visualDescription": "Smooth rectangular shape with rounded corners...",
    "category": 1,
    "complexity": 1,
    "tags": ["rectangle", "rounded", "geometric"],
    "parameters": [{"name": "Width", "type": "float", "defaultValue": "0.6"}],
    "embedding": [0.016, -0.012, ...],
    "verificationScore": 9,
    "animators": [{
      "fileName": "RoundedRectanglePulse",
      "scriptPath": "Assets/ShaderGraphs/Animations/RoundedRectanglePulse.cs",
      "propertiesUsed": ["_FillColor"],
      "animationSummary": "Pulses fill color between two hues",
      "embedding": [...]
    }]
  }]
}
```

**Category enum**: `Uncategorized=0`, `GeometricPrimitives=1`, `OrganicShapes=2`, `SymbolsAndIcons=3`, `CompositeShapes=4`

**Complexity enum**: `Unknown=0`, `Primitive=1`, `Intermediate=2`, `Complex=3`

---

## Setup & Installation

### Requirements
- Unity **6000.0.41f1** (Unity 6) or later
- **Newtonsoft.Json** package (via Package Manager: `com.unity.nuget.newtonsoft-json`)
- API keys for at least one of: Google Gemini, OpenAI, Anthropic Claude

### Steps

1. **Clone** this repository into your Unity project's `Assets/` folder (or open as a Unity project directly).

2. **Install Newtonsoft.Json** via Unity Package Manager:
   ```
   Window → Package Manager → Add package by name → com.unity.nuget.newtonsoft-json
   ```

3. **Create the Config asset**:
   - Right-click in the Project window
   - `Create → ShaderGraphGenerator → Config`
   - Name it `ShaderGraphGeneratorConfig` (or any name — it's found by type)

4. **Add API keys** to the Config asset:
   - `openAIKey` — required for VLM scoring and image description
   - `geminiKey` — required for HLSL generation and most LLM calls
   - `claudeKey` — optional, alternative generation backend

5. **Open the chatbot**:
   ```
   Tools → ShaderGraph Generator → Chat UI
   ```

6. **Open the main generator** (standalone mode):
   ```
   Tools → ShaderGraph Generator → 2.9 Unified RAG Generator
   ```

---

## Configuration

All API keys are stored in a `ShaderGraphGeneratorConfig` ScriptableObject asset:

```csharp
[CreateAssetMenu(menuName = "ShaderGraphGenerator/Config")]
public class ShaderGraphGeneratorConfig : ScriptableObject
{
    public string openAIKey;   // GPT-4o Vision — VLM scoring, image descriptions
    public string geminiKey;   // Gemini — HLSL generation, classification, property suggestion
    public string claudeKey;   // Claude — alternative structured generation (optional)
}
```

The asset is located anywhere in the project; all pipelines find it via `AssetDatabase.FindAssets("t:ShaderGraphGeneratorConfig")`.

---

## Editor Windows

| Window | Menu Path | Purpose |
|---|---|---|
| **Chat UI** | Tools / ShaderGraph Generator / Chat UI | Main conversational interface |
| **Unified RAG Generator** | Tools / ShaderGraph Generator / 2.9 Unified RAG Generator | Direct text/image generation with VLM loop |
| **Material Animator** | Tools / ShaderGraph Generator / Animator | Generate animation scripts for materials |
| **Human Review** | Tools / ShaderGraph Generator / Human Review | Score and curate generated shapes |
| **Auto Learn** | Tools / ShaderGraph Generator / Auto Learn | Ingest successful results into knowledge base |
| **RAG Update** | Tools / ShaderGraph Generator / Update | Edit an existing shape's HLSL |
| **Image to Shader** | Tools / ShaderGraph Generator / Image to Shader | Standalone image-to-material pipeline |
| **Embedding Generator** | Tools / ShaderGraph Generator / Embeddings | Generate/update KB embeddings |

---

## Output File Locations

| Asset Type | Path |
|---|---|
| Generated HLSL | `Assets/ShaderGraphs/RAG_Generated/{name}.hlsl` |
| Updated HLSL | `Assets/ShaderGraphs/RAG_Updates/{name}.hlsl` |
| Imported HLSL | `Assets/ShaderGraphs/Generated/HLSL/{name}.hlsl` |
| ShaderGraph | `Assets/ShaderGraphs/RAG_Generated/{name}.shadergraph` |
| Effect ShaderGraph | `Assets/ShaderGraphs/Effects/{name}_Pixelated.shadergraph` |
| Material | `Assets/ShaderGraphs/RAG_Generated/{name}.mat` |
| Preview PNG | `Assets/ShaderGraphs/Previews/{name}_{iter}.png` |
| Animation Script | `Assets/ShaderGraphs/Animations/{ClassName}.cs` |
| Knowledge Base | `Assets/ShaderGraphGenerator/KnowledgeBase/shape_metadata.json` |
| Contact Messages | `{ProjectRoot}/contact_messages.json` |

---

## API Reference

### Google Gemini

- **Model**: `gemini-3-pro-preview`
- **Endpoint**: `https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`
- **Used for**: HLSL code generation, animation script generation, animation/edit classification, property value suggestion
- **Vision variant**: Accepts `inlineData` base64 image alongside text prompt

### OpenAI

- **Model**: `gpt-4o`
- **Endpoint**: `https://api.openai.com/v1/chat/completions`
- **Used for**: VLM visual evaluation (1–10 scoring), reference image description, before/after edit comparison
- **Also**: Embedding generation for semantic search (`text-embedding-3-small`)

### Anthropic Claude

- **Model**: `claude-sonnet-4-5-20250929`
- **Endpoint**: `https://api.anthropic.com/v1/messages`
- **Used for**: Alternative HLSL generation with structured JSON schema enforcement
- **Optional** — the system works without a Claude key

---

## Project Structure

```
Assets/
├── ShaderGraphGenerator/           ← All tool source code
│   ├── Editor/                     ← Unity editor-only scripts
│   │   ├── Chat/                   ← Chatbot state machine + HTTP bridge
│   │   ├── Core/                   ← APIs, material helpers, prompt builders
│   │   ├── KnowledgeBase/          ← Embedding search, KB management
│   │   └── RAG/                    ← All generation pipelines + windows
│   │       ├── Animation/          ← Animation pipeline + C# script generation
│   │       ├── Curation/           ← KB ingestion and management
│   │       ├── Edit/               ← Edit classification
│   │       ├── Generation/         ← RAG composition engine
│   │       ├── Pipelines/          ← Top-level pipeline orchestrators
│   │       └── Windows/            ← All EditorWindow UIs
│   └── KnowledgeBase/              ← shape_metadata.json + embeddings
│
├── ShaderGraphs/
│   ├── RAG_Generated/              ← Generated HLSL, shadergraphs, materials
│   ├── RAG_Updates/                ← Edited/updated versions
│   ├── Effects/                    ← Effect variants (pixelation, etc.)
│   ├── Generated/                  ← HLSL imports + their shadergraphs
│   ├── Animations/                 ← Generated C# animation MonoBehaviours
│   ├── Previews/                   ← PNG screenshots of generated shapes
│   └── SuccessfulResults/          ← Manually curated HLSL library
│
└── ShaderGraphGeneratorConfig.asset ← API keys (do not commit)
```

---

## Tech Stack

| Component | Technology |
|---|---|
| **Runtime** | Unity 6 (6000.0.41f1), C# 9 |
| **Editor UI** | Unity IMGUI (EditorWindow, GUILayout) |
| **HTTP Server** | `System.Net.HttpListener` on localhost:7723 |
| **Async** | `async/await` + `Task`, `CancellationToken` |
| **JSON** | Newtonsoft.Json with custom `JsonConverter` |
| **LLM — Code Gen** | Google Gemini (`gemini-3-pro-preview`) |
| **LLM — Vision** | OpenAI GPT-4o (`gpt-4o`) |
| **LLM — Structured** | Anthropic Claude (`claude-sonnet-4-5`) |
| **Embeddings** | OpenAI `text-embedding-3-small` |
| **Shader Format** | Unity ShaderGraph JSON (custom node wiring) |
| **Shader Language** | HLSL (Custom Function nodes in ShaderGraph) |
| **Persistence** | `EditorPrefs` (domain reload safety), JSON files |

---

## Notes

- **API keys** — Never commit `ShaderGraphGeneratorConfig.asset` to a public repository. Add it to `.gitignore`.
- **Domain reloads** — The animation pipeline survives Unity's script compilation domain reload by serialising state to `EditorPrefs` before triggering `AssetDatabase.Refresh()`.
- **VLM threshold** — The acceptance threshold is score > 7 out of 10. Shapes below this are automatically refined with feedback up to 3 times.
- **Knowledge base growth** — Every shape accepted through Human Review (score ≥ 8) can be added to `shape_metadata.json` via the Auto Learn window, improving future RAG retrievals.
- **Pixelation** — Implemented as a deterministic ShaderGraph modification (UV quantisation via Floor/Divide nodes), not an LLM call. Takes ~2 seconds.

---

*Master Thesis — Niloufar Moradijam — 2026*
