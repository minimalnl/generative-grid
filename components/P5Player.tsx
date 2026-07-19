"use client";

import { useState } from "react";

// Jouw p5-script. Later komt dit uit de blockchain; nu staat het hier vast.
const SCRIPT = `// ---- variabelen om mee te spelen ----
const WERK_MAAT = 2400;

const ACHTERGRONDEN = ['#fcfaf6', '#f7f3ea', '#faf8f2'];

const VIERKANT_KLEUREN = [
  '#9b9980ff',
  '#9b8d80ff',
  '#9b7980ff'
];

const MIN_MAAT = 0.236;
const MAX_MAAT = 0.382;

const KORREL_DICHTHEID = 0.5;
const KORREL_STERKTE = 30;
const KORREL_GROOTTE = 0.5;
const KORREL_ALPHA = 150;
// -------------------------------------

const SCHAAL = WERK_MAAT / 1200;
const KORREL_PX = KORREL_GROOTTE * SCHAAL;

function setup() {
  createCanvas(WERK_MAAT, WERK_MAAT);
  randomSeed(SEED);
  noLoop();
  noStroke();
}

function draw() {
  const achtergrond = random(ACHTERGRONDEN);
  background(achtergrond);

  const kleur = random(VIERKANT_KLEUREN);
  const maat = random(MIN_MAAT, MAX_MAAT) * WERK_MAAT;

  fill(kleur);
  rectMode(CENTER);
  rect(width / 2, height / 2, maat, maat);

  const marge = KORREL_PX;
  const links = width / 2 - maat / 2 + marge;
  const boven = height / 2 - maat / 2 + marge;
  const ruisMaat = maat - marge * 2;

  const basis = color(kleur);
  const r = red(basis);
  const g = green(basis);
  const b = blue(basis);
  const aantal = (maat * maat * KORREL_DICHTHEID) / (SCHAAL * SCHAAL);

  strokeWeight(KORREL_PX);
  for (let i = 0; i < aantal; i++) {
    const x = links + random(ruisMaat);
    const y = boven + random(ruisMaat);
    const v = random(-KORREL_STERKTE, KORREL_STERKTE);
    stroke(r + v, g + v, b + v, KORREL_ALPHA);
    point(x, y);
  }
  noStroke();
}`;

function buildSrcdoc(script: string, seed: number) {
  return `<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<style>html,body{margin:0;padding:0;overflow:hidden;background:#000;height:100%}main{height:100%;display:flex;align-items:center;justify-content:center}canvas{display:block;width:100% !important;height:100% !important;max-width:100vmin;max-height:100vmin}</style>
<script src="https://cdnjs.cloudflare.com/ajax/libs/p5.js/1.9.0/p5.min.js"><\/script>
</head>
<body>
<script>
const SEED = ${seed};
try {
${script}
} catch (e) {
  document.body.innerHTML = '<pre style="color:#f66;padding:12px;font-size:12px">' + e + '</pre>';
}
<\/script>
</body>
</html>`;
}

export function P5Player() {
    const [seed, setSeed] = useState(() => Math.floor(Math.random() * 1e9));
    const prijs = 1; // straks uit de prijstrap / het contract

  return (
    <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 12, width: "min(90vw, 420px)" }}>
      <div style={{ width: "100%", aspectRatio: "1 / 1", overflow: "hidden", background: "#000" }}>
        <iframe
          sandbox="allow-scripts"
          srcDoc={buildSrcdoc(SCRIPT, seed)}
          style={{ width: "100%", height: "100%", border: 0, display: "block" }}
          title="Generatieve kunst"
        />
      </div>

      <div style={{ display: "flex", gap: 12, width: "100%" }}>
        <button
          onClick={() => setSeed(Math.floor(Math.random() * 1e9))}
          style={{ flex: 1, padding: "12px 0", border: "none", background: "#353839", color: "#fff", fontWeight: 600, cursor: "pointer" }}
        >
          Genereer
        </button>
        <button
          style={{ flex: 1, padding: "12px 0", border: "none", background: "#353839", color: "#fff", fontWeight: 600, cursor: "pointer" }}
        >
          Mint voor {prijs} LYX
        </button>
      </div>
    </div>
  );
}