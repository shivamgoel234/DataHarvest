<div align="center">

# 🌾 DataHarvest

### The Physical Data Marketplace for AI

**Where real-world data meets real-world rewards.**

Labs post bounties. People record. AI scores. Everyone wins.

[![Next.js](https://img.shields.io/badge/Next.js_16-black?style=for-the-badge&logo=next.js&logoColor=white)](https://nextjs.org/)
[![React](https://img.shields.io/badge/React_19-61DAFB?style=for-the-badge&logo=react&logoColor=black)](https://react.dev/)
[![TypeScript](https://img.shields.io/badge/TypeScript-3178C6?style=for-the-badge&logo=typescript&logoColor=white)](https://typescriptlang.org/)
[![Supabase](https://img.shields.io/badge/Supabase-3FCF8E?style=for-the-badge&logo=supabase&logoColor=white)](https://supabase.com/)
[![Python](https://img.shields.io/badge/Python_3.12-3776AB?style=for-the-badge&logo=python&logoColor=white)](https://python.org/)
[![Swift](https://img.shields.io/badge/Swift-F05138?style=for-the-badge&logo=swift&logoColor=white)](https://swift.org/)
[![TailwindCSS](https://img.shields.io/badge/Tailwind_CSS_4-06B6D4?style=for-the-badge&logo=tailwindcss&logoColor=white)](https://tailwindcss.com/)
[![Modal](https://img.shields.io/badge/Modal-Serverless_GPU-7C3AED?style=for-the-badge)](https://modal.com/)

---

**[🚀 Live Demo](https://dataharvest.vercel.app)** · **[📱 iOS App](#-ios-data-collector)** · **[🧠 AI Pipeline](#-ai-analysis-pipeline)** · **[📖 Docs](#-getting-started)**

</div>

---

## 🎯 The Problem

> **73% of robotics and embodied AI teams** cite lack of real-world training data as their #1 blocker.

Web-scraped video can't provide what physical AI models actually need:
- ❌ No camera trajectory (where was the phone in 3D space?)
- ❌ No depth maps (how far away is that object?)
- ❌ No synchronized IMU (was the device moving? rotating?)
- ❌ No ground-truth sensor metadata of any kind

**The data gap between simulation and reality is the bottleneck for robotics.**

---

## 💡 The Solution

**DataHarvest** is a two-sided marketplace that connects:

| 🔬 **AI Research Labs** | 📱 **Data Collectors** |
|:---:|:---:|
| Post bounties with specific recording tasks | Browse available tasks & earn money |
| Define exactly what data they need | Record with iPhone sensors (video + LiDAR + IMU + GPS) |
| Get auto-scored, quality-verified submissions | Upload instantly — get paid when approved |
| Access robot-ready training datasets | Track earnings on a personal dashboard |

### How It Works

```
┌─────────────┐     ┌──────────────┐     ┌─────────────────┐     ┌──────────────┐
│  🔬 Lab     │────▶│  📋 Bounty   │────▶│  📱 Collector   │────▶│  ☁️ Upload   │
│  Posts Task  │     │  "Pick up a  │     │  Records with   │     │  to Supabase │
│  + Reward   │     │   cup — $5"  │     │  iPhone App     │     │  Storage     │
└─────────────┘     └──────────────┘     └─────────────────┘     └──────┬───────┘
                                                                        │
                    ┌──────────────┐     ┌─────────────────┐            │
                    │  💰 Payment  │◀────│  🤖 AI Scores   │◀───────────┘
                    │  Released    │     │  Quality 0-10   │
                    └──────────────┘     └─────────────────┘
```

---

## ✨ Key Features

### 🌐 Web Platform
- **Bounty Marketplace** — Labs create tasks with descriptions, requirements & rewards
- **Live Submission Ticker** — Real-time feed of recordings landing from around the world
- **Lab Dashboard** — Review submissions, view AI analysis, approve/reject
- **Collector Dashboard** — Browse tasks, track uploads, monitor earnings
- **Leaderboard** — Top collectors ranked by quality scores
- **3D Studio Viewer** — Interactive Gaussian splat visualization of recorded scenes
- **Video Search** — Natural language search across the entire video corpus

### 📱 iOS Data Collector App
- **Multi-sensor capture** — Video + LiDAR depth + IMU (100Hz) + GPS + ARKit 6DoF pose
- **Bundle format** — Each recording is a self-describing folder with synchronized streams
- **Local-first** — Record offline, upload when ready
- **Background uploads** — Resilient upload via `URLSession` that survives backgrounding
- **Voice narration** — On-device WhisperKit transcription of collector commentary

### 🧠 AI Analysis Pipeline (Serverless GPU)
- **ChatGPT Evaluation** — Automatic scoring (0-10) with success detection & reasoning
- **YOLO v26 Object Detection** — Real-time object identification across all frames
- **MediaPipe Hand Tracking** — 21-joint hand pose estimation for manipulation tasks
- **SAM 3.1 Segmentation** — Concept-based video segmentation with text prompts
- **Temporal Action Segmentation** — Automatic action boundary detection & labeling
- **Gaussian Splatting** — 3D scene reconstruction from iPhone LiDAR data via NerfStudio

---

## 🏗️ Architecture

```
dataharvest/
├── web/                          # 🌐 Next.js 16 Frontend
│   ├── src/app/                  #    App Router pages
│   │   ├── page.tsx              #    Landing page with live ticker
│   │   ├── collector/            #    Collector: tasks, earnings, leaderboard
│   │   ├── lab/                  #    Lab: dashboard, recordings, search
│   │   ├── studio/[id]/          #    3D Gaussian splat viewer (Three.js)
│   │   ├── login/ & signup/      #    Auth flows
│   │   └── api/                  #    TwelveLabs video search proxy
│   ├── src/lib/supabase/         #    Client & server Supabase helpers
│   └── src/components/           #    Shared UI components
│
├── backend/                      # 🤖 Modal Serverless Backend (Python)
│   ├── modal_app.py              #    Main Modal app — all GPU functions
│   ├── backend/
│   │   ├── analyzers/gpt_eval.py #    ChatGPT video evaluation
│   │   ├── orchestrator.py       #    Pipeline coordination
│   │   ├── contracts.py          #    Shared types & schemas
│   │   ├── artifacts.py          #    Storage path management
│   │   ├── supabase_api.py       #    Supabase REST client
│   │   ├── modal_inference/      #    YOLO, MediaPipe, SAM wrappers
│   │   └── splat/                #    Gaussian splatting pipeline
│   └── tests/                    #    Full test suite
│
├── iosApp/                       # 📱 Swift iOS App
│   ├── DataCollector/            #    SwiftUI + ARKit + CoreMotion
│   └── project.yml               #    XcodeGen project definition
│
├── supabase/                     # 🗄️ Database & Edge Functions
│   ├── migrations/               #    PostgreSQL schema migrations
│   ├── functions/                #    Deno edge functions
│   └── config.toml               #    Project configuration
│
└── playground/                   # 🧪 ML Research Experiments
    ├── temporal_action_segmentation/
    ├── modal-inference/
    ├── video_eval/
    └── yolo/
```

---

## 🛠️ Tech Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| **Frontend** | Next.js 16, React 19, TypeScript | Server components, app router |
| **Styling** | Tailwind CSS 4, CSS Modules | Responsive dark-mode UI |
| **3D Viewer** | Three.js, `@mkkellogg/gaussian-splats-3d` | Interactive splat visualization |
| **Auth & DB** | Supabase (PostgreSQL + Auth + Storage) | User accounts, data storage, RLS |
| **Edge Functions** | Supabase Edge Functions (Deno) | Submission processing, Modal dispatch |
| **AI Backend** | Modal (Serverless GPU) | Auto-scaling GPU inference |
| **AI — Scoring** | OpenAI ChatGPT (GPT-4o) | Video evaluation & quality scoring |
| **AI — Detection** | Ultralytics YOLO v26 | Object detection & instance segmentation |
| **AI — Hands** | Google MediaPipe | 21-joint hand pose estimation |
| **AI — Segmentation** | Meta SAM 3.1 | Text-prompted video segmentation |
| **AI — Actions** | Custom TAS pipeline | Temporal action boundary detection |
| **AI — 3D** | NerfStudio Splatfacto | Gaussian splat training from LiDAR |
| **iOS App** | Swift, SwiftUI, ARKit, CoreMotion | Multi-sensor data capture |
| **Video Search** | TwelveLabs API | Natural language video search |
| **Deployment** | Vercel (web), Modal (backend) | Production hosting |

---

## 🚀 Getting Started

### Prerequisites

- **Node.js** ≥ 18
- **npm** ≥ 9
- A [Supabase](https://supabase.com) account (free tier works)

### 1. Clone & Install

```bash
git clone https://github.com/YOUR_USERNAME/dataharvest.git
cd dataharvest/web
npm install
```

### 2. Configure Environment

```bash
cp .env.local.example .env.local
```

Edit `web/.env.local`:

```env
NEXT_PUBLIC_SUPABASE_URL=https://your-project.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your_anon_key_here
```

### 3. Run Development Server

```bash
npm run dev:next
```

Open [http://localhost:3000](http://localhost:3000) — you're live! 🎉

---

## ☁️ Deployment

### Web App → Vercel

```bash
cd web
npx vercel --prod
```

Or connect your GitHub repo to [Vercel](https://vercel.com) for auto-deploy on push.

> **Important:** Set the **Root Directory** to `web` in Vercel project settings.

### Backend → Modal

```bash
cd backend
uv run --python 3.12 modal deploy modal_app.py
```

---

## 📊 Data Flow

```
iPhone App                    Supabase                      Modal (GPU)
─────────                    ────────                      ───────────
                                                           
Record video ──────────────▶ Storage bucket                
  + LiDAR depth              recordings/{id}/              
  + IMU (100Hz)               ├── video.mp4                
  + ARKit 6DoF pose           ├── depth.bin                
  + GPS coordinates           ├── poses.parquet            
                              ├── imu.parquet              
                              ├── intrinsics.json          
Tap "Upload" ─────────────▶   └── metadata.json ─────────▶ submit-recording
                                                           Edge Function
                                                                │
                              recording_analysis_jobs            │
                              ┌────────────────────┐            ▼
                              │ gpt_eval: running  │◀─── ChatGPT scoring
                              │ yolo: running      │◀─── YOLO detection
                              │ mediapipe: running │◀─── Hand tracking
                              │ sam: running       │◀─── SAM segmentation
                              │ temporal: running  │◀─── Action labeling
                              └────────────────────┘
                                       │
                                       ▼
                              recordings/{id}/analysis/
                               ├── gpt-eval.json
                               ├── yolo-detections.json
                               ├── mediapipe-hands.json
                               ├── sam-segments.json
                               └── temporal-actions.json
```

---

## 📱 iOS Data Collector

The iOS app captures richly-annotated recordings with synchronized multi-sensor data:

| Sensor | Rate | Data |
|--------|------|------|
| **RGB Video** | 30 fps | 1080p HEVC (~60 MB/min) |
| **ARKit 6DoF Pose** | 60 fps | Camera position + orientation in 3D |
| **LiDAR Depth** | 10-15 fps | Metric depth maps |
| **IMU** | 100 Hz | Accelerometer + Gyroscope + Magnetometer |
| **GPS** | 1 Hz | Latitude, longitude, accuracy |
| **Audio** | — | On-device WhisperKit transcription |

Built with Swift + SwiftUI, targeting iPhone 14 Pro and newer.

```bash
cd iosApp
xcodegen generate        # Generate Xcode project from project.yml
open DataCollector.xcodeproj
```

---

## 🧪 AI Analysis Pipeline

Every uploaded recording passes through **5 parallel AI analyzers** on serverless GPUs:

### 1. 🧠 ChatGPT Evaluation (`gpt_eval`)
Watches the full video and returns structured scoring:
```json
{
  "summary": "Person picks up a red mug from the kitchen counter",
  "success": true,
  "success_reasoning": "The mug is clearly grasped and lifted",
  "score": 8,
  "score_reasoning": "Clean execution with minor hesitation at grasp"
}
```

### 2. 🎯 YOLO v26 Object Detection (`yolo_objects`)
Detects and tracks objects across every frame with bounding boxes and confidence scores.

### 3. ✋ MediaPipe Hand Tracking (`mediapipe_hands`)
Extracts 21-joint hand pose landmarks — the exact data needed for robot manipulation learning.

### 4. 🎨 SAM 3.1 Segmentation (`sam_segments`)
Text-prompted concept segmentation: "segment the hand", "segment the cup" → pixel-precise masks.

### 5. ⚡ Temporal Action Segmentation (`temporal_actions`)
Detects action boundaries and labels each segment with imperative robot-style instructions: "Pick up the mug", "Open the drawer".

### Bonus: 🌐 Gaussian Splat (`gaussian_splat`)
For recordings with LiDAR depth data, trains a 3D Gaussian splat via NerfStudio Splatfacto — viewable in the interactive web studio.

---

## 🔐 Environment Variables

### Web App (`web/.env.local`)

| Variable | Required | Description |
|----------|----------|-------------|
| `NEXT_PUBLIC_SUPABASE_URL` | ✅ | Supabase project URL |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | ✅ | Supabase anonymous/public key |
| `TWELVELABS_API_KEY` | ❌ | TwelveLabs API key (video search) |
| `TWELVELABS_INDEX_ID` | ❌ | TwelveLabs index ID |

### Backend (Modal Secrets)

| Variable | Required | Description |
|----------|----------|-------------|
| `SUPABASE_URL` | ✅ | Supabase project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | ✅ | Supabase service role key |
| `SUPABASE_ANON_KEY` | ✅ | Supabase anonymous key |
| `OPENAI_API_KEY` | ✅ | OpenAI API key for ChatGPT eval |
| `MODAL_ANALYSIS_SECRET` | ✅ | Shared secret for edge function ↔ Modal auth |

---

## 📄 License

This project is proprietary. All rights reserved.

---

<div align="center">

**Built with ❤️ for the future of physical AI**

*Making real-world data accessible to every robotics team on the planet.*

---

[⬆ Back to top](#-dataharvest)

</div>
