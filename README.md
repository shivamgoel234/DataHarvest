# DataHarvest — Physical Data Marketplace

A marketplace platform where AI research labs post data collection tasks with bounties, and everyday people earn money by capturing real-world physical data using their iPhones.

> **"AI needs the real world. Models can't touch reality. You can. Capture the world, get paid."**

## Architecture

- `web/` — Next.js 16 frontend (React 19, TailwindCSS 4, Supabase)
- `backend/` — Python serverless analysis pipeline (Modal, GPT, YOLO, MediaPipe, SAM)
- `iosApp/` — iOS Swift app for data collection
- `supabase/` — Database migrations and Edge Functions
- `playground/` — ML research experiments

## Getting Started

Install dependencies for the web app:

```bash
cd web
npm install
```

Create a `.env.local` file in the `web/` directory:

```env
NEXT_PUBLIC_SUPABASE_URL=your_supabase_url
NEXT_PUBLIC_SUPABASE_ANON_KEY=your_supabase_anon_key
```

Then run the development server:

```bash
cd web
npm run dev:next
```

Open `http://localhost:3000` in your browser.

## Tech Stack

- **Frontend:** Next.js 16, React 19, TailwindCSS 4, TypeScript, Three.js
- **Backend:** Python 3.12, Modal (serverless GPU), OpenAI GPT, MediaPipe, YOLO, SAM
- **Database:** Supabase (PostgreSQL + Auth + Storage + Edge Functions)
- **Mobile:** Swift + SwiftUI + ARKit (iOS data collection)

## Deploy on Vercel

The easiest way to deploy the web app:

```bash
cd web
npx vercel
```

Or connect your GitHub repository to [Vercel](https://vercel.com) for automatic deployments.
